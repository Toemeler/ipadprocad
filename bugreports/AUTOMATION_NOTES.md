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
