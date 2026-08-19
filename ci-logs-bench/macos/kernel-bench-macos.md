# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T23:28:31Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.045 | [0.764, 1.325] | 0.9638 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.011 | [1.987, 2.036] | 0.9999 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.103 | [0.980, 1.225] | 0.9936 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.030 | 0.9995 | [0.999, 1.061] |
| `edgeInfo1` | edges | 4 | 1.045 | 0.9638 | [0.764, 1.325] |
| `allEdges` | edges | 4 | 2.011 | 0.9999 | [1.987, 2.036] |
| `allEdgesBulk` | edges | 4 | 1.865 | 0.9985 | [1.766, 1.963] |
| `buildOnly` | edges | 4 | 1.103 | 0.9936 | [0.980, 1.225] |
| `counts` | edges | 4 | 1.039 | 0.9992 | [0.998, 1.081] |
| `bbox` | edges | 4 | 0.844 | 0.9834 | [0.692, 0.996] |
| `mesh` | edges | 4 | 1.011 | 0.9988 | [0.962, 1.061] |
| `fuse` | edges | 4 | 1.008 | 0.9088 | [0.566, 1.451] |
| `cut` | edges | 4 | 1.344 | 0.9956 | [1.221, 1.468] |
| `rayHits` | edges | 4 | 0.252 | 0.8965 | [0.133, 0.371] |
| `filletEx1` | edges | 4 | 0.150 | 0.0460 | [-0.799, 1.100] |
| `fillet.edges` | edgesBlended | 3 | 0.596 | 0.9937 | [0.504, 0.689] |
| `fillet.scenario` | edgesBlended | 3 | 0.177 | 0.8973 | [0.060, 0.294] |
| `fillet.radius` | radius | 4 | 1.636 | 0.6357 | [-0.081, 3.353] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.55808 | 0.17638 | 3.92733 | 5.0 % | 33890 | 5335600 | +0 | 14.3 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.54700 | 0.17194 | 1.93617 | 11.1 % | 14153 | 2130000 | +0 | 15.1 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 325.45977 | 16.43568 | 359.10558 | 5.0 % | 2838089 | 406026976 | +0 | 15.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 21.03733 | 0.72951 | 21.88863 | 3.5 % | 184680 | 30723440 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 9.84442 | 0.35805 | 10.34479 | 3.6 % | 84071 | 225974848 | -12160 | 22.9 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08095 | 0.00241 | 0.08550 | 3.0 % | 375 | 59360 | +0 | 22.9 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.07030 | 0.02629 | 0.12814 | 37.4 % | 63 | 80640 | +0 | 22.9 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.22213 | 0.58817 | 5.51896 | 13.9 % | 34056 | 13154158 | +0 | 23.0 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 99.18915 | 73.66509 | 217.57558 | 74.3 % | 270412 | 66623335 | +0 | 28.2 |
| `cut` | edges | 180 | 180 | 7 | 1 | 39.26642 | 1.73070 | 41.70271 | 4.4 % | 242921 | 59659106 | +0 | 28.3 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.21198 | 0.00435 | 0.21716 | 2.1 % | 1976 | 308336 | +0 | 28.3 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 26.26673 | 0.86993 | 27.19321 | 3.3 % | 211425 | 25882480 | +0 | 30.0 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.06459 | 1.00544 | 9.31429 | 14.2 % | 67568 | 10408048 | +0 | 30.0 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.03793 | 0.51282 | 4.19862 | 16.9 % | 27715 | 4078672 | +0 | 30.0 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1357.71256 | 77.66259 | 1450.64633 | 5.7 % | 11116716 | 1558379984 | +0 | 30.0 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 67.37164 | 5.26375 | 74.93592 | 7.8 % | 633718 | 101960880 | +0 | 30.1 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 17.73539 | 0.24967 | 18.06462 | 1.4 % | 167561 | 446577664 | -24320 | 36.7 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15812 | 0.00090 | 0.15961 | 0.6 % | 737 | 93024 | +0 | 36.7 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.15159 | 0.08760 | 0.34238 | 57.8 % | 123 | 157440 | +0 | 36.7 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 7.99115 | 0.27863 | 8.36475 | 3.5 % | 67923 | 24575301 | +0 | 36.7 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 115.22265 | 38.05655 | 191.57063 | 33.0 % | 614286 | 133956674 | +0 | 40.4 |
| `cut` | edges | 360 | 360 | 7 | 1 | 82.82816 | 3.49620 | 89.99783 | 4.2 % | 560322 | 120355399 | +0 | 40.4 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.22626 | 0.00221 | 0.22932 | 1.0 % | 2096 | 392112 | +0 | 40.4 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 7.61245 | 0.35120 | 8.24329 | 4.6 % | 68952 | 11624128 | +0 | 40.6 |
| `build` | edges | 720 | 720 | 7 | 1 | 14.29395 | 0.37973 | 14.88825 | 2.7 % | 134894 | 20360432 | +0 | 40.6 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 8.84331 | 2.01754 | 13.08867 | 22.8 % | 54839 | 7992400 | +0 | 40.6 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5298.11644 | 27.80612 | 5320.55633 | 0.5 % | 44080847 | 6109275264 | +0 | 40.6 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 253.23699 | 5.23170 | 257.43229 | 2.1 % | 2326872 | 366271424 | +0 | 40.6 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 41.10494 | 0.83533 | 41.95188 | 2.0 % | 334258 | 888838496 | -48640 | 53.3 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.34551 | 0.01641 | 0.36820 | 4.7 % | 1457 | 127584 | +0 | 53.3 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.21774 | 0.00687 | 0.23092 | 3.2 % | 243 | 311040 | +0 | 53.3 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.31968 | 0.90349 | 17.57796 | 5.5 % | 135627 | 48367506 | +0 | 53.3 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 253.05275 | 7.55808 | 269.09925 | 3.0 % | 1539824 | 274723303 | +0 | 61.8 |
| `cut` | edges | 720 | 720 | 7 | 1 | 235.85368 | 23.58984 | 288.05458 | 10.0 % | 1432971 | 247781611 | +0 | 61.8 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.26111 | 0.01425 | 0.29271 | 5.5 % | 2336 | 559664 | +0 | 61.8 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 14.51387 | 1.09457 | 16.21533 | 7.5 % | 134712 | 22247488 | +0 | 61.8 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 30.38073 | 1.81231 | 32.26404 | 6.0 % | 269554 | 40496624 | +0 | 61.8 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 12.10858 | 0.53418 | 13.18658 | 4.4 % | 109093 | 15971536 | +0 | 61.8 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 21566.31525 | 562.21459 | 22215.27913 | 2.6 % | 175482141 | 24398762544 | +0 | 61.8 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1005.96038 | 88.64598 | 1191.28517 | 8.8 % | 8886779 | 1428881600 | +0 | 61.8 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 95.05571 | 13.30479 | 116.88329 | 14.0 % | 668060 | 1775223216 | -97280 | 87.0 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.68875 | 0.01913 | 0.71588 | 2.8 % | 2899 | 229472 | +0 | 87.0 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.43822 | 0.01956 | 0.47707 | 4.5 % | 483 | 618240 | +0 | 87.0 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.43214 | 4.29575 | 43.66125 | 12.5 % | 271030 | 96173390 | +0 | 87.0 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 784.39385 | 113.54560 | 974.67333 | 14.5 % | 4342727 | 590686402 | +0 | 103.5 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 618.84052 | 54.52360 | 692.70538 | 8.8 % | 4130119 | 536940121 | +0 | 103.5 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.36203 | 0.01174 | 0.37684 | 3.2 % | 2816 | 894768 | +0 | 103.5 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 29.98830 | 1.46216 | 31.42983 | 4.9 % | 266270 | 44116800 | +0 | 103.5 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 51.65070 | 2.56105 | 54.22021 | 5.0 % | 478775 | 69176096 | +0 | 103.5 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.62085 | 0.02663 | 0.67081 | 4.3 % | 4013 | 309760 | +0 | 103.5 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.02501 | 0.17326 | 4.35621 | 4.3 % | 29913 | 5127328 | +0 | 103.5 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.30232 | 0.17854 | 11.58671 | 1.6 % | 92919 | 11590416 | +0 | 103.5 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 23.42312 | 0.23602 | 23.75067 | 1.0 % | 202372 | 22644144 | +0 | 103.5 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 50.12383 | 2.26929 | 53.20733 | 4.5 % | 486810 | 49139568 | +0 | 103.5 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 58.16523 | 1.16364 | 60.73950 | 2.0 % | 571694 | 80766512 | +0 | 103.5 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 65.68185 | 0.61672 | 66.69496 | 0.9 % | 681147 | 91820240 | +0 | 103.5 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 91.21580 | 0.89170 | 92.78250 | 1.0 % | 965585 | 118315664 | +0 | 103.5 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 19.51051 | 0.12137 | 19.77263 | 0.6 % | 202345 | 22639152 | +0 | 103.5 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 20.21226 | 0.77107 | 21.52800 | 3.8 % | 202372 | 22644144 | +0 | 103.5 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 23.02398 | 0.43989 | 23.57821 | 1.9 % | 202370 | 22640112 | +0 | 103.5 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 818.72614 | 132.65426 | 1022.69921 | 16.2 % | 3554373 | 535954400 | +0 | 103.5 |

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
