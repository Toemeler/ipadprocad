# Vendored: libslvs (SolveSpace geometric constraint solver)

## What
`libslvs/` is the isolated constraint solver from **SolveSpace**, i.e. the
solver core with the SolveSpace CAD application stripped away. It exposes a
plain **C API** in `libslvs/include/slvs.h` (`Slvs_System`, `Slvs_Solve`,
`Slvs_MakeConstraint`, ...).

## Why (path B)
QCAD is a non-parametric drafter and has **no constraint solver** (the QCAD
maintainer has stated there are no plans for parametric constraints). So the
Inventor-style behaviour this project wants — coincident/parallel/etc.,
driving dimensions, over-constraint rejection, and **degrees-of-freedom
analysis** for the fully-constrained (white) vs under-constrained (violet)
colouring — has to come from a real geometric constraint solver.

Division of labour:
- **QCAD** — geometry primitives, DXF load/save, geometry for rendering.
- **libslvs** — constraints, solving, DOF. (Replaces the hand-rolled
  Levenberg-Marquardt in `frontend/lib/solver.dart` once the FFI shim lands.)

`slvs.h` natively provides everything needed: `SLVS_C_POINTS_COINCIDENT`,
`SLVS_C_PT_ON_LINE`, `SLVS_C_HORIZONTAL/VERTICAL`, `SLVS_C_PARALLEL`,
`SLVS_C_PERPENDICULAR`, `SLVS_C_DIAMETER`, `SLVS_C_ANGLE`,
`SLVS_C_ARC_LINE_TANGENT`, `SLVS_C_EQUAL_*`, `SLVS_C_SYMMETRIC*`,
`SLVS_C_WHERE_DRAGGED` (live grip pinning), plus `Slvs_System.dof`,
`.result`, and `.failed[]`/`.faileds` (over-constraint list).

## Source
Isolated build from https://github.com/JacobStoren/SolveSpaceLib
(upstream: https://github.com/solvespace/solvespace). No external
dependencies — C++ standard library only (no Qt, no Eigen).

## License
**GPLv3**, matching QCAD's GPLv3 already used in `backend/qcad-core`.
See `libslvs/LICENSE`.

## Build
- Host smoke:  `cmake -S . -B build -DSLVS_SMOKE=ON && cmake --build build && ./build/slvs_smoke`
- iOS static:  `cmake -S . -B build-ios -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 && cmake --build build-ios`

CI: `.github/workflows/slvs-build.yml`.

## Status / next
- [x] Vendored, builds static on host, solver smoke passes (rectangle forced
      square by H/V, driving width dimension = 50, point-on-line satisfied,
      DOF reported).
- [ ] iOS arm64 static link verified in CI (this push).
- [ ] Thin C shim `slvs_shim.{h,cpp}`: flat-array "solve this sketch → params
      + dof" surface for Dart FFI.
- [ ] Dart FFI bindings + swap `solveConstraints`/`analyzeSketch` to libslvs
      (polylines decomposed to points+segments, solved, re-assembled).
- [ ] DOF → entity colouring (blue selected / white fully-defined / violet
      under-defined) and Inventor-style live dimension preview.
