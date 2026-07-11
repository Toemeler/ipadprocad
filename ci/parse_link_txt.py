#!/usr/bin/env python3
"""Translate a CMake link.txt (Apple ld link line) into linker inputs that can
be fed to Xcode via OTHER_LDFLAGS.

Usage: parse_link_txt.py <link.txt> <target-build-dir>

Keeps: .o/.a paths (relative ones resolved against the target build dir,
which is the directory CMake executes the link command in), -l*, -framework
pairs and -Wl,* flags. Drops: the compiler driver, -o <output>, the smoke
test's own main object (tests/smoke.c.o), and flags Xcode supplies itself
(-arch/-isysroot/-target and their values, optimisation flags, etc.).

Rationale (M5): Qt static finalizers GENERATE the Qml type-registration
translation units in the consumer build tree; they exist nowhere in the Qt
package. The only authoritative, complete list of link inputs is therefore
CMake's own link line for the qcad_capi_smoke device build.
"""
import os
import shlex
import sys


def main() -> int:
    link_txt, cwd = sys.argv[1], sys.argv[2]
    toks = shlex.split(open(link_txt).read().strip())
    out = []
    i = 0  # category filter drops the driver, ':' and '&&' shell glue
    while i < len(toks):
        t = toks[i]
        if t in ('-o', '-arch', '-isysroot', '-target'):
            i += 2
            continue
        if t == '-framework':
            out += [t, toks[i + 1]]
            i += 2
            continue
        if t.endswith('.o') or t.endswith('.a'):
            p = t if os.path.isabs(t) else os.path.normpath(os.path.join(cwd, t))
            if not p.endswith('/smoke.c.o'):
                out.append(p)
            i += 1
            continue
        if t.startswith('-l') or t.startswith('-Wl,'):
            out.append(t)
            i += 1
            continue
        i += 1  # everything else is Xcode's business
    print(' '.join(out))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
