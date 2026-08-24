# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T14:14:08Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v24 (OCCT 7.9.3) (shim v24) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.031 | [0.640, 1.422] | 0.9302 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.988 | [1.797, 2.179] | 0.9952 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.119 | [0.697, 1.540] | 0.9312 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.048 | 0.9784 | [0.832, 1.264] |
| `edgeInfo1` | edges | 4 | 1.031 | 0.9302 | [0.640, 1.422] |
| `allEdges` | edges | 4 | 1.988 | 0.9952 | [1.797, 2.179] |
| `allEdgesBulk` | edges | 4 | 1.416 | 0.9174 | [0.828, 2.005] |
| `buildOnly` | edges | 4 | 1.119 | 0.9312 | [0.697, 1.540] |
| `counts` | edges | 4 | 1.127 | 0.8954 | [0.593, 1.660] |
| `bbox` | edges | 4 | 0.850 | 0.9864 | [0.712, 0.989] |
| `mesh` | edges | 4 | 1.072 | 0.9954 | [0.971, 1.173] |
| `fuse` | edges | 4 | 1.389 | 0.9904 | [1.199, 1.578] |
| `cut` | edges | 4 | 1.376 | 0.9950 | [1.241, 1.512] |
| `rayHits` | edges | 4 | 0.311 | 0.9575 | [0.220, 0.402] |
| `filletEx1` | edges | 4 | 0.151 | 0.0667 | [-0.632, 0.935] |
| `fillet.edges` | edgesBlended | 3 | 0.452 | 0.7317 | [-0.084, 0.988] |
| `fillet.scenario` | edgesBlended | 3 | 0.552 | 0.9901 | [0.444, 0.660] |
| `fillet.radius` | radius | 4 | 1.421 | 0.6414 | [-0.052, 2.893] |
| `sweep.segments` | segments | 3 | 1.162 | 0.9959 | [1.015, 1.308] |
| `sweep.legacy` | segments | 3 | 1.896 | 0.9633 | [1.171, 2.621] |
| `sweep.coil` | segments | 3 | 1.314 | 0.9992 | [1.239, 1.389] |
| `sweep.ph.build` | segments | 3 | 1.913 | 0.9812 | [1.394, 2.432] |
| `sweep.ph.unify` | segments | 3 | 1.030 | 0.9986 | [0.954, 1.105] |
| `sweep.ph.total` | segments | 3 | 1.850 | 0.9803 | [1.336, 2.363] |
| `sweep.spans` | spans | 5 | 0.208 | 0.0297 | [-1.134, 1.549] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 5.23951 | 1.71961 | 8.01108 | 32.8 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.10431 | 0.02644 | 0.16047 | 25.3 % | 821 | 158368 | +0 | 14.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 25.81384 | 4.93873 | 34.13575 | 19.1 % | 148205 | 28566976 | +0 | 14.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 1.25292 | 0.52373 | 2.08146 | 41.8 % | 6209 | 596032 | +0 | 14.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 16.15492 | 4.17774 | 23.45938 | 25.9 % | 84071 | 225974848 | -12160 | 22.4 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.12963 | 0.03454 | 0.19124 | 26.6 % | 375 | 59360 | +0 | 22.4 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.07362 | 0.01459 | 0.09244 | 19.8 % | 63 | 80640 | +0 | 22.4 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.34365 | 0.73429 | 6.63246 | 13.7 % | 34056 | 13154158 | +0 | 22.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 57.16220 | 6.42928 | 68.98733 | 11.2 % | 270298 | 66603403 | +0 | 27.9 |
| `cut` | edges | 180 | 180 | 7 | 1 | 52.76397 | 7.31383 | 66.29242 | 13.9 % | 242896 | 59653986 | +0 | 27.9 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.25912 | 0.06088 | 0.35478 | 23.5 % | 1976 | 308336 | +0 | 27.9 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 33.25018 | 7.82017 | 46.60258 | 23.5 % | 211425 | 25882480 | +0 | 29.3 |
| `build` | edges | 360 | 360 | 7 | 1 | 9.76324 | 2.32578 | 13.76875 | 23.8 % | 67568 | 10408048 | +0 | 29.3 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.23691 | 0.13608 | 0.53505 | 57.4 % | 1601 | 269728 | +0 | 29.3 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 77.22827 | 8.95282 | 92.40188 | 11.6 % | 577205 | 97204096 | +0 | 29.3 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.70024 | 0.55730 | 2.95442 | 32.8 % | 12392 | 1160128 | +0 | 29.3 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 34.44876 | 4.77189 | 43.74479 | 13.9 % | 167561 | 446577664 | -24320 | 35.8 |
| `counts` | edges | 360 | 360 | 7 | 8 | 0.36069 | 0.08385 | 0.52001 | 23.2 % | 737 | 93024 | +0 | 35.8 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.16330 | 0.05029 | 0.23367 | 30.8 % | 123 | 157440 | +0 | 35.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 11.10112 | 2.97018 | 17.16400 | 26.8 % | 67923 | 24575301 | +0 | 35.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 160.48732 | 29.26345 | 209.68054 | 18.2 % | 614289 | 133957259 | +0 | 39.7 |
| `cut` | edges | 360 | 360 | 7 | 1 | 142.20714 | 18.66992 | 177.72842 | 13.1 % | 560330 | 120357008 | +0 | 39.7 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.34940 | 0.14170 | 0.63522 | 40.6 % | 2096 | 392112 | +0 | 39.7 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 13.27398 | 4.49929 | 20.22962 | 33.9 % | 68952 | 11624128 | +0 | 39.9 |
| `build` | edges | 720 | 720 | 7 | 1 | 27.20017 | 4.60589 | 36.73188 | 16.9 % | 134894 | 20360432 | +0 | 39.9 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 2 | 0.69381 | 0.33074 | 1.21498 | 47.7 % | 3161 | 492448 | +0 | 39.9 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 355.18952 | 38.03682 | 401.91050 | 10.7 % | 2277605 | 354747136 | +0 | 39.9 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.66441 | 1.46041 | 6.66971 | 31.3 % | 24753 | 2255552 | +0 | 39.9 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 47.28376 | 3.45101 | 53.48933 | 7.3 % | 334258 | 888838496 | -48640 | 52.5 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.37931 | 0.06272 | 0.46788 | 16.5 % | 1457 | 127584 | +0 | 52.5 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.25960 | 0.03387 | 0.31784 | 13.0 % | 243 | 311040 | +0 | 52.5 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 21.02712 | 2.90600 | 25.25929 | 13.8 % | 135627 | 48367506 | +0 | 52.5 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 326.65080 | 14.67752 | 342.50117 | 4.5 % | 1539812 | 274720816 | +0 | 60.9 |
| `cut` | edges | 720 | 720 | 7 | 1 | 310.13746 | 21.45541 | 333.45096 | 6.9 % | 1433021 | 247770750 | +0 | 60.9 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.44451 | 0.12836 | 0.65268 | 28.9 % | 2336 | 559664 | +0 | 60.9 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.92865 | 2.74166 | 24.62067 | 14.5 % | 134712 | 22247488 | +0 | 60.9 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 41.95820 | 3.62593 | 46.73442 | 8.6 % | 269554 | 40496624 | +0 | 60.9 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.78929 | 0.14199 | 1.05211 | 18.0 % | 6285 | 1003424 | +0 | 60.9 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1533.65949 | 128.22885 | 1673.90429 | 8.4 % | 9053767 | 1445313024 | +0 | 60.9 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 23.61236 | 6.80247 | 35.60554 | 28.8 % | 49478 | 4511936 | +0 | 60.9 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 192.81980 | 68.31197 | 340.84408 | 35.4 % | 668060 | 1775223216 | -97280 | 85.0 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 1.72163 | 0.32944 | 2.04456 | 19.1 % | 2899 | 229472 | +0 | 85.0 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.45007 | 0.02324 | 0.49749 | 5.2 % | 483 | 618240 | +0 | 85.0 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 51.43057 | 7.87156 | 65.14721 | 15.3 % | 271030 | 96173390 | +0 | 86.0 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1116.45323 | 59.49524 | 1196.65621 | 5.3 % | 4343118 | 590745319 | +0 | 102.2 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 978.14946 | 55.63463 | 1027.02875 | 5.7 % | 4130071 | 536930320 | +0 | 102.2 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 0.49087 | 0.12717 | 0.75754 | 25.9 % | 2816 | 894768 | +0 | 102.2 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 41.89375 | 3.42237 | 46.95779 | 8.2 % | 266270 | 44116800 | +0 | 102.2 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 4.53116 | 1.54544 | 7.39721 | 34.1 % | 25307 | 4253072 | +0 | 102.2 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.72878 | 0.11913 | 0.93686 | 16.3 % | 4013 | 309760 | +0 | 102.2 |
| `valid` | edges | 72 | 72 | 7 | 1 | 7.07134 | 2.31508 | 11.66958 | 32.7 % | 29913 | 5127328 | +0 | 102.2 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 30.73967 | 31.16816 | 99.19567 | 101.4 % | 92919 | 11590416 | +0 | 102.2 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 32.65210 | 6.34449 | 42.21708 | 19.4 % | 202372 | 22644144 | +0 | 102.2 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 98.86893 | 55.69596 | 222.95583 | 56.3 % | 486810 | 49139568 | +0 | 102.2 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 23.83184 | 2.80905 | 27.82800 | 11.8 % | 118226 | 15843488 | +0 | 102.2 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 45.68629 | 9.43153 | 60.24146 | 20.6 % | 227679 | 26897216 | +0 | 102.2 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 94.79401 | 21.18688 | 139.67242 | 22.4 % | 512117 | 53392640 | +0 | 102.2 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 33.89823 | 4.66414 | 40.22521 | 13.8 % | 202345 | 22639152 | +0 | 102.2 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 53.50578 | 35.29440 | 119.45200 | 66.0 % | 202372 | 22644144 | +0 | 102.2 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 41.18442 | 9.19956 | 55.18637 | 22.3 % | 202370 | 22640112 | +0 | 102.2 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 985.60855 | 158.95638 | 1225.51296 | 16.1 % | 3554373 | 535954400 | +0 | 102.2 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 53.81285 | 2.92996 | 56.28817 | 5.4 % | 115765 | 20752032 | +0 | 102.2 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 131.66761 | 19.22756 | 170.64742 | 14.6 % | 249401 | 63466032 | +0 | 102.2 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 269.29330 | 22.49826 | 318.65971 | 8.4 % | 526495 | 134945888 | +0 | 105.3 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 302.48757 | 13.79079 | 328.83075 | 4.6 % | 1236848 | 249935056 | +0 | 105.5 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 721.93007 | 62.77758 | 827.93296 | 8.7 % | 2634121 | 524105264 | +0 | 105.6 |
| `sweep.legacy` | segments | 128 | 4224 | 5 | 1 | 4188.46282 | 173.88164 | 4384.03754 | 4.2 % | 6057892 | 1210486000 | +0 | 107.8 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 24.51682 | 2.67524 | 27.56200 | 10.9 % | 100529 | 15713552 | +0 | 108.5 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 63.83689 | 4.69056 | 69.77942 | 7.3 % | 210352 | 47931248 | +0 | 109.6 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 151.60321 | 14.70723 | 179.14271 | 9.7 % | 449873 | 107867264 | +0 | 112.5 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 70.73226 | 59.16552 | 204.02754 | 83.6 % | 287370 | 34951712 | +0 | 112.5 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 1058.97486 | 102.12857 | 1204.13258 | 9.6 % | 1042546 | 198791584 | +0 | 121.3 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2088.11427 | 81.51885 | 2248.84125 | 3.9 % | 2008917 | 403883408 | +0 | 121.3 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 257.97012 | 20.45610 | 297.87750 | 7.9 % | 546392 | 133805120 | +0 | 121.9 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 294.29679 | 12.50370 | 310.41817 | 4.2 % | 526495 | 134945888 | +0 | 121.9 |
| `sweep.ph.wire` | segments | 128 | 0 | 5 | 1 | 0.07778 | 0.00669 | 0.08513 | 8.6 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.spine` | segments | 128 | 0 | 5 | 1 | 0.00812 | 0.00105 | 0.00942 | 13.0 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.build` | segments | 128 | 0 | 5 | 1 | 4221.54438 | 155.89851 | 4409.93746 | 3.7 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.solid` | segments | 128 | 0 | 5 | 1 | 37.80764 | 9.77657 | 53.65054 | 25.9 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.unify` | segments | 128 | 0 | 5 | 1 | 102.32936 | 10.18581 | 120.02425 | 10.0 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.total` | segments | 128 | 0 | 5 | 1 | 4361.76728 | 152.42474 | 4545.17967 | 3.5 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.03796 | 0.02072 | 0.08471 | 54.6 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01005 | 0.00665 | 0.02513 | 66.2 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 297.73886 | 11.87842 | 318.18017 | 4.0 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 13.35686 | 7.93989 | 29.99125 | 59.4 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 24.55473 | 6.01723 | 34.83117 | 24.5 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 335.69846 | 20.14107 | 368.36654 | 6.0 % | n/a | n/a | n/a | 140.8 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.07820 | 0.05144 | 0.17463 | 65.8 % | n/a | n/a | n/a | 140.9 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00996 | 0.00529 | 0.02175 | 53.1 % | n/a | n/a | n/a | 140.9 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 815.84806 | 38.61223 | 899.98517 | 4.7 % | n/a | n/a | n/a | 140.9 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 19.76234 | 4.83239 | 27.06063 | 24.5 % | n/a | n/a | n/a | 140.9 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 47.85385 | 7.16234 | 59.71542 | 15.0 % | n/a | n/a | n/a | 140.9 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 883.55241 | 38.02339 | 963.89367 | 4.3 % | n/a | n/a | n/a | 140.9 |
| `sweep.var.v23poly` | segments | 128 | 0 | 5 | 1 | 4215.17214 | 90.51214 | 4367.70704 | 2.1 % | n/a | n/a | n/a | 140.9 |
| `sweep.var.noUnify` | segments | 128 | 0 | 5 | 1 | 4257.41493 | 234.56451 | 4632.95063 | 5.5 % | n/a | n/a | n/a | 140.9 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 326.28539 | 11.21618 | 343.71246 | 3.4 % | n/a | n/a | n/a | 141.0 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 748.09840 | 74.29518 | 880.82983 | 9.9 % | n/a | n/a | n/a | 142.7 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 279.44259 | 16.92010 | 308.77342 | 6.1 % | n/a | n/a | n/a | 149.5 |

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
