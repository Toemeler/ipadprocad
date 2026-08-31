# Automation notes

Running log for the bug-report automation. Read first; append, don't rewrite.

## Guidance (persistent)

- Swift (the iOS platform plugins under `frontend/packages/*/ios/`) CANNOT be
  compiled in the Linux sandbox — no Xcode, no Apple SDK. That is normal, not a
  reason to block. Run `flutter analyze` and `flutter test` (the Dart suite does
  not exercise Swift) and push; CI's macOS build compiles the iOS plugin and is
  the source of truth for Swift.

## 2026-08-28

- #2 — rendered mode: no floor shadow. `fixed:` `DirectionalLightComponent.Shadow.maximumDistance` is deprecated on iOS 18 (→ `shadowProjection`) and may be ignored, killing the shadow on every model; `depthBias = max(1.0, reach * 0.02)` also exceeded a thin part's floor gap. Commit `d9d6d0d`.
- #3 — gallery (home "menu") chrome (bottom tab bar, bug button, quick-tool rail) stayed offset because it cleared a ribbon band that isn't drawn there; the docking insets held their last document values. `fixed:` gated insets on whether the band is actually drawn (`RibbonMetrics.contentInsetsFor(ribbonDrawn)` → zero when absent), used with `!app.isHome`. Commit `dd6e2ee`.
- #5 — appearance dropdowns (Material, Display mode) drew as an opaque dark "field" well with a near-black `sep` seam, reading as holes punched through the liquid-glass ribbon. `fixed:` switched both chips to the same translucent wash `_DropChip` already uses (`hover6` fill, `border10` hairline; `hover7`/`accent` when hovered). Commit `e3fc520`.

## 2026-08-29

- #6 — coordinate triad (viewport, LEFT dock) sat `collapsedWidth` (80 pt) out in open space when the model browser was retracted, even though M199 removed the glass slab and left only the glyph column at the TOP of the card — the bottom-left corner is clear. `fixed:` mapped the collapsed occupancy back to the left border via `NativeModelBrowser.triadInset` (returns `0` when `occupied == collapsedWidth`, else `occupied`), applied in both `viewport3d.dart` and `viewport_assembly.dart`; added `frontend/test/coordinate_triad_test.dart`. Commit `bbe253b`.

- #7 — no way to hide the rendered floor. `fixed:` a "Boden anzeigen"/"Display floor" checkbox under Aussehen/Appearance, shown only while `displayMode.isRendered` (the working views draw no floor, so a checkbox there would do nothing); it flips a per-document `showFloor` (default visible, written only when hidden) threaded PartModel/AssemblyModel → scene payload + signature → the Swift renderer's `applyGround()` (`guard rendered, showFloor`). New `viewFloor` strings (de/en) + `frontend/test/m286_floor_toggle_test.dart`. Commit `d1a18c5`.

- #8 — rendered floor was a hardcoded charcoal, so the model browser's icons (which flip dark-on-light per scheme) vanished against it in Chalk mode. `fixed:` added a per-scheme `Palette.floor` pushed Dart → `setFloorColor` method channel → `RealityPartView.setFloorColor`, re-tinting live renderers' ground plane via `applyGround()`/`groundMaterial()`; new contrast test in `m236_theme_test.dart`. Commit `f5f309e`.

- #9 — The gallery export action (`_sendFile`) fixed the format by document kind and called `partExportStep`/`sketchExportPath` immediately, so the destination picker opened with no format choice. The format picker belongs before the location picker for 3D part cards, and STL export itself is missing from `AppState`. Commit `0431693`.

- #10 — The export format chooser used a Flutter Material `SimpleDialog` instead of the app's native glass menu surface. The STL writer emitted zero facet normals because it didn't compute them from the triangle geometry; the fix calculates and normalizes each triangle's cross-product normal before writing the binary STL. Commit `7bf188d`.

## 2026-08-31

- #11 — the accent (the "blueish green" for icons, selection and highlight) was
  the palette's, with no way to change it. `fixed:` an `Accent` enum in
  `theme.dart` — eight entries, each carrying a LIGHT and a DARK value because
  a teal that reads on cream is not the teal that reads on charcoal — behind
  `T.accent`, which all ~450 call sites already read; its own `ValueNotifier`
  and one more builder at the app root, because `T.scheme` holds the same
  `Palette` instance before and after and so never fires; `materialTheme` takes
  the accent as an argument so the cursor and selection follow it; the choice
  merges into the same `settings.json` as the appearance and the language. A
  CLOSED LIST rather than a picker: `m236_theme_test` holds the accent to
  4.5:1 against panel and viewport in both palettes, and that test now iterates
  every entry (worst case 5.04:1). Commit `97cf4cc`.

  Written BY HAND, not by the pipeline, after eight attempts and ~$2.15. The
  native glass tab bar still uses its built-in teal: `GlassTabBar.swift` holds
  the two accents as `static let` UIColors captured across the view tree, and
  making them settable is Swift that cannot be compiled here.

### What the eight attempts on #11 taught the pipeline

Every one of these was the pipeline withholding or misstating something, not
the model reasoning badly, and each fix is general:

- the relay appends `Bundle:` and `Raw zip:` URLs to every report, so `bug`,
  `zip`, `github` and `raw` were half the query on a short one and ranked the
  bug REPORTER above the file the fix belonged in. Stripped from the ranking
  query.
- a house rule that names a file ("every colour lives in theme.dart") is
  evidence BM25 cannot see, because the widgets that use a colour mention it
  far more than the one file allowed to define it. `pack.PINNED` promotes it.
- a pinned file is grepped, not query-sliced: the slicer spent theme.dart's
  whole budget on one run of `final Color x;` declarations and never reached
  the two `accent: Color(0x…)` palette rows.
- `DECL_RE` did not match getters, so all of `T` counted as mentions.
- the model's own earlier patch stays in its context while `git_reset` throws
  it away, so it wrote SEARCH text against a file state that never existed.
  The repair prompt now says the tree was reset.
- "SEARCH appears 2 times" named neither. In this app that is the EXPECTED
  shape of a correct fix — every native surface has a Flutter fallback — so it
  now names both sites and says so.


- #12 — `exportFormatsFor` matched the human-readable labels `'part'`/`'sketch'`, but document kinds are stored by file extension (`ptp`/`pts`). Part cards therefore fell through to the default `['step']`, so the chooser never offered STL, and the old code path then handled the part as a sketch, producing no export. Commit `d3b8d51`.
