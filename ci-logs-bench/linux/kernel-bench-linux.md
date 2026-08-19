# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T23:38:21Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.030 | [0.999, 1.061] | 0.9995 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.026 | [2.017, 2.035] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.024 | [0.996, 1.051] | 0.9996 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.061 | 0.9997 | [1.035, 1.086] |
| `edgeInfo1` | edges | 4 | 1.030 | 0.9995 | [0.999, 1.061] |
| `allEdges` | edges | 4 | 2.026 | 1.0000 | [2.017, 2.035] |
| `allEdgesBulk` | edges | 4 | 1.899 | 0.9997 | [1.850, 1.948] |
| `buildOnly` | edges | 4 | 1.024 | 0.9996 | [0.996, 1.051] |
| `counts` | edges | 4 | 1.050 | 0.9985 | [0.994, 1.105] |
| `bbox` | edges | 4 | 1.018 | 1.0000 | [1.011, 1.025] |
| `mesh` | edges | 4 | 1.005 | 0.9994 | [0.970, 1.039] |
| `fuse` | edges | 4 | 1.294 | 0.9975 | [1.204, 1.383] |
| `cut` | edges | 4 | 1.300 | 0.9974 | [1.208, 1.392] |
| `rayHits` | edges | 4 | 0.279 | 0.9729 | [0.215, 0.344] |
| `filletEx1` | edges | 4 | 0.201 | 0.0872 | [-0.699, 1.100] |
| `fillet.edges` | edgesBlended | 3 | 0.625 | 0.9915 | [0.512, 0.739] |
| `fillet.scenario` | edgesBlended | 3 | 0.197 | 0.9439 | [0.103, 0.291] |
| `fillet.radius` | radius | 4 | 1.447 | 0.5992 | [-0.193, 3.087] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.95375 | 0.02142 | 3.98815 | 0.5 % | 33890 | 4998094 | +0 | 10.8 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.79089 | 0.01944 | 1.83214 | 1.1 % | 14153 | 1995379 | +0 | 11.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 354.67803 | 1.54516 | 357.39202 | 0.4 % | 2838089 | 381415775 | +0 | 12.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.75912 | 0.08762 | 22.87225 | 0.4 % | 184678 | 29388624 | +0 | 12.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.34724 | 0.12923 | 11.59871 | 1.1 % | 84141 | 210177818 | -13006 | 15.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07445 | 0.00037 | 0.07525 | 0.5 % | 375 | 55352 | +0 | 15.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05903 | 0.00024 | 0.05945 | 0.4 % | 63 | 71064 | +0 | 15.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.60022 | 0.05349 | 4.70391 | 1.2 % | 34051 | 7911187 | +0 | 15.6 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 51.69666 | 0.27632 | 52.16450 | 0.5 % | 270360 | 61759477 | +0 | 19.6 |
| `cut` | edges | 180 | 180 | 7 | 1 | 47.51941 | 0.31757 | 47.78029 | 0.7 % | 242911 | 55322278 | +0 | 19.6 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.26007 | 0.00352 | 0.26594 | 1.4 % | 1976 | 287978 | +0 | 19.6 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 30.04292 | 0.52880 | 30.97912 | 1.8 % | 211444 | 24606498 | +0 | 21.9 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.16809 | 0.02929 | 8.21041 | 0.4 % | 67568 | 9755710 | +0 | 21.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.75345 | 0.08606 | 3.93762 | 2.3 % | 27715 | 3818851 | +0 | 21.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1463.30342 | 6.22605 | 1475.48212 | 0.4 % | 11116716 | 1463492992 | +0 | 27.4 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 80.43617 | 0.35723 | 80.92649 | 0.4 % | 633716 | 97573077 | +0 | 27.4 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.22925 | 0.18324 | 22.51444 | 0.8 % | 167656 | 415789159 | -26007 | 29.6 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14768 | 0.00081 | 0.14891 | 0.5 % | 737 | 86312 | +0 | 29.6 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11825 | 0.00016 | 0.11840 | 0.1 % | 123 | 138744 | +0 | 29.6 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.82226 | 0.09666 | 8.99039 | 1.1 % | 67916 | 14718102 | +0 | 29.6 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 113.39292 | 0.60503 | 114.06761 | 0.5 % | 614312 | 125168128 | +0 | 29.6 |
| `cut` | edges | 360 | 360 | 7 | 1 | 104.94601 | 1.45381 | 107.88556 | 1.4 % | 560345 | 112630385 | +0 | 29.6 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.29387 | 0.00095 | 0.29503 | 0.3 % | 2096 | 361100 | +0 | 29.6 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.57508 | 0.08406 | 9.72424 | 0.9 % | 68952 | 10994158 | +0 | 29.6 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.68686 | 0.05077 | 16.76387 | 0.3 % | 134894 | 19067618 | +0 | 29.6 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.32167 | 0.01332 | 7.34386 | 0.2 % | 54839 | 7481894 | +0 | 29.6 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5888.06053 | 39.48187 | 5936.08115 | 0.7 % | 44080847 | 5736400752 | +0 | 29.6 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 299.66431 | 0.85971 | 300.51825 | 0.3 % | 2326870 | 350743259 | +0 | 29.6 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 46.94387 | 1.13867 | 49.27393 | 2.4 % | 334430 | 827091577 | -51963 | 32.6 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.29818 | 0.00304 | 0.30497 | 1.0 % | 1457 | 114936 | +0 | 32.6 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.24092 | 0.00077 | 0.24205 | 0.3 % | 243 | 274104 | +0 | 32.6 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 18.57296 | 0.34583 | 19.32717 | 1.9 % | 135617 | 28301615 | +0 | 32.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 283.07011 | 3.09013 | 287.92083 | 1.1 % | 1539793 | 260075530 | +0 | 34.5 |
| `cut` | edges | 720 | 720 | 7 | 1 | 260.68691 | 4.98507 | 270.36309 | 1.9 % | 1432823 | 235359134 | +0 | 34.5 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.35628 | 0.00482 | 0.36344 | 1.4 % | 2336 | 511342 | +0 | 34.5 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.91303 | 0.16013 | 19.17702 | 0.8 % | 134712 | 21028311 | +0 | 34.5 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 36.12820 | 0.15892 | 36.32902 | 0.4 % | 269554 | 37904882 | +0 | 34.5 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 15.48890 | 0.17088 | 15.78777 | 1.1 % | 109093 | 14942086 | +0 | 34.5 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 24067.90934 | 197.30867 | 24282.93730 | 0.8 % | 175482141 | 22898398381 | +0 | 34.5 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1181.83321 | 9.56151 | 1198.16880 | 0.8 % | 8886777 | 1369494753 | +0 | 34.5 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 94.18214 | 0.72362 | 95.12946 | 0.8 % | 668604 | 1650872736 | -103934 | 44.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.66601 | 0.00377 | 0.67037 | 0.6 % | 2899 | 204665 | +0 | 44.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.48877 | 0.00120 | 0.49132 | 0.2 % | 483 | 544824 | +0 | 44.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 36.56447 | 0.83377 | 38.18989 | 2.3 % | 271017 | 55030826 | +0 | 44.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 757.23956 | 5.50771 | 765.95657 | 0.7 % | 4342704 | 570599576 | +0 | 50.1 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 706.99770 | 6.40892 | 719.97825 | 0.9 % | 4130090 | 520712654 | +0 | 50.1 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.46518 | 0.00626 | 0.47587 | 1.3 % | 2816 | 806143 | +0 | 50.1 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 38.05697 | 0.24178 | 38.37195 | 0.6 % | 266270 | 41701687 | +0 | 50.1 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 63.17930 | 0.30666 | 63.76601 | 0.5 % | 478775 | 64891974 | +0 | 50.1 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.78102 | 0.00138 | 0.78272 | 0.2 % | 4013 | 304744 | +0 | 50.1 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.53989 | 0.04872 | 4.63370 | 1.1 % | 29913 | 4795133 | +0 | 50.1 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.14673 | 0.12572 | 13.32662 | 1.0 % | 92923 | 10991443 | +0 | 50.1 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 27.74328 | 0.29927 | 28.09097 | 1.1 % | 202410 | 21707296 | +0 | 52.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 62.75655 | 0.27012 | 63.15843 | 0.4 % | 486842 | 47304304 | +0 | 52.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 76.98626 | 0.34573 | 77.61110 | 0.4 % | 571698 | 75890272 | +0 | 52.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 91.56717 | 0.18188 | 91.82196 | 0.2 % | 681185 | 86600593 | +0 | 52.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 126.50112 | 0.83271 | 128.12884 | 0.7 % | 965617 | 112215354 | +0 | 52.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 27.86508 | 0.08866 | 28.03946 | 0.3 % | 203528 | 21785598 | +0 | 52.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 27.67682 | 0.13288 | 27.86047 | 0.5 % | 202410 | 21706542 | +0 | 52.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.77529 | 0.22522 | 28.11698 | 0.8 % | 202365 | 21698682 | +0 | 52.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 788.08578 | 3.53092 | 793.35029 | 0.4 % | 3554579 | 512300723 | +0 | 54.0 |

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
