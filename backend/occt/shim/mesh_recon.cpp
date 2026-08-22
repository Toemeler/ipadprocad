/* M232 — mesh -> B-Rep reconstruction. See mesh_recon.h for the shape of it. */
#include "mesh_recon.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <unordered_map>
#include <vector>

#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
#include <BRepLib.hxx>
#include <BRepTools.hxx>
#include <GProp_GProps.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_ConicalSurface.hxx>
#include <Geom_CylindricalSurface.hxx>
#include <Geom_Plane.hxx>
#include <Geom_SphericalSurface.hxx>
#include <Geom_Surface.hxx>
#include <Geom_TrimmedCurve.hxx>
#include <Geom_ToroidalSurface.hxx>
#include <GeomAPI_IntSS.hxx>
#include <GeomAPI_PointsToBSpline.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <ShapeFix_Face.hxx>
#include <ShapeFix_Shape.hxx>
#include <ShapeFix_Shell.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <TopoDS_Vertex.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Ax3.hxx>
#include <gp_Circ.hxx>
#include <gp_Cone.hxx>
#include <gp_Cylinder.hxx>
#include <gp_Lin.hxx>
#include <gp_Pln.hxx>
#include <gp_Sphere.hxx>
#include <gp_Torus.hxx>

namespace meshrecon {

Params Defaults()
{
    Params p;
    p.mode = 1;
    p.tol_frac = 2.0e-3;
    p.sharp_deg = 22.0;
    p.weld_frac = 1.0e-6;
    p.snap_deg = 1.5;
    p.snap_radius_frac = 2.0e-3;
    p.max_faceted_triangles = 120000;
    p.min_patch_triangles = 2;
    return p;
}

void ClearReport(Report &r)
{
    std::memset(&r, 0, sizeof(r));
}

/* ====================================================================== */
/* Small vector maths. Deliberately local: pulling gp_Vec through the      */
/* fitting inner loops costs more than three doubles are worth, and the    */
/* eigen solver below has no OCCT equivalent that is any simpler to call.  */
/* ====================================================================== */
namespace {

struct V3
{
    double x, y, z;
    V3() : x(0), y(0), z(0) {}
    V3(double a, double b, double c) : x(a), y(b), z(c) {}
    V3 operator+(const V3 &o) const { return V3(x + o.x, y + o.y, z + o.z); }
    V3 operator-(const V3 &o) const { return V3(x - o.x, y - o.y, z - o.z); }
    V3 operator*(double s) const { return V3(x * s, y * s, z * s); }
    V3 &operator+=(const V3 &o)
    {
        x += o.x;
        y += o.y;
        z += o.z;
        return *this;
    }
};

inline double Dot(const V3 &a, const V3 &b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
inline V3 Cross(const V3 &a, const V3 &b)
{
    return V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z,
              a.x * b.y - a.y * b.x);
}
inline double Norm(const V3 &a)
{
    return std::sqrt(Dot(a, a));
}
inline V3 Unit(const V3 &a)
{
    const double n = Norm(a);
    return n > 0 ? V3(a.x / n, a.y / n, a.z / n) : V3(0, 0, 1);
}
inline gp_Pnt P(const V3 &a)
{
    return gp_Pnt(a.x, a.y, a.z);
}
inline gp_Dir D(const V3 &a)
{
    return gp_Dir(a.x, a.y, a.z);
}

/* Eigen-decomposition of a symmetric 3x3, by cyclic Jacobi.
 *
 * m is row-major and is destroyed. Eigenvalues come back in `val` ASCENDING,
 * with the matching unit eigenvectors in the ROWS of `vec`. Every surface fit
 * below leans on this: a plane's normal, a cylinder's axis and a cone's axis
 * are all "the eigenvector of some covariance with the smallest eigenvalue". */
void Jacobi3(double m[9], double val[3], double vec[9])
{
    for (int i = 0; i < 9; ++i)
        vec[i] = (i % 4 == 0) ? 1.0 : 0.0;
    for (int sweep = 0; sweep < 24; ++sweep) {
        double off = 0;
        for (int i = 0; i < 3; ++i)
            for (int j = i + 1; j < 3; ++j)
                off += m[i * 3 + j] * m[i * 3 + j];
        if (off < 1e-30)
            break;
        for (int p = 0; p < 3; ++p) {
            for (int q = p + 1; q < 3; ++q) {
                const double apq = m[p * 3 + q];
                if (std::fabs(apq) < 1e-300)
                    continue;
                const double theta = (m[q * 3 + q] - m[p * 3 + p]) / (2 * apq);
                const double t =
                    (theta >= 0 ? 1.0 : -1.0) /
                    (std::fabs(theta) + std::sqrt(theta * theta + 1));
                const double c = 1 / std::sqrt(t * t + 1), s = t * c;
                for (int k = 0; k < 3; ++k) {
                    const double akp = m[k * 3 + p], akq = m[k * 3 + q];
                    m[k * 3 + p] = c * akp - s * akq;
                    m[k * 3 + q] = s * akp + c * akq;
                }
                for (int k = 0; k < 3; ++k) {
                    const double apk = m[p * 3 + k], aqk = m[q * 3 + k];
                    m[p * 3 + k] = c * apk - s * aqk;
                    m[q * 3 + k] = s * apk + c * aqk;
                }
                for (int k = 0; k < 3; ++k) {
                    const double vkp = vec[k * 3 + p], vkq = vec[k * 3 + q];
                    vec[k * 3 + p] = c * vkp - s * vkq;
                    vec[k * 3 + q] = s * vkp + c * vkq;
                }
            }
        }
    }
    /* vec currently holds eigenvectors in COLUMNS; sort ascending and transpose
     * into rows so callers can say vec[0..2] for "the smallest". */
    int order[3] = {0, 1, 2};
    double d[3] = {m[0], m[4], m[8]};
    for (int i = 0; i < 3; ++i)
        for (int j = i + 1; j < 3; ++j)
            if (d[order[j]] < d[order[i]])
                std::swap(order[i], order[j]);
    double out[9];
    for (int i = 0; i < 3; ++i) {
        val[i] = d[order[i]];
        for (int k = 0; k < 3; ++k)
            out[i * 3 + k] = vec[k * 3 + order[i]];
    }
    std::memcpy(vec, out, sizeof(out));
}

/* Gauss elimination with partial pivoting. n <= 8. False if singular. */
bool SolveLin(double *a, double *b, int n)
{
    for (int c = 0; c < n; ++c) {
        int piv = c;
        for (int r = c + 1; r < n; ++r)
            if (std::fabs(a[r * n + c]) > std::fabs(a[piv * n + c]))
                piv = r;
        if (std::fabs(a[piv * n + c]) < 1e-14)
            return false;
        if (piv != c) {
            for (int k = 0; k < n; ++k)
                std::swap(a[c * n + k], a[piv * n + k]);
            std::swap(b[c], b[piv]);
        }
        for (int r = 0; r < n; ++r) {
            if (r == c)
                continue;
            const double f = a[r * n + c] / a[c * n + c];
            if (f == 0)
                continue;
            for (int k = c; k < n; ++k)
                a[r * n + k] -= f * a[c * n + k];
            b[r] -= f * b[c];
        }
    }
    for (int i = 0; i < n; ++i)
        b[i] /= a[i * n + i];
    return true;
}

/* ====================================================================== */
/* The mesh                                                               */
/* ====================================================================== */

struct Mesh
{
    std::vector<V3> pos;
    std::vector<int> tri;      /* 3 per triangle */
    std::vector<V3> tnorm;     /* per triangle, unit */
    std::vector<double> tarea; /* per triangle */
    /* adj[t*3+k] is the triangle across the k-th edge of triangle t — the
     * edge (tri[t*3+k], tri[t*3+(k+1)%3]) — or -1 at a boundary or at a
     * non-manifold edge. */
    std::vector<int> adj;
    V3 bbmin, bbmax;
    double diagonal = 0;

    int triCount() const { return static_cast<int>(tri.size() / 3); }
    int vertCount() const { return static_cast<int>(pos.size()); }
};

/* Welds vertices within `tol` using a hash grid, probing the 27 neighbouring
 * cells so a pair straddling a cell boundary still merges. This is the weld
 * mesh_io.dart deliberately does not do: it needs a spatial index over
 * millions of points and it needs the part's own scale to pick `tol`. */
struct WeldGrid
{
    double cell;
    std::unordered_map<long long, std::vector<int>> cells;
    const std::vector<V3> *pts;

    static long long Key(long long a, long long b, long long c)
    {
        /* Three 21-bit cell coordinates in one 64-bit key. The offset keeps
         * negative coordinates in range without a signed-shift question. */
        const long long m = 0x1FFFFF;
        return ((a + 0x100000) & m) | (((b + 0x100000) & m) << 21) |
               (((c + 0x100000) & m) << 42);
    }

    int Find(const V3 &p, double tol2) const
    {
        const long long ci = static_cast<long long>(std::floor(p.x / cell));
        const long long cj = static_cast<long long>(std::floor(p.y / cell));
        const long long ck = static_cast<long long>(std::floor(p.z / cell));
        for (int dx = -1; dx <= 1; ++dx)
            for (int dy = -1; dy <= 1; ++dy)
                for (int dz = -1; dz <= 1; ++dz) {
                    auto it = cells.find(Key(ci + dx, cj + dy, ck + dz));
                    if (it == cells.end())
                        continue;
                    for (int idx : it->second) {
                        const V3 d = (*pts)[idx] - p;
                        if (Dot(d, d) <= tol2)
                            return idx;
                    }
                }
        return -1;
    }

    void Add(const V3 &p, int idx)
    {
        const long long ci = static_cast<long long>(std::floor(p.x / cell));
        const long long cj = static_cast<long long>(std::floor(p.y / cell));
        const long long ck = static_cast<long long>(std::floor(p.z / cell));
        cells[Key(ci, cj, ck)].push_back(idx);
    }
};

bool BuildMesh(const double *xyz, int nv, const int *tri, int nt,
               const Params &prm, Mesh &m, Report &rep)
{
    rep.vertices_in = nv;
    rep.triangles_in = nt;
    if (nv < 3 || nt < 1)
        return false;

    m.bbmin = V3(1e300, 1e300, 1e300);
    m.bbmax = V3(-1e300, -1e300, -1e300);
    for (int i = 0; i < nv; ++i) {
        const V3 p(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);
        m.bbmin.x = std::min(m.bbmin.x, p.x);
        m.bbmax.x = std::max(m.bbmax.x, p.x);
        m.bbmin.y = std::min(m.bbmin.y, p.y);
        m.bbmax.y = std::max(m.bbmax.y, p.y);
        m.bbmin.z = std::min(m.bbmin.z, p.z);
        m.bbmax.z = std::max(m.bbmax.z, p.z);
    }
    m.diagonal = Norm(m.bbmax - m.bbmin);
    if (!(m.diagonal > 0))
        return false;
    rep.diagonal = m.diagonal;

    const double tol = std::max(m.diagonal * prm.weld_frac, 1e-12);
    WeldGrid grid;
    grid.cell = tol * 2;
    grid.pts = &m.pos;
    m.pos.reserve(nv);
    std::vector<int> remap(nv, -1);
    const double tol2 = tol * tol;
    for (int i = 0; i < nv; ++i) {
        const V3 p(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);
        int hit = grid.Find(p, tol2);
        if (hit < 0) {
            hit = static_cast<int>(m.pos.size());
            m.pos.push_back(p);
            grid.Add(p, hit);
        }
        remap[i] = hit;
    }
    rep.vertices_welded = static_cast<int>(m.pos.size());

    m.tri.reserve(nt * 3);
    for (int t = 0; t < nt; ++t) {
        const int a = tri[t * 3], b = tri[t * 3 + 1], c = tri[t * 3 + 2];
        if (a < 0 || b < 0 || c < 0 || a >= nv || b >= nv || c >= nv)
            continue;
        const int ra = remap[a], rb = remap[b], rc = remap[c];
        if (ra == rb || rb == rc || ra == rc)
            continue;
        const V3 n = Cross(m.pos[rb] - m.pos[ra], m.pos[rc] - m.pos[ra]);
        /* A triangle with no area carries no normal and no adjacency worth
         * having; keeping it only puts a degenerate face in the shell. */
        if (Norm(n) <= 1e-24 * m.diagonal * m.diagonal)
            continue;
        m.tri.push_back(ra);
        m.tri.push_back(rb);
        m.tri.push_back(rc);
    }
    rep.triangles_used = m.triCount();
    if (m.triCount() < 1)
        return false;

    m.tnorm.resize(m.triCount());
    m.tarea.resize(m.triCount());
    for (int t = 0; t < m.triCount(); ++t) {
        const V3 n = Cross(m.pos[m.tri[t * 3 + 1]] - m.pos[m.tri[t * 3]],
                           m.pos[m.tri[t * 3 + 2]] - m.pos[m.tri[t * 3]]);
        m.tarea[t] = Norm(n) * 0.5;
        m.tnorm[t] = Unit(n);
    }
    return true;
}

/* Reverses one triangle's winding, keeping its adjacency straight.
 *
 * adj[t*3+k] is the neighbour across the edge (tri[k], tri[k+1]). Swapping
 * vertices 1 and 2 renames those edges — old edge 0 becomes new edge 2 and
 * vice versa — so the adjacency has to be permuted with them. Flipping without
 * this leaves the mesh believing in neighbours it does not have, and the bug
 * only shows up on meshes that needed flipping at all. */
void FlipTriangle(Mesh &m, int t)
{
    std::swap(m.tri[t * 3 + 1], m.tri[t * 3 + 2]);
    if (!m.adj.empty())
        std::swap(m.adj[t * 3 + 0], m.adj[t * 3 + 2]);
    m.tnorm[t] = V3(-m.tnorm[t].x, -m.tnorm[t].y, -m.tnorm[t].z);
}

/* Fills m.adj. An edge shared by more than two triangles is non-manifold; both
 * sides are left unlinked, which turns it into a patch boundary. That is the
 * right answer rather than an error: downloaded models are full of them, and a
 * non-manifold edge IS a feature boundary in every case that matters. */
void BuildAdjacency(Mesh &m, Report &rep)
{
    m.adj.assign(m.tri.size(), -1);
    /* Key an undirected edge on its two welded vertex ids. */
    std::unordered_map<long long, int> half; /* edge -> first (t*3+k) */
    std::unordered_map<long long, int> count;
    half.reserve(m.tri.size());
    count.reserve(m.tri.size());
    const long long n = m.vertCount();
    for (int t = 0; t < m.triCount(); ++t) {
        for (int k = 0; k < 3; ++k) {
            const int a = m.tri[t * 3 + k], b = m.tri[t * 3 + (k + 1) % 3];
            const long long key =
                (long long)std::min(a, b) * n + std::max(a, b);
            const int c = ++count[key];
            if (c == 1) {
                half[key] = t * 3 + k;
            } else if (c == 2) {
                const int other = half[key];
                m.adj[t * 3 + k] = other / 3;
                m.adj[other] = t;
            } else {
                /* Third and later: unlink the pair already made. */
                const int other = half[key];
                if (m.adj[other] >= 0) {
                    const int o2 = m.adj[other];
                    for (int kk = 0; kk < 3; ++kk)
                        if (m.adj[o2 * 3 + kk] == other / 3)
                            m.adj[o2 * 3 + kk] = -1;
                    m.adj[other] = -1;
                }
                m.adj[t * 3 + k] = -1;
            }
        }
    }
    for (auto &e : count) {
        if (e.second == 1)
            rep.boundary_edges++;
        else if (e.second > 2)
            rep.non_manifold_edges++;
    }
}

/* Makes the winding consistent across each connected component, then flips
 * whole components whose enclosed volume comes out negative.
 *
 * Downloaded meshes are routinely inside-out, and an inside-out shell sews
 * into a solid of negative volume that every boolean afterwards gets wrong. */
void OrientMesh(Mesh &m, Report &rep)
{
    const int nt = m.triCount();
    std::vector<char> seen(nt, 0);
    std::vector<int> stack, comp;
    for (int seed = 0; seed < nt; ++seed) {
        if (seen[seed])
            continue;
        stack.clear();
        comp.clear();
        stack.push_back(seed);
        seen[seed] = 1;
        while (!stack.empty()) {
            const int t = stack.back();
            stack.pop_back();
            comp.push_back(t);
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0 || seen[o])
                    continue;
                /* Neighbours agree when they traverse the shared edge in
                 * OPPOSITE directions. If they do not, flip the neighbour. */
                const int a = m.tri[t * 3 + k], b = m.tri[t * 3 + (k + 1) % 3];
                bool same = false;
                for (int kk = 0; kk < 3; ++kk) {
                    if (m.tri[o * 3 + kk] == a &&
                        m.tri[o * 3 + (kk + 1) % 3] == b) {
                        same = true;
                        break;
                    }
                }
                if (same) {
                    FlipTriangle(m, o);
                    rep.flipped_triangles++;
                }
                seen[o] = 1;
                stack.push_back(o);
            }
        }
        /* Signed volume of this component about the origin; negative means the
         * component is inside-out as a whole. */
        double vol = 0;
        for (int t : comp) {
            const V3 &a = m.pos[m.tri[t * 3]];
            const V3 &b = m.pos[m.tri[t * 3 + 1]];
            const V3 &c = m.pos[m.tri[t * 3 + 2]];
            vol += Dot(a, Cross(b, c));
        }
        if (vol < 0) {
            for (int t : comp) {
                FlipTriangle(m, t);
                rep.flipped_triangles++;
            }
        }
    }
}

/* ====================================================================== */
/* Surface fitting                                                        */
/* ====================================================================== */

enum SurfKind {
    kNone = 0,
    kPlane,
    kCylinder,
    kCone,
    kSphere,
    kTorus,
    kFreeform,
    kFaceted
};

/* A fitted surface as parameters, before it becomes a Geom_Surface.
 *
 * q[] is the same parameter vector the refiner works on, laid out per kind:
 *   plane    nx ny nz d                (n unit, d = n.p)
 *   sphere   cx cy cz r
 *   cylinder px py pz ax ay az r       (p any point on the axis, a unit)
 *   cone     apex(3) axis(3) halfangle
 *   torus    cx cy cz ax ay az R r
 * Keeping one vector for all five is what lets one Gauss-Newton serve them. */
struct Fit
{
    SurfKind kind = kNone;
    double q[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    double rms = 1e300;
    /* Mean |cos| between this surface's normals and the mesh's. Kept on the
     * fit because MergeRegions holds it to a far higher standard than the
     * first-pass classifier does — see kMergeNormalGate. */
    double agree = 0;
};

int ParamCount(SurfKind k)
{
    switch (k) {
    case kPlane:
        return 4;
    case kSphere:
        return 4;
    case kCylinder:
        return 7;
    case kCone:
        return 7;
    case kTorus:
        return 8;
    default:
        return 0;
    }
}

/* Signed distance from p to the surface described by q. Sign is meaningful
 * (outside positive for the closed kinds); only the magnitude is ever used. */
double SurfDist(SurfKind k, const double *q, const V3 &p)
{
    switch (k) {
    case kPlane: {
        return q[0] * p.x + q[1] * p.y + q[2] * p.z - q[3];
    }
    case kSphere: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        return Norm(v) - q[3];
    }
    case kCylinder: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        const V3 a(q[3], q[4], q[5]);
        const double u = Dot(v, a);
        return Norm(v - a * u) - q[6];
    }
    case kCone: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        const V3 a(q[3], q[4], q[5]);
        const double u = Dot(v, a);
        const double w = Norm(v - a * u);
        return w * std::cos(q[6]) - u * std::sin(q[6]);
    }
    case kTorus: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        const V3 a(q[3], q[4], q[5]);
        const double u = Dot(v, a);
        const double w = Norm(v - a * u);
        const double dr = w - q[6];
        return std::sqrt(dr * dr + u * u) - q[7];
    }
    default:
        return 0;
    }
}

/* Keeps the direction entries of q unit-length. Gauss-Newton walks them off
 * the sphere otherwise and the distance function stops meaning anything. */
void Renormalise(SurfKind k, double *q)
{
    if (k == kPlane) {
        const V3 n = Unit(V3(q[0], q[1], q[2]));
        q[0] = n.x;
        q[1] = n.y;
        q[2] = n.z;
    } else if (k == kCylinder || k == kCone || k == kTorus) {
        const V3 a = Unit(V3(q[3], q[4], q[5]));
        q[3] = a.x;
        q[4] = a.y;
        q[5] = a.z;
    }
}

/* What a fit reads off a set of triangles.
 *
 * TWO clouds, and the split is the hard-won part. `pts` are the patch's unique
 * VERTICES and carry the residual: they sit exactly on the original surface.
 * `spos`/`snrm` are oriented SAMPLES — each triangle contributes its three
 * corners, each tagged with that triangle's own normal — and every
 * direction-sensitive step reads those.
 *
 * Two wrong versions of this were written before the right one, and both
 * are worth keeping in view because both look reasonable:
 *
 *   per-VERTEX averaged normals. A vertex normal has to be blended from the
 *   triangles around it, and on a cylinder's rim those belong to the barrel AND
 *   to the cap. The blend points somewhere that exists on neither surface, and
 *   it is enough to convince the fitter that cap and barrel are one cylinder.
 *
 *   per-TRIANGLE centroids and normals. Uncontaminated, and degenerate exactly
 *   where it matters: a tessellated barrel is RULED, so every centroid lands at
 *   mid-height — the one height where a sphere through the two end rings has a
 *   radial normal too. A drilled hole came back a ball.
 *
 * Corner positions with the owning triangle's normal have neither problem. The
 * normal never blends, and the samples spread over the whole patch instead of
 * collapsing onto one iso-line. */
struct PatchData
{
    std::vector<V3> pts;        /* unique vertices, for the residual */
    std::vector<V3> spos, snrm; /* corner positions + owning triangle normal */
};

/* The surface normal at p, as the gradient of the distance function.
 *
 * Numerical rather than five hand-derived gradients, for the same reason the
 * refiner's Jacobian is: SurfDist is already the single definition of each
 * surface, and a normal from it cannot drift out of agreement with it. */
V3 SurfNormal(SurfKind k, const double *q, const V3 &p, double h)
{
    const V3 g(SurfDist(k, q, V3(p.x + h, p.y, p.z)) -
                   SurfDist(k, q, V3(p.x - h, p.y, p.z)),
               SurfDist(k, q, V3(p.x, p.y + h, p.z)) -
                   SurfDist(k, q, V3(p.x, p.y - h, p.z)),
               SurfDist(k, q, V3(p.x, p.y, p.z + h)) -
                   SurfDist(k, q, V3(p.x, p.y, p.z - h)));
    return Unit(g);
}

/* Mean |cos| between the fitted surface's normal and the mesh's own normal.
 *
 * WHY THIS EXISTS. Point distance alone does not identify a surface, and the
 * case that proves it is the common one: a tessellated cylinder barrel is a
 * RULED strip, so every vertex sits on one of the two end circles and nowhere
 * in between. Those two circles lie exactly on a sphere as well as on the
 * cylinder, so a points-only fit reports a perfect sphere and means it. The
 * normals are what tell them apart — a cylinder's point along the radius, the
 * sphere's tilt toward its centre — and checking them is the difference
 * between recognising a hole and inventing a ball. */
double NormalAgreement(SurfKind k, const double *q, const std::vector<V3> &spos,
                       const std::vector<V3> &snrm, double scale)
{
    if (spos.empty() || snrm.size() != spos.size())
        return 0;
    const double h = std::max(scale * 1e-5, 1e-9);
    double acc = 0;
    int n = 0;
    for (size_t i = 0; i < spos.size(); ++i) {
        const V3 sn = SurfNormal(k, q, spos[i], h);
        if (Norm(sn) < 0.5)
            continue; /* on an axis or at an apex */
        acc += std::fabs(Dot(sn, snrm[i]));
        n++;
    }
    return n > 0 ? acc / n : 0;
}

double FitRms(SurfKind k, const double *q, const std::vector<V3> &pts)
{
    if (pts.empty())
        return 1e300;
    double s = 0;
    for (const V3 &p : pts) {
        const double d = SurfDist(k, q, p);
        s += d * d;
    }
    return std::sqrt(s / pts.size());
}

/* Gauss-Newton with a numerical Jacobian and Levenberg damping.
 *
 * Numerical rather than analytic on purpose: five surface kinds times up to
 * eight parameters is forty derivatives to get right and to keep right, and
 * the fit runs once per patch, not per frame. The damping is what makes it
 * survive a bad seed, which on a downloaded mesh it will regularly get. */
void RefineFit(SurfKind k, double *q, const std::vector<V3> &pts, double scale,
               const bool *freeMask = nullptr)
{
    const int n = ParamCount(k);
    if (n == 0 || pts.size() < static_cast<size_t>(n))
        return;
    const double h = std::max(scale * 1e-6, 1e-12);
    double lambda = 1e-6;
    double best = FitRms(k, q, pts);
    std::vector<double> J(n);
    for (int iter = 0; iter < 24; ++iter) {
        double JtJ[64] = {0}, Jtr[8] = {0};
        for (const V3 &p : pts) {
            const double r = SurfDist(k, q, p);
            for (int i = 0; i < n; ++i) {
                if (freeMask && !freeMask[i]) {
                    J[i] = 0;
                    continue;
                }
                const double save = q[i];
                q[i] = save + h;
                const double rp = SurfDist(k, q, p);
                q[i] = save - h;
                const double rm = SurfDist(k, q, p);
                q[i] = save;
                J[i] = (rp - rm) / (2 * h);
            }
            for (int i = 0; i < n; ++i) {
                Jtr[i] -= J[i] * r;
                for (int j = 0; j < n; ++j)
                    JtJ[i * n + j] += J[i] * J[j];
            }
        }
        double A[64], b[8];
        std::memcpy(A, JtJ, sizeof(A));
        std::memcpy(b, Jtr, sizeof(b));
        for (int i = 0; i < n; ++i) {
            if (freeMask && !freeMask[i]) {
                A[i * n + i] = 1.0;
                continue;
            }
            A[i * n + i] *= (1.0 + lambda);
        }
        if (!SolveLin(A, b, n))
            break;
        double cand[8];
        std::memcpy(cand, q, sizeof(cand));
        for (int i = 0; i < n; ++i)
            cand[i] += b[i];
        Renormalise(k, cand);
        if (freeMask) {
            for (int i = 0; i < n; ++i)
                if (!freeMask[i])
                    cand[i] = q[i];
        }
        const double rms = FitRms(k, cand, pts);
        if (!(rms < best)) {
            lambda *= 8;
            if (lambda > 1e8)
                break;
            continue;
        }
        const double gain = best - rms;
        std::memcpy(q, cand, sizeof(cand));
        best = rms;
        lambda = std::max(lambda * 0.3, 1e-12);
        if (gain < scale * 1e-12)
            break;
    }
}

/* --- seeds ----------------------------------------------------------- */

void Centroid(const std::vector<V3> &pts, V3 &c)
{
    c = V3();
    for (const V3 &p : pts)
        c += p;
    if (!pts.empty())
        c = c * (1.0 / pts.size());
}

/* Covariance of pts about their centroid, row-major. */
void Covariance(const std::vector<V3> &pts, const V3 &c, double m[9])
{
    std::memset(m, 0, sizeof(double) * 9);
    for (const V3 &p : pts) {
        const V3 d = p - c;
        const double v[3] = {d.x, d.y, d.z};
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                m[i * 3 + j] += v[i] * v[j];
    }
}

bool SeedPlane(const std::vector<V3> &pts, double *q)
{
    if (pts.size() < 3)
        return false;
    V3 c;
    Centroid(pts, c);
    double m[9], val[3], vec[9];
    Covariance(pts, c, m);
    Jacobi3(m, val, vec);
    const V3 n = Unit(V3(vec[0], vec[1], vec[2])); /* smallest eigenvalue */
    q[0] = n.x;
    q[1] = n.y;
    q[2] = n.z;
    q[3] = Dot(n, c);
    return true;
}

/* Algebraic sphere: |p|^2 = 2c.p + (r^2 - |c|^2), which is linear in
 * (cx, cy, cz, k). Good enough to start Gauss-Newton from. */
bool SeedSphere(const std::vector<V3> &pts, double *q)
{
    if (pts.size() < 4)
        return false;
    double A[16] = {0}, b[4] = {0};
    for (const V3 &p : pts) {
        const double row[4] = {2 * p.x, 2 * p.y, 2 * p.z, 1.0};
        const double rhs = p.x * p.x + p.y * p.y + p.z * p.z;
        for (int i = 0; i < 4; ++i) {
            b[i] += row[i] * rhs;
            for (int j = 0; j < 4; ++j)
                A[i * 4 + j] += row[i] * row[j];
        }
    }
    if (!SolveLin(A, b, 4))
        return false;
    const double r2 = b[3] + b[0] * b[0] + b[1] * b[1] + b[2] * b[2];
    if (!(r2 > 0))
        return false;
    q[0] = b[0];
    q[1] = b[1];
    q[2] = b[2];
    q[3] = std::sqrt(r2);
    return true;
}

/* A cylinder's normals are all perpendicular to its axis, so the axis is the
 * direction the normal cloud never points in: the smallest eigenvector of
 * sum(n n^T). With the axis known the rest is a 2D circle fit. */
bool SeedCylinder(const std::vector<V3> &pts, const std::vector<V3> &nrm,
                  double *q)
{
    if (pts.size() < 5 || nrm.size() != pts.size())
        return false;
    double m[9] = {0}, val[3], vec[9];
    for (const V3 &n : nrm) {
        const double v[3] = {n.x, n.y, n.z};
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                m[i * 3 + j] += v[i] * v[j];
    }
    Jacobi3(m, val, vec);
    const V3 a = Unit(V3(vec[0], vec[1], vec[2]));
    /* Build an orthonormal frame across the axis and fit a circle in it. */
    V3 e1 = Cross(a, std::fabs(a.x) < 0.9 ? V3(1, 0, 0) : V3(0, 1, 0));
    e1 = Unit(e1);
    const V3 e2 = Cross(a, e1);
    V3 c;
    Centroid(pts, c);
    double A[9] = {0}, b[3] = {0};
    for (const V3 &p : pts) {
        const V3 d = p - c;
        const double x = Dot(d, e1), y = Dot(d, e2);
        const double row[3] = {2 * x, 2 * y, 1.0};
        const double rhs = x * x + y * y;
        for (int i = 0; i < 3; ++i) {
            b[i] += row[i] * rhs;
            for (int j = 0; j < 3; ++j)
                A[i * 3 + j] += row[i] * row[j];
        }
    }
    if (!SolveLin(A, b, 3))
        return false;
    const double r2 = b[2] + b[0] * b[0] + b[1] * b[1];
    if (!(r2 > 0))
        return false;
    const V3 axisPt = c + e1 * b[0] + e2 * b[1];
    q[0] = axisPt.x;
    q[1] = axisPt.y;
    q[2] = axisPt.z;
    q[3] = a.x;
    q[4] = a.y;
    q[5] = a.z;
    q[6] = std::sqrt(r2);
    return true;
}

/* A cone's normals all make the same angle with its axis, so they lie on a
 * PLANE when read as points on the unit sphere: that plane's normal is the
 * axis. The apex then falls out of a 2D fit in the plane across it. */
bool SeedCone(const std::vector<V3> &pts, const std::vector<V3> &nrm, double *q)
{
    if (pts.size() < 6 || nrm.size() != pts.size())
        return false;
    double pl[4];
    if (!SeedPlane(nrm, pl))
        return false;
    V3 a = Unit(V3(pl[0], pl[1], pl[2]));
    double sinA = pl[3];
    if (sinA < 0) {
        a = a * -1.0;
        sinA = -sinA;
    }
    if (!(sinA > 1e-3) || sinA > 0.999)
        return false; /* cylinder or plane */
    const double alpha = std::asin(std::min(1.0, sinA));

    /* Axis line: in the plane across `a` the projected normals point away from
     * the axis, so the axis point is the least-squares intersection of the
     * projected normal lines. Each line contributes (I - dd^T). */
    V3 e1 = Unit(Cross(a, std::fabs(a.x) < 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)));
    const V3 e2 = Cross(a, e1);
    V3 c;
    Centroid(pts, c);
    double A[4] = {0}, b[2] = {0};
    for (size_t i = 0; i < pts.size(); ++i) {
        const V3 d = pts[i] - c;
        const double px = Dot(d, e1), py = Dot(d, e2);
        V3 np = nrm[i] - a * Dot(nrm[i], a);
        const double nn = Norm(np);
        if (nn < 1e-9)
            continue;
        np = np * (1.0 / nn);
        const double dx = Dot(np, e1), dy = Dot(np, e2);
        /* Distance from x to the line through (px,py) along (dx,dy): the
         * normal of that line is (-dy, dx). */
        const double lx = -dy, ly = dx;
        const double off = lx * px + ly * py;
        A[0] += lx * lx;
        A[1] += lx * ly;
        A[2] += ly * lx;
        A[3] += ly * ly;
        b[0] += lx * off;
        b[1] += ly * off;
    }
    if (!SolveLin(A, b, 2))
        return false;
    const V3 axisPt = c + e1 * b[0] + e2 * b[1];

    /* Apex: distance from the axis falls linearly to zero along it. */
    double su = 0, sw = 0, suu = 0, suw = 0;
    const int n = static_cast<int>(pts.size());
    for (const V3 &p : pts) {
        const V3 v = p - axisPt;
        const double u = Dot(v, a);
        const double w = Norm(v - a * u);
        su += u;
        sw += w;
        suu += u * u;
        suw += u * w;
    }
    const double den = n * suu - su * su;
    if (std::fabs(den) < 1e-18)
        return false;
    const double slope = (n * suw - su * sw) / den;
    const double inter = (sw - slope * su) / n;
    if (std::fabs(slope) < 1e-9)
        return false;
    const double uApex = -inter / slope;
    const V3 apex = axisPt + a * uApex;
    /* Point the axis from the apex INTO the material, so the half-angle is
     * positive and Geom_ConicalSurface gets a growing radius. */
    const V3 dir = slope > 0 ? a : a * -1.0;
    q[0] = apex.x;
    q[1] = apex.y;
    q[2] = apex.z;
    q[3] = dir.x;
    q[4] = dir.y;
    q[5] = dir.z;
    q[6] = alpha;
    return true;
}

/* A torus's normal lines all meet the SPINE circle, so the closest approach of
 * two nearby normal lines lands on it. Fit a plane to those meeting points and
 * the plane's normal is the axis; fit a circle in it and that is R. */
bool SeedTorus(const std::vector<V3> &pts, const std::vector<V3> &nrm,
               double *q)
{
    const size_t n = pts.size();
    if (n < 12 || nrm.size() != n)
        return false;
    std::vector<V3> spine;
    spine.reserve(n);
    /* Pair each point with one a stride away, so the two normals are far
     * enough apart to intersect well but still on the same tube. */
    const size_t stride = std::max<size_t>(1, n / 16);
    for (size_t i = 0; i + stride < n; ++i) {
        const V3 &p1 = pts[i];
        const V3 &d1 = nrm[i];
        const V3 &p2 = pts[i + stride];
        const V3 &d2 = nrm[i + stride];
        const double d1d2 = Dot(d1, d2);
        const double den = 1 - d1d2 * d1d2;
        if (den < 1e-4)
            continue; /* near-parallel: no usable intersection */
        const V3 w = p1 - p2;
        const double t1 = (d1d2 * Dot(w, d2) - Dot(w, d1)) / den;
        const double t2 = (Dot(w, d2) - d1d2 * Dot(w, d1)) / den;
        spine.push_back((p1 + d1 * t1 + (p2 + d2 * t2)) * 0.5);
    }
    if (spine.size() < 8)
        return false;
    double pl[4];
    if (!SeedPlane(spine, pl))
        return false;
    const V3 a = Unit(V3(pl[0], pl[1], pl[2]));
    V3 c;
    Centroid(spine, c);
    /* Project the spine points into the plane and take the mean radius. */
    double R = 0;
    for (const V3 &s : spine) {
        const V3 v = s - c;
        R += Norm(v - a * Dot(v, a));
    }
    R /= spine.size();
    if (!(R > 0))
        return false;
    /* Minor radius: mean distance from the points to the spine circle. */
    double r = 0;
    for (const V3 &p : pts) {
        const V3 v = p - c;
        const double u = Dot(v, a);
        const double w = Norm(v - a * u) - R;
        r += std::sqrt(w * w + u * u);
    }
    r /= n;
    if (!(r > 0) || r >= R * 4)
        return false;
    q[0] = c.x;
    q[1] = c.y;
    q[2] = c.z;
    q[3] = a.x;
    q[4] = a.y;
    q[5] = a.z;
    q[6] = R;
    q[7] = r;
    return true;
}

/* Tries all five and keeps the simplest one that fits inside `tol`.
 *
 * Order matters and is not by residual alone: a sphere will fit a shallow
 * cylindrical patch to within tolerance, and a torus will fit almost anything
 * given enough freedom. Preferring the earlier kind at equal quality is what
 * keeps a flat face a PLANE instead of a sphere of radius 10^6. */
#ifdef MESHRECON_TRACE
#define MR_TRACE(...) std::fprintf(stderr, __VA_ARGS__)
/* Compiled in only for the development harness; see backend/occt/tests. */
const char *KindName(SurfKind k)
{
    switch (k) {
    case kPlane:
        return "plane";
    case kSphere:
        return "sphere";
    case kCylinder:
        return "cyl";
    case kCone:
        return "cone";
    case kTorus:
        return "torus";
    default:
        return "?";
    }
}
#else
#define MR_TRACE(...) ((void)0)
#endif

/* Mean |cos| a candidate surface's normals must reach to be believed. About
 * 25 degrees of average slack: loose enough for a coarse download's estimated
 * vertex normals, tight enough that a sphere never passes for a cylinder. */
const double kMinNormalAgreement = 0.90;

/* Largest fitted radius worth believing, as a multiple of the part's own
 * bounding-box diagonal. */
const double kMaxRadiusFactor = 4.0;

Fit FitPatch(const PatchData &d, double tol, double scale)
{
    const std::vector<V3> &pts = d.pts;
    Fit best;
    const SurfKind order[5] = {kPlane, kSphere, kCylinder, kCone, kTorus};
    for (int i = 0; i < 5; ++i) {
        const SurfKind k = order[i];
        double q[8] = {0};
        bool ok = false;
        switch (k) {
        case kPlane:
            ok = SeedPlane(pts, q);
            break;
        case kSphere:
            ok = SeedSphere(pts, q);
            break;
        case kCylinder:
            ok = SeedCylinder(d.spos, d.snrm, q);
            break;
        case kCone:
            ok = SeedCone(d.spos, d.snrm, q);
            break;
        case kTorus:
            ok = SeedTorus(d.spos, d.snrm, q);
            break;
        default:
            break;
        }
        if (!ok)
            continue;
        Renormalise(k, q);
        RefineFit(k, q, pts, scale);
        const double rms = FitRms(k, q, pts);
#ifdef MESHRECON_TRACE
        std::fprintf(
            stderr,
            "      %-6s rms=%.6f tol=%.6f nrm=%.3f n=%d  "
            "q=[%.3f %.3f %.3f %.3f %.3f %.3f %.4f %.4f]\n",
            KindName(k), rms, tol, NormalAgreement(k, q, d.spos, d.snrm, scale),
            (int)pts.size(), q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7]);
#endif
        if (!(rms < 1e299))
            continue;
        /* Reject degenerate radii outright: a "cylinder" of radius 10^6 across
         * a 20 mm part is a plane that fitted by accident, and it would build
         * a surface no downstream operation can use. */
        /* A radius many times the whole part is not a feature of it. Such a
         * fit is a plane that curved slightly by accident — and `plane` was
         * tried first and already declined, so there is nothing to lose by
         * refusing it and letting the patch be split further. */
        const double rMax = scale * kMaxRadiusFactor;
        if ((k == kCylinder && q[6] > rMax) || (k == kSphere && q[3] > rMax) ||
            (k == kTorus && (q[6] > rMax || q[7] > rMax))) {
            continue;
        }
        /* A surface that passes through the points but faces the wrong way is
         * not the surface those points came off. See NormalAgreement. */
        const double agree = NormalAgreement(k, q, d.spos, d.snrm, scale);
        if (agree < kMinNormalAgreement)
            continue;
        if (rms <= tol) {
            best.kind = k;
            std::memcpy(best.q, q, sizeof(q));
            best.rms = rms;
            best.agree = agree;
            return best; /* simplest kind that fits wins */
        }
        if (rms < best.rms) {
            best.kind = k;
            std::memcpy(best.q, q, sizeof(q));
            best.rms = rms;
            best.agree = agree;
        }
    }
    if (best.rms > tol)
        best.kind = kNone; /* nothing fitted; caller decides */
    return best;
}

/* ====================================================================== */
/* Segmentation                                                           */
/* ====================================================================== */

struct Patch
{
    std::vector<int> tris;
    Fit fit;
    /* Which smooth patch this came out of. MergeRegions will only put two
     * patches back together if they started as one, which is what keeps a
     * merge from ever crossing a sharp edge. */
    int origin = -1;
};

void PatchPoints(const Mesh &m, const std::vector<int> &tris, PatchData &d,
                 int cap)
{
    d.pts.clear();
    d.spos.clear();
    d.snrm.clear();
    std::unordered_map<int, char> seen;
    seen.reserve(tris.size() * 2);
    /* Fitting a million points buys no accuracy over fitting four thousand of
     * them, and costs a second per patch. Stride, do not truncate: the first
     * four thousand triangles of a patch are one corner of it. */
    const size_t step = (cap > 0 && tris.size() > static_cast<size_t>(cap))
                            ? tris.size() / cap + 1
                            : 1;
    d.spos.reserve(tris.size() / step * 3 + 3);
    d.snrm.reserve(tris.size() / step * 3 + 3);
    for (size_t i = 0; i < tris.size(); i += step) {
        const int t = tris[i];
        for (int k = 0; k < 3; ++k) {
            const int v = m.tri[t * 3 + k];
            d.spos.push_back(m.pos[v]);
            d.snrm.push_back(m.tnorm[t]);
            if (seen.emplace(v, 1).second)
                d.pts.push_back(m.pos[v]);
        }
    }
}

/* Groups triangles into patches bounded by sharp edges — the cheap, correct
 * first cut. A model that came from CAD (which is most of what gets
 * downloaded) is already almost segmented this way: a cylinder's barrel is one
 * smooth run bounded by the sharp circles at its ends. */
void SmoothPatches(const Mesh &m, double sharpDeg, std::vector<int> &patchOf,
                   int &patchCount)
{
    const double cosSharp = std::cos(sharpDeg * M_PI / 180.0);
    const int nt = m.triCount();
    patchOf.assign(nt, -1);
    patchCount = 0;
    std::vector<int> stack;
    for (int seed = 0; seed < nt; ++seed) {
        if (patchOf[seed] >= 0)
            continue;
        const int id = patchCount++;
        stack.clear();
        stack.push_back(seed);
        patchOf[seed] = id;
        while (!stack.empty()) {
            const int t = stack.back();
            stack.pop_back();
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0 || patchOf[o] >= 0)
                    continue;
                if (Dot(m.tnorm[t], m.tnorm[o]) < cosSharp)
                    continue;
                patchOf[o] = id;
                stack.push_back(o);
            }
        }
    }
}

/* How closely a candidate triangle's normal must follow the running fit's, to
 * be taken into the region. About 8 degrees: tight enough that a plane stops
 * one facet into a blend, loose enough that a blend's own facets — half a facet
 * angle off the fitted surface — all get in. */
const double kGrowNormalGate = 0.99;

/* Splits one patch that fitted nothing into sub-patches that do, by growing a
 * region from a seed while a running fit keeps holding.
 *
 * This is the step that separates a fillet from the faces it blends. A fillet
 * meets its neighbours TANGENTIALLY, so no dihedral threshold will ever cut
 * there — but a plane fit stops accepting triangles the moment the surface
 * starts to curve, and that is exactly the fillet's edge. */
void SplitByFit(const Mesh &m, const std::vector<int> &tris, double tol,
                double scale, int minTris, int origin, std::vector<Patch> &out)
{
    std::unordered_map<int, int> local; /* triangle -> index in tris */
    for (size_t i = 0; i < tris.size(); ++i)
        local.emplace(tris[i], static_cast<int>(i));
    std::vector<char> taken(tris.size(), 0);

    /* How sharply the surface turns at each triangle: the largest angle to a
     * neighbour INSIDE this patch. Used ONLY to order the seeds.
     *
     * It is tempting to gate the growth on this too, and it does not work: the
     * value is the max over neighbours, so a flat triangle that happens to
     * touch a fillet reports the fillet's angle and is indistinguishable from
     * one. As a seed ORDER it is still worth having — the flat, confident parts
     * of the patch claim their triangles before a blend starts guessing. */
    std::vector<double> bend(tris.size(), 0.0);
    for (size_t i = 0; i < tris.size(); ++i) {
        const int t = tris[i];
        double worst = 0;
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || local.find(o) == local.end())
                continue;
            const double c =
                std::max(-1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])));
            worst = std::max(worst, std::acos(c));
        }
        bend[i] = worst;
    }

    /* Flattest first, then largest. A planar face is the most confident thing
     * in the patch, so it should claim its triangles before a blend does. */
    std::vector<int> byArea(tris.size());
    for (size_t i = 0; i < tris.size(); ++i)
        byArea[i] = static_cast<int>(i);
    std::sort(byArea.begin(), byArea.end(), [&](int a, int b) {
        if (std::fabs(bend[a] - bend[b]) > 1e-4)
            return bend[a] < bend[b];
        return m.tarea[tris[a]] > m.tarea[tris[b]];
    });

    std::vector<int> region, frontier;
    PatchData pd;
    for (int si : byArea) {
        if (taken[si])
            continue;
        region.clear();
        region.push_back(tris[si]);
        taken[si] = 1;

        /* Seed the fit from the immediate neighbourhood, then grow. */
        Fit fit;
        int sinceRefit = 0;
        frontier.assign(1, tris[si]);
        while (!frontier.empty()) {
            const int t = frontier.back();
            frontier.pop_back();
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0)
                    continue;
                auto it = local.find(o);
                if (it == local.end() || taken[it->second])
                    continue;
                bool accept;
                if (fit.kind == kNone) {
                    /* Before there is a fit there is nothing to test against,
                     * so hold the seed together by normal alone and let the fit
                     * take over as soon as there are points enough to make one.
                     * This only has to avoid turning a corner; a tangent seam
                     * it cannot see; MergeRegions repairs that after. */
                    accept = region.size() < 12 &&
                             Dot(m.tnorm[o], m.tnorm[tris[si]]) > 0.9;
                } else {
                    accept = true;
                    V3 c;
                    for (int kk = 0; kk < 3 && accept; ++kk) {
                        const V3 &p = m.pos[m.tri[o * 3 + kk]];
                        c += p;
                        if (std::fabs(SurfDist(fit.kind, fit.q, p)) >
                            tol * 1.5) {
                            accept = false;
                        }
                    }
                    /* Distance alone lets a PLANE eat into a fillet.
                     *
                     * The blend leaves the plane tangentially, so its first
                     * facets are only microns off it and pass any distance
                     * test — and once two of them are in the region, the fit
                     * is of a plane-and-a-bit-of-arc, which lands on a sphere
                     * of radius fifty on a forty-five millimetre part. Where
                     * the surface goes is what separates them: one facet into
                     * the blend the direction is already visibly turning. */
                    if (accept) {
                        const V3 sn =
                            SurfNormal(fit.kind, fit.q, c * (1.0 / 3.0),
                                       std::max(scale * 1e-5, 1e-9));
                        if (Norm(sn) > 0.5 &&
                            std::fabs(Dot(sn, m.tnorm[o])) < kGrowNormalGate) {
                            accept = false;
                        }
                    }
                }
                if (!accept)
                    continue;
                taken[it->second] = 1;
                region.push_back(o);
                frontier.push_back(o);
                if (++sinceRefit >=
                    std::max<int>(8, static_cast<int>(region.size()) / 4)) {
                    sinceRefit = 0;
                    PatchPoints(m, region, pd, 2000);
                    const Fit f = FitPatch(pd, tol, scale);
                    if (f.kind != kNone)
                        fit = f;
                }
            }
        }
        PatchPoints(m, region, pd, 4000);
        Patch pa;
        pa.tris = region;
        pa.origin = origin;
        pa.fit = FitPatch(pd, tol, scale);
        if (pa.fit.kind == kNone && static_cast<int>(region.size()) < minTris) {
            /* Too small to say anything about; it will be emitted faceted. */
        }
        out.push_back(pa);
    }
}

/* Weight on the angular half of the boundary score, as a fraction of the part's
 * diagonal per unit of (1 - |cos|). Half a degree of disagreement then weighs
 * about as much as tolerance-sized distance does on a typical part. */
const double kBoundaryAngleWeight = 0.5;

/* Moves boundary triangles to whichever fitted surface actually describes them.
 *
 * Greedy growth leaves its seams in roughly the right place, not exactly. The
 * case that matters is a blend leaving a flat face: the first facet of the
 * blend is tangent, so it is within tolerance of the PLANE too and whichever
 * region got there first keeps it. When the plane keeps it, the planar face
 * reaches a facet past the true tangency and bulges out beyond the real
 * surface — about 1.2% of the volume of a filleted block, in the case that
 * found this.
 *
 * Deciding it by fit rather than by arrival order is both cheaper and more
 * honest than trying to grow perfectly: by the time this runs, both surfaces
 * exist and the triangle can simply be asked which one it is on. Distance
 * alone cannot answer at a tangency — both are zero there — so the direction
 * the surface goes has to carry the decision, which is why the score mixes the
 * two. */
void RefineBoundaries(const Mesh &m, std::vector<Patch> &patches, double tol,
                      double scale, int passes)
{
    const int n = static_cast<int>(patches.size());
    if (n < 2)
        return;
    const double h = std::max(scale * 1e-5, 1e-9);
    PatchData pd;

    /* How badly patch `pi` describes triangle `t`. Length units throughout, so
     * the two halves are comparable: the angular term is scaled by the part
     * size to become a distance. */
    auto score = [&](int pi, int t) -> double {
        const Fit &f = patches[pi].fit;
        if (f.kind == kNone)
            return 1e300;
        double worst = 0;
        V3 c;
        for (int k = 0; k < 3; ++k) {
            const V3 &p = m.pos[m.tri[t * 3 + k]];
            c += p;
            worst = std::max(worst, std::fabs(SurfDist(f.kind, f.q, p)));
        }
        const V3 sn = SurfNormal(f.kind, f.q, c * (1.0 / 3.0), h);
        const double agree =
            (Norm(sn) > 0.5) ? std::fabs(Dot(sn, m.tnorm[t])) : 0.0;
        return worst + scale * kBoundaryAngleWeight * (1.0 - agree);
    };

    for (int pass = 0; pass < passes; ++pass) {
        std::vector<int> patchOf(m.triCount(), -1);
        for (int i = 0; i < n; ++i) {
            for (int t : patches[i].tris)
                patchOf[t] = i;
        }
        std::vector<std::pair<int, int>> moves; /* (triangle, new patch) */
        std::vector<int> sizes(n);
        for (int i = 0; i < n; ++i)
            sizes[i] = static_cast<int>(patches[i].tris.size());

        for (int t = 0; t < m.triCount(); ++t) {
            const int own = patchOf[t];
            if (own < 0 || patches[own].fit.kind == kNone)
                continue;
            double mine = score(own, t);
            int bestP = -1;
            double best = mine;
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0)
                    continue;
                const int q = patchOf[o];
                if (q < 0 || q == own)
                    continue;
                /* Only ever move within one smooth patch, for the same reason
                 * MergeRegions does: a sharp edge is a real boundary and no
                 * amount of good fit on the far side changes that. */
                if (patches[q].origin < 0 ||
                    patches[q].origin != patches[own].origin) {
                    continue;
                }
                const double sc = score(q, t);
                if (sc < best) {
                    best = sc;
                    bestP = q;
                }
            }
            /* A clear win only, and never the last triangle of a patch. */
            if (bestP >= 0 && best < mine * 0.5 && sizes[own] > 1) {
                moves.emplace_back(t, bestP);
                sizes[own]--;
                sizes[bestP]++;
            }
        }
        if (moves.empty())
            return;

        for (const std::pair<int, int> &mv : moves)
            patchOf[mv.first] = mv.second;
        std::vector<std::vector<int>> rebuilt(n);
        for (int t = 0; t < m.triCount(); ++t) {
            if (patchOf[t] >= 0)
                rebuilt[patchOf[t]].push_back(t);
        }
        for (int i = 0; i < n; ++i) {
            if (rebuilt[i].size() == patches[i].tris.size())
                continue;
            patches[i].tris.swap(rebuilt[i]);
            if (patches[i].tris.empty())
                continue;
            PatchPoints(m, patches[i].tris, pd, 4000);
            const Fit f = FitPatch(pd, tol, scale);
            if (f.kind != kNone)
                patches[i].fit = f;
        }
        std::vector<Patch> keep;
        keep.reserve(patches.size());
        for (Patch &pa : patches) {
            if (!pa.tris.empty())
                keep.push_back(std::move(pa));
        }
        patches.swap(keep);
        if (static_cast<int>(patches.size()) != n)
            return; /* sizes moved; stop */
    }
}

/* How well a merged surface's normals must follow the mesh's before two
 * patches are put together: about 8 degrees of mean slack, against the 25 the
 * first-pass classifier allows. */
const double kMergeNormalGate = 0.99;

/* Merges neighbouring patches that turn out to share one surface.
 *
 * The repair pass for greedy growth, and the thing that finally recovers a
 * fillet. Growing from a seed cannot see a tangent seam, so a 3 mm blend comes
 * out as three or four planar slivers, each of which honestly fits a plane over
 * its own two facets. Fitting the UNION of two of them finds the cylinder they
 * were always part of, and one merge makes the next one easier. Sweeping
 * smallest-first means slivers get absorbed into real surfaces rather than real
 * surfaces into each other.
 *
 * The tolerance gate is what keeps this safe: a merge only happens when ONE
 * primitive describes both patches to within the same tolerance every other
 * stage uses, so two perpendicular faces of a box are never candidates. */
void MergeRegions(const Mesh &m, std::vector<Patch> &patches, double tol,
                  double scale, int maxPasses)
{
    PatchData pd;
    for (int pass = 0; pass < maxPasses; ++pass) {
        const int n = static_cast<int>(patches.size());
        if (n < 2)
            return;
        std::vector<int> patchOf(m.triCount(), -1);
        for (int i = 0; i < n; ++i) {
            for (int t : patches[i].tris)
                patchOf[t] = i;
        }
        /* Which patches touch which. */
        std::vector<std::pair<int, int>> pairs;
        {
            std::vector<long long> seen;
            seen.reserve(m.tri.size());
            for (int t = 0; t < m.triCount(); ++t) {
                const int a = patchOf[t];
                if (a < 0)
                    continue;
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    const int b = patchOf[o];
                    if (b < 0 || b == a)
                        continue;
                    seen.push_back(static_cast<long long>(std::min(a, b)) * n +
                                   std::max(a, b));
                }
            }
            std::sort(seen.begin(), seen.end());
            seen.erase(std::unique(seen.begin(), seen.end()), seen.end());
            pairs.reserve(seen.size());
            for (long long k : seen) {
                pairs.emplace_back(static_cast<int>(k / n),
                                   static_cast<int>(k % n));
            }
        }
        if (pairs.empty())
            return;
        /* Smallest first. */
        std::sort(
            pairs.begin(), pairs.end(),
            [&](const std::pair<int, int> &x, const std::pair<int, int> &y) {
                const size_t sx = std::min(patches[x.first].tris.size(),
                                           patches[x.second].tris.size());
                const size_t sy = std::min(patches[y.first].tris.size(),
                                           patches[y.second].tris.size());
                return sx < sy;
            });

        std::vector<int> mergedInto(n, -1);
        std::vector<char> touched(n, 0);
        bool changed = false;
        std::vector<int> uni;
        for (const std::pair<int, int> &pr : pairs) {
            const int a = pr.first, b = pr.second;
            if (touched[a] || touched[b])
                continue;
            if (mergedInto[a] >= 0 || mergedInto[b] >= 0)
                continue;
            /* Only ever reunite what one smooth patch was cut into.
             *
             * Without this the pass is not a repair, it is a demolition. A
             * box's eight corners lie EXACTLY on their circumsphere, so a
             * sphere fits six merged faces with zero residual and normals that
             * agree to within six degrees — and the box becomes a ball. A
             * cylinder's cap and barrel go the same way. A sharp edge is a
             * feature boundary and nothing on the far side of one belongs to
             * this surface, however well it fits. */
            if (patches[a].origin < 0 ||
                patches[a].origin != patches[b].origin) {
                continue;
            }
            uni.clear();
            uni.reserve(patches[a].tris.size() + patches[b].tris.size());
            uni.insert(uni.end(), patches[a].tris.begin(),
                       patches[a].tris.end());
            uni.insert(uni.end(), patches[b].tris.begin(),
                       patches[b].tris.end());
            PatchPoints(m, uni, pd, 4000);
            const Fit f = FitPatch(pd, tol, scale);
            if (f.kind == kNone || f.rms > tol)
                continue;
            /* Merging is never obligatory, so it should only happen on strong
             * evidence. The residual alone is not strong: a side face and the
             * first facets of the blend leaving it are fitted to within
             * tolerance by a sphere the size of a small planet, and merging on
             * that turns four flat faces and four fillets into four spheres.
             * Demanding that the merged surface also POINT the way the mesh
             * does, and much more strictly than the first-pass classifier
             * does, is what tells a real shared surface from a coincidence. */
            if (f.agree < kMergeNormalGate)
                continue;
            patches[a].tris.swap(uni);
            patches[a].fit = f;
            patches[a].origin = patches[b].origin;
            patches[b].tris.clear();
            mergedInto[b] = a;
            touched[a] = touched[b] = 1;
            changed = true;
        }
        /* Drop the emptied patches. */
        std::vector<Patch> keep;
        keep.reserve(patches.size());
        for (Patch &p : patches) {
            if (!p.tris.empty())
                keep.push_back(std::move(p));
        }
        patches.swap(keep);
        if (!changed)
            return;
    }
}

/* ====================================================================== */
/* Regularisation — where "design intent" comes from                      */
/* ====================================================================== */

/* Snaps `d` to the nearest global axis, or to an already-agreed direction,
 * when it is within `cosTol` of one. Returns true when it moved. */
bool SnapDirection(V3 &d, const std::vector<V3> &agreed, double cosTol)
{
    const V3 globals[3] = {V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1)};
    for (int i = 0; i < 3; ++i) {
        const double c = Dot(d, globals[i]);
        if (std::fabs(c) >= cosTol) {
            d = c >= 0 ? globals[i] : globals[i] * -1.0;
            return true;
        }
    }
    for (const V3 &a : agreed) {
        const double c = Dot(d, a);
        if (std::fabs(c) >= cosTol) {
            d = c >= 0 ? a : a * -1.0;
            return true;
        }
    }
    return false;
}

/* Makes the fitted surfaces agree with each other.
 *
 * A fit is an independent estimate per patch, so a part whose faces are
 * genuinely parallel comes back with twelve normals a tenth of a degree apart
 * and eight cylinders of radius 5.0013, 4.9987, 5.0004. Every downstream
 * operation — a boolean, a fillet, a STEP export someone opens in Inventor —
 * is worse for that. This pass is what makes the output look like a part
 * somebody modelled rather than a part somebody measured. */
void Regularise(std::vector<Patch> &patches, const Mesh &m, const Params &prm,
                double tol, double scale)
{
    if (!(prm.snap_deg > 0))
        return;
    const double cosTol = std::cos(prm.snap_deg * M_PI / 180.0);

    /* Pass 1 — directions. Largest patches first, so the big faces set the
     * convention and the small ones follow it rather than the reverse. */
    std::vector<int> order;
    for (size_t i = 0; i < patches.size(); ++i) {
        if (patches[i].fit.kind != kNone)
            order.push_back(static_cast<int>(i));
    }
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return patches[a].tris.size() > patches[b].tris.size();
    });

    std::vector<V3> agreed;
    PatchData pd;
    for (int i : order) {
        Fit &f = patches[i].fit;
        const int dirOff =
            (f.kind == kPlane)                                             ? 0
            : (f.kind == kCylinder || f.kind == kCone || f.kind == kTorus) ? 3
                                                                           : -1;
        if (dirOff < 0)
            continue;
        V3 d = Unit(V3(f.q[dirOff], f.q[dirOff + 1], f.q[dirOff + 2]));
        const V3 before = d;
        if (!SnapDirection(d, agreed, cosTol)) {
            agreed.push_back(d);
            continue;
        }
        f.q[dirOff] = d.x;
        f.q[dirOff + 1] = d.y;
        f.q[dirOff + 2] = d.z;
        /* Re-settle everything else around the snapped direction, then keep it
         * only if the fit is still inside tolerance. Snapping a direction must
         * never make the surface stop describing the mesh. */
        PatchPoints(m, patches[i].tris, pd, 4000);
        bool freeMask[8];
        for (int k = 0; k < 8; ++k)
            freeMask[k] = true;
        freeMask[dirOff] = freeMask[dirOff + 1] = freeMask[dirOff + 2] = false;
        double q2[8];
        std::memcpy(q2, f.q, sizeof(q2));
        RefineFit(f.kind, q2, pd.pts, scale, freeMask);
        const double rms = FitRms(f.kind, q2, pd.pts);
        if (rms <= std::max(tol, f.rms * 1.5)) {
            std::memcpy(f.q, q2, sizeof(q2));
            f.rms = rms;
        } else {
            f.q[dirOff] = before.x;
            f.q[dirOff + 1] = before.y;
            f.q[dirOff + 2] = before.z;
        }
    }

    /* Pass 2 — radii. Cylinders sharing an axis direction and a radius within
     * tolerance are one hole drilled several times; give them one number. */
    if (!(prm.snap_radius_frac > 0))
        return;
    const double rTol = scale * prm.snap_radius_frac;
    std::vector<int> cyl;
    for (size_t i = 0; i < patches.size(); ++i) {
        if (patches[i].fit.kind == kCylinder)
            cyl.push_back(static_cast<int>(i));
    }
    std::vector<char> done(cyl.size(), 0);
    for (size_t a = 0; a < cyl.size(); ++a) {
        if (done[a])
            continue;
        std::vector<int> group(1, cyl[a]);
        done[a] = 1;
        const V3 axA =
            Unit(V3(patches[cyl[a]].fit.q[3], patches[cyl[a]].fit.q[4],
                    patches[cyl[a]].fit.q[5]));
        for (size_t b = a + 1; b < cyl.size(); ++b) {
            if (done[b])
                continue;
            const Fit &fb = patches[cyl[b]].fit;
            const V3 axB = Unit(V3(fb.q[3], fb.q[4], fb.q[5]));
            if (std::fabs(Dot(axA, axB)) < cosTol)
                continue;
            if (std::fabs(fb.q[6] - patches[cyl[a]].fit.q[6]) > rTol)
                continue;
            group.push_back(cyl[b]);
            done[b] = 1;
        }
        if (group.size() < 2)
            continue;
        /* Weight by patch size: the radius the biggest surface measured is the
         * one with the most evidence behind it. */
        double num = 0, den = 0;
        for (int g : group) {
            const double w = static_cast<double>(patches[g].tris.size());
            num += patches[g].fit.q[6] * w;
            den += w;
        }
        const double r = num / den;
        for (int g : group) {
            Fit &f = patches[g].fit;
            const double saved = f.q[6];
            f.q[6] = r;
            PatchPoints(m, patches[g].tris, pd, 4000);
            bool freeMask[8] = {true,  true,  true,  false,
                                false, false, false, true};
            double q2[8];
            std::memcpy(q2, f.q, sizeof(q2));
            RefineFit(f.kind, q2, pd.pts, scale, freeMask);
            const double rms = FitRms(f.kind, q2, pd.pts);
            if (rms <= std::max(tol, f.rms * 1.5)) {
                std::memcpy(f.q, q2, sizeof(q2));
                f.rms = rms;
            } else {
                f.q[6] = saved;
            }
        }
    }
}

/* ====================================================================== */
/* B-Rep construction                                                     */
/* ====================================================================== */

/* The fitted parameters as a real OCCT surface. Null when the parameters are
 * degenerate — a cone of zero angle, a torus whose tube swallows its hole —
 * which the caller treats as "this patch is freeform after all". */
Handle(Geom_Surface) MakeSurface(const Fit &f)
{
    try {
        switch (f.kind) {
        case kPlane: {
            const V3 n(f.q[0], f.q[1], f.q[2]);
            return new Geom_Plane(gp_Pln(P(n * f.q[3]), D(n)));
        }
        case kSphere: {
            if (!(f.q[3] > 0))
                return nullptr;
            return new Geom_SphericalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]), gp_Dir(0, 0, 1)),
                f.q[3]);
        }
        case kCylinder: {
            if (!(f.q[6] > 0))
                return nullptr;
            return new Geom_CylindricalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]),
                       gp_Dir(f.q[3], f.q[4], f.q[5])),
                f.q[6]);
        }
        case kCone: {
            /* OCCT wants the half-angle strictly inside (0, pi/2). */
            if (!(f.q[6] > 1e-4) || f.q[6] > M_PI / 2 - 1e-4)
                return nullptr;
            return new Geom_ConicalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]),
                       gp_Dir(f.q[3], f.q[4], f.q[5])),
                f.q[6], 0.0);
        }
        case kTorus: {
            if (!(f.q[6] > 0) || !(f.q[7] > 0) || f.q[7] >= f.q[6])
                return nullptr;
            return new Geom_ToroidalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]),
                       gp_Dir(f.q[3], f.q[4], f.q[5])),
                f.q[6], f.q[7]);
        }
        default:
            return nullptr;
        }
    } catch (const Standard_Failure &) {
        return nullptr;
    }
}

/* One run of boundary edges of a patch that all face the SAME neighbouring
 * patch. This is the unit an edge gets built from: a whole circular rim
 * between a barrel and its cap is one chain and becomes one exact circle,
 * where per-mesh-edge construction would have made two hundred segments. */
struct Chain
{
    std::vector<int> verts; /* in order; front()==back() when closed */
    int other = -1;         /* neighbouring patch, or -1 at a free boundary */
    bool closed = false;
};

/* Walks a patch's boundary into oriented loops, then cuts each loop into
 * chains at the points where the neighbouring patch changes. */
void PatchChains(const Mesh &m, const std::vector<int> &tris,
                 const std::vector<int> &patchOf, int self,
                 std::vector<std::vector<Chain>> &loops)
{
    /* Directed boundary edges, in the winding of the owning triangle, so the
     * loop already runs anticlockwise about the patch's own normal. */
    struct BE
    {
        int b;
        int other;
    };
    std::unordered_map<int, std::vector<BE>> outgoing;
    size_t total = 0;
    for (int t : tris) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            const int op = (o < 0) ? -1 : patchOf[o];
            if (op == self)
                continue;
            const int a = m.tri[t * 3 + k], b = m.tri[t * 3 + (k + 1) % 3];
            BE e;
            e.b = b;
            e.other = op;
            outgoing[a].push_back(e);
            total++;
        }
    }
    if (total == 0)
        return;

    std::unordered_map<int, size_t> cursor;
    size_t consumed = 0;
    while (consumed < total) {
        /* Start at any vertex with an unused outgoing edge. */
        int start = -1;
        for (auto &e : outgoing) {
            if (cursor[e.first] < e.second.size()) {
                start = e.first;
                break;
            }
        }
        if (start < 0)
            break;

        std::vector<int> loopVerts;
        std::vector<int> loopOther;
        int v = start;
        while (true) {
            auto it = outgoing.find(v);
            if (it == outgoing.end())
                break;
            size_t &c = cursor[v];
            if (c >= it->second.size())
                break;
            const BE e = it->second[c++];
            consumed++;
            loopVerts.push_back(v);
            loopOther.push_back(e.other);
            v = e.b;
            if (v == start)
                break;
        }
        if (loopVerts.size() < 2)
            continue;
        const bool closedLoop = (v == start);

        /* Cut into chains where `other` changes. Rotate a closed loop so it
         * starts at a change, or the first and last chain would be two halves
         * of the same one. */
        const size_t n = loopVerts.size();
        size_t begin = 0;
        if (closedLoop) {
            size_t k = 0;
            for (; k < n; ++k) {
                if (loopOther[k] != loopOther[(k + n - 1) % n])
                    break;
            }
            begin =
                (k == n) ? 0 : k; /* k==n: one neighbour all the way round */
        }
        std::vector<Chain> chains;
        Chain cur;
        cur.other = loopOther[begin];
        cur.verts.push_back(loopVerts[begin]);
        for (size_t i = 1; i <= n; ++i) {
            const size_t idx = closedLoop ? (begin + i) % n : begin + i;
            if (!closedLoop && idx >= n) {
                cur.verts.push_back(v); /* the open loop's final vertex */
                break;
            }
            const int nextOther = closedLoop ? loopOther[idx] : loopOther[idx];
            const int vertex = closedLoop ? loopVerts[idx] : loopVerts[idx];
            cur.verts.push_back(vertex);
            if (i == n)
                break;
            if (nextOther != cur.other) {
                chains.push_back(cur);
                cur = Chain();
                cur.other = nextOther;
                cur.verts.push_back(vertex);
            }
        }
        /* The i == n step above already appended loopVerts[begin], which is
         * what closes the loop; appending it a second time here left every
         * final chain one vertex longer than the same chain seen from the
         * neighbouring patch, so the two never agreed on a key and the shared
         * edge was built twice. */
        if (closedLoop && chains.empty())
            cur.closed = true;
        if (cur.verts.size() >= 2)
            chains.push_back(cur);
        if (!chains.empty())
            loops.push_back(chains);
    }
}

/* An edge built once and used by both faces that meet along it.
 *
 * Sharing the TopoDS_Edge is not an optimisation — it is what makes the shell
 * sew. Two faces holding geometrically-equal but distinct edges sew only by
 * tolerance, and on a model with ten thousand of them, some pair fails. */
struct EdgeKey
{
    int p1, p2, v1, v2, vm;
    bool operator<(const EdgeKey &o) const
    {
        if (p1 != o.p1)
            return p1 < o.p1;
        if (p2 != o.p2)
            return p2 < o.p2;
        if (v1 != o.v1)
            return v1 < o.v1;
        if (v2 != o.v2)
            return v2 < o.v2;
        return vm < o.vm;
    }
};

/* A name for a chain that BOTH patches sharing it will arrive at.
 *
 * This has to be independent of which way the chain is walked and of where the
 * walk started, because the two patches either side of a boundary traverse it
 * in opposite directions, and a closed rim may not even begin at the same
 * vertex. Keying on the endpoints and a midpoint — the obvious first try —
 * satisfies none of that: for a two-vertex chain the "midpoint" is the far END,
 * so the key flipped with the direction, every shared edge was built twice, and
 * the two copies then had to be reconciled by sewing tolerance. Boxes survived
 * that. Filleted parts did not.
 *
 * The vertex SET of a chain is the same from both sides however it is walked,
 * so its extremes and its length name it canonically. */
EdgeKey KeyFor(const Chain &c, int self)
{
    EdgeKey k;
    k.p1 = std::min(self, c.other);
    k.p2 = std::max(self, c.other);
    int lo = c.verts[0], hi = c.verts[0];
    for (int v : c.verts) {
        lo = std::min(lo, v);
        hi = std::max(hi, v);
    }
    k.v1 = lo;
    k.v2 = hi;
    /* Length separates two chains that join the same patches over overlapping
     * vertex ranges — a rim cut in half is the case that needs it. */
    k.vm = static_cast<int>(c.verts.size());
    return k;
}

struct BuildCtx
{
    const Mesh *m = nullptr;
    double tol = 0;
    double scale = 0;
    std::map<EdgeKey, TopoDS_Edge> edges;
    std::unordered_map<int, TopoDS_Vertex> verts;
    int analytic = 0, approximated = 0;
};

TopoDS_Vertex VertexAt(BuildCtx &ctx, int v)
{
    auto it = ctx.verts.find(v);
    if (it != ctx.verts.end())
        return it->second;
    const TopoDS_Vertex tv = BRepBuilderAPI_MakeVertex(P((*ctx.m).pos[v]));
    ctx.verts.emplace(v, tv);
    return tv;
}

/* The exact intersection curve of two analytic surfaces, when there is one
 * that follows this chain. Null otherwise.
 *
 * This is the whole quality argument for the prismatic path: a hole's rim
 * comes out a real gp_Circ, so a fillet on it later has a circle to roll along
 * and a STEP export carries a circle rather than a 200-segment spline. */
Handle(Geom_Curve) IntersectionCurve(const Handle(Geom_Surface) & s1,
                                     const Handle(Geom_Surface) & s2,
                                     const std::vector<gp_Pnt> &pts, double tol)
{
    if (s1.IsNull() || s2.IsNull())
        return nullptr;
    try {
        GeomAPI_IntSS iss(s1, s2, tol * 0.1);
        if (!iss.IsDone() || iss.NbLines() < 1)
            return nullptr;
        Handle(Geom_Curve) best;
        double bestErr = 1e300;
        for (int i = 1; i <= iss.NbLines(); ++i) {
            Handle(Geom_Curve) c = iss.Line(i);
            if (c.IsNull())
                continue;
            /* IntSS hands back a Geom_TrimmedCurve WRAPPING the real conic,
             * and a trimmed curve reports IsClosed() and IsPeriodic() as
             * false however complete it is. Left wrapped, a cap rim never
             * takes the full-circle path and every hole in the model came out
             * as a spline through the mesh points instead of the circle it
             * actually is. Unwrap to the basis curve and the conic is itself
             * again. */
            for (int guard = 0; guard < 4; ++guard) {
                Handle(Geom_TrimmedCurve) tc =
                    Handle(Geom_TrimmedCurve)::DownCast(c);
                if (tc.IsNull())
                    break;
                c = tc->BasisCurve();
            }
            if (c.IsNull())
                continue;
            /* Score by how far the chain's own points sit from the candidate:
             * two surfaces can meet in more than one curve and only one of them
             * is the edge this chain is walking. */
            double err = 0;
            int n = 0;
            for (size_t k = 0; k < pts.size();
                 k += std::max<size_t>(1, pts.size() / 8)) {
                GeomAPI_ProjectPointOnCurve pp(pts[k], c);
                if (pp.NbPoints() < 1) {
                    err = 1e300;
                    break;
                }
                err += pp.LowerDistance();
                n++;
            }
            if (n == 0)
                continue;
            err /= n;
            if (err < bestErr) {
                bestErr = err;
                best = c;
            }
        }
        if (best.IsNull() || bestErr > tol * 3)
            return nullptr;
        return best;
    } catch (const Standard_Failure &) {
        return nullptr;
    }
}

/* Builds (or reuses) the edge for one chain. */
TopoDS_Edge ChainEdge(BuildCtx &ctx, const Chain &c, int self,
                      const Handle(Geom_Surface) & selfSurf,
                      const std::vector<Handle(Geom_Surface)> &surfs)
{
    const EdgeKey key = KeyFor(c, self);
    auto it = ctx.edges.find(key);
    if (it != ctx.edges.end())
        return it->second;

    std::vector<gp_Pnt> pts;
    pts.reserve(c.verts.size());
    for (int v : c.verts)
        pts.push_back(P(ctx.m->pos[v]));

    TopoDS_Edge e;
    const bool closed = c.verts.front() == c.verts.back();

    /* 1 — the exact curve where two analytic surfaces meet. */
    if (c.other >= 0 && c.other < static_cast<int>(surfs.size()) &&
        !selfSurf.IsNull() && !surfs[c.other].IsNull()) {
        const Handle(Geom_Curve) cur =
            IntersectionCurve(selfSurf, surfs[c.other], pts, ctx.tol);
        if (!cur.IsNull()) {
            try {
                if (closed && cur->IsClosed()) {
                    BRepBuilderAPI_MakeEdge me(cur);
                    if (me.IsDone())
                        e = me.Edge();
                } else {
                    GeomAPI_ProjectPointOnCurve p1(pts.front(), cur);
                    GeomAPI_ProjectPointOnCurve p2(pts.back(), cur);
                    if (p1.NbPoints() > 0 && p2.NbPoints() > 0) {
                        double u1 = p1.LowerDistanceParameter();
                        double u2 = p2.LowerDistanceParameter();
                        if (cur->IsPeriodic()) {
                            /* Go round the way the chain actually goes: check a
                             * midpoint rather than assuming the short arc. */
                            const double per = cur->Period();
                            GeomAPI_ProjectPointOnCurve pm(pts[pts.size() / 2],
                                                           cur);
                            if (pm.NbPoints() > 0) {
                                double um = pm.LowerDistanceParameter();
                                while (u2 < u1)
                                    u2 += per;
                                while (um < u1)
                                    um += per;
                                if (um > u2)
                                    u2 -= per; /* the other way round */
                            }
                        }
                        if (std::fabs(u2 - u1) > 1e-12) {
                            BRepBuilderAPI_MakeEdge me(
                                cur, VertexAt(ctx, c.verts.front()),
                                VertexAt(ctx, c.verts.back()), std::min(u1, u2),
                                std::max(u1, u2));
                            if (me.IsDone())
                                e = me.Edge();
                        }
                    }
                }
            } catch (const Standard_Failure &) {
                e = TopoDS_Edge();
            }
            if (!e.IsNull())
                ctx.analytic++;
        }
    }

    /* 2 — a straight edge, when the chain is one mesh edge long. */
    if (e.IsNull() && c.verts.size() == 2) {
        try {
            BRepBuilderAPI_MakeEdge me(VertexAt(ctx, c.verts.front()),
                                       VertexAt(ctx, c.verts.back()));
            if (me.IsDone()) {
                e = me.Edge();
                ctx.approximated++;
            }
        } catch (const Standard_Failure &) {
        }
    }

    /* 3 — a spline through the chain. Not exact, but continuous and compact,
     *     which a polyline of two hundred segments is not. */
    if (e.IsNull() && pts.size() >= 3) {
        try {
            const int n = static_cast<int>(pts.size()) - (closed ? 1 : 0);
            if (n >= 3) {
                TColgp_Array1OfPnt arr(1, n);
                for (int i = 0; i < n; ++i)
                    arr.SetValue(i + 1, pts[i]);
                GeomAPI_PointsToBSpline approx(arr, 3, 8, GeomAbs_C2, ctx.tol);
                Handle(Geom_BSplineCurve) bs = approx.Curve();
                if (!bs.IsNull()) {
                    if (closed)
                        bs->SetPeriodic();
                    BRepBuilderAPI_MakeEdge me(bs);
                    if (me.IsDone()) {
                        e = me.Edge();
                        ctx.approximated++;
                    }
                }
            }
        } catch (const Standard_Failure &) {
            e = TopoDS_Edge();
        }
    }

    /* 4 — a polyline. Always available, never pretty. */
    if (e.IsNull() && pts.size() >= 2) {
        try {
            BRepBuilderAPI_MakeEdge me(VertexAt(ctx, c.verts.front()),
                                       VertexAt(ctx, c.verts.back()));
            if (me.IsDone()) {
                e = me.Edge();
                ctx.approximated++;
            }
        } catch (const Standard_Failure &) {
        }
    }

    if (!e.IsNull())
        ctx.edges.emplace(key, e);
    return e;
}

/* Every triangle of a patch as its own planar face — the honest fallback when
 * the patch fitted nothing, or when the analytic face refused to build. */
void EmitFaceted(const Mesh &m, const std::vector<int> &tris,
                 std::vector<TopoDS_Face> &out)
{
    for (int t : tris) {
        try {
            BRepBuilderAPI_MakePolygon poly(
                P(m.pos[m.tri[t * 3]]), P(m.pos[m.tri[t * 3 + 1]]),
                P(m.pos[m.tri[t * 3 + 2]]), Standard_True);
            if (!poly.IsDone())
                continue;
            BRepBuilderAPI_MakeFace mf(poly.Wire(), Standard_True);
            if (mf.IsDone())
                out.push_back(mf.Face());
        } catch (const Standard_Failure &) {
        }
    }
}

/* Turns the face the way the mesh faces.
 *
 * A face built on a fitted surface has whatever normal the fit happened to
 * produce, and half of them come out pointing into the material. Sewing does
 * not care; every boolean and every fillet afterwards does. */
void OrientFaceLikeMesh(TopoDS_Face &face, const Handle(Geom_Surface) & surf,
                        const Mesh &m, const std::vector<int> &tris)
{
    double area = 0;
    V3 meshN;
    for (int t : tris) {
        meshN += m.tnorm[t] * m.tarea[t];
        area += m.tarea[t];
    }
    if (!(area > 0))
        return;
    meshN = Unit(meshN);
    try {
        GProp_GProps gp;
        BRepGProp::SurfaceProperties(face, gp);
        GeomAPI_ProjectPointOnSurf proj(gp.CentreOfMass(), surf);
        if (proj.NbPoints() < 1)
            return;
        Standard_Real u, v;
        proj.LowerDistanceParameters(u, v);
        gp_Pnt sp;
        gp_Vec du, dv;
        surf->D1(u, v, sp, du, dv);
        const gp_Vec sn = du.Crossed(dv);
        if (sn.Magnitude() <= 1e-12)
            return;
        const V3 nn = Unit(V3(sn.X(), sn.Y(), sn.Z()));
        const bool reversed = (face.Orientation() == TopAbs_REVERSED);
        if (Dot(nn, meshN) * (reversed ? -1.0 : 1.0) < 0)
            face.Reverse();
    } catch (const Standard_Failure &) {
    }
}

/* Where the patch sits in the surface's own (u,v) parameters. */
struct UvExtent
{
    double u1 = 0, u2 = 0, v1 = 0, v2 = 0;
    bool uFull = false, vFull = false;
    bool ok = false;
};

UvExtent MeasureUv(const Mesh &m, const std::vector<int> &tris,
                   const Handle(Geom_Surface) & surf)
{
    UvExtent e;
    Standard_Real nu1, nu2, nv1, nv2;
    surf->Bounds(nu1, nu2, nv1, nv2);
    const bool uPer = surf->IsUPeriodic() != Standard_False;
    const bool vPer = surf->IsVPeriodic() != Standard_False;

    /* Sampling rather than projecting every vertex: projection onto an
     * analytic surface is not cheap and the extent of a patch is not a
     * quantity that needs a million witnesses. */
    std::vector<int> vids;
    const size_t step = std::max<size_t>(1, tris.size() / 400);
    for (size_t i = 0; i < tris.size(); i += step) {
        for (int k = 0; k < 3; ++k)
            vids.push_back(m.tri[tris[i] * 3 + k]);
    }
    std::vector<double> us, vs;
    us.reserve(vids.size());
    vs.reserve(vids.size());
    try {
        for (int v : vids) {
            GeomAPI_ProjectPointOnSurf proj(P(m.pos[v]), surf);
            if (proj.NbPoints() < 1)
                continue;
            Standard_Real u, w;
            proj.LowerDistanceParameters(u, w);
            us.push_back(u);
            vs.push_back(w);
        }
    } catch (const Standard_Failure &) {
        return e;
    }
    if (us.size() < 3)
        return e;

    /* A periodic direction is "full" when the samples leave no wide gap
     * anywhere around the circle. Sorting and taking the largest CYCLIC gap is
     * what distinguishes a whole barrel from a fillet's quarter of one. */
    auto span = [&](std::vector<double> &t, bool periodic, double lo, double hi,
                    double &a, double &b, bool &full) {
        std::sort(t.begin(), t.end());
        if (!periodic) {
            a = t.front();
            b = t.back();
            full = false;
            return;
        }
        const double per = hi - lo;
        double gap = t.front() + per - t.back();
        size_t at = 0;
        for (size_t i = 1; i < t.size(); ++i) {
            const double g = t[i] - t[i - 1];
            if (g > gap) {
                gap = g;
                at = i;
            }
        }
        if (gap < per * 0.15) {
            a = lo;
            b = hi;
            full = true;
            return;
        }
        full = false;
        if (at == 0) {
            a = t.front();
            b = t.back();
        } else {
            a = t[at];
            b = t[at - 1] + per;
        }
    };
    span(us, uPer, nu1, nu2, e.u1, e.u2, e.uFull);
    span(vs, vPer, nv1, nv2, e.v1, e.v2, e.vFull);
    if (!(e.u2 > e.u1) || !(e.v2 > e.v1))
        return e;
    e.ok = true;
    return e;
}

/* Builds the face straight from parameter bounds.
 *
 * The path for a patch that wraps the whole way round a periodic surface — a
 * cylinder's barrel, a hole, a cone, a whole sphere. Such a patch has NO seam
 * in the mesh (it is a closed tube), so there is no boundary chain to build a
 * wire from and the wire path cannot work at all. Asking the surface for its
 * own parametric rectangle gives the seam for free, which is exactly what the
 * B-Rep needs and the mesh never had. */
bool BuildParametricFace(BuildCtx &ctx, const Mesh &m, const Patch &patch,
                         const Handle(Geom_Surface) & surf,
                         std::vector<TopoDS_Face> &out)
{
    try {
        const UvExtent e = MeasureUv(m, patch.tris, surf);
        TopoDS_Face face;
        if (!e.ok) {
            BRepBuilderAPI_MakeFace mf(surf, ctx.tol);
            if (!mf.IsDone()) {
                MR_TRACE("      param: natural bounds failed\n");
                return false;
            }
            face = mf.Face();
        } else {
            BRepBuilderAPI_MakeFace mf(surf, e.u1, e.u2, e.v1, e.v2, ctx.tol);
            if (!mf.IsDone()) {
                MR_TRACE(
                    "      param: bounds u[%.3f %.3f] v[%.3f %.3f] failed\n",
                    e.u1, e.u2, e.v1, e.v2);
                return false;
            }
            face = mf.Face();
        }
        if (face.IsNull())
            return false;
        OrientFaceLikeMesh(face, surf, m, patch.tris);
        out.push_back(face);
        return true;
    } catch (const Standard_Failure &f) {
        MR_TRACE("      param: exception %s\n",
                 f.GetMessageString() ? f.GetMessageString() : "(none)");
        return false;
    }
}

/* Builds one analytic face. Returns false when the patch has to go faceted. */
bool BuildAnalyticFace(BuildCtx &ctx, const Mesh &m, const Patch &patch,
                       int self, const std::vector<int> &patchOf,
                       const std::vector<Handle(Geom_Surface)> &surfs,
                       std::vector<TopoDS_Face> &out)
{
    const Handle(Geom_Surface) &surf = surfs[self];
    if (surf.IsNull())
        return false;

    std::vector<std::vector<Chain>> loops;
    PatchChains(m, patch.tris, patchOf, self, loops);
    MR_TRACE("      face %d: kind=%s loops=%d tris=%d\n", self,
             KindName(patch.fit.kind), (int)loops.size(),
             (int)patch.tris.size());

    /* No boundary at all means a closed surface the mesh wrapped completely —
      * a whole sphere, a whole torus. Only the parametric path has it. */
    if (loops.empty())
        return BuildParametricFace(ctx, m, patch, surf, out);

    /* Every boundary run closed, and the patch goes the whole way round: also
     * seamless, also parametric. A barrel between two caps is this case. */
    bool allClosed = true;
    for (const std::vector<Chain> &chains : loops) {
        if (chains.size() != 1 ||
            chains[0].verts.front() != chains[0].verts.back()) {
            allClosed = false;
            break;
        }
    }
    if (allClosed && (surf->IsUPeriodic() || surf->IsVPeriodic())) {
        const UvExtent e = MeasureUv(m, patch.tris, surf);
        if (e.ok && (e.uFull || e.vFull)) {
            if (BuildParametricFace(ctx, m, patch, surf, out))
                return true;
        }
    }

    std::vector<TopoDS_Wire> wires;
    for (const std::vector<Chain> &chains : loops) {
        BRepBuilderAPI_MakeWire mw;
        bool ok = true;
        for (const Chain &c : chains) {
            const TopoDS_Edge e = ChainEdge(ctx, c, self, surf, surfs);
            if (e.IsNull()) {
                ok = false;
                break;
            }
            try {
                mw.Add(e);
            } catch (const Standard_Failure &) {
                ok = false;
                break;
            }
            if (!mw.IsDone()) {
                ok = false;
                break;
            }
        }
        if (!ok || !mw.IsDone()) {
            MR_TRACE("      face %d: wire of %d chains failed\n", self,
                     (int)chains.size());
            return false;
        }
        wires.push_back(mw.Wire());
    }
    if (wires.empty())
        return false;

    try {
        /* Largest wire first: BRepBuilderAPI_MakeFace takes the first as the
         * outer boundary and the rest as holes. */
        std::sort(wires.begin(), wires.end(),
                  [](const TopoDS_Wire &a, const TopoDS_Wire &b) {
                      GProp_GProps ga, gb;
                      BRepGProp::LinearProperties(a, ga);
                      BRepGProp::LinearProperties(b, gb);
                      return ga.Mass() > gb.Mass();
                  });
        BRepBuilderAPI_MakeFace mf(surf, wires[0], Standard_False);
        if (!mf.IsDone()) {
            MR_TRACE("      face %d: MakeFace(outer of %d wires) failed\n",
                     self, (int)wires.size());
            return false;
        }
        TopoDS_Face face = mf.Face();
        /* Inner wires go on TOPOLOGICALLY, not through MakeFace::Add.
         *
         * MakeFace::Add classifies each new wire as outer or inner, and to do
         * that it needs the wire's bounding box in the surface's PARAMETERS —
         * which these edges do not have yet, because they were built from 3D
         * intersection curves. Asked anyway, OCCT raises "Bnd_Box is void", and
         * on this pipeline that meant the two faces that carry every hole in a
         * drilled plate fell back to triangles: eighteen surfaces recovered
         * perfectly and the part still arrived as 281 faces.
         *
         * ShapeFix_Face below builds the pcurves and then sorts outer from
          * inner itself, which is the order these two steps must go in. */
        {
            BRep_Builder bb;
            for (size_t i = 1; i < wires.size(); ++i)
                bb.Add(face, wires[i]);
        }

        /* The wires were built from 3D curves; the face needs pcurves on the
         * surface and a consistent outer/inner orientation before it is worth
         * sewing. ShapeFix does both, and is the reason this pipeline can hand
         * OCCT approximate input at all. */
        BRepLib::BuildCurves3d(face);
        Handle(ShapeFix_Face) fix = new ShapeFix_Face(face);
        fix->SetPrecision(ctx.tol);
        fix->SetMaxTolerance(ctx.tol * 100);
        fix->FixAddNaturalBoundMode() = Standard_False;
        fix->Perform();
        fix->FixOrientation();
        face = fix->Face();
        if (face.IsNull()) {
            MR_TRACE("      face %d: ShapeFix returned null\n", self);
            return false;
        }

        OrientFaceLikeMesh(face, surf, m, patch.tris);
        out.push_back(face);
        return true;
    } catch (const Standard_Failure &f) {
        MR_TRACE("      face %d: exception %s\n", self,
                 f.GetMessageString() ? f.GetMessageString() : "(none)");
        return false;
    }
}

} // namespace

/* ====================================================================== */
/* The pipeline                                                           */
/* ====================================================================== */

namespace {

/* Sews faces into a shell, heals it, and closes it into a solid if it can.
 *
 * "If it can" is deliberate. A downloaded mesh with a hole in it cannot become
 * a solid, and returning the open shell — which the app can still display,
 * still section, still export — beats returning nothing. */
TopoDS_Shape SewAndSolidify(const std::vector<TopoDS_Face> &faces, double tol,
                            Report &rep)
{
    if (faces.empty())
        return TopoDS_Shape();
    TopoDS_Shape sewn;
    try {
        BRepBuilderAPI_Sewing sew(tol, Standard_True, Standard_True,
                                  Standard_True, Standard_False);
        for (const TopoDS_Face &f : faces)
            sew.Add(f);
        sew.Perform();
        sewn = sew.SewedShape();
    } catch (const Standard_Failure &) {
        sewn = TopoDS_Shape();
    }
    if (sewn.IsNull()) {
        BRep_Builder b;
        TopoDS_Compound c;
        b.MakeCompound(c);
        for (const TopoDS_Face &f : faces)
            b.Add(c, f);
        return c;
    }

    try {
        Handle(ShapeFix_Shape) fix = new ShapeFix_Shape(sewn);
        fix->SetPrecision(tol);
        fix->SetMaxTolerance(tol * 100);
        fix->Perform();
        if (!fix->Shape().IsNull())
            sewn = fix->Shape();
    } catch (const Standard_Failure &) {
    }

    /* Sewing a single face returns the FACE, not a shell — which is exactly
     * what a whole sphere or a whole torus arrives as. Wrap the loose faces in
     * a shell first, or the explorer below finds nothing and the caller gets an
     * empty compound for a perfectly good surface. */
    if (!TopExp_Explorer(sewn, TopAbs_SHELL).More()) {
        std::vector<TopoDS_Face> loose;
        for (TopExp_Explorer ex(sewn, TopAbs_FACE); ex.More(); ex.Next()) {
            loose.push_back(TopoDS::Face(ex.Current()));
        }
        if (!loose.empty()) {
            try {
                BRep_Builder b;
                TopoDS_Shell sh;
                b.MakeShell(sh);
                for (const TopoDS_Face &f : loose)
                    b.Add(sh, f);
                /* A face closed in both parameters closes the shell by itself;
                 * BRep_Tool cannot tell, so say so explicitly. */
                Handle(ShapeFix_Shell) fs = new ShapeFix_Shell(sh);
                fs->SetPrecision(tol);
                fs->SetMaxTolerance(tol * 100);
                fs->Perform();
                if (!fs->Shell().IsNull())
                    sh = fs->Shell();
                BRepCheck_Analyzer ana(sh);
                if (loose.size() == 1) {
                    const TopoDS_Face &f = loose[0];
                    Handle(Geom_Surface) su = BRep_Tool::Surface(f);
                    const bool sphere =
                        !Handle(Geom_SphericalSurface)::DownCast(su).IsNull();
                    if (!su.IsNull() && su->IsUClosed() &&
                        (su->IsVClosed() || sphere)) {
                        /* A sphere's V runs pole to pole and reports "not
                         * closed", but the poles are degenerate points, not a
                         * boundary: the shell really is closed. */
                        sh.Closed(Standard_True);
                    }
                } else if (ana.IsValid()) {
                    BRepTools::Update(sh);
                }
                sewn = sh;
            } catch (const Standard_Failure &) {
            }
        }
    }

    /* Every closed shell becomes a solid; open ones are left as they are. A
     * compound of one solid is unwrapped, because the app's feature tree wants
     * a body, not a bag holding one. */
    std::vector<TopoDS_Solid> solids;
    std::vector<TopoDS_Shape> open;
    for (TopExp_Explorer ex(sewn, TopAbs_SHELL); ex.More(); ex.Next()) {
        const TopoDS_Shell sh = TopoDS::Shell(ex.Current());
        rep.shells++;
        if (sh.Closed()) {
            try {
                BRepBuilderAPI_MakeSolid ms(sh);
                if (ms.IsDone()) {
                    solids.push_back(ms.Solid());
                    continue;
                }
            } catch (const Standard_Failure &) {
            }
        }
        open.push_back(sh);
    }
    rep.solids = static_cast<int>(solids.size());
    rep.closed = (!solids.empty() && open.empty()) ? 1 : 0;

    if (solids.size() == 1 && open.empty()) {
        /* Orient the solid so its volume is positive: a shell sewn from
         * inward-facing faces makes a valid solid describing the whole of
         * space minus the part, and nothing downstream survives that. */
        TopoDS_Solid s = solids[0];
        try {
            GProp_GProps g;
            BRepGProp::VolumeProperties(s, g);
            if (g.Mass() < 0)
                s.Reverse();
        } catch (const Standard_Failure &) {
        }
        return s;
    }
    if (solids.empty() && open.size() == 1)
        return open[0];

    BRep_Builder b;
    TopoDS_Compound c;
    b.MakeCompound(c);
    for (const TopoDS_Solid &s : solids)
        b.Add(c, s);
    for (const TopoDS_Shape &s : open)
        b.Add(c, s);
    return c;
}

} // namespace

TopoDS_Shape Reconstruct(const double *xyz, int nv, const int *tri, int nt,
                         const Params &prm, Report &rep, std::string &err)
{
    ClearReport(rep);
    err.clear();
    if (!xyz || !tri) {
        err = "no mesh data";
        return TopoDS_Shape();
    }

    Mesh m;
    try {
        if (!BuildMesh(xyz, nv, tri, nt, prm, m, rep)) {
            err = "the mesh has no usable triangles";
            return TopoDS_Shape();
        }
        BuildAdjacency(m, rep);
        OrientMesh(m, rep);
    } catch (const std::bad_alloc &) {
        err = "the mesh is too large to load";
        return TopoDS_Shape();
    } catch (const Standard_Failure &f) {
        err = f.GetMessageString() ? f.GetMessageString()
                                   : "mesh preparation failed";
        return TopoDS_Shape();
    } catch (const std::exception &e) {
        err = e.what() ? e.what() : "mesh preparation failed";
        return TopoDS_Shape();
    } catch (...) {
        err = "mesh preparation failed";
        return TopoDS_Shape();
    }

    const double scale = m.diagonal;
    const double tol = std::max(scale * prm.tol_frac, 1e-9);
    std::vector<TopoDS_Face> faces;

    /* ---- faceted -------------------------------------------------- */
    if (prm.mode == 0) {
        if (m.triCount() > prm.max_faceted_triangles) {
            /* One B-Rep face per triangle is linear in the mesh and quadratic
             * in the misery: a 500k-triangle download becomes a 500k-face
             * shape that takes minutes to sew and that no later operation can
             * touch. Refuse it and say why rather than hang the app. */
            char buf[192];
            std::snprintf(buf, sizeof(buf),
                          "%d triangles is too many to convert face-by-face "
                          "(limit %d) — use the surface-fitting mode",
                          m.triCount(), prm.max_faceted_triangles);
            err = buf;
            return TopoDS_Shape();
        }
        std::vector<int> all(m.triCount());
        for (int i = 0; i < m.triCount(); ++i)
            all[i] = i;
        EmitFaceted(m, all, faces);
        rep.patches = 1;
        rep.faceted_patches = 1;
        rep.faces_built = static_cast<int>(faces.size());
        TopoDS_Shape out = SewAndSolidify(faces, tol, rep);
        if (out.IsNull())
            err = "the faces would not sew into a shell";
        else {
            /* Coplanar triangles become one face — the only thing that makes a
             * faceted conversion usable at all. */
            try {
                ShapeUpgrade_UnifySameDomain uni(out, Standard_True,
                                                 Standard_True, Standard_False);
                uni.Build();
                if (!uni.Shape().IsNull())
                    out = uni.Shape();
            } catch (const Standard_Failure &) {
            }
        }
        return out;
    }

    /* ---- prismatic ------------------------------------------------ */
    std::vector<int> patchOf;
    int rawPatches = 0;
    std::vector<Patch> patches;
    try {
        SmoothPatches(m, prm.sharp_deg, patchOf, rawPatches);
        std::vector<std::vector<int>> byPatch(rawPatches);
        for (int t = 0; t < m.triCount(); ++t)
            byPatch[patchOf[t]].push_back(t);

        PatchData pd;
        for (int i = 0; i < rawPatches; ++i) {
            if (byPatch[i].empty())
                continue;
            PatchPoints(m, byPatch[i], pd, 4000);
            Patch pa;
            pa.tris = byPatch[i];
            pa.origin = i;
            pa.fit = FitPatch(pd, tol, scale);
            if (pa.fit.kind != kNone || static_cast<int>(byPatch[i].size()) <
                                            prm.min_patch_triangles * 4) {
                patches.push_back(pa);
            } else {
                /* A patch that fits nothing is usually several surfaces that
                 * meet tangentially — a fillet and the faces it blends. Growing
                 * with a running fit finds the seam no dihedral test can. */
                const size_t before = patches.size();
                SplitByFit(m, byPatch[i], tol, scale, prm.min_patch_triangles,
                           i, patches);
                if (patches.size() == before)
                    patches.push_back(pa);
            }
        }
        MergeRegions(m, patches, tol, scale, 8);
        RefineBoundaries(m, patches, tol, scale, 6);
        Regularise(patches, m, prm, tol, scale);
    } catch (const std::bad_alloc &) {
        err = "the mesh is too large to segment";
        return TopoDS_Shape();
    } catch (const Standard_Failure &f) {
        err =
            f.GetMessageString() ? f.GetMessageString() : "segmentation failed";
        return TopoDS_Shape();
    } catch (const std::exception &e) {
        err = e.what() ? e.what() : "segmentation failed";
        return TopoDS_Shape();
    } catch (...) {
        err = "segmentation failed";
        return TopoDS_Shape();
    }

    rep.patches = static_cast<int>(patches.size());

    /* patchOf has to be re-derived: SplitByFit renumbered everything. */
    patchOf.assign(m.triCount(), -1);
    for (size_t i = 0; i < patches.size(); ++i) {
        for (int t : patches[i].tris)
            patchOf[t] = static_cast<int>(i);
    }

    std::vector<Handle(Geom_Surface)> surfs(patches.size());
    double rmsNum = 0, rmsDen = 0;
    for (size_t i = 0; i < patches.size(); ++i) {
        surfs[i] = MakeSurface(patches[i].fit);
        if (surfs[i].IsNull())
            continue;
        double area = 0;
        for (int t : patches[i].tris)
            area += m.tarea[t];
        rmsNum += patches[i].fit.rms * area;
        rmsDen += area;
        switch (patches[i].fit.kind) {
        case kPlane:
            rep.planes++;
            break;
        case kCylinder:
            rep.cylinders++;
            break;
        case kCone:
            rep.cones++;
            break;
        case kSphere:
            rep.spheres++;
            break;
        case kTorus:
            rep.tori++;
            break;
        default:
            break;
        }
    }
    rep.fit_rms = rmsDen > 0 ? rmsNum / rmsDen : 0;

    BuildCtx ctx;
    ctx.m = &m;
    ctx.tol = tol;
    ctx.scale = scale;

    int facetedTriangles = 0;
    std::vector<std::vector<int>> deferred;
    for (size_t i = 0; i < patches.size(); ++i) {
        bool built = false;
        if (!surfs[i].IsNull()) {
            try {
                built =
                    BuildAnalyticFace(ctx, m, patches[i], static_cast<int>(i),
                                      patchOf, surfs, faces);
            } catch (const Standard_Failure &) {
                built = false;
            } catch (const std::exception &) {
                built = false;
            } catch (...) {
                /* One patch that will not build goes faceted. It never stops
                 * the conversion, and it must never leave this loop. */
                built = false;
            }
        }
        if (built) {
            rep.faces_built++;
        } else {
            if (!surfs[i].IsNull())
                rep.faces_failed++;
            rep.faceted_patches++;
            facetedTriangles += static_cast<int>(patches[i].tris.size());
            deferred.push_back(patches[i].tris);
        }
    }

    if (facetedTriangles > prm.max_faceted_triangles) {
        char buf[224];
        std::snprintf(buf, sizeof(buf),
                      "only %d of %d patches became surfaces; the remaining "
                      "%d triangles are too many to keep face-by-face",
                      rep.faces_built, rep.patches, facetedTriangles);
        err = buf;
        return TopoDS_Shape();
    }
    for (const std::vector<int> &tris : deferred)
        EmitFaceted(m, tris, faces);

    rep.analytic_edges = ctx.analytic;
    rep.approximated_edges = ctx.approximated;
    rep.freeform = 0;

    if (faces.empty()) {
        err = "no faces could be built from that mesh";
        return TopoDS_Shape();
    }
    TopoDS_Shape out = SewAndSolidify(faces, tol, rep);
    if (out.IsNull()) {
        err = "the faces would not sew into a shell";
        return TopoDS_Shape();
    }
    try {
        ShapeUpgrade_UnifySameDomain uni(out, Standard_True, Standard_True,
                                         Standard_False);
        uni.Build();
        if (!uni.Shape().IsNull())
            out = uni.Shape();
    } catch (const Standard_Failure &) {
    }
    return out;
}

} // namespace meshrecon
