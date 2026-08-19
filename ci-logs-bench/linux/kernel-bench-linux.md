# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T17:26:19Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.031 | [1.016, 1.046] | 0.9999 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.031 | [2.013, 2.049] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.011 | [0.989, 1.033] | 0.9998 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.064 | 0.9994 | [1.028, 1.101] |
| `edgeInfo1` | edges | 4 | 1.031 | 0.9999 | [1.016, 1.046] |
| `allEdges` | edges | 4 | 2.031 | 1.0000 | [2.013, 2.049] |
| `allEdgesBulk` | edges | 4 | 1.912 | 0.9993 | [1.843, 1.982] |
| `buildOnly` | edges | 4 | 1.011 | 0.9998 | [0.989, 1.033] |
| `counts` | edges | 4 | 1.038 | 0.9983 | [0.978, 1.098] |
| `bbox` | edges | 4 | 1.004 | 0.9997 | [0.979, 1.030] |
| `mesh` | edges | 4 | 0.964 | 0.9987 | [0.916, 1.012] |
| `fuse` | edges | 4 | 1.276 | 0.9981 | [1.199, 1.354] |
| `cut` | edges | 4 | 1.302 | 0.9971 | [1.204, 1.399] |
| `rayHits` | edges | 4 | 0.325 | 0.9722 | [0.249, 0.401] |
| `filletEx1` | edges | 4 | 0.217 | 0.1030 | [-0.671, 1.106] |
| `fillet.edges` | edgesBlended | 3 | 0.607 | 0.9899 | [0.486, 0.727] |
| `fillet.scenario` | edgesBlended | 3 | 0.191 | 0.9468 | [0.102, 0.279] |
| `fillet.radius` | radius | 4 | 1.476 | 0.6014 | [-0.189, 3.141] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.71689 | 0.02415 | 3.74821 | 0.6 % | 33890 | 4998032 | +0 | 10.7 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.61121 | 0.01164 | 1.62980 | 0.7 % | 14153 | 1995163 | +0 | 11.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 323.04101 | 6.75966 | 337.34909 | 2.1 % | 2838089 | 381394483 | +0 | 12.1 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 21.83096 | 0.09921 | 21.94619 | 0.5 % | 184544 | 29730565 | +0 | 12.1 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.93005 | 0.12443 | 11.18259 | 1.1 % | 84141 | 210182579 | -13013 | 15.4 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07529 | 0.00063 | 0.07658 | 0.8 % | 375 | 55336 | +0 | 15.4 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05608 | 0.00069 | 0.05763 | 1.2 % | 63 | 71064 | +0 | 15.4 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.36581 | 0.07184 | 4.51689 | 1.6 % | 34051 | 7905720 | +0 | 15.4 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 53.91182 | 0.40118 | 54.57959 | 0.7 % | 270330 | 61751151 | +0 | 19.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 49.14976 | 0.38597 | 49.83128 | 0.8 % | 242904 | 55315723 | +0 | 19.7 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.22158 | 0.00129 | 0.22425 | 0.6 % | 1976 | 288877 | +0 | 19.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 28.69811 | 0.11642 | 28.85953 | 0.4 % | 211444 | 24606889 | +0 | 21.9 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.75577 | 0.01510 | 7.78129 | 0.2 % | 67568 | 9756761 | +0 | 21.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.34971 | 0.02075 | 3.38065 | 0.6 % | 27715 | 3818874 | +0 | 21.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1333.21527 | 2.82606 | 1338.29225 | 0.2 % | 11116716 | 1463355481 | +0 | 27.2 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 76.13760 | 0.23063 | 76.49795 | 0.3 % | 633459 | 98194778 | +0 | 27.2 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.31881 | 0.13381 | 21.50654 | 0.6 % | 167656 | 415798722 | -25998 | 29.4 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15144 | 0.00128 | 0.15399 | 0.8 % | 737 | 86040 | +0 | 29.4 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11688 | 0.00476 | 0.12560 | 4.1 % | 123 | 138744 | +0 | 29.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.39418 | 0.07933 | 8.53950 | 0.9 % | 67916 | 14712303 | +0 | 29.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 122.13049 | 9.12509 | 142.71503 | 7.5 % | 614237 | 125157859 | +0 | 29.4 |
| `cut` | edges | 360 | 360 | 7 | 1 | 108.08106 | 0.45237 | 108.76347 | 0.4 % | 560337 | 112652057 | +0 | 29.4 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.25259 | 0.00246 | 0.25700 | 1.0 % | 2096 | 361111 | +0 | 29.4 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.41931 | 0.08842 | 9.57567 | 0.9 % | 68952 | 10993995 | +0 | 29.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.59382 | 0.04451 | 15.66911 | 0.3 % | 134894 | 19067746 | +0 | 29.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.69457 | 0.02076 | 6.72410 | 0.3 % | 54839 | 7482335 | +0 | 29.4 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5314.33179 | 15.37392 | 5329.67804 | 0.3 % | 44080847 | 5736558520 | +0 | 29.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 286.15356 | 1.19049 | 287.72756 | 0.4 % | 2326372 | 351874427 | +0 | 29.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 43.79916 | 0.34691 | 44.15419 | 0.8 % | 334430 | 827070446 | -51973 | 31.9 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.29531 | 0.00234 | 0.29829 | 0.8 % | 1457 | 114824 | +0 | 31.9 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22807 | 0.00230 | 0.23056 | 1.0 % | 243 | 274104 | +0 | 31.9 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.43558 | 0.20033 | 17.68518 | 1.1 % | 135617 | 28303880 | +0 | 31.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 288.28346 | 1.86560 | 290.39891 | 0.6 % | 1539843 | 260116952 | +0 | 34.5 |
| `cut` | edges | 720 | 720 | 7 | 1 | 268.43602 | 2.89776 | 271.63195 | 1.1 % | 1432875 | 235399207 | +0 | 34.5 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.32119 | 0.01200 | 0.34816 | 3.7 % | 2336 | 508806 | +0 | 34.5 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.57941 | 0.33105 | 19.31199 | 1.8 % | 134712 | 21028107 | +0 | 34.5 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 34.43974 | 0.14462 | 34.62039 | 0.4 % | 269554 | 37905022 | +0 | 34.5 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 13.83892 | 0.06220 | 13.94884 | 0.4 % | 109093 | 14941137 | +0 | 34.5 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 22244.32038 | 377.19685 | 22523.54395 | 1.7 % | 175482141 | 22893803069 | +0 | 34.5 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1165.16415 | 5.00861 | 1172.13883 | 0.4 % | 8885798 | 1372287241 | +0 | 34.5 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 88.89896 | 0.70685 | 89.85801 | 0.8 % | 668604 | 1650869993 | -103931 | 43.5 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.66297 | 0.02073 | 0.68603 | 3.1 % | 2899 | 204649 | +0 | 43.5 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.45697 | 0.00160 | 0.45891 | 0.3 % | 483 | 544840 | +0 | 43.5 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 31.73985 | 0.51720 | 32.90225 | 1.6 % | 271017 | 55035777 | +0 | 43.5 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 772.98824 | 2.96956 | 778.05304 | 0.4 % | 4342812 | 570165589 | +0 | 48.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 734.28546 | 5.40594 | 741.37774 | 0.7 % | 4130222 | 521042155 | +0 | 48.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.43360 | 0.00598 | 0.44665 | 1.4 % | 2816 | 804824 | +0 | 48.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.80588 | 0.17894 | 38.03573 | 0.5 % | 266270 | 41706551 | +0 | 48.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 58.01737 | 0.06775 | 58.10114 | 0.1 % | 478775 | 64927656 | +0 | 48.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.75239 | 0.00393 | 0.76117 | 0.5 % | 4013 | 303096 | +0 | 48.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.27260 | 0.05870 | 4.39043 | 1.4 % | 29913 | 4794477 | +0 | 48.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.60466 | 0.11172 | 12.78294 | 0.9 % | 92923 | 10992595 | +0 | 48.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 25.74270 | 0.08050 | 25.87894 | 0.3 % | 202410 | 21702880 | +0 | 50.3 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 57.48441 | 0.57413 | 58.59306 | 1.0 % | 486842 | 47282375 | +0 | 50.3 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 71.50490 | 0.31463 | 72.01685 | 0.4 % | 571698 | 75950722 | +0 | 50.3 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 84.81630 | 0.22105 | 85.09123 | 0.3 % | 681185 | 86657329 | +0 | 50.3 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 115.68539 | 0.27710 | 116.08605 | 0.2 % | 965617 | 112226643 | +0 | 50.3 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.84252 | 0.15423 | 26.09726 | 0.6 % | 203528 | 21786242 | +0 | 50.3 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.83665 | 0.10779 | 26.04056 | 0.4 % | 202410 | 21701659 | +0 | 50.3 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 26.00220 | 0.13969 | 26.26822 | 0.5 % | 202365 | 21692611 | +0 | 50.3 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 780.70213 | 5.57299 | 791.77540 | 0.7 % | 3554579 | 512475075 | +0 | 51.3 |

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
