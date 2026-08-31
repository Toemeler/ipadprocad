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
