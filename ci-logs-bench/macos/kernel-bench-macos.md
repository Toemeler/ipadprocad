# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-21T11:48:45Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v22) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.049 | [0.744, 1.353] | 0.9579 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.864 | [1.859, 1.868] | 1.0000 | yes | **DISAGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.928 | [0.707, 1.150] | 0.9712 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.081 | 0.9977 | [1.010, 1.153] |
| `edgeInfo1` | edges | 4 | 1.049 | 0.9579 | [0.744, 1.353] |
| `allEdges` | edges | 4 | 1.864 | 1.0000 | [1.859, 1.868] |
| `allEdgesBulk` | edges | 4 | 0.985 | 0.9108 | [0.558, 1.412] |
| `buildOnly` | edges | 4 | 0.928 | 0.9712 | [0.707, 1.150] |
| `counts` | edges | 4 | 1.037 | 0.9802 | [0.832, 1.241] |
| `bbox` | edges | 4 | 0.443 | 0.4612 | [-0.221, 1.107] |
| `mesh` | edges | 4 | 0.743 | 0.9370 | [0.476, 1.009] |
| `fuse` | edges | 4 | 1.057 | 0.9292 | [0.652, 1.461] |
| `cut` | edges | 4 | 1.430 | 0.9831 | [1.170, 1.690] |
| `rayHits` | edges | 4 | 0.401 | 0.9874 | [0.338, 0.464] |
| `filletEx1` | edges | 4 | 0.017 | 0.0004 | [-1.110, 1.143] |
| `fillet.edges` | edgesBlended | 3 | 0.677 | 0.9974 | [0.609, 0.745] |
| `fillet.scenario` | edgesBlended | 3 | 0.620 | 0.9890 | [0.492, 0.749] |
| `fillet.radius` | radius | 4 | 1.479 | 0.5835 | [-0.253, 3.212] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.71399 | 0.12595 | 3.88179 | 3.4 % | 33890 | 5335600 | +0 | 14.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.09457 | 0.01907 | 0.12973 | 20.2 % | 821 | 158368 | +0 | 14.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 21.45683 | 3.99210 | 27.96554 | 18.6 % | 148205 | 28566976 | +0 | 14.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.72983 | 0.06917 | 0.82911 | 9.5 % | 6209 | 596032 | +0 | 14.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 13.02960 | 1.16164 | 14.50567 | 8.9 % | 84071 | 225974848 | -12160 | 22.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08170 | 0.00481 | 0.09118 | 5.9 % | 375 | 59360 | +0 | 22.7 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.20442 | 0.13793 | 0.47697 | 67.5 % | 63 | 80640 | +0 | 22.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 8.64110 | 4.05196 | 14.91313 | 46.9 % | 34056 | 13154158 | +0 | 22.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 95.72076 | 82.22801 | 269.09646 | 85.9 % | 270375 | 66619202 | +0 | 28.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 45.46096 | 4.24722 | 50.98021 | 9.3 % | 242874 | 59649598 | +0 | 28.5 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.23299 | 0.02253 | 0.26581 | 9.7 % | 1976 | 308336 | +0 | 28.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 52.22045 | 44.64212 | 149.84967 | 85.5 % | 211425 | 25882480 | +0 | 30.0 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.17020 | 0.19004 | 7.45508 | 2.7 % | 67568 | 10408048 | +0 | 30.0 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.16095 | 0.00073 | 0.16165 | 0.5 % | 1601 | 269728 | +0 | 30.0 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 78.58892 | 25.72575 | 134.60104 | 32.7 % | 577205 | 97204096 | +0 | 30.0 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.52975 | 0.10596 | 1.65069 | 6.9 % | 12392 | 1160128 | +0 | 30.0 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 26.26683 | 7.22687 | 38.06775 | 27.5 % | 167561 | 446577664 | -24320 | 36.8 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15699 | 0.00682 | 0.16747 | 4.3 % | 737 | 93024 | +0 | 36.8 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.10268 | 0.00218 | 0.10734 | 2.1 % | 123 | 157440 | +0 | 36.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 9.79092 | 1.81971 | 12.62283 | 18.6 % | 67923 | 24575301 | +0 | 36.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 114.46167 | 23.78395 | 158.79862 | 20.8 % | 614213 | 133941753 | +0 | 40.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 100.18815 | 14.15845 | 117.91258 | 14.1 % | 560356 | 120362421 | +0 | 40.8 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.28022 | 0.09392 | 0.48632 | 33.5 % | 2096 | 392112 | +0 | 40.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.87802 | 1.66621 | 12.78988 | 16.9 % | 68952 | 11624128 | +0 | 41.0 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.81541 | 2.31264 | 19.96300 | 13.8 % | 134894 | 20360432 | +0 | 41.0 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.51602 | 0.38450 | 1.35768 | 74.5 % | 3161 | 492448 | +0 | 41.0 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 284.50307 | 39.07726 | 353.98233 | 13.7 % | 2277605 | 354747136 | +0 | 41.0 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.69058 | 2.44033 | 8.98608 | 52.0 % | 24753 | 2255552 | +0 | 41.0 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 61.38671 | 32.47008 | 132.98792 | 52.9 % | 334258 | 888838496 | -48640 | 53.5 |
| `counts` | edges | 720 | 720 | 7 | 4 | 0.42053 | 0.06036 | 0.53766 | 14.4 % | 1457 | 127584 | +0 | 53.5 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.26675 | 0.02184 | 0.29513 | 8.2 % | 243 | 311040 | +0 | 53.5 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 22.74887 | 13.88254 | 54.11504 | 61.0 % | 135627 | 48367506 | +0 | 53.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 286.20254 | 21.00567 | 319.37783 | 7.3 % | 1539833 | 274725205 | +0 | 61.9 |
| `cut` | edges | 720 | 720 | 7 | 1 | 240.56944 | 20.68496 | 285.45013 | 8.6 % | 1432916 | 247770347 | +0 | 61.9 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.39778 | 0.16814 | 0.68020 | 42.3 % | 2336 | 559664 | +0 | 61.9 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 26.02318 | 7.62872 | 40.29075 | 29.3 % | 134712 | 22247488 | +0 | 61.9 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 34.00371 | 3.26021 | 39.59992 | 9.6 % | 269554 | 40496624 | +0 | 61.9 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.72321 | 0.05846 | 0.84220 | 8.1 % | 6285 | 1003424 | +0 | 61.9 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1035.69523 | 41.90072 | 1090.49400 | 4.0 % | 9053767 | 1445313024 | +0 | 61.9 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 4.89042 | 0.10841 | 5.04279 | 2.2 % | 49478 | 4511936 | +0 | 62.0 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 83.86379 | 4.34421 | 91.89333 | 5.2 % | 668060 | 1775223216 | -97280 | 87.4 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.64525 | 0.01089 | 0.65795 | 1.7 % | 2899 | 229472 | +0 | 87.4 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.41391 | 0.01833 | 0.44603 | 4.4 % | 483 | 618240 | +0 | 87.4 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 36.27435 | 2.74353 | 41.54900 | 7.6 % | 271030 | 96173390 | +0 | 87.4 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 810.21729 | 78.61396 | 924.91783 | 9.7 % | 4342888 | 590719463 | +0 | 103.8 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 924.39193 | 45.12383 | 1000.89813 | 4.9 % | 4130192 | 536955042 | +0 | 103.8 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.52337 | 0.13534 | 0.72867 | 25.9 % | 2816 | 894768 | +0 | 103.8 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 39.29141 | 2.46130 | 41.72554 | 6.3 % | 266270 | 44116800 | +0 | 103.8 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 5.02963 | 1.81069 | 7.86529 | 36.0 % | 25307 | 4253072 | +0 | 103.8 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.80294 | 0.19785 | 1.15312 | 24.6 % | 4013 | 309760 | +0 | 103.8 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.47553 | 0.83024 | 6.18438 | 18.6 % | 29913 | 5127328 | +0 | 103.8 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.81149 | 1.37881 | 15.98650 | 10.0 % | 92919 | 11590416 | +0 | 103.8 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 32.85162 | 3.79374 | 37.83825 | 11.5 % | 202372 | 22644144 | +0 | 103.8 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 74.72843 | 10.04892 | 87.27962 | 13.4 % | 486810 | 49139568 | +0 | 103.8 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 19.29110 | 2.65299 | 23.34763 | 13.8 % | 118226 | 15843488 | +0 | 103.8 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 52.21548 | 11.90302 | 69.43250 | 22.8 % | 227679 | 26897216 | +0 | 103.8 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 89.16420 | 12.70588 | 110.08671 | 14.2 % | 512117 | 53392640 | +0 | 103.8 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 36.07398 | 5.87168 | 47.83429 | 16.3 % | 202345 | 22639152 | +0 | 103.8 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 34.11821 | 8.68385 | 50.49788 | 25.5 % | 202372 | 22644144 | +0 | 103.8 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 33.59685 | 5.08226 | 42.10429 | 15.1 % | 202370 | 22640112 | +0 | 103.8 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 1106.43137 | 49.45292 | 1174.21312 | 4.5 % | 3554373 | 535954400 | +0 | 103.8 |

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
