#!/usr/bin/env python3
"""M372 — WITH_PYTHON=OFF must not switch the renderer off with it.

WHAT IT IS
----------

Blender's top-level CMakeLists.txt carries

    set_and_warn_dependency(WITH_PYTHON WITH_CYCLES        OFF)

and `WITH_PYTHON=OFF` is what makes a desktop Cycles build tractable at all:
configuring the whole of Blender otherwise pulls in Python, GHOST, Vulkan (and
therefore shaderc), three audio backends and the file-format importers, none of
which Cycles needs and all of which have to be FOUND before CMake will finish.

So `WITH_CYCLES` goes OFF one line into the configure — while
`WITH_CYCLES_STANDALONE=ON` still adds `intern/cycles`, which still compiles
`bvh/embree.cpp`, because `WITH_CYCLES_EMBREE` is a separate switch and stays
ON. What is lost is every `if(WITH_CYCLES AND ...)` block in the platform file,
and the one that matters is `find_package(Embree)`: Embree's headers are found
either way, so every `rtc*` call compiles and `EMBREE_LIBRARIES` is empty in the
link line. Several hundred undefined `rtc...` symbols at the very last step of
a very long build, with nothing in the configure output pointing at the cause
but one line reading "WITH_PYTHON is disabled, setting WITH_CYCLES=OFF".

The dependency is REAL for Blender — the render engine is driven from Python —
and false for this build, which compiles `intern/cycles` and links it into a C
library. `WITH_CYCLES_BLENDER` is already OFF and nothing here calls a Python
API, so the line goes.

WHY IT IS ITS OWN FILE
----------------------

It started as a dozen lines inside build_cycles_linux.sh, and then Windows
needed exactly the same edit — the line is in the top-level CMakeLists, not in
a platform file, so it fires on every platform that turns Python off. A patch
that is written down twice is a patch that gets fixed once; this repository has
already had one instance of that (the --no-checkout clone, restored in its own
commit after a file copy between branches undid it).

SELF-VERIFYING, like the others here: the anchor must appear exactly once, or
this aborts rather than silently doing nothing. Running it on an already
patched tree is a no-op that says so.

Run from the directory whose child is `blender/`, which is the shape all three
callers use:

    python3 backend/cycles/patches/no_python_cycles.py
"""
import sys

PATH = 'blender/CMakeLists.txt'
ANCHOR = 'set_and_warn_dependency(WITH_PYTHON WITH_CYCLES        OFF)'
MARKER = 'M372 (ipadprocad) no-python-no-cycles'

with open(PATH, encoding='utf-8') as f:
    s = f.read()

if MARKER in s:
    print(f'{PATH}: no-python-no-cycles already applied')
    sys.exit(0)

n = s.count(ANCHOR)
if n != 1:
    sys.stderr.write(
        f'FATAL {PATH}: the WITH_PYTHON/WITH_CYCLES dependency line was found '
        f'{n} times (need 1).\nBlender\'s top level has changed shape. Stopping '
        f'rather than configuring a build that would silently drop Embree.\n')
    sys.exit(1)

s = s.replace(
    ANCHOR,
    f'# {MARKER} — removed by backend/cycles/patches/no_python_cycles.py.\n'
    '# This build has no Python and no Blender, and the dependency is on\n'
    "# Cycles' Blender integration (WITH_CYCLES_BLENDER, already OFF) rather\n"
    '# than on the renderer. Left in place it takes Embree out of the link\n'
    '# line without taking rtc* out of the compile.\n'
    '# ' + ANCHOR, 1)

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(s)
print(f'{PATH}: applied no-python-no-cycles')
