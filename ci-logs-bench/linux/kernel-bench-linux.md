# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:57:36Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.062 | [1.001, 1.123] | 0.9983 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.063 | [2.002, 2.123] | 0.9996 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.000 | [0.986, 1.014] | 0.9999 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.077 | 0.9986 | [1.022, 1.132] |
| `edgeInfo1` | edges | 4 | 1.062 | 0.9983 | [1.001, 1.123] |
| `allEdges` | edges | 4 | 2.063 | 0.9996 | [2.002, 2.123] |
| `allEdgesBulk` | edges | 4 | 1.922 | 0.9999 | [1.900, 1.945] |
| `buildOnly` | edges | 4 | 1.000 | 0.9999 | [0.986, 1.014] |
| `counts` | edges | 4 | 0.998 | 0.9999 | [0.986, 1.010] |
| `bbox` | edges | 4 | 0.993 | 1.0000 | [0.989, 0.997] |
| `mesh` | edges | 4 | 0.999 | 0.9999 | [0.986, 1.012] |
| `fuse` | edges | 4 | 1.346 | 0.9974 | [1.251, 1.442] |
| `cut` | edges | 4 | 1.360 | 0.9974 | [1.263, 1.456] |
| `rayHits` | edges | 4 | 0.279 | 0.9640 | [0.204, 0.354] |
| `filletEx1` | edges | 4 | 0.217 | 0.1051 | [-0.660, 1.093] |
| `fillet.edges` | edgesBlended | 3 | 0.633 | 0.9899 | [0.507, 0.758] |
| `fillet.scenario` | edgesBlended | 3 | 0.196 | 0.9442 | [0.102, 0.289] |
| `fillet.radius` | radius | 4 | 1.380 | 0.5982 | [-0.187, 2.947] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 5.20211 | 0.01141 | 5.22051 | 0.2 % | 33890 | 4998048 | +0 | 10.6 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 1 | 2.21243 | 0.02462 | 2.25319 | 1.1 % | 14153 | 1995075 | +0 | 11.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 440.73003 | 0.65289 | 441.57183 | 0.1 % | 2838089 | 381363256 | +0 | 12.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 28.23791 | 0.10417 | 28.39324 | 0.4 % | 184544 | 29708866 | +0 | 12.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 15.30794 | 0.10470 | 15.46462 | 0.7 % | 84141 | 210179135 | -12994 | 15.4 |
| `counts` | edges | 180 | 180 | 7 | 16 | 0.12875 | 0.00100 | 0.13036 | 0.8 % | 375 | 55384 | +0 | 15.4 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.09372 | 0.00014 | 0.09398 | 0.1 % | 63 | 71064 | +0 | 15.4 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 6.33462 | 0.06059 | 6.44907 | 1.0 % | 34051 | 7902806 | +0 | 15.4 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 66.15370 | 0.36530 | 66.85965 | 0.6 % | 270360 | 61749193 | +0 | 19.9 |
| `cut` | edges | 180 | 180 | 7 | 1 | 60.01427 | 0.16352 | 60.27939 | 0.3 % | 242938 | 55320897 | +0 | 19.9 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.33844 | 0.00095 | 0.33935 | 0.3 % | 1976 | 287689 | +0 | 19.9 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 39.54432 | 0.04356 | 39.59941 | 0.1 % | 211444 | 24605115 | +0 | 22.0 |
| `build` | edges | 360 | 360 | 7 | 1 | 11.90110 | 0.03365 | 11.96023 | 0.3 % | 67568 | 9757845 | +0 | 22.0 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 5.04040 | 0.01046 | 5.05132 | 0.2 % | 27715 | 3818486 | +0 | 22.0 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 2010.92499 | 1.06554 | 2012.21367 | 0.1 % | 11116716 | 1463332750 | +0 | 22.0 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 109.50902 | 0.16951 | 109.75731 | 0.2 % | 633459 | 98222593 | +0 | 22.0 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 30.06162 | 0.13482 | 30.22476 | 0.4 % | 167656 | 415795682 | -25995 | 24.6 |
| `counts` | edges | 360 | 360 | 7 | 8 | 0.25372 | 0.00112 | 0.25604 | 0.4 % | 737 | 86056 | +0 | 24.6 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.18610 | 0.00069 | 0.18763 | 0.4 % | 123 | 138744 | +0 | 24.6 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 12.42359 | 0.09887 | 12.59276 | 0.8 % | 67916 | 14722701 | +0 | 24.6 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 151.11962 | 0.80244 | 152.78397 | 0.5 % | 614300 | 125140913 | +0 | 25.6 |
| `cut` | edges | 360 | 360 | 7 | 1 | 138.46246 | 0.41951 | 139.21320 | 0.3 % | 560375 | 112647611 | +0 | 25.6 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.38081 | 0.00111 | 0.38243 | 0.3 % | 2096 | 361066 | +0 | 25.6 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 13.12797 | 0.03147 | 13.17038 | 0.2 % | 68952 | 10997941 | +0 | 26.6 |
| `build` | edges | 720 | 720 | 7 | 1 | 24.10705 | 0.09090 | 24.25093 | 0.4 % | 134894 | 19067730 | +0 | 26.6 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 10.12790 | 0.05361 | 10.23431 | 0.5 % | 54839 | 7482504 | +0 | 26.6 |
| `allEdges` | edges | 720 | 720 | 3 | 1 | 8056.93476 | 14.49791 | 8073.03376 | 0.2 % | 44080847 | 5736611272 | +0 | 26.6 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 401.30537 | 0.56249 | 402.54011 | 0.1 % | 2326372 | 351821431 | +0 | 26.6 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 60.39519 | 0.17900 | 60.67440 | 0.3 % | 334430 | 827076469 | -51973 | 30.9 |
| `counts` | edges | 720 | 720 | 7 | 4 | 0.50651 | 0.00083 | 0.50786 | 0.2 % | 1457 | 114921 | +0 | 30.9 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.36952 | 0.00030 | 0.36990 | 0.1 % | 243 | 274104 | +0 | 30.9 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 25.06352 | 0.20558 | 25.33516 | 0.8 % | 135617 | 28288598 | +0 | 30.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 384.54686 | 4.88196 | 393.63415 | 1.3 % | 1539733 | 260156120 | +0 | 33.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 354.50199 | 4.82088 | 364.54215 | 1.4 % | 1432882 | 235380757 | +0 | 33.7 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.45671 | 0.00230 | 0.46166 | 0.5 % | 2336 | 508826 | +0 | 33.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 26.09980 | 0.42007 | 26.87267 | 1.6 % | 134712 | 21024576 | +0 | 33.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 49.55739 | 0.09905 | 49.69181 | 0.2 % | 269554 | 37904866 | +0 | 33.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 20.38934 | 0.03720 | 20.43635 | 0.2 % | 109093 | 14941425 | +0 | 33.7 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 32595.45372 | 69.00979 | 32674.67616 | 0.2 % | 175482141 | 22895699811 | +0 | 38.6 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1555.31514 | 2.34416 | 1558.76892 | 0.2 % | 8885798 | 1371746297 | +0 | 38.6 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 122.35713 | 0.99068 | 123.50033 | 0.8 % | 668604 | 1650835995 | -103968 | 45.0 |
| `counts` | edges | 1440 | 1440 | 7 | 2 | 1.02593 | 0.00336 | 1.03239 | 0.3 % | 2899 | 204665 | +0 | 45.0 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.73991 | 0.00340 | 0.74627 | 0.5 % | 483 | 544824 | +0 | 45.0 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 50.44968 | 0.26990 | 50.83346 | 0.5 % | 271017 | 55005782 | +0 | 45.0 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1087.59356 | 4.84384 | 1098.05409 | 0.4 % | 4342955 | 571199602 | +0 | 48.9 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 1014.94220 | 1.99577 | 1018.30809 | 0.2 % | 4130122 | 521352342 | +0 | 48.9 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 0.60678 | 0.00202 | 0.61084 | 0.3 % | 2816 | 805701 | +0 | 48.9 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 51.89562 | 0.11484 | 52.03593 | 0.2 % | 266270 | 41750501 | +0 | 48.9 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 86.12665 | 0.31741 | 86.67976 | 0.4 % | 478775 | 64877958 | +0 | 48.9 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.97251 | 0.00037 | 0.97306 | 0.0 % | 4013 | 306824 | +0 | 48.9 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.74901 | 0.01630 | 5.76912 | 0.3 % | 29913 | 4795407 | +0 | 48.9 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 17.16022 | 0.07964 | 17.29357 | 0.5 % | 92923 | 10994886 | +0 | 48.9 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 36.13652 | 0.06277 | 36.19347 | 0.2 % | 202410 | 21707520 | +0 | 50.4 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 83.51969 | 0.29155 | 84.12099 | 0.3 % | 486842 | 47302391 | +0 | 50.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 103.26381 | 0.20484 | 103.68321 | 0.2 % | 571698 | 75875282 | +0 | 50.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 122.75804 | 0.77428 | 124.16525 | 0.6 % | 681185 | 86590355 | +0 | 50.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 169.29658 | 0.17331 | 169.50983 | 0.1 % | 965617 | 112186042 | +0 | 50.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 36.41799 | 0.19697 | 36.80618 | 0.5 % | 203528 | 21788761 | +0 | 50.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 36.18473 | 0.10658 | 36.31045 | 0.3 % | 202410 | 21702926 | +0 | 50.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 36.16368 | 0.10617 | 36.36476 | 0.3 % | 202365 | 21693354 | +0 | 50.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 882.65768 | 1.18502 | 885.15096 | 0.1 % | 3554579 | 512318915 | +0 | 51.6 |

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
