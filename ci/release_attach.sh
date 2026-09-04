#!/usr/bin/env bash
#
# Put one platform's build into the release for this commit.
#
# Usage: ci/release_attach.sh <tag> <asset> [asset...]
#
# Environment (all provided by Actions):
#   GH_TOKEN            token with contents:write
#   GITHUB_REPOSITORY   owner/repo
#   GITHUB_SHA          the commit the assets were built from
#
# WHY THIS IS NOT `gh release create`:
#
# Three workflows publish into one tag — the iOS job through
# ci/publish_release.sh and the Linux and Windows jobs through this — and they
# run at the same time on the same commit. Exactly one of them will find the
# release missing and create it; the other two must not fail because they
# lost that race. So the create is allowed to fail and the upload is not.
#
# The notes and the title belong to the iOS job alone, which is why nothing
# here writes them beyond the placeholder used when this script is what
# creates the release. Two writers of one notes body is a lost section, and
# the assets say which platforms are present without any prose.
set -euo pipefail

TAG="${1:?usage: release_attach.sh <tag> <asset>...}"
shift
[ "$#" -gt 0 ] || { echo "release_attach: no assets given" >&2; exit 1; }
for a in "$@"; do
  [ -f "$a" ] || { echo "release_attach: no such asset: $a" >&2; exit 1; }
done

REPO="${GITHUB_REPOSITORY:?}"
SHA="${GITHUB_SHA:?}"

# The placeholder body, used ONLY when this script creates the release. If the
# iOS job publishes afterwards it replaces this wholesale; if it never does —
# it failed, or the commit only touched desktop files — this is what the page
# says, and it should still be worth reading.
NOTES="Build of \`${SHA:0:7}\`.

Assets are attached per platform as each build finishes: the IPA from the iOS
job, the AppImage and tarball from the Linux job, the zip from the Windows one.
A platform whose build was not green is simply absent."

if gh release create "$TAG" \
     --repo "$REPO" \
     --target "$SHA" \
     --title "Build ${SHA:0:7}" \
     --notes "$NOTES" \
     --prerelease 2>/dev/null
then
  echo "release_attach: created $TAG"
else
  echo "release_attach: $TAG already exists"
fi

# NOT conditional, and --clobber so a re-run of the job replaces its own
# assets rather than failing on the name.
gh release upload "$TAG" "$@" --repo "$REPO" --clobber

echo "release_attach: ${TAG} <- $*"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Attached to \`${TAG}\`"
    echo ""
    for a in "$@"; do echo "- \`$(basename "$a")\`"; done
    echo ""
    echo "https://github.com/${REPO}/releases/tag/${TAG}"
  } >> "$GITHUB_STEP_SUMMARY"
fi
