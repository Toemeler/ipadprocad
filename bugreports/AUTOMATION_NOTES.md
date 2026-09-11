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

- #12 — **the entry above is wrong, and the fix did not work.** Appended
  rather than edited, per this file's own rule. `exportFormatsFor` is declared
  in `home_view.dart` and called from `lib/` NOWHERE: the export path is
  `_sendFile`, which asks `app.isPartName(name)` and then hardcodes its two
  menu items inline. Changing that function cannot affect the app, so tapping
  export still does nothing, and "the old code path then handled the part as a
  sketch" describes a path that does not exist. Every gate passed honestly —
  the test failed before and passed after, and coverage watched the changed
  lines run — because none of them asked whether the app can REACH the change.
  `verify.dead_new_symbols` now also examines the declaration whose body a hunk
  edits; replayed against this diff it names `exportFormatsFor`. Issue
  reopened.


- #12 — `exportFormatsFor` was never called by the gallery export action; the action still branched on `isPartName(name)`, which returns false for dotted names like `flange.ptp`. Part cards therefore skipped the STL/STEP chooser and fell into the sketch export path, producing no file. The format chooser also only existed for non-share part exports, with hardcoded items. Commit `0e0f480`.

- #12 — `exportFormatsFor` was never called by the gallery export action; the action still branched on `isPartName(name)`, which returns false for dotted document names like `flange.ptp`. Part cards therefore skipped the STL/STEP chooser and fell into the sketch export path, producing no file. `exportFormatsFor` also did not understand dotted names, returning only `['step']` for them even when called. Commit `220e3f9`.

- #46 — the bug-report upload stopped working on the iPad because the BUNDLE
  had grown, not because the relay had moved. Every rolling log went into the
  zip whole: the report filed on 2026-09-10 is 10.74 MB, of which 10.22 MB —
  95 % — is `performance_logs_prev.txt`, 57.6 MB of previous-session perf lines
  that nothing ever capped. That breaks the upload on a tablet twice over. By
  SIZE: `bugUploadTimeoutFor` caps its budget at 90 s, so 10.24 MiB asks for
  ~950 kbit/s of sustained uplink, which is the exact figure M415 wrote down
  as what a tablet does not clear and a desktop does — M415 made the budget
  follow the payload, and the payload then grew past where it still could. By
  MEMORY: `readAsStringSync` on 57.6 MB, re-encoded by the zip writer and
  deflated into a third buffer, is a few hundred MB of peak allocation on top
  of a CAD app holding meshes; Windows pages it out, iOS kills the process.
  Rolling logs are now read as their last 2 MiB via a seek (`readLogTail`),
  which takes that bundle under a megabyte and never materialises the rest.
  Two smaller faults on the same path went with it: the response BODY read had
  no deadline (only `send()` did), so a relay that stalled its answer left the
  app waiting forever behind a UI that shows nothing; and a non-200 threw away
  the relay's own explanation, so "bundle too large: N bytes" reached the
  reporter as "HTTP 413". Commit `a6fcc8d`.

## 2026-09-11

- #49 — "if the ribbon is retracted on ios there shouldnt be this Vertical
  bar. and it should only come expand when I swipe right from the left edge
  with a clean native Apple style animation." The retract grip (M405,
  `ribbon_dock_layout.dart`) already answered a tap AND a swipe toward the
  document, so the gesture asked for was already there; what was not is that
  retracted, the 18 pt strip kept painting a solid coloured bar with a
  chevron on it for as long as the ribbon stayed away — on a phone, where the
  ribbon retracts by default (M405/#38), that is most of the app's life.
  `fixed:` `ribbonGripPaintsBar(retracted)` — the strip keeps its size and
  both gestures either way, it just paints nothing while retracted, matching
  how iOS's own edge-swipe affordances draw nothing until touched. New
  `frontend/test/issue49_ribbon_grip_edge_test.dart`, confirmed failing
  against the old unconditional-paint behaviour and passing with the fix.
  Commit `b8928e7`.

- #50 — "the main workplanes when highlighted have these round circle
  corners which look awfull. the corners should be very small quadratic
  points." A work plane's border is a closed rectangle stroked as four
  independent round tube segments (`OutlineBuilder.tube`,
  `PartScene.swift`); that method's own comment already says the round
  joints are only invisible because "tiny joint gaps are invisible at these
  radii" on the free-form polylines it was written for — a work plane's
  sharp 90° corners are exactly the case where the circular cross-section
  shows past the corner. `fixed:` `OutlineBuilder.rectFrame` (new) strokes
  the same rectangle as four SQUARE cross-section boxes, mitered by
  extending each edge by its own half-width into the corner, so two boxes
  always meet flush there instead of showing a circle. Swift-only (the iOS
  platform code under `frontend/packages/*/ios/` cannot be compiled without
  Xcode, per this file's standing guidance); syntax-checked with a
  downloaded Linux Swift 6.0.3 toolchain (`swiftc -parse`, clean) since no
  Dart-testable seam exists for native RealityKit geometry — CI's macOS
  build remains the source of truth for the type-check. Commit `b49fc80`.

- #49 — **the entry above is a third of the fix, and the test under it proved
  nothing.** Appended rather than edited, per this file's own rule. The report
  asks for three things and `b8928e7` did one of them:

  * there was NO ANIMATION, which the report names outright. The rail stayed
    `SizedBox(width: retracted ? 0 : railWidth)` — absent to full width
    between two frames — before the fix and after it;
  * the strip stopped PAINTING but was still an 18 pt row child with
    `HitTestBehavior.opaque` on it, so it went on eating every tap and orbit
    landing at the screen edge, now with nothing drawn to explain why. An
    invisible dead zone is worse than the bar that was reported;
  * the swipe was never the reported one: `onHorizontalDragEnd` needed
    50 px/s AT RELEASE, so a slow deliberate drag did nothing and nothing
    tracked the finger;
  * and `expect(ribbonGripPaintsBar(true), isFalse)` asserted a constant, on
    a function written so that something could be asserted. Every gate passed
    and none of them asked what the report asked.

  `fixed:` (5a1c0ff) the handle is drawn only while the band is OUT;
  `_RibbonEdgeSwipe` is a translucent 20 pt overlay claiming horizontal drags
  and nothing else; it tracks the thumb by ABSOLUTE position (a drag competing
  with another recognizer spends its first move winning the gesture arena and
  that delta is never delivered, so summing deltas left the band a movement
  behind); it commits past halfway at any speed or on a flick; and the reveal
  is a 320 ms ease-out that clips the band to a fraction of its full size so
  the icons slide rigidly instead of squashing.

  Two faults the rework found that no gate would have reported: wrapping the
  tree in a Stack only while retracted REPARENTED the whole band on the frame
  the flag flipped, so the tween re-initialised at its target and snapped — an
  animation that is written and never runs; and `RibbonDockLayout` read the
  retract flag without listening, animating correctly only because main.dart
  happens to rebuild the shell.

  `frontend/test/issue49_ribbon_edge_swipe_test.dart` — seven widget tests on
  a 393x852 surface, each run against the behaviour it pins: forcing
  `kRibbonReveal` to zero fails exactly the animation test, forcing the edge
  zone back to `opaque` fails exactly the dead-zone test. `isPhoneOverride`
  (device_class.dart) is the seam, mirroring `RibbonSurface.glassOverride`;
  driving `defaultTargetPlatform` instead would make the host a phone for
  every widget test at once, which m405_ribbon_retract_test forbids.

- #51 — "somehow the planes look weird. the edges are the same color and
  exactly the same even when they are behind another plane." Not a matter of
  taste, and it did not need the colour decision I first asked the reporter
  for: it is arithmetic. All three origin planes were one frozen orange with
  the border a second orange beside it, and a plane draws as a 28% fill over
  an opaque border — so a border seen through the plane in front of it came to
  (238.3, 165.2, 100.6) against (240, 168, 104) in the open. Under four parts
  in 255: no depth cue at all, exactly as reported, and nothing to tell two
  crossing borders apart either. `fixed:` each origin plane takes the colour
  of the axis it stands ACROSS (`yz`->X, `xz`->Y, `xy`->Z), the same axisX/Y/Z
  the triad already draws, so the wash over a border is a different HUE and
  the same comparison lands in the tens of parts. Pushed from Dart on the
  existing `tint` payload road rather than named in PartScene.swift, per
  M237's rule about this app having two palettes; work planes and older native
  builds fall back to the orange unchanged. `issue51_plane_depth_cue_test.dart`
  runs the renderer's own compositing over both palettes and keeps a permanent
  negative control that holds the two oranges BELOW the bar. Commit `598a1ad`.
