# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T09:28:04Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.010 | [0.981, 1.039] | 0.9996 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.997 | [1.968, 2.026] | 0.9999 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.021 | [0.969, 1.073] | 0.9986 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.053 | 0.9971 | [0.974, 1.132] |
| `edgeInfo1` | edges | 4 | 1.010 | 0.9996 | [0.981, 1.039] |
| `allEdges` | edges | 4 | 1.997 | 0.9999 | [1.968, 2.026] |
| `allEdgesBulk` | edges | 4 | 1.057 | 0.9978 | [0.989, 1.125] |
| `buildOnly` | edges | 4 | 1.021 | 0.9986 | [0.969, 1.073] |
| `counts` | edges | 4 | 1.109 | 0.9987 | [1.054, 1.165] |
| `bbox` | edges | 4 | 1.084 | 0.9987 | [1.030, 1.137] |
| `mesh` | edges | 4 | 0.983 | 0.9999 | [0.969, 0.996] |
| `fuse` | edges | 4 | 1.286 | 0.9903 | [1.109, 1.462] |
| `cut` | edges | 4 | 1.335 | 0.9950 | [1.203, 1.466] |
| `rayHits` | edges | 4 | 0.226 | 0.8433 | [0.091, 0.361] |
| `filletEx1` | edges | 4 | 0.183 | 0.0683 | [-0.755, 1.122] |
| `fillet.edges` | edgesBlended | 3 | 0.632 | 0.9907 | [0.511, 0.752] |
| `fillet.scenario` | edgesBlended | 3 | 0.561 | 0.9856 | [0.429, 0.694] |
| `fillet.radius` | radius | 4 | 1.395 | 0.5962 | [-0.196, 2.986] |
| `sweep.segments` | segments | 3 | 1.256 | 0.9947 | [1.076, 1.436] |
| `sweep.holed` | segments | 3 | 1.071 | 0.9999 | [1.045, 1.096] |
| `sweep.legacy` | segments | 3 | 1.947 | 0.9796 | [1.396, 2.497] |
| `sweep.coil` | segments | 3 | 1.406 | 0.9789 | [1.002, 1.810] |
| `sweep.ph.build` | segments | 3 | 1.997 | 0.9785 | [1.417, 2.577] |
| `sweep.ph.unify` | segments | 3 | 1.093 | 0.9998 | [1.065, 1.121] |
| `sweep.ph.total` | segments | 3 | 1.945 | 0.9788 | [1.384, 2.506] |
| `sweep.spans` | spans | 5 | 0.259 | 0.0345 | [-1.290, 1.808] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.93222 | 0.03316 | 3.99841 | 0.8 % | 33890 | 4998073 | +0 | 10.8 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08756 | 0.00185 | 0.08948 | 2.1 % | 821 | 150488 | +0 | 10.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 17.18830 | 2.12534 | 21.94234 | 12.4 % | 148205 | 27139978 | +0 | 10.9 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.65089 | 0.03445 | 0.69740 | 5.3 % | 6207 | 572862 | +0 | 10.9 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 12.14325 | 0.26013 | 12.58531 | 2.1 % | 84141 | 210177432 | -12990 | 15.0 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08545 | 0.00031 | 0.08581 | 0.4 % | 375 | 55352 | +0 | 15.0 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.06541 | 0.00051 | 0.06653 | 0.8 % | 63 | 71064 | +0 | 15.0 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.86863 | 0.63028 | 7.04605 | 10.7 % | 34051 | 7902687 | +0 | 15.0 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 54.02286 | 1.91400 | 57.53754 | 3.5 % | 270292 | 61727983 | +0 | 19.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 44.73447 | 0.98527 | 46.26737 | 2.2 % | 242882 | 55311791 | +0 | 19.8 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25860 | 0.00217 | 0.26063 | 0.8 % | 1976 | 287499 | +0 | 19.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.88907 | 0.40451 | 30.27988 | 1.4 % | 211444 | 24608391 | +0 | 22.0 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.80159 | 0.17831 | 8.91977 | 2.0 % | 67568 | 9755623 | +0 | 22.0 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.17974 | 0.00086 | 0.18075 | 0.5 % | 1601 | 255896 | +0 | 22.0 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 65.96209 | 1.95880 | 69.69754 | 3.0 % | 577205 | 92202250 | +0 | 22.0 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.45083 | 0.00374 | 1.45649 | 0.3 % | 12390 | 1116151 | +0 | 22.0 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 24.07251 | 0.19194 | 24.44736 | 0.8 % | 167656 | 415799195 | -25989 | 24.8 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16962 | 0.00134 | 0.17254 | 0.8 % | 737 | 86360 | +0 | 24.8 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.12913 | 0.00043 | 0.12986 | 0.3 % | 123 | 138744 | +0 | 24.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 11.40707 | 0.27446 | 11.80363 | 2.4 % | 67916 | 14713155 | +0 | 24.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 103.50179 | 0.42480 | 104.41441 | 0.4 % | 614343 | 125205617 | +0 | 25.7 |
| `cut` | edges | 360 | 360 | 7 | 1 | 94.72925 | 0.28357 | 95.20574 | 0.3 % | 560348 | 112728616 | +0 | 25.7 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.25579 | 0.00123 | 0.25831 | 0.5 % | 2096 | 361283 | +0 | 25.7 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.82987 | 0.01253 | 8.85485 | 0.1 % | 68952 | 10995079 | +0 | 26.5 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.22596 | 0.03640 | 16.26187 | 0.2 % | 134894 | 19071554 | +0 | 26.5 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.34727 | 0.00165 | 0.35088 | 0.5 % | 3161 | 465960 | +0 | 26.5 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 266.45519 | 12.71071 | 288.56217 | 4.8 % | 2277605 | 335642794 | +0 | 26.5 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.04833 | 0.14025 | 3.19775 | 4.6 % | 24751 | 2170840 | +0 | 26.5 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 52.47465 | 1.41269 | 55.07003 | 2.7 % | 334430 | 827094921 | -51963 | 31.8 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.38739 | 0.00095 | 0.38937 | 0.2 % | 1457 | 114968 | +0 | 31.8 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.27912 | 0.00592 | 0.28512 | 2.1 % | 243 | 277992 | +0 | 31.8 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 23.00585 | 0.08210 | 23.07293 | 0.4 % | 135617 | 28312634 | +0 | 31.8 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 272.90558 | 13.00359 | 289.87603 | 4.8 % | 1539793 | 259944543 | +0 | 33.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 250.76819 | 11.34520 | 267.64038 | 4.5 % | 1432911 | 235407702 | +0 | 33.7 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.30727 | 0.00175 | 0.31104 | 0.6 % | 2336 | 508830 | +0 | 33.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.09285 | 0.57732 | 19.00106 | 3.2 % | 134712 | 21027045 | +0 | 33.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 36.54918 | 2.88274 | 39.83604 | 7.9 % | 269554 | 37904942 | +0 | 33.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.72515 | 0.00216 | 0.72782 | 0.3 % | 6285 | 950695 | +0 | 33.7 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1088.56536 | 22.65320 | 1126.51882 | 2.1 % | 9053767 | 1369341498 | +0 | 33.7 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 5.83876 | 0.00959 | 5.84682 | 0.2 % | 49476 | 4347705 | +0 | 33.7 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 99.12913 | 1.70509 | 102.44407 | 1.7 % | 668604 | 1650867195 | -103922 | 43.0 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.84159 | 0.02525 | 0.89509 | 3.0 % | 2899 | 204729 | +0 | 43.0 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.61881 | 0.01202 | 0.64007 | 1.9 % | 483 | 544824 | +0 | 43.0 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 44.97104 | 1.13224 | 46.87494 | 2.5 % | 271017 | 55072947 | +0 | 45.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 762.40370 | 18.12965 | 791.55755 | 2.4 % | 4342749 | 570251806 | +0 | 51.8 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 706.16181 | 15.67009 | 739.59848 | 2.2 % | 4130182 | 521251698 | +0 | 51.8 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.40993 | 0.00182 | 0.41291 | 0.4 % | 2816 | 804503 | +0 | 51.8 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 35.95016 | 1.11543 | 38.11208 | 3.1 % | 266270 | 41698030 | +0 | 51.8 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.81445 | 0.01777 | 2.85413 | 0.6 % | 25307 | 4021274 | +0 | 51.8 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.67087 | 0.00222 | 0.67553 | 0.3 % | 4013 | 303528 | +0 | 51.8 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.90630 | 0.07071 | 4.05529 | 1.8 % | 29913 | 4795274 | +0 | 51.8 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.57214 | 0.04635 | 11.64519 | 0.4 % | 92923 | 10994218 | +0 | 51.8 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 24.46691 | 0.11938 | 24.70676 | 0.5 % | 202410 | 21702142 | +0 | 53.3 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 56.15541 | 0.15708 | 56.42018 | 0.3 % | 486842 | 47296699 | +0 | 53.3 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.42568 | 0.03802 | 14.46944 | 0.3 % | 118230 | 15007520 | +0 | 53.3 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 27.30361 | 0.12480 | 27.57753 | 0.5 % | 227717 | 25740456 | +0 | 53.3 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 58.87337 | 0.07292 | 58.99332 | 0.1 % | 512149 | 51327315 | +0 | 53.3 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 24.71129 | 0.32476 | 25.42358 | 1.3 % | 203528 | 21785134 | +0 | 53.3 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 24.38902 | 0.06670 | 24.51921 | 0.3 % | 202410 | 21701266 | +0 | 53.3 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 24.33327 | 0.06056 | 24.45894 | 0.2 % | 202365 | 21692847 | +0 | 53.3 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 620.96966 | 0.65136 | 621.99111 | 0.1 % | 3554579 | 512452721 | +0 | 54.4 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 30.97614 | 0.12765 | 31.21702 | 0.4 % | 115749 | 19923777 | +0 | 54.4 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 82.61850 | 4.31795 | 88.77497 | 5.2 % | 249465 | 61441681 | +0 | 54.4 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 176.77462 | 3.74060 | 182.29337 | 2.1 % | 526502 | 130753559 | +0 | 82.9 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 73.03267 | 0.67049 | 73.88455 | 0.9 % | 228967 | 53740797 | +0 | 83.1 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 155.80093 | 0.75822 | 157.33630 | 0.5 % | 484408 | 132868485 | +0 | 87.3 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 322.17366 | 1.30531 | 324.40157 | 0.4 % | 1025529 | 277128856 | +0 | 149.8 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 205.50602 | 1.54937 | 208.52821 | 0.8 % | 1236869 | 235586566 | +0 | 149.8 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 565.32624 | 2.17996 | 570.01167 | 0.4 % | 2634211 | 495700691 | +0 | 149.8 |
| `sweep.legacy` | segments | 128 | 4224 | 7 | 1 | 3053.42902 | 29.66796 | 3104.61477 | 1.0 % | 6057816 | 1150894110 | +0 | 149.8 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 13.91646 | 0.03406 | 13.95465 | 0.2 % | 100513 | 14756225 | +0 | 149.8 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 47.23760 | 0.25984 | 47.64799 | 0.6 % | 226265 | 55175389 | +0 | 149.8 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 97.72069 | 0.89768 | 98.69696 | 0.9 % | 449824 | 104238167 | +0 | 149.8 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 30.83900 | 0.04828 | 30.92838 | 0.2 % | 287322 | 33582073 | +0 | 149.8 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 739.53998 | 26.69382 | 775.99801 | 3.6 % | 1042469 | 191403990 | +0 | 149.8 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1571.75783 | 44.96605 | 1645.72815 | 2.9 % | 2008842 | 381631166 | +0 | 149.8 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 158.10507 | 1.67851 | 161.20167 | 1.1 % | 546395 | 129683889 | +0 | 149.8 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 163.45967 | 0.79407 | 165.01798 | 0.5 % | 526502 | 130738258 | +0 | 149.8 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.09761 | 0.00803 | 0.11336 | 8.2 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.01079 | 0.00044 | 0.01130 | 4.0 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 2923.45073 | 59.32009 | 3040.60654 | 2.0 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 27.64254 | 0.91907 | 29.25267 | 3.3 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 64.18836 | 1.60020 | 67.77521 | 2.5 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 3015.39003 | 59.73183 | 3131.23821 | 2.0 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.04491 | 0.02830 | 0.10781 | 63.0 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01220 | 0.00304 | 0.01809 | 24.9 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 183.50659 | 2.94194 | 189.64456 | 1.6 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 5.73961 | 0.04273 | 5.80452 | 0.7 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 14.10479 | 0.10990 | 14.34563 | 0.8 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 203.40811 | 3.08267 | 209.87198 | 1.5 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.05927 | 0.00838 | 0.07101 | 14.1 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.01091 | 0.00173 | 0.01480 | 15.8 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 513.54907 | 6.48018 | 528.07269 | 1.3 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 12.27713 | 0.06400 | 12.33145 | 0.5 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 29.58341 | 0.19921 | 29.84340 | 0.7 % | n/a | n/a | n/a | 149.8 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 555.47980 | 6.40805 | 569.82211 | 1.2 % | n/a | n/a | n/a | 149.8 |
| `sweep.var.v23poly` | segments | 128 | 0 | 7 | 1 | 3002.23657 | 43.05782 | 3079.57148 | 1.4 % | n/a | n/a | n/a | 149.8 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2954.48697 | 65.38410 | 3060.59882 | 2.2 % | n/a | n/a | n/a | 152.7 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 218.09989 | 0.38649 | 218.65005 | 0.2 % | n/a | n/a | n/a | 152.7 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 465.57523 | 0.91960 | 467.15352 | 0.2 % | n/a | n/a | n/a | 152.7 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 164.06952 | 8.09517 | 181.36705 | 4.9 % | n/a | n/a | n/a | 152.7 |

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
- `sweep.segments` (x=32): occt_sweep_profile against profile segment count — 32 segments x 16 spans, 34 faces, volume 6742.2918
- `sweep.segments` (x=64): occt_sweep_profile against profile segment count — 64 segments x 16 spans, 66 faces, volume 6774.9148
- `sweep.segments` (x=128): occt_sweep_profile against profile segment count — 128 segments x 16 spans, 130 faces, volume 6783.0853
- `sweep.holed` (x=32): occt_sweep_profile with one hole — v27 assembles it, v26 cut it out with a boolean — 32 segments x 16 spans, 66 faces, volume 5056.7198
- `sweep.holed` (x=64): occt_sweep_profile with one hole — v27 assembles it, v26 cut it out with a boolean — 64 segments x 16 spans, 130 faces, volume 5081.1870
- `sweep.holed` (x=128): occt_sweep_profile with one hole — v27 assembles it, v26 cut it out with a boolean — 128 segments x 16 spans, 258 faces, volume 5087.3149
- `sweep.legacy` (x=32): occt_sweep_profile_ex with OCCT_SWEEP_PATH_POLY — the v23 polyline spine, every joint mitered — 32 segments x 16 spans, 512 faces, volume 6742.3215
- `sweep.legacy` (x=64): occt_sweep_profile_ex with OCCT_SWEEP_PATH_POLY — the v23 polyline spine, every joint mitered — 64 segments x 16 spans, 1026 faces, volume 6774.9447
- `sweep.legacy` (x=128): occt_sweep_profile_ex with OCCT_SWEEP_PATH_POLY — the v23 polyline spine, every joint mitered — 128 segments x 16 spans, 2050 faces, volume 6783.1153
- `sweep.coil` (x=32): occt_coil_profile — same section, same quarter turn of radius 18 rising 60, but the spine is one analytic helix edge instead of a polyline sample of it — 32 segments, 34 faces, volume 7453.4671
- `sweep.coil` (x=64): occt_coil_profile — same section, same quarter turn of radius 18 rising 60, but the spine is one analytic helix edge instead of a polyline sample of it — 64 segments, 66 faces, volume 7489.5313
- `sweep.coil` (x=128): occt_coil_profile — same section, same quarter turn of radius 18 rising 60, but the spine is one analytic helix edge instead of a polyline sample of it — 128 segments, 130 faces, volume 7498.5636
- `sweep.spans` (x=1): occt_sweep_profile against path span count — 128 segments x 1 spans, 130 faces, volume 6783.1153
- `sweep.spans` (x=2): occt_sweep_profile against path span count — 128 segments x 2 spans, 258 faces, volume 6783.1153
- `sweep.spans` (x=4): occt_sweep_profile against path span count — 128 segments x 4 spans, 514 faces, volume 6783.1153
- `sweep.spans` (x=8): occt_sweep_profile against path span count — 128 segments x 8 spans, 130 faces, volume 6782.5695
- `sweep.spans` (x=16): occt_sweep_profile against path span count — 128 segments x 16 spans, 130 faces, volume 6783.0853
- `sweep.ph.wire` (x=128): the v23 pipeline, phase by phase — 128 seg x 16 spans, 2050 faces, spine edges 16, volume 6783.115299, valid
- `sweep.ph.spine` (x=128): the v23 pipeline, phase by phase — 128 seg x 16 spans, 2050 faces, spine edges 16, volume 6783.115299, valid
- `sweep.ph.build` (x=128): the v23 pipeline, phase by phase — 128 seg x 16 spans, 2050 faces, spine edges 16, volume 6783.115299, valid
- `sweep.ph.solid` (x=128): the v23 pipeline, phase by phase — 128 seg x 16 spans, 2050 faces, spine edges 16, volume 6783.115299, valid
- `sweep.ph.unify` (x=128): the v23 pipeline, phase by phase — 128 seg x 16 spans, 2050 faces, spine edges 16, volume 6783.115299, valid
- `sweep.ph.total` (x=128): the v23 pipeline, phase by phase — 128 seg x 16 spans, 2050 faces, spine edges 16, volume 6783.115299, valid
- `sweep.ph.wire` (x=32): the v23 pipeline, phase by phase — 32 seg x 16 spans, 512 faces, spine edges 16, volume 6742.321529, valid
- `sweep.ph.spine` (x=32): the v23 pipeline, phase by phase — 32 seg x 16 spans, 512 faces, spine edges 16, volume 6742.321529, valid
- `sweep.ph.build` (x=32): the v23 pipeline, phase by phase — 32 seg x 16 spans, 512 faces, spine edges 16, volume 6742.321529, valid
- `sweep.ph.solid` (x=32): the v23 pipeline, phase by phase — 32 seg x 16 spans, 512 faces, spine edges 16, volume 6742.321529, valid
- `sweep.ph.unify` (x=32): the v23 pipeline, phase by phase — 32 seg x 16 spans, 512 faces, spine edges 16, volume 6742.321529, valid
- `sweep.ph.total` (x=32): the v23 pipeline, phase by phase — 32 seg x 16 spans, 512 faces, spine edges 16, volume 6742.321529, valid
- `sweep.ph.wire` (x=64): the v23 pipeline, phase by phase — 64 seg x 16 spans, 1026 faces, spine edges 16, volume 6774.944740, valid
- `sweep.ph.spine` (x=64): the v23 pipeline, phase by phase — 64 seg x 16 spans, 1026 faces, spine edges 16, volume 6774.944740, valid
- `sweep.ph.build` (x=64): the v23 pipeline, phase by phase — 64 seg x 16 spans, 1026 faces, spine edges 16, volume 6774.944740, valid
- `sweep.ph.solid` (x=64): the v23 pipeline, phase by phase — 64 seg x 16 spans, 1026 faces, spine edges 16, volume 6774.944740, valid
- `sweep.ph.unify` (x=64): the v23 pipeline, phase by phase — 64 seg x 16 spans, 1026 faces, spine edges 16, volume 6774.944740, valid
- `sweep.ph.total` (x=64): the v23 pipeline, phase by phase — 64 seg x 16 spans, 1026 faces, spine edges 16, volume 6774.944740, valid
- `sweep.var.v23poly` (x=128): RightCorner, polyline spine, UnifySameDomain — the v23 pipeline, which is what OCCT_SWEEP_PATH_POLY still selects — 2050 faces, spine edges 16, volume 6783.115299 (+0.0000 % vs the v23 pipeline), valid
- `sweep.var.noUnify` (x=128): the v23 pipeline WITHOUT the closing UnifySameDomain — 2050 faces, spine edges 16, volume 6783.115299 (+0.0000 % vs the v23 pipeline), valid
- `sweep.var.transformed` (x=128): BRepBuilderAPI_Transformed — no corner trimming at all — 2050 faces, spine edges 16, volume 6783.115299 (+0.0000 % vs the v23 pipeline), valid
- `sweep.var.deadband` (x=128): RightCorner with OCCT's own angmin deadband raised to 5 deg, so shallow joints are not treated as corners — 2050 faces, spine edges 16, volume 8982.628131 (+32.4263 % vs the v23 pipeline), INVALID
- `sweep.var.smoothSpine` (x=128): a C2 B-spline interpolated through the same path points — one spine edge, so no joints to treat — 130 faces, spine edges 1, volume 6783.085827 (-0.0004 % vs the v23 pipeline), valid
