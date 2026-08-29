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
