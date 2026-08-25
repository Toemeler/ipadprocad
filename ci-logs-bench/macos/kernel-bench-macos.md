# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-25T07:32:16Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v27 (OCCT 7.9.3) (shim v27) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.724 | [1.162, 2.285] | 0.9477 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 1.974 | [1.830, 2.118] | 0.9972 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 0.798 | [0.731, 0.864] | 0.9964 | no | **DISAGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.069 | 0.8821 | [0.527, 1.610] |
| `edgeInfo1` | edges | 4 | 1.724 | 0.9477 | [1.162, 2.285] |
| `allEdges` | edges | 4 | 1.974 | 0.9972 | [1.830, 2.118] |
| `allEdgesBulk` | edges | 4 | 0.778 | 0.9045 | [0.428, 1.128] |
| `buildOnly` | edges | 4 | 0.798 | 0.9964 | [0.731, 0.864] |
| `counts` | edges | 4 | 0.929 | 0.9864 | [0.778, 1.080] |
| `bbox` | edges | 4 | 0.784 | 0.9924 | [0.689, 0.879] |
| `mesh` | edges | 4 | 0.969 | 0.9796 | [0.775, 1.163] |
| `fuse` | edges | 4 | 1.475 | 0.9978 | [1.379, 1.572] |
| `cut` | edges | 4 | 1.280 | 0.9975 | [1.192, 1.369] |
| `rayHits` | edges | 4 | -0.049 | 0.0820 | [-0.276, 0.178] |
| `filletEx1` | edges | 4 | 0.074 | 0.0102 | [-0.931, 1.078] |
| `fillet.edges` | edgesBlended | 3 | 0.617 | 0.9999 | [0.608, 0.625] |
| `fillet.scenario` | edgesBlended | 3 | 0.549 | 0.9994 | [0.524, 0.575] |
| `fillet.radius` | radius | 4 | 1.473 | 0.5797 | [-0.265, 3.212] |
| `sweep.segments` | segments | 3 | 1.067 | 0.9995 | [1.020, 1.113] |
| `sweep.holed` | segments | 3 | 1.043 | 0.9987 | [0.970, 1.116] |
| `sweep.legacy` | segments | 3 | 1.915 | 0.9755 | [1.321, 2.510] |
| `sweep.coil` | segments | 3 | 1.439 | 0.9964 | [1.270, 1.609] |
| `sweep.ph.build` | segments | 3 | 1.895 | 0.9672 | [1.211, 2.580] |
| `sweep.ph.unify` | segments | 3 | 0.986 | 0.9928 | [0.822, 1.151] |
| `sweep.ph.total` | segments | 3 | 1.845 | 0.9690 | [1.199, 2.492] |
| `sweep.spans` | spans | 5 | 0.349 | 0.0648 | [-1.151, 1.848] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.60134 | 0.16076 | 3.84896 | 4.5 % | 33890 | 5335600 | +0 | 14.3 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.09650 | 0.00942 | 0.11273 | 9.8 % | 821 | 158368 | +0 | 14.3 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 24.61548 | 2.66607 | 28.25908 | 10.8 % | 148205 | 28566976 | +0 | 14.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 1 | 1.52045 | 1.13672 | 3.78904 | 74.8 % | 6209 | 596032 | +0 | 14.5 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 18.56049 | 3.08837 | 24.85700 | 16.6 % | 84071 | 225974848 | -12160 | 22.7 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.12777 | 0.03101 | 0.18436 | 24.3 % | 375 | 59360 | +0 | 22.7 |
| `bbox` | edges | 180 | 180 | 7 | 32 | 0.08981 | 0.03665 | 0.15671 | 40.8 % | 63 | 80640 | +0 | 22.7 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 5.57019 | 1.33990 | 7.70221 | 24.1 % | 34056 | 13154158 | +0 | 22.7 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 44.58818 | 1.05651 | 46.43204 | 2.4 % | 270341 | 66612327 | +0 | 28.6 |
| `cut` | edges | 180 | 180 | 7 | 1 | 55.44006 | 21.40379 | 100.45321 | 38.6 % | 242897 | 59654279 | +0 | 28.7 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.43228 | 0.27710 | 1.03091 | 64.1 % | 1976 | 308336 | +0 | 28.7 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 39.37006 | 7.65249 | 51.06612 | 19.4 % | 211425 | 25882480 | +0 | 30.2 |
| `build` | edges | 360 | 360 | 7 | 1 | 16.76430 | 15.25534 | 50.59821 | 91.0 % | 67568 | 10408048 | +0 | 30.2 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.16476 | 0.00801 | 0.18089 | 4.9 % | 1601 | 269728 | +0 | 30.2 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 78.36233 | 20.86003 | 107.59692 | 26.6 % | 577205 | 97204096 | +0 | 30.2 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 1 | 1.61545 | 0.33778 | 2.33650 | 20.9 % | 12392 | 1160128 | +0 | 30.2 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 31.22726 | 3.46366 | 36.75688 | 11.1 % | 167561 | 446577664 | -24320 | 36.4 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.24356 | 0.07099 | 0.35468 | 29.1 % | 737 | 93024 | +0 | 36.4 |
| `bbox` | edges | 360 | 360 | 7 | 8 | 0.17653 | 0.04847 | 0.27673 | 27.5 % | 123 | 157440 | +0 | 36.4 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 13.12995 | 1.82959 | 15.20954 | 13.9 % | 67923 | 24575301 | +0 | 36.8 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 128.91613 | 22.43997 | 159.95817 | 17.4 % | 614332 | 133966183 | +0 | 40.7 |
| `cut` | edges | 360 | 360 | 7 | 1 | 137.92617 | 10.26019 | 155.05225 | 7.4 % | 560335 | 120358032 | +0 | 40.7 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.37266 | 0.15568 | 0.71109 | 41.8 % | 2096 | 392112 | +0 | 40.7 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 11.56698 | 3.14549 | 16.46700 | 27.2 % | 68952 | 11624128 | +0 | 40.9 |
| `build` | edges | 720 | 720 | 7 | 1 | 23.21382 | 3.41922 | 28.78908 | 14.7 % | 134894 | 20360432 | +0 | 40.9 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.57187 | 0.19658 | 0.84445 | 34.4 % | 3161 | 492448 | +0 | 40.9 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 367.82480 | 65.48490 | 461.53246 | 17.8 % | 2277605 | 354747136 | +0 | 40.9 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.48038 | 1.18618 | 6.47121 | 26.5 % | 24753 | 2255552 | +0 | 40.9 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 51.71680 | 12.34060 | 76.82712 | 23.9 % | 334258 | 888838496 | -48640 | 53.7 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.39125 | 0.02988 | 0.44137 | 7.6 % | 1457 | 127584 | +0 | 53.7 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.26757 | 0.02305 | 0.30330 | 8.6 % | 243 | 311040 | +0 | 53.7 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 19.21495 | 1.37765 | 21.92058 | 7.2 % | 135627 | 48367506 | +0 | 53.8 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 314.73995 | 34.78896 | 363.97854 | 11.1 % | 1539766 | 274711307 | +0 | 62.1 |
| `cut` | edges | 720 | 720 | 7 | 1 | 299.09724 | 58.70611 | 376.08938 | 19.6 % | 1432942 | 247775760 | +0 | 62.1 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.30597 | 0.04794 | 0.41192 | 15.7 % | 2336 | 559664 | +0 | 62.1 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 15.66173 | 0.21120 | 15.88179 | 1.3 % | 134712 | 22247488 | +0 | 62.1 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 38.16142 | 7.11067 | 50.09687 | 18.6 % | 269554 | 40496624 | +0 | 62.1 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 1 | 3.42047 | 3.61374 | 10.95067 | 105.7 % | 6285 | 1003424 | +0 | 62.1 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1405.49531 | 141.56411 | 1632.61429 | 10.1 % | 9053767 | 1445313024 | +0 | 62.1 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.52928 | 0.45617 | 7.07146 | 7.0 % | 49478 | 4511936 | +0 | 62.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 99.11204 | 26.07374 | 142.44804 | 26.3 % | 668060 | 1775223216 | -97280 | 86.3 |
| `counts` | edges | 1440 | 1440 | 7 | 2 | 0.93341 | 0.44587 | 1.79833 | 47.8 % | 2899 | 229472 | +0 | 86.3 |
| `bbox` | edges | 1440 | 1440 | 7 | 4 | 0.47830 | 0.04808 | 0.55115 | 10.1 % | 483 | 618240 | +0 | 86.3 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 46.02782 | 8.92837 | 62.12817 | 19.4 % | 271030 | 96173390 | +0 | 87.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1000.80376 | 140.57589 | 1165.60483 | 14.0 % | 4342706 | 590682160 | +0 | 103.1 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 825.30415 | 83.59339 | 959.42533 | 10.1 % | 4130157 | 536948021 | +0 | 103.1 |
| `rayHits` | edges | 1440 | 1440 | 7 | 4 | 0.41221 | 0.03114 | 0.45404 | 7.6 % | 2816 | 894768 | +0 | 103.1 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 42.18763 | 10.40457 | 61.18312 | 24.7 % | 266270 | 44116800 | +0 | 103.1 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 3.09348 | 0.36358 | 3.75283 | 11.8 % | 25307 | 4253072 | +0 | 103.1 |
| `volume` | edges | 72 | 72 | 7 | 2 | 0.71220 | 0.04921 | 0.77410 | 6.9 % | 4013 | 309760 | +0 | 103.1 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.71907 | 0.78622 | 5.79525 | 16.7 % | 29913 | 5127328 | +0 | 103.1 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.85614 | 1.58141 | 14.79513 | 12.3 % | 92919 | 11590416 | +0 | 103.1 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 29.95190 | 4.06092 | 38.18187 | 13.6 % | 202372 | 22644144 | +0 | 103.1 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 59.54691 | 10.59092 | 82.56867 | 17.8 % | 486810 | 49139568 | +0 | 103.1 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 14.07224 | 0.53502 | 14.76025 | 3.8 % | 118226 | 15843488 | +0 | 103.1 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 29.32349 | 4.04105 | 36.78758 | 13.8 % | 227679 | 26897216 | +0 | 103.1 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 55.18126 | 1.06421 | 56.10575 | 1.9 % | 512117 | 53392640 | +0 | 103.1 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 23.75903 | 0.90630 | 25.40471 | 3.8 % | 202345 | 22639152 | +0 | 103.1 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 25.08286 | 3.02688 | 31.15517 | 12.1 % | 202372 | 22644144 | +0 | 103.1 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 21.81088 | 0.39639 | 22.45346 | 1.8 % | 202370 | 22640112 | +0 | 103.1 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 748.83461 | 87.55719 | 902.02400 | 11.7 % | 3554373 | 535954400 | +0 | 103.1 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 44.81383 | 0.58852 | 45.62738 | 1.3 % | 115765 | 20752032 | +0 | 103.1 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 96.59272 | 3.13914 | 99.57600 | 3.2 % | 249401 | 63466032 | +0 | 103.1 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 196.62490 | 2.08252 | 199.37404 | 1.1 % | 526495 | 134945888 | +0 | 112.0 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 89.14440 | 9.10457 | 109.43867 | 10.2 % | 228999 | 55827744 | +0 | 112.5 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 192.05919 | 14.87989 | 223.36404 | 7.7 % | 484280 | 137463776 | +0 | 119.1 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 378.52624 | 24.81210 | 420.07592 | 6.6 % | 1025516 | 286467696 | +0 | 181.4 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 215.93996 | 25.42931 | 273.18279 | 11.8 % | 1236848 | 249935056 | +0 | 181.5 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 565.95535 | 29.93179 | 611.98804 | 5.3 % | 2634121 | 524105264 | +0 | 181.7 |
| `sweep.legacy` | segments | 128 | 4224 | 7 | 1 | 3072.37607 | 258.35332 | 3450.74546 | 8.4 % | 6057892 | 1210486000 | +0 | 184.0 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 14.89876 | 0.57985 | 15.56354 | 3.9 % | 100529 | 15713552 | +0 | 184.8 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 44.82336 | 2.78311 | 48.90129 | 6.2 % | 210352 | 47931248 | +0 | 186.3 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 109.59411 | 6.35053 | 120.19496 | 5.8 % | 449873 | 107867264 | +0 | 189.2 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 30.20837 | 0.61412 | 30.86658 | 2.0 % | 287370 | 34951712 | +0 | 189.2 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 759.44673 | 75.17194 | 898.58229 | 9.9 % | 1042546 | 198791584 | +0 | 198.2 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1498.26935 | 45.45450 | 1568.48858 | 3.0 % | 2008917 | 403883408 | +0 | 198.3 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 185.85060 | 8.22120 | 201.08929 | 4.4 % | 546392 | 133805120 | +0 | 198.3 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 204.50457 | 8.44863 | 220.29487 | 4.1 % | 526495 | 134945888 | +0 | 198.3 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.12278 | 0.11138 | 0.37188 | 90.7 % | n/a | n/a | n/a | 217.5 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.10765 | 0.24918 | 0.67229 | 231.5 % | n/a | n/a | n/a | 217.5 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 2977.81004 | 241.26477 | 3428.07450 | 8.1 % | n/a | n/a | n/a | 217.5 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 26.27145 | 6.16818 | 39.28342 | 23.5 % | n/a | n/a | n/a | 217.5 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 62.36037 | 5.05485 | 70.73129 | 8.1 % | n/a | n/a | n/a | 217.5 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 3066.67229 | 246.61212 | 3520.96458 | 8.0 % | n/a | n/a | n/a | 217.5 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02964 | 0.00604 | 0.04075 | 20.4 % | n/a | n/a | n/a | 217.6 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00779 | 0.00096 | 0.00912 | 12.3 % | n/a | n/a | n/a | 217.6 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 215.15124 | 23.48613 | 254.98917 | 10.9 % | n/a | n/a | n/a | 217.6 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.36779 | 0.93622 | 7.46612 | 14.7 % | n/a | n/a | n/a | 217.6 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 15.89145 | 2.40892 | 19.38308 | 15.2 % | n/a | n/a | n/a | 217.6 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 237.44790 | 26.14774 | 280.31621 | 11.0 % | n/a | n/a | n/a | 217.6 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04752 | 0.00781 | 0.06208 | 16.4 % | n/a | n/a | n/a | 217.7 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00815 | 0.00175 | 0.01167 | 21.5 % | n/a | n/a | n/a | 217.7 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 526.38149 | 44.94895 | 602.00742 | 8.5 % | n/a | n/a | n/a | 217.7 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 13.02255 | 1.86223 | 15.94275 | 14.3 % | n/a | n/a | n/a | 217.7 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 34.81658 | 14.83898 | 68.05754 | 42.6 % | n/a | n/a | n/a | 217.7 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 574.27630 | 46.38499 | 644.93217 | 8.1 % | n/a | n/a | n/a | 217.7 |
| `sweep.var.v23poly` | segments | 128 | 0 | 7 | 1 | 3350.89758 | 557.07810 | 4359.22796 | 16.6 % | n/a | n/a | n/a | 217.7 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 3171.08812 | 378.87120 | 3845.08929 | 11.9 % | n/a | n/a | n/a | 217.7 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 221.59424 | 28.95909 | 279.16858 | 13.1 % | n/a | n/a | n/a | 217.9 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 457.10549 | 29.29103 | 506.01971 | 6.4 % | n/a | n/a | n/a | 219.5 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 170.50475 | 7.66287 | 185.76137 | 4.5 % | n/a | n/a | n/a | 220.8 |

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
