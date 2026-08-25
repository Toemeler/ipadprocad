# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T10:12:23Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v28 (OCCT 7.9.3) (shim v28) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.376 | [1.211, 1.542] | 0.9925 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.010 | [1.944, 2.075] | 0.9994 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.085 | [0.940, 1.230] | 0.9908 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.182 | 0.9612 | [0.853, 1.511] |
| `edgeInfo1` | edges | 4 | 1.376 | 0.9925 | [1.211, 1.542] |
| `allEdges` | edges | 4 | 2.010 | 0.9994 | [1.944, 2.075] |
| `allEdgesBulk` | edges | 4 | 1.080 | 0.9567 | [0.761, 1.398] |
| `buildOnly` | edges | 4 | 1.085 | 0.9908 | [0.940, 1.230] |
| `counts` | edges | 4 | 0.971 | 0.9461 | [0.650, 1.292] |
| `bbox` | edges | 4 | 0.949 | 0.9885 | [0.807, 1.090] |
| `mesh` | edges | 4 | 1.113 | 0.9787 | [0.886, 1.341] |
| `fuse` | edges | 4 | 1.352 | 0.9982 | [1.274, 1.431] |
| `cut` | edges | 4 | 1.399 | 0.9969 | [1.290, 1.507] |
| `rayHits` | edges | 4 | 0.245 | 0.8802 | [0.120, 0.370] |
| `filletEx1` | edges | 4 | 0.134 | 0.0301 | [-0.919, 1.187] |
| `fillet.edges` | edgesBlended | 3 | 0.663 | 0.9972 | [0.595, 0.731] |
| `fillet.scenario` | edgesBlended | 3 | 0.576 | 0.9759 | [0.398, 0.753] |
| `fillet.radius` | radius | 4 | 1.411 | 0.5817 | [-0.247, 3.070] |
| `sweep.segments` | segments | 3 | 1.018 | 0.9959 | [0.889, 1.146] |
| `sweep.holed` | segments | 3 | 1.011 | 1.0000 | [1.001, 1.021] |
| `sweep.legacy` | segments | 3 | 1.838 | 0.9718 | [1.224, 2.453] |
| `sweep.coil` | segments | 3 | 1.432 | 0.9924 | [1.185, 1.678] |
| `sweep.ph.build` | segments | 3 | 2.042 | 0.9546 | [1.169, 2.915] |
| `sweep.ph.unify` | segments | 3 | 1.293 | 0.9964 | [1.141, 1.446] |
| `sweep.ph.total` | segments | 3 | 2.005 | 0.9563 | [1.165, 2.845] |
| `sweep.spans` | spans | 5 | 0.470 | 0.1159 | [-0.999, 1.939] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.62103 | 0.11705 | 3.83533 | 3.2 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08026 | 0.00152 | 0.08219 | 1.9 % | 821 | 158368 | +0 | 14.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 20.79738 | 3.81343 | 29.09304 | 18.3 % | 148205 | 28566976 | +0 | 14.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 2 | 1.05904 | 0.19496 | 1.31365 | 18.4 % | 6209 | 596032 | +0 | 14.4 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.13217 | 0.58820 | 11.30029 | 5.8 % | 84071 | 225974848 | -12160 | 22.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.11709 | 0.04778 | 0.20626 | 40.8 % | 375 | 59360 | +0 | 22.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.06521 | 0.00800 | 0.07633 | 12.3 % | 63 | 80640 | +0 | 22.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.45204 | 0.45166 | 5.30442 | 10.1 % | 34056 | 13154158 | +0 | 22.6 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 50.65043 | 8.09701 | 64.03571 | 16.0 % | 270356 | 66615399 | +0 | 28.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 40.23207 | 1.42341 | 42.75088 | 3.5 % | 242870 | 59648720 | +0 | 28.8 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.23619 | 0.03578 | 0.30801 | 15.2 % | 1976 | 308336 | +0 | 28.8 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 35.87673 | 6.71795 | 47.51767 | 18.7 % | 211425 | 25882480 | +0 | 30.6 |
| `build` | edges | 360 | 360 | 7 | 1 | 11.79320 | 9.51501 | 33.23404 | 80.7 % | 67568 | 10408048 | +0 | 30.6 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 8 | 0.18778 | 0.04114 | 0.24838 | 21.9 % | 1601 | 269728 | +0 | 30.6 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 79.90880 | 17.26935 | 117.95542 | 21.6 % | 577205 | 97204096 | +0 | 30.6 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 1.60158 | 0.42017 | 2.33329 | 26.2 % | 12392 | 1160128 | +0 | 30.6 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 26.61773 | 8.75617 | 45.96783 | 32.9 % | 167561 | 446577664 | -24320 | 37.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.30907 | 0.29888 | 0.97872 | 96.7 % | 737 | 93024 | +0 | 37.1 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.14679 | 0.07077 | 0.29314 | 48.2 % | 123 | 157440 | +0 | 37.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 9.53832 | 2.17991 | 13.28579 | 22.9 % | 67923 | 24575301 | +0 | 37.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 115.94008 | 13.93803 | 134.00504 | 12.0 % | 614273 | 133954041 | +0 | 40.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 109.49645 | 13.14576 | 130.25871 | 12.0 % | 560334 | 120357886 | +0 | 40.8 |
| `rayHits` | edges | 360 | 360 | 7 | 4 | 0.24831 | 0.02212 | 0.28730 | 8.9 % | 2096 | 392112 | +0 | 40.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.15598 | 0.21827 | 8.58808 | 2.7 % | 68952 | 11624128 | +0 | 41.0 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.36381 | 1.95736 | 19.77600 | 12.0 % | 134894 | 20360432 | +0 | 41.0 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.61810 | 0.28258 | 1.05342 | 45.7 % | 3161 | 492448 | +0 | 41.0 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 311.39309 | 21.09288 | 333.29767 | 6.8 % | 2277605 | 354747136 | +0 | 41.0 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.28330 | 0.28959 | 3.75475 | 8.8 % | 24753 | 2255552 | +0 | 41.0 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 47.57564 | 2.73241 | 50.66517 | 5.7 % | 334258 | 888838496 | -48640 | 53.8 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.37459 | 0.02942 | 0.42904 | 7.9 % | 1457 | 127584 | +0 | 53.8 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.28530 | 0.04553 | 0.37902 | 16.0 % | 243 | 311040 | +0 | 53.8 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 26.77677 | 6.34385 | 35.40579 | 23.7 % | 135627 | 48367506 | +0 | 53.8 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 307.95600 | 60.84519 | 428.22050 | 19.8 % | 1539833 | 274725205 | +0 | 62.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 318.33588 | 36.19051 | 376.58767 | 11.4 % | 1432877 | 247762448 | +0 | 62.2 |
| `rayHits` | edges | 720 | 720 | 7 | 4 | 0.28601 | 0.01049 | 0.30210 | 3.7 % | 2336 | 559664 | +0 | 62.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 28.26473 | 7.97389 | 43.28717 | 28.2 % | 134712 | 22247488 | +0 | 62.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 49.80599 | 12.73898 | 70.80967 | 25.6 % | 269554 | 40496624 | +0 | 62.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 1.29783 | 0.54577 | 2.02451 | 42.1 % | 6285 | 1003424 | +0 | 62.2 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1373.19793 | 95.04877 | 1484.60362 | 6.9 % | 9053767 | 1445313024 | +0 | 62.2 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 10.10543 | 4.53795 | 16.39712 | 44.9 % | 49478 | 4511936 | +0 | 62.3 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 102.38908 | 7.64341 | 111.68937 | 7.5 % | 668060 | 1775223216 | -97280 | 86.6 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 1.03551 | 0.29622 | 1.50834 | 28.6 % | 2899 | 229472 | +0 | 86.6 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46775 | 0.01004 | 0.48061 | 2.1 % | 483 | 618240 | +0 | 86.6 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 41.31763 | 5.74258 | 52.91829 | 13.9 % | 271030 | 96173390 | +0 | 87.6 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 832.09798 | 35.63282 | 909.03521 | 4.3 % | 4342877 | 590717269 | +0 | 103.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 713.72820 | 51.78574 | 787.68596 | 7.3 % | 4130059 | 536927833 | +0 | 103.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.39650 | 0.01358 | 0.41289 | 3.4 % | 2816 | 894768 | +0 | 103.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 32.29578 | 1.96116 | 34.30067 | 6.1 % | 266270 | 44116800 | +0 | 103.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.31226 | 0.09494 | 2.52117 | 4.1 % | 25307 | 4253072 | +0 | 103.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.66468 | 0.05902 | 0.74004 | 8.9 % | 4013 | 309760 | +0 | 103.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.54587 | 0.18291 | 3.79025 | 5.2 % | 29913 | 5127328 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 10.49144 | 0.65657 | 11.33071 | 6.3 % | 92919 | 11590416 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 24.47346 | 0.41780 | 25.01079 | 1.7 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 54.80670 | 1.48956 | 57.19608 | 2.7 % | 486810 | 49139568 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.70311 | 1.00982 | 16.48296 | 6.9 % | 118226 | 15843488 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 27.08798 | 0.77589 | 28.56317 | 2.9 % | 227679 | 26897216 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 62.43673 | 7.51648 | 77.70963 | 12.0 % | 512117 | 53392640 | +0 | 103.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 27.84642 | 2.58115 | 31.10083 | 9.3 % | 202345 | 22639152 | +0 | 103.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.05520 | 1.92772 | 28.50154 | 7.4 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.82218 | 2.85261 | 31.99171 | 11.0 % | 202370 | 22640112 | +0 | 103.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 728.34752 | 41.91720 | 814.62721 | 5.8 % | 3554373 | 535954400 | +0 | 103.6 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 52.64965 | 4.66909 | 61.39717 | 8.9 % | 115765 | 20752032 | +0 | 103.6 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 115.29236 | 10.55510 | 130.87179 | 9.2 % | 249401 | 63466032 | +0 | 103.6 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 215.79676 | 8.97121 | 230.42192 | 4.2 % | 526495 | 134945888 | +0 | 108.1 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 115.97517 | 23.14578 | 158.45212 | 20.0 % | 228999 | 55827744 | +0 | 108.7 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 232.25382 | 13.04372 | 249.76450 | 5.6 % | 484280 | 137463776 | +0 | 115.1 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 470.90635 | 40.69059 | 533.10346 | 8.6 % | 1025516 | 286467696 | +0 | 177.3 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 262.21367 | 23.04747 | 304.55762 | 8.8 % | 1236848 | 249935056 | +0 | 177.6 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 643.74093 | 51.40302 | 723.10658 | 8.0 % | 2634121 | 524105264 | +0 | 177.8 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3353.51416 | 130.08440 | 3568.50471 | 3.9 % | 6057892 | 1210486000 | +0 | 180.2 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 15.01177 | 1.22790 | 16.74875 | 8.2 % | 100529 | 15713552 | +0 | 180.9 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 47.09326 | 1.49318 | 50.39771 | 3.2 % | 210352 | 47931248 | +0 | 182.0 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 109.25113 | 11.32216 | 127.82317 | 10.4 % | 449873 | 107867264 | +0 | 185.0 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 33.73883 | 2.22720 | 38.23363 | 6.6 % | 287370 | 34951712 | +0 | 185.0 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 717.35448 | 63.23672 | 802.57088 | 8.8 % | 1042546 | 198791584 | +0 | 196.3 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2013.51944 | 94.86806 | 2169.20054 | 4.7 % | 2008917 | 403883408 | +0 | 196.3 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 254.09574 | 26.76502 | 292.79108 | 10.5 % | 546392 | 133805120 | +0 | 196.3 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 289.08049 | 28.71468 | 330.44892 | 9.9 % | 526495 | 134945888 | +0 | 196.3 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.12481 | 0.07209 | 0.21638 | 57.8 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01731 | 0.01058 | 0.03104 | 61.1 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3639.08662 | 886.29749 | 4749.93396 | 24.4 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 35.93828 | 18.29156 | 66.28096 | 50.9 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 79.47356 | 23.60172 | 116.59913 | 29.7 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3754.64059 | 925.38394 | 4932.93538 | 24.6 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02977 | 0.00416 | 0.03521 | 14.0 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00795 | 0.00148 | 0.01067 | 18.6 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 214.55378 | 38.25261 | 263.62275 | 17.8 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 5.11712 | 0.43549 | 5.63467 | 8.5 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 13.22710 | 1.64434 | 15.78329 | 12.4 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 232.93572 | 39.59334 | 285.00017 | 17.0 % | n/a | n/a | n/a | 214.1 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04077 | 0.00693 | 0.05437 | 17.0 % | n/a | n/a | n/a | 214.2 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00694 | 0.00080 | 0.00871 | 11.6 % | n/a | n/a | n/a | 214.2 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 517.66851 | 45.77163 | 612.11883 | 8.8 % | n/a | n/a | n/a | 214.2 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 11.79200 | 1.89150 | 15.43975 | 16.0 % | n/a | n/a | n/a | 214.2 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 29.53608 | 6.29693 | 41.64796 | 21.3 % | n/a | n/a | n/a | 214.2 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 559.04430 | 51.99756 | 669.26963 | 9.3 % | n/a | n/a | n/a | 214.2 |
| `sweep.var.v23poly` | segments | 128 | 0 | 7 | 1 | 2857.60209 | 170.54779 | 3116.01496 | 6.0 % | n/a | n/a | n/a | 214.2 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2647.49222 | 154.89443 | 2868.48046 | 5.9 % | n/a | n/a | n/a | 214.2 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 197.43729 | 10.78225 | 209.40654 | 5.5 % | n/a | n/a | n/a | 214.4 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 478.73487 | 32.44272 | 518.89562 | 6.8 % | n/a | n/a | n/a | 216.0 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 186.83467 | 23.86001 | 221.39538 | 12.8 % | n/a | n/a | n/a | 217.2 |

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
