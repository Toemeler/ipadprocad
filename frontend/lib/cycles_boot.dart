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
import 'render_engine.dart' show realtimeEngineName;
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
    // NAMED, not assumed. This line said "stays RealityKit" on every platform,
    // and RealityKit does not exist on two of the three the app ships on — so
    // a Linux or Windows log answered "what draws rendered mode here?" with a
    // renderer that is not in the build. That is #36's mistake in the log
    // instead of the picker, and it misleads exactly the person reading a
    // desktop report to find out why a render did nothing.
    //
    // `realtimeEngineName` is the same question the viewport and the picker
    // ask, so all three keep one answer.
    final falls = realtimeEngineName() ?? 'the CPU painter';
    Log.i('cycles', 'no renderer in this build; rendered mode stays $falls');
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
  // kernels are in the binary; the warm-up would be a full render nobody asked
  // for, on every launch, to fill a cache that is already full.
  //
  // M383 — BUT IT STILL HAS TO BE TOLD SO, and that omission was the whole of
  // "Cycles never loads, it always says loading and never renders". M371 read
  // as "a desktop needs no warm-up", which is true, and acted on it by not
  // starting one — leaving CyclesWarmup in the phase it begins in, `absent`,
  // the phase that means THERE IS NO RENDERER. cycles_layer.dart gates the
  // tracer on `warmup.ready`, so on Windows and Linux rendered mode turned on,
  // showed the warm-up panel, and sat there for ever in front of a path
  // tracer that — as the Windows render test says, in full — renders,
  // converges and denoises perfectly well.
  switch (cyclesWarmupPlan(
    haveRenderer: true,
    needsKernelSource: cyclesNeedsKernelSource,
  )) {
    case CyclesWarmupPlan.compile:
      CyclesWarmup.instance.start();
    case CyclesWarmupPlan.alreadyWarm:
      CyclesWarmup.instance.markReady();
    case CyclesWarmupPlan.nothing:
      break;
  }
}

/// For tests, which must not inherit another case's answer.
void resetCyclesForTest({bool ready = false}) => _ready = ready;
