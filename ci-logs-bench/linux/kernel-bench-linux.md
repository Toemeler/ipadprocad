# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:02:48Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.018 | [1.004, 1.031] | 0.9999 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.016 | [2.009, 2.024] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.023 | [0.989, 1.056] | 0.9994 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.059 | 0.9999 | [1.045, 1.073] |
| `edgeInfo1` | edges | 4 | 1.018 | 0.9999 | [1.004, 1.031] |
| `allEdges` | edges | 4 | 2.016 | 1.0000 | [2.009, 2.024] |
| `allEdgesBulk` | edges | 4 | 1.901 | 0.9997 | [1.858, 1.943] |
| `buildOnly` | edges | 4 | 1.023 | 0.9994 | [0.989, 1.056] |
| `counts` | edges | 4 | 1.064 | 0.9994 | [1.029, 1.100] |
| `bbox` | edges | 4 | 1.020 | 0.9999 | [1.010, 1.030] |
| `mesh` | edges | 4 | 1.004 | 0.9994 | [0.968, 1.039] |
| `fuse` | edges | 4 | 1.296 | 0.9967 | [1.192, 1.399] |
| `cut` | edges | 4 | 1.303 | 0.9966 | [1.197, 1.408] |
| `rayHits` | edges | 4 | 0.279 | 0.9583 | [0.199, 0.360] |
| `filletEx1` | edges | 4 | 0.213 | 0.0984 | [-0.681, 1.107] |
| `fillet.edges` | edgesBlended | 3 | 0.621 | 0.9913 | [0.507, 0.735] |
| `fillet.scenario` | edgesBlended | 3 | 0.197 | 0.9462 | [0.105, 0.289] |
| `fillet.radius` | radius | 4 | 1.473 | 0.5979 | [-0.201, 3.147] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.91190 | 0.03276 | 3.97421 | 0.8 % | 33890 | 4998005 | +0 | 10.5 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.76924 | 0.00520 | 1.77578 | 0.3 % | 14153 | 1995407 | +0 | 11.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 353.63001 | 2.58288 | 357.89223 | 0.7 % | 2838089 | 381390561 | +0 | 12.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.39463 | 0.08893 | 22.50419 | 0.4 % | 184544 | 29692693 | +0 | 12.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.28607 | 0.11669 | 11.44573 | 1.0 % | 84141 | 210179366 | -13006 | 15.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07317 | 0.00028 | 0.07372 | 0.4 % | 375 | 55344 | +0 | 15.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05606 | 0.00009 | 0.05614 | 0.2 % | 63 | 71064 | +0 | 15.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.61727 | 0.07842 | 4.75594 | 1.7 % | 34051 | 7907921 | +0 | 15.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 51.74243 | 0.47468 | 52.74088 | 0.9 % | 270360 | 61727214 | +0 | 19.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 47.29484 | 0.14733 | 47.56233 | 0.3 % | 242921 | 55320789 | +0 | 19.7 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.26214 | 0.00264 | 0.26782 | 1.0 % | 1976 | 287849 | +0 | 19.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.23709 | 0.34869 | 29.59407 | 1.2 % | 211444 | 24605723 | +0 | 21.9 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.14589 | 0.02595 | 8.18071 | 0.3 % | 67568 | 9755762 | +0 | 21.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.65618 | 0.02405 | 3.70472 | 0.7 % | 27715 | 3819185 | +0 | 21.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1437.11067 | 2.91053 | 1439.91164 | 0.2 % | 11116716 | 1463540151 | +0 | 21.9 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 79.99380 | 0.33641 | 80.58424 | 0.4 % | 633459 | 98211663 | +0 | 21.9 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.30235 | 0.93695 | 24.36102 | 4.2 % | 167656 | 415792139 | -25984 | 24.4 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14843 | 0.00112 | 0.15024 | 0.8 % | 737 | 86248 | +0 | 24.4 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11329 | 0.00039 | 0.11417 | 0.3 % | 123 | 138744 | +0 | 24.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.78059 | 0.06793 | 8.90125 | 0.8 % | 67916 | 14717183 | +0 | 24.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 114.08476 | 1.09553 | 116.42485 | 1.0 % | 614288 | 125121978 | +0 | 25.5 |
| `cut` | edges | 360 | 360 | 7 | 1 | 105.05182 | 0.57721 | 106.14529 | 0.5 % | 560402 | 112642657 | +0 | 25.5 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.29284 | 0.00082 | 0.29415 | 0.3 % | 2096 | 361107 | +0 | 25.5 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.48556 | 0.03969 | 9.53392 | 0.4 % | 68952 | 10993248 | +0 | 26.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.72253 | 0.10029 | 16.93933 | 0.6 % | 134894 | 19067822 | +0 | 26.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.31939 | 0.05776 | 7.42708 | 0.8 % | 54839 | 7482186 | +0 | 26.4 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5754.21296 | 13.69451 | 5773.35092 | 0.2 % | 44080847 | 5736737380 | +0 | 26.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 297.15257 | 1.19354 | 298.56643 | 0.4 % | 2326372 | 351883600 | +0 | 26.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 44.73741 | 0.35571 | 45.29615 | 0.8 % | 334430 | 827089218 | -51977 | 30.7 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.30660 | 0.00291 | 0.31110 | 0.9 % | 1457 | 115032 | +0 | 30.7 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22764 | 0.00053 | 0.22855 | 0.2 % | 243 | 274104 | +0 | 30.7 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 18.22787 | 0.18941 | 18.63400 | 1.0 % | 135617 | 28305391 | +0 | 30.7 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 276.88293 | 2.47336 | 280.29733 | 0.9 % | 1539853 | 260216274 | +0 | 33.5 |
| `cut` | edges | 720 | 720 | 7 | 1 | 254.35733 | 1.53209 | 256.55134 | 0.6 % | 1432888 | 235281222 | +0 | 33.5 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.35162 | 0.00319 | 0.35670 | 0.9 % | 2336 | 509317 | +0 | 33.5 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.76129 | 0.15910 | 19.09108 | 0.8 % | 134712 | 21044807 | +0 | 33.5 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 35.55535 | 0.07941 | 35.71646 | 0.2 % | 269554 | 37905029 | +0 | 33.5 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 14.73585 | 0.03664 | 14.80263 | 0.2 % | 109093 | 14946063 | +0 | 33.5 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 23501.02641 | 167.00723 | 23678.99702 | 0.7 % | 175482141 | 22899131187 | +0 | 38.4 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1167.50866 | 16.80745 | 1204.14912 | 1.4 % | 8885798 | 1371555979 | +0 | 38.4 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 95.05567 | 1.02002 | 96.76313 | 1.1 % | 668604 | 1650882270 | -103947 | 45.0 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.67192 | 0.00593 | 0.68314 | 0.9 % | 2899 | 204745 | +0 | 45.0 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46873 | 0.00440 | 0.47668 | 0.9 % | 483 | 544824 | +0 | 45.0 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 36.77915 | 0.35346 | 37.36018 | 1.0 % | 271017 | 54959496 | +0 | 45.0 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 768.90451 | 9.87055 | 782.82900 | 1.3 % | 4342895 | 571738551 | +0 | 48.5 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 714.38876 | 9.19085 | 730.16367 | 1.3 % | 4129980 | 521093778 | +0 | 48.5 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.47025 | 0.00529 | 0.47696 | 1.1 % | 2816 | 805222 | +0 | 48.5 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 38.11845 | 0.33089 | 38.44450 | 0.9 % | 266270 | 41694142 | +0 | 48.5 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 63.14086 | 1.07136 | 65.11527 | 1.7 % | 478775 | 64876584 | +0 | 48.5 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.77667 | 0.00202 | 0.78080 | 0.3 % | 4013 | 303432 | +0 | 48.5 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.51498 | 0.04961 | 4.62312 | 1.1 % | 29913 | 4794893 | +0 | 48.5 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.05682 | 0.06554 | 13.13763 | 0.5 % | 92923 | 10991183 | +0 | 48.5 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 27.36959 | 0.12016 | 27.56818 | 0.4 % | 202410 | 21699099 | +0 | 50.0 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 61.63019 | 0.26668 | 61.93708 | 0.4 % | 486842 | 47295730 | +0 | 50.0 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 75.95759 | 0.22238 | 76.33419 | 0.3 % | 571698 | 75869739 | +0 | 50.0 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 90.56164 | 0.21962 | 90.81806 | 0.2 % | 681185 | 86581633 | +0 | 50.0 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 124.87784 | 0.39132 | 125.41881 | 0.3 % | 965617 | 112176589 | +0 | 50.0 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 27.67998 | 0.24105 | 28.10614 | 0.9 % | 203528 | 21786608 | +0 | 50.0 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 27.56787 | 0.19132 | 27.80162 | 0.7 % | 202410 | 21703810 | +0 | 50.0 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.42833 | 0.22052 | 27.78212 | 0.8 % | 202365 | 21690095 | +0 | 50.0 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 833.36966 | 20.08541 | 871.19792 | 2.4 % | 3554579 | 512358310 | +0 | 50.9 |

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
