# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T07:51:07Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.981 | [0.819, 1.144] | 0.9859 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.006 | [1.969, 2.043] | 0.9998 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.006 | [0.932, 1.079] | 0.9972 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 0.928 | 0.9807 | [0.748, 1.109] |
| `edgeInfo1` | edges | 4 | 0.981 | 0.9859 | [0.819, 1.144] |
| `allEdges` | edges | 4 | 2.006 | 0.9998 | [1.969, 2.043] |
| `allEdgesBulk` | edges | 4 | 1.075 | 0.9958 | [0.979, 1.171] |
| `buildOnly` | edges | 4 | 1.006 | 0.9972 | [0.932, 1.079] |
| `counts` | edges | 4 | 0.873 | 0.6890 | [0.060, 1.685] |
| `bbox` | edges | 4 | 1.001 | 1.0000 | [0.991, 1.010] |
| `mesh` | edges | 4 | 1.007 | 0.9257 | [0.612, 1.403] |
| `fuse` | edges | 4 | 1.358 | 0.9997 | [1.325, 1.391] |
| `cut` | edges | 4 | 1.398 | 0.9985 | [1.323, 1.474] |
| `rayHits` | edges | 4 | 0.381 | 0.8978 | [0.203, 0.559] |
| `filletEx1` | edges | 4 | 0.278 | 0.1268 | [-0.733, 1.288] |
| `fillet.edges` | edgesBlended | 3 | 0.526 | 0.9665 | [0.334, 0.718] |
| `fillet.scenario` | edgesBlended | 3 | 0.557 | 0.9846 | [0.420, 0.694] |
| `fillet.radius` | radius | 4 | 1.468 | 0.5881 | [-0.235, 3.171] |
| `sweep.segments` | segments | 3 | 1.137 | 0.9980 | [1.038, 1.236] |
| `sweep.holed` | segments | 3 | 1.035 | 0.9934 | [0.870, 1.200] |
| `sweep.legacy` | segments | 3 | 1.944 | 0.9755 | [1.340, 2.549] |
| `sweep.coil` | segments | 3 | 1.371 | 0.9937 | [1.156, 1.585] |
| `sweep.ph.build` | segments | 3 | 1.947 | 0.9702 | [1.278, 2.615] |
| `sweep.ph.unify` | segments | 3 | 1.004 | 0.9999 | [0.983, 1.024] |
| `sweep.ph.total` | segments | 3 | 1.898 | 0.9708 | [1.252, 2.543] |
| `sweep.spans` | spans | 5 | 0.359 | 0.0706 | [-1.116, 1.834] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.08285 | 0.75809 | 5.70333 | 18.6 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08125 | 0.00467 | 0.08684 | 5.7 % | 821 | 158368 | +0 | 14.3 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.73296 | 0.63043 | 16.46554 | 4.0 % | 148205 | 28566976 | +0 | 14.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 0.66192 | 0.02841 | 0.70967 | 4.3 % | 6209 | 596032 | +0 | 14.4 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.11912 | 0.51363 | 10.70071 | 5.1 % | 84071 | 225974848 | -12160 | 22.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08174 | 0.00121 | 0.08330 | 1.5 % | 375 | 59360 | +0 | 22.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05200 | 0.00074 | 0.05354 | 1.4 % | 63 | 80640 | +0 | 22.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 3.93063 | 0.07824 | 4.09187 | 2.0 % | 34056 | 13154158 | +0 | 22.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 40.11462 | 3.21797 | 44.00238 | 8.0 % | 270294 | 66602672 | +0 | 28.8 |
| `cut` | edges | 180 | 180 | 7 | 1 | 36.00949 | 1.36255 | 38.04783 | 3.8 % | 242884 | 59651646 | +0 | 28.9 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.19728 | 0.01043 | 0.21572 | 5.3 % | 1976 | 308336 | +0 | 28.9 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 24.51640 | 1.89992 | 26.67279 | 7.7 % | 211425 | 25882480 | +0 | 30.4 |
| `build` | edges | 360 | 360 | 7 | 1 | 9.63799 | 8.61580 | 29.17358 | 89.4 % | 67568 | 10408048 | +0 | 30.4 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 4 | 0.19967 | 0.05559 | 0.29833 | 27.8 % | 1601 | 269728 | +0 | 30.4 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 60.64563 | 2.84666 | 64.60846 | 4.7 % | 577205 | 97204096 | +0 | 30.4 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.37264 | 0.12366 | 1.64629 | 9.0 % | 12392 | 1160128 | +0 | 30.4 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 19.94600 | 1.21061 | 21.62671 | 6.1 % | 167561 | 446577664 | -24320 | 36.8 |
| `counts` | edges | 360 | 360 | 7 | 4 | 0.48373 | 0.35030 | 1.01060 | 72.4 % | 737 | 93024 | +0 | 36.8 |
| `bbox` | edges | 360 | 360 | 7 | 16 | 0.10494 | 0.00380 | 0.11220 | 3.6 % | 123 | 157440 | +0 | 36.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 13.03509 | 7.65577 | 26.11675 | 58.7 % | 67923 | 24575301 | +0 | 36.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 98.16601 | 7.20704 | 112.50329 | 7.3 % | 614311 | 133961794 | +0 | 40.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 87.19573 | 4.07125 | 93.10896 | 4.7 % | 560369 | 120364907 | +0 | 40.8 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.23605 | 0.00886 | 0.24983 | 3.8 % | 2096 | 392112 | +0 | 40.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 7.28863 | 0.51992 | 7.93754 | 7.1 % | 68952 | 11624128 | +0 | 41.0 |
| `build` | edges | 720 | 720 | 7 | 1 | 14.06158 | 0.25923 | 14.56150 | 1.8 % | 134894 | 20360432 | +0 | 41.1 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.31432 | 0.00296 | 0.32043 | 0.9 % | 3161 | 492448 | +0 | 41.1 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 257.44265 | 31.19735 | 316.33392 | 12.1 % | 2277605 | 354747136 | +0 | 41.1 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.62561 | 0.06533 | 2.72833 | 2.5 % | 24753 | 2255552 | +0 | 41.1 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 37.37362 | 3.26040 | 44.35333 | 8.7 % | 334258 | 888838496 | -48640 | 54.0 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.31629 | 0.00859 | 0.32674 | 2.7 % | 1457 | 127584 | +0 | 54.0 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.20694 | 0.00237 | 0.21002 | 1.1 % | 243 | 311040 | +0 | 54.0 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 23.79199 | 8.95609 | 40.32092 | 37.6 % | 135627 | 48367506 | +0 | 54.0 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 263.00579 | 46.49666 | 334.42950 | 17.7 % | 1539767 | 274711600 | +0 | 62.4 |
| `cut` | edges | 720 | 720 | 7 | 1 | 230.12067 | 16.22173 | 258.67217 | 7.0 % | 1432892 | 247765520 | +0 | 62.4 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.26928 | 0.00495 | 0.27987 | 1.8 % | 2336 | 559664 | +0 | 62.4 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 14.76355 | 1.23372 | 17.00850 | 8.4 % | 134712 | 22247488 | +0 | 62.4 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 30.73469 | 1.72007 | 33.95954 | 5.6 % | 269554 | 40496624 | +0 | 62.4 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.67409 | 0.02357 | 0.71085 | 3.5 % | 6285 | 1003424 | +0 | 62.4 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1000.43556 | 79.65192 | 1178.66879 | 8.0 % | 9053767 | 1445313024 | +0 | 62.4 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.39177 | 0.35581 | 7.08858 | 5.6 % | 49478 | 4511936 | +0 | 62.4 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 83.79790 | 6.49120 | 98.25796 | 7.7 % | 668060 | 1775223216 | -97280 | 87.7 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.70742 | 0.03860 | 0.76900 | 5.5 % | 2899 | 229472 | +0 | 87.7 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.41851 | 0.01182 | 0.44164 | 2.8 % | 483 | 618240 | +0 | 87.7 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 32.96316 | 0.45517 | 33.51179 | 1.4 % | 271030 | 96173390 | +0 | 87.7 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 665.21068 | 26.11749 | 717.49879 | 3.9 % | 4342767 | 590694741 | +0 | 103.7 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 659.27795 | 37.64749 | 713.46267 | 5.7 % | 4130060 | 536927979 | +0 | 103.7 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.45553 | 0.02411 | 0.50726 | 5.3 % | 2816 | 894768 | +0 | 103.7 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 36.81821 | 1.75093 | 39.26504 | 4.8 % | 266270 | 44116800 | +0 | 103.7 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.57338 | 0.04828 | 2.65942 | 1.9 % | 25307 | 4253072 | +0 | 103.7 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.61610 | 0.02413 | 0.66476 | 3.9 % | 4013 | 309760 | +0 | 103.7 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.87976 | 0.19191 | 4.19600 | 4.9 % | 29913 | 5127328 | +0 | 103.7 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.65874 | 0.94832 | 15.73508 | 6.9 % | 92919 | 11590416 | +0 | 103.7 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 23.12005 | 0.59063 | 23.79117 | 2.6 % | 202372 | 22644144 | +0 | 103.7 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 51.27070 | 2.03466 | 53.34458 | 4.0 % | 486810 | 49139568 | +0 | 103.7 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 13.23783 | 0.88515 | 14.27971 | 6.7 % | 118226 | 15843488 | +0 | 103.7 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 24.80446 | 1.22185 | 26.44825 | 4.9 % | 227679 | 26897216 | +0 | 103.7 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 53.45563 | 1.26984 | 55.33104 | 2.4 % | 512117 | 53392640 | +0 | 103.7 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 22.01526 | 0.70782 | 23.02758 | 3.2 % | 202345 | 22639152 | +0 | 103.7 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 22.71766 | 1.06421 | 24.64300 | 4.7 % | 202372 | 22644144 | +0 | 103.7 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 20.93739 | 0.85670 | 21.64062 | 4.1 % | 202370 | 22640112 | +0 | 103.7 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 672.79954 | 29.57836 | 723.18967 | 4.4 % | 3554373 | 535954400 | +0 | 103.7 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 42.62976 | 1.54665 | 44.27971 | 3.6 % | 115765 | 20752032 | +0 | 103.7 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 99.62658 | 7.16556 | 111.40863 | 7.2 % | 249401 | 63466032 | +0 | 103.7 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 206.16482 | 17.00022 | 232.48767 | 8.2 % | 526495 | 134945888 | +0 | 108.0 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 87.71193 | 7.98897 | 99.00579 | 9.1 % | 228999 | 55827744 | +0 | 108.6 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 198.82221 | 18.48605 | 221.35458 | 9.3 % | 484280 | 137463776 | +0 | 114.9 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 368.18865 | 9.64105 | 378.72087 | 2.6 % | 1025516 | 286467696 | +0 | 177.2 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 191.33888 | 10.44311 | 207.37775 | 5.5 % | 1236848 | 249935056 | +0 | 177.4 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 508.50129 | 28.93765 | 561.98904 | 5.7 % | 2634121 | 524105264 | +0 | 177.6 |
| `sweep.legacy` | segments | 128 | 4224 | 7 | 1 | 2833.50273 | 124.07723 | 2978.10708 | 4.4 % | 6057892 | 1210486000 | +0 | 180.0 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 15.09100 | 0.70120 | 16.12142 | 4.6 % | 100529 | 15713552 | +0 | 180.7 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 44.51023 | 1.79276 | 46.19058 | 4.0 % | 210352 | 47931248 | +0 | 181.9 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 100.94008 | 1.75730 | 103.41758 | 1.7 % | 449873 | 107867264 | +0 | 184.9 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 30.25394 | 1.20467 | 31.15921 | 4.0 % | 287370 | 34951712 | +0 | 184.9 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 701.18017 | 36.47394 | 774.34479 | 5.2 % | 1042546 | 198791584 | +0 | 193.9 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1479.96024 | 41.20542 | 1522.52050 | 2.8 % | 2008917 | 403883408 | +0 | 193.9 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 202.88848 | 10.04917 | 213.31813 | 5.0 % | 546392 | 133805120 | +0 | 193.9 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 195.21308 | 7.25851 | 202.17771 | 3.7 % | 526495 | 134945888 | +0 | 193.9 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.07478 | 0.00761 | 0.08388 | 10.2 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.00747 | 0.00077 | 0.00904 | 10.3 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 2703.82107 | 106.07015 | 2868.53312 | 3.9 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 21.47562 | 2.17727 | 25.82388 | 10.1 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 51.96940 | 6.60821 | 62.69083 | 12.7 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 2777.34835 | 114.30459 | 2957.14075 | 4.1 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02786 | 0.01243 | 0.05358 | 44.6 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00724 | 0.00069 | 0.00842 | 9.6 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 181.94718 | 9.63611 | 195.71183 | 5.3 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 5.13374 | 0.35438 | 5.56379 | 6.9 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 12.92942 | 1.10326 | 14.27437 | 8.5 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 200.04545 | 10.16446 | 215.50383 | 5.1 % | n/a | n/a | n/a | 213.2 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.03836 | 0.00515 | 0.04654 | 13.4 % | n/a | n/a | n/a | 213.3 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00691 | 0.00069 | 0.00829 | 10.0 % | n/a | n/a | n/a | 213.3 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 465.64798 | 22.22215 | 493.69708 | 4.8 % | n/a | n/a | n/a | 213.3 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 10.76252 | 1.87556 | 14.50488 | 17.4 % | n/a | n/a | n/a | 213.3 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 25.59602 | 2.48314 | 29.48492 | 9.7 % | n/a | n/a | n/a | 213.3 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 502.05180 | 23.96627 | 534.46654 | 4.8 % | n/a | n/a | n/a | 213.3 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3370.96383 | 483.94033 | 4137.83225 | 14.4 % | n/a | n/a | n/a | 213.3 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2986.08985 | 83.17328 | 3097.38688 | 2.8 % | n/a | n/a | n/a | 213.3 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 219.16150 | 18.07351 | 258.02008 | 8.2 % | n/a | n/a | n/a | 213.5 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 483.34530 | 20.01948 | 526.46758 | 4.1 % | n/a | n/a | n/a | 215.0 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 202.84065 | 19.07956 | 236.67117 | 9.4 % | n/a | n/a | n/a | 216.3 |

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
