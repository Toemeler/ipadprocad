#!/usr/bin/env bash
# Prototype — build the desktop CAD kernels.
#
# Produces, in <repo>/frontend/build/native (which is exactly where
# frontend/linux/CMakeLists.txt looks and where frontend/lib/ffi/native_lib.dart
# searches):
#
#   libprototype_native.so     QCAD C-API + libslvs shim + OCCT shim
#   prototype_native_smoke     the dlopen gate that proves it answers
#   deps/                      the shared libraries it was linked against
#
# It is a SEPARATE step from `flutter build linux` on purpose. OCCT is a
# 5400-file compile; putting it in front of every UI change would make the
# Flutter build unusable, and requiring it at all would make `flutter run`
# impossible on a machine that has not built it. The app has a defined,
# reported behaviour with no kernels — the Dart drawing engine, the Dart
# solver, no 3D — so this is the step you run once and then forget.
#
#   tools/desktop/build_native.sh                 # everything, incl. OCCT
#   tools/desktop/build_native.sh --no-occt       # 2D + solver only, minutes
#   tools/desktop/build_native.sh --occt-only     # just (re)build OCCT
#
# Dependencies, on Debian/Ubuntu:
#   sudo apt-get install -y cmake ninja-build g++ pkg-config \
#        qt6-base-dev qt6-declarative-dev qt6-svg-dev
# (OCCT is built from the pinned submodule; nothing else is needed for it,
# because every USE_* third-party option is off — see occt/VENDOR.md.)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

with_occt=1
occt_only=0
jobs="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
for arg in "$@"; do
  case "$arg" in
    --no-occt) with_occt=0 ;;
    --occt-only) occt_only=1 ;;
    -j*) jobs="${arg#-j}" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

occt_src="$repo/backend/occt/upstream"
occt_build="$repo/backend/occt/build-occt-linux"
occt_install="$repo/backend/occt/install-linux"
out="$repo/frontend/build/native"

say() { printf '\n=== %s ===\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. OCCT
#
# Flags identical to .github/workflows/occt-build.yml's OCCT_COMMON_FLAGS, with
# one addition: position-independent code, because unlike the iOS build this
# one links the static toolkits INTO a shared library, and a non-PIC .a cannot
# go into a .so on x86-64.
#
# Skipped when the install tree is already there. OCCT is pinned to a tag (see
# backend/occt/VENDOR.md), so a present tree is by construction the right one;
# delete backend/occt/install-linux to force a rebuild.
# ---------------------------------------------------------------------------
if [ "$with_occt" = 1 ]; then
  if [ -f "$occt_install/lib/libTKernel.a" ] || [ -f "$occt_install/lib/libTKernel.so" ]; then
    say "OCCT already installed in $occt_install — skipping"
  else
    if [ ! -f "$occt_src/CMakeLists.txt" ]; then
      say "fetching the OCCT submodule"
      git -C "$repo" submodule update --init --depth 1 -- backend/occt/upstream
    fi
    say "configuring OCCT (static, no third-party)"
    cmake -S "$occt_src" -B "$occt_build" -G Ninja \
      -DINSTALL_DIR="$occt_install" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DBUILD_LIBRARY_TYPE=Static \
      -DBUILD_MODULE_FoundationClasses=ON \
      -DBUILD_MODULE_ModelingData=ON \
      -DBUILD_MODULE_ModelingAlgorithms=ON \
      -DBUILD_MODULE_DataExchange=ON \
      -DBUILD_MODULE_ApplicationFramework=OFF \
      -DBUILD_MODULE_Visualization=OFF \
      -DBUILD_MODULE_Draw=OFF \
      -DBUILD_MODULE_DETools=OFF \
      -DBUILD_DOC_Overview=OFF \
      -DUSE_FREETYPE=OFF -DUSE_TK=OFF -DUSE_XLIB=OFF -DUSE_FREEIMAGE=OFF \
      -DUSE_OPENVR=OFF -DUSE_FFMPEG=OFF -DUSE_RAPIDJSON=OFF -DUSE_DRACO=OFF \
      -DUSE_TBB=OFF -DUSE_VTK=OFF
    say "building OCCT (this is the long one)"
    cmake --build "$occt_build" -j"$jobs"
    cmake --install "$occt_build"
  fi
fi
[ "$occt_only" = 1 ] && { say "OCCT only — done"; exit 0; }

# ---------------------------------------------------------------------------
# 2. The kernel library
# ---------------------------------------------------------------------------
say "configuring the kernel library"
cmake_args=(
  -S "$repo/backend/desktop" -B "$out" -G Ninja
  -DCMAKE_BUILD_TYPE=Release
)
if [ "$with_occt" = 1 ]; then
  cmake_args+=(-DPROTOTYPE_WITH_OCCT=ON -DCMAKE_PREFIX_PATH="$occt_install")
else
  cmake_args+=(-DPROTOTYPE_WITH_OCCT=OFF)
fi
cmake "${cmake_args[@]}"

say "building the kernel library"
cmake --build "$out" -j"$jobs"

# ---------------------------------------------------------------------------
# 3. The gate
#
# Not optional and not "nice to have". Everything that can go wrong with this
# library is invisible at link time — an archive that contributed no objects, a
# version script that hid what it should have exported, a forgotten
# --whole-archive — and every one of them produces a .so the app reports as
# simply missing. The verdict is the MARKER in the output, not the exit code:
# a process that dies inside a kernel exits non-zero for reasons that say
# nothing about how far it got.
# ---------------------------------------------------------------------------
say "smoke: dlopen + one call into each kernel"
smoke_log="$out/native-smoke.log"
"$out/prototype_native_smoke" "$out/libprototype_native.so" 2>&1 | tee "$smoke_log" || true
if ! grep -q "NATIVE SMOKE: PASS" "$smoke_log"; then
  echo "NATIVE BUILD: FAIL (smoke did not pass — see $smoke_log)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. The runtime closure
#
# Qt is linked SHARED (it is LGPL, and a static Qt would put the relinking
# obligation on every user of the resulting binary). So whatever the library
# needs at run time has to travel with it, or the bundle only runs on the
# machine that built it.
#
# WHAT TRAVELS, AND WHAT MUST NOT.
#
# `ldd` on the finished library lists the whole transitive closure — about
# thirty entries. Copying all of them is wrong in two directions:
#
#   * The base system's own — glibc, libstdc++, libgcc, libm, the loader —
#     must come from the HOST. Ship them and the bundle stops booting on any
#     distribution whose kernel or loader is newer than the build machine's.
#   * The GRAPHICS stack — libEGL, libGL, libX11, libwayland — must come from
#     the host too, and for a sharper reason: those libraries are the user's
#     GPU driver's entry points. A bundled libEGL loads the bundle's idea of a
#     driver interface against the host's actual driver, and the failure is a
#     black window rather than a missing symbol.
#
# Copying only libQt6* — which is what this did until the CI runner caught it
# — is wrong in the other direction, and the comment that justified it was
# simply untrue: "everything else Qt pulls in is base-system furniture on any
# desktop that can run a GTK app". It is not. `libmd4c`, `libdouble-conversion`,
# `libpcre2-16` (GTK brings the 8-bit one), `libb2`, ICU and `libproxy` arrive
# as dependencies OF QT and of nothing else, so a machine with the full GTK
# stack and no Qt cannot dlopen the library at all. It fell back to the Dart
# engine, silently, exactly as it would on a user's machine.
#
# So the rule is the closure MINUS a denylist, rather than an allowlist of one
# name: everything Qt drags in travels, and the three families that must be the
# host's stay behind. Getting the denylist wrong now fails the build (see the
# closure check below) rather than shipping a bundle that quietly degrades.
#
# The third family in the denylist is GTK's own stack. Those are not "system"
# in the loader's sense, but this is a GTK app: they are in the process before
# the kernels are dlopen'd, and one soname means one copy — bundling a second
# is at best dead weight and at worst two initialisations of one library.
#
# WHY THERE IS A TLS STACK IN A CAD BUNDLE. libQt6Network has libproxy in its
# DT_NEEDED, libproxy has its backend, and the backend has libcurl, which has
# gnutls, openssl, ldap, ssh and the rest. The app never opens a socket — the
# QCAD core links Qt Network and never calls it — but DT_NEEDED is resolved at
# LOAD time, so the loader wants all of it present before the first symbol is
# looked up. Nothing here can prune that except dropping Qt Network from the
# QCAD core, which is a change to what the kernel links, not to what ships. So
# it travels, and the deps tree is ~75 MB rather than ~20.
say "collecting the runtime closure"
deps="$out/deps"
rm -rf "$deps"
mkdir -p "$deps"

# Matched against the SONAME. Anything not matched here travels in deps/.
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
  cp -L "$path" "$deps/$name"
  copied=$((copied + 1))
done < <(ldd "$out/libprototype_native.so")
echo "copied $copied libraries into $deps ($(du -sh "$deps" | cut -f1))"

# THE INVARIANT, checked rather than reasoned about.
#
# Every library that ships has to be satisfiable from the bundle plus the host
# families above. This is the check the "Qt and only Qt" filter never had, and
# it is the difference between a bundle that runs on the machine that built it
# and one that runs anywhere: the build machine has Qt's dependencies installed
# because it just built against Qt, and nothing about `ldd` succeeding there
# says anything about a machine that does not.
say "checking the closure is complete"
unsatisfied=0
for lib in "$out/libprototype_native.so" "$deps"/*.so*; do
  [ -f "$lib" ] || continue
  while read -r need; do
    [ -e "$deps/$need" ] && continue
    printf '%s' "$need" | grep -Eq "$host_only" && continue
    echo "  MISSING: $(basename "$lib") needs $need — neither bundled nor a host library"
    unsatisfied=$((unsatisfied + 1))
  done < <(objdump -p "$lib" | awk '/NEEDED/{print $2}')
done
if [ "$unsatisfied" -ne 0 ]; then
  echo "CLOSURE: FAIL ($unsatisfied unsatisfied)"
  exit 1
fi
echo "CLOSURE: PASS"

say "done"
echo "library : $out/libprototype_native.so"
echo "size    : $(du -h "$out/libprototype_native.so" | cut -f1)"
echo
echo "Next:  cd frontend && flutter build linux --release"
echo "       (frontend/linux/CMakeLists.txt picks the library up from $out)"
