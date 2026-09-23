# AI lab — running the assistant live, measuring it, iterating

The owner's brief (2026-09-23): stop waiting for bug reports. With a
DeepSeek key in the environment, run the assistant yourself on real modelling
tasks, measure speed and accuracy, and iterate — fast, trial and error, many
different ideas — until it models like a professional human 3D modeller: as
fast, as accurate, and creative. Push every improvement directly to `main`.
Research before writing anything into `knowledge/`.

## 1. Setup in a fresh cloud container (≈5 min, no 150-min kernel build)

```sh
# Flutter (the container has none)
S=/tmp/lab && mkdir -p $S && cd $S
git clone -q --depth 1 -b stable https://github.com/flutter/flutter.git
export PATH=$S/flutter/bin:$PATH

# The real kernel, from the latest release's Linux bundle — the same
# libprototype_native.so the app ships, OCCT included.
curl -sSL -o app.tgz \
  "$(curl -sS https://api.github.com/repos/Toemeler/ipadprocad/releases/latest \
     | python3 -c 'import sys,json;print(next(a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith("linux-x64.tar.gz")))')"
tar xzf app.tgz
export PROTOTYPE_NATIVE_DIR=$S/prototype-linux-x64/lib

# Two system libraries Qt pulls in that the container lacks
apt-get install -y -qq libegl1 libopengl0 || { apt-get update -qq; apt-get install -y -qq libegl1 libopengl0; }

cd <repo>/frontend && flutter pub get
flutter test --no-pub test/ai_real_kernel_test.dart   # must NOT say "no kernel library"
```

The key: the environment variable `DEEPSEEK_API_KEY` (set in the cloud
environment's settings; only sessions started after it was added see it).
Never print it, never commit it, never paste it into a file.

## 2. The benchmark

`frontend/test/bench/ai_bench_test.dart` runs the real controller loop on the
real kernel and scores the part the app measures, never the model's account.

```sh
AI_BENCH=live AI_BENCH_PROVIDER=deepseek AI_BENCH_MODEL=deepseek-flash \
AI_BENCH_KEY="$DEEPSEEK_API_KEY" AI_BENCH_ONLY=cup \
AI_BENCH_OUT=/tmp/lab/run.json flutter test --no-pub test/bench/ai_bench_test.dart
```

`AI_BENCH=replay` (no key) proves the harness. Scenarios and their checks:
`frontend/test/bench/scenarios.json`.

## 3. First jobs

1. **Fix the suite.** A full `flutter test` on main after #95 showed
   `+4956 ~24 -6` — six failures, not yet identified. Run
   `flutter test --no-pub -r expanded 2>&1 | grep '\[E\]$'`, fix, push.
2. **Add the real tasks from #90–#95 as scenarios**, with checks:
   - spool on the motor's Ø0.8 D-shaft (needs the motor STEP; the bug-report
     bundles on the `bug-reports` branch carry the part and its imports) —
     bore centred on the shaft axis, ≤ Ø4.5, ≤ 4 mm, symmetric groove;
   - 1:10 capstan wheel beside it, same height, pitch ratio 10 ± 0.2;
   - case fitted to both (use of `enclose`, outside ≤ contents + 2 × (wall +
     clearance) + 1 mm);
   - tapered 250 ml cup, wider at the top, then an angular handle joined along
     its whole height;
   - cable clip / cup / teacup already exist.
3. **Record per run**: time to the first executed op, total wall time, rounds,
   thinking cuts, input/output tokens, blocks rolled back, pass/fail per check.

## 4. Levers worth trying (measure each; keep only what wins)

- Thinking: budget per round (now 5 s, then cut → retry with `none`; after one
  cut the rest of the turn goes `none`); think only on round 0 with a larger
  budget; `none` everywhere; `low` with no cut.
- Prompt size: `kAiActionInstructions` + shared text is ~67k characters and is
  resent every round (~30k input tokens/round). Trim, split by task type, or
  send the op reference only for ops in use.
- Knowledge budget (`maxInputBytes ~/ 6`, ≤ 28000) and which docs open.
- Bigger steps: more actions per block (cap 12), composite ops like `enclose`
  for the common parts (revolve-profile helper, handle helper, shaft-fit
  helper), so a professional's 3–4 moves are 3–4 blocks.
- What the report tells the model after each block (`partAfter`, views):
  smaller and more decisive, e.g. a one-line "what changed" plus checks.
- Streaming execution: run a block the moment its fence closes.
- A plan-then-execute split: one short planning call that emits the whole
  op list, then no model call between blocks unless a check fails.

## 5. Rules

- Push directly to `main` (the owner's standing instruction), after the
  relevant tests pass; run the full suite before pushing big changes.
- Research (web) before adding or changing anything in `knowledge/`, and cite
  sources in the document.
- Keep the key out of logs, traces, commits and bundles.
