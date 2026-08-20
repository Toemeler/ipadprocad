# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-20T07:14:40Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.068 | [0.951, 1.185] | 0.9938 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.002 | [1.932, 2.072] | 0.9994 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.090 | [1.034, 1.146] | 0.9986 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.221 | 0.9975 | [1.136, 1.306] |
| `edgeInfo1` | edges | 4 | 1.068 | 0.9938 | [0.951, 1.185] |
| `allEdges` | edges | 4 | 2.002 | 0.9994 | [1.932, 2.072] |
| `allEdgesBulk` | edges | 4 | 1.892 | 0.9992 | [1.819, 1.966] |
| `buildOnly` | edges | 4 | 1.090 | 0.9986 | [1.034, 1.146] |
| `counts` | edges | 4 | 1.033 | 0.9966 | [0.949, 1.117] |
| `bbox` | edges | 4 | 1.033 | 0.9686 | [0.775, 1.291] |
| `mesh` | edges | 4 | 1.235 | 0.9954 | [1.119, 1.351] |
| `fuse` | edges | 4 | 1.395 | 1.0000 | [1.383, 1.406] |
| `cut` | edges | 4 | 1.394 | 0.9998 | [1.365, 1.423] |
| `rayHits` | edges | 4 | 0.437 | 0.9608 | [0.315, 0.560] |
| `filletEx1` | edges | 4 | 0.211 | 0.1332 | [-0.535, 0.956] |
| `fillet.edges` | edgesBlended | 3 | 0.641 | 0.9891 | [0.509, 0.773] |
| `fillet.scenario` | edgesBlended | 3 | 0.180 | 0.9433 | [0.093, 0.266] |
| `fillet.radius` | radius | 4 | 1.449 | 0.5949 | [-0.208, 3.106] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.74406 | 0.23556 | 4.11058 | 6.3 % | 33890 | 5335600 | +0 | 14.3 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.52854 | 0.05533 | 1.64523 | 3.6 % | 14153 | 2130000 | +0 | 15.1 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 363.11578 | 36.94335 | 424.29808 | 10.2 % | 2838089 | 406026976 | +0 | 15.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 20.55983 | 0.24189 | 20.92692 | 1.2 % | 184544 | 31080240 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.20711 | 0.54924 | 11.38246 | 5.4 % | 84071 | 225974848 | -12160 | 23.2 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08543 | 0.00393 | 0.09103 | 4.6 % | 375 | 59360 | +0 | 23.2 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.05609 | 0.00244 | 0.06079 | 4.3 % | 63 | 80640 | +0 | 23.2 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.03586 | 0.10341 | 4.23583 | 2.6 % | 34056 | 13154158 | +0 | 23.3 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 43.53140 | 1.60840 | 45.01167 | 3.7 % | 270371 | 66617118 | +0 | 28.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 40.57807 | 0.29444 | 41.00413 | 0.7 % | 242857 | 59646087 | +0 | 28.8 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.22151 | 0.00948 | 0.23546 | 4.3 % | 1976 | 308336 | +0 | 28.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 26.84721 | 0.53401 | 27.59562 | 2.0 % | 211425 | 25882480 | +0 | 30.4 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.68895 | 0.25333 | 8.11192 | 3.3 % | 67568 | 10408048 | +0 | 30.5 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.20315 | 0.23124 | 3.60983 | 7.2 % | 27715 | 4078672 | +0 | 30.5 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1527.45610 | 177.42158 | 1752.44896 | 11.6 % | 11116716 | 1558379984 | +0 | 30.5 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 84.27645 | 13.17970 | 105.75142 | 15.6 % | 633459 | 102663664 | +0 | 30.5 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 23.11137 | 5.90708 | 32.49908 | 25.6 % | 167561 | 446577664 | -24320 | 37.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16807 | 0.01449 | 0.19800 | 8.6 % | 737 | 93024 | +0 | 37.1 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.12823 | 0.00665 | 0.13989 | 5.2 % | 123 | 157440 | +0 | 37.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 7.98230 | 0.43963 | 8.76579 | 5.5 % | 67923 | 24575301 | +0 | 37.3 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 116.32453 | 20.68714 | 160.58471 | 17.8 % | 614250 | 133949360 | +0 | 41.0 |
| `cut` | edges | 360 | 360 | 7 | 1 | 111.30418 | 13.36849 | 131.63763 | 12.0 % | 560384 | 120367979 | +0 | 41.0 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.25148 | 0.00848 | 0.26268 | 3.4 % | 2096 | 392112 | +0 | 41.0 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 10.24595 | 1.33683 | 11.95800 | 13.0 % | 68952 | 11624128 | +0 | 41.2 |
| `build` | edges | 720 | 720 | 7 | 1 | 19.58757 | 4.38861 | 27.91525 | 22.4 % | 134894 | 20360432 | +0 | 41.2 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.65322 | 1.61652 | 10.53371 | 21.1 % | 54839 | 7992400 | +0 | 41.2 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 6343.79565 | 403.23508 | 6617.37308 | 6.4 % | 44080847 | 6109275264 | +0 | 41.2 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 303.38276 | 41.12972 | 386.18496 | 13.6 % | 2326372 | 367698944 | +0 | 41.2 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 45.27639 | 4.07649 | 51.46042 | 9.0 % | 334258 | 888838496 | -48640 | 53.6 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.38610 | 0.03227 | 0.44799 | 8.4 % | 1457 | 127584 | +0 | 53.6 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.32126 | 0.07762 | 0.42348 | 24.2 % | 243 | 311040 | +0 | 53.6 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 21.24096 | 2.90014 | 26.89679 | 13.7 % | 135627 | 48367506 | +0 | 54.4 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 303.34863 | 39.69102 | 356.58038 | 13.1 % | 1539820 | 274722425 | +0 | 62.8 |
| `cut` | edges | 720 | 720 | 7 | 1 | 283.02262 | 46.60825 | 343.53883 | 16.5 % | 1432921 | 247771518 | +0 | 62.8 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.36833 | 0.06718 | 0.50408 | 18.2 % | 2336 | 559664 | +0 | 62.8 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 22.34992 | 2.69558 | 26.19796 | 12.1 % | 134712 | 22247488 | +0 | 62.8 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 46.04651 | 6.95064 | 58.28454 | 15.1 % | 269554 | 40496624 | +0 | 62.8 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 13.47239 | 0.54634 | 14.31338 | 4.1 % | 109093 | 15971536 | +0 | 62.8 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 23036.10626 | 1275.37113 | 24356.77117 | 5.5 % | 175482141 | 24398762544 | +0 | 62.8 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1062.82667 | 110.61128 | 1238.82392 | 10.4 % | 8885798 | 1431758592 | +0 | 62.8 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 101.23980 | 6.53967 | 111.42363 | 6.5 % | 668060 | 1775223216 | -97280 | 87.6 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.70456 | 0.06892 | 0.79435 | 9.8 % | 2899 | 229472 | +0 | 87.6 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.44941 | 0.06126 | 0.58443 | 13.6 % | 483 | 618240 | +0 | 87.6 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 50.51579 | 6.39240 | 56.88054 | 12.7 % | 271030 | 96173390 | +0 | 87.6 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 793.17214 | 55.55306 | 847.48812 | 7.0 % | 4342949 | 590710649 | +0 | 104.1 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 744.54074 | 60.31566 | 847.30433 | 8.1 % | 4130125 | 536941291 | +0 | 104.1 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.53572 | 0.14073 | 0.77645 | 26.3 % | 2816 | 894768 | +0 | 104.1 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 33.69395 | 3.64538 | 41.89317 | 10.8 % | 266270 | 44116800 | +0 | 104.1 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 61.90679 | 7.56942 | 73.94929 | 12.2 % | 478775 | 69176096 | +0 | 104.1 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.64031 | 0.02753 | 0.68983 | 4.3 % | 4013 | 309760 | +0 | 104.1 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.01055 | 1.25157 | 7.68758 | 25.0 % | 29913 | 5127328 | +0 | 104.1 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.29283 | 0.50578 | 12.32854 | 4.5 % | 92919 | 11590416 | +0 | 104.1 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 23.88060 | 1.17934 | 25.69288 | 4.9 % | 202372 | 22644144 | +0 | 104.1 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 56.11320 | 4.62180 | 65.56904 | 8.2 % | 486810 | 49139568 | +0 | 104.1 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 72.77124 | 7.04199 | 79.75213 | 9.7 % | 571694 | 80766512 | +0 | 104.1 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 85.24311 | 7.41888 | 101.48242 | 8.7 % | 681147 | 91820240 | +0 | 104.1 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 114.62867 | 5.84315 | 120.84325 | 5.1 % | 965585 | 118315664 | +0 | 104.1 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 23.22877 | 0.71031 | 24.69400 | 3.1 % | 202345 | 22639152 | +0 | 104.1 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 23.18536 | 0.82869 | 24.53412 | 3.6 % | 202372 | 22644144 | +0 | 104.1 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 22.73992 | 0.24132 | 23.10746 | 1.1 % | 202370 | 22640112 | +0 | 104.1 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 664.87321 | 21.06939 | 701.79725 | 3.2 % | 3554373 | 535954400 | +0 | 104.1 |

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
