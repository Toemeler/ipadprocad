# S15 — a holed profile should build too: the assembly, and the guard it needs

**Session:** S15 (round three, the second sweep session).
**Branch:** `claude/s15-holed-profile-sweep-cus40t`, cut from
`claude/perf-opt2` at `1b0675c`.
**Owns:** `backend/occt/shim/**`, `backend/bench/**`, `backend/occt/tests/**`,
this file.
**Governing rules:** `OPTIMIZATION_PLAN_2.md`, `perf/findings/README.md`,
`OPTIMIZATION_PLAN.md` §2 for the prediction form.
**Reads as given, does not re-derive:** `perf/findings/S14-sweep.md` §10 and
§12.

---

## 0. The gap this session exists for

S14 fixed the sweep for profiles **without** holes. A 1200-segment ring on a
16-span sampled arc went from failing after 742 249 ms to building valid in
3 559.2 ms, and the fitted exponent from ~3 to 1.150 (S14 §5.2).

A profile **with** a hole gets none of that, and the reason is one line of
`occt_sweep_profile_ex`:

```cpp
    const int effective_mode =
        (path_mode == OCCT_SWEEP_PATH_AUTO && nloops > 1)
            ? OCCT_SWEEP_PATH_POLY
            : path_mode;
```

A holed profile is forced back onto the v23 polyline spine, because
`finish_pipe` removes each hole with a `BRepAlgoAPI_Cut` and that boolean costs
21 653.6 ms between two smooth-spine solids against 66.0 ms for the two sweeps
that feed it (S14 §4.1). So the holed path still takes the mitered route and
still fails at exactly the size the owner's goal names.

**The bar for this session:** a 1200-segment profile with a hole, swept along an
arc, must build and must be valid.

### 0.1 What S14 settled, and is not re-tested here

1. **`MakePipeShell` cannot take a multi-wire section on OCCT 7.9.3.** Settled
   from source: `BRepFill_Section`'s constructor accepts a WIRE or a VERTEX and
   throws `"BRepFill_Section: bad shape type of section"` for anything else
   (S14 §12.1). Sweeping the annulus as one section is not available.
2. **The alternative — assemble instead of subtract — is prototyped and
   measured at 24 segments.** Two lateral shells plus two planar end caps
   whose outer boundary is the outer sweep's end section and whose inner
   boundary is the hole's, sewn and made solid. Same volume to ten significant
   figures, same face count, both valid, 5 730× faster on the smooth spine
   (S14 §12.2).
3. **It is NOT verified at 1200 segments.** S14 killed its prototype after
   25 minutes and labelled its own explanation — that the process was stuck in
   `vol()` / `BRepCheck_Analyzer` rather than in construction — an inference
   from where a timer sat, not a measurement (S14 §12.2, §14.3 item 3).

Item 3 is the first thing this session settles, because if **verification**
costs 25 minutes then the right design is a different one, not merely a slower
schedule.

---

## 1. Pre-registration, round 1 — where the 25 minutes goes

Nothing in the shipped path is changed by anything in this section. The
instrument is a separate host-only executable (`backend/bench/hole_probe.cpp`),
built from the same `occt_capi` translation unit the app links, and it times
the assembly's stages **separately** so that the question S14 could only infer
an answer to can be answered by measurement.

The stages it separates, on a 1200-segment r = 6 ring with an r = 3 hole over
the 16-span sampled arc, SMOOTH spine:

| stage | what it covers |
| --- | --- |
| `sweep` | the two `BRepOffsetAPI_MakePipeShell::Build()` calls |
| `caps` | the two planar cap faces, outer wire + inner wire |
| `sew` | `BRepBuilderAPI_Sewing` over the four pieces, and the solid |
| `unify` | `ShapeUpgrade_UnifySameDomain`, which `finish_pipe` already runs |
| `volume` | `BRepGProp::VolumeProperties` |
| `valid` | `BRepCheck_Analyzer::IsValid` |

`sweep + caps + sew` is CONSTRUCTION. `volume + valid` is VERIFICATION and is
**not in the shipped path at all** — `finish_pipe` never calls either. `unify`
is shipped and is counted with construction.

```
## Prediction P1 — construction at 1200 segments is seconds, not minutes
Target        : the assembly of a 1200-segment r=6 ring with an r=3 hole over
                the 16-span sampled arc, SMOOTH spine; stages sweep+caps+sew
                +unify only.
Baseline      : none exists — S14's prototype never reported one.
Predicted     : under 30 000 ms.
Derivation    : the finished solid has 1200 + 1200 + 2 = 2402 faces against
                the 24-segment prototype's 50, a factor of 48.0.
                - the two sweeps cost 30.1 ms at 24 segments (S14 §12.2) and
                  the sweep's fitted exponent in SEGMENTS is k = 1.150
                  (S14 §5.2), so 30.1 x 50^1.150 = 30.1 x 90.0 = 2 709 ms.
                  Cross-check: [37d] builds ONE unholed 1200-segment sweep,
                  and unifies, measures and validates it, in 3 559.2 ms total,
                  so ~1.35 s for one sweep is consistent.
                - caps+sew cost 3.7 ms at 24 segments. Sewing uses a
                  BRepBuilderAPI_CellFilter and should be near-linear in faces:
                  3.7 x 48 = 178 ms. Allowing it to be QUADRATIC instead gives
                  3.7 x 48^2 = 8 525 ms.
                - unify is shipped today and [37d] pays it at 1202 faces
                  inside its 3 559.2 ms; at 2402 faces, linearly, ~2x that
                  share.
                Ceiling: 2 709 + 8 525 + a few seconds of unify = ~15 s.
                Registered at 30 000 ms, i.e. double the ceiling.
Falsifiable by: construction above 30 000 ms. That would mean the assembly
                itself does not scale, the 24-segment table is misleading, and
                S14's inference is wrong in the direction that kills the
                design rather than merely delays it.

## Prediction P2 — verification is what cost 25 minutes, and one call does it
Target        : the same shape; stage `valid` alone, against the same stage on
                the UNHOLED 1200-segment sweep built in the same run.
Predicted     : the holed solid's BRepCheck_Analyzer costs at least 20x the
                unholed solid's, and is the single largest stage.
Mechanism     : BRepCheck_Face::IntersectWires
                (backend/occt/upstream/src/BRepCheck/BRepCheck_Face.cxx:240)
                runs its wire-pair loop as `while (Index < Nbwire)`. An
                unholed sweep's end cap has ONE wire, so that body never
                executes and the check is free. A holed sweep's cap has TWO,
                so each cap runs Intersect(outer, inner) — a full
                edge x edge double loop.
Derivation    : 1200 x 1200 = 1 440 000 edge pairs per cap, 2 880 000 over the
                two caps. Each iteration calls
                BRep_Tool::CurveOnSurface(edg2, F, first2, last2) BEFORE the
                Bnd_Box2d rejection, and the cap is planar with no stored
                pcurve on its inner wire, so every one of those calls goes
                through BRep_Tool::CurveOnPlane and CONSTRUCTS a projected
                Geom2d curve. At 1 us each that is 2.9 s; at 100 us each it is
                288 s; at 500 us each it is 1 440 s, which is the 25 minutes
                S14 saw. The unholed control pays ZERO of this.
                Note the two rings are radially separated by 3 units and every
                edge box is a sub-unit segment, so essentially NO pair reaches
                Geom2dInt_GInter: the cost is the per-pair setup, 2.88e6 times.
Falsifiable by: a ratio under 20x, or any other single stage exceeding
                `valid`. Either moves the 25 minutes somewhere I have not
                looked and makes P3 the interesting result instead.

## Prediction P3 — the split, stated as a share
Target        : the same measurement.
Predicted     : verification (volume + valid) is more than 50 % of the whole
                holed 1200-segment measurement, and construction is less than
                10 % of it.
Derivation    : P1 caps construction at ~15 s expected; P2 puts `valid` alone
                in the hundreds of seconds. If both hold, construction's share
                is 15 / (15 + several hundred) < 10 %.
Falsifiable by: construction above 10 %. This is the prediction that decides
                whether the design is right, as distinct from P1/P2 which
                decide where the time goes: if CONSTRUCTION is the expensive
                half, the assembly route is not obviously better than the
                boolean at scale and this session should say so and stop.

## Prediction P4 — the shipped v26 route, at the same size, does not finish
Target        : occt_sweep_profile_ex on the same 1200-segment holed profile
                and the same 16-span arc, exactly as shipped (AUTO), capped at
                900 000 ms.
Predicted     : no solid — either a null return or the cap expiring.
Derivation    : nloops > 1 forces OCCT_SWEEP_PATH_POLY, so the outer wire is
                swept along v23's mitered polyline spine, and S14 measured
                that exact configuration WITHOUT a hole as FAILED after
                742 249 ms (S14 §5.2). Adding a hole adds a second sweep of
                the same kind and a boolean between them; it cannot become
                cheaper.
Falsifiable by: a solid coming back. That would mean the holed path is not
                actually broken at 1200 and the premise of this session is
                wrong.

## Prediction P0 — the instrument reproduces S14's 24-segment table
Target        : the same probe at 24 segments, 16 spans.
Predicted     : polyline spine 5 031.442237 and 770 faces; smooth spine
                5 031.420889 and 50 faces; both valid; the assembly's own
                volume equal to the boolean's to 10 significant figures.
Derivation    : these are S14 §12.2's measured numbers. This arm exists so
                that a disagreement is attributed to my instrument rather
                than to the kernel.
Falsifiable by: any disagreement, which invalidates every number below it.
```
