cmake_minimum_required(VERSION 3.13)
project(ipadprocad_slvs CXX C)

# ---------------------------------------------------------------------------
# Vendored SolveSpace constraint solver (libslvs), built as a STATIC library
# for linking into the Flutter iOS app via a thin C shim (later milestone).
# QCAD stays the geometry/DXF store; libslvs owns constraints + DOF.
#
# libslvs has NO external dependencies (no Qt, no Eigen) — just the C++
# standard library — so the iOS cross-compile is a plain static build with
# the usual -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64.
# ---------------------------------------------------------------------------

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SLVS_DIR ${CMAKE_CURRENT_LIST_DIR}/libslvs)

add_library(slvs STATIC
    ${SLVS_DIR}/constrainteq.cpp
    ${SLVS_DIR}/entity.cpp
    ${SLVS_DIR}/expr.cpp
    ${SLVS_DIR}/system.cpp
    ${SLVS_DIR}/util.cpp
    ${SLVS_DIR}/lib.cpp
    ${SLVS_DIR}/SolveSpaceSystem.cpp
    ${SLVS_DIR}/platform/unixutil.cpp
    ${CMAKE_CURRENT_LIST_DIR}/shim/slvs_shim.cpp)

target_include_directories(slvs
    PUBLIC  ${SLVS_DIR}/include ${CMAKE_CURRENT_LIST_DIR}/shim
    PRIVATE ${SLVS_DIR})

target_compile_definitions(slvs PRIVATE -DLIBRARY)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(slvs PRIVATE -Wno-missing-field-initializers)
endif()

# Host-only runnable smoke test: solves a constrained rectangle and prints
# result + DOF (see tests/slvs_smoke.c). Never built for the iOS target.
option(SLVS_SMOKE "Build the host smoke-test executables" OFF)
if(SLVS_SMOKE)
    add_executable(slvs_smoke ${CMAKE_CURRENT_LIST_DIR}/tests/slvs_smoke.c)
    target_link_libraries(slvs_smoke PRIVATE slvs)
    target_include_directories(slvs_smoke PRIVATE ${SLVS_DIR}/include)

    # Exercises the FFI shim through its flat C API (the surface Dart calls).
    add_executable(shim_test ${CMAKE_CURRENT_LIST_DIR}/tests/shim_test.c)
    target_link_libraries(shim_test PRIVATE slvs)
    target_include_directories(shim_test PRIVATE ${CMAKE_CURRENT_LIST_DIR}/shim)
endif()
