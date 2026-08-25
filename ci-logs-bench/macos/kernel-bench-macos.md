# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T09:51:03Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.982 | [0.725, 1.239] | 0.9656 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.910 | [1.834, 1.986] | 0.9992 | yes | **AGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.828 | [0.617, 1.038] | 0.9675 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.002 | 0.9572 | [0.709, 1.296] |
| `edgeInfo1` | edges | 4 | 0.982 | 0.9656 | [0.725, 1.239] |
| `allEdges` | edges | 4 | 1.910 | 0.9992 | [1.834, 1.986] |
| `allEdgesBulk` | edges | 4 | 1.092 | 0.9979 | [1.023, 1.162] |
| `buildOnly` | edges | 4 | 0.828 | 0.9675 | [0.617, 1.038] |
| `counts` | edges | 4 | 1.029 | 0.8381 | [0.402, 1.655] |
| `bbox` | edges | 4 | 0.895 | 0.9194 | [0.527, 1.262] |
| `mesh` | edges | 4 | 0.944 | 0.9736 | [0.729, 1.160] |
| `fuse` | edges | 4 | 1.251 | 0.9950 | [1.128, 1.375] |
| `cut` | edges | 4 | 1.291 | 0.9909 | [1.120, 1.462] |
| `rayHits` | edges | 4 | 0.178 | 0.7788 | [0.046, 0.309] |
| `filletEx1` | edges | 4 | 0.077 | 0.0130 | [-0.855, 1.010] |
| `fillet.edges` | edgesBlended | 3 | 0.624 | 0.9504 | [0.345, 0.904] |
| `fillet.scenario` | edgesBlended | 3 | 0.549 | 0.9726 | [0.368, 0.730] |
| `fillet.radius` | radius | 4 | 1.490 | 0.6123 | [-0.153, 3.133] |
| `sweep.segments` | segments | 3 | 1.184 | 1.0000 | [1.181, 1.186] |
| `sweep.holed` | segments | 3 | 1.108 | 0.9996 | [1.067, 1.149] |
| `sweep.legacy` | segments | 3 | 1.824 | 0.9730 | [1.229, 2.420] |
| `sweep.coil` | segments | 3 | 1.407 | 0.9935 | [1.184, 1.630] |
| `sweep.ph.build` | segments | 3 | 1.912 | 0.9760 | [1.324, 2.500] |
| `sweep.ph.unify` | segments | 3 | 1.061 | 0.9997 | [1.022, 1.099] |
| `sweep.ph.total` | segments | 3 | 1.855 | 0.9752 | [1.274, 2.435] |
| `sweep.spans` | spans | 5 | 0.316 | 0.0542 | [-1.177, 1.808] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 6.46032 | 1.55532 | 8.33912 | 24.1 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.11234 | 0.03853 | 0.18565 | 34.3 % | 821 | 158368 | +0 | 14.3 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 25.92739 | 7.84705 | 37.00058 | 30.3 % | 148205 | 28566976 | +0 | 14.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.86642 | 0.36168 | 1.64136 | 41.7 % | 6209 | 596032 | +0 | 14.4 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 19.89176 | 4.74788 | 27.42317 | 23.9 % | 84071 | 225974848 | -12160 | 22.5 |
| `counts` | edges | 180 | 180 | 7 | 16 | 0.16620 | 0.01978 | 0.19941 | 11.9 % | 375 | 59360 | +0 | 22.5 |
| `bbox` | edges | 180 | 180 | 7 | 16 | 0.06990 | 0.01770 | 0.10959 | 25.3 % | 63 | 80640 | +0 | 22.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 6.84829 | 1.74687 | 9.67592 | 25.5 % | 34056 | 13154158 | +0 | 22.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 65.03726 | 6.79624 | 74.69583 | 10.4 % | 270324 | 66608816 | +0 | 28.3 |
| `cut` | edges | 180 | 180 | 7 | 1 | 52.45854 | 8.09712 | 67.97996 | 15.4 % | 242879 | 59650622 | +0 | 28.3 |
| `rayHits` | edges | 180 | 180 | 7 | 4 | 0.26896 | 0.03274 | 0.33698 | 12.2 % | 1976 | 308336 | +0 | 28.3 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 33.30711 | 3.54027 | 37.43012 | 10.6 % | 211425 | 25882480 | +0 | 29.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 9.30743 | 2.02579 | 13.15454 | 21.8 % | 67568 | 10408048 | +0 | 29.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.22483 | 0.05761 | 0.29119 | 25.6 % | 1601 | 269728 | +0 | 29.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 89.08890 | 8.19760 | 97.71400 | 9.2 % | 577205 | 97204096 | +0 | 29.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 2.04823 | 0.80618 | 3.67979 | 39.4 % | 12392 | 1160128 | +0 | 29.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 30.70303 | 6.62746 | 39.78604 | 21.6 % | 167561 | 446577664 | -24320 | 36.4 |
| `counts` | edges | 360 | 360 | 7 | 8 | 0.22505 | 0.06018 | 0.31592 | 26.7 % | 737 | 93024 | +0 | 36.4 |
| `bbox` | edges | 360 | 360 | 7 | 8 | 0.20235 | 0.07134 | 0.28585 | 35.3 % | 123 | 157440 | +0 | 36.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 17.99792 | 2.91663 | 23.08454 | 16.2 % | 67923 | 24575301 | +0 | 36.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 140.55774 | 15.99622 | 165.30592 | 11.4 % | 614290 | 133957552 | +0 | 40.3 |
| `cut` | edges | 360 | 360 | 7 | 1 | 138.78735 | 26.28170 | 187.14925 | 18.9 % | 560378 | 120366809 | +0 | 40.3 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.36480 | 0.11058 | 0.50520 | 30.3 % | 2096 | 392112 | +0 | 40.3 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.64035 | 3.21682 | 16.89275 | 33.4 % | 68952 | 11624128 | +0 | 40.5 |
| `build` | edges | 720 | 720 | 7 | 1 | 28.88940 | 5.50011 | 36.70108 | 19.0 % | 134894 | 20360432 | +0 | 40.5 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 4 | 0.58683 | 0.30808 | 1.03898 | 52.5 % | 3161 | 492448 | +0 | 40.5 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 337.37941 | 31.13409 | 367.24342 | 9.2 % | 2277605 | 354747136 | +0 | 40.5 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.13124 | 1.68468 | 7.77346 | 40.8 % | 24753 | 2255552 | +0 | 40.5 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 48.43833 | 12.44447 | 74.48517 | 25.7 % | 334258 | 888838496 | -48640 | 53.0 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.32114 | 0.01892 | 0.34278 | 5.9 % | 1457 | 127584 | +0 | 53.0 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.21935 | 0.00744 | 0.23241 | 3.4 % | 243 | 311040 | +0 | 53.0 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 26.38174 | 2.68122 | 30.47467 | 10.2 % | 135627 | 48367506 | +0 | 53.0 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 317.10207 | 29.88733 | 364.93658 | 9.4 % | 1539847 | 274718585 | +0 | 61.4 |
| `cut` | edges | 720 | 720 | 7 | 1 | 268.72520 | 13.70924 | 291.68887 | 5.1 % | 1432881 | 247763179 | +0 | 61.4 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.34549 | 0.02137 | 0.38838 | 6.2 % | 2336 | 559664 | +0 | 61.4 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 16.17226 | 0.54925 | 17.31017 | 3.4 % | 134712 | 22247488 | +0 | 61.4 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 44.88510 | 6.99081 | 56.31192 | 15.6 % | 269554 | 40496624 | +0 | 61.4 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 0.78952 | 0.10648 | 0.94379 | 13.5 % | 6285 | 1003424 | +0 | 61.4 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1372.93995 | 79.87614 | 1506.28429 | 5.8 % | 9053767 | 1445313024 | +0 | 61.4 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 8.55800 | 2.93849 | 13.33479 | 34.3 % | 49478 | 4511936 | +0 | 61.4 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 115.69291 | 14.77420 | 138.30800 | 12.8 % | 668060 | 1775223216 | -97280 | 86.6 |
| `counts` | edges | 1440 | 1440 | 7 | 2 | 1.58976 | 0.67171 | 2.35627 | 42.3 % | 2899 | 229472 | +0 | 86.6 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.53752 | 0.16009 | 0.88256 | 29.8 % | 483 | 618240 | +0 | 86.6 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 53.43585 | 5.59643 | 62.41250 | 10.5 % | 271030 | 96173390 | +0 | 86.7 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 892.77405 | 55.09227 | 966.97375 | 6.2 % | 4342829 | 590707321 | +0 | 102.9 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 831.25150 | 32.89467 | 883.24013 | 4.0 % | 4129940 | 536903403 | +0 | 102.9 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.41284 | 0.02602 | 0.45105 | 6.3 % | 2816 | 894768 | +0 | 102.9 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 33.51980 | 0.98565 | 35.18654 | 2.9 % | 266270 | 44116800 | +0 | 102.9 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.64918 | 0.04559 | 2.69708 | 1.7 % | 25307 | 4253072 | +0 | 102.9 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.61745 | 0.01172 | 0.63129 | 1.9 % | 4013 | 309760 | +0 | 102.9 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.01870 | 0.07293 | 4.15796 | 1.8 % | 29913 | 5127328 | +0 | 102.9 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.69996 | 0.97035 | 14.77479 | 7.6 % | 92919 | 11590416 | +0 | 102.9 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 22.46805 | 3.16793 | 27.55946 | 14.1 % | 202372 | 22644144 | +0 | 102.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 61.35710 | 5.21096 | 70.54600 | 8.5 % | 486810 | 49139568 | +0 | 102.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.81043 | 2.70805 | 20.80958 | 18.3 % | 118226 | 15843488 | +0 | 102.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 26.20471 | 1.44703 | 27.59025 | 5.5 % | 227679 | 26897216 | +0 | 102.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 58.89214 | 2.69024 | 63.95233 | 4.6 % | 512117 | 53392640 | +0 | 102.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.92825 | 2.84077 | 31.73771 | 11.0 % | 202345 | 22639152 | +0 | 102.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 24.33519 | 0.65881 | 25.29283 | 2.7 % | 202372 | 22644144 | +0 | 102.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.37642 | 3.34929 | 32.25713 | 12.2 % | 202370 | 22640112 | +0 | 102.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 779.86331 | 49.91104 | 842.16275 | 6.4 % | 3554373 | 535954400 | +0 | 102.9 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 53.28513 | 7.44899 | 63.61787 | 14.0 % | 115765 | 20752032 | +0 | 102.9 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 121.23651 | 15.19632 | 138.58337 | 12.5 % | 249401 | 63466032 | +0 | 102.9 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 274.89878 | 47.72505 | 371.79446 | 17.4 % | 526495 | 134945888 | +0 | 111.1 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 100.73975 | 3.95543 | 107.27208 | 3.9 % | 228999 | 55827744 | +0 | 111.7 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 222.65571 | 18.78695 | 248.89413 | 8.4 % | 484280 | 137463776 | +0 | 118.2 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 468.13668 | 18.05822 | 489.39800 | 3.9 % | 1025516 | 286467696 | +0 | 180.2 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 277.13835 | 30.32535 | 307.27804 | 10.9 % | 1236848 | 249935056 | +0 | 180.3 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 681.48752 | 48.06405 | 757.08967 | 7.1 % | 2634121 | 524105264 | +0 | 180.4 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3475.43574 | 251.21529 | 3734.36650 | 7.2 % | 6057892 | 1210486000 | +0 | 182.7 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 15.50368 | 1.00615 | 17.09246 | 6.5 % | 100529 | 15713552 | +0 | 183.5 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 47.14184 | 2.91070 | 49.82879 | 6.2 % | 210352 | 47931248 | +0 | 184.9 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 109.01900 | 10.17255 | 128.87083 | 9.3 % | 449873 | 107867264 | +0 | 187.8 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 32.94673 | 0.37904 | 33.49617 | 1.2 % | 287370 | 34951712 | +0 | 187.8 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 771.41365 | 24.37826 | 806.46800 | 3.2 % | 1042546 | 198791584 | +0 | 196.6 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1559.23062 | 30.40670 | 1599.56258 | 2.0 % | 2008917 | 403883408 | +0 | 196.7 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 182.65500 | 1.63871 | 184.71287 | 0.9 % | 546392 | 133805120 | +0 | 196.7 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 202.21743 | 4.68163 | 207.01321 | 2.3 % | 526495 | 134945888 | +0 | 196.7 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.07057 | 0.00612 | 0.08188 | 8.7 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.00735 | 0.00082 | 0.00912 | 11.2 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 2798.24345 | 28.32162 | 2833.91450 | 1.0 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 28.64673 | 11.99298 | 55.64342 | 41.9 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 58.79880 | 5.50475 | 69.08054 | 9.4 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 2885.76689 | 38.57644 | 2947.80725 | 1.3 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02959 | 0.00723 | 0.04196 | 24.4 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00822 | 0.00114 | 0.00971 | 13.9 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 197.62524 | 13.93971 | 226.08467 | 7.1 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 9.46489 | 10.67680 | 33.66121 | 112.8 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 13.51233 | 0.76676 | 14.69729 | 5.7 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 220.64028 | 14.78335 | 245.14062 | 6.7 % | n/a | n/a | n/a | 215.5 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04825 | 0.01719 | 0.08712 | 35.6 % | n/a | n/a | n/a | 215.7 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00787 | 0.00062 | 0.00908 | 7.8 % | n/a | n/a | n/a | 215.7 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 518.65951 | 56.84785 | 645.11154 | 11.0 % | n/a | n/a | n/a | 215.7 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 11.71161 | 1.88383 | 15.71771 | 16.1 % | n/a | n/a | n/a | 215.7 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 28.86197 | 3.01167 | 35.13992 | 10.4 % | n/a | n/a | n/a | 215.7 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 559.28921 | 57.39732 | 686.96146 | 10.3 % | n/a | n/a | n/a | 215.7 |
| `sweep.var.v23poly` | segments | 128 | 0 | 7 | 1 | 2634.49719 | 177.47664 | 2873.61650 | 6.7 % | n/a | n/a | n/a | 215.7 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2575.24017 | 153.87173 | 2814.88600 | 6.0 % | n/a | n/a | n/a | 215.7 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 202.74461 | 39.12700 | 285.70492 | 19.3 % | n/a | n/a | n/a | 215.8 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 560.11982 | 47.36247 | 617.44600 | 8.5 % | n/a | n/a | n/a | 217.4 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 196.92710 | 15.94487 | 215.40367 | 8.1 % | n/a | n/a | n/a | 218.7 |

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
