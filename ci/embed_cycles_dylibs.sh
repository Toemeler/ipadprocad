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

# A tripwire, not a filter. If this ever reappears in the harvested set,
# something upstream changed and the app is about to get a different malloc
# than the one Flutter, Qt and OCCT were built against — which is what build
# 616 shipped, and it crashed on the first part opened.
for f in "${DYLIBS[@]}"; do
  case "$(basename "$f")" in
    libtbbmalloc_proxy.dylib)
      echo "CYCLES DYLIBS: FAIL — libtbbmalloc_proxy.dylib must never be bundled;"
      echo "  it replaces the process allocator by being loaded. See M319."
      exit 1 ;;
  esac
done

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

# The two things worth failing the build over, both of which produce an app
# that will not launch and neither of which is visible until a device tries.
#
#   1. a load command still naming a path that will not exist on the device —
#      the build machine's directory, or anywhere outside the bundle;
#   2. a load command that IS bundle-relative and names a file that is not in
#      the bundle. This is the one the first check misses, and it is the more
#      likely of the two: the embedded set is computed from a probe binary,
#      and if the app ever needs one more library than the probe did, every
#      name is correctly spelled and one file is simply absent.
#
# Frameworks other than the dylibs (Flutter's, the plugins') are left alone —
# they are not ours to place — so only @rpath entries naming a plain .dylib
# are required to be present.
BAD=0
for t in "${TARGETS[@]}"; do
  [ -f "$t" ] || continue
  while read -r dep; do
    case "$dep" in
      @rpath/*.dylib)
        base="${dep#@rpath/}"
        [ -f "$FW/$base" ] || { echo "CYCLES DYLIBS: $(basename "$t") loads $dep and it is not in the bundle"; BAD=1; }
        ;;
      @rpath/*|@executable_path/*|@loader_path/*) ;;
      /usr/lib/*|/System/*) ;;
      *) echo "CYCLES DYLIBS: $(basename "$t") still loads $dep"; BAD=1 ;;
    esac
  done < <(otool -L "$t" | tail -n +2 | awk '{print $1}')
done
[ "$BAD" -eq 0 ] || { echo "CYCLES DYLIBS: FAIL (see the load commands above)"; exit 1; }
echo "CYCLES DYLIBS: PASS (every load command is bundle-relative and present)"
