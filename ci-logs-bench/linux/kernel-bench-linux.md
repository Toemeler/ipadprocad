# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-21T11:48:47Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v22) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.065 | [1.002, 1.127] | 0.9982 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.074 | [2.026, 2.121] | 0.9997 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.930 | [0.830, 1.031] | 0.9939 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.055 | 0.9998 | [1.036, 1.073] |
| `edgeInfo1` | edges | 4 | 1.065 | 0.9982 | [1.002, 1.127] |
| `allEdges` | edges | 4 | 2.074 | 0.9997 | [2.026, 2.121] |
| `allEdgesBulk` | edges | 4 | 1.037 | 0.9998 | [1.015, 1.058] |
| `buildOnly` | edges | 4 | 0.930 | 0.9939 | [0.830, 1.031] |
| `counts` | edges | 4 | 1.021 | 0.9957 | [0.928, 1.114] |
| `bbox` | edges | 4 | 1.019 | 0.9995 | [0.987, 1.052] |
| `mesh` | edges | 4 | 0.983 | 0.9995 | [0.953, 1.012] |
| `fuse` | edges | 4 | 1.291 | 0.9964 | [1.184, 1.398] |
| `cut` | edges | 4 | 1.302 | 0.9967 | [1.199, 1.406] |
| `rayHits` | edges | 4 | 0.290 | 0.9663 | [0.215, 0.365] |
| `filletEx1` | edges | 4 | 0.214 | 0.0984 | [-0.683, 1.111] |
| `fillet.edges` | edgesBlended | 3 | 0.618 | 0.9906 | [0.500, 0.735] |
| `fillet.scenario` | edgesBlended | 3 | 0.556 | 0.9887 | [0.439, 0.672] |
| `fillet.radius` | radius | 4 | 1.468 | 0.6008 | [-0.190, 3.127] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.96733 | 0.07617 | 4.13946 | 1.9 % | 33890 | 4998114 | +0 | 10.6 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08650 | 0.00520 | 0.09685 | 6.0 % | 821 | 150520 | +0 | 10.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.37015 | 0.20521 | 15.79379 | 1.3 % | 148205 | 27145754 | +0 | 10.7 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.73876 | 0.00559 | 0.75057 | 0.8 % | 6207 | 572858 | +0 | 10.7 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 13.05541 | 2.68417 | 19.13875 | 20.6 % | 84141 | 210175722 | -13008 | 14.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08228 | 0.01039 | 0.10421 | 12.6 % | 375 | 55384 | +0 | 14.7 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05668 | 0.00217 | 0.06141 | 3.8 % | 63 | 71064 | +0 | 14.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.51958 | 0.06711 | 4.61977 | 1.5 % | 34051 | 7904061 | +0 | 14.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 51.44905 | 0.59521 | 52.69334 | 1.2 % | 270381 | 61748183 | +0 | 19.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 47.01274 | 0.11109 | 47.23284 | 0.2 % | 242859 | 55320679 | +0 | 19.8 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25319 | 0.00164 | 0.25577 | 0.6 % | 1976 | 287576 | +0 | 19.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 28.95156 | 0.38008 | 29.75024 | 1.3 % | 211444 | 24608261 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.14722 | 0.07926 | 8.28281 | 1.0 % | 67568 | 9756622 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.16950 | 0.00081 | 0.17102 | 0.5 % | 1601 | 255944 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 61.99141 | 0.14537 | 62.25527 | 0.2 % | 577205 | 92225322 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.55848 | 0.00622 | 1.56697 | 0.4 % | 12390 | 1116245 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.53784 | 0.17923 | 21.90062 | 0.8 % | 167656 | 415797063 | -25970 | 24.4 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14807 | 0.00034 | 0.14848 | 0.2 % | 737 | 86296 | +0 | 24.4 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.10944 | 0.00054 | 0.11059 | 0.5 % | 123 | 138744 | +0 | 24.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.56201 | 0.10347 | 8.69445 | 1.2 % | 67916 | 14718275 | +0 | 24.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 112.66866 | 0.29032 | 113.10012 | 0.3 % | 614235 | 125193401 | +0 | 25.5 |
| `cut` | edges | 360 | 360 | 7 | 1 | 104.19881 | 0.35676 | 104.67231 | 0.3 % | 560377 | 112655217 | +0 | 25.5 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.28521 | 0.00235 | 0.28820 | 0.8 % | 2096 | 360918 | +0 | 25.5 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.40251 | 0.03982 | 9.46244 | 0.4 % | 68952 | 10995406 | +0 | 26.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.72766 | 0.04515 | 16.81802 | 0.3 % | 134894 | 19067689 | +0 | 26.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.35215 | 0.00145 | 0.35342 | 0.4 % | 3161 | 466039 | +0 | 26.4 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 257.22862 | 0.66121 | 258.12006 | 0.3 % | 2277605 | 335688938 | +0 | 26.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.17595 | 0.00567 | 3.18210 | 0.2 % | 24751 | 2170945 | +0 | 26.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 43.71881 | 0.26600 | 44.08116 | 0.6 % | 334430 | 827082359 | -51963 | 31.1 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.30900 | 0.00215 | 0.31354 | 0.7 % | 1457 | 115016 | +0 | 31.1 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22847 | 0.00210 | 0.23320 | 0.9 % | 243 | 274104 | +0 | 31.1 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.57379 | 2.00483 | 22.11389 | 11.4 % | 135617 | 28289464 | +0 | 31.1 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 272.14038 | 2.39273 | 276.91846 | 0.9 % | 1539717 | 259955510 | +0 | 33.5 |
| `cut` | edges | 720 | 720 | 7 | 1 | 253.61213 | 2.67894 | 258.23718 | 1.1 % | 1432799 | 235328123 | +0 | 33.5 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.34761 | 0.00523 | 0.35459 | 1.5 % | 2336 | 509129 | +0 | 33.5 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.39140 | 0.05510 | 18.49346 | 0.3 % | 134712 | 21022569 | +0 | 33.5 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 35.69548 | 0.14666 | 35.98122 | 0.4 % | 269554 | 37904935 | +0 | 33.5 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.79311 | 0.00211 | 0.79695 | 0.3 % | 6285 | 950632 | +0 | 33.5 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1151.86457 | 2.14443 | 1155.42821 | 0.2 % | 9053767 | 1369157114 | +0 | 33.5 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.39296 | 0.04208 | 6.47076 | 0.7 % | 49476 | 4347689 | +0 | 33.5 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 88.50787 | 1.01955 | 90.49678 | 1.2 % | 668604 | 1650895296 | -103918 | 42.9 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.68183 | 0.00456 | 0.68852 | 0.7 % | 2899 | 204697 | +0 | 42.9 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46751 | 0.00518 | 0.47861 | 1.1 % | 483 | 544824 | +0 | 42.9 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.45034 | 0.46754 | 35.08295 | 1.4 % | 271017 | 55056614 | +0 | 42.9 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 756.44459 | 6.51245 | 764.41264 | 0.9 % | 4342909 | 571267214 | +0 | 49.2 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 708.51904 | 8.97425 | 727.05262 | 1.3 % | 4130114 | 521587670 | +0 | 49.2 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.46307 | 0.00465 | 0.47020 | 1.0 % | 2816 | 806465 | +0 | 49.2 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.93549 | 0.15817 | 38.14857 | 0.4 % | 266270 | 41704347 | +0 | 49.2 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.75876 | 0.01489 | 2.77836 | 0.5 % | 25307 | 4006618 | +0 | 49.2 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.75393 | 0.00345 | 0.76138 | 0.5 % | 4013 | 302664 | +0 | 49.2 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.47392 | 0.01295 | 4.49537 | 0.3 % | 29913 | 4794186 | +0 | 49.2 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.81464 | 0.10532 | 13.00775 | 0.8 % | 92923 | 10994106 | +0 | 49.2 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.64455 | 0.12936 | 26.88348 | 0.5 % | 202410 | 21701413 | +0 | 50.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 60.05051 | 0.95400 | 62.16490 | 1.6 % | 486842 | 47289751 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 15.59479 | 0.08127 | 15.73953 | 0.5 % | 118230 | 15003051 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 29.79866 | 0.17878 | 30.13921 | 0.6 % | 227717 | 25715270 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 62.62864 | 0.25409 | 62.88878 | 0.4 % | 512149 | 51301587 | +0 | 50.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.73616 | 0.16841 | 26.96082 | 0.6 % | 203528 | 21782994 | +0 | 50.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.67283 | 0.10852 | 26.83137 | 0.4 % | 202410 | 21704850 | +0 | 50.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 26.83113 | 0.42260 | 27.60358 | 1.6 % | 202365 | 21692767 | +0 | 50.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 793.73638 | 7.06234 | 809.02376 | 0.9 % | 3554579 | 512317347 | +0 | 51.9 |

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
