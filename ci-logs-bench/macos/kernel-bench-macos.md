# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T19:39:29Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.885 | [0.557, 1.213] | 0.9332 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.939 | [1.854, 2.023] | 0.9990 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.918 | [0.519, 1.317] | 0.9104 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 0.905 | 0.9584 | [0.644, 1.167] |
| `edgeInfo1` | edges | 4 | 0.885 | 0.9332 | [0.557, 1.213] |
| `allEdges` | edges | 4 | 1.939 | 0.9990 | [1.854, 2.023] |
| `allEdgesBulk` | edges | 4 | 1.765 | 0.9781 | [1.399, 2.131] |
| `buildOnly` | edges | 4 | 0.918 | 0.9104 | [0.519, 1.317] |
| `counts` | edges | 4 | 0.871 | 0.9484 | [0.589, 1.153] |
| `bbox` | edges | 4 | 0.904 | 0.9040 | [0.496, 1.312] |
| `mesh` | edges | 4 | 0.882 | 0.9253 | [0.534, 1.229] |
| `fuse` | edges | 4 | 1.226 | 0.9770 | [0.965, 1.487] |
| `cut` | edges | 4 | 1.179 | 0.9835 | [0.968, 1.391] |
| `rayHits` | edges | 4 | 0.244 | 0.3856 | [-0.183, 0.671] |
| `filletEx1` | edges | 4 | 0.049 | 0.0045 | [-0.955, 1.053] |
| `fillet.edges` | edgesBlended | 3 | 0.624 | 0.9887 | [0.493, 0.755] |
| `fillet.scenario` | edgesBlended | 3 | 0.198 | 0.9384 | [0.098, 0.297] |
| `fillet.radius` | radius | 4 | 1.456 | 0.6017 | [-0.186, 3.097] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 6.77318 | 2.99926 | 10.95187 | 44.3 % | 33890 | 5335600 | +0 | 14.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 1 | 2.81108 | 1.28335 | 4.58454 | 45.7 % | 14153 | 2130000 | +0 | 14.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 494.69130 | 58.21576 | 606.94221 | 11.8 % | 2838089 | 406026976 | +0 | 15.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 30.64695 | 5.86827 | 40.79275 | 19.1 % | 184680 | 30723440 | +0 | 15.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 15.05062 | 2.72930 | 18.56729 | 18.1 % | 84071 | 225974848 | -12160 | 22.9 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.13155 | 0.05830 | 0.22905 | 44.3 % | 375 | 59360 | +0 | 22.9 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.07889 | 0.05611 | 0.20497 | 71.1 % | 63 | 80640 | +0 | 22.9 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.90021 | 2.56392 | 11.47717 | 43.5 % | 34056 | 13154158 | +0 | 22.9 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 57.40024 | 6.63432 | 64.26617 | 11.6 % | 270353 | 66614814 | +0 | 28.1 |
| `cut` | edges | 180 | 180 | 7 | 1 | 57.34067 | 9.87803 | 69.54083 | 17.2 % | 242903 | 59655449 | +0 | 28.1 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.26182 | 0.05244 | 0.34790 | 20.0 % | 1976 | 308336 | +0 | 28.1 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 37.29200 | 7.20703 | 47.56558 | 19.3 % | 211425 | 25882480 | +0 | 29.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 10.61090 | 3.04200 | 16.72729 | 28.7 % | 67568 | 10408048 | +0 | 29.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 5.68650 | 2.62591 | 10.29954 | 46.2 % | 27715 | 4078672 | +0 | 29.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1678.75896 | 165.04766 | 1997.15988 | 9.8 % | 11116716 | 1558379984 | +0 | 29.9 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 80.54892 | 11.74239 | 100.94046 | 14.6 % | 633718 | 101960880 | +0 | 29.9 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.83913 | 3.84993 | 28.12746 | 16.9 % | 167561 | 446577664 | -24320 | 36.3 |
| `counts` | edges | 360 | 360 | 7 | 8 | 0.23481 | 0.05856 | 0.33072 | 24.9 % | 737 | 93024 | +0 | 36.3 |
| `bbox` | edges | 360 | 360 | 7 | 8 | 0.16798 | 0.06707 | 0.26573 | 39.9 % | 123 | 157440 | +0 | 36.3 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 13.21489 | 3.37048 | 20.45683 | 25.5 % | 67923 | 24575301 | +0 | 36.3 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 112.97642 | 9.82765 | 125.50017 | 8.7 % | 614291 | 133957845 | +0 | 40.2 |
| `cut` | edges | 360 | 360 | 7 | 1 | 117.26127 | 30.50623 | 168.44204 | 26.0 % | 560352 | 120361543 | +0 | 40.2 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.26794 | 0.04048 | 0.34718 | 15.1 % | 2096 | 392112 | +0 | 40.2 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.59148 | 0.49726 | 9.26346 | 5.8 % | 68952 | 11624128 | +0 | 40.4 |
| `build` | edges | 720 | 720 | 7 | 1 | 17.25732 | 4.26880 | 26.86525 | 24.7 % | 134894 | 20360432 | +0 | 40.4 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.89230 | 0.24886 | 7.43171 | 3.6 % | 54839 | 7992400 | +0 | 40.4 |
| `allEdges` | edges | 720 | 720 | 3 | 1 | 7165.62989 | 882.65858 | 7874.44737 | 12.3 % | 44080847 | 6109275264 | +0 | 40.4 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 466.64753 | 26.18687 | 504.09000 | 5.6 % | 2326872 | 366271424 | +0 | 40.4 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 75.64380 | 5.59796 | 83.49554 | 7.4 % | 334258 | 888838496 | -48640 | 53.2 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.59777 | 0.20047 | 0.96351 | 33.5 % | 1457 | 127584 | +0 | 53.2 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.45047 | 0.12400 | 0.60141 | 27.5 % | 243 | 311040 | +0 | 53.2 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 30.64187 | 5.74298 | 37.80229 | 18.7 % | 135627 | 48367506 | +0 | 53.2 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 385.45185 | 29.75862 | 445.02496 | 7.7 % | 1539798 | 274717890 | +0 | 61.6 |
| `cut` | edges | 720 | 720 | 7 | 1 | 355.66533 | 29.10879 | 391.05450 | 8.2 % | 1432911 | 247769470 | +0 | 61.6 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.55670 | 0.23760 | 0.99188 | 42.7 % | 2336 | 559664 | +0 | 61.6 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 26.43805 | 6.75608 | 38.78937 | 25.6 % | 134712 | 22247488 | +0 | 61.6 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 46.64861 | 4.50793 | 53.20308 | 9.7 % | 269554 | 40496624 | +0 | 61.6 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 20.38249 | 6.22727 | 28.78533 | 30.6 % | 109093 | 15971536 | +0 | 61.6 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 26898.19287 | 757.89295 | 27384.27900 | 2.8 % | 175482141 | 24398762544 | +0 | 61.6 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 1008.06045 | 64.53429 | 1133.77233 | 6.4 % | 8886779 | 1428881600 | +0 | 61.6 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 84.17119 | 5.99231 | 95.37196 | 7.1 % | 668060 | 1775223216 | -97280 | 86.8 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.72077 | 0.05701 | 0.79331 | 7.9 % | 2899 | 229472 | +0 | 86.8 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.45831 | 0.02634 | 0.51615 | 5.7 % | 483 | 618240 | +0 | 86.8 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.18074 | 2.10500 | 37.59358 | 6.2 % | 271030 | 96173390 | +0 | 86.8 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 648.46117 | 17.07462 | 682.85329 | 2.6 % | 4342840 | 590709662 | +0 | 103.3 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 604.18304 | 19.76989 | 643.61983 | 3.3 % | 4129977 | 536911157 | +0 | 103.3 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.36055 | 0.00245 | 0.36528 | 0.7 % | 2816 | 894768 | +0 | 103.3 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 28.68789 | 0.20530 | 28.96942 | 0.7 % | 266270 | 44116800 | +0 | 103.3 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 49.32848 | 0.27653 | 49.94279 | 0.6 % | 478775 | 69176096 | +0 | 103.3 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.56718 | 0.00298 | 0.56974 | 0.5 % | 4013 | 309760 | +0 | 103.3 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.59950 | 0.05968 | 3.72529 | 1.7 % | 29913 | 5127328 | +0 | 103.3 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 10.26879 | 0.32352 | 10.83242 | 3.2 % | 92919 | 11590416 | +0 | 103.3 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 21.24977 | 0.15155 | 21.45921 | 0.7 % | 202372 | 22644144 | +0 | 103.3 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 48.96036 | 0.62679 | 50.25675 | 1.3 % | 486810 | 49139568 | +0 | 103.3 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 59.55664 | 0.36439 | 60.17929 | 0.6 % | 571694 | 80766512 | +0 | 103.3 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 70.53533 | 0.18563 | 70.72713 | 0.3 % | 681147 | 91820240 | +0 | 103.3 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 98.13389 | 0.25335 | 98.40267 | 0.3 % | 965585 | 118315664 | +0 | 103.3 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 21.15462 | 0.12090 | 21.28350 | 0.6 % | 202345 | 22639152 | +0 | 103.3 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 22.90739 | 1.24423 | 25.18463 | 5.4 % | 202372 | 22644144 | +0 | 103.3 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 21.33290 | 0.33691 | 21.87692 | 1.6 % | 202370 | 22640112 | +0 | 103.3 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 625.74733 | 17.36928 | 648.89308 | 2.8 % | 3554373 | 535954400 | +0 | 103.3 |

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
