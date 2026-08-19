cmake_minimum_required(VERSION 3.16)
project(prototype_backend CXX C)

# ---------------------------------------------------------------------------
# Umbrella over the native layer, so one configure line reaches both the OCCT
# shim and the Lane C benchmark that measures it:
#
#   cmake -S backend -B build-backend -G Ninja \
#         -DCMAKE_BUILD_TYPE=Release \
#         -DCMAKE_PREFIX_PATH=<occt install tree>
#
# It exists only to compose; every setting still lives in the subproject that
# owns it. backend/qcad-core and backend/slvs are deliberately NOT included —
# they have their own workflows, their own toolchain requirements, and pulling
# them in here would make a kernel benchmark depend on Qt.
# ---------------------------------------------------------------------------

add_subdirectory(occt)
add_subdirectory(bench)
