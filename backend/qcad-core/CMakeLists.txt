cmake_minimum_required(VERSION 3.16)

# Headless-only build of the QCAD core libraries, vendored from
# https://github.com/qcad/qcad (see VENDOR.md for commit + scope).
# Excludes gui, run, and the scripts/ JS action layer — those are
# Phase 2 (M4/M5) concerns, not needed for the pure C++ core.

option(BUILD_QT6 "Build against Qt6" ON)

project(qcadcore_headless LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The static 3rd-party lib (dxflib) is linked into shared libraries (libqcaddxf
# etc.). On Linux that requires all objects to be position-independent; enable
# PIC for every target here (no-op on iOS/arm64, where code is always PIC).
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# M1 headless scope, applied to every subdirectory:
#  - QCAD_HEADLESS  guards out the QtWidgets-coupled code paths in core/
#    (menu/toolbar wiring, widget helpers). Reintroduced in Phase 2 (M4/M5).
#  - R_NO_OPENNURBS builds RSpline against its opennurbs-free fallback, so the
#    core needs no vendored opennurbs (which itself bundles zlib + freetype,
#    ~430 files). Re-enabling NURBS-backed splines later is isolated to RSpline:
#    vendor src/3rdparty/opennurbs and drop this define.
add_compile_definitions(QCAD_HEADLESS R_NO_OPENNURBS)

add_subdirectory(src/3rdparty/dxflib)
# src/spatialindex builds the optional "Navel" R-tree backend, which needs the
# unvendored libspatialindex (src/3rdparty/spatialindexnavel). Nothing in the
# headless core links it: RDocumentInterface uses the self-contained
# RSpatialIndexSimple (in src/core) instead. Re-enable by vendoring
# spatialindexnavel and uncommenting this line.
#add_subdirectory(src/spatialindex)
# src/snap is the interaction-layer snapping toolset (snap-to-grid/endpoint/etc.),
# used by the UI, not by the headless core. It is a leaf target (nothing links it)
# and depends on qcadgrid (src/grid), which is not vendored. Both belong to the
# touch/Pencil interaction milestone; re-enable by vendoring src/grid + src/snap
# and uncommenting this line.
#add_subdirectory(src/snap)
add_subdirectory(src/operations)
add_subdirectory(src/io)
add_subdirectory(src/entity)
add_subdirectory(src/core)
# M2: C-ABI wrapper (extern "C") over the static core, for Dart FFI / iOS.
add_subdirectory(src/capi)
