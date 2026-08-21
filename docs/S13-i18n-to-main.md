# S13 — moving the M234 localisation off the perf branch and onto `main`

**What this was.** S12 made the app natively German with an English toggle
(M234). That work landed on `claude/perf-opt2` only because that is where S12
was told to work. This session replays it onto `main` on its own lineage, so
that a perf regression and a translation change never have to be bisected as
one unit.

**`claude/perf-opt2` was not touched.** No push, no merge, no rebase, no
cherry-pick into it. The branch still points at `4858fc4`, which is the commit
the unsigned IPA for the round-two device capture was built from. Everything
below was read out of that lineage and written only to
`claude/i18n-to-main-s13-8hol4t`.

---

## 1. The seven commits, and where each landed

Source range `783a905..3b71df8` (7 commits, no merges), replayed in order onto
`origin/main` @ `8b7e636`:

| # | S12 commit | S13 commit | conflicts |
|---|-----------|-----------|-----------|
| 1 | `8a999ee` die Lokalisierungsschicht — ARB, Sprachumschalter, Ribbon, Galerie | `4409bbe` | **3, all in `ribbon.dart`** |
| 2 | `ff522cc` alle sichtbaren Zeichenketten in die Lokalisierungsschicht | `5eb4124` | none (3 files auto-merged) |
| 3 | `cba4ce0` die Tests, die Arbeitselement-Meldungen und die Ratsche | `57d7932` | `perf/findings/` only — dropped |
| 4 | `1aac0f0` der Restbestand an englischen Zeichenketten, und der geerbte Bruch | `296d3a7` | `perf/findings/` only — dropped |
| 5 | `46d4169` m205 prüft die Schlüssel statt der englischen Beschriftungen | `2191a69` | none |
| 6 | `15f91aa` das Dezimalkomma in zwei Tests, und der systematische Durchgang | `23c5bf4` | `perf/findings/` only — dropped |
| 7 | `3b71df8` den geerbten Bruch am Ende der Sitzung noch einmal nachgestellt | **— (not replayed)** | n/a |

**Commit 7 is deliberately absent, and this is not an omission.** `3b71df8`
changes exactly one file, `perf/findings/S12-i18n.md`, by 22 lines. It contains
no `frontend/` content at all (`git diff --name-only 15f91aa 3b71df8 --
frontend/` returns nothing). Under the rule that the optimisation project's
record stays with the optimisation project, it replays to the empty commit. I
did not create an empty commit for it.

Net: **57 files, 17104 insertions, 1369 deletions.** That is S12's 59 files /
17894 insertions minus exactly `perf/findings/CROSS-SESSION.md` (63 lines) and
`perf/findings/S12-i18n.md` (727 lines) = 790 lines. The two numbers reconcile
to the line.

Of the 17104 insertions, **14257 are generated or declarative**
(`lib/l10n/gen/*` and the two `.arb` files) and 2847 are hand-written. None of
the generated code was hand-edited — see §4.

---

## 2. The conflicts: what caused them and how each was resolved

### The divergence surface is five files, not the whole tree

Before replaying anything I measured which of S12's files actually differ
between `main` and S12's base `783a905`:

```
$ git diff --name-status main 783a905 -- <every file S12 touched>
M frontend/lib/app_state.dart
M frontend/lib/main.dart
M frontend/lib/widgets/ribbon.dart
M frontend/lib/widgets/viewport.dart
M frontend/lib/widgets/viewport3d.dart
```

Five files. Every other file S12 touched is byte-identical on `main` and on
S12's base, so those replay verbatim and cannot carry perf collateral. This
also confirms the brief's first established fact from the other direction:
nothing S12 touched was created by a perf session.

Note this corrects one detail of the brief in a way that mattered: the brief
listed S3/S4 as touching `app_state.dart` only, but `viewport.dart` also
carries S4 (`8a0e8c9`), plus M211b and M212 fixtures. It was in the conflict
surface I had to watch, and it auto-merged rather than conflicting.

### The three real conflicts — all in `ribbon.dart`, all from `b08a721` (M209c)

M209c split three ribbon builders in two so it could wrap them in a
`Perf.span`:

```dart
Widget _homeRibbon(AppState app) =>
    Perf.span('menu.ribbon.home', () => _homeRibbonInner(app));

Widget _homeRibbonInner(AppState app) {
```

S12's localisation change to each of those methods was to insert
`final t = L.of(context);` as the first line of the body. Both edits land on
the same line, so all three conflicted.

| file | line | perf commit | resolution |
|---|---|---|---|
| `lib/widgets/ribbon.dart` | `_homeRibbon` | `b08a721` M209c | kept **main's** un-split signature, applied **S12's** `final t = L.of(context);` |
| `lib/widgets/ribbon.dart` | `_partRibbon` | `b08a721` M209c | same |
| `lib/widgets/ribbon.dart` | `_sketchRibbon` | `b08a721` M209c | same |

The `Perf.span` wrapper and the `_xRibbonInner` split were discarded, and the
resulting file has no reference to either (`grep 'RibbonInner\|Perf\.'
lib/widgets/ribbon.dart` is empty). These three are the only hand resolutions
in the whole transplant. **I did not guess at intent on any of them** — see §6.

### Everything else auto-merged

`app_state.dart`, `main.dart`, `viewport.dart` and `viewport3d.dart` all
auto-merged. Auto-merge is the dangerous case here, not the conflicting one:
git applies S12's hunks silently and nobody looks. So I verified them
mechanically rather than by eye, with the invariant in §3.

### The `perf/findings/` conflicts were expected and are not resolutions

Commits 3, 4 and 6 each raised a `modify/delete` conflict on
`perf/findings/CROSS-SESSION.md` and/or `perf/findings/S12-i18n.md`, because
those files do not exist on `main`. Each was dropped with `git rm --cached`
plus a working-tree delete. Nothing under `perf/` is in any of my six commits.

---

## 3. Leak checks

### Check 1 — every changed path is under `frontend/`

```
$ git diff --name-only origin/main...HEAD | grep -v '^frontend/'
(no output)
```

All 57 changed paths are under `frontend/`. No `perf/`, no `backend/`, no
`ci/`, no `PERFORMANCE_PROFILE.md`.

### Check 2 — no `Perf.` on any added line

```
$ git diff origin/main...HEAD -- frontend/ | grep -nE '^\+.*Perf\.'
(no output — empty, as required)
```

Empty. Also empty for `Perf.count`, `Perf.gauge` and the S3/S4 identifiers.

**One thing worth stating plainly, because the check reads as stronger than it
is:** `main` *already* carries a `Perf` class of its own — `lib/perf.dart`
exists on `main`, and `app_state.dart` on `main` already contains four `Perf.`
call sites. So a stack trace from the test run on this branch does show
`Perf.span (package:prototype/perf.dart:211)`, and that is main's own
pre-existing code, not a leak. What must not cross is the M209/M209b/M209c/M210
measurement net and the S3/S4 optimisation bodies, and the check above — which
only looks at *added* lines — is the right instrument for that. It is clean.

### Check 3 — the strong one: my tip differs from S12's tip by *exactly* the perf lineage

The two checks above prove nothing perf-shaped came across. They do not prove
that all of the localisation *did*, nor that an auto-merge did not quietly drop
a hunk. So I checked the stronger property directly. For every file, the
residual difference between my result and S12's result should equal the
pre-existing divergence between `main` and S12's base:

    diff(my_tip, 3b71df8)  ==  diff(main, 783a905)      for every file

Comparing changed lines only (context and hunk offsets necessarily differ),
**55 files** differ between my tip and S12's tip under `frontend/`. Of those,
**27 exist on `main`, and the invariant holds exactly for all 27** — including
all five conflict-surface files. Zero violations:

```
OK  frontend/lib/app_state.dart          (residual == perf divergence, 217 lines)
OK  frontend/lib/main.dart               (residual == perf divergence,  21 lines)
OK  frontend/lib/widgets/ribbon.dart     (residual == perf divergence,  19 lines)
OK  frontend/lib/widgets/viewport.dart   (residual == perf divergence, 143 lines)
OK  frontend/lib/widgets/viewport3d.dart (residual == perf divergence,  21 lines)
OK  frontend/lib/solver.dart             (residual == perf divergence, 937 lines)
OK  frontend/lib/perf.dart               (residual == perf divergence, 361 lines)
... (20 more, all OK)
```

The other **28** are perf-only files that do not exist on `main` at all, so no
divergence is possible for them (`perf_scenarios*.dart`, `perf_hook.dart`,
`PerfProbe.swift`, `RvPerf.swift`, the m211/m213/m232/m233/s4/s9 tests). They
correctly stayed off.

This is the result I would want the integrator to have: **the localisation
transplant added nothing the perf lineage did not have, and dropped nothing the
perf lineage did have.** The two lineages now differ by the perf work alone.

---

## 4. `flutter gen-l10n` round-trips clean

```
$ rm -rf frontend/lib/l10n/gen && flutter gen-l10n && git status --short
(no output)
```

**Clean.** The committed `lib/l10n/gen/*` is byte-identical to what the two
ARBs produce. The 14257 generated/declarative lines are genuinely generated;
none were hand-written and the committed output matches the ARBs.

Worth recording for the integrator: `l10n.yaml` sets
`template-arb-file: app_de.arb`. **German is the template, not the
translation** — gen-l10n reads placeholders, plural forms and descriptions from
it, so `app_en.arb` is the translation of the German source. Anyone
regenerating after a merge needs to keep that direction.

---

## 5. The two known hazards

### The lockfile — checked, and the verbatim replay turns out to be correct

The brief warned that `flutter pub get` on a different channel than CI silently
rewrites `pubspec.lock` (S3-3, S3-6). It does. I measured it rather than
assuming, in a throwaway worktree on pristine `main`:

- **Baseline drift:** `flutter pub get` on **untouched `main`**, with CI's
  toolchain (`channel: stable` = Flutter 3.47.1 / Dart 3.13.1), already
  rewrites 19 lines of `pubspec.lock` — `fake_async`, `leak_tracker` ×3,
  `matcher`, `material_color_utilities`, `meta`, `test_api`, `vector_math`, and
  the `dart:` constraint. That drift is nothing to do with S12; it is main's
  lockfile being stale against current stable.
- **S12's lock diff** is exactly that same baseline drift **plus**
  `flutter_localizations` (sdk) and `intl` `0.20.3` — which are precisely the
  two dependencies S12 intended.
- **Proof:** I took main's tree, applied only S12's `pubspec.yaml` and
  `l10n.yaml` and the two ARBs, ran `flutter pub get` on the CI toolchain, and
  diffed the result against S12's committed lock:

  ```
  $ diff -u /tmp/s12lock <regenerated>
  IDENTICAL — S12's lock is exactly what CI stable resolves
  ```

So replaying S12's lockfile verbatim was the right move, not a risk: it is
byte-for-byte what CI will resolve. Confirmed after the fact too — `flutter pub
get` on my finished branch left `pubspec.lock` **untouched** (`git status` clean).

`frontend/.flutter-plugins-dependencies` never appeared as a tracked or
untracked change; it is covered by `frontend/.gitignore:8`, so the
absolute-local-paths hazard is neutralised by the repo itself.

### `l10n_untranslated.json` — not in the final tree

`8a999ee` added `frontend/l10n_untranslated.json`; `1aac0f0` removed it and
redirected the generator's report to `.dart_tool/l10n_untranslated.json`, which
is not versioned. Both replayed, so the net is zero. Verified on the final
tree: `frontend/l10n_untranslated.json` does not exist, and after a fresh
`gen-l10n` the report lands in `.dart_tool/` containing `{}`.

---

## 6. What I changed rather than replayed verbatim

**Nothing in the source, other than the three `ribbon.dart` resolutions in §2.**
There is no file on this branch that differs from S12's version by anything
other than the absence of perf-lineage content — §3 check 3 is exactly that
statement, verified mechanically.

Two deliberate non-changes, both of which I could have "tidied" and chose not
to:

1. **The `unnecessary_import` info in `test/l10n_completeness_test.dart:17`.**
   This is the single new analyzer issue on the branch (see §7). It is a
   one-line deletion and entirely safe. I left it, because replay fidelity is
   the point of this task: editing that line would make the file differ from
   S12's version for a non-fatal info, and would give the integrator a
   gratuitous textual conflict to resolve when the two lineages are
   reconciled. If someone wants it gone, it should be a separate commit on
   `main` afterwards.
2. **Commit messages.** Kept S12's German subject lines verbatim, with a
   provenance trailer appended naming the source SHA and branch, so the
   integrator can map each commit back. The commits are cherry-picked with
   `-x`, so the original SHA is recorded twice.

---

## 7. Definition of done

| # | check | result |
|---|---|---|
| 1 | `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | **exit 0**, zero errors |
| 2 | `flutter test` (whole suite) | **1984 tests, all passed**, exit 0 |
| 3 | `gen-l10n` round-trip | **clean**, empty diff |
| 4 | leak checks | **both empty** (§3) |
| 5 | German default, English toggle, `LocaleStore` outside the `.ptp` | **verified** (below) |

### On "zero issues" in check 1 — the honest number

`flutter analyze` reports **56 issues** on this branch. It reports **55 on
pristine `main`**. Literal zero is not reachable without editing files this
task has no business touching. What I can state precisely is the *delta*, which
I measured by running the same analyze on a pristine `main` worktree and
diffing the normalised issue lists:

- **0 new errors** (there are no errors at all, on either branch).
- **0 new warnings.**
- **+1 new info:** the `unnecessary_import` in `test/l10n_completeness_test.dart:17`.

Every other apparent difference is the same pre-existing issue at a shifted
line number (18 `withOpacity` deprecation infos and 4 warnings that moved
because the localisation inserted lines above them). Exit code is 0 under CI's
flags, which is what `dart-checks` actually gates on.

### Check 2 detail

Whole suite green. The 18 pre-existing test files S12 modified were also run in
isolation (`+276: All tests passed!`), as were the four new
`l10n_*_test.dart` (`+28: All tests passed!`).

One risk here did not materialise but is worth naming, because it easily could
have: `l10n_no_hardcoded_test.dart` walks `lib/widgets` and carries a
per-file allow-list. It excludes files whose name starts with `perf`, and every
file it names in the allow-list exists on `main`. Its "the allow-list is not
stale" assertion passes on `main`'s narrower widget layer. Had S12 allow-listed
a string that only exists in a perf-only widget, that test would have failed
here — it does not.

### Check 5 detail

- `lib/l10n/l.dart:56` — `static final ValueNotifier<Locale> locale =
  ValueNotifier<Locale>(kDe);`. **German is the default**, not a
  device-locale guess.
- `lib/main.dart` wraps `MaterialApp` in a `ValueListenableBuilder<Locale>` on
  `L.locale`, so the toggle rebuilds the subtree without a restart.
  `l10n_toggle_test.dart` (234 lines) exercises this and passes.
- `app_state.dart:1242` — `L.attachStore(LocaleStore(_cacheRoot))`, and
  `_cacheRoot` is `Directory('${_docsDir!.path}/.cache')` (`app_state.dart:1287`).
  So persistence is `<documents>/.cache/settings.json`, as required.
- The locale is **not** in the document. No `locale` key appears in any `.ptp`
  serialisation path. `locale_store.dart` states the reason in its header: a
  `.ptp` is a part, not a workstation setting. **Property preserved.**

---

## 8. What I am unsure of

Ranked by how much it could matter.

1. **I did not verify the three `ribbon.dart` resolutions at runtime, only
   structurally and by test.** I am confident in them — the perf hunk and the
   S12 hunk are trivially separable, and §3 check 3 proves the residual is
   exactly `Perf.span` and the `Inner` split — but "the ribbon renders
   correctly in German on a device" is not something I measured. The test suite
   covers the ribbon (`m50_ribbon_slimming_test`, `m57_new_menu_test`,
   `m205_flyout_button_test` all pass), which is why I rate this low. **I did
   not guess at intent on any conflict.** All three had one mechanical reading
   and I took it.

2. **I could not run CI's toolchain identically, only equivalently.** I
   installed Flutter 3.47.1 stable, which is what `subosito/flutter-action@v2`
   with `channel: stable` resolves to *today*. If stable moves between my run
   and CI's, the lockfile conclusion in §5 could shift. It would show up as a
   `pubspec.lock` rewrite in CI, not as a test failure.

3. **The lockfile carries 19 lines of baseline SDK drift onto `main`.** This is
   measured, not assumed (§5), and it is drift `main` would take on its next
   `pub get` by anybody. But it does mean commit `4409bbe` — nominally a
   localisation commit — also refreshes nine transitive package pins. If the
   integrator would rather `main` took that separately, it is separable: the
   localisation-only part of the lock diff is `flutter_localizations` and
   `intl`. I judged splitting it to be more churn than it is worth and did not
   do it.

4. **I did not review S12's German for quality**, by instruction. If a string
   is wrong, it is wrong identically on both lineages, which is the correct
   place for it to be wrong.

5. **`3b71df8` not being replayed is a judgement call I want visible.** It is
   the only one of the seven that produced no commit. I believe dropping it is
   right — it is 22 lines of a findings file and contains no product code — but
   if someone counts commits rather than content they will find six where the
   brief said seven. The content is fully accounted for; the range
   `783a905..3b71df8` is replayed in full apart from `perf/findings/`.

---

## 9. Note for the integrator

After this lands, `main` and `claude/perf-opt2` both carry the M234
localisation from two different lineages, and merging them will need care. I
was told not to solve that, and did not. What should make it tractable:

- The two lineages now differ by **exactly the perf work** — §3 check 3 is a
  mechanical statement of that, and it can be re-run at any time.
- The only places where the localisation and the perf work genuinely overlap
  are the **three `ribbon.dart` builders** (`_homeRibbon`, `_partRibbon`,
  `_sketchRibbon`). Everywhere else the two changesets are disjoint and should
  merge without a decision. On those three, the reconciled result wants
  **both**: the `Perf.span` wrapper and the `_xRibbonInner` split from
  `b08a721`, *and* `final t = L.of(context);` as the first line of the `Inner`
  body. `main` currently has the second without the first; `claude/perf-opt2`
  has both.
- `perf/findings/S12-i18n.md` and S12's `CROSS-SESSION.md` entries were left on
  the perf branch untouched, so the optimisation project's record is intact and
  needs no repair.
- `claude/perf-opt2` still points at `4858fc4`. The IPA under test still
  corresponds to the branch.
