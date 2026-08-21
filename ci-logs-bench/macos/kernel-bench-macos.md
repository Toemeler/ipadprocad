# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-21T11:33:49Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v22) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.041 | [0.991, 1.091] | 0.9988 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.024 | [1.993, 2.054] | 0.9999 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.090 | [1.003, 1.178] | 0.9967 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.039 | 0.9998 | [1.017, 1.061] |
| `edgeInfo1` | edges | 4 | 1.041 | 0.9988 | [0.991, 1.091] |
| `allEdges` | edges | 4 | 2.024 | 0.9999 | [1.993, 2.054] |
| `allEdgesBulk` | edges | 4 | 1.040 | 0.9996 | [1.013, 1.068] |
| `buildOnly` | edges | 4 | 1.090 | 0.9967 | [1.003, 1.178] |
| `counts` | edges | 4 | 1.015 | 0.9963 | [0.928, 1.101] |
| `bbox` | edges | 4 | 1.049 | 0.9988 | [0.998, 1.099] |
| `mesh` | edges | 4 | 1.017 | 1.0000 | [1.013, 1.020] |
| `fuse` | edges | 4 | 1.343 | 0.9993 | [1.293, 1.393] |
| `cut` | edges | 4 | 1.382 | 0.9958 | [1.258, 1.506] |
| `rayHits` | edges | 4 | 0.245 | 0.8166 | [0.084, 0.406] |
| `filletEx1` | edges | 4 | 0.185 | 0.0774 | [-0.700, 1.071] |
| `fillet.edges` | edgesBlended | 3 | 0.621 | 0.9942 | [0.528, 0.714] |
| `fillet.scenario` | edgesBlended | 3 | 0.527 | 0.9915 | [0.431, 0.623] |
| `fillet.radius` | radius | 4 | 1.472 | 0.6040 | [-0.180, 3.123] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.48489 | 0.17698 | 3.70371 | 5.1 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.07583 | 0.00229 | 0.07960 | 3.0 % | 821 | 158368 | +0 | 14.3 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 14.58801 | 0.56526 | 15.24325 | 3.9 % | 148205 | 28566976 | +0 | 14.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.67266 | 0.00860 | 0.68964 | 1.3 % | 6209 | 596032 | +0 | 14.5 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 9.53768 | 0.19184 | 9.77467 | 2.0 % | 84071 | 225974848 | -12160 | 22.8 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08426 | 0.00810 | 0.10247 | 9.6 % | 375 | 59360 | +0 | 22.8 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05357 | 0.00086 | 0.05544 | 1.6 % | 63 | 80640 | +0 | 22.8 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 3.94965 | 0.07013 | 4.08792 | 1.8 % | 34056 | 13154158 | +0 | 22.9 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 42.04059 | 0.46580 | 42.56871 | 1.1 % | 270413 | 66623627 | +0 | 28.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 38.22896 | 1.83704 | 40.26196 | 4.8 % | 242881 | 59651061 | +0 | 28.9 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.23394 | 0.05233 | 0.34290 | 22.4 % | 1976 | 308336 | +0 | 28.9 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 24.58959 | 1.46493 | 26.36704 | 6.0 % | 211425 | 25882480 | +0 | 30.6 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.35404 | 0.18193 | 7.75425 | 2.5 % | 67568 | 10408048 | +0 | 30.6 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.16813 | 0.00213 | 0.17254 | 1.3 % | 1601 | 269728 | +0 | 30.6 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 61.67696 | 0.47977 | 62.38417 | 0.8 % | 577205 | 97204096 | +0 | 30.6 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.33273 | 0.03204 | 1.38854 | 2.4 % | 12392 | 1160128 | +0 | 30.6 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 18.83544 | 0.26743 | 19.19104 | 1.4 % | 167561 | 446577664 | -24320 | 37.0 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16748 | 0.00704 | 0.18199 | 4.2 % | 737 | 93024 | +0 | 37.0 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.10886 | 0.00106 | 0.10990 | 1.0 % | 123 | 157440 | +0 | 37.0 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 7.99117 | 0.21085 | 8.34713 | 2.6 % | 67923 | 24575301 | +0 | 37.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 99.32954 | 6.62824 | 113.95929 | 6.7 % | 614231 | 133945410 | +0 | 40.9 |
| `cut` | edges | 360 | 360 | 7 | 1 | 87.36285 | 3.25351 | 89.58413 | 3.7 % | 560374 | 120365931 | +0 | 40.9 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.23266 | 0.00489 | 0.24052 | 2.1 % | 2096 | 392112 | +0 | 40.9 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.05438 | 0.22292 | 8.44937 | 2.8 % | 68952 | 11624128 | +0 | 41.0 |
| `build` | edges | 720 | 720 | 7 | 1 | 14.64228 | 0.18926 | 14.96571 | 1.3 % | 134894 | 20360432 | +0 | 41.0 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.33060 | 0.01757 | 0.36811 | 5.3 % | 3161 | 492448 | +0 | 41.0 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 240.18342 | 5.88613 | 251.64900 | 2.5 % | 2277605 | 354747136 | +0 | 41.0 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.77364 | 0.12081 | 3.02479 | 4.4 % | 24753 | 2255552 | +0 | 41.1 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 38.94130 | 0.97832 | 41.05517 | 2.5 % | 334258 | 888838496 | -48640 | 53.5 |
| `counts` | edges | 720 | 720 | 7 | 4 | 0.31082 | 0.00370 | 0.31868 | 1.2 % | 1457 | 127584 | +0 | 53.5 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.21579 | 0.00330 | 0.22062 | 1.5 % | 243 | 311040 | +0 | 53.5 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.10099 | 0.47017 | 16.90400 | 2.9 % | 135627 | 48367506 | +0 | 53.5 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 259.19954 | 18.94417 | 296.00692 | 7.3 % | 1539729 | 274703847 | +0 | 61.9 |
| `cut` | edges | 720 | 720 | 7 | 1 | 225.35537 | 7.93546 | 238.59025 | 3.5 % | 1432862 | 247759376 | +0 | 61.9 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.27390 | 0.00623 | 0.28769 | 2.3 % | 2336 | 559664 | +0 | 61.9 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 14.83545 | 0.88459 | 15.95875 | 6.0 % | 134712 | 22247488 | +0 | 61.9 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 30.55065 | 1.05137 | 31.73050 | 3.4 % | 269554 | 40496624 | +0 | 61.9 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.67085 | 0.01720 | 0.69788 | 2.6 % | 6285 | 1003424 | +0 | 61.9 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 994.92415 | 19.08551 | 1026.43392 | 1.9 % | 9053767 | 1445313024 | +0 | 61.9 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 5.83017 | 0.19619 | 6.23667 | 3.4 % | 49478 | 4511936 | +0 | 62.0 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 92.98586 | 18.61777 | 134.65187 | 20.0 % | 668060 | 1775223216 | -97280 | 87.5 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.71464 | 0.02097 | 0.75761 | 2.9 % | 2899 | 229472 | +0 | 87.5 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.48096 | 0.03297 | 0.55324 | 6.9 % | 483 | 618240 | +0 | 87.5 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 32.75387 | 0.86761 | 34.21550 | 2.6 % | 271030 | 96173390 | +0 | 87.5 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 679.19596 | 23.55095 | 725.67958 | 3.5 % | 4342705 | 590682014 | +0 | 103.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 679.06319 | 30.62720 | 738.28800 | 4.5 % | 4130469 | 536945607 | +0 | 103.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.39051 | 0.00691 | 0.40391 | 1.8 % | 2816 | 894768 | +0 | 103.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 30.76456 | 1.07394 | 31.93929 | 3.5 % | 266270 | 44116800 | +0 | 103.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.33431 | 0.10871 | 2.54708 | 4.7 % | 25307 | 4253072 | +0 | 103.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.53180 | 0.00769 | 0.53815 | 1.4 % | 4013 | 309760 | +0 | 103.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.58612 | 0.01539 | 3.61404 | 0.4 % | 29913 | 5127328 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.04058 | 0.67817 | 11.78029 | 6.1 % | 92919 | 11590416 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 23.67638 | 0.31962 | 24.13271 | 1.3 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 52.06251 | 1.87910 | 54.64129 | 3.6 % | 486810 | 49139568 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.04783 | 0.24494 | 14.42008 | 1.7 % | 118226 | 15843488 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 26.35723 | 0.22215 | 26.64463 | 0.8 % | 227679 | 26897216 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 52.45899 | 1.10562 | 54.01196 | 2.1 % | 512117 | 53392640 | +0 | 103.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 22.69899 | 0.70526 | 23.82717 | 3.1 % | 202345 | 22639152 | +0 | 103.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 21.45697 | 1.27352 | 23.62792 | 5.9 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 23.10284 | 0.90228 | 24.54225 | 3.9 % | 202370 | 22640112 | +0 | 103.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 663.81511 | 15.15651 | 679.65167 | 2.3 % | 3554373 | 535954400 | +0 | 103.6 |

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
