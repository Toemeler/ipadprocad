#!/usr/bin/env bash
#
# Put one platform's build into the release for this commit or this version.
#
# Usage: ci/release_attach.sh <tag> [--notes-file F] [--title T] <asset>...
#
# Environment (all provided by Actions):
#   GH_TOKEN            token with contents:write
#   GITHUB_REPOSITORY   owner/repo
#   GITHUB_SHA          the commit the assets were built from
#   GITHUB_REF_NAME     the branch or tag, for the notes placeholders
#   GITHUB_RUN_ID       ditto
#
# WHY THIS IS NOT `gh release create`:
#
# Three workflows publish into one tag — iOS, Linux and Windows — and they run
# at the same time on the same commit. Exactly one of them will find the
# release missing and create it; the other two must not fail because they lost
# that race. So the create is allowed to fail and the upload is not.
#
# WHY THE NOTES ARE A FILE IN THE REPOSITORY, for a named version:
#
# Whoever wins the race writes the notes, and which of three jobs finishes
# first is not something to build a release page on. A file every one of them
# passes makes the body the same regardless — and it can then describe all
# three platforms, which no single platform's job is in a position to do.
# @TAG@, @REF@, @SHA@ and @RUN@ are substituted here.
#
# The per-commit `build-<sha>` release passes no notes and gets the
# placeholder below; the iOS job replaces that wholesale when it publishes,
# because there the notes are SideStore's install instructions and belong to
# it alone.
set -euo pipefail

TAG="${1:?usage: release_attach.sh <tag> [--notes-file F] [--title T] <asset>...}"
shift

NOTES_FILE=""
TITLE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --notes-file) NOTES_FILE="${2:?--notes-file needs a path}"; shift 2 ;;
    --title)      TITLE="${2:?--title needs a value}"; shift 2 ;;
    --)           shift; break ;;
    -*)           echo "release_attach: unknown option: $1" >&2; exit 1 ;;
    *)            break ;;
  esac
done

[ "$#" -gt 0 ] || { echo "release_attach: no assets given" >&2; exit 1; }
for a in "$@"; do
  [ -f "$a" ] || { echo "release_attach: no such asset: $a" >&2; exit 1; }
done

REPO="${GITHUB_REPOSITORY:?}"
SHA="${GITHUB_SHA:?}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${REPO}/actions/runs/${GITHUB_RUN_ID:-0}"

if [ -n "$NOTES_FILE" ]; then
  [ -f "$NOTES_FILE" ] || { echo "release_attach: no notes at $NOTES_FILE" >&2; exit 1; }
  # sed with | as the delimiter: the run URL has slashes in it.
  NOTES="$(sed -e "s|@TAG@|${TAG}|g" \
               -e "s|@REF@|${GITHUB_REF_NAME:-$SHA}|g" \
               -e "s|@SHA@|${SHA:0:12}|g" \
               -e "s|@RUN@|${RUN_URL}|g" "$NOTES_FILE")"
  [ -n "$TITLE" ] || TITLE="Prototype ${TAG}"
else
  # The placeholder body, used ONLY when this script creates the release. If
  # the iOS job publishes afterwards it replaces this wholesale; if it never
  # does — it failed, or the commit only touched desktop files — this is what
  # the page says, and it should still be worth reading.
  NOTES="Build of \`${SHA:0:7}\`.

Assets are attached per platform as each build finishes: the IPA from the iOS
job, the AppImage and tarball from the Linux job, the zip from the Windows one.
A platform whose build was not green is simply absent."
  [ -n "$TITLE" ] || TITLE="Build ${SHA:0:7}"
fi

if gh release create "$TAG" \
     --repo "$REPO" \
     --target "$SHA" \
     --title "$TITLE" \
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
echo "release_attach: attached $# asset(s) to $TAG"
