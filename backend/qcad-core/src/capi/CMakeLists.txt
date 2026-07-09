cmake_minimum_required(VERSION 3.16)

# Shared build settings (QT_SHAREDPOINTER_TRACK_POINTERS to match the core ABI,
# APPLE deployment target, PIC). QCAD_HEADLESS / R_NO_OPENNURBS are inherited
# from the root CMakeLists via add_compile_definitions.
include(../../CMakeInclude.txt)

project(qcadcapi VERSION 0.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(${QT_VER} REQUIRED COMPONENTS Core Concurrent Gui Network Qml Svg Xml)
qt_standard_project_setup()

# NOTE: QCAD_DLL is deliberately NOT defined here. As a *consumer* of the static
# core libraries, the QCAD*_EXPORT macros must expand to empty (see
# src/core/core_global.h), which is exactly the !QCAD_DLL branch.

add_library(qcadcapi STATIC
    qcad_capi.cpp
    qcad_capi.h
)

# Public: the C header, so downstream (Dart FFI bundling / iOS) can find it.
target_include_directories(qcadcapi PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)
# Private: the QCAD core headers this wrapper is implemented against.
target_include_directories(qcadcapi PRIVATE
    ../../src/3rdparty
    ../../src/core
    ../../src/core/math
    ../../src/entity
    ../../src/operations
    ../../src/io/dxf
)

target_link_libraries(qcadcapi PUBLIC
    qcadcore
    qcadentity
    qcadoperations
    qcaddxf
    dxflib
    Qt::Core
    Qt::Concurrent
    Qt::Gui
    Qt::Network
    Qt::Qml
    Qt::Svg
    Qt::Xml
)

if (CMAKE_BUILD_TYPE STREQUAL "Release")
    set_target_properties(qcadcapi PROPERTIES
        ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../../release)
else()
    set_target_properties(qcadcapi PROPERTIES
        ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../../debug)
endif()

# ---------------------------------------------------------------------------
# Optional host-side smoke test (Linux/macOS). Proves the C ABI compiles as C,
# links against the whole static core, and round-trips a DXF at runtime.
# Not built on iOS (there is no link step for .a there).
# ---------------------------------------------------------------------------
option(QCAD_CAPI_SMOKE "Build the C-ABI smoke test executable" OFF)
if(QCAD_CAPI_SMOKE)
    add_executable(qcad_capi_smoke tests/smoke.c)
    # core/entity/operations have circular static-link references; wrap the
    # archives in a link group so the linker rescans them.
    target_link_libraries(qcad_capi_smoke PRIVATE
        -Wl,--start-group
        qcadcapi qcadcore qcadentity qcadoperations qcaddxf dxflib
        -Wl,--end-group
        Qt::Core Qt::Concurrent Qt::Gui Qt::Network Qt::Qml Qt::Svg Qt::Xml
    )
    set_target_properties(qcad_capi_smoke PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../../release)
endif()
