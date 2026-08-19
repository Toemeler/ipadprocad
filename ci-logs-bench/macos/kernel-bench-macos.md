# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T19:37:16Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.961 | [0.910, 1.013] | 0.9985 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.954 | [1.885, 2.023] | 0.9993 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.014 | [0.925, 1.104] | 0.9960 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.059 | 0.9907 | [0.916, 1.201] |
| `edgeInfo1` | edges | 4 | 0.961 | 0.9985 | [0.910, 1.013] |
| `allEdges` | edges | 4 | 1.954 | 0.9993 | [1.885, 2.023] |
| `allEdgesBulk` | edges | 4 | 1.788 | 0.9981 | [1.679, 1.896] |
| `buildOnly` | edges | 4 | 1.014 | 0.9960 | [0.925, 1.104] |
| `counts` | edges | 4 | 0.991 | 0.9976 | [0.924, 1.058] |
| `bbox` | edges | 4 | 0.969 | 0.9982 | [0.912, 1.026] |
| `mesh` | edges | 4 | 0.548 | 0.6625 | [0.006, 1.090] |
| `fuse` | edges | 4 | 1.215 | 0.9978 | [1.135, 1.295] |
| `cut` | edges | 4 | 1.266 | 0.9983 | [1.193, 1.338] |
| `rayHits` | edges | 4 | 0.120 | 0.4793 | [-0.053, 0.294] |
| `filletEx1` | edges | 4 | -0.002 | 0.0000 | [-1.016, 1.012] |
| `fillet.edges` | edgesBlended | 3 | 0.675 | 0.9841 | [0.507, 0.843] |
| `fillet.scenario` | edgesBlended | 3 | 0.156 | 0.8703 | [0.038, 0.274] |
| `fillet.radius` | radius | 4 | 1.456 | 0.5998 | [-0.192, 3.105] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.63242 | 0.07190 | 3.76542 | 2.0 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.79202 | 0.58385 | 3.11471 | 32.6 % | 14153 | 2130000 | +0 | 15.0 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 404.48764 | 43.89526 | 489.18892 | 10.9 % | 2838089 | 406026976 | +0 | 15.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 26.59508 | 9.66607 | 44.74188 | 36.3 % | 184680 | 30723440 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.31257 | 1.50473 | 13.50429 | 13.3 % | 84071 | 225974848 | -12160 | 23.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08029 | 0.00085 | 0.08129 | 1.1 % | 375 | 59360 | +0 | 23.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05607 | 0.00410 | 0.06508 | 7.3 % | 63 | 80640 | +0 | 23.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 12.58840 | 7.30802 | 24.36308 | 58.1 % | 34056 | 13154158 | +0 | 23.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 52.42842 | 17.20299 | 87.70775 | 32.8 % | 270379 | 66620080 | +0 | 29.1 |
| `cut` | edges | 180 | 180 | 7 | 1 | 45.44088 | 8.56896 | 62.74450 | 18.9 % | 242869 | 59648574 | +0 | 29.1 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.27056 | 0.03746 | 0.32757 | 13.8 % | 1976 | 308336 | +0 | 29.2 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 35.67620 | 11.06152 | 53.00683 | 31.0 % | 211425 | 25882480 | +0 | 30.9 |
| `build` | edges | 360 | 360 | 7 | 1 | 9.33829 | 2.97183 | 15.92800 | 31.8 % | 67568 | 10408048 | +0 | 30.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.29792 | 0.11336 | 3.40888 | 3.4 % | 27715 | 4078672 | +0 | 30.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1426.06514 | 78.79122 | 1560.66538 | 5.5 % | 11116716 | 1558379984 | +0 | 30.9 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 78.17348 | 4.14095 | 84.08554 | 5.3 % | 633718 | 101960880 | +0 | 30.9 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.19673 | 2.47744 | 25.18604 | 11.7 % | 167561 | 446577664 | -24320 | 37.2 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.17638 | 0.03258 | 0.24960 | 18.5 % | 737 | 93024 | +0 | 37.2 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.10889 | 0.00190 | 0.11173 | 1.7 % | 123 | 157440 | +0 | 37.2 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.32555 | 0.41880 | 9.05358 | 5.0 % | 67923 | 24575301 | +0 | 37.2 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 110.00811 | 7.20741 | 119.18933 | 6.6 % | 614311 | 133961794 | +0 | 40.9 |
| `cut` | edges | 360 | 360 | 7 | 1 | 98.03689 | 10.34218 | 115.82488 | 10.5 % | 560360 | 120363152 | +0 | 40.9 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.33164 | 0.15678 | 0.58748 | 47.3 % | 2096 | 392112 | +0 | 40.9 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.21242 | 0.14432 | 8.40979 | 1.8 % | 68952 | 11624128 | +0 | 41.1 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.42583 | 1.96066 | 19.81325 | 11.9 % | 134894 | 20360432 | +0 | 41.1 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.93357 | 0.63096 | 7.92404 | 9.1 % | 54839 | 7992400 | +0 | 41.1 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5695.67690 | 189.72494 | 5970.37258 | 3.3 % | 44080847 | 6109275264 | +0 | 41.1 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 295.52742 | 31.44274 | 331.29292 | 10.6 % | 2326872 | 366271424 | +0 | 41.1 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 48.91499 | 4.60733 | 54.83925 | 9.4 % | 334258 | 888838496 | -48640 | 54.0 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.32761 | 0.00683 | 0.33741 | 2.1 % | 1457 | 127584 | +0 | 54.0 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22843 | 0.00323 | 0.23513 | 1.4 % | 243 | 311040 | +0 | 54.0 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 18.07482 | 2.03999 | 21.79500 | 11.3 % | 135627 | 48367506 | +0 | 54.1 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 260.51581 | 11.17207 | 281.18042 | 4.3 % | 1539689 | 274695655 | +0 | 62.5 |
| `cut` | edges | 720 | 720 | 7 | 1 | 255.92813 | 8.88701 | 271.15879 | 3.5 % | 1432899 | 247766983 | +0 | 62.5 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.28001 | 0.01239 | 0.30297 | 4.4 % | 2336 | 559664 | +0 | 62.5 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 16.20266 | 1.22678 | 18.49558 | 7.6 % | 134712 | 22247488 | +0 | 62.5 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 34.75421 | 3.39231 | 40.20433 | 9.8 % | 269554 | 40496624 | +0 | 62.5 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 12.89270 | 1.32975 | 15.52021 | 10.3 % | 109093 | 15971536 | +0 | 62.5 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 23278.65324 | 608.81346 | 23727.77117 | 2.6 % | 175482141 | 24398762544 | +0 | 62.5 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1062.08777 | 96.37604 | 1178.94950 | 9.1 % | 8886779 | 1428881600 | +0 | 62.6 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 89.21229 | 4.01490 | 95.70829 | 4.5 % | 668060 | 1775223216 | -97280 | 87.6 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.64476 | 0.01851 | 0.67209 | 2.9 % | 2899 | 229472 | +0 | 87.6 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.41119 | 0.00894 | 0.42770 | 2.2 % | 483 | 618240 | +0 | 87.6 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.46075 | 3.45617 | 39.79471 | 10.0 % | 271030 | 96173390 | +0 | 87.6 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 651.68803 | 18.87596 | 692.41371 | 2.9 % | 4342790 | 590699275 | +0 | 103.7 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 614.54257 | 16.46893 | 646.27679 | 2.7 % | 4130336 | 536939646 | +0 | 103.7 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.37801 | 0.02387 | 0.41935 | 6.3 % | 2816 | 894768 | +0 | 103.7 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 28.32411 | 1.25813 | 30.86796 | 4.4 % | 266270 | 44116800 | +0 | 103.7 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 49.06333 | 1.36652 | 51.74504 | 2.8 % | 478775 | 69176096 | +0 | 103.7 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.59553 | 0.01990 | 0.62022 | 3.3 % | 4013 | 309760 | +0 | 103.7 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.53749 | 0.12186 | 3.71579 | 3.4 % | 29913 | 5127328 | +0 | 103.7 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 10.11689 | 0.18524 | 10.33550 | 1.8 % | 92919 | 11590416 | +0 | 103.7 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 21.59101 | 0.57822 | 22.14862 | 2.7 % | 202372 | 22644144 | +0 | 103.7 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 54.88729 | 4.97058 | 62.11113 | 9.1 % | 486810 | 49139568 | +0 | 103.7 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 65.46460 | 2.98414 | 71.32408 | 4.6 % | 571694 | 80766512 | +0 | 103.7 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 71.74742 | 1.45207 | 73.61742 | 2.0 % | 681147 | 91820240 | +0 | 103.7 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 97.42282 | 0.86485 | 98.53875 | 0.9 % | 965585 | 118315664 | +0 | 103.7 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 21.30859 | 0.49022 | 21.93850 | 2.3 % | 202345 | 22639152 | +0 | 103.7 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 20.98088 | 0.52463 | 21.94692 | 2.5 % | 202372 | 22644144 | +0 | 103.7 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 21.29130 | 0.61971 | 22.17004 | 2.9 % | 202370 | 22640112 | +0 | 103.7 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 613.50865 | 7.15619 | 624.40808 | 1.2 % | 3554373 | 535954400 | +0 | 103.7 |

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
