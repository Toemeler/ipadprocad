#!/usr/bin/env bash
#
# Publish one GitHub Release per green M5 build — the download target for the
# iPad (SideStore). See AUTOINSTALL.md for the device side.
#
# Usage: ci/publish_release.sh <path-to-ipa>
#
# Environment (all provided by Actions):
#   GH_TOKEN            token with contents:write
#   GITHUB_REPOSITORY   owner/repo
#   GITHUB_RUN_NUMBER   becomes the build number AND the release tag
#   GITHUB_RUN_ID       for the run link in the release notes
#   GITHUB_SHA          commit the IPA was built from
#   GITHUB_STEP_SUMMARY optional, gets the install links
#
# Writes source.json (SideStore/AltStore source) and latest.json (the tiny
# manifest the iPad Shortcut polls) next to the IPA and uploads all three.
#
# WHY A TAGGED RELEASE PER BUILD AND NOT ONE ROLLING "latest" TAG:
# the per-build asset URL is immutable, so a download can never be served a
# stale CDN copy of a different build — and old builds stay installable, which
# is the only way back when a build turns out broken on the device. The stable
# entry point is GitHub's own /releases/latest/download/<asset> redirect.

set -euo pipefail

IPA_PATH="${1:?usage: publish_release.sh <path-to-ipa>}"
[ -f "$IPA_PATH" ] || { echo "publish_release: no IPA at $IPA_PATH" >&2; exit 1; }

REPO="${GITHUB_REPOSITORY:?}"
# THE BUILD NUMBER, WHICH IS NOT THE RUN NUMBER ANY MORE. build.yml calls the
# three platform workflows as reusable workflows, and a reusable workflow
# reports the CALLER's run number — so the counter restarted at 1 when the
# orchestrator took over, and SideStore, which shows the version as 0.1.<n>,
# would have seen 0.1.1 arrive after 0.1.702 and read it as a downgrade.
# build.yml passes BUILD_NUMBER = a base + its own run number, which is
# monotonic across the change. The fallback keeps this script runnable on its
# own, which is how it is tested.
RUN="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:?}}"
SHA="${GITHUB_SHA:?}"
RUN_ID="${GITHUB_RUN_ID:-0}"

# ONE RELEASE PER COMMIT, AND ALL THREE PLATFORMS PUT THEIR BUILD IN IT.
#
# This used to be build-<run number>, which no other workflow can compute: the
# Linux and Windows workflows have their own run numbers and there is no way
# from inside one to learn another's. Keying the tag to the COMMIT gives all
# three the same answer without any of them talking to the others, so a push
# to main produces one release page carrying the IPA, the AppImage and the
# Windows zip rather than three pages carrying one file each.
#
# The run number stays where it was meaningful — the version string and the
# AltStore buildVersion, which are iOS's alone and have to keep counting up.
TAG="build-${SHA:0:7}"
VERSION="0.1.${RUN}"
BUNDLE_ID="com.prototype.prototype"
ASSET_NAME="ipadprocad-${RUN}.ipa"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cp "$IPA_PATH" "$WORKDIR/$ASSET_NAME"
SIZE="$(wc -c < "$WORKDIR/$ASSET_NAME" | tr -d ' ')"
SHA256="$(shasum -a 256 "$WORKDIR/$ASSET_NAME" | cut -d' ' -f1)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SUBJECT="$(git log -1 --pretty=%s "$SHA")"
BRANCH="${GITHUB_REF_NAME:-unknown}"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"
# Pinned to the commit, not to a branch: a branch URL would start serving a
# different icon (or 404 after a branch delete) for releases already published.
ICON_URL="https://raw.githubusercontent.com/${REPO}/${SHA}/frontend/branding/AppIcon.appiconset/Icon-App-1024x1024%401x.png"

# ---------------------------------------------------------------- source.json
#
# Keys per the AltStore source format, which SideStore parses with the same
# CodingKeys (AltStoreCore/Model/{Source,StoreApp,AppVersion}.swift).
# versions[] is ordered NEWEST FIRST — AltStore takes element 0 as the current
# release and does NOT sort by version number.
#
# The previous release's source.json is pulled in and the new build prepended,
# so the last 10 builds stay listed and reachable from SideStore's version
# picker. A missing/unparsable predecessor is not fatal: the source then simply
# starts over with this build.
PREV_VERSIONS="[]"
if curl -fsSL --max-time 30 \
     "https://github.com/${REPO}/releases/latest/download/source.json" \
     -o "$WORKDIR/prev-source.json" 2>/dev/null
then
  PREV_VERSIONS="$(jq -c '[.apps[0].versions[]?] // []' "$WORKDIR/prev-source.json" 2>/dev/null || echo '[]')"
fi

jq -n \
  --arg version "$VERSION" \
  --arg build "$RUN" \
  --arg date "$DATE" \
  --arg desc "Build ${RUN} — ${SUBJECT} (${SHA:0:7}, ${BRANCH})" \
  --arg url "$DOWNLOAD_URL" \
  --arg sha256 "$SHA256" \
  --argjson size "$SIZE" \
  --argjson prev "$PREV_VERSIONS" \
  --arg icon "$ICON_URL" \
  --arg bundle "$BUNDLE_ID" \
  --arg repo "$REPO" \
  '{
     name: "ipadprocad builds",
     identifier: "com.prototype.ci",
     subtitle: "Every green CI build, newest first",
     website: ("https://github.com/" + $repo),
     apps: [{
       name: "prototype",
       bundleIdentifier: $bundle,
       developerName: "Toemeler",
       subtitle: "2D-CAD fuer iPad",
       localizedDescription: "Unsigned CI build of the ipadprocad prototype. SideStore signs it on device.",
       iconURL: $icon,
       category: "developer",
       appPermissions: { entitlements: [], privacy: {} },
       versions: ([{
         version: $version,
         buildVersion: $build,
         date: $date,
         localizedDescription: $desc,
         downloadURL: $url,
         size: $size,
         sha256: $sha256,
         minOSVersion: "14.0"
       }] + $prev | .[0:10])
     }],
     news: []
   }' > "$WORKDIR/source.json"

# ---------------------------------------------------------------- latest.json
# What the Shortcut reads. Deliberately flat and tiny.
jq -n \
  --argjson build "$RUN" \
  --arg version "$VERSION" \
  --arg url "$DOWNLOAD_URL" \
  --arg sha "${SHA:0:7}" \
  --arg branch "$BRANCH" \
  --arg subject "$SUBJECT" \
  --arg date "$DATE" \
  --argjson size "$SIZE" \
  '{ build: $build, version: $version, ipaURL: $url, sha: $sha,
     branch: $branch, subject: $subject, date: $date, size: $size }' \
  > "$WORKDIR/latest.json"

# -------------------------------------------------------------------- release
NOTES="$(cat <<EOF
**${SUBJECT}**

| | |
|---|---|
| Build | ${RUN} (\`${VERSION}\`) |
| Commit | \`${SHA:0:7}\` on \`${BRANCH}\` |
| IPA | ${SIZE} bytes, sha256 \`${SHA256}\` |
| Run | https://github.com/${REPO}/actions/runs/${RUN_ID} |

Unsigned — SideStore signs it on the device. Install: \`sidestore://install?url=${DOWNLOAD_URL}\`
EOF
)"

# CREATE-IF-MISSING, then set the notes and upload. The Linux and Windows
# workflows publish into this same tag and may get there first, in which case
# the release already exists and `gh release create` would fail with a 422 —
# so its failure is not an error here. What must not be conditional is the
# rest: iOS is the one writer of the notes and the title (the desktop jobs
# only ever attach assets), so it sets them whether it created the release or
# found it, and --clobber makes the upload idempotent on a re-run.
gh release create "$TAG" \
  --repo "$REPO" \
  --target "$SHA" \
  --title "Build ${RUN} — ${SUBJECT}" \
  --notes "$NOTES" \
  --latest 2>/dev/null || echo "release ${TAG} already exists (a desktop job got here first)"

gh release edit "$TAG" \
  --repo "$REPO" \
  --title "Build ${RUN} — ${SUBJECT}" \
  --notes "$NOTES" \
  --latest

gh release upload "$TAG" \
  "$WORKDIR/$ASSET_NAME" "$WORKDIR/source.json" "$WORKDIR/latest.json" \
  --repo "$REPO" --clobber

# ---------------------------------------------------------------------- prune
# 15 builds ≈ 400 MB. Older ones go, tag and all — the rollback window that
# matters is the last few builds, and an unbounded list makes the release page
# useless. Failure here must not fail the build: the release is already out.
{
  gh release list --repo "$REPO" --limit 100 --json tagName,createdAt \
    | jq -r '[.[] | select(.tagName | startswith("build-"))]
             | sort_by(.createdAt) | reverse | .[15:] | .[].tagName' \
    | while read -r old; do
        [ -n "$old" ] || continue
        echo "pruning $old"
        gh release delete "$old" --repo "$REPO" --cleanup-tag --yes || true
      done
} || echo "prune skipped (non-fatal)"

# -------------------------------------------------------------------- summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Build ${RUN} published"
    echo ""
    echo "- Release: https://github.com/${REPO}/releases/tag/${TAG}"
    echo "- IPA: ${DOWNLOAD_URL}"
    echo "- Install on the iPad: \`sidestore://install?url=${DOWNLOAD_URL}\`"
    echo "- Source (add once in SideStore): \`https://github.com/${REPO}/releases/latest/download/source.json\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "publish_release: ${TAG} -> ${DOWNLOAD_URL}"
