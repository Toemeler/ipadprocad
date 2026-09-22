---
id: design/process/critique
title: Design critique — reviewing an object
type: checklist
process: design
triggers: [critique, kritik, review, überprüfen, bewerten, feedback, is this good, ist das gut, whats wrong, was stimmt nicht, assess, beurteilen, check the design, design prüfen, before finishing, fertig]
depends_on: [design/start-here, design/principles/what-good-looks-like]
confidence: medium
updated: 2026-09-22
---

# Design critique — reviewing an object

The pass before an object is called finished. It takes five minutes and it is
the point at which "it looks wrong" becomes a list of specific, fixable
things.

The discipline that makes a critique useful rather than an opinion exchange:
**state the goals first, then work the checklist, then rank the findings.**
Feedback that is not measured against a stated intention is just taste.

## When this applies

Before declaring any object finished, before showing it to anybody, and
whenever somebody says it looks wrong and cannot say why.

## Good starting values

### Step 0 — restate the intention

Read the brief out loud, or the one sentence that stands in for it. Every
finding below is *against that intention*, not against a general standard.
→ [`design-brief`](design-brief.md)

### The checklist

**Systems**
- [ ] Count the distinct radii. More than four?
- [ ] Count the distinct gap sizes. More than five?
- [ ] Does every dimension come from the spacing scale?
- [ ] Do the proportions come from two ratios, not six?

**Composition**
- [ ] Can you name the primary element in one word?
- [ ] Is it at least twice the weight of the next thing?
- [ ] Is everything grouped, with gaps doing the grouping?
- [ ] Does every feature align to something?
- [ ] Is anything 0.5–4 mm off an alignment — the dead zone?
- [ ] Symmetrical or clearly asymmetrical, not nearly-symmetrical?

**People**
- [ ] Is it clear how it is held, without being told?
- [ ] Does the form say what to do, or does it need a label?
- [ ] Can it be assembled or used the wrong way round? Can a constraint stop that?
- [ ] Do the controls meet the size and gap minimums?
- [ ] Does every mark meet its contrast minimum?

**Craft**
- [ ] Is every edge a hand meets chamfered or radiused?
- [ ] Is the bottom edge chamfered?
- [ ] Is the underside finished?
- [ ] Are the process marks deliberately placed?
- [ ] Are fasteners minimal, recessed and aligned?

**Restraint**
- [ ] What are the three things that could be removed?
- [ ] Is there any decoration doing the work of form?
- [ ] Two materials? Two colours plus a neutral?

**The two tests**
- [ ] **Thumbnail test** — at 10 % size, is the primary element still
      identifiable, and is the silhouette good?
- [ ] **Photograph test** — photograph it. A photograph is unforgiving in a
      way a render is not, and it is how everyone else will first see it.

### Ranking the findings

Not all findings are equal, and a list of twenty is not actionable.

| Rank | Kind | Act |
|---|---|---|
| **1** | It does not do its job, or it excludes users | fix now |
| **2** | It contradicts its own systems — inconsistent radii, gaps, alignment | fix now; these are cheap |
| **3** | It is over-featured | subtract |
| **4** | Taste — you would have done it differently | note, do not act |

Rank 4 is the one that wastes the most time in a review. Say it once, mark it
as taste, and move on.

### If you are critiquing somebody else's work

| Do | Do not |
|---|---|
| Ask what the intention was, first | assume the intention |
| Describe what you observe, then why it matters | prescribe a solution immediately |
| Separate "this breaks its own rule" from "I would do it differently" | present taste as a defect |
| Rank the findings | deliver twenty equal items |
| Say what works | list only faults — the author then cannot tell what to protect |

## How to build it

1. Restate the intention.
2. Work the checklist in order — systems, composition, people, craft,
   restraint.
3. Do the thumbnail and photograph tests.
4. Rank every finding 1–4.
5. Fix ranks 1 and 2. Consider rank 3. Note rank 4 and leave it.
6. Re-run the two tests after fixing.

## When to do it differently

- **A jig** → the people and craft sections only, and only the edges row of
  craft.
- **A deadline** → rank 1 and 2 only. Those are also the cheapest.
- **An object in a family** → add one check: does it look like its siblings?
  Consistency across a family outranks perfection within one object.
- **Somebody else's finished product** → the checklist still works, and the
  findings are for your learning rather than for them.

## Images

None — this document is a checklist.

## Source & date

- Critique structure — state goals first, request specific feedback, keep it
  constructive: [NN/g — design critiques](https://www.nngroup.com/articles/design-critiques/),
  [UX Tigers — how to run a UX design critique](https://www.uxtigers.com/post/design-crit),
  [Designlab — a 10-point design critique checklist](https://designlab.com/blog/design-critique-checklist-for-ux-designers).
- The checklist items are drawn from the documents in this folder.
- `confidence: medium`.
