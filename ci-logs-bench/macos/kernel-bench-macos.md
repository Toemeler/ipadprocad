# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:25:44Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.024 | [0.928, 1.120] | 0.9955 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.888 | [1.824, 1.953] | 0.9994 | yes | **AGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.861 | [0.658, 1.064] | 0.9718 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 0.929 | 0.7975 | [0.280, 1.577] |
| `edgeInfo1` | edges | 4 | 1.024 | 0.9955 | [0.928, 1.120] |
| `allEdges` | edges | 4 | 1.888 | 0.9994 | [1.824, 1.953] |
| `allEdgesBulk` | edges | 4 | 1.782 | 0.9989 | [1.701, 1.863] |
| `buildOnly` | edges | 4 | 0.861 | 0.9718 | [0.658, 1.064] |
| `counts` | edges | 4 | 0.746 | 0.9741 | [0.578, 0.915] |
| `bbox` | edges | 4 | 0.931 | 0.9978 | [0.870, 0.992] |
| `mesh` | edges | 4 | 1.026 | 0.9968 | [0.945, 1.107] |
| `fuse` | edges | 4 | 1.291 | 0.9931 | [1.142, 1.440] |
| `cut` | edges | 4 | 1.191 | 0.9960 | [1.086, 1.296] |
| `rayHits` | edges | 4 | 0.174 | 0.6680 | [0.004, 0.343] |
| `filletEx1` | edges | 4 | 0.058 | 0.0073 | [-0.872, 0.987] |
| `fillet.edges` | edgesBlended | 3 | 0.636 | 0.9929 | [0.530, 0.742] |
| `fillet.scenario` | edgesBlended | 3 | 0.163 | 0.9769 | [0.114, 0.212] |
| `fillet.radius` | radius | 4 | 1.529 | 0.6044 | [-0.185, 3.243] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.76082 | 0.24826 | 4.29596 | 6.6 % | 33890 | 5335600 | +0 | 14.3 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.53046 | 0.07528 | 1.61323 | 4.9 % | 14153 | 2130000 | +0 | 15.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 383.28533 | 30.62881 | 428.06079 | 8.0 % | 2838089 | 406026976 | +0 | 15.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 22.36512 | 3.04901 | 26.86733 | 13.6 % | 184544 | 31080240 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 14.07436 | 2.49567 | 18.59125 | 17.7 % | 84071 | 225974848 | -12160 | 23.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.13669 | 0.04375 | 0.19626 | 32.0 % | 375 | 59360 | +0 | 23.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05606 | 0.00277 | 0.06043 | 4.9 % | 63 | 80640 | +0 | 23.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.04462 | 0.14948 | 4.28208 | 3.7 % | 34056 | 13154158 | +0 | 23.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 48.26266 | 3.24608 | 52.57571 | 6.7 % | 270366 | 66617447 | +0 | 29.0 |
| `cut` | edges | 180 | 180 | 7 | 1 | 48.80861 | 5.54731 | 56.15046 | 11.4 % | 242893 | 59653401 | +0 | 29.1 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25048 | 0.03087 | 0.29807 | 12.3 % | 1976 | 308336 | +0 | 29.1 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.62314 | 6.01209 | 43.22933 | 20.3 % | 211425 | 25882480 | +0 | 30.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 18.48520 | 13.35992 | 43.56054 | 72.3 % | 67568 | 10408048 | +0 | 30.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.31390 | 0.10664 | 3.44800 | 3.2 % | 27715 | 4078672 | +0 | 30.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1558.92303 | 208.56153 | 1930.22458 | 13.4 % | 11116716 | 1558379984 | +0 | 30.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 68.28285 | 3.17284 | 70.12483 | 4.6 % | 633459 | 102663664 | +0 | 30.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 19.44458 | 0.49772 | 20.04683 | 2.6 % | 167561 | 446577664 | -24320 | 37.2 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.17917 | 0.01648 | 0.21262 | 9.2 % | 737 | 93024 | +0 | 37.2 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.10513 | 0.00289 | 0.11126 | 2.7 % | 123 | 157440 | +0 | 37.2 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 7.37814 | 0.08015 | 7.46300 | 1.1 % | 67923 | 24575301 | +0 | 37.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 100.35889 | 4.51897 | 106.13142 | 4.5 % | 614304 | 133960331 | +0 | 41.2 |
| `cut` | edges | 360 | 360 | 7 | 1 | 97.08351 | 7.66741 | 113.24400 | 7.9 % | 560301 | 120351157 | +0 | 41.2 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.24299 | 0.00388 | 0.24955 | 1.6 % | 2096 | 392112 | +0 | 41.2 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.19181 | 0.16667 | 8.35812 | 2.0 % | 68952 | 11624128 | +0 | 41.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.91476 | 0.72981 | 17.48346 | 4.6 % | 134894 | 20360432 | +0 | 41.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 7.11411 | 0.62393 | 8.10642 | 8.8 % | 54839 | 7992400 | +0 | 41.4 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5505.44782 | 233.03003 | 5738.73150 | 4.2 % | 44080847 | 6109275264 | +0 | 41.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 249.56252 | 8.77486 | 257.47308 | 3.5 % | 2326372 | 367698944 | +0 | 41.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 38.32115 | 2.20090 | 40.72558 | 5.7 % | 334258 | 888838496 | -48640 | 54.2 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.33965 | 0.03271 | 0.40342 | 9.6 % | 1457 | 127584 | +0 | 54.2 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.18947 | 0.00057 | 0.19018 | 0.3 % | 243 | 311040 | +0 | 54.2 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 15.54658 | 0.94085 | 16.69375 | 6.1 % | 135627 | 48367506 | +0 | 54.2 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 244.01299 | 6.83648 | 252.36004 | 2.8 % | 1539806 | 274719499 | +0 | 62.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 229.59921 | 5.77469 | 232.98629 | 2.5 % | 1432970 | 247781465 | +0 | 62.7 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.26007 | 0.01711 | 0.29463 | 6.6 % | 2336 | 559664 | +0 | 62.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 14.91432 | 1.52140 | 17.05554 | 10.2 % | 134712 | 22247488 | +0 | 62.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 33.78227 | 1.21716 | 36.47000 | 3.6 % | 269554 | 40496624 | +0 | 62.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 12.63986 | 0.35957 | 13.34592 | 2.8 % | 109093 | 15971536 | +0 | 62.7 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 19751.32319 | 411.30934 | 20022.78317 | 2.1 % | 175482141 | 24398762544 | +0 | 62.7 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 891.84467 | 26.24423 | 929.62283 | 2.9 % | 8885798 | 1431758592 | +0 | 62.7 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 81.98645 | 12.18434 | 108.86592 | 14.9 % | 668060 | 1775475998 | -97280 | 87.7 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.61971 | 0.01966 | 0.66169 | 3.2 % | 2899 | 229472 | +0 | 87.7 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.39587 | 0.00915 | 0.41655 | 2.3 % | 483 | 618240 | +0 | 87.7 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.74898 | 2.97907 | 38.65392 | 8.8 % | 271030 | 97942862 | +0 | 87.7 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 708.56460 | 52.73378 | 802.87225 | 7.4 % | 4342724 | 590685817 | +0 | 104.1 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 574.40317 | 26.43305 | 625.10079 | 4.6 % | 4130038 | 536923591 | +0 | 104.1 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.36578 | 0.01661 | 0.38732 | 4.5 % | 2816 | 894768 | +0 | 104.1 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 27.71296 | 0.84527 | 28.81154 | 3.1 % | 266270 | 44116800 | +0 | 104.1 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 47.63629 | 0.61253 | 48.57317 | 1.3 % | 478775 | 69176096 | +0 | 104.1 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.53367 | 0.00345 | 0.53959 | 0.6 % | 4013 | 309760 | +0 | 104.1 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.44271 | 0.09427 | 3.52354 | 2.7 % | 29913 | 5127328 | +0 | 104.1 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 9.55962 | 0.32836 | 9.97658 | 3.4 % | 92919 | 11590416 | +0 | 104.1 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 20.65238 | 0.68052 | 21.46050 | 3.3 % | 202372 | 22644144 | +0 | 104.1 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 46.86151 | 0.85830 | 48.66121 | 1.8 % | 486810 | 49139568 | +0 | 104.1 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 66.99440 | 7.89786 | 77.27396 | 11.8 % | 571694 | 80766512 | +0 | 104.1 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 79.73253 | 3.38146 | 83.47596 | 4.2 % | 681147 | 91820240 | +0 | 104.1 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 100.87244 | 5.70620 | 111.45413 | 5.7 % | 965585 | 118315664 | +0 | 104.1 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 23.19505 | 0.23266 | 23.48817 | 1.0 % | 202345 | 22639152 | +0 | 104.1 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 22.08907 | 0.91461 | 23.19029 | 4.1 % | 202372 | 22644144 | +0 | 104.1 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 23.66708 | 0.39673 | 24.12862 | 1.7 % | 202370 | 22640112 | +0 | 104.1 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 775.54051 | 117.75131 | 955.12950 | 15.2 % | 3554373 | 535954400 | +0 | 104.1 |

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
