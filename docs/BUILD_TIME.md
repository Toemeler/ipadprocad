# Where the build's hour goes

Measured on the last three green runs of `build.yml`, from the GitHub Actions
job and step timings — not from estimates.

| run | commit | wall clock |
|---|---|---|
| [34478689042](https://github.com/Toemeler/ipadprocad/actions/runs/34478689042) | `7b0af49` | **78 min** |
| [34493818656](https://github.com/Toemeler/ipadprocad/actions/runs/34493818656) | `9076e08` | **65 min** |
| [34471044060](https://github.com/Toemeler/ipadprocad/actions/runs/34471044060) | `0fa7246` | 54 min |

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

## 3. The OCCT cache was being evicted, and nothing said so

The step is called "cache miss only" and is skipped on a hit, so in the log a
hit looks like a miss somebody already fixed, and a miss looks like a build
that simply takes that long. It took reading three runs side by side to see it:

| run | restore step | build step | post-job save |
|---|---|---|---|
| 34478689042 | 1 s | **38:20** | 7 s → `Cache saved with key: occt-ios-arm64-V7_9_3-r1` |
| 34493818656 | 0 s | **29:35** | 5 s → `Cache saved with key: occt-ios-arm64-V7_9_3-r1` |

The key is a constant — `occt-ios-arm64-V7_9_3-r1`, no hash, no `hashFiles`.
Both runs were on `main`, two and a half hours apart. Both missed. And both
**saved successfully afterwards**, which is the part that settles it: a cache
save only succeeds when the key is free. So the entry existed at 14:03, was
gone by 15:37, was rebuilt, and was gone again by the next run.

Nothing in the repository deletes caches. GitHub does, when a repository is
over its 10 GB allowance: least recently used first, silently.

This repository is far over it. Six OCCT install trees (`ios-arm64`, `linux`,
`windows`, `host`, `macos-arm64`, `sim-x86_64`), Blender's precompiled library
set for iOS *and* macOS, Qt for four targets, two ccache trees, the Cycles
distributions — and a 2.22 GB Flutter SDK per platform per patch release. On
top of that, every content-hashed key (`ccache-ipa-<hash>`,
`cycles-linux-<ref>-<hash>`) writes a *new* entry on every change and never
removes the old one.

The OCCT iOS tree is the single most expensive thing in the cache and one of
the least frequently written, so it is exactly what LRU eviction takes first.

## 4. What changed (M426)

**The eviction.** `subosito/flutter-action` had `cache: true` on the macOS
runner. Measured against each other, run 34478689042 (hit) installed Flutter in
1:17 and run 34493818656 (miss) in 1:31 — the cache saved **14 seconds**, and
cost 2.22 GB of the allowance plus 1:14 uploading it in the post-job. It is off.
`.github/workflows/cache-gc.yml` now holds the allowance under 8 GiB on a
six-hourly schedule, in three passes: caches belonging to workflows that are
not part of `build.yml`; superseded generations of every rotating key; and, if
that is not enough, least-recently-accessed first until it is. The three OCCT
trees, Blender's iOS libraries and anything Qt are protected in every pass.
`m5-flutter-ipa` now also prints, in its own log, whether the OCCT cache hit
and how full the allowance is — so this cannot be invisible a second time.

**The duplicated suite.** `flutter test` ran twice: once in `dart-checks` on
ubuntu (4:26) and again inside M5 on macOS (11:35), same command, same
directory. The macOS copy gated nothing — M5 already `needs: dart-checks` — and
sat on the critical path on the runner that bills at ten times the rate. It is
gone. What that gives up, stated plainly: a test that fails only on a macOS
host will no longer be caught. The suite is host logic (solver, dimension
system, document container) and asks the operating system nothing, so this is
judged cheap; if it stops being true, the answer is a parallel macOS job, not a
step in the middle of this one.

**The gate.** `m5-flutter-ipa` waited for all of `dart-checks`, so the 4:26
test suite ran *before* the expensive runner was allowed to start. The suite
moved to its own parallel `dart-tests` job and the gate is now `flutter
analyze` alone, ~45 s. A red test still fails the run and still blocks the
release through `needs` in `build.yml`; it just no longer holds M5 back. The
gate's original argument survives intact, because it was never an argument
about tests — the case its comment describes is a *typo*, and `analyze` finds
those in fifteen seconds.

**ccache on the build that is actually big.** The job installs ccache, caches
`~/Library/Caches/ccache`, and set `CMAKE_*_COMPILER_LAUNCHER` on libslvs (0:15)
and the OCCT shim (0:17) — but not on the 4:40 core build. The saved ccache
tree was 985 kB, because it only ever held those two. The flags are on the core
build and the OCCT rebuild now. `restore-keys: ccache-ipa-` was already there,
so a C++ change recompiles only what it touched, and a Dart-only change — the
case this is all for — should come out of the cache entirely.

## 5. What to expect, and what is not reachable

With the OCCT cache holding, the arithmetic on run 34493818656's own step times
is 65 min → **≈15 min**: 29:35 of OCCT and 11:35 of duplicated tests leave the
critical path, the gate gives back ~4:30, and ccache should take most of the
4:40 core build with it on a Dart-only change.

**Five minutes is not reachable for this build, and it is worth being exact
about why.** With every cache hitting and nothing wasted, M5 still has to
install Qt and Flutter (~2:40), scaffold the iOS project and run `pub get`
(1:01), link the core (4:40, less with a warm ccache), run `flutter build ios
--release` (4:42), and package and upload the IPA (0:30). `flutter build ios`
and the Xcode link are irreducible: they compile this application. That floor
is **10–15 minutes**, and it is the floor for producing a signed-shaped IPA plus
a Windows installer plus a Linux tarball — not for finding out whether a change
is good.

For that, the thing to watch is the two-tier split this already has:

- **`dart-checks` (~45 s) and `dart-tests` (~4:30)** answer "is this change
  correct?" and are the jobs to read on a push. That is the one-to-five-minute
  loop, and it exists today.
- **the full run (~15 min)** answers "does this ship on three platforms?", and
  is worth waiting for once, not on every keystroke.

## 6. If more is wanted after this

Roughly in order of return:

1. **`flutter build ios` (4:42) is the largest remaining item.** Most of it is
   Dart AOT plus the Xcode link, and neither caches well across runners.
2. **A Dart-only change still rebuilds every native artifact.** All of them
   come from caches, but the jobs still spin up. A path filter that reuses the
   previous run's native artifacts when nothing under `backend/` changed would
   cut the desktop jobs out entirely — they are off the critical path, so it
   buys billing rather than wall clock.
3. **Pin OCCT as a release asset instead of a cache.** It changes only when the
   submodule pin does, it is 37 MB compressed, and a release asset cannot be
   evicted. That removes this failure mode permanently rather than managing it.
