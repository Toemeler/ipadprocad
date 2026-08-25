# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T08:23:58Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.717 | [0.612, 0.822] | 0.9890 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.725 | [1.715, 1.736] | 1.0000 | yes | **DISAGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.836 | [0.747, 0.924] | 0.9942 | no | **DISAGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 0.747 | 0.9969 | [0.688, 0.805] |
| `edgeInfo1` | edges | 4 | 0.717 | 0.9890 | [0.612, 0.822] |
| `allEdges` | edges | 4 | 1.725 | 1.0000 | [1.715, 1.736] |
| `allEdgesBulk` | edges | 4 | 0.588 | 0.9531 | [0.407, 0.768] |
| `buildOnly` | edges | 4 | 0.836 | 0.9942 | [0.747, 0.924] |
| `counts` | edges | 4 | 0.949 | 0.9724 | [0.727, 1.170] |
| `bbox` | edges | 4 | 0.659 | 0.9458 | [0.440, 0.878] |
| `mesh` | edges | 4 | 0.670 | 0.9777 | [0.530, 0.811] |
| `fuse` | edges | 4 | 1.057 | 0.9836 | [0.868, 1.246] |
| `cut` | edges | 4 | 1.155 | 0.9852 | [0.959, 1.352] |
| `rayHits` | edges | 4 | 0.178 | 0.5666 | [-0.038, 0.393] |
| `filletEx1` | edges | 4 | 0.203 | 0.0742 | [-0.789, 1.194] |
| `fillet.edges` | edgesBlended | 3 | 0.613 | 0.9975 | [0.553, 0.673] |
| `fillet.scenario` | edgesBlended | 3 | 0.613 | 0.9839 | [0.459, 0.766] |
| `fillet.radius` | radius | 4 | 1.464 | 0.6409 | [-0.055, 2.983] |
| `sweep.segments` | segments | 3 | 0.985 | 0.9613 | [0.597, 1.372] |
| `sweep.holed` | segments | 3 | 1.109 | 0.9999 | [1.086, 1.131] |
| `sweep.legacy` | segments | 3 | 1.916 | 0.9801 | [1.381, 2.451] |
| `sweep.coil` | segments | 3 | 1.339 | 0.9821 | [0.984, 1.694] |
| `sweep.ph.build` | segments | 3 | 1.891 | 0.9772 | [1.325, 2.456] |
| `sweep.ph.unify` | segments | 3 | 1.011 | 0.9836 | [0.755, 1.267] |
| `sweep.ph.total` | segments | 3 | 1.842 | 0.9769 | [1.287, 2.397] |
| `sweep.spans` | spans | 5 | 0.487 | 0.1151 | [-1.042, 2.016] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 6.45326 | 2.50068 | 10.32612 | 38.8 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 16 | 0.13898 | 0.06055 | 0.21265 | 43.6 % | 821 | 158368 | +0 | 14.3 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 27.54282 | 5.64590 | 35.73054 | 20.5 % | 148205 | 28566976 | +0 | 14.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 2 | 1.58658 | 1.42355 | 4.79875 | 89.7 % | 6209 | 596032 | +0 | 14.5 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 16.86654 | 2.28845 | 21.29625 | 13.6 % | 84071 | 225974848 | -12160 | 23.0 |
| `counts` | edges | 180 | 180 | 7 | 16 | 0.11806 | 0.02877 | 0.17799 | 24.4 % | 375 | 59360 | +0 | 23.0 |
| `bbox` | edges | 180 | 180 | 7 | 16 | 0.12060 | 0.03334 | 0.18676 | 27.6 % | 63 | 80640 | +0 | 23.0 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 8.59295 | 3.13379 | 12.28525 | 36.5 % | 34056 | 13154158 | +0 | 23.0 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 78.85079 | 6.44991 | 90.28275 | 8.2 % | 270336 | 66611303 | +0 | 28.9 |
| `cut` | edges | 180 | 180 | 7 | 1 | 61.37283 | 9.18195 | 77.10808 | 15.0 % | 242847 | 59644039 | +0 | 29.0 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.28646 | 0.13580 | 0.52045 | 47.4 % | 1976 | 308336 | +0 | 29.0 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 33.69121 | 5.92777 | 44.15425 | 17.6 % | 211425 | 25882480 | +0 | 30.4 |
| `build` | edges | 360 | 360 | 7 | 1 | 10.64026 | 3.13594 | 14.96779 | 29.5 % | 67568 | 10408048 | +0 | 30.4 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.22771 | 0.11542 | 0.48107 | 50.7 % | 1601 | 269728 | +0 | 30.4 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 90.24892 | 5.11934 | 96.38779 | 5.7 % | 577205 | 97204096 | +0 | 30.4 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.82382 | 0.48892 | 2.49702 | 26.8 % | 12392 | 1160128 | +0 | 30.5 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 26.61580 | 2.89486 | 31.07858 | 10.9 % | 167561 | 446577664 | -24320 | 36.8 |
| `counts` | edges | 360 | 360 | 7 | 8 | 0.17449 | 0.00971 | 0.19580 | 5.6 % | 737 | 93024 | +0 | 36.8 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.15261 | 0.04387 | 0.22573 | 28.7 % | 123 | 157440 | +0 | 36.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 15.94861 | 2.72093 | 20.04942 | 17.1 % | 67923 | 24575301 | +0 | 36.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 125.67656 | 13.81654 | 140.89808 | 11.0 % | 614298 | 133959161 | +0 | 40.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 114.23024 | 13.17899 | 131.20867 | 11.5 % | 560384 | 120368126 | +0 | 40.8 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.25525 | 0.03397 | 0.33172 | 13.3 % | 2096 | 392112 | +0 | 40.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.73821 | 1.91035 | 13.86088 | 19.6 % | 68952 | 11624128 | +0 | 41.0 |
| `build` | edges | 720 | 720 | 7 | 1 | 19.25076 | 4.61948 | 27.24929 | 24.0 % | 134894 | 20360432 | +0 | 41.0 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 2 | 0.42206 | 0.22875 | 0.94019 | 54.2 % | 3161 | 492448 | +0 | 41.0 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 297.24349 | 24.98658 | 336.02842 | 8.4 % | 2277605 | 354747136 | +0 | 41.0 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.37920 | 1.29445 | 6.27479 | 38.3 % | 24753 | 2255552 | +0 | 41.0 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 53.46095 | 11.02655 | 64.12446 | 20.6 % | 334258 | 888838496 | -48640 | 53.6 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.46636 | 0.19056 | 0.79016 | 40.9 % | 1457 | 127584 | +0 | 53.6 |
| `bbox` | edges | 720 | 720 | 7 | 4 | 0.33453 | 0.14184 | 0.54561 | 42.4 % | 243 | 311040 | +0 | 53.6 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 20.57945 | 4.31753 | 27.24038 | 21.0 % | 135627 | 48367506 | +0 | 53.6 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 290.36805 | 56.85201 | 410.29654 | 19.6 % | 1539831 | 274724619 | +0 | 62.0 |
| `cut` | edges | 720 | 720 | 7 | 1 | 240.90952 | 18.51556 | 257.33200 | 7.7 % | 1432898 | 247766837 | +0 | 62.0 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.28769 | 0.00740 | 0.29708 | 2.6 % | 2336 | 559664 | +0 | 62.0 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.66333 | 3.57209 | 22.54442 | 19.1 % | 134712 | 22247488 | +0 | 62.0 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 29.72758 | 1.61141 | 31.76133 | 5.4 % | 269554 | 40496624 | +0 | 62.0 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.59359 | 0.00713 | 0.60684 | 1.2 % | 6285 | 1003424 | +0 | 62.0 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 997.35068 | 42.47335 | 1053.24333 | 4.3 % | 9053767 | 1445313024 | +0 | 62.0 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 5.02216 | 0.26015 | 5.52746 | 5.2 % | 49478 | 4511936 | +0 | 62.0 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 92.16364 | 8.18232 | 103.54037 | 8.9 % | 668060 | 1775223216 | -97280 | 87.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.76199 | 0.03518 | 0.80817 | 4.6 % | 2899 | 229472 | +0 | 87.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.42563 | 0.02298 | 0.47725 | 5.4 % | 483 | 618240 | +0 | 87.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 37.13266 | 1.10081 | 39.37479 | 3.0 % | 271030 | 96173390 | +0 | 87.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 685.78787 | 42.49251 | 751.17042 | 6.2 % | 4342742 | 590689474 | +0 | 103.4 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 690.64941 | 128.42587 | 912.92029 | 18.6 % | 4130320 | 536936427 | +0 | 103.4 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.41501 | 0.00945 | 0.42671 | 2.3 % | 2816 | 894768 | +0 | 103.4 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 43.31078 | 7.96169 | 56.94725 | 18.4 % | 266270 | 44116800 | +0 | 103.4 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.61583 | 0.06053 | 2.69933 | 2.3 % | 25307 | 4253072 | +0 | 103.4 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.67510 | 0.15815 | 1.02068 | 23.4 % | 4013 | 309760 | +0 | 103.4 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.30975 | 1.45253 | 8.28546 | 27.4 % | 29913 | 5127328 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.73274 | 2.24074 | 17.20533 | 17.6 % | 92919 | 11590416 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 27.96513 | 4.30487 | 34.44029 | 15.4 % | 202372 | 22644144 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 58.70832 | 4.56531 | 64.29183 | 7.8 % | 486810 | 49139568 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 16.89122 | 1.51392 | 19.37733 | 9.0 % | 118226 | 15843488 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 33.58692 | 9.19801 | 51.22987 | 27.4 % | 227679 | 26897216 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 78.45774 | 25.87474 | 134.67558 | 33.0 % | 512117 | 53392640 | +0 | 103.4 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.10657 | 4.25596 | 35.37571 | 16.3 % | 202345 | 22639152 | +0 | 103.4 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.08281 | 2.29951 | 30.37646 | 8.8 % | 202372 | 22644144 | +0 | 103.4 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 30.95817 | 8.30291 | 46.99617 | 26.8 % | 202370 | 22640112 | +0 | 103.4 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 726.31464 | 124.87194 | 986.12162 | 17.2 % | 3554373 | 535954400 | +0 | 103.4 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 49.80582 | 8.84238 | 69.75571 | 17.8 % | 115765 | 20752032 | +0 | 103.4 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 124.93594 | 19.27537 | 157.38600 | 15.4 % | 249401 | 63466032 | +0 | 103.4 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 195.02456 | 12.78029 | 214.56571 | 6.6 % | 526495 | 134945888 | +0 | 111.6 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 83.76983 | 3.49224 | 86.84442 | 4.2 % | 228999 | 55827744 | +0 | 112.1 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 178.17960 | 9.84956 | 189.45358 | 5.5 % | 484280 | 137463776 | +0 | 118.5 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 389.64313 | 19.19964 | 414.94529 | 4.9 % | 1025516 | 286467696 | +0 | 180.5 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 205.94053 | 10.15228 | 227.34396 | 4.9 % | 1236848 | 249935056 | +0 | 180.6 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 560.10150 | 43.17152 | 611.94117 | 7.7 % | 2634121 | 524105264 | +0 | 180.7 |
| `sweep.legacy` | segments | 128 | 4224 | 7 | 1 | 2932.41648 | 76.47014 | 3056.30592 | 2.6 % | 6057892 | 1210486000 | +0 | 183.0 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 16.50611 | 1.78429 | 19.05246 | 10.8 % | 100529 | 15713552 | +0 | 183.8 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 51.88433 | 0.99294 | 53.32492 | 1.9 % | 210352 | 47931248 | +0 | 185.2 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 105.60913 | 4.10158 | 110.36667 | 3.9 % | 449873 | 107867264 | +0 | 188.2 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 36.04810 | 6.61987 | 50.19854 | 18.4 % | 287370 | 34951712 | +0 | 188.2 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 1014.46659 | 39.01636 | 1057.02750 | 3.8 % | 1042546 | 198791584 | +0 | 197.0 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2392.71624 | 138.14442 | 2614.50925 | 5.8 % | 2008917 | 403883408 | +0 | 197.1 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 338.60968 | 28.15165 | 371.75292 | 8.3 % | 546392 | 133805120 | +0 | 197.1 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 337.79304 | 63.21452 | 472.02317 | 18.7 % | 526495 | 134945888 | +0 | 197.1 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.08131 | 0.00667 | 0.09183 | 8.2 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.00973 | 0.00093 | 0.01104 | 9.6 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3400.99797 | 311.60895 | 3829.62792 | 9.2 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 35.47091 | 8.59565 | 44.72900 | 24.2 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 75.79031 | 14.14971 | 96.13450 | 18.7 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3512.35023 | 323.89706 | 3949.62925 | 9.2 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02943 | 0.01022 | 0.05212 | 34.7 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00770 | 0.00101 | 0.00967 | 13.2 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 247.33262 | 61.27516 | 336.51763 | 24.8 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 7.16237 | 2.03858 | 11.09500 | 28.5 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 18.66737 | 6.90684 | 29.26579 | 37.0 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 273.19949 | 69.32465 | 374.42846 | 25.4 % | n/a | n/a | n/a | 215.9 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04952 | 0.00882 | 0.06596 | 17.8 % | n/a | n/a | n/a | 216.1 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00804 | 0.00124 | 0.00983 | 15.4 % | n/a | n/a | n/a | 216.1 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 648.59035 | 48.16277 | 683.89646 | 7.4 % | n/a | n/a | n/a | 216.1 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 16.40778 | 3.73371 | 20.53283 | 22.8 % | n/a | n/a | n/a | 216.1 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 32.15374 | 7.79274 | 49.35483 | 24.2 % | n/a | n/a | n/a | 216.1 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 697.20943 | 53.63235 | 753.00725 | 7.7 % | n/a | n/a | n/a | 216.1 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3343.90117 | 519.20280 | 3921.58504 | 15.5 % | n/a | n/a | n/a | 216.1 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2681.63249 | 148.55191 | 2910.80646 | 5.5 % | n/a | n/a | n/a | 216.1 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 251.38870 | 69.05376 | 394.83046 | 27.5 % | n/a | n/a | n/a | 216.1 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 667.64090 | 174.28810 | 1046.74533 | 26.1 % | n/a | n/a | n/a | 217.8 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 183.40405 | 25.84987 | 229.94392 | 14.1 % | n/a | n/a | n/a | 217.8 |

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
