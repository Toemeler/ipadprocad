# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T15:47:41Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v20 (OCCT 7.9.3) (shim v20) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.998 | [0.983, 1.014] | 0.9999 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.016 | [2.005, 2.028] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.998 | [0.971, 1.026] | 0.9996 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.043 | 0.9997 | [1.017, 1.069] |
| `edgeInfo1` | edges | 4 | 0.998 | 0.9999 | [0.983, 1.014] |
| `allEdges` | edges | 4 | 2.016 | 1.0000 | [2.005, 2.028] |
| `buildOnly` | edges | 4 | 0.998 | 0.9996 | [0.971, 1.026] |
| `counts` | edges | 4 | 1.060 | 0.9988 | [1.009, 1.112] |
| `bbox` | edges | 4 | 1.034 | 0.9982 | [0.974, 1.094] |
| `mesh` | edges | 4 | 0.969 | 0.9997 | [0.947, 0.992] |
| `fuse` | edges | 4 | 1.282 | 0.9968 | [1.181, 1.382] |
| `cut` | edges | 4 | 1.295 | 0.9965 | [1.188, 1.402] |
| `rayHits` | edges | 4 | 0.277 | 0.9800 | [0.222, 0.332] |
| `filletEx1` | edges | 4 | 0.213 | 0.1004 | [-0.670, 1.096] |
| `fillet.edges` | edgesBlended | 3 | 0.621 | 0.9914 | [0.507, 0.734] |
| `fillet.scenario` | edgesBlended | 3 | 0.193 | 0.9404 | [0.098, 0.289] |
| `fillet.radius` | radius | 4 | 1.453 | 0.5949 | [-0.209, 3.114] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.10584 | 0.13706 | 4.40584 | 3.3 % | 33890 | 4998089 | +0 | 10.7 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.86940 | 0.19612 | 2.31061 | 10.5 % | 14152 | 1994509 | +0 | 11.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 353.96329 | 0.45069 | 354.76488 | 0.1 % | 2837909 | 381349640 | +0 | 12.1 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.34258 | 0.22234 | 11.80528 | 2.0 % | 84141 | 210181928 | -12997 | 15.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08199 | 0.00029 | 0.08235 | 0.4 % | 375 | 55352 | +0 | 15.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05683 | 0.00014 | 0.05704 | 0.2 % | 63 | 71064 | +0 | 15.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.55269 | 0.05044 | 4.62239 | 1.1 % | 34051 | 7903823 | +0 | 15.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 51.34200 | 0.12838 | 51.55604 | 0.3 % | 270339 | 61740104 | +0 | 19.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 47.20668 | 0.17384 | 47.39918 | 0.4 % | 242938 | 55317481 | +0 | 19.5 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.26243 | 0.00309 | 0.26696 | 1.2 % | 1976 | 287903 | +0 | 19.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.51225 | 0.34971 | 30.10153 | 1.2 % | 211444 | 24606480 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.23495 | 0.02982 | 8.27738 | 0.4 % | 67568 | 9755707 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.64795 | 0.02363 | 3.68041 | 0.6 % | 27714 | 3818569 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1448.96520 | 6.25454 | 1459.79594 | 0.4 % | 11116356 | 1463262631 | +0 | 27.2 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.83210 | 0.21260 | 22.18068 | 1.0 % | 167656 | 415793751 | -26007 | 29.5 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16296 | 0.00124 | 0.16552 | 0.8 % | 737 | 86088 | +0 | 29.5 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11426 | 0.00025 | 0.11465 | 0.2 % | 123 | 138744 | +0 | 29.5 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.62633 | 0.07814 | 8.77933 | 0.9 % | 67916 | 14723459 | +0 | 29.5 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 112.40420 | 0.25663 | 112.69664 | 0.2 % | 614277 | 125189638 | +0 | 29.5 |
| `cut` | edges | 360 | 360 | 7 | 1 | 103.98395 | 0.37651 | 104.51042 | 0.4 % | 560290 | 112611018 | +0 | 29.5 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.29735 | 0.00264 | 0.30286 | 0.9 % | 2096 | 361059 | +0 | 29.5 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.63510 | 0.03569 | 9.70347 | 0.4 % | 68952 | 10994864 | +0 | 29.5 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.92923 | 0.07968 | 17.08688 | 0.5 % | 134894 | 19067723 | +0 | 29.5 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.40577 | 0.04478 | 7.49065 | 0.6 % | 54838 | 7481543 | +0 | 29.5 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5869.45179 | 12.74421 | 5886.17510 | 0.2 % | 44080127 | 5737404848 | +0 | 29.5 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 44.16546 | 0.38200 | 45.00961 | 0.9 % | 334430 | 827080791 | -51966 | 32.7 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.36703 | 0.00303 | 0.37135 | 0.8 % | 1457 | 114984 | +0 | 32.7 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.25302 | 0.00220 | 0.25695 | 0.9 % | 243 | 274104 | +0 | 32.7 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.16999 | 0.11934 | 17.34773 | 0.7 % | 135617 | 28292918 | +0 | 32.7 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 270.27374 | 0.62989 | 271.08931 | 0.2 % | 1539860 | 260049798 | +0 | 34.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 251.01625 | 0.95925 | 252.31471 | 0.4 % | 1432941 | 235166761 | +0 | 34.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.36385 | 0.00250 | 0.36712 | 0.7 % | 2336 | 508894 | +0 | 34.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 19.46420 | 0.01985 | 19.48718 | 0.1 % | 134712 | 21029026 | +0 | 34.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 35.94515 | 0.19981 | 36.33326 | 0.6 % | 269554 | 37904880 | +0 | 34.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 14.81639 | 0.07315 | 14.91845 | 0.5 % | 109092 | 14943310 | +0 | 34.2 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 23417.32534 | 10.41984 | 23426.20379 | 0.0 % | 175480701 | 22896893421 | +0 | 34.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 90.06174 | 1.88411 | 93.91094 | 2.1 % | 668604 | 1650868880 | -103952 | 43.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.72497 | 0.00959 | 0.73597 | 1.3 % | 2899 | 204713 | +0 | 43.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.47541 | 0.00421 | 0.48189 | 0.9 % | 483 | 544824 | +0 | 43.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.98216 | 0.17349 | 34.31887 | 0.5 % | 271017 | 55022282 | +0 | 43.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 740.35226 | 3.41668 | 744.54610 | 0.5 % | 4342881 | 569882081 | +0 | 47.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 701.49289 | 17.71240 | 739.46338 | 2.5 % | 4130012 | 522095477 | +0 | 47.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.46576 | 0.00314 | 0.47213 | 0.7 % | 2816 | 807639 | +0 | 47.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 38.17302 | 0.07491 | 38.29984 | 0.2 % | 266270 | 41700546 | +0 | 47.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 62.89603 | 0.17150 | 63.16163 | 0.3 % | 478703 | 64866461 | +0 | 47.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.03028 | 0.03606 | 13.08359 | 0.3 % | 92923 | 10992527 | +0 | 47.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 27.33546 | 0.21437 | 27.80556 | 0.8 % | 202410 | 21704795 | +0 | 49.0 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 61.52516 | 0.28112 | 61.96537 | 0.5 % | 486842 | 47281947 | +0 | 49.0 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 76.61153 | 1.60349 | 80.22045 | 2.1 % | 571626 | 75855403 | +0 | 49.0 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 90.56141 | 0.12001 | 90.70689 | 0.1 % | 681113 | 86577894 | +0 | 49.0 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 124.85816 | 0.19824 | 125.19481 | 0.2 % | 965545 | 112186017 | +0 | 49.0 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 27.83041 | 0.71236 | 29.37565 | 2.6 % | 203528 | 21784853 | +0 | 49.0 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 27.30349 | 0.07027 | 27.37333 | 0.3 % | 202410 | 21705591 | +0 | 49.0 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.23486 | 0.09078 | 27.35109 | 0.3 % | 202365 | 21693953 | +0 | 49.0 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 798.79401 | 1.32129 | 800.72631 | 0.2 % | 3554579 | 512437528 | +0 | 50.2 |

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
