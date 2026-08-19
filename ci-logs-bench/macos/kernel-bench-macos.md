# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T19:08:49Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.914 | [0.739, 1.088] | 0.9814 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.936 | [1.891, 1.982] | 0.9997 | yes | **AGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.096 | [1.016, 1.176] | 0.9972 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.012 | 0.9809 | [0.816, 1.207] |
| `edgeInfo1` | edges | 4 | 0.914 | 0.9814 | [0.739, 1.088] |
| `allEdges` | edges | 4 | 1.936 | 0.9997 | [1.891, 1.982] |
| `allEdgesBulk` | edges | 4 | 1.975 | 0.9978 | [1.848, 2.102] |
| `buildOnly` | edges | 4 | 1.096 | 0.9972 | [1.016, 1.176] |
| `counts` | edges | 4 | 1.042 | 0.9979 | [0.975, 1.109] |
| `bbox` | edges | 4 | 1.066 | 0.9480 | [0.720, 1.412] |
| `mesh` | edges | 4 | 1.024 | 0.9963 | [0.937, 1.110] |
| `fuse` | edges | 4 | 1.414 | 0.9913 | [1.231, 1.598] |
| `cut` | edges | 4 | 1.310 | 0.9950 | [1.181, 1.439] |
| `rayHits` | edges | 4 | 0.566 | 0.5190 | [-0.189, 1.320] |
| `filletEx1` | edges | 4 | 0.178 | 0.0503 | [-0.894, 1.250] |
| `fillet.edges` | edgesBlended | 3 | 0.697 | 0.9765 | [0.485, 0.909] |
| `fillet.scenario` | edgesBlended | 3 | 0.099 | 0.5247 | [-0.086, 0.284] |
| `fillet.radius` | radius | 4 | 1.559 | 0.6559 | [-0.006, 3.124] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.30519 | 0.66283 | 5.75383 | 15.4 % | 33890 | 5335600 | +0 | 14.3 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 2.04620 | 0.80340 | 3.85117 | 39.3 % | 14153 | 2130000 | +0 | 15.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 479.44502 | 40.74469 | 533.64525 | 8.5 % | 2838089 | 406026976 | +0 | 15.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 25.99023 | 3.34235 | 28.90642 | 12.9 % | 184544 | 31080240 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 14.46672 | 2.31492 | 17.17229 | 16.0 % | 84071 | 225974848 | -12160 | 23.2 |
| `counts` | edges | 180 | 180 | 7 | 16 | 0.10576 | 0.04136 | 0.19083 | 39.1 % | 375 | 59360 | +0 | 23.2 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.07446 | 0.02907 | 0.12290 | 39.0 % | 63 | 80640 | +0 | 23.2 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 6.70604 | 1.29093 | 8.28008 | 19.3 % | 34056 | 13154158 | +0 | 23.3 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 56.76112 | 6.83741 | 68.54504 | 12.0 % | 270391 | 66619586 | +0 | 28.9 |
| `cut` | edges | 180 | 180 | 7 | 1 | 53.85102 | 6.45350 | 64.63379 | 12.0 % | 242912 | 59657351 | +0 | 29.0 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.35305 | 0.12263 | 0.55121 | 34.7 % | 1976 | 308336 | +0 | 29.0 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 46.29220 | 29.88348 | 111.45296 | 64.6 % | 211425 | 25882480 | +0 | 30.7 |
| `build` | edges | 360 | 360 | 7 | 1 | 11.42640 | 6.92655 | 26.09942 | 60.6 % | 67568 | 10408048 | +0 | 30.7 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.88216 | 0.92986 | 5.69821 | 24.0 % | 27715 | 4078672 | +0 | 30.7 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1844.67881 | 97.20267 | 2002.34108 | 5.3 % | 11116716 | 1558379984 | +0 | 30.7 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 100.47446 | 12.53535 | 121.25504 | 12.5 % | 633459 | 102663664 | +0 | 30.7 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 32.82810 | 3.52933 | 36.87604 | 10.8 % | 167561 | 446577664 | -24320 | 37.3 |
| `counts` | edges | 360 | 360 | 7 | 8 | 0.23829 | 0.08809 | 0.42910 | 37.0 % | 737 | 93024 | +0 | 37.3 |
| `bbox` | edges | 360 | 360 | 7 | 8 | 0.18490 | 0.05495 | 0.24831 | 29.7 % | 123 | 157440 | +0 | 37.3 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 12.13261 | 1.18908 | 13.22033 | 9.8 % | 67923 | 24575301 | +0 | 37.3 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 118.15076 | 9.90448 | 138.66775 | 8.4 % | 614265 | 133952432 | +0 | 41.2 |
| `cut` | edges | 360 | 360 | 7 | 1 | 115.97414 | 12.60176 | 133.96363 | 10.9 % | 560304 | 120351595 | +0 | 41.2 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.28814 | 0.05110 | 0.39240 | 17.7 % | 2096 | 392112 | +0 | 41.2 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 12.53032 | 1.43637 | 14.47392 | 11.5 % | 68952 | 11624128 | +0 | 41.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 17.77083 | 2.95009 | 23.93104 | 16.6 % | 134894 | 20360432 | +0 | 41.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 8.84558 | 2.70203 | 13.69875 | 30.5 % | 54839 | 7992400 | +0 | 41.4 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 6689.22874 | 494.94871 | 7119.70921 | 7.4 % | 44080847 | 6109275264 | +0 | 41.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 346.58724 | 20.76877 | 375.93846 | 6.0 % | 2326372 | 367698944 | +0 | 41.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 62.41330 | 10.46653 | 76.03600 | 16.8 % | 334258 | 888838496 | -48640 | 53.9 |
| `counts` | edges | 720 | 720 | 7 | 4 | 0.44693 | 0.18290 | 0.84215 | 40.9 % | 1457 | 127584 | +0 | 53.9 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.23975 | 0.02178 | 0.27269 | 9.1 % | 243 | 311040 | +0 | 53.9 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 25.57221 | 3.04326 | 28.96617 | 11.9 % | 135627 | 48367506 | +0 | 53.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 339.20608 | 19.03753 | 374.60083 | 5.6 % | 1539758 | 274709845 | +0 | 62.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 286.09599 | 27.10008 | 328.72946 | 9.5 % | 1432865 | 247759961 | +0 | 62.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.30928 | 0.04587 | 0.41241 | 14.8 % | 2336 | 559664 | +0 | 62.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 21.23862 | 3.18827 | 28.05796 | 15.0 % | 134712 | 22247488 | +0 | 62.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 38.46399 | 5.72888 | 47.22637 | 14.9 % | 269554 | 40496624 | +0 | 62.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 12.84104 | 0.32342 | 13.37142 | 2.5 % | 109093 | 15971536 | +0 | 62.2 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 27369.36164 | 1921.41275 | 29408.97021 | 7.0 % | 175482141 | 24398762544 | +0 | 62.2 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1648.67537 | 270.56437 | 2071.85596 | 16.4 % | 8885798 | 1431758592 | +0 | 62.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 146.97854 | 22.67062 | 187.11642 | 15.4 % | 668060 | 1775223216 | -97280 | 87.5 |
| `counts` | edges | 1440 | 1440 | 7 | 2 | 0.95326 | 0.27150 | 1.37013 | 28.5 % | 2899 | 229472 | +0 | 87.5 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.80157 | 0.26341 | 1.10535 | 32.9 % | 483 | 618240 | +0 | 87.5 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 55.69526 | 6.05423 | 66.18675 | 10.9 % | 271030 | 96173390 | +0 | 87.5 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1048.79170 | 62.69851 | 1134.05263 | 6.0 % | 4342852 | 590712002 | +0 | 103.9 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 822.42004 | 108.57188 | 1059.93775 | 13.2 % | 4130086 | 536933392 | +0 | 103.9 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 1.27400 | 0.37089 | 1.71882 | 29.1 % | 2816 | 894768 | +0 | 103.9 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 58.57812 | 7.79644 | 71.22888 | 13.3 % | 266270 | 44116800 | +0 | 103.9 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 70.01061 | 15.08038 | 95.65600 | 21.5 % | 478775 | 69176096 | +0 | 103.9 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.63232 | 0.05500 | 0.74800 | 8.7 % | 4013 | 309760 | +0 | 103.9 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.22785 | 0.33637 | 4.65133 | 8.0 % | 29913 | 5127328 | +0 | 103.9 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.61898 | 2.38841 | 17.88250 | 17.5 % | 92919 | 11590416 | +0 | 103.9 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 28.63130 | 2.71318 | 31.62008 | 9.5 % | 202372 | 22644144 | +0 | 103.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 78.42190 | 18.19188 | 117.97271 | 23.2 % | 486810 | 49139568 | +0 | 103.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 99.22446 | 14.05608 | 123.52858 | 14.2 % | 571694 | 80766512 | +0 | 103.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 93.65714 | 15.15244 | 120.21392 | 16.2 % | 681147 | 91820240 | +0 | 103.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 128.91511 | 12.37026 | 142.41417 | 9.6 % | 965585 | 118315664 | +0 | 103.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.44987 | 1.15201 | 27.75225 | 4.5 % | 202345 | 22639152 | +0 | 103.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 29.80340 | 4.98266 | 38.42383 | 16.7 % | 202372 | 22644144 | +0 | 103.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 32.48797 | 5.45757 | 40.89650 | 16.8 % | 202370 | 22640112 | +0 | 103.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 906.81676 | 103.09061 | 1097.21800 | 11.4 % | 3554373 | 535954400 | +0 | 103.9 |

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
