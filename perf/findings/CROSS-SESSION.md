# Cross-session notes — append only

Per `OPTIMIZATION_PLAN.md` §7: this file is for things you need that live in
another session's files, and for defects you find in another session's area.
**Append; never edit an existing entry.** A silent fix in someone else's file is
indistinguishable from a merge accident and will be reverted.

Format: `<session>-<n>`, what, where, what you would change, and whether you are
blocked on it.

---

## S1-1 — §6.5 evidence 4 prints a Student-t interval; everything else prints 1.96

**Found by:** Session 1 (bench harness), while choosing the reference intervals
the Lane C calibration gate compares against.
**Files:** `PERFORMANCE_PROFILE.md` §6.5 (nobody edits it), possibly
`ci/perf_report.py` / `ci/perf_profile.py`.
**Blocked:** no. Worked around, in the open.

Refitting §6.5 evidence 4's own published rungs — 360/720/1440 edges against
616/2508/10017 ms — reproduces the section's point estimate and its residual
exactly:

| | |
| --- | --- |
| k | **2.0117** (§6.5 prints 2.012) |
| R² | 0.99998 (§6.5 prints 1.0000) |
| se | 0.007995 |
| k ± 1.96·se | **[1.996, 2.027]** |
| k ± t(0.975, df=1)·se = k ± 12.706·se | **[1.910, 2.113]** |

§6.5 prints **[1.910, 2.113]** — the Student-t interval at one degree of
freedom. But the other two fits in the same section print the normal interval:

| Evidence | N | printed CI | k ± 1.96·se | k ± t·se |
| --- | ---: | --- | --- | --- |
| 1 — `ramp.allEdges` | 7 | [1.910, 1.960] | **[1.911, 1.961]** ✓ | [1.904, 1.969] |
| 2 — `edgeInfoScale` | 4 | [0.97, 1.01] | **[0.973, 1.005]** ✓ | [0.954, 1.024] |
| 4 — `stress.allEdges` | 3 | [1.910, 2.113] | [1.996, 2.027] | **[1.910, 2.113]** ✓ |

`ci/perf_profile.py:170` computes `k ± 1.96·se` and nothing in `ci/` computes a
t critical value, so evidence 4's interval did not come from the recorded
tooling.

**Which is right is a real question, not a typo.** At one degree of freedom the
t interval is the statistically defensible one and the normal interval is far
too narrow; so the tooling arguably understates every small-N interval it
prints, and it prints a lot of them. But the tooling's convention is what the
rest of the document was built on, and mixing the two inside one section means
two exponents in the same table are not comparable.

**What Session 1 did about it, rather than fix a file it does not own:** the
Lane C gate compares its own fit against the **published** interval, because
"agrees with §6.5" can only mean what §6.5 prints — and reports the comparison
against the tool-convention interval [1.996, 2.027] beside it, on every output,
labelled informational. Gating on the wider interval alone would be a lenient
test wearing a strict test's clothes; hiding the narrow one would be worse.

**What integration (§8) should decide:** one convention for the whole document,
applied to every fit in it, with the choice stated. If it is the t interval,
`ci/perf_profile.py::fit_cell` needs a t table and several published intervals
widen. If it is the normal interval, §6.5 evidence 4's interval narrows to
[1.996, 2.027] — which does not change any verdict in the section, since 2.012
and 1.063 stay disjoint either way.

---

## S1-2 — `backend/CMakeLists.txt` did not exist; it does now

**Found by:** Session 1.
**Files:** `backend/CMakeLists.txt` (assigned to S1 by §3), `backend/occt/CMakeLists.txt`
(assigned to nobody).
**Blocked:** no.

§3 grants Session 1 `backend/CMakeLists.txt`, but there was no such file — the
native layer has one CMake project per subdirectory. It has been created as a
two-line umbrella over `occt` and `bench`, which is the only reading under which
the grant means anything.

`backend/occt/CMakeLists.txt` was **not** touched. `backend/bench/CMakeLists.txt`
reaches the `occt_capi` target with `add_subdirectory(../occt)`, so the benchmark
links the same translation unit, with the same flags, that the app ships — and
Session 2 can change the shim without the bench needing to know.

`backend/bench/publish-bench.sh` is the CI delivery step. It lives under
`backend/bench/**` rather than in `.github/scripts/` so that it falls inside
Session 1's exclusive ownership without argument.

---

## S1-3 — `perf/findings/` was empty; the shared coordination files are seeded

**Found by:** Session 1.
**Files:** `perf/findings/CROSS-SESSION.md`, `perf/findings/CONFLICTS.md`.
**Blocked:** no.

§7 names both files but neither existed. Session 1 created them with their
append-only rule at the top. Nothing else is in them; the entries above are
Session 1's own.

---

## S1-4 — the "flat 25.5 ms fillet" is the candidate search, not the blend

**Found by:** Session 1, when the Lane C harness reproduced §6.3's numbers but
not §10.2's.
**For:** **Session 2** — this changes what your §6.3 brief sends you to look for.
**Files:** `PERFORMANCE_PROFILE.md` §6.3 / §10.2 / §16 (nobody edits it),
`OPTIMIZATION_PLAN.md` §5 Session 2 (nobody edits it).
**Blocked:** no. Session 1 measured both halves separately so the ambiguity
cannot repeat.

`OPTIMIZATION_PLAN.md` §5 tells Session 2:

> **Fillet and chamfer cost the same for 1, 4 or 12 edges** — 25.5 ms flat,
> k = 0.00, reproduced under both clocks and across two builds (§10.2). Flat
> cost against a swept axis means the work is not per-edge; find what the fixed
> cost is.

**There is no mysterious fixed cost to find. The blend is per-edge, and the
flat quantity is `allEdges` — the same enumeration that is already your main
target.** Three independent things say so.

**1. The profile's own §6.3 table** gives `filletEdges` alone as

| edges blended | 1 | 4 | 12 |
| --- | ---: | ---: | ---: |
| `filletEdges` | 10.1 ms | 20.8 ms | 46.7 ms |

which fits k = 0.62 — a 4.6× rise over a 12× range. That is not flat.

**2. §12.2 reproduces it across two runs** (10.17 / 20.76 / 47.07 in run 3,
10.10 / 20.76 / 46.66 in run 4 — "runs 3 and 4 agree to within 1 % on every
fillet quantity"). Whatever is flat, `filletEdges` is not.

**3. The appendix settles what the flat number is.** §10.2's row reads
`kernel.fillet.edges | 1:25.54 4:25.57 12:25.83 | 0.00`, and §16 lists the
same family with its columns labelled:

```
| kernel.chamfer.edges.1  | ui | 31.413 | ffi.occt.allEdges | 25.536 | 3 |
| kernel.chamfer.edges.4  | ui | 36.353 | ffi.occt.allEdges | 25.571 | 3 |
| kernel.chamfer.edges.12 | ui | 50.775 | ffi.occt.allEdges | 25.829 | 3 |
```

25.54 / 25.57 / 25.83 is the **`ffi.occt.allEdges` column** — the candidate
search. The scenario's own wall time is the `ui` column, 31.4 / 36.4 / 50.8,
and that grows. §10.2's row carries the scenario's name against the child
span's numbers, and §6.3's prose ("the wall time does not move because
candidate search dominates it") states the mechanism correctly while the
summary table at §4 item 6 compresses it into "Fillet / chamfer fixed cost —
25.5 ms regardless of edge count", which is where the plan's brief picked it up.

The flatness is real and it is trivial: enumerating a fixed solid costs the
same however many of its edges you afterwards blend.

**Lane C reproduces both halves independently, on a desktop, in minutes**
(ring(24, 40) × 10, the device's own fillet fixture, `--quick` run,
2026-08-19):

| quantity | device | Lane C (linux/x86_64) |
| --- | ---: | ---: |
| blend, 1 / 4 / 12 edges | 10.1 / 20.8 / 46.7 ms | 19.3 / 40.3 / 94.7 ms |
| implied exponent | **0.616** | **0.640** |
| candidate search | 49.3 ms | 95.9 ms |
| **search : blend at 1 edge** | **4.9×** (runs 3 and 4) | **4.97×** |
| radius r=1 → r=4 on the same solid | **65×** | **24×** |

Absolute milliseconds are not comparable and are not offered as such (§13.3);
the exponent and the ratio are, and they land on top of each other.

**What this means for Session 2's work:**

1. The `filletEdges` brief's premise is wrong, but its conclusion points the
   right way — §6.3 already says "the candidate search costs 4.9× the actual
   blending at one edge, which points back at your main finding". It does not
   point back at it; it **is** it. Fixing the enumeration fixes ~83 % of what a
   one-edge fillet costs, with nothing else to do.
2. The per-edge blend cost is OCCT's own `BRepFilletAPI` and there is no
   evidence here that the shim can improve it.
3. The **radius discontinuity is the real second finding** and it is not a
   clock artefact: Lane C reproduces a 24× step at r = 4.0 on a solid where
   r = 0.5, 1.0 and 2.0 are indistinguishable from each other. A 24× step on a
   desktop against 65× on the device is the same phenomenon at a different
   ratio of fixed to scaling cost. It is now iterable in minutes.
4. `occt_bench` reports `filletCandidateSearch`, `fillet.edges` (blend alone)
   and `fillet.scenario` (their sum, which is what the device span covers) as
   three separate operations, so no future reader has to work out which one a
   number means.

**What integration (§8) should decide:** whether §4 item 6 and §10.2's row
label are corrected. Session 1 did not touch either file.

---

## S1-5 — booleans bend upward past the device ladder's top rung

**Found by:** Session 1, from the Lane C ladder, which reaches four times the
operand size `ramp.boolean` did.
**For:** **Session 2** (kernel), and the next device capture.
**Files:** none. This is a measurement, not a defect.
**Blocked:** no.

§6.2 fits `ramp.boolean` at **k = 1.07, R² = 0.9974, CI [1.03, 1.12]** and
concludes "the CI excludes quadratic decisively and barely admits anything
above linear — about as favourable as boolean scaling gets". That ladder runs
12 → 144 profile points, i.e. **36 → 432 edges**.

Lane C runs 180 → 1440 edges on the same fixture pair (`ring(n, 40) × 10`
against `ring(n, 25) × 20`, exactly `ramp.kernel.boolean`'s operands) and the
local exponent **climbs across it**:

| edges | fuse (ms) | local exponent |
| ---: | ---: | ---: |
| 180 | 77.0 | — |
| 360 | 179.4 | 1.22 |
| 720 | 435.7 | 1.28 |
| 1440 | 1214.8 | **1.48** |

Whole-range fits: `fuse` **k = 1.322 [1.240, 1.405]**, R² = 0.9980;
`cut` **k = 1.368 [1.258, 1.478]**, R² = 0.9966. Neither interval overlaps
§6.2's [1.03, 1.12].

**This is not a contradiction of §6.2 — it is what lies past its last rung.**
The device ladder's top (432 edges) sits at the bottom of the bend, where the
local exponent here is about 1.25, and a whole-range fit over 36 → 432 edges
would flatten that toward 1.1. A rising local exponent inside one machine's own
data is a structural observation, which §13.3 permits; the absolute
milliseconds are not offered and are not comparable.

**Why it matters.** A rebuild performs one boolean per feature, and §6.2
already marks 144 ms "a perceptible stall". If the bend is real on device too,
a part whose bodies carry ~1400 edges pays something closer to a second per
boolean, per feature, on every rebuild — a cost that compounds with Session
5's per-occurrence finding (§8.2) in the same way §6.5 does.

**What would settle it:** extend `ramp.kernel.boolean`'s ladder past 144
profile points on the next device capture. It currently stops at
`const [12, 24, 36, 48, 72, 96, 144]` in `frontend/lib/perf_scenarios_ramp.dart`
— which is `perf*.dart`, a file §3 says nobody edits, so Session 1 has not
touched it. This is a request for the integration step (§8), not a change.

---

## S1-6 — fillet has a SECOND cost discontinuity, on corner angle

**Found by:** Session 1, chasing an anomaly in its own fillet ladder.
**For:** **Session 2** — this sits beside the radius discontinuity your §6.3
brief already names.
**Files:** none touched. `backend/occt/shim/**` is yours.
**Blocked:** no.

§6.3 gives you one fillet discontinuity: 10 ms at r = 1.0 against 658 ms at
r = 4.0 on the same solid, a 65× step (Lane C reproduces 24× on a desktop).
There is a second one, on a different axis, and it is not in the profile.

Lane C blends **one vertical corner edge** of a `ring(n, 40) × 10` prism at a
fixed 0.1 mm radius, and the cost is **not monotone in shape size**:

| n | edges | dihedral | ms |
| ---: | ---: | ---: | ---: |
| 60 | 180 | 174.00° | **45.8** |
| 120 | 360 | 177.00° | 14.5 |
| 240 | 720 | 178.50° | 29.4 |
| 480 | 1440 | 179.25° | 56.9 |

Reproduced across three runs. The shim's own report rules out the retry ladder:
`dropped = 0`, `scale = 1.000000` at every rung — nothing is skipped and no
tangency retry fires.

Two probes separate the candidates.

**A. The blend's size relative to the geometry does not matter.** Holding
n = 60 (dihedral and shape size both fixed) and sweeping the profile radius
over 16×, so that radius : facet moves from 0.096 to 0.006:

| profile radius | 10 | 20 | 40 | 80 | 160 |
| --- | ---: | ---: | ---: | ---: | ---: |
| radius : facet | 0.0955 | 0.0478 | 0.0239 | 0.0119 | 0.0060 |
| ms | 32.9 | 34.7 | 31.6 | 33.1 | 32.4 |

Flat to 5 %.

**B. `n` is what matters.** Holding radius : facet at 0.0239 and sweeping n:
**33.1 / 10.9 / 21.8 / 43.8 ms**. From n = 120 upward the cost doubles with the
shape exactly (k = 1.00, intercept ≈ 0). Extrapolating that law back to n = 60
predicts ≈ 5.4 ms; the measurement is 33.1 ms.

**So there is an excess of about 28 ms at a 174° corner that has vanished by
177°, at fixed shape size and fixed relative radius.**

**What is NOT established:** whether the driver is the dihedral angle itself or
something else that varies with `n` — the topology where the blended edge meets
the cap faces changes too, and this fixture cannot separate them. Two fixtures
would: a prism whose corner angles vary while its edge count does not, or a
blend on an edge with no vertex blending at its ends.

**Why it may matter to you.** §6.3's radius step is plausibly OCCT's own
behaviour and a legitimate "not fixable in the shim" result. This one is a
different shape of problem: a **sharper** corner costing several times a flatter
one is the opposite of what a user would guess, and real parts are full of 90°
corners, which are far sharper than anything this fixture reaches. Nothing here
says the 90° case is slow — the fixture never gets there — but it says the axis
exists and is worth one measurement before either discontinuity is written off.

Lane C makes both iterable in minutes. `occt_bench` reports `filletEx1` per
rung with the shim's `dropped`/`scale` beside it, and `fillet.radius` sweeps
r = 0.5 / 1 / 2 / 4 on the device's own fixture.
