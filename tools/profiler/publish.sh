#!/usr/bin/env bash
# Publish a capture to the ci-logs-profile branch.
#
# An artifact is delivered from Azure blob storage, which the agent proxy
# refuses with a 403 on the CONNECT tunnel. PERFORMANCE_PROFILE.md §13.1 is
# what that costs: sim-perf.yml ran green for a dozen runs and not one of its
# numbers was ever read. Git is reachable from every environment that needs to
# read these, so the capture goes on a branch as well as into an artifact.
#
# Same shape as ci-debug-logs-dart/-m3/-m5 and ci-logs-perf, including the
# `|| exit 0` that keeps a no-change run green.
set -euo pipefail

lane="${1:?lane name}"
run_id="${2:-}"
run_number="${3:-}"
sha="${4:-}"
ref="${5:-}"

out="ci-logs-profile/${lane}"
rm -rf "$out"
mkdir -p "$out"
cp -R "profiler-out/${lane}/." "$out/" 2>/dev/null || true
cp ci-profiler-*.log "$out/" 2>/dev/null || true

{
  echo "lane:       ${lane}"
  echo "run_id:     ${run_id}"
  echo "run_number: ${run_number}"
  echo "sha:        ${sha}"
  echo "ref:        ${ref}"
  echo "published:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "How to read what is here:"
  echo "  attribution.md      the flat profile and the phase split, with"
  echo "                      95 % intervals and the census that says how much"
  echo "                      of the elapsed time was observed at all"
  echo "  validation.md       PASS/FAIL against the registered expectation"
  echo "  trace.json.gz       gunzip, then open at ui.perfetto.dev"
  echo "  stacks.folded.txt.gz  one line per distinct stack, greppable"
  echo "  samples.json.gz     the raw normalised capture; re-read it with"
  echo "                      python3 tools/profiler/profile.py report <file>"
} > "$out/RUN.txt"

gzip -9 -f "$out/stacks.folded.txt" 2>/dev/null || true
find ci-logs-profile -type f -exec ls -la {} \;

git config user.email "ci@prototype.local"
git config user.name "Prototype CI"
git add -f ci-logs-profile
git commit -m "CI(profiler): ${lane} capture from run ${run_id} (${sha})" || exit 0
git push origin HEAD:ci-logs-profile --force
