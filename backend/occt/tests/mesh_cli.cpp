/* mesh_cli — run the mesh->B-Rep reconstruction on a FILE, from a terminal.
 *
 * The suite in mesh_recon_test.cpp builds its meshes with OCCT, so every one of
 * them is closed, consistently wound and in double precision. A downloaded STL
 * is none of those by default, and every failure this converter has had in the
 * field came from a file rather than from a fixture. This is the tool that
 * opens one:
 *
 *   occt_mesh_cli part.stl [--faceted] [--tol 0.001] [--sharp 25]
 *                          [--brep out.brep] [--step out.step]
 *
 * It reads the file exactly as frontend/lib/mesh_io.dart does — binary or ASCII
 * STL, OBJ, and the same exact-bit vertex dedup — so what it hands the kernel
 * is byte-for-byte what the app hands it, and a failure reproduced here is the
 * failure the user saw. Prints the Report and the timing; writes the body when
 * asked, for mesh_check to measure.
 *
 * Host only, built with OCCT_SMOKE. Never linked into the app. */
#include "mesh_recon.h"

#include <BRepTools.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <Poly_Triangulation.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopLoc_Location.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <STEPControl_Writer.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopAbs.hxx>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

/* The app's dedup: exact float bits, no tolerance — see mesh_io.dart. The
 * welding proper is the kernel's job and happens inside Reconstruct. */
struct Key
{
    float x, y, z;
    bool operator==(const Key &o) const
    {
        return std::memcmp(this, &o, sizeof(Key)) == 0;
    }
};
struct KeyHash
{
    size_t operator()(const Key &k) const
    {
        size_t h = 1469598103934665603ull;
        const unsigned char *p = reinterpret_cast<const unsigned char *>(&k);
        for (size_t i = 0; i < sizeof(Key); ++i) {
            h ^= p[i];
            h *= 1099511628211ull;
        }
        return h;
    }
};

struct Soup
{
    std::vector<double> xyz;
    std::vector<int> tri;
};

bool ReadAll(const char *path, std::vector<unsigned char> &out)
{
    FILE *f = std::fopen(path, "rb");
    if (!f)
        return false;
    std::fseek(f, 0, SEEK_END);
    const long n = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    if (n < 0) {
        std::fclose(f);
        return false;
    }
    out.resize(static_cast<size_t>(n));
    const size_t got = n > 0 ? std::fread(out.data(), 1, out.size(), f) : 0;
    std::fclose(f);
    return got == out.size();
}

void Add(Soup &s, std::unordered_map<Key, int, KeyHash> &seen, float x, float y,
         float z, int *idx)
{
    Key k{x, y, z};
    auto it = seen.find(k);
    if (it != seen.end()) {
        *idx = it->second;
        return;
    }
    const int i = static_cast<int>(s.xyz.size() / 3);
    seen.emplace(k, i);
    s.xyz.push_back(x);
    s.xyz.push_back(y);
    s.xyz.push_back(z);
    *idx = i;
}

bool LooksBinaryStl(const std::vector<unsigned char> &b)
{
    if (b.size() < 84)
        return false;
    unsigned int n = 0;
    std::memcpy(&n, b.data() + 80, 4);
    return b.size() == 84 + static_cast<size_t>(n) * 50;
}

bool ReadStlBinary(const std::vector<unsigned char> &b, Soup &s)
{
    unsigned int n = 0;
    std::memcpy(&n, b.data() + 80, 4);
    std::unordered_map<Key, int, KeyHash> seen;
    size_t off = 84;
    for (unsigned int t = 0; t < n; ++t, off += 50) {
        float v[12];
        std::memcpy(v, b.data() + off, 48);
        int a, c, d;
        Add(s, seen, v[3], v[4], v[5], &a);
        Add(s, seen, v[6], v[7], v[8], &c);
        Add(s, seen, v[9], v[10], v[11], &d);
        s.tri.push_back(a);
        s.tri.push_back(c);
        s.tri.push_back(d);
    }
    return n > 0;
}

bool ReadStlAscii(const std::vector<unsigned char> &b, Soup &s)
{
    const std::string txt(reinterpret_cast<const char *>(b.data()), b.size());
    std::unordered_map<Key, int, KeyHash> seen;
    size_t i = 0;
    std::vector<int> face;
    while (i < txt.size()) {
        const size_t v = txt.find("vertex", i);
        if (v == std::string::npos)
            break;
        double x = 0, y = 0, z = 0;
        if (std::sscanf(txt.c_str() + v + 6, "%lf %lf %lf", &x, &y, &z) != 3)
            break;
        int idx;
        Add(s, seen, static_cast<float>(x), static_cast<float>(y),
            static_cast<float>(z), &idx);
        face.push_back(idx);
        if (face.size() == 3) {
            s.tri.insert(s.tri.end(), face.begin(), face.end());
            face.clear();
        }
        i = v + 6;
    }
    return !s.tri.empty();
}

bool ReadObj(const std::vector<unsigned char> &b, Soup &s)
{
    const std::string txt(reinterpret_cast<const char *>(b.data()), b.size());
    std::vector<double> vs;
    size_t i = 0;
    while (i <= txt.size()) {
        size_t e = txt.find('\n', i);
        if (e == std::string::npos)
            e = txt.size();
        const std::string line = txt.substr(i, e - i);
        i = e + 1;
        if (line.size() > 2 && line[0] == 'v' && (line[1] == ' ' || line[1] == '\t')) {
            double x, y, z;
            if (std::sscanf(line.c_str() + 1, "%lf %lf %lf", &x, &y, &z) == 3) {
                vs.push_back(x);
                vs.push_back(y);
                vs.push_back(z);
            }
        } else if (line.size() > 2 && line[0] == 'f' &&
                   (line[1] == ' ' || line[1] == '\t')) {
            std::vector<int> poly;
            size_t p = 1;
            while (p < line.size()) {
                while (p < line.size() && (line[p] == ' ' || line[p] == '\t'))
                    ++p;
                if (p >= line.size())
                    break;
                int idx = std::atoi(line.c_str() + p);
                if (idx < 0)
                    idx = static_cast<int>(vs.size() / 3) + idx + 1;
                if (idx >= 1 && idx <= static_cast<int>(vs.size() / 3))
                    poly.push_back(idx - 1);
                while (p < line.size() && line[p] != ' ' && line[p] != '\t')
                    ++p;
            }
            for (size_t k = 2; k < poly.size(); ++k) {
                s.tri.push_back(poly[0]);
                s.tri.push_back(poly[k - 1]);
                s.tri.push_back(poly[k]);
            }
        }
        if (e == txt.size())
            break;
    }
    s.xyz = vs;
    return !s.tri.empty();
}

int CountOf(const TopoDS_Shape &s, TopAbs_ShapeEnum k)
{
    int n = 0;
    for (TopExp_Explorer e(s, k); e.More(); e.Next())
        ++n;
    return n;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) {
        std::fprintf(stderr,
                     "usage: %s mesh.(stl|obj) [--faceted] [--tol frac] "
                     "[--sharp deg] [--brep out.brep] [--step out.step] "
                     "[--stl out.stl]\n",
                     argv[0]);
        return 2;
    }
    const char *path = argv[1];
    meshrecon::Params p = meshrecon::Defaults();
    const char *brepOut = nullptr, *stepOut = nullptr, *stlOut = nullptr;
    /* Deflection for --stl, as a fraction of the body's diagonal. */
    double stlDefl = 0.001;
    for (int i = 2; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--faceted")
            p.mode = 0;
        else if (a == "--tol" && i + 1 < argc)
            p.tol_frac = std::atof(argv[++i]);
        else if (a == "--sharp" && i + 1 < argc)
            p.sharp_deg = std::atof(argv[++i]);
        else if (a == "--weld" && i + 1 < argc)
            p.weld_frac = std::atof(argv[++i]);
        else if (a == "--minpatch" && i + 1 < argc)
            p.min_patch_triangles = std::atoi(argv[++i]);
        else if (a == "--brep" && i + 1 < argc)
            brepOut = argv[++i];
        else if (a == "--step" && i + 1 < argc)
            stepOut = argv[++i];
        else if (a == "--stl" && i + 1 < argc)
            stlOut = argv[++i];
        else if (a == "--defl" && i + 1 < argc)
            stlDefl = std::atof(argv[++i]);
        else {
            std::fprintf(stderr, "unknown option: %s\n", a.c_str());
            return 2;
        }
    }

    std::vector<unsigned char> bytes;
    if (!ReadAll(path, bytes)) {
        std::fprintf(stderr, "cannot read %s\n", path);
        return 1;
    }
    Soup s;
    const std::string ext(path);
    bool ok = false;
    if (ext.size() > 4 && ext.compare(ext.size() - 4, 4, ".obj") == 0)
        ok = ReadObj(bytes, s);
    else if (LooksBinaryStl(bytes))
        ok = ReadStlBinary(bytes, s);
    else
        ok = ReadStlAscii(bytes, s);
    if (!ok) {
        std::fprintf(stderr, "no triangles in %s\n", path);
        return 1;
    }
    const int nv = static_cast<int>(s.xyz.size() / 3);
    const int nt = static_cast<int>(s.tri.size() / 3);
    std::printf("%s: %d triangles, %d vertices after exact dedup\n", path, nt, nv);

    meshrecon::Report r;
    std::string err;
    const auto t0 = std::chrono::steady_clock::now();
    const TopoDS_Shape out = meshrecon::Reconstruct(s.xyz.data(), nv,
                                                    s.tri.data(), nt, p, r, err);
    const auto t1 = std::chrono::steady_clock::now();
    const double ms =
        std::chrono::duration<double, std::milli>(t1 - t0).count();

    std::printf("  %.0f ms  mode=%s tol=%g*diag sharp=%g\n", ms,
                p.mode ? "fit" : "faceted", p.tol_frac, p.sharp_deg);
    std::printf("  in       %d tri, %d vert  (used %d, welded to %d)\n",
                r.triangles_in, r.vertices_in, r.triangles_used,
                r.vertices_welded);
    std::printf("  mesh     %d non-manifold, %d boundary, %d flipped, diag %.4f\n",
                r.non_manifold_edges, r.boundary_edges, r.flipped_triangles,
                r.diagonal);
    std::printf("  patches  %d  (plane %d cyl %d cone %d sph %d torus %d "
                "freeform %d faceted %d)\n",
                r.patches, r.planes, r.cylinders, r.cones, r.spheres, r.tori,
                r.freeform, r.faceted_patches);
    std::printf("  faces    %d built, %d failed;  edges %d exact, %d approx\n",
                r.faces_built, r.faces_failed, r.analytic_edges,
                r.approximated_edges);
    std::printf("  result   shells %d solids %d closed %d  fit rms %.6f\n",
                r.shells, r.solids, r.closed, r.fit_rms);
    if (out.IsNull()) {
        std::printf("  FAILED: %s\n", err.c_str());
        return 1;
    }
    std::printf("  shape    %d faces, %d edges, %d vertices\n",
                CountOf(out, TopAbs_FACE), CountOf(out, TopAbs_EDGE),
                CountOf(out, TopAbs_VERTEX));
    try {
        GProp_GProps vg;
        BRepGProp::VolumeProperties(out, vg);
        std::printf("  volume   %.6f\n", std::fabs(vg.Mass()));
    } catch (const Standard_Failure &) {
    }
    if (brepOut) {
        BRepTools::Write(out, brepOut);
        std::printf("  wrote    %s\n", brepOut);
    }
    {   /* Free edges: an edge on exactly one face is a hole in the shell, and
         * the count of them is the difference between a body and a bag of
         * surfaces. */
        TopTools_IndexedDataMapOfShapeListOfShape em;
        TopExp::MapShapesAndAncestors(out, TopAbs_EDGE, TopAbs_FACE, em);
        int free1 = 0, over = 0;
        for (int i = 1; i <= em.Extent(); ++i) {
            const int n = em.FindFromIndex(i).Extent();
            if (n == 1) ++free1;
            else if (n > 2) ++over;
        }
        std::printf("  edges    %d free, %d shared by more than two faces\n",
                    free1, over);
    }
    if (stlOut) {
        /* The body as the app would DRAW it, so the conversion can be looked
         * at rather than only counted. */
        Bnd_Box bb;
        BRepBndLib::Add(out, bb);
        double x0, y0, z0, x1, y1, z1;
        bb.Get(x0, y0, z0, x1, y1, z1);
        const double diag = std::sqrt((x1 - x0) * (x1 - x0) +
                                      (y1 - y0) * (y1 - y0) +
                                      (z1 - z0) * (z1 - z0));
        std::vector<double> areas;
        double factor = 0;
        const int empty = meshrecon::TessellateCovered(out, diag * stlDefl, 0.35,
                                                       areas, factor);
        FILE *f = std::fopen(stlOut, "wb");
        if (f) {
            unsigned char hdr[80] = {0};
            std::fwrite(hdr, 1, 80, f);
            std::vector<float> tri;
            unsigned int nfac = 0;
            for (TopExp_Explorer ex(out, TopAbs_FACE); ex.More(); ex.Next()) {
                const TopoDS_Face fc = TopoDS::Face(ex.Current());
                TopLoc_Location L;
                Handle(Poly_Triangulation) tr = BRep_Tool::Triangulation(fc, L);
                if (tr.IsNull()) continue;
                const bool rev = fc.Orientation() == TopAbs_REVERSED;
                for (int i = 1; i <= tr->NbTriangles(); ++i) {
                    int a, b, c;
                    tr->Triangle(i).Get(a, b, c);
                    if (rev) std::swap(b, c);
                    const gp_Pnt p[3] = {tr->Node(a).Transformed(L),
                                         tr->Node(b).Transformed(L),
                                         tr->Node(c).Transformed(L)};
                    for (int k = 0; k < 3; ++k) tri.push_back(0.f);
                    for (int v = 0; v < 3; ++v)
                        for (int k = 0; k < 3; ++k)
                            tri.push_back((float)p[v].Coord(k + 1));
                    ++nfac;
                }
            }
            std::fwrite(&nfac, 4, 1, f);
            for (unsigned int i = 0; i < nfac; ++i) {
                std::fwrite(&tri[i * 12], 4, 12, f);
                const unsigned short z = 0;
                std::fwrite(&z, 2, 1, f);
            }
            std::fclose(f);
            std::printf("  wrote    %s (%u triangles, %d faces empty)\n",
                        stlOut, nfac, empty);
        }
    }
    if (stepOut) {
        STEPControl_Writer w;
        w.Transfer(out, STEPControl_AsIs);
        w.Write(stepOut);
        std::printf("  wrote    %s\n", stepOut);
    }
    return 0;
}
