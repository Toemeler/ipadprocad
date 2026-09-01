# M298 — build the shim as a Cycles target, inside Cycles' own tree.
#
# Appended to intern/cycles/CMakeLists.txt by the probe workflow, after the
# copy that puts cycles_shim.* in intern/cycles/shim/.
#
# WHY, and it is not convenience. Run 4 tried to compile the shim with flags
# reverse-engineered out of the Xcode project and failed twice over: the
# namespace macros are COMMAND-LINE defines (`-DCCL_NAMESPACE_BEGIN=namespace
# ccl {`, from intern/cycles/CMakeLists.txt line 208) and arrived mangled by
# shell word-splitting, and `util/simd.h` includes <sse2neon.h> on arm64, which
# lives in Blender's extern/ and was not on the include path.
#
# Both are symptoms of the same mistake. Cycles' headers are configured by
# around two dozen WITH_* defines, and several of them change STRUCT LAYOUTS —
# so a set that is merely close enough to compile is worse than one that fails:
# it links and then misreads memory. Guessing them is not a thing worth getting
# right.
#
# add_definitions() and include_directories() are directory-scoped and apply to
# targets created after them in the same CMakeLists. Appending here therefore
# gives this target exactly what cycles_scene and cycles_session get, by
# construction, with nothing written down twice.
add_library(cycles_shim STATIC shim/cycles_shim.cpp)
target_include_directories(cycles_shim PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# M344 — and the denoiser, which is a second translation unit on purpose.
#
# It names no Cycles type and includes no Cycles header except `util/tbb.h`,
# and that one through `__has_include` so it is optional. Keeping it separate
# is what lets the host render test link it on its own and check, with hand-made
# buffers and no GPU, the one property that decides whether a denoiser is
# usable on a CAD render: that it does not blur an edge.
#
# Listed as a second source of the SAME target rather than as a library of its
# own, because it is one file with one caller and a second CMake target would
# be a second thing for three workflows to remember to build.
target_sources(cycles_shim PRIVATE shim/cycles_denoise.cpp)
