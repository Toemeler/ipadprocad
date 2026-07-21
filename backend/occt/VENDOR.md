# Vendored: OpenCASCADE Technology (OCCT) — 3D B-Rep + STEP kernel

## What
`upstream/` is a **git submodule** of Open CASCADE Technology, pinned to the
exact release tag **`V7_9_3`** (OCCT 7.9.3, released 2025-12-06 — the last
patch release of the mature 7.9 line). OCCT is the boundary-representation
(B-Rep) modelling kernel: solids, booleans, fillets, and the STEP/IGES
translators.

Unlike `backend/slvs` (small enough for a source drop), OCCT is ~7500 source
files; a submodule keeps the repo light while still pinning byte-exact
sources. CI fetches it shallowly at the pinned commit
(`git submodule update --init --depth 1 -- backend/occt/upstream`).

- Upstream repo: https://github.com/Open-Cascade-SAS/OCCT
- Pinned tag:    `V7_9_3` (see the gitlink of `upstream/` for the exact SHA)
- NOT pinned to 8.0.0: OCCT 8.0.0 shipped 2026-05-07 with a reworked CMake
  system and a reorganised source tree — exactly the churn you don't put
  under a brand-new shim. Revisit once 8.0.x has patch releases.

## Why
The app's Inventor-style roadmap needs real 3D part modelling on top of the
2D sketcher: extrude a constrained sketch profile into a solid, boolean it,
and exchange parts via STEP. OCCT is the **only mature open-source B-Rep +
STEP kernel** (it powers FreeCAD, KiCad's 3D exchange, CadQuery, Gmsh).

Division of labour stays as before, one kernel per job:
- **QCAD**    — 2D geometry primitives, DXF load/save (unchanged).
- **libslvs** — constraints, solving, DOF (unchanged).
- **OCCT**    — 3D B-Rep solids + STEP exchange (this directory).

## License
**LGPL 2.1 (only) with the OCCT exception** — see `upstream/LICENSE_LGPL_21.txt`
and `upstream/OCCT_LGPL_EXCEPTION.txt`. The exception explicitly permits
static linking into a larger work without extending copyleft to that work,
which is what the iOS build does. This is a *different* license from the
GPLv3 of qcad-core/libslvs; the exception text is why the combination is
fine for this app.

## Layout
```
backend/occt/
  upstream/            OCCT V7_9_3 (submodule — do not edit, ever)
  shim/occt_capi.{h,cpp}  flat C ABI over OCCT (14 functions, marker string
                          "iPadProCAD OCCT shim" for the CI link check)
  tests/smoke_occt.c   standalone C smoke test → "OCCT SMOKE: PASS"
  CMakeLists.txt       builds libocct_capi.a against an OCCT install tree
```

## Building OCCT itself (both CI jobs use exactly this)
Minimal static configuration. Only four modules are switched ON; OCCT's
CMake (`EXCTRACT_TOOLKIT_FULL_DEPS`) then auto-includes the toolkits from
disabled modules that the STEP translator needs as link-time dependencies
(TKCDF/TKLCAF/TKCAF/TKVCAF, TKService/TKV3d via TKXCAF ← TKDESTEP). With
`USE_FREETYPE=OFF` (+ all other `USE_*` off) those build with **zero
third-party dependencies** — C++17 standard library only, like libslvs.

```
cmake -S upstream -B build-occt \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_LIBRARY_TYPE=Static \
  -DINSTALL_DIR=$PWD/install \
  -DBUILD_MODULE_FoundationClasses=ON \
  -DBUILD_MODULE_ModelingData=ON \
  -DBUILD_MODULE_ModelingAlgorithms=ON \
  -DBUILD_MODULE_DataExchange=ON \
  -DBUILD_MODULE_ApplicationFramework=OFF \
  -DBUILD_MODULE_Visualization=OFF \
  -DBUILD_MODULE_Draw=OFF \
  -DBUILD_MODULE_DETools=OFF \
  -DBUILD_DOC_Overview=OFF \
  -DUSE_FREETYPE=OFF -DUSE_TK=OFF -DUSE_XLIB=OFF -DUSE_FREEIMAGE=OFF \
  -DUSE_OPENVR=OFF -DUSE_FFMPEG=OFF -DUSE_RAPIDJSON=OFF -DUSE_DRACO=OFF \
  -DUSE_TBB=OFF -DUSE_VTK=OFF
cmake --build build-occt -j && cmake --install build-occt
```

iOS adds (same values the app/slvs builds use):
```
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
```

**iOS find_package trap:** `CMAKE_SYSTEM_NAME=iOS` makes CMake re-root every
`find_package` into the iPhoneOS SDK (`Darwin.cmake` sets
`CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY`), so the *shim* configure on iOS
must pass `-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH` or the OCCT install
tree is invisible despite a correct `CMAKE_PREFIX_PATH` (CI run 29807468644).

## Building the shim + smoke
```
cmake -S . -B build -DOCCT_SMOKE=ON -DCMAKE_PREFIX_PATH=$PWD/install
cmake --build build -j
./build/occt_smoke        # must print "OCCT SMOKE: PASS"
```

CI: `.github/workflows/occt-build.yml` (isolated: triggers only on
`backend/occt/**`, `.gitmodules` and itself). The iOS install tree is shared
with the `m5-flutter-ipa` job through an `actions/cache` entry keyed
`occt-ios-arm64-V7_9_3-r1` — bump the suffix when the configure flags change.

## Status / next
- [x] Vendored at `V7_9_3`, shim + smoke written, shim compile-checked
      against the real OCCT headers locally.
- [ ] Host smoke green in CI (box / L-extrude / cylinder / fuse / STEP
      roundtrip — read the "OCCT SMOKE:" marker, not the checkmark).
- [ ] iOS arm64 static cross-build green in CI, `_occt_*` symbols present.
- [ ] Linked into the Runner binary, "OCCT LINK CHECK: PASS" + 14 `_occt_*`
      symbols via nm (M5-style check).
- [ ] **Next session, not this one:** Dart FFI binding
      (`frontend/lib/ffi/occt_engine.dart`) + UI wiring. Nothing in Dart may
      reference OCCT yet.
