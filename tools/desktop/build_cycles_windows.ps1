# Prototype — the desktop path tracer, for Windows.
#
#   frontend\build\native\prototype_cycles.dll        the library the app opens
#   frontend\build\native\deps\                       the DLLs it needs to run
#   frontend\build\native\prototype_cycles_probe.exe  the gate, which also
#                                                     prints the device
#
#   pwsh tools/desktop/build_cycles_windows.ps1
#   pwsh tools/desktop/build_cycles_windows.ps1 -Keep   # keep blender\ after
#
# THE SAME BUILD AS LINUX, and deliberately so: the same Blender pin (read out
# of that script rather than repeated), the same three patches from
# backend/cycles/patches/, the same shim grafted as a Cycles target, the same
# WITH_* switches, and the link line taken from the same line of build.ninja.
# tools/desktop/build_cycles_linux.sh carries the reasoning for all of that and
# is the file to read. This one documents what is DIFFERENT, which is the last
# third — how a Windows library decides what it exports and how it finds its
# dependencies.
#
# WHAT IS DIFFERENT, and it is all in the linking and the loading
# ---------------------------------------------------------------
#   * A .def instead of a version script. GNU ld exports everything not named
#     in a `local:` clause; MSVC exports NOTHING unless asked. Same policy,
#     stated the other way round — and DERIVED from the shim's own archive
#     rather than written out, for the reason backend/desktop/
#     windows_exports.cmake gives for the kernels': a hand-kept list drifts.
#   * /WHOLEARCHIVE: instead of --whole-archive, and only on the shim.
#   * No --start-group. MSVC's linker resolves an archive set to a fixed point
#     by itself; GNU ld is the one that has to be told.
#   * No rpath, because Windows has none, and no ldd, because an import is
#     resolved by NAME beside the importing module. So the closure is a
#     dumpbin /DEPENDENTS walk done by hand, and everything travels FLAT into
#     the bundle's lib\ beside prototype_cycles.dll — which is exactly what
#     frontend/windows/CMakeLists.txt installs.
#   * No distribution fallback. The Linux script can build against Ubuntu's own
#     Embree, TBB, OpenImageIO and OpenEXR because a distribution HAS them;
#     getting five libraries to versions this Cycles accepts through vcpkg is a
#     second project. Here the precompiled set is required, and its absence is
#     an error rather than a lesser build.
param([switch]$Keep)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$here = Split-Path -Parent $PSCommandPath
$repo = (Resolve-Path (Join-Path $here '..\..')).Path
$out  = Join-Path $repo 'frontend\build\native'
if ($env:CYCLES_WORK_DIR) { $work = $env:CYCLES_WORK_DIR }
else { $work = Join-Path $repo 'backend\cycles\build-windows' }
if ($env:JOBS) { $jobs = $env:JOBS } else { $jobs = $env:NUMBER_OF_PROCESSORS }

# THE PIN IS READ OUT OF THE LINUX SCRIPT, not repeated here. Two platforms
# building two different Blenders against one shim is a bug that surfaces as a
# compile error months later, and the honest way to make it impossible is to
# have exactly one copy of the number.
$linuxScript = Get-Content (Join-Path $repo 'tools\desktop\build_cycles_linux.sh') -Raw
if ($env:BLENDER_REF) { $BLENDER_REF = $env:BLENDER_REF }
else { $BLENDER_REF = [regex]::Match($linuxScript, 'BLENDER_REF:-([0-9a-f]{40})').Groups[1].Value }
if ($env:BLENDER_BRANCH) { $BLENDER_BRANCH = $env:BLENDER_BRANCH }
else { $BLENDER_BRANCH = [regex]::Match($linuxScript, 'BLENDER_BRANCH:-([A-Za-z0-9_.-]+)').Groups[1].Value }
if ($env:BLENDER_REMOTE) { $BLENDER_REMOTE = $env:BLENDER_REMOTE }
else { $BLENDER_REMOTE = 'https://github.com/blender/blender.git' }
if (-not $BLENDER_REF -or -not $BLENDER_BRANCH) {
  throw "could not read the Blender pin out of tools/desktop/build_cycles_linux.sh"
}

function Say([string]$m) { Write-Host ''; Write-Host "=== $m ===" }

function Run([string]$exe, [string[]]$argv, [string]$log, [string]$what) {
  & $exe @argv *> $log
  if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED: $what"
    Get-Content $log -Tail 40 | ForEach-Object { Write-Host $_ }
    exit 1
  }
}

foreach ($tool in @('cmake', 'ninja', 'cl', 'link', 'dumpbin', 'git', 'python')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Write-Host "missing: $tool"
    Write-Host '  cl/link/dumpbin come from a Developer Command Prompt or from'
    Write-Host '  ilammy/msvc-dev-cmd; cmake and ninja from the Visual Studio'
    Write-Host '  installer or winget.'
    exit 1
  }
}

New-Item -ItemType Directory -Force -Path $work, $out | Out-Null
$blender = Join-Path $work 'blender'

# ---------------------------------------------------------------------------
# 1. Blender's tree and its precompiled dependencies
# ---------------------------------------------------------------------------
# --no-checkout, for the reason the Linux script sets out at length: the tree
# is under git-lfs, this build wants none of the large files, and a machine
# with git-lfs installed cannot then check the pinned commit out over what the
# clone's own checkout left behind.
$env:GIT_LFS_SKIP_SMUDGE = '1'
if (-not (Test-Path (Join-Path $blender '.git'))) {
  Say "cloning Blender ($BLENDER_BRANCH @ $($BLENDER_REF.Substring(0, 12)))"
  & git clone --no-checkout --depth 2 --branch $BLENDER_BRANCH $BLENDER_REMOTE $blender
  if ($LASTEXITCODE -ne 0) { throw 'could not clone Blender' }
  Push-Location $blender
  & git config --local lfs.fetchexclude '*'
  & git fetch --depth 1 origin $BLENDER_REF
  & git checkout --force $BLENDER_REF
  if ($LASTEXITCODE -ne 0) { & git checkout --force FETCH_HEAD }
  Pop-Location
}
Push-Location $blender; & git log --oneline -1; Pop-Location

# The directory EXISTING is not the test: make_update.py creates it and then
# fails to populate it when the host is unreachable, which looks like success
# and configures a build with no dependencies at all.
$libdir = Join-Path $blender 'lib\windows_x64'
function Test-Bundle {
  (Test-Path $libdir) -and
  (@(Get-ChildItem $libdir -ErrorAction SilentlyContinue).Count -gt 0)
}
if (-not (Test-Bundle)) {
  Say 'fetching the precompiled Windows dependency set'
  Push-Location $blender
  & python .\build_files\utils\make_update.py --no-blender
  Pop-Location
}
if (-not (Test-Bundle)) {
  Write-Host 'no lib\windows_x64 — the precompiled dependency set is REQUIRED on'
  Write-Host 'Windows (see the header). It comes from projects.blender.org through'
  Write-Host 'make_update.py, and needs git-lfs installed and that host reachable.'
  exit 1
}
$libGB = [math]::Round(
  (Get-ChildItem $libdir -Recurse -File | Measure-Object Length -Sum).Sum / 1GB, 1)
Write-Host "using Blender's precompiled set ($libGB GB)"

# ---------------------------------------------------------------------------
# 2. The shim, as a Cycles target inside Cycles' own tree
#
# See backend/cycles/shim/append.cmake for why it is grafted rather than
# compiled beside Cycles with flags copied out of the build.
# ---------------------------------------------------------------------------
Say 'grafting the shim'
$shimDir = Join-Path $blender 'intern\cycles\shim'
New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
Copy-Item -Force -Destination $shimDir -Path @(
  (Join-Path $repo 'backend\cycles\shim\cycles_shim.cpp'),
  (Join-Path $repo 'backend\cycles\shim\cycles_shim.h'),
  (Join-Path $repo 'backend\cycles\shim\cycles_denoise.cpp'),
  (Join-Path $repo 'backend\cycles\shim\cycles_denoise.h'))
# Idempotent: a second run must not append the block twice.
$cyclesCMake = Join-Path $blender 'intern\cycles\CMakeLists.txt'
if (-not (Select-String -Path $cyclesCMake -Pattern 'add_library\(cycles_shim' -Quiet)) {
  Add-Content -Path $cyclesCMake -Value ''
  Add-Content -Path $cyclesCMake -Value `
    (Get-Content (Join-Path $repo 'backend\cycles\shim\append.cmake'))
}

# The three patches. All self-verifying — an anchor that does not match exactly
# once fails rather than silently doing nothing — and all shared with the Linux
# build; the third is shared because the line it removes is in Blender's TOP
# LEVEL and fires wherever WITH_PYTHON is off. They address the tree as
# `blender\intern\cycles\...` relative to the working directory, so they run
# from $work.
Say 'patching Cycles (progressive sampling, denoiser ceiling, WITH_PYTHON)'
Push-Location $work
foreach ($p in @('progressive.py', 'oidn_memory.py', 'no_python_cycles.py')) {
  & python (Join-Path $repo "backend\cycles\patches\$p")
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw "patch failed: $p" }
}
Pop-Location

# ---------------------------------------------------------------------------
# 3. Configure and build
# ---------------------------------------------------------------------------
# Does this dependency set ship OpenImageDenoise? Asked rather than assumed,
# exactly as the iOS and Linux jobs ask it: absent, the shim's own a-trous
# filter finishes the frame and cy_denoiser_name says so.
$oidn = 'OFF'
if (@(Get-ChildItem $libdir -Recurse -Filter 'OpenImageDenoise*' -ErrorAction SilentlyContinue |
      Select-Object -First 1).Count -gt 0) { $oidn = 'ON' }
Say "configuring (OpenImageDenoise: $oidn)"

# The same switches as Linux and they mean the same things; that script says
# why each one is off. WITH_WINDOWS_BUNDLE_CRT is the one addition — it copies
# the Visual C++ redistributable into an install tree this build does not have
# and the app does not want a second copy of.
$cfg = @(
  '-S', $blender,
  '-B', (Join-Path $work 'build'),
  '-G', 'Ninja',
  '-DCMAKE_BUILD_TYPE=Release',
  '-DWITH_BLENDER=OFF',
  '-DWITH_CYCLES_BLENDER=OFF',
  '-DWITH_CYCLES_STANDALONE=ON',
  '-DWITH_CYCLES_STANDALONE_GUI=OFF',
  '-DWITH_CYCLES=ON',
  '-DWITH_VULKAN_BACKEND=OFF',
  '-DWITH_PYTHON=OFF',
  '-DWITH_WINDOWS_BUNDLE_CRT=OFF',
  "-DWITH_OPENIMAGEDENOISE=$oidn",
  '-DWITH_OPENVDB=OFF', '-DWITH_NANOVDB=OFF',
  '-DWITH_ALEMBIC=OFF', '-DWITH_USD=OFF',
  '-DWITH_CYCLES_OSL=OFF',
  '-DWITH_CYCLES_PATH_GUIDING=OFF')
Run 'cmake' $cfg (Join-Path $work 'configure.log') 'configure'

Say 'building Cycles and the shim'
# The named ones first, so a failure says which library it was in. `cycles`
# LAST and it is not redundant: it is Cycles' own standalone renderer, and
# building it is what guarantees every archive in the link line below actually
# exists — extern_cuew, extern_hipew and bf_intern_libc_compat are all in that
# line and in none of the names anyone would think to write down.
$targets = @('cycles_util', 'cycles_graph', 'cycles_bvh', 'cycles_subd',
             'cycles_scene', 'cycles_integrator', 'cycles_session',
             'cycles_device', 'cycles_kernel', 'bf_intern_guardedalloc',
             'bf_intern_sky', 'cycles_shim', 'cycles')
foreach ($t in $targets) {
  Run 'cmake' @('--build', (Join-Path $work 'build'), '--target', $t, '-j', "$jobs") `
      (Join-Path $work "build_$t.log") $t
  Write-Host "built $t"
}

# ---------------------------------------------------------------------------
# 4. Link prototype_cycles.dll
# ---------------------------------------------------------------------------
Say 'linking prototype_cycles.dll'
$build = Join-Path $work 'build'
$shimLib = Get-ChildItem $build -Recurse -Filter 'cycles_shim.lib' | Select-Object -First 1
if (-not $shimLib) { throw 'no cycles_shim.lib was built' }

# WHICH LIBRARIES, DECIDED BY THE BUILD RATHER THAN BY ME — the same trick and
# the same line of build.ninja as Linux, one file extension apart. Paths in it
# are relative to the build directory, so the link runs from there.
$linkLine = $null
$inRule = $false
foreach ($line in (Get-Content (Join-Path $build 'build.ninja'))) {
  if ($line -match '^build bin/cycles\.exe: ') { $inRule = $true; continue }
  if ($inRule -and ($line -match '^  LINK_LIBRARIES = (.*)$')) {
    $linkLine = $Matches[1]
    break
  }
  if ($inRule -and ($line -eq '')) { $inRule = $false }
}
if (-not $linkLine) { throw 'no LINK_LIBRARIES for bin/cycles.exe in build.ninja' }
# UNESCAPED BY HAND, because ninja's escaping and PowerShell's Split disagree
# about exactly the case that matters. Ninja writes a literal space inside a
# path as '$ ' and a literal '$' as '$$', so splitting on ' ' would cut a
# path like "Program Files" in half and hand the linker two arguments that are
# each a file that does not exist. One pass, one rule: '$' escapes whatever
# follows it.
$linkLibs = New-Object 'System.Collections.Generic.List[string]'
$token = ''
for ($i = 0; $i -lt $linkLine.Length; $i++) {
  $ch = $linkLine[$i]
  if (($ch -eq '$') -and ($i + 1 -lt $linkLine.Length)) {
    $i++
    $token += $linkLine[$i]
    continue
  }
  if ($ch -eq ' ') {
    if ($token -ne '') { $linkLibs.Add($token); $token = '' }
    continue
  }
  $token += $ch
}
if ($token -ne '') { $linkLibs.Add($token) }
Write-Host "$($linkLibs.Count) libraries in the link line"

# THE EXPORT SURFACE, DERIVED. `cy_` is the whole C API — the policy the
# version script states as `global: cy_*` — and the true list lives in the
# shim's own archive. UNDEF entries are what the shim CALLS; exporting one of
# those makes a DLL that claims to define something it does not.
$symLines = @(& dumpbin /SYMBOLS $shimLib.FullName |
  Select-String -Pattern 'External\s+\|\s+(cy_\w+)' |
  Where-Object { $_.Line -notmatch 'UNDEF' })
$syms = @($symLines | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
if ($syms.Count -lt 10) {
  throw "only $($syms.Count) cy_ symbols in cycles_shim.lib — that is not the shim's archive"
}
$defPath = Join-Path $work 'prototype_cycles.def'
@('; Generated by tools/desktop/build_cycles_windows.ps1 from cycles_shim.lib.',
  "; The policy is backend/desktop/prototype_cycles.map's: cy_* and nothing else.",
  'EXPORTS') + @($syms | ForEach-Object { "  $_" }) |
  Set-Content -Path $defPath -Encoding ascii
Write-Host "$($syms.Count) cy_ symbols in the .def"

# A RESPONSE FILE rather than a command line. Cycles links about forty archives
# and the precompiled set's paths are long; a command line is capped at 32767
# characters and the failure when it is exceeded is not a message about being
# too long, it is a truncated link.
$rsp = Join-Path $work 'link.rsp'
@("/OUT:`"$out\prototype_cycles.dll`"",
  "/IMPLIB:`"$out\prototype_cycles.lib`"",
  "/DEF:`"$defPath`"",
  "/WHOLEARCHIVE:`"$($shimLib.FullName)`"") +
  @($linkLibs | ForEach-Object { "`"$_`"" }) |
  Set-Content -Path $rsp -Encoding ascii
Push-Location $build
& link /nologo /DLL /MACHINE:X64 "@$rsp" *> (Join-Path $work 'link.log')
$linkStatus = $LASTEXITCODE
Pop-Location
if ($linkStatus -ne 0) {
  Write-Host 'the shim does not link:'
  @(Select-String -Path (Join-Path $work 'link.log') -Pattern 'unresolved external|LNK\d+' |
    Select-Object -First 30) | ForEach-Object { Write-Host $_.Line }
  exit 1
}
$mb = [math]::Round((Get-Item "$out\prototype_cycles.dll").Length / 1MB, 1)
Write-Host "linked: $mb MB"

# Checked rather than trusted, exactly as the Linux script checks its version
# script: the .def is the only thing between this and an export table with all
# of Cycles, Embree, TBB and OpenImageIO in it.
$exported = @(& dumpbin /EXPORTS "$out\prototype_cycles.dll" |
  Select-String -Pattern '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(\S+)' |
  ForEach-Object { $_.Matches[0].Groups[1].Value })
$leaked = @($exported | Where-Object { $_ -notmatch '^cy_' })
if ($leaked.Count -gt 0) {
  Write-Host 'EXPORT CHECK: FAIL — symbols escaped the .def:'
  $leaked | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
  exit 1
}
Write-Host "exports $($exported.Count) cy_ symbols and nothing else"

# ---------------------------------------------------------------------------
# 5. The closure
# ---------------------------------------------------------------------------
Say 'collecting the runtime closure'
$deps = Join-Path $out 'deps'
New-Item -ItemType Directory -Force -Path $deps | Out-Null

# What the machine provides; everything else travels. api-ms-win-* and the
# ucrt/vcruntime pair are the Universal CRT, which every supported Windows has
# and which the app's own installer would otherwise ship a second copy of.
$hostOnly = '^(api-ms-win-.*|ext-ms-.*|kernel32|kernelbase|user32|gdi32|gdiplus|' +
            'advapi32|shell32|shlwapi|ole32|oleaut32|comdlg32|comctl32|version|' +
            'winmm|imm32|ws2_32|wsock32|iphlpapi|crypt32|bcrypt|ncrypt|secur32|' +
            'wintrust|dbghelp|psapi|setupapi|cfgmgr32|userenv|netapi32|mpr|' +
            'rpcrt4|d3d9|d3d11|d3d12|dxgi|dxguid|d2d1|dwrite|opengl32|glu32|' +
            'msvcrt|msvcp\d+|vcruntime\d+.*|ucrtbase|ucrtbased|concrt\d+|ntdll|' +
            'powrprof|winspool\.drv|uxtheme|dwmapi|propsys|windowscodecs|authz|' +
            'avrt|hid|cabinet|normaliz|wldap32|dnsapi|mswsock)\.dll$'

# Where a DLL can be found. The precompiled set keeps them under bin\ or lib\
# depending on the package, and none of it is on PATH.
$searchDirs = @(Get-ChildItem $libdir -Recurse -Directory |
                Where-Object { $_.Name -in @('bin', 'lib') } |
                ForEach-Object { $_.FullName })
$searchDirs += $out

$queue = New-Object 'System.Collections.Generic.Queue[string]'
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$missing = 0
$copied = 0
$queue.Enqueue("$out\prototype_cycles.dll")
while ($queue.Count -gt 0) {
  $lib = $queue.Dequeue()
  $needs = @(& dumpbin /DEPENDENTS $lib |
    Select-String -Pattern '^\s+(\S+\.dll)\s*$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value })
  foreach ($need in $needs) {
    $key = $need.ToLower()
    if ($key -match $hostOnly) { continue }
    if (-not $seen.Add($key)) { continue }
    $target = Join-Path $deps $need
    if (-not (Test-Path $target)) {
      $found = $null
      foreach ($d in $searchDirs) {
        $candidate = Join-Path $d $need
        if (Test-Path $candidate) { $found = $candidate; break }
      }
      if (-not $found) {
        Write-Host "  MISSING: $(Split-Path -Leaf $lib) needs $need — nowhere to be found"
        $missing++
        continue
      }
      Copy-Item $found $target -Force
      $copied++
    }
    $queue.Enqueue($target)
  }
}
$depsMB = [math]::Round(
  (Get-ChildItem $deps -File | Measure-Object Length -Sum).Sum / 1MB, 0)
Write-Host "added $copied DLLs to $deps ($depsMB MB total)"
if ($missing -ne 0) { Write-Host "CLOSURE: FAIL ($missing unsatisfied)"; exit 1 }
Write-Host 'CLOSURE: PASS'

# ---------------------------------------------------------------------------
# 6. The link gate, which is also the device report
# ---------------------------------------------------------------------------
Say 'the link gate'
# cl compiles the .c as C++ (/TP), which is what the Linux and iOS gates do too.
Push-Location $work
& cl /nologo /TP /EHsc "/I$repo\backend\cycles\shim" `
  "$repo\backend\cycles\shim\shim_probe.c" `
  "/Fe:$out\prototype_cycles_probe.exe" `
  /link "$out\prototype_cycles.lib" *> (Join-Path $work 'probe.log')
$probeStatus = $LASTEXITCODE
Pop-Location
if ($probeStatus -ne 0) {
  Get-Content (Join-Path $work 'probe.log') -Tail 20 | ForEach-Object { Write-Host $_ }
  exit 1
}
# An import is looked up beside the importing module and then on PATH. In the
# shipped bundle everything is flat in lib\; here the dependencies are one
# directory down, which is one PATH entry rather than a different arrangement.
$env:PATH = "$deps;$out;$env:PATH"
& "$out\prototype_cycles_probe.exe"

if (-not $Keep -and -not $env:CYCLES_WORK_DIR) {
  Write-Host ''
  Write-Host "(Blender's tree is $work. Delete it when you are done, or pass"
  Write-Host ' -Keep to be reminded rather than told.)'
}

Say 'done'
Write-Host "library : $out\prototype_cycles.dll"
Write-Host ''
Write-Host 'Next:  cd frontend; flutter build windows --release'
