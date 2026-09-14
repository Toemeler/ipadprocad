/* tessellate — a B-Rep to an STL, at a stated deflection.
 *
 *   occt_tessellate in.step|in.brep out.stl [--defl 0.001] [--ang 0.35]
 *                   [--float32] [--noise 0]
 *
 * This exists so a body that CAME FROM CAD can be round-tripped: mesh it here,
 * hand the triangles to the reconstruction, and compare what comes back
 * against the body we started from. It is the only test in the suite with
 * exact ground truth — every other measurement is against the mesh, which is
 * itself an approximation of something nobody has.
 *
 * `--defl` is a FRACTION of the bounding-box diagonal, matching mesh_cli.
 * `--float32` rounds every coordinate to single precision, which is what an
 * STL file does to it, so the round trip is honest about the precision the
 * reconstruction will actually see. `--noise` adds uniform jitter of that
 * fraction of the diagonal, for measuring how the pipeline degrades on a
 * scanned rather than exported mesh.
 *
 * Host only, built with OCCT_SMOKE. Never linked into the app. */
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPControl_Reader.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>

int main(int argc, char **argv)
{
    if (argc < 3) {
        std::fprintf(stderr,
                     "usage: %s in.(step|brep) out.stl [--defl frac] "
                     "[--ang rad] [--float32] [--noise frac]\n", argv[0]);
        return 2;
    }
    const char *in = argv[1], *out = argv[2];
    double defl = 0.001, ang = 0.35, noise = 0.0;
    bool f32 = false;
    for (int i = 3; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--defl" && i+1 < argc) defl = std::atof(argv[++i]);
        else if (a == "--ang" && i+1 < argc) ang = std::atof(argv[++i]);
        else if (a == "--noise" && i+1 < argc) noise = std::atof(argv[++i]);
        else if (a == "--float32") f32 = true;
        else { std::fprintf(stderr, "unknown option: %s\n", a.c_str()); return 2; }
    }

    TopoDS_Shape s;
    const std::string p(in);
    const bool isStep = p.size() > 4 &&
        (p.compare(p.size()-4,4,".stp")==0 || p.compare(p.size()-5,5,".step")==0);
    if (isStep) {
        STEPControl_Reader r;
        if (r.ReadFile(in) != IFSelect_RetDone) {
            std::fprintf(stderr, "cannot read STEP %s\n", in); return 1;
        }
        r.TransferRoots();
        s = r.OneShape();
    } else {
        BRep_Builder b;
        if (!BRepTools::Read(s, in, b)) {
            std::fprintf(stderr, "cannot read BREP %s\n", in); return 1;
        }
    }
    if (s.IsNull()) { std::fprintf(stderr, "empty shape\n"); return 1; }

    Bnd_Box bb; BRepBndLib::Add(s, bb);
    double x0,y0,z0,x1,y1,z1; bb.Get(x0,y0,z0,x1,y1,z1);
    const double diag = std::sqrt((x1-x0)*(x1-x0)+(y1-y0)*(y1-y0)+(z1-z0)*(z1-z0));

    BRepMesh_IncrementalMesh im(s, diag*defl, Standard_False, ang, Standard_True);
    im.Perform();

    /* Jitter is keyed on the VERTEX POSITION, not on the triangle corner.
     * A shared node reached from three faces must move once, the same way
     * each time, or the noise tears the mesh open and what is measured
     * afterwards is the tear rather than the noise. Hashing the exact
     * coordinates gives every triangle that meets at a node the same offset
     * without needing a welded index. */
    auto jitterAt = [&](const gp_Pnt &q, int axis) {
        if (noise <= 0) return 0.0;
        std::uint64_t h = 1469598103934665603ull;
        const double c[3] = { q.X(), q.Y(), q.Z() };
        for (int i = 0; i < 3; ++i) {
            std::uint64_t bits;
            std::memcpy(&bits, &c[i], sizeof(bits));
            h = (h ^ bits) * 1099511628211ull;
        }
        h = (h ^ static_cast<std::uint64_t>(axis)) * 1099511628211ull;
        h ^= h >> 33;
        const double u = static_cast<double>(h >> 11) /
                         static_cast<double>(1ull << 53);
        return (u * 2.0 - 1.0) * noise * diag;
    };

    std::vector<float> tri;
    unsigned int nfac = 0;
    int emptyFaces = 0;
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next()) {
        const TopoDS_Face f = TopoDS::Face(ex.Current());
        TopLoc_Location L;
        Handle(Poly_Triangulation) t = BRep_Tool::Triangulation(f, L);
        if (t.IsNull()) { ++emptyFaces; continue; }
        const bool rev = f.Orientation() == TopAbs_REVERSED;
        for (int i = 1; i <= t->NbTriangles(); ++i) {
            int a,b,c; t->Triangle(i).Get(a,b,c);
            if (rev) std::swap(b,c);
            gp_Pnt q[3] = { t->Node(a).Transformed(L),
                            t->Node(b).Transformed(L),
                            t->Node(c).Transformed(L) };
            for (int k = 0; k < 3; ++k) tri.push_back(0.f);
            for (int v = 0; v < 3; ++v) {
                const double xyz[3] = { q[v].X(), q[v].Y(), q[v].Z() };
                for (int k = 0; k < 3; ++k) {
                    double d = xyz[k] + jitterAt(q[v], k);
                    if (f32) d = static_cast<double>(static_cast<float>(d));
                    tri.push_back(static_cast<float>(d));
                }
            }
            ++nfac;
        }
    }

    FILE *fp = std::fopen(out, "wb");
    if (!fp) { std::fprintf(stderr, "cannot write %s\n", out); return 1; }
    unsigned char hdr[80] = {0};
    std::snprintf(reinterpret_cast<char*>(hdr), 80,
                  "occt_tessellate defl=%g ang=%g", defl, ang);
    std::fwrite(hdr, 1, 80, fp);
    std::fwrite(&nfac, 4, 1, fp);
    for (unsigned int i = 0; i < nfac; ++i) {
        std::fwrite(&tri[i*12], 4, 12, fp);
        const unsigned short z = 0;
        std::fwrite(&z, 2, 1, fp);
    }
    std::fclose(fp);

    std::printf("in=%s diagonal=%.6f deflection=%.6f\n", in, diag, diag*defl);
    std::printf("out=%s triangles=%u faces_without_triangulation=%d float32=%d noise=%g\n",
                out, nfac, emptyFaces, f32 ? 1 : 0, noise);
    return 0;
}
