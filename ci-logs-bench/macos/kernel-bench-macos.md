# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:22:06Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.004 | [0.953, 1.055] | 0.9987 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.001 | [1.903, 2.099] | 0.9988 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.012 | [0.983, 1.041] | 0.9996 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.044 | 0.9956 | [0.947, 1.140] |
| `edgeInfo1` | edges | 4 | 1.004 | 0.9987 | [0.953, 1.055] |
| `allEdges` | edges | 4 | 2.001 | 0.9988 | [1.903, 2.099] |
| `allEdgesBulk` | edges | 4 | 1.883 | 0.9997 | [1.838, 1.927] |
| `buildOnly` | edges | 4 | 1.012 | 0.9996 | [0.983, 1.041] |
| `counts` | edges | 4 | 0.950 | 0.9951 | [0.857, 1.043] |
| `bbox` | edges | 4 | 0.982 | 0.9850 | [0.814, 1.149] |
| `mesh` | edges | 4 | 0.991 | 0.9922 | [0.869, 1.112] |
| `fuse` | edges | 4 | 1.316 | 0.9986 | [1.247, 1.385] |
| `cut` | edges | 4 | 1.321 | 0.9986 | [1.252, 1.391] |
| `rayHits` | edges | 4 | 0.223 | 0.9265 | [0.136, 0.310] |
| `filletEx1` | edges | 4 | 0.085 | 0.0332 | [-0.551, 0.721] |
| `fillet.edges` | edgesBlended | 3 | 0.625 | 0.9916 | [0.512, 0.738] |
| `fillet.scenario` | edgesBlended | 3 | 0.165 | 0.8927 | [0.053, 0.277] |
| `fillet.radius` | radius | 4 | 1.487 | 0.6021 | [-0.188, 3.162] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.52409 | 0.07365 | 3.65683 | 2.1 % | 33890 | 5335600 | +0 | 14.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.53901 | 0.04757 | 1.63585 | 3.1 % | 14153 | 2130000 | +0 | 14.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 328.01217 | 17.64515 | 356.54125 | 5.4 % | 2838089 | 406026976 | +0 | 15.0 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 19.69873 | 0.42173 | 20.36029 | 2.1 % | 184544 | 31080240 | +0 | 15.0 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 9.76283 | 0.17928 | 9.90629 | 1.8 % | 84071 | 225974848 | -12160 | 22.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08938 | 0.00883 | 0.10696 | 9.9 % | 375 | 59360 | +0 | 22.7 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05415 | 0.00096 | 0.05534 | 1.8 % | 63 | 80640 | +0 | 22.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.10947 | 0.17360 | 4.43758 | 4.2 % | 34056 | 13154158 | +0 | 22.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 43.44334 | 1.68837 | 45.91196 | 3.9 % | 270330 | 66609986 | +0 | 27.9 |
| `cut` | edges | 180 | 180 | 7 | 1 | 39.27036 | 3.71023 | 44.57238 | 9.4 % | 242869 | 59648574 | +0 | 27.9 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.21738 | 0.01521 | 0.24997 | 7.0 % | 1976 | 308336 | +0 | 28.0 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 25.45013 | 0.56225 | 26.11454 | 2.2 % | 211425 | 25882480 | +0 | 29.6 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.30442 | 0.59070 | 8.95979 | 7.1 % | 67568 | 10408048 | +0 | 29.6 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 3.07686 | 0.17543 | 3.40617 | 5.7 % | 27715 | 4078672 | +0 | 29.6 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1510.31460 | 139.21169 | 1720.12037 | 9.2 % | 11116716 | 1558379984 | +0 | 29.6 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 68.42595 | 1.88754 | 72.01971 | 2.8 % | 633459 | 102663664 | +0 | 29.6 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 20.55686 | 2.25065 | 25.50942 | 10.9 % | 167561 | 446577664 | -24320 | 36.4 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.19823 | 0.02340 | 0.23204 | 11.8 % | 737 | 93024 | +0 | 36.4 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.13717 | 0.01462 | 0.16103 | 10.7 % | 123 | 157440 | +0 | 36.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 9.67014 | 0.27625 | 10.06033 | 2.9 % | 67923 | 24575301 | +0 | 36.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 107.71005 | 8.94512 | 116.90058 | 8.3 % | 614262 | 133951847 | +0 | 40.0 |
| `cut` | edges | 360 | 360 | 7 | 1 | 88.68021 | 1.18596 | 90.55583 | 1.3 % | 560349 | 120360958 | +0 | 40.0 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.28483 | 0.04553 | 0.37917 | 16.0 % | 2096 | 392112 | +0 | 40.0 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 11.65353 | 4.30059 | 19.91058 | 36.9 % | 68952 | 11624128 | +0 | 40.2 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.02654 | 0.43701 | 15.62412 | 2.9 % | 134894 | 20360432 | +0 | 40.2 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 6.54549 | 0.11667 | 6.73187 | 1.8 % | 54839 | 7992400 | +0 | 40.2 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 5326.22770 | 146.25250 | 5510.71450 | 2.7 % | 44080847 | 6109275264 | +0 | 40.2 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 257.00860 | 10.15476 | 279.17900 | 4.0 % | 2326372 | 367698944 | +0 | 40.2 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 40.39048 | 0.64261 | 41.27129 | 1.6 % | 334258 | 888838496 | -48640 | 52.8 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.34466 | 0.01188 | 0.36844 | 3.4 % | 1457 | 127584 | +0 | 52.8 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23567 | 0.00774 | 0.24390 | 3.3 % | 243 | 311040 | +0 | 52.8 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 18.07002 | 2.34174 | 23.08563 | 13.0 % | 135627 | 48367506 | +0 | 52.8 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 248.95921 | 3.40644 | 253.47688 | 1.4 % | 1539768 | 274711746 | +0 | 61.3 |
| `cut` | edges | 720 | 720 | 7 | 1 | 232.72673 | 2.70662 | 237.76175 | 1.2 % | 1432916 | 247770494 | +0 | 61.3 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.29412 | 0.02061 | 0.33539 | 7.0 % | 2336 | 559664 | +0 | 61.3 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 15.45480 | 0.62792 | 16.38858 | 4.1 % | 134712 | 22247488 | +0 | 61.3 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 32.24024 | 0.22482 | 32.59837 | 0.7 % | 269554 | 40496624 | +0 | 61.3 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 12.16758 | 0.11669 | 12.35450 | 1.0 % | 109093 | 15971536 | +0 | 61.3 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 21944.19836 | 285.54607 | 22176.90192 | 1.3 % | 175482141 | 24398762544 | +0 | 61.3 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 981.54158 | 32.08383 | 1030.73962 | 3.3 % | 8885798 | 1431758592 | +0 | 61.3 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 80.80742 | 0.60543 | 81.66646 | 0.7 % | 668060 | 1775223216 | -97280 | 86.5 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.66742 | 0.01926 | 0.69428 | 2.9 % | 2899 | 229472 | +0 | 86.5 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.43685 | 0.01917 | 0.46663 | 4.4 % | 483 | 618240 | +0 | 86.5 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 32.92738 | 0.72722 | 33.82713 | 2.2 % | 271030 | 96173390 | +0 | 86.5 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 687.52486 | 66.86792 | 820.35029 | 9.7 % | 4342849 | 590690315 | +0 | 103.0 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 602.86911 | 15.46592 | 634.72496 | 2.6 % | 4130155 | 536947435 | +0 | 103.0 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.36020 | 0.00475 | 0.37066 | 1.3 % | 2816 | 894768 | +0 | 103.0 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 28.19334 | 0.61679 | 28.87987 | 2.2 % | 266270 | 44116800 | +0 | 103.0 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 49.33153 | 0.72290 | 50.04821 | 1.5 % | 478775 | 69176096 | +0 | 103.0 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.55510 | 0.01007 | 0.56535 | 1.8 % | 4013 | 309760 | +0 | 103.0 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.41773 | 0.05659 | 3.54233 | 1.7 % | 29913 | 5127328 | +0 | 103.0 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 10.07239 | 0.08035 | 10.17217 | 0.8 % | 92919 | 11590416 | +0 | 103.0 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 21.25940 | 0.17344 | 21.54629 | 0.8 % | 202372 | 22644144 | +0 | 103.0 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 48.04804 | 1.05244 | 49.20046 | 2.2 % | 486810 | 49139568 | +0 | 103.0 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 64.53597 | 2.43580 | 66.34592 | 3.8 % | 571694 | 80766512 | +0 | 103.0 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 72.06681 | 1.90529 | 74.96379 | 2.6 % | 681147 | 91820240 | +0 | 103.0 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 98.15648 | 1.59582 | 99.92992 | 1.6 % | 965585 | 118315664 | +0 | 103.0 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 21.11609 | 0.13758 | 21.29350 | 0.7 % | 202345 | 22639152 | +0 | 103.0 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 21.31399 | 0.17026 | 21.55096 | 0.8 % | 202372 | 22644144 | +0 | 103.0 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 21.30868 | 0.23254 | 21.69663 | 1.1 % | 202370 | 22640112 | +0 | 103.0 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 655.71829 | 26.71358 | 690.14100 | 4.1 % | 3554373 | 535954400 | +0 | 103.0 |

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
