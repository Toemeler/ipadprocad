# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T08:52:38Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.052 | [1.009, 1.095] | 0.9991 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.042 | [1.964, 2.120] | 0.9992 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.006 | [0.986, 1.026] | 0.9998 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.059 | 0.9999 | [1.042, 1.076] |
| `edgeInfo1` | edges | 4 | 1.052 | 0.9991 | [1.009, 1.095] |
| `allEdges` | edges | 4 | 2.042 | 0.9992 | [1.964, 2.120] |
| `allEdgesBulk` | edges | 4 | 0.993 | 0.9996 | [0.967, 1.019] |
| `buildOnly` | edges | 4 | 1.006 | 0.9998 | [0.986, 1.026] |
| `counts` | edges | 4 | 1.039 | 0.9980 | [0.974, 1.104] |
| `bbox` | edges | 4 | 0.912 | 0.9944 | [0.817, 1.007] |
| `mesh` | edges | 4 | 0.959 | 0.9992 | [0.922, 0.996] |
| `fuse` | edges | 4 | 1.288 | 0.9973 | [1.195, 1.380] |
| `cut` | edges | 4 | 1.296 | 0.9973 | [1.202, 1.390] |
| `rayHits` | edges | 4 | 0.313 | 0.9584 | [0.222, 0.403] |
| `filletEx1` | edges | 4 | 0.227 | 0.1158 | [-0.643, 1.098] |
| `fillet.edges` | edgesBlended | 3 | 0.615 | 0.9917 | [0.505, 0.726] |
| `fillet.scenario` | edgesBlended | 3 | 0.555 | 0.9875 | [0.432, 0.677] |
| `fillet.radius` | radius | 4 | 1.476 | 0.5974 | [-0.203, 3.155] |
| `sweep.segments` | segments | 3 | 1.176 | 0.9961 | [1.032, 1.319] |
| `sweep.holed` | segments | 3 | 1.100 | 0.9986 | [1.018, 1.182] |
| `sweep.legacy` | segments | 3 | 2.061 | 0.9686 | [1.333, 2.788] |
| `sweep.coil` | segments | 3 | 1.525 | 0.9963 | [1.343, 1.707] |
| `sweep.ph.build` | segments | 3 | 2.099 | 0.9682 | [1.353, 2.844] |
| `sweep.ph.unify` | segments | 3 | 1.071 | 0.9996 | [1.029, 1.112] |
| `sweep.ph.total` | segments | 3 | 2.048 | 0.9686 | [1.325, 2.770] |
| `sweep.spans` | spans | 5 | 0.376 | 0.0663 | [-1.221, 1.974] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.67362 | 0.01582 | 3.70126 | 0.4 % | 33890 | 4998030 | +0 | 10.7 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08168 | 0.00022 | 0.08195 | 0.3 % | 821 | 150504 | +0 | 10.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.18265 | 0.75643 | 16.89754 | 5.0 % | 148205 | 27142874 | +0 | 10.9 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.75306 | 0.08768 | 0.92207 | 11.6 % | 6207 | 572856 | +0 | 10.9 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.83132 | 0.17420 | 11.09638 | 1.6 % | 84141 | 210178733 | -12999 | 14.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07501 | 0.00011 | 0.07518 | 0.1 % | 375 | 55368 | +0 | 14.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.07002 | 0.01801 | 0.09712 | 25.7 % | 63 | 71064 | +0 | 14.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.56367 | 0.16333 | 4.82055 | 3.6 % | 34051 | 7905082 | +0 | 14.6 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 52.10336 | 0.15495 | 52.32112 | 0.3 % | 270390 | 61755825 | +0 | 19.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 48.22293 | 0.29261 | 48.67129 | 0.6 % | 242934 | 55315536 | +0 | 19.5 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.22601 | 0.00181 | 0.22884 | 0.8 % | 1976 | 289192 | +0 | 19.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 27.54831 | 0.16186 | 27.73205 | 0.6 % | 211444 | 24608903 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.59704 | 0.04898 | 7.67809 | 0.6 % | 67568 | 9757449 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.16304 | 0.00090 | 0.16486 | 0.6 % | 1601 | 255752 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 59.81416 | 0.10896 | 59.98096 | 0.2 % | 577205 | 92156090 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.45045 | 0.02366 | 1.50309 | 1.6 % | 12390 | 1116142 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.12418 | 0.18684 | 21.50108 | 0.9 % | 167656 | 415796672 | -25986 | 24.5 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.15036 | 0.00127 | 0.15217 | 0.8 % | 737 | 86136 | +0 | 24.5 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11547 | 0.00182 | 0.11913 | 1.6 % | 123 | 138744 | +0 | 24.5 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.41706 | 0.10251 | 8.64481 | 1.2 % | 67916 | 14720051 | +0 | 24.5 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 114.91869 | 0.49039 | 115.81991 | 0.4 % | 614316 | 125179111 | +0 | 25.5 |
| `cut` | edges | 360 | 360 | 7 | 1 | 106.52491 | 0.30499 | 106.96377 | 0.3 % | 560370 | 112626035 | +0 | 25.5 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.25968 | 0.00304 | 0.26461 | 1.2 % | 2096 | 361419 | +0 | 25.5 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.32502 | 0.04644 | 9.41779 | 0.5 % | 68952 | 10995717 | +0 | 26.5 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.61847 | 0.04493 | 15.67303 | 0.3 % | 134894 | 19067769 | +0 | 26.5 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.33328 | 0.01326 | 0.36243 | 4.0 % | 3161 | 465992 | +0 | 26.5 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 233.92648 | 0.50187 | 234.42888 | 0.2 % | 2277605 | 335665802 | +0 | 31.8 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.90570 | 0.01132 | 2.91639 | 0.4 % | 24751 | 2170950 | +0 | 31.8 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 43.09303 | 0.34546 | 43.66479 | 0.8 % | 334430 | 827077184 | -51977 | 35.3 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.29293 | 0.00307 | 0.29728 | 1.0 % | 1457 | 114760 | +0 | 35.3 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22779 | 0.00179 | 0.23175 | 0.8 % | 243 | 274104 | +0 | 35.3 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 16.70476 | 0.21378 | 17.17697 | 1.3 % | 135617 | 28315311 | +0 | 35.3 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 279.84816 | 1.48916 | 282.14156 | 0.5 % | 1539908 | 260037511 | +0 | 35.3 |
| `cut` | edges | 720 | 720 | 7 | 1 | 261.90801 | 2.61719 | 264.95272 | 1.0 % | 1432923 | 235302120 | +0 | 35.3 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.31271 | 0.00670 | 0.32528 | 2.1 % | 2336 | 508789 | +0 | 35.3 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.42509 | 0.11994 | 18.67706 | 0.7 % | 134712 | 21027298 | +0 | 35.3 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 33.35933 | 0.24747 | 33.73451 | 0.7 % | 269554 | 37904933 | +0 | 35.3 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.73100 | 0.01224 | 0.74718 | 1.7 % | 6285 | 950552 | +0 | 35.3 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1078.11969 | 19.65143 | 1121.15887 | 1.8 % | 9053767 | 1369134026 | +0 | 35.3 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 5.92475 | 0.04390 | 6.02015 | 0.7 % | 49476 | 4347669 | +0 | 35.3 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 87.29779 | 0.46938 | 87.98837 | 0.5 % | 668604 | 1650828153 | -103973 | 43.3 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.66258 | 0.01260 | 0.68098 | 1.9 % | 2899 | 204553 | +0 | 43.3 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.45910 | 0.00130 | 0.46090 | 0.3 % | 483 | 544824 | +0 | 43.3 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 33.29851 | 0.13662 | 33.47041 | 0.4 % | 271017 | 55034648 | +0 | 43.3 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 759.09261 | 4.38363 | 765.00630 | 0.6 % | 4342930 | 571851142 | +0 | 48.7 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 713.62775 | 10.57635 | 735.65090 | 1.5 % | 4130031 | 520962707 | +0 | 48.7 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.43735 | 0.00250 | 0.44096 | 0.6 % | 2816 | 805482 | +0 | 48.7 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.12167 | 0.15062 | 37.45110 | 0.4 % | 266270 | 41699031 | +0 | 48.7 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.56633 | 0.01166 | 2.58607 | 0.5 % | 25307 | 4003994 | +0 | 48.7 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.75135 | 0.00813 | 0.76971 | 1.1 % | 4013 | 302664 | +0 | 48.7 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.19366 | 0.02980 | 4.24081 | 0.7 % | 29913 | 4795224 | +0 | 48.7 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.19368 | 0.07157 | 12.30764 | 0.6 % | 92923 | 10993601 | +0 | 48.7 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 25.46770 | 0.11168 | 25.70780 | 0.4 % | 202410 | 21707867 | +0 | 50.2 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 56.78976 | 0.31792 | 57.37275 | 0.6 % | 486842 | 47293017 | +0 | 50.2 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.84976 | 0.04602 | 14.94087 | 0.3 % | 118230 | 14999337 | +0 | 50.2 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 28.15686 | 0.07030 | 28.25026 | 0.2 % | 227717 | 25716079 | +0 | 50.2 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 59.56217 | 0.11625 | 59.70911 | 0.2 % | 512149 | 51329917 | +0 | 50.2 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.66712 | 0.13500 | 25.90330 | 0.5 % | 203528 | 21787755 | +0 | 50.2 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.46343 | 0.08291 | 25.64421 | 0.3 % | 202410 | 21703136 | +0 | 50.2 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.37890 | 0.09065 | 25.55704 | 0.4 % | 202365 | 21693064 | +0 | 50.2 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 777.84654 | 0.97854 | 779.80450 | 0.1 % | 3554579 | 512374616 | +0 | 51.2 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 47.03821 | 0.14725 | 47.31679 | 0.3 % | 115749 | 19927105 | +0 | 51.8 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 116.01167 | 0.23928 | 116.26544 | 0.2 % | 249465 | 61438630 | +0 | 51.8 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 240.00731 | 3.35717 | 247.32878 | 1.4 % | 526502 | 130746343 | +0 | 80.0 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 100.42257 | 0.81479 | 102.23732 | 0.8 % | 228967 | 53743283 | +0 | 80.0 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 226.28381 | 0.35998 | 226.75174 | 0.2 % | 484408 | 132865863 | +0 | 84.1 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 461.16749 | 0.86019 | 462.78787 | 0.2 % | 1025529 | 277171453 | +0 | 146.6 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 225.28277 | 0.91547 | 227.13112 | 0.4 % | 1236869 | 235600929 | +0 | 146.6 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 601.74929 | 2.40423 | 604.35110 | 0.4 % | 2634211 | 495749965 | +0 | 146.6 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3919.94111 | 53.41835 | 3974.11772 | 1.4 % | 6057816 | 1150762208 | +0 | 146.6 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 26.26829 | 15.29218 | 58.11825 | 58.2 % | 100513 | 14758367 | +0 | 146.6 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 67.63541 | 1.43843 | 70.81603 | 2.1 % | 226265 | 55180065 | +0 | 146.6 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 217.56463 | 104.05660 | 343.45175 | 47.8 % | 449824 | 104230158 | +0 | 146.6 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 31.49515 | 0.15024 | 31.76777 | 0.5 % | 287322 | 33577952 | +0 | 146.6 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 970.88637 | 6.37515 | 981.50284 | 0.7 % | 1042469 | 191371549 | +0 | 146.6 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2049.63453 | 1.75685 | 2052.39821 | 0.1 % | 2008842 | 381618377 | +0 | 146.6 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 228.84048 | 0.38422 | 229.43857 | 0.2 % | 546395 | 129690577 | +0 | 146.6 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 238.90077 | 0.41047 | 239.50329 | 0.2 % | 526502 | 130748331 | +0 | 146.6 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.11066 | 0.02152 | 0.15250 | 19.4 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01053 | 0.00196 | 0.01445 | 18.6 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3764.50624 | 11.89038 | 3783.00137 | 0.3 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 29.84134 | 0.80058 | 31.15879 | 2.7 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 61.60465 | 1.05233 | 62.68304 | 1.7 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3856.07342 | 12.34892 | 3874.64509 | 0.3 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.04451 | 0.02878 | 0.10687 | 64.7 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00939 | 0.00105 | 0.01082 | 11.2 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 205.20402 | 2.36716 | 210.22623 | 1.2 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.38731 | 0.05151 | 6.46370 | 0.8 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 13.95860 | 0.30389 | 14.58053 | 2.2 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 225.60383 | 2.36970 | 230.73733 | 1.1 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.05832 | 0.00730 | 0.07007 | 12.5 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.01046 | 0.00344 | 0.01822 | 32.9 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 556.74301 | 2.27548 | 561.02818 | 0.4 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 13.73625 | 0.30175 | 14.22012 | 2.2 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 28.58783 | 0.31768 | 29.12895 | 1.1 % | n/a | n/a | n/a | 146.6 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 599.13588 | 2.53026 | 603.37883 | 0.4 % | n/a | n/a | n/a | 146.6 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3856.62834 | 15.36412 | 3878.02307 | 0.4 % | n/a | n/a | n/a | 146.6 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3772.52055 | 10.68550 | 3781.62389 | 0.3 % | n/a | n/a | n/a | 146.6 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 233.26781 | 1.46737 | 234.96506 | 0.6 % | n/a | n/a | n/a | 146.6 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 549.48897 | 3.32070 | 553.83986 | 0.6 % | n/a | n/a | n/a | 146.6 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 228.42040 | 3.51649 | 236.34679 | 1.5 % | n/a | n/a | n/a | 146.6 |

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
