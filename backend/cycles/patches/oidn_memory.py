#!/usr/bin/env python3
"""M369 — put a ceiling on what OpenImageDenoise is allowed to allocate.

WHAT THE REPORT WAS
-------------------

    "When it came to denoising the App crashed"

M367 turned Cycles' own denoiser on, and it denoises the finished frame at the
viewport's full 1:1 resolution. On a Mac that is unremarkable. On an iPad it is
the largest single allocation in the whole render, arriving at the one moment
the process is already holding everything else.

WHY IT IS A MEMORY CEILING AND NOT A SMALLER PICTURE
----------------------------------------------------

OIDN tiles its network when it has to, and it decides when it has to from two
numbers (core/unet_filter.cpp):

    const int    maxTileSize      = (maxMemoryMB < 0) ? defaultMaxTileSize : INT_MAX;
    const size_t maxMemoryByteSize = (maxMemoryMB >= 0) ? maxMemoryMB << 20 : SIZE_MAX;

`defaultMaxTileSize` is `2160*2160` — 4.67 megapixels. An iPad Pro viewport at
1:1 is under that, so OIDN takes the whole frame as ONE tile and allocates the
network for it in one piece. And because Cycles never sets `maxMemoryMB` at all,
the second bound is SIZE_MAX: there is nothing to fall back on.

That is fine on a desktop and it is not fine here. This repo's own
`ios_metal.py` already documents the ceiling being pushed against:

    "4M path states is a 1.38 GB SoA allocation, made BEFORE kernel
     compilation. That memory pressure starves MTLCompilerService ... and risks
     a jetsam kill shortly after rendering starts."

— which is why the path-state pool was cut to about 350 MB. M367 then added,
at the END of the render rather than the start: the guide passes and a denoised
Combined (about ten more floats per pixel of render buffer), a host copy of the
whole buffer for the CPU denoiser, and OIDN's own arena for a four-megapixel
tile. The crash lands exactly where those meet.

Setting `maxMemoryMB` is the mechanism OIDN provides for precisely this. It
keeps the output at full resolution — the frame is still denoised whole, in
tiles with overlap — and bounds the peak instead of the picture. That is much
better than the alternative of rendering smaller, which would cost the 1:1
sharpness M353 went to some trouble to get back.

WHY IT IS SET FOR EVERY BUILD AND NOT ONLY FOR iOS
---------------------------------------------------

The other patches in this directory guard their edits with
WITH_APPLE_CROSSPLATFORM because they encode an iOS-specific fact. This one does
not: an unbounded denoiser is wrong everywhere, it is merely survivable on a
desktop. Bounding it for every build also means the host render test exercises
the same code the iPad runs, which is the whole reason that test exists.

The number is a judgement, and deliberately on the cautious side of one. 256 MB
sits well inside what an iPad can spare next to the ~350 MB path-state pool,
the render buffers and their host copy. A viewport-sized frame then needs a
handful of tiles, and OIDN's tile overlap makes more tiles slower rather than
wrong; the floor is its own minimum tile of 768x768, whose network is far below
this. Erring small is the right way round for a first fix to a crash: too
generous costs another crash, too mean costs a denoise that takes a little
longer. It is one constant, in one place.

SELF-VERIFYING, like every patch here: the anchor must appear exactly once, and
the marker makes the edit idempotent.
"""
import sys


def edit(path, replacements):
    """Apply (anchor, replacement, tag) edits to [path], exactly once each.

    The already-applied test is the tag, not the replacement text, for the
    reason progressive.py spells out: this edit INSERTS beside a line it keeps,
    so the anchor survives and "is the replacement present" cannot distinguish
    a patched tree from an unpatched one.
    """
    with open(path, encoding='utf-8') as f:
        s = f.read()
    for old, new, tag in replacements:
        marker = f'M369 (ipadprocad) {tag}'
        if marker not in new:
            sys.stderr.write(f'FATAL {path}: replacement {tag!r} carries no marker\n')
            sys.exit(1)
        if marker in s:
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


OIDN = 'blender/intern/cycles/integrator/denoiser_oidn.cpp'

edit(OIDN, [
    # Added inside set_quality rather than beside one filter, because it has to
    # reach BOTH: the beauty filter and, when the prefilter is ACCURATE, the
    # albedo and normal filters, which are separate networks with their own
    # arenas. set_quality is the one function every one of them goes through.
    ('      case DENOISER_QUALITY_HIGH:\n'
     '      default:\n'
     '        oidn_filter.set("quality", OIDN_QUALITY_HIGH);\n'
     '    }\n'
     '#  endif\n'
     '  }\n',
     '      case DENOISER_QUALITY_HIGH:\n'
     '      default:\n'
     '        oidn_filter.set("quality", OIDN_QUALITY_HIGH);\n'
     '    }\n'
     '#  endif\n'
     '\n'
     '    /* M369 (ipadprocad) memory-ceiling — bound the arena so OIDN tiles.\n'
     '     *\n'
     '     * Cycles never sets this, so OIDN falls back to its own rule: tile only\n'
     '     * above `defaultMaxTileSize`, which is 2160*2160 = 4.67 megapixels\n'
     '     * (core/unet_filter.cpp). A tablet viewport at 1:1 is under that, so the\n'
     '     * whole frame becomes one tile and the network is allocated for it in\n'
     '     * one piece, at the end of a render that is already holding the path\n'
     '     * state pool, the BVH and the render buffers. That is what killed the\n'
     '     * app; see backend/cycles/patches/oidn_memory.py.\n'
     '     *\n'
     '     * Bounding the MEMORY rather than the image keeps the output at full\n'
     '     * resolution — OIDN tiles with overlap and the result is the same\n'
     '     * picture — and costs only time when the bound actually binds. */\n'
     '    oidn_filter.set("maxMemoryMB", 256);\n'
     '  }\n',
     'memory-ceiling'),
])

print('OIDN memory ceiling patch APPLIED OK')
