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
