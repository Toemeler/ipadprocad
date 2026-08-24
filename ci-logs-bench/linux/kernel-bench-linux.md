# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T16:56:50Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v26 (OCCT 7.9.3) (shim v26) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.071 | [1.022, 1.121] | 0.9989 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.062 | [1.991, 2.132] | 0.9994 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.035 | [1.007, 1.063] | 0.9996 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.055 | 0.9997 | [1.030, 1.081] |
| `edgeInfo1` | edges | 4 | 1.071 | 0.9989 | [1.022, 1.121] |
| `allEdges` | edges | 4 | 2.062 | 0.9994 | [1.991, 2.132] |
| `allEdgesBulk` | edges | 4 | 1.032 | 0.9999 | [1.022, 1.042] |
| `buildOnly` | edges | 4 | 1.035 | 0.9996 | [1.007, 1.063] |
| `counts` | edges | 4 | 1.045 | 0.9988 | [0.994, 1.096] |
| `bbox` | edges | 4 | 1.019 | 0.9997 | [0.995, 1.042] |
| `mesh` | edges | 4 | 0.995 | 0.9997 | [0.970, 1.019] |
| `fuse` | edges | 4 | 1.305 | 0.9974 | [1.212, 1.398] |
| `cut` | edges | 4 | 1.298 | 0.9970 | [1.199, 1.397] |
| `rayHits` | edges | 4 | 0.251 | 0.8405 | [0.099, 0.402] |
| `filletEx1` | edges | 4 | 0.233 | 0.1187 | [-0.647, 1.113] |
| `fillet.edges` | edgesBlended | 3 | 0.616 | 0.9929 | [0.514, 0.719] |
| `fillet.scenario` | edgesBlended | 3 | 0.553 | 0.9890 | [0.439, 0.668] |
| `fillet.radius` | radius | 4 | 1.462 | 0.5979 | [-0.200, 3.125] |
| `sweep.segments` | segments | 3 | 1.169 | 0.9959 | [1.021, 1.317] |
| `sweep.legacy` | segments | 3 | 2.063 | 0.9705 | [1.357, 2.768] |
| `sweep.coil` | segments | 3 | 1.427 | 0.9680 | [0.918, 1.935] |
| `sweep.ph.build` | segments | 3 | 2.106 | 0.9699 | [1.379, 2.833] |
| `sweep.ph.unify` | segments | 3 | 1.222 | 0.9978 | [1.111, 1.333] |
| `sweep.ph.total` | segments | 3 | 2.058 | 0.9705 | [1.354, 2.761] |
| `sweep.spans` | spans | 5 | 0.381 | 0.0681 | [-1.214, 1.977] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.74609 | 0.03287 | 3.81084 | 0.9 % | 33890 | 4998112 | +0 | 10.7 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.07682 | 0.00025 | 0.07716 | 0.3 % | 821 | 150488 | +0 | 10.8 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 14.22800 | 0.20669 | 14.66872 | 1.5 % | 148205 | 27137082 | +0 | 10.8 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.70495 | 0.00301 | 0.70928 | 0.4 % | 6207 | 572828 | +0 | 10.8 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.78629 | 0.14138 | 11.10024 | 1.3 % | 84141 | 210179048 | -13003 | 14.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07461 | 0.00020 | 0.07497 | 0.3 % | 375 | 55376 | +0 | 14.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05510 | 0.00031 | 0.05576 | 0.6 % | 63 | 71064 | +0 | 14.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.34291 | 0.04920 | 4.45301 | 1.1 % | 34051 | 7907135 | +0 | 14.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 51.91651 | 0.08092 | 52.04739 | 0.2 % | 270309 | 61741567 | +0 | 19.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 48.56908 | 2.30608 | 53.79158 | 4.7 % | 242879 | 55318602 | +0 | 19.7 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.27012 | 0.07355 | 0.42678 | 27.2 % | 1976 | 287972 | +0 | 19.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 27.33840 | 0.13254 | 27.56541 | 0.5 % | 211444 | 24605623 | +0 | 22.1 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.56162 | 0.02252 | 7.60820 | 0.3 % | 67568 | 9755680 | +0 | 22.1 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.15562 | 0.00111 | 0.15718 | 0.7 % | 1601 | 255736 | +0 | 22.1 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 56.02912 | 0.03942 | 56.10697 | 0.1 % | 577205 | 92167594 | +0 | 22.1 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.46191 | 0.00715 | 1.47265 | 0.5 % | 12390 | 1116278 | +0 | 22.1 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.37889 | 1.08509 | 23.83162 | 5.1 % | 167656 | 415803079 | -25984 | 25.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14732 | 0.00078 | 0.14855 | 0.5 % | 737 | 86120 | +0 | 25.1 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11090 | 0.00029 | 0.11151 | 0.3 % | 123 | 138744 | +0 | 25.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.36524 | 0.06158 | 8.44193 | 0.7 % | 67916 | 14712159 | +0 | 25.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 115.56472 | 0.77251 | 117.01555 | 0.7 % | 614220 | 125221906 | +0 | 25.7 |
| `cut` | edges | 360 | 360 | 7 | 1 | 106.94459 | 0.41612 | 107.62445 | 0.4 % | 560387 | 112685677 | +0 | 25.7 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.26255 | 0.00608 | 0.27032 | 2.3 % | 2096 | 360925 | +0 | 25.7 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.18225 | 0.04968 | 9.25193 | 0.5 % | 68952 | 11034926 | +0 | 26.6 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.72303 | 0.06295 | 15.81381 | 0.4 % | 134894 | 19067630 | +0 | 26.6 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.31925 | 0.00803 | 0.33391 | 2.5 % | 3161 | 465976 | +0 | 26.6 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 227.58988 | 1.23836 | 228.51286 | 0.5 % | 2277605 | 335665818 | +0 | 26.6 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.97388 | 0.02806 | 3.03197 | 0.9 % | 24751 | 2170904 | +0 | 26.6 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 43.92132 | 0.45030 | 44.52796 | 1.0 % | 334430 | 827096533 | -52000 | 32.0 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.29891 | 0.00446 | 0.30819 | 1.5 % | 1457 | 114872 | +0 | 32.0 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23156 | 0.00060 | 0.23249 | 0.3 % | 243 | 274104 | +0 | 32.0 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.87808 | 0.19680 | 17.22237 | 1.2 % | 135617 | 28309167 | +0 | 32.0 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 285.68434 | 3.04618 | 289.66805 | 1.1 % | 1539753 | 260025710 | +0 | 36.9 |
| `cut` | edges | 720 | 720 | 7 | 1 | 262.61773 | 1.55813 | 265.13584 | 0.6 % | 1432861 | 235272143 | +0 | 36.9 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.33096 | 0.00141 | 0.33349 | 0.4 % | 2336 | 509261 | +0 | 36.9 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.23856 | 0.06364 | 18.32721 | 0.3 % | 134712 | 21025344 | +0 | 36.9 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 33.60801 | 0.26564 | 34.12827 | 0.8 % | 269554 | 37904974 | +0 | 36.9 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.71838 | 0.01531 | 0.74767 | 2.1 % | 6285 | 950744 | +0 | 36.9 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1044.40542 | 6.28689 | 1058.45573 | 0.6 % | 9053767 | 1369341546 | +0 | 38.5 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.03618 | 0.01863 | 6.06333 | 0.3 % | 49476 | 4347682 | +0 | 38.5 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 92.67482 | 6.54566 | 102.22329 | 7.1 % | 668604 | 1650858066 | -103963 | 44.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.65922 | 0.01770 | 0.68268 | 2.7 % | 2899 | 204761 | +0 | 44.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.45373 | 0.00083 | 0.45519 | 0.2 % | 483 | 544824 | +0 | 44.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.21665 | 0.38702 | 34.84943 | 1.1 % | 271017 | 55025919 | +0 | 44.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 783.01553 | 15.99725 | 816.97495 | 2.0 % | 4342925 | 571345913 | +0 | 47.9 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 722.00034 | 11.31540 | 741.28016 | 1.6 % | 4130005 | 521932209 | +0 | 47.9 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.44635 | 0.00533 | 0.45441 | 1.2 % | 2816 | 804613 | +0 | 47.9 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.25299 | 0.19713 | 37.49310 | 0.5 % | 266270 | 41705707 | +0 | 47.9 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.53368 | 0.02341 | 2.58059 | 0.9 % | 25307 | 4014122 | +0 | 47.9 |
| `volume` | edges | 72 | 72 | 7 | 2 | 0.75302 | 0.00827 | 0.76808 | 1.1 % | 4013 | 303080 | +0 | 47.9 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.21060 | 0.01378 | 4.22575 | 0.3 % | 29913 | 4793327 | +0 | 47.9 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.17873 | 0.06075 | 12.25002 | 0.5 % | 92923 | 10991537 | +0 | 47.9 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 25.69218 | 0.21541 | 26.02234 | 0.8 % | 202410 | 21700078 | +0 | 47.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 56.82166 | 0.26653 | 57.22922 | 0.5 % | 486842 | 47291360 | +0 | 47.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.87481 | 0.06489 | 14.96459 | 0.4 % | 118230 | 14996517 | +0 | 47.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 28.39402 | 0.27903 | 28.81005 | 1.0 % | 227717 | 25704765 | +0 | 47.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 59.41864 | 0.33283 | 60.11453 | 0.6 % | 512149 | 51302799 | +0 | 47.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.81227 | 0.06582 | 25.91016 | 0.3 % | 203528 | 21782450 | +0 | 47.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.59985 | 0.07608 | 25.75387 | 0.3 % | 202410 | 21702949 | +0 | 47.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.57912 | 0.10057 | 25.68999 | 0.4 % | 202365 | 21689814 | +0 | 47.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 757.62784 | 2.22001 | 761.49895 | 0.3 % | 3554579 | 512416387 | +0 | 47.9 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 47.01300 | 0.31630 | 47.71502 | 0.7 % | 115749 | 19931133 | +0 | 48.2 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 115.72972 | 0.80355 | 117.45595 | 0.7 % | 249465 | 61436413 | +0 | 49.8 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 237.74275 | 0.96039 | 239.73420 | 0.4 % | 526502 | 130769081 | +0 | 79.2 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 225.02185 | 1.09601 | 226.52078 | 0.5 % | 1236869 | 235594737 | +0 | 79.2 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 610.27746 | 11.05852 | 629.77636 | 1.8 % | 2634211 | 495691539 | +0 | 79.2 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3926.46815 | 47.99298 | 3992.62310 | 1.2 % | 6057816 | 1150900117 | +0 | 79.2 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 18.21853 | 0.04026 | 18.25518 | 0.2 % | 100513 | 14756127 | +0 | 79.2 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 66.86321 | 0.25871 | 67.41244 | 0.4 % | 226265 | 55176536 | +0 | 79.2 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 131.63294 | 0.26098 | 131.88457 | 0.2 % | 449824 | 104231326 | +0 | 79.2 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 31.48127 | 0.15040 | 31.76736 | 0.5 % | 287322 | 33576117 | +0 | 79.2 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 967.93121 | 2.36862 | 972.72276 | 0.2 % | 1042469 | 191396947 | +0 | 79.2 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2061.14091 | 7.80038 | 2074.26492 | 0.4 % | 2008842 | 381690914 | +0 | 79.2 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 234.83662 | 13.56148 | 265.50521 | 5.8 % | 546395 | 129684968 | +0 | 79.2 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 239.60612 | 2.69129 | 245.17334 | 1.1 % | 526502 | 130724192 | +0 | 79.2 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.10447 | 0.00958 | 0.11713 | 9.2 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01074 | 0.00236 | 0.01556 | 22.0 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3846.82267 | 38.97763 | 3885.96820 | 1.0 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 36.91977 | 3.59298 | 41.04950 | 9.7 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 77.31321 | 8.70506 | 85.85310 | 11.3 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3961.17087 | 49.22346 | 4003.86265 | 1.2 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.04102 | 0.00758 | 0.04855 | 18.5 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01149 | 0.00323 | 0.01838 | 28.1 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 207.45285 | 3.08294 | 212.86452 | 1.5 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.79042 | 0.35436 | 7.48826 | 5.2 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 14.21049 | 0.34942 | 14.82168 | 2.5 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 228.50628 | 3.70925 | 235.23164 | 1.6 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.06821 | 0.00877 | 0.08798 | 12.9 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.01014 | 0.00197 | 0.01456 | 19.4 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 572.31734 | 2.37282 | 576.11408 | 0.4 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 14.95444 | 0.65365 | 16.33833 | 4.4 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 30.96216 | 2.91182 | 37.52651 | 9.4 % | n/a | n/a | n/a | 79.2 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 618.31229 | 4.48210 | 627.30908 | 0.7 % | n/a | n/a | n/a | 79.2 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3966.95510 | 16.24974 | 3992.45676 | 0.4 % | n/a | n/a | n/a | 79.2 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3905.71039 | 23.73786 | 3949.86181 | 0.6 % | n/a | n/a | n/a | 79.2 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 249.77897 | 3.96930 | 254.24571 | 1.6 % | n/a | n/a | n/a | 79.2 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 579.31767 | 4.30438 | 586.36354 | 0.7 % | n/a | n/a | n/a | 79.2 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 227.63186 | 1.39460 | 230.67650 | 0.6 % | n/a | n/a | n/a | 86.3 |

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
