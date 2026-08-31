# `ci/bugfix` — the bug-report pipeline

Fixes a `bug-report` issue end to end: claim it, read the diagnostic bundle,
find the code, write the patch and a test that pins it, prove it with
`flutter analyze` and the full suite, commit, push to `main`, close the issue,
log it. The language model is called between **one and four times**. Everything
else is deterministic.

## Why this replaced the agent session

Three OpenHands sessions were exported and measured turn by turn. Same model
(DeepSeek V4 Pro), same repo, one issue each:

| | issue | model calls | median context | prompt tokens | condensations | cost |
|---|---|---:|---:|---:|---:|---:|
| S1 | #5 dropdown colours | 212 | 52,816 | 11.17M | 9 | **$1.4925** |
| S2 | #8 browser icon contrast | 193 | 59,199 | 11.47M | 8 | **$1.6040** |
| S3 | #6 triad position | 387 | 58,022 | 22.42M | 17 | **$3.1157** |

S1 shipped a 16-line change to `ribbon.dart` and an 85-line test. It burned
11.17M prompt tokens doing it, because a ~53k-token conversation was replayed
212 times. **Cost is linear in turn count**, and the turn count was roughly ten
times what the work needed.

Classifying all 796 actions across the three runs:

| category | S1 | S2 | S3 | what happened to it |
|---|---:|---:|---:|---|
| code read + search (`sed`/`grep`) | 88 | 92 | 227 | → `rank.py`, free |
| token/auth discovery | 32 | 15 | 23 | → gone; `GITHUB_TOKEN` is correct in Actions |
| screenshot pixel forensics | 10 | 5 | 39 | → banned; the 3D body is never in the image |
| Flutter install | 9 | 9 | 5 | → `subosito/flutter-action`, cached |
| `unzip` shim | 7 | 13 | 14 | → present on the runner |
| re-reading protocol/notes | 10 | 9 | 17 | → in the cached prefix, read once |
| `sleep` polling | 9 | 2 | 0 | → foreground, once |

Two findings drove the redesign:

**Condensation was ~26 % of every run.** DeepSeek's cache only hits on a
byte-for-byte identical prefix from token 0. The condenser rewrote the middle
of the conversation every 4–6 minutes, invalidating all of it. Every large
cache-miss spike in all three sessions — 9 of 9 in S1, 17 of 17 in S3 — lands
within 90 seconds of a condensation. It also caused the amnesia:
`MAINTAINER_PROTOCOL.md` was re-read five times in one session.

**An injected skill was wrong.** 11,204 tokens of `github` and
`openhands-automation` skills were pasted into every context, telling the agent
the token was `GITHUB_TOKEN` (it was `github_token`), to always open a PR (the
protocol forbids PRs), and never to push to `main` (the protocol requires it).

## What it costs now

Rates fitted to the three sessions' own cost and token counters, and validated
against S1's first call to within 0.1 %:

| token class | $/1M |
|---|---:|
| input, cache **miss** | 1.3184 |
| input, cache **hit** | 0.0441 |
| output (reasoning included) | 3.9583 |

A run's arithmetic. The token counts are measured — `pack.build()` against
issue #5's real bundle, not an estimate:

| | tokens | $/1M | cost |
|---|---:|---:|---:|
| stable prefix — house rules, repo map, bundle guide (cache hit from run 2) | 1,974 | 0.0441 | 0.00009 |
| issue pack — report, bundle, 6 sliced files | 13,988 | 1.3184 | 0.01844 |
| output — patch + test, `reasoning_effort: medium` | ~2,400 | 3.9583 | 0.00950 |
| **one call, happy path** | | | **$0.0280** |
| expected with escalation (≈40 % need a second round) | | | **~$0.036** |

The pack grew from 9.2k tokens to 14k deliberately. Of the pipeline defects
found in production, nine of ten were the pack withholding something the model
needed — an import, a declaration, the failing SEARCH, the two lines that hold
the colour. A thousand extra lines of slice is about a cent; the round it
prevents is a nickel and twenty minutes.

Against S1 that is **53×**. Against S3, **111×**. Plan against ~1/50 rather
than the best case: hard bugs escalate, and an escalation round is ~$0.015.

The pipeline prints its own cost per run, so a regression shows up in the
workflow log rather than on next month's invoice.

## Files

| | |
|---|---|
| `rank.py` | BM25 retrieval over Dart + Swift. German ARB bridge, recency boost. Replaces the `grep`/`sed` turns. |
| `pack.py` | Bundle + issue + ranked slices → one context pack, split into cacheable prefix and per-issue body. |
| `model.py` | The DeepSeek call. Fixed message order so the prefix stays cacheable. |
| `edits.py` | Search/replace block format, parsing and all-or-nothing application. Enforces forbidden paths. |
| `verify.py` | `analyze`, `test`, and the test-first gate. |
| `run.py` | The loop: ask → gate → verify → ship, or escalate, or block. |
| `test_*.py` | 173 tests. Run by the workflow *before* the model is called. |

## Setup

One secret and one optional variable on the repository:

- `DEEPSEEK_API_KEY` — **required**. Settings → Secrets → Actions.
- `DEEPSEEK_MODEL` — optional repo *variable*, defaults to `deepseek-v4-pro`.
  Set it if your account exposes the model under a different id; the old
  automation reached it through LiteLLM as `deepseek/deepseek-v4-pro`.

Nothing else. `GITHUB_TOKEN` is provided by Actions.

The OpenHands automation stays on as the fallback for when this workflow is off
or an issue lands on `openhands-blocked`. Its importable config is
`bugreports/openhands-automation.json`, and there is nothing else to set: the
generated `main.py` that starts an automation builds its own agent, so the
condenser and the injected skills do not come from user settings at all.
`bugreports/openhands-settings.md` shows the evidence and what carries the load
instead — the prompt, `.openhands/`, and the protocol.

## Running it

```bash
ci/bugfix/run.py --issue 12              # the real thing
ci/bugfix/run.py --issue 12 --dry-run    # pack + model, no writes, no push
ci/bugfix/pack.py 12                     # just look at what the model gets
ci/bugfix/rank.py "the floor is dark"    # just the ranking
python3 -m unittest discover -s ci/bugfix -p 'test_*.py'
```

`workflow_dispatch` takes an issue number, for re-running a blocked one after a
fix to the pipeline. It passes `--force`, because a blocked issue no longer
carries the `bug-report` label that `gh.claim` swaps on — without it every
manual re-run reported "already claimed by another run" and exited 0. The
race is still closed: under `--force` the live-run signal is
`openhands-working`.

## The test-first gate

`verify.gate()` applies the model's **test alone**, requires it to **fail**,
then applies the fix and requires it to **pass**.

The old protocol said "a fix with no test is not finished" but never said the
test had to fail without the fix, and nothing checked — so a test asserting
behaviour the code already had would pass review and pin nothing. Two extra
`flutter test` invocations against one file close that hole for free. This is
the one place where the new pipeline is *stricter* than what it replaced, not
merely cheaper.

## The post-push check

`run.py` verifies on a Linux runner. That is most of the truth and it is what
keeps a bad fix off `main`, but it is not all of it: Swift cannot be compiled
there, the simulator test and the IPA build run on macOS, and even the fast
Dart job runs without the native OCCT library. A fix can go green, land, and
turn `Core + C-API Build (iOS)` red minutes later with the issue already closed.

`.github/workflows/bugfix-verify.yml` fires on that build completing and runs
`postpush.py`, which reopens the issue, labels it `openhands-blocked`, and
names the failing job and step. It first checks whether the same workflow was
already red on `main` before the commit and says so either way — reporting a
pre-existing failure as "your fix broke the build" sends a human to read an
innocent diff.

It deliberately does NOT re-run the fixer. Handing a red build back to the
model that produced it would put a push-to-`main` loop in motion, which is the
one thing this system is careful never to do.

## Every run ends somewhere actionable

`claim()` takes `bug-report` off the issue and puts `openhands-working` on.
Every planned ending puts the issue back into a state something can act on —
closed, or `openhands-blocked` with the reason. An unplanned one did not: an
API 500 or an evicted runner left `openhands-working` standing with no run
behind it, the relay files each report only once so no second event is coming,
and `--force` refuses precisely when that label is present. `run.guarded()`
closes it: any unhandled exception blocks the issue with the traceback, so the
next step is always a re-run rather than an archaeology session.

## Honest limits

- **Retrieval finds the neighbourhood, not always the whole fix.**
  `test_rank.py::test_known_misses` records this: for issue #8 the fix also
  touched `theme.dart`, which the ranker misses from the title; for #7 it also
  touched `part_model.dart`. That is why the model can answer with `expand`
  instead of a patch — one more slice costs ~$0.004, against $1.49 for the
  search it replaces. If recall@5 ever drops below ~85 %, widen
  `pack.FILES_IN_PACK`.
- **Cross-cutting Dart↔Swift fixes are the common hard case** (#7 and #8 both
  were). Swift is in the corpus and it cannot be compiled on Linux — CI's
  macOS build remains the source of truth for it, exactly as
  `AUTOMATION_NOTES.md` has said since #2. Two things about it ARE checked
  here, and between them they cover how these actually break:
  `verify.swift_contract()` matches every Dart `invokeMethod` the diff adds
  against the `case "…"` and `args["…"]` on the Swift side — a name or a key
  spelled differently compiles on both sides and is a silent no-op that no
  test in this repo would catch — and `verify.swift_braces()` counts brackets,
  so a search/replace that drops one fails in milliseconds instead of twenty
  minutes later on macOS. A shipped fix that touched Swift says so on the
  issue rather than closing as if it had been built.
- **Prefix drift is silent.** A timestamp or an issue number accidentally
  placed ahead of the pack in `model.SYSTEM` costs 30× on every call and breaks
  nothing visibly. If the printed cost per run climbs, look there first.
- **A miss on the anchor is not a wrong fix.** A SEARCH that does not match is
  mechanical, so it gets a bounded exemption from the fix budget
  (`MAX_APPLY_ROUNDS`) the way `expand` does. Issue #11 lost five of nineteen
  rounds across three attempts to exactly that, and its eighth attempt reached
  a complete verified fix only on round 8 of a budget of 6.
- **`main` moving mid-run is normal.** `ship()` re-fetches and retries the push
  once, and resolves the one file that always collides for a reason that is not
  a disagreement — every fix appends to the end of `AUTOMATION_NOTES.md`, so
  both entries are kept. A genuine content conflict still raises at once and
  `main` is never forced.
- **Hard bugs still block.** After six rounds it labels `openhands-blocked`,
  posts what failed, and pushes nothing — the same outcome as before, reached
  for about $0.45 at the very worst instead of $3.12. Six rather than four
  because issue #11's rounds converged rather than repeated and it ran out one
  short, twice; a bug that is genuinely misunderstood still fails fast, since
  most issues finish in one or two.

## Untrusted input

A bug report is written by whoever pressed the button in the app, and the relay
that files it treats its shared secret as an abuse throttle rather than a
security boundary (`relay/README.md`). So the issue text and the bundle reach
the model as attacker-controllable text, and this pipeline pushes to `main`.

Three things contain that, in order of how much they are relied on:

1. **`edits.FORBIDDEN` is enforced in code**, not asked for in a prompt.
   `.github/`, `ci/`, `relay/`, `lib/l10n/gen/` and any path containing `..`
   are rejected before anything is written, so a successful prompt injection
   still cannot reach the workflow, this pipeline, or the relay.
2. **The full suite must pass**, and the model never sees a credential — the
   API keys are in the environment, not in the context.
3. **The system prompt frames the report as data**, not instructions.

The residual risk is a plausible-looking but wrong change to app code under
`frontend/lib/`, which is the same risk any automated fix carries: it lands as
one reviewable, revertable commit with a test attached.
