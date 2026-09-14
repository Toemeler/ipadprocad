/* Will a kernel actually OPERATE on this body?
 *
 *   occt_boolean_check body.brep [label]
 *
 * cad_audit asks whether the body is valid and whether its faces cross. This
 * asks the question a user asks, which is not the same one and is harder:
 * cut the thing in half and see what comes back. It is the commonest next
 * step after an import, and it is the first operation that fails on a body
 * that looks fine.
 *
 * M440. The distinction is not academic. Measured across the corpus, every
 * body that certifies clean cuts to half its volume with a valid result in
 * tens of milliseconds. The three that do not certify all report the cut as
 * DONE and return rubbish:
 *
 *   butterfly   2 faces and 0.8 mm3 of a 6,296 mm3 part — the model is gone
 *   whale       39 faces and 26% of its volume where half was asked for
 *   Bunny       219,756 faces and 1,221% of the volume it started with,
 *               after three and a quarter minutes
 *
 * So `IsDone()` is not the test and neither is an exception. The test is
 * whether the ANSWER is the right size and whether it is valid, and a
 * converter that is production-ready has to pass this one on every model it
 * accepts. Anything else ships a body that draws correctly and destroys
 * itself the first time someone uses it.
 *
 * The tool is deliberately blunt: one cut, with a box covering the lower half
 * of the body's own bounding box and grown well past it sideways, so the
 * expected volume is known without knowing the model. Exit code 0 only when
 * the cut is done, the result is valid, and its volume is between 20% and 80%
 * of the input — a cut that removed nothing or everything did not work.
 *
 * Host only, built with OCCT_SMOKE. Never linked into the app. */
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <TopExp_Explorer.hxx>
#include <gp_Pnt.hxx>

#include <chrono>
#include <cmath>
#include <cstdio>

namespace {
int FaceCount(const TopoDS_Shape &s)
{
    int n = 0;
    for (TopExp_Explorer e(s, TopAbs_FACE); e.More(); e.Next())
        ++n;
    return n;
}
} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s body.brep [label]\n", argv[0]);
        return 2;
    }
    const char *label = argc > 2 ? argv[2] : argv[1];

    TopoDS_Shape s;
    BRep_Builder b;
    if (!BRepTools::Read(s, argv[1], b) || s.IsNull()) {
        std::fprintf(stderr, "cannot read %s\n", argv[1]);
        return 1;
    }

    Bnd_Box bb;
    BRepBndLib::AddOptimal(s, bb, Standard_False, Standard_False);
    if (bb.IsVoid()) {
        std::fprintf(stderr, "empty body\n");
        return 1;
    }
    Standard_Real x0, y0, z0, x1, y1, z1;
    bb.Get(x0, y0, z0, x1, y1, z1);
    const double dx = x1 - x0, dy = y1 - y0, dz = z1 - z0;
    const gp_Pnt lo(x0 - dx * 0.1, y0 - dy * 0.1, z0 - dz * 0.1);
    const gp_Pnt hi(x1 + dx * 0.1, y1 + dy * 0.1, z0 + dz * 0.5);

    double volIn = 0;
    try {
        GProp_GProps g;
        BRepGProp::VolumeProperties(s, g);
        volIn = std::fabs(g.Mass());
    } catch (const Standard_Failure &) {
    }

    const auto t0 = std::chrono::steady_clock::now();
    bool done = false, valid = false;
    int faces = 0;
    double volOut = 0;
    const char *err = "";
    try {
        const TopoDS_Shape tool = BRepPrimAPI_MakeBox(lo, hi).Shape();
        BRepAlgoAPI_Cut cut(s, tool);
        cut.SetRunParallel(Standard_False);
        cut.Build();
        if (cut.IsDone() && !cut.Shape().IsNull()) {
            done = true;
            const TopoDS_Shape r = cut.Shape();
            faces = FaceCount(r);
            try {
                GProp_GProps g;
                BRepGProp::VolumeProperties(r, g);
                volOut = std::fabs(g.Mass());
            } catch (const Standard_Failure &) {
            }
            try {
                valid = BRepCheck_Analyzer(r, Standard_True).IsValid() ==
                        Standard_True;
            } catch (const Standard_Failure &) {
            } catch (...) {
            }
        } else {
            err = "the cut did not complete";
        }
    } catch (const Standard_Failure &e) {
        err = e.GetMessageString() ? e.GetMessageString() : "exception";
    } catch (...) {
        err = "exception";
    }
    const double ms = std::chrono::duration<double, std::milli>(
                          std::chrono::steady_clock::now() - t0)
                          .count();

    const double frac = volIn > 0 ? volOut / volIn : 0.0;
    const bool sane = done && valid && frac > 0.2 && frac < 0.8;
    std::printf("%-14s cut %-6s %8.0f ms  faces %7d  volume %.6g of %.6g "
                "(%.1f%%)  valid %d  %s%s\n",
                label, done ? "done" : "FAILED", ms, faces, volOut, volIn,
                100.0 * frac, valid ? 1 : 0, sane ? "USABLE" : "NOT USABLE",
                err);
    return sane ? 0 : 3;
}
