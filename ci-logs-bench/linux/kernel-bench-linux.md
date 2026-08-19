# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T17:37:10Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.025 | [0.998, 1.053] | 0.9996 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.018 | [2.007, 2.029] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.045 | [0.991, 1.098] | 0.9986 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.054 | 0.9999 | [1.039, 1.068] |
| `edgeInfo1` | edges | 4 | 1.025 | 0.9996 | [0.998, 1.053] |
| `allEdges` | edges | 4 | 2.018 | 1.0000 | [2.007, 2.029] |
| `allEdgesBulk` | edges | 4 | 1.904 | 0.9994 | [1.842, 1.967] |
| `buildOnly` | edges | 4 | 1.045 | 0.9986 | [0.991, 1.098] |
| `counts` | edges | 4 | 1.031 | 0.9988 | [0.982, 1.079] |
| `bbox` | edges | 4 | 0.990 | 0.9923 | [0.869, 1.111] |
| `mesh` | edges | 4 | 0.987 | 0.9992 | [0.949, 1.025] |
| `fuse` | edges | 4 | 1.274 | 0.9971 | [1.178, 1.369] |
| `cut` | edges | 4 | 1.284 | 0.9970 | [1.187, 1.381] |
| `rayHits` | edges | 4 | 0.305 | 0.9666 | [0.227, 0.384] |
| `filletEx1` | edges | 4 | 0.205 | 0.0944 | [-0.676, 1.087] |
| `fillet.edges` | edgesBlended | 3 | 0.615 | 0.9918 | [0.505, 0.725] |
| `fillet.scenario` | edgesBlended | 3 | 0.196 | 0.9718 | [0.130, 0.261] |
| `fillet.radius` | radius | 4 | 1.477 | 0.5985 | [-0.199, 3.153] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.78660 | 0.01575 | 3.80720 | 0.4 % | 33890 | 4998505 | +0 | 11.0 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.63339 | 0.01242 | 1.65421 | 0.8 % | 14153 | 1995337 | +0 | 12.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 330.16244 | 2.26947 | 334.85765 | 0.7 % | 2838089 | 381383194 | +0 | 12.4 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.28297 | 0.10664 | 22.46826 | 0.5 % | 184544 | 29695895 | +0 | 12.4 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.92519 | 0.11761 | 11.12435 | 1.1 % | 84141 | 210178618 | -12997 | 15.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07516 | 0.00074 | 0.07679 | 1.0 % | 375 | 55336 | +0 | 15.7 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05546 | 0.00009 | 0.05558 | 0.2 % | 63 | 71064 | +0 | 15.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.44872 | 0.07185 | 4.57693 | 1.6 % | 34051 | 7903208 | +0 | 15.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 53.87441 | 0.99418 | 55.52841 | 1.8 % | 270363 | 61758381 | +0 | 20.1 |
| `cut` | edges | 180 | 180 | 7 | 1 | 49.11548 | 0.37094 | 49.59773 | 0.8 % | 242864 | 55304619 | +0 | 20.1 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.23674 | 0.00199 | 0.24017 | 0.8 % | 1976 | 288106 | +0 | 20.1 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.39581 | 2.45554 | 34.84550 | 8.4 % | 211444 | 24606242 | +0 | 22.0 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.84280 | 0.05177 | 7.92022 | 0.7 % | 67568 | 9759127 | +0 | 22.0 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.42378 | 0.04228 | 3.46122 | 1.2 % | 27715 | 3820205 | +0 | 22.0 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1358.41682 | 4.14607 | 1363.35655 | 0.3 % | 11116716 | 1464130830 | +0 | 27.3 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 78.00789 | 1.17762 | 80.22549 | 1.5 % | 633459 | 98342625 | +0 | 27.3 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.77099 | 0.20821 | 22.16277 | 1.0 % | 167656 | 415797072 | -25995 | 29.6 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15379 | 0.01162 | 0.17937 | 7.6 % | 737 | 86232 | +0 | 29.6 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.13093 | 0.01576 | 0.15001 | 12.0 % | 123 | 138760 | +0 | 29.6 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.95170 | 0.26759 | 9.51806 | 3.0 % | 67916 | 14718979 | +0 | 29.6 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 119.30920 | 1.13434 | 120.66568 | 1.0 % | 614364 | 125256595 | +0 | 29.6 |
| `cut` | edges | 360 | 360 | 7 | 1 | 109.07049 | 1.07231 | 110.35323 | 1.0 % | 560385 | 112761574 | +0 | 29.6 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.27179 | 0.00096 | 0.27320 | 0.4 % | 2096 | 362560 | +0 | 29.6 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.71078 | 0.36061 | 10.51971 | 3.7 % | 68952 | 11050439 | +0 | 29.6 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.03860 | 0.06319 | 16.15794 | 0.4 % | 134894 | 19067753 | +0 | 29.6 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.98011 | 0.05509 | 7.08473 | 0.8 % | 54839 | 7482504 | +0 | 29.6 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5418.17056 | 26.88452 | 5454.23639 | 0.5 % | 44080847 | 5736482580 | +0 | 29.6 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 290.88306 | 5.29256 | 302.51815 | 1.8 % | 2326372 | 352160770 | +0 | 29.6 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 43.52866 | 0.16715 | 43.75073 | 0.4 % | 334430 | 827090843 | -51995 | 32.7 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.29718 | 0.00452 | 0.30280 | 1.5 % | 1457 | 115064 | +0 | 32.7 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22250 | 0.00042 | 0.22299 | 0.2 % | 243 | 274104 | +0 | 32.7 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.86606 | 0.10469 | 17.08229 | 0.6 % | 135617 | 28299617 | +0 | 32.7 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 281.12083 | 1.33065 | 283.66112 | 0.5 % | 1539777 | 260035496 | +0 | 34.8 |
| `cut` | edges | 720 | 720 | 7 | 1 | 259.86949 | 0.73820 | 260.94203 | 0.3 % | 1432939 | 235117531 | +0 | 34.8 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.32922 | 0.00169 | 0.33136 | 0.5 % | 2336 | 509007 | +0 | 34.8 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.66592 | 0.08111 | 18.81616 | 0.4 % | 134712 | 21028898 | +0 | 34.8 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 34.03391 | 0.30423 | 34.64590 | 0.9 % | 269554 | 37904935 | +0 | 34.8 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 13.75905 | 0.07868 | 13.86338 | 0.6 % | 109093 | 14944287 | +0 | 34.8 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 22048.73697 | 20.60901 | 22072.46125 | 0.1 % | 175482141 | 22898363923 | +0 | 34.8 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1170.76855 | 5.50723 | 1179.10960 | 0.5 % | 8885798 | 1371732485 | +0 | 34.8 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 96.90500 | 10.02604 | 118.72265 | 10.3 % | 668604 | 1650904055 | -103954 | 41.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.65275 | 0.01030 | 0.66682 | 1.6 % | 2899 | 204553 | +0 | 41.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.45752 | 0.00157 | 0.46054 | 0.3 % | 483 | 544824 | +0 | 41.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 35.24169 | 0.55711 | 36.12728 | 1.6 % | 271017 | 55035043 | +0 | 41.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 767.70471 | 7.71786 | 777.09833 | 1.0 % | 4342930 | 570962930 | +0 | 49.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 715.00217 | 4.09726 | 720.77928 | 0.6 % | 4130087 | 520308608 | +0 | 49.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.44954 | 0.00471 | 0.45395 | 1.0 % | 2816 | 804738 | +0 | 49.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.99704 | 0.30294 | 38.52609 | 0.8 % | 266270 | 41703968 | +0 | 49.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 59.23960 | 0.11584 | 59.44370 | 0.2 % | 478775 | 64934989 | +0 | 49.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.76824 | 0.00483 | 0.77830 | 0.6 % | 4013 | 303464 | +0 | 49.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.31533 | 0.02714 | 4.35355 | 0.6 % | 29913 | 4795560 | +0 | 49.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.55300 | 0.05147 | 12.64666 | 0.4 % | 92923 | 10994392 | +0 | 49.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.23315 | 0.20734 | 26.65064 | 0.8 % | 202410 | 21703666 | +0 | 50.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 58.46157 | 0.18376 | 58.65223 | 0.3 % | 486842 | 47301298 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 71.80213 | 0.20871 | 72.08435 | 0.3 % | 571698 | 75881973 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 87.91950 | 4.91779 | 98.79321 | 5.6 % | 681185 | 86615967 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 117.47095 | 0.75554 | 118.64852 | 0.6 % | 965617 | 112212605 | +0 | 50.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.42806 | 0.22635 | 26.79345 | 0.9 % | 203528 | 21789118 | +0 | 50.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.20522 | 0.06046 | 26.32125 | 0.2 % | 202410 | 21706912 | +0 | 50.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 26.26447 | 0.21050 | 26.65326 | 0.8 % | 202365 | 21696024 | +0 | 50.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 800.81787 | 6.64327 | 815.54824 | 0.8 % | 3554579 | 512367679 | +0 | 53.0 |

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
