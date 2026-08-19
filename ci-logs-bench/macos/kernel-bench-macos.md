# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T17:34:23Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.193 | [0.979, 1.408] | 0.9835 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.143 | [2.098, 2.189] | 0.9998 | yes | **AGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.194 | [0.972, 1.417] | 0.9823 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.163 | 0.9551 | [0.814, 1.513] |
| `edgeInfo1` | edges | 4 | 1.193 | 0.9835 | [0.979, 1.408] |
| `allEdges` | edges | 4 | 2.143 | 0.9998 | [2.098, 2.189] |
| `allEdgesBulk` | edges | 4 | 1.982 | 0.9981 | [1.862, 2.102] |
| `buildOnly` | edges | 4 | 1.194 | 0.9823 | [0.972, 1.417] |
| `counts` | edges | 4 | 1.105 | 0.9912 | [0.960, 1.249] |
| `bbox` | edges | 4 | 1.015 | 0.9939 | [0.905, 1.125] |
| `mesh` | edges | 4 | 1.187 | 0.9901 | [1.022, 1.351] |
| `fuse` | edges | 4 | 1.343 | 0.9983 | [1.266, 1.420] |
| `cut` | edges | 4 | 1.560 | 0.9915 | [1.360, 1.760] |
| `rayHits` | edges | 4 | 0.227 | 0.4294 | [-0.135, 0.589] |
| `filletEx1` | edges | 4 | 0.424 | 0.2210 | [-0.680, 1.529] |
| `fillet.edges` | edgesBlended | 3 | 0.613 | 0.9991 | [0.578, 0.649] |
| `fillet.scenario` | edgesBlended | 3 | 0.232 | 0.9076 | [0.087, 0.377] |
| `fillet.radius` | radius | 4 | 1.332 | 0.5454 | [-0.354, 3.018] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.59117 | 0.73315 | 5.72404 | 16.0 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 1 | 1.72131 | 0.21804 | 2.18875 | 12.7 % | 14153 | 2130000 | +0 | 15.0 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 367.79334 | 22.35203 | 408.45833 | 6.1 % | 2838089 | 406026976 | +0 | 15.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.71816 | 1.21991 | 24.33742 | 5.4 % | 184680 | 30723440 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.61717 | 0.63611 | 11.48379 | 6.0 % | 84071 | 225974848 | -12160 | 23.2 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08382 | 0.00336 | 0.09025 | 4.0 % | 375 | 59360 | +0 | 23.2 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.06652 | 0.01724 | 0.10175 | 25.9 % | 63 | 80640 | +0 | 23.2 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.95620 | 0.61130 | 6.22021 | 12.3 % | 34056 | 13154158 | +0 | 23.4 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 52.76729 | 6.21988 | 61.37571 | 11.8 % | 270339 | 66611888 | +0 | 28.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 41.36367 | 3.78234 | 47.72121 | 9.1 % | 242920 | 59655486 | +0 | 28.9 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.37113 | 0.19273 | 0.62090 | 51.9 % | 1976 | 308336 | +0 | 28.9 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 31.48852 | 4.44190 | 40.11383 | 14.1 % | 211425 | 25882480 | +0 | 30.7 |
| `build` | edges | 360 | 360 | 7 | 1 | 9.18156 | 0.99274 | 10.32225 | 10.8 % | 67568 | 10408048 | +0 | 30.7 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.78208 | 0.11329 | 3.96008 | 3.0 % | 27715 | 4078672 | +0 | 30.7 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1522.59168 | 83.21257 | 1644.98504 | 5.5 % | 11116716 | 1558379984 | +0 | 30.7 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 95.51695 | 12.11404 | 109.19662 | 12.7 % | 633718 | 101960880 | +0 | 30.7 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.18365 | 1.95983 | 24.41400 | 9.3 % | 167561 | 446577664 | -24320 | 37.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.22318 | 0.04479 | 0.29240 | 20.1 % | 737 | 93024 | +0 | 37.1 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.15539 | 0.04709 | 0.25529 | 30.3 % | 123 | 157440 | +0 | 37.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 9.41371 | 0.54399 | 10.06371 | 5.8 % | 67923 | 24575301 | +0 | 37.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 122.64161 | 23.48937 | 173.91962 | 19.2 % | 614277 | 133954919 | +0 | 40.9 |
| `cut` | edges | 360 | 360 | 7 | 1 | 100.25246 | 20.19496 | 144.47346 | 20.1 % | 560304 | 120351742 | +0 | 40.9 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.26400 | 0.03180 | 0.32845 | 12.0 % | 2096 | 392112 | +0 | 40.9 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.13329 | 0.18989 | 8.38417 | 2.3 % | 68952 | 11624128 | +0 | 41.1 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.14357 | 0.20264 | 15.51137 | 1.3 % | 134894 | 20360432 | +0 | 41.1 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.00135 | 0.58946 | 8.00596 | 8.4 % | 54839 | 7992400 | +0 | 41.1 |
| `allEdges` | edges | 720 | 720 | 3 | 1 | 7136.71838 | 1041.28389 | 8009.69908 | 14.6 % | 44080847 | 6109275264 | +0 | 41.1 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 410.62279 | 28.81690 | 457.06246 | 7.0 % | 2326872 | 366271424 | +0 | 41.1 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 66.63353 | 9.08267 | 80.89625 | 13.6 % | 334258 | 888838496 | -48640 | 54.3 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.42660 | 0.16842 | 0.79311 | 39.5 % | 1457 | 127584 | +0 | 54.3 |
| `bbox` | edges | 720 | 720 | 7 | 4 | 0.30246 | 0.07444 | 0.41936 | 24.6 % | 243 | 311040 | +0 | 54.3 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 27.39813 | 2.45740 | 31.19900 | 9.0 % | 135627 | 48367506 | +0 | 54.3 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 348.86280 | 22.28687 | 368.93129 | 6.4 % | 1539777 | 274713648 | +0 | 62.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 398.89387 | 68.28102 | 535.53717 | 17.1 % | 1432913 | 247769762 | +0 | 62.8 |
| `rayHits` | edges | 720 | 720 | 7 | 2 | 0.50620 | 0.22842 | 0.88119 | 45.1 % | 2336 | 559664 | +0 | 62.8 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 28.77970 | 5.45633 | 38.21721 | 19.0 % | 134712 | 22247488 | +0 | 62.8 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 57.12882 | 8.54524 | 67.59733 | 15.0 % | 269554 | 40496624 | +0 | 62.8 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 22.08199 | 7.03775 | 31.71912 | 31.9 % | 109093 | 15971536 | +0 | 62.8 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 31100.73563 | 2419.05324 | 33450.68346 | 7.8 % | 175482141 | 24398762544 | +0 | 62.8 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1362.46886 | 151.77485 | 1596.95404 | 11.1 % | 8886779 | 1428881600 | +0 | 62.8 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 114.39490 | 9.81926 | 134.97779 | 8.6 % | 668060 | 1775223216 | -97280 | 85.7 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.86680 | 0.10725 | 0.99178 | 12.4 % | 2899 | 229472 | +0 | 85.7 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.55606 | 0.06912 | 0.70831 | 12.4 % | 483 | 618240 | +0 | 85.7 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 53.87598 | 6.16749 | 65.77129 | 11.4 % | 271030 | 96173390 | +0 | 85.7 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 829.29011 | 57.06439 | 909.21096 | 6.9 % | 4342762 | 590693717 | +0 | 102.2 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 959.65382 | 89.21467 | 1086.90846 | 9.3 % | 4130239 | 536943449 | +0 | 102.2 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 0.50424 | 0.08841 | 0.63091 | 17.5 % | 2816 | 894768 | +0 | 102.2 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 55.09257 | 19.55676 | 95.43567 | 35.5 % | 266270 | 44116800 | +0 | 102.2 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 78.94742 | 6.23695 | 87.14558 | 7.9 % | 478775 | 69176096 | +0 | 102.2 |
| `volume` | edges | 72 | 72 | 7 | 4 | 1.33060 | 0.24077 | 1.64397 | 18.1 % | 4013 | 309760 | +0 | 102.2 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.47974 | 0.93927 | 6.74146 | 17.1 % | 29913 | 5127328 | +0 | 102.2 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 14.59236 | 2.03382 | 17.10346 | 13.9 % | 92919 | 11590416 | +0 | 102.2 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 32.89611 | 7.01833 | 45.37550 | 21.3 % | 202372 | 22644144 | +0 | 102.2 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 67.18661 | 5.72082 | 76.33742 | 8.5 % | 486810 | 49139568 | +0 | 102.2 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 97.95353 | 16.54629 | 121.83779 | 16.9 % | 571694 | 80766512 | +0 | 102.2 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 115.91564 | 16.50333 | 131.32875 | 14.2 % | 681147 | 91820240 | +0 | 102.2 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 176.41480 | 19.90147 | 208.78117 | 11.3 % | 965585 | 118315664 | +0 | 102.2 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 40.24699 | 4.74918 | 45.82283 | 11.8 % | 202345 | 22639152 | +0 | 102.2 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 37.45635 | 2.19445 | 39.64650 | 5.9 % | 202372 | 22644144 | +0 | 102.2 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 32.36096 | 6.62527 | 40.97833 | 20.5 % | 202370 | 22640112 | +0 | 102.2 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 917.40696 | 77.86304 | 1035.14113 | 8.5 % | 3554373 | 535954400 | +0 | 102.2 |

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
