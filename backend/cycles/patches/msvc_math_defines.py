#!/usr/bin/env python3
"""M372 — M_PI is not a thing on MSVC unless something asks for it.

WHAT IT IS
----------

MSVC's <cmath> declares M_PI, M_SQRT2 and the rest of the BSD math constants
only when _USE_MATH_DEFINES is defined before it is included. They are not
standard C++, so this is conforming rather than a defect — and it means any
header that reaches for M_PI compiles everywhere except here.

OpenSubdiv's does. `sdc/loopScheme.h` and `sdc/catmarkScheme.h` use M_PI in
the limit-mask maths, and `cycles_subd` instantiates exactly those templates:

    opensubdiv/far/../sdc/loopScheme.h(301): error C2065: 'M_PI': undeclared
    opensubdiv/far/../sdc/loopScheme.h(301): error C3861: 'M_PI': not found

and eleven more, across dice.cpp and subdivision.cpp, all of them that one
identifier reached through `Sdc::Scheme<SCHEME_LOOP>::assignSmoothLimitMask`
and its neighbours. The headers come from the precompiled dependency set, so
there is nothing to fix in them and no version of them that behaves
differently.

Blender's tree never defines _USE_MATH_DEFINES globally — the only mention in
the whole platform file is OPENVDB_DEFINITIONS, which is handed to OpenVDB's
targets alone and reaches no Cycles target. So the define goes in the same
add_definitions() block that already carries the other five compatibility
macros this platform needs, where it is in front of every translation unit
rather than in front of the one that failed today.

WHY THE PLATFORM FILE AND NOT OUR CONFIGURE LINE
------------------------------------------------

`-DCMAKE_CXX_FLAGS=...` on the command line REPLACES the value CMake computed
rather than adding to it, and that value is where /DWIN32, /D_WINDOWS and the
warning level live; Blender then appends its own dozen switches to whatever is
left. Getting a compatibility macro in should not mean taking responsibility
for reproducing the default flags of every CMake this ever runs under.

Applied on both platforms, like no_python_cycles.py and for the same reason:
this file is only *included* on Windows, so on Linux the edit is inert — but a
patch list that differs by platform is a patch list where the platforms drift,
and this tree has already had one instance of that.

SELF-VERIFYING: the anchor must appear exactly once, or this aborts rather
than silently doing nothing. Running it on an already patched tree is a no-op
that says so.

Run from the directory whose child is `blender/`, which is the shape all the
callers use:

    python3 backend/cycles/patches/msvc_math_defines.py
"""
import sys

PATH = 'blender/build_files/cmake/platform/platform_win32.cmake'
ANCHOR = """add_definitions(
  -D_CRT_NONSTDC_NO_DEPRECATE
  -D_CRT_SECURE_NO_DEPRECATE
  -D_SCL_SECURE_NO_DEPRECATE
  -D_CONSOLE
  -D_LIB
)"""
MARKER = 'M372 (ipadprocad) use-math-defines'

with open(PATH, encoding='utf-8') as f:
    s = f.read()

if MARKER in s:
    print(f'{PATH}: use-math-defines already applied')
    sys.exit(0)

n = s.count(ANCHOR)
if n != 1:
    sys.stderr.write(
        f'FATAL {PATH}: the compatibility-macro block was found {n} times '
        f'(need 1).\nBlender\'s Windows platform file has changed shape. '
        f'Stopping rather than\nconfiguring a build that would fail on M_PI '
        f'thirteen targets later.\n')
    sys.exit(1)

s = s.replace(
    ANCHOR,
    'add_definitions(\n'
    '  -D_CRT_NONSTDC_NO_DEPRECATE\n'
    '  -D_CRT_SECURE_NO_DEPRECATE\n'
    '  -D_SCL_SECURE_NO_DEPRECATE\n'
    '  -D_CONSOLE\n'
    '  -D_LIB\n'
    f'  # {MARKER} — added by\n'
    '  # backend/cycles/patches/msvc_math_defines.py. MSVC declares M_PI and\n'
    "  # the other BSD math constants only under this, and OpenSubdiv's\n"
    '  # sdc/loopScheme.h uses M_PI in templates cycles_subd instantiates.\n'
    '  -D_USE_MATH_DEFINES\n'
    ')', 1)

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(s)
print(f'{PATH}: applied use-math-defines')
