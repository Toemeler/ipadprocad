# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:30:07Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.206 | [1.119, 1.293] | 0.9973 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.049 | [1.964, 2.133] | 0.9991 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.993 | [0.873, 1.112] | 0.9925 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.251 | 0.9947 | [1.124, 1.378] |
| `edgeInfo1` | edges | 4 | 1.206 | 0.9973 | [1.119, 1.293] |
| `allEdges` | edges | 4 | 2.049 | 0.9991 | [1.964, 2.133] |
| `allEdgesBulk` | edges | 4 | 1.836 | 0.9989 | [1.750, 1.922] |
| `buildOnly` | edges | 4 | 0.993 | 0.9925 | [0.873, 1.112] |
| `counts` | edges | 4 | 1.058 | 0.9856 | [0.881, 1.236] |
| `bbox` | edges | 4 | 1.064 | 0.9730 | [0.818, 1.309] |
| `mesh` | edges | 4 | 0.973 | 0.9323 | [0.609, 1.336] |
| `fuse` | edges | 4 | 1.454 | 0.9979 | [1.361, 1.547] |
| `cut` | edges | 4 | 1.339 | 0.9963 | [1.225, 1.453] |
| `rayHits` | edges | 4 | 0.306 | 0.6432 | [-0.010, 0.621] |
| `filletEx1` | edges | 4 | 0.244 | 0.1109 | [-0.714, 1.202] |
| `fillet.edges` | edgesBlended | 3 | 0.606 | 0.9715 | [0.402, 0.809] |
| `fillet.scenario` | edgesBlended | 3 | 0.230 | 0.8825 | [0.066, 0.394] |
| `fillet.radius` | radius | 4 | 1.372 | 0.5710 | [-0.276, 3.021] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.82892 | 0.17705 | 4.17708 | 4.6 % | 33890 | 5335600 | +0 | 14.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.58792 | 0.07869 | 1.70106 | 5.0 % | 14153 | 2130000 | +0 | 14.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 373.30312 | 22.54819 | 395.02837 | 6.0 % | 2838089 | 406026976 | +0 | 15.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 25.61293 | 1.70236 | 28.39242 | 6.6 % | 184544 | 31080240 | +0 | 15.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 13.94782 | 2.49287 | 17.83871 | 17.9 % | 84071 | 225974848 | -12160 | 23.1 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.09981 | 0.01442 | 0.13016 | 14.4 % | 375 | 59360 | +0 | 23.1 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.06815 | 0.00958 | 0.08375 | 14.1 % | 63 | 80640 | +0 | 23.1 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 7.45719 | 4.00704 | 16.39525 | 53.7 % | 34056 | 13154158 | +0 | 23.1 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 49.47213 | 6.27032 | 62.45854 | 12.7 % | 270290 | 66601794 | +0 | 28.4 |
| `cut` | edges | 180 | 180 | 7 | 1 | 52.73667 | 9.55942 | 70.21150 | 18.1 % | 242871 | 59649013 | +0 | 28.4 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25710 | 0.02218 | 0.28649 | 8.6 % | 1976 | 308336 | +0 | 28.4 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 30.09698 | 0.70355 | 30.85942 | 2.3 % | 211425 | 25882480 | +0 | 29.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.99964 | 0.36209 | 9.50700 | 4.0 % | 67568 | 10408048 | +0 | 29.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.89955 | 0.83587 | 5.76367 | 21.4 % | 27715 | 4078672 | +0 | 29.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1718.78974 | 130.16371 | 1914.78950 | 7.6 % | 11116716 | 1558379984 | +0 | 29.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 85.84789 | 7.73412 | 95.66450 | 9.0 % | 633459 | 102663664 | +0 | 29.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 25.08341 | 6.41756 | 34.53467 | 25.6 % | 167561 | 446577664 | -24320 | 36.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16774 | 0.01734 | 0.20572 | 10.3 % | 737 | 93024 | +0 | 36.1 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.13720 | 0.02069 | 0.17947 | 15.1 % | 123 | 157440 | +0 | 36.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.79117 | 0.90196 | 10.56363 | 10.3 % | 67923 | 24575301 | +0 | 36.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 118.73898 | 15.97868 | 143.05937 | 13.5 % | 614367 | 133966402 | +0 | 40.0 |
| `cut` | edges | 360 | 360 | 7 | 1 | 129.47119 | 22.43638 | 163.71696 | 17.3 % | 560339 | 120358910 | +0 | 40.0 |
| `rayHits` | edges | 360 | 360 | 7 | 4 | 0.24114 | 0.00639 | 0.25017 | 2.7 % | 2096 | 392112 | +0 | 40.0 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.54504 | 0.49786 | 9.61742 | 5.8 % | 68952 | 11624128 | +0 | 40.2 |
| `build` | edges | 720 | 720 | 7 | 1 | 24.87753 | 6.61568 | 35.66654 | 26.6 % | 134894 | 20360432 | +0 | 40.2 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.92389 | 1.82755 | 10.61217 | 23.1 % | 54839 | 7992400 | +0 | 40.2 |
| `allEdges` | edges | 720 | 720 | 3 | 1 | 6969.06215 | 351.80361 | 7173.99700 | 5.0 % | 44080847 | 6109275264 | +0 | 40.2 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 347.43743 | 49.18000 | 393.63642 | 14.2 % | 2326372 | 367698944 | +0 | 40.2 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 47.82015 | 2.33841 | 51.73696 | 4.9 % | 334258 | 888838496 | -48640 | 53.0 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.35846 | 0.03665 | 0.43736 | 10.2 % | 1457 | 127584 | +0 | 53.0 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22381 | 0.00349 | 0.22880 | 1.6 % | 243 | 311040 | +0 | 53.0 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 27.99020 | 11.22626 | 42.51150 | 40.1 % | 135627 | 48367506 | +0 | 53.0 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 343.33472 | 18.87331 | 370.08804 | 5.5 % | 1539768 | 274711893 | +0 | 61.3 |
| `cut` | edges | 720 | 720 | 7 | 1 | 294.77240 | 26.66740 | 340.94742 | 9.0 % | 1432847 | 247756304 | +0 | 61.4 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.47715 | 0.20184 | 0.77194 | 42.3 % | 2336 | 559664 | +0 | 61.4 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 23.31621 | 3.36307 | 27.33700 | 14.4 % | 134712 | 22247488 | +0 | 61.4 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 49.07433 | 18.96972 | 78.39846 | 38.7 % | 269554 | 40496624 | +0 | 61.4 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 20.34554 | 4.11066 | 26.70979 | 20.2 % | 109093 | 15971536 | +0 | 61.4 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 26624.22086 | 1787.50608 | 28519.98700 | 6.7 % | 175482141 | 24398762544 | +0 | 61.4 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1117.84887 | 39.62438 | 1177.37458 | 3.5 % | 8885798 | 1431758592 | +0 | 61.4 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 111.48232 | 13.81054 | 129.91146 | 12.4 % | 668060 | 1775223216 | -97280 | 85.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.89384 | 0.10702 | 1.05373 | 12.0 % | 2899 | 229472 | +0 | 85.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.67627 | 0.21208 | 1.07636 | 31.4 % | 483 | 618240 | +0 | 85.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 47.96658 | 9.73368 | 56.87438 | 20.3 % | 271030 | 96173390 | +0 | 85.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 998.85555 | 96.58010 | 1146.89321 | 9.7 % | 4342875 | 590716830 | +0 | 101.5 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 884.03999 | 73.21262 | 969.73537 | 8.3 % | 4130233 | 536963527 | +0 | 101.5 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.41495 | 0.02054 | 0.45889 | 4.9 % | 2816 | 894768 | +0 | 101.5 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.85023 | 4.54843 | 43.23775 | 12.0 % | 266270 | 44116800 | +0 | 101.5 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 76.76556 | 11.88942 | 94.77246 | 15.5 % | 478775 | 69176096 | +0 | 101.5 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.77112 | 0.07137 | 0.91639 | 9.3 % | 4013 | 309760 | +0 | 101.5 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.49452 | 1.08793 | 7.85842 | 19.8 % | 29913 | 5127328 | +0 | 101.5 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 15.33837 | 2.38114 | 18.63292 | 15.5 % | 92919 | 11590416 | +0 | 101.5 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 28.65707 | 2.62827 | 32.60700 | 9.2 % | 202372 | 22644144 | +0 | 101.5 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 70.30362 | 10.64226 | 92.04238 | 15.1 % | 486810 | 49139568 | +0 | 101.5 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 82.64553 | 5.98230 | 89.92296 | 7.2 % | 571694 | 80766512 | +0 | 101.5 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 95.55893 | 10.23223 | 107.94717 | 10.7 % | 681147 | 91820240 | +0 | 101.5 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 148.39052 | 9.94318 | 159.04583 | 6.7 % | 965585 | 118315664 | +0 | 101.5 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 35.95979 | 6.44921 | 44.49517 | 17.9 % | 202345 | 22639152 | +0 | 101.5 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 32.96443 | 4.16257 | 40.05792 | 12.6 % | 202372 | 22644144 | +0 | 101.5 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 31.99505 | 4.28686 | 38.09437 | 13.4 % | 202370 | 22640112 | +0 | 101.5 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 865.55165 | 54.80901 | 954.08854 | 6.3 % | 3554373 | 535954400 | +0 | 101.5 |

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
