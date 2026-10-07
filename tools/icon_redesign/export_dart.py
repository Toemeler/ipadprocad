#!/usr/bin/env python3
"""Generates frontend/lib/svg_icons.dart from design/icons/ (SPEC v2 "Modern Crisp").

    python3 tools/icon_redesign/export_dart.py            # write frontend/lib/svg_icons.dart
    python3 tools/icon_redesign/export_dart.py --check    # exit 1 if the file is stale (CI / pre-commit)
    python3 tools/icon_redesign/export_dart.py --out F    # write somewhere else

then `dart format frontend/lib/svg_icons.dart` (the script prints the reminder).

What goes in:

* Every v2 drawing under design/icons/<MAP>/<key>.svg becomes <MAP>['<key>'], and design/icons/single/<name>.svg
  becomes the top-level const <name>. A file listed in SUPERSEDED.txt whose content still has the listed sha256 is
  an old (v1) drawing and is skipped, as the build does. _motifs/ is reference art, never exported.
* A <key>.sm.svg (the 18 px master, SPEC §2.4) goes into `smallIcons`, keyed by its master's SVG string, and
  `iconWidget` draws it whenever the icon renders at 20 px or less.
* Every key the app had before v2 that design/icons does not redraw (PD, AC, the model-browser singles, ...) keeps
  its exact old string from tools/icon_redesign/legacy_icons.json, so nothing the app references can disappear.
  Those keys are listed in `legacyIconKeys`.

Stdlib only. Re-runnable: the output depends on design/icons and legacy_icons.json, never on its own last output.
"""
import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
DESIGN = os.path.join(ROOT, 'design', 'icons')
LEGACY = os.path.join(HERE, 'legacy_icons.json')
SUPERSEDED = os.path.join(DESIGN, 'SUPERSEDED.txt')
DEFAULT_OUT = os.path.join(ROOT, 'frontend', 'lib', 'svg_icons.dart')

# The public maps, in the order the app has always declared them. A map that design/icons adds (DE) goes after.
MAP_ORDER = ['IC', 'CN', 'IN', 'MD', 'PD', 'VW', 'MS', 'CR', 'MO', 'WF', 'PT', 'PL', 'AX', 'PN', 'AS', 'AC', 'DE']
MAP_DOC = {
    'IC': 'Sketch Create: big and small buttons, the flyout variants, Project Geometry, sketch Pattern.',
    'CN': 'Sketch Constrain: Dimension, the constraint grid and its overflow.',
    'IN': 'Sketch Insert panel and its overflow (IN[\'params\'] is the Parameters button).',
    'MD': 'Sketch Modify panel and its overflow.',
    'PD': 'Pattern / chamfer dialog glyphs (v1, not redrawn).',
    'VW': 'Appearance values (display mode, section, renderer, floor).',
    'MS': 'Measure.',
    'CR': 'Part Create panel and its overflow.',
    'MO': 'Part Modify panel and its overflow.',
    'WF': 'Work Features buttons.',
    'PT': 'Part Pattern (PT.rect / PT.mirror also serve the assembly Pattern panel).',
    'PL': 'Work Plane flyout variants.',
    'AX': 'Work Axis flyout variants (waAuto... in ribbon.dart).',
    'PN': 'Work Point flyout variants (wptAuto... in ribbon.dart).',
    'AS': 'Assembly ribbon: Component, Position, Relationships, Pattern > Copy.',
    'AC': 'Assembly Constrain and Joint dialogs (v1, not redrawn).',
    'DE': 'Part Direct edit flyout (deMove... in ribbon.dart).',
}


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def superseded():
    out = {}
    if os.path.exists(SUPERSEDED):
        for line in open(SUPERSEDED, encoding='utf-8'):
            m = re.match(r'^([0-9a-f]{64})\s+(\S+)\s*$', line)
            if m:
                out[m.group(2)] = m.group(1)
    return out


def read_design():
    """{'maps': {MAP: {key: svg}}, 'small': {MAP: {key: svg}}, 'singles': {...}, 'singles_sm': {...}}"""
    sup = superseded()
    maps, small, singles, singles_sm = {}, {}, {}, {}
    skipped = []
    for d in sorted(os.listdir(DESIGN)):
        full = os.path.join(DESIGN, d)
        if not os.path.isdir(full) or d.startswith('_'):
            continue
        for f in sorted(os.listdir(full)):
            if not f.endswith('.svg'):
                continue
            rel = '%s/%s' % (d, f)
            src = open(os.path.join(full, f), encoding='utf-8').read().strip()
            if sup.get(rel) == sha(open(os.path.join(full, f), encoding='utf-8').read()):
                skipped.append(rel)
                continue
            sm = f.endswith('.sm.svg')
            key = f[:-7] if sm else f[:-4]
            if d == 'single':
                (singles_sm if sm else singles)[key] = src
            else:
                (small if sm else maps).setdefault(d, {})[key] = src
    return maps, small, singles, singles_sm, skipped


def dart_str(s):
    if "'''" not in s and not s.endswith("'") and not s.endswith('\\'):
        return "r'''" + s + "'''"
    return json.dumps(s).replace('$', '\\$')  # a JSON string is a valid Dart string once $ is escaped


def ident(m, k, sm=False):
    return '_%s_%s%s' % (m, re.sub(r'\W', '_', k), '_sm' if sm else '')


def build():
    legacy = json.load(open(LEGACY, encoding='utf-8'))
    maps, small, singles, singles_sm, skipped = read_design()
    errs = []
    for m in maps:
        if m not in MAP_ORDER:
            errs.append('design/icons/%s is not a known map (add it to MAP_ORDER)' % m)
    for m, v in small.items():
        for k in v:
            if k not in maps.get(m, {}):
                errs.append('%s/%s.sm.svg has no master' % (m, k))
    for k in singles_sm:
        if k not in singles:
            errs.append('single/%s.sm.svg has no master' % k)
    for k in singles:
        if k not in legacy['singles']:
            errs.append('single/%s.svg is not a const the app has (legacy_icons.json)' % k)
    if errs:
        sys.exit('export_dart: ' + '\n  '.join([''] + errs))

    consts = []           # (ident, svg)
    map_entries = {}      # MAP -> [(key, ident)]
    legacy_keys = []
    small_pairs = []      # (master ident, master svg, sm ident, sm svg, ref)
    v2_count = 0
    for m in MAP_ORDER:
        old = legacy['maps'].get(m, {})
        new = maps.get(m, {})
        keys = list(old) + sorted(k for k in new if k not in old)
        if not keys:
            continue
        rows = []
        for k in keys:
            i = ident(m, k)
            if k in new:
                consts.append((i, new[k]))
                v2_count += 1
                if k in small.get(m, {}):
                    si = ident(m, k, True)
                    small_pairs.append((i, new[k], si, small[m][k], '%s.%s' % (m, k)))
            else:
                consts.append((i, old[k]))
                legacy_keys.append('%s.%s' % (m, k))
            rows.append((k, i))
        map_entries[m] = rows
    single_rows = []
    for name, src in legacy['singles'].items():
        if name in singles:
            single_rows.append((name, singles[name]))
            v2_count += 1
            if name in singles_sm:
                si = '_single_%s_sm' % name
                small_pairs.append((name, singles[name], si, singles_sm[name], name))
        else:
            single_rows.append((name, src))
            legacy_keys.append(name)

    # smallIcons is keyed by the master's SVG STRING (that is all iconWidget has). Two keys with an identical
    # master (an alias drawn without gradients) must then agree on the small master too.
    seen = {}
    small_rows = []
    for mi, msrc, si, ssrc, ref in small_pairs:
        if msrc in seen:
            if seen[msrc][1] != ssrc:
                sys.exit('export_dart: %s and %s have the same master but different .sm masters' % (seen[msrc][0], ref))
            continue
        seen[msrc] = (ref, ssrc)
        small_rows.append((mi, si))
        consts.append((si, ssrc))   # only the small masters that are reachable get a const

    n_small = len(small_rows)
    L = []
    L.append('// GENERATED FILE. DO NOT EDIT BY HAND.')
    L.append('//')
    L.append('// Generated by tools/icon_redesign/export_dart.py from design/icons/ (SPEC v2,')
    L.append('// "Modern Crisp", design/icons/SPEC.md). To change an icon, change its family')
    L.append('// generator under tools/icon_redesign/families/, rebuild design/icons, then run')
    L.append('// (from the repo root):')
    L.append('//')
    L.append('//   python3 tools/icon_redesign/export_dart.py')
    L.append('//   dart format frontend/lib/svg_icons.dart')
    L.append('//')
    L.append('// %d icons are v2 drawings. %d keys the set does not redraw (%s)' % (
        v2_count, len(legacy_keys), ', '.join(sorted({k.split('.')[0] if '.' in k else 'singles' for k in legacy_keys}))))
    L.append('// keep their exact pre-v2 strings from tools/icon_redesign/legacy_icons.json;')
    L.append('// they are listed in [legacyIconKeys]. %d icons have an 18 px master in' % n_small)
    L.append('// [smallIcons].')
    L.append('//')
    L.append('// Colours are the authored ones; icon_theme.dart maps them into the active')
    L.append('// palette at the draw site (SPEC §12). Gradient ids are g-<MAP>-<key>[-sm]-*,')
    L.append('// unique app-wide. Rendered with flutter_svg through iconWidget.')
    L.append('// ignore_for_file: constant_identifier_names, non_constant_identifier_names')
    L.append('')
    for m in MAP_ORDER:
        if m not in map_entries:
            continue
        L.append('/// %s' % MAP_DOC.get(m, m))
        L.append('const Map<String, String> %s = {' % m)
        for k, i in map_entries[m]:
            L.append("  '%s': %s," % (k, i))
        L.append('};')
        L.append('')
    for name, src in single_rows:
        L.append('const %s = %s;' % (name, dart_str(src)))
        L.append('')
    L.append('/// The 18 px master of an icon, keyed by the icon\'s own SVG string. Drawn by')
    L.append('/// iconWidget whenever the icon renders at [smallIconMaxSize] or less.')
    L.append('const Map<String, String> smallIcons = {')
    for mi, si in small_rows:
        L.append('  %s: %s,' % (mi, si))
    L.append('};')
    L.append('')
    L.append('/// The largest rendered size, in logical pixels, that uses [smallIcons].')
    L.append('const double smallIconMaxSize = 20;')
    L.append('')
    L.append('/// Keys carried over unchanged from the pre-v2 set (MAP.key, or a const name).')
    L.append('const Set<String> legacyIconKeys = {')
    for k in legacy_keys:
        L.append("  '%s'," % k)
    L.append('};')
    L.append('')
    for i, src in consts:
        L.append('const %s = %s;' % (i, dart_str(src)))
    L.append('')
    return '\n'.join(L), v2_count, len(legacy_keys), n_small, skipped


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default=DEFAULT_OUT)
    ap.add_argument('--check', action='store_true', help='compare with --out (after dart format) instead of writing')
    a = ap.parse_args()
    text, n2, nl, ns, skipped = build()
    if a.check:
        # dart format reflows the map rows, so compare the icon payload only: every string literal.
        lit = re.compile(r"r'''(.*?)'''", re.S)
        have = open(a.out, encoding='utf-8').read() if os.path.exists(a.out) else ''
        if sorted(lit.findall(have)) != sorted(lit.findall(text)):
            sys.exit('%s is stale: run python3 tools/icon_redesign/export_dart.py' % os.path.relpath(a.out, ROOT))
        print('up to date')
        return
    with open(a.out, 'w', encoding='utf-8') as f:
        f.write(text)
    print('wrote %s: %d v2 icons, %d legacy keys, %d small masters%s' % (
        os.path.relpath(a.out, ROOT), n2, nl, ns, ', skipped (superseded) %s' % skipped if skipped else ''))
    print('now: dart format %s' % os.path.relpath(a.out, ROOT))


if __name__ == '__main__':
    main()
