#!/usr/bin/env python3
"""M372 — `guarded_allocator.h` uses std::_Container_proxy without including it.

WHAT MSVC SAYS

    intern/cycles/util/guarded_allocator.h(126):
      error C2039: '_Container_proxy': is not a member of 'std'
    ...MSVC\\14.44.35207\\include\\new(20): note: see declaration of 'std'

and then nine more errors that are all that one, cascading.

WHY IT IS REAL AND NOT A TOOLCHAIN COMPLAINT

The header includes exactly three things — <cstddef>, <cstdlib>, <new> — and
then, under `#ifdef _MSC_VER`, specialises

    template<> struct rebind<std::_Container_proxy> { ... };
    operator std::allocator<std::_Container_proxy>() const { ... }

`std::allocator` lives in <memory> and `std::_Container_proxy` in <xmemory>,
which <memory> pulls in. Neither is reachable from <new>. The header has
therefore always depended on somebody else having included <memory> first, and
the note in the error says who did not: at that point the only declaration of
namespace `std` came from <new>.

This is the one Blender build that finds out. A full Blender compiles this
header deep inside translation units that have included half the standard
library by the time they reach it; a Cycles-only build with the targets in
dependency order reaches `util/aligned_malloc.cpp` FIRST, and that file
includes almost nothing else. The comment above the specialisation calls
itself "a bit fragile, unfortunately", which is fair.

WHY <memory> AND NOT <xmemory>

<xmemory> is an MSVC implementation header and including it directly is
exactly the kind of thing that breaks on the next toolchain. <memory> is
standard, is what provides `std::allocator` the code is already using, and
brings `_Container_proxy` with it on the only compiler that has one. It is
added unconditionally rather than under `#ifdef _MSC_VER`, because a header
that uses `std::allocator` should include <memory> on every compiler, and the
other two get it for nothing.

SELF-VERIFYING, like the others here: the anchor must appear exactly once, or
this aborts rather than silently doing nothing. Running it on an already
patched tree is a no-op that says so.

Run from the directory whose child is `blender/`:

    python3 backend/cycles/patches/msvc_container_proxy.py
"""
import sys

PATH = 'blender/intern/cycles/util/guarded_allocator.h'
ANCHOR = '#include <cstddef>\n#include <cstdlib>\n#include <new>\n'
MARKER = 'M372 (ipadprocad) container-proxy-include'

with open(PATH, encoding='utf-8') as f:
    s = f.read()

if MARKER in s:
    print(f'{PATH}: container-proxy-include already applied')
    sys.exit(0)

n = s.count(ANCHOR)
if n != 1:
    sys.stderr.write(
        f'FATAL {PATH}: the include block was found {n} times (need 1).\n'
        "Cycles' guarded allocator has changed shape; check whether it still\n"
        'needs <memory> before patching it.\n')
    sys.exit(1)

s = s.replace(
    ANCHOR,
    '#include <cstddef>\n'
    '#include <cstdlib>\n'
    '/* ' + MARKER + ' — added by\n'
    ' * backend/cycles/patches/msvc_container_proxy.py.\n'
    ' *\n'
    ' * The MSVC branch below names std::allocator and std::_Container_proxy,\n'
    ' * and <new> provides neither. A full Blender build only ever reaches\n'
    ' * this header after something else has included <memory>; a Cycles-only\n'
    ' * build reaches it from util/aligned_malloc.cpp, which has not. */\n'
    '#include <memory>\n'
    '#include <new>\n', 1)

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(s)
print(f'{PATH}: applied container-proxy-include')
