# Freeform charts — where this stands

Three attempts at Stage 1/2 of the freeform plan, all measured on the whale
(83,178 triangles, tolerance 0.4079, 204 mm diagonal).

| variant                   | volume err | faces  | failed | free edges | closed | time  |
|---------------------------|-----------:|-------:|-------:|-----------:|:------:|------:|
| shipping (grid, build 519)|    -1.21%  |    305 |      0 |          0 |  yes   |  24 s |
| charts everywhere         |    -0.06%  | 12,140 |     21 |        270 |   no   | 146 s |
| charts in the merge only  |    -5.92%  |      — |      4 |          — |   no   | 114 s |
| seam smoothing (labels)   |    -1.06%  |      — |      0 |          0 |  yes*  |  29 s |

*BRepCheck invalid, and the seams came out only 2.2% shorter (4309 -> 4217
total length) — not enough to see, so it was dropped.

## The blocker, and it is the same one every time

The fit is not the problem. Fitted over a conformal chart the surfaces are
demonstrably right: volume error goes from -1.21% to -0.06%. What breaks is
the TRIMMING.

A face's pcurves come from `ShapeFix_Edge::FixAddPCurve`, which projects the
edge's 3D curve onto the surface. On a plane, cylinder or torus that is
reliable. On a B-spline built over a chart it is ambiguous — the projection
can land anywhere on a surface that folds back over itself in space — and the
face is then trimmed to a region its own boundary never described.

The chart already knows the answer exactly: every boundary vertex has its
(u, v) from the flattening. Supplying that as the pcurve, instead of letting
OCCT rediscover it, is the missing piece.

## Why it was not just done

The chains are the delicate part of the file. A chain edge is SHARED — the
same TopoDS_Edge is used by the fitted face and by the triangles beside it,
which is what lets a hybrid shell sew at all (measured: 29 of 3030 edges
one-sided with the shared-edge path, 719 of 3379 without it). Supplying a
pcurve per (edge, face) has to keep that sharing intact and has to keep
working for the analytic faces the bracket and the broom holder are made of.

That is the next piece of work, and it is not a small one.
