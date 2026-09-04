# Prototype — build the CAD kernels for Windows.
#
# Produces, in <repo>\frontend\build\native (which is where
# frontend\windows\CMakeLists.txt looks and where native_lib.dart searches):
#
#   prototype_native.dll   QCAD C-API + libslvs shim + OCCT shim
#   deps\                  Qt and its plugins, in the layout Qt expects
#   native-smoke.log       the verdict of the load-and-call gate
#
#   tools\desktop\build_native_windows.ps1
#   tools\desktop\build_native_windows.ps1 -NoOcct     # 2D + solver only
#   tools\desktop\build_native_windows.ps1 -OcctOnly   # just (re)build OCCT
#
# WHAT IT WANTS FROM THE MACHINE
#   * A Visual Studio 2022 build environment on PATH (a "x64 Native Tools"
#     prompt, or run after `Launch-VsDevShell.ps1 -Arch amd64`). cl.exe, link
#     and dumpbin all have to be reachable — the last one because the DLL's
#     export list is DERIVED from the archives rather than written down; see
#     backend\desktop\windows_exports.cmake.
#   * CMake and Ninja.
#   * Qt 6 for MSVC, with qtsvg and qtdeclarative, findable through
#     CMAKE_PREFIX_PATH or the QT_ROOT_DIR environment variable.
#
# It is a SEPARATE step from `flutter build windows` for the reason the Linux
# script gives: OCCT is a long compile and the app has a defined behaviour
# without it, so putting it in front of every UI change would be wrong.
[CmdletBinding()]
param(
  [switch]$NoOcct,
  [switch]$OcctOnly,
  [string]$QtRoot = $env:QT_ROOT_DIR
)

$ErrorActionPreference = 'Stop'

function Say($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here '..\..')
$out = Join-Path $repo 'frontend\build\native'
$occtSrc = Join-Path $repo 'backend\occt\upstream'
$occtBuild = Join-Path $repo 'backend\occt\build-windows'
$occtInstall = Join-Path $repo 'backend\occt\install-windows'

foreach ($tool in @('cmake', 'ninja', 'cl', 'dumpbin')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "missing: $tool — run this from a x64 Native Tools prompt"
  }
}

# ---------------------------------------------------------------------------
# 1. OCCT
#
# The SAME flags as tools/desktop/build_native.sh and the iOS job: every USE_*
# off, four modules on. The shim is written against one configuration, and a
# platform that quietly turned a module on would be a platform with its own
# bugs. Skipped when the install tree is there — OCCT is pinned to a tag, so a
# present tree is by construction the right one.
# ---------------------------------------------------------------------------
if (-not $NoOcct) {
  if (Test-Path (Join-Path $occtInstall 'lib\TKernel.lib')) {
    Say "OCCT already installed in $occtInstall — skipping"
  } else {
    if (-not (Test-Path (Join-Path $occtSrc 'CMakeLists.txt'))) {
      Say 'fetching the OCCT submodule'
      git -C $repo submodule update --init --depth 1 -- backend/occt/upstream
    }
    Say 'configuring OCCT (static, no third-party)'
    cmake -S $occtSrc -B $occtBuild -G Ninja `
      "-DINSTALL_DIR=$occtInstall" `
      -DCMAKE_BUILD_TYPE=Release `
      -DBUILD_LIBRARY_TYPE=Static `
      -DBUILD_MODULE_FoundationClasses=ON `
      -DBUILD_MODULE_ModelingData=ON `
      -DBUILD_MODULE_ModelingAlgorithms=ON `
      -DBUILD_MODULE_DataExchange=ON `
      -DBUILD_MODULE_ApplicationFramework=OFF `
      -DBUILD_MODULE_Visualization=OFF `
      -DBUILD_MODULE_Draw=OFF `
      -DBUILD_MODULE_DETools=OFF `
      -DBUILD_DOC_Overview=OFF `
      -DUSE_FREETYPE=OFF -DUSE_TK=OFF -DUSE_XLIB=OFF -DUSE_FREEIMAGE=OFF `
      -DUSE_OPENVR=OFF -DUSE_FFMPEG=OFF -DUSE_RAPIDJSON=OFF -DUSE_DRACO=OFF `
      -DUSE_TBB=OFF -DUSE_VTK=OFF
    if ($LASTEXITCODE) { throw 'OCCT configure failed' }
    Say 'building OCCT (this is the long one)'
    cmake --build $occtBuild
    if ($LASTEXITCODE) { throw 'OCCT build failed' }
    cmake --install $occtBuild
    if ($LASTEXITCODE) { throw 'OCCT install failed' }
  }
}
if ($OcctOnly) { Say 'OCCT only — done'; exit 0 }

# ---------------------------------------------------------------------------
# 2. The kernel library
# ---------------------------------------------------------------------------
Say 'configuring the kernel library'
$prefix = @()
if (-not $NoOcct) { $prefix += $occtInstall }
if ($QtRoot) { $prefix += $QtRoot }
$args = @('-S', (Join-Path $repo 'backend\desktop'), '-B', $out, '-G', 'Ninja',
          '-DCMAKE_BUILD_TYPE=Release')
if ($NoOcct) {
  $args += '-DPROTOTYPE_WITH_OCCT=OFF'
} else {
  $args += '-DPROTOTYPE_WITH_OCCT=ON'
}
if ($prefix.Count) { $args += "-DCMAKE_PREFIX_PATH=$($prefix -join ';')" }
cmake @args
if ($LASTEXITCODE) { throw 'configure failed' }

Say 'building the kernel library'
cmake --build $out
if ($LASTEXITCODE) { throw 'build failed' }

# ---------------------------------------------------------------------------
# 3. What it needs at run time
#
# Windows has no rpath. A DLL's dependencies are searched in the directory of
# the EXE that loaded it, so Qt travels FLAT beside prototype.exe — and Qt's
# platform plugin is loaded by PATH rather than by import table, so it has to
# keep its `platforms\` subdirectory. windeployqt produces exactly that layout,
# which is why it is used rather than a copy of a list of names.
# ---------------------------------------------------------------------------
Say 'collecting the runtime closure'
$deps = Join-Path $out 'deps'
New-Item -ItemType Directory -Force -Path $deps | Out-Null
$windeployqt = if ($QtRoot) { Join-Path $QtRoot 'bin\windeployqt.exe' } else { 'windeployqt.exe' }
& $windeployqt --release --no-translations --no-compiler-runtime `
    --dir $deps (Join-Path $out 'prototype_native.dll')
if ($LASTEXITCODE) { throw 'windeployqt failed' }
Get-ChildItem -Recurse $deps | Select-Object FullName, Length | Format-Table

# ---------------------------------------------------------------------------
# 4. The gate
#
# Not optional. Everything that can go wrong with this library is invisible at
# link time — an archive that contributed no objects, a .def derived from the
# wrong file, a forgotten /WHOLEARCHIVE — and every one of them produces a DLL
# the app reports as simply missing. The verdict is the MARKER in the output,
# not the exit code.
# ---------------------------------------------------------------------------
Say 'smoke: load + one call into each kernel'
$log = Join-Path $out 'native-smoke.log'
$env:PATH = "$deps;$env:PATH"
& (Join-Path $out 'prototype_native_smoke.exe') (Join-Path $out 'prototype_native.dll') `
  2>&1 | Tee-Object -FilePath $log
if (-not (Select-String -Path $log -Pattern 'NATIVE SMOKE: PASS' -Quiet)) {
  throw "NATIVE BUILD: FAIL (smoke did not pass — see $log)"
}

Say 'done'
Write-Host "library : $(Join-Path $out 'prototype_native.dll')"
Write-Host "Next:  cd frontend; flutter build windows --release"
