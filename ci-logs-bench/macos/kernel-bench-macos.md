# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T15:34:47Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v20 (OCCT 7.9.3) (shim v20) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.080 | [1.039, 1.120] | 0.9993 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.113 | [1.979, 2.247] | 0.9979 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.145 | [0.579, 1.712] | 0.8870 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.063 | 0.9960 | [0.970, 1.157] |
| `edgeInfo1` | edges | 4 | 1.080 | 0.9993 | [1.039, 1.120] |
| `allEdges` | edges | 4 | 2.113 | 0.9979 | [1.979, 2.247] |
| `buildOnly` | edges | 4 | 1.145 | 0.8870 | [0.579, 1.712] |
| `counts` | edges | 4 | 1.288 | 0.9516 | [0.885, 1.691] |
| `bbox` | edges | 4 | 1.240 | 0.9647 | [0.911, 1.569] |
| `mesh` | edges | 4 | 1.292 | 0.9874 | [1.090, 1.494] |
| `fuse` | edges | 4 | 1.577 | 0.9715 | [1.203, 1.951] |
| `cut` | edges | 4 | 1.517 | 0.9929 | [1.339, 1.694] |
| `rayHits` | edges | 4 | 0.313 | 0.9492 | [0.212, 0.413] |
| `filletEx1` | edges | 4 | 0.055 | 0.0052 | [-1.002, 1.112] |
| `fillet.edges` | edgesBlended | 3 | 0.715 | 0.9559 | [0.414, 1.016] |
| `fillet.scenario` | edgesBlended | 3 | 0.214 | 0.9278 | [0.097, 0.332] |
| `fillet.radius` | radius | 4 | 1.367 | 0.5896 | [-0.214, 2.947] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.22561 | 0.10277 | 3.44429 | 3.2 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.38877 | 0.03537 | 1.45821 | 2.5 % | 14152 | 2129552 | +0 | 15.0 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 321.09117 | 20.25438 | 359.96854 | 6.3 % | 2837909 | 405946336 | +0 | 15.2 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 14.28085 | 10.66986 | 38.36517 | 74.7 % | 84071 | 225974848 | -12160 | 22.8 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08099 | 0.00856 | 0.10039 | 10.6 % | 375 | 59360 | +0 | 22.8 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05427 | 0.00368 | 0.06257 | 6.8 % | 63 | 80640 | +0 | 22.8 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 3.97676 | 0.27834 | 4.58225 | 7.0 % | 34056 | 13154158 | +0 | 22.9 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 42.90934 | 2.22039 | 45.14204 | 5.2 % | 270332 | 66606951 | +0 | 28.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 34.35773 | 0.58387 | 35.65471 | 1.7 % | 242911 | 59657058 | +0 | 28.5 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.19909 | 0.01363 | 0.22224 | 6.8 % | 1976 | 308336 | +0 | 28.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 33.62318 | 11.29015 | 53.16558 | 33.6 % | 211425 | 25882480 | +0 | 30.2 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.57902 | 0.41159 | 7.95146 | 5.4 % | 67568 | 10408048 | +0 | 30.2 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.11504 | 0.10104 | 3.30446 | 3.2 % | 27714 | 4078224 | +0 | 30.2 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1284.82064 | 76.09264 | 1389.24758 | 5.9 % | 11116356 | 1558218704 | +0 | 30.2 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 17.37520 | 0.84594 | 19.01096 | 4.9 % | 167561 | 446577664 | -24320 | 36.7 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15254 | 0.01057 | 0.17101 | 6.9 % | 737 | 93024 | +0 | 36.7 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.10085 | 0.00412 | 0.10612 | 4.1 % | 123 | 157440 | +0 | 36.7 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 7.30430 | 0.17899 | 7.49062 | 2.5 % | 67923 | 24575301 | +0 | 36.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 91.02259 | 3.53315 | 96.37667 | 3.9 % | 614273 | 133954041 | +0 | 40.6 |
| `cut` | edges | 360 | 360 | 7 | 1 | 85.47990 | 4.24824 | 90.11625 | 5.0 % | 560405 | 120372368 | +0 | 40.6 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.23625 | 0.00673 | 0.24490 | 2.8 % | 2096 | 392112 | +0 | 40.6 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 7.92493 | 0.17891 | 8.31242 | 2.3 % | 68952 | 11624128 | +0 | 40.8 |
| `build` | edges | 720 | 720 | 7 | 1 | 13.83362 | 1.33694 | 16.77038 | 9.7 % | 134894 | 20360432 | +0 | 40.8 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.27805 | 0.07599 | 6.39117 | 1.2 % | 54838 | 7991952 | +0 | 40.8 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5099.84783 | 135.16378 | 5284.86146 | 2.7 % | 44080127 | 6108952704 | +0 | 40.8 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 36.48819 | 2.18927 | 38.91375 | 6.0 % | 334258 | 888838496 | -48640 | 53.5 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.29498 | 0.00294 | 0.29901 | 1.0 % | 1457 | 127584 | +0 | 53.5 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.20276 | 0.01052 | 0.21806 | 5.2 % | 243 | 311040 | +0 | 53.5 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 20.14873 | 10.93053 | 44.92162 | 54.2 % | 135627 | 48367506 | +0 | 53.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 244.41772 | 12.67606 | 269.16746 | 5.2 % | 1539822 | 274722864 | +0 | 62.0 |
| `cut` | edges | 720 | 720 | 7 | 1 | 226.66083 | 15.45890 | 244.36317 | 6.8 % | 1432893 | 247765666 | +0 | 62.0 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.27185 | 0.00404 | 0.27699 | 1.5 % | 2336 | 559664 | +0 | 62.0 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 14.57256 | 0.19913 | 15.01892 | 1.4 % | 134712 | 22247488 | +0 | 62.0 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 30.79958 | 0.25069 | 31.20396 | 0.8 % | 269554 | 40496624 | +0 | 62.0 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 13.31807 | 0.88893 | 14.78058 | 6.7 % | 109092 | 15971088 | +0 | 62.0 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 26755.53312 | 5373.77805 | 32208.26958 | 20.1 % | 175480701 | 24398117424 | +0 | 62.0 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 157.21927 | 14.57472 | 179.18300 | 9.3 % | 668060 | 1775223216 | -97280 | 87.0 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 1.27552 | 0.46862 | 2.01031 | 36.7 % | 2899 | 229472 | +0 | 87.0 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.75525 | 0.18370 | 1.09888 | 24.3 % | 483 | 618240 | +0 | 87.0 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 56.06938 | 2.95380 | 60.76900 | 5.3 % | 271030 | 96173390 | +0 | 87.0 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1179.50685 | 126.66310 | 1357.97704 | 10.7 % | 4342869 | 590715513 | +0 | 102.8 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 825.43304 | 55.31279 | 893.36425 | 6.7 % | 4130099 | 536936025 | +0 | 102.8 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.39129 | 0.01027 | 0.41104 | 2.6 % | 2816 | 894768 | +0 | 102.8 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 31.17250 | 1.37135 | 32.90133 | 4.4 % | 266270 | 44116800 | +0 | 102.8 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 57.51011 | 3.66140 | 61.97154 | 6.4 % | 478703 | 69143840 | +0 | 102.8 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.68990 | 0.71404 | 12.82742 | 6.1 % | 92919 | 11590416 | +0 | 102.8 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 22.92301 | 0.43264 | 23.31138 | 1.9 % | 202372 | 22644144 | +0 | 102.8 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 70.87472 | 19.98267 | 98.84929 | 28.2 % | 486810 | 49139568 | +0 | 102.8 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 88.92404 | 15.11794 | 111.66729 | 17.0 % | 571622 | 80734256 | +0 | 102.8 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 105.76598 | 19.24171 | 131.92033 | 18.2 % | 681075 | 91787984 | +0 | 102.8 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 152.99749 | 19.31656 | 179.09996 | 12.6 % | 965513 | 118283408 | +0 | 102.8 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 28.98485 | 6.89556 | 39.07329 | 23.8 % | 202345 | 22639152 | +0 | 102.8 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.59052 | 2.35913 | 29.37063 | 9.2 % | 202372 | 22644144 | +0 | 102.8 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.87114 | 4.33182 | 35.53650 | 15.5 % | 202370 | 22640112 | +0 | 102.8 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 662.69033 | 56.54347 | 780.43733 | 8.5 % | 3554373 | 535954400 | +0 | 102.8 |

### Notes

- `build` (x=180): occt_extrude_profile_arcs — the fixture itself
- `edgeInfo1` (x=180): one occt_shape_edge_info, index 1, against a growing shape
- `allEdges` (x=180): per-edge enumeration — the quadratic
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
- `buildOnly` (x=1440): CONTROL: build + counts + full mesh, never enumerated
- `counts` (x=1440): control: touching the shape is cheap
- `bbox` (x=1440): control: touching the shape is cheap
- `mesh` (x=1440): occt_mesh_create at the app's linDeflection 0.2 / ang 0.35
- `fuse` (x=1440): occt_fuse of two ring prisms at this rung's complexity
- `cut` (x=1440): occt_cut of the same pair
- `rayHits` (x=1440): one ray through the solid — the 3D pick path
- `filletEx1` (x=1440): occt_fillet_edges_ex, ONE vertical corner edge, at a radius fixed independently of the ladder
- `filletCandidateSearch` (x=72): enumerate every filletable edge — what a UI does before it can offer a blend set
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
