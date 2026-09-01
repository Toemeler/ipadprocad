#!/usr/bin/env python3
"""M331 — make the `ios` branch compile for macOS, so the render test can run.

The render test builds Cycles natively on the runner and renders a known
scene. It builds it from the SAME pinned Blender tree the iPad build uses,
which is the point: a test against a different Cycles would not be a test of
what ships.

That tree does not compile for macOS. One reference survives:

    device/metal/kernel.mm:51
    #  ifndef WITH_APPLE_CROSSPLATFORM
        if (MetalInfo::get_device_vendor(mtlDevice) == METAL_GPU_APPLE) {

`MetalInfo::get_device_vendor` and the whole `MetalGPUVendor` enum were
REMOVED on the `ios` branch — reasonably, since every Metal device iOS runs on
is an Apple GPU, so a vendor test there is a test with one possible answer.
What was missed is that the reference above sits in the `#ifndef` half, which
iOS never compiles and which therefore nobody on that branch ever built. It is
a latent break in code that branch does not use.

The fix says the thing the branch already assumes. It is not a workaround
around a real dependency: the runner is an Apple-silicon Mac, the only devices
this tree supports are Apple GPUs, and `get_apple_gpu_architecture` — which
the block goes on to switch over — is still there and still right.

APPLIED ONLY BY THE RENDER-TEST WORKFLOW. The iOS build never compiles this
half of the file, so patching it there would be an edit with no effect and one
more anchor to keep matching.

SELF-VERIFYING, like ios_metal.py: the anchor must appear exactly once or this
aborts. If the branch ever restores the vendor API, this fails loudly on the
next run rather than silently patching nothing.
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


edit('blender/intern/cycles/device/metal/kernel.mm', [
    ('    if (MetalInfo::get_device_vendor(mtlDevice) == METAL_GPU_APPLE) {\n',
     '    /* M331 — the `ios` branch removed MetalInfo::get_device_vendor and the\n'
     '     * MetalGPUVendor enum, but left this one call behind in the half of the\n'
     '     * file iOS does not compile. Every Metal device this tree supports is an\n'
     '     * Apple GPU, so the test had one answer; this is that answer. */\n'
     '    if (true) {\n',
     'vendor-test-removed-upstream'),
])

print('host macOS compile patches APPLIED OK')
