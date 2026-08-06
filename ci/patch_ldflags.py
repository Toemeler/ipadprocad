#!/usr/bin/env python3
"""Write OTHER_LDFLAGS directly onto the app target's build configurations.

WHY THIS EXISTS — the short version, because it is not obvious and it cost ten
CI runs to establish:

On the simulator lane the xcconfig route does not reach the link. All of the
following are true at once, and were verified rather than assumed:

  * `#include "ffi.xcconfig"` is present in ios/Flutter/Debug.xcconfig at
    build time.
  * `xcodebuild -showBuildSettings` resolves OTHER_LDFLAGS WITH all three
    -force_load flags and every OCCT archive.
  * `ld` demonstrably runs for the Runner target (its warnings appear) and
    reports no "ignoring file" for any of our archives.
  * The archives exist, are x86_64, their members carry platform 7 / sdk 26.5,
    and the C-API marker string is inside them.
  * The produced binary nevertheless has 70 symbols total and zero
    occt_/qcad_/slvs_ — nothing of ours arrives.

Run 10 removed -exported_symbols_list as a single-variable experiment to test
the "loaded, then dead-stripped" branch. The result was identical, which rules
that branch out and leaves only: the setting never arrives at the link.

So set it where a build setting cannot be inherited away — on the target's own
build configurations. Target-level settings take precedence over xcconfig,
which is the same precedence m5 documents having been bitten by for
IPHONEOS_DEPLOYMENT_TARGET; here it is used on purpose. The xcconfig include
stays in place as well: whichever path wins, the flags are present, and that
redundancy is the point rather than an oversight.

Usage:  patch_ldflags.py <project.pbxproj> <ffi.xcconfig>
"""
import re
import sys


def ldflags_from_xcconfig(path: str) -> str:
    """The OTHER_LDFLAGS value as written by the workflow, minus the key."""
    for line in open(path):
        if line.startswith('OTHER_LDFLAGS'):
            return line.split('=', 1)[1].strip()
    raise SystemExit(f'no OTHER_LDFLAGS in {path}')


def patch(pbxproj: str, value: str) -> int:
    """Adds OTHER_LDFLAGS to every app-target build configuration.

    The app target's configurations are identified by carrying
    PRODUCT_BUNDLE_IDENTIFIER — the Pods and project-level ones do not. A
    configuration that already sets OTHER_LDFLAGS is left alone rather than
    being given a second, conflicting entry.
    """
    src = open(pbxproj).read()
    # pbxproj is a quoted string format: escape " and \ in the value.
    quoted = value.replace('\\', '\\\\').replace('"', '\\"')
    count = 0

    def repl(m: 're.Match[str]') -> str:
        nonlocal count
        body = m.group(0)
        if 'PRODUCT_BUNDLE_IDENTIFIER' not in body:
            return body
        if 'OTHER_LDFLAGS' in body:
            return body
        count += 1
        return body.replace(
            'buildSettings = {',
            'buildSettings = {\n\t\t\t\tOTHER_LDFLAGS = "%s";' % quoted,
            1)

    out = re.sub(r'buildSettings = \{.*?\n\t\t\};', repl, src, flags=re.S)
    if count:
        open(pbxproj, 'w').write(out)
    return count


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    proj, xcconfig = sys.argv[1], sys.argv[2]
    n = patch(proj, ldflags_from_xcconfig(xcconfig))
    print(f'pbxproj: OTHER_LDFLAGS written into {n} app-target '
          f'configuration(s)')
    if n == 0:
        # Loud, not silent: zero means the heuristic missed and the whole
        # point of this script was lost. A green step that changed nothing is
        # exactly the sort of thing this lane has already wasted runs on.
        raise SystemExit('FAIL: no app-target configuration was patched')
