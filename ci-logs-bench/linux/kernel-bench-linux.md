# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T07:44:53Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.049 | [0.982, 1.116] | 0.9979 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.068 | [1.996, 2.140] | 0.9994 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.006 | [0.971, 1.040] | 0.9994 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.064 | 0.9997 | [1.039, 1.088] |
| `edgeInfo1` | edges | 4 | 1.049 | 0.9979 | [0.982, 1.116] |
| `allEdges` | edges | 4 | 2.068 | 0.9994 | [1.996, 2.140] |
| `allEdgesBulk` | edges | 4 | 1.041 | 0.9998 | [1.022, 1.059] |
| `buildOnly` | edges | 4 | 1.006 | 0.9994 | [0.971, 1.040] |
| `counts` | edges | 4 | 1.047 | 0.9995 | [1.014, 1.080] |
| `bbox` | edges | 4 | 0.987 | 0.9997 | [0.965, 1.009] |
| `mesh` | edges | 4 | 0.981 | 0.9996 | [0.954, 1.007] |
| `fuse` | edges | 4 | 1.286 | 0.9975 | [1.196, 1.376] |
| `cut` | edges | 4 | 1.300 | 0.9980 | [1.219, 1.381] |
| `rayHits` | edges | 4 | 0.310 | 0.9711 | [0.236, 0.384] |
| `filletEx1` | edges | 4 | 0.223 | 0.1068 | [-0.670, 1.116] |
| `fillet.edges` | edgesBlended | 3 | 0.618 | 0.9918 | [0.508, 0.728] |
| `fillet.scenario` | edgesBlended | 3 | 0.560 | 0.9890 | [0.444, 0.676] |
| `fillet.radius` | radius | 4 | 1.474 | 0.5989 | [-0.198, 3.147] |
| `sweep.segments` | segments | 3 | 1.172 | 0.9961 | [1.029, 1.316] |
| `sweep.holed` | segments | 3 | 1.107 | 0.9985 | [1.022, 1.191] |
| `sweep.legacy` | segments | 3 | 2.049 | 0.9708 | [1.353, 2.745] |
| `sweep.coil` | segments | 3 | 1.426 | 0.9692 | [0.928, 1.924] |
| `sweep.ph.build` | segments | 3 | 2.099 | 0.9711 | [1.389, 2.810] |
| `sweep.ph.unify` | segments | 3 | 1.089 | 1.0000 | [1.075, 1.103] |
| `sweep.ph.total` | segments | 3 | 2.048 | 0.9716 | [1.362, 2.735] |
| `sweep.spans` | spans | 5 | 0.375 | 0.0661 | [-1.220, 1.970] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.67567 | 0.01910 | 3.70080 | 0.5 % | 33890 | 4998048 | +0 | 10.7 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.07922 | 0.00192 | 0.08344 | 2.4 % | 821 | 150472 | +0 | 10.9 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 14.28573 | 0.17705 | 14.65139 | 1.2 % | 148205 | 27137098 | +0 | 10.9 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.68694 | 0.00437 | 0.69246 | 0.6 % | 6207 | 572861 | +0 | 10.9 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.09893 | 0.37075 | 11.74536 | 3.3 % | 84141 | 210178717 | -12999 | 14.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.07382 | 0.00068 | 0.07515 | 0.9 % | 375 | 55352 | +0 | 14.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05843 | 0.00354 | 0.06621 | 6.1 % | 63 | 71064 | +0 | 14.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.47316 | 0.15697 | 4.79189 | 3.5 % | 34051 | 7904097 | +0 | 14.8 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 52.68257 | 0.96499 | 54.80325 | 1.8 % | 270351 | 61735867 | +0 | 19.6 |
| `cut` | edges | 180 | 180 | 7 | 1 | 47.76419 | 0.25673 | 48.19972 | 0.5 % | 242887 | 55308073 | +0 | 19.6 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.22878 | 0.00345 | 0.23545 | 1.5 % | 1976 | 288016 | +0 | 19.6 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 27.95273 | 0.23303 | 28.33336 | 0.8 % | 211444 | 24604944 | +0 | 21.9 |
| `build` | edges | 360 | 360 | 7 | 1 | 7.54571 | 0.02355 | 7.57636 | 0.3 % | 67568 | 9755577 | +0 | 21.9 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.15396 | 0.00086 | 0.15525 | 0.6 % | 1601 | 255768 | +0 | 21.9 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 55.73469 | 0.11821 | 55.91711 | 0.2 % | 577205 | 92173418 | +0 | 21.9 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.45273 | 0.00979 | 1.46190 | 0.7 % | 12390 | 1116208 | +0 | 21.9 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 21.16887 | 0.20327 | 21.56845 | 1.0 % | 167656 | 415794071 | -25979 | 24.6 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.14853 | 0.00116 | 0.15093 | 0.8 % | 737 | 86328 | +0 | 24.6 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11215 | 0.00047 | 0.11304 | 0.4 % | 123 | 138744 | +0 | 24.6 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.48421 | 0.07931 | 8.61147 | 0.9 % | 67916 | 14715393 | +0 | 24.6 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 115.58310 | 0.58530 | 116.57600 | 0.5 % | 614245 | 125155200 | +0 | 25.6 |
| `cut` | edges | 360 | 360 | 7 | 1 | 107.28508 | 1.07096 | 108.99801 | 1.0 % | 560373 | 112694679 | +0 | 25.6 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.26323 | 0.00370 | 0.26724 | 1.4 % | 2096 | 361043 | +0 | 25.6 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.15713 | 0.05956 | 9.24722 | 0.7 % | 68952 | 10994229 | +0 | 26.5 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.59127 | 0.07014 | 15.68262 | 0.4 % | 134894 | 19067813 | +0 | 26.5 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.31334 | 0.00417 | 0.31938 | 1.3 % | 3161 | 466103 | +0 | 26.5 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 230.95385 | 1.66015 | 233.88626 | 0.7 % | 2277605 | 335758106 | +0 | 26.5 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.92831 | 0.01381 | 2.94817 | 0.5 % | 24751 | 2170931 | +0 | 26.5 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 44.04509 | 0.31971 | 44.54770 | 0.7 % | 334430 | 827076475 | -51973 | 30.9 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.30262 | 0.00330 | 0.30814 | 1.1 % | 1457 | 115112 | +0 | 30.9 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.22607 | 0.00099 | 0.22801 | 0.4 % | 243 | 274104 | +0 | 30.9 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.24216 | 0.20990 | 17.59950 | 1.2 % | 135617 | 28293295 | +0 | 30.9 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 284.12270 | 3.58950 | 289.88193 | 1.3 % | 1539817 | 260149181 | +0 | 33.6 |
| `cut` | edges | 720 | 720 | 7 | 1 | 264.65055 | 9.02173 | 283.88310 | 3.4 % | 1432915 | 235228974 | +0 | 33.6 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.32260 | 0.00232 | 0.32710 | 0.7 % | 2336 | 511098 | +0 | 33.6 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.15351 | 0.06938 | 18.24755 | 0.4 % | 134712 | 21025733 | +0 | 33.6 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 33.69241 | 0.41352 | 34.37931 | 1.2 % | 269554 | 37904857 | +0 | 33.6 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.70548 | 0.00968 | 0.71770 | 1.4 % | 6285 | 950647 | +0 | 33.6 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1057.13211 | 9.53796 | 1077.84150 | 0.9 % | 9053767 | 1369249306 | +0 | 33.6 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.01912 | 0.04637 | 6.11729 | 0.8 % | 49476 | 4347650 | +0 | 33.6 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 88.78685 | 1.11634 | 91.07007 | 1.3 % | 668604 | 1650855776 | -103922 | 43.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.65391 | 0.01735 | 0.68183 | 2.7 % | 2899 | 204713 | +0 | 43.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.45222 | 0.00341 | 0.45984 | 0.8 % | 483 | 544824 | +0 | 43.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 34.04624 | 0.25646 | 34.54590 | 0.8 % | 271017 | 55026182 | +0 | 43.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 761.95929 | 4.64509 | 768.96732 | 0.6 % | 4343018 | 572082703 | +0 | 49.3 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 712.65199 | 3.84035 | 716.81710 | 0.5 % | 4130171 | 521527272 | +0 | 49.3 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.43775 | 0.00340 | 0.44364 | 0.8 % | 2816 | 805199 | +0 | 49.3 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.23594 | 0.24932 | 37.78886 | 0.7 % | 266270 | 41700448 | +0 | 49.3 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.48964 | 0.00936 | 2.50458 | 0.4 % | 25307 | 3995642 | +0 | 49.3 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.77633 | 0.00283 | 0.78144 | 0.4 % | 4013 | 302664 | +0 | 49.3 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.23473 | 0.03855 | 4.29854 | 0.9 % | 29913 | 4793869 | +0 | 49.3 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.29187 | 0.06215 | 12.37052 | 0.5 % | 92923 | 10990216 | +0 | 49.3 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 25.78573 | 0.22123 | 26.26559 | 0.9 % | 202410 | 21699367 | +0 | 50.9 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 57.66830 | 0.17783 | 57.90411 | 0.3 % | 486842 | 47285113 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.91603 | 0.02653 | 14.95357 | 0.2 % | 118230 | 15001273 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 28.69018 | 0.87412 | 30.64842 | 3.0 % | 227717 | 25712655 | +0 | 50.9 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 60.58145 | 0.85318 | 62.48599 | 1.4 % | 512149 | 51294209 | +0 | 50.9 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.98099 | 0.12274 | 26.22783 | 0.5 % | 203528 | 21781458 | +0 | 50.9 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.76253 | 0.10052 | 25.90853 | 0.4 % | 202410 | 21705280 | +0 | 50.9 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.85533 | 0.18331 | 26.22622 | 0.7 % | 202365 | 21691832 | +0 | 50.9 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 782.54394 | 2.19956 | 787.28081 | 0.3 % | 3554579 | 512457135 | +0 | 51.9 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 46.92928 | 0.08275 | 47.10577 | 0.2 % | 115749 | 19929862 | +0 | 51.9 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 115.47892 | 0.21460 | 115.80988 | 0.2 % | 249465 | 61437976 | +0 | 51.9 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 238.38677 | 1.72900 | 241.42818 | 0.7 % | 526502 | 130722176 | +0 | 80.6 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 99.30803 | 0.30229 | 99.67245 | 0.3 % | 228967 | 53744765 | +0 | 80.6 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 225.18269 | 0.39995 | 225.68331 | 0.2 % | 484408 | 132871691 | +0 | 84.7 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 460.44178 | 5.52776 | 472.80815 | 1.2 % | 1025529 | 277176621 | +0 | 147.3 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 224.14850 | 1.16754 | 226.12629 | 0.5 % | 1236869 | 235596317 | +0 | 147.3 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 605.62699 | 2.35750 | 608.94261 | 0.4 % | 2634211 | 495721480 | +0 | 147.3 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3838.88330 | 18.33473 | 3864.33290 | 0.5 % | 6057816 | 1150964219 | +0 | 147.3 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 18.23357 | 0.06219 | 18.33645 | 0.3 % | 100513 | 14755725 | +0 | 147.3 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 66.44722 | 0.31544 | 67.08630 | 0.5 % | 226265 | 55172618 | +0 | 147.3 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 131.56528 | 0.30406 | 132.03970 | 0.2 % | 449824 | 104235577 | +0 | 147.3 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 31.51292 | 0.12409 | 31.74286 | 0.4 % | 287322 | 33574738 | +0 | 147.3 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 958.94769 | 1.25127 | 961.24500 | 0.1 % | 1042469 | 191385853 | +0 | 150.3 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 2041.60640 | 2.29364 | 2043.47689 | 0.1 % | 2008842 | 381604738 | +0 | 151.4 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 228.72505 | 0.63218 | 229.51737 | 0.3 % | 546395 | 129683537 | +0 | 151.4 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 236.66817 | 0.32407 | 237.25297 | 0.1 % | 526502 | 130759906 | +0 | 151.4 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.09821 | 0.02011 | 0.13910 | 20.5 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01022 | 0.00241 | 0.01512 | 23.5 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3745.35050 | 19.87913 | 3761.27900 | 0.5 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 30.69483 | 2.34422 | 34.21376 | 7.6 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 62.80657 | 2.56093 | 66.85757 | 4.1 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3838.96034 | 22.23610 | 3855.61473 | 0.6 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.04314 | 0.00889 | 0.05591 | 20.6 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01017 | 0.00233 | 0.01488 | 22.9 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 203.95220 | 1.14283 | 206.19027 | 0.6 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.46032 | 0.30232 | 7.13776 | 4.7 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 13.87711 | 0.37756 | 14.62653 | 2.7 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 224.34294 | 1.18399 | 226.17764 | 0.5 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.06590 | 0.00583 | 0.07498 | 8.8 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00873 | 0.00031 | 0.00938 | 3.6 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 565.69220 | 6.35683 | 573.14223 | 1.1 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 14.25999 | 0.68150 | 14.99250 | 4.8 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 29.27187 | 1.01041 | 30.60024 | 3.5 % | n/a | n/a | n/a | 151.4 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 609.29869 | 7.69670 | 618.14619 | 1.3 % | n/a | n/a | n/a | 151.4 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3870.14878 | 37.74649 | 3938.58185 | 1.0 % | n/a | n/a | n/a | 151.4 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3917.20585 | 61.00501 | 3990.87250 | 1.6 % | n/a | n/a | n/a | 151.4 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 275.27949 | 5.25286 | 280.24331 | 1.9 % | n/a | n/a | n/a | 151.4 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 587.53578 | 12.85735 | 601.79568 | 2.2 % | n/a | n/a | n/a | 151.4 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 227.70908 | 1.02854 | 229.25526 | 0.5 % | n/a | n/a | n/a | 151.4 |

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
