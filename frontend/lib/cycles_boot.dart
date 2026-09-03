// M306 — pointing Cycles at its own kernel source, and refusing to pretend
// otherwise when it is not there.
//
// ---------------------------------------------------------------------------
// THE FAILURE THIS EXISTS TO PREVENT
// ---------------------------------------------------------------------------
//
// Cycles' Metal backend does not ship compiled kernels. It builds them at
// runtime, from source, on the device:
//
//     source = "\n#include \"kernel/device/metal/kernel.metal\"\n";
//     source = path_source_replace_includes(source, path_get("source"));
//                                  — intern/cycles/device/metal/device_impl.mm
//
// and `path_get("source")` is `<resource path>/source`. So an app that ships
// the nine static libraries and not the kernel TREE links, launches, shows a
// working viewport, and then fails at the first render with an error from
// inside a shader compiler — the one failure mode of this whole integration
// that names nothing useful.
//
// So the tree's presence is checked HERE, at launch, once, and reported as a
// log line that says exactly what is missing. And if it is missing, the
// renderer is treated as absent: rendered mode stays the RealityKit view
// rather than offering a render that cannot happen.
import 'dart:io';

import 'cycles_assets.dart';
import 'platform/app_dirs.dart';
import 'cycles_warmup.dart';
import 'ffi/cycles_engine.dart';
import 'log.dart';
import 'materials.dart' show materialIds;

/// The directory Cycles is given as its resource root, or null where the app
/// has no bundle to find it in.
///
/// The kernel tree is bundled at `Runner.app/cycles/source`, so the root is
/// `Runner.app/cycles`, and the executable is the only thing that knows where
/// Runner.app is at runtime. Cycles' own fallback does the same thing —
/// `path_dirname(this_program_path())` — but relies on the tree sitting in the
/// bundle ROOT, and a bundle root that quietly acquires a `source/` directory
/// is not something to build on.
///
/// M371 — and the same arithmetic on a desktop, where `cycles/` sits beside
/// the runner in the bundle. It holds the render ASSETS there rather than a
/// kernel tree (see [cyclesNeedsKernelSource]), but Cycles still wants a
/// resource root and the assets still have to be found under one.
String? cyclesResourceRoot([String? executable]) {
  final exe = executable ??
      ((Platform.isIOS || isDesktopHost) ? Platform.resolvedExecutable : '');
  if (exe.isEmpty) return null;
  // Both separators: this is the one place a Windows path reaches this file,
  // and `\` is not a character a POSIX path can carry, so accepting both is
  // unambiguous rather than lenient.
  final i = exe.lastIndexOf(RegExp(r'[/\\]'));
  if (i <= 0) return null;
  return '${exe.substring(0, i)}/cycles';
}

/// Whether this platform's Cycles device compiles its kernels FROM SOURCE at
/// run time, and therefore needs the kernel tree on disk.
///
/// M371 — only Metal does. The CPU device's kernels are compiled into the
/// archive at build time and CUDA's are cubins produced by the same build, so
/// a Linux or Windows bundle carries no `source/` tree and must not be judged
/// for the lack of one: gating on it there would report "no renderer" about a
/// renderer that works.
bool get cyclesNeedsKernelSource => Platform.isIOS || Platform.isMacOS;

/// The one file whose absence means no render can ever succeed.
///
/// Every other kernel header is reached from it by the include walker, so if
/// this is there the tree was copied; if it is not, nothing else matters.
/// Only meaningful where [cyclesNeedsKernelSource].
String cyclesKernelProbe(String root) =>
    '$root/source/kernel/device/metal/kernel.metal';

/// Whether this build can actually render: the shim is linked AND its kernel
/// source is on disk.
///
/// False until [initCycles] has run, and false forever on a build with no
/// renderer — which is every host test.
bool get cyclesReady => _ready;
bool _ready = false;

/// Called once at launch, before anything can ask for a render.
void initCycles() {
  _ready = false;
  final ffi = CyclesFfi.instance;
  if (ffi == null) {
    Log.i('cycles', 'no renderer in this build; rendered mode stays RealityKit');
    return;
  }
  final root = cyclesResourceRoot();
  if (root == null) {
    Log.w('cycles', 'no resource root on this platform');
    return;
  }
  if (cyclesNeedsKernelSource &&
      !File(cyclesKernelProbe(root)).existsSync()) {
    // The exact sentence someone will search for when the render button does
    // nothing. It names the file, so the fix is obvious from the log alone.
    Log.w(
        'cycles',
        'kernel source missing: ${cyclesKernelProbe(root)} — the Metal device '
            'compiles its kernels from source at runtime, so rendered mode '
            'stays RealityKit until the tree is in the bundle');
    return;
  }
  ffi.setResourcePath(root);
  _ready = true;
  Log.i('cycles', 'ready: device ${ffi.deviceName}, resources $root');
  // M344 — the optional HDRI and PBR texture sets, if this build carries them.
  // One directory walk, here, once: the alternative is a stat per appearance
  // per render, and there are thirty renders a second during an orbit. Nothing
  // it finds is required and nothing it misses is an error — see
  // cycles_assets.dart.
  CyclesAssets.instance.scan(root, materialIds: materialIds);
  // M320 — and start compiling the Metal kernels NOW, on another isolate.
  // They take minutes on a cold install and nothing on every launch after,
  // and the only question is whether that wait lands here, while a document
  // is being opened, or on the first person to switch to rendered mode.
  // Strictly after setResourcePath: the compiler needs the source tree.
  //
  // M371 — and only where there is a compile to warm. A desktop build's
  // kernels are in the binary; the warmup would be a full render nobody asked
  // for, on every launch, to fill a cache that is already full.
  if (cyclesNeedsKernelSource) CyclesWarmup.instance.start();
}

/// For tests, which must not inherit another case's answer.
void resetCyclesForTest({bool ready = false}) => _ready = ready;
