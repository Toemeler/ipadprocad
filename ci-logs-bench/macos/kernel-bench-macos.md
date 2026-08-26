# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-26T09:13:00Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v28 (OCCT 7.9.3) (shim v28) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.047 | [0.901, 1.192] | 0.9900 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.148 | [1.977, 2.320] | 0.9967 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.022 | [0.884, 1.160] | 0.9906 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.087 | 0.9565 | [0.765, 1.408] |
| `edgeInfo1` | edges | 4 | 1.047 | 0.9900 | [0.901, 1.192] |
| `allEdges` | edges | 4 | 2.148 | 0.9967 | [1.977, 2.320] |
| `allEdgesBulk` | edges | 4 | 0.858 | 0.9501 | [0.586, 1.130] |
| `buildOnly` | edges | 4 | 1.022 | 0.9906 | [0.884, 1.160] |
| `counts` | edges | 4 | 1.004 | 0.9520 | [0.691, 1.316] |
| `bbox` | edges | 4 | 1.065 | 0.9530 | [0.737, 1.393] |
| `mesh` | edges | 4 | 1.143 | 0.9893 | [0.978, 1.308] |
| `fuse` | edges | 4 | 1.429 | 0.9997 | [1.395, 1.463] |
| `cut` | edges | 4 | 1.377 | 0.9956 | [1.250, 1.503] |
| `rayHits` | edges | 4 | 0.448 | 0.8273 | [0.164, 0.731] |
| `filletEx1` | edges | 4 | 0.282 | 0.1839 | [-0.542, 1.106] |
| `fillet.edges` | edgesBlended | 3 | 0.652 | 0.9913 | [0.532, 0.771] |
| `fillet.scenario` | edgesBlended | 3 | 0.624 | 0.9992 | [0.589, 0.659] |
| `fillet.radius` | radius | 4 | 1.489 | 0.5938 | [-0.218, 3.195] |
| `sweep.segments` | segments | 3 | 1.188 | 0.9918 | [0.976, 1.400] |
| `sweep.holed` | segments | 3 | 0.935 | 0.9969 | [0.833, 1.036] |
| `sweep.legacy` | segments | 3 | 1.881 | 0.9807 | [1.363, 2.399] |
| `sweep.coil` | segments | 3 | 1.402 | 0.9984 | [1.291, 1.513] |
| `sweep.ph.build` | segments | 3 | 2.090 | 0.9690 | [1.358, 2.822] |
| `sweep.ph.unify` | segments | 3 | 1.204 | 0.9948 | [1.033, 1.376] |
| `sweep.ph.total` | segments | 3 | 2.036 | 0.9690 | [1.322, 2.750] |
| `sweep.spans` | spans | 5 | 0.243 | 0.0305 | [-1.306, 1.792] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 6.10723 | 1.81162 | 9.34467 | 29.7 % | 33890 | 5335600 | +0 | 14.1 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 16 | 0.13324 | 0.04933 | 0.20631 | 37.0 % | 821 | 158368 | +0 | 14.1 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 22.33689 | 4.11850 | 30.98187 | 18.4 % | 148205 | 28566976 | +0 | 14.1 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 2 | 1.71904 | 0.57738 | 2.61454 | 33.6 % | 6209 | 596032 | +0 | 14.3 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 16.58019 | 4.12880 | 23.11800 | 24.9 % | 84071 | 225974848 | -12160 | 22.8 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.14231 | 0.03433 | 0.19842 | 24.1 % | 375 | 59360 | +0 | 22.8 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.08558 | 0.04618 | 0.18588 | 54.0 % | 63 | 80640 | +0 | 22.8 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.07860 | 1.17388 | 7.49546 | 23.1 % | 34056 | 13154158 | +0 | 22.8 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 56.54743 | 4.42552 | 61.85467 | 7.8 % | 270396 | 66620610 | +0 | 28.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 59.94395 | 13.98755 | 81.37363 | 23.3 % | 242904 | 59652907 | +0 | 28.5 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.27610 | 0.08511 | 0.46327 | 30.8 % | 1976 | 308336 | +0 | 28.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 33.56514 | 4.29225 | 39.07058 | 12.8 % | 211425 | 25882480 | +0 | 30.2 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.41951 | 1.69503 | 12.18988 | 20.1 % | 67568 | 10408048 | +0 | 30.2 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.25683 | 0.10963 | 0.49316 | 42.7 % | 1601 | 269728 | +0 | 30.2 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 80.42887 | 7.05540 | 87.15083 | 8.8 % | 577205 | 97204096 | +0 | 30.2 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 2.08505 | 0.42866 | 2.88467 | 20.6 % | 12392 | 1160128 | +0 | 30.2 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 29.77741 | 4.36271 | 34.52633 | 14.7 % | 167561 | 446577664 | -24320 | 36.7 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.27107 | 0.09029 | 0.43157 | 33.3 % | 737 | 93024 | +0 | 36.7 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.13553 | 0.02865 | 0.18245 | 21.1 % | 123 | 157440 | +0 | 36.7 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 14.21665 | 2.08946 | 18.05187 | 14.7 % | 67923 | 24575301 | +0 | 36.7 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 155.05667 | 20.95312 | 193.62512 | 13.5 % | 614254 | 133950091 | +0 | 40.4 |
| `cut` | edges | 360 | 360 | 7 | 1 | 129.00745 | 20.84977 | 159.14871 | 16.2 % | 560415 | 120374416 | +0 | 40.4 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.27029 | 0.01800 | 0.29258 | 6.7 % | 2096 | 392112 | +0 | 40.4 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 12.31986 | 3.06580 | 15.92083 | 24.9 % | 68952 | 11624128 | +0 | 40.6 |
| `build` | edges | 720 | 720 | 7 | 1 | 20.34535 | 5.78147 | 30.84650 | 28.4 % | 134894 | 20360432 | +0 | 40.6 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.47604 | 0.18633 | 0.89129 | 39.1 % | 3161 | 492448 | +0 | 40.6 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 365.86648 | 14.57827 | 385.15704 | 4.0 % | 2277605 | 354747136 | +0 | 40.6 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.66890 | 1.68625 | 7.72958 | 36.1 % | 24753 | 2255552 | +0 | 40.6 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 57.93251 | 6.46252 | 65.19375 | 11.2 % | 334258 | 888838496 | -48640 | 53.4 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.39743 | 0.08885 | 0.52920 | 22.4 % | 1457 | 127584 | +0 | 53.4 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.46178 | 0.14213 | 0.58615 | 30.8 % | 243 | 311040 | +0 | 53.4 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 25.42234 | 3.54556 | 31.11183 | 13.9 % | 135627 | 48367506 | +0 | 54.1 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 427.39399 | 33.42156 | 456.13129 | 7.8 % | 1539800 | 274718329 | +0 | 62.5 |
| `cut` | edges | 720 | 720 | 7 | 1 | 371.32171 | 25.92737 | 421.72125 | 7.0 % | 1432879 | 247762887 | +0 | 62.5 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.56073 | 0.18690 | 0.90503 | 33.3 % | 2336 | 559664 | +0 | 62.5 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 26.51701 | 4.86211 | 32.47187 | 18.3 % | 134712 | 22247488 | +0 | 62.5 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 56.03918 | 6.24136 | 68.78050 | 11.1 % | 269554 | 40496624 | +0 | 62.5 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 1.21752 | 0.66683 | 2.24837 | 54.8 % | 6285 | 1003424 | +0 | 62.5 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1929.82215 | 126.22876 | 2183.29875 | 6.5 % | 9053767 | 1445313024 | +0 | 62.5 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 9.54024 | 1.59799 | 11.59287 | 16.8 % | 49478 | 4511936 | +0 | 62.5 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 140.81219 | 9.19447 | 156.56287 | 6.5 % | 668060 | 1775223216 | -97280 | 87.1 |
| `counts` | edges | 1440 | 1440 | 7 | 2 | 1.27353 | 0.32980 | 1.82685 | 25.9 % | 2899 | 229472 | +0 | 87.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.66599 | 0.29536 | 1.12557 | 44.3 % | 483 | 618240 | +0 | 87.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 58.66020 | 2.92013 | 61.99100 | 5.0 % | 271030 | 96173390 | +0 | 87.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1094.84838 | 89.04664 | 1251.75488 | 8.1 % | 4343079 | 590737419 | +0 | 103.4 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 1014.11992 | 47.86435 | 1071.19037 | 4.7 % | 4130050 | 536926078 | +0 | 103.4 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.60891 | 0.18966 | 1.01764 | 31.1 % | 2816 | 894768 | +0 | 103.4 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 49.90272 | 7.10061 | 59.16258 | 14.2 % | 266270 | 44116800 | +0 | 103.4 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 4.90220 | 2.23037 | 8.13479 | 45.5 % | 25307 | 4253072 | +0 | 103.4 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.94948 | 0.43977 | 1.83460 | 46.3 % | 4013 | 309760 | +0 | 103.4 |
| `valid` | edges | 72 | 72 | 7 | 1 | 6.78124 | 2.06195 | 9.64987 | 30.4 % | 29913 | 5127328 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 14.31978 | 2.62972 | 19.19217 | 18.4 % | 92919 | 11590416 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 31.15355 | 6.28956 | 40.86738 | 20.2 % | 202372 | 22644144 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 73.07104 | 6.32455 | 79.72413 | 8.7 % | 486810 | 49139568 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 18.56947 | 1.82322 | 20.55979 | 9.8 % | 118226 | 15843488 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 42.52686 | 7.28397 | 54.26308 | 17.1 % | 227679 | 26897216 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 87.86078 | 10.80231 | 105.46171 | 12.3 % | 512117 | 53392640 | +0 | 103.4 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 35.79974 | 6.73742 | 45.52792 | 18.8 % | 202345 | 22639152 | +0 | 103.4 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 35.36489 | 8.87055 | 51.72358 | 25.1 % | 202372 | 22644144 | +0 | 103.4 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 34.85456 | 5.02932 | 39.33017 | 14.4 % | 202370 | 22640112 | +0 | 103.4 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 1121.56800 | 82.06386 | 1227.65863 | 7.3 % | 3554373 | 535954400 | +0 | 103.4 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 56.14023 | 5.16721 | 64.13421 | 9.2 % | 115765 | 20752032 | +0 | 103.4 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 145.65871 | 21.35851 | 179.20212 | 14.7 % | 249401 | 63466032 | +0 | 103.4 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 291.46065 | 14.12889 | 308.58417 | 4.8 % | 526495 | 134945888 | +0 | 111.0 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 138.28349 | 6.98191 | 148.54442 | 5.0 % | 228999 | 55827744 | +0 | 111.5 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 248.44086 | 10.75250 | 269.40458 | 4.3 % | 484280 | 137463776 | +0 | 117.9 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 505.44940 | 19.91588 | 533.03192 | 3.9 % | 1025516 | 286467696 | +0 | 180.0 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 295.51282 | 21.33113 | 320.86142 | 7.2 % | 1236848 | 249935056 | +0 | 180.2 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 792.60520 | 50.95572 | 863.01446 | 6.4 % | 2634121 | 524105264 | +0 | 180.2 |
| `sweep.legacy` | segments | 128 | 4224 | 5 | 1 | 4008.32083 | 575.92126 | 4548.54496 | 14.4 % | 6057892 | 1210486000 | +0 | 182.6 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 26.84334 | 6.39547 | 38.71579 | 23.8 % | 100529 | 15713552 | +0 | 183.4 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 75.92764 | 30.03239 | 142.61429 | 39.6 % | 210352 | 47931248 | +0 | 184.8 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 187.42762 | 25.94989 | 243.91600 | 13.8 % | 449873 | 107867264 | +0 | 187.7 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 48.84055 | 5.92308 | 61.25121 | 12.1 % | 287370 | 34951712 | +0 | 187.7 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 1157.23823 | 81.34842 | 1313.42175 | 7.0 % | 1042546 | 198791584 | +0 | 198.9 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2346.81152 | 231.85654 | 2628.08042 | 9.9 % | 2008917 | 403883408 | +0 | 198.9 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 200.39871 | 11.02663 | 212.36767 | 5.5 % | 546392 | 133805120 | +0 | 198.9 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 272.32671 | 20.19633 | 303.14946 | 7.4 % | 526495 | 134945888 | +0 | 198.9 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.09015 | 0.02778 | 0.14408 | 30.8 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.00869 | 0.00144 | 0.01096 | 16.6 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3759.51024 | 289.74410 | 4021.82746 | 7.7 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 28.22228 | 3.63951 | 35.21108 | 12.9 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 84.73043 | 18.35857 | 117.56554 | 21.7 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3872.56180 | 304.10249 | 4168.34529 | 7.9 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.03074 | 0.00666 | 0.04337 | 21.7 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00836 | 0.00130 | 0.01100 | 15.5 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 207.46789 | 17.21096 | 232.99621 | 8.3 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.68416 | 1.50974 | 9.79596 | 22.6 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 15.95987 | 1.70789 | 18.29296 | 10.7 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 230.15102 | 16.30594 | 251.11062 | 7.1 % | n/a | n/a | n/a | 216.2 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04611 | 0.00196 | 0.04971 | 4.3 % | n/a | n/a | n/a | 216.4 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00786 | 0.00070 | 0.00904 | 8.8 % | n/a | n/a | n/a | 216.4 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 564.01092 | 31.58420 | 614.94588 | 5.6 % | n/a | n/a | n/a | 216.4 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 12.47412 | 1.65201 | 14.23612 | 13.2 % | n/a | n/a | n/a | 216.4 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 33.10833 | 3.73263 | 36.75521 | 11.3 % | n/a | n/a | n/a | 216.4 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 609.64735 | 35.60242 | 663.00096 | 5.8 % | n/a | n/a | n/a | 216.4 |
| `sweep.var.v23poly` | segments | 128 | 0 | 7 | 1 | 2853.54898 | 102.18123 | 3022.47354 | 3.6 % | n/a | n/a | n/a | 216.4 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 3035.79823 | 211.38815 | 3385.60017 | 7.0 % | n/a | n/a | n/a | 216.4 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 204.70707 | 13.94711 | 225.71717 | 6.8 % | n/a | n/a | n/a | 216.5 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 516.31055 | 40.37322 | 553.58204 | 7.8 % | n/a | n/a | n/a | 218.2 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 201.81196 | 37.51927 | 272.62733 | 18.6 % | n/a | n/a | n/a | 219.3 |

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
