# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-23T09:51:00Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v23) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.056 | [0.983, 1.129] | 0.9975 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.074 | [2.024, 2.123] | 0.9997 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.973 | [0.928, 1.018] | 0.9989 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.058 | 0.9997 | [1.035, 1.081] |
| `edgeInfo1` | edges | 4 | 1.056 | 0.9975 | [0.983, 1.129] |
| `allEdges` | edges | 4 | 2.074 | 0.9997 | [2.024, 2.123] |
| `allEdgesBulk` | edges | 4 | 1.038 | 0.9998 | [1.015, 1.060] |
| `buildOnly` | edges | 4 | 0.973 | 0.9989 | [0.928, 1.018] |
| `counts` | edges | 4 | 1.056 | 0.9993 | [1.016, 1.096] |
| `bbox` | edges | 4 | 1.024 | 0.9999 | [1.010, 1.038] |
| `mesh` | edges | 4 | 0.966 | 0.9997 | [0.942, 0.990] |
| `fuse` | edges | 4 | 1.286 | 0.9975 | [1.196, 1.376] |
| `cut` | edges | 4 | 1.283 | 0.9960 | [1.170, 1.395] |
| `rayHits` | edges | 4 | 0.282 | 0.9600 | [0.202, 0.362] |
| `filletEx1` | edges | 4 | 0.211 | 0.0971 | [-0.680, 1.102] |
| `fillet.edges` | edgesBlended | 3 | 0.622 | 0.9916 | [0.509, 0.734] |
| `fillet.scenario` | edgesBlended | 3 | 0.541 | 0.9814 | [0.395, 0.687] |
| `fillet.radius` | radius | 4 | 1.460 | 0.5987 | [-0.197, 3.117] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.01470 | 0.01089 | 4.03304 | 0.3 % | 33890 | 4998343 | +0 | 10.6 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.09118 | 0.00997 | 0.11375 | 10.9 % | 821 | 150504 | +0 | 10.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.73704 | 0.06506 | 15.87669 | 0.4 % | 148205 | 27145770 | +0 | 10.7 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.74952 | 0.00334 | 0.75632 | 0.4 % | 6207 | 572862 | +0 | 10.7 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 12.22809 | 0.28661 | 12.38983 | 2.3 % | 84141 | 210181599 | -13031 | 14.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08318 | 0.00065 | 0.08445 | 0.8 % | 375 | 55384 | +0 | 14.7 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05737 | 0.00059 | 0.05856 | 1.0 % | 63 | 71064 | +0 | 14.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.66482 | 0.07137 | 4.79547 | 1.5 % | 34051 | 7904383 | +0 | 14.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 51.79637 | 0.25803 | 52.29297 | 0.5 % | 270368 | 61751808 | +0 | 19.6 |
| `cut` | edges | 180 | 180 | 7 | 1 | 49.31739 | 2.43401 | 53.35820 | 4.9 % | 242870 | 55314373 | +0 | 19.6 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25984 | 0.00273 | 0.26306 | 1.0 % | 1976 | 287523 | +0 | 19.6 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.79354 | 1.06892 | 32.21162 | 3.6 % | 211444 | 24605771 | +0 | 21.9 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.29248 | 0.09320 | 8.46916 | 1.1 % | 67568 | 9756046 | +0 | 21.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.17296 | 0.00074 | 0.17421 | 0.4 % | 1601 | 255880 | +0 | 21.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 62.76441 | 0.63343 | 64.00440 | 1.0 % | 577205 | 92202266 | +0 | 21.9 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.58648 | 0.00752 | 1.59922 | 0.5 % | 12390 | 1116230 | +0 | 21.9 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.46385 | 0.21009 | 22.71698 | 0.9 % | 167656 | 415799529 | -26007 | 25.2 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16731 | 0.00118 | 0.16915 | 0.7 % | 737 | 86264 | +0 | 25.2 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11426 | 0.00040 | 0.11487 | 0.4 % | 123 | 138744 | +0 | 25.2 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.82031 | 0.04823 | 8.89620 | 0.5 % | 67916 | 14729405 | +0 | 25.2 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 115.33056 | 1.65143 | 118.94655 | 1.4 % | 614315 | 125226911 | +0 | 25.7 |
| `cut` | edges | 360 | 360 | 7 | 1 | 105.60418 | 0.74409 | 106.74377 | 0.7 % | 560412 | 112711045 | +0 | 25.7 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.29554 | 0.00192 | 0.29905 | 0.7 % | 2096 | 362151 | +0 | 25.7 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.69701 | 0.05965 | 9.79169 | 0.6 % | 68952 | 11054270 | +0 | 26.6 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.91834 | 0.02929 | 16.96870 | 0.2 % | 134894 | 19067589 | +0 | 26.6 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.36584 | 0.00677 | 0.38083 | 1.8 % | 3161 | 465928 | +0 | 26.6 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 263.79255 | 0.80584 | 265.28634 | 0.3 % | 2277605 | 335619658 | +0 | 26.6 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.22565 | 0.02074 | 3.26496 | 0.6 % | 24751 | 2170817 | +0 | 26.6 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 45.58281 | 0.99920 | 47.83405 | 2.2 % | 334430 | 827093959 | -51931 | 31.3 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.34271 | 0.00875 | 0.36233 | 2.6 % | 1457 | 114792 | +0 | 31.3 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23536 | 0.00210 | 0.23960 | 0.9 % | 243 | 274104 | +0 | 31.3 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.40894 | 0.16132 | 17.75509 | 0.9 % | 135617 | 28307747 | +0 | 31.3 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 277.58155 | 2.61907 | 282.31126 | 0.9 % | 1539855 | 259832867 | +0 | 33.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 257.46236 | 3.42546 | 263.87055 | 1.3 % | 1432988 | 235166123 | +0 | 33.7 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.34881 | 0.00377 | 0.35640 | 1.1 % | 2336 | 508704 | +0 | 33.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 19.10382 | 0.11229 | 19.32203 | 0.6 % | 134712 | 21022162 | +0 | 33.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 36.46209 | 0.17856 | 36.83208 | 0.5 % | 269554 | 37904937 | +0 | 33.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.81521 | 0.00806 | 0.82796 | 1.0 % | 6285 | 950744 | +0 | 33.7 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1175.06652 | 24.27905 | 1230.05373 | 2.1 % | 9053767 | 1369341514 | +0 | 33.7 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.50352 | 0.02354 | 6.54449 | 0.4 % | 49476 | 4347737 | +0 | 33.7 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 91.39861 | 1.69710 | 94.22324 | 1.9 % | 668604 | 1650880096 | -103927 | 44.9 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.75136 | 0.00336 | 0.75838 | 0.4 % | 2899 | 204713 | +0 | 44.9 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.48013 | 0.01119 | 0.50514 | 2.3 % | 483 | 544824 | +0 | 44.9 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.65189 | 0.24725 | 35.11294 | 0.7 % | 271017 | 55057706 | +0 | 44.9 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 754.79666 | 6.21866 | 763.86518 | 0.8 % | 4342836 | 570672251 | +0 | 48.9 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 709.43828 | 5.05565 | 718.81681 | 0.7 % | 4130167 | 521196945 | +0 | 48.9 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.47160 | 0.00314 | 0.47519 | 0.7 % | 2816 | 805082 | +0 | 48.9 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 38.67503 | 0.11133 | 38.91092 | 0.3 % | 266270 | 41697392 | +0 | 48.9 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.77945 | 0.02786 | 2.83694 | 1.0 % | 25307 | 3987329 | +0 | 48.9 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.77638 | 0.00067 | 0.77767 | 0.1 % | 4013 | 305320 | +0 | 48.9 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.54550 | 0.01623 | 4.57789 | 0.4 % | 29913 | 4794419 | +0 | 48.9 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.00687 | 0.04671 | 13.09205 | 0.4 % | 92923 | 10990365 | +0 | 48.9 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 27.34761 | 0.13406 | 27.50530 | 0.5 % | 202410 | 21703152 | +0 | 50.4 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 61.53017 | 0.21570 | 61.79548 | 0.4 % | 486842 | 47291730 | +0 | 50.4 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 16.55025 | 1.85197 | 20.74838 | 11.2 % | 118230 | 15000713 | +0 | 50.4 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 30.01604 | 0.05369 | 30.11586 | 0.2 % | 227717 | 25709761 | +0 | 50.4 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 64.21740 | 0.34386 | 64.86708 | 0.5 % | 512149 | 51304214 | +0 | 50.4 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 27.40943 | 0.08856 | 27.58909 | 0.3 % | 203528 | 21781312 | +0 | 50.4 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 27.32476 | 0.12711 | 27.52100 | 0.5 % | 202410 | 21701687 | +0 | 50.4 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.25835 | 0.09291 | 27.41478 | 0.3 % | 202365 | 21687958 | +0 | 50.4 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 800.22766 | 1.38751 | 802.03655 | 0.2 % | 3554579 | 512437192 | +0 | 51.5 |

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
