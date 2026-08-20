# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-20T07:17:48Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.068 | [1.023, 1.112] | 0.9991 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.063 | [2.014, 2.112] | 0.9997 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.016 | [1.001, 1.032] | 0.9999 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.082 | 0.9993 | [1.043, 1.121] |
| `edgeInfo1` | edges | 4 | 1.068 | 0.9991 | [1.023, 1.112] |
| `allEdges` | edges | 4 | 2.063 | 0.9997 | [2.014, 2.112] |
| `allEdgesBulk` | edges | 4 | 1.927 | 0.9999 | [1.898, 1.956] |
| `buildOnly` | edges | 4 | 1.016 | 0.9999 | [1.001, 1.032] |
| `counts` | edges | 4 | 0.999 | 1.0000 | [0.990, 1.008] |
| `bbox` | edges | 4 | 0.985 | 0.9998 | [0.965, 1.004] |
| `mesh` | edges | 4 | 1.006 | 0.9998 | [0.988, 1.024] |
| `fuse` | edges | 4 | 1.343 | 0.9977 | [1.254, 1.433] |
| `cut` | edges | 4 | 1.354 | 0.9977 | [1.264, 1.445] |
| `rayHits` | edges | 4 | 0.281 | 0.9614 | [0.203, 0.359] |
| `filletEx1` | edges | 4 | 0.217 | 0.1046 | [-0.663, 1.096] |
| `fillet.edges` | edgesBlended | 3 | 0.633 | 0.9905 | [0.511, 0.754] |
| `fillet.scenario` | edgesBlended | 3 | 0.197 | 0.9394 | [0.099, 0.294] |
| `fillet.radius` | radius | 4 | 1.401 | 0.5983 | [-0.190, 2.992] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 5.02869 | 0.04262 | 5.09680 | 0.8 % | 33890 | 4998089 | +0 | 11.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 1 | 2.14244 | 0.01314 | 2.16644 | 0.6 % | 14153 | 1995325 | +0 | 12.3 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 423.09273 | 0.28657 | 423.63374 | 0.1 % | 2838089 | 381354307 | +0 | 12.5 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 27.01306 | 0.05624 | 27.06857 | 0.2 % | 184544 | 29714181 | +0 | 12.5 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 14.37673 | 0.10316 | 14.59656 | 0.7 % | 84141 | 210179391 | -12985 | 16.0 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.12086 | 0.00086 | 0.12258 | 0.7 % | 375 | 55336 | +0 | 16.0 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.08889 | 0.00209 | 0.09360 | 2.4 % | 63 | 71064 | +0 | 16.0 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.89390 | 0.06319 | 6.02137 | 1.1 % | 34051 | 7904950 | +0 | 16.0 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 63.51435 | 0.25016 | 63.95451 | 0.4 % | 270405 | 61756054 | +0 | 20.2 |
| `cut` | edges | 180 | 180 | 7 | 1 | 57.77772 | 0.19364 | 58.09223 | 0.3 % | 242898 | 55308717 | +0 | 20.2 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.32363 | 0.00131 | 0.32544 | 0.4 % | 1976 | 287838 | +0 | 20.2 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 37.81406 | 0.26003 | 38.17578 | 0.7 % | 211444 | 24603168 | +0 | 22.3 |
| `build` | edges | 360 | 360 | 7 | 1 | 11.29387 | 0.03049 | 11.34145 | 0.3 % | 67568 | 9755769 | +0 | 22.3 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 4.80177 | 0.02462 | 4.85389 | 0.5 % | 27715 | 3819939 | +0 | 22.3 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1900.15673 | 2.21997 | 1904.02896 | 0.1 % | 11116716 | 1464103145 | +0 | 22.3 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 103.50863 | 0.53514 | 104.57588 | 0.5 % | 633459 | 98247322 | +0 | 22.3 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 28.50746 | 0.15271 | 28.71489 | 0.5 % | 167656 | 415797593 | -26002 | 25.4 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.23872 | 0.00049 | 0.23942 | 0.2 % | 737 | 86232 | +0 | 25.4 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.18062 | 0.00225 | 0.18420 | 1.2 % | 123 | 138760 | +0 | 25.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 11.52624 | 0.12537 | 11.74594 | 1.1 % | 67916 | 14732520 | +0 | 25.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 145.95777 | 0.36503 | 146.49138 | 0.3 % | 614282 | 125180051 | +0 | 25.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 133.45882 | 0.63776 | 134.58277 | 0.5 % | 560310 | 112644569 | +0 | 25.8 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.36224 | 0.00143 | 0.36533 | 0.4 % | 2096 | 363373 | +0 | 25.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 12.53793 | 0.04278 | 12.59823 | 0.3 % | 68952 | 11025879 | +0 | 26.7 |
| `build` | edges | 720 | 720 | 7 | 1 | 23.02096 | 0.06084 | 23.14499 | 0.3 % | 134894 | 19067673 | +0 | 26.7 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 9.65610 | 0.04884 | 9.70224 | 0.5 % | 54839 | 7482726 | +0 | 26.7 |
| `allEdges` | edges | 720 | 720 | 3 | 1 | 7655.13164 | 2.41664 | 7657.39921 | 0.0 % | 44080847 | 5736432632 | +0 | 26.7 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 379.42789 | 0.88272 | 380.96372 | 0.2 % | 2326372 | 351892085 | +0 | 26.7 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 57.90616 | 0.15627 | 58.07386 | 0.3 % | 334430 | 827097897 | -51986 | 32.9 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.47874 | 0.00363 | 0.48600 | 0.8 % | 1457 | 114776 | +0 | 32.9 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.34793 | 0.00123 | 0.35015 | 0.4 % | 243 | 274104 | +0 | 32.9 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 23.46716 | 0.19347 | 23.79093 | 0.8 % | 135617 | 28294705 | +0 | 32.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 369.71328 | 1.19707 | 372.03402 | 0.3 % | 1539740 | 260139315 | +0 | 34.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 341.52292 | 1.33439 | 344.43571 | 0.4 % | 1432918 | 235386333 | +0 | 34.7 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.43657 | 0.00134 | 0.43811 | 0.3 % | 2336 | 508837 | +0 | 34.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 24.77739 | 0.23409 | 25.29457 | 0.9 % | 134712 | 21027269 | +0 | 34.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 48.31347 | 0.18698 | 48.71049 | 0.4 % | 269554 | 37904987 | +0 | 34.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 20.00813 | 0.06261 | 20.08740 | 0.3 % | 109093 | 14942819 | +0 | 34.7 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 31273.40304 | 148.96976 | 31441.05187 | 0.5 % | 175482141 | 22897982157 | +0 | 40.6 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1503.71105 | 1.72047 | 1506.25796 | 0.1 % | 8885798 | 1371867783 | +0 | 40.6 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 118.78553 | 1.34420 | 120.96371 | 1.1 % | 668604 | 1650879483 | -103927 | 45.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.96423 | 0.00295 | 0.96843 | 0.3 % | 2899 | 204665 | +0 | 45.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.69544 | 0.00344 | 0.70307 | 0.5 % | 483 | 544824 | +0 | 45.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 47.48689 | 0.54114 | 48.01631 | 1.1 % | 271017 | 55029016 | +0 | 45.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1038.23303 | 4.67845 | 1047.58332 | 0.5 % | 4342641 | 571010045 | +0 | 50.1 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 965.64832 | 2.62578 | 970.31207 | 0.3 % | 4130097 | 521889697 | +0 | 50.1 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 0.58151 | 0.00501 | 0.58811 | 0.9 % | 2816 | 804476 | +0 | 50.1 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 49.72966 | 0.25820 | 50.19153 | 0.5 % | 266270 | 41732647 | +0 | 50.1 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 81.23099 | 0.16553 | 81.49208 | 0.2 % | 478775 | 64918792 | +0 | 50.1 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.91516 | 0.01339 | 0.94222 | 1.5 % | 4013 | 303448 | +0 | 50.1 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.54801 | 0.10019 | 5.77428 | 1.8 % | 29913 | 4794461 | +0 | 50.1 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 16.28034 | 0.02325 | 16.30296 | 0.1 % | 92923 | 10993192 | +0 | 50.1 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 34.43077 | 0.05880 | 34.49836 | 0.2 % | 202410 | 21699566 | +0 | 51.3 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 79.22498 | 0.07392 | 79.31550 | 0.1 % | 486842 | 47288718 | +0 | 51.3 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 97.65180 | 0.15578 | 97.91955 | 0.2 % | 571698 | 75922110 | +0 | 51.3 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 115.65426 | 0.20702 | 115.89943 | 0.2 % | 681185 | 86619062 | +0 | 51.3 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 160.46818 | 0.32463 | 160.86193 | 0.2 % | 965617 | 112223487 | +0 | 51.3 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 34.67917 | 0.05559 | 34.75247 | 0.2 % | 203528 | 21783394 | +0 | 51.3 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 34.48240 | 0.12827 | 34.75370 | 0.4 % | 202410 | 21701191 | +0 | 51.3 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 34.44754 | 0.16939 | 34.79443 | 0.5 % | 202365 | 21691208 | +0 | 51.3 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 883.16980 | 0.53189 | 883.98246 | 0.1 % | 3554579 | 512369967 | +0 | 52.6 |

### Notes

- `build` (x=180): occt_extrude_profile_arcs — the fixture itself
- `edgeInfo1` (x=180): one occt_shape_edge_info, index 1, against a growing shape
- `allEdges` (x=180): per-edge enumeration — the quadratic
- `allEdgesBulk` (x=180): the same enumeration through ONE occt_shape_edges_info call (shim v21+) — compare its exponent against allEdges
- `buildOnly` (x=180): CONTROL: build + counts + full mesh, never enumerated
- `counts` (x=180): control: touching the shape is cheap
- `bbox` (x=180): control: touching the shape is cheap
- `mesh` (x=180): occt_mesh_create at the app's linDeflection 0.2 / ang 0.35
- `fuse` (x=180): occt_fuse of two ring prisms at this rung's complexity
- `cut` (x=180): occt_cut of the same pair
- `rayHits` (x=180): one ray through the solid — the 3D pick path
- `filletEx1` (x=180): occt_fillet_edges_ex, ONE vertical corner edge, at a radius fixed independently of the ladder
- `build` (x=360): occt_extrude_profile_arcs — the fixture itself
- `edgeInfo1` (x=360): one occt_shape_edge_info, index 1, against a growing shape
- `allEdges` (x=360): per-edge enumeration — the quadratic
- `allEdgesBulk` (x=360): the same enumeration through ONE occt_shape_edges_info call (shim v21+) — compare its exponent against allEdges
- `buildOnly` (x=360): CONTROL: build + counts + full mesh, never enumerated
- `counts` (x=360): control: touching the shape is cheap
- `bbox` (x=360): control: touching the shape is cheap
- `mesh` (x=360): occt_mesh_create at the app's linDeflection 0.2 / ang 0.35
- `fuse` (x=360): occt_fuse of two ring prisms at this rung's complexity
- `cut` (x=360): occt_cut of the same pair
- `rayHits` (x=360): one ray through the solid — the 3D pick path
- `filletEx1` (x=360): occt_fillet_edges_ex, ONE vertical corner edge, at a radius fixed independently of the ladder
- `build` (x=720): occt_extrude_profile_arcs — the fixture itself
- `edgeInfo1` (x=720): one occt_shape_edge_info, index 1, against a growing shape
- `allEdges` (x=720): per-edge enumeration — the quadratic
- `allEdgesBulk` (x=720): the same enumeration through ONE occt_shape_edges_info call (shim v21+) — compare its exponent against allEdges
- `buildOnly` (x=720): CONTROL: build + counts + full mesh, never enumerated
- `counts` (x=720): control: touching the shape is cheap
- `bbox` (x=720): control: touching the shape is cheap
- `mesh` (x=720): occt_mesh_create at the app's linDeflection 0.2 / ang 0.35
- `fuse` (x=720): occt_fuse of two ring prisms at this rung's complexity
- `cut` (x=720): occt_cut of the same pair
- `rayHits` (x=720): one ray through the solid — the 3D pick path
- `filletEx1` (x=720): occt_fillet_edges_ex, ONE vertical corner edge, at a radius fixed independently of the ladder
- `build` (x=1440): occt_extrude_profile_arcs — the fixture itself
- `edgeInfo1` (x=1440): one occt_shape_edge_info, index 1, against a growing shape
- `allEdges` (x=1440): per-edge enumeration — the quadratic
- `allEdgesBulk` (x=1440): the same enumeration through ONE occt_shape_edges_info call (shim v21+) — compare its exponent against allEdges
- `buildOnly` (x=1440): CONTROL: build + counts + full mesh, never enumerated
- `counts` (x=1440): control: touching the shape is cheap
- `bbox` (x=1440): control: touching the shape is cheap
- `mesh` (x=1440): occt_mesh_create at the app's linDeflection 0.2 / ang 0.35
- `fuse` (x=1440): occt_fuse of two ring prisms at this rung's complexity
- `cut` (x=1440): occt_cut of the same pair
- `rayHits` (x=1440): one ray through the solid — the 3D pick path
- `filletEx1` (x=1440): occt_fillet_edges_ex, ONE vertical corner edge, at a radius fixed independently of the ladder
- `filletCandidateSearch` (x=72): enumerate every filletable edge — what a UI does before it can offer a blend set
- `volume` (x=72): one occt_shape_volume — the guard runs TWO of these per fillet (S2-2)
- `valid` (x=72): one occt_shape_valid — BRepCheck_Analyzer, the third leg of the guard (S2-2)
- `fillet.edges` (x=1): the BLEND alone. §6.3's table measured 10.1 / 20.8 / 46.7 ms at 1 / 4 / 12 on the device — per-edge, not flat
- `fillet.edges` (x=4): the BLEND alone. §6.3's table measured 10.1 / 20.8 / 46.7 ms at 1 / 4 / 12 on the device — per-edge, not flat
- `fillet.edges` (x=12): the BLEND alone. §6.3's table measured 10.1 / 20.8 / 46.7 ms at 1 / 4 / 12 on the device — per-edge, not flat
- `fillet.scenario` (x=1): search + blend, as the device scenario span covers them — this is the one §10.2's flat row describes
- `fillet.scenario` (x=4): search + blend, as the device scenario span covers them — this is the one §10.2's flat row describes
- `fillet.scenario` (x=12): search + blend, as the device scenario span covers them — this is the one §10.2's flat row describes
- `fillet.radius` (x=0.5): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
- `fillet.radius` (x=1): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
- `fillet.radius` (x=2): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
- `fillet.radius` (x=4): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
