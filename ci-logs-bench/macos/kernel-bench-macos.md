# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T23:43:14Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.118 | [0.808, 1.428] | 0.9615 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.945 | [1.801, 2.089] | 0.9972 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.942 | [0.269, 1.615] | 0.7899 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.251 | 0.9803 | [1.005, 1.497] |
| `edgeInfo1` | edges | 4 | 1.118 | 0.9615 | [0.808, 1.428] |
| `allEdges` | edges | 4 | 1.945 | 0.9972 | [1.801, 2.089] |
| `allEdgesBulk` | edges | 4 | 1.783 | 0.9578 | [1.264, 2.302] |
| `buildOnly` | edges | 4 | 0.942 | 0.7899 | [0.269, 1.615] |
| `counts` | edges | 4 | 0.908 | 0.8465 | [0.372, 1.444] |
| `bbox` | edges | 4 | 0.927 | 0.9490 | [0.629, 1.225] |
| `mesh` | edges | 4 | 0.951 | 0.8603 | [0.420, 1.483] |
| `fuse` | edges | 4 | 1.286 | 0.9851 | [1.067, 1.505] |
| `cut` | edges | 4 | 1.199 | 0.9785 | [0.953, 1.446] |
| `rayHits` | edges | 4 | 0.049 | 0.0053 | [-0.876, 0.974] |
| `filletEx1` | edges | 4 | 0.117 | 0.1305 | [-0.300, 0.533] |
| `fillet.edges` | edgesBlended | 3 | 0.616 | 0.9885 | [0.486, 0.746] |
| `fillet.scenario` | edgesBlended | 3 | 0.198 | 0.9515 | [0.110, 0.286] |
| `fillet.radius` | radius | 4 | 1.450 | 0.6025 | [-0.182, 3.083] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.21665 | 0.07340 | 3.36967 | 2.3 % | 33890 | 5335600 | +0 | 14.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.39779 | 0.02624 | 1.44227 | 1.9 % | 14153 | 2130000 | +0 | 14.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 392.71498 | 88.52827 | 569.29579 | 22.5 % | 2838089 | 406026976 | +0 | 14.9 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 18.58232 | 1.38159 | 21.63733 | 7.4 % | 184544 | 31080240 | +0 | 15.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 9.12817 | 0.63484 | 10.04092 | 7.0 % | 84071 | 225974848 | -12160 | 22.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07764 | 0.00222 | 0.08159 | 2.9 % | 375 | 59360 | +0 | 22.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05136 | 0.00107 | 0.05318 | 2.1 % | 63 | 80640 | +0 | 22.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 3.89567 | 0.03097 | 3.94583 | 0.8 % | 34056 | 13154158 | +0 | 22.8 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 42.45793 | 2.39257 | 46.22288 | 5.6 % | 270331 | 66610279 | +0 | 27.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 48.61873 | 12.87797 | 67.59858 | 26.5 % | 242906 | 59652560 | +0 | 27.8 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.23261 | 0.01367 | 0.25958 | 5.9 % | 1976 | 308336 | +0 | 27.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 25.82062 | 1.61938 | 27.97296 | 6.3 % | 211425 | 25882480 | +0 | 29.5 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.38558 | 0.20169 | 7.76383 | 2.7 % | 67568 | 10408048 | +0 | 29.5 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.15414 | 0.08825 | 3.32196 | 2.8 % | 27715 | 4078672 | +0 | 29.5 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1867.71613 | 128.97376 | 2145.20258 | 6.9 % | 11116716 | 1558379984 | +0 | 29.5 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 137.55071 | 30.84063 | 180.78017 | 22.4 % | 633459 | 102663664 | +0 | 29.5 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 42.79438 | 14.73171 | 75.01392 | 34.4 % | 167561 | 446577664 | -24320 | 36.0 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.32299 | 0.06832 | 0.41780 | 21.2 % | 737 | 93024 | +0 | 36.0 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.15230 | 0.04491 | 0.23004 | 29.5 % | 123 | 157440 | +0 | 36.0 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 14.54418 | 3.64992 | 20.11825 | 25.1 % | 67923 | 24575301 | +0 | 36.0 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 132.35998 | 8.66970 | 141.70746 | 6.6 % | 614308 | 133961209 | +0 | 39.7 |
| `cut` | edges | 360 | 360 | 7 | 1 | 129.71929 | 22.53744 | 164.61775 | 17.4 % | 560353 | 120361689 | +0 | 39.7 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.96080 | 0.72101 | 2.15183 | 75.0 % | 2096 | 392112 | +0 | 39.7 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 15.02798 | 2.94544 | 19.82608 | 19.6 % | 68952 | 11624128 | +0 | 39.8 |
| `build` | edges | 720 | 720 | 7 | 1 | 23.66907 | 5.12893 | 29.53621 | 21.7 % | 134894 | 20360432 | +0 | 39.8 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 9.41816 | 3.26490 | 14.01692 | 34.7 % | 54839 | 7992400 | +0 | 39.8 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 6448.59902 | 1002.43956 | 7943.30521 | 15.5 % | 44080847 | 6109275264 | +0 | 39.8 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 316.05939 | 44.72801 | 402.33238 | 14.2 % | 2326372 | 367698944 | +0 | 39.8 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 64.50798 | 12.92680 | 80.46508 | 20.0 % | 334258 | 888838496 | -48640 | 52.6 |
| `counts` | edges | 720 | 720 | 7 | 4 | 0.38890 | 0.15700 | 0.74484 | 40.4 % | 1457 | 127584 | +0 | 52.6 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.22389 | 0.00549 | 0.23258 | 2.5 % | 243 | 311040 | +0 | 52.6 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 25.37748 | 3.87508 | 33.20587 | 15.3 % | 135627 | 48367506 | +0 | 52.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 322.14604 | 41.78060 | 392.97375 | 13.0 % | 1539793 | 274717013 | +0 | 61.1 |
| `cut` | edges | 720 | 720 | 7 | 1 | 346.62699 | 32.37532 | 397.74921 | 9.3 % | 1432878 | 247762741 | +0 | 61.1 |
| `rayHits` | edges | 720 | 720 | 7 | 4 | 0.42553 | 0.23067 | 0.85224 | 54.2 % | 2336 | 559664 | +0 | 61.1 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 25.89959 | 6.13013 | 35.32417 | 23.7 % | 134712 | 22247488 | +0 | 61.1 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 39.27136 | 6.86988 | 49.37438 | 17.5 % | 269554 | 40496624 | +0 | 61.1 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 12.84130 | 1.22876 | 15.26358 | 9.6 % | 109093 | 15971536 | +0 | 61.1 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 23230.12418 | 3264.21549 | 25196.04342 | 14.1 % | 175482141 | 24398762544 | +0 | 61.1 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 867.36037 | 19.29498 | 894.99017 | 2.2 % | 8885798 | 1431758592 | +0 | 61.1 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 70.12514 | 0.72404 | 70.87467 | 1.0 % | 668060 | 1775223216 | -97280 | 85.8 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.59514 | 0.00127 | 0.59667 | 0.2 % | 2899 | 229472 | +0 | 85.8 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.38503 | 0.00093 | 0.38641 | 0.2 % | 483 | 618240 | +0 | 85.8 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 29.15518 | 1.12484 | 31.64829 | 3.9 % | 271030 | 96173390 | +0 | 85.8 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 615.35960 | 43.46238 | 708.18242 | 7.1 % | 4342957 | 590733653 | +0 | 102.0 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 559.69299 | 14.71358 | 583.34625 | 2.6 % | 4130191 | 536954896 | +0 | 102.0 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.34165 | 0.00940 | 0.36243 | 2.8 % | 2816 | 894768 | +0 | 102.0 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 28.19128 | 1.31330 | 30.53271 | 4.7 % | 266270 | 44116800 | +0 | 102.0 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 46.59042 | 0.12862 | 46.84625 | 0.3 % | 478775 | 69176096 | +0 | 102.0 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.55356 | 0.00233 | 0.55766 | 0.4 % | 4013 | 309760 | +0 | 102.0 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.27406 | 0.00423 | 3.27813 | 0.1 % | 29913 | 5127328 | +0 | 102.0 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 9.55063 | 0.17892 | 9.82087 | 1.9 % | 92919 | 11590416 | +0 | 102.0 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 19.55123 | 0.16830 | 19.90221 | 0.9 % | 202372 | 22644144 | +0 | 102.0 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 44.61759 | 0.12357 | 44.80900 | 0.3 % | 486810 | 49139568 | +0 | 102.0 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 55.58999 | 0.21770 | 55.74542 | 0.4 % | 571694 | 80766512 | +0 | 102.0 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 66.68785 | 3.59796 | 74.80962 | 5.4 % | 681147 | 91820240 | +0 | 102.0 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 91.59393 | 1.58195 | 94.08054 | 1.7 % | 965585 | 118315664 | +0 | 102.0 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 19.51620 | 0.18009 | 19.78800 | 0.9 % | 202345 | 22639152 | +0 | 102.0 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 21.15129 | 3.52061 | 29.12146 | 16.6 % | 202372 | 22644144 | +0 | 102.0 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 19.74172 | 0.04345 | 19.81504 | 0.2 % | 202370 | 22640112 | +0 | 102.0 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 569.74304 | 21.90323 | 619.37142 | 3.8 % | 3554373 | 535954400 | +0 | 102.0 |

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
