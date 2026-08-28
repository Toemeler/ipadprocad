# Automation notes

Running log for the bug-report automation. Read first; append, don't rewrite.

## 2026-08-28

- #2 — rendered mode: no floor shadow. `blocked:` RealityKit shadow (Swift, device-only, unverifiable here); `maximumDistance` deprecated iOS 18+ (→ `shadowProjection`) and `depthBias = reach * 0.02` (≈3.8 mm) outgrows the 2 mm part. Patch proposed in the issue comment.
