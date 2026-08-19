# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:25:01Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.030 | [1.008, 1.051] | 0.9998 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.016 | [2.009, 2.023] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.975 | [0.944, 1.006] | 0.9995 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.055 | 0.9998 | [1.037, 1.073] |
| `edgeInfo1` | edges | 4 | 1.030 | 0.9998 | [1.008, 1.051] |
| `allEdges` | edges | 4 | 2.016 | 1.0000 | [2.009, 2.023] |
| `allEdgesBulk` | edges | 4 | 1.898 | 0.9997 | [1.852, 1.945] |
| `buildOnly` | edges | 4 | 0.975 | 0.9995 | [0.944, 1.006] |
| `counts` | edges | 4 | 1.056 | 0.9996 | [1.026, 1.087] |
| `bbox` | edges | 4 | 1.014 | 0.9999 | [1.000, 1.028] |
| `mesh` | edges | 4 | 0.946 | 0.9995 | [0.917, 0.974] |
| `fuse` | edges | 4 | 1.288 | 0.9972 | [1.193, 1.382] |
| `cut` | edges | 4 | 1.296 | 0.9969 | [1.196, 1.396] |
| `rayHits` | edges | 4 | 0.296 | 0.9737 | [0.228, 0.363] |
| `filletEx1` | edges | 4 | 0.216 | 0.1018 | [-0.674, 1.106] |
| `fillet.edges` | edgesBlended | 3 | 0.619 | 0.9918 | [0.508, 0.730] |
| `fillet.scenario` | edgesBlended | 3 | 0.195 | 0.9448 | [0.103, 0.287] |
| `fillet.radius` | radius | 4 | 1.456 | 0.5998 | [-0.192, 3.104] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.96003 | 0.02382 | 3.99773 | 0.6 % | 33890 | 4998080 | +0 | 11.0 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.71147 | 0.01114 | 1.72319 | 0.7 % | 14153 | 1997181 | +0 | 12.0 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 339.93764 | 4.33330 | 349.46598 | 1.3 % | 2838089 | 381728703 | +0 | 12.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.31590 | 0.20298 | 22.68507 | 0.9 % | 184544 | 29699127 | +0 | 12.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.80606 | 0.18754 | 12.14469 | 1.6 % | 84141 | 210182513 | -13017 | 15.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07351 | 0.00047 | 0.07430 | 0.6 % | 375 | 55368 | +0 | 15.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05624 | 0.00122 | 0.05893 | 2.2 % | 63 | 71064 | +0 | 15.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.69771 | 0.03471 | 4.75441 | 0.7 % | 34051 | 7906547 | +0 | 15.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 50.99382 | 0.14038 | 51.13731 | 0.3 % | 270336 | 61737498 | +0 | 19.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 46.96255 | 0.34945 | 47.70842 | 0.7 % | 242957 | 55305667 | +0 | 19.8 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25000 | 0.00222 | 0.25382 | 0.9 % | 1976 | 287893 | +0 | 19.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 28.60854 | 0.31749 | 29.27264 | 1.1 % | 211444 | 24604688 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.07038 | 0.04219 | 8.11461 | 0.5 % | 67568 | 9755600 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.53305 | 0.03581 | 3.58855 | 1.0 % | 27715 | 3818625 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1389.35579 | 1.22772 | 1390.97643 | 0.1 % | 11116716 | 1463366480 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 78.59041 | 0.32786 | 79.18195 | 0.4 % | 633459 | 98185455 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.22548 | 0.29383 | 22.58213 | 1.3 % | 167656 | 415789502 | -25991 | 25.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14901 | 0.00100 | 0.15038 | 0.7 % | 737 | 86168 | +0 | 25.1 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11127 | 0.00012 | 0.11143 | 0.1 % | 123 | 138744 | +0 | 25.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.67343 | 0.13086 | 8.90394 | 1.5 % | 67916 | 14716271 | +0 | 25.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 112.72233 | 0.34157 | 113.27156 | 0.3 % | 614270 | 125207987 | +0 | 25.4 |
| `cut` | edges | 360 | 360 | 7 | 1 | 103.93604 | 0.33745 | 104.63034 | 0.3 % | 560322 | 112654427 | +0 | 25.4 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.28286 | 0.00324 | 0.28678 | 1.1 % | 2096 | 361257 | +0 | 25.4 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.29220 | 0.03840 | 9.34465 | 0.4 % | 68952 | 10994343 | +0 | 26.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.73719 | 0.12933 | 16.96433 | 0.8 % | 134894 | 19067739 | +0 | 26.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.00023 | 0.02605 | 7.04897 | 0.4 % | 54839 | 7481695 | +0 | 26.4 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5567.77482 | 6.83134 | 5574.52447 | 0.1 % | 44080847 | 5736380100 | +0 | 26.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 295.18884 | 0.78305 | 296.07788 | 0.3 % | 2326372 | 351850199 | +0 | 26.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 44.35390 | 0.22825 | 44.61076 | 0.5 % | 334430 | 827080023 | -51995 | 30.8 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.30658 | 0.00506 | 0.31441 | 1.7 % | 1457 | 114872 | +0 | 30.8 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22665 | 0.00066 | 0.22792 | 0.3 % | 243 | 274104 | +0 | 30.8 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.06884 | 0.08589 | 17.20281 | 0.5 % | 135617 | 28310342 | +0 | 30.8 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 272.53868 | 1.14207 | 273.80593 | 0.4 % | 1539751 | 259966618 | +0 | 33.6 |
| `cut` | edges | 720 | 720 | 7 | 1 | 252.49521 | 2.06550 | 255.40148 | 0.8 % | 1432997 | 235355395 | +0 | 33.6 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.35057 | 0.02050 | 0.39698 | 5.8 % | 2336 | 511642 | +0 | 33.6 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.77275 | 0.71448 | 20.39268 | 3.8 % | 134712 | 21029675 | +0 | 33.6 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 35.54261 | 0.09237 | 35.66979 | 0.3 % | 269554 | 37904869 | +0 | 33.6 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 14.70754 | 0.94276 | 16.46172 | 6.4 % | 109093 | 14942918 | +0 | 33.6 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 22553.89985 | 10.69248 | 22561.30082 | 0.0 % | 175482141 | 22896546861 | +0 | 33.6 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1153.54638 | 3.24226 | 1157.59944 | 0.3 % | 8885798 | 1372601662 | +0 | 38.5 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 89.14513 | 1.65174 | 92.51963 | 1.9 % | 668604 | 1650872992 | -103954 | 44.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.66368 | 0.00445 | 0.67288 | 0.7 % | 2899 | 204649 | +0 | 44.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46146 | 0.00125 | 0.46311 | 0.3 % | 483 | 544824 | +0 | 44.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.31819 | 0.17426 | 33.52762 | 0.5 % | 271017 | 55024294 | +0 | 44.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 744.36206 | 6.75532 | 752.80263 | 0.9 % | 4342845 | 571154297 | +0 | 50.4 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 698.25633 | 8.06189 | 709.19526 | 1.2 % | 4129991 | 521230285 | +0 | 50.4 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.46079 | 0.00425 | 0.46847 | 0.9 % | 2816 | 804587 | +0 | 50.4 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.28117 | 0.25857 | 37.78663 | 0.7 % | 266270 | 41697762 | +0 | 50.4 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 60.72533 | 0.23364 | 61.14496 | 0.4 % | 478775 | 64908522 | +0 | 50.4 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.76261 | 0.00486 | 0.77301 | 0.6 % | 4013 | 303944 | +0 | 50.4 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.45740 | 0.06457 | 4.59398 | 1.4 % | 29913 | 4796298 | +0 | 50.4 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.58987 | 0.05762 | 12.67176 | 0.5 % | 92923 | 10992851 | +0 | 50.4 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.42664 | 0.06709 | 26.53509 | 0.3 % | 202410 | 21701943 | +0 | 51.7 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 59.18854 | 0.25537 | 59.59439 | 0.4 % | 486842 | 47287211 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 73.37994 | 0.18681 | 73.59395 | 0.3 % | 571698 | 75899767 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 87.20931 | 0.16100 | 87.38755 | 0.2 % | 681185 | 86603270 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 120.02138 | 0.20107 | 120.37497 | 0.2 % | 965617 | 112179601 | +0 | 51.7 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.40418 | 0.14805 | 26.71605 | 0.6 % | 203528 | 21783191 | +0 | 51.7 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.25694 | 0.12118 | 26.44559 | 0.5 % | 202410 | 21704969 | +0 | 51.7 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 26.38139 | 0.21972 | 26.85306 | 0.8 % | 202365 | 21690019 | +0 | 51.7 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 761.95600 | 1.25649 | 763.67460 | 0.2 % | 3554579 | 512341656 | +0 | 52.9 |

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
