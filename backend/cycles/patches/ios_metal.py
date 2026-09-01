#!/usr/bin/env python3
"""M320 — the iOS Metal kernel-loading fixes, taken from Toemeler/blender-iOS-ipa.

Cycles' Metal backend compiles its kernels from source on the device. Upstream
that is tuned for a Mac plugged into the wall; on an iPad it is a different
problem, and the blender-iOS-ipa pipeline has already spent builds 22, 24, 26,
30 and 31 finding out how. Every edit below is that work, applied to the tree
this app builds Cycles from, with its original reasoning kept.

WHAT GOES WRONG WITHOUT THESE, in the order it was discovered on-device:

  * Two huge shade kernels compiling concurrently get the MTLCompilerService
    XPC connection killed under memory pressure (130+ s, then failure).
  * 4M path states is a 1.38 GB allocation made BEFORE kernel compilation.
    That pressure starves the compiler service and risks a jetsam kill.
  * Binary archives are disabled on iOS upstream, so NOTHING persists and
    every single launch recompiles kernels that take 30-130 s each.
  * Specialized PSOs recompile in the background DURING rendering; the
    combined pressure of render buffers plus compiler killed the app.
  * integrator_shade_volume/_shadow took ~300 s each until Apple's
    optimize-for-size was used — WWDC22's "Target and optimize GPU binaries"
    cites Cycles by name for exactly this.
  * Hardware ray tracing makes the intersect/shade kernels dramatically more
    expensive to compile; the one-time cost outweighs the render speedup.
  * The volume kernels are the heaviest of all and a CAD scene has no volumes.

NOT HERE, deliberately: build-30's writable-cache-location fix. Cycles reads
XDG_CACHE_HOME before falling back to $HOME/.cache (util/path.cpp,
path_xdg_cache_get), and $HOME/.cache is the app container root, which iOS
forbids writing to — which is the true cause of every "Invalid URL" archive
save. The shim sets XDG_CACHE_HOME to Library/Caches at startup instead, so
that one needs no patch at all. See cy_set_resource_path.

SELF-VERIFYING. Every anchor must appear exactly once or this aborts. A silent
no-op here is a build that looks fine and recompiles its kernels forever.
"""
import sys


def edit(path, replacements):
    with open(path, encoding='utf-8') as f:
        s = f.read()
    for old, new, tag in replacements:
        if new in s and old not in s:
            print(f'{path}: {tag} already applied')
            continue
        n = s.count(old)
        if n != 1:
            sys.stderr.write(f'FATAL {path}: anchor {tag!r} found {n} times (need 1)\n')
            sys.exit(1)
        s = s.replace(old, new, 1)
        print(f'{path}: applied {tag}')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)


KM = 'blender/intern/cycles/device/metal/kernel.mm'
QM = 'blender/intern/cycles/device/metal/queue.mm'
DI = 'blender/intern/cycles/device/metal/device_impl.mm'

edit(KM, [
    ('      int max_mtlcompiler_threads = 2;\n',
     '      int max_mtlcompiler_threads = 2;\n'
     '#  ifdef WITH_APPLE_CROSSPLATFORM\n'
     '      /* iPadOS kills the MTLCompilerService XPC connection under memory pressure when two\n'
     '       * huge shade kernels compile concurrently (integrator_shade_volume/_shadow failed\n'
     '       * with XPC_ERROR_CONNECTION_INTERRUPTED after 130+ s). Compile serially so each\n'
     '       * kernel gets the full compiler-service budget. */\n'
     '      max_mtlcompiler_threads = 1;\n'
     '#  endif\n',
     'serial-compile'),

    ('#  ifdef WITH_APPLE_CROSSPLATFORM\n  return false;\n#  endif\n'
     '  /* Issues with binary archives in older macOS versions. */\n'
     '  if (@available(macOS 15.4, *)) {\n',
     '  /* Binary archives are ENABLED on iOS, so the expensive shade kernels (30-130+ s each on\n'
     '   * an iPad) compile once and load near-instantly on every later launch. Upstream returns\n'
     '   * false here for iOS; without the archive nothing persists and the wait is paid every\n'
     "   * single time. The MetalRT exclusion below still applies (linked functions are not\n"
     "   * archivable). Note that @available(macOS 15.4, *) is TRUE on iOS — unlisted platforms\n"
     "   * match '*'. */\n"
     '  /* Issues with binary archives in older macOS versions. */\n'
     '  if (@available(macOS 15.4, *)) {\n',
     'ios-binary-archive'),

    ('''  if (device_kernel == DEVICE_KERNEL_INTEGRATOR_SHADE_SURFACE_MNEE) {
    if ((device->kernel_features & KERNEL_FEATURE_MNEE) == 0) {
      /* Skip shade_surface_mnee kernel if the scene doesn't require it. */
      return false;
    }
  }
''',
     '''  if (device_kernel == DEVICE_KERNEL_INTEGRATOR_SHADE_SURFACE_MNEE) {
    if ((device->kernel_features & KERNEL_FEATURE_MNEE) == 0) {
      /* Skip shade_surface_mnee kernel if the scene doesn't require it. */
      return false;
    }
  }

#  ifdef WITH_APPLE_CROSSPLATFORM
  /* The volumetric kernels are by far the heaviest to compile and were observed taking 300+ s
   * and getting the Metal compiler service killed on an iPad. Skip them for scenes without
   * volumes, the same pattern used for raytrace and MNEE above. A CAD body is triangles; if a
   * volume scene ever arrives they compile then. */
  if (device_kernel == DEVICE_KERNEL_INTEGRATOR_SHADE_VOLUME ||
      device_kernel == DEVICE_KERNEL_INTEGRATOR_INTERSECT_VOLUME_STACK)
  {
    if ((device->kernel_features & KERNEL_FEATURE_VOLUME) == 0) {
      return false;
    }
  }
#  endif
''',
     'skip-volume-kernels'),
])

edit(QM, [
    ('  result = 4194304;\n#  ifdef WITH_APPLE_CROSSPLATFORM\n'
     '  /* Return minimal default working set.\n'
     '   * TODO: Tune based on device and runtime status on iOS. */\n'
     '  return result;\n#  endif\n',
     '  result = 4194304;\n#  ifdef WITH_APPLE_CROSSPLATFORM\n'
     '  /* 4M path states is a 1.38 GB SoA allocation, made BEFORE kernel compilation. That\n'
     '   * memory pressure starves MTLCompilerService (XPC compile failures seen on-device) and\n'
     '   * risks a jetsam kill shortly after rendering starts. 1M states (~350 MB) still keeps an\n'
     '   * Apple GPU saturated — busy:total is 1:4, so 256K busy paths. */\n'
     '  result = 1048576;\n'
     '  return result;\n#  endif\n',
     'path-state-cap'),
])

edit(DI, [
    ('    if (auto *envstr = getenv("CYCLES_METAL_SPECIALIZATION_LEVEL")) {\n',
     '#  ifdef WITH_APPLE_CROSSPLATFORM\n'
     '    /* Specialized PSOs recompile kernels in the background DURING rendering; on an iPad\n'
     '     * the combined memory pressure of render buffers plus MTLCompilerService got the app\n'
     '     * killed (observed at ~15 min, right as the PSO_SPECIALIZED_INTERSECT compiles ran).\n'
     '     * Generic pipelines only: slightly slower renders, no mid-render compile storms. */\n'
     '    kernel_specialization_level = PSO_GENERIC;\n'
     '#  endif\n'
     '    if (auto *envstr = getenv("CYCLES_METAL_SPECIALIZATION_LEVEL")) {\n',
     'no-specialization'),

    ('    options.fastMathEnabled = YES;\n',
     '    options.fastMathEnabled = YES;\n'
     '#  ifdef WITH_APPLE_CROSSPLATFORM\n'
     "    /* Apple's WWDC22 \"Target and optimize GPU binaries\" cites Cycles as the case where\n"
     '     * optimize-for-size fixes unexpectedly long compiles — less inlining and unrolling\n'
     '     * means far smaller AIR for the backend. integrator_shade_volume/_shadow took ~300 s\n'
     '     * each on an iPad and starved MTLCompilerService into XPC kills. */\n'
     '    if (@available(iOS 16.0, *)) {\n'
     '      options.optimizationLevel = MTLLibraryOptimizationLevelSize;\n'
     '    }\n'
     '#  endif\n',
     'optimize-for-size'),

    ('    use_metalrt = info.use_hardware_raytracing;\n',
     '    use_metalrt = info.use_hardware_raytracing;\n'
     '#  ifdef WITH_APPLE_CROSSPLATFORM\n'
     '    /* Hardware ray tracing makes the intersect and shade kernels dramatically more\n'
     '     * expensive to compile, and the one-time compile cost on an iPad outweighs the render\n'
     '     * speedup for the scenes this app produces. Software BVH2 traversal instead.\n'
     '     * CYCLES_METALRT=1 in the environment still re-enables it. */\n'
     '    use_metalrt = false;\n'
     '#  endif\n',
     'no-metalrt'),
])

print('iOS Metal kernel patches APPLIED OK')
