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
# WRITTEN FOR BASH 3.2, which is what /bin/bash is on a macOS runner: no
# associative arrays and no mapfile. The seen-set is a space-delimited string,
# which for thirty names is not worth a data structure. M314's job failed
# silently on `declare -A`.
#
# Usage: harvest_cycles_dylibs.sh <binary> <search-root> <out-dir>
set -eu

BIN="${1:?usage: harvest_cycles_dylibs.sh <binary> <search-root> <out-dir>}"
ROOT="${2:?}"
OUT="${3:?}"
mkdir -p "$OUT"

rpath_deps() {
  otool -L "$1" | tail -n +2 | awk '{print $1}' | sed -n 's|^@rpath/||p'
}

QUEUE="$(rpath_deps "$BIN" | tr '\n' ' ')"
SEEN=" "
COUNT=0

while [ -n "${QUEUE// /}" ]; do
  set -- $QUEUE
  name="$1"
  shift
  QUEUE="$*"
  case "$SEEN" in *" $name "*) continue ;; esac
  SEEN="$SEEN$name "
  f="$(find "$ROOT" -name "$name" -not -path '*/python/*' -type f 2>/dev/null | head -1)"
  if [ -z "$f" ]; then
    echo "CYCLES DYLIBS: FAIL — $name is required and is not in $ROOT"
    exit 1
  fi
  # -L: the package uses symlinks for versioned names, and a bundle cannot
  # ship a link to a path that will not be there.
  cp -Lf "$f" "$OUT/$name"
  chmod u+w "$OUT/$name"
  COUNT=$((COUNT + 1))
  QUEUE="$QUEUE $(rpath_deps "$OUT/$name" | tr '\n' ' ')"
done

echo "CYCLES DYLIBS: $COUNT needed ->$SEEN"
du -sh "$OUT"
