cmake_minimum_required(VERSION 3.16)
project(prototype_native CXX C)

# ---------------------------------------------------------------------------
# THE DESKTOP KERNEL LIBRARY
#
# One shared library holding all three kernels the app calls through FFI:
#
#   QCAD core + C-API   2D geometry, layers, DXF          (backend/qcad-core)
#   libslvs + shim      constraints, DOF                  (backend/slvs)
#   OCCT + shim         3D B-Rep, booleans, STEP, meshes  (backend/occt)
#
# WHY A LIBRARY AND NOT A LINK INTO THE APP
# -----------------------------------------
# On iOS these are static archives and the CI links them straight into the
# Runner binary, which is why every FFI facade starts from
# `DynamicLibrary.process()`. A Flutter desktop app has no such link step that
# we own: `flutter build linux` compiles a runner from a template and we do not
# get to add archives to it without forking that template. So the desktop
# builds ONE .so, ships it in the bundle's lib/, and dlopens it by name. See
# frontend/lib/ffi/native_lib.dart, which knows the search order, and
# frontend/linux/CMakeLists.txt, which installs what this produces.
#
# WHY ONE LIBRARY AND NOT THREE
# -----------------------------
# The three kernels are not independent at run time: occt_capi and qcad_capi
# both drag in a C++ runtime and both are reached from the same isolate, and
# three libraries would mean three dlopens, three search failures to diagnose
# and three chances for a partial install to look like a working one. One
# library has one answer: it is there, or the app runs on its Dart fallbacks.
# (Cycles stays separate — see NativeLib.cycles for why.)
#
# WHAT IT EXPORTS
# ---------------
# Only qcad_*, slvs_* and occt_*, enforced by prototype_native.map. Everything
# else — Qt, OCCT, the QCAD core — is statically linked in and hidden. See the
# map file for why that is not merely tidiness.
#
# USAGE
#   cmake -S backend/desktop -B build/native -G Ninja \
#         -DCMAKE_BUILD_TYPE=Release \
#         -DCMAKE_PREFIX_PATH=<occt install tree>
#   cmake --build build/native
#
# tools/desktop/build_native.sh does all of that, including OCCT itself.
# ---------------------------------------------------------------------------

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Building the 3D kernel is what makes this a forty-minute job rather than a
# four-minute one, and the app has a defined behaviour without it (no 3D
# kernel, reported as such). So it is a switch — off it, `flutter run` gets the
# real 2D engine and the real solver in a few minutes.
option(PROTOTYPE_WITH_OCCT "Include the OCCT 3D kernel" ON)

# ---------------------------------------------------------------------------
# The kernels, each built by the CMakeLists that already owns it. None of these
# files is modified for the desktop: the iOS build configures the same three
# subprojects with the same options, which is the point.
# ---------------------------------------------------------------------------
add_subdirectory(../qcad-core qcad-core)
add_subdirectory(../slvs slvs)
if(PROTOTYPE_WITH_OCCT)
  add_subdirectory(../occt occt)
endif()

add_library(prototype_native SHARED prototype_native.cpp)

# --whole-archive on the three SHIMS, and only on them.
#
# A static archive contributes only the objects something references, and
# nothing in this library references the C API — the callers are in another
# process image entirely (the Dart isolate, through dlsym). Without this the
# .so links cleanly, exports nothing, and every FFI probe reports "symbols not
# linked", which reads exactly like a missing library.
#
# The kernels UNDER the shims are deliberately left as ordinary archives: they
# are pulled in by what the shims actually call, and whole-archiving OCCT would
# add a few hundred megabytes of unreachable toolkit code to the result.
set(PROTOTYPE_SHIMS qcadcapi slvs)
if(PROTOTYPE_WITH_OCCT)
  list(APPEND PROTOTYPE_SHIMS occt_capi)
endif()

target_link_libraries(prototype_native PRIVATE
  -Wl,--whole-archive ${PROTOTYPE_SHIMS} -Wl,--no-whole-archive)

# The QCAD core's three archives reference each other in a cycle, which GNU ld
# only resolves inside a group. (Apple's ld64 resolves it by itself and rejects
# the flags, which is why qcad-core/src/capi/CMakeLists.txt branches on APPLE
# for its own smoke test — the same cycle, the same fix.)
target_link_libraries(prototype_native PRIVATE
  -Wl,--start-group qcadcore qcadentity qcadoperations qcaddxf dxflib -Wl,--end-group)

find_package(Qt6 REQUIRED COMPONENTS Core Concurrent Gui Network Qml Svg Xml)
target_link_libraries(prototype_native PRIVATE
  Qt6::Core Qt6::Concurrent Qt6::Gui Qt6::Network Qt6::Qml Qt6::Svg Qt6::Xml)

find_package(Threads REQUIRED)
target_link_libraries(prototype_native PRIVATE Threads::Threads ${CMAKE_DL_LIBS})

# Hide everything the map file does not name.
#
# The version script and NOTHING ELSE. `--exclude-libs,ALL` looks like it
# belongs here and is actively wrong: it makes every symbol that came out of a
# static archive local BEFORE versioning runs, and since all four C APIs come
# out of static archives, the result is a library that exports nothing at all —
# which links cleanly, loads cleanly, and answers no symbol the app asks for.
# (Measured, not assumed: the first build with both flags exported 0 symbols
# and the dlopen smoke below caught it.)
set(PROTOTYPE_VERSION_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/prototype_native.map")
target_link_options(prototype_native PRIVATE
  "-Wl,--version-script=${PROTOTYPE_VERSION_SCRIPT}")
set_target_properties(prototype_native PROPERTIES
  LINK_DEPENDS "${PROTOTYPE_VERSION_SCRIPT}"
  # No "lib" games and no SONAME version suffix: native_lib.dart opens this by
  # an exact file name, and a versioned soname would make the file it finds
  # differ from the file the bundle installed.
  OUTPUT_NAME "prototype_native"
  # $ORIGIN, so the Qt libraries that travel in the bundle are found NEXT TO
  # this file. It is dlopen'd, not linked into the runner, so the runner's own
  # rpath ($ORIGIN/lib, set by the Flutter template) does not apply to it and
  # the loader would otherwise only look at the system's Qt. Falls through to
  # the system harmlessly during development, where the build directory has no
  # Qt in it.
  BUILD_RPATH "$ORIGIN"
  INSTALL_RPATH "$ORIGIN")

if(NOT PROTOTYPE_WITH_OCCT)
  target_compile_definitions(prototype_native PRIVATE PROTOTYPE_NO_OCCT)
endif()

# Where `flutter build linux` looks (frontend/linux/CMakeLists.txt's
# PROTOTYPE_NATIVE_DIR default), so a plain configure-and-build in build/native
# lands in the right place with nothing to copy.
set_target_properties(prototype_native PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

# ---------------------------------------------------------------------------
# The gate: a host executable that dlopens the finished library exactly the way
# Dart does and calls one function from each kernel.
#
# It exists because every failure this library can have is invisible from the
# link step. An archive that contributed no objects links fine. A version
# script with a typo links fine. A missing --whole-archive links fine. All
# three produce a .so that loads and answers nothing, and on the app side all
# three look identical to "no library at all".
# ---------------------------------------------------------------------------
option(PROTOTYPE_NATIVE_SMOKE "Build the dlopen smoke test" ON)
if(PROTOTYPE_NATIVE_SMOKE)
  add_executable(prototype_native_smoke smoke.c)
  target_link_libraries(prototype_native_smoke PRIVATE ${CMAKE_DL_LIBS})
  add_dependencies(prototype_native_smoke prototype_native)
  set_target_properties(prototype_native_smoke PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
endif()
