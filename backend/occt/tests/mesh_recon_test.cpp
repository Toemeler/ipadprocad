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
#include <BRepAlgoAPI_Common.hxx>
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
#include <algorithm>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_GTransform.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <Bnd_Box.hxx>
#include <gp_GTrsf.hxx>
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
static double g_meshDiag = 0;
static double g_meshLo[3], g_meshHi[3];

/* How far outside the MESH's own bounding box the built shape reaches.
 *
 * The number that matters for a face that lost its trimming: an untrimmed
 * plane is infinite, so it shows up here as an overshoot the size of the whole
 * model, and in the viewer as a shard with edges running to the horizon and a
 * bounding box that grows on every re-tessellation. */
static double Overshoot(const TopoDS_Shape &out)
{
    if (out.IsNull())
        return 0;
    /* AddOptimal: the cheap box is built from the curves' POLES, and a
     * spline's control polygon stands outside the curve — on a fitted shell
     * that read as 28% of the model when the truth was zero. */
    Bnd_Box b;
    BRepBndLib::AddOptimal(out, b, Standard_False, Standard_False);
    if (b.IsVoid())
        return 0;
    Standard_Real x0, y0, z0, x1, y1, z1;
    b.Get(x0, y0, z0, x1, y1, z1);
    const double f[6] = {g_meshLo[0] - x0, g_meshLo[1] - y0, g_meshLo[2] - z0,
                         x1 - g_meshHi[0], y1 - g_meshHi[1], z1 - g_meshHi[2]};
    double worst = 0;
    for (int k = 0; k < 6; ++k)
        worst = std::max(worst, f[k]);
    return worst;
}

static TopoDS_Shape Run(const TopoDS_Shape &src, double defl,
                        meshrecon::Report &rep, int mode = 1)
{
    std::vector<double> xyz;
    std::vector<int> tri;
    Tessellate(src, defl, xyz, tri);
    g_meshVolume = std::fabs(MeshVolume(xyz, tri));
    for (int k = 0; k < 3; ++k) {
        g_meshLo[k] = 1e300;
        g_meshHi[k] = -1e300;
    }
    for (size_t i = 0; i < xyz.size(); i += 3)
        for (int k = 0; k < 3; ++k) {
            g_meshLo[k] = std::min(g_meshLo[k], xyz[i + k]);
            g_meshHi[k] = std::max(g_meshHi[k], xyz[i + k]);
        }
    g_meshDiag =
        std::sqrt((g_meshHi[0] - g_meshLo[0]) * (g_meshHi[0] - g_meshLo[0]) +
                  (g_meshHi[1] - g_meshLo[1]) * (g_meshHi[1] - g_meshLo[1]) +
                  (g_meshHi[2] - g_meshLo[2]) * (g_meshHi[2] - g_meshLo[2]));
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
            /* Plane against plane is closed-form in OCCT and must stay on the
             * exact path: the guard that keeps GeomAPI_IntSS off the quadric
             * pairs it can hang on must not cost a box its straight edges. */
            chk("edges still built exactly", r.analytic_edges >= 6,
                std::to_string(r.analytic_edges) + " exact");
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
            /* Two of these come off plane against CYLINDER — the hole's two
             * rims, real circles. That pair also has to stay exact. */
            chk("hole rims and box edges exact", r.analytic_edges >= 8,
                std::to_string(r.analytic_edges) + " exact");
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
                chk("nothing reaches outside the mesh",
                    Overshoot(out) < g_meshDiag * 0.02,
                    std::to_string(Overshoot(out)) + " mm");
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
        {
            meshrecon::Report r;
            TopoDS_Shape out = Run(src, 0.4, r);
            report(r);
            chk("survives the cone face", !out.IsNull());
            chk("still a closed solid", r.closed == 1);
            chk("and recognised, coarse as it is",
                r.planes == 1 && r.cylinders == 1 && r.cones == 1,
                std::to_string(r.planes) + "pl " +
                    std::to_string(r.cylinders) + "cy " +
                    std::to_string(r.cones) + "co");
        }
    }
    // ---- 10. the same post, tessellated finely: crease splitting ---------
    //
    // The cylinder meets the cone at 21.8 degrees — under the 22-degree sharp
    // threshold, so the two arrive as ONE smooth patch that fits no primitive.
    // Region growing alone came apart on it: every seed near the crease
    // straddles both surfaces, and a barrel came out as a fan of thirty planar
    // strips, open. SplitAtCrease reads the patch's own dihedral distribution
    // and cuts the one ring that stands above the tessellation step.
    {
        std::printf("== tapered post, 21.8 degree crease ==\n");
        TopoDS_Shape src =
            BRepAlgoAPI_Fuse(
                BRepPrimAPI_MakeCylinder(4., 10.).Shape(),
                BRepPrimAPI_MakeCone(gp_Ax2(gp_Pnt(0, 0, 10), gp_Dir(0, 0, 1)),
                                     4., 0., 10.)
                    .Shape())
                .Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.02, r);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            Counts c = FaceKinds(out);
            chk("closed solid", r.closed == 1);
            chk("exactly disc + barrel + cone",
                c.total == 3 && c.planes == 1 && c.cyl == 1 && c.cone == 1,
                std::to_string(c.total) + " faces: " +
                    std::to_string(c.planes) + "pl " + std::to_string(c.cyl) +
                    "cy " + std::to_string(c.cone) + "co");
            chk("volume tracks the mesh",
                std::fabs(Volume(out) - g_meshVolume) / g_meshVolume < 5e-3,
                std::to_string(Volume(out)) + " mesh " +
                    std::to_string(g_meshVolume));
            chk("valid", BRepCheck_Analyzer(out).IsValid());
        }
    }

    // ---- 11. two parallel cylinders fused --------------------------------
    //
    // Their barrels are adjacent, so the edge builder is asked where two
    // parallel cylinders meet. GeomAPI_IntSS has no time bound and its
    // implicit-implicit path can grind on a quadric pair for minutes — on a
    // 444-triangle mesh it had not finished after ninety seconds, which on an
    // iPad is a frozen app the watchdog kills. IntersectablePair keeps that
    // pair off the analytic path; the seam becomes a curve through the mesh
    // points, which is what it would have been anyway.
    {
        std::printf("== two parallel cylinders fused ==\n");
        TopoDS_Shape src =
            BRepAlgoAPI_Fuse(
                BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)),
                                         5., 20.)
                    .Shape(),
                BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(6, 0, 0), gp_Dir(0, 0, 1)),
                                         3., 20.)
                    .Shape())
                .Shape();
        meshrecon::Report r;
        const auto t0 = std::chrono::steady_clock::now();
        TopoDS_Shape out = Run(src, 0.05, r);
        const double ms = std::chrono::duration<double, std::milli>(
                              std::chrono::steady_clock::now() - t0)
                              .count();
        report(r);
        std::printf("   %.0f ms\n", ms);
        chk("built something", !out.IsNull());
        chk("closed solid", r.closed == 1);
        chk("two barrels and two flats", r.cylinders == 2 && r.planes == 2,
            std::to_string(r.cylinders) + "cy " + std::to_string(r.planes) +
                "pl");
        /* Generous by two orders of magnitude against the ~10 ms it takes;
         * this fails only if the analytic path is let back onto the pair. */
        chk("converts promptly", ms < 5000.0, std::to_string(ms) + " ms");
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

    // ---- 12. an ORGANIC model, which fits no primitive anywhere ---------
    //
    // Every case above is prismatic, and a real download often is not: the file
    // this milestone was built for turned out to be a curved shell. On one of
    // those the fitter has nothing to recognise. It shattered into one patch
    // per handful of triangles, none of them meeting — and worse, some of those
    // faces lost their trimming, so an untrimmed plane reached nearly THREE
    // TIMES the model's own diagonal outside it: shards across the viewport
    // with edges running off screen, and a bounding box that grew every time
    // the viewer re-tessellated.
    //
    // Two things stop that. A face that escapes its own triangles is refused
    // and its patch goes faceted; and a fitted shell that will not close is
    // dropped for the faceted build when THAT closes. One face per triangle
    // recognises nothing, but on a watertight mesh it cannot fail, and a heavy
    // solid the user can cut and fillet beats a light shell they cannot.
    {
        std::printf("== organic: an ellipsoid, no primitive anywhere ==\n");
        gp_GTrsf g;
        g.SetValue(1, 1, 1.0);
        g.SetValue(2, 2, 2.2);
        g.SetValue(3, 3, 0.45);
        TopoDS_Shape src =
            BRepBuilderAPI_GTransform(BRepPrimAPI_MakeSphere(20.).Shape(), g,
                                      Standard_True)
                .Shape();
        for (double defl : {1.2, 0.4}) {
            meshrecon::Report r;
            const auto t0 = std::chrono::steady_clock::now();
            TopoDS_Shape out = Run(src, defl, r);
            const double ms = std::chrono::duration<double, std::milli>(
                                  std::chrono::steady_clock::now() - t0)
                                  .count();
            report(r);
            std::printf("   %.0f ms\n", ms);
            chk("built something", !out.IsNull());
            chk("closed solid", r.closed == 1);
            /* The faceted shell is built with ONE vertex per welded mesh
             * vertex and ONE edge per mesh edge, so it is sewn by
             * construction. Handing loose triangles to BRepBuilderAPI_Sewing
             * instead — which is what this did first — makes OCCT rediscover
             * by geometric search the adjacency this code already knows, at
             * about a millisecond per triangle: 43 seconds for 40 000
             * triangles, and on an iPad that is the app gone. The ceiling is
             * ten times the measured cost and a fifth of the old one, so it
             * separates the two without being flaky on a slow runner. */
            chk("converts in linear time", ms < 5000.0,
                std::to_string(ms) + " ms for " +
                    std::to_string(r.triangles_used) + " triangles");
            chk("nothing reaches outside the mesh",
                Overshoot(out) < g_meshDiag * 0.02,
                std::to_string(Overshoot(out)) + " mm of " +
                    std::to_string(g_meshDiag));
            chk("volume is the mesh's own",
                std::fabs(Volume(out) - g_meshVolume) / g_meshVolume < 1e-6,
                std::to_string(Volume(out)) + " mesh " +
                    std::to_string(g_meshVolume));
        }

        /* And the same blob with a HOLE in it. Downloaded meshes often are not
         * watertight, and then NOTHING closes — so "take the faceted build if
         * it closes" would leave the shards in place, which is the state the
         * user was looking at. What decides it instead is whether the fitted
         * pass read the model at all. Here it does: fifty patches over 1770
         * triangles is thirty-five triangles a face, a reading. The file that
         * exposed this managed six, and that is not one. */
        {
            std::vector<double> xyz;
            std::vector<int> tri;
            Tessellate(src, 1.2, xyz, tri);
            for (int k = 0; k < 3; ++k) {
                g_meshLo[k] = 1e300;
                g_meshHi[k] = -1e300;
            }
            for (size_t i = 0; i < xyz.size(); i += 3)
                for (int k = 0; k < 3; ++k) {
                    g_meshLo[k] = std::min(g_meshLo[k], xyz[i + k]);
                    g_meshHi[k] = std::max(g_meshHi[k], xyz[i + k]);
                }
            g_meshDiag = std::sqrt(
                (g_meshHi[0] - g_meshLo[0]) * (g_meshHi[0] - g_meshLo[0]) +
                (g_meshHi[1] - g_meshLo[1]) * (g_meshHi[1] - g_meshLo[1]) +
                (g_meshHi[2] - g_meshLo[2]) * (g_meshHi[2] - g_meshLo[2]));
            tri.resize(tri.size() - 3 * 40); /* punch a hole */
            meshrecon::Params p = meshrecon::Defaults();
            meshrecon::Report r;
            std::string err;
            TopoDS_Shape out = meshrecon::Reconstruct(
                xyz.data(), (int)(xyz.size() / 3), tri.data(),
                (int)(tri.size() / 3), p, r, err);
            report(r);
            chk("an open organic mesh still builds", !out.IsNull(), err);
            chk("and nothing reaches outside it",
                Overshoot(out) < g_meshDiag * 0.02,
                std::to_string(Overshoot(out)) + " mm of " +
                    std::to_string(g_meshDiag));
        }
    }

    // ---- 13. a curved shell with REAL holes in it ------------------------
    //
    // The case the user was actually looking at, and the one that made the
    // all-or-nothing fallback indefensible: a shell that fits no primitive
    // anywhere, drilled with holes that are exactly what they look like. The
    // fitted pass shatters on the shell and is right about the holes, so the
    // decision has to be made per PATCH: the holes keep their cylinders, the
    // shell goes to triangles, and neither is thrown away because of the other.
    //
    // What separates a real hole from a strip of the shell is not the residual
    // — on a squashed sphere a strip fits a cylinder to a fiftieth of tolerance
    // — but where the patch came from. A hole arrives as a whole smooth patch
    // bounded by its own rim; a strip is one of the pieces a smooth region was
    // broken into.
    {
        std::printf("== a curved shell with four real holes ==\n");
        gp_GTrsf g;
        g.SetValue(1, 1, 1.0);
        g.SetValue(2, 2, 1.7);
        g.SetValue(3, 3, 0.55);
        TopoDS_Shape src =
            BRepAlgoAPI_Cut(
                BRepBuilderAPI_GTransform(BRepPrimAPI_MakeSphere(30.).Shape(), g,
                                          Standard_True)
                    .Shape(),
                BRepBuilderAPI_GTransform(BRepPrimAPI_MakeSphere(27.).Shape(), g,
                                          Standard_True)
                    .Shape())
                .Shape();
        src = BRepAlgoAPI_Common(
                  src, BRepPrimAPI_MakeBox(gp_Pnt(-60, -60, 0),
                                           gp_Pnt(60, 60, 60))
                           .Shape())
                  .Shape();
        const double rad[4] = {2., 3., 4., 5.};
        const double hx[4] = {-14, 14, -14, 14}, hy[4] = {-22, -22, 22, 22};
        for (int i = 0; i < 4; ++i)
            src = BRepAlgoAPI_Cut(
                      src, BRepPrimAPI_MakeCylinder(
                               gp_Ax2(gp_Pnt(hx[i], hy[i], -50), gp_Dir(0, 0, 1)),
                               rad[i], 200.)
                               .Shape())
                      .Shape();

        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.4, r);
        report(r);
        chk("built something", !out.IsNull());
        chk("the four holes are cylinders", r.cylinders == 4,
            std::to_string(r.cylinders) + " cylinders");
        chk("and nothing was invented on the shell", r.spheres == 0,
            std::to_string(r.spheres) + " spheres");
        chk("the shell itself went to triangles", r.faceted_patches > 10,
            std::to_string(r.faceted_patches) + " faceted patches");
        if (!out.IsNull()) {
            std::vector<double> radii;
            for (TopExp_Explorer ex(out, TopAbs_FACE); ex.More(); ex.Next()) {
                BRepAdaptor_Surface sa(TopoDS::Face(ex.Current()));
                if (sa.GetType() == GeomAbs_Cylinder)
                    radii.push_back(sa.Cylinder().Radius());
            }
            std::sort(radii.begin(), radii.end());
            bool exact = radii.size() == 4;
            for (size_t i = 0; i < radii.size() && exact; ++i)
                exact = std::fabs(radii[i] - rad[i]) < 1e-4;
            std::string got;
            for (double x : radii)
                got += std::to_string(x) + " ";
            chk("with their true radii, to four decimals", exact, got);
            chk("nothing reaches outside the mesh",
                Overshoot(out) < g_meshDiag * 0.02,
                std::to_string(Overshoot(out)) + " mm");
        }
    }

    // ---- 14. the same post at every taper, which greedy growing could not --
    //
    // A cylinder into a cone, swept from a 6-degree taper to a 63-degree one.
    // Region growing was right at the ends and hopeless in the middle — 24 and
    // 26 patches at 9 and 15 degrees, open shells both — because the first
    // seed off a tessellated barrel is a PLANE that fits three columns to well
    // inside tolerance, and once it has committed there is no way back.
    //
    // RANSAC does not commit. It proposes candidates from random seeds and
    // scores each against the whole patch, so the plane's three columns lose
    // to the cylinder's barrel on evidence. Every angle in the sweep now comes
    // back as exactly what it is.
    {
        std::printf("== a tapered post at every taper ==\n");
        for (double coneH : {40., 25., 15., 10., 6., 2.}) {
            TopoDS_Shape src =
                BRepAlgoAPI_Fuse(
                    BRepPrimAPI_MakeCylinder(4., 10.).Shape(),
                    BRepPrimAPI_MakeCone(
                        gp_Ax2(gp_Pnt(0, 0, 10), gp_Dir(0, 0, 1)), 4., 0., coneH)
                        .Shape())
                    .Shape();
            meshrecon::Report r;
            TopoDS_Shape out = Run(src, 0.02, r);
            const double halfAngle = std::atan(4.0 / coneH) * 180.0 / M_PI;
            std::printf("   %5.1f deg taper: ", halfAngle);
            report(r);
            chk("disc + barrel + cone, whatever the taper",
                r.planes == 1 && r.cylinders == 1 && r.cones == 1,
                std::to_string(halfAngle) + " deg: " +
                    std::to_string(r.planes) + "pl " +
                    std::to_string(r.cylinders) + "cy " +
                    std::to_string(r.cones) + "co");
            chk("closed solid", r.closed == 1,
                std::to_string(halfAngle) + " deg");
        }
    }

    // ---- what a DOWNLOADED mesh is, and none of the above was ------------
    //
    // Every fixture up to here came out of OCCT's own tessellator: closed,
    // manifold, consistently wound. A model off a print site is none of those
    // by default, and none of these may take the process down — a null result
    // and a reason is a fine answer, a signal is not. Ported from the
    // adversarial harness that was written while hunting the crash, so the
    // robustness it established cannot quietly rot.
    {
        std::printf("== broken the way downloads are broken ==\n");
        auto cube = [](std::vector<double> &v, double sz, double ox = 0,
                       double oy = 0, double oz = 0) {
            const double c[8][3] = {{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0},
                                    {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1}};
            for (int i = 0; i < 8; ++i) {
                v.push_back(ox + c[i][0] * sz);
                v.push_back(oy + c[i][1] * sz);
                v.push_back(oz + c[i][2] * sz);
            }
        };
        static const int kQuads[6][4] = {{0, 3, 2, 1}, {4, 5, 6, 7},
                                         {0, 1, 5, 4}, {1, 2, 6, 5},
                                         {2, 3, 7, 6}, {3, 0, 4, 7}};
        auto cubeTris = [](std::vector<int> &t, int base, int skip = -1) {
            for (int q = 0; q < 6; ++q) {
                if (q == skip)
                    continue;
                const int *f = kQuads[q];
                t.push_back(base + f[0]);
                t.push_back(base + f[1]);
                t.push_back(base + f[2]);
                t.push_back(base + f[0]);
                t.push_back(base + f[2]);
                t.push_back(base + f[3]);
            }
        };
        auto survives = [](const char *what, std::vector<double> xyz,
                           std::vector<int> tri) {
            meshrecon::Params p = meshrecon::Defaults();
            meshrecon::Report r;
            std::string err;
            bool ok = true;
            try {
                meshrecon::Reconstruct(xyz.data(), (int)(xyz.size() / 3),
                                       tri.data(), (int)(tri.size() / 3), p, r,
                                       err);
            } catch (...) {
                ok = false;
            }
            chk(what, ok, "threw out of Reconstruct");
        };

        {   // a hole: the top face simply missing
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20);
            cubeTris(t, 0, 1);
            survives("open shell", v, t);
        }
        {   // non-manifold: two cubes sharing a whole face
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20);
            cube(v, 20, 0, 0, 20);
            cubeTris(t, 0);
            cubeTris(t, 8);
            survives("non-manifold, two cubes on a shared face", v, t);
        }
        {   // every triangle present twice
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20);
            cubeTris(t, 0);
            const std::vector<int> d = t;
            t.insert(t.end(), d.begin(), d.end());
            survives("duplicate triangles", v, t);
        }
        {   // half the faces inside out
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20);
            cubeTris(t, 0);
            for (size_t i = 0; i < t.size(); i += 6)
                std::swap(t[i + 1], t[i + 2]);
            survives("mixed winding", v, t);
        }
        {   // a vertex on the middle of a neighbour's edge. Common in
            // converted and hand-made STLs, and it breaks the edge pairing
            // adjacency is built on.
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20);
            cubeTris(t, 0);
            v.push_back(10);
            v.push_back(0);
            v.push_back(0);
            t.push_back(0); t.push_back(8); t.push_back(4);
            t.push_back(8); t.push_back(1); t.push_back(5);
            survives("T-junction on an edge", v, t);
        }
        {   // two shells, far apart
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20);
            cube(v, 20, 500, 0, 0);
            cubeTris(t, 0);
            cubeTris(t, 8);
            survives("two disconnected shells", v, t);
        }
        {   // near-degenerate, but above the area threshold
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20);
            cubeTris(t, 0);
            v.push_back(0);  v.push_back(0);    v.push_back(0);
            v.push_back(20); v.push_back(0);    v.push_back(0);
            v.push_back(10); v.push_back(1e-4); v.push_back(0);
            t.push_back(8); t.push_back(9); t.push_back(10);
            survives("sliver triangle", v, t);
        }
        {   // a hundred triangles round one vertex, no cap
            std::vector<double> v{0, 0, 0};
            std::vector<int> t;
            const int n = 100;
            for (int i = 0; i < n; ++i) {
                const double a = 2 * M_PI * i / n;
                v.push_back(10 * std::cos(a));
                v.push_back(10 * std::sin(a));
                v.push_back(5);
            }
            for (int i = 0; i < n; ++i) {
                t.push_back(0);
                t.push_back(1 + i);
                t.push_back(1 + (i + 1) % n);
            }
            survives("open cone fan, no cap", v, t);
        }
        {   // STL coordinates often are
            std::vector<double> v;
            std::vector<int> t;
            cube(v, 20, 100000, 100000, 100000);
            cubeTris(t, 0);
            survives("far from the origin", v, t);
        }
        {   // nothing but one point
            survives("all vertices coincident",
                     {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}, {0, 1, 2, 1, 2, 3});
        }
        {   // no structure at all
            std::vector<double> v;
            std::vector<int> t;
            unsigned seed = 7;
            auto rnd = [&seed]() {
                seed = seed * 1103515245u + 12345u;
                return (seed >> 16) & 0x7fff;
            };
            for (int i = 0; i < 300; ++i)
                v.push_back((rnd() % 2000) / 100.0);
            const int nv = (int)(v.size() / 3);
            for (int i = 0; i < 200; ++i) {
                t.push_back(rnd() % nv);
                t.push_back(rnd() % nv);
                t.push_back(rnd() % nv);
            }
            survives("random triangle soup", v, t);
        }
    }

    // ---- 15. a torus, which nothing in this suite had ever asked for -----
    {
        std::printf("== a plain torus R=20 r=6 ==\n");
        for (double defl : {0.4, 0.1}) {
            TopoDS_Shape src = BRepPrimAPI_MakeTorus(20., 6.).Shape();
            meshrecon::Report r;
            TopoDS_Shape out = Run(src, defl, r);
            report(r);
            chk("built something", !out.IsNull());
            if (out.IsNull())
                continue;
            Counts c = FaceKinds(out);
            /* The old seed paired each normal with one a stride away and
             * intersected the lines. That finds a cylinder's axis; on a torus
             * a normal meets the SPINE, not the axis, so half the samples
             * landed in the wrong place and the fit came back R=16.1 r=16.1
             * against a truth of 20 and 6, at a residual of 4.6 mm on a mesh
             * with no noise in it. A torus was therefore never once
             * recognised, and every fillet ring — the only torus most parts
             * contain — came back as several hundred planes. */
            chk("one toroidal face", c.tor == 1 && c.total == 1,
                std::to_string(c.tor) + " tori of " +
                    std::to_string(c.total) + " faces");
            chk("closed solid", r.closed == 1);
            for (TopExp_Explorer ex(out, TopAbs_FACE); ex.More(); ex.Next()) {
                BRepAdaptor_Surface sa(TopoDS::Face(ex.Current()));
                if (sa.GetType() != GeomAbs_Torus)
                    continue;
                chk("with its true radii",
                    std::fabs(sa.Torus().MajorRadius() - 20.) < 1e-3 &&
                        std::fabs(sa.Torus().MinorRadius() - 6.) < 1e-3,
                    std::to_string(sa.Torus().MajorRadius()) + " / " +
                        std::to_string(sa.Torus().MinorRadius()));
            }
        }
    }
    // ---- 16. the plate a download actually looks like ---------------------
    {
        /* Rounded corners, a raised boss, five holes, and coarse enough that
         * its circles are twelve-sided — which is what came back from the
         * user's file with its corners in flat bands and its holes as prisms.
         *
         * Two things had to be true for this to work and neither was. RANSAC
         * fitted every candidate to a fixed forty-triangle neighbourhood, so
         * on a part whose fillets are twelve facets each every sample spanned
         * a fillet AND the wall it is tangent to, every fit failed, and the
         * side band came back with nothing found in it at all. And a merge
         * only had to stay within tolerance, so a fillet that HAD been found
         * was then fused with two triangles of that wall into a torus bent
         * round an axis that is nowhere in the part, which added 42% to the
         * model's volume. */
        std::printf("== coarse plate: rounded corners, boss, five holes ==\n");
        TopoDS_Shape box = BRepPrimAPI_MakeBox(60., 40., 6.).Shape();
        BRepFilletAPI_MakeFillet fil(box);
        TopTools_IndexedMapOfShape edges;
        TopExp::MapShapes(box, TopAbs_EDGE, edges);
        for (int i = 1; i <= edges.Extent(); ++i) {
            const TopoDS_Edge e = TopoDS::Edge(edges(i));
            gp_Pnt a = BRep_Tool::Pnt(TopExp::FirstVertex(e));
            gp_Pnt b = BRep_Tool::Pnt(TopExp::LastVertex(e));
            if (std::fabs(a.X() - b.X()) < 1e-7 &&
                std::fabs(a.Y() - b.Y()) < 1e-7)
                fil.Add(5., e); /* the four vertical corners */
        }
        TopoDS_Shape src = fil.Shape();
        src = BRepAlgoAPI_Fuse(
                  src, BRepPrimAPI_MakeCylinder(
                           gp_Ax2(gp_Pnt(30., 20., 6.), gp_Dir(0, 0, 1)), 9.,
                           4.)
                           .Shape())
                  .Shape();
        const double hx[5] = {30., 10., 50., 10., 50.};
        const double hy[5] = {20., 8., 8., 32., 32.};
        const double hr[5] = {4.5, 2.2, 2.2, 2.2, 2.2};
        for (int i = 0; i < 5; ++i)
            src = BRepAlgoAPI_Cut(
                      src,
                      BRepPrimAPI_MakeCylinder(
                          gp_Ax2(gp_Pnt(hx[i], hy[i], -1.), gp_Dir(0, 0, 1)),
                          hr[i], 20.)
                          .Shape())
                      .Shape();
        meshrecon::Report r;
        TopoDS_Shape out = Run(src, 0.25, r);
        report(r);
        chk("built something", !out.IsNull());
        if (!out.IsNull()) {
            Counts c = FaceKinds(out);
            chk("closed solid", r.closed == 1);
            chk("nothing went to triangles", r.faceted_patches == 0,
                std::to_string(r.faceted_patches) + " faceted");
            /* 7 planes: top, bottom, four walls, boss top.
             * 10 cylinders: four corner fillets, five holes, the boss. */
            chk("7 planes and 10 cylinders, and nothing else",
                c.planes == 7 && c.cyl == 10 && c.total == 17,
                std::to_string(c.planes) + "pl " + std::to_string(c.cyl) +
                    "cy of " + std::to_string(c.total));
            std::vector<double> radii;
            for (TopExp_Explorer ex(out, TopAbs_FACE); ex.More(); ex.Next()) {
                BRepAdaptor_Surface sa(TopoDS::Face(ex.Current()));
                if (sa.GetType() == GeomAbs_Cylinder)
                    radii.push_back(sa.Cylinder().Radius());
            }
            std::sort(radii.begin(), radii.end());
            const double want[10] = {2.2, 2.2, 2.2, 2.2, 4.5,
                                     5.0, 5.0, 5.0, 5.0, 9.0};
            bool exact = radii.size() == 10;
            std::string got;
            for (size_t i = 0; i < radii.size(); ++i) {
                got += std::to_string(radii[i]) + " ";
                if (i < 10 && std::fabs(radii[i] - want[i]) > 1e-4)
                    exact = false;
            }
            chk("every radius exact: four fillets, five holes, the boss",
                exact, got);
            const double v = Volume(out);
            chk("volume", std::fabs(v - g_meshVolume) / g_meshVolume < 1e-3,
                std::to_string(v) + " mesh " + std::to_string(g_meshVolume));
        }
    }

    std::printf("\n%s  (%d passed, %d failed)\n",
                fails == 0 ? "ALL PASSED" : "FAILURES", passes, fails);
    return fails == 0 ? 0 : 1;
}
