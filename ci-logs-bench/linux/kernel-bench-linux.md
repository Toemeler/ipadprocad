# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-21T11:46:47Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v22) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.091 | [1.041, 1.141] | 0.9989 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.066 | [1.989, 2.144] | 0.9993 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.025 | [0.991, 1.059] | 0.9994 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.057 | 0.9997 | [1.031, 1.083] |
| `edgeInfo1` | edges | 4 | 1.091 | 0.9989 | [1.041, 1.141] |
| `allEdges` | edges | 4 | 2.066 | 0.9993 | [1.989, 2.144] |
| `allEdgesBulk` | edges | 4 | 1.030 | 0.9999 | [1.017, 1.042] |
| `buildOnly` | edges | 4 | 1.025 | 0.9994 | [0.991, 1.059] |
| `counts` | edges | 4 | 1.085 | 0.9985 | [1.027, 1.144] |
| `bbox` | edges | 4 | 1.014 | 0.9998 | [0.995, 1.033] |
| `mesh` | edges | 4 | 0.979 | 0.9997 | [0.958, 1.001] |
| `fuse` | edges | 4 | 1.278 | 0.9963 | [1.170, 1.386] |
| `cut` | edges | 4 | 1.304 | 0.9962 | [1.191, 1.416] |
| `rayHits` | edges | 4 | 0.265 | 0.9691 | [0.199, 0.330] |
| `filletEx1` | edges | 4 | 0.210 | 0.0968 | [-0.680, 1.100] |
| `fillet.edges` | edgesBlended | 3 | 0.627 | 0.9912 | [0.511, 0.742] |
| `fillet.scenario` | edgesBlended | 3 | 0.563 | 0.9874 | [0.438, 0.687] |
| `fillet.radius` | radius | 4 | 1.456 | 0.5979 | [-0.199, 3.111] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.91758 | 0.02465 | 3.97189 | 0.6 % | 33890 | 4998121 | +0 | 10.4 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08549 | 0.00053 | 0.08600 | 0.6 % | 821 | 150488 | +0 | 10.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 16.38747 | 2.44796 | 21.93767 | 14.9 % | 148205 | 27139978 | +0 | 10.7 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.75764 | 0.01664 | 0.79305 | 2.2 % | 6207 | 572855 | +0 | 10.7 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.23221 | 0.11748 | 11.46981 | 1.0 % | 84141 | 210179750 | -13008 | 14.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07574 | 0.00053 | 0.07695 | 0.7 % | 375 | 55336 | +0 | 14.7 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05803 | 0.00030 | 0.05845 | 0.5 % | 63 | 71064 | +0 | 14.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.55976 | 0.03359 | 4.61388 | 0.7 % | 34051 | 7906822 | +0 | 14.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 53.38839 | 3.33333 | 60.90848 | 6.2 % | 270325 | 61740305 | +0 | 19.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 48.01134 | 0.39698 | 48.80883 | 0.8 % | 242908 | 55301949 | +0 | 19.7 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25671 | 0.00098 | 0.25811 | 0.4 % | 1976 | 288254 | +0 | 19.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.70362 | 0.12410 | 29.84314 | 0.4 % | 211444 | 24610240 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.41495 | 0.51060 | 9.16238 | 6.1 % | 67568 | 9755685 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.17271 | 0.00184 | 0.17591 | 1.1 % | 1601 | 255816 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 62.59619 | 0.23075 | 62.90497 | 0.4 % | 577205 | 92179146 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.57538 | 0.01571 | 1.60714 | 1.0 % | 12390 | 1117961 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.89666 | 0.16351 | 22.20686 | 0.7 % | 167656 | 415801925 | -25982 | 24.5 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15243 | 0.00028 | 0.15280 | 0.2 % | 737 | 86104 | +0 | 24.5 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11391 | 0.00018 | 0.11408 | 0.2 % | 123 | 138744 | +0 | 24.5 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.70175 | 0.07031 | 8.81866 | 0.8 % | 67916 | 14712255 | +0 | 24.5 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 114.01921 | 0.45377 | 114.38834 | 0.4 % | 614260 | 125165861 | +0 | 25.4 |
| `cut` | edges | 360 | 360 | 7 | 1 | 104.99361 | 0.36239 | 105.59652 | 0.3 % | 560297 | 112636422 | +0 | 25.4 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.28948 | 0.00190 | 0.29280 | 0.7 % | 2096 | 362827 | +0 | 25.4 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.65913 | 0.03115 | 9.70423 | 0.3 % | 68952 | 11077758 | +0 | 26.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.84818 | 0.09182 | 17.03117 | 0.5 % | 134894 | 19069141 | +0 | 26.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.36629 | 0.00356 | 0.37141 | 1.0 % | 3161 | 465912 | +0 | 26.4 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 264.69500 | 1.27008 | 266.70590 | 0.5 % | 2277605 | 335608186 | +0 | 26.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.18825 | 0.01761 | 3.21054 | 0.6 % | 24751 | 2170863 | +0 | 26.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 44.89251 | 0.29289 | 45.28921 | 0.7 % | 334430 | 827105877 | -51957 | 31.7 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.31808 | 0.00239 | 0.32309 | 0.8 % | 1457 | 114920 | +0 | 31.7 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23470 | 0.00108 | 0.23599 | 0.5 % | 243 | 274104 | +0 | 31.7 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.53241 | 0.56535 | 18.77008 | 3.2 % | 135617 | 28309585 | +0 | 31.7 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 279.41923 | 5.69877 | 291.02848 | 2.0 % | 1539713 | 260094008 | +0 | 33.6 |
| `cut` | edges | 720 | 720 | 7 | 1 | 257.51568 | 6.62445 | 272.46059 | 2.6 % | 1432941 | 235240168 | +0 | 33.6 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.34297 | 0.00756 | 0.35709 | 2.2 % | 2336 | 508902 | +0 | 33.6 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 19.09366 | 0.15408 | 19.43800 | 0.8 % | 134712 | 21026331 | +0 | 33.6 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 35.72447 | 0.05941 | 35.79856 | 0.2 % | 269554 | 37904914 | +0 | 33.6 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.82721 | 0.00365 | 0.83290 | 0.4 % | 6285 | 950750 | +0 | 33.6 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1200.52331 | 2.33664 | 1203.47039 | 0.2 % | 9053767 | 1369272362 | +0 | 33.6 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.46745 | 0.01898 | 6.50573 | 0.3 % | 49476 | 4347776 | +0 | 33.6 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 94.42044 | 2.61876 | 99.90558 | 2.8 % | 668604 | 1650882967 | -103922 | 43.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.72776 | 0.03478 | 0.80375 | 4.8 % | 2899 | 204729 | +0 | 43.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.47487 | 0.00109 | 0.47615 | 0.2 % | 483 | 544824 | +0 | 43.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.68315 | 0.52129 | 35.66941 | 1.5 % | 271017 | 55024849 | +0 | 43.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 759.43283 | 7.31369 | 765.20058 | 1.0 % | 4342857 | 572663301 | +0 | 49.4 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 723.78080 | 8.54285 | 737.60890 | 1.2 % | 4130246 | 521818614 | +0 | 49.4 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.44709 | 0.00689 | 0.45860 | 1.5 % | 2816 | 804595 | +0 | 49.4 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 38.46822 | 0.13912 | 38.73440 | 0.4 % | 266270 | 41699127 | +0 | 49.4 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.72472 | 0.00846 | 2.74086 | 0.3 % | 25307 | 3980195 | +0 | 49.4 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.77900 | 0.00216 | 0.78366 | 0.3 % | 4013 | 303880 | +0 | 49.4 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.52569 | 0.01573 | 4.55703 | 0.3 % | 29913 | 4794310 | +0 | 49.4 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.08916 | 0.07482 | 13.24032 | 0.6 % | 92923 | 10992893 | +0 | 49.4 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 27.63209 | 0.11521 | 27.86607 | 0.4 % | 202410 | 21701079 | +0 | 50.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 62.77137 | 0.36451 | 63.10651 | 0.6 % | 486842 | 47296967 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 15.87961 | 0.06521 | 16.01716 | 0.4 % | 118230 | 15003157 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 30.37274 | 0.07258 | 30.47903 | 0.2 % | 227717 | 25709027 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 64.94961 | 0.15223 | 65.22183 | 0.2 % | 512149 | 51306429 | +0 | 50.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 27.86816 | 0.18221 | 28.20439 | 0.7 % | 203528 | 21783959 | +0 | 50.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 27.70727 | 0.12686 | 27.87258 | 0.5 % | 202410 | 21701559 | +0 | 50.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.61779 | 0.06429 | 27.73275 | 0.2 % | 202365 | 21693711 | +0 | 50.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 806.31150 | 1.35454 | 808.10865 | 0.2 % | 3554579 | 512427722 | +0 | 51.9 |

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
