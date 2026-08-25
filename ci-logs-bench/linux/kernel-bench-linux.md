# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T07:39:51Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.052 | [1.017, 1.087] | 0.9994 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.028 | [2.001, 2.054] | 0.9999 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.007 | [0.975, 1.040] | 0.9994 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.076 | 0.9991 | [1.032, 1.121] |
| `edgeInfo1` | edges | 4 | 1.052 | 0.9994 | [1.017, 1.087] |
| `allEdges` | edges | 4 | 2.028 | 0.9999 | [2.001, 2.054] |
| `allEdgesBulk` | edges | 4 | 1.069 | 0.9978 | [1.000, 1.138] |
| `buildOnly` | edges | 4 | 1.007 | 0.9994 | [0.975, 1.040] |
| `counts` | edges | 4 | 0.833 | 0.9693 | [0.627, 1.038] |
| `bbox` | edges | 4 | 0.994 | 1.0000 | [0.986, 1.002] |
| `mesh` | edges | 4 | 0.983 | 0.9999 | [0.974, 0.993] |
| `fuse` | edges | 4 | 1.336 | 0.9973 | [1.239, 1.433] |
| `cut` | edges | 4 | 1.356 | 0.9973 | [1.259, 1.453] |
| `rayHits` | edges | 4 | 0.289 | 0.9555 | [0.203, 0.376] |
| `filletEx1` | edges | 4 | 0.211 | 0.0992 | [-0.672, 1.094] |
| `fillet.edges` | edgesBlended | 3 | 0.632 | 0.9898 | [0.506, 0.757] |
| `fillet.scenario` | edgesBlended | 3 | 0.563 | 0.9849 | [0.426, 0.700] |
| `fillet.radius` | radius | 4 | 1.409 | 0.6002 | [-0.185, 3.003] |
| `sweep.segments` | segments | 3 | 1.115 | 0.9991 | [1.049, 1.180] |
| `sweep.holed` | segments | 3 | 1.114 | 0.9985 | [1.028, 1.200] |
| `sweep.legacy` | segments | 3 | 1.912 | 0.9778 | [1.347, 2.477] |
| `sweep.coil` | segments | 3 | 1.409 | 0.9714 | [0.935, 1.883] |
| `sweep.ph.build` | segments | 3 | 1.959 | 0.9774 | [1.375, 2.543] |
| `sweep.ph.unify` | segments | 3 | 1.063 | 0.9999 | [1.042, 1.084] |
| `sweep.ph.total` | segments | 3 | 1.907 | 0.9778 | [1.344, 2.471] |
| `sweep.spans` | spans | 5 | 0.277 | 0.0428 | [-1.206, 1.760] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.99643 | 0.02218 | 5.02171 | 0.4 % | 33890 | 4998071 | +0 | 10.9 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.11287 | 0.00047 | 0.11371 | 0.4 % | 821 | 151496 | +0 | 11.1 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 21.37575 | 1.73910 | 24.94930 | 8.1 % | 148205 | 27217754 | +0 | 11.1 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.88406 | 0.00115 | 0.88557 | 0.1 % | 6207 | 573321 | +0 | 11.1 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 14.48395 | 0.71286 | 16.00085 | 4.9 % | 84141 | 210179574 | -13019 | 15.2 |
| `counts` | edges | 180 | 180 | 7 | 16 | 0.17773 | 0.00859 | 0.18316 | 4.8 % | 375 | 55368 | +0 | 15.2 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.08877 | 0.00058 | 0.08994 | 0.7 % | 63 | 71064 | +0 | 15.2 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.78791 | 0.07277 | 5.91538 | 1.3 % | 34051 | 7901000 | +0 | 15.2 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 63.90276 | 1.65288 | 67.51519 | 2.6 % | 270363 | 61746983 | +0 | 19.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 57.62217 | 0.28949 | 58.15064 | 0.5 % | 242891 | 55307597 | +0 | 19.5 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.32300 | 0.00232 | 0.32632 | 0.7 % | 1976 | 287936 | +0 | 19.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 37.32476 | 0.12815 | 37.57523 | 0.3 % | 211444 | 24604064 | +0 | 21.9 |
| `build` | edges | 360 | 360 | 7 | 1 | 11.27064 | 0.02430 | 11.31047 | 0.2 % | 67568 | 9755810 | +0 | 21.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.24544 | 0.00044 | 0.24594 | 0.2 % | 1601 | 255816 | +0 | 21.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 89.79647 | 0.53834 | 90.96413 | 0.6 % | 577205 | 92179178 | +0 | 21.9 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 2.05190 | 0.01330 | 2.07534 | 0.6 % | 12390 | 1116139 | +0 | 21.9 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 27.88730 | 0.17181 | 28.18869 | 0.6 % | 167656 | 415801296 | -26014 | 24.8 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.23684 | 0.00013 | 0.23710 | 0.1 % | 737 | 86248 | +0 | 24.8 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.17498 | 0.00025 | 0.17535 | 0.1 % | 123 | 138744 | +0 | 24.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 11.30423 | 0.12151 | 11.56983 | 1.1 % | 67916 | 14721793 | +0 | 24.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 144.74903 | 0.32888 | 145.37815 | 0.2 % | 614278 | 125206058 | +0 | 25.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 132.38832 | 0.29215 | 132.97507 | 0.2 % | 560344 | 112645318 | +0 | 25.8 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.35688 | 0.00235 | 0.36211 | 0.7 % | 2096 | 360994 | +0 | 25.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 12.27993 | 0.03208 | 12.32976 | 0.3 % | 68952 | 10996213 | +0 | 26.7 |
| `build` | edges | 720 | 720 | 7 | 1 | 22.78050 | 0.13777 | 23.08250 | 0.6 % | 134894 | 19067611 | +0 | 26.7 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.48499 | 0.00083 | 0.48631 | 0.2 % | 3161 | 466041 | +0 | 26.7 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 352.00792 | 0.20876 | 352.39335 | 0.1 % | 2277605 | 335677386 | +0 | 26.7 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.09307 | 0.01515 | 4.11502 | 0.4 % | 24751 | 2170984 | +0 | 26.7 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 56.68775 | 0.36122 | 57.14981 | 0.6 % | 334430 | 827098457 | -51966 | 31.4 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.47360 | 0.00088 | 0.47479 | 0.2 % | 1457 | 114952 | +0 | 31.4 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.34919 | 0.00206 | 0.35379 | 0.6 % | 243 | 274104 | +0 | 31.4 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 22.67458 | 0.12925 | 22.88207 | 0.6 % | 135617 | 28286669 | +0 | 31.4 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 365.51933 | 1.31312 | 367.06391 | 0.4 % | 1539706 | 260101355 | +0 | 33.8 |
| `cut` | edges | 720 | 720 | 7 | 1 | 338.40713 | 1.21084 | 340.21038 | 0.4 % | 1433066 | 235169194 | +0 | 33.8 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.43891 | 0.00328 | 0.44421 | 0.7 % | 2336 | 508869 | +0 | 33.8 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 24.14429 | 0.03177 | 24.18982 | 0.1 % | 134712 | 21026823 | +0 | 33.8 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 47.52675 | 0.08579 | 47.65016 | 0.2 % | 269554 | 37904944 | +0 | 33.8 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 2 | 1.02192 | 0.00757 | 1.03485 | 0.7 % | 6285 | 950714 | +0 | 33.8 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1468.90482 | 8.09663 | 1486.45758 | 0.6 % | 9053767 | 1369318410 | +0 | 33.8 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 8.29870 | 0.04171 | 8.36204 | 0.5 % | 49476 | 4347785 | +0 | 33.8 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 117.22462 | 0.42471 | 118.01020 | 0.4 % | 668604 | 1650840825 | -103943 | 43.4 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.96654 | 0.00422 | 0.97491 | 0.4 % | 2899 | 204665 | +0 | 43.4 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.70076 | 0.00717 | 0.71658 | 1.0 % | 483 | 544824 | +0 | 43.4 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 44.52221 | 0.46629 | 45.50319 | 1.0 % | 271017 | 54967000 | +0 | 43.7 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1028.66764 | 4.29504 | 1036.35438 | 0.4 % | 4343126 | 570161370 | +0 | 50.3 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 966.54994 | 3.22034 | 971.94382 | 0.3 % | 4130102 | 521258063 | +0 | 50.3 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 0.58844 | 0.00166 | 0.59136 | 0.3 % | 2816 | 804580 | +0 | 50.3 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 48.55537 | 0.32939 | 49.24289 | 0.7 % | 266270 | 41695888 | +0 | 50.3 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 3.94108 | 0.00685 | 3.95314 | 0.2 % | 25307 | 4045480 | +0 | 50.3 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.91820 | 0.00223 | 0.92189 | 0.2 % | 4013 | 302696 | +0 | 50.3 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.52883 | 0.01670 | 5.56224 | 0.3 % | 29913 | 4796472 | +0 | 50.3 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 16.24648 | 0.04234 | 16.32340 | 0.3 % | 92923 | 10993032 | +0 | 50.3 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 34.16409 | 0.08323 | 34.26666 | 0.2 % | 202410 | 21701602 | +0 | 51.7 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 78.89132 | 0.09398 | 79.07308 | 0.1 % | 486842 | 47298071 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 20.17344 | 0.02363 | 20.20359 | 0.1 % | 118230 | 15020919 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 38.12432 | 0.05382 | 38.18336 | 0.1 % | 227717 | 25742301 | +0 | 51.7 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 82.75475 | 0.21297 | 83.06725 | 0.3 % | 512149 | 51306563 | +0 | 51.7 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 34.32181 | 0.09304 | 34.45027 | 0.3 % | 203528 | 21784039 | +0 | 51.7 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 34.40188 | 0.11291 | 34.60776 | 0.3 % | 202410 | 21703008 | +0 | 51.7 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 34.35312 | 0.14314 | 34.59065 | 0.4 % | 202365 | 21694787 | +0 | 51.7 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 890.81727 | 1.38380 | 893.67236 | 0.2 % | 3554579 | 512336362 | +0 | 52.8 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 49.82807 | 11.35326 | 75.34365 | 22.8 % | 115749 | 19929206 | +0 | 53.2 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 112.29319 | 0.18511 | 112.56022 | 0.2 % | 249465 | 61441784 | +0 | 53.2 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 233.61140 | 0.42865 | 234.18970 | 0.2 % | 526502 | 130739001 | +0 | 81.3 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 97.79803 | 0.27744 | 98.41107 | 0.3 % | 228967 | 53743821 | +0 | 81.4 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 223.18013 | 0.37355 | 223.71934 | 0.2 % | 484408 | 132856523 | +0 | 85.5 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 458.37779 | 0.54533 | 458.97651 | 0.1 % | 1025529 | 277178968 | +0 | 148.0 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 280.35083 | 0.76728 | 281.77945 | 0.3 % | 1236869 | 235571821 | +0 | 148.0 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 746.40106 | 3.37089 | 752.76230 | 0.5 % | 2634211 | 495789994 | +0 | 148.0 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3970.69871 | 8.76960 | 3981.01144 | 0.2 % | 6057816 | 1150897523 | +0 | 148.0 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 19.83407 | 0.03672 | 19.88386 | 0.2 % | 100513 | 14756474 | +0 | 148.0 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 70.41079 | 0.15122 | 70.62185 | 0.2 % | 226265 | 55177624 | +0 | 148.0 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 139.89970 | 0.47477 | 140.74067 | 0.3 % | 449824 | 104224702 | +0 | 148.0 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 43.68107 | 0.08840 | 43.84532 | 0.2 % | 287322 | 33573726 | +0 | 148.0 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 931.49632 | 4.29348 | 940.35121 | 0.5 % | 1042469 | 191365455 | +0 | 148.0 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1964.80722 | 3.83404 | 1971.78523 | 0.2 % | 2008842 | 381593819 | +0 | 148.0 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 222.89446 | 0.57888 | 223.71456 | 0.3 % | 546395 | 129692239 | +0 | 148.0 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 233.24459 | 0.35817 | 233.91303 | 0.2 % | 526502 | 130748983 | +0 | 148.0 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.14438 | 0.01496 | 0.17471 | 10.4 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01554 | 0.00075 | 0.01703 | 4.8 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3846.83938 | 10.36328 | 3865.92588 | 0.3 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 38.30505 | 1.34065 | 40.77002 | 3.5 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 85.10489 | 1.10791 | 87.12698 | 1.3 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3970.40924 | 12.59561 | 3993.97290 | 0.3 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.04931 | 0.00894 | 0.05869 | 18.1 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01604 | 0.00266 | 0.01997 | 16.6 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 254.55525 | 4.81756 | 265.09497 | 1.9 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 8.03635 | 0.04934 | 8.12477 | 0.6 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 19.49784 | 0.13167 | 19.70945 | 0.7 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 282.15479 | 4.95681 | 292.99742 | 1.8 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.06974 | 0.00573 | 0.08189 | 8.2 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.01444 | 0.00027 | 0.01474 | 1.9 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 691.87027 | 3.89831 | 699.95215 | 0.6 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 17.20024 | 0.45898 | 17.74659 | 2.7 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 40.21270 | 0.76539 | 41.72571 | 1.9 % | n/a | n/a | n/a | 148.0 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 749.36738 | 4.23031 | 757.68417 | 0.6 % | n/a | n/a | n/a | 148.0 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3904.72598 | 11.80220 | 3927.77789 | 0.3 % | n/a | n/a | n/a | 148.0 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3826.32476 | 10.25049 | 3839.07254 | 0.3 % | n/a | n/a | n/a | 148.0 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 306.58058 | 0.82128 | 307.85887 | 0.3 % | n/a | n/a | n/a | 148.0 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 643.00099 | 2.52530 | 646.24805 | 0.4 % | n/a | n/a | n/a | 148.0 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 223.75329 | 0.58145 | 224.56689 | 0.3 % | n/a | n/a | n/a | 148.0 |

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
