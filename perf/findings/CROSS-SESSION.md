# Cross-session notes — append only

Per `OPTIMIZATION_PLAN.md` §7: this file is for things you need that live in
another session's files, and for defects you find in another session's area.
**Append; never edit an existing entry.** A silent fix in someone else's file is
indistinguishable from a merge accident and will be reverted.

Format: `<session>-<n>`, what, where, what you would change, and whether you are
blocked on it.

---

## S2-1 — Lane C should bench `occt_shape_edges_info` (shim v21), or it cannot adjudicate the change it exists to adjudicate

**Raised by:** Session 2 (OCCT shim).
**Files:** `backend/bench/bench_occt.cpp` — Session 1's, not touched.
**Blocked:** no. S2's work is complete without it; this only decides whether
Lane C can say anything before the device run.

Session 2 has added a bulk entry point:

```c
int occt_shape_edges_info(const occt_shape *shape, double *out12n, int cap);
```

It writes 12 doubles per edge, records in edge-index order, `cap` in RECORDS,
returns the number written or −1. `occt_shape_edge_count` sizes the buffer.

Lane C currently benches `occt_shape_edge_info` two ways — one call against a
growing shape, and the full enumeration — which is exactly right, because those
two are what §6.5 evidence 2 and evidence 4 measure. The bulk path is the
change that is supposed to move the second of them, and Lane C cannot see it,
because it was written before the symbol existed.

**What would help, in priority order:**

1. **A third op on the same ladder**: the full enumeration through one
   `occt_shape_edges_info` call, at the same 120 / 240 / 480 profile points,
   published beside the per-edge enumeration. Two fitted exponents on identical
   solids is the isolation §6.5 evidence 4 built, and it is what separates
   Session 2's H1 from its H2 (`perf/findings/S2-shim.md` §3.1) **without a
   device**. That is the single most valuable number Lane C could produce for
   this session.
2. **Peak RSS for the bulk call.** It allocates `12 × n` doubles in one block
   where the old path allocated 12 at a time: 138 KB at 1440 edges, 553 KB at
   5760. Expected to be invisible against the 3.9 GB of headroom §6.5 records,
   but it is the one resource the change makes *worse*, so it should be
   measured rather than asserted.
3. **A guard on the shim version**, so an old binary skips the op instead of
   failing to link: `occt_shim_version() >= 21`.

The calibration pin does not change: the per-edge ops are untouched by Session
2 on purpose (they are its control, `S2-shim.md` P3), so Lane C's agreement
with §6.5's k = 0.985 and k = 2.012 must still hold after this change. **If the
per-edge exponents move, that is a Session 2 defect and Lane C is where it
would show first.** Please report it rather than working around it.

## S2-2 — the fillet fixed cost cannot be decomposed without a bench, and Lane C already has the fixtures

**Raised by:** Session 2 (OCCT shim).
**Files:** `backend/bench/bench_occt.cpp` — Session 1's, not touched.
**Blocked:** no. Session 2 has recorded the finding as closed; this would turn
a source-level decomposition into a measured one.

§6.3 / §10.2 measure `kernel.fillet.edges` at k = 0.00 — 25.5 ms whether one
edge is filleted or twelve. Session 2 read the source and found six whole-shape
operations per call, none of them per-edge (`S2-shim.md` §5.1). Three of the
six are the catastrophe guard — `solid_volume(base)`, `solid_volume(out)`,
`BRepCheck_Analyzer(out).IsValid()` — and Session 2 did **not** touch them,
because removing them would let corrupt solids through, which is a behaviour
change and out of scope for this whole branch.

Whether they are worth a cheaper guard is a real question, and it turns on one
number nobody has: **what fraction of the flat 25.5 ms is the guard rather than
`BRepFilletAPI_MakeFillet::Build()`?** Both halves are separately benchable
with entry points that already exist and that Lane C already links:

- `occt_shape_volume(s)` — one of the two volume integrations
- `occt_shape_valid(s)` — the analyzer pass
- `occt_fillet_edges_ex(...)` — the whole thing, which Lane C already benches

`2 × volume + valid` against the whole call, on the fillet ladder's own base
solid, bounds the guard from below and settles it. No new fixture is needed.

If it comes out small — say under 15 % — the question is closed for good and
should be written into the profile as closed. If it comes out large, that is a
finding for integration (§8) to route, not something to act on mid-flight.
