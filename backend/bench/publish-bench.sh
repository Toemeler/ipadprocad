#!/usr/bin/env bash
#
# Publish a Lane C capture to the ci-logs-bench branch.
#
# WHY A BRANCH AND NOT AN ARTIFACT. PERFORMANCE_PROFILE.md §13.1 is the
# cautionary tale: sim-perf.yml was green from run 32 onward and not one of its
# numbers was ever read, because artifacts are served from blob storage the
# restricted network refuses (403 on the CONNECT tunnel). The measurement
# existed; the delivery did not. A committed file is reachable with git alone.
#
# WHY THIS IS A SCRIPT AND NOT INLINE YAML. Two jobs publish — ubuntu and
# macos — and they finish at unpredictable times. sim-perf.yml can afford
# `git push --force` because it has one publisher; two force-pushing jobs would
# each erase the other's capture, and the loser would be silent. So this
# fetches, replays onto whatever is there, and retries. Each platform writes
# into its OWN subdirectory, so the merge never has to resolve anything.
#
# Usage: publish-bench.sh <platform-tag>     (env: RUN_ID RUN_NUMBER SHA REF)

set -u
set -o pipefail

PLATFORM="${1:?usage: publish-bench.sh <platform-tag>}"
BRANCH="ci-logs-bench"
DEST="ci-logs-bench/${PLATFORM}"

if [ ! -d bench-out ]; then
    echo "publish-bench: no bench-out/ to publish; nothing to do"
    exit 0
fi

git config user.email "ci@prototype.local"
git config user.name "Prototype CI"

# Stash the capture outside the work tree: the checkout below replaces the
# index and the working copy, and the files have to survive that.
STAGE="$(mktemp -d)"
cp -R bench-out/. "$STAGE/" 2>/dev/null || true

{
    echo "platform:   ${PLATFORM}"
    echo "run_id:     ${RUN_ID:-?}"
    echo "run_number: ${RUN_NUMBER:-?}"
    echo "sha:        ${SHA:-?}"
    echo "ref:        ${REF:-?}"
    echo "captured:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "ABSOLUTE MILLISECONDS IN THESE FILES ARE NOT iPad MILLISECONDS."
    echo "Read relative costs, exponents, allocation and RSS behaviour."
    echo "PERFORMANCE_PROFILE.md §13.3 says why."
} > "$STAGE/RUN.txt"

for attempt in 1 2 3 4 5; do
    git fetch origin "$BRANCH" 2>/dev/null || true
    if git rev-parse --verify -q "origin/${BRANCH}" >/dev/null; then
        git checkout -B "$BRANCH" "origin/${BRANCH}" || exit 0
    else
        # First ever publish: an ORPHAN branch, so the log branch does not drag
        # a copy of the source tree's history along with it.
        git checkout --orphan "$BRANCH" || exit 0
        git rm -rq --cached . 2>/dev/null || true
    fi

    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -R "$STAGE/." "$DEST/"
    find "$DEST" -type f -exec ls -la {} \;

    git add -f "$DEST"
    git commit -q -m "CI(bench): Lane C ${PLATFORM} capture from run ${RUN_ID:-?} (${SHA:-?})" \
        || { echo "publish-bench: nothing changed"; exit 0; }

    if git push origin "HEAD:${BRANCH}"; then
        echo "publish-bench: published ${PLATFORM} to ${BRANCH}"
        exit 0
    fi
    # Somebody else published between the fetch and the push. Drop this attempt
    # and replay onto their commit — never --force, which is what would make
    # the other job's capture disappear without trace.
    echo "publish-bench: push rejected, retrying (attempt ${attempt})"
    git reset -q --hard HEAD~1 || true
    sleep $((attempt * 3))
done

echo "publish-bench: could not publish after 5 attempts"
exit 0
