#!/bin/bash
# M311 — put Cycles' dynamic dependencies inside the app, and make the app
# able to find them.
#
# Four of Cycles' dependencies — OpenImageIO, OpenColorIO, Imath and TBB, plus
# what they pull behind them — ship in Blender's iOS library package as
# .dylib rather than .a. There is no static build of them to link, so the app
# has to carry them.
#
# On iOS a bundled dylib lives in Runner.app/Frameworks and is found through
# the binary's runpath, which Flutter's generated project already sets to
# @executable_path/Frameworks. What is NOT already true is that these dylibs
# name themselves that way: a library built on a build machine usually carries
# that machine's absolute path as its install name, and a binary that records
# `/Users/somebody/blender/lib/...` as a load command cannot start on an iPad.
#
# So every copy is renamed to @rpath/<name>, and then every reference to it —
# in the other dylibs, and in the Runner itself — is rewritten to match. The
# rewrite is driven by what otool reports rather than by a list, because the
# set of cross-references between these libraries is theirs to decide, not
# ours to hardcode.
#
# Usage: embed_cycles_dylibs.sh <dylib-dir> <Runner.app>
set -euo pipefail

SRC="${1:?usage: embed_cycles_dylibs.sh <dylib-dir> <Runner.app>}"
APP="${2:?usage: embed_cycles_dylibs.sh <dylib-dir> <Runner.app>}"
FW="$APP/Frameworks"
BIN="$APP/Runner"

shopt -s nullglob
DYLIBS=("$SRC"/*.dylib)
if [ ${#DYLIBS[@]} -eq 0 ]; then
  echo "CYCLES DYLIBS: none to embed"
  exit 0
fi

mkdir -p "$FW"
for f in "${DYLIBS[@]}"; do
  # -L follows the symlinks the package uses for versioned names, so what
  # lands in the bundle is a real file rather than a dangling link.
  cp -Lf "$f" "$FW/"
  chmod u+w "$FW/$(basename "$f")"
done
echo "CYCLES DYLIBS: embedded ${#DYLIBS[@]}"

# Everything that might reference one of them.
TARGETS=("$BIN")
for f in "$FW"/*.dylib; do TARGETS+=("$f"); done

for f in "$FW"/*.dylib; do
  install_name_tool -id "@rpath/$(basename "$f")" "$f"
done

for t in "${TARGETS[@]}"; do
  [ -f "$t" ] || continue
  # tail -n +2 drops the line that is the file's own id.
  otool -L "$t" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    base="$(basename "$dep")"
    if [ -f "$FW/$base" ] && [ "$dep" != "@rpath/$base" ]; then
      install_name_tool -change "$dep" "@rpath/$base" "$t"
    fi
  done
done

# The one thing worth failing the build over: a load command still naming a
# path that will not exist on the device. Anything left pointing at the build
# machine, or at a directory outside the bundle, is an app that cannot launch.
BAD=0
for t in "${TARGETS[@]}"; do
  [ -f "$t" ] || continue
  while read -r dep; do
    case "$dep" in
      @rpath/*|@executable_path/*|@loader_path/*) ;;
      /usr/lib/*|/System/*) ;;
      *) echo "CYCLES DYLIBS: $(basename "$t") still loads $dep"; BAD=1 ;;
    esac
  done < <(otool -L "$t" | tail -n +2 | awk '{print $1}')
done
[ "$BAD" -eq 0 ] || { echo "CYCLES DYLIBS: FAIL (unrewritten load commands above)"; exit 1; }
echo "CYCLES DYLIBS: PASS (every load command is bundle-relative)"
