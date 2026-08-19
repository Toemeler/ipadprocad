# CROSS-SESSION

**Append-only.** Add entries at the end. Never edit or delete an entry written
by another session — see `OPTIMIZATION_PLAN.md` §7.

Format: `## <date> — <session> — <one line>` then the detail.

---

## 2026-08-19 — S4 (painter) — `quality.frameBudget` hardcodes the two solves I removed

**What I need:** one line changed in `frontend/lib/perf_scenarios_quality.dart`,
in the `quality.frameBudget` scenario:

```dart
// TWO solves per painted frame — that is what the painter actually
// does today (viewport.dart:2088 and :2683), so a budget computed on
// one solve would be optimistic by exactly a factor of two.
final perFrame = ms * 2;
```

**Why:** that is no longer what the painter does. S4 memoised
`displayGeometry` on the drag position, so every caller within one drag position
— both paint phases, the tool preview, the snap path and `endGripDrag` — shares
one solve. The painter now performs **one** solve per painted frame, and the
comment's own justification for the factor is what changed.

**What I would change:** `ms * 2` to `ms`, and the comment and the scenario
`note:` to match. I have **not** done it: `lib/perf*.dart` is the measurement
apparatus and plan §3 puts it off limits to every session, because changing the
suite invalidates `perf/baseline.json` and every comparison built on it.

**Consequence if it is left alone — and this needs saying at integration:**
`quality.budget.entitiesAt120Hz` (192) and `quality.budget.entitiesAt60Hz` (256)
will come back from the device run **unchanged**, because they are computed from
the hardcoded factor rather than observed from the painter. That is not evidence
the fix did nothing. It is the apparatus reporting a painter that no longer
exists. Registered as prediction P2 in `S4-painter.md`.

**Whose call:** whoever runs integration (plan §8). The correction and the
baseline re-record want to happen together, in that order.
