/*
 * M232 — the mesh -> B-Rep round trip.
 *
 * Builds a solid with OCCT, tessellates it, throws the B-Rep away, and
 * reconstructs from the triangles alone — which is exactly what opening a
 * downloaded STL asks the converter to do, except that here the right answer
 * is known. Checks the TOPOLOGY (how many faces, and of what kind) and the
 * VOLUME, because either alone can be right while the model is wrong.
 *
 * Host only, like smoke_occt.c: it links TKPrim/TKBO/TKFillet to build the
 * reference solids, which the shipped shim does not.
 *
 * Build:  cmake -S backend/occt -B build -DOCCT_SMOKE=ON \
 *               -DCMAKE_PREFIX_PATH=<occt install>
 *         cmake --build build --target occt_mesh_recon_test
 *         ./build/occt_mesh_recon_test
 */
#include "mesh_recon.h"

#include <chrono>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepPrimAPI_MakeSphere.hxx>
#include <BRepPrimAPI_MakeCone.hxx>
#include <BRepPrimAPI_MakeTorus.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Tool.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <Poly_Triangulation.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopLoc_Location.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <cstdio>
#include <cmath>
#include <vector>
#include <string>

static int passes = 0, fails = 0;
static void chk(const char *what, bool ok, const std::string &extra = "")
{
    if (ok) {
        passes++;
    } else {
        fails++;
        std::printf("   FAIL: %s %s\n", what, extra.c_str());
    }
}

// Tessellate a shape into a plain triangle soup (as a mesh FILE would give us:
// no face ids, no normals, nothing but points and indices).
static void Tessellate(const TopoDS_Shape &s, double defl,
                       std::vector<double> &xyz, std::vector<int> &tri)
{
    BRepMesh_IncrementalMesh mesher(s, defl, Standard_False, 0.3,
                                    Standard_True);
    xyz.clear();
    tri.clear();
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next()) {
        const TopoDS_Face f = TopoDS::Face(ex.Current());
        TopLoc_Location loc;
        Handle(Poly_Triangulation) t = BRep_Tool::Triangulation(f, loc);
        if (t.IsNull())
            continue;
        const int base = (int)(xyz.size() / 3);
        const gp_Trsf &tr = loc.Transformation();
        for (int i = 1; i <= t->NbNodes(); ++i) {
            gp_Pnt p = t->Node(i).Transformed(tr);
            xyz.push_back(p.X());
            xyz.push_back(p.Y());
            xyz.push_back(p.Z());
        }
        const bool rev = (f.Orientation() == TopAbs_REVERSED);
        for (int i = 1; i <= t->NbTriangles(); ++i) {
            int a, b, c;
            t->Triangle(i).Get(a, b, c);
            if (rev)
                std::swap(b, c);
            tri.push_back(base + a - 1);
            tri.push_back(base + b - 1);
            tri.push_back(base + c - 1);
        }
    }
}

// The volume the MESH encloses -- what the converter actually sees, as opposed
// to the solid the mesh was made from.
static double MeshVolume(const std::vector<double> &xyz,
                         const std::vector<int> &tri)
{
    double v = 0;
    for (size_t i = 0; i < tri.size(); i += 3) {
        const double *a = &xyz[tri[i] * 3];
        const double *b = &xyz[tri[i + 1] * 3];
        const double *c = &xyz[tri[i + 2] * 3];
        v += a[0] * (b[1] * c[2] - b[2] * c[1]) -
             a[1] * (b[0] * c[2] - b[2] * c[0]) +
             a[2] * (b[0] * c[1] - b[1] * c[0]);
    }
    return v / 6.0;
}

static double Volume(const TopoDS_Shape &s)
{
    if (s.IsNull())
        return 0;
    GProp_GProps g;
    BRepGProp::VolumeProperties(s, g);
    return g.Mass();
}

struct Counts
{
    int planes = 0, cyl = 0, cone = 0, sph = 0, tor = 0, other = 0, total = 0;
};
static Counts FaceKinds(const TopoDS_Shape &s)
{
    Counts c;
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next()) {
        BRepAdaptor_Surface sa(TopoDS::Face(ex.Current()));
        c.total++;
        switch (sa.GetType()) {
        case GeomAbs_Plane:
            c.planes++;
            break;
        case GeomAbs_Cylinder:
            c.cyl++;
            break;
        case GeomAbs_Cone:
            c.cone++;
            break;
        case GeomAbs_Sphere:
            c.sph++;
            break;
        case GeomAbs_Torus:
            c.tor++;
            break;
        default:
            c.other++;
            break;
        }
    }
    return c;
}

static void report(const meshrecon::Report &r)
{
    std::printf("   tri %d->%d  vtx %d->%d  patches %d  "
                "[pl %d cy %d co %d sp %d to %d] faceted %d  "
                "faces %d (failed %d)  edges %d exact / %d approx  "
                "rms %.5f  solid %d\n",
                r.triangles_in, r.triangles_used, r.vertices_in,
                r.vertices_welded, r.patches, r.planes, r.cylinders, r.cones,
                r.spheres, r.tori, r.faceted_patches, r.faces_built,
                r.faces_failed, r.analytic_edges, r.approximated_edges,
                r.fit_rms, r.closed);
}

static double g_meshVolume = 0;

static TopoDS_Shape Run(const TopoDS_Shape &src, double defl,
                        meshrecon::Report &rep, int mode = 1)
{
    std::vector<double> xyz;
    std::vector<int> tri;
    Tessellate(src, defl, xyz, tri);
    g_meshVolume = std::fabs(MeshVolume(xyz, tri));
    meshrecon::Params p = meshrecon::Defaults();
    p.mode = mode;
    std::string err;
    TopoDS_Shape out =
        meshrecon::Reconstruct(xyz.data(), (int)(xyz.size() / 3), tri.data(),
                               (int)(tri.size() / 3), p, rep, err);
    if (out.IsNull())
        std::printf("   (null: %s)\n", err.c_str());
    return out;
}

int main()
{
    // ---- 1. box ---------------------------------------------------------
    {
        std::printf("== box 10x20x30 ==\n");
        TopoDS_Shape src = BRepPrimAPI_MakeBox(10., 20., 30.).Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.05, r);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            Counts c = FaceKinds(out);
            chk("closed solid", r.closed == 1);
            chk("6 planar faces", c.planes == 6 && c.total == 6,
                "got " + std::to_string(c.total) + " faces, " +
                    std::to_string(c.planes) + " planar");
            chk("volume 6000", std::fabs(Volume(out) - 6000.) < 1e-6,
                std::to_string(Volume(out)));
            chk("valid", BRepCheck_Analyzer(out).IsValid());
        }
    }
    // ---- 2. cylinder ----------------------------------------------------
    {
        std::printf("== cylinder r=8 h=25 ==\n");
        TopoDS_Shape src = BRepPrimAPI_MakeCylinder(8., 25.).Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.02, r);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            Counts c = FaceKinds(out);
            chk("closed solid", r.closed == 1);
            chk("2 planes + 1 cylinder", c.planes == 2 && c.cyl == 1,
                std::to_string(c.planes) + "pl " + std::to_string(c.cyl) +
                    "cy " + std::to_string(c.other) + "other");
            const double want = M_PI * 64. * 25.;
            chk("volume", std::fabs(Volume(out) - want) / want < 2e-3,
                std::to_string(Volume(out)) + " want " + std::to_string(want));
        }
    }
    // ---- 3. sphere ------------------------------------------------------
    {
        std::printf("== sphere r=12 ==\n");
        TopoDS_Shape src = BRepPrimAPI_MakeSphere(12.).Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.02, r);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            Counts c = FaceKinds(out);
            chk("spherical", c.sph >= 1, std::to_string(c.sph));
            const double want = 4. / 3. * M_PI * 12. * 12. * 12.;
            chk("volume", std::fabs(Volume(out) - want) / want < 5e-3,
                std::to_string(Volume(out)) + " want " + std::to_string(want));
        }
    }
    // ---- 4. cone --------------------------------------------------------
    {
        std::printf("== truncated cone r1=10 r2=4 h=20 ==\n");
        TopoDS_Shape src = BRepPrimAPI_MakeCone(10., 4., 20.).Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.02, r);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            Counts c = FaceKinds(out);
            chk("conical face", c.cone >= 1, std::to_string(c.cone));
            const double want = M_PI * 20. / 3. * (100. + 40. + 16.);
            chk("volume", std::fabs(Volume(out) - want) / want < 5e-3,
                std::to_string(Volume(out)) + " want " + std::to_string(want));
        }
    }
    // ---- 5. block with a through hole -----------------------------------
    {
        std::printf("== block 40x40x12 with a d=10 hole ==\n");
        TopoDS_Shape box = BRepPrimAPI_MakeBox(40., 40., 12.).Shape();
        gp_Ax2 ax(gp_Pnt(20., 20., -1.), gp_Dir(0, 0, 1));
        TopoDS_Shape hole = BRepPrimAPI_MakeCylinder(ax, 5., 14.).Shape();
        TopoDS_Shape src = BRepAlgoAPI_Cut(box, hole).Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.02, r);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            Counts c = FaceKinds(out);
            chk("closed solid", r.closed == 1);
            chk("6 planes + 1 cylinder", c.planes == 6 && c.cyl == 1,
                std::to_string(c.planes) + "pl " + std::to_string(c.cyl) +
                    "cy " + std::to_string(c.other) + "other");
            const double want = 40. * 40. * 12. - M_PI * 25. * 12.;
            chk("volume", std::fabs(Volume(out) - want) / want < 2e-3,
                std::to_string(Volume(out)) + " want " + std::to_string(want));
        }
    }
    // ---- 6. inside-out box ----------------------------------------------
    {
        std::printf("== box with reversed winding ==\n");
        TopoDS_Shape src = BRepPrimAPI_MakeBox(10., 10., 10.).Shape();
        std::vector<double> xyz;
        std::vector<int> tri;
        Tessellate(src, 0.05, xyz, tri);
        for (size_t i = 0; i < tri.size(); i += 3)
            std::swap(tri[i + 1], tri[i + 2]);
        meshrecon::Params p = meshrecon::Defaults();
        meshrecon::Report r;
        std::string err;
        TopoDS_Shape out = meshrecon::Reconstruct(
            xyz.data(), (int)(xyz.size() / 3), tri.data(),
            (int)(tri.size() / 3), p, r, err);
        report(r);
        chk("built something", !out.IsNull(), err);
        if (!out.IsNull()) {
            chk("volume is POSITIVE 1000",
                std::fabs(Volume(out) - 1000.) < 1e-6,
                std::to_string(Volume(out)));
        }
    }
    // ---- 7. faceted mode -------------------------------------------------
    {
        std::printf("== faceted mode on a box ==\n");
        TopoDS_Shape src = BRepPrimAPI_MakeBox(10., 10., 10.).Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.05, r, 0);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            chk("volume 1000", std::fabs(Volume(out) - 1000.) < 1e-6,
                std::to_string(Volume(out)));
            Counts c = FaceKinds(out);
            chk("coplanar merge got it to 6", c.total == 6,
                std::to_string(c.total));
        }
    }
    // ---- 8. filleted block (the hard one) --------------------------------
    {
        std::printf("== block with 3mm fillets on the vertical edges ==\n");
        TopoDS_Shape box = BRepPrimAPI_MakeBox(30., 30., 15.).Shape();
        BRepFilletAPI_MakeFillet fil(box);
        for (TopExp_Explorer ex(box, TopAbs_EDGE); ex.More(); ex.Next()) {
            const TopoDS_Edge e = TopoDS::Edge(ex.Current());
            Standard_Real f, l;
            Handle(Geom_Curve) c = BRep_Tool::Curve(e, f, l);
            if (c.IsNull())
                continue;
            gp_Pnt p1 = c->Value(f), p2 = c->Value(l);
            if (std::fabs(p1.Z() - p2.Z()) > 1e-6)
                fil.Add(3., e);
        }
        TopoDS_Shape src;
        try {
            src = fil.Shape();
        } catch (...) {
        }
        if (src.IsNull()) {
            std::printf("   (fillet failed, skipped)\n");
        } else {
            meshrecon::Report r;
            TopoDS_Shape out = Run(src, 0.01, r);
            report(r);
            chk("built something", !out.IsNull());
            if (!out.IsNull()) {
                Counts c = FaceKinds(out);
                chk("closed solid", r.closed == 1);
                chk("6 planes + 4 fillet cylinders",
                    c.planes == 6 && c.cyl == 4,
                    std::to_string(c.planes) + "pl " + std::to_string(c.cyl) +
                        "cy");
                // Compare against the MESH, not the original solid: the mesh is
                // the whole of the converter's evidence.
                chk("volume tracks the mesh",
                    std::fabs(Volume(out) - g_meshVolume) / g_meshVolume < 5e-3,
                    std::to_string(Volume(out)) + " mesh " +
                        std::to_string(g_meshVolume) + " src " +
                        std::to_string(Volume(src)));
                chk("valid", BRepCheck_Analyzer(out).IsValid());
            }
        }
    }
    // ---- 9. a cone on a cylinder: the shape that killed the app ---------
    //
    // A tapered post -- a nozzle, a pin, a chamfered boss -- is ordinary in a
    // printed part and was fatal. ShapeFix_Face::Perform runs
    // FixPeriodicDegenerated, which fires on a CONICAL face whose one wire
    // wraps the full 2*pi, and that function ends with an unguarded
    //
    //     Context()->Replace(myFace, myResult);
    //
    // while ShapeFix_Face -- unlike ShapeFix_Shape and ShapeFix_Shell -- never
    // creates a context of its own. Null dereference, SIGSEGV, no exception to
    // catch: the app was simply gone, with no crash report and a log that
    // stopped mid-import. Still unguarded in the 7.9.3 we pin, so the fix is on
    // our side: hand the tool a context. This case reproduced it at every
    // deflection tried.
    {
        std::printf("== cone fused on a cylinder (ShapeFix context) ==\n");
        TopoDS_Shape src =
            BRepAlgoAPI_Fuse(
                BRepPrimAPI_MakeCylinder(4., 10.).Shape(),
                BRepPrimAPI_MakeCone(gp_Ax2(gp_Pnt(0, 0, 10), gp_Dir(0, 0, 1)),
                                     4., 0., 10.)
                    .Shape())
                .Shape();
        for (double defl : {0.4, 0.05}) {
            meshrecon::Report r;
            TopoDS_Shape out = Run(src, defl, r);
            report(r);
            chk("survives the cone face", !out.IsNull(),
                "deflection " + std::to_string(defl));
            chk("recovers cone surfaces", r.cones > 0,
                std::to_string(r.cones) + " cones");
        }
    }

    // ---- scale, and input broken the way downloads are broken -----------

    // A part with many features: a plate with a grid of holes and some bosses.
    TopoDS_Shape part = BRepPrimAPI_MakeBox(120., 80., 10.).Shape();
    for (int i = 0; i < 5; ++i)
        for (int j = 0; j < 3; ++j) {
            gp_Ax2 ax(gp_Pnt(15. + i * 22.5, 15. + j * 25., -1.),
                      gp_Dir(0, 0, 1));
            part = BRepAlgoAPI_Cut(
                       part, BRepPrimAPI_MakeCylinder(ax, 4., 12.).Shape())
                       .Shape();
        }
    for (int i = 0; i < 3; ++i) {
        gp_Ax2 ax(gp_Pnt(25. + i * 35., 45., 10.), gp_Dir(0, 0, 1));
        part = BRepAlgoAPI_Fuse(part,
                                BRepPrimAPI_MakeCylinder(ax, 6., 14.).Shape())
                   .Shape();
    }
    int srcFaces = 0;
    for (TopExp_Explorer ex(part, TopAbs_FACE); ex.More(); ex.Next())
        srcFaces++;
    GProp_GProps gs;
    BRepGProp::VolumeProperties(part, gs);

    for (double defl : {0.2, 0.05, 0.01}) {
        std::vector<double> xyz;
        std::vector<int> tri;
        Tessellate(part, defl, xyz, tri);
        meshrecon::Params p = meshrecon::Defaults();
        meshrecon::Report r;
        std::string err;
        const auto t0 = std::chrono::steady_clock::now();
        TopoDS_Shape out = meshrecon::Reconstruct(
            xyz.data(), (int)(xyz.size() / 3), tri.data(),
            (int)(tri.size() / 3), p, r, err);
        const double ms = std::chrono::duration<double, std::milli>(
                              std::chrono::steady_clock::now() - t0)
                              .count();
        int nf = 0;
        for (TopExp_Explorer ex(out, TopAbs_FACE); ex.More(); ex.Next())
            nf++;
        double vol = 0;
        if (!out.IsNull()) {
            GProp_GProps g;
            BRepGProp::VolumeProperties(out, g);
            vol = g.Mass();
        }
        std::printf(
            "defl %.2f: %7d tri -> %3d faces (src %d)  %6.0f ms  "
            "patches %d pl %d cy %d built %d failed %d faceted %d  solid %d  "
            "vol %.1f (src %.1f)  %s\n",
            defl, (int)(tri.size() / 3), nf, srcFaces, ms, r.patches, r.planes,
            r.cylinders, r.faces_built, r.faces_failed, r.faceted_patches,
            r.closed, vol, gs.Mass(), err.c_str());
        chk("built", !out.IsNull(), err);
        chk("closed solid", r.closed == 1);
        chk("face count matches the source", nf == srcFaces,
            std::to_string(nf) + " vs " + std::to_string(srcFaces));
        chk("volume", std::fabs(vol - gs.Mass()) / gs.Mass() < 5e-3,
            std::to_string(vol));
        chk("valid", !out.IsNull() && BRepCheck_Analyzer(out).IsValid());
    }

    // ---- robustness: input that is broken the way downloads are broken ----
    {
        meshrecon::Params p = meshrecon::Defaults();
        meshrecon::Report r;
        std::string err;
        chk("empty input returns null, not a crash",
            meshrecon::Reconstruct(nullptr, 0, nullptr, 0, p, r, err).IsNull());
        double one[9] = {0, 0, 0, 1, 0, 0, 0, 1, 0};
        int t1[3] = {0, 1, 2};
        meshrecon::Reconstruct(one, 3, t1, 1, p, r, err); // must not crash
        int bad[3] = {0, 1, 99};                          // out-of-range index
        chk("out-of-range indices are refused",
            meshrecon::Reconstruct(one, 3, bad, 1, p, r, err).IsNull());
        double flat[9] = {0, 0, 0, 1, 0, 0, 2, 0, 0}; // zero-area
        chk("degenerate triangle is refused",
            meshrecon::Reconstruct(flat, 3, t1, 1, p, r, err).IsNull());
        // Duplicated, unwelded vertices: an STL triangle soup.
        std::vector<double> xyz;
        std::vector<int> tri;
        Tessellate(BRepPrimAPI_MakeBox(10., 10., 10.).Shape(), 0.1, xyz, tri);
        std::vector<double> soup;
        std::vector<int> stri;
        for (size_t i = 0; i < tri.size(); ++i) {
            soup.push_back(xyz[tri[i] * 3]);
            soup.push_back(xyz[tri[i] * 3 + 1]);
            soup.push_back(xyz[tri[i] * 3 + 2]);
            stri.push_back((int)i);
        }
        meshrecon::Report r2;
        TopoDS_Shape out = meshrecon::Reconstruct(
            soup.data(), (int)(soup.size() / 3), stri.data(),
            (int)(stri.size() / 3), p, r2, err);
        chk("unwelded soup welds and closes", r2.closed == 1,
            std::to_string(r2.vertices_in) + "->" +
                std::to_string(r2.vertices_welded));
        chk("welded to 8 corners", r2.vertices_welded == 8,
            std::to_string(r2.vertices_welded));
    }

    std::printf("\n%s  (%d passed, %d failed)\n",
                fails == 0 ? "ALL PASSED" : "FAILURES", passes, fails);
    return fails == 0 ? 0 : 1;
}
