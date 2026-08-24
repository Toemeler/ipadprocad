# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T23:32:47Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v26 (OCCT 7.9.3) (shim v26) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.987 | [0.903, 1.070] | 0.9963 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.032 | [1.978, 2.085] | 0.9996 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.036 | [0.960, 1.113] | 0.9972 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 0.959 | 0.9966 | [0.881, 1.036] |
| `edgeInfo1` | edges | 4 | 0.987 | 0.9963 | [0.903, 1.070] |
| `allEdges` | edges | 4 | 2.032 | 0.9996 | [1.978, 2.085] |
| `allEdgesBulk` | edges | 4 | 0.965 | 0.9807 | [0.777, 1.153] |
| `buildOnly` | edges | 4 | 1.036 | 0.9972 | [0.960, 1.113] |
| `counts` | edges | 4 | 0.964 | 0.9998 | [0.945, 0.983] |
| `bbox` | edges | 4 | 0.980 | 0.9918 | [0.856, 1.104] |
| `mesh` | edges | 4 | 0.898 | 0.9807 | [0.723, 1.073] |
| `fuse` | edges | 4 | 1.323 | 0.9974 | [1.229, 1.417] |
| `cut` | edges | 4 | 1.385 | 0.9986 | [1.313, 1.458] |
| `rayHits` | edges | 4 | 0.310 | 0.9326 | [0.194, 0.425] |
| `filletEx1` | edges | 4 | 0.089 | 0.0142 | [-0.943, 1.122] |
| `fillet.edges` | edgesBlended | 3 | 0.620 | 0.9919 | [0.511, 0.730] |
| `fillet.scenario` | edgesBlended | 3 | 0.554 | 0.9758 | [0.383, 0.725] |
| `fillet.radius` | radius | 4 | 1.553 | 0.6274 | [-0.106, 3.211] |
| `sweep.segments` | segments | 3 | 1.183 | 1.0000 | [1.176, 1.190] |
| `sweep.legacy` | segments | 3 | 1.807 | 0.9537 | [1.027, 2.588] |
| `sweep.coil` | segments | 3 | 1.415 | 0.9890 | [1.123, 1.707] |
| `sweep.ph.build` | segments | 3 | 2.030 | 0.9713 | [1.345, 2.714] |
| `sweep.ph.unify` | segments | 3 | 1.216 | 1.0000 | [1.214, 1.219] |
| `sweep.ph.total` | segments | 3 | 1.987 | 0.9725 | [1.332, 2.641] |
| `sweep.spans` | spans | 5 | 0.348 | 0.0642 | [-1.154, 1.850] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 4.29682 | 0.58999 | 5.51933 | 13.7 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08848 | 0.00443 | 0.09778 | 5.0 % | 821 | 158368 | +0 | 14.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 17.00658 | 1.94427 | 20.35350 | 11.4 % | 148205 | 28566976 | +0 | 14.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.77068 | 0.08039 | 0.89853 | 10.4 % | 6209 | 596032 | +0 | 14.4 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 9.94731 | 0.25799 | 10.31625 | 2.6 % | 84071 | 225974848 | -12160 | 22.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08932 | 0.01855 | 0.13038 | 20.8 % | 375 | 59360 | +0 | 22.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.06285 | 0.00861 | 0.07972 | 13.7 % | 63 | 80640 | +0 | 22.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.06496 | 0.74425 | 6.10904 | 14.7 % | 34056 | 13154158 | +0 | 22.8 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 46.69873 | 2.47913 | 50.70433 | 5.3 % | 270331 | 66610279 | +0 | 28.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 39.68602 | 1.16263 | 41.50833 | 2.9 % | 242874 | 59649598 | +0 | 28.5 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.21987 | 0.01910 | 0.25960 | 8.7 % | 1976 | 308336 | +0 | 28.6 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 34.89948 | 7.86424 | 51.53929 | 22.5 % | 211425 | 25882480 | +0 | 30.3 |
| `build` | edges | 360 | 360 | 7 | 1 | 9.12173 | 1.09136 | 10.83429 | 12.0 % | 67568 | 10408048 | +0 | 30.3 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.17131 | 0.00303 | 0.17489 | 1.8 % | 1601 | 269728 | +0 | 30.3 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 73.45921 | 8.52579 | 86.84275 | 11.6 % | 577205 | 97204096 | +0 | 30.3 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 1.93436 | 1.07655 | 4.11217 | 55.7 % | 12392 | 1160128 | +0 | 30.3 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.56140 | 2.08243 | 26.38563 | 9.2 % | 167561 | 446577664 | -24320 | 36.8 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.17122 | 0.01725 | 0.20757 | 10.1 % | 737 | 93024 | +0 | 36.8 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.12694 | 0.02281 | 0.17642 | 18.0 % | 123 | 157440 | +0 | 36.8 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 11.90751 | 3.09107 | 17.39688 | 26.0 % | 67923 | 24575301 | +0 | 36.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 123.51833 | 11.90652 | 136.10654 | 9.6 % | 614231 | 133945557 | +0 | 40.5 |
| `cut` | edges | 360 | 360 | 7 | 1 | 95.08160 | 3.02283 | 98.19542 | 3.2 % | 560385 | 120368272 | +0 | 40.5 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.25446 | 0.03141 | 0.32404 | 12.3 % | 2096 | 392112 | +0 | 40.5 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 8.61190 | 0.64370 | 9.65612 | 7.5 % | 68952 | 11624128 | +0 | 40.7 |
| `build` | edges | 720 | 720 | 7 | 1 | 15.80148 | 1.09421 | 16.90737 | 6.9 % | 134894 | 20360432 | +0 | 40.7 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.31460 | 0.01379 | 0.33403 | 4.4 % | 3161 | 492448 | +0 | 40.7 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 277.22302 | 22.66791 | 308.90692 | 8.2 % | 2277605 | 354747136 | +0 | 40.7 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.90533 | 0.14508 | 3.08829 | 5.0 % | 24753 | 2255552 | +0 | 40.8 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 41.50627 | 2.18959 | 44.76842 | 5.3 % | 334258 | 888838496 | -48640 | 53.5 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.34370 | 0.00764 | 0.35531 | 2.2 % | 1457 | 127584 | +0 | 53.5 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.28276 | 0.08381 | 0.44494 | 29.6 % | 243 | 311040 | +0 | 53.5 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.36213 | 0.62077 | 18.59479 | 3.6 % | 135627 | 48367506 | +0 | 53.5 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 270.39406 | 15.73162 | 293.31712 | 5.8 % | 1539800 | 274718329 | +0 | 61.9 |
| `cut` | edges | 720 | 720 | 7 | 1 | 250.47164 | 14.24178 | 277.28679 | 5.7 % | 1432880 | 247763033 | +0 | 61.9 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.29322 | 0.01740 | 0.32046 | 5.9 % | 2336 | 559664 | +0 | 61.9 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 16.54983 | 1.37962 | 19.20388 | 8.3 % | 134712 | 22247488 | +0 | 61.9 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 32.77091 | 1.33431 | 34.80267 | 4.1 % | 269554 | 40496624 | +0 | 61.9 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.70649 | 0.02347 | 0.74726 | 3.3 % | 6285 | 1003424 | +0 | 61.9 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1193.99916 | 116.19410 | 1415.90796 | 9.7 % | 9053767 | 1445313024 | +0 | 61.9 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.25795 | 0.27111 | 6.75488 | 4.3 % | 49478 | 4511936 | +0 | 62.0 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 88.96849 | 3.56488 | 95.00483 | 4.0 % | 668060 | 1775223216 | -97280 | 87.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.65640 | 0.01795 | 0.67831 | 2.7 % | 2899 | 229472 | +0 | 87.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46318 | 0.01761 | 0.49870 | 3.8 % | 483 | 618240 | +0 | 87.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 35.56969 | 2.18261 | 38.12342 | 6.1 % | 271030 | 96173390 | +0 | 87.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 764.29269 | 22.94081 | 801.12479 | 3.0 % | 4342703 | 590681575 | +0 | 103.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 705.60020 | 26.40501 | 738.18929 | 3.7 % | 4130158 | 536948167 | +0 | 103.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.42886 | 0.05688 | 0.54171 | 13.3 % | 2816 | 894768 | +0 | 103.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 34.51369 | 1.52883 | 36.07858 | 4.4 % | 266270 | 44116800 | +0 | 103.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.78490 | 0.31744 | 3.41167 | 11.4 % | 25307 | 4253072 | +0 | 103.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.65438 | 0.02602 | 0.68195 | 4.0 % | 4013 | 309760 | +0 | 103.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.04290 | 0.10774 | 4.17387 | 2.7 % | 29913 | 5127328 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 11.78118 | 0.99084 | 13.91004 | 8.4 % | 92919 | 11590416 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 24.79541 | 1.01332 | 26.12283 | 4.1 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 55.54870 | 3.49268 | 61.02163 | 6.3 % | 486810 | 49139568 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 15.32740 | 1.22451 | 17.94392 | 8.0 % | 118226 | 15843488 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 27.56631 | 0.16941 | 27.84712 | 0.6 % | 227679 | 26897216 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 61.55364 | 3.08195 | 64.47642 | 5.0 % | 512117 | 53392640 | +0 | 103.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 24.14858 | 0.54200 | 25.06433 | 2.2 % | 202345 | 22639152 | +0 | 103.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 24.45258 | 0.49875 | 25.27792 | 2.0 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 27.26802 | 2.85467 | 31.64317 | 10.5 % | 202370 | 22640112 | +0 | 103.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 841.89511 | 87.80535 | 920.71225 | 10.4 % | 3554373 | 535954400 | +0 | 103.6 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 55.84730 | 10.12215 | 72.25633 | 18.1 % | 115765 | 20752032 | +0 | 103.6 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 126.24780 | 5.98763 | 133.34854 | 4.7 % | 249401 | 63466032 | +0 | 103.6 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 287.79586 | 15.50586 | 305.06292 | 5.4 % | 526495 | 134945888 | +0 | 112.1 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 315.16958 | 21.04924 | 353.32150 | 6.7 % | 1236848 | 249935056 | +0 | 112.3 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 683.86412 | 54.87368 | 805.11000 | 8.0 % | 2634121 | 524105264 | +0 | 112.4 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3860.72612 | 128.94191 | 4012.42404 | 3.3 % | 6057892 | 1210486000 | +0 | 114.7 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 18.06529 | 3.47857 | 23.41646 | 19.3 % | 100529 | 15713552 | +0 | 115.6 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 57.60493 | 4.61484 | 63.20617 | 8.0 % | 210352 | 47931248 | +0 | 117.2 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 128.42060 | 6.28922 | 140.01221 | 4.9 % | 449873 | 107867264 | +0 | 120.2 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 37.09330 | 5.32383 | 47.50254 | 14.4 % | 287370 | 34951712 | +0 | 120.2 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 939.16768 | 45.31847 | 1013.52150 | 4.8 % | 1042546 | 198791584 | +0 | 131.5 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1863.18142 | 67.38937 | 1949.79733 | 3.6 % | 2008917 | 403883408 | +0 | 131.6 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 250.59805 | 20.29913 | 283.48229 | 8.1 % | 546392 | 133805120 | +0 | 132.2 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 239.57154 | 8.82575 | 253.29896 | 3.7 % | 526495 | 134945888 | +0 | 132.2 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.11749 | 0.07005 | 0.23446 | 59.6 % | n/a | n/a | n/a | 149.9 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.01510 | 0.00973 | 0.03488 | 64.5 % | n/a | n/a | n/a | 149.9 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 3093.20239 | 445.51127 | 3782.02804 | 14.4 % | n/a | n/a | n/a | 149.9 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 26.83929 | 8.24236 | 44.06129 | 30.7 % | n/a | n/a | n/a | 149.9 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 67.63890 | 24.00902 | 118.41563 | 35.5 % | n/a | n/a | n/a | 149.9 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 3187.81317 | 471.33398 | 3890.55771 | 14.8 % | n/a | n/a | n/a | 149.9 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02344 | 0.00554 | 0.03429 | 23.6 % | n/a | n/a | n/a | 150.0 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00694 | 0.00032 | 0.00737 | 4.6 % | n/a | n/a | n/a | 150.0 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 185.54007 | 1.50395 | 188.03292 | 0.8 % | n/a | n/a | n/a | 150.0 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 4.89854 | 0.20309 | 5.20096 | 4.1 % | n/a | n/a | n/a | 150.0 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 12.52660 | 0.24660 | 12.82687 | 2.0 % | n/a | n/a | n/a | 150.0 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 202.99558 | 1.42658 | 205.15938 | 0.7 % | n/a | n/a | n/a | 150.0 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04304 | 0.00357 | 0.04925 | 8.3 % | n/a | n/a | n/a | 150.1 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00746 | 0.00050 | 0.00850 | 6.7 % | n/a | n/a | n/a | 150.1 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 498.18721 | 40.44096 | 557.31508 | 8.1 % | n/a | n/a | n/a | 150.1 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 11.48824 | 1.20021 | 13.75042 | 10.4 % | n/a | n/a | n/a | 150.1 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 29.06014 | 3.53690 | 34.13308 | 12.2 % | n/a | n/a | n/a | 150.1 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 538.78608 | 41.82264 | 596.43454 | 7.8 % | n/a | n/a | n/a | 150.1 |
| `sweep.var.v23poly` | segments | 128 | 0 | 7 | 1 | 2755.51920 | 76.82336 | 2899.30813 | 2.8 % | n/a | n/a | n/a | 150.1 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2712.01127 | 117.00151 | 2888.30642 | 4.3 % | n/a | n/a | n/a | 150.1 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 219.25586 | 31.31243 | 265.10113 | 14.3 % | n/a | n/a | n/a | 150.4 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 594.65382 | 43.25513 | 663.57004 | 7.3 % | n/a | n/a | n/a | 151.9 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 226.29763 | 53.94047 | 347.99125 | 23.8 % | n/a | n/a | n/a | 160.1 |

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
