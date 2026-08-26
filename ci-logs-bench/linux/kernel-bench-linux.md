# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-26T08:44:02Z |
| host | Linux / x86_64 |
| kernel | Prototype OCCT shim v28 (OCCT 7.9.3) (shim v28) |
| allocation counting | ld --wrap + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.085 | [1.067, 1.103] | 0.9999 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.082 | [2.039, 2.125] | 0.9998 | yes | **AGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.014 | [0.987, 1.041] | 0.9996 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.067 | 0.9998 | [1.047, 1.087] |
| `edgeInfo1` | edges | 4 | 1.085 | 0.9999 | [1.067, 1.103] |
| `allEdges` | edges | 4 | 2.082 | 0.9998 | [2.039, 2.125] |
| `allEdgesBulk` | edges | 4 | 1.036 | 0.9997 | [1.011, 1.060] |
| `buildOnly` | edges | 4 | 1.014 | 0.9996 | [0.987, 1.041] |
| `counts` | edges | 4 | 1.054 | 0.9995 | [1.021, 1.087] |
| `bbox` | edges | 4 | 0.968 | 0.9987 | [0.920, 1.017] |
| `mesh` | edges | 4 | 0.990 | 0.9997 | [0.968, 1.013] |
| `fuse` | edges | 4 | 1.283 | 0.9972 | [1.189, 1.378] |
| `cut` | edges | 4 | 1.299 | 0.9974 | [1.208, 1.391] |
| `rayHits` | edges | 4 | 0.285 | 0.9793 | [0.228, 0.343] |
| `filletEx1` | edges | 4 | 0.212 | 0.0983 | [-0.677, 1.100] |
| `fillet.edges` | edgesBlended | 3 | 0.623 | 0.9914 | [0.509, 0.736] |
| `fillet.scenario` | edgesBlended | 3 | 0.552 | 0.9850 | [0.419, 0.686] |
| `fillet.radius` | radius | 4 | 1.452 | 0.5973 | [-0.200, 3.104] |
| `sweep.segments` | segments | 3 | 1.162 | 0.9962 | [1.021, 1.303] |
| `sweep.holed` | segments | 3 | 1.108 | 0.9986 | [1.026, 1.190] |
| `sweep.legacy` | segments | 3 | 1.977 | 0.9782 | [1.399, 2.555] |
| `sweep.coil` | segments | 3 | 1.421 | 0.9717 | [0.946, 1.895] |
| `sweep.ph.build` | segments | 3 | 2.030 | 0.9781 | [1.434, 2.626] |
| `sweep.ph.unify` | segments | 3 | 1.076 | 0.9984 | [0.992, 1.160] |
| `sweep.ph.total` | segments | 3 | 1.979 | 0.9780 | [1.397, 2.562] |
| `sweep.spans` | spans | 5 | 0.378 | 0.0733 | [-1.142, 1.898] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.93515 | 0.01847 | 3.96969 | 0.5 % | 33890 | 4998037 | +0 | 10.6 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.08113 | 0.00029 | 0.08138 | 0.4 % | 821 | 150456 | +0 | 10.7 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 14.71301 | 0.09279 | 14.87544 | 0.6 % | 148205 | 27134202 | +0 | 10.7 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.74333 | 0.00198 | 0.74587 | 0.3 % | 6207 | 572858 | +0 | 10.7 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.34750 | 0.44024 | 12.30962 | 3.9 % | 84141 | 210180342 | -12999 | 14.4 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.08170 | 0.00063 | 0.08291 | 0.8 % | 375 | 55368 | +0 | 14.4 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.06469 | 0.01475 | 0.09814 | 22.8 % | 63 | 71064 | +0 | 14.4 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.55384 | 0.04124 | 4.63239 | 0.9 % | 34051 | 7905331 | +0 | 14.4 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 50.82389 | 0.31918 | 51.42572 | 0.6 % | 270376 | 61746072 | +0 | 19.4 |
| `cut` | edges | 180 | 180 | 7 | 1 | 46.66926 | 0.25614 | 47.12949 | 0.5 % | 242850 | 55320853 | +0 | 19.6 |
| `rayHits` | edges | 180 | 180 | 7 | 8 | 0.25238 | 0.00334 | 0.25830 | 1.3 % | 1976 | 287642 | +0 | 19.6 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 28.86061 | 0.37364 | 29.32765 | 1.3 % | 211444 | 24613554 | +0 | 21.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 8.18557 | 0.03581 | 8.24459 | 0.4 % | 67568 | 9755771 | +0 | 21.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.17070 | 0.00289 | 0.17593 | 1.7 % | 1601 | 255896 | +0 | 21.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 58.88644 | 0.14836 | 59.15670 | 0.3 % | 577205 | 92202266 | +0 | 21.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.57828 | 0.01856 | 1.60469 | 1.2 % | 12390 | 1116211 | +0 | 21.8 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 22.02036 | 0.22042 | 22.37037 | 1.0 % | 167656 | 415798569 | -25998 | 24.5 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.16380 | 0.00155 | 0.16651 | 0.9 % | 737 | 86248 | +0 | 24.5 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.11799 | 0.00049 | 0.11875 | 0.4 % | 123 | 138760 | +0 | 24.5 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 8.79659 | 0.04995 | 8.87332 | 0.6 % | 67916 | 14712486 | +0 | 24.5 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 113.13033 | 2.01865 | 117.13728 | 1.8 % | 614343 | 125204098 | +0 | 25.4 |
| `cut` | edges | 360 | 360 | 7 | 1 | 103.67648 | 0.71994 | 104.51857 | 0.7 % | 560348 | 112615873 | +0 | 25.4 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.28457 | 0.00256 | 0.28769 | 0.9 % | 2096 | 363039 | +0 | 25.4 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 9.45949 | 0.04062 | 9.52047 | 0.4 % | 68952 | 11048400 | +0 | 26.3 |
| `build` | edges | 720 | 720 | 7 | 1 | 16.85581 | 0.04695 | 16.93381 | 0.3 % | 134894 | 19067735 | +0 | 26.3 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.37124 | 0.04404 | 0.44476 | 11.9 % | 3161 | 465928 | +0 | 26.3 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 252.84181 | 5.82600 | 264.37359 | 2.3 % | 2277605 | 335631274 | +0 | 26.3 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.18916 | 0.08764 | 3.38430 | 2.7 % | 24751 | 2170927 | +0 | 26.3 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 45.32086 | 0.85447 | 47.22213 | 1.9 % | 334430 | 827083301 | -51979 | 31.4 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.33926 | 0.00397 | 0.34766 | 1.2 % | 1457 | 114904 | +0 | 31.4 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23853 | 0.00173 | 0.24160 | 0.7 % | 243 | 274104 | +0 | 31.4 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 17.55203 | 0.27516 | 18.06903 | 1.6 % | 135617 | 28308721 | +0 | 31.4 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 269.11894 | 1.75776 | 272.54154 | 0.7 % | 1539939 | 260088162 | +0 | 33.7 |
| `cut` | edges | 720 | 720 | 7 | 1 | 255.35798 | 9.53099 | 276.65706 | 3.7 % | 1432928 | 235104474 | +0 | 33.7 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.35524 | 0.00998 | 0.37732 | 2.8 % | 2336 | 509044 | +0 | 33.7 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 18.45185 | 0.13283 | 18.69423 | 0.7 % | 134712 | 21029970 | +0 | 33.7 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 36.40372 | 0.10330 | 36.56547 | 0.3 % | 269554 | 37905017 | +0 | 33.7 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.76840 | 0.00713 | 0.77520 | 0.9 % | 6285 | 950633 | +0 | 33.7 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1111.20297 | 1.35957 | 1113.20458 | 0.1 % | 9053767 | 1369203242 | +0 | 33.7 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 6.43312 | 0.03321 | 6.49964 | 0.5 % | 49476 | 4347669 | +0 | 33.7 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 92.85514 | 0.42884 | 93.62699 | 0.5 % | 668604 | 1650877856 | -103920 | 44.3 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.73164 | 0.00305 | 0.73832 | 0.4 % | 2899 | 204697 | +0 | 44.3 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.47944 | 0.00089 | 0.48065 | 0.2 % | 483 | 544824 | +0 | 44.3 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 35.66752 | 0.15956 | 35.96155 | 0.4 % | 271017 | 55013382 | +0 | 44.3 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 738.31285 | 11.77658 | 763.50522 | 1.6 % | 4342885 | 571937214 | +0 | 48.5 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 695.81170 | 8.27717 | 705.73447 | 1.2 % | 4130257 | 522048889 | +0 | 48.5 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.45311 | 0.00581 | 0.46466 | 1.3 % | 2816 | 804605 | +0 | 48.5 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 37.67042 | 0.12067 | 37.79248 | 0.3 % | 266270 | 41703602 | +0 | 48.5 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.71296 | 0.01084 | 2.72416 | 0.4 % | 25307 | 3984058 | +0 | 48.5 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.76383 | 0.00145 | 0.76611 | 0.2 % | 4013 | 302665 | +0 | 48.5 |
| `valid` | edges | 72 | 72 | 7 | 1 | 4.45304 | 0.03804 | 4.53567 | 0.9 % | 29913 | 4794646 | +0 | 48.5 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 12.69032 | 0.06135 | 12.78847 | 0.5 % | 92923 | 10991683 | +0 | 48.5 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.68827 | 0.05855 | 26.77388 | 0.2 % | 202410 | 21701310 | +0 | 50.1 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 60.19989 | 0.60038 | 61.35680 | 1.0 % | 486842 | 47291856 | +0 | 50.1 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 15.75448 | 0.91750 | 17.82894 | 5.8 % | 118230 | 15011547 | +0 | 50.1 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 29.42696 | 0.15964 | 29.73478 | 0.5 % | 227717 | 25713046 | +0 | 50.1 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 62.84433 | 0.47283 | 63.84281 | 0.8 % | 512149 | 51303112 | +0 | 50.1 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 26.75752 | 0.08068 | 26.84513 | 0.3 % | 203528 | 21786727 | +0 | 50.1 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.75264 | 0.29719 | 27.29704 | 1.1 % | 202410 | 21705623 | +0 | 50.1 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 26.45689 | 0.03923 | 26.51607 | 0.1 % | 202365 | 21689759 | +0 | 50.1 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 768.96469 | 1.73298 | 771.30079 | 0.2 % | 3554579 | 512441055 | +0 | 51.2 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 47.84703 | 0.35638 | 48.61655 | 0.7 % | 115749 | 19930602 | +0 | 51.2 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 116.72042 | 0.35797 | 117.19492 | 0.3 % | 249465 | 61443313 | +0 | 51.2 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 239.54356 | 0.65998 | 240.21995 | 0.3 % | 526502 | 130727769 | +0 | 79.9 |
| `sweep.holed` | segments | 32 | 192 | 7 | 1 | 98.79799 | 0.16901 | 99.06610 | 0.2 % | 228967 | 53738943 | +0 | 80.0 |
| `sweep.holed` | segments | 64 | 384 | 7 | 1 | 223.85170 | 0.31027 | 224.37052 | 0.1 % | 484408 | 132872251 | +0 | 84.1 |
| `sweep.holed` | segments | 128 | 768 | 7 | 1 | 458.81981 | 1.96757 | 462.17419 | 0.4 % | 1025529 | 277185130 | +0 | 146.7 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 233.13709 | 0.24090 | 233.41356 | 0.1 % | 1236869 | 235571231 | +0 | 146.7 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 643.97655 | 0.56371 | 645.00788 | 0.1 % | 2634211 | 495746118 | +0 | 146.7 |
| `sweep.legacy` | segments | 128 | 4224 | 6 | 1 | 3611.39677 | 16.33656 | 3637.85981 | 0.5 % | 6057816 | 1150938869 | +0 | 146.7 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 18.43250 | 0.09517 | 18.57869 | 0.5 % | 100513 | 14755677 | +0 | 146.7 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 66.00013 | 0.19120 | 66.40210 | 0.3 % | 226265 | 55178246 | +0 | 146.7 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 132.10004 | 0.20477 | 132.41794 | 0.2 % | 449824 | 104224139 | +0 | 146.7 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 33.15989 | 0.05943 | 33.22727 | 0.2 % | 287322 | 33567383 | +0 | 146.7 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 864.30064 | 1.71878 | 867.63237 | 0.2 % | 1042469 | 191374003 | +0 | 146.7 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1826.73040 | 2.33135 | 1830.42234 | 0.1 % | 2008842 | 381643497 | +0 | 146.7 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 230.03562 | 1.01148 | 232.08883 | 0.4 % | 546395 | 129693901 | +0 | 146.7 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 237.92746 | 0.33007 | 238.56459 | 0.1 % | 526502 | 130744112 | +0 | 146.7 |
| `sweep.ph.wire` | segments | 128 | 0 | 6 | 1 | 0.09897 | 0.00751 | 0.10795 | 7.6 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.spine` | segments | 128 | 0 | 6 | 1 | 0.01225 | 0.00539 | 0.02325 | 44.0 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.build` | segments | 128 | 0 | 6 | 1 | 3479.61386 | 21.02109 | 3516.91994 | 0.6 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.solid` | segments | 128 | 0 | 6 | 1 | 28.08388 | 1.61499 | 31.26213 | 5.8 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.unify` | segments | 128 | 0 | 6 | 1 | 66.08880 | 8.76385 | 83.48125 | 13.3 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.total` | segments | 128 | 0 | 6 | 1 | 3573.89775 | 24.90023 | 3614.02337 | 0.7 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.03580 | 0.00928 | 0.05037 | 25.9 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.01190 | 0.00360 | 0.01979 | 30.2 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 208.60078 | 0.99897 | 210.07512 | 0.5 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 6.37971 | 0.04900 | 6.43525 | 0.8 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 14.87233 | 0.13136 | 15.13434 | 0.9 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 229.90053 | 0.95163 | 231.33323 | 0.4 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.05188 | 0.00075 | 0.05316 | 1.4 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00962 | 0.00017 | 0.00991 | 1.8 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 591.50585 | 1.04317 | 593.12095 | 0.2 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 13.15443 | 0.06604 | 13.29221 | 0.5 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 29.77941 | 0.22998 | 30.05770 | 0.8 % | n/a | n/a | n/a | 146.7 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 634.50119 | 1.05221 | 636.32557 | 0.2 % | n/a | n/a | n/a | 146.7 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3532.15734 | 11.40704 | 3549.02805 | 0.3 % | n/a | n/a | n/a | 149.9 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3467.51503 | 9.83483 | 3478.25218 | 0.3 % | n/a | n/a | n/a | 149.9 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 237.38895 | 0.42821 | 238.07341 | 0.2 % | n/a | n/a | n/a | 149.9 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 534.02006 | 0.87483 | 535.62989 | 0.2 % | n/a | n/a | n/a | 149.9 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 224.97695 | 0.55451 | 225.93165 | 0.2 % | n/a | n/a | n/a | 149.9 |

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
