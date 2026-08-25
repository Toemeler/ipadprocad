# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T10:11:45Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v28 (OCCT 7.9.3) (shim v28) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.136 | [0.979, 1.293] | 0.9901 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.049 | [1.981, 2.117] | 0.9994 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.991 | [0.938, 1.043] | 0.9985 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.079 | 0.9995 | [1.043, 1.114] |
| `edgeInfo1` | edges | 4 | 1.136 | 0.9901 | [0.979, 1.293] |
| `allEdges` | edges | 4 | 2.049 | 0.9994 | [1.981, 2.117] |
| `allEdgesBulk` | edges | 4 | 1.042 | 1.0000 | [1.035, 1.050] |
| `buildOnly` | edges | 4 | 0.991 | 0.9985 | [0.938, 1.043] |
| `counts` | edges | 4 | 1.036 | 0.9985 | [0.981, 1.092] |
| `bbox` | edges | 4 | 0.987 | 1.0000 | [0.980, 0.995] |
| `mesh` | edges | 4 | 0.987 | 0.9997 | [0.964, 1.010] |
| `fuse` | edges | 4 | 1.294 | 0.9973 | [1.201, 1.387] |
| `cut` | edges | 4 | 1.299 | 0.9975 | [1.209, 1.388] |
| `rayHits` | edges | 4 | 0.326 | 0.9526 | [0.225, 0.427] |
| `filletEx1` | edges | 4 | 0.215 | 0.0961 | [-0.698, 1.127] |
| `fillet.edges` | edgesBlended | 3 | 0.616 | 0.9915 | [0.504, 0.728] |
| `fillet.scenario` | edgesBlended | 3 | 0.557 | 0.9879 | [0.436, 0.678] |
| `fillet.radius` | radius | 4 | 1.496 | 0.5974 | [-0.206, 3.199] |
| `sweep.segments` | segments | 3 | 1.166 | 0.9964 | [1.028, 1.304] |
| `sweep.holed` | segments | 3 | 1.106 | 0.9984 | [1.019, 1.192] |
| `sweep.legacy` | segments | 3 | 2.052 | 0.9696 | [1.340, 2.764] |
| `sweep.coil` | segments | 3 | 1.427 | 0.9694 | [0.930, 1.925] |
| `sweep.ph.build` | segments | 3 | 2.101 | 0.9684 | [1.358, 2.845] |
| `sweep.ph.unify` | segments | 3 | 1.076 | 0.9999 | [1.051, 1.101] |
| `sweep.ph.total` | segments | 3 | 2.050 | 0.9688 | [1.330, 2.771] |
| `sweep.spans` | spans | 5 | 0.377 | 0.0662 | [-1.223, 1.976] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 2.87085 | 0.01856 | 2.90563 | 0.6 % | 33890 | 4998139 | +0 | 10.6 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 64 | 0.06125 | 0.00017 | 0.06146 | 0.3 % | 821 | 151512 | +0 | 10.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 11.16348 | 0.08029 | 11.31271 | 0.7 % | 148205 | 27324330 | +0 | 10.7 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.53741 | 0.00473 | 0.54688 | 0.9 % | 6207 | 573182 | +0 | 10.7 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 8.89870 | 0.27522 | 9.18496 | 3.1 % | 84141 | 210180520 | -13022 | 14.7 |
| `counts` | edges | 180 | 180 | 7 | 64 | 0.05852 | 0.00023 | 0.05888 | 0.4 % | 375 | 55360 | +0 | 14.7 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.04580 | 0.00019 | 0.04608 | 0.4 % | 63 | 71064 | +0 | 14.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 3.40429 | 0.01646 | 3.43461 | 0.5 % | 34051 | 7905391 | +0 | 14.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 40.06089 | 0.12664 | 40.30426 | 0.3 % | 270363 | 61743538 | +0 | 19.3 |
| `cut` | edges | 180 | 180 | 7 | 1 | 36.94518 | 0.12730 | 37.15610 | 0.3 % | 242856 | 55314038 | +0 | 19.3 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.17678 | 0.00377 | 0.18519 | 2.1 % | 1976 | 289927 | +0 | 19.4 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 22.27852 | 2.47478 | 27.88829 | 11.1 % | 211444 | 24609378 | +0 | 21.6 |
| `build` | edges | 360 | 360 | 7 | 1 | 5.99847 | 0.24542 | 6.55314 | 4.1 % | 67568 | 9755586 | +0 | 21.6 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 32 | 0.12216 | 0.00126 | 0.12452 | 1.0 % | 1601 | 255800 | +0 | 21.6 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 44.43918 | 1.10639 | 46.92846 | 2.5 % | 577205 | 92173370 | +0 | 21.6 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.11913 | 0.00688 | 1.12821 | 0.6 % | 12390 | 1116175 | +0 | 21.6 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 16.49487 | 0.43642 | 17.43812 | 2.6 % | 167656 | 415793534 | -25982 | 24.4 |
| `counts` | edges | 360 | 360 | 7 | 32 | 0.11449 | 0.00035 | 0.11517 | 0.3 % | 737 | 86136 | +0 | 24.4 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.08980 | 0.00046 | 0.09084 | 0.5 % | 123 | 138744 | +0 | 24.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 6.60922 | 0.10206 | 6.81287 | 1.5 % | 67916 | 14717615 | +0 | 24.4 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 88.71884 | 0.24143 | 89.04648 | 0.3 % | 614324 | 125233086 | +0 | 25.2 |
| `cut` | edges | 360 | 360 | 7 | 1 | 82.22060 | 0.23263 | 82.55245 | 0.3 % | 560419 | 112669624 | +0 | 25.2 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.19501 | 0.00108 | 0.19721 | 0.6 % | 2096 | 361218 | +0 | 25.2 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 6.98584 | 0.08668 | 7.17687 | 1.2 % | 68952 | 10996747 | +0 | 26.3 |
| `build` | edges | 720 | 720 | 7 | 1 | 12.27832 | 0.09087 | 12.45887 | 0.7 % | 134894 | 19067426 | +0 | 26.3 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 16 | 0.24405 | 0.00111 | 0.24616 | 0.5 % | 3161 | 466008 | +0 | 26.3 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 175.81949 | 0.65569 | 176.58807 | 0.4 % | 2277605 | 335677400 | +0 | 26.3 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 2.28609 | 0.02127 | 2.31012 | 0.9 % | 24751 | 2170925 | +0 | 26.3 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 35.31372 | 0.35662 | 35.80535 | 1.0 % | 334430 | 827105168 | -52002 | 31.4 |
| `counts` | edges | 720 | 720 | 7 | 16 | 0.23019 | 0.00104 | 0.23149 | 0.5 % | 1457 | 114904 | +0 | 31.4 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.17942 | 0.00898 | 0.19974 | 5.0 % | 243 | 274104 | +0 | 31.4 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 13.56131 | 0.09020 | 13.69012 | 0.7 % | 135617 | 28315663 | +0 | 31.4 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 216.89832 | 4.03320 | 225.76264 | 1.9 % | 1539798 | 260266858 | +0 | 33.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 202.26655 | 2.33060 | 205.56702 | 1.2 % | 1432964 | 235231592 | +0 | 33.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.25060 | 0.00228 | 0.25361 | 0.9 % | 2336 | 508979 | +0 | 33.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 14.37305 | 0.38182 | 15.03729 | 2.7 % | 134712 | 21030507 | +0 | 33.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 27.32377 | 1.98776 | 31.30364 | 7.3 % | 269554 | 37904896 | +0 | 33.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.67145 | 0.09929 | 0.80559 | 14.8 % | 6285 | 950569 | +0 | 33.2 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 802.85343 | 1.26586 | 804.45913 | 0.2 % | 9053767 | 1369110970 | +0 | 33.2 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 4.70452 | 0.08781 | 4.88629 | 1.9 % | 49476 | 4347573 | +0 | 33.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 68.11803 | 0.28484 | 68.70542 | 0.4 % | 668604 | 1650884558 | -103936 | 42.8 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.50832 | 0.01065 | 0.52289 | 2.1 % | 2899 | 204617 | +0 | 42.8 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.35597 | 0.00071 | 0.35663 | 0.2 % | 483 | 544824 | +0 | 42.8 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 26.21126 | 0.18269 | 26.56459 | 0.7 % | 271017 | 55034534 | +0 | 42.8 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 591.62470 | 14.50885 | 623.74983 | 2.5 % | 4342730 | 572340561 | +0 | 48.3 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 550.02527 | 3.16422 | 556.81726 | 0.6 % | 4130141 | 522443350 | +0 | 48.3 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.34521 | 0.00205 | 0.34822 | 0.6 % | 2816 | 804689 | +0 | 48.3 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 28.76484 | 0.07972 | 28.88534 | 0.3 % | 266270 | 41702978 | +0 | 48.3 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 2 | 1.94869 | 0.00427 | 1.95464 | 0.2 % | 25307 | 4021545 | +0 | 48.3 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.58583 | 0.00280 | 0.59136 | 0.5 % | 4013 | 303912 | +0 | 48.3 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.27660 | 0.02174 | 3.32264 | 0.7 % | 29913 | 4794289 | +0 | 48.3 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 9.53763 | 0.03034 | 9.57540 | 0.3 % | 92923 | 10992561 | +0 | 48.3 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 19.91110 | 0.03331 | 19.94812 | 0.2 % | 202410 | 21698347 | +0 | 49.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 44.52628 | 0.15751 | 44.81013 | 0.4 % | 486842 | 47290080 | +0 | 49.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 11.56892 | 0.03805 | 11.64653 | 0.3 % | 118230 | 15018229 | +0 | 49.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 22.04367 | 0.08421 | 22.20546 | 0.4 % | 227717 | 25742381 | +0 | 49.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 46.67766 | 0.11439 | 46.79699 | 0.2 % | 512149 | 51325425 | +0 | 49.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 20.16688 | 0.05414 | 20.23324 | 0.3 % | 203528 | 21782939 | +0 | 49.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 19.95992 | 0.02513 | 19.99241 | 0.1 % | 202410 | 21703051 | +0 | 49.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 19.94192 | 0.08403 | 20.07229 | 0.4 % | 202365 | 21690289 | +0 | 49.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 640.29129 | 0.93201 | 642.06912 | 0.1 % | 3554579 | 512303695 | +0 | 50.9 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 36.78483 | 0.48696 | 37.68360 | 1.3 % | 115749 | 19923697 | +0 | 51.4 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 89.82757 | 0.05416 | 89.92114 | 0.1 % | 249465 | 61438543 | +0 | 51.4 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 185.17503 | 0.50971 | 186.31518 | 0.3 % | 526502 | 130741627 | +0 | 79.4 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 77.69804 | 0.37967 | 78.53457 | 0.5 % | 228967 | 53744259 | +0 | 79.5 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 176.30932 | 1.42981 | 179.24776 | 0.8 % | 484408 | 132858567 | +0 | 83.8 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 359.82693 | 1.10689 | 362.02179 | 0.3 % | 1025529 | 277175443 | +0 | 146.3 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 175.25537 | 0.41036 | 175.79519 | 0.2 % | 1236869 | 235569846 | +0 | 146.3 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 469.86969 | 0.41554 | 470.45137 | 0.1 % | 2634211 | 495768863 | +0 | 146.3 |
| `sweep.legacy` | segments | 128 | 4224 | 7 | 1 | 3013.32229 | 2.56406 | 3018.20769 | 0.1 % | 6057816 | 1150938517 | +0 | 146.3 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 14.18916 | 0.05372 | 14.28721 | 0.4 % | 100513 | 14757050 | +0 | 146.3 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 51.74977 | 0.10099 | 51.86834 | 0.2 % | 226265 | 55175105 | +0 | 146.3 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 102.62328 | 0.18445 | 102.93748 | 0.2 % | 449824 | 104226421 | +0 | 146.3 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 24.38876 | 0.06992 | 24.50791 | 0.3 % | 287322 | 33560811 | +0 | 146.3 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 752.40975 | 1.50343 | 753.72211 | 0.2 % | 1042469 | 191383046 | +0 | 146.3 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1598.94141 | 1.83119 | 1602.16423 | 0.1 % | 2008842 | 381599762 | +0 | 146.3 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 177.60800 | 0.11476 | 177.74508 | 0.1 % | 546395 | 129689825 | +0 | 146.3 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 185.08815 | 0.53156 | 186.22368 | 0.3 % | 526502 | 130749883 | +0 | 146.3 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.07508 | 0.00641 | 0.08705 | 8.5 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.00879 | 0.00307 | 0.01575 | 34.9 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 2909.99359 | 7.81316 | 2924.08514 | 0.3 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 22.48722 | 0.17373 | 22.66524 | 0.8 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 47.35324 | 1.54057 | 50.77508 | 3.3 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 2979.91793 | 8.39620 | 2993.71082 | 0.3 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.03195 | 0.00760 | 0.04529 | 23.8 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00975 | 0.00219 | 0.01373 | 22.5 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 158.02743 | 0.89176 | 159.59653 | 0.6 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 4.96672 | 0.05326 | 5.03686 | 1.1 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 10.65405 | 0.08048 | 10.73325 | 0.8 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 173.68990 | 0.90883 | 175.25088 | 0.5 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04342 | 0.00495 | 0.05360 | 11.4 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00718 | 0.00022 | 0.00747 | 3.1 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 430.04225 | 0.50924 | 430.58515 | 0.1 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 10.44882 | 0.12050 | 10.70824 | 1.2 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 22.11709 | 0.34411 | 22.78639 | 1.6 % | n/a | n/a | n/a | 146.3 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 462.65876 | 0.80894 | 464.12735 | 0.2 % | n/a | n/a | n/a | 146.3 |
| `sweep.var.v23poly` | segments | 128 | 0 | 7 | 1 | 2965.46016 | 2.48661 | 2970.16908 | 0.1 % | n/a | n/a | n/a | 146.3 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2919.97508 | 2.92910 | 2926.07443 | 0.1 % | n/a | n/a | n/a | 146.3 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 178.37661 | 0.48947 | 179.09700 | 0.3 % | n/a | n/a | n/a | 146.3 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 426.47406 | 0.65379 | 427.24625 | 0.2 % | n/a | n/a | n/a | 146.3 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 176.21568 | 0.29493 | 176.53967 | 0.2 % | n/a | n/a | n/a | 146.3 |

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
