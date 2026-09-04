#!/usr/bin/env python3
"""M372 — `uint` is a POSIX type, and MSVC is not POSIX.

WHAT IT IS
----------

intern/mikktspace is header-only, and mikk_util.hh declares everything it
counts with in `uint`:

    uint bins[datasize][257] = {{0}};
    for (uint pass = 0; pass < datasize; pass++) {
    for (uint i = 2; i < 256; i++) {

`uint` is not a C or C++ type. It is a glibc convenience typedef out of
<sys/types.h>, which on Linux and macOS arrives through almost any standard
header, so the file has never needed to say where it comes from. On MSVC
there is no such typedef, nothing else in the include chain provides one —
Cycles' own `using uint = unsigned int` is inside CCL_NAMESPACE and cannot be
seen from `namespace mikk` — and the whole radix sort stops parsing:

    mikk_util.hh(127): error C2760: syntax error: ')' was unexpected here
    mikk_util.hh(128): error C2065: 'bins': undeclared identifier
    mikk_util.hh(128): error C2065: 'pass': undeclared identifier
    mikk_util.hh(128): error C2065: 'i': undeclared identifier
    mikk_util.hh(136): fatal error C1003: error count exceeds 100

Every one of those names is declared `uint`, which is what says the type is
the problem rather than the code.

It reaches Cycles through scene/mesh.cpp, which includes "mikktspace.hh" at
global scope for tangent generation, so cycles_scene is where it lands.

The alias is added at global scope ahead of `namespace mikk`, under _MSC_VER
because on the other two platforms the platform already provides it and this
patch should not be the one deciding what `uint` is there. Re-declaring a
typedef to the same type is legal, so nothing breaks if a future include
chain provides one as well.

SELF-VERIFYING: the anchor must appear exactly once, or this aborts rather
than silently doing nothing. Running it on an already patched tree is a no-op
that says so.

Run from the directory whose child is `blender/`, which is the shape all the
callers use:

    python3 backend/cycles/patches/msvc_uint.py
"""
import sys

PATH = 'blender/intern/mikktspace/mikk_util.hh'
ANCHOR = """#ifndef M_PI_F
#  define M_PI_F (3.1415926535897932f) /* pi */
#endif
"""
MARKER = 'M372 (ipadprocad) msvc-uint'

with open(PATH, encoding='utf-8') as f:
    s = f.read()

if MARKER in s:
    print(f'{PATH}: msvc-uint already applied')
    sys.exit(0)

n = s.count(ANCHOR)
if n != 1:
    sys.stderr.write(
        f'FATAL {PATH}: the M_PI_F block was found {n} times (need 1).\n'
        'mikktspace has changed shape; check where `uint` comes from there\n'
        'before patching it.\n')
    sys.exit(1)

s = s.replace(
    ANCHOR,
    ANCHOR +
    '\n'
    '/* ' + MARKER + ' — added by backend/cycles/patches/msvc_uint.py.\n'
    ' *\n'
    ' * This header counts in `uint`, which is a <sys/types.h> typedef rather\n'
    " * than a language type. MSVC has no such thing, and Cycles' own alias is\n"
    ' * inside CCL_NAMESPACE where `namespace mikk` cannot see it. */\n'
    '#ifdef _MSC_VER\n'
    'using uint = unsigned int;\n'
    '#endif\n', 1)

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(s)
print(f'{PATH}: applied msvc-uint')
