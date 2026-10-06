#!/usr/bin/env python3
"""Build docs/icon_style_study.html: ten ribbon icons drawn in three premium directions, shown in the
Carbon Pro Neutral app mock next to the current (rejected) redesign and the original icons. Stdlib only.

    python3 tools/icon_redesign/style_study.py ICONS_JSON [OUT_HTML]

ICONS_JSON  the ORIGINAL icons, from tools/ribbon_icon_mockup/dump.dart ({"maps": {...}, "singles": {...}})
OUT_HTML    default docs/icon_style_study.html

Sources
  tools/icon_redesign/study/{mono,steel,hybrid}/<MAP.key>.svg   the three directions (this study)
  design/icons/<MAP>/<key>.svg                                  the current, rejected redesign
Reused, not rewritten
  tools/icon_redesign/build.py        Carbon Pro Neutral palettes, the _map port (shipping + SPEC §12)
  tools/palette_proposals/template.html   the app mock CSS + JS (rail, browser, viewport, tab bar)
  tools/ribbon_icon_mockup/build.py   the ribbon band CSS + JS (names-on band)
"""
import importlib.util
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
STUDY = os.path.join(HERE, 'study')
DEFAULT_OUT = os.path.join(ROOT, 'docs', 'icon_style_study.html')
ARB = os.path.join(ROOT, 'frontend', 'lib', 'l10n', 'app_en.arb')


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


IB = load('icon_build', os.path.join(HERE, 'build.py'))
PB, RB = IB.PB, IB.RB

REFS = ['IC.line34', 'IC.circle34', 'IC.rect34', 'CN.coincident', 'CN.dim',
        'CR.extrude', 'CR.revolve', 'MO.fillet', 'MO.hole', 'WF.plane']
NAMES = {'IC.line34': 'Line', 'IC.circle34': 'Circle', 'IC.rect34': 'Rectangle', 'CN.coincident': 'Coincident',
         'CN.dim': 'Dimension', 'CR.extrude': 'Extrude', 'CR.revolve': 'Revolve', 'MO.fillet': 'Fillet',
         'MO.hole': 'Hole', 'WF.plane': 'Work plane'}
DIRS = ['mono', 'steel', 'hybrid']

# ------------------------------------------------------------------ style sheets
STYLES = {
    'mono': {
        'n': 1, 'name': 'Pro Monochrome', 'bench': 'SF Symbols (hierarchical) · Shapr3D · Plasticity · Onshape 2025 · Figma',
        'idea': 'Typography, not illustration. One ink, a quieter second ink for context, and a single accent '
                'mark only where the meaning lives: the point you are placing, the face you are moving, the edge you are rounding.',
        'sheet': [
            ('Grid', '28 × 28 artboard, 24 × 24 live area (2 u margin). Solids on a 2 : 1 dimetric lattice (edges run 1 u across, ½ u up), so every iso edge lands on half-pixels at 28 and 56.'),
            ('Stroke', 'Primary 1.5 u, secondary 1.25 u, round caps and joins. No hairlines below 1.25. Lines stop 1 u short of a point marker instead of running under it.'),
            ('Palette', 'INK #E6E6E6 (primary) · SEC #8E8E8E (context: extension lines, axes, the start point) · ACC #6AA9ED (one detail) · ACC fill at 22 % for the one accented face. Nothing else.'),
            ('Lighting', 'None. Volume is told by line hierarchy and one tinted face. No gradients.'),
            ('Rules', 'Exactly one accented element per glyph, and it is the operation’s result. Never two hues. Points are 2.5 u discs (accent) or 2 u rings (secondary). No squares, no arrows except where motion is the meaning (extrude, revolve, plane normal).'),
            ('_map', 'Works with the shipping _map. Better with SPEC §12 (a): hue-less greys stop the pink cast of the light-theme ink. Needs nothing new.'),
        ],
    },
    'steel': {
        'n': 2, 'name': 'Rendered Steel', 'bench': 'Autodesk Fusion · Inventor 2025 · SolidWorks 2025 feature icons',
        'idea': 'Small product renders. Bodies are brushed-steel neutrals lit from the upper left; the feature being '
                'created or operated on is the same material in a calm engineering blue. Tools (arrows, axes) are slim flat ink.',
        'sheet': [
            ('Grid', 'Same 28-unit grid and 2 : 1 dimetric lattice as direction 1. A contact shadow sits 0–1 u under each solid; nothing crosses 1.5 / 26.5.'),
            ('Stroke', 'Material contour 1.0 u (a dark gradient, not a black line). Highlight edge 0.8 u white at 45–95 %. Tool lines 1.25 u flat ink with filled, long-tapered arrowheads.'),
            ('Palette', 'Steel: top #EDEDED→#BEBEBE, lit side #ABABAB→#858585, shade side #727272→#525252, contour #5C5C5C→#2E2E2E. Accent material: top #D3E6F9→#93BFEE, lit #7EB2E7→#4D88C8, shade #3E75B1→#26518A, contour #2A5C94→#16395F. Ink #D4D4D4, context #8E8E8E.'),
            ('Lighting', 'Key light upper left, 45°. Top faces lightest, left faces mid, right faces darkest; one specular highlight line on the leading edge; cylinders get a 4-stop band (rim dark, highlight at 30 %, falloff, shadow rim). Contact shadow: black radial 50 % → 0.'),
            ('Rules', 'Material only in gradients; flat paint is only ever ink. Accent material only on the result feature. Sketch glyphs stay line drawings, with rendered “bead” points (radial accent or steel).'),
            ('_map', 'NEEDS a new rule (data-lit, below). Under the shipping _map every grey stop is inverted on the light theme, so the light comes from below and steel becomes gunmetal.'),
        ],
    },
    'hybrid': {
        'n': 3, 'name': 'Hybrid Precision', 'bench': 'Siemens NX 2025 · SolidWorks 2025 · Reality Composer Pro',
        'idea': 'The line system of direction 1 with a quiet volume: solids get a soft neutral face fill drawn in the ink '
                'at low opacity, and the result feature is a translucent accent fill with a fine accent outline.',
        'sheet': [
            ('Grid', 'Identical to direction 1 (28 grid, 24 live, 2 : 1 dimetric).'),
            ('Stroke', 'Ink outline 1.5 u; accent outline 1.25 u (finer, so the fill carries the colour); secondary 1.25 u.'),
            ('Palette', 'INK #E6E6E6 · SEC #8E8E8E · ACC #6AA9ED. Neutral faces are the ink itself at 30→18 % (top), 16→9 % (lit side), 7→3 % (shade side). Accent fills 30–45 %.'),
            ('Lighting', 'Implied, two-tone: face order top > left > right by opacity, with a gentle diagonal gradient. Because faces are ink-at-opacity the order holds in both themes with no _map change: more ink is always more contrast.'),
            ('Rules', 'One accent family per glyph, translucent fill + fine outline, on the result only. Sketch regions (circle, rectangle) get the neutral face tint so “closed profile” reads.'),
            ('_map', 'Works with the shipping _map. SPEC §12 (a) recommended for hue-less greys. No gradient-order problem, because stop-opacity, not stop lightness, carries the shading.'),
        ],
    },
}

RULE_LIT = ('Proposed <code>_map</code> addition for direction 2, opt-in per glyph with <code>data-lit</code> on the root element: '
            'inside a data-lit SVG a <b>gradient stop</b> (<code>stop-color</code>) is <b>material</b>, not ink. A neutral stop keeps its own lightness in both themes '
            '(no inversion; hue-less; clamped .12–.92), so the key light stays upper-left on paper. A chromatic stop moves to the bucket hue like today but keeps '
            'its own lightness (clamped .22–.86) and the lower of its own and the target saturation, so the material stays muted and its ramp keeps its order. '
            '<b>Flat</b> fill / stroke colours in the same SVG are ink and go through <code>_map</code> unchanged, so arrows and axes still invert. '
            'Implementation: match <code>stop-color="#rrggbb"</code> before the generic <code>#rrggbb</code> pass in <code>themedIcon</code>; about 15 lines. '
            'This is why <code>data-fixed</code> is not the answer: it would freeze the accent at blue whatever accent the user picks.')

ALLOWED_EL = {'svg', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon', 'g', 'defs',
              'linearGradient', 'radialGradient', 'stop'}
PREFIX = {'mono': 'm', 'steel': 's', 'hybrid': 'h'}


def lint(d, ref, src):
    errs = []
    E = errs.append
    if re.search(r'<\s*(text|tspan|filter)\b', src) or 'filter=' in src:
        E('text/filter banned')
    for h in re.findall(r'#[0-9A-Fa-f]+\b', src):
        if len(h) != 7:
            E('colour %s not 6-digit' % h)
    if re.search(r'rgba?\(|hsla?\(|currentColor', src):
        E('rgb()/hsl()/currentColor banned')
    try:
        root = ET.fromstring(src)
    except ET.ParseError as e:
        return ['not XML: %s' % e]
    if root.get('viewBox') != '0 0 28 28':
        E('viewBox must be 0 0 28 28')
    for el in root.iter():
        t = el.tag.split('}')[-1]
        if t not in ALLOWED_EL:
            E('element <%s> banned' % t)
    ids = [el.get('id') for el in root.iter() if el.get('id')]
    for i in ids:
        if not i.startswith(PREFIX[d]):
            E('gradient id %s lacks the %s- prefix' % (i, PREFIX[d]))
        if re.fullmatch(r'[0-9a-fA-F]{6}.*', i):
            E('id %s starts with six hex digits: _map would rewrite url(#%s)' % (i, i))
    for u in re.findall(r'url\(#([^)]+)\)', src):
        if u not in ids:
            E('url(#%s) has no target' % u)
    return ['%s/%s: %s' % (d, ref, e) for e in errs]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        sys.exit(__doc__)
    icons = json.load(open(args[0], encoding='utf-8'))
    out = args[1] if len(args) > 1 else DEFAULT_OUT
    pals = IB.palettes()
    old = {}
    for m, v in icons['maps'].items():
        for k, s in v.items():
            old['%s.%s' % (m, k)] = s
    old.update(icons['singles'])
    cur = {}
    for r in REFS:
        p = IB.file_of(r)
        if os.path.exists(p):
            cur[r] = open(p, encoding='utf-8').read().strip()
    sets = {'old': {r: old[r] for r in REFS if r in old}, 'cur': cur}
    errs = []
    seen_ids = {}
    for d in DIRS:
        sets[d] = {}
        for r in REFS:
            p = os.path.join(STUDY, d, r + '.svg')
            if not os.path.exists(p):
                errs.append('%s/%s: missing' % (d, r))
                continue
            s = open(p, encoding='utf-8').read().strip()
            errs += lint(d, r, s)
            for i in re.findall(r'id="([^"]+)"', s):
                if i in seen_ids and seen_ids[i] != (d, r):
                    errs.append('%s/%s: id %s also used by %s/%s' % (d, r, i, *seen_ids[i]))
                seen_ids[i] = (d, r)
            sets[d][r] = s
    print('lint: %d SVGs, %d error(s)' % (sum(len(sets[d]) for d in DIRS), len(errs)))
    for e in errs:
        print('  ERROR ' + e)

    arb = json.load(open(ARB, encoding='utf-8'))
    label_keys = ['btnLine', 'btnCircle', 'btnRectangle', 'btnDimension', 'conCoincident', 'btnExtrude', 'btnRevolve',
                  'btnFillet', 'btnHole', 'btnPlane', 'panelCreate', 'panelConstrain', 'panelModify',
                  'panelWorkFeatures', 'panelSketch']
    labels = {k: arb[k] for k in label_keys if isinstance(arb.get(k), str)}
    ribbon = [
        RB.panel('panelCreate', [RB.split('IC.line34', 'btnLine', fly='line'), RB.split('IC.circle34', 'btnCircle', fly='circle'),
                                 RB.split('IC.rect34', 'btnRectangle', fly='rect')]),
        RB.panel('panelConstrain', [{'k': 'dim', 'icon': 'CN.dim', 'label': 'btnDimension'},
                                    RB.col(RB.row('CN.coincident', 'conCoincident'), pad=2)]),
        RB.panel('panelCreate', [RB.wide('CR.extrude', 'btnExtrude', 58), RB.wide('CR.revolve', 'btnRevolve', 58)]),
        RB.panel('panelModify', [RB.wide('MO.fillet', 'btnFillet', 58), RB.col(RB.row('MO.hole', 'btnHole'), pad=2)]),
        RB.panel('panelWorkFeatures', [RB.split('WF.plane', 'btnPlane', fly='plane')]),
    ]
    rbdata = {'ribbons': [], 'flyouts': {}, 'cons': [], 'intended': {}, 'labels': labels, 'flyNew': {},
              'icons': {'maps': {'IC': {}, 'PL': {}}}}
    fields = [k for k in pals['pro-neutral-dark'] if not k.startswith('_')]
    data = {
        'pals': pals, 'fields': fields, 'pid': {'dark': 'pro-neutral-dark', 'light': 'pro-neutral-light'},
        'oldAll': old, 'sets': sets, 'refs': REFS, 'names': NAMES, 'dirs': DIRS,
        'styles': STYLES, 'ruleLit': RULE_LIT, 'rb': rbdata, 'ribbon': ribbon, 'lint': errs,
    }
    ptpl = open(os.path.join(ROOT, 'tools', 'palette_proposals', 'template.html'), encoding='utf-8').read()
    pal_css = IB.between(ptpl, '<style>', '</style>')
    pal_js = IB.between(ptpl, '// ------------------------------------------------------------ colour helpers',
                        '// ---------------------------------------------------------------- viewer UI', True)
    rb_css = IB.between(RB.TEMPLATE, '/* ---- mockup palette (set from JS) ---- */', '/* atlas */', True)
    rb_js = IB.between(RB.TEMPLATE, 'const esc = s =>', '// ---------------------------------------------------------------- render', True)
    tpl = open(os.path.join(HERE, 'style_study.html'), encoding='utf-8').read()
    blob = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    html = (tpl.replace('/*__PALETTE_CSS__*/', pal_css).replace('/*__RIBBON_CSS__*/', rb_css)
            .replace('/*__PALETTE_JS__*/', pal_js).replace('/*__RIBBON_JS__*/', rb_js)
            .replace('/*__DATA__*/null', blob))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(html)
    print('wrote %s (%d bytes)' % (out, len(html)))
    if errs:
        sys.exit(1)


if __name__ == '__main__':
    main()
