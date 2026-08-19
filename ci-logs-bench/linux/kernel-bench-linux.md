# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T23:44:47Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.013 | [0.974, 1.052] | 0.9992 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.019 | [2.009, 2.029] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.006 | [0.983, 1.030] | 0.9997 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.061 | 0.9999 | [1.046, 1.077] |
| `edgeInfo1` | edges | 4 | 1.013 | 0.9992 | [0.974, 1.052] |
| `allEdges` | edges | 4 | 2.019 | 1.0000 | [2.009, 2.029] |
| `allEdgesBulk` | edges | 4 | 1.907 | 0.9998 | [1.866, 1.947] |
| `buildOnly` | edges | 4 | 1.006 | 0.9997 | [0.983, 1.030] |
| `counts` | edges | 4 | 1.052 | 0.9987 | [0.999, 1.105] |
| `bbox` | edges | 4 | 1.037 | 0.9996 | [1.007, 1.067] |
| `mesh` | edges | 4 | 0.968 | 0.9997 | [0.945, 0.991] |
| `fuse` | edges | 4 | 1.279 | 0.9974 | [1.190, 1.369] |
| `cut` | edges | 4 | 1.292 | 0.9973 | [1.199, 1.385] |
| `rayHits` | edges | 4 | 0.271 | 0.9645 | [0.199, 0.343] |
| `filletEx1` | edges | 4 | 0.222 | 0.1063 | [-0.669, 1.112] |
| `fillet.edges` | edgesBlended | 3 | 0.620 | 0.9914 | [0.507, 0.734] |
| `fillet.scenario` | edgesBlended | 3 | 0.194 | 0.9468 | [0.104, 0.285] |
| `fillet.radius` | radius | 4 | 1.449 | 0.5970 | [-0.201, 3.099] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.89741 | 0.01689 | 3.93334 | 0.4 % | 33890 | 4998041 | +0 | 10.9 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.73701 | 0.01749 | 1.75900 | 1.0 % | 14153 | 1995269 | +0 | 12.1 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 341.65089 | 0.25494 | 341.94100 | 0.1 % | 2838089 | 381354566 | +0 | 12.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.57448 | 0.09704 | 22.74590 | 0.4 % | 184544 | 29693493 | +0 | 12.2 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.05192 | 0.05084 | 11.12631 | 0.5 % | 84141 | 210183958 | -12992 | 15.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07506 | 0.00051 | 0.07580 | 0.7 % | 375 | 55336 | +0 | 15.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05536 | 0.00007 | 0.05549 | 0.1 % | 63 | 71064 | +0 | 15.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.49234 | 0.04173 | 4.58270 | 0.9 % | 34051 | 7905930 | +0 | 15.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 50.90572 | 0.08604 | 51.01526 | 0.2 % | 270382 | 61753375 | +0 | 19.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 46.68287 | 0.14139 | 46.93269 | 0.3 % | 242891 | 55298273 | +0 | 20.0 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25207 | 0.00090 | 0.25354 | 0.4 % | 1976 | 287416 | +0 | 20.0 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 28.74929 | 0.04725 | 28.82203 | 0.2 % | 211444 | 24607088 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.07678 | 0.03880 | 8.15926 | 0.5 % | 67568 | 9755675 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.71312 | 0.23416 | 4.15613 | 6.3 % | 27715 | 3818360 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1405.82039 | 2.48136 | 1409.66139 | 0.2 % | 11116716 | 1463359189 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 80.72145 | 0.19741 | 80.98025 | 0.2 % | 633459 | 98198285 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.46980 | 0.14403 | 21.78450 | 0.7 % | 167656 | 415800512 | -25979 | 24.4 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14835 | 0.00501 | 0.15968 | 3.4 % | 737 | 86072 | +0 | 24.4 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11069 | 0.00062 | 0.11203 | 0.6 % | 123 | 138744 | +0 | 24.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.51352 | 0.07853 | 8.60487 | 0.9 % | 67916 | 14727226 | +0 | 24.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 112.55266 | 0.30073 | 112.89978 | 0.3 % | 614338 | 125223217 | +0 | 25.3 |
| `cut` | edges | 360 | 360 | 7 | 1 | 103.74208 | 0.28179 | 104.07180 | 0.3 % | 560364 | 112656591 | +0 | 25.3 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.28329 | 0.00254 | 0.28722 | 0.9 % | 2096 | 360923 | +0 | 25.3 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.42752 | 0.09251 | 9.61596 | 1.0 % | 68952 | 11026014 | +0 | 26.3 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.65397 | 0.15642 | 16.99085 | 0.9 % | 134894 | 19067637 | +0 | 26.3 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.15460 | 0.03124 | 7.19876 | 0.4 % | 54839 | 7482527 | +0 | 26.3 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5655.65408 | 2.01463 | 5657.67512 | 0.0 % | 44080847 | 5736477476 | +0 | 26.3 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 303.46693 | 2.45479 | 308.61560 | 0.8 % | 2326372 | 352129017 | +0 | 26.3 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 43.70263 | 0.35142 | 44.18097 | 0.8 % | 334430 | 827127717 | -52011 | 31.4 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.30277 | 0.00181 | 0.30559 | 0.6 % | 1457 | 114920 | +0 | 31.4 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22491 | 0.00082 | 0.22632 | 0.4 % | 243 | 274104 | +0 | 31.4 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.84188 | 0.11631 | 17.05997 | 0.7 % | 135617 | 28271926 | +0 | 31.4 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 270.41843 | 1.13611 | 272.07494 | 0.4 % | 1539930 | 259969649 | +0 | 33.4 |
| `cut` | edges | 720 | 720 | 7 | 1 | 251.33261 | 1.63094 | 254.01530 | 0.6 % | 1433004 | 235314506 | +0 | 33.4 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.33720 | 0.00346 | 0.34421 | 1.0 % | 2336 | 509003 | +0 | 33.4 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.76067 | 0.02980 | 18.80779 | 0.2 % | 134712 | 21188642 | +0 | 33.4 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 35.57187 | 0.18275 | 35.89700 | 0.5 % | 269554 | 37904795 | +0 | 33.4 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 14.49232 | 0.02847 | 14.53370 | 0.2 % | 109093 | 14942575 | +0 | 33.4 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 22824.43126 | 29.19797 | 22850.34817 | 0.1 % | 175482141 | 22896752696 | +0 | 33.4 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1188.78642 | 2.46502 | 1192.48471 | 0.2 % | 8885798 | 1371656171 | +0 | 38.3 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 89.14780 | 1.21908 | 90.15074 | 1.4 % | 668604 | 1650903218 | -103920 | 44.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.67255 | 0.00883 | 0.69041 | 1.3 % | 2899 | 204521 | +0 | 44.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.47983 | 0.03160 | 0.55122 | 6.6 % | 483 | 544824 | +0 | 44.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.49027 | 0.69051 | 34.79541 | 2.1 % | 271017 | 55055032 | +0 | 44.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 730.38263 | 3.27789 | 734.02109 | 0.4 % | 4342977 | 570846482 | +0 | 48.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 687.90812 | 2.88424 | 691.92152 | 0.4 % | 4130047 | 522555383 | +0 | 48.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.44463 | 0.00449 | 0.45242 | 1.0 % | 2816 | 804951 | +0 | 48.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 38.13393 | 1.67046 | 41.83145 | 4.4 % | 266270 | 41707634 | +0 | 48.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 60.83876 | 0.23379 | 61.31635 | 0.4 % | 478775 | 64868595 | +0 | 48.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.75871 | 0.00458 | 0.76599 | 0.6 % | 4013 | 302664 | +0 | 48.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.41761 | 0.01159 | 4.43508 | 0.3 % | 29913 | 4795130 | +0 | 48.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.66561 | 0.09004 | 12.83230 | 0.7 % | 92923 | 10992326 | +0 | 48.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.55387 | 0.05723 | 26.63747 | 0.2 % | 202410 | 21702736 | +0 | 48.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 59.74763 | 0.09521 | 59.83696 | 0.2 % | 486842 | 47295008 | +0 | 48.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 74.16194 | 0.15575 | 74.43621 | 0.2 % | 571698 | 75890843 | +0 | 48.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 88.26723 | 0.39763 | 88.91094 | 0.5 % | 681185 | 86581656 | +0 | 48.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 121.13979 | 0.35250 | 121.63328 | 0.3 % | 965617 | 112178614 | +0 | 48.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.79494 | 0.15796 | 27.08373 | 0.6 % | 203528 | 21787785 | +0 | 48.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.56135 | 0.18331 | 26.93583 | 0.7 % | 202410 | 21701307 | +0 | 48.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 26.45502 | 0.02852 | 26.49684 | 0.1 % | 202365 | 21696545 | +0 | 48.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 762.72624 | 0.53296 | 763.49992 | 0.1 % | 3554579 | 512376723 | +0 | 48.6 |

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
