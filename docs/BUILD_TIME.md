# Where the build's hour went

Measured from the GitHub Actions job and step timings of the runs named below —
not from estimates. The short version: 68m53s to 19m45s, and the cause was one
copy too many of Qt.

| run | commit | wall clock |
|---|---|---|
| [34478689042](https://github.com/Toemeler/ipadprocad/actions/runs/34478689042) | `7b0af49` | **78 min** |
| [34568753636](https://github.com/Toemeler/ipadprocad/actions/runs/34568753636) | `8c7a3a1` | **69 min** |
| [34493818656](https://github.com/Toemeler/ipadprocad/actions/runs/34493818656) | `9076e08` | **65 min** |
| [34471044060](https://github.com/Toemeler/ipadprocad/actions/runs/34471044060) | `0fa7246` | 54 min |
| [34580467549](https://github.com/Toemeler/ipadprocad/actions/runs/34580467549) | `c10242c` | **19m45s** — after |

## 1. There is only one job on the critical path

`build.yml` fans out to fourteen jobs. Thirteen of them are finished twenty
minutes in. In run 34493818656 the last desktop job ended at 15:31 and the
release was published at 16:15 — **forty-four minutes in which the entire
build was one macOS runner**.

```
15:11  ├─ Dart analyze + host tests ──────┤ 5:20
       ├─ Linux OCCT (cache hit) ─┤ 0:25
       ├─ Windows OCCT (cache hit) ─┤ 0:41
       ├─ Cycles iOS (cache hit) ─┤ 0:32
       ├─ build-core-ios ──────────────────────┤ 6:33
       ├─ M3 simulator smoke ────────────────────┤ 10:07
       ├─ Linux kernels ──────────────┤ 6:20    ├─ Linux bundle ────┤ 4:28
       ├─ Windows kernels ──────────────────┤ 12:16  ├─ Win bundle ──────┤ 7:31
15:16                    └─ M5 Flutter iOS + IPA ══════════════════════════╗
                                                                          ║
16:14                                                                     ╝ 57:51
16:15  └─ release ┤ 0:35
```

Everything worth fixing is inside `m5-flutter-ipa`, or is the reason it starts
late.

## 2. Inside M5

| step | run 34493818656 | share |
|---|---|---|
| **Build OpenCASCADE static (iOS, "cache miss only")** | **29:35** | **51%** |
| **Dart unit tests (solver + dimension system)** | **11:35** | **20%** |
| Build iOS app (release, unsigned) | 4:42 | 8% |
| Configure + build core & C-API | 4:40 | 8% |
| post-job cache uploads | 1:45 | 3% |
| Install Flutter | 1:31 | 3% |
| Scaffold iOS project + pub get | 1:01 | 2% |
| Qt6 host + iOS | 1:10 | 2% |
| everything else | ~1:20 | 2% |

## 3. Every OCCT cache was being evicted, and nothing said so

The step is called "cache miss only" and is skipped on a hit, so in the log a
hit looks like a miss somebody already fixed, and a miss looks like a build
that simply takes that long. Run 34568753636, on `main`, missed **all three**:

| OCCT cache | run 34493818656 (Sep 10) | run 34568753636 (Sep 11) |
|---|---|---|
| Linux | hit, 0:25 | **miss — rebuilt 22:25** |
| Windows | hit, 0:41 | **miss — rebuilt 29:35** |
| iOS (inside M5) | miss — rebuilt 29:35 | **miss — rebuilt 31:26** |

**83 minutes of recomputation in one run**, all of it work done the day before.
The keys are constants — `occt-ios-arm64-V7_9_3-r1` and friends, no hash — and
each run **saved successfully afterwards**, which settles it: a cache save only
succeeds when the key is free. The entries existed and then did not.

Nothing in this repository deletes caches. GitHub does, above 10 GB, least
recently used first, silently.

## 4. What is actually in the 10 GB — measured, not guessed

The diagnostic added in M426 prints it from inside the job. Run 34574418966:

```
CACHE BUDGET: 9671 MiB von 10240 MiB belegt
  UEBER 9 GiB — es wird geraeumt, und zwar das Aelteste zuerst.
Die groessten Eintraege:
3207 MiB  install-qt-action-mac-23.6.0-ios-6.7.*-.../qt-ios/Qt-...
3207 MiB  install-qt-action-mac-25.6.0-ios-6.7.*-.../qt-ios/Qt-...
1116 MiB  install-qt-action-mac-23.6.0-desktop-6.7.*-.../qt-host/Qt-...
1116 MiB  install-qt-action-mac-25.6.0-desktop-6.7.*-.../qt-host/Qt-...
 548 MiB  blender-ios-libs-m294-v1
 143 MiB  cycles-dist-v4-...
 114 MiB  occt-windows-V7_9_3-r1
  42 MiB  occt-linux-V7_9_3-r1
```

**Qt is 8646 of the 9671 occupied MiB — 89% of the allowance — and exactly half
of that is a duplicate of the other half.**

`23.6.0` and `25.6.0` are not Qt versions. They are **Darwin kernel versions**:
macos-14 is Darwin 23.6.0, macos-26 is Darwin 25.6.0. `install-qt-action` puts
the runner's OS version in its cache key, so the same Qt 6.7, for the same
target, into the same path, was cached once for the jobs on macos-14
(`build-core-ios`, `m3-ios-sim-logic`) and again for the job on macos-26
(`m5-flutter-ipa`).

**4323 MiB of the allowance was one redundant copy of Qt** — and what it
crowded out was a **37 MiB** OCCT tree whose absence costs half an hour.

That is the whole mechanism. The first version of this document blamed the
2.22 GB Flutter SDK, which was real but second-order; the number that mattered
could not be guessed and had to be printed.

## 5. What changed

**The duplication (M426b).** `build-core-ios` and `m3-ios-sim-logic` moved from
macos-14 to macos-26, so all three Qt-installing jobs share one image and one
Qt cache generation. This was due regardless: macos-14 entered deprecation on
2026-07-06 and is unsupported from 2026-11-02. The risk the m5 comment names —
"Qt 6.7 + the Xcode 26 toolchain building qcad-core" — is already retired, because
m5 does exactly that on macos-26 today, with the same flags and the same Qt.

**The Flutter SDK cache** on the macOS runner is off. Measured hit against
miss, it saved **14 seconds** and cost 2.22 GB plus 1:14 uploading it.

**`cache-gc.yml`** holds the allowance under 8 GiB every six hours: caches of
workflows outside `build.yml`, then superseded generations of each rotating
key, then least-recently-accessed until under target. The OCCT trees and
Blender's iOS libraries are protected unconditionally. **Qt is protected only
while it is in use** — an entry touched in the last 24 hours stays, one that is
not (a generation belonging to a withdrawn runner image) is collectable. The
first draft protected anything matching `qt` outright, which would have
protected the problem and collected the 37 MiB it displaces.

**The duplicated suite.** `flutter test` ran twice: once in `dart-checks` on
ubuntu (4:26) and again inside M5 on macOS (9:09-11:35 depending on the run),
same command, same directory. It gated nothing — M5 already `needs:
dart-checks` — and sat on the critical path on the runner billed at ten times
the rate. Removed. What that gives up: a test that fails only on a macOS host.
The suite is host logic and asks the operating system nothing; if that stops
being true, the answer is a parallel macOS job, not a step inside this one.

**The gate.** M5 waited for all of `dart-checks`, so the 4:26 suite ran before
the expensive runner could start. The suite is its own parallel `dart-tests`
job now and the gate is `flutter analyze` alone. **Measured: 5:20 to 0:54.**
A red test still fails the run and still blocks the release through `needs`.
The gate's argument survives because it was never about tests — the case its
own comment describes is a typo, and `analyze` finds those in fifteen seconds.

**ccache on the build that is big.** The job installed ccache, cached
`~/Library/Caches/ccache` and set `CMAKE_*_COMPILER_LAUNCHER` on libslvs (0:15)
and the OCCT shim (0:17) — but not on the 4:40 core build. The saved tree was
**985 kB**, because it only ever held those two. With the flags on the core
build it saved **329 MB**. Whether that converts into time is not yet
measured: the run that populates a cache cannot benefit from it.

## 6. Measured

Run [34580467549](https://github.com/Toemeler/ipadprocad/actions/runs/34580467549)
against run [34568753636](https://github.com/Toemeler/ipadprocad/actions/runs/34568753636)
on `main`:

| | before | after |
|---|---|---|
| Dart gate blocking M5 | 5:20 | **0:54** |
| Dart suite inside M5 | 9:09 | **gone** |
| `build-core-ios`, Qt host + iOS | 1:25 + 1:22 | **0:23 + 1:04** |
| `build-core-ios`, whole job | 7:49 | **5:50** |
| M5, configure + build core | 5:06 | **0:21** |
| M5, build OpenCASCADE | 31:26 | **skipped — cache hit** |
| **M5, whole job** | **60:39** | **11:20** |
| **whole build** | **68:53** | **19:45** |

The cache, from the same run's diagnostic:

```
OCCT IOS CACHE: HIT — der 30-Minuten-Build entfaellt.
CACHE BUDGET: 7481 MiB von 10240 MiB belegt
3207 MiB  install-qt-action-mac-25.6.0-ios-...      <- one generation, not two
1640 MiB  flutter-linux-stable-3.47.3-x64-...
1116 MiB  install-qt-action-mac-25.6.0-desktop-...  <- one generation, not two
 548 MiB  blender-ios-libs-m294-v1
 314 MiB  ccache-ipa-497a2095...
  35 MiB  occt-ios-arm64-V7_9_3-r1                  <- survives
```

9671 MiB to 7481 MiB, and the entry that kept being evicted is sitting in it.

Two things are worth reading twice. **The core build went from 5:06 to 21
seconds** — that is the ccache flags reaching the build that is actually big,
restoring the 314 MiB tree the previous run wrote. And **`flutter build ios`
(4:26) is now 39% of M5**, which is what section 7 predicted would become the
floor once everything else got out of the way.

## 7. Why five minutes is still not reachable for the full build

M5 is 11:20 and the run is 19:45, which is close enough to the original request
to say exactly where the remainder sits. Of M5's 11:20:

| | |
|---|---|
| `flutter build ios --release` | 4:26 |
| Qt host + iOS install | 2:10 |
| scaffold + `pub get` | 1:04 |
| Install Flutter | 1:18 |
| analyze, verify, package, upload | 1:00 |
| configure + build core (ccache) | 0:21 |
| everything else | ~0:40 |

`flutter build ios` compiles this application — Dart AOT plus the Xcode link —
and does not cache across runners. The rest is installation. **The floor for a
full three-platform build is 10-15 minutes**, and 19:45 is already near it.

Five minutes is for finding out whether a change is good, and that is a
different question with a different answer:

- **`dart-checks` (0:54) and `dart-tests` (~6:18)** run on every push and answer
  "is this change correct?".
- **the full run (~20 min)** answers "does this ship on three platforms?".

## 8. If more is wanted after this

1. **`cycles-ios`'s cache key hashes the whole 89 KB `m1-core-build.yml`.**
   Editing a comment in any of its six jobs discards a ~7:30 build and writes a
   fresh 143 MiB entry — both generations are visible in the listing above,
   differing only in the last hash segment. Hashing that job's own inputs
   instead would fix it. `cache-gc.yml` collects the superseded generation, so
   this now costs time rather than space.
2. **`flutter build ios` (4:26) is the largest remaining step**, and mostly
   irreducible.
3. **Pin the OCCT trees as release assets rather than caches.** 35 MiB for iOS,
   changing only when the submodule pin or the configure flags do. A release
   asset cannot be evicted at all.
