# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T23:14:32Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.015 | [0.703, 1.328] | 0.9531 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.027 | [1.874, 2.179] | 0.9971 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.137 | [0.967, 1.307] | 0.9885 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 0.971 | 0.8745 | [0.461, 1.481] |
| `edgeInfo1` | edges | 4 | 1.015 | 0.9531 | [0.703, 1.328] |
| `allEdges` | edges | 4 | 2.027 | 0.9971 | [1.874, 2.179] |
| `allEdgesBulk` | edges | 4 | 1.844 | 0.9974 | [1.713, 1.974] |
| `buildOnly` | edges | 4 | 1.137 | 0.9885 | [0.967, 1.307] |
| `counts` | edges | 4 | 0.953 | 0.9983 | [0.898, 1.008] |
| `bbox` | edges | 4 | 1.027 | 0.9642 | [0.753, 1.301] |
| `mesh` | edges | 4 | 1.146 | 0.9882 | [0.972, 1.320] |
| `fuse` | edges | 4 | 1.285 | 0.9824 | [1.047, 1.523] |
| `cut` | edges | 4 | 1.287 | 0.9705 | [0.976, 1.598] |
| `rayHits` | edges | 4 | 0.118 | 0.1148 | [-0.337, 0.574] |
| `filletEx1` | edges | 4 | 0.325 | 0.1440 | [-0.774, 1.425] |
| `fillet.edges` | edgesBlended | 3 | 0.697 | 0.9789 | [0.497, 0.898] |
| `fillet.scenario` | edgesBlended | 3 | 0.231 | 0.9708 | [0.152, 0.309] |
| `fillet.radius` | radius | 4 | 1.458 | 0.6256 | [-0.105, 3.021] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 6.14755 | 3.10709 | 11.44846 | 50.5 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 2.04572 | 0.36773 | 2.63427 | 18.0 % | 14153 | 2130000 | +0 | 15.1 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 384.36491 | 44.93399 | 438.57096 | 11.7 % | 2838089 | 406026976 | +0 | 15.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.73328 | 1.71968 | 26.24625 | 7.6 % | 184544 | 31080240 | +0 | 15.2 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.32522 | 0.26021 | 10.73329 | 2.5 % | 84071 | 225974848 | -12160 | 23.2 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.09064 | 0.00147 | 0.09276 | 1.6 % | 375 | 59360 | +0 | 23.2 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05553 | 0.00219 | 0.05981 | 3.9 % | 63 | 80640 | +0 | 23.2 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.46331 | 0.28224 | 5.04783 | 6.3 % | 34056 | 13154158 | +0 | 23.2 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 52.89183 | 4.50110 | 62.06592 | 8.5 % | 270371 | 66612656 | +0 | 28.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 52.98390 | 11.62497 | 70.90400 | 21.9 % | 242868 | 59648281 | +0 | 28.9 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.40136 | 0.20714 | 0.74388 | 51.6 % | 1976 | 308336 | +0 | 28.9 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 28.13895 | 7.65547 | 43.76567 | 27.2 % | 211425 | 25882480 | +0 | 30.6 |
| `build` | edges | 360 | 360 | 7 | 1 | 6.90461 | 0.65024 | 8.13487 | 9.4 % | 67568 | 10408048 | +0 | 30.6 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.35514 | 0.24550 | 3.74329 | 7.3 % | 27715 | 4078672 | +0 | 30.6 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1270.67855 | 63.80070 | 1394.40817 | 5.0 % | 11116716 | 1558379984 | +0 | 30.6 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 67.14413 | 3.21905 | 71.07962 | 4.8 % | 633459 | 102663664 | +0 | 30.6 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 17.61359 | 1.05188 | 19.23100 | 6.0 % | 167561 | 446577664 | -24320 | 37.0 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16190 | 0.00898 | 0.17051 | 5.5 % | 737 | 93024 | +0 | 37.0 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.09529 | 0.00073 | 0.09645 | 0.8 % | 123 | 157440 | +0 | 37.0 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 7.64891 | 0.43764 | 8.19896 | 5.7 % | 67923 | 24575301 | +0 | 37.0 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 90.66359 | 4.21918 | 96.22825 | 4.7 % | 614246 | 133948629 | +0 | 40.9 |
| `cut` | edges | 360 | 360 | 7 | 1 | 81.08123 | 3.36110 | 85.21179 | 4.1 % | 560318 | 120354521 | +0 | 40.9 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.23825 | 0.01329 | 0.26573 | 5.6 % | 2096 | 392112 | +0 | 40.9 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 7.11740 | 0.43917 | 7.92483 | 6.2 % | 68952 | 11624128 | +0 | 41.0 |
| `build` | edges | 720 | 720 | 7 | 1 | 13.26895 | 0.75424 | 14.94971 | 5.7 % | 134894 | 20360432 | +0 | 41.0 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 5.70252 | 0.33983 | 6.33333 | 6.0 % | 54839 | 7992400 | +0 | 41.0 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5557.25693 | 420.59480 | 6032.44154 | 7.6 % | 44080847 | 6109275264 | +0 | 41.0 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 269.75407 | 27.80536 | 309.28638 | 10.3 % | 2326372 | 367698944 | +0 | 41.0 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 46.75810 | 6.26295 | 56.54537 | 13.4 % | 334258 | 888838496 | -48640 | 54.4 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.32687 | 0.00848 | 0.33687 | 2.6 % | 1457 | 127584 | +0 | 54.4 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.28764 | 0.07917 | 0.43466 | 27.5 % | 243 | 311040 | +0 | 54.4 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 19.31093 | 3.29336 | 26.50983 | 17.1 % | 135627 | 48367506 | +0 | 54.4 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 266.64163 | 35.14209 | 337.25475 | 13.2 % | 1539761 | 274710283 | +0 | 62.8 |
| `cut` | edges | 720 | 720 | 7 | 1 | 266.72920 | 20.32777 | 294.47725 | 7.6 % | 1432916 | 247770347 | +0 | 62.8 |
| `rayHits` | edges | 720 | 720 | 7 | 4 | 0.30459 | 0.03135 | 0.35042 | 10.3 % | 2336 | 559664 | +0 | 62.8 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 19.19476 | 1.96706 | 22.62608 | 10.2 % | 134712 | 22247488 | +0 | 62.8 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 46.58820 | 18.88210 | 80.37625 | 40.5 % | 269554 | 40496624 | +0 | 62.8 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 17.89686 | 2.85315 | 22.23571 | 15.9 % | 109093 | 15971536 | +0 | 62.8 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 25411.27400 | 1398.55584 | 26566.06567 | 5.5 % | 175482141 | 24398762544 | +0 | 62.8 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1012.31874 | 74.54612 | 1143.47113 | 7.4 % | 8885798 | 1431758592 | +0 | 62.8 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 103.14087 | 2.43791 | 106.54229 | 2.4 % | 668060 | 1775223216 | -97280 | 87.5 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.64898 | 0.02763 | 0.69615 | 4.3 % | 2899 | 229472 | +0 | 87.5 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.41198 | 0.00360 | 0.41601 | 0.9 % | 483 | 618240 | +0 | 87.5 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 46.28802 | 4.81992 | 49.40158 | 10.4 % | 271030 | 96173390 | +0 | 87.5 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 718.58853 | 74.85962 | 865.05237 | 10.4 % | 4342851 | 590711856 | +0 | 103.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 696.49465 | 204.53779 | 1160.02496 | 29.4 % | 4130103 | 536936903 | +0 | 103.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.48606 | 0.19367 | 0.91702 | 39.8 % | 2816 | 894768 | +0 | 103.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 42.88316 | 6.04633 | 50.50196 | 14.1 % | 266270 | 44116800 | +0 | 103.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 70.32268 | 16.25137 | 100.61737 | 23.1 % | 478775 | 69176096 | +0 | 103.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.99779 | 0.59855 | 2.00417 | 60.0 % | 4013 | 309760 | +0 | 103.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.32329 | 0.65411 | 5.27963 | 15.1 % | 29913 | 5127328 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.99885 | 2.23543 | 15.74371 | 17.2 % | 92919 | 11590416 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 27.64910 | 3.02368 | 31.09263 | 10.9 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 74.75838 | 8.98532 | 85.43746 | 12.0 % | 486810 | 49139568 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 76.03928 | 10.00386 | 94.68721 | 13.2 % | 571694 | 80766512 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 96.39810 | 7.31135 | 108.13679 | 7.6 % | 681147 | 91820240 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 135.84528 | 32.99503 | 192.80379 | 24.3 % | 965585 | 118315664 | +0 | 103.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 29.50116 | 7.76353 | 42.62975 | 26.3 % | 202345 | 22639152 | +0 | 103.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.14972 | 2.73057 | 29.70217 | 10.4 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 33.02574 | 5.35626 | 41.19221 | 16.2 % | 202370 | 22640112 | +0 | 103.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 792.60954 | 74.57825 | 874.76733 | 9.4 % | 3554373 | 535954400 | +0 | 103.6 |

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
