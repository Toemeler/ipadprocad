# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:05:38Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.910 | [0.717, 1.103] | 0.9770 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.932 | [1.795, 2.069] | 0.9974 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.035 | [0.782, 1.288] | 0.9699 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 0.988 | 0.9837 | [0.811, 1.164] |
| `edgeInfo1` | edges | 4 | 0.910 | 0.9770 | [0.717, 1.103] |
| `allEdges` | edges | 4 | 1.932 | 0.9974 | [1.795, 2.069] |
| `allEdgesBulk` | edges | 4 | 1.832 | 0.9997 | [1.788, 1.876] |
| `buildOnly` | edges | 4 | 1.035 | 0.9699 | [0.782, 1.288] |
| `counts` | edges | 4 | 0.906 | 0.9836 | [0.744, 1.068] |
| `bbox` | edges | 4 | 1.066 | 0.9487 | [0.722, 1.409] |
| `mesh` | edges | 4 | 0.872 | 0.9302 | [0.541, 1.204] |
| `fuse` | edges | 4 | 1.307 | 0.9951 | [1.179, 1.434] |
| `cut` | edges | 4 | 1.236 | 0.9992 | [1.188, 1.284] |
| `rayHits` | edges | 4 | 0.236 | 0.5071 | [-0.087, 0.559] |
| `filletEx1` | edges | 4 | 0.172 | 0.1050 | [-0.525, 0.870] |
| `fillet.edges` | edgesBlended | 3 | 0.683 | 0.9991 | [0.643, 0.724] |
| `fillet.scenario` | edgesBlended | 3 | 0.209 | 0.9999 | [0.206, 0.212] |
| `fillet.radius` | radius | 4 | 1.461 | 0.6014 | [-0.187, 3.108] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.72429 | 1.90909 | 8.98617 | 40.4 % | 33890 | 5335600 | +0 | 14.3 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.98493 | 0.27628 | 2.40444 | 13.9 % | 14153 | 2130000 | +0 | 15.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 357.20607 | 37.76813 | 430.49246 | 10.6 % | 2838089 | 406026976 | +0 | 15.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 19.98507 | 1.30749 | 22.63908 | 6.5 % | 184544 | 31080240 | +0 | 15.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.25698 | 0.47199 | 11.23837 | 4.6 % | 84071 | 225974848 | -12160 | 23.1 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.09520 | 0.02356 | 0.14721 | 24.8 % | 375 | 59360 | +0 | 23.1 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05186 | 0.00256 | 0.05714 | 4.9 % | 63 | 80640 | +0 | 23.1 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.95245 | 2.98802 | 12.59292 | 50.2 % | 34056 | 13154158 | +0 | 23.1 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 45.35173 | 1.96392 | 48.15792 | 4.3 % | 270317 | 66607353 | +0 | 28.6 |
| `cut` | edges | 180 | 180 | 7 | 1 | 48.46677 | 14.23963 | 79.25750 | 29.4 % | 242861 | 59646818 | +0 | 28.6 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.21701 | 0.00786 | 0.23187 | 3.6 % | 1976 | 308336 | +0 | 28.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 25.95468 | 1.52942 | 28.26004 | 5.9 % | 211425 | 25882480 | +0 | 30.4 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.50311 | 0.27939 | 7.89317 | 3.7 % | 67568 | 10408048 | +0 | 30.4 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 4.13776 | 0.93623 | 5.85392 | 22.6 % | 27715 | 4078672 | +0 | 30.4 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1594.14129 | 151.37624 | 1768.06725 | 9.5 % | 11116716 | 1558379984 | +0 | 30.4 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 75.92422 | 7.82611 | 88.89638 | 10.3 % | 633459 | 102663664 | +0 | 30.4 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.83686 | 4.25700 | 28.85837 | 19.5 % | 167561 | 446577664 | -24320 | 36.9 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16727 | 0.00350 | 0.17421 | 2.1 % | 737 | 93024 | +0 | 36.9 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11303 | 0.00583 | 0.12440 | 5.2 % | 123 | 157440 | +0 | 36.9 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 9.23314 | 2.43807 | 13.18804 | 26.4 % | 67923 | 24575301 | +0 | 37.0 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 115.26645 | 10.54733 | 129.74013 | 9.2 % | 614249 | 133949067 | +0 | 40.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 108.46564 | 9.77494 | 125.06733 | 9.0 % | 560356 | 120362274 | +0 | 40.8 |
| `rayHits` | edges | 360 | 360 | 7 | 4 | 0.39127 | 0.11685 | 0.56797 | 29.9 % | 2096 | 392112 | +0 | 40.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 10.33827 | 2.41466 | 15.21658 | 23.4 % | 68952 | 11624128 | +0 | 40.9 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.50196 | 0.77695 | 17.01004 | 5.0 % | 134894 | 20360432 | +0 | 40.9 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 8.87668 | 2.78684 | 12.62150 | 31.4 % | 54839 | 7992400 | +0 | 40.9 |
| `allEdges` | edges | 720 | 720 | 4 | 1 | 6050.71690 | 217.86013 | 6329.51263 | 3.6 % | 44080847 | 6109275264 | +0 | 40.9 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 260.82215 | 14.27973 | 287.18883 | 5.5 % | 2326372 | 367698944 | +0 | 40.9 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 57.77407 | 6.31098 | 66.69163 | 10.9 % | 334258 | 888838496 | -48640 | 53.5 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.38965 | 0.08835 | 0.58735 | 22.7 % | 1457 | 127584 | +0 | 53.5 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.33786 | 0.17747 | 0.60954 | 52.5 % | 243 | 311040 | +0 | 53.5 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 26.76885 | 4.87166 | 33.53571 | 18.2 % | 135627 | 48367506 | +0 | 54.1 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 322.45031 | 34.85140 | 354.03721 | 10.8 % | 1539805 | 274719353 | +0 | 62.6 |
| `cut` | edges | 720 | 720 | 7 | 1 | 254.65006 | 45.37773 | 324.24242 | 17.8 % | 1432985 | 247784537 | +0 | 62.6 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.29201 | 0.00783 | 0.30083 | 2.7 % | 2336 | 559664 | +0 | 62.6 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 21.32251 | 5.84725 | 33.18192 | 27.4 % | 134712 | 22247488 | +0 | 62.6 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 36.33663 | 6.14457 | 49.35983 | 16.9 % | 269554 | 40496624 | +0 | 62.6 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 12.59597 | 0.68300 | 13.34700 | 5.4 % | 109093 | 15971536 | +0 | 62.6 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 19888.44935 | 1222.32283 | 21064.51217 | 6.1 % | 175482141 | 24398762544 | +0 | 62.6 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 912.81199 | 81.97625 | 1027.35833 | 9.0 % | 8885798 | 1431758592 | +0 | 62.6 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 80.99927 | 5.77208 | 89.47033 | 7.1 % | 668060 | 1775223216 | -97280 | 87.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.58257 | 0.00541 | 0.59379 | 0.9 % | 2899 | 229472 | +0 | 87.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.42246 | 0.04425 | 0.48611 | 10.5 % | 483 | 618240 | +0 | 87.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 31.33081 | 2.81484 | 36.04408 | 9.0 % | 271030 | 96173390 | +0 | 87.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 659.00647 | 50.60806 | 756.61779 | 7.7 % | 4343069 | 590735225 | +0 | 103.8 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 634.31071 | 98.48929 | 791.30083 | 15.5 % | 4130225 | 536961771 | +0 | 103.8 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.41309 | 0.03106 | 0.47227 | 7.5 % | 2816 | 894768 | +0 | 103.8 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 30.36896 | 2.02335 | 32.79808 | 6.7 % | 266270 | 44116800 | +0 | 103.8 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 48.34184 | 2.44232 | 51.78058 | 5.1 % | 478775 | 69176096 | +0 | 103.8 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.54964 | 0.01539 | 0.58278 | 2.8 % | 4013 | 309760 | +0 | 103.8 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.09276 | 0.47133 | 4.99954 | 11.5 % | 29913 | 5127328 | +0 | 103.8 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 9.40674 | 0.16076 | 9.70404 | 1.7 % | 92919 | 11590416 | +0 | 103.8 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 23.24037 | 4.27909 | 29.60304 | 18.4 % | 202372 | 22644144 | +0 | 103.8 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 51.57394 | 3.61845 | 59.69979 | 7.0 % | 486810 | 49139568 | +0 | 103.8 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 56.00812 | 1.20949 | 58.11504 | 2.2 % | 571694 | 80766512 | +0 | 103.8 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 75.08108 | 7.55787 | 86.87500 | 10.1 % | 681147 | 91820240 | +0 | 103.8 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 94.16002 | 6.49154 | 108.48829 | 6.9 % | 965585 | 118315664 | +0 | 103.8 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 19.57611 | 0.39819 | 20.47775 | 2.0 % | 202345 | 22639152 | +0 | 103.8 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 19.46354 | 0.12317 | 19.71554 | 0.6 % | 202372 | 22644144 | +0 | 103.8 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 19.69532 | 0.38894 | 20.34267 | 2.0 % | 202370 | 22640112 | +0 | 103.8 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 569.61476 | 7.32677 | 579.14233 | 1.3 % | 3554373 | 535954400 | +0 | 103.8 |

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
