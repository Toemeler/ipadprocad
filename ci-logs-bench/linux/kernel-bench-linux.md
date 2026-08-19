# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-19T18:29:36Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v21 (OCCT 7.9.3) (shim v21) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.027 | [1.014, 1.041] | 0.9999 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.021 | [2.004, 2.038] | 1.0000 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.005 | [0.985, 1.025] | 0.9998 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.061 | 0.9998 | [1.039, 1.083] |
| `edgeInfo1` | edges | 4 | 1.027 | 0.9999 | [1.014, 1.041] |
| `allEdges` | edges | 4 | 2.021 | 1.0000 | [2.004, 2.038] |
| `allEdgesBulk` | edges | 4 | 1.909 | 0.9995 | [1.849, 1.969] |
| `buildOnly` | edges | 4 | 1.005 | 0.9998 | [0.985, 1.025] |
| `counts` | edges | 4 | 1.049 | 0.9989 | [1.002, 1.097] |
| `bbox` | edges | 4 | 0.993 | 0.9995 | [0.961, 1.024] |
| `mesh` | edges | 4 | 0.971 | 0.9999 | [0.956, 0.986] |
| `fuse` | edges | 4 | 1.280 | 0.9971 | [1.184, 1.377] |
| `cut` | edges | 4 | 1.299 | 0.9977 | [1.212, 1.385] |
| `rayHits` | edges | 4 | 0.296 | 0.9412 | [0.193, 0.398] |
| `filletEx1` | edges | 4 | 0.229 | 0.1170 | [-0.644, 1.103] |
| `fillet.edges` | edgesBlended | 3 | 0.617 | 0.9911 | [0.502, 0.731] |
| `fillet.scenario` | edgesBlended | 3 | 0.195 | 0.9432 | [0.101, 0.289] |
| `fillet.radius` | radius | 4 | 1.463 | 0.5983 | [-0.198, 3.124] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 2.90589 | 0.01502 | 2.92978 | 0.5 % | 33890 | 4998110 | +0 | 10.5 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 2 | 1.25145 | 0.00477 | 1.25956 | 0.4 % | 14153 | 1997024 | +0 | 11.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 248.71018 | 0.47616 | 249.68372 | 0.2 % | 2838089 | 381660568 | +0 | 12.1 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 16.82987 | 0.09274 | 17.02939 | 0.6 % | 184678 | 29391262 | +0 | 12.1 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 8.41652 | 0.07436 | 8.55068 | 0.9 % | 84141 | 210179887 | -12997 | 15.6 |
| `counts` | edges | 180 | 180 | 7 | 64 | 0.05875 | 0.00015 | 0.05893 | 0.2 % | 375 | 55320 | +0 | 15.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.04517 | 0.00007 | 0.04527 | 0.1 % | 63 | 71064 | +0 | 15.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 3.41642 | 0.06146 | 3.54791 | 1.8 % | 34051 | 7905446 | +0 | 15.6 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 40.75640 | 0.35045 | 41.24049 | 0.9 % | 270346 | 61736319 | +0 | 19.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 36.91239 | 0.14674 | 37.10030 | 0.4 % | 242948 | 55310201 | +0 | 19.8 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.17919 | 0.00328 | 0.18586 | 1.8 % | 1976 | 288036 | +0 | 19.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 21.43960 | 0.14620 | 21.74781 | 0.7 % | 211444 | 24606864 | +0 | 22.0 |
| `build` | edges | 360 | 360 | 7 | 1 | 5.95362 | 0.03191 | 6.01487 | 0.5 % | 67568 | 9761221 | +0 | 22.0 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 1 | 2.60013 | 0.02326 | 2.65064 | 0.9 % | 27715 | 3818511 | +0 | 22.0 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 1034.77488 | 8.85886 | 1054.48475 | 0.9 % | 11116716 | 1463532992 | +0 | 22.0 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 58.67167 | 0.35116 | 59.13845 | 0.6 % | 633716 | 97682162 | +0 | 22.0 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 16.40144 | 0.18754 | 16.81158 | 1.1 % | 167656 | 415788425 | -25998 | 24.7 |
| `counts` | edges | 360 | 360 | 7 | 32 | 0.11681 | 0.00029 | 0.11721 | 0.3 % | 737 | 86040 | +0 | 24.7 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.08869 | 0.00310 | 0.09570 | 3.5 % | 123 | 138744 | +0 | 24.7 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 6.56537 | 0.04867 | 6.66334 | 0.7 % | 67916 | 14718182 | +0 | 24.7 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 88.81576 | 0.20751 | 89.08549 | 0.2 % | 614245 | 125183775 | +0 | 25.7 |
| `cut` | edges | 360 | 360 | 7 | 1 | 82.05647 | 0.14426 | 82.27489 | 0.2 % | 560356 | 112667568 | +0 | 25.7 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.20225 | 0.00332 | 0.20746 | 1.6 % | 2096 | 361200 | +0 | 25.7 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 7.25024 | 0.04153 | 7.31063 | 0.6 % | 68952 | 10996014 | +0 | 26.7 |
| `build` | edges | 720 | 720 | 7 | 1 | 12.30906 | 0.12160 | 12.57392 | 1.0 % | 134894 | 19067669 | +0 | 26.7 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 1 | 5.25232 | 0.06308 | 5.37470 | 1.2 % | 54839 | 7481846 | +0 | 26.7 |
| `allEdges` | edges | 720 | 720 | 5 | 1 | 4142.57808 | 10.20907 | 4160.19190 | 0.2 % | 44080847 | 5736574811 | +0 | 26.7 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 222.93172 | 1.27935 | 225.51245 | 0.6 % | 2326870 | 350723559 | +0 | 26.7 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 33.39323 | 0.17925 | 33.63552 | 0.5 % | 334430 | 827077152 | -51979 | 31.6 |
| `counts` | edges | 720 | 720 | 7 | 16 | 0.23773 | 0.00188 | 0.24137 | 0.8 % | 1457 | 114952 | +0 | 31.6 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.17220 | 0.00033 | 0.17258 | 0.2 % | 243 | 274104 | +0 | 31.6 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 12.95170 | 0.10226 | 13.15930 | 0.8 % | 135617 | 28306785 | +0 | 31.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 215.95500 | 0.76745 | 217.49674 | 0.4 % | 1539729 | 260208752 | +0 | 33.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 203.29131 | 3.71566 | 210.72394 | 1.8 % | 1432991 | 235157079 | +0 | 33.7 |
| `rayHits` | edges | 720 | 720 | 7 | 16 | 0.23860 | 0.00362 | 0.24439 | 1.5 % | 2336 | 508841 | +0 | 33.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 14.29353 | 0.08434 | 14.43848 | 0.6 % | 134712 | 21026567 | +0 | 33.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 26.46601 | 0.31048 | 27.05933 | 1.2 % | 269554 | 37905015 | +0 | 33.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 10.63144 | 0.08245 | 10.79332 | 0.8 % | 109093 | 14942607 | +0 | 33.7 |
| `allEdges` | edges | 1440 | 1440 | 3 | 1 | 16698.12338 | 31.31914 | 16723.81764 | 0.2 % | 175482141 | 22895800323 | +0 | 38.7 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 887.98450 | 2.56157 | 890.78532 | 0.3 % | 8886777 | 1369798755 | +0 | 38.7 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 67.70538 | 0.51704 | 68.50336 | 0.8 % | 668604 | 1650871465 | -103890 | 45.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.52386 | 0.00716 | 0.52917 | 1.4 % | 2899 | 204809 | +0 | 45.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.35887 | 0.00264 | 0.36480 | 0.7 % | 483 | 544824 | +0 | 45.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 25.69686 | 0.24830 | 25.94555 | 1.0 % | 271017 | 55005098 | +0 | 45.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 583.71601 | 2.84826 | 587.56982 | 0.5 % | 4342710 | 571097891 | +0 | 48.9 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 548.18001 | 2.16482 | 551.71244 | 0.4 % | 4129959 | 522584133 | +0 | 48.9 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.33605 | 0.00313 | 0.33958 | 0.9 % | 2816 | 804667 | +0 | 48.9 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 29.04867 | 0.11024 | 29.20490 | 0.4 % | 266270 | 41710731 | +0 | 48.9 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 44.68821 | 0.15631 | 44.99496 | 0.3 % | 478775 | 64891688 | +0 | 48.9 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.58338 | 0.00110 | 0.58503 | 0.2 % | 4013 | 303448 | +0 | 48.9 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.30573 | 0.01085 | 3.32091 | 0.3 % | 29913 | 4795055 | +0 | 48.9 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 9.54303 | 0.07340 | 9.70215 | 0.8 % | 92923 | 10992911 | +0 | 48.9 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 19.88806 | 0.07902 | 20.03785 | 0.4 % | 202410 | 21702203 | +0 | 50.4 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 44.62039 | 0.14682 | 44.83046 | 0.3 % | 486842 | 47299131 | +0 | 50.4 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 54.61320 | 0.25125 | 55.08292 | 0.5 % | 571698 | 75927735 | +0 | 50.4 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 64.82264 | 0.20257 | 65.06721 | 0.3 % | 681185 | 86613165 | +0 | 50.4 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 89.37938 | 0.22497 | 89.82805 | 0.3 % | 965617 | 112223027 | +0 | 50.4 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 19.98825 | 0.05077 | 20.07513 | 0.3 % | 203528 | 21792423 | +0 | 50.4 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 19.89965 | 0.11679 | 20.09100 | 0.6 % | 202410 | 21705790 | +0 | 50.4 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 19.84831 | 0.13904 | 20.13384 | 0.7 % | 202365 | 21696723 | +0 | 50.4 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 587.39240 | 0.87244 | 589.15191 | 0.1 % | 3554579 | 512445654 | +0 | 51.4 |

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
