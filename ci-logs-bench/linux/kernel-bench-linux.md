# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T17:44:21Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.060 | [1.008, 1.113] | 0.9987 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.064 | [2.019, 2.109] | 0.9998 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.003 | [0.973, 1.033] | 0.9995 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.075 | 0.9988 | [1.024, 1.126] |
| `edgeInfo1` | edges | 4 | 1.060 | 0.9987 | [1.008, 1.113] |
| `allEdges` | edges | 4 | 2.064 | 0.9998 | [2.019, 2.109] |
| `allEdgesBulk` | edges | 4 | 1.921 | 0.9999 | [1.891, 1.952] |
| `buildOnly` | edges | 4 | 1.003 | 0.9995 | [0.973, 1.033] |
| `counts` | edges | 4 | 0.995 | 0.9996 | [0.966, 1.024] |
| `bbox` | edges | 4 | 0.992 | 1.0000 | [0.986, 0.998] |
| `mesh` | edges | 4 | 1.010 | 0.9996 | [0.983, 1.038] |
| `fuse` | edges | 4 | 1.348 | 0.9970 | [1.245, 1.450] |
| `cut` | edges | 4 | 1.356 | 0.9970 | [1.253, 1.460] |
| `rayHits` | edges | 4 | 0.278 | 0.9588 | [0.198, 0.358] |
| `filletEx1` | edges | 4 | 0.222 | 0.1080 | [-0.662, 1.107] |
| `fillet.edges` | edgesBlended | 3 | 0.630 | 0.9905 | [0.509, 0.752] |
| `fillet.scenario` | edgesBlended | 3 | 0.197 | 0.9522 | [0.110, 0.283] |
| `fillet.radius` | radius | 4 | 1.406 | 0.6017 | [-0.179, 2.992] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.53166 | 0.01763 | 3.56828 | 0.5 % | 33890 | 4998071 | +0 | 10.9 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.51324 | 0.00811 | 1.52456 | 0.5 % | 14153 | 1994915 | +0 | 12.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 303.29356 | 3.64681 | 309.59059 | 1.2 % | 2838089 | 381409985 | +0 | 12.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 19.66182 | 0.50598 | 20.80312 | 2.6 % | 184544 | 29706569 | +0 | 12.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 12.31712 | 0.27180 | 12.65136 | 2.2 % | 84141 | 210178042 | -12987 | 15.9 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08799 | 0.00346 | 0.09462 | 3.9 % | 375 | 55384 | +0 | 15.9 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.06511 | 0.00022 | 0.06551 | 0.3 % | 63 | 71064 | +0 | 15.9 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.27926 | 0.07524 | 5.44011 | 1.4 % | 34051 | 7905901 | +0 | 16.4 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 45.62504 | 0.03278 | 45.67413 | 0.1 % | 270363 | 61736938 | +0 | 20.2 |
| `cut` | edges | 180 | 180 | 7 | 1 | 41.52749 | 0.06704 | 41.64955 | 0.2 % | 242856 | 55306463 | +0 | 20.2 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.22948 | 0.00093 | 0.23133 | 0.4 % | 1976 | 287922 | +0 | 20.2 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 26.82282 | 0.04958 | 26.90197 | 0.2 % | 211444 | 24605794 | +0 | 22.2 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.02620 | 0.00801 | 8.04153 | 0.1 % | 67568 | 9755790 | +0 | 22.2 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.40789 | 0.00770 | 3.41481 | 0.2 % | 27715 | 3818678 | +0 | 22.2 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1351.37704 | 2.22121 | 1356.22739 | 0.2 % | 11116716 | 1463431986 | +0 | 27.7 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 74.26528 | 0.05400 | 74.36117 | 0.1 % | 633459 | 98249770 | +0 | 27.7 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 23.97449 | 0.40550 | 24.47522 | 1.7 % | 167656 | 415790910 | -25998 | 29.9 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16872 | 0.00036 | 0.16937 | 0.2 % | 737 | 86152 | +0 | 29.9 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.12832 | 0.00022 | 0.12872 | 0.2 % | 123 | 138744 | +0 | 29.9 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 11.07968 | 0.34879 | 11.70105 | 3.1 % | 67916 | 14720673 | +0 | 29.9 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 104.03811 | 0.19882 | 104.32036 | 0.2 % | 614261 | 125192152 | +0 | 29.9 |
| `cut` | edges | 360 | 360 | 7 | 1 | 95.07556 | 0.07609 | 95.14954 | 0.1 % | 560311 | 112680367 | +0 | 29.9 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.25630 | 0.00123 | 0.25866 | 0.5 % | 2096 | 361076 | +0 | 29.9 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.89098 | 0.01742 | 8.92306 | 0.2 % | 68952 | 10993849 | +0 | 29.9 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.16746 | 0.03264 | 16.20728 | 0.2 % | 134894 | 19083424 | +0 | 29.9 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.83090 | 0.07284 | 6.91683 | 1.1 % | 54839 | 7481208 | +0 | 29.9 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5507.80805 | 45.56176 | 5551.77752 | 0.8 % | 44080847 | 5736289804 | +0 | 29.9 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 272.46678 | 0.50432 | 273.42063 | 0.2 % | 2326372 | 351834361 | +0 | 29.9 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 47.75662 | 0.60024 | 48.81025 | 1.3 % | 334430 | 827114654 | -51970 | 32.7 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.34014 | 0.00668 | 0.35406 | 2.0 % | 1457 | 115032 | +0 | 32.7 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.25679 | 0.00085 | 0.25837 | 0.3 % | 243 | 274104 | +0 | 32.7 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 21.64533 | 0.30239 | 21.92607 | 1.4 % | 135617 | 28326618 | +0 | 32.7 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 262.93908 | 0.76500 | 263.90506 | 0.3 % | 1539881 | 260042007 | +0 | 34.8 |
| `cut` | edges | 720 | 720 | 7 | 1 | 241.96922 | 0.53878 | 242.84524 | 0.2 % | 1432869 | 235164174 | +0 | 34.8 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.30762 | 0.00030 | 0.30801 | 0.1 % | 2336 | 508977 | +0 | 34.8 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 17.51304 | 0.03550 | 17.58448 | 0.2 % | 134712 | 21030279 | +0 | 34.8 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 33.52627 | 0.07557 | 33.68117 | 0.2 % | 269554 | 37904914 | +0 | 34.8 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 13.89904 | 0.02730 | 13.94401 | 0.2 % | 109093 | 14943357 | +0 | 34.8 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 22367.90119 | 154.19494 | 22498.50145 | 0.7 % | 175482141 | 22897853976 | +0 | 34.8 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1080.25659 | 21.63043 | 1117.39945 | 2.0 % | 8885798 | 1372763232 | +0 | 34.8 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 99.32444 | 1.01924 | 101.11752 | 1.0 % | 668604 | 1650845714 | -103945 | 43.8 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.69426 | 0.00175 | 0.69687 | 0.3 % | 2899 | 204729 | +0 | 43.8 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.51138 | 0.00193 | 0.51530 | 0.4 % | 483 | 544824 | +0 | 43.8 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 43.57717 | 0.41514 | 44.00123 | 1.0 % | 271017 | 55062931 | +0 | 43.8 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 754.07020 | 3.32836 | 757.88082 | 0.4 % | 4342988 | 571157777 | +0 | 48.0 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 698.37814 | 3.17834 | 702.45912 | 0.5 % | 4130115 | 521024147 | +0 | 48.0 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.41050 | 0.00112 | 0.41175 | 0.3 % | 2816 | 804539 | +0 | 48.0 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 35.74438 | 0.15812 | 36.07651 | 0.4 % | 266270 | 41740032 | +0 | 48.0 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 57.96591 | 0.11681 | 58.19772 | 0.2 % | 478775 | 64930986 | +0 | 48.0 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.66278 | 0.00138 | 0.66481 | 0.2 % | 4013 | 305592 | +0 | 48.0 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.89128 | 0.01808 | 3.92508 | 0.5 % | 29913 | 4795706 | +0 | 48.0 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.58127 | 0.01576 | 11.60074 | 0.1 % | 92923 | 10992275 | +0 | 48.0 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 24.42026 | 0.05994 | 24.49742 | 0.2 % | 202410 | 21701691 | +0 | 49.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 56.04064 | 0.06193 | 56.09846 | 0.1 % | 486842 | 47291170 | +0 | 49.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 69.57432 | 0.10590 | 69.79166 | 0.2 % | 571698 | 75887911 | +0 | 49.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 83.42750 | 2.63956 | 89.41017 | 3.2 % | 681185 | 86608655 | +0 | 49.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 114.28759 | 0.28842 | 114.87794 | 0.3 % | 965617 | 112185603 | +0 | 49.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 24.57772 | 0.03931 | 24.62685 | 0.2 % | 203528 | 21783314 | +0 | 49.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 24.40879 | 0.05923 | 24.49537 | 0.2 % | 202410 | 21701925 | +0 | 49.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 24.75096 | 0.55708 | 25.56808 | 2.3 % | 202365 | 21693722 | +0 | 49.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 630.14880 | 6.08774 | 637.22389 | 1.0 % | 3554579 | 512385407 | +0 | 50.6 |

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
