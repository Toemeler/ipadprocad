# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T23:38:12Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v26 (OCCT 7.9.3) (shim v26) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.052 | [0.985, 1.119] | 0.9979 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.054 | [1.977, 2.132] | 0.9993 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.009 | [0.960, 1.058] | 0.9988 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.049 | 0.9998 | [1.028, 1.070] |
| `edgeInfo1` | edges | 4 | 1.052 | 0.9979 | [0.985, 1.119] |
| `allEdges` | edges | 4 | 2.054 | 0.9993 | [1.977, 2.132] |
| `allEdgesBulk` | edges | 4 | 1.052 | 0.9999 | [1.034, 1.069] |
| `buildOnly` | edges | 4 | 1.009 | 0.9988 | [0.960, 1.058] |
| `counts` | edges | 4 | 1.046 | 0.9977 | [0.976, 1.115] |
| `bbox` | edges | 4 | 1.014 | 1.0000 | [1.008, 1.020] |
| `mesh` | edges | 4 | 0.960 | 0.9996 | [0.934, 0.986] |
| `fuse` | edges | 4 | 1.280 | 0.9969 | [1.180, 1.380] |
| `cut` | edges | 4 | 1.299 | 0.9972 | [1.204, 1.395] |
| `rayHits` | edges | 4 | 0.304 | 0.9724 | [0.233, 0.375] |
| `filletEx1` | edges | 4 | 0.230 | 0.1153 | [-0.653, 1.113] |
| `fillet.edges` | edgesBlended | 3 | 0.610 | 0.9916 | [0.500, 0.720] |
| `fillet.scenario` | edgesBlended | 3 | 0.555 | 0.9870 | [0.430, 0.679] |
| `fillet.radius` | radius | 4 | 1.466 | 0.5975 | [-0.201, 3.133] |
| `sweep.segments` | segments | 3 | 1.160 | 0.9964 | [1.023, 1.297] |
| `sweep.legacy` | segments | 3 | 2.052 | 0.9687 | [1.329, 2.775] |
| `sweep.coil` | segments | 3 | 1.427 | 0.9688 | [0.926, 1.929] |
| `sweep.ph.build` | segments | 3 | 2.102 | 0.9682 | [1.355, 2.849] |
| `sweep.ph.unify` | segments | 3 | 1.070 | 0.9999 | [1.046, 1.093] |
| `sweep.ph.total` | segments | 3 | 2.051 | 0.9686 | [1.327, 2.775] |
| `sweep.spans` | spans | 5 | 0.371 | 0.0648 | [-1.225, 1.968] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.71978 | 0.01750 | 3.75210 | 0.5 % | 33890 | 4998046 | +0 | 10.6 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.07755 | 0.00053 | 0.07862 | 0.7 % | 821 | 150536 | +0 | 10.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 14.11245 | 0.08771 | 14.30616 | 0.6 % | 148205 | 27151530 | +0 | 10.7 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.69307 | 0.00455 | 0.70095 | 0.7 % | 6207 | 572889 | +0 | 10.7 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.69661 | 0.10578 | 10.90626 | 1.0 % | 84141 | 210178511 | -12999 | 14.8 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07380 | 0.00038 | 0.07450 | 0.5 % | 375 | 55384 | +0 | 14.8 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05488 | 0.00025 | 0.05533 | 0.5 % | 63 | 71064 | +0 | 14.8 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.48285 | 0.35872 | 5.29200 | 8.0 % | 34051 | 7904824 | +0 | 14.8 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 52.50268 | 1.35731 | 55.45705 | 2.6 % | 270361 | 61747119 | +0 | 19.4 |
| `cut` | edges | 180 | 180 | 7 | 1 | 47.38481 | 0.21673 | 47.79117 | 0.5 % | 242921 | 55317697 | +0 | 19.4 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.22733 | 0.00293 | 0.23115 | 1.3 % | 1976 | 288796 | +0 | 19.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 27.26484 | 0.07408 | 27.39141 | 0.3 % | 211444 | 24605899 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.71888 | 0.35933 | 8.52767 | 4.7 % | 67568 | 9755593 | +0 | 27.4 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.15445 | 0.00124 | 0.15664 | 0.8 % | 1601 | 255816 | +0 | 27.4 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 55.90652 | 0.59295 | 57.20632 | 1.1 % | 577205 | 92173418 | +0 | 27.4 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.44410 | 0.01546 | 1.47342 | 1.1 % | 12390 | 1116101 | +0 | 27.4 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 23.03981 | 1.03441 | 24.31276 | 4.5 % | 167656 | 415793150 | -25995 | 29.5 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16825 | 0.03602 | 0.23523 | 21.4 % | 737 | 86184 | +0 | 29.5 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11055 | 0.00035 | 0.11109 | 0.3 % | 123 | 138760 | +0 | 29.5 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.78033 | 0.05567 | 8.83275 | 0.6 % | 67916 | 14709713 | +0 | 29.5 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 113.74542 | 0.33368 | 114.40517 | 0.3 % | 614305 | 125201155 | +0 | 29.5 |
| `cut` | edges | 360 | 360 | 7 | 1 | 105.11252 | 0.27747 | 105.44147 | 0.3 % | 560422 | 112654134 | +0 | 29.5 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.26152 | 0.00528 | 0.26711 | 2.0 % | 2096 | 361129 | +0 | 29.5 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.08373 | 0.05676 | 9.16996 | 0.6 % | 68952 | 10993799 | +0 | 29.5 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.57318 | 0.05210 | 15.65513 | 0.3 % | 134894 | 19067573 | +0 | 29.5 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.30694 | 0.00399 | 0.31496 | 1.3 % | 3161 | 465993 | +0 | 29.5 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 221.36645 | 0.85486 | 222.35280 | 0.4 % | 2277605 | 335654282 | +0 | 29.5 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.92647 | 0.01736 | 2.95056 | 0.6 % | 24751 | 2170931 | +0 | 29.5 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 43.37345 | 1.67345 | 47.13766 | 3.9 % | 334430 | 827075630 | -51941 | 32.8 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.33321 | 0.07180 | 0.49446 | 21.5 % | 1457 | 114872 | +0 | 32.8 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22229 | 0.00056 | 0.22316 | 0.3 % | 243 | 274104 | +0 | 32.8 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.53099 | 0.12974 | 16.81284 | 0.8 % | 135617 | 28298776 | +0 | 32.8 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 277.28074 | 1.56788 | 279.69755 | 0.6 % | 1539877 | 260042465 | +0 | 34.5 |
| `cut` | edges | 720 | 720 | 7 | 1 | 257.86517 | 1.08671 | 259.44968 | 0.4 % | 1432884 | 235362163 | +0 | 34.5 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.31887 | 0.00243 | 0.32259 | 0.8 % | 2336 | 509035 | +0 | 34.5 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.09492 | 0.06340 | 18.22425 | 0.4 % | 134712 | 21026695 | +0 | 34.5 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 33.23832 | 0.11509 | 33.36920 | 0.3 % | 269554 | 37904882 | +0 | 34.5 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.70068 | 0.00976 | 0.71558 | 1.4 % | 6285 | 950567 | +0 | 34.5 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1027.25562 | 7.91526 | 1044.16232 | 0.8 % | 9053767 | 1369087962 | +0 | 34.5 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.22209 | 0.58015 | 7.53667 | 9.3 % | 49476 | 4347671 | +0 | 34.5 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 89.10565 | 0.58206 | 90.01647 | 0.7 % | 668604 | 1650849952 | -103934 | 43.6 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.65842 | 0.01087 | 0.66994 | 1.7 % | 2899 | 204617 | +0 | 43.6 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.45295 | 0.00377 | 0.45847 | 0.8 % | 483 | 544824 | +0 | 43.6 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.39432 | 0.50096 | 34.44504 | 1.5 % | 271017 | 55033331 | +0 | 43.6 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 750.74246 | 1.16400 | 752.07283 | 0.2 % | 4342968 | 571874381 | +0 | 48.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 707.42869 | 3.60286 | 711.27100 | 0.5 % | 4130058 | 521987921 | +0 | 48.7 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.42953 | 0.00345 | 0.43469 | 0.8 % | 2816 | 804512 | +0 | 48.7 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 36.87843 | 0.16397 | 37.13438 | 0.4 % | 266270 | 41699419 | +0 | 48.7 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.49496 | 0.02898 | 2.55519 | 1.2 % | 25307 | 4021672 | +0 | 48.7 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.74594 | 0.00307 | 0.75199 | 0.4 % | 4013 | 306408 | +0 | 48.7 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.20731 | 0.01459 | 4.22626 | 0.3 % | 29913 | 4795265 | +0 | 48.7 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.16640 | 0.10045 | 12.34249 | 0.8 % | 92923 | 10992442 | +0 | 48.7 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 25.22281 | 0.08964 | 25.37403 | 0.4 % | 202410 | 21707595 | +0 | 48.7 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 55.86262 | 0.19637 | 56.11873 | 0.4 % | 486842 | 47319390 | +0 | 48.7 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.67451 | 0.10156 | 14.88293 | 0.7 % | 118230 | 15013486 | +0 | 48.7 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 27.75037 | 0.07198 | 27.88377 | 0.3 % | 227717 | 25730175 | +0 | 48.7 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 58.83722 | 0.45354 | 59.61793 | 0.8 % | 512149 | 51341615 | +0 | 48.7 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.38698 | 0.05576 | 25.49693 | 0.2 % | 203528 | 21790206 | +0 | 48.7 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.17069 | 0.08970 | 25.34956 | 0.4 % | 202410 | 21700887 | +0 | 48.7 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.12209 | 0.07922 | 25.25465 | 0.3 % | 202365 | 21698847 | +0 | 48.7 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 750.70284 | 0.74565 | 751.98302 | 0.1 % | 3554579 | 512305345 | +0 | 48.7 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 47.28127 | 0.69050 | 48.47182 | 1.5 % | 115749 | 19928088 | +0 | 48.7 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 114.92742 | 0.22520 | 115.31152 | 0.2 % | 249465 | 61439843 | +0 | 50.5 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 236.14074 | 0.34449 | 236.73240 | 0.1 % | 526502 | 130735259 | +0 | 79.9 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 223.73636 | 0.41920 | 224.38879 | 0.2 % | 1236869 | 235578111 | +0 | 79.9 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 595.94340 | 1.06710 | 597.42038 | 0.2 % | 2634211 | 495706147 | +0 | 79.9 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3847.16447 | 6.47686 | 3858.08149 | 0.2 % | 6057816 | 1150896595 | +0 | 79.9 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 18.28466 | 0.02870 | 18.34345 | 0.2 % | 100513 | 14755357 | +0 | 79.9 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 66.87843 | 0.29545 | 67.35492 | 0.4 % | 226265 | 55180010 | +0 | 79.9 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 132.28594 | 1.03343 | 134.59722 | 0.8 % | 449824 | 104227959 | +0 | 79.9 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 31.63567 | 0.11017 | 31.81053 | 0.3 % | 287322 | 33571579 | +0 | 79.9 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 964.56727 | 1.04662 | 965.81162 | 0.1 % | 1042469 | 191355743 | +0 | 79.9 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2045.34288 | 2.06961 | 2048.53251 | 0.1 % | 2008842 | 381578514 | +0 | 79.9 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 226.94074 | 0.29676 | 227.41840 | 0.1 % | 546395 | 129695377 | +0 | 79.9 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 236.17629 | 0.34293 | 236.57288 | 0.1 % | 526502 | 130757415 | +0 | 79.9 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.10128 | 0.01586 | 0.13045 | 15.7 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01087 | 0.00326 | 0.01753 | 30.0 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3752.88012 | 3.98558 | 3757.59039 | 0.1 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 29.46118 | 0.24589 | 29.77597 | 0.8 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 60.90483 | 0.26532 | 61.29649 | 0.4 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3843.35829 | 4.03537 | 3848.32286 | 0.1 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.04079 | 0.01168 | 0.06213 | 28.6 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01132 | 0.00334 | 0.01854 | 29.5 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 203.63120 | 1.30627 | 205.57195 | 0.6 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.40556 | 0.03255 | 6.43245 | 0.5 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 13.82581 | 0.12460 | 13.99307 | 0.9 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 223.91467 | 1.21999 | 225.72165 | 0.5 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.05137 | 0.00069 | 0.05225 | 1.3 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00932 | 0.00022 | 0.00968 | 2.4 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 553.17874 | 1.32251 | 555.47235 | 0.2 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 13.60895 | 0.18689 | 13.85805 | 1.4 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 28.59900 | 0.16196 | 28.85038 | 0.6 % | n/a | n/a | n/a | 79.9 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 595.44738 | 1.55684 | 598.24095 | 0.3 % | n/a | n/a | n/a | 79.9 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3842.73688 | 5.28834 | 3853.01246 | 0.1 % | n/a | n/a | n/a | 79.9 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3751.94317 | 15.28302 | 3779.41060 | 0.4 % | n/a | n/a | n/a | 79.9 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 229.11348 | 0.51661 | 229.75939 | 0.2 % | n/a | n/a | n/a | 79.9 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 545.94135 | 1.18584 | 547.98303 | 0.2 % | n/a | n/a | n/a | 79.9 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 225.45538 | 1.43929 | 228.57821 | 0.6 % | n/a | n/a | n/a | 91.3 |

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
