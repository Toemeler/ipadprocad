cmake_minimum_required(VERSION 3.16)

# Headless-only build of the QCAD core libraries, vendored from
# https://github.com/qcad/qcad (see VENDOR.md for commit + scope).
# Excludes gui, run, and the scripts/ JS action layer — those are
# Phase 2 (M4/M5) concerns, not needed for the pure C++ core.

option(BUILD_QT6 "Build against Qt6" ON)

project(qcadcore_headless LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(src/3rdparty/dxflib)
add_subdirectory(src/spatialindex)
add_subdirectory(src/snap)
add_subdirectory(src/operations)
add_subdirectory(src/io)
add_subdirectory(src/entity)
add_subdirectory(src/core)
