# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:34:40Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.021 | [1.005, 1.037] | 0.9999 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.018 | [1.997, 2.040] | 0.9999 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.003 | [0.982, 1.024] | 0.9998 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.061 | 1.0000 | [1.054, 1.069] |
| `edgeInfo1` | edges | 4 | 1.021 | 0.9999 | [1.005, 1.037] |
| `allEdges` | edges | 4 | 2.018 | 0.9999 | [1.997, 2.040] |
| `allEdgesBulk` | edges | 4 | 1.907 | 0.9999 | [1.876, 1.939] |
| `buildOnly` | edges | 4 | 1.003 | 0.9998 | [0.982, 1.024] |
| `counts` | edges | 4 | 1.049 | 0.9996 | [1.020, 1.079] |
| `bbox` | edges | 4 | 1.023 | 0.9999 | [1.006, 1.039] |
| `mesh` | edges | 4 | 0.972 | 0.9999 | [0.957, 0.986] |
| `fuse` | edges | 4 | 1.280 | 0.9975 | [1.191, 1.369] |
| `cut` | edges | 4 | 1.293 | 0.9972 | [1.197, 1.389] |
| `rayHits` | edges | 4 | 0.291 | 0.9708 | [0.221, 0.361] |
| `filletEx1` | edges | 4 | 0.215 | 0.1029 | [-0.665, 1.096] |
| `fillet.edges` | edgesBlended | 3 | 0.618 | 0.9923 | [0.512, 0.725] |
| `fillet.scenario` | edgesBlended | 3 | 0.196 | 0.9469 | [0.105, 0.286] |
| `fillet.radius` | radius | 4 | 1.453 | 0.5976 | [-0.200, 3.106] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.83687 | 0.02017 | 3.86275 | 0.5 % | 33890 | 4998375 | +0 | 10.5 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.67117 | 0.00412 | 1.67860 | 0.2 % | 14153 | 1995433 | +0 | 11.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 331.53162 | 1.02995 | 333.49081 | 0.3 % | 2838089 | 381354081 | +0 | 12.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.47124 | 0.17260 | 22.84405 | 0.8 % | 184678 | 29382197 | +0 | 12.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.00830 | 0.12065 | 11.24652 | 1.1 % | 84141 | 210184371 | -13001 | 15.4 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07406 | 0.00053 | 0.07505 | 0.7 % | 375 | 55336 | +0 | 15.4 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05845 | 0.00011 | 0.05856 | 0.2 % | 63 | 71064 | +0 | 15.4 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.49126 | 0.04736 | 4.56568 | 1.1 % | 34051 | 7902593 | +0 | 15.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 50.43866 | 0.17054 | 50.81156 | 0.3 % | 270382 | 61747395 | +0 | 19.6 |
| `cut` | edges | 180 | 180 | 7 | 1 | 46.31569 | 0.04594 | 46.39171 | 0.1 % | 242889 | 55314367 | +0 | 19.6 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.24642 | 0.00273 | 0.25089 | 1.1 % | 1976 | 288105 | +0 | 19.6 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 28.23786 | 0.07624 | 28.35428 | 0.3 % | 211444 | 24605445 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.97171 | 0.05192 | 8.08658 | 0.7 % | 67568 | 9755627 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.46970 | 0.01046 | 3.48853 | 0.3 % | 27715 | 3818778 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1387.56187 | 27.76845 | 1448.88101 | 2.0 % | 11116716 | 1463386683 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 81.69463 | 1.19249 | 83.42639 | 1.5 % | 633716 | 97653273 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.44652 | 0.14968 | 21.77146 | 0.7 % | 167656 | 415800750 | -25993 | 24.3 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15029 | 0.00164 | 0.15362 | 1.1 % | 737 | 86168 | +0 | 24.3 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11920 | 0.00054 | 0.11982 | 0.5 % | 123 | 138744 | +0 | 24.3 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.63921 | 0.16510 | 8.93045 | 1.9 % | 67916 | 14720173 | +0 | 24.3 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 111.33899 | 0.63752 | 112.42482 | 0.6 % | 614265 | 125188815 | +0 | 25.2 |
| `cut` | edges | 360 | 360 | 7 | 1 | 102.77076 | 0.15673 | 103.04122 | 0.2 % | 560444 | 112658270 | +0 | 25.2 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.28166 | 0.00144 | 0.28337 | 0.5 % | 2096 | 361005 | +0 | 25.2 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.36001 | 0.03093 | 9.40082 | 0.3 % | 68952 | 10999707 | +0 | 26.0 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.55651 | 0.10068 | 16.77878 | 0.6 % | 134894 | 19067671 | +0 | 26.0 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.96359 | 0.03784 | 7.03701 | 0.5 % | 54839 | 7482305 | +0 | 26.0 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5500.16324 | 3.38278 | 5504.12760 | 0.1 % | 44080847 | 5736535300 | +0 | 26.0 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 304.73995 | 1.12533 | 306.13594 | 0.4 % | 2326870 | 350825415 | +0 | 26.0 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 44.24761 | 0.83895 | 46.10650 | 1.9 % | 334430 | 827097877 | -51966 | 31.9 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.30596 | 0.00340 | 0.31275 | 1.1 % | 1457 | 114824 | +0 | 31.9 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23722 | 0.00029 | 0.23769 | 0.1 % | 243 | 274104 | +0 | 31.9 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.03413 | 0.15520 | 17.30331 | 0.9 % | 135617 | 28291546 | +0 | 31.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 268.85420 | 1.39241 | 270.80381 | 0.5 % | 1539782 | 260176565 | +0 | 33.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 248.98589 | 1.54396 | 251.05000 | 0.6 % | 1432931 | 235456843 | +0 | 33.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.33990 | 0.00359 | 0.34578 | 1.1 % | 2336 | 509141 | +0 | 33.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.36221 | 0.06600 | 18.50862 | 0.4 % | 134712 | 21029952 | +0 | 33.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 34.92474 | 0.18692 | 35.32272 | 0.5 % | 269554 | 37905003 | +0 | 33.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 14.01556 | 0.04764 | 14.06322 | 0.3 % | 109093 | 14942086 | +0 | 33.2 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 22209.65699 | 19.04919 | 22228.63770 | 0.1 % | 175482141 | 22896129411 | +0 | 38.1 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1188.03385 | 13.52800 | 1218.68147 | 1.1 % | 8886777 | 1369657128 | +0 | 38.1 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 87.84193 | 1.41014 | 89.19591 | 1.6 % | 668604 | 1650856789 | -103973 | 43.8 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.66039 | 0.00672 | 0.67508 | 1.0 % | 2899 | 204697 | +0 | 43.8 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.49376 | 0.01733 | 0.53158 | 3.5 % | 483 | 544824 | +0 | 43.8 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.81621 | 0.81871 | 35.64067 | 2.4 % | 271017 | 55011702 | +0 | 43.8 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 723.99938 | 4.38255 | 730.12701 | 0.6 % | 4342922 | 571036581 | +0 | 49.8 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 683.99179 | 4.89721 | 690.52323 | 0.7 % | 4130270 | 521269888 | +0 | 49.8 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.45378 | 0.00125 | 0.45572 | 0.3 % | 2816 | 805097 | +0 | 49.8 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.08558 | 0.24328 | 37.45154 | 0.7 % | 266270 | 41701346 | +0 | 49.8 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 59.59532 | 0.22743 | 59.91217 | 0.4 % | 478775 | 64894296 | +0 | 49.8 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.74700 | 0.00072 | 0.74800 | 0.1 % | 4013 | 302664 | +0 | 49.8 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.36925 | 0.01484 | 4.39902 | 0.3 % | 29913 | 4795542 | +0 | 49.8 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.43416 | 0.06890 | 12.55898 | 0.6 % | 92923 | 10992083 | +0 | 49.8 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.17669 | 0.28533 | 26.70661 | 1.1 % | 202410 | 21703109 | +0 | 51.4 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 58.31083 | 0.30869 | 58.87562 | 0.5 % | 486842 | 47295461 | +0 | 51.4 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 72.41014 | 0.20055 | 72.71886 | 0.3 % | 571698 | 75878839 | +0 | 51.4 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 86.27996 | 0.68779 | 87.71968 | 0.8 % | 681185 | 86585642 | +0 | 51.4 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 118.62217 | 1.03320 | 120.94306 | 0.9 % | 965617 | 112191469 | +0 | 51.4 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.19505 | 0.19264 | 26.57173 | 0.7 % | 203528 | 21782437 | +0 | 51.4 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.09417 | 0.15021 | 26.38253 | 0.6 % | 202410 | 21706887 | +0 | 51.4 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.93043 | 0.04043 | 26.00781 | 0.2 % | 202365 | 21693137 | +0 | 51.4 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 754.25248 | 1.01327 | 755.31359 | 0.1 % | 3554579 | 512390198 | +0 | 52.6 |

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
