# S11 brief — the sweep, and the sizes the suite never measured

**Written by the integrator from a user session on build `b2de0c2`** — i.e.
*after* round one's optimisations. The evidence is a `prototype_log.txt`,
`performance_logs.txt` and `Part1.ptp` the user captured while actually working;
none of it is in the repository, so the numbers are transcribed here.

## 1. What happened

```
10:05:11  user taps the curve to sweep along
10:06:55  PREVIEW sweep completes      tris=91646     (~103 s)
10:06:55  reality: setScene #20: 0 solid(s)           <- preview result discarded
10:08:49  Sweep1 completes             tris=91646     (~103 s)
10:10:32  Sweep1 completes AGAIN       tris=91646     (~103 s)
10:10:33  mesh Sweep1: tris=91646 faces=20290 verts=132226
```

**Five minutes twenty-three seconds from tap to visible result.** From the
session's own perf table:

| span | n | mean | worst | total | share of session |
| --- | ---: | ---: | ---: | ---: | ---: |
| `kernel.feature.sweep` | 3 | **103 584.7 ms** | 103 761.7 ms | 310.75 s | **53.0 %** |
| `ffi.occt.sweepProfile` | 35 | 8 853.6 ms | **102 244.4 ms** | 309.88 s | 52.8 % |

## 2. Three distinct faults, and they are not the same size

**(a) The same sweep runs three times, identically.** All three log
`tris=91646` — byte-identical output. Two are pure waste: **207 s of the 310 s.**

**(b) The preview costs the same as the committed operation, then is thrown
away.** The line immediately after the preview completes is
`setScene #20: 0 solid(s)`. 103 seconds of full-fidelity work, nothing shown.
A preview that costs what the real thing costs is not a preview.

**(c) Loop detection manufactures phantoms.** `loops: "Sketch1": 116 loop(s)`
with **6 non-zero areas** — `[1230.71, 322.49, 338.66, 142.55, 230.93, 123.79]`
— and **110 loops of exactly 0.00 area.**

## 3. The profile really is complex — this is the part that matters

Read from `Part1.ptp` (`PROTOv1\n` + u32 header length + JSON index + blobs;
`sketches/Sketch1.dxf` is the swept profile):

| entity | count |
| --- | ---: |
| `LINE` | 12 |
| `ARC` | 6 |
| `LWPOLYLINE` | 1 — **1200 vertices, closed** (group 90 = 1200, flag 70 = 129) |
| **effective segments** | **~1218** |

So **six real loops is the correct answer** for this geometry, and the 110
zero-area loops are phantoms. But note the arithmetic before concluding the
phantoms are the cost:

&nbsp;&nbsp;&nbsp;&nbsp;20 290 faces ÷ 1218 segments ≈ **16.7 sweep steps**

**The face count is dominated by the legitimate 1200-vertex polyline, not by the
phantoms.** Remove the waste and the phantoms and a single honest sweep of this
profile still costs on the order of 100 s. **That is the optimisation target.**

## 4. Why no tier caught it

`PERFORMANCE_PROFILE.md` records `ffi.occt.sweepProfile` at **81.9 ms mean,
392 ms worst** and ranks it #8, "PROBLEM (absolute)". The real profile reached
**102 244 ms** — a factor of **1250×** beyond anything the suite has measured.

The stress tier climbs `allEdges` to 5 760 edges and `analyze` to 1 024
entities. **No tier anywhere sweeps a profile of more than a few dozen
segments.** The ladders found the walls they were pointed at; they were pointed
at the wrong sizes. That is the generalisable finding, and it is worth more than
the sweep fix alone.

## 5. What the user has asked for, in their words

> "The goal of the optimization is that even such extremely complex things are
> handled fast and with ease so at the end extremely complex parts are
> possible."

So the target is **not** to reject or simplify complex profiles. It is to make
1200-segment sweeps, hundred-loop sketches and 90 000-triangle results fast.

## 6. Two things not yet established, cheap to check first

- **Which sketch is the sweep path**, and what sets the ~17 steps. If the step
  count is derived from path curvature or a fixed tolerance, it is a parameter
  with a large multiplier attached and worth understanding before anything else.
- **Where the 110 phantoms come from.** The polyline is the only entity that
  could produce them — duplicate or collinear vertices among 1200 are the
  obvious candidate. Determine it rather than assume it.
