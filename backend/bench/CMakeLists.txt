cmake_minimum_required(VERSION 3.16)
project(kernel_bench CXX C)

# ---------------------------------------------------------------------------
# Lane C — headless kernel benchmark (OPTIMIZATION_PLAN.md §5, Session 1).
#
# Standalone-configurable, so the fastest loop stays one command:
#
#   cmake -S backend/bench -B build-bench -G Ninja \
#         -DCMAKE_BUILD_TYPE=Release \
#         -DCMAKE_PREFIX_PATH=<occt install tree>
#   cmake --build build-bench -j
#   ./build-bench/occt_bench --md bench-out/kernel-bench.md
#
# It pulls in backend/occt/CMakeLists.txt for the `occt_capi` target rather
# than compiling the shim itself: the benchmark must measure the SAME
# translation unit the app links, with the same flags, or its numbers describe
# a different program. It does not modify that file — Session 2 owns the shim.
#
# CMAKE_BUILD_TYPE MUST be Release. A debug OCCT is a different kernel with
# different asymptotics (containers gain bounds checks), and the calibration
# in §6.5 was taken against a Release build; the check below refuses anything
# else rather than let a Debug run be quoted as a measurement.
# ---------------------------------------------------------------------------

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
if(NOT CMAKE_BUILD_TYPE STREQUAL "Release"
   AND NOT CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    message(FATAL_ERROR
        "CMAKE_BUILD_TYPE is '${CMAKE_BUILD_TYPE}'. Lane C is calibrated "
        "against a Release kernel (PERFORMANCE_PROFILE.md §6.5); a Debug "
        "build measures a different program. Configure with Release.")
endif()

# The shim target. Reachable whether this is configured standalone or through
# backend/CMakeLists.txt, in which case occt_capi already exists.
if(NOT TARGET occt_capi)
    add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/../occt occt-shim)
endif()

add_executable(occt_bench
    bench_occt.cpp
    bench_stats.cpp
    bench_alloc.cpp
    bench_sweep.cpp)

target_link_libraries(occt_bench PRIVATE occt_capi)

# bench_sweep.cpp is the one file here that talks to OCCT directly instead of
# through the C shim. It has to: the sweep's cost lives inside ONE C call, and
# the only way to say which of that call's five internal steps is expensive —
# or to vary the corner deadband BRepOffsetAPI_MakePipeShell hard-codes — is to
# rebuild the pipeline out of the same classes. occt_capi keeps the OCCT
# include path PRIVATE (it is a shim, and nothing else should need it), so this
# target asks for it itself. The toolkits arrive transitively from occt_capi's
# PUBLIC link line; only the headers are missing.
find_package(OpenCASCADE CONFIG REQUIRED)
target_include_directories(occt_bench PRIVATE ${OpenCASCADE_INCLUDE_DIR})

find_package(Threads REQUIRED)
target_link_libraries(occt_bench PRIVATE Threads::Threads ${CMAKE_DL_LIBS})

# ---------------------------------------------------------------------------
# Allocation accounting — see backend/bench/bench_alloc.h for why this exists
# and why two mechanisms are needed. Neither is trusted on the strength of the
# platform check alone: bench_alloc.cpp self-tests at startup and reports the
# columns as "n/a" if the counters did not move, so a wrong guess here
# degrades the report rather than corrupting it.
# ---------------------------------------------------------------------------
include(CheckCXXSourceCompiles)

if(APPLE)
    target_compile_definitions(occt_bench PRIVATE BENCH_ALLOC_APPLE_ZONE)
    set(BENCH_ALLOC_MECH "apple zone (malloc defined in the executable)")
else()
    # --wrap is a GNU ld / lld feature. Probe it rather than assume it: a
    # toolchain without it must still produce a working benchmark.
    set(CMAKE_REQUIRED_LINK_OPTIONS "-Wl,--wrap=malloc")
    check_cxx_source_compiles(
        "#include <cstdlib>\n
         extern \"C\" void *__real_malloc(size_t);\n
         extern \"C\" void *__wrap_malloc(size_t n){return __real_malloc(n);}\n
         int main(){ return std::malloc(1) ? 0 : 1; }"
        BENCH_HAVE_LD_WRAP)
    unset(CMAKE_REQUIRED_LINK_OPTIONS)
    if(BENCH_HAVE_LD_WRAP)
        target_compile_definitions(occt_bench PRIVATE BENCH_ALLOC_WRAP)
        target_link_options(occt_bench PRIVATE
            -Wl,--wrap=malloc -Wl,--wrap=free
            -Wl,--wrap=calloc -Wl,--wrap=realloc)
        set(BENCH_ALLOC_MECH "ld --wrap")
    else()
        set(BENCH_ALLOC_MECH "none (linker has no --wrap; memory columns off)")
    endif()
endif()
message(STATUS "Lane C allocation accounting: ${BENCH_ALLOC_MECH}")

# The harness's own unit tests: the statistics must recover an exponent it is
# given analytically, exactly as ci/test_perf_tools.py checks the Python side.
# An uncalibrated instrument measuring with unchecked arithmetic is two
# unverified layers, and the profile spends §13.1 on what that costs.
option(BENCH_TESTS "Build the Lane C self-tests" ON)
if(BENCH_TESTS)
    add_executable(bench_stats_test bench_stats_test.cpp bench_stats.cpp)
    target_include_directories(bench_stats_test PRIVATE ${CMAKE_CURRENT_LIST_DIR})
    enable_testing()
    add_test(NAME bench_stats COMMAND bench_stats_test)
endif()

# ---------------------------------------------------------------------------
# S15 — the holed-sweep probe. NOT a Lane C scenario, deliberately: a rung
# here can take a quarter of an hour, and Lane C runs on every push. It answers
# the one question S14 §12.2 could only infer an answer to — whether the 25
# minutes it saw at 1200 segments was construction or verification — by timing
# those stages apart. See perf/findings/S15-holes.md §1.
# ---------------------------------------------------------------------------
option(BENCH_HOLE_PROBE "Build the S15 holed-sweep probe" OFF)
if(BENCH_HOLE_PROBE)
    add_executable(hole_probe hole_probe.cpp)
    target_link_libraries(hole_probe PRIVATE occt_capi Threads::Threads
                          ${CMAKE_DL_LIBS})
    target_include_directories(hole_probe PRIVATE ${OpenCASCADE_INCLUDE_DIR})
endif()
