# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T16:55:32Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.047 | [0.938, 1.157] | 0.9943 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.012 | [1.978, 2.045] | 0.9999 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.089 | [0.829, 1.348] | 0.9714 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.124 | 0.9861 | [0.939, 1.309] |
| `edgeInfo1` | edges | 4 | 1.047 | 0.9943 | [0.938, 1.157] |
| `allEdges` | edges | 4 | 2.012 | 0.9999 | [1.978, 2.045] |
| `allEdgesBulk` | edges | 4 | 1.960 | 0.9985 | [1.854, 2.066] |
| `buildOnly` | edges | 4 | 1.089 | 0.9714 | [0.829, 1.348] |
| `counts` | edges | 4 | 1.035 | 0.9777 | [0.818, 1.251] |
| `bbox` | edges | 4 | 0.995 | 0.9947 | [0.894, 1.095] |
| `mesh` | edges | 4 | 1.106 | 0.9336 | [0.697, 1.515] |
| `fuse` | edges | 4 | 1.402 | 0.9905 | [1.212, 1.592] |
| `cut` | edges | 4 | 1.383 | 0.9907 | [1.197, 1.569] |
| `rayHits` | edges | 4 | 0.334 | 0.7280 | [0.051, 0.617] |
| `filletEx1` | edges | 4 | 0.220 | 0.0996 | [-0.698, 1.138] |
| `fillet.edges` | edgesBlended | 3 | 0.621 | 0.9889 | [0.492, 0.750] |
| `fillet.scenario` | edgesBlended | 3 | 0.306 | 0.8695 | [0.074, 0.538] |
| `fillet.radius` | radius | 4 | 1.442 | 0.5974 | [-0.198, 3.082] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.59525 | 0.08574 | 3.73383 | 2.4 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.55026 | 0.04082 | 1.62648 | 2.6 % | 14153 | 2130000 | +0 | 15.1 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 343.14423 | 19.07766 | 378.56450 | 5.6 % | 2838089 | 406026976 | +0 | 15.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 19.84576 | 0.38873 | 20.15713 | 2.0 % | 184544 | 31080240 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 9.43531 | 0.06074 | 9.52037 | 0.6 % | 84071 | 225974848 | -12160 | 23.1 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08289 | 0.00159 | 0.08624 | 1.9 % | 375 | 59360 | +0 | 23.1 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05459 | 0.00086 | 0.05560 | 1.6 % | 63 | 80640 | +0 | 23.1 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.02051 | 0.20139 | 4.40313 | 5.0 % | 34056 | 13154158 | +0 | 23.2 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 41.15032 | 1.60607 | 43.19029 | 3.9 % | 270270 | 66597698 | +0 | 28.6 |
| `cut` | edges | 180 | 180 | 7 | 1 | 39.22297 | 0.36997 | 39.96346 | 0.9 % | 242932 | 59661447 | +0 | 28.6 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.21449 | 0.01302 | 0.24063 | 6.1 % | 1976 | 308336 | +0 | 28.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 25.51905 | 0.21446 | 25.80217 | 0.8 % | 211425 | 25882480 | +0 | 30.3 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.31793 | 0.20547 | 7.73717 | 2.8 % | 67568 | 10408048 | +0 | 30.3 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.12183 | 0.04156 | 3.18471 | 1.3 % | 27715 | 4078672 | +0 | 30.3 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1320.28941 | 109.93656 | 1479.65829 | 8.3 % | 11116716 | 1558379984 | +0 | 30.3 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 69.47414 | 0.69384 | 70.34029 | 1.0 % | 633459 | 102663664 | +0 | 30.3 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 18.04612 | 0.46260 | 18.86958 | 2.6 % | 167561 | 446577664 | -24320 | 36.8 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16253 | 0.00224 | 0.16506 | 1.4 % | 737 | 93024 | +0 | 36.8 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11864 | 0.01404 | 0.14114 | 11.8 % | 123 | 157440 | +0 | 36.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.06832 | 0.06039 | 8.15354 | 0.7 % | 67923 | 24575301 | +0 | 36.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 101.87103 | 4.05122 | 107.22958 | 4.0 % | 614281 | 133955797 | +0 | 40.5 |
| `cut` | edges | 360 | 360 | 7 | 1 | 91.66863 | 11.36490 | 117.06050 | 12.4 % | 560373 | 120362329 | +0 | 40.5 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.21122 | 0.00661 | 0.22144 | 3.1 % | 2096 | 392112 | +0 | 40.5 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 7.52702 | 0.61779 | 8.22346 | 8.2 % | 68952 | 11624128 | +0 | 40.7 |
| `build` | edges | 720 | 720 | 7 | 1 | 13.66288 | 0.74540 | 14.67371 | 5.5 % | 134894 | 20360432 | +0 | 40.7 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 5.81542 | 0.33575 | 6.40254 | 5.8 % | 54839 | 7992400 | +0 | 40.7 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5422.98227 | 107.32462 | 5566.91700 | 2.0 % | 44080847 | 6109275264 | +0 | 40.7 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 316.87770 | 54.90130 | 394.68454 | 17.3 % | 2326372 | 367698944 | +0 | 40.7 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 54.42889 | 6.80437 | 65.51571 | 12.5 % | 334258 | 888838496 | -48640 | 53.9 |
| `counts` | edges | 720 | 720 | 7 | 4 | 0.43582 | 0.15242 | 0.77529 | 35.0 % | 1457 | 127584 | +0 | 53.9 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.24447 | 0.01579 | 0.26691 | 6.5 % | 243 | 311040 | +0 | 53.9 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 28.66406 | 4.29014 | 34.07171 | 15.0 % | 135627 | 48367506 | +0 | 53.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 345.85404 | 25.46115 | 392.54262 | 7.4 % | 1539778 | 274713941 | +0 | 62.4 |
| `cut` | edges | 720 | 720 | 7 | 1 | 311.59209 | 27.36922 | 363.70333 | 8.8 % | 1432963 | 247780002 | +0 | 62.4 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.40611 | 0.20679 | 0.85518 | 50.9 % | 2336 | 559664 | +0 | 62.4 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 20.28215 | 4.28970 | 29.11421 | 21.2 % | 134712 | 22247488 | +0 | 62.4 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 39.21917 | 4.43248 | 45.31175 | 11.3 % | 269554 | 40496624 | +0 | 62.4 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 14.17097 | 2.03920 | 18.38771 | 14.4 % | 109093 | 15971536 | +0 | 62.4 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 22372.44967 | 1876.93987 | 24539.55021 | 8.4 % | 175482141 | 24398762544 | +0 | 62.4 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1108.43821 | 222.19427 | 1589.09742 | 20.0 % | 8885798 | 1431758592 | +0 | 62.4 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 80.76749 | 1.69590 | 83.75033 | 2.1 % | 668060 | 1775223216 | -97280 | 87.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.65165 | 0.01136 | 0.66533 | 1.7 % | 2899 | 229472 | +0 | 87.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.42702 | 0.01666 | 0.46163 | 3.9 % | 483 | 618240 | +0 | 87.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.93392 | 1.18861 | 36.46500 | 3.5 % | 271030 | 96173390 | +0 | 87.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 698.36012 | 14.31597 | 724.01296 | 2.0 % | 4342871 | 590715952 | +0 | 103.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 637.47364 | 14.75904 | 659.28887 | 2.3 % | 4130022 | 536920373 | +0 | 103.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.37329 | 0.01906 | 0.41030 | 5.1 % | 2816 | 894768 | +0 | 103.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 30.50790 | 0.37779 | 31.20246 | 1.2 % | 266270 | 44116800 | +0 | 103.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 51.82346 | 0.72399 | 52.73458 | 1.4 % | 478775 | 69176096 | +0 | 103.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.59846 | 0.02887 | 0.66077 | 4.8 % | 4013 | 309760 | +0 | 103.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.84057 | 0.33790 | 4.60342 | 8.8 % | 29913 | 5127328 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 10.88111 | 0.40816 | 11.47804 | 3.8 % | 92919 | 11590416 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 22.45015 | 0.38985 | 23.11233 | 1.7 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 51.43272 | 1.04686 | 52.65054 | 2.0 % | 486810 | 49139568 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 63.38461 | 1.46353 | 66.32204 | 2.3 % | 571694 | 80766512 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 75.78854 | 2.04317 | 78.93229 | 2.7 % | 681147 | 91820240 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 138.18138 | 23.07236 | 167.66208 | 16.7 % | 965585 | 118315664 | +0 | 103.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 23.68043 | 2.00721 | 27.61258 | 8.5 % | 202345 | 22639152 | +0 | 103.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 24.45561 | 2.87900 | 30.44621 | 11.8 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 23.43476 | 0.66789 | 24.35742 | 2.8 % | 202370 | 22640112 | +0 | 103.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 671.74617 | 34.69622 | 742.21217 | 5.2 % | 3554373 | 535954400 | +0 | 103.6 |

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
