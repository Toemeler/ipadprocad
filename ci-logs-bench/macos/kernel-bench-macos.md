# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T17:25:07Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.978 | [0.735, 1.222] | 0.9687 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.787 | [1.722, 1.852] | 0.9993 | yes | **DISAGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.768 | [0.450, 1.086] | 0.9180 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.025 | 0.9341 | [0.647, 1.402] |
| `edgeInfo1` | edges | 4 | 0.978 | 0.9687 | [0.735, 1.222] |
| `allEdges` | edges | 4 | 1.787 | 0.9993 | [1.722, 1.852] |
| `allEdgesBulk` | edges | 4 | 1.648 | 0.9864 | [1.380, 1.916] |
| `buildOnly` | edges | 4 | 0.768 | 0.9180 | [0.450, 1.086] |
| `counts` | edges | 4 | 0.705 | 0.9168 | [0.411, 1.000] |
| `bbox` | edges | 4 | 0.832 | 0.9688 | [0.625, 1.039] |
| `mesh` | edges | 4 | 0.812 | 0.9474 | [0.547, 1.077] |
| `fuse` | edges | 4 | 1.139 | 0.9574 | [0.806, 1.472] |
| `cut` | edges | 4 | 1.170 | 0.9794 | [0.935, 1.405] |
| `rayHits` | edges | 4 | 0.144 | 0.6005 | [-0.019, 0.307] |
| `filletEx1` | edges | 4 | -0.018 | 0.0006 | [-1.045, 1.009] |
| `fillet.edges` | edgesBlended | 3 | 0.560 | 0.9569 | [0.327, 0.793] |
| `fillet.scenario` | edgesBlended | 3 | 0.202 | 0.9470 | [0.109, 0.296] |
| `fillet.radius` | radius | 4 | 1.456 | 0.5997 | [-0.193, 3.105] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.32346 | 0.05111 | 3.40963 | 1.5 % | 33890 | 5335600 | +0 | 14.0 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.44763 | 0.04563 | 1.54531 | 3.2 % | 14153 | 2130000 | +0 | 14.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 488.56260 | 59.64762 | 536.15404 | 12.2 % | 2838089 | 406026976 | +0 | 14.9 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 33.58732 | 5.26593 | 41.32487 | 15.7 % | 184544 | 31080240 | +0 | 15.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 17.81379 | 3.38538 | 23.16075 | 19.0 % | 84071 | 225974848 | -12160 | 22.5 |
| `counts` | edges | 180 | 180 | 7 | 16 | 0.15514 | 0.04462 | 0.20950 | 28.8 % | 375 | 59360 | +0 | 22.5 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.08498 | 0.01917 | 0.12147 | 22.6 % | 63 | 80640 | +0 | 22.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 6.64689 | 1.64895 | 9.23671 | 24.8 % | 34056 | 13154158 | +0 | 22.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 69.85219 | 7.97280 | 82.05850 | 11.4 % | 270295 | 66602965 | +0 | 27.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 58.07114 | 8.02338 | 66.98975 | 13.8 % | 242869 | 59648427 | +0 | 27.8 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.27691 | 0.10133 | 0.43506 | 36.6 % | 1976 | 308336 | +0 | 27.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 36.69480 | 8.13269 | 47.56221 | 22.2 % | 211425 | 25882480 | +0 | 29.2 |
| `build` | edges | 360 | 360 | 7 | 1 | 11.86177 | 2.45160 | 15.68104 | 20.7 % | 67568 | 10408048 | +0 | 29.2 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 4.07279 | 0.48992 | 4.71150 | 12.0 % | 27715 | 4078672 | +0 | 29.2 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1594.15733 | 208.41981 | 1859.83629 | 13.1 % | 11116716 | 1558379984 | +0 | 29.2 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 70.37328 | 0.72326 | 71.63475 | 1.0 % | 633459 | 102663664 | +0 | 29.2 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 19.48719 | 0.14617 | 19.71104 | 0.8 % | 167561 | 446577664 | -24320 | 36.0 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16551 | 0.00323 | 0.17148 | 1.9 % | 737 | 93024 | +0 | 36.0 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11422 | 0.00081 | 0.11586 | 0.7 % | 123 | 157440 | +0 | 36.0 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.08496 | 0.08353 | 8.19333 | 1.0 % | 67923 | 24575301 | +0 | 36.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 97.00279 | 2.85258 | 102.33633 | 2.9 % | 614269 | 133953163 | +0 | 40.1 |
| `cut` | edges | 360 | 360 | 7 | 1 | 91.85868 | 3.06499 | 96.64804 | 3.3 % | 560324 | 120355838 | +0 | 40.1 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.24156 | 0.00204 | 0.24560 | 0.8 % | 2096 | 392112 | +0 | 40.1 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.21293 | 0.09797 | 8.35492 | 1.2 % | 68952 | 11624128 | +0 | 40.3 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.78810 | 0.38645 | 16.39396 | 2.4 % | 134894 | 20360432 | +0 | 40.3 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.73301 | 0.12437 | 6.95917 | 1.8 % | 54839 | 7992400 | +0 | 40.3 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5382.13268 | 122.94315 | 5549.87996 | 2.3 % | 44080847 | 6109275264 | +0 | 40.3 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 288.62057 | 38.48782 | 360.18725 | 13.3 % | 2326372 | 367698944 | +0 | 40.3 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 39.00187 | 1.21828 | 40.63012 | 3.1 % | 334258 | 888838496 | -48640 | 52.5 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.32629 | 0.00523 | 0.33667 | 1.6 % | 1457 | 127584 | +0 | 52.5 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22200 | 0.00222 | 0.22525 | 1.0 % | 243 | 311040 | +0 | 52.5 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.16369 | 1.17145 | 18.28567 | 7.2 % | 135627 | 48367506 | +0 | 52.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 251.47883 | 4.04563 | 257.25729 | 1.6 % | 1539721 | 274702238 | +0 | 61.4 |
| `cut` | edges | 720 | 720 | 7 | 1 | 259.48843 | 37.52567 | 313.63129 | 14.5 % | 1432831 | 247752939 | +0 | 61.4 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.29844 | 0.01510 | 0.33220 | 5.1 % | 2336 | 559664 | +0 | 61.4 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 16.02043 | 0.14541 | 16.19829 | 0.9 % | 134712 | 22247488 | +0 | 61.4 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 32.23325 | 0.73610 | 33.49238 | 2.3 % | 269554 | 40496624 | +0 | 61.4 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 11.73927 | 0.13407 | 11.85879 | 1.1 % | 109093 | 15971536 | +0 | 61.4 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 20222.62654 | 516.05700 | 20751.98750 | 2.6 % | 175482141 | 24398762544 | +0 | 61.4 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 945.12642 | 65.00040 | 1081.41467 | 6.9 % | 8885798 | 1431758592 | +0 | 61.4 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 83.34910 | 5.01138 | 90.31683 | 6.0 % | 668060 | 1775223216 | -97280 | 86.6 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.63086 | 0.00812 | 0.64786 | 1.3 % | 2899 | 229472 | +0 | 86.6 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46514 | 0.01535 | 0.48612 | 3.3 % | 483 | 618240 | +0 | 86.6 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.44618 | 3.09768 | 39.29746 | 9.0 % | 271030 | 96173390 | +0 | 86.6 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 706.03818 | 106.41053 | 934.85346 | 15.1 % | 4342697 | 590680258 | +0 | 103.0 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 613.27787 | 32.39006 | 685.65092 | 5.3 % | 4130229 | 536962649 | +0 | 103.0 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.35997 | 0.00193 | 0.36349 | 0.5 % | 2816 | 894768 | +0 | 103.0 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 28.17062 | 0.72984 | 29.27842 | 2.6 % | 266270 | 44116800 | +0 | 103.0 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 50.32563 | 1.33944 | 53.34763 | 2.7 % | 478775 | 69176096 | +0 | 103.0 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.57119 | 0.00542 | 0.58109 | 0.9 % | 4013 | 309760 | +0 | 103.0 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.64439 | 0.04475 | 3.72592 | 1.2 % | 29913 | 5127328 | +0 | 103.0 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.07679 | 2.16862 | 14.81717 | 18.0 % | 92919 | 11590416 | +0 | 103.0 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 20.52128 | 0.40577 | 21.34163 | 2.0 % | 202372 | 22644144 | +0 | 103.0 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 49.49925 | 0.73254 | 50.56112 | 1.5 % | 486810 | 49139568 | +0 | 103.0 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 59.14101 | 1.34327 | 60.52400 | 2.3 % | 571694 | 80766512 | +0 | 103.0 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 70.91492 | 1.75323 | 72.68900 | 2.5 % | 681147 | 91820240 | +0 | 103.0 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 98.58873 | 2.19457 | 101.43917 | 2.2 % | 965585 | 118315664 | +0 | 103.0 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 21.44013 | 0.24862 | 21.96421 | 1.2 % | 202345 | 22639152 | +0 | 103.0 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 21.32629 | 0.09286 | 21.49250 | 0.4 % | 202372 | 22644144 | +0 | 103.0 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 21.41455 | 0.23315 | 21.84662 | 1.1 % | 202370 | 22640112 | +0 | 103.0 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 618.96126 | 18.51673 | 660.40067 | 3.0 % | 3554373 | 535954400 | +0 | 103.0 |

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
