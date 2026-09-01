#!/bin/bash
# M313 — work out which dynamic libraries the app will actually load, and
# copy exactly those.
#
# ld records a load command for EVERY dylib handed to it on the command line,
# used or not, unless it is told otherwise. The probe link passes all thirty
# in lib/ios_arm64 because that is how the missing four were found, and the
# resulting binary duly claims to need USD and Vulkan — libusd_ms.dylib alone
# is bigger than the rest of the app.
#
# So the link is done with -dead_strip_dylibs, which drops the load commands
# for dylibs nothing referenced, and then the answer is read back out of the
# binary rather than guessed: whatever @rpath names survive in the load
# commands are what the app must carry. Their own @rpath dependencies are
# followed to a fixed point, because a bundled dylib that cannot find ITS
# dylib fails at load time with the same nothing-useful message.
#
# Usage: harvest_cycles_dylibs.sh <binary> <search-root> <out-dir>
set -euo pipefail

BIN="${1:?usage: harvest_cycles_dylibs.sh <binary> <search-root> <out-dir>}"
ROOT="${2:?}"
OUT="${3:?}"
mkdir -p "$OUT"

rpath_deps() {
  otool -L "$1" | tail -n +2 | awk '{print $1}' \
    | sed -n 's|^@rpath/||p'
}

find_lib() {
  find "$ROOT" -name "$1" -not -path '*/python/*' -type f 2>/dev/null | head -1
}

declare -a QUEUE=()
while IFS= read -r n; do [ -n "$n" ] && QUEUE+=("$n"); done < <(rpath_deps "$BIN")

declare -A SEEN=()
while [ ${#QUEUE[@]} -gt 0 ]; do
  name="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")
  [ -n "${SEEN[$name]:-}" ] && continue
  SEEN[$name]=1
  f="$(find_lib "$name")"
  if [ -z "$f" ]; then
    echo "CYCLES DYLIBS: $name is required and is not in $ROOT" >&2
    exit 1
  fi
  cp -Lf "$f" "$OUT/$name"
  chmod u+w "$OUT/$name"
  while IFS= read -r d; do [ -n "$d" ] && QUEUE+=("$d"); done < <(rpath_deps "$f")
done

echo "CYCLES DYLIBS: ${#SEEN[@]} needed"
ls -la "$OUT" | tail -n +2
du -sh "$OUT"
