cmake_minimum_required(VERSION 3.16)
project(ipadprocad_occt CXX C)

# ---------------------------------------------------------------------------
# iPadProCAD OCCT layer: a thin, flat C shim (occt_capi) built as a STATIC
# library over an already-built OpenCASCADE, for linking into the Flutter iOS
# app via FFI in a LATER session. Mirrors backend/slvs/CMakeLists.txt.
#
# Unlike libslvs, OCCT is far too big to build via add_subdirectory here, so
# this project CONSUMES an OCCT install tree produced from the pinned
# submodule in ./upstream (see VENDOR.md for the exact configure lines):
#
#   host : cmake -S upstream -B build-occt-host  <flags> && install
#   iOS  : cmake -S upstream -B build-occt-ios   <flags> && install
#
# then point this project at it with
#   -DCMAKE_PREFIX_PATH=<occt install dir>
# ---------------------------------------------------------------------------

set(CMAKE_CXX_STANDARD 17)          # OCCT 7.9 requires C++17
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCASCADE CONFIG REQUIRED)
message(STATUS "OpenCASCADE ${OpenCASCADE_VERSION} from ${OpenCASCADE_DIR}")

add_library(occt_capi STATIC shim/occt_capi.cpp)

target_include_directories(occt_capi
    PUBLIC  ${CMAKE_CURRENT_LIST_DIR}/shim
    PRIVATE ${OpenCASCADE_INCLUDE_DIR})

# Direct dependencies only — the imported targets from OpenCASCADEConfig
# carry their transitive toolkit closure (TKernel..TKShHealing etc.), and
# CMake orders the final link line topologically for GNU ld on the host.
target_link_libraries(occt_capi PUBLIC
    TKDESTEP    # STEPControl_* reader/writer
    TKPrim      # BRepPrimAPI_* box/cylinder/prism
    TKBO        # BRepAlgoAPI_Fuse
    TKTopAlgo   # BRepBuilderAPI_*, BRepCheck, BRepGProp, BRepBndLib
    TKBRep      # TopoDS/TopExp/TopTools
    TKMath      # gp, GProp, Bnd
    TKernel)

# Host-only runnable smoke test (the real "does OCCT hold up" gate); never
# built for the iOS target — same pattern as SLVS_SMOKE in backend/slvs.
option(OCCT_SMOKE "Build the host smoke-test executable" OFF)
if(OCCT_SMOKE)
    find_package(Threads REQUIRED)
    add_executable(occt_smoke tests/smoke_occt.c)
    target_link_libraries(occt_smoke PRIVATE occt_capi
        Threads::Threads ${CMAKE_DL_LIBS})
endif()
