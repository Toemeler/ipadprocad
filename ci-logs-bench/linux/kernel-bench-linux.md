# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T13:59:20Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v24 (OCCT 7.9.3) (shim v24) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.047 | [1.008, 1.085] | 0.9993 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.047 | [2.004, 2.089] | 0.9998 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.007 | [0.991, 1.024] | 0.9999 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.077 | 0.9991 | [1.031, 1.122] |
| `edgeInfo1` | edges | 4 | 1.047 | 0.9993 | [1.008, 1.085] |
| `allEdges` | edges | 4 | 2.047 | 0.9998 | [2.004, 2.089] |
| `allEdgesBulk` | edges | 4 | 1.062 | 0.9981 | [0.998, 1.126] |
| `buildOnly` | edges | 4 | 1.007 | 0.9999 | [0.991, 1.024] |
| `counts` | edges | 4 | 0.994 | 0.9999 | [0.978, 1.011] |
| `bbox` | edges | 4 | 0.996 | 1.0000 | [0.990, 1.002] |
| `mesh` | edges | 4 | 0.980 | 0.9997 | [0.958, 1.001] |
| `fuse` | edges | 4 | 1.340 | 0.9970 | [1.239, 1.441] |
| `cut` | edges | 4 | 1.356 | 0.9972 | [1.256, 1.456] |
| `rayHits` | edges | 4 | 0.288 | 0.9649 | [0.212, 0.364] |
| `filletEx1` | edges | 4 | 0.212 | 0.0988 | [-0.675, 1.099] |
| `fillet.edges` | edgesBlended | 3 | 0.631 | 0.9905 | [0.509, 0.752] |
| `fillet.scenario` | edgesBlended | 3 | 0.566 | 0.9849 | [0.428, 0.703] |
| `fillet.radius` | radius | 4 | 1.401 | 0.5980 | [-0.191, 2.993] |
| `sweep.segments` | segments | 3 | 1.187 | 0.9956 | [1.033, 1.342] |
| `sweep.legacy` | segments | 3 | 1.914 | 0.9794 | [1.370, 2.457] |
| `sweep.coil` | segments | 3 | 1.390 | 0.9726 | [0.932, 1.847] |
| `sweep.ph.build` | segments | 3 | 1.960 | 0.9794 | [1.403, 2.517] |
| `sweep.ph.unify` | segments | 3 | 1.095 | 0.9993 | [1.039, 1.151] |
| `sweep.ph.total` | segments | 3 | 1.909 | 0.9796 | [1.370, 2.449] |
| `sweep.spans` | spans | 5 | 0.281 | 0.0441 | [-1.199, 1.761] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 5.01569 | 0.03575 | 5.07735 | 0.7 % | 33890 | 4998016 | +0 | 10.8 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.11226 | 0.00099 | 0.11335 | 0.9 % | 821 | 150488 | +0 | 10.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 20.33276 | 0.06340 | 20.45964 | 0.3 % | 148205 | 27139994 | +0 | 10.9 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.88739 | 0.00361 | 0.89415 | 0.4 % | 6207 | 572862 | +0 | 10.9 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 14.36027 | 0.27557 | 14.82822 | 1.9 % | 84141 | 210177562 | -12994 | 14.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.11970 | 0.00019 | 0.12011 | 0.2 % | 375 | 55384 | +0 | 14.7 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.08881 | 0.00079 | 0.08965 | 0.9 % | 63 | 71064 | +0 | 14.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.90104 | 0.06271 | 5.98775 | 1.1 % | 34051 | 7904518 | +0 | 14.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 63.36513 | 0.37947 | 63.94417 | 0.6 % | 270379 | 61755562 | +0 | 19.7 |
| `cut` | edges | 180 | 180 | 7 | 1 | 57.30307 | 0.18185 | 57.50976 | 0.3 % | 242949 | 55328607 | +0 | 19.7 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.32049 | 0.00213 | 0.32457 | 0.7 % | 1976 | 287747 | +0 | 19.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 37.67227 | 0.25375 | 38.00820 | 0.7 % | 211444 | 24607134 | +0 | 22.0 |
| `build` | edges | 360 | 360 | 7 | 1 | 11.31875 | 0.03789 | 11.38651 | 0.3 % | 67568 | 9755705 | +0 | 22.0 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.24559 | 0.00067 | 0.24670 | 0.3 % | 1601 | 255800 | +0 | 22.0 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 89.34153 | 0.54984 | 90.57211 | 0.6 % | 577205 | 92173386 | +0 | 22.0 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 2.03401 | 0.00787 | 2.04559 | 0.4 % | 12390 | 1116192 | +0 | 22.0 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 28.16248 | 0.21969 | 28.56184 | 0.8 % | 167656 | 415805435 | -25993 | 24.7 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.23958 | 0.00072 | 0.24112 | 0.3 % | 737 | 86152 | +0 | 24.7 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.17783 | 0.00208 | 0.17976 | 1.2 % | 123 | 138744 | +0 | 24.7 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 11.53960 | 0.13596 | 11.68848 | 1.2 % | 67916 | 14724911 | +0 | 24.7 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 143.94780 | 0.54111 | 144.87444 | 0.4 % | 614257 | 125222797 | +0 | 30.9 |
| `cut` | edges | 360 | 360 | 7 | 1 | 131.50125 | 0.51879 | 132.19082 | 0.4 % | 560370 | 112655699 | +0 | 30.9 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.36227 | 0.00199 | 0.36584 | 0.5 % | 2096 | 361407 | +0 | 30.9 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 12.34142 | 0.02500 | 12.37350 | 0.2 % | 68952 | 10996130 | +0 | 31.8 |
| `build` | edges | 720 | 720 | 7 | 1 | 22.96468 | 0.07858 | 23.11909 | 0.3 % | 134894 | 19067728 | +0 | 31.8 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.48448 | 0.00101 | 0.48627 | 0.2 % | 3161 | 466072 | +0 | 31.8 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 350.45302 | 1.05961 | 352.83331 | 0.3 % | 2277605 | 335723482 | +0 | 31.8 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.06263 | 0.00850 | 4.07456 | 0.2 % | 24751 | 2170973 | +0 | 31.8 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 57.65608 | 0.30883 | 58.23949 | 0.5 % | 334430 | 827088315 | -51947 | 34.6 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.46723 | 0.00063 | 0.46832 | 0.1 % | 1457 | 115096 | +0 | 34.6 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.35148 | 0.00329 | 0.35540 | 0.9 % | 243 | 274104 | +0 | 34.6 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 23.42292 | 0.26424 | 23.96700 | 1.1 % | 135617 | 28280351 | +0 | 34.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 361.67989 | 1.13165 | 364.08509 | 0.3 % | 1539769 | 260184830 | +0 | 34.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 335.21598 | 0.91160 | 336.62468 | 0.3 % | 1432912 | 235269989 | +0 | 34.7 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.43711 | 0.00395 | 0.44561 | 0.9 % | 2336 | 509070 | +0 | 34.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 24.26655 | 0.06320 | 24.38328 | 0.3 % | 134712 | 21026944 | +0 | 34.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 47.66823 | 0.08139 | 47.74638 | 0.2 % | 269554 | 37904971 | +0 | 34.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 2 | 1.00474 | 0.00427 | 1.01094 | 0.4 % | 6285 | 950711 | +0 | 34.7 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1458.64157 | 14.21566 | 1490.86118 | 1.0 % | 9053767 | 1369318506 | +0 | 34.7 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 8.19741 | 0.02270 | 8.22661 | 0.3 % | 49476 | 4347845 | +0 | 34.7 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 115.94265 | 1.12575 | 117.91630 | 1.0 % | 668604 | 1650871646 | -103867 | 45.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.95344 | 0.00546 | 0.96077 | 0.6 % | 2899 | 204777 | +0 | 45.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.70660 | 0.00360 | 0.71026 | 0.5 % | 483 | 544824 | +0 | 45.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 44.81615 | 0.44677 | 45.60491 | 1.0 % | 271017 | 55022047 | +0 | 45.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1030.22890 | 5.36130 | 1039.38456 | 0.5 % | 4342893 | 570841582 | +0 | 50.3 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 962.05997 | 4.10666 | 968.07446 | 0.4 % | 4130160 | 520746559 | +0 | 50.3 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 0.58513 | 0.00344 | 0.58852 | 0.6 % | 2816 | 804968 | +0 | 50.3 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 49.06841 | 0.18693 | 49.30594 | 0.4 % | 266270 | 41701397 | +0 | 50.3 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 3.93383 | 0.00683 | 3.94560 | 0.2 % | 25307 | 4013944 | +0 | 50.3 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.91627 | 0.00433 | 0.92583 | 0.5 % | 4013 | 302664 | +0 | 50.3 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.50464 | 0.01391 | 5.52800 | 0.3 % | 29913 | 4795384 | +0 | 50.3 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 16.32244 | 0.12264 | 16.52805 | 0.8 % | 92923 | 10991695 | +0 | 50.3 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 34.42637 | 0.07979 | 34.53852 | 0.2 % | 202410 | 21702791 | +0 | 52.0 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 79.06106 | 0.14691 | 79.23086 | 0.2 % | 486842 | 47302014 | +0 | 52.0 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 20.19102 | 0.10320 | 20.40428 | 0.5 % | 118230 | 15021179 | +0 | 52.0 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 38.26397 | 0.10367 | 38.43983 | 0.3 % | 227717 | 25738051 | +0 | 52.0 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 83.30282 | 0.67917 | 84.67086 | 0.8 % | 512149 | 51316031 | +0 | 52.0 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 34.50613 | 0.11355 | 34.71799 | 0.3 % | 203528 | 21785209 | +0 | 52.0 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 34.37647 | 0.10997 | 34.55072 | 0.3 % | 202410 | 21703909 | +0 | 52.0 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 34.23095 | 0.07784 | 34.38254 | 0.2 % | 202365 | 21695455 | +0 | 52.0 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 879.76995 | 0.77242 | 881.10121 | 0.1 % | 3554579 | 512358211 | +0 | 53.0 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 45.03852 | 0.08091 | 45.15579 | 0.2 % | 115749 | 19930749 | +0 | 53.0 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 112.76774 | 0.37770 | 113.23863 | 0.3 % | 249465 | 61445496 | +0 | 53.0 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 233.59584 | 0.36542 | 234.25717 | 0.2 % | 526502 | 130748969 | +0 | 81.7 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 277.17721 | 1.00300 | 278.46725 | 0.4 % | 1236869 | 235607480 | +0 | 81.7 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 748.50627 | 5.36818 | 757.22512 | 0.7 % | 2634211 | 495740515 | +0 | 81.7 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3934.85658 | 13.91022 | 3948.27601 | 0.4 % | 6057816 | 1150764216 | +0 | 81.7 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 20.35864 | 0.53491 | 21.51566 | 2.6 % | 100513 | 14758122 | +0 | 81.7 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 70.58558 | 0.17180 | 70.77804 | 0.2 % | 226265 | 55174536 | +0 | 81.7 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 139.77170 | 0.74849 | 141.19924 | 0.5 % | 449824 | 104228965 | +0 | 81.7 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 43.40429 | 0.04264 | 43.46523 | 0.1 % | 287322 | 33585733 | +0 | 81.7 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 923.26571 | 2.47571 | 927.70226 | 0.3 % | 1042469 | 191372635 | +0 | 83.8 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1946.28678 | 2.83874 | 1949.57702 | 0.1 % | 2008842 | 381695865 | +0 | 83.8 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 223.14018 | 0.30903 | 223.59446 | 0.1 % | 546395 | 129695663 | +0 | 83.8 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 233.78828 | 0.32021 | 234.29818 | 0.1 % | 526502 | 130756667 | +0 | 83.8 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.14476 | 0.02032 | 0.18621 | 14.0 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01945 | 0.00508 | 0.02673 | 26.1 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3819.63892 | 7.25905 | 3829.26625 | 0.2 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 39.48762 | 3.10374 | 45.57004 | 7.9 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 88.73253 | 3.43145 | 94.54997 | 3.9 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3948.02328 | 11.48000 | 3964.44335 | 0.3 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.04478 | 0.00678 | 0.05428 | 15.1 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01737 | 0.00242 | 0.02135 | 13.9 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 252.21193 | 1.57255 | 253.99944 | 0.6 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 8.08222 | 0.09240 | 8.16983 | 1.1 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 19.44657 | 0.05735 | 19.54358 | 0.3 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 279.80286 | 1.61076 | 281.60116 | 0.6 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.08790 | 0.01229 | 0.11271 | 14.0 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.01629 | 0.00158 | 0.01981 | 9.7 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 697.74520 | 8.06319 | 710.62073 | 1.2 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 17.18702 | 0.15590 | 17.42597 | 0.9 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 40.13424 | 0.55512 | 40.94482 | 1.4 % | n/a | n/a | n/a | 83.8 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 755.17065 | 8.14215 | 767.61080 | 1.1 % | n/a | n/a | n/a | 83.8 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3948.77962 | 15.62311 | 3968.46025 | 0.4 % | n/a | n/a | n/a | 83.8 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3819.54787 | 11.80840 | 3831.55933 | 0.3 % | n/a | n/a | n/a | 83.8 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 311.97655 | 2.63973 | 316.77793 | 0.8 % | n/a | n/a | n/a | 83.8 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 652.70487 | 4.18346 | 660.53039 | 0.6 % | n/a | n/a | n/a | 89.9 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 223.87072 | 0.43771 | 224.77094 | 0.2 % | n/a | n/a | n/a | 94.6 |

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
