---
id: process/folder/document-name
title: Human readable title
type: recipe
process: laser
triggers: [english term, another english term, deutscher Begriff]
depends_on: []
confidence: medium
updated: 2026-09-22
---

# Human readable title

One or two sentences: what this document is for, in plain language. If the
reader only gets this far, they should still know whether to keep reading.

## When this applies

- The situation this covers.
- The situation it does **not** cover, with a pointer to the document that does.

## Good starting values

| What | Start with | Works between | Why |
|---|---|---|---|
| Example parameter | 1.2 mm | 0.8–2.5 mm | below this it does not fill; above it warps |

Every row needs the *why*. A row without one will be ignored the first time
the model has an idea of its own.

## How to build it

1. First operation.
2. Second operation.
3. The one that must come last, and what happens if it does not.

## When to do it differently

- **Situation X** → do Y instead, because Z.
- **Situation that makes this document irrelevant** → see `other/document`.

## Images

![short alt text](img/example-good.svg)
*What to look at in this picture, and why it is the good one.*

![short alt text](img/example-bad.svg)
*What went wrong here — name the visible symptom, not the abstract rule.*

## Source & date

- Where the numbers came from (link or "measured on <machine>, <date>").
- `confidence:` justification — is this physics, common practice, or a guess
  that needs measuring?
