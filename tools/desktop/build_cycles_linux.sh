#!/usr/bin/env bash
# Prototype — build the Cycles path tracer for Linux.
#
# Produces, in <repo>/frontend/build/native (beside the CAD kernels, which is
# where frontend/linux/CMakeLists.txt looks and where native_lib.dart searches):
#
#   libprototype_cycles.so     Cycles + the shim, exporting only cy_*
#   prototype_cycles_probe     the link gate, which also prints the device
#   deps/                      the shared libraries it was linked against
#
#   tools/desktop/build_cycles_linux.sh
#   tools/desktop/build_cycles_linux.sh --keep   # don't delete blender/ after
#
# WHY IT BUILDS INSIDE BLENDER'S TREE
# -----------------------------------
# `intern/cycles` is Apache-2.0 and meant to be embedded, but its CMake still
# expects Blender's top level to have found Embree, TBB, OpenImageIO and
# OpenColorIO first. Blender's own build already does all of that and fetches a
# matching precompiled dependency set with one command, so borrowing it is a
# dozen lines; configuring Cycles standalone is a project. This is the same
# decision the iOS job made (m1-core-build.yml, cycles-ios) and the same recipe
# with the Apple-specific parts removed.
#
# WHAT IS DIFFERENT FROM iOS, and it is less than it looks
# ---------------------------------------------------------
#   * The device. iOS is Metal-or-nothing; here Cycles picks the fastest
#     backend the build has and the machine can run, ending at the CPU. See
#     pick_device() in cycles_shim.cpp — that is the entire platform
#     difference in 2400 lines of shim.
#   * No kernel source tree ships. Metal compiles its kernels from source at
#     run time; the CPU device's are in the archive. So no `source/` directory
#     and no warm-up render at launch.
#   * A SHARED LIBRARY, not a pile of archives for Xcode to link. Everything
#     is resolved here, once, and only cy_* leaves.
#   * ios_metal.py is not applied. progressive.py and oidn_memory.py are:
#     neither is Apple-specific — one makes the viewport refine a sample at a
#     time, the other stops OpenImageDenoise allocating a viewport-sized frame
#     whole.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="$repo/frontend/build/native"
work="${CYCLES_WORK_DIR:-$repo/backend/cycles/build-linux}"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

keep=0
for arg in "$@"; do
  case "$arg" in
    --keep) keep=1 ;;
    -j*) jobs="${arg#-j}" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# THE SAME REF THE iOS JOB PINS, and that is deliberate rather than lazy. The
# shim is written against one Cycles API; building it against a different
# checkout on each platform is how the two builds drift into different bugs.
# The `ios` branch is Blender plus iOS additions — a superset — so a Linux
# build of it is a Linux build of that Blender.
BLENDER_REF="${BLENDER_REF:-d9b6fe34ddce527d93b97c0bf42ad92cebac4e4e}"
BLENDER_BRANCH="${BLENDER_BRANCH:-ios}"
# GitHub's official read-only mirror rather than projects.blender.org, which
# the iOS job uses. Same commits, same branches — `ios` is there — and one
# fewer host that has to be reachable from wherever this runs; some build
# environments allow github.com and nothing else.
BLENDER_REMOTE="${BLENDER_REMOTE:-https://github.com/blender/blender.git}"

say() { printf '\n=== %s ===\n' "$1"; }

for tool in cmake ninja g++ git python3 patchelf; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing: $tool" >&2
    echo "  sudo apt-get install -y cmake ninja-build g++ git python3 patchelf" >&2
    exit 1
  }
done

mkdir -p "$work"
blender="$work/blender"

# ---------------------------------------------------------------------------
# 1. Blender's tree and its precompiled dependencies
# ---------------------------------------------------------------------------
# --no-checkout, and it is not an optimisation.
#
# Blender's tree is under git-lfs, and this build wants none of the large
# files. GIT_LFS_SKIP_SMUDGE leaves them as pointer files — but a machine WITH
# git-lfs installed then finds a working tree git and lfs disagree about, and
# the checkout of the pinned commit fails with both halves of the same
# complaint at once: "your local changes would be overwritten" for the tracked
# files and "untracked working tree files would be overwritten" for whatever
# the interrupted clone left behind. (That is a CI failure and not a local one:
# a machine without git-lfs never runs the filter and never notices.)
#
# So: clone without a working tree at all, disable the filter for this
# repository, and materialise the pinned commit ONCE, with nothing to conflict
# with.
export GIT_LFS_SKIP_SMUDGE=1
if [ ! -d "$blender/.git" ]; then
  say "cloning Blender ($BLENDER_BRANCH @ ${BLENDER_REF:0:12})"
  git clone --no-checkout --depth 2 --branch "$BLENDER_BRANCH" \
    "$BLENDER_REMOTE" "$blender" 2>&1 | tail -3
  (
    cd "$blender"
    # Belt and braces: the environment variable covers the smudge filter, this
    # covers `git lfs pull` and anything that reaches for the objects.
    git config --local lfs.fetchexclude '*'
    git fetch --depth 1 origin "$BLENDER_REF" 2>&1 | tail -2
    git checkout --force "$BLENDER_REF" 2>/dev/null \
      || git checkout --force FETCH_HEAD
  )
fi
(cd "$blender" && git log --oneline -1)

# WHERE THE DEPENDENCIES COME FROM, and there are two honest answers.
#
# Blender ships a precompiled set (`lib/linux_x64`, several gigabytes) that is
# exactly the versions its own builds are tested against, including
# OpenImageDenoise — which Ubuntu does not package at all. That is the better
# set, and it is what CI uses.
#
# It comes from projects.blender.org, and not every build environment can reach
# that host. So the fallback is the distribution's own Embree, TBB,
# OpenImageIO, OpenColorIO and OpenEXR, which Blender's platform_unix.cmake
# looks for whenever `lib/linux_x64` is absent. Cycles builds and renders
# against them; what is lost is OpenImageDenoise, and the shim already has a
# defined answer for that — its own a-trous filter, reported by
# cy_denoiser_name — because iOS has spent most of its life without OIDN too.
#
# The directory EXISTING is not the test. make_update.py creates it and then
# fails to populate it when the host is unreachable, which is a state that
# looks like success to `-d` and then configures a build with no dependencies
# at all.
bundle_ok() { [ -n "$(ls -A "$blender/lib/linux_x64" 2>/dev/null || true)" ]; }
if ! bundle_ok; then
  say "fetching the precompiled Linux dependency set"
  # --no-blender: only the libraries, not another copy of the source.
  (cd "$blender" && python3 ./build_files/utils/make_update.py --no-blender 2>&1 | tail -5) || true
fi
if bundle_ok; then
  echo "using Blender's precompiled set ($(du -sh "$blender/lib/linux_x64" | cut -f1))"
else
  echo "no lib/linux_x64 — building against the system's own Embree, TBB,"
  echo "OpenImageIO, OpenColorIO and OpenEXR. On Debian/Ubuntu:"
  echo "  sudo apt-get install -y libembree-dev libtbb-dev libopenimageio-dev \\"
  echo "       libopencolorio-dev libopenexr-dev libimath-dev libpugixml-dev \\"
  echo "       libyaml-cpp-dev libtiff-dev libwebp-dev libzstd-dev libdeflate-dev"
  # An empty directory is worse than none: platform_unix.cmake tests for the
  # PATH and would point every find_package at nothing.
  rmdir "$blender/lib/linux_x64" 2>/dev/null || true
fi

# WHAT THE DISTRIBUTION CANNOT SATISFY, turned off explicitly rather than
# discovered as a compile error.
#
# OpenColorIO is the one that bites. Ubuntu 24.04 ships 2.1.3; Cycles calls
# `CPUProcessor::apply(const PackedImageDesc &) const`, which arrived in 2.2,
# so scene/colorspace.cpp does not compile against it. Cycles builds without
# OCIO and falls back to its own built-in sRGB transform, which for a clay
# render of a machined part is the transform anyway.
#
# This is the price of the fallback path and it is worth naming: the build CI
# ships is the one with Blender's own dependency set, which has a matching
# OpenColorIO AND OpenImageDenoise. A local build against distribution
# packages is for developing the shim, not for judging the picture.
extra_flags=()
if ! bundle_ok; then
  extra_flags+=(-DWITH_OPENCOLORIO=OFF)
  # TBB has to be POINTED AT, and then ARGUED WITH about its version.
  #
  # Two separate failures, both of which end the same way — several hundred
  # undefined `tbb::detail::r1::` references at the very last step of a long
  # build, because WITH_TBB stays ON either way, the headers sit on the default
  # include path, every parallel_for compiles against them, and the library
  # reaches no link line.
  #
  #   1. Debian keeps the CMake config package under the multiarch directory,
  #      which is not on CMake's default search path. Hence -DTBB_DIR.
  #   2. platform_unix.cmake asks for `TBB 2021.13.0`; Ubuntu 24.04 ships
  #      2021.11.0, and TBBConfigVersion.cmake rejects anything older than the
  #      request. The 2021 series is ABI-stable on libtbb.so.12 and Cycles uses
  #      only parallel_for / task_arena / enumerable_thread_specific, all of
  #      which 2021.11 has, so the rejection is a version-file policy rather
  #      than a real incompatibility. Point TBB_DIR at a two-file overlay that
  #      answers the version question and forwards to the system config for the
  #      targets themselves.
  for tbb_dir in /usr/lib/*/cmake/TBB /usr/lib/cmake/TBB; do
    [ -f "$tbb_dir/TBBConfig.cmake" ] || continue
    tbb_shim="$work/tbb-version-shim"
    mkdir -p "$tbb_shim"
    cat > "$tbb_shim/TBBConfigVersion.cmake" <<EOF
# Generated by tools/desktop/build_cycles_linux.sh — see the note there.
set(PACKAGE_VERSION "$(sed -n 's/^set(PACKAGE_VERSION "\(.*\)").*/\1/p' \
                       "$tbb_dir/TBBConfigVersion.cmake" | head -1)")
set(PACKAGE_VERSION_COMPATIBLE TRUE)
set(PACKAGE_VERSION_EXACT FALSE)
EOF
    cat > "$tbb_shim/TBBConfig.cmake" <<EOF
include("$tbb_dir/TBBConfig.cmake")
EOF
    extra_flags+=(-DTBB_DIR="$tbb_shim")
    echo "  (TBB $(sed -n 's/^set(PACKAGE_VERSION "\(.*\)").*/\1/p' \
                   "$tbb_dir/TBBConfigVersion.cmake" | head -1) accepted for a"
    echo "   2021.13 request: same libtbb.so.12 ABI, and Cycles uses only the"
    echo "   parts 2021.11 already has.)"
    break
  done
  echo "  (OpenColorIO off: 2.1 is too old for this Cycles. Colour management"
  echo "   falls back to Cycles' own sRGB.)"
fi

# ---------------------------------------------------------------------------
# 2. The shim, as a Cycles target inside Cycles' own tree
#
# See backend/cycles/shim/append.cmake for why it is grafted rather than
# compiled beside Cycles with flags copied out of the build: around two dozen
# WITH_* defines change STRUCT LAYOUTS, and a set that is merely close enough
# to compile links and then misreads memory.
# ---------------------------------------------------------------------------
say "grafting the shim"
mkdir -p "$blender/intern/cycles/shim"
cp "$repo"/backend/cycles/shim/cycles_shim.cpp \
   "$repo"/backend/cycles/shim/cycles_shim.h \
   "$repo"/backend/cycles/shim/cycles_denoise.cpp \
   "$repo"/backend/cycles/shim/cycles_denoise.h \
   "$blender/intern/cycles/shim/"
# Idempotent: a second run must not append the block twice.
if ! grep -q "add_library(cycles_shim" "$blender/intern/cycles/CMakeLists.txt"; then
  cat "$repo/backend/cycles/shim/append.cmake" >> "$blender/intern/cycles/CMakeLists.txt"
fi

# The two portable patches. Both are self-verifying — an anchor that does not
# match exactly once fails rather than silently doing nothing — so running them
# on an already-patched tree is an error, not a no-op. Marked with a stamp.
if [ ! -f "$work/.patched" ]; then
  # Run from $work, whose child IS `blender/`: both scripts address the tree
  # as `blender/intern/cycles/...` relative to the working directory, which is
  # the shape the CI jobs give them.
  say "patching Cycles (progressive sampling, denoiser memory ceiling)"
  (cd "$work" && python3 "$repo/backend/cycles/patches/progressive.py")
  (cd "$work" && python3 "$repo/backend/cycles/patches/oidn_memory.py")
  touch "$work/.patched"
fi

# THE THIRD PATCH, and it is Linux-only, which is why it is here rather than
# in backend/cycles/patches/ beside the two the iOS job shares.
#
# Blender's top level carries
#
#     set_and_warn_dependency(WITH_PYTHON WITH_CYCLES OFF)
#
# and `WITH_PYTHON=OFF` is what makes this build tractable at all (see the
# configure step). So WITH_CYCLES goes OFF one line into the configure — while
# WITH_CYCLES_STANDALONE=ON still adds `intern/cycles`, which still compiles
# `bvh/embree.cpp`, because `WITH_CYCLES_EMBREE` is a separate switch and stays
# ON.
#
# What is lost is every `if(WITH_CYCLES AND ...)` block in platform_unix.cmake,
# and the one that matters is `find_package(Embree)`. Embree's headers are on
# the system include path either way, so Cycles compiles every rtc* call and
# EMBREE_LIBRARIES is empty in the link line: several hundred undefined
# `rtc...` references at the last step of a long build, with nothing in the
# configure output pointing at the cause but a single line reading
# "WITH_PYTHON is disabled, setting WITH_CYCLES=OFF".
#
# The dependency is real for Blender — the render engine is driven from Python
# — and false for this build, which builds `intern/cycles` and links it into a
# C library. WITH_CYCLES_BLENDER is already OFF; nothing here calls a Python
# API. So the line goes, and Embree is found.
py_dep='set_and_warn_dependency(WITH_PYTHON WITH_CYCLES        OFF)'
if grep -qF "$py_dep" "$blender/CMakeLists.txt"; then
  say "patching Blender's top level (WITH_PYTHON must not switch Cycles off)"
  python3 - "$blender/CMakeLists.txt" "$py_dep" <<'PYEOF'
import sys
path, needle = sys.argv[1], sys.argv[2]
text = open(path).read()
if text.count(needle) != 1:
    sys.exit("expected exactly one %r, found %d" % (needle, text.count(needle)))
open(path, "w").write(text.replace(
    needle,
    "# Removed by tools/desktop/build_cycles_linux.sh: this build has no Python\n"
    "# and no Blender, and the dependency is on Cycles' Blender integration\n"
    "# (WITH_CYCLES_BLENDER, already OFF), not on the renderer.\n"
    "# " + needle))
PYEOF
elif ! grep -q "Removed by tools/desktop/build_cycles_linux.sh" "$blender/CMakeLists.txt"; then
  echo "WITH_PYTHON/WITH_CYCLES dependency line not found and not already" >&2
  echo "patched — Blender's top level has changed shape. Stopping rather than" >&2
  echo "configuring a build that would silently drop Embree." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Configure and build
# ---------------------------------------------------------------------------
# Does this dependency set ship OpenImageDenoise? Asked rather than assumed,
# exactly as the iOS job asks it: absent, the shim's own a-trous filter
# finishes the frame and cy_denoiser_name says so.
oidn=OFF
if find "$blender/lib/linux_x64" -iname 'libOpenImageDenoise*' 2>/dev/null | grep -q .; then
  oidn=ON
fi
say "configuring (OpenImageDenoise: $oidn)"

# The four features that are OFF are off because this renders triangles out of
# a CAD kernel: no volumes, no cached point clouds, no shader scripts, no path
# guiding. Each one left ON is a dependency chain compiled in to serve code
# nothing will ever call.
#
# No GPU backend is asked for here. Cycles' CUDA and HIP backends need their
# vendor toolchains at BUILD time to produce cubins, which would make this
# script — and the CI job that runs it — depend on hardware the builder may not
# have. pick_device() already prefers OptiX, CUDA, HIP and oneAPI over the CPU,
# so a build that adds one needs no code change: add the flag here.
# WITH_BLENDER=OFF is what makes this tractable. Configuring the whole of
# Blender pulls in GHOST, Vulkan (and therefore shaderc), Python, three audio
# backends and the file-format importers — none of which Cycles needs, all of
# which have to be found before CMake will finish. Blender's own
# `cycles_standalone.cmake` preset is exactly this pair of switches; the GUI
# half is off because a standalone viewer would want SDL and a window.
#
# Vulkan and Python are named separately because platform_unix.cmake runs
# WHOLESALE — it is included before anything asks what is being built, so its
# `pkg_check_modules(SHADERC REQUIRED shaderc)` fires even for a configure that
# will not compile one line of Blender. Turning the backend off is what makes
# that block unreachable; the same is true of PythonLibsUnix.
cmake -S "$blender" -B "$work/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DWITH_BLENDER=OFF \
  -DWITH_CYCLES_BLENDER=OFF \
  -DWITH_CYCLES_STANDALONE=ON \
  -DWITH_CYCLES_STANDALONE_GUI=OFF \
  -DWITH_CYCLES=ON \
  -DWITH_VULKAN_BACKEND=OFF \
  -DWITH_PYTHON=OFF \
  -DWITH_OPENIMAGEDENOISE=$oidn \
  -DWITH_OPENVDB=OFF -DWITH_NANOVDB=OFF \
  -DWITH_ALEMBIC=OFF -DWITH_USD=OFF \
  -DWITH_CYCLES_OSL=OFF \
  -DWITH_CYCLES_PATH_GUIDING=OFF \
  "${extra_flags[@]}" \
  > "$work/configure.log" 2>&1 || { tail -40 "$work/configure.log"; exit 1; }

say "building Cycles and the shim"
# bf_intern_guardedalloc and bf_intern_sky are Blender's, not Cycles': built
# inside Blender's tree, Cycles allocates through MEM_mallocN and calls the
# Nishita sky model.
# The named ones first, so a failure says which library it was in rather than
# scrolling past in one big build. `cycles` LAST and it is not redundant: it is
# Cycles' own standalone renderer, and building it is what guarantees every
# archive in the link line below actually exists — extern_cuew, extern_hipew
# and bf_intern_libc_compat are all in that line and in none of the names
# anyone would think to write down.
targets="cycles_util cycles_graph cycles_bvh cycles_subd cycles_scene
         cycles_integrator cycles_session cycles_device cycles_kernel
         bf_intern_guardedalloc bf_intern_sky cycles_shim cycles"
for t in $targets; do
  cmake --build "$work/build" --target "$t" -j "$jobs" \
    > "$work/build_$t.log" 2>&1 \
    || { echo "FAILED: $t"; grep -E "error:|fatal error:" "$work/build_$t.log" | head -30; exit 1; }
  echo "built $t"
done

# ---------------------------------------------------------------------------
# 4. Link libprototype_cycles.so
#
# --start-group, unlike the iOS link: GNU ld resolves a group to a fixed point,
# so the archives need no ordering and none is invented. --whole-archive on the
# shim alone, because nothing references cy_* from inside the link and the
# linker would otherwise discard every one of them.
# ---------------------------------------------------------------------------
say "linking libprototype_cycles.so"
mkdir -p "$out"
shim_a=$(find "$work/build" -name 'libcycles_shim.a' | head -1)
[ -n "$shim_a" ] || { echo "no libcycles_shim.a was built" >&2; exit 1; }

# WHICH LIBRARIES, DECIDED BY THE BUILD RATHER THAN BY ME.
#
# The iOS job answers this with `-Wl,-t`, tracing what the link actually
# loaded. There is a better answer here: `WITH_CYCLES_STANDALONE=ON` means
# CMake has already worked out the complete link line for Cycles' own
# standalone renderer, and written it into build.ninja as one LINK_LIBRARIES
# variable. Taking it verbatim is exactly right and cannot drift — it covers
# the bundle path and the system-package path with the same three lines, and
# it caught two archives a hand-written list had missed (extern_cuew,
# extern_hipew, which Cycles links even when neither backend is compiled in,
# to report that they are absent).
#
# Paths in build.ninja are relative to the build directory, so the link runs
# from there.
link_libs=$(awk '
  /^build bin\/cycles: / { inrule = 1 }
  inrule && /^  LINK_LIBRARIES = / {
    sub(/^  LINK_LIBRARIES = /, ""); print; exit
  }
  inrule && /^$/ { inrule = 0 }
' "$work/build/build.ninja")
[ -n "$link_libs" ] || {
  echo "no LINK_LIBRARIES for bin/cycles in build.ninja — cannot link" >&2
  exit 1
}

# --start-group, unlike the iOS link: GNU ld resolves a group to a fixed point,
# so the archives need no ordering and none is invented. --whole-archive on the
# shim alone, because nothing inside the link references cy_* and the linker
# would otherwise discard every one of them.
( cd "$work/build" && g++ -shared -fPIC -o "$out/libprototype_cycles.so" \
  -Wl,--version-script="$repo/backend/desktop/prototype_cycles.map" \
  -Wl,--whole-archive "$shim_a" -Wl,--no-whole-archive \
  -Wl,--start-group $link_libs -Wl,--end-group \
  -Wl,-rpath,'$ORIGIN' -Wl,--disable-new-dtags \
  -lpthread -ldl -lm ) > "$work/link.log" 2>&1 || {
    echo "the shim does not link:"
    grep -oE "undefined reference to \`[^']+'" "$work/link.log" | sort -u | head -30
    tail -20 "$work/link.log"
    exit 1
  }
echo "linked: $(du -h "$out/libprototype_cycles.so" | cut -f1)"

# THE EXPORT SURFACE, checked rather than trusted. The version script is the
# only thing standing between this and a symbol table with all of Cycles,
# Embree, TBB and OpenImageIO in it.
exported=$(nm -D --defined-only "$out/libprototype_cycles.so" | awk '{print $3}' | grep -v '^$' || true)
leaked=$(printf '%s\n' "$exported" | grep -vE '^(cy_|_init|_fini|_edata|_end|__bss_start)' | head -5 || true)
if [ -n "$leaked" ]; then
  echo "EXPORT CHECK: FAIL — symbols escaped the version script:"
  printf '%s\n' "$leaked"
  exit 1
fi
echo "exports $(printf '%s\n' "$exported" | grep -c '^cy_') cy_ symbols and nothing else"

# ---------------------------------------------------------------------------
# 5. The closure, on the same rule as the CAD kernels
# ---------------------------------------------------------------------------
say "collecting the runtime closure"
deps="$out/deps"
mkdir -p "$deps"
host_only='^(ld-linux.*|libc|libm|libdl|libpthread|librt|libresolv|libgcc_s'
host_only="$host_only"'|libstdc\+\+|libEGL|libGL|libGLX|libGLdispatch|libOpenGL'
host_only="$host_only"'|libX11|libXau|libXdmcp|libXext|libXrender|libXi|libXfixes'
host_only="$host_only"'|libxcb.*|libwayland.*|libdrm|libgbm'
host_only="$host_only"'|libglib-2\.0|libgobject-2\.0|libgio-2\.0|libgmodule-2\.0'
host_only="$host_only"'|libgthread-2\.0|libpango.*|libcairo.*|libgdk.*|libgtk.*'
host_only="$host_only"'|libatk.*|libharfbuzz.*|libfontconfig|libfreetype|libpng16'
host_only="$host_only"'|libz|libpixman.*|libepoxy|libxkbcommon.*|libsystemd'
host_only="$host_only"'|libselinux|libmount|libblkid|libpcre2-8)\.so.*$'

copied=0
while read -r name arrow path rest; do
  [ "${arrow:-}" = "=>" ] || continue
  [ -f "${path:-}" ] || continue
  printf '%s' "$name" | grep -Eq "$host_only" && continue
  # Already there from the CAD kernels' own closure: same file, same name.
  [ -e "$deps/$name" ] && continue
  cp -L "$path" "$deps/$name"
  copied=$((copied + 1))
done < <(ldd "$out/libprototype_cycles.so")
for lib in "$deps"/*.so*; do
  [ -f "$lib" ] && patchelf --set-rpath '$ORIGIN' "$lib"
done
echo "added $copied libraries to $deps ($(du -sh "$deps" | cut -f1) total)"

say "the link gate"
# g++ compiles a .c file as C++, which is what the iOS job's clang++ does too.
g++ -I "$repo/backend/cycles/shim" "$repo/backend/cycles/shim/shim_probe.c" \
  -o "$out/prototype_cycles_probe" \
  -L"$out" -lprototype_cycles -Wl,-rpath,"$out" \
  > "$work/probe.log" 2>&1 || { tail -20 "$work/probe.log"; exit 1; }
"$out/prototype_cycles_probe" || true

if [ "$keep" = 0 ] && [ -z "${CYCLES_WORK_DIR:-}" ]; then
  echo
  echo "(Blender's tree is $work — $(du -sh "$work" 2>/dev/null | cut -f1). Delete it"
  echo " when you are done, or pass --keep to be reminded rather than told.)"
fi

say "done"
echo "library : $out/libprototype_cycles.so"
echo
echo "Next:  cd frontend && flutter build linux --release"
