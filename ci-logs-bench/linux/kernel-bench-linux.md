# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T16:01:23Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v26 (OCCT 7.9.3) (shim v26) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.087 | [1.048, 1.127] | 0.9993 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.067 | [2.010, 2.124] | 0.9996 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.023 | [0.940, 1.107] | 0.9966 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.057 | 0.9999 | [1.039, 1.075] |
| `edgeInfo1` | edges | 4 | 1.087 | 0.9993 | [1.048, 1.127] |
| `allEdges` | edges | 4 | 2.067 | 0.9996 | [2.010, 2.124] |
| `allEdgesBulk` | edges | 4 | 1.017 | 0.9999 | [1.000, 1.034] |
| `buildOnly` | edges | 4 | 1.023 | 0.9966 | [0.940, 1.107] |
| `counts` | edges | 4 | 1.066 | 0.9998 | [1.046, 1.087] |
| `bbox` | edges | 4 | 1.030 | 0.9972 | [0.953, 1.106] |
| `mesh` | edges | 4 | 0.992 | 0.9992 | [0.954, 1.029] |
| `fuse` | edges | 4 | 1.286 | 0.9974 | [1.194, 1.377] |
| `cut` | edges | 4 | 1.295 | 0.9968 | [1.193, 1.397] |
| `rayHits` | edges | 4 | 0.274 | 0.9573 | [0.193, 0.354] |
| `filletEx1` | edges | 4 | 0.204 | 0.0918 | [-0.686, 1.095] |
| `fillet.edges` | edgesBlended | 3 | 0.616 | 0.9901 | [0.495, 0.736] |
| `fillet.scenario` | edgesBlended | 3 | 0.560 | 0.9872 | [0.435, 0.685] |
| `fillet.radius` | radius | 4 | 1.448 | 0.5989 | [-0.194, 3.089] |
| `sweep.segments` | segments | 3 | 1.172 | 0.9955 | [1.018, 1.325] |
| `sweep.legacy` | segments | 3 | 1.993 | 0.9789 | [1.419, 2.567] |
| `sweep.coil` | segments | 3 | 1.429 | 0.9687 | [0.926, 1.932] |
| `sweep.ph.build` | segments | 3 | 2.040 | 0.9783 | [1.445, 2.636] |
| `sweep.ph.unify` | segments | 3 | 1.126 | 0.9958 | [0.982, 1.270] |
| `sweep.ph.total` | segments | 3 | 1.991 | 0.9780 | [1.406, 2.576] |
| `sweep.spans` | spans | 5 | 0.384 | 0.0750 | [-1.143, 1.911] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.95274 | 0.02376 | 3.99367 | 0.6 % | 33890 | 4998039 | +0 | 10.3 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08002 | 0.00076 | 0.08153 | 1.0 % | 821 | 150504 | +0 | 10.5 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.34848 | 2.10104 | 20.10587 | 13.7 % | 148205 | 27142874 | +0 | 10.5 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.78089 | 0.05592 | 0.86211 | 7.2 % | 6207 | 572853 | +0 | 10.5 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.34952 | 0.18258 | 11.69725 | 1.6 % | 84141 | 210183443 | -12999 | 14.6 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08050 | 0.00030 | 0.08087 | 0.4 % | 375 | 55352 | +0 | 14.6 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05641 | 0.00238 | 0.06180 | 4.2 % | 63 | 71064 | +0 | 14.6 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.61227 | 0.11706 | 4.85289 | 2.5 % | 34051 | 7905336 | +0 | 14.6 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 51.51496 | 0.60665 | 52.69606 | 1.2 % | 270320 | 61731350 | +0 | 19.5 |
| `cut` | edges | 180 | 180 | 7 | 1 | 47.15285 | 0.40402 | 47.88813 | 0.9 % | 242923 | 55325082 | +0 | 19.5 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25847 | 0.00235 | 0.26340 | 0.9 % | 1976 | 287647 | +0 | 19.5 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 29.45693 | 0.21540 | 29.74158 | 0.7 % | 211444 | 24606631 | +0 | 21.6 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.13585 | 0.08186 | 8.28744 | 1.0 % | 67568 | 9755634 | +0 | 21.6 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.17020 | 0.00623 | 0.18394 | 3.7 % | 1601 | 255864 | +0 | 21.6 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 61.40072 | 0.16422 | 61.66293 | 0.3 % | 577205 | 92190762 | +0 | 21.6 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.61059 | 0.04434 | 1.70654 | 2.8 % | 12390 | 1116192 | +0 | 21.6 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.07237 | 0.18245 | 22.44590 | 0.8 % | 167656 | 415796185 | -25984 | 24.2 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16399 | 0.00086 | 0.16489 | 0.5 % | 737 | 86328 | +0 | 24.2 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11282 | 0.00028 | 0.11322 | 0.3 % | 123 | 138744 | +0 | 24.2 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.80543 | 0.12905 | 8.99698 | 1.5 % | 67916 | 14717501 | +0 | 24.2 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 113.49031 | 0.54003 | 114.17421 | 0.5 % | 614310 | 125200223 | +0 | 25.3 |
| `cut` | edges | 360 | 360 | 7 | 1 | 104.12214 | 0.54557 | 104.92601 | 0.5 % | 560327 | 112619048 | +0 | 25.3 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.28587 | 0.00106 | 0.28709 | 0.4 % | 2096 | 361106 | +0 | 25.3 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.50667 | 0.06308 | 9.63777 | 0.7 % | 68952 | 10994078 | +0 | 26.3 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.74275 | 0.12693 | 17.02257 | 0.8 % | 134894 | 19067710 | +0 | 26.3 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.34582 | 0.00128 | 0.34836 | 0.4 % | 3161 | 465928 | +0 | 26.3 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 251.62632 | 2.69110 | 257.59218 | 1.1 % | 2277605 | 335619674 | +0 | 26.3 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.25800 | 0.11849 | 3.48789 | 3.6 % | 24751 | 2170877 | +0 | 26.3 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 50.40808 | 4.86969 | 60.59849 | 9.7 % | 334430 | 827092841 | -51945 | 31.4 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.34618 | 0.02695 | 0.40668 | 7.8 % | 1457 | 114712 | +0 | 31.4 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.25395 | 0.00206 | 0.25822 | 0.8 % | 243 | 274104 | +0 | 31.4 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 18.52265 | 0.64604 | 19.96318 | 3.5 % | 135617 | 28303818 | +0 | 31.4 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 276.31579 | 9.50204 | 297.05760 | 3.4 % | 1539705 | 259996267 | +0 | 33.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 252.34487 | 1.48285 | 254.63477 | 0.6 % | 1432973 | 235292787 | +0 | 33.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.34517 | 0.00342 | 0.35092 | 1.0 % | 2336 | 510019 | +0 | 33.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.86634 | 0.09277 | 19.06424 | 0.5 % | 134712 | 21031968 | +0 | 33.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 35.72668 | 0.17456 | 36.00679 | 0.5 % | 269554 | 37904898 | +0 | 33.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.77919 | 0.00923 | 0.79885 | 1.2 % | 6285 | 950745 | +0 | 33.2 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1138.17470 | 9.24466 | 1158.42602 | 0.8 % | 9053767 | 1369341498 | +0 | 33.2 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.47018 | 0.02997 | 6.53427 | 0.5 % | 49476 | 4347698 | +0 | 33.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 91.66238 | 1.39513 | 94.09943 | 1.5 % | 668604 | 1650871083 | -103911 | 46.6 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.73712 | 0.00698 | 0.75010 | 0.9 % | 2899 | 204729 | +0 | 46.6 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.46461 | 0.00182 | 0.46723 | 0.4 % | 483 | 544824 | +0 | 46.6 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 35.57710 | 0.58263 | 36.84274 | 1.6 % | 271017 | 54972390 | +0 | 46.6 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 746.62119 | 8.36567 | 761.86756 | 1.1 % | 4342712 | 571431343 | +0 | 50.0 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 699.13250 | 5.87087 | 709.81179 | 0.8 % | 4130180 | 521806173 | +0 | 50.0 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.45666 | 0.00292 | 0.46191 | 0.6 % | 2816 | 804847 | +0 | 50.0 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.58547 | 0.12102 | 37.72699 | 0.3 % | 266270 | 41697193 | +0 | 50.0 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.69399 | 0.02462 | 2.73556 | 0.9 % | 25307 | 4020072 | +0 | 50.0 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.76490 | 0.00135 | 0.76772 | 0.2 % | 4013 | 302664 | +0 | 50.0 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.45796 | 0.02558 | 4.50928 | 0.6 % | 29913 | 4794056 | +0 | 50.0 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.93291 | 0.20520 | 13.19937 | 1.6 % | 92923 | 10992115 | +0 | 50.0 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.73437 | 0.05726 | 26.81121 | 0.2 % | 202410 | 21711015 | +0 | 51.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 60.31622 | 0.24523 | 60.62138 | 0.4 % | 486842 | 47299707 | +0 | 51.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 15.57906 | 0.14064 | 15.78060 | 0.9 % | 118230 | 15015541 | +0 | 51.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 29.66903 | 0.16224 | 29.88825 | 0.5 % | 227717 | 25734673 | +0 | 51.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 63.27824 | 0.31036 | 63.81848 | 0.5 % | 512149 | 51333427 | +0 | 51.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.98991 | 0.12193 | 27.20609 | 0.5 % | 203528 | 21790126 | +0 | 51.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 27.07616 | 0.39211 | 27.90364 | 1.4 % | 202410 | 21711577 | +0 | 51.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 26.87120 | 0.13438 | 27.02192 | 0.5 % | 202365 | 21704495 | +0 | 51.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 767.23614 | 2.00760 | 770.10513 | 0.3 % | 3554579 | 512333400 | +0 | 52.7 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 47.56467 | 0.13938 | 47.82294 | 0.3 % | 115749 | 19926335 | +0 | 53.2 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 117.71930 | 0.68475 | 119.03901 | 0.6 % | 249465 | 61433891 | +0 | 53.2 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 241.32854 | 0.78454 | 242.61336 | 0.3 % | 526502 | 130710533 | +0 | 81.2 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 233.30835 | 0.70208 | 234.38967 | 0.3 % | 1236869 | 235584758 | +0 | 81.2 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 653.43828 | 7.10495 | 662.84723 | 1.1 % | 2634211 | 495724849 | +0 | 81.2 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3697.50801 | 23.53387 | 3723.03082 | 0.6 % | 6057816 | 1150856936 | +0 | 81.2 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 18.61841 | 0.04022 | 18.67670 | 0.2 % | 100513 | 14756719 | +0 | 81.2 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 68.23061 | 0.15772 | 68.48026 | 0.2 % | 226265 | 55177117 | +0 | 81.2 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 134.97344 | 0.45549 | 135.52079 | 0.3 % | 449824 | 104232551 | +0 | 81.2 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 32.87001 | 0.05620 | 32.95878 | 0.2 % | 287322 | 33586110 | +0 | 81.2 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 875.85672 | 10.98304 | 899.72312 | 1.3 % | 1042469 | 191375725 | +0 | 81.2 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1854.48978 | 3.16480 | 1857.59886 | 0.2 % | 2008842 | 381605328 | +0 | 81.2 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 232.88179 | 0.99399 | 234.08099 | 0.4 % | 546395 | 129690369 | +0 | 81.2 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 241.36924 | 1.52117 | 244.50154 | 0.6 % | 526502 | 130763753 | +0 | 81.2 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.11169 | 0.02529 | 0.16321 | 22.6 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01235 | 0.00485 | 0.02224 | 39.3 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3568.38584 | 12.73012 | 3586.72355 | 0.4 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 33.17154 | 2.75107 | 36.34270 | 8.3 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 70.66956 | 6.24990 | 78.12153 | 8.8 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3672.35098 | 18.39726 | 3698.76239 | 0.5 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.03955 | 0.00731 | 0.05115 | 18.5 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.02251 | 0.02875 | 0.08750 | 127.7 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 210.93375 | 1.08560 | 212.94143 | 0.5 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.63019 | 0.11970 | 6.77612 | 1.8 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 14.83442 | 0.07423 | 14.92292 | 0.5 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 232.46042 | 1.12126 | 234.48377 | 0.5 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.06336 | 0.00092 | 0.06445 | 1.5 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00970 | 0.00021 | 0.01005 | 2.2 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 602.38083 | 2.45150 | 605.64252 | 0.4 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 13.71572 | 0.20240 | 13.97791 | 1.5 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 29.64749 | 0.59126 | 30.75087 | 2.0 % | n/a | n/a | n/a | 81.2 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 645.81711 | 2.42146 | 648.67851 | 0.4 % | n/a | n/a | n/a | 81.2 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3590.05360 | 17.93085 | 3621.36469 | 0.5 % | n/a | n/a | n/a | 88.5 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3521.31806 | 10.62901 | 3536.66676 | 0.3 % | n/a | n/a | n/a | 88.5 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 241.64004 | 1.77774 | 243.87182 | 0.7 % | n/a | n/a | n/a | 88.5 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 539.09166 | 1.99192 | 542.69256 | 0.4 % | n/a | n/a | n/a | 88.5 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 228.69745 | 0.86195 | 230.33760 | 0.4 % | n/a | n/a | n/a | 94.1 |

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
