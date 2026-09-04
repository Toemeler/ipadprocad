Vendored from https://github.com/qcad/qcad @ 11f76756577a987955d4e11186acc05a427fba3d
Directories: src/core, src/entity, src/operations, src/io, src/snap, src/spatialindex, src/3rdparty
License: GPLv3 (see LICENSE.txt, gpl-3.0.txt, gpl-3.0-exceptions.txt)
Only headless-relevant subsystems included; gui, run, scripts (JS action layer) intentionally excluded — added in Phase 2.

Local changes to the vendored CMake files, all of one kind: the five
`if(WIN32) set(RC *.rc)` lines (src/core, src/entity, src/operations,
src/io/dxf, src/3rdparty/dxflib) are commented out. They add a Windows
resource script carrying DLL version metadata to targets that are STATIC
libraries here, so nothing ever links it out; three of the scripts also
`#include "../../shared.rc"`, which lives at the QCAD repo root and is
therefore outside the vendored `src/` scope — on MSVC that is a hard
`C1083`. The shim DLL built by backend/desktop carries the version
metadata a Windows build actually ships.
