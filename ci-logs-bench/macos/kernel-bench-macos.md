# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-23T10:16:53Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v23) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.086 | [1.025, 1.148] | 0.9983 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.031 | [1.994, 2.068] | 0.9998 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.003 | [0.914, 1.093] | 0.9958 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.064 | 0.9994 | [1.028, 1.101] |
| `edgeInfo1` | edges | 4 | 1.086 | 0.9983 | [1.025, 1.148] |
| `allEdges` | edges | 4 | 2.031 | 0.9998 | [1.994, 2.068] |
| `allEdgesBulk` | edges | 4 | 1.029 | 0.9996 | [1.002, 1.057] |
| `buildOnly` | edges | 4 | 1.003 | 0.9958 | [0.914, 1.093] |
| `counts` | edges | 4 | 1.009 | 0.9985 | [0.954, 1.064] |
| `bbox` | edges | 4 | 1.002 | 0.9998 | [0.983, 1.021] |
| `mesh` | edges | 4 | 1.041 | 0.9994 | [1.005, 1.078] |
| `fuse` | edges | 4 | 1.327 | 0.9972 | [1.229, 1.424] |
| `cut` | edges | 4 | 1.296 | 0.9961 | [1.183, 1.409] |
| `rayHits` | edges | 4 | 0.303 | 0.9668 | [0.225, 0.381] |
| `filletEx1` | edges | 4 | 0.148 | 0.0583 | [-0.678, 0.974] |
| `fillet.edges` | edgesBlended | 3 | 0.625 | 0.9904 | [0.504, 0.746] |
| `fillet.scenario` | edgesBlended | 3 | 0.556 | 0.9860 | [0.427, 0.686] |
| `fillet.radius` | radius | 4 | 1.453 | 0.5969 | [-0.202, 3.109] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.34815 | 0.12925 | 3.58771 | 3.9 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.07472 | 0.00291 | 0.07890 | 3.9 % | 821 | 158368 | +0 | 14.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.20968 | 0.58943 | 15.76746 | 3.9 % | 148205 | 28566976 | +0 | 14.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.68508 | 0.01178 | 0.70193 | 1.7 % | 6209 | 596032 | +0 | 14.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 9.73892 | 0.15844 | 10.03325 | 1.6 % | 84071 | 225974848 | -12160 | 22.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08762 | 0.00715 | 0.10123 | 8.2 % | 375 | 59360 | +0 | 22.7 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05507 | 0.00123 | 0.05763 | 2.2 % | 63 | 80640 | +0 | 22.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.04606 | 0.19094 | 4.36021 | 4.7 % | 34056 | 13154158 | +0 | 22.8 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 44.70978 | 3.60202 | 52.78708 | 8.1 % | 270308 | 66605598 | +0 | 28.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 42.63714 | 8.47497 | 61.81779 | 19.9 % | 242929 | 59660862 | +0 | 28.9 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.20509 | 0.00943 | 0.22595 | 4.6 % | 1976 | 308336 | +0 | 28.9 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 25.90065 | 0.27917 | 26.27958 | 1.1 % | 211425 | 25882480 | +0 | 30.4 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.37435 | 0.15237 | 7.61696 | 2.1 % | 67568 | 10408048 | +0 | 30.4 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.16563 | 0.00293 | 0.16901 | 1.8 % | 1601 | 269728 | +0 | 30.4 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 61.28993 | 1.82942 | 63.94188 | 3.0 % | 577205 | 97204096 | +0 | 30.4 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.34129 | 0.02036 | 1.37333 | 1.5 % | 12392 | 1160128 | +0 | 30.4 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.02102 | 6.55083 | 36.39946 | 29.7 % | 167561 | 446577664 | -24320 | 36.6 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16853 | 0.00692 | 0.18181 | 4.1 % | 737 | 93024 | +0 | 36.6 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.10928 | 0.00093 | 0.11061 | 0.9 % | 123 | 157440 | +0 | 36.6 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.17766 | 0.20103 | 8.47671 | 2.5 % | 67923 | 24575301 | +0 | 36.6 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 103.39336 | 8.58812 | 122.33021 | 8.3 % | 614359 | 133968267 | +0 | 40.6 |
| `cut` | edges | 360 | 360 | 7 | 1 | 108.49726 | 12.05520 | 135.52550 | 11.1 % | 560823 | 120392299 | +0 | 40.6 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.24967 | 0.00961 | 0.26053 | 3.8 % | 2096 | 392112 | +0 | 40.6 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.12462 | 1.04017 | 10.61483 | 11.4 % | 68952 | 11624128 | +0 | 40.8 |
| `build` | edges | 720 | 720 | 7 | 1 | 14.70509 | 0.33596 | 15.06446 | 2.3 % | 134894 | 20360432 | +0 | 40.8 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.32164 | 0.00922 | 0.33851 | 2.9 % | 3161 | 492448 | +0 | 40.8 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 243.06570 | 2.29275 | 245.64979 | 0.9 % | 2277605 | 354747136 | +0 | 40.8 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.80835 | 0.18309 | 3.12604 | 6.5 % | 24753 | 2255552 | +0 | 40.8 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 38.92988 | 0.48563 | 39.48971 | 1.2 % | 334258 | 888838496 | -48640 | 53.6 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.33191 | 0.00477 | 0.33983 | 1.4 % | 1457 | 127584 | +0 | 53.6 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22479 | 0.01141 | 0.24358 | 5.1 % | 243 | 311040 | +0 | 53.6 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.38886 | 0.28725 | 16.67625 | 1.8 % | 135627 | 48367506 | +0 | 53.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 250.02303 | 14.29969 | 276.41242 | 5.7 % | 1539799 | 274718183 | +0 | 61.9 |
| `cut` | edges | 720 | 720 | 7 | 1 | 229.88261 | 7.51035 | 243.29862 | 3.3 % | 1432968 | 247781026 | +0 | 61.9 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.28510 | 0.00692 | 0.29225 | 2.4 % | 2336 | 559664 | +0 | 61.9 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 15.27072 | 0.12213 | 15.52129 | 0.8 % | 134712 | 22247488 | +0 | 61.9 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 31.11027 | 0.93373 | 32.59546 | 3.0 % | 269554 | 40496624 | +0 | 61.9 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.73681 | 0.07193 | 0.89219 | 9.8 % | 6285 | 1003424 | +0 | 61.9 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1049.27665 | 73.14589 | 1192.29117 | 7.0 % | 9053767 | 1445313024 | +0 | 61.9 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 5.77751 | 0.06333 | 5.86979 | 1.1 % | 49478 | 4511936 | +0 | 61.9 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 81.83603 | 0.66862 | 82.68637 | 0.8 % | 668060 | 1775223216 | -97280 | 87.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.71885 | 0.07525 | 0.88706 | 10.5 % | 2899 | 229472 | +0 | 87.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.43864 | 0.00828 | 0.44960 | 1.9 % | 483 | 618240 | +0 | 87.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 35.57209 | 0.60052 | 36.36325 | 1.7 % | 271030 | 96173390 | +0 | 87.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 714.16653 | 15.73287 | 732.89029 | 2.2 % | 4342963 | 590734823 | +0 | 103.1 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 662.57617 | 4.21689 | 669.27800 | 0.6 % | 4130057 | 536927394 | +0 | 103.1 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.39537 | 0.00415 | 0.40062 | 1.0 % | 2816 | 894768 | +0 | 103.1 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 30.73282 | 2.20615 | 33.17262 | 7.2 % | 266270 | 44116800 | +0 | 103.1 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.58719 | 0.05569 | 2.68825 | 2.2 % | 25307 | 4253072 | +0 | 103.1 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.66010 | 0.02973 | 0.71447 | 4.5 % | 4013 | 309760 | +0 | 103.1 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.22430 | 0.21028 | 4.53229 | 5.0 % | 29913 | 5127328 | +0 | 103.1 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.34526 | 0.22939 | 11.73513 | 2.0 % | 92919 | 11590416 | +0 | 103.1 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 23.76126 | 0.28008 | 24.24221 | 1.2 % | 202372 | 22644144 | +0 | 103.1 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 54.21770 | 0.35925 | 54.82658 | 0.7 % | 486810 | 49139568 | +0 | 103.1 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 13.99529 | 0.17597 | 14.25858 | 1.3 % | 118226 | 15843488 | +0 | 103.1 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 26.38838 | 0.37456 | 27.00908 | 1.4 % | 227679 | 26897216 | +0 | 103.1 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 56.38636 | 0.38966 | 56.94408 | 0.7 % | 512117 | 53392640 | +0 | 103.1 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 23.88224 | 0.35495 | 24.53600 | 1.5 % | 202345 | 22639152 | +0 | 103.1 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 24.00459 | 0.44450 | 24.60808 | 1.9 % | 202372 | 22644144 | +0 | 103.1 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 23.57777 | 0.21074 | 23.81571 | 0.9 % | 202370 | 22640112 | +0 | 103.1 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 690.31367 | 33.71064 | 757.89292 | 4.9 % | 3554373 | 535954400 | +0 | 103.1 |

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
