# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T16:58:31Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v26 (OCCT 7.9.3) (shim v26) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 0.917 | [0.578, 1.255] | 0.9336 | yes | **AGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.134 | [1.985, 2.283] | 0.9975 | yes | **AGREES** | [1.996, 2.027] → AGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.114 | [0.996, 1.232] | 0.9942 | no | **AGREES** | same convention |

**Harness verdict: VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.024 | 0.9295 | [0.633, 1.415] |
| `edgeInfo1` | edges | 4 | 0.917 | 0.9336 | [0.578, 1.255] |
| `allEdges` | edges | 4 | 2.134 | 0.9975 | [1.985, 2.283] |
| `allEdgesBulk` | edges | 4 | 1.085 | 0.9911 | [0.943, 1.228] |
| `buildOnly` | edges | 4 | 1.114 | 0.9942 | [0.996, 1.232] |
| `counts` | edges | 4 | 1.041 | 0.9405 | [0.678, 1.404] |
| `bbox` | edges | 4 | 1.010 | 0.9615 | [0.730, 1.290] |
| `mesh` | edges | 4 | 1.004 | 0.9616 | [0.726, 1.282] |
| `fuse` | edges | 4 | 1.182 | 0.9885 | [1.005, 1.359] |
| `cut` | edges | 4 | 1.230 | 0.9990 | [1.177, 1.283] |
| `rayHits` | edges | 4 | 0.336 | 0.5070 | [-0.123, 0.795] |
| `filletEx1` | edges | 4 | 0.090 | 0.0254 | [-0.683, 0.864] |
| `fillet.edges` | edgesBlended | 3 | 0.556 | 0.9628 | [0.342, 0.770] |
| `fillet.scenario` | edgesBlended | 3 | 0.588 | 0.9968 | [0.523, 0.654] |
| `fillet.radius` | radius | 4 | 1.425 | 0.5993 | [-0.190, 3.039] |
| `sweep.segments` | segments | 3 | 1.065 | 0.9990 | [1.001, 1.130] |
| `sweep.legacy` | segments | 3 | 1.773 | 0.9643 | [1.104, 2.442] |
| `sweep.coil` | segments | 3 | 1.393 | 0.9897 | [1.114, 1.671] |
| `sweep.ph.build` | segments | 3 | 1.964 | 0.9675 | [1.258, 2.670] |
| `sweep.ph.unify` | segments | 3 | 1.144 | 0.9988 | [1.066, 1.222] |
| `sweep.ph.total` | segments | 3 | 1.919 | 0.9684 | [1.239, 2.599] |
| `sweep.spans` | spans | 5 | 0.411 | 0.0914 | [-1.055, 1.876] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.73063 | 0.27171 | 4.17867 | 7.3 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.09403 | 0.01113 | 0.11427 | 11.8 % | 821 | 158368 | +0 | 14.2 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.37741 | 0.88043 | 16.75625 | 5.7 % | 148205 | 28566976 | +0 | 14.2 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 4 | 0.85548 | 0.06705 | 0.96905 | 7.8 % | 6209 | 596032 | +0 | 14.4 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 11.32841 | 2.05890 | 15.49746 | 18.2 % | 84071 | 225974848 | -12160 | 22.3 |
| `counts` | edges | 180 | 180 | 7 | 16 | 0.08606 | 0.00954 | 0.10127 | 11.1 % | 375 | 59360 | +0 | 22.3 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05486 | 0.00552 | 0.06501 | 10.1 % | 63 | 80640 | +0 | 22.3 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.35954 | 0.28997 | 4.86017 | 6.7 % | 34056 | 13154158 | +0 | 22.4 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 66.25404 | 7.47487 | 79.15263 | 11.3 % | 270379 | 66620080 | +0 | 28.1 |
| `cut` | edges | 180 | 180 | 7 | 1 | 58.88440 | 7.41943 | 73.99404 | 12.6 % | 242876 | 59649890 | +0 | 28.1 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.47868 | 0.21778 | 0.81421 | 45.5 % | 1976 | 308336 | +0 | 28.1 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 37.22030 | 5.42307 | 45.71388 | 14.6 % | 211425 | 25882480 | +0 | 29.5 |
| `build` | edges | 360 | 360 | 7 | 1 | 10.83024 | 3.43922 | 17.40167 | 31.8 % | 67568 | 10408048 | +0 | 29.5 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.29505 | 0.13539 | 0.52586 | 45.9 % | 1601 | 269728 | +0 | 29.5 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 83.60018 | 6.36895 | 91.11667 | 7.6 % | 577205 | 97204096 | +0 | 29.5 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.82633 | 0.28210 | 2.21917 | 15.4 % | 12392 | 1160128 | +0 | 29.5 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 29.25185 | 2.93948 | 35.64500 | 10.0 % | 167561 | 446577664 | -24320 | 36.1 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.27403 | 0.14014 | 0.57697 | 51.1 % | 737 | 93024 | +0 | 36.1 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.16636 | 0.06867 | 0.28936 | 41.3 % | 123 | 157440 | +0 | 36.1 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 13.16008 | 2.56970 | 16.39021 | 19.5 % | 67923 | 24575301 | +0 | 36.1 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 115.57959 | 17.70252 | 150.57483 | 15.3 % | 614241 | 133947458 | +0 | 40.0 |
| `cut` | edges | 360 | 360 | 7 | 1 | 131.15389 | 17.02994 | 163.58937 | 13.0 % | 560363 | 120363737 | +0 | 40.0 |
| `rayHits` | edges | 360 | 360 | 7 | 16 | 0.35304 | 0.11444 | 0.51061 | 32.4 % | 2096 | 392112 | +0 | 40.0 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 12.84596 | 4.42902 | 21.02179 | 34.5 % | 68952 | 11624128 | +0 | 40.2 |
| `build` | edges | 720 | 720 | 7 | 1 | 24.60595 | 4.36926 | 29.54775 | 17.8 % | 134894 | 20360432 | +0 | 40.2 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.40017 | 0.07783 | 0.52141 | 19.5 % | 3161 | 492448 | +0 | 40.2 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 334.36719 | 26.02179 | 360.15500 | 7.8 % | 2277605 | 354747136 | +0 | 40.2 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 4.52639 | 1.35040 | 6.47833 | 29.8 % | 24753 | 2255552 | +0 | 40.2 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 56.45582 | 5.19267 | 62.82421 | 9.2 % | 334258 | 888838496 | -48640 | 53.2 |
| `counts` | edges | 720 | 720 | 7 | 8 | 0.53734 | 0.09890 | 0.66422 | 18.4 % | 1457 | 127584 | +0 | 53.2 |
| `bbox` | edges | 720 | 720 | 7 | 16 | 0.23781 | 0.01381 | 0.26334 | 5.8 % | 243 | 311040 | +0 | 53.2 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 21.36233 | 3.56486 | 26.37454 | 16.7 % | 135627 | 48367506 | +0 | 53.7 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 320.15198 | 45.97433 | 379.15312 | 14.4 % | 1539723 | 274702530 | +0 | 62.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 333.02129 | 56.87136 | 437.05346 | 17.1 % | 1432934 | 247774151 | +0 | 62.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.46240 | 0.19262 | 0.88235 | 41.7 % | 2336 | 559664 | +0 | 62.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 35.69050 | 22.46998 | 78.40692 | 63.0 % | 134712 | 22247488 | +0 | 62.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 30.25680 | 1.11626 | 32.35008 | 3.7 % | 269554 | 40496624 | +0 | 62.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.70614 | 0.03302 | 0.75793 | 4.7 % | 6285 | 1003424 | +0 | 62.2 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1341.75757 | 123.47766 | 1520.76408 | 9.2 % | 9053767 | 1445313024 | +0 | 62.2 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 7.75972 | 2.17074 | 12.22617 | 28.0 % | 49478 | 4511936 | +0 | 62.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 119.31527 | 10.32454 | 132.82558 | 8.7 % | 668060 | 1775223216 | -97280 | 87.1 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 0.76230 | 0.07705 | 0.87439 | 10.1 % | 2899 | 229472 | +0 | 87.1 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.50219 | 0.04691 | 0.56836 | 9.3 % | 483 | 618240 | +0 | 87.1 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 37.73494 | 3.85673 | 43.72083 | 10.2 % | 271030 | 96173390 | +0 | 87.1 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 724.05383 | 30.02184 | 790.90717 | 4.1 % | 4342679 | 590676601 | +0 | 103.4 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 739.64913 | 49.47827 | 803.86396 | 6.7 % | 4130071 | 536930320 | +0 | 103.4 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.95036 | 1.01906 | 2.97527 | 107.2 % | 2816 | 894768 | +0 | 103.4 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 32.60931 | 0.60499 | 33.33458 | 1.9 % | 266270 | 44116800 | +0 | 103.4 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 2.66794 | 0.12817 | 2.87158 | 4.8 % | 25307 | 4253072 | +0 | 103.4 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.60331 | 0.01211 | 0.62777 | 2.0 % | 4013 | 309760 | +0 | 103.4 |
| `valid` | edges | 72 | 72 | 7 | 1 | 3.94921 | 0.11936 | 4.06325 | 3.0 % | 29913 | 5127328 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 13.96432 | 7.69393 | 31.39487 | 55.1 % | 92919 | 11590416 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 24.06756 | 0.62626 | 24.77575 | 2.6 % | 202372 | 22644144 | +0 | 103.4 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 56.56514 | 4.71738 | 64.65550 | 8.3 % | 486810 | 49139568 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 15.01729 | 1.60372 | 18.57879 | 10.7 % | 118226 | 15843488 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 31.67684 | 3.80948 | 37.10504 | 12.0 % | 227679 | 26897216 | +0 | 103.4 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 65.12954 | 11.89618 | 88.58971 | 18.3 % | 512117 | 53392640 | +0 | 103.4 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 25.11418 | 1.28948 | 27.79471 | 5.1 % | 202345 | 22639152 | +0 | 103.4 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 26.22317 | 2.70172 | 31.93321 | 10.3 % | 202372 | 22644144 | +0 | 103.4 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 25.05443 | 0.79088 | 26.52696 | 3.2 % | 202370 | 22640112 | +0 | 103.4 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 685.53447 | 27.76485 | 740.65608 | 4.1 % | 3554373 | 535954400 | +0 | 103.4 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 45.94148 | 0.56026 | 47.01379 | 1.2 % | 115765 | 20752032 | +0 | 103.4 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 100.02677 | 2.98864 | 103.75704 | 3.0 % | 249401 | 63466032 | +0 | 103.4 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 201.19495 | 5.44987 | 210.90058 | 2.7 % | 526495 | 134945888 | +0 | 111.7 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 258.57860 | 29.54795 | 301.37313 | 11.4 % | 1236848 | 249935056 | +0 | 111.8 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 586.59170 | 29.58518 | 643.16375 | 5.0 % | 2634121 | 524105264 | +0 | 112.0 |
| `sweep.legacy` | segments | 128 | 4224 | 7 | 1 | 3019.19198 | 109.14737 | 3248.93358 | 3.6 % | 6057892 | 1210486000 | +0 | 114.4 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 14.53575 | 0.17005 | 14.78513 | 1.2 % | 100529 | 15713552 | +0 | 115.2 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 45.26316 | 0.41897 | 45.88896 | 0.9 % | 210352 | 47931248 | +0 | 116.8 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 100.18777 | 4.66584 | 105.68646 | 4.7 % | 449873 | 107867264 | +0 | 119.9 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 30.96093 | 0.50935 | 31.62771 | 1.6 % | 287370 | 34951712 | +0 | 119.9 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 731.95355 | 41.02602 | 805.98187 | 5.6 % | 1042546 | 198791584 | +0 | 128.9 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1573.37788 | 63.26271 | 1662.67683 | 4.0 % | 2008917 | 403883408 | +0 | 128.9 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 206.42861 | 11.91835 | 227.46054 | 5.8 % | 546392 | 133805120 | +0 | 129.5 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 242.00328 | 7.18819 | 249.68300 | 3.0 % | 526495 | 134945888 | +0 | 129.5 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.07469 | 0.00651 | 0.08517 | 8.7 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.01001 | 0.00111 | 0.01204 | 11.1 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 2969.38382 | 140.31557 | 3234.23092 | 4.7 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 25.87765 | 2.75913 | 30.11342 | 10.7 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 65.50633 | 9.36171 | 81.92183 | 14.3 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 3060.85251 | 150.53746 | 3346.36100 | 4.9 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02841 | 0.00395 | 0.03379 | 13.9 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00764 | 0.00051 | 0.00854 | 6.7 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 195.12701 | 2.43312 | 197.81746 | 1.2 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 5.51610 | 0.30492 | 6.04550 | 5.5 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 13.41662 | 0.41603 | 13.90117 | 3.1 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 214.09579 | 2.62590 | 217.26071 | 1.2 % | n/a | n/a | n/a | 148.8 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.04090 | 0.00358 | 0.04650 | 8.8 % | n/a | n/a | n/a | 148.9 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.00711 | 0.00058 | 0.00833 | 8.2 % | n/a | n/a | n/a | 148.9 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 493.94066 | 4.56858 | 501.65892 | 0.9 % | n/a | n/a | n/a | 148.9 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 11.54820 | 0.27662 | 12.04592 | 2.4 % | n/a | n/a | n/a | 148.9 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 28.26561 | 0.69644 | 28.93258 | 2.5 % | n/a | n/a | n/a | 148.9 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 533.80249 | 4.90283 | 541.69813 | 0.9 % | n/a | n/a | n/a | 148.9 |
| `sweep.var.v23poly` | segments | 128 | 0 | 6 | 1 | 3490.51711 | 658.49507 | 4349.02488 | 18.9 % | n/a | n/a | n/a | 148.9 |
| `sweep.var.noUnify` | segments | 128 | 0 | 7 | 1 | 2808.90184 | 339.58917 | 3440.31742 | 12.1 % | n/a | n/a | n/a | 148.9 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 199.33387 | 13.74549 | 223.74071 | 6.9 % | n/a | n/a | n/a | 149.1 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 607.11918 | 195.28418 | 1004.73354 | 32.2 % | n/a | n/a | n/a | 150.7 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 251.87764 | 58.61893 | 367.88879 | 23.3 % | n/a | n/a | n/a | 158.7 |

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
