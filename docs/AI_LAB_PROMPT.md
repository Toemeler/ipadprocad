# The AI lab prompt — paste into a new session

```text
You are taking over one job in the repository toemeler/ipadprocad: make the
app's AI modelling assistant model like a professional human 3D modeller —
as fast as one, as accurate as one, and as creative as one. You work on this
until that is measurably true. Not until it is "better". Until it is true.

═══ CONTEXT ═══
The app ("Prototype") is a Flutter CAD app with an OpenCASCADE kernel. Its
assistant (frontend/lib/ai/) talks to DeepSeek (model "deepseek-flash"),
emits ```cad``` action blocks (sketch, extrude, revolve, fillet, shell,
enclose, …), the app runs them on the real kernel and reports back, round
after round. Until now the owner found every problem by using the app and
filing bug reports (issues #82–#95; bundles on the `bug-reports` branch).
That loop is too slow. You now have the key yourself: the environment
variable DEEPSEEK_API_KEY. Use it to run the assistant live, as often as you
need, and improve it by trial and error — fast, many different ideas,
measured, keep what wins.

WHERE YOU WORK: locally, in this session's own Linux terminal. Build,
test, run the benchmark and call DeepSeek from here. Do NOT iterate through
GitHub Actions — no workflow_dispatch runs, no waiting on CI; a CI round
trip is minutes, a local run is seconds, and speed of iteration is the
point. GitHub is only where you push results.

Read these first, in this order:
  1. docs/AI_LAB.md — local setup (Flutter + the real kernel in ~5 min from
     the release's Linux bundle, no 150-min build), the live benchmark
     command, first jobs, levers.
  2. frontend/test/bench/ai_bench_test.dart and scenarios.json — the harness.
  3. The last ten commits on main touching frontend/lib/ai/ and the issues
     #90–#95 — what has already been found and fixed, and why.

═══ THE END GOAL (the owner's words) ═══
"Iterate fast with trial and error to get to an incredibly efficient,
creative way to make this model work like an absolute pro — as fast as a
human would. Very, very fast and also very, very accurate. It needs to end
up high over the standard and model as a professional human 3D modelling
pro would, with the same speed and accuracy. Be creative, try new things,
take the time you need." And, from the bug reports: as soon as the prompt is
sent, work must be visible within seconds; no minute-long thinking; the
result must be correct the first time; designs must not all look the same.

═══ DEFINITION OF DONE — all of it, measured, not estimated ═══
Build a benchmark set of at least 12 scenarios covering what users ask for:
the ones in scenarios.json, plus the real tasks from #90–#95 (mini spool
press-fitted on the motor's Ø0.8 D-shaft from the STEP in the bug bundle;
a 1:10 capstan wheel beside it at the same height; a case fitted around
motor + both wheels with a cord outlet; a tapered 250 ml cup, wider at the
top, then an angular handle joined along its full height; cable clip with a
countersunk screw; plate with holes; a simple gearbox housing; …). Give each
scenario hard, automatic checks (valid single solid, no failed feature,
printable, dimensions within ±0.1 mm or the stated tolerance of the request,
features joined, requirement-specific checks like "bore centred on the shaft
axis within 0.05 mm", "groove symmetric", "taper widens upward").
Then hold back at least 4 MORE scenarios you write but never tune on (a
hold-out set), so you cannot overfit.

Done means ALL of these, on BOTH sets:
  • Speed: first executed CAD op ≤ 5 s after the request is sent, for every
    scenario. Total wall time ≤ what a skilled human needs in Fusion 360 or
    Inventor for the same part: count the operations a pro would use and
    allow ~8 s per operation (e.g. a plain cup ≈ 5 ops ≈ 40 s; spool ≈ 6 ops
    ≈ 50 s; fitted case with outlet ≈ 8 ops ≈ 65 s). Write this reference
    time into each scenario and measure against it.
  • Accuracy: every check passes, in 3 consecutive full runs of the whole
    set (the model is not deterministic — one lucky run is not a result).
    At most one rolled-back block per scenario per run.
  • Professional quality: you render each finished part (the app's `look`
    renders views; the bench can save them) and review the images yourself
    like a senior designer reviewing a junior: proportions, symmetric
    grooves, edges broken sensibly and scaled to the part, handles and bosses
    joined properly, nothing floating, nothing a pro would redo. Record the
    verdict per scenario. A pass needs "a pro would hand this over".
  • Creativity: the same open request run 3 times gives visibly different,
    sensible designs (different profile/proportions/details), not the same
    part three times.
If any one of these fails on any scenario, you are not done.

═══ THE LOOP ═══
  1. Measure the current state: run the full set live, record per scenario
     time-to-first-op, total time, rounds, thinking cuts, tokens in/out,
     rollbacks, each check, the rendered verdict. Keep a table.
  2. Pick the biggest gap. Form a hypothesis. Change ONE thing.
  3. Run the affected scenarios live (in parallel where you can), compare
     with the table. Keep the change only if it wins without regressing
     anything else. Otherwise revert it and try the next idea.
  4. Every kept change: tests pass → commit → push to main. Update the log.
  5. Repeat. Every ~10 kept changes, re-run the full set and the hold-out set.

Try many genuinely different ideas, not variations of one. At least:
  • thinking strategy (per-round budget, think only on round 0 with a longer
    budget, never think, plan-once-then-execute);
  • prompt size and shape (the instructions are ~67k characters resent every
    round — trim, split by task, send only the op reference in use, cache);
  • bigger, smarter steps: composite ops for what pros do in one move
    (revolved profile, handle, shaft fit, fitted case, pattern of holes,
    shell+rim+foot), so a part takes 3–5 blocks, not 15;
  • what the app reports back after each block (shorter, decisive, checks
    instead of prose);
  • running a block the moment its code fence closes in the stream;
  • knowledge: which documents open, how much, worked examples vs rules;
  • self-checks the app runs automatically before the model is asked again;
  • anything else you think of. Be creative. Read how professional CAD users
    and other CAD assistants work, and borrow what is good.

═══ NEVER STOP BEFORE DONE ═══
  • Do not end your turn, and do not report "finished", while any target in
    the definition of done is unmet. A partial improvement is a progress
    note, never an ending.
  • If you are blocked on one lever, switch to another. If an idea fails,
    that is data — log it and try the next. There is always a next idea.
  • Keep docs/AI_LAB_LOG.md in the repo: the current results table, what
    you tried, what won, what lost, what is next. Commit and push it often.
    If your context is compacted or the session restarts, re-read it and
    continue exactly where you were.
  • If you ever have to end a turn (waiting, a limit, a long run), first
    schedule a wake-up (send_later, a few minutes out) whose message says
    "Continue the AI lab from docs/AI_LAB_LOG.md; the goal is not reached
    yet", so work always resumes by itself.
  • Only when every target is met on both sets, 3 runs in a row, write a
    final report into the log (before/after table, what made the difference)
    and tell the owner. Until then, keep going — take the time you need.

═══ RULES ═══
  • Push directly to main, after the relevant tests pass (the owner's
    standing instruction). Run the full suite before pushing large changes.
    First job: a full `flutter test` on main showed 6 failures after #95 —
    find and fix them.
  • Research on the web before adding or changing anything in knowledge/,
    and cite the sources in the document. Never write knowledge from memory.
  • Never print, log, commit or write the key anywhere. It lives only in the
    environment variable.
  • The owner may still file bug reports (GitHub issues with a bundle on the
    `bug-reports` branch). Check for new ones now and then and fold them
    into the benchmark as scenarios.
  • Report progress to the owner briefly (numbers, not prose): where you
    started, where you are, what is next.
```
