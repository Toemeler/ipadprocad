/* M232 — mesh -> B-Rep reconstruction. See mesh_recon.h for the shape of it. */
#include "mesh_recon.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepBndLib.hxx>
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
#include <Geom_Circle.hxx>
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
#include <ShapeBuild_ReShape.hxx>
#include <ShapeFix_Edge.hxx>
#include <ShapeFix_Face.hxx>
#include <ShapeFix_Shape.hxx>
#include <ShapeFix_Shell.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TopExp.hxx>
#include <TopTools_DataMapOfShapeInteger.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
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

/* Fits a circle to points already known to be near-coplanar, in that plane.
 *
 * Algebraic (Kasa) form: |x|^2 = 2 x.c + k, which is linear in (c, k). Exact
 * for points on a circle, and these are — they are tube centres. */
bool CircleInPlane(const std::vector<V3> &s, const V3 &a, V3 &centre,
                   double &radius)
{
    if (s.size() < 3)
        return false;
    V3 u = Cross(a, V3(0, 0, 1));
    if (Norm(u) < 1e-6)
        u = Cross(a, V3(1, 0, 0));
    u = Unit(u);
    const V3 v = Unit(Cross(a, u));
    V3 o;
    Centroid(s, o);
    double A[9] = {0}, b[3] = {0};
    for (const V3 &x : s) {
        const V3 d = x - o;
        const double du = Dot(d, u), dv = Dot(d, v);
        const double row[3] = {2 * du, 2 * dv, 1};
        const double rhs = du * du + dv * dv;
        for (int i = 0; i < 3; ++i) {
            b[i] += row[i] * rhs;
            for (int j = 0; j < 3; ++j)
                A[i * 3 + j] += row[i] * row[j];
        }
    }
    if (!SolveLin(A, b, 3))
        return false;
    const double rr = b[2] + b[0] * b[0] + b[1] * b[1];
    if (!(rr > 0))
        return false;
    radius = std::sqrt(rr);
    centre = o + u * b[0] + v * b[1];
    /* Put the centre in the plane the points lie in. */
    double off = 0;
    for (const V3 &x : s)
        off += Dot(x - centre, a);
    centre = centre + a * (off / static_cast<double>(s.size()));
    return true;
}

/* Fits a torus by searching for its MINOR radius.
 *
 * The old seed paired each point's normal with one a stride away and
 * intersected the two lines. On a cylinder or a cone that recovers the axis,
 * which is why it was written that way — but on a torus a normal line does not
 * meet the axis, it meets the SPINE, the circle of tube centres. Two normals a
 * step apart along a meridian meet on the spine; two a step apart around the
 * spine meet near the axis instead, a long way off. Averaging the two kinds
 * gave a torus of major radius 16.1 and minor 16.1-not-6 where the truth was
 * 20 and 6, at a residual of 4.6 mm on a mesh with no noise in it at all. A
 * plain torus was therefore never recognised once, at any tessellation, and a
 * fillet ring — which is the only torus most parts contain — came back as
 * several hundred planes.
 *
 * The structure that IS reliable: every point of a torus lies exactly its
 * minor radius from the spine, along its own normal. So for the true r, the
 * points p - r n collapse onto a circle, and for any other r they do not.
 * That makes r a one-dimensional search with a sharp, well-behaved minimum:
 * scan it, take the sign of n that works (outward on a boss, inward in a
 * blend), and read the axis, centre and major radius off the circle. */
bool SeedTorus(const std::vector<V3> &pts, const std::vector<V3> &nrm,
               double *q)
{
    const size_t n = pts.size();
    if (n < 12 || nrm.size() != n)
        return false;
    /* Bounded work per call: this runs inside the RANSAC trial loop. */
    std::vector<V3> p, d;
    const size_t stride = std::max<size_t>(1, n / 400);
    for (size_t i = 0; i < n; i += stride) {
        p.push_back(pts[i]);
        d.push_back(nrm[i]);
    }
    const size_t m = p.size();
    if (m < 12)
        return false;
    V3 c0;
    Centroid(p, c0);
    double ext = 0;
    for (const V3 &x : p)
        ext = std::max(ext, Norm(x - c0));
    if (!(ext > 0))
        return false;

    std::vector<V3> spine(m);
    double out[8];
    /* How far from a circle the tube centres fall for this minor radius. */
    auto residual = [&](double r, int sgn, double *keep) -> double {
        for (size_t i = 0; i < m; ++i)
            spine[i] = p[i] + d[i] * (sgn * r);
        double pl[4];
        if (!SeedPlane(spine, pl))
            return 1e300;
        const V3 a = Unit(V3(pl[0], pl[1], pl[2]));
        V3 c;
        double R = 0;
        if (!CircleInPlane(spine, a, c, R))
            return 1e300;
        if (!(R > r))
            return 1e300; /* r >= R is a self-intersecting torus, not a part */
        double ss = 0;
        for (const V3 &x : spine) {
            const V3 v = x - c;
            const double u = Dot(v, a);
            const double w = Norm(v - a * u) - R;
            ss += u * u + w * w;
        }
        if (keep) {
            keep[0] = c.x;
            keep[1] = c.y;
            keep[2] = c.z;
            keep[3] = a.x;
            keep[4] = a.y;
            keep[5] = a.z;
            keep[6] = R;
            keep[7] = r;
        }
        return std::sqrt(ss / static_cast<double>(m));
    };

    const double lo = ext * 0.004, hi = ext * 2.0;
    const int steps = 56;
    double bestR = -1, bestScore = 1e300;
    int bestSign = 1;
    for (int sgn = -1; sgn <= 1; sgn += 2) {
        for (int i = 0; i <= steps; ++i) {
            const double r =
                lo * std::pow(hi / lo, i / static_cast<double>(steps));
            const double sc = residual(r, sgn, nullptr);
            if (sc < bestScore) {
                bestScore = sc;
                bestR = r;
                bestSign = sgn;
            }
        }
    }
    if (!(bestR > 0) || bestScore > 1e299)
        return false;
    /* Golden-section down to a fraction of the step the scan used. */
    const double ratio = std::pow(hi / lo, 1.0 / steps);
    double a0 = bestR / ratio, b0 = bestR * ratio;
    const double gr = 0.6180339887498949;
    double x1 = b0 - gr * (b0 - a0), x2 = a0 + gr * (b0 - a0);
    double f1 = residual(x1, bestSign, nullptr);
    double f2 = residual(x2, bestSign, nullptr);
    for (int it = 0; it < 32 && b0 - a0 > bestR * 1e-6; ++it) {
        if (f1 < f2) {
            b0 = x2;
            x2 = x1;
            f2 = f1;
            x1 = b0 - gr * (b0 - a0);
            f1 = residual(x1, bestSign, nullptr);
        } else {
            a0 = x1;
            x1 = x2;
            f1 = f2;
            x2 = a0 + gr * (b0 - a0);
            f2 = residual(x2, bestSign, nullptr);
        }
    }
    const double rFinal = 0.5 * (a0 + b0);
    if (residual(rFinal, bestSign, out) > 1e299)
        return false;
    for (int i = 0; i < 8; ++i)
        q[i] = out[i];
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
/* Wall-clock at each stage boundary, so a model that takes twenty seconds can
 * say which pass took them. */
static std::chrono::steady_clock::time_point mrPrev;
#define MR_STAGE(name)                                                        \
    do {                                                                      \
        static std::chrono::steady_clock::time_point mrLast;                  \
        const auto mrNow = std::chrono::steady_clock::now();                  \
        if (std::string(name) == "start")                                     \
            std::fprintf(stderr, "  [stage] --- start ---\n");                \
        else                                                                  \
            std::fprintf(                                                     \
                stderr, "  [stage] %-28s %8.1f ms\n", name,                   \
                std::chrono::duration<double, std::milli>(mrNow - mrPrev)      \
                    .count());                                                \
        (void)mrLast;                                                         \
        mrPrev = mrNow;                                                       \
    } while (0)
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
#define MR_STAGE(name) ((void)0)
#endif

/* Mean |cos| a candidate surface's normals must reach to be believed. About
 * 25 degrees of average slack: loose enough for a coarse download's estimated
 * vertex normals, tight enough that a sphere never passes for a cylinder. */
const double kMinNormalAgreement = 0.90;

/* How much better a later, more complex kind must agree with the mesh normals
 * before it displaces an earlier one that also fits. Level kinds keep the
 * simpler answer. */
const double kAgreeSlack = 0.004;

/* Agreement past which no later kind could win by more than the slack, so the
 * search can stop. */
const double kAgreeCertain = 0.9995;

/* Where in the sorted dihedrals of a patch to read "the sharpest edges in it".
 * A crease ring is a few per cent of a patch's internal edges. */
const double kCreaseQuantile = 0.98;

/* How many times the ordinary curvature step that ring must reach before it is
 * a crease and not just the tessellation. Below this the crease and the facet
 * angle are the same size and no dihedral test can separate them. */
const double kCreaseRatio = 2.0;

/* And an absolute floor, so a very finely tessellated smooth patch is never cut
 * at a two-degree "crease" that is really its own curvature. */
const double kMinCreaseAngle = 2.0 * M_PI / 180.0;

/* A patch with more creases than this is not a pair of surfaces, it is noise. */
const int kMaxCreaseDepth = 4;

/* RANSAC budget. Bounded on purpose: this runs only on patches that fitted
 * nothing, and being thorough on a pathological patch at the cost of being
 * slow on every model is not a trade worth making. */
const int kRansacRounds = 32;   /* surfaces extracted per patch */
const int kRansacMinPatch = 10; /* below this, growing is fine */
const int kRansacMinSupport = 6;/* triangles a winner must explain */
const double kRansacNormalGate = 0.90;

/* HOW BIG a neighbourhood a candidate is fitted to — and the reason this is a
 * ladder rather than a number.
 *
 * A sample that straddles two surfaces fits neither, so it proposes nothing.
 * A fixed forty-triangle seed is therefore not "more evidence", it is a
 * commitment to features at least forty triangles wide: on a 60 mm plate whose
 * corner fillets are twelve facets each, every one of the forty-eight trials
 * on the side band drew a sample containing wall AND fillet, every fit failed,
 * and RANSAC returned nothing at all — measured, 56 triangles in, 0 surfaces
 * out. The fillets then went to triangles, which is what "the radiuses are not
 * radiuses" looks like from the outside.
 *
 * Classical RANSAC avoids this by sampling MINIMALLY — three points for a
 * plane — precisely so a sample cannot span a boundary. But a minimal sample
 * off a coarse mesh also fits a sphere the size of a house through any four
 * facets. So sample at several scales and let support decide: the small seeds
 * find the small features, the large seeds are stable on the large ones, and a
 * proposal that describes nothing real claims nothing and loses. */
const int kRansacSeedLadder[] = {4, 6, 10, 18, 30, 48};
const int kRansacLadderSteps =
    (int)(sizeof(kRansacSeedLadder) / sizeof(kRansacSeedLadder[0]));
const int kRansacTrialsPerSize = 12; /* candidates per rung, per round */

/* A residual this far below tolerance is not "within tolerance", it is the
 * surface the mesh was made from. */
const double kExactFitFraction = 0.02;

/* Below this an edge is not turning at all: the quad diagonals of a
 * quad-meshed surface sit at exactly zero and must never be averaged in. */
const double kBendFloorDeg = 0.5;

/* The band the feature angle is allowed to land in, and the sample it needs
 * before it is worth reading at all. Outside the band the histogram is saying
 * something the geometry does not support — a model with no features, or one
 * that is nothing but features — and the caller's own value stands. */
const double kFeatureAngleMinDeg = 12.0;
const double kFeatureAngleMaxDeg = 55.0;
const int kFeatureAngleMinEdges = 24;

/* What makes the split believable: each side of it must hold at least a
 * twelfth of the bending edges, and the gap between them must be this many
 * degrees wide. */
const double kFeatureModeFraction = 12.0;
const int kFeatureGapBins = 6; /* degrees of empty histogram that make a gap */

/* How much slack a second sewing pass gets when the first leaves a hybrid
 * shell open. Bounded: past this the "seam" being closed is a real gap. */
const double kSewRetryFactor = 5.0;

/* Fewer triangles than this and the fit has no sample to speak of. */
const int kMinTrustTriangles = 6;

/* How much of the tolerance a surface may use up and still be believed to be
 * THE surface rather than one that happens to pass nearby. */
const double kTrustRmsFraction = 0.15;

/* How far off a facet's interior a fitted surface may bow, as a fraction of
 * that facet's own size. A surface the mesh was tessellated from bows by the
 * chord height, which is quadratic in facet size and therefore small: measured
 * on a 12-segment cylinder, under a hundredth of the facet. A quarter of the
 * facet is not a tessellation of anything. */
const double kCentroidFacetFraction = 0.25;

/* When a smooth run is judged freeform rather than prismatic: it has to be big
 * enough for the judgement to mean anything, less than half of it accounted
 * for by surfaces, and those surfaces facet-sized. */
const int kFreeformMinRun = 60;
const int kFreeformPieceTriangles = 8;
const int kFreeformCoverDenom = 8; /* under an eighth explained: freeform */

/* How small a fitted patch must be, as a fraction of the model's surface,
 * before being alone among triangles is reason enough to become triangles. */
const double kScrapAreaFraction = 0.002;

/* The precision a tessellated model's own vertices hold, as a fraction of its
 * size: float32 gives about a tenth of this, so it is a bar with headroom and
 * still four hundred times tighter than a typical tolerance. */
const double kMeshPrecisionFrac = 1.0e-6;

/* How far round its own surface a patch must reach before the radius it
 * fitted means anything. Twenty-five degrees of arc; below that a wide range
 * of radii pass through the same points within tolerance. */
const double kMinSweepRad = 25.0 * M_PI / 180.0;

/* How many facet steps of normal disagreement a fit may have and still be
 * describing THIS surface. Half a step is what a perfect fit costs on a
 * tessellation; four times that is something else. */
const double kAgreeFacetFactor = 2.0;

/* ...and a floor, so an exactly-tessellated flat face is not held to zero. */
const double kAgreeFloorRad = 4.0 * M_PI / 180.0;

/* Above this the faceted fallback is not a rescue, it is a freeze.
 *
 * Measured at 90 to 140 microseconds a triangle — a tenth of what it cost
 * before the shell was built directly, but still a hundred times the fitted
 * path — and an iPad is a few times slower than the machine it was measured
 * on. Thirty thousand triangles is then of the order of ten seconds with a
 * notice on screen, which is a long wait for an import and a short one for a
 * mistake. Past it the fitted result is kept however poor: a model that is
 * visibly wrong beats an app that is visibly dead, and its faces are at least
 * bounded now. */
const int kMaxAutoFacetedTriangles = 30000;

/* Fewer triangles per patch than this and the fit did not read the model, it
 * came apart on it. A recognised part runs to tens or hundreds of triangles a
 * face; the download that exposed this managed six. */
const int kShatterTrianglesPerPatch = 10;

/* And the ratio says nothing on a small mesh: a cube with one face missing is
 * five patches for ten triangles and exactly right. */
const int kShatterFloorTriangles = 200;

/* Largest fitted radius worth believing, as a multiple of the part's own
 * bounding-box diagonal. */
const double kMaxRadiusFactor = 4.0;

/* How much of a surface a sample actually goes ROUND, in radians.
 *
 * A radius is only knowable from a sample that turns far enough about it.
 * Twenty degrees of a cylinder is an arc that a thousand different radii pass
 * through within tolerance, and the one a fitter picks off it is noise. The
 * same is true of a sphere's cap and of a torus's spine. A plane has no radius
 * to pin down, so it is always fully covered. */
double SurfaceCoverage(SurfKind k, const double *q, const std::vector<V3> &pts)
{
    if (k == kPlane)
        return 2.0 * M_PI;
    if (pts.size() < 3)
        return 0;
    if (k == kSphere) {
        const V3 c(q[0], q[1], q[2]);
        V3 mean;
        for (const V3 &x : pts)
            mean += Unit(x - c);
        if (Norm(mean) < 1e-12)
            return 2.0 * M_PI; /* points all round it: a whole sphere */
        mean = Unit(mean);
        /* The RANGE of colatitude, not its maximum.
         *
         * On a genuine cap the mean direction is inside it, so the range runs
         * from zero and the two are the same number. On a thin RING they are
         * not: the mean points at the pole the ring encircles, every point is
         * the same distance from it, and a cap-angle test reads the ring's
         * latitude — wide — where its actual extent is a few degrees. That
         * matters because one row of a surface of revolution lies EXACTLY on
         * a sphere centred on its axis: a boss's fillet ring came back as a
         * stack of concentric spherical bands, each with a residual of zero,
         * because nothing asked whether the sample had any width. */
        double lo = M_PI, hi = 0;
        for (const V3 &x : pts) {
            const double t =
                std::acos(std::max(-1.0, std::min(1.0, Dot(Unit(x - c), mean))));
            lo = std::min(lo, t);
            hi = std::max(hi, t);
        }
        return (hi - lo) * 2.0;
    }
    /* Cylinder, cone and torus all turn about an axis. */
    const V3 c(q[0], q[1], q[2]);
    const V3 ax = Unit(V3(q[3], q[4], q[5]));
    if (!(Norm(ax) > 0.5))
        return 0;
    V3 u = Cross(ax, V3(0, 0, 1));
    if (Norm(u) < 1e-6)
        u = Cross(ax, V3(1, 0, 0));
    u = Unit(u);
    const V3 v = Unit(Cross(ax, u));
    std::vector<double> ang;
    ang.reserve(pts.size());
    for (const V3 &x : pts) {
        const V3 d = (x - c) - ax * Dot(x - c, ax);
        if (Norm(d) < 1e-12)
            continue;
        ang.push_back(std::atan2(Dot(d, v), Dot(d, u)));
    }
    if (ang.size() < 3)
        return 0;
    std::sort(ang.begin(), ang.end());
    /* The sweep is a full turn minus the widest gap between samples. */
    double gap = ang.front() + 2.0 * M_PI - ang.back();
    for (size_t i = 1; i < ang.size(); ++i)
        gap = std::max(gap, ang[i] - ang[i - 1]);
    return 2.0 * M_PI - gap;
}

Fit FitPatch(const PatchData &d, double tol, double scale)
{
    const std::vector<V3> &pts = d.pts;
    Fit best;
    Fit chosen;
    bool have = false;
    bool chosenPinned = false;
    bool chosenExact = false;
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
            /* Which of the kinds that PASS through the points is the surface
             * these points came off. Three questions, in order.
             *
             * CAN THIS SAMPLE PIN IT DOWN? Twenty degrees of a cylinder is an
             * arc a thousand radii pass through within tolerance. Six
             * triangles off a coarse corner fillet fit a sphere marginally
             * better than the cylinder they came from — the normals barely
             * separate them — but they go ninety degrees round the cylinder
             * and a few round the sphere. Only one of the two is knowable from
             * this sample, and taking the other sent the fillet to triangles.
             *
             * IS IT EXACT? A tessellation puts its vertices ON the surface
             * they came from, so this is not a matter of degree: it separates
             * the surface the part was built from one that merely passes near.
             * Two rows of a boss's fillet ring were fitted by a sphere at
             * 0.0377, a cone at 0.0350 and a torus at 0.0000030 — the true
             * R=10.5, r=1.5, to seven figures — while their normal agreements
             * were 0.985, 0.987 and 0.987. At three decimals the normals
             * cannot tell them apart; the residual does, by twelve thousand.
             * (On a noisy mesh nothing is exact, every candidate lands in the
             * same tier, and this question simply does not arise.)
             *
             * DOES IT POINT THE WAY THE MESH DOES, and is the simpler kind
             * level with it? A plane fits three columns of a tessellated
             * cylinder to well inside tolerance and so does a sphere the size
             * of a house; the residual cannot tell those apart but the normals
             * can, by a wide margin — 0.94 against 0.999 on that strip. The
             * slack keeps a genuinely flat face a PLANE rather than a sphere
             * of radius ten thousand. */
            const bool pinned = SurfaceCoverage(k, q, pts) >= kMinSweepRad;
            const bool exact = rms <= tol * kExactFitFraction;
            const bool better =
                !have || (pinned && !chosenPinned) ||
                (pinned == chosenPinned && exact && !chosenExact) ||
                (pinned == chosenPinned && exact == chosenExact &&
                 agree > chosen.agree + kAgreeSlack);
            if (better) {
                chosen.kind = k;
                std::memcpy(chosen.q, q, sizeof(q));
                chosen.rms = rms;
                chosen.agree = agree;
                chosenPinned = pinned;
                chosenExact = exact;
                have = true;
            }
            /* Nothing later can beat this by more than the slack, so stop —
             * which is the common case (a flat face, first kind tried). */
            if (chosenPinned && chosenExact && chosen.agree >= kAgreeCertain)
                return chosen;
            continue;
        }
        if (rms < best.rms) {
            best.kind = k;
            std::memcpy(best.q, q, sizeof(q));
            best.rms = rms;
            best.agree = agree;
        }
    }
    if (have)
        return chosen;
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

/* At what angle an edge stops being TESSELLATION and becomes a FEATURE — read
 * off this mesh, not fixed in advance.
 *
 * A fixed bar cannot work, because the two things it separates live at
 * different angles in different files. The user's part is a 20x50 plate from
 * Shapr3D: its fillets are tessellated in so few rows that consecutive facets
 * turn by 22 to 30 degrees, while its real edges turn by 80 to 100. At the
 * shipped 22 degrees, 252 of those tessellation steps counted as features and
 * the model arrived at the fitter as 149 smooth runs — most of them a single
 * facet — where the part has about twenty faces. Nothing downstream recovers
 * from that: a face carved out of one facet fits its own plane exactly, and
 * 124 of them were kept.
 *
 * The mesh says where the line is. A tessellated CAD model has a bimodal
 * histogram — a dense cluster of small steps from tessellating smooth
 * surfaces, a second cluster at the corners — and the answer is the valley
 * between them. Otsu's threshold (maximum between-class variance) finds it
 * without assuming where it is: on that plate it lands at 42.5 degrees, and
 * the count of sharp edges is flat at 385-387 anywhere from 30 to 50, which
 * is what a real valley looks like.
 *
 * Biased high on purpose. Under-segmentation is recoverable — a patch holding
 * two surfaces is exactly what SplitPatch, the crease cut and RANSAC are for —
 * and over-segmentation is not. */
double FeatureAngleDeg(const Mesh &m, double fallback)
{
    std::vector<int> hist(180, 0);
    int nb = 0;
    const int nt = m.triCount();
    for (int t = 0; t < nt; ++t) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || o < t)
                continue;
            const double c =
                std::max(-1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])));
            const double deg = std::acos(c) * 180.0 / M_PI;
            /* The quad diagonals of a quad-meshed surface sit at exactly zero
             * and say nothing about where the line is. */
            if (deg <= kBendFloorDeg)
                continue;
            hist[std::min(179, static_cast<int>(deg))]++;
            nb++;
        }
    }
    if (nb < kFeatureAngleMinEdges)
        return fallback;

    /* Walk UP from the middle of the tessellation until the histogram opens.
     *
     * Otsu's threshold was the obvious tool and it is the wrong one, because
     * the histogram often has three clusters rather than two: on a plate with
     * large corner fillets there is a mode where the fillet leaves the wall
     * tangentially, a second at the fillet's own facet steps, and a third at
     * the ninety-degree edges. Otsu maximises between-class variance, lands in
     * the FIRST valley at 21 degrees, and cuts the fillet along its own
     * tessellation — precisely the failure this exists to prevent.
     *
     * Walking down from the sharpest edge is wrong the other way: it clears
     * every tessellation cluster but also every OBLIQUE feature, and on the
     * user's part that put the line at 57 degrees, swallowing eighteen real
     * edges between 45 and 56.
     *
     * The median bending angle is inside the tessellation by construction —
     * that is what most edges are on a tessellated model — so start there and
     * take the first real gap above it. Below the gap is how finely this mesh
     * was cut up; above it is the part. */
    int med = 0;
    {
        int seen = 0;
        for (int i = 0; i < 180; ++i) {
            seen += hist[i];
            if (seen * 2 >= nb) {
                med = i;
                break;
            }
        }
    }
    int at = -1, run = 0;
    for (int i = med + 1; i < 180; ++i) {
        if (hist[i] == 0) {
            if (++run == 1)
                at = i;
            if (run >= kFeatureGapBins)
                break;
        } else {
            run = 0;
            at = -1;
        }
    }
    /* No gap above the median: the mesh is nothing but tessellation (an
     * organic shell) or nothing but features (a low-poly design). Neither
     * wants a computed angle, and the caller's own value stands. */
    if (at < 0 || run < kFeatureGapBins)
        return fallback;
    double above = 0;
    for (int i = at; i < 180; ++i)
        above += hist[i];
    const double below = nb - above;
    if (std::min(above, below) * kFeatureModeFraction < nb)
        return fallback;

    return std::max(kFeatureAngleMinDeg,
                    std::min(kFeatureAngleMaxDeg, at + 0.0));
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

/* Is a fitted surface EVIDENCE, or an artifact of the sample it was fitted to?
 *
 * This is the question that decides whether a model comes back as CAD or as a
 * bag of triangles, and getting it wrong in either direction is visible. Six
 * triangles off a curved shell fit a plane to well inside tolerance and a
 * sphere the size of a house even better; keeping those is how a smooth shell
 * became 179 "surfaces" that met nowhere. Throwing the whole model away
 * because of them is how its real holes stopped being circles.
 *
 * So it is asked per patch, on two counts.
 *
 * COVERAGE. A radius is only knowable from a patch that goes round enough of
 * it. Twenty degrees of a cylinder is an arc that a thousand different radii
 * pass through within tolerance, and the one the fitter picked is noise. This
 * is an absolute geometric fact, independent of how finely the thing is
 * tessellated, so it is an absolute threshold.
 *
 * AGREEMENT, against what the tessellation can actually deliver. A coarse
 * twelve-sided cylinder has facet normals fifteen degrees off the surface at
 * the corners; demanding better than that would reject every low-poly download
 * there is. So the bar is not a fixed angle but the patch's own facet step:
 * a fit whose normals are off by about half a facet is as good as this mesh
 * can be, and one that is off by four times that is describing something else.
 */
/* How far a surface strays from a facet's INTERIOR, against what that facet's
 * size allows.
 *
 * Three vertices pin a fit; the surface between them is then free, and a
 * surface with enough parameters uses that freedom. Returns the worst
 * deviation at the centroid and the three edge midpoints — the points furthest
 * from the vertices — and sets `bar` to what a real tessellation of this facet
 * would show there, which is the chord height: quadratic in facet size and so
 * far below the facet itself that the two never come close. */
double FacetBulge(SurfKind k, const double *q, const Mesh &m, int t,
                  double &bar)
{
    const V3 &a = m.pos[m.tri[t * 3]];
    const V3 &b = m.pos[m.tri[t * 3 + 1]];
    const V3 &c = m.pos[m.tri[t * 3 + 2]];
    const V3 probe[4] = {V3((a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3,
                            (a.z + b.z + c.z) / 3),
                         V3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2),
                         V3((b.x + c.x) / 2, (b.y + c.y) / 2, (b.z + c.z) / 2),
                         V3((c.x + a.x) / 2, (c.y + a.y) / 2, (c.z + a.z) / 2)};
    double worst = 0;
    for (int i = 0; i < 4; ++i)
        worst = std::max(worst, std::fabs(SurfDist(k, q, probe[i])));
    bar = std::max(std::max(Norm(b - a), Norm(c - b)), Norm(a - c)) *
          kCentroidFacetFraction;
    return worst;
}

#ifdef MESHRECON_TRACE
const char *g_why = "ok";
#define WHY(x) (g_why = (x))
#else
#define WHY(x) ((void)0)
#endif

bool Identifiable(const Patch &p, const Mesh &m, double tol, bool fragment)
{
    WHY("ok");
    if (p.fit.kind == kNone)
        return WHY("nofit"), false;

    /* RESIDUAL. This is the sharpest of the three, and the reason is that a
     * tessellation puts its vertices ON the surface it came from: a real hole
     * fits its cylinder with a residual of nothing at all, at any mesh
     * density. A surface that merely happens to pass through a patch does not
     * — it squeaks inside tolerance and no further. Measured on a curved shell
     * with four drilled holes, at a tolerance of 0.20 mm: the four real
     * cylinders came back at 0.000, and the twenty "spheres" the fitter
     * invented on the shell at 0.05 to 0.16. Nothing lands in between. */
    if (p.fit.rms > tol * kTrustRmsFraction)
        return WHY("rms"), false;
    /* And a FRAGMENT is held to the exact bar instead.
     *
     * A patch that is a whole smooth run has a witness: the mesh's own sharp
     * edges bound it, and the model is saying "this is one face". A patch the
     * splitter carved out of a bigger one has no witness at all — the splitter
     * will always find something, and on a smooth organic shell it finds
     * hundreds of little planes that each sit inside the ordinary residual bar
     * and none of which exist. Measured on a 2676-triangle ellipsoidal shell:
     * 129 invented planes and 3 spheres, every one of them under 0.15 of
     * tolerance, and every one of them gone at 0.02 — while the four real
     * drilled holes in the same shell fit at 0.00000 and stay. */
    if (fragment && p.fit.rms > tol * kExactFitFraction)
        return WHY("notexact"), false;
    /* A plane is pinned down exactly by three points, so the sample-size floor
     * is for the CURVED kinds only — a box face is two triangles and perfectly
     * knowable, and holding it to six was how a box lost its planes. */
    if (p.fit.kind != kPlane &&
        static_cast<int>(p.tris.size()) < kMinTrustTriangles)
        return WHY("tootiny"), false;

    /* What this tessellation can deliver: the median angle between neighbouring
     * facets inside the patch. A fit cannot be truer than half of that. */
    std::vector<double> step;
    step.reserve(p.tris.size());
    std::unordered_set<int> mine(p.tris.begin(), p.tris.end());
    for (int t : p.tris) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || o < t || mine.find(o) == mine.end())
                continue;
            step.push_back(std::acos(std::max(
                -1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])))));
        }
    }
    /* NOT the plain median. Half the internal edges of a quad-meshed surface
     * are the diagonals inside the quads, whose dihedral is exactly zero, so a
     * median reads 0 on every tessellated cylinder — and then the bar collapses
     * to the floor and real cylinders sit on the edge of rejection. Take the
     * median of the edges that actually bend. */
    double facet = 0;
    if (!step.empty()) {
        std::sort(step.begin(), step.end());
        const double floorAng = std::max(step.back() * 0.05, 1e-4);
        size_t lo = 0;
        while (lo < step.size() && step[lo] < floorAng)
            lo++;
        if (lo < step.size())
            facet = step[lo + (step.size() - lo) / 2];
    }
    const double allowed =
        std::max(facet * kAgreeFacetFactor, kAgreeFloorRad);
    if (std::acos(std::max(-1.0, std::min(1.0, p.fit.agree))) > allowed)
        return WHY("agree"), false;

    /* A plane has no radius to pin down, so agreement is the whole test. */
    if (p.fit.kind == kPlane)
        return true;

    /* Does the surface pass through the mesh's FACES, or only its vertices?
     *
     * Everything above is measured at vertices, and a surface with enough
     * freedom can thread every vertex of a patch and still bulge through the
     * middle of it. That is not a hypothetical: a 12 mm corner fillet plus two
     * triangles of the wall beside it was fitted EXACTLY — residual 0.00000 at
     * every vertex — by a torus of major radius 25 mm about the part's own
     * vertical axis, which bows 11.2 mm out through the facets in between. Its
     * trimmed face added three hundred percent to the model's volume.
     *
     * A facet is a chord of the surface it came off, so the surface stands off
     * its interior by the chord height, which is quadratic in facet size and
     * tiny: 0.05 mm on the real fillets in that same model, against 11.2 for
     * the torus. Sampling the centroid and the three edge midpoints — the
     * points furthest from the vertices that pinned the fit — separates the
     * two by two orders of magnitude, so the bar can be loose and still
     * decisive. */
    {
        const int stride2 = std::max<int>(1, (int)p.tris.size() / 256);
        for (size_t i = 0; i < p.tris.size(); i += stride2) {
            double bar = 0;
            if (FacetBulge(p.fit.kind, p.fit.q, m, p.tris[i], bar) >
                std::max(bar, tol))
                return WHY("bulge"), false;
        }
    }

    /* Sample the patch's corners — a few hundred is ample to establish a
     * quarter turn, and a patch can hold thousands. */
    std::vector<V3> pts;
    const int stride = std::max<int>(1, static_cast<int>(p.tris.size()) / 96);
    for (size_t i = 0; i < p.tris.size(); i += stride)
        for (int k = 0; k < 3; ++k)
            pts.push_back(m.pos[m.tri[p.tris[i] * 3 + k]]);
    if (pts.size() < 3)
        return WHY("nopoints"), false;
    if (SurfaceCoverage(p.fit.kind, p.fit.q, pts) < kMinSweepRad)
        return WHY("sweep"), false;
    return true;
}

/* Cuts a patch at its own sharpest internal crease, if it has one.
 *
 * A smooth patch that fits no primitive is often two surfaces meeting at an
 * angle SHALLOWER than the global sharp-edge threshold: a cylinder into a
 * gentle cone, a nozzle, a tapered boss, a shallow chamfer. Region growing
 * handles a TANGENT seam well and a creased one badly — at a crease every seed
 * near it straddles both surfaces and fits neither, and the patch comes apart
 * into shards instead of two faces.
 *
 * The crease is visible in the patch's own dihedral statistics, with no
 * absolute angle anywhere: on a smoothly curved patch every internal dihedral
 * is about the tessellation step, so the distribution is tight; a crease puts
 * one ring of edges far above it. Comparing a high quantile against that step
 * is self-calibrating — it reads the same on a 12-segment download as on a
 * 2000-segment export, and it says "no crease" on a sphere.
 *
 * The step is NOT the plain median: half the internal edges of a quad-meshed
 * surface are the diagonals inside the quads, whose dihedral is exactly zero,
 * so a median reads zero on every cylinder and the cut lands everywhere. Take
 * the median of the edges that actually bend. */
bool SplitAtCrease(const Mesh &m, const std::vector<int> &tris, int minTris,
                   std::vector<std::vector<int>> &parts)
{
    parts.clear();
    if (tris.size() < 8)
        return false;
    std::unordered_map<int, int> local;
    for (size_t i = 0; i < tris.size(); ++i)
        local.emplace(tris[i], static_cast<int>(i));

    std::vector<double> ang;
    ang.reserve(tris.size() * 3 / 2);
    for (int t : tris) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || o < t || local.find(o) == local.end())
                continue;
            const double c =
                std::max(-1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])));
            ang.push_back(std::acos(c));
        }
    }
    if (ang.size() < 8)
        return false;
    std::sort(ang.begin(), ang.end());
    const double hi = ang[(size_t)(ang.size() * kCreaseQuantile)];
    if (hi < kMinCreaseAngle)
        return false;
    const double floorAng = std::max(hi * 0.05, 0.2 * M_PI / 180.0);
    size_t lo = 0;
    while (lo < ang.size() && ang[lo] < floorAng)
        lo++;
    if (lo >= ang.size())
        return false;
    const double step = ang[lo + (ang.size() - lo) / 2];
    if (hi < kCreaseRatio * std::max(step, 1e-4))
        return false;

    /* Cut between the two: above every ordinary curvature step, below the
     * crease. The geometric mean puts it there on any tessellation. */
    double thr = std::sqrt(std::max(step, 1e-6) * hi);
    thr = std::max(thr, 1.5 * step);
    thr = std::min(thr, 0.8 * hi);
    const double cosThr = std::cos(thr);

    std::vector<int> comp(tris.size(), -1);
    int n = 0;
    std::vector<int> stack;
    for (size_t si = 0; si < tris.size(); ++si) {
        if (comp[si] >= 0)
            continue;
        const int id = n++;
        stack.assign(1, static_cast<int>(si));
        comp[si] = id;
        while (!stack.empty()) {
            const int i = stack.back();
            stack.pop_back();
            const int t = tris[i];
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0)
                    continue;
                auto it = local.find(o);
                if (it == local.end() || comp[it->second] >= 0)
                    continue;
                if (Dot(m.tnorm[t], m.tnorm[o]) < cosThr)
                    continue;
                comp[it->second] = id;
                stack.push_back(it->second);
            }
        }
    }
    if (n < 2)
        return false;
    parts.assign(n, std::vector<int>());
    for (size_t i = 0; i < tris.size(); ++i)
        parts[comp[i]].push_back(tris[i]);
    /* Two real pieces, not one piece and a rim of strays. */
    int big = 0;
    for (const std::vector<int> &pp : parts)
        if (static_cast<int>(pp.size()) >= std::max(minTris, 3))
            big++;
    if (big < 2) {
        parts.clear();
        return false;
    }
    return true;
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

/* RANSAC over one patch: propose many primitives, keep the one the mesh
 * supports best, take its triangles, repeat.
 *
 * This is the segmentation step the classical literature settled on (Schnabel,
 * Wahl & Klein 2007) and it is what the commercial converters use, because
 * greedy region growing has a failure mode it cannot escape: it commits to
 * whatever the first seed suggested. On a coarse prismatic model — a
 * downloaded one, in other words — the first seed off a twelve-sided cylinder
 * is a PLANE that fits three columns to well inside tolerance, and the barrel
 * comes back as a fan of planar strips.
 *
 * Proposing instead of committing removes that. A candidate is grown from a
 * random seed, fitted, and then scored against the WHOLE patch: how many
 * triangles does this surface actually explain? The plane explains three
 * columns; the cylinder explains the barrel. The cylinder wins on evidence
 * rather than on being asked first.
 *
 * Deterministic on purpose — the generator is seeded from the patch — because
 * a converter whose output depends on the weather cannot be tested. */
/* Which of two RANSAC proposals describes the part better.
 *
 * Support alone is the obvious score and it is wrong, because a surface with
 * one more degree of freedom can always reach a little further. Measured on a
 * 60 mm plate with four r=5 corner fillets: three came back as cylinders with
 * 32 triangles and a residual of EXACTLY zero, and the fourth as a torus with
 * 34 — the same fillet plus two triangles of the wall it is tangent to, held
 * together by a major radius of 15 mm that exists nowhere in the part. Two
 * extra triangles bought it the round, and the trimmed torus that came out of
 * it added forty-two percent to the model's volume.
 *
 * The residual is what separates them, and it separates them completely. A
 * tessellation puts its vertices ON the surface they came from, so a proposal
 * that is really that surface fits it to zero while a proposal that is merely
 * near it does not. So: an exact candidate beats an inexact one no matter how
 * much more the inexact one claims; among equals, more support wins; and on a
 * genuine tie the simpler primitive does, since kind order runs plane, sphere,
 * cylinder, cone, torus. On a noisy scan nothing is exact, everything lands in
 * the lower tier, and this is support-first again, as it was. */
bool BeatsCandidate(size_t nA, double rmsA, SurfKind kA, size_t nB, double rmsB,
                    SurfKind kB, double tol)
{
    if (nA == 0)
        return false;
    if (nB == 0)
        return true;
    const bool exA = rmsA <= tol * kExactFitFraction;
    const bool exB = rmsB <= tol * kExactFitFraction;
    if (exA != exB)
        return exA;
    if (nA != nB)
        return nA > nB;
    if (std::fabs(rmsA - rmsB) > tol * 1e-3)
        return rmsA < rmsB;
    return kA < kB;
}

void SplitByRansac(const Mesh &m, const std::vector<int> &tris, double tol,
                   double scale, int minTris, int origin,
                   std::vector<Patch> &out, std::vector<int> &leftover)
{
    leftover.clear();
    const int n = static_cast<int>(tris.size());
    if (n < kRansacMinPatch) {
        leftover = tris;
        return;
    }
    std::unordered_map<int, int> local;
    for (int i = 0; i < n; ++i)
        local.emplace(tris[i], i);
    const size_t before = out.size();
    std::vector<char> taken(n, 0);
    std::vector<char> barred(n, 0); /* seeds that led nowhere */
    int remaining = n;

    unsigned rng = 0x9E3779B9u ^ (unsigned)n ^ ((unsigned)tris[0] * 2654435761u);
    auto next = [&rng]() {
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        return rng;
    };

    PatchData pd;
    std::vector<int> seedRegion, stack, inliers, best;
    Fit bestFit;
    double bestRms = 1e300;
    int bestStart = -1;
    const int trials = kRansacLadderSteps * kRansacTrialsPerSize;
    for (int round = 0; round < kRansacRounds && remaining >= minTris; ++round) {
        best.clear();
        bestFit = Fit();
        bestRms = 1e300;
        bestStart = -1;
        for (int trial = 0; trial < trials; ++trial) {
            const int want = kRansacSeedLadder[trial % kRansacLadderSteps];
            int start = -1;
            for (int a = 0; a < 16 && start < 0; ++a) {
                const int c = (int)(next() % (unsigned)n);
                if (!taken[c] && !barred[c])
                    start = c;
            }
            if (start < 0)
                continue;
            seedRegion.clear();
            stack.assign(1, start);
            std::unordered_map<int, char> inSeed;
            inSeed.emplace(tris[start], 1);
            while (!stack.empty() && (int)seedRegion.size() < want) {
                const int i = stack.back();
                stack.pop_back();
                seedRegion.push_back(tris[i]);
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[tris[i] * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || taken[it->second])
                        continue;
                    if (inSeed.find(o) != inSeed.end())
                        continue;
                    inSeed.emplace(o, 1);
                    stack.push_back(it->second);
                }
            }
            if ((int)seedRegion.size() < 4)
                continue;
            PatchPoints(m, seedRegion, pd, 600);
            const Fit f = FitPatch(pd, tol, scale);
            if (f.kind == kNone || f.rms > tol * kTrustRmsFraction)
                continue;

            /* Score it against the whole patch, CONNECTED to the seed: a
             * cylinder must not claim the identical hole on the far side of
             * the part. */
            inliers.clear();
            double ss = 0;
            int sn2 = 0;
            std::unordered_map<int, char> mark;
            stack.assign(1, start);
            mark.emplace(tris[start], 1);
            while (!stack.empty()) {
                const int i = stack.back();
                stack.pop_back();
                const int t = tris[i];
                bool ok = true;
                double d2 = 0;
                for (int k = 0; k < 3 && ok; ++k) {
                    const V3 &p = m.pos[m.tri[t * 3 + k]];
                    const double dd = SurfDist(f.kind, f.q, p);
                    if (std::fabs(dd) > tol)
                        ok = false;
                    d2 += dd * dd;
                }
                if (ok) {
                    const V3 sn = SurfNormal(f.kind, f.q, m.pos[m.tri[t * 3]],
                                             std::max(scale * 1e-5, 1e-9));
                    if (Norm(sn) > 0.5 &&
                        std::fabs(Dot(sn, m.tnorm[t])) < kRansacNormalGate)
                        ok = false;
                }
                /* And it must pass through the facet, not merely its corners.
                 * A torus threaded exactly through every vertex of a wall,
                 * a corner fillet and the next wall bulges 12.5 mm out
                 * through the middle of them; on vertices alone it was an
                 * exact fit claiming 22 triangles, and it beat the true
                 * cylinder claiming 8. */
                if (ok) {
                    double bar = 0;
                    if (FacetBulge(f.kind, f.q, m, t, bar) >
                        std::max(bar, tol))
                        ok = false;
                }
                if (!ok)
                    continue;
                inliers.push_back(i);
                ss += d2;
                sn2 += 3;
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || taken[it->second])
                        continue;
                    if (mark.find(o) != mark.end())
                        continue;
                    mark.emplace(o, 1);
                    stack.push_back(it->second);
                }
            }
            const double candRms = sn2 ? std::sqrt(ss / sn2) : 1e300;
            /* A candidate that cannot be kept must not be allowed to win.
             *
             * Four triangles fit a sphere exactly wherever you put them, and
             * such a sphere — support 4, residual zero — took the round from a
             * cylinder explaining nineteen triangles of a real fillet, purely
             * by being exact. The extraction then stopped for want of support
             * and two thirds of the run went to triangles. Nothing below the
             * floor is evidence; it should not be on the ballot. */
            if ((int)inliers.size() < std::max(minTris, kRansacMinSupport))
                continue;
            if (BeatsCandidate(inliers.size(), candRms, f.kind, best.size(),
                               bestRms, bestFit.kind, tol)) {
                best = inliers;
                bestFit = f;
                bestRms = candRms;
                bestStart = start;
            }
        }
#ifdef MESHRECON_TRACE
        {
            V3 lo(1e30, 1e30, 1e30), hi(-1e30, -1e30, -1e30);
            for (int i : best)
                for (int k = 0; k < 3; ++k) {
                    const V3 &q = m.pos[m.tri[tris[i] * 3 + k]];
                    lo = V3(std::min(lo.x, q.x), std::min(lo.y, q.y),
                            std::min(lo.z, q.z));
                    hi = V3(std::max(hi.x, q.x), std::max(hi.y, q.y),
                            std::max(hi.z, q.z));
                }
            MR_TRACE("        round %d: best %d tri, kind %s, rms %.6f, "
                     "box (%.2f %.2f %.2f)-(%.2f %.2f %.2f) (remaining %d)\n",
                     round, (int)best.size(), KindName(bestFit.kind), bestRms,
                     lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, remaining);
        }
#endif
        if ((int)best.size() < std::max(minTris, kRansacMinSupport)) {
            MR_TRACE("        -> too little support, stop\n");
            break;
        }

        /* TIGHTEN the claim — either because the winner is exact, or as a
         * RECOVERY when its refit is not.
         *
         * Claiming at tolerance is right for the surface being proposed and
         * too generous at a TANGENCY, where the neighbouring face hugs the
         * proposal for a strip sqrt(2 r tol) wide — 1.2 mm where an r=5 fillet
         * meets its wall. Those triangles pass the distance test and the
         * normal test (at the tangent line the two surfaces share a normal),
         * so the fillet arrives at the refit carrying two triangles of flat
         * wall and comes back as a torus bent round an axis that exists
         * nowhere in the part.
         *
         * A surface the mesh was tessellated from is met by its own vertices
         * exactly, so re-claiming at that standard drops the tangent strip and
         * moves nothing that really is the surface. Worth doing when the
         * winner already looks exact, and worth doing AGAIN, around the refit,
         * when it does not: a mixed claim whose refit misses the exact bar is
         * usually one good surface plus a fringe, and the fringe is what the
         * tight threshold removes. */
        auto tighten = [&](SurfKind kind, const double *q) {
            if (bestStart < 0)
                return;
            /* The mesh's OWN precision, not a fraction of tolerance.
             *
             * A tessellated CAD model's vertices sit on their surface to
             * float32 — three millionths of a millimetre at this size — so
             * anything measurably off it belongs to something else. Measured
             * on the user's part: every triangle of the r=1 fillet along its
             * long edge lies at 0.0000 from that cylinder, and the ten
             * triangles of the transition beside it at 0.0018 to 0.0275. A
             * bar of two thousandths let the nearest of those in, the strip
             * stopped being a cylinder, and the whole fillet went to
             * triangles. */
            const double tight = std::max(scale * kMeshPrecisionFrac, 1e-9);
            std::vector<int> tightened;
            std::unordered_map<int, char> mark2;
            stack.assign(1, bestStart);
            mark2.emplace(tris[bestStart], 1);
            while (!stack.empty()) {
                const int i = stack.back();
                stack.pop_back();
                const int t = tris[i];
                bool ok = true;
                for (int k = 0; k < 3 && ok; ++k)
                    if (std::fabs(SurfDist(kind, q, m.pos[m.tri[t * 3 + k]])) >
                        tight)
                        ok = false;
                if (!ok)
                    continue;
                tightened.push_back(i);
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || taken[it->second])
                        continue;
                    if (mark2.find(o) != mark2.end())
                        continue;
                    mark2.emplace(o, 1);
                    stack.push_back(it->second);
                }
            }
            if ((int)tightened.size() >= std::max(minTris, kRansacMinSupport))
                best.swap(tightened);
        };
        if (bestRms <= tol * kExactFitFraction)
            tighten(bestFit.kind, bestFit.q);

        /* Refit on everything it claimed, and keep it only if it still holds. */
        std::vector<int> claimed;
        claimed.reserve(best.size());
        for (int i : best)
            claimed.push_back(tris[i]);
        PatchPoints(m, claimed, pd, 4000);
        Patch pa;
        pa.tris = claimed;
        pa.origin = origin;
        pa.fit = FitPatch(pd, tol, scale);
        /* EXACT, not merely within tolerance.
         *
         * RANSAC is being asked to find a surface inside a patch that fitted
         * nothing, and it will always find something: four triangles of an
         * organic shell fit a plane, six fit a sphere, and with a small enough
         * seed it can propose one anywhere. Held to the ordinary residual bar
         * it carved a smooth 2676-triangle shell into 129 invented planes and
         * three spheres — the "179 surfaces that met nowhere" failure, back
         * again from the other end.
         *
         * A tessellation puts its vertices ON the surface it came from, so a
         * surface that is really there is recovered to zero and one that is
         * merely nearby is not. That is the whole difference between a
         * downloaded CAD model, where this pass should find every fillet, and
         * an organic one, where it should find nothing at all. */
        if (pa.fit.kind == kNone || pa.fit.rms > tol * kExactFitFraction ||
            !Identifiable(pa, m, tol, true)) {
            /* Before giving up on this seed, re-claim TIGHTLY and refit.
             *
             * A claim made at tolerance is a claim made five hundred times
             * looser than a tessellated model's own vertices, so on a narrow
             * blend it runs straight past the point where the blend stops
             * being a cylinder and becomes a torus, and the mixture fits
             * nothing. The seed itself was fitted to a handful of triangles
             * and is usually a real local surface — measured on the user's
             * part, thirteen rounds in a row proposed one and had its claim
             * spoiled this way — so re-claim around the SEED at the mesh's own
             * precision, and failing that around the refit. */
            for (int attempt = 0; attempt < 2; ++attempt) {
                const double *q = attempt == 0 ? bestFit.q : pa.fit.q;
                const SurfKind kind = attempt == 0 ? bestFit.kind : pa.fit.kind;
                if (kind == kNone)
                    continue;
                const size_t was = best.size();
                tighten(kind, q);
                if (best.size() == was)
                    continue;
                claimed.clear();
                for (int i : best)
                    claimed.push_back(tris[i]);
                PatchPoints(m, claimed, pd, 4000);
                pa.tris = claimed;
                pa.fit = FitPatch(pd, tol, scale);
                if (pa.fit.kind != kNone &&
                    pa.fit.rms <= tol * kExactFitFraction &&
                    Identifiable(pa, m, tol, true))
                    break;
            }
        }
        if (pa.fit.kind == kNone || pa.fit.rms > tol * kExactFitFraction ||
            !Identifiable(pa, m, tol, true)) {
            /* A proposal that does not survive its refit is not the end of the
             * search — it only means this seed was a bad one. Bar its
             * triangles from seeding again (or the same winner comes back
             * every round) and carry on; they stay claimable by anything else
             * and otherwise fall through to the leftover. Stopping here
             * instead left two thirds of the user's part unexplained. */
            MR_TRACE("        -> refit %s rms %.6f rejected, reseeding\n",
                     KindName(pa.fit.kind), pa.fit.rms);
            bool anyNew = false;
            for (int i : best)
                if (!barred[i]) {
                    barred[i] = 1;
                    anyNew = true;
                }
            if (!anyNew)
                break;
            continue;
        }
        out.push_back(pa);
        for (int i : best) {
            taken[i] = 1;
            remaining--;
        }
        /* A seed that led nowhere may lead somewhere now: taking a surface out
         * changes what its neighbours are next to, and the claim that ran past
         * a transition last time may stop at it this time. */
        std::fill(barred.begin(), barred.end(), 0);
    }
    /* Sweep the leftovers into the surfaces already found.
     *
     * What RANSAC leaves behind is rarely a surface of its own — it is the
     * fringe of one it already has, dropped because a claim stopped a row
     * short or a seed was barred. A triangle lying EXACTLY on a surface this
     * patch is already known to contain belongs to it, and taking it there is
     * both more accurate and one seam fewer than emitting it as loose
     * triangles. Held to the mesh's own precision, not to tolerance, so
     * nothing is dragged across a tangency. */
    if (out.size() > before) {
        const double tight = std::max(tol * kExactFitFraction, scale * 1e-6);
        std::vector<int> owner(n, -1);
        for (size_t p = before; p < out.size(); ++p)
            for (int t : out[p].tris) {
                auto it = local.find(t);
                if (it != local.end())
                    owner[it->second] = static_cast<int>(p);
            }
        bool moved = true;
        while (moved) {
            moved = false;
            for (int i = 0; i < n; ++i) {
                if (taken[i])
                    continue;
                const int t = tris[i];
                int into = -1;
                for (int k = 0; k < 3 && into < 0; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || owner[it->second] < 0)
                        continue;
                    const Fit &f = out[owner[it->second]].fit;
                    bool ok = true;
                    for (int v = 0; v < 3 && ok; ++v)
                        if (std::fabs(SurfDist(f.kind, f.q,
                                               m.pos[m.tri[t * 3 + v]])) >
                            tight)
                            ok = false;
                    if (ok) {
                        const V3 sn =
                            SurfNormal(f.kind, f.q, m.pos[m.tri[t * 3]],
                                       std::max(scale * 1e-5, 1e-9));
                        if (Norm(sn) > 0.5 &&
                            std::fabs(Dot(sn, m.tnorm[t])) < kRansacNormalGate)
                            ok = false;
                    }
                    if (ok) {
                        double bar = 0;
                        if (FacetBulge(f.kind, f.q, m, t, bar) >
                            std::max(bar, tol))
                            ok = false;
                    }
                    if (ok)
                        into = owner[it->second];
                }
                if (into >= 0) {
                    out[into].tris.push_back(t);
                    owner[i] = into;
                    taken[i] = 1;
                    moved = true;
                }
            }
        }
    }

    for (int i = 0; i < n; ++i)
        if (!taken[i])
            leftover.push_back(tris[i]);
}

/* Splits a patch that fits nothing: crease first, running fit second.
 *
 * Cutting at a crease is both cheaper and more reliable than growing across
 * one, so it is tried first and recursed into; SplitByFit then handles what is
 * left, which is the tangent case it was written for. */
void SplitPatch(const Mesh &m, const std::vector<int> &tris, double tol,
                double scale, int minTris, int origin, int depth,
                std::vector<Patch> &out)
{
    PatchData pd;
    PatchPoints(m, tris, pd, 4000);
    Patch pa;
    pa.tris = tris;
    pa.origin = origin;
    pa.fit = FitPatch(pd, tol, scale);
    if (pa.fit.kind != kNone || static_cast<int>(tris.size()) < minTris * 4) {
        out.push_back(pa);
        return;
    }
    MR_TRACE("    split %d tri (depth %d): fit %s\n", (int)tris.size(), depth,
             KindName(pa.fit.kind));
    if (depth < kMaxCreaseDepth) {
        std::vector<std::vector<int>> parts;
        if (SplitAtCrease(m, tris, minTris, parts)) {
#ifdef MESHRECON_TRACE
            MR_TRACE("      crease ->");
            for (const std::vector<int> &pp : parts)
                MR_TRACE(" %d", (int)pp.size());
            MR_TRACE("\n");
#endif
            for (const std::vector<int> &pp : parts)
                SplitPatch(m, pp, tol, scale, minTris, origin, depth + 1, out);
            return;
        }
    }
    /* Propose-and-score before grow-and-hope. RANSAC takes the surfaces the
     * mesh actually supports; SplitByFit then works on what is left, which is
     * the tangent-blend case it was written for and is good at. */
    const size_t before = out.size();
    std::vector<int> rest;
    SplitByRansac(m, tris, tol, scale, minTris, origin, out, rest);
    MR_TRACE("      ransac %d tri -> %d surfaces, %d left\n", (int)tris.size(),
             (int)(out.size() - before), (int)rest.size());
    if (rest.empty())
        return;
    if (rest.size() < tris.size()) {
        /* Something was recognised; the remainder is a smaller problem and
         * gets the same treatment, but without recursing on RANSAC again. */
        SplitByFit(m, rest, tol, scale, minTris, origin, out);
        if (out.size() == before)
            out.push_back(pa);
        return;
    }
    SplitByFit(m, tris, tol, scale, minTris, origin, out);
    if (out.size() == before)
        out.push_back(pa);
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
/* Which smooth runs are FREEFORM rather than prismatic.
 *
 * Asked once per run, not once per piece, because the splitter always
 * succeeds: a quad of a quad-meshed surface is exactly planar, so a plane
 * through it has no residual at all and passes every per-piece test there is —
 * correctly, since two triangles really is a box's face. On a 2676-triangle
 * organic shell that produced 129 invented planes and 3 spheres, none of which
 * exists.
 *
 * What separates them is the run. A prismatic run is ACCOUNTED FOR: its pieces
 * are faces and they cover it. A freeform run is not — most of it fits nothing
 * and what does fit is facet-sized. A plate's side band, four fillets and four
 * walls, is covered to the last triangle and is never touched.
 *
 * It is worth knowing EARLY as well as late. Everything downstream of
 * segmentation — merging pairs, refining boundaries, building faces — is
 * per-patch work on a run that is about to be thrown away whole, and on an
 * organic model that is nearly all of the time the conversion takes: 3.5
 * seconds of merging on a 3480-triangle blob, against 0.4 for the faceted
 * build that is the eventual answer. */
void FreeformRuns(const std::vector<Patch> &patches, const Mesh &m, double tol,
                  std::unordered_set<int> &freeform)
{
    freeform.clear();
    std::unordered_map<int, int> cutInto;
    for (const Patch &pa : patches)
        cutInto[pa.origin]++;
    std::unordered_map<int, std::pair<int, int>> cover; /* kept, total */
    std::unordered_map<int, std::vector<int>> keptSizes;
    for (const Patch &pa : patches) {
        if (pa.origin < 0)
            continue;
        std::pair<int, int> &c = cover[pa.origin];
        c.second += static_cast<int>(pa.tris.size());
        const bool frag = cutInto[pa.origin] > 1;
        const bool id = pa.fit.kind != kNone && Identifiable(pa, m, tol, frag);
        if (pa.tris.size() >= 8)
            MR_TRACE("     run %d piece %4d tri %-7s rms %.6f -> %s (%s)\n",
                     pa.origin, (int)pa.tris.size(), KindName(pa.fit.kind),
                     pa.fit.rms, id ? "keep" : "drop",
#ifdef MESHRECON_TRACE
                     g_why
#else
                     ""
#endif
            );
        if (id) {
            c.first += static_cast<int>(pa.tris.size());
            keptSizes[pa.origin].push_back(static_cast<int>(pa.tris.size()));
        }
    }
    for (std::unordered_map<int, std::pair<int, int>>::iterator it =
             cover.begin();
         it != cover.end(); ++it) {
        const int kept = it->second.first, total = it->second.second;
        if (total < kFreeformMinRun || kept * 2 >= total)
            continue;
        std::vector<int> &sz = keptSizes[it->first];
        if (sz.empty()) {
            freeform.insert(it->first);
            continue;
        }
        /* Barely accounted for at all: freeform whatever the pieces look like.
         * A run that is 98% triangles is not a set of faces with a few gaps,
         * and the two or three surfaces standing in it are worth less than the
         * seams they cost. */
        if (kept * kFreeformCoverDenom < total) {
            freeform.insert(it->first);
            continue;
        }
        /* And most of what IS explained has to be scraps.
         *
         * The median piece size looked like the right statistic and is not: a
         * run can be mostly triangles and still contain one real face, and
         * then the median is dominated by the scraps beside it. On the user's
         * part the blend ring round the boss on the underside — a torus, 87
         * triangles, residual zero — shared its run with sixteen one-triangle
         * offcuts, so the median said "facet-sized" and the whole run, ring
         * included, went to triangles. Weigh by triangles instead: 87 of the
         * 106 explained are that one ring, so the run is not scrap. */
        int scrap = 0;
        for (int x : sz)
            if (x < kFreeformPieceTriangles)
                scrap += x;
        if (scrap * 2 > kept)
            freeform.insert(it->first);
    }
    MR_TRACE("  [freeform] %d of %d runs\n", (int)freeform.size(),
             (int)cover.size());
    for (std::unordered_map<int, std::pair<int, int>>::iterator it =
             cover.begin();
         it != cover.end(); ++it)
        MR_TRACE("     run %d: kept %d of %d in %d pieces%s\n", it->first,
                 it->second.first, it->second.second,
                 (int)keptSizes[it->first].size(),
                 freeform.count(it->first) ? "  FREEFORM" : "");
}

void MergeRegions(const Mesh &m, std::vector<Patch> &patches, double tol,
                  double scale, int maxPasses,
                  const std::unordered_set<int> &skipOrigins)
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
            /* And nothing at all inside a run already judged freeform: every
             * pair there costs a full five-kind fit and every one of them
             * fails. */
            if (skipOrigins.find(patches[a].origin) != skipOrigins.end())
                continue;
            uni.clear();
            uni.reserve(patches[a].tris.size() + patches[b].tris.size());
            uni.insert(uni.end(), patches[a].tris.begin(),
                       patches[a].tris.end());
            uni.insert(uni.end(), patches[b].tris.begin(),
                       patches[b].tris.end());
            PatchPoints(m, uni, pd, 4000);
            const Fit f = FitPatch(pd, tol, scale);
            MR_TRACE("  merge? %d(%s,%d) + %d(%s,%d) -> %s rms %.5f agree "
                     "%.4f (tol %.5f)\n",
                     a, KindName(patches[a].fit.kind),
                     (int)patches[a].tris.size(), b,
                     KindName(patches[b].fit.kind),
                     (int)patches[b].tris.size(), KindName(f.kind), f.rms,
                     f.agree, tol);
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
            /* An EXACT merged fit is believed on its residual instead.
             *
             * The normal gate is a proxy for "is this really one surface", and
             * it is the right proxy when the fit is approximate. When the fit
             * is exact it is the weaker evidence of the two, and it says no to
             * things that are plainly true: two adjacent rows of a boss's
             * fillet ring merged into a torus at residual 0.0000000 — the
             * fillet, exactly — with mean normal agreement 0.9872, and were
             * kept apart by a bar of 0.99. Their coarse facet normals cannot
             * agree better than that; the surface underneath them is still the
             * torus. The facet test below is what keeps this honest. */
            const bool mergedExact = f.rms <= tol * kExactFitFraction;
            if (!mergedExact && f.agree < kMergeNormalGate)
                continue;
            /* Merging two surfaces that were each already RECOGNISED must not
             * make the fit worse than either of them was.
             *
             * The pass exists to reunite one surface that the splitter cut in
             * two, and there the union fits exactly, because both halves did.
             * When it instead joins two DIFFERENT surfaces the union fits only
             * loosely — and loosely is still inside tolerance, which is why
             * the residual gate alone let it through. Measured: an r=5 corner
             * fillet (32 triangles, cylinder, residual zero) merged with the
             * two triangles of the flat wall it is tangent to (plane, residual
             * zero) and came back as a torus at 0.0102, wrapped around a major
             * radius of 15 mm that is nowhere in the part; trimmed, it added
             * 42% to the model's volume. Neither half was improved by the
             * merge, and that is exactly what the test should say.
             *
             * A patch that fitted NOTHING has nothing to lose, so the repair
             * case this pass was written for is untouched. */
            /* And the merged surface must pass through the FACETS of both,
             * not merely their vertices — the same test the fitter and RANSAC
             * apply, and for the same reason: this is where a torus threaded
             * through a fillet and the flat wall beside it gives itself away. */
            {
                bool bulges = false;
                const int st = std::max<int>(1, (int)uni.size() / 256);
                for (size_t i = 0; i < uni.size() && !bulges; i += st) {
                    double bar = 0;
                    if (FacetBulge(f.kind, f.q, m, uni[i], bar) >
                        std::max(bar, tol))
                        bulges = true;
                }
                if (bulges)
                    continue;
            }
            if (patches[a].fit.kind != kNone && patches[b].fit.kind != kNone) {
                const double worse =
                    std::max(patches[a].fit.rms, patches[b].fit.rms);
                if (f.rms > std::max(worse, tol * kExactFitFraction))
                    continue;
            }
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
    /* One straight edge per MESH edge, keyed on its two vertex ids. Shared by
     * every faceted triangle that uses it, so triangles are sewn to each other
     * by construction rather than by geometric search afterwards. */
    std::unordered_map<long long, TopoDS_Edge> meshEdges;
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

/* Reads a quadric's axis and size, for the degeneracy test below. */
struct Quadric
{
    int kind = -1; /* 0 plane, 1 cylinder, 2 cone, 3 sphere, 4 torus */
    gp_Pnt loc;
    gp_Dir dir;
    double size = 0; /* radius, or a cone's semi-angle */
};

bool ReadQuadric(const Handle(Geom_Surface) & s, Quadric &q)
{
    if (Handle(Geom_Plane) x = Handle(Geom_Plane)::DownCast(s)) {
        q.kind = 0;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        return true;
    }
    if (Handle(Geom_CylindricalSurface) x =
            Handle(Geom_CylindricalSurface)::DownCast(s)) {
        q.kind = 1;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->Radius();
        return true;
    }
    if (Handle(Geom_ConicalSurface) x =
            Handle(Geom_ConicalSurface)::DownCast(s)) {
        q.kind = 2;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->SemiAngle();
        return true;
    }
    if (Handle(Geom_SphericalSurface) x =
            Handle(Geom_SphericalSurface)::DownCast(s)) {
        q.kind = 3;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->Radius();
        return true;
    }
    if (Handle(Geom_ToroidalSurface) x =
            Handle(Geom_ToroidalSurface)::DownCast(s)) {
        q.kind = 4;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->MajorRadius();
        return true;
    }
    return false;
}

/* Which surface pairs are safe to hand to GeomAPI_IntSS.
 *
 * IntSS has no time bound, and OCCT's implicit-implicit intersector can grind
 * on a quadric pair indefinitely — two parallel cylinders whose axes are a
 * millimetre apart took over ninety seconds on a 444-triangle mesh and had not
 * finished. On an iPad that is not a slow conversion; it is a frozen app the
 * watchdog kills, indistinguishable from the crash this same file already cost
 * a day to find. There is no way to interrupt it once it is running, so the
 * only safe bound is on what goes in.
 *
 * Two cases carry essentially all the value, and both are the well-trodden
 * paths in OCCT:
 *
 *   - a PLANE against anything, including another plane. This is the hole rim,
 *     the cap edge, the box edge, the flat a boss stands on — a circle or a
 *     line, exactly, and OCCT solves it in closed form.
 *   - two COAXIAL quadrics of different kinds: a cylinder into a cone is the
 *     rim of a countersunk hole, a cylinder into a torus the rim of a filleted
 *     one. Also a circle, exactly.
 *
 * Everything else — two cylinders crossing, a cone against a sphere — meets in
 * a curve of degree four that OCCT would hand back approximated anyway, so the
 * polyline fallback loses nothing that was ever exact. Coaxial pairs of the
 * SAME kind are refused outright: they meet nowhere or everywhere. */
bool IntersectablePair(const Handle(Geom_Surface) & s1,
                       const Handle(Geom_Surface) & s2, double tol)
{
    Quadric a, b;
    if (!ReadQuadric(s1, a) || !ReadQuadric(s2, b))
        return false;
    const double cosPar = 1.0 - 1e-7;
    if (a.kind == 0 && b.kind == 0) /* parallel planes meet nowhere */
        return std::fabs(a.dir.Dot(b.dir)) <= cosPar;
    if (a.kind == 0 || b.kind == 0)
        return true;
    /* Same axis LINE, not merely the same direction. */
    if (std::fabs(a.dir.Dot(b.dir)) <= cosPar)
        return false;
    if (a.kind == b.kind)
        return false;
    const gp_Vec off(a.loc, b.loc);
    const double along = off.Dot(gp_Vec(a.dir));
    const double perp2 = off.SquareMagnitude() - along * along;
    const double gap = perp2 > 0 ? std::sqrt(perp2) : 0.0;
    return gap <= tol;
}

/* The exact intersection curve of two analytic surfaces, when there is one
 * that follows this chain. Null otherwise.
 *
 * This is the whole quality argument for the prismatic path: a hole's rim
 * comes out a real gp_Circ, so a fillet on it later has a circle to roll along
 * and a STEP export carries a circle rather than a 200-segment spline. */
/* The circle where a fillet TOUCHES what it blends into.
 *
 * A fillet meets its neighbours tangentially — that is what a fillet is — and
 * a tangential contact is the one case a general surface intersector cannot
 * do: the two surfaces do not cross, they graze, and the system is singular
 * exactly along the answer. GeomAPI_IntSS returns nothing, the edge falls back
 * to the polyline through the mesh vertices, and the fillet's own face keeps
 * the true circle. Measured on a boss fillet ring: the torus side carried a
 * circle of circumference 65.973 and the plate top an inscribed polygon of
 * 64.529, half a millimetre apart at the middle of every segment, and the
 * shell stayed open along that one seam — 2 free edges out of 45.
 *
 * But a fillet's contacts are not general intersections at all, they are
 * known: a torus is touched by the plane perpendicular to its axis at exactly
 * its minor radius, in the circle of its MAJOR radius; and by the coaxial
 * cylinder of radius R+r or R-r, in the circle of that radius. Both are
 * closed-form, both are exact, and both are checked against the chain before
 * being believed. */
Handle(Geom_Curve) TangentContact(const Handle(Geom_Surface) & s1,
                                  const Handle(Geom_Surface) & s2, double tol)
{
    Handle(Geom_ToroidalSurface) tor =
        Handle(Geom_ToroidalSurface)::DownCast(s1);
    Handle(Geom_Surface) other = s2;
    if (tor.IsNull()) {
        tor = Handle(Geom_ToroidalSurface)::DownCast(s2);
        other = s1;
    }
    if (tor.IsNull())
        return nullptr;
    const gp_Pnt c = tor->Position().Location();
    const gp_Dir d = tor->Position().Direction();
    const double R = tor->MajorRadius(), r = tor->MinorRadius();
    const double cosPar = 1.0 - 1e-7;

    if (Handle(Geom_Plane) pl = Handle(Geom_Plane)::DownCast(other)) {
        if (std::fabs(pl->Position().Direction().Dot(d)) < cosPar)
            return nullptr;
        const double h =
            gp_Vec(c, pl->Position().Location()).Dot(gp_Vec(d));
        if (std::fabs(std::fabs(h) - r) > tol)
            return nullptr;
        return new Geom_Circle(gp_Ax2(c.Translated(gp_Vec(d) * h), d), R);
    }
    if (Handle(Geom_CylindricalSurface) cy =
            Handle(Geom_CylindricalSurface)::DownCast(other)) {
        if (std::fabs(cy->Position().Direction().Dot(d)) < cosPar)
            return nullptr;
        /* The same axis LINE, not merely the same direction. */
        const gp_Vec off(c, cy->Position().Location());
        const double along = off.Dot(gp_Vec(d));
        const double perp2 = off.SquareMagnitude() - along * along;
        if (perp2 > tol * tol)
            return nullptr;
        const double cr = cy->Radius();
        double want = 0;
        if (std::fabs(cr - (R + r)) <= tol)
            want = R + r;
        else if (R > r && std::fabs(cr - (R - r)) <= tol)
            want = R - r;
        else
            return nullptr;
        return new Geom_Circle(gp_Ax2(c, d), want);
    }
    return nullptr;
}

Handle(Geom_Curve) IntersectionCurve(const Handle(Geom_Surface) & s1,
                                     const Handle(Geom_Surface) & s2,
                                     const std::vector<gp_Pnt> &pts, double tol)
{
    if (s1.IsNull() || s2.IsNull())
        return nullptr;
    /* A grazing contact first: the intersector cannot find it and it has a
     * closed form. Believed only if the chain really is on it. */
    if (Handle(Geom_Curve) t = TangentContact(s1, s2, tol)) {
        bool on = true;
        try {
            for (size_t k = 0; k < pts.size() && on;
                 k += std::max<size_t>(1, pts.size() / 6)) {
                GeomAPI_ProjectPointOnCurve pp(pts[k], t);
                if (pp.NbPoints() < 1 || pp.LowerDistance() > tol * 3)
                    on = false;
            }
        } catch (const Standard_Failure &) {
            on = false;
        }
        if (on)
            return t;
    }
    if (!IntersectablePair(s1, s2, tol))
        return nullptr;
    /* And the chain has to be ON both surfaces before it is worth asking where
     * they meet: if it is not, whatever curve comes back is not this edge, and
     * the check costs a handful of projections against an intersection that can
     * cost everything. */
    try {
        for (size_t k = 0; k < pts.size();
             k += std::max<size_t>(1, pts.size() / 4)) {
            GeomAPI_ProjectPointOnSurf p1(pts[k], s1);
            if (!p1.IsDone() || p1.NbPoints() < 1 ||
                p1.LowerDistance() > tol * 3)
                return nullptr;
            GeomAPI_ProjectPointOnSurf p2(pts[k], s2);
            if (!p2.IsDone() || p2.NbPoints() < 1 ||
                p2.LowerDistance() > tol * 3)
                return nullptr;
        }
    } catch (const Standard_Failure &) {
        return nullptr;
    }
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

    /* Whether the far side of this chain is triangles rather than a surface.
     *
     * An edge is ONE curve and both faces either side must agree on it. Where
     * the neighbour is faceted, the triangles' chords are what it agrees to,
     * so nothing smoother may be used here however exact it is on this side —
     * a hole's rim came back a true circle while the shell beside it was the
     * inscribed polygon, and a coarse mesh's sagitta is wider than any sewing
     * tolerance. That left the four holes recognised and the shell unsewn
     * round every one of them. The cylinder is still a cylinder of radius
     * exactly 2; only its RIM gives up being a conic, and only where it meets
     * triangles. Between two fitted faces the exact conic still wins. */
    const bool neighbourFaceted =
        c.other < 0 || c.other >= static_cast<int>(surfs.size()) ||
        surfs[c.other].IsNull();

    /* 1 — the exact curve where two analytic surfaces meet. */
    if (!neighbourFaceted && !selfSurf.IsNull()) {
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

    /* 3a — the POLYLINE, when the other side of this chain is triangles.
     *
     * A fitted face and a faceted region have to meet along the same curve or
     * the shell does not sew, and the two disagree by construction: the spline
     * below is an APPROXIMATION within tolerance, while the triangles use the
     * straight chords between the very same vertices. On a coarse mesh that
     * gap is bigger than the sewing tolerance, and the result is a model with
     * its holes recognised and a seam round every one of them.
     *
     * Where the neighbour is faceted, the chords ARE the truth. A degree-one
     * B-spline through the chain is exactly them. */
    if (e.IsNull() && neighbourFaceted && pts.size() >= 3) {
        try {
            const int n = static_cast<int>(pts.size());
            TColgp_Array1OfPnt poles(1, n);
            for (int i = 0; i < n; ++i)
                poles.SetValue(i + 1, pts[i]);
            TColStd_Array1OfReal knots(1, n);
            TColStd_Array1OfInteger mult(1, n);
            for (int i = 0; i < n; ++i) {
                knots.SetValue(i + 1, i);
                mult.SetValue(i + 1, 1);
            }
            mult.SetValue(1, 2);
            mult.SetValue(n, 2);
            Handle(Geom_BSplineCurve) poly =
                new Geom_BSplineCurve(poles, knots, mult, 1);
            BRepBuilderAPI_MakeEdge me(poly, VertexAt(ctx, c.verts.front()),
                                       VertexAt(ctx, c.verts.back()),
                                       poly->FirstParameter(),
                                       poly->LastParameter());
            if (me.IsDone()) {
                e = me.Edge();
                ctx.approximated++;
            }
        } catch (const Standard_Failure &) {
            e = TopoDS_Edge();
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
/* A face has to stay inside the triangles it was built from.
 *
 * The wires come from mesh vertices, so a well-built face is within a facet's
 * sagitta of its own patch. One that is not has lost its trimming — a plane
 * whose wire failed to bound it is INFINITE, and an infinite plane in a shell
 * is not a slightly wrong face, it is a black shard across the model with
 * edges running off to the horizon and a bounding box that grows every time
 * the viewer re-tessellates it. That is exactly what a real organic download
 * produced: faces reaching nearly three times the whole model's diagonal
 * outside it.
 *
 * The patch's own triangles are the honest bound, and the margin is generous
 * by two orders of magnitude against what a broken face does, so this cannot
 * refuse a face that is merely imperfect. */
bool FaceWithinPatch(const TopoDS_Face &face, const Mesh &m,
                     const std::vector<int> &tris, double tol)
{
    if (tris.empty())
        return false;
    V3 lo(1e300, 1e300, 1e300), hi(-1e300, -1e300, -1e300);
    for (int t : tris) {
        for (int k = 0; k < 3; ++k) {
            const V3 &p = m.pos[m.tri[t * 3 + k]];
            lo.x = std::min(lo.x, p.x);
            lo.y = std::min(lo.y, p.y);
            lo.z = std::min(lo.z, p.z);
            hi.x = std::max(hi.x, p.x);
            hi.y = std::max(hi.y, p.y);
            hi.z = std::max(hi.z, p.z);
        }
    }
    const double slack = std::max(tol * 8.0, Norm(hi - lo) * 0.08);
    /* Two boxes, cheap first.
     *
     * BRepBndLib::Add boxes a face by its pcurves' POLES, so it never
     * UNDERstates the face — if that box is inside the patch, the face
     * certainly is, and on a model that is behaving this is the only box ever
     * computed. It does overstate: a B-spline's control polygon stands well
     * outside the curve, which on a plate's end cap read as 1.7 mm of
     * overshoot on a face that was exactly right. So a failure there is not a
     * verdict, only a reason to pay for AddOptimal, which evaluates the curves
     * instead of trusting their hulls. */
    auto inside = [&](const Bnd_Box &b) {
        if (b.IsVoid() || b.IsWhole() || b.IsOpenXmin() || b.IsOpenXmax() ||
            b.IsOpenYmin() || b.IsOpenYmax() || b.IsOpenZmin() || b.IsOpenZmax())
            return false;
        Standard_Real x0, y0, z0, x1, y1, z1;
        b.Get(x0, y0, z0, x1, y1, z1);
        const double v[6] = {x0, y0, z0, x1, y1, z1};
        for (int k = 0; k < 6; ++k)
            if (!(v[k] > -1e99 && v[k] < 1e99))
                return false;
        return x0 >= lo.x - slack && y0 >= lo.y - slack && z0 >= lo.z - slack &&
               x1 <= hi.x + slack && y1 <= hi.y + slack && z1 <= hi.z + slack;
    };
    try {
        Bnd_Box quick;
        BRepBndLib::Add(face, quick, Standard_False);
        if (inside(quick))
            return true;
        Bnd_Box tight;
        BRepBndLib::AddOptimal(face, tight, Standard_False, Standard_False);
        return inside(tight);
    } catch (const Standard_Failure &) {
        return false;
    }
}

/* One face per triangle, sharing this build's vertices and mesh edges.
 *
 * Loose triangles have to be re-matched to each other by BRepBuilderAPI_Sewing
 * afterwards, and on a hybrid model that left the shell open where one faceted
 * region met another — a model with its holes recognised and a split down its
 * side. Sharing the edge makes those seams exact rather than approximate, and
 * it costs nothing: the mesh already knows which triangles share which edge. */
void EmitFacetedShared(BuildCtx &ctx, const Mesh &m,
                       const std::vector<int> &tris,
                       std::vector<TopoDS_Face> &out)
{
    BRep_Builder bb;
    const long long n = m.vertCount();
    auto edgeFor = [&](int a, int b) {
        const int lo = std::min(a, b), hi = std::max(a, b);
        const long long key = (long long)lo * n + hi;
        auto it = ctx.meshEdges.find(key);
        if (it != ctx.meshEdges.end())
            return it->second;
        const TopoDS_Edge e =
            BRepBuilderAPI_MakeEdge(VertexAt(ctx, lo), VertexAt(ctx, hi));
        ctx.meshEdges.emplace(key, e);
        return e;
    };
    for (int t : tris) {
        try {
            const int v[3] = {m.tri[t * 3], m.tri[t * 3 + 1], m.tri[t * 3 + 2]};
            TopoDS_Wire w;
            bb.MakeWire(w);
            for (int k = 0; k < 3; ++k) {
                const int a = v[k], b = v[(k + 1) % 3];
                const TopoDS_Edge e = edgeFor(a, b);
                bb.Add(w, TopoDS::Edge(e.Oriented(
                              a < b ? TopAbs_FORWARD : TopAbs_REVERSED)));
            }
            BRepBuilderAPI_MakeFace mf(w, Standard_True);
            if (!mf.IsDone())
                continue;
            TopoDS_Face f = mf.Face();
            const Handle(Geom_Plane) pl =
                Handle(Geom_Plane)::DownCast(BRep_Tool::Surface(f));
            if (!pl.IsNull()) {
                const gp_Dir d = pl->Position().Direction();
                V3 nn(d.X(), d.Y(), d.Z());
                if (f.Orientation() == TopAbs_REVERSED)
                    nn = V3(-nn.x, -nn.y, -nn.z);
                if (Dot(nn, m.tnorm[t]) < 0)
                    f.Reverse();
            }
            out.push_back(f);
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
    /* A boundary that goes all the way ROUND a periodic surface does not say
     * which side of itself the face is on.
     *
     * Two circles round a torus bound the ninety-degree band between them and
     * equally the two-hundred-and-seventy-degree band the other way, and
     * MakeFace picks by the surface's own parametrisation rather than by the
     * mesh. On the user's part the blend ring round the boss came back as
     * three quarters of its tube — a face of area 535 where the ring is 160,
     * ballooning out of the model and adding fifteen percent to its volume.
     * The mesh knows which band it is: MeasureUv reads the extent off the
     * triangles. So whenever a direction comes back FULL, trim
     * parametrically and do not ask MakeFace to guess. */
    if (surf->IsUPeriodic() || surf->IsVPeriodic()) {
        const UvExtent e = MeasureUv(m, patch.tris, surf);
        MR_TRACE("      periodic: uv ok=%d u[%.3f %.3f]%s v[%.3f %.3f]%s\n",
                 (int)e.ok, e.u1, e.u2, e.uFull ? " FULL" : "", e.v1, e.v2,
                 e.vFull ? " FULL" : "");
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
            /* Against a FACETED neighbour, walk the mesh edges one by one and
             * take the very objects the triangles are using.
             *
             * A single edge spanning the whole chain is geometrically the same
             * polyline, and it still will not sew: the far side has one edge
             * per triangle and OCCT is left to reconcile one long curve with a
             * dozen short ones. Sharing them removes the reconciliation
             * entirely — this is what took the last 26 open edges out of a
             * hybrid shell and turned it into a solid. */
            const bool faceted =
                c.other < 0 || c.other >= static_cast<int>(surfs.size()) ||
                surfs[c.other].IsNull();
            std::vector<TopoDS_Edge> segs;
            if (faceted && c.verts.size() >= 2) {
                const long long nv = ctx.m->vertCount();
                for (size_t i = 0; i + 1 < c.verts.size(); ++i) {
                    const int a = c.verts[i], b = c.verts[i + 1];
                    if (a == b)
                        continue;
                    const int lo = std::min(a, b), hi = std::max(a, b);
                    const long long key = (long long)lo * nv + hi;
                    auto it = ctx.meshEdges.find(key);
                    TopoDS_Edge me;
                    if (it != ctx.meshEdges.end()) {
                        me = it->second;
                    } else {
                        try {
                            BRepBuilderAPI_MakeEdge mk(VertexAt(ctx, lo),
                                                       VertexAt(ctx, hi));
                            if (mk.IsDone()) {
                                me = mk.Edge();
                                ctx.meshEdges.emplace(key, me);
                            }
                        } catch (const Standard_Failure &) {
                        }
                    }
                    if (me.IsNull()) {
                        segs.clear();
                        break;
                    }
                    segs.push_back(TopoDS::Edge(me.Oriented(
                        a < b ? TopAbs_FORWARD : TopAbs_REVERSED)));
                }
            }
            if (segs.empty()) {
                const TopoDS_Edge e = ChainEdge(ctx, c, self, surf, surfs);
                if (e.IsNull()) {
                    ok = false;
                    break;
                }
                segs.push_back(e);
            } else {
                ctx.approximated++;
            }
            for (const TopoDS_Edge &e : segs) {
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
            if (!ok)
                break;
        }
        if (!ok || !mw.IsDone()) {
            MR_TRACE("      face %d: wire of %d chains failed\n", self,
                     (int)chains.size());
            /* A boundary that will not close is not a reason to throw the
             * SURFACE away — but nor may the loop simply be dropped, because
             * an inner rim left out is a hole not cut and the face then
             * covers it (measured: +194% volume, and no solid). On a periodic
             * surface the mesh's own uv extent trims it honestly instead,
             * which is how a recognised blend ring stays a blend ring when a
             * neighbouring patch leaves a nick in its edge. FaceWithinPatch
             * has the last word on anything that overreaches, and sends it to
             * triangles as before. */
            if (surf->IsUPeriodic() || surf->IsVPeriodic())
                return BuildParametricFace(ctx, m, patch, surf, out);
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

        /* Give the edges their pcurves IN PLACE, before anything is allowed to
         * rebuild them.
         *
         * ShapeFix_Face::Perform heals a face by making a new one, and the new
         * one has new edges. That is right for a face assembled from loose
         * geometry and ruinous here: these wires are built from the very
         * TopoDS_Edge objects the triangles beside them are using, which is
         * what lets a fitted face and a faceted region be sewn already rather
         * than reconciled afterwards. Measured on a curved shell with four
         * drilled holes: 719 of 3379 edges belonged to one face only after
         * Perform, and 29 of 3030 without it. ShapeFix_Edge adds the pcurve to
         * the edge that is there. */
        {
            Handle(ShapeFix_Edge) fe = new ShapeFix_Edge;
            for (TopExp_Explorer ex(face, TopAbs_EDGE); ex.More(); ex.Next()) {
                try {
                    fe->FixAddPCurve(TopoDS::Edge(ex.Current()), face,
                                     Standard_False, ctx.tol);
                } catch (const Standard_Failure &) {
                }
            }
        }
        Handle(ShapeFix_Face) fix = new ShapeFix_Face(face);
        /* The context is NOT optional, and leaving it out is what killed the
         * app on real models.
         *
         * ShapeFix_Face::Perform runs FixPeriodicDegenerated, which fires on a
         * CONICAL face whose single wire wraps the full 2*pi — a countersink, a
         * chamfered hole, a tapered boss: the commonest features there are in a
         * printed part. Every other Context() use in that file is guarded by
         * IsNull(); its last line is not:
         *
         *     myResult = aNewFace;
         *     Context()->Replace(myFace, myResult);   // ShapeFix_Face.cxx
         *
         * ShapeFix_Face, unlike ShapeFix_Shape and ShapeFix_Shell, never makes
         * a context of its own, so without this line that dereferences null and
         * takes the process down — no exception, nothing to catch, the app is
         * simply gone. Present in 7.6 and still present in the 7.9.3 we pin.
         * Giving it a context is also what ShapeFix_Shape does when it drives
         * this same tool, and it stops the null being handed further down to
         * ShapeFix_Wire, which never checks it at all. */
        fix->SetContext(new ShapeBuild_ReShape);
        fix->SetPrecision(ctx.tol);
        fix->SetMaxTolerance(ctx.tol * 100);
        fix->FixAddNaturalBoundMode() = Standard_False;
        /* Orientation only: sorting outer wire from inner, which does not
         * touch the edges. The full Perform is the thing that replaces them. */
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
TopoDS_Shape Solidify(const TopoDS_Shape &sewn, Report &rep);

/* Assembles faces that ALREADY share their edges into a shell, without sewing.
 *
 * BRepBuilderAPI_Sewing rebuilds the topology it is given: it takes the faces
 * apart and re-creates their edges by geometric search. That is exactly what
 * is wanted for a pile of loose faces and exactly wrong for these, which were
 * built sharing one TopoDS_Edge per boundary on purpose — the fitted faces
 * take their seams from the same pool the triangles use. Sewing threw that
 * away and then failed to rediscover it, leaving twenty-six edges open around
 * the holes of a model whose holes were otherwise perfect.
 *
 * Returns a null shape when the faces do NOT in fact close, so the caller can
 * fall back to sewing, which is still the right tool when they don't. */
TopoDS_Shape AssembleShell(const std::vector<TopoDS_Face> &faces)
{
    if (faces.empty())
        return TopoDS_Shape();
    BRep_Builder bb;
    TopoDS_Shell sh;
    bb.MakeShell(sh);
    for (const TopoDS_Face &f : faces)
        bb.Add(sh, f);
    /* Count USES, not neighbouring faces. A closed tube's seam edge is used
     * twice by the ONE face it belongs to, and an ancestor map — which lists
     * distinct faces — reads that as an edge with a single neighbour and calls
     * a perfectly closed shell open. */
    try {
        TopTools_DataMapOfShapeInteger uses;
        for (TopExp_Explorer fx(sh, TopAbs_FACE); fx.More(); fx.Next()) {
            for (TopExp_Explorer ex(fx.Current(), TopAbs_EDGE); ex.More();
                 ex.Next()) {
                const TopoDS_Shape &e = ex.Current();
                if (BRep_Tool::Degenerated(TopoDS::Edge(e)))
                    continue;
                if (uses.IsBound(e))
                    uses.ChangeFind(e) += 1;
                else
                    uses.Bind(e, 1);
            }
        }
        for (TopTools_DataMapIteratorOfDataMapOfShapeInteger it(uses); it.More();
             it.Next())
            if (it.Value() != 2)
                return TopoDS_Shape();
    } catch (const Standard_Failure &) {
        return TopoDS_Shape();
    }
    sh.Closed(Standard_True);
    return sh;
}

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

    return Solidify(sewn, rep);
}

/* Every closed shell becomes a solid; open ones are left as they are. A
 * compound of one solid is unwrapped, because the app's feature tree wants a
 * body, not a bag holding one. */
TopoDS_Shape Solidify(const TopoDS_Shape &sewn, Report &rep)
{
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

namespace {

/* One B-Rep face per triangle, built as a shell that is ALREADY sewn.
 *
 * The whole of mode 0, and the safety net under mode 1: it recognises nothing,
 * but on a watertight mesh it cannot fail either.
 *
 * The obvious way — make each triangle its own face and hand the pile to
 * BRepBuilderAPI_Sewing — asks OCCT to rediscover by geometric search over
 * every face the adjacency this file computed exactly in BuildAdjacency, and
 * it charges about a millisecond per triangle to do it: 43 seconds for 40 000
 * triangles, which on an iPad is the app gone. Sharing ONE vertex per welded
 * mesh vertex and ONE edge per mesh edge makes the shell sewn by construction,
 * needs no healing afterwards (the edges are identical, not merely close), and
 * is linear. */
TopoDS_Shape FacetedShell(const Mesh &m, int &faceCount)
{
    faceCount = 0;
    BRep_Builder bb;
    std::vector<TopoDS_Vertex> vs(m.vertCount());
    for (int i = 0; i < m.vertCount(); ++i)
        vs[i] = BRepBuilderAPI_MakeVertex(P(m.pos[i]));

    std::unordered_map<long long, TopoDS_Edge> edges;
    edges.reserve(m.tri.size());
    const long long n = m.vertCount();
    auto edgeFor = [&](int a, int b) {
        const int lo = std::min(a, b), hi = std::max(a, b);
        const long long key = (long long)lo * n + hi;
        auto it = edges.find(key);
        if (it != edges.end())
            return it->second;
        const TopoDS_Edge e = BRepBuilderAPI_MakeEdge(vs[lo], vs[hi]);
        edges.emplace(key, e);
        return e;
    };

    TopoDS_Shell shell;
    bb.MakeShell(shell);
    for (int t = 0; t < m.triCount(); ++t) {
        try {
            const int v[3] = {m.tri[t * 3], m.tri[t * 3 + 1], m.tri[t * 3 + 2]};
            TopoDS_Wire w;
            bb.MakeWire(w);
            for (int k = 0; k < 3; ++k) {
                const int a = v[k], b = v[(k + 1) % 3];
                const TopoDS_Edge e = edgeFor(a, b);
                /* The stored edge runs low id -> high id; a triangle that uses
                 * it the other way takes it REVERSED, which is what makes the
                 * two faces either side agree and the shell hold together. */
                bb.Add(w, TopoDS::Edge(e.Oriented(
                              a < b ? TopAbs_FORWARD : TopAbs_REVERSED)));
            }
            BRepBuilderAPI_MakeFace mf(w, Standard_True);
            if (!mf.IsDone())
                continue;
            TopoDS_Face f = mf.Face();
            /* MakeFace picks the plane by least squares and its normal is not
             * bound to the wire's winding, so half the faces come out facing
             * inward. Sewing used to hide that; a shell built directly has
             * nothing to hide it, and an inside-out face makes a solid whose
             * volume comes back zero or a tenth of the truth. The triangle
             * already knows which way it faces. */
            const Handle(Geom_Plane) pl =
                Handle(Geom_Plane)::DownCast(BRep_Tool::Surface(f));
            if (!pl.IsNull()) {
                const gp_Dir d = pl->Position().Direction();
                V3 nn(d.X(), d.Y(), d.Z());
                if (f.Orientation() == TopAbs_REVERSED)
                    nn = V3(-nn.x, -nn.y, -nn.z);
                if (Dot(nn, m.tnorm[t]) < 0)
                    f.Reverse();
            }
            bb.Add(shell, f);
            faceCount++;
        } catch (const Standard_Failure &) {
        }
    }
    if (faceCount == 0)
        return TopoDS_Shape();
    return shell;
}

TopoDS_Shape BuildFaceted(const Mesh &m, double tol, Report &rep)
{
    (void)tol;
    int built = 0;
    TopoDS_Shell shell;
    try {
        const TopoDS_Shape sh = FacetedShell(m, built);
        if (sh.IsNull())
            return TopoDS_Shape();
        shell = TopoDS::Shell(sh);
    } catch (const Standard_Failure &) {
        return TopoDS_Shape();
    }
    /* Whether it closes is known exactly from the mesh, and asking OCCT to
     * work it out over a hundred thousand faces is not free. */
    if (rep.boundary_edges == 0 && rep.non_manifold_edges == 0)
        shell.Closed(Standard_True);
    rep.patches = 1;
    rep.faceted_patches = 1;
    rep.faces_built = built;
    TopoDS_Shape out = Solidify(shell, rep);
    if (out.IsNull())
        return out;

    /* Coplanar triangles become one face — the only thing that makes a faceted
     * conversion usable at all, and about half its running time.
     *
     * Not skippable on the grounds that a curved model has nothing coplanar:
     * measured, a finely tessellated ellipsoid has 9 to 13 per cent of its
     * neighbouring pairs flat with each other to within a quarter of a degree,
     * and a coarser one a third of them. The merge earns its time there too. */
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
        TopoDS_Shape out = BuildFaceted(m, tol, rep);
        if (out.IsNull())
            err = "the faces would not sew into a shell";
        return out;
    }

    /* ---- prismatic ------------------------------------------------ */
    std::vector<int> patchOf;
    int rawPatches = 0;
    std::vector<Patch> patches;
    std::unordered_set<int> freeform;
    try {
        MR_STAGE("start");
        const double sharpDeg = FeatureAngleDeg(m, prm.sharp_deg);
        MR_TRACE("  feature angle: %.1f deg (default %.1f)\n", sharpDeg,
                 prm.sharp_deg);
        SmoothPatches(m, sharpDeg, patchOf, rawPatches);
        MR_STAGE("smooth patches");
        std::vector<std::vector<int>> byPatch(rawPatches);
        for (int t = 0; t < m.triCount(); ++t)
            byPatch[patchOf[t]].push_back(t);

        for (int i = 0; i < rawPatches; ++i) {
            if (byPatch[i].empty())
                continue;
            /* A patch that fits nothing is several surfaces in one: met at a
             * crease too shallow for the global threshold, or met tangentially,
             * where no dihedral test will ever cut. SplitPatch tries the crease
             * first and the running fit after. */
            SplitPatch(m, byPatch[i], tol, scale, prm.min_patch_triangles, i, 0,
                       patches);
        }
        MR_STAGE("split");
#ifdef MESHRECON_TRACE
        {
            std::vector<int> own(m.triCount(), -1);
            for (size_t i = 0; i < patches.size(); ++i)
                for (int t : patches[i].tris)
                    own[t] = static_cast<int>(i);
            FILE *sf = std::fopen("segments_split.txt", "w");
            if (sf) {
                for (int t = 0; t < m.triCount(); ++t) {
                    const int i = own[t];
                    std::fprintf(sf, "%d %d %d %d\n", t, i,
                                 i >= 0 ? patches[i].origin : -1,
                                 i >= 0 ? (int)patches[i].fit.kind : 0);
                }
                std::fclose(sf);
            }
        }
#endif
        FreeformRuns(patches, m, tol, freeform);
        for (Patch &pa : patches)
            if (freeform.find(pa.origin) != freeform.end())
                pa.fit = Fit();
        MR_STAGE("freeform runs");
        MergeRegions(m, patches, tol, scale, 8, freeform);
        MR_STAGE("merge");
        RefineBoundaries(m, patches, tol, scale, 6);
        MR_STAGE("refine boundaries");
        Regularise(patches, m, prm, tol, scale);
        MR_STAGE("regularise");
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

    /* A patch keeps its surface only if the surface is evidence. The ones that
     * do not go to triangles INDIVIDUALLY — which is the whole difference
     * between a model whose holes are still circles and one that was thrown
     * away wholesale because its shell happened to be organic. */
    std::unordered_map<int, int> cutInto;
    for (const Patch &pa : patches)
        cutInto[pa.origin]++;
    for (size_t pi = 0; pi < patches.size(); ++pi) {
        Patch &pa = patches[pi];
        const bool frag = pa.origin < 0 || cutInto[pa.origin] > 1;
        const bool keep =
            pa.fit.kind != kNone && Identifiable(pa, m, tol, frag);
        MR_TRACE("  patch %3d origin %3d %5d tri  %-8s rms %.5f agree %.4f  "
                 "%s%s\n",
                 (int)pi, pa.origin, (int)pa.tris.size(),
                 KindName(pa.fit.kind), pa.fit.rms, pa.fit.agree,
                 keep ? "KEEP" : "drop", frag ? " (fragment)" : "");
        if (!keep)
            pa.fit = Fit();
    }

    /* And again after merging, which changes what is explained. */
    {
        std::unordered_set<int> again;
        FreeformRuns(patches, m, tol, again);
        for (Patch &pa : patches)
            if (again.find(pa.origin) != again.end())
                pa.fit = Fit();
    }

    /* A tiny face alone in a sea of triangles is worth less than the triangles.
     *
     * A squashed ellipsoid throws off single facets whose three neighbours are
     * all across a sharp edge, so each becomes a smooth run of ONE triangle
     * that fits its own plane exactly. Nothing above rejects them and nothing
     * should: two triangles really is a box's face. What settles it is the
     * company they keep. A face among faces shares its edges with faces; a
     * face among triangles has to be stitched to a triangle strip along every
     * side, which is where a hybrid shell leaves its open seams — and here it
     * buys nothing at all, because the fitted plane IS the triangle. So let it
     * be the triangle. */
    {
        double totalArea = 0;
        for (int t = 0; t < m.triCount(); ++t)
            totalArea += m.tarea[t];
        std::vector<int> owner(m.triCount(), -1);
        for (size_t i = 0; i < patches.size(); ++i)
            for (int t : patches[i].tris)
                owner[t] = static_cast<int>(i);
        for (int pass = 0; pass < 3; ++pass) {
            bool again = false;
            for (size_t i = 0; i < patches.size(); ++i) {
                Patch &pa = patches[i];
                if (pa.fit.kind == kNone ||
                    static_cast<int>(pa.tris.size()) >= kFreeformPieceTriangles)
                    continue;
                /* Small in AREA, not merely in triangles.
                 *
                 * Triangle count says a six-facet strip is as slight as a
                 * single facet, and it is not: on the user's part that strip
                 * is a flat wall forty millimetres long, four percent of the
                 * model's surface, and demoting it started an avalanche —
                 * every fitted neighbour then had a faceted neighbour of its
                 * own. What this rule is for is the offcut a lumpy surface
                 * throws off, which is a thousandth of the part. */
                double area = 0;
                for (int t : pa.tris)
                    area += m.tarea[t];
                if (area > totalArea * kScrapAreaFraction)
                    continue;
                /* How much of its BOUNDARY faces triangles.
                 *
                 * "Has a fitted neighbour" is not enough: two one-triangle
                 * runs side by side are each other's fitted neighbour and both
                 * survive on that alone, which is how a lumpy blob kept
                 * twenty-six "faces" that are its own facets. Nor is "has a
                 * big fitted neighbour" — a box is six faces of two triangles
                 * and every neighbour of every one of them is just as small.
                 * What separates them is what lies along the edges: a box face
                 * meets faces on all four sides, a facet adrift in an organic
                 * shell meets triangles on most of its own. */
                int outward = 0, toTriangles = 0;
                for (int t : pa.tris) {
                    for (int k = 0; k < 3; ++k) {
                        const int o = m.adj[t * 3 + k];
                        if (o < 0)
                            continue;
                        const int j = owner[o];
                        if (j < 0 || j == static_cast<int>(i))
                            continue;
                        outward++;
                        if (patches[j].fit.kind == kNone)
                            toTriangles++;
                    }
                }
                if (outward > 0 && toTriangles * 2 > outward) {
                    pa.fit = Fit();
                    again = true;
                }
            }
            if (!again)
                break;
        }
    }

    /* Nothing at all was recognised: then this is a mesh, and it should be
     * built as one piece rather than as a mosaic of faceted patches. The
     * difference is not cosmetic — each faceted patch is emitted with its own
     * vertices, so 183 of them meet along seams that sewing has to rediscover,
     * and a squashed ellipsoid came back 0.02% light where one faceted shell
     * reproduces the mesh's volume exactly. */
    {
        bool anyFit = false;
        for (const Patch &pa : patches)
            if (pa.fit.kind != kNone) {
                anyFit = true;
                break;
            }
        if (!anyFit && m.triCount() <= prm.max_faceted_triangles) {
            Report fr;
            ClearReport(fr);
            fr.triangles_in = rep.triangles_in;
            fr.vertices_in = rep.vertices_in;
            fr.triangles_used = rep.triangles_used;
            fr.vertices_welded = rep.vertices_welded;
            fr.non_manifold_edges = rep.non_manifold_edges;
            fr.boundary_edges = rep.boundary_edges;
            fr.flipped_triangles = rep.flipped_triangles;
            fr.diagonal = rep.diagonal;
            fr.patches = rep.patches;
            TopoDS_Shape alt;
            try {
                alt = BuildFaceted(m, tol, fr);
            } catch (const Standard_Failure &) {
            } catch (const std::exception &) {
            } catch (...) {
            }
            if (!alt.IsNull()) {
                rep = fr;
                MR_STAGE("faceted (nothing recognised)");
                return alt;
            }
        }
    }
    MR_STAGE("patch verdicts");
#ifdef MESHRECON_TRACE
    /* One line per triangle: which patch, which smooth run, what kind was
     * kept. The development harness renders the mesh from this, which is the
     * only way to see WHAT a run that fitted nothing actually is. */
    {
        std::vector<int> ownerOf(m.triCount(), -1);
        for (size_t i = 0; i < patches.size(); ++i)
            for (int t : patches[i].tris)
                ownerOf[t] = static_cast<int>(i);
        FILE *sf = std::fopen("segments.txt", "w");
        if (sf) {
            for (int t = 0; t < m.triCount(); ++t) {
                const int i = ownerOf[t];
                std::fprintf(sf, "%d %d %d %d\n", t, i,
                             i >= 0 ? patches[i].origin : -1,
                             i >= 0 ? (int)patches[i].fit.kind : 0);
            }
            std::fclose(sf);
        }
    }
#endif

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
        const size_t before = faces.size();
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
            /* Checked HERE rather than inside the builder because the analytic
             * path can also hand off to the parametric one, and a face that
             * escaped its patch is worthless whichever built it. */
            for (size_t k = before; k < faces.size(); ++k) {
                if (!FaceWithinPatch(faces[k], m, patches[i].tris, tol)) {
                    built = false;
                    break;
                }
            }
            if (!built)
                faces.resize(before);
        }
        if (built) {
            rep.faces_built++;
        } else {
            faces.resize(before);
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
    MR_STAGE("build faces");
    for (const std::vector<int> &tris : deferred)
        EmitFacetedShared(ctx, m, tris, faces);
    MR_STAGE("emit faceted");

    rep.analytic_edges = ctx.analytic;
    rep.approximated_edges = ctx.approximated;
    rep.freeform = 0;

    if (faces.empty()) {
        err = "no faces could be built from that mesh";
        return TopoDS_Shape();
    }
    /* These faces were built sharing their edges, so try assembling them
     * as they are before handing them to a tool that would rebuild them. */
    TopoDS_Shape out;
    {
        const TopoDS_Shape direct = AssembleShell(faces);
        if (!direct.IsNull())
            out = Solidify(direct, rep);
    }
    if (out.IsNull())
        out = SewAndSolidify(faces, tol, rep);
    /* A hybrid shell — fitted faces beside triangles — can come out of sewing
     * with a handful of edges still open where the two kinds meet: 26 of 3032
     * on the model this was measured on, the seams round its four holes. They
     * are not gaps in the model, they are two descriptions of the same seam
     * that sewing declined to identify at the tolerance it was given. Ask
     * again, once, with room. */
    if (rep.closed != 1 && !faces.empty()) {
        Report r2 = rep;
        r2.shells = r2.solids = r2.closed = 0;
        TopoDS_Shape again;
        try {
            again = SewAndSolidify(faces, tol * kSewRetryFactor, r2);
        } catch (const Standard_Failure &) {
        }
        if (!again.IsNull() && r2.closed == 1) {
            rep = r2;
            out = again;
        }
    }
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

    /* A shell that will not close is not a body, and an ORGANIC model produces
     * exactly that.
     *
     * Surface fitting has nothing to recognise on a shape that is curved
     * everywhere and analytic nowhere: it shatters into one small patch per
     * handful of triangles, none of them meeting cleanly, and the result is an
     * open shell that cannot be filleted, cut or booleaned — the whole reason
     * for converting at all. One face per triangle recognises nothing either,
     * but on a watertight mesh it CANNOT fail, and a heavy solid the user can
     * actually work on beats a light shell they cannot.
     *
     * Decided by trying it rather than by predicting it: if the faceted build
     * closes where the fitted one did not, it wins; otherwise nothing is lost
     * but the attempt.
     *
     * Closing is not the only reason to prefer it. A mesh that is not
     * watertight — and downloaded ones often are not — closes under neither,
     * and then the question is which OPEN shell is worth having. A fitted one
     * that recognised the model is: it is lighter and its faces are real
     * surfaces. One that SHATTERED is not, and shattering is plain in the
     * numbers — the file this was found on came back as 179 patches for 1138
     * triangles, one face per six, which is not a reading of the shape but a
     * failure to read it. Below a floor the ratio means nothing (a cube with a
     * face missing is 5 patches for 10 triangles and perfectly recognised), so
     * it only applies to meshes big enough for it to say something. */
    const bool shattered =
        m.triCount() >= kShatterFloorTriangles &&
        rep.patches * kShatterTrianglesPerPatch > m.triCount();

    /* Whether anything CURVED was recognised, and survived the identifiability
     * test — a cylinder, cone, sphere or torus, not merely a plane.
     *
     * This is what decides whether the faceted build is allowed to replace the
     * fitted one, and it is the difference between a model whose holes are
     * holes and a bag of triangles. On a curved shell with four drilled holes
     * the fitted pass finds the four cylinders at radius exactly 2, 3, 4 and 5
     * and turns the shell itself into triangles, which is the right answer and
     * the one that was asked for; replacing all of it because the hybrid shell
     * did not close would throw the four holes away to gain a solid. A model
     * that recognised nothing has nothing to lose and takes the solid. */
    /* How many pieces each smooth patch was cut into. A feature of the DESIGN
     * — a hole, a boss, a fillet — arrives as a whole smooth patch, bounded by
     * its own sharp rim; SplitByFit never had to touch it. A cylinder that is
     * really a strip of a smooth shell is one of many pieces that patch was
     * broken into, and on a squashed sphere such a strip fits a cylinder to
     * better than a fiftieth of tolerance. The residual cannot separate those
     * two; where the patch CAME FROM can. */
    std::unordered_map<int, int> piecesOfOrigin;
    for (const Patch &pa : patches)
        piecesOfOrigin[pa.origin]++;

    bool recognisedFeatures = false;
    for (const Patch &pa : patches) {
        if (pa.fit.kind == kNone || pa.fit.kind == kPlane)
            continue;
        if (pa.origin >= 0 && piecesOfOrigin[pa.origin] != 1)
            continue; /* a shard of a smooth region, not a feature of the part */
        /* "Recognised" means EXACT, not merely allowed. A tessellation puts
         * its vertices on the surface they came from, so a real hole fits its
         * cylinder with a residual of nothing; the identifiability test
         * already refuses anything above a sixth of tolerance, but a coarse
         * organic shell can still throw up a sphere at a twentieth of it, and
         * three of those were enough to stop an ellipsoid taking the solid it
         * should have had. Only a feature that fits to the mesh's own
         * precision is worth keeping an open shell for. */
        if (pa.fit.rms <= tol * kExactFitFraction) {
            recognisedFeatures = true;
            break;
        }
    }
    if (rep.closed != 1 && !recognisedFeatures &&
        m.triCount() <= kMaxAutoFacetedTriangles &&
        m.triCount() <= prm.max_faceted_triangles) {
        Report fr;
        ClearReport(fr);
        fr.triangles_in = rep.triangles_in;
        fr.vertices_in = rep.vertices_in;
        fr.triangles_used = rep.triangles_used;
        fr.vertices_welded = rep.vertices_welded;
        fr.non_manifold_edges = rep.non_manifold_edges;
        fr.boundary_edges = rep.boundary_edges;
        fr.flipped_triangles = rep.flipped_triangles;
        fr.diagonal = rep.diagonal;
        TopoDS_Shape alt;
        try {
            alt = BuildFaceted(m, tol, fr);
        } catch (const Standard_Failure &) {
        } catch (const std::exception &) {
        } catch (...) {
        }
        if (!alt.IsNull() && (fr.closed == 1 || shattered)) {
            rep = fr;
            return alt;
        }
    }
    return out;
}

} // namespace meshrecon
