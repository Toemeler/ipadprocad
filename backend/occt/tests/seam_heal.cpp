/* Does re-deriving the edge tolerances shrink the seams a sewer inflated?
 *
 * The sewer sets an edge's tolerance to whatever it needed to bridge the gap
 * it found, and never revisits it. BRepLib::SameParameter recomputes the
 * tolerance each edge ACTUALLY needs against its pcurves, which is the same
 * question asked properly. If the seams are fat because of a guess rather than
 * because of the geometry, this is where that shows. */
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepLib.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <ShapeFix_Shape.hxx>
#include <ShapeUpgrade_ShapeDivideClosed.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_ListIteratorOfListOfShape.hxx>
#include <TopExp.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <vector>
#include <algorithm>
#include <utility>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Edge.hxx>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <string>

static double Diag(const TopoDS_Shape &s)
{
    Bnd_Box b; BRepBndLib::AddOptimal(s, b, Standard_False, Standard_False);
    if (b.IsVoid()) return 0;
    double a[6]; b.Get(a[0],a[1],a[2],a[3],a[4],a[5]);
    return std::sqrt((a[3]-a[0])*(a[3]-a[0])+(a[4]-a[1])*(a[4]-a[1])+
                     (a[5]-a[2])*(a[5]-a[2]));
}

static void Report(const char *tag, const TopoDS_Shape &s)
{
    const double d = Diag(s);
    int fat = 0, n = 0; double worst = 0;
    for (TopExp_Explorer e(s, TopAbs_EDGE); e.More(); e.Next()) {
        const double t = BRep_Tool::Tolerance(TopoDS::Edge(e.Current()));
        ++n; worst = std::max(worst, t);
        if (t > d * 1e-3) ++fat;
    }
    bool ok = false;
    try { ok = BRepCheck_Analyzer(s, Standard_True).IsValid() == Standard_True; }
    catch (const Standard_Failure &) {}
    std::printf("%-22s edges=%d fat=%d worst_tol=%.6f valid=%d\n", tag, n, fat,
                worst, ok ? 1 : 0);
}

int main(int argc, char **argv)
{
    if (argc < 3) { std::fprintf(stderr, "usage: heal in.brep out.brep\n"); return 2; }
    TopoDS_Shape s; BRep_Builder b;
    if (!BRepTools::Read(s, argv[1], b) || s.IsNull()) {
        std::fprintf(stderr, "cannot read\n"); return 1;
    }
    Report("as built", s);

    /* WHERE the fattest seams are, and between what. A body-wide worst
     * tolerance says the patches do not meet; the faces on either side of that
     * edge say whether it is two fitted surfaces disagreeing — which is
     * architectural — or a fitted surface against a FACETED region, which the
     * chain builder has a dedicated path for and would be a bug. */
    {
        TopTools_IndexedDataMapOfShapeListOfShape e2f;
        TopExp::MapShapesAndAncestors(s, TopAbs_EDGE, TopAbs_FACE, e2f);
        std::vector<std::pair<double, int>> byTol;
        for (int i = 1; i <= e2f.Extent(); ++i)
            byTol.push_back(std::make_pair(
                BRep_Tool::Tolerance(TopoDS::Edge(e2f.FindKey(i))), i));
        std::sort(byTol.rbegin(), byTol.rend());
        for (int k = 0; k < 8 && k < (int)byTol.size(); ++k) {
            const int i = byTol[k].second;
            std::string kinds;
            for (TopTools_ListIteratorOfListOfShape it(e2f(i)); it.More();
                 it.Next()) {
                BRepAdaptor_Surface ad(TopoDS::Face(it.Value()), Standard_False);
                kinds += kinds.empty() ? "" : "+";
                switch (ad.GetType()) {
                case GeomAbs_Plane: kinds += "plane"; break;
                case GeomAbs_Cylinder: kinds += "cyl"; break;
                case GeomAbs_BSplineSurface: kinds += "bspline"; break;
                default: kinds += "other"; break;
                }
            }
            double len = 0;
            try { GProp_GProps g;
                  BRepGProp::LinearProperties(e2f.FindKey(i), g);
                  len = g.Mass(); } catch (const Standard_Failure &) {}
            std::printf("  fat edge tol=%.6f len=%.4f between %s\n",
                        byTol[k].first, len, kinds.c_str());
        }
    }

    const double d = Diag(s);
    try {
        BRepLib::SameParameter(s, d * 1e-5, Standard_True);
        Report("SameParameter 1e-5", s);
    } catch (const Standard_Failure &e) {
        std::printf("SameParameter raised: %s\n",
                    e.GetMessageString() ? e.GetMessageString() : "?");
    }
    try {
        Handle(ShapeFix_Shape) fx = new ShapeFix_Shape(s);
        fx->SetPrecision(d * 1e-5);
        fx->SetMaxTolerance(d * 1e-3);
        fx->Perform();
        if (!fx->Shape().IsNull()) { s = fx->Shape(); Report("ShapeFix_Shape", s); }
    } catch (const Standard_Failure &e) {
        std::printf("ShapeFix raised: %s\n",
                    e.GetMessageString() ? e.GetMessageString() : "?");
    }
    BRepTools::Write(s, argv[2]);
    return 0;
}
