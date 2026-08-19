# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T23:42:46Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.021 | [1.007, 1.035] | 0.9999 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.026 | [2.018, 2.034] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.988 | [0.932, 1.044] | 0.9983 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.045 | 0.9998 | [1.022, 1.067] |
| `edgeInfo1` | edges | 4 | 1.021 | 0.9999 | [1.007, 1.035] |
| `allEdges` | edges | 4 | 2.026 | 1.0000 | [2.018, 2.034] |
| `allEdgesBulk` | edges | 4 | 1.907 | 0.9994 | [1.844, 1.971] |
| `buildOnly` | edges | 4 | 0.988 | 0.9983 | [0.932, 1.044] |
| `counts` | edges | 4 | 1.031 | 0.9984 | [0.973, 1.089] |
| `bbox` | edges | 4 | 1.012 | 0.9995 | [0.982, 1.043] |
| `mesh` | edges | 4 | 1.019 | 0.9942 | [0.911, 1.126] |
| `fuse` | edges | 4 | 1.282 | 0.9977 | [1.196, 1.367] |
| `cut` | edges | 4 | 1.294 | 0.9980 | [1.214, 1.373] |
| `rayHits` | edges | 4 | 0.313 | 0.9435 | [0.207, 0.419] |
| `filletEx1` | edges | 4 | 0.230 | 0.1209 | [-0.630, 1.091] |
| `fillet.edges` | edgesBlended | 3 | 0.614 | 0.9918 | [0.504, 0.723] |
| `fillet.scenario` | edgesBlended | 3 | 0.195 | 0.9432 | [0.101, 0.289] |
| `fillet.radius` | radius | 4 | 1.464 | 0.5984 | [-0.198, 3.127] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.81667 | 0.06231 | 3.93188 | 1.6 % | 33890 | 4998030 | +0 | 10.5 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.60961 | 0.02892 | 1.66714 | 1.8 % | 14153 | 1995240 | +0 | 11.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 318.59356 | 0.47660 | 319.34577 | 0.1 % | 2838089 | 381447197 | +0 | 12.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 21.77152 | 0.32552 | 22.32613 | 1.5 % | 184544 | 29711504 | +0 | 12.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.51724 | 0.10162 | 11.66874 | 0.9 % | 84141 | 210178255 | -13015 | 15.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07656 | 0.00086 | 0.07786 | 1.1 % | 375 | 55336 | +0 | 15.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05664 | 0.00076 | 0.05812 | 1.3 % | 63 | 71064 | +0 | 15.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.60854 | 0.05741 | 4.71311 | 1.2 % | 34051 | 7903880 | +0 | 15.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 53.16624 | 1.81294 | 57.23315 | 3.4 % | 270365 | 61746686 | +0 | 19.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 48.11296 | 0.07330 | 48.20470 | 0.2 % | 242905 | 55294351 | +0 | 19.7 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.22634 | 0.00443 | 0.23325 | 2.0 % | 1976 | 287740 | +0 | 19.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 27.37283 | 0.08924 | 27.52474 | 0.3 % | 211444 | 24613742 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.68238 | 0.03971 | 7.76921 | 0.5 % | 67568 | 9755593 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.33411 | 0.03526 | 3.40764 | 1.1 % | 27715 | 3819034 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1313.06085 | 0.74268 | 1314.03421 | 0.1 % | 11116716 | 1463503303 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 75.90083 | 0.28923 | 76.52741 | 0.4 % | 633459 | 98187642 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.17677 | 0.37743 | 21.91292 | 1.8 % | 167656 | 415787456 | -26002 | 25.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14934 | 0.00088 | 0.15094 | 0.6 % | 737 | 86184 | +0 | 25.1 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11198 | 0.00080 | 0.11332 | 0.7 % | 123 | 138744 | +0 | 25.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.39540 | 0.06650 | 8.52538 | 0.8 % | 67916 | 14716993 | +0 | 25.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 118.93141 | 7.22486 | 135.28381 | 6.1 % | 614344 | 125210975 | +0 | 25.6 |
| `cut` | edges | 360 | 360 | 7 | 1 | 108.19146 | 0.78604 | 109.21448 | 0.7 % | 560354 | 112638813 | +0 | 25.6 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.25897 | 0.00659 | 0.27030 | 2.5 % | 2096 | 361201 | +0 | 25.6 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.36136 | 0.06186 | 9.45795 | 0.7 % | 68952 | 10997200 | +0 | 26.5 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.84070 | 0.07202 | 15.94287 | 0.5 % | 134894 | 19067657 | +0 | 26.5 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.69908 | 0.02294 | 6.72816 | 0.3 % | 54839 | 7481759 | +0 | 26.5 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5306.29739 | 6.83358 | 5316.23785 | 0.1 % | 44080847 | 5736651256 | +0 | 31.8 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 285.63816 | 2.05203 | 289.39936 | 0.7 % | 2326372 | 352080805 | +0 | 31.8 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 42.98241 | 0.43870 | 43.93543 | 1.0 % | 334430 | 827109936 | -51963 | 36.2 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.29802 | 0.00345 | 0.30499 | 1.2 % | 1457 | 114824 | +0 | 36.2 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22204 | 0.00053 | 0.22286 | 0.2 % | 243 | 274104 | +0 | 36.2 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.67235 | 0.08729 | 16.84045 | 0.5 % | 135617 | 28291112 | +0 | 36.2 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 284.09348 | 1.16001 | 285.52568 | 0.4 % | 1539763 | 260348758 | +0 | 36.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 264.12327 | 2.12452 | 267.98295 | 0.8 % | 1433106 | 235212983 | +0 | 36.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.30695 | 0.00452 | 0.31408 | 1.5 % | 2336 | 509187 | +0 | 36.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.75589 | 1.44931 | 22.03954 | 7.7 % | 134712 | 21029586 | +0 | 36.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 33.51779 | 0.13072 | 33.70592 | 0.4 % | 269554 | 37904939 | +0 | 36.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 13.49930 | 0.05599 | 13.56931 | 0.4 % | 109093 | 14944783 | +0 | 36.2 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 21560.49900 | 34.05153 | 21596.85220 | 0.2 % | 175482141 | 22896605565 | +0 | 36.2 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1147.51055 | 4.40830 | 1152.71049 | 0.4 % | 8885798 | 1373862462 | +0 | 36.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 89.12443 | 1.23287 | 90.21549 | 1.4 % | 668604 | 1650897186 | -103943 | 42.8 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.65864 | 0.01055 | 0.67188 | 1.6 % | 2899 | 204649 | +0 | 42.8 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46770 | 0.03951 | 0.55726 | 8.4 % | 483 | 544824 | +0 | 42.8 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 38.57149 | 7.22336 | 54.84798 | 18.7 % | 271017 | 55038262 | +0 | 44.3 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 768.32057 | 6.30597 | 774.59946 | 0.8 % | 4342903 | 570327401 | +0 | 50.1 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 709.68624 | 4.88931 | 715.42879 | 0.7 % | 4130392 | 523186992 | +0 | 50.1 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.44063 | 0.00157 | 0.44264 | 0.4 % | 2816 | 804479 | +0 | 50.1 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 36.96214 | 0.21996 | 37.41129 | 0.6 % | 266270 | 41693790 | +0 | 50.1 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 57.32664 | 0.28228 | 57.93328 | 0.5 % | 478775 | 64868488 | +0 | 50.1 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.80623 | 0.08458 | 0.99676 | 10.5 % | 4013 | 305176 | +0 | 50.1 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.52748 | 1.02803 | 7.28889 | 18.6 % | 29913 | 4794312 | +0 | 50.1 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.17145 | 0.05431 | 12.26076 | 0.4 % | 92923 | 10993041 | +0 | 50.1 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 25.38744 | 0.15982 | 25.69556 | 0.6 % | 202410 | 21705426 | +0 | 51.7 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 56.45241 | 0.28253 | 56.95658 | 0.5 % | 486842 | 47294329 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 69.81632 | 0.25994 | 70.11762 | 0.4 % | 571698 | 75873179 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 82.88179 | 0.13078 | 83.07234 | 0.2 % | 681185 | 86599407 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 114.32600 | 1.83016 | 118.42311 | 1.6 % | 965617 | 112175183 | +0 | 51.7 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.55004 | 0.12294 | 25.78692 | 0.5 % | 203528 | 21789399 | +0 | 51.7 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.49573 | 0.36726 | 26.30354 | 1.4 % | 202410 | 21703991 | +0 | 51.7 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.37332 | 0.25228 | 25.91781 | 1.0 % | 202365 | 21695583 | +0 | 51.7 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 754.07013 | 1.00368 | 755.34254 | 0.1 % | 3554579 | 512341727 | +0 | 52.6 |

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
