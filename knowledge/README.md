# `knowledge/` — the manufacturing knowledge base

This folder is what the in-app AI assistant reads **while it is modelling**, so
that what it builds can actually be made. Two processes are covered in depth:

| Folder | Covers | Read it |
|---|---|---|
| [`design/`](design/) | how an object should look, sit, be held and be understood | **on every part** |
| [`laser/`](laser/) | CO₂ laser cutting and engraving, **wood-first** | when cutting from sheet |
| [`fdm/`](fdm/) | FDM / FFF filament 3D printing | when printing solids |

### The standing instruction

The two process folders answer *can this be made?* The design folder answers
*should it look like this?* — and that question applies to every part, not
only to the ones somebody calls a design job.

So `design/` is loaded by triggers like everything else, but it carries a
standing instruction the other two do not:

> **Every part is a design decision as well as a manufacturing one.** Before
> drawing, open [`design/start-here`](design/00-start-here.md) and choose the
> object's systems — its radius set, its spacing scale, its proportion family.
> Before finishing, run [`design-critique`](design/05-process/design-critique.md).
> A bracket nobody will see still has proportions, a stance and a level of
> finish; those get chosen whether or not anyone decides them.

Two exceptions worth stating out loud rather than assuming: a jig or fixture
needs the ergonomics and affordance documents and little else, and a part
sealed inside an assembly needs consistency but not composition. Say which
applies rather than skipping quietly.

The laser half is written for **wood** — plywood, solid hardwood, bamboo and
MDF. Acrylic, card and leather each keep a document because they turn up, but
the defaults, the worked examples and the numbers in every other file assume
wood. That is a deliberate narrowing: wood takes a press fit and it takes a
screw, which is what most laser-cut objects actually need.

It is **not** a manual for the user, and it is not advice the assistant reads
out loud. It is the reference it opens before it draws, the way a workshop
hand reaches for the shelf above the bench.

---

## The one design decision this folder is built on

Nothing here is enforced. There is no validator that rejects the assistant's
geometry, no clamp on a parameter, no gate it has to pass. That is deliberate:
the assistant stays free to model, and the knowledge base's only job is to
**be in front of it at the moment it matters**.

The cost of that decision is that every document has to earn its compliance.
A bare number with no reasoning gets ignored the first time the model has an
idea of its own. So every rule in here is written in the same shape:

> **a starting value, a range around it, and half a sentence saying what goes
> wrong outside the range.**

A model that understands *why* 0.6× wall thickness matters will apply it to a
shape nobody wrote a rule for. A model told only "rib = 0.6× wall" will not.

The single exception is [`laser/02-materials/never-cut-these.md`](laser/02-materials/never-cut-these.md).
Cutting PVC fills a room with chlorine gas and corrodes the machine from the
inside. That document is written as a hard stop, and it says so.

---

## How a document reaches the assistant

Three layers, cheapest first:

1. **The menu.** [`index.md`](index.md) (for humans) and `index.json` (for the
   app) carry one line per document: its id, its title, and the words that
   should pull it off the shelf. Only this menu needs to sit in the
   assistant's context permanently — it is a few hundred tokens, not a few
   hundred kilobytes.

2. **Trigger matching.** The assistant states a short plan before it builds
   ("base plate, four screw bosses, two ribs, cable cutout"). The app matches
   the words in that plan against the `triggers:` list of every document and
   loads what hits. Triggers are listed in English *and* German, because the
   app is natively German and the user will type `Fingerzinken`, not
   `finger joint`.

3. **Dependencies.** A document may declare `depends_on:`. Loading
   `laser/joints/finger-joint` therefore also loads
   `laser/basics/kerf-and-tolerance`, because a finger joint without kerf
   compensation is a finger joint that does not close. The assistant never has
   to know that connection — the index carries it.

The assistant can also browse: `list_topics()` returns the menu,
`open_topic(id)` returns one document plus its images. Both paths are
supported and both use the same index.

---

## What a document looks like

Every file has YAML frontmatter and then six fixed sections. `TEMPLATE.md` is
the copy-me skeleton; `tools/kb/validate_kb.py` checks that nothing drifts.

```yaml
---
id: laser/joints/finger-joint          # stable; the app addresses documents by this
title: Finger joint (box joint)
type: recipe                           # see the table below
process: laser                         # laser | fdm | shared
triggers: [finger joint, box joint, Fingerzinken, Kiste, box]
depends_on: [laser/basics/kerf-and-tolerance]
confidence: high                       # high | medium | starting-point
updated: 2026-09-22
---
```

| `type:` | The document answers | Example |
|---|---|---|
| `basics` | why the process behaves the way it does | `kerf-and-tolerance` |
| `material` | what this stuff does, and what that means for geometry | `acrylic` |
| `rules` | the numbers, as tables | `clearance-table` |
| `recipe` | how to build this feature, in order | `finger-joint` |
| `decision` | which option to pick, and when | `choosing-a-material` |
| `failures` | symptom → cause → fix | `failure-catalogue` |
| `checklist` | what to verify before handing the file over | `before-you-export` |
| `example` | a complete part, start to finish | `finger-joint-box` |

The six sections, in this order:

1. **When this applies** — and, just as important, when it does not.
2. **Good starting values** — a table: value, working range, why.
3. **How to build it** — the operation order that works.
4. **When to do it differently** — the escape hatches. Without this section a
   model either follows the numbers blindly or discards the document whole.
5. **Images** — with captions that say what to look at.
6. **Source & date** — where the number came from, and when it was last true.

---

## Numbers: baseline vs. measured

Every number in here is a **baseline from published sources**, not a
measurement from your machine. Kerf in particular is a property of the
machine, the lens, the power, the speed and the sheet — not of the material
alone. Documents mark this explicitly:

- `confidence: high` — physics or near-universal practice (45° overhangs,
  Z-axis weakness, PVC).
- `confidence: medium` — widely agreed numbers that vary by setup (clearances,
  insert boss sizes).
- `confidence: starting-point` — a first guess that **must** be measured
  (kerf values, press-fit interference).

Two documents exist purely to replace baselines with measurements:
[`laser/01-basics/kerf-test-comb.md`](laser/01-basics/kerf-test-comb.md) and
[`fdm/01-basics/tolerance-test-part.md`](fdm/01-basics/tolerance-test-part.md).
When a user runs one, their measured value belongs in
`machine-assumptions.md` for that process, and it overrides everything else.

---

## Images

Two kinds live side by side in each `img/` folder:

- **`*.svg` — diagrams drawn for this repository.** Schematic, one point per
  picture, no licensing question, they diff in git and scale to any size.
- **`*.jpg` / `*.png` — photographs.** Real parts, real failures. Photos beat
  diagrams for "what does a sink mark / charred edge / delamination actually
  look like", which is exactly what a model cannot infer from prose.

[`PHOTOS.md`](PHOTOS.md) lists every photograph the documents would like to
have, with its target filename and what must be visible in it. A document
never breaks for a missing photo — the entry is simply not referenced until
the file lands.

Diagram conventions are in [`img-style.md`](img-style.md). Follow them, or the
set stops reading as one system.

---

## Adding or changing a document

```bash
cp knowledge/TEMPLATE.md knowledge/fdm/05-features/my-feature.md
$EDITOR knowledge/fdm/05-features/my-feature.md
python3 tools/kb/build_index.py          # regenerates index.json and index.md
python3 tools/kb/validate_kb.py          # frontmatter, sections, dead links
```

CI runs both on every push that touches `knowledge/` or `tools/kb/`
(`.github/workflows/knowledge-base.yml`). A stale index is a failing build,
because an index that does not match the folder is worse than no index: the
assistant asks for a document that is not there and silently proceeds without
it.

---

## The maintenance loop

This knowledge base is meant to grow from mistakes, not from an attempt to
write everything down in advance.

When the assistant produces something wrong, exactly one of three things is
true, and each has a different fix:

| What happened | Fix |
|---|---|
| It never opened the right document | the `triggers:` list is too narrow |
| It opened it and ignored the rule | the rule has no *why*, or no range |
| It opened it and the rule was absent | write the rule, and add the failure to the catalogue |

Do that thirty times and the assistant is better than its own intuition — and
unlike the intuition, you can read why it decided what it decided.
