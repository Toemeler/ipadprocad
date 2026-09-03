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

# Drain QUEUE, copying each dylib and queueing whatever IT names. A function
# rather than a bare loop because M367 has a second thing to feed in — see
# below — and those libraries need their own dependencies followed exactly as
# these do. SEEN, COUNT and QUEUE are the shared state; this is bash 3.2, so
# they are globals and not locals.
walk() {
while [ -n "${QUEUE// /}" ]; do
  set -- $QUEUE
  name="$1"
  shift
  QUEUE="$*"
  case "$SEEN" in *" $name "*) continue ;; esac
  # NEVER libtbbmalloc_proxy. It is not a library anything calls — it exists
  # to REPLACE the process's malloc/free with TBB's, by dyld interposition,
  # purely by being loaded. Blender ships it in the package and does not link
  # it. Build 616 did, because the link passes every dylib in the package and
  # ld records a load command for each, and the app then died the first time
  # a part was opened: launch was fine, and the first heavy allocation
  # (OCCT meshing) was not. Nothing here wants another allocator.
  case "$name" in
    libtbbmalloc_proxy.dylib)
      echo "CYCLES DYLIBS: refusing $name (it interposes malloc; see the note above)"
      continue ;;
  esac
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
}

walk

# M367 — AND OpenImageDenoise's DEVICE MODULES, WHICH NO LOAD COMMAND NAMES.
#
# Everything above works because a dylib says what it needs: `otool -L` lists
# it, the queue follows it, and the fixed point is the truth. OIDN 2.x breaks
# that assumption on purpose. It is split into an API library, a core, and one
# module per compute device, and the core loads the module ITSELF, at runtime,
# by an absolute path it builds from its own location (core/module.cpp:
# `dlopen(modulePathPrefix + "libOpenImageDenoise_device_cpu.dylib")`). There
# is no load command, so nothing above can see it.
#
# What that costs if it is missed is not a missing feature. `oidnNewDevice`
# fails, `OIDNDenoiser` calls `Denoiser::set_error`, which is
# `Device::set_error`, and `Session::run_main_render_loop` breaks out of its
# loop the next time it checks `device->have_error()`. Rendered mode dies —
# on the iPad, after a render that had been going fine, with every CI job
# green. It is exactly the shape of failure this whole script exists for.
#
# So: whenever the walk above pulled in anything called libOpenImageDenoise*,
# take every OTHER libOpenImageDenoise* dylib sitting beside it. That is what
# Blender itself does — `add_bundled_libraries(openimagedenoise/lib)` in
# build_files/cmake/platform/platform_apple.cmake bundles the directory rather
# than the dependency graph, for this reason.
#
# The module resolves at runtime because embed_cycles_dylibs.sh puts all of
# these in the SAME directory (Runner.app/Frameworks) and OIDN looks beside
# its own core, not on a search path.
OIDN_SRC=""
for n in $SEEN; do
  case "$n" in
    libOpenImageDenoise*)
      f="$(find "$ROOT" -name "$n" -not -path '*/python/*' -type f 2>/dev/null | head -1)"
      [ -n "$f" ] && OIDN_SRC="$(dirname "$f")"
      break ;;
  esac
done
if [ -n "$OIDN_SRC" ]; then
  # Queued rather than copied, and then walked, so a module gets its OWN
  # dependencies followed like anything else. The first draft copied them
  # straight into place and would have shipped a module whose own dylibs were
  # missing — the same bug one level down.
  for f in "$OIDN_SRC"/libOpenImageDenoise*.dylib; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    case "$SEEN" in *" $name "*) continue ;; esac
    echo "CYCLES DYLIBS: +$name (OIDN loads it by path; no load command names it)"
    QUEUE="$QUEUE $name"
  done
  walk
  # The CPU device module is the one that decides whether OIDN can come up at
  # all on an iPad, so its absence is worth failing the build over rather than
  # discovering on device. A future package that ships a Metal module instead
  # would satisfy this too — the test is that SOME device module is there.
  case "$SEEN" in
    *libOpenImageDenoise_device_*) ;;
    *)
      echo "CYCLES DYLIBS: FAIL — OpenImageDenoise is bundled with no device"
      echo "  module beside it. It would load, find no device, and take the"
      echo "  render session down. Looked in: $OIDN_SRC"
      exit 1 ;;
  esac
fi

echo "CYCLES DYLIBS: $COUNT needed ->$SEEN"
du -sh "$OUT"
