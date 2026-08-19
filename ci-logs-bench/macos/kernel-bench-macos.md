# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T09:34:36Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v20 (OCCT 7.9.3) (shim v20) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.989 | [0.889, 1.090] | 0.9947 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.975 | [1.930, 2.021] | 0.9997 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.982 | [0.906, 1.058] | 0.9969 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.040 | 0.9996 | [1.013, 1.068] |
| `edgeInfo1` | edges | 4 | 0.989 | 0.9947 | [0.889, 1.090] |
| `allEdges` | edges | 4 | 1.975 | 0.9997 | [1.930, 2.021] |
| `buildOnly` | edges | 4 | 0.982 | 0.9969 | [0.906, 1.058] |
| `counts` | edges | 4 | 0.976 | 0.9987 | [0.927, 1.026] |
| `bbox` | edges | 4 | 0.926 | 0.9971 | [0.857, 0.996] |
| `mesh` | edges | 4 | 1.059 | 0.9979 | [0.991, 1.126] |
| `fuse` | edges | 4 | 1.289 | 0.9940 | [1.150, 1.429] |
| `cut` | edges | 4 | 1.352 | 0.9998 | [1.325, 1.380] |
| `rayHits` | edges | 4 | 0.307 | 0.9972 | [0.285, 0.330] |
| `filletEx1` | edges | 4 | 0.178 | 0.0684 | [-0.732, 1.087] |
| `fillet.edges` | edgesBlended | 3 | 0.629 | 0.9939 | [0.533, 0.726] |
| `fillet.radius` | radius | 4 | 1.460 | 0.5921 | [-0.220, 3.139] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.70933 | 0.11192 | 3.88738 | 3.0 % | 33890 | 5335600 | +0 | 14.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.65193 | 0.03747 | 1.69052 | 2.3 % | 14152 | 2129552 | +0 | 14.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 338.19860 | 12.41569 | 352.57667 | 3.7 % | 2837909 | 405946336 | +0 | 15.1 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.57843 | 0.50204 | 11.40146 | 4.7 % | 84071 | 225974848 | -12160 | 23.1 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.09213 | 0.00359 | 0.09767 | 3.9 % | 375 | 59360 | +0 | 23.1 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.06807 | 0.00792 | 0.08028 | 11.6 % | 63 | 80640 | +0 | 23.1 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.01961 | 0.23643 | 4.49733 | 5.9 % | 34056 | 13154158 | +0 | 23.2 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 48.20861 | 13.94349 | 79.24508 | 28.9 % | 270353 | 66614814 | +0 | 28.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 39.23492 | 2.26247 | 42.25579 | 5.8 % | 242885 | 59648958 | +0 | 28.7 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.19956 | 0.00360 | 0.20576 | 1.8 % | 1976 | 308336 | +0 | 28.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 26.41339 | 2.49963 | 30.28329 | 9.5 % | 211425 | 25882480 | +0 | 30.5 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.72305 | 0.30530 | 8.16754 | 4.0 % | 67568 | 10408048 | +0 | 30.5 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.50130 | 0.27639 | 4.05387 | 7.9 % | 27714 | 4078224 | +0 | 30.5 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1301.48811 | 36.06848 | 1366.12675 | 2.8 % | 11116356 | 1558218704 | +0 | 30.5 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 18.64672 | 0.52953 | 19.51150 | 2.8 % | 167561 | 446577664 | -24320 | 36.9 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.17004 | 0.00642 | 0.18219 | 3.8 % | 737 | 93024 | +0 | 36.9 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11739 | 0.00372 | 0.12398 | 3.2 % | 123 | 157440 | +0 | 36.9 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.28408 | 0.24010 | 8.76662 | 2.9 % | 67923 | 24575301 | +0 | 37.0 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 98.63268 | 3.62965 | 102.68867 | 3.7 % | 614335 | 133966768 | +0 | 40.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 96.07971 | 5.74576 | 105.70196 | 6.0 % | 560370 | 120365200 | +0 | 40.8 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.24318 | 0.01286 | 0.27071 | 5.3 % | 2096 | 392112 | +0 | 40.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.05979 | 0.05004 | 8.12504 | 0.6 % | 68952 | 11624128 | +0 | 40.9 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.22485 | 0.72101 | 17.27313 | 4.4 % | 134894 | 20360432 | +0 | 40.9 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.01496 | 0.11487 | 6.22529 | 1.9 % | 54838 | 7991952 | +0 | 40.9 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5448.86165 | 172.75702 | 5660.83717 | 3.2 % | 44080127 | 6108952704 | +0 | 40.9 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 39.45817 | 1.06186 | 40.74242 | 2.7 % | 334258 | 888838496 | -48640 | 53.7 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.33968 | 0.00816 | 0.35404 | 2.4 % | 1457 | 127584 | +0 | 53.7 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23129 | 0.00255 | 0.23341 | 1.1 % | 243 | 311040 | +0 | 53.7 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.12361 | 0.38711 | 16.43196 | 2.4 % | 135627 | 48367506 | +0 | 53.7 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 250.11633 | 5.03599 | 254.38058 | 2.0 % | 1539870 | 274723413 | +0 | 62.1 |
| `cut` | edges | 720 | 720 | 7 | 1 | 252.47396 | 20.72434 | 277.38246 | 8.2 % | 1433009 | 247789511 | +0 | 62.1 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.29716 | 0.00659 | 0.30763 | 2.2 % | 2336 | 559664 | +0 | 62.1 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 16.43339 | 0.32372 | 17.10767 | 2.0 % | 134712 | 22247488 | +0 | 62.1 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 32.03463 | 0.16920 | 32.27608 | 0.5 % | 269554 | 40496624 | +0 | 62.1 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 13.56893 | 0.19130 | 13.99075 | 1.4 % | 109092 | 15971088 | +0 | 62.1 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 20139.39817 | 874.83730 | 21149.54333 | 4.3 % | 175480701 | 24398117424 | +0 | 62.1 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 79.63271 | 0.61068 | 80.22250 | 0.8 % | 668060 | 1775223216 | -97280 | 87.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.69827 | 0.03423 | 0.77111 | 4.9 % | 2899 | 229472 | +0 | 87.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.46136 | 0.01791 | 0.48224 | 3.9 % | 483 | 618240 | +0 | 87.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 37.16600 | 1.62767 | 39.00729 | 4.4 % | 271030 | 96173390 | +0 | 87.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 695.48555 | 23.87385 | 713.58129 | 3.4 % | 4342854 | 590712441 | +0 | 103.5 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 646.95362 | 18.78523 | 668.67450 | 2.9 % | 4130150 | 536946558 | +0 | 103.5 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.37965 | 0.00593 | 0.38786 | 1.6 % | 2816 | 894768 | +0 | 103.5 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 31.41540 | 1.30560 | 32.55237 | 4.2 % | 266270 | 44116800 | +0 | 103.5 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 55.62987 | 2.97321 | 59.90458 | 5.3 % | 478703 | 69143840 | +0 | 103.5 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.49206 | 0.11190 | 11.69650 | 1.0 % | 92919 | 11590416 | +0 | 103.5 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 24.83731 | 1.70086 | 27.04129 | 6.8 % | 202372 | 22644144 | +0 | 103.5 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 55.35665 | 4.02385 | 63.87221 | 7.3 % | 486810 | 49139568 | +0 | 103.5 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 23.37390 | 0.31514 | 23.89200 | 1.3 % | 202345 | 22639152 | +0 | 103.5 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 24.01211 | 0.79275 | 25.24058 | 3.3 % | 202372 | 22644144 | +0 | 103.5 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 22.61017 | 1.69202 | 25.56975 | 7.5 % | 202370 | 22640112 | +0 | 103.5 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 695.26338 | 17.94330 | 714.90675 | 2.6 % | 3554373 | 535954400 | +0 | 103.5 |

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
- `filletEx1` (x=180): occt_fillet_edges_ex, ONE edge, radius constant across the whole ladder
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
- `filletEx1` (x=360): occt_fillet_edges_ex, ONE edge, radius constant across the whole ladder
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
- `filletEx1` (x=720): occt_fillet_edges_ex, ONE edge, radius constant across the whole ladder
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
- `filletEx1` (x=1440): occt_fillet_edges_ex, ONE edge, radius constant across the whole ladder
- `filletCandidateSearch` (x=72): enumerate every filletable edge — what a UI does before it can offer a blend set
- `fillet.edges` (x=1): §6.3: the device measured this FLAT at 25.5 ms for 1, 4 and 12
- `fillet.edges` (x=4): §6.3: the device measured this FLAT at 25.5 ms for 1, 4 and 12
- `fillet.edges` (x=12): §6.3: the device measured this FLAT at 25.5 ms for 1, 4 and 12
- `fillet.radius` (x=0.5): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
- `fillet.radius` (x=1): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
- `fillet.radius` (x=2): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
- `fillet.radius` (x=4): §6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a 65x discontinuity, and it may be OCCT's own behaviour
