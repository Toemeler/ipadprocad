# Lane C — headless kernel benchmark

RELATIVE costs, exponents, allocation and RSS may be read from this table.
ABSOLUTE milliseconds may NOT be quoted as iPad milliseconds (PERFORMANCE_PROFILE.md §13.3).

| | |
| --- | --- |
| generated | 2026-08-24T16:02:02Z |
| host | Darwin / arm64 |
| kernel | Prototype OCCT shim v26 (OCCT 7.9.3) (shim v26) |
| allocation counting | apple zone + operator new |
| reps / budget | 7 / 20000 ms |

## Calibration against the device

The harness is believable only where it reproduces the SHAPE of the device finding. Agreement is interval overlap.

| op | device k | device CI (as printed) | bench k | bench CI | R² | gating | verdict | vs tool-convention CI |
| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |
| `edgeInfo1` | 0.990 | [0.970, 1.010] | 1.196 | [1.111, 1.280] | 0.9974 | yes | **DISAGREES** | same convention |
| `allEdges` | 2.012 | [1.910, 2.113] | 2.254 | [2.109, 2.399] | 0.9979 | yes | **AGREES** | [1.996, 2.027] → DISAGREES |
| `buildOnly` | 1.063 | [0.959, 1.167] | 1.318 | [1.111, 1.526] | 0.9873 | no | **AGREES** | same convention |

**Harness verdict: NOT VALIDATED**

## Fitted exponents

| op | axis | N | k | R² | 95 % CI |
| --- | --- | ---: | ---: | ---: | --- |
| `build` | edges | 4 | 1.155 | 0.9831 | [0.945, 1.365] |
| `edgeInfo1` | edges | 4 | 1.196 | 0.9974 | [1.111, 1.280] |
| `allEdges` | edges | 4 | 2.254 | 0.9979 | [2.109, 2.399] |
| `allEdgesBulk` | edges | 4 | 1.159 | 0.9913 | [1.008, 1.310] |
| `buildOnly` | edges | 4 | 1.318 | 0.9873 | [1.111, 1.526] |
| `counts` | edges | 4 | 1.597 | 0.9472 | [1.074, 2.119] |
| `bbox` | edges | 4 | 1.312 | 0.9943 | [1.175, 1.449] |
| `mesh` | edges | 4 | 1.331 | 0.9743 | [1.031, 1.630] |
| `fuse` | edges | 4 | 1.527 | 0.9995 | [1.478, 1.575] |
| `cut` | edges | 4 | 1.280 | 0.9801 | [1.027, 1.533] |
| `rayHits` | edges | 4 | 0.202 | 0.3029 | [-0.223, 0.626] |
| `filletEx1` | edges | 4 | 0.138 | 0.0388 | [-0.815, 1.091] |
| `fillet.edges` | edgesBlended | 3 | 0.649 | 0.9571 | [0.380, 0.919] |
| `fillet.scenario` | edgesBlended | 3 | 0.575 | 0.9999 | [0.564, 0.585] |
| `fillet.radius` | radius | 4 | 1.393 | 0.5667 | [-0.295, 3.082] |
| `sweep.segments` | segments | 3 | 1.065 | 0.9999 | [1.043, 1.088] |
| `sweep.legacy` | segments | 3 | 1.690 | 0.9914 | [1.382, 1.997] |
| `sweep.coil` | segments | 3 | 1.403 | 0.9861 | [1.076, 1.729] |
| `sweep.ph.build` | segments | 3 | 1.865 | 0.9996 | [1.794, 1.936] |
| `sweep.ph.unify` | segments | 3 | 0.998 | 0.9069 | [0.371, 1.624] |
| `sweep.ph.total` | segments | 3 | 1.822 | 0.9999 | [1.784, 1.860] |
| `sweep.spans` | spans | 5 | 0.338 | 0.0646 | [-1.118, 1.795] |

## Measurements

| op | axis | x | edges | n | ×inner | mean ms | sd | p95 | CV | alloc/call | bytes/call | live Δ | RSS peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `build` | edges | 180 | 180 | 7 | 1 | 3.56843 | 0.16088 | 3.83725 | 4.5 % | 33890 | 5335600 | +0 | 14.2 |
| `edgeInfo1` | edges | 180 | 180 | 7 | 32 | 0.07769 | 0.00137 | 0.08061 | 1.8 % | 821 | 158368 | +0 | 14.3 |
| `allEdges` | edges | 180 | 180 | 7 | 1 | 15.73167 | 0.85005 | 17.48663 | 5.4 % | 148205 | 28566976 | +0 | 14.3 |
| `allEdgesBulk` | edges | 180 | 180 | 7 | 2 | 0.80445 | 0.12100 | 1.03067 | 15.0 % | 6209 | 596032 | +0 | 14.5 |
| `buildOnly` | edges | 180 | 180 | 7 | 1 | 10.49093 | 0.68572 | 11.81212 | 6.5 % | 84071 | 225974848 | -12160 | 22.5 |
| `counts` | edges | 180 | 180 | 7 | 32 | 0.09045 | 0.00690 | 0.10555 | 7.6 % | 375 | 59360 | +0 | 22.5 |
| `bbox` | edges | 180 | 180 | 7 | 64 | 0.05568 | 0.00172 | 0.05803 | 3.1 % | 63 | 80640 | +0 | 22.5 |
| `mesh` | edges | 180 | 180 | 7 | 1 | 4.18614 | 0.13671 | 4.31275 | 3.3 % | 34056 | 13154158 | +0 | 22.5 |
| `fuse` | edges | 180 | 180 | 7 | 1 | 45.39326 | 3.46660 | 50.98358 | 7.6 % | 270352 | 66614521 | +0 | 28.3 |
| `cut` | edges | 180 | 180 | 7 | 1 | 54.09915 | 10.08283 | 73.79500 | 18.6 % | 242889 | 59652523 | +0 | 28.3 |
| `rayHits` | edges | 180 | 180 | 7 | 16 | 0.28647 | 0.06996 | 0.39495 | 24.4 % | 1976 | 308336 | +0 | 28.4 |
| `filletEx1` | edges | 180 | 180 | 7 | 1 | 37.42232 | 6.70429 | 51.33529 | 17.9 % | 211425 | 25882480 | +0 | 29.8 |
| `build` | edges | 360 | 360 | 7 | 1 | 10.64364 | 2.76976 | 16.09038 | 26.0 % | 67568 | 10408048 | +0 | 29.8 |
| `edgeInfo1` | edges | 360 | 360 | 7 | 16 | 0.19277 | 0.01751 | 0.22382 | 9.1 % | 1601 | 269728 | +0 | 29.8 |
| `allEdges` | edges | 360 | 360 | 7 | 1 | 82.40749 | 12.15915 | 102.30529 | 14.8 % | 577205 | 97204096 | +0 | 29.8 |
| `allEdgesBulk` | edges | 360 | 360 | 7 | 2 | 1.74582 | 0.34851 | 2.31144 | 20.0 % | 12392 | 1160128 | +0 | 29.9 |
| `buildOnly` | edges | 360 | 360 | 7 | 1 | 27.66817 | 6.08292 | 35.31829 | 22.0 % | 167561 | 446577664 | -24320 | 36.7 |
| `counts` | edges | 360 | 360 | 7 | 16 | 0.33510 | 0.10223 | 0.41910 | 30.5 % | 737 | 93024 | +0 | 36.7 |
| `bbox` | edges | 360 | 360 | 7 | 32 | 0.13643 | 0.04138 | 0.21531 | 30.3 % | 123 | 157440 | +0 | 36.7 |
| `mesh` | edges | 360 | 360 | 7 | 1 | 13.10916 | 2.91067 | 18.21542 | 22.2 % | 67923 | 24575301 | +0 | 36.7 |
| `fuse` | edges | 360 | 360 | 7 | 1 | 125.10399 | 7.21532 | 138.68613 | 5.8 % | 614323 | 133960953 | +0 | 40.8 |
| `cut` | edges | 360 | 360 | 7 | 1 | 106.00155 | 10.64313 | 128.13333 | 10.0 % | 560371 | 120365346 | +0 | 40.8 |
| `rayHits` | edges | 360 | 360 | 7 | 8 | 0.27098 | 0.08001 | 0.45121 | 29.5 % | 2096 | 392112 | +0 | 40.8 |
| `filletEx1` | edges | 360 | 360 | 7 | 1 | 10.19795 | 1.42300 | 12.23804 | 14.0 % | 68952 | 11624128 | +0 | 40.9 |
| `build` | edges | 720 | 720 | 7 | 1 | 17.86371 | 3.60696 | 23.17125 | 20.2 % | 134894 | 20360432 | +0 | 40.9 |
| `edgeInfo1` | edges | 720 | 720 | 7 | 8 | 0.38892 | 0.13583 | 0.69333 | 34.9 % | 3161 | 492448 | +0 | 40.9 |
| `allEdges` | edges | 720 | 720 | 7 | 1 | 319.15924 | 27.70526 | 367.09617 | 8.7 % | 2277605 | 354747136 | +0 | 40.9 |
| `allEdgesBulk` | edges | 720 | 720 | 7 | 1 | 3.36074 | 1.03896 | 5.66350 | 30.9 % | 24753 | 2255552 | +0 | 40.9 |
| `buildOnly` | edges | 720 | 720 | 7 | 1 | 52.91046 | 2.94911 | 56.48267 | 5.6 % | 334258 | 888838496 | -48640 | 53.8 |
| `counts` | edges | 720 | 720 | 7 | 4 | 0.50357 | 0.18646 | 0.79702 | 37.0 % | 1457 | 127584 | +0 | 53.8 |
| `bbox` | edges | 720 | 720 | 7 | 8 | 0.29313 | 0.02114 | 0.31921 | 7.2 % | 243 | 311040 | +0 | 53.8 |
| `mesh` | edges | 720 | 720 | 7 | 1 | 21.26893 | 3.41805 | 26.17883 | 16.1 % | 135627 | 48367506 | +0 | 53.8 |
| `fuse` | edges | 720 | 720 | 7 | 1 | 355.80382 | 32.87865 | 404.64654 | 9.2 % | 1539727 | 274703408 | +0 | 62.2 |
| `cut` | edges | 720 | 720 | 7 | 1 | 375.02029 | 63.88970 | 504.42121 | 17.0 % | 1432899 | 247766983 | +0 | 62.2 |
| `rayHits` | edges | 720 | 720 | 7 | 8 | 0.55785 | 0.18518 | 0.82294 | 33.2 % | 2336 | 559664 | +0 | 62.2 |
| `filletEx1` | edges | 720 | 720 | 7 | 1 | 22.58908 | 3.88735 | 28.50421 | 17.2 % | 134712 | 22247488 | +0 | 62.2 |
| `build` | edges | 1440 | 1440 | 7 | 1 | 43.27674 | 7.22074 | 56.24483 | 16.7 % | 269554 | 40496624 | +0 | 62.2 |
| `edgeInfo1` | edges | 1440 | 1440 | 7 | 4 | 0.97407 | 0.32591 | 1.61189 | 33.5 % | 6285 | 1003424 | +0 | 62.2 |
| `allEdges` | edges | 1440 | 1440 | 7 | 1 | 1830.06184 | 277.00947 | 2235.48362 | 15.1 % | 9053767 | 1445313024 | +0 | 62.2 |
| `allEdgesBulk` | edges | 1440 | 1440 | 7 | 1 | 9.40889 | 1.65281 | 12.03862 | 17.6 % | 49478 | 4511936 | +0 | 62.2 |
| `buildOnly` | edges | 1440 | 1440 | 7 | 1 | 177.76710 | 12.77723 | 188.42746 | 7.2 % | 668060 | 1775223216 | -97280 | 87.2 |
| `counts` | edges | 1440 | 1440 | 7 | 4 | 3.15988 | 3.36213 | 8.08982 | 106.4 % | 2899 | 229472 | +0 | 87.2 |
| `bbox` | edges | 1440 | 1440 | 7 | 8 | 0.89421 | 0.26566 | 1.17619 | 29.7 % | 483 | 618240 | +0 | 87.2 |
| `mesh` | edges | 1440 | 1440 | 7 | 1 | 77.10810 | 21.79529 | 115.40233 | 28.3 % | 271030 | 96173390 | +0 | 87.2 |
| `fuse` | edges | 1440 | 1440 | 7 | 1 | 1090.59194 | 121.48157 | 1232.54971 | 11.1 % | 4342815 | 590704542 | +0 | 103.6 |
| `cut` | edges | 1440 | 1440 | 7 | 1 | 683.02667 | 63.49630 | 790.10825 | 9.3 % | 4130713 | 536997849 | +0 | 103.6 |
| `rayHits` | edges | 1440 | 1440 | 7 | 8 | 0.35904 | 0.01160 | 0.38168 | 3.2 % | 2816 | 894768 | +0 | 103.6 |
| `filletEx1` | edges | 1440 | 1440 | 7 | 1 | 39.49769 | 6.72721 | 51.34721 | 17.0 % | 266270 | 44116800 | +0 | 103.6 |
| `filletCandidateSearch` | edges | 72 | 72 | 7 | 1 | 3.31786 | 1.24909 | 6.03754 | 37.6 % | 25307 | 4253072 | +0 | 103.6 |
| `volume` | edges | 72 | 72 | 7 | 4 | 0.84465 | 0.27520 | 1.31948 | 32.6 % | 4013 | 309760 | +0 | 103.6 |
| `valid` | edges | 72 | 72 | 7 | 1 | 5.32768 | 2.58199 | 11.15583 | 48.5 % | 29913 | 5127328 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 1 | 72 | 7 | 1 | 14.51962 | 3.14386 | 21.19004 | 21.7 % | 92919 | 11590416 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 4 | 72 | 7 | 1 | 26.87764 | 7.46945 | 41.19492 | 27.8 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.edges` | edgesBlended | 12 | 72 | 7 | 1 | 74.59970 | 8.46944 | 88.30504 | 11.4 % | 486810 | 49139568 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 1 | 72 | 7 | 1 | 13.10383 | 0.99454 | 14.61929 | 7.6 % | 118226 | 15843488 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 4 | 72 | 7 | 1 | 29.36871 | 4.54545 | 38.44062 | 15.5 % | 227679 | 26897216 | +0 | 103.6 |
| `fillet.scenario` | edgesBlended | 12 | 72 | 7 | 1 | 54.57945 | 3.64345 | 59.98667 | 6.7 % | 512117 | 53392640 | +0 | 103.6 |
| `fillet.radius` | radius | 0.5 | 72 | 7 | 1 | 28.42677 | 12.15283 | 55.37463 | 42.8 % | 202345 | 22639152 | +0 | 103.6 |
| `fillet.radius` | radius | 1 | 72 | 7 | 1 | 28.51514 | 3.29314 | 33.53425 | 11.5 % | 202372 | 22644144 | +0 | 103.6 |
| `fillet.radius` | radius | 2 | 72 | 7 | 1 | 24.81087 | 2.21327 | 27.52413 | 8.9 % | 202370 | 22640112 | +0 | 103.6 |
| `fillet.radius` | radius | 4 | 72 | 7 | 1 | 744.50290 | 62.41978 | 862.03583 | 8.4 % | 3554373 | 535954400 | +0 | 103.6 |
| `sweep.segments` | segments | 32 | 96 | 7 | 1 | 63.54990 | 21.19484 | 107.16654 | 33.4 % | 115765 | 20752032 | +0 | 103.6 |
| `sweep.segments` | segments | 64 | 192 | 7 | 1 | 134.85526 | 17.35513 | 156.41917 | 12.9 % | 249401 | 63466032 | +0 | 103.6 |
| `sweep.segments` | segments | 128 | 384 | 7 | 1 | 278.30504 | 52.88541 | 388.80971 | 19.0 % | 526495 | 134945888 | +0 | 107.7 |
| `sweep.legacy` | segments | 32 | 1054 | 7 | 1 | 281.84644 | 30.00214 | 321.08225 | 10.6 % | 1236848 | 249935056 | +0 | 107.9 |
| `sweep.legacy` | segments | 64 | 2112 | 7 | 1 | 753.02997 | 50.88302 | 804.37987 | 6.8 % | 2634121 | 524105264 | +0 | 108.0 |
| `sweep.legacy` | segments | 128 | 4224 | 7 | 1 | 2932.55235 | 159.68651 | 3199.08871 | 5.4 % | 6057892 | 1210486000 | +0 | 110.3 |
| `sweep.coil` | segments | 32 | 96 | 7 | 1 | 14.47376 | 1.13302 | 16.05779 | 7.8 % | 100529 | 15713552 | +0 | 111.1 |
| `sweep.coil` | segments | 64 | 192 | 7 | 1 | 46.73970 | 10.36896 | 66.83537 | 22.2 % | 210352 | 47931248 | +0 | 112.3 |
| `sweep.coil` | segments | 128 | 384 | 7 | 1 | 101.16797 | 17.80342 | 138.10525 | 17.6 % | 449873 | 107867264 | +0 | 115.4 |
| `sweep.spans` | spans | 1 | 384 | 7 | 1 | 36.30437 | 8.13325 | 53.21804 | 22.4 % | 287370 | 34951712 | +0 | 115.4 |
| `sweep.spans` | spans | 2 | 640 | 7 | 1 | 838.53655 | 60.06170 | 913.74508 | 7.2 % | 1042546 | 198791584 | +0 | 124.4 |
| `sweep.spans` | spans | 4 | 1152 | 7 | 1 | 1617.27970 | 90.89412 | 1712.60150 | 5.6 % | 2008917 | 403883408 | +0 | 124.5 |
| `sweep.spans` | spans | 8 | 384 | 7 | 1 | 231.31993 | 56.18489 | 354.94983 | 24.3 % | 546392 | 133805120 | +0 | 125.1 |
| `sweep.spans` | spans | 16 | 384 | 7 | 1 | 223.13795 | 25.38587 | 265.82654 | 11.4 % | 526495 | 134945888 | +0 | 125.1 |
| `sweep.ph.wire` | segments | 128 | 0 | 7 | 1 | 0.07471 | 0.02153 | 0.12221 | 28.8 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.spine` | segments | 128 | 0 | 7 | 1 | 0.00864 | 0.00110 | 0.01071 | 12.8 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.build` | segments | 128 | 0 | 7 | 1 | 3006.44850 | 141.79350 | 3160.08342 | 4.7 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.solid` | segments | 128 | 0 | 7 | 1 | 25.86010 | 5.32527 | 33.91342 | 20.6 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.unify` | segments | 128 | 0 | 7 | 1 | 58.95337 | 7.30615 | 66.66033 | 12.4 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.total` | segments | 128 | 0 | 7 | 1 | 3091.34532 | 141.46531 | 3235.96079 | 4.6 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.wire` | segments | 32 | 0 | 7 | 1 | 0.02814 | 0.00481 | 0.03771 | 17.1 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.spine` | segments | 32 | 0 | 7 | 1 | 0.00727 | 0.00033 | 0.00775 | 4.6 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.build` | segments | 32 | 0 | 7 | 1 | 226.68882 | 18.19328 | 254.84588 | 8.0 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.solid` | segments | 32 | 0 | 7 | 1 | 5.76104 | 0.52551 | 6.51654 | 9.1 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.unify` | segments | 32 | 0 | 7 | 1 | 14.78499 | 1.22213 | 16.13858 | 8.3 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.total` | segments | 32 | 0 | 7 | 1 | 247.27026 | 18.89074 | 277.15792 | 7.6 % | n/a | n/a | n/a | 144.4 |
| `sweep.ph.wire` | segments | 64 | 0 | 7 | 1 | 0.05342 | 0.02537 | 0.10721 | 47.5 % | n/a | n/a | n/a | 144.5 |
| `sweep.ph.spine` | segments | 64 | 0 | 7 | 1 | 0.02283 | 0.03572 | 0.10300 | 156.5 % | n/a | n/a | n/a | 144.5 |
| `sweep.ph.build` | segments | 64 | 0 | 7 | 1 | 790.35246 | 87.61253 | 968.77600 | 11.1 % | n/a | n/a | n/a | 144.5 |
| `sweep.ph.solid` | segments | 64 | 0 | 7 | 1 | 20.20962 | 4.70771 | 26.64883 | 23.3 % | n/a | n/a | n/a | 144.5 |
| `sweep.ph.unify` | segments | 64 | 0 | 7 | 1 | 43.33067 | 4.39958 | 49.11300 | 10.2 % | n/a | n/a | n/a | 144.5 |
| `sweep.ph.total` | segments | 64 | 0 | 7 | 1 | 853.96901 | 90.01127 | 1036.90937 | 10.5 % | n/a | n/a | n/a | 144.5 |
| `sweep.var.v23poly` | segments | 128 | 0 | 5 | 1 | 4658.19711 | 282.11641 | 5041.97058 | 6.1 % | n/a | n/a | n/a | 144.5 |
| `sweep.var.noUnify` | segments | 128 | 0 | 6 | 1 | 3622.75881 | 346.27033 | 4119.13338 | 9.6 % | n/a | n/a | n/a | 144.5 |
| `sweep.var.transformed` | segments | 128 | 0 | 7 | 1 | 300.63721 | 50.60488 | 393.05700 | 16.8 % | n/a | n/a | n/a | 144.7 |
| `sweep.var.deadband` | segments | 128 | 0 | 7 | 1 | 715.06057 | 112.84003 | 931.61087 | 15.8 % | n/a | n/a | n/a | 146.2 |
| `sweep.var.smoothSpine` | segments | 128 | 0 | 7 | 1 | 336.08688 | 32.62794 | 384.22183 | 9.7 % | n/a | n/a | n/a | 154.3 |

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
