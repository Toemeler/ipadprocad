#!/usr/bin/env python3
"""Build docs/icon_style_study.html: ten ribbon icons drawn in three premium directions, shown in the
Carbon Pro Neutral app mock next to the current (rejected) redesign and the original icons. Stdlib only.

    python3 tools/icon_redesign/style_study.py ICONS_JSON [OUT_HTML]

ICONS_JSON  the ORIGINAL icons, from tools/ribbon_icon_mockup/dump.dart ({"maps": {...}, "singles": {...}})
OUT_HTML    default docs/icon_style_study.html

Sources
  tools/icon_redesign/study/{mono,steel,hybrid}/<MAP.key>.svg   the three directions (this study)
  tools/icon_redesign/study/steel-modern/{satin,crisp}/<MAP.key>.svg   2M, Rendered Steel - Modern (draw.py there)
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
DIRS = ['mono', 'steel', 'hybrid', 'modA', 'modB']
# 'Rendered Steel - Modern' lives in one folder with a sub-folder per sub-variant (drawn by its draw.py)
DIRPATH = {'modA': os.path.join('steel-modern', 'satin'), 'modB': os.path.join('steel-modern', 'crisp')}

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

def modern_sheet(v):
    """v: the sub-variant ('A' satin or 'B' crisp); values match study/steel-modern/draw.py."""
    a = v == 'A'
    return [
        ('Grid', '28 × 28 artboard, 24 u live area, filled: solids are 18.5–23 u wide and 19–20 u tall (old steel: 16–18). Same 2 : 1 dimetric lattice. '
                 'Every silhouette corner gets a soft fillet of %s; internal face edges stay sharp and run into the fillet’s midpoint, so faces meet with no notch.' % ('2.0 u' if a else '0.6 u')),
        ('Material', 'Matte, exactly 2 stops per face, top-left → bottom-right, no chrome band, no specular stripe, no radial bead. Faces told apart by value only. '
                     + ('Satin: soft ramps (8–12 % per face), gentler step between faces. Steel top #E4E5E7→#C6C9CD, lit #AEB2B7→#8D939A, shade #787F87→#62686F.'
                        if a else 'Crisp: near-flat faces (2–4 % per face), a decisive step between them. Steel top #ECEDEE→#E1E3E5, lit #9BA0A6→#93999F, shade #595E64→#54595F.')
                     + ' Steel is a cool grey (hue 212, S .06, under the .12 neutral line).'),
        ('Edges', 'No contour stroke at all. ' + ('No highlight either.' if a else 'One 0.6 u hairline highlight on the lit top-front edge only (white 80 → 15 %, a gradient, so it is material).')),
        ('Shadow', 'None: no contact shadow, no drop shadow, no AO. The shade face is the shadow.'),
        ('Colour', 'Cool steel + ONE accent material, a calm lighter blue, only on the feature the tool makes (extruded / revolved body, fillet, bore, plane). '
                   + ('Accent top #C9DBED→#A3C1E0, lit #8CB1D9→#5E92C9, shade #4B85C3→#386EA8 (S .50).' if a else
                      'Accent top #D0E0F1→#C0D5EC, lit #76A4D6→#6A9CD2, shade #3571B1→#3169A5 (S .54).')
                   + ' No amber, green or red in tool glyphs.'),
        ('Ink', 'Flat ink #D6D6D6, secondary #8C8C8C, flat accent #6AA9ED. Arrows 1.25 u, round caps. One arrowhead for the set: filled triangle 4 u wide × 3.4 u long, softened by a 0.5 u round-join stroke of the same ink.'),
        ('Sketch', '2D tools are line art on purpose: 1.5 u ink geometry, 1.25 u secondary construction, flat dots (start point ink r 1.9, the point you place accent r 2.4; coincident adds a 1 u accent ring). No beads, no gradients, no data-lit. The sketch rail is lighter than the 3D rail by design.'),
        ('_map', 'data-lit="2" (see _map changes): material stops keep their own hue / saturation, and on a light theme the material ramp is compressed to L′ = 0.10 + 0.70 L, so the lit top face separates from paper without an outline. Flat paint is ink, unchanged.'),
    ]


STYLES['modA'] = {
    'n': '2M·A', 'name': 'Rendered Steel — Modern · A satin',
    'bench': 'macOS Tahoe app icons · SF Symbols hierarchical · Spline · Shapr3D · Figma/Linear illustrations',
    'idea': 'What the user liked about Rendered Steel (real volume, lit steel, a product-render feel) without the 2008 render tricks: '
            'bigger, simpler, softly filleted forms in a matte satin material, separated by value alone. The softer, more Apple of the two.',
    'sheet': modern_sheet('A'),
}
STYLES['modB'] = {
    'n': '2M·B', 'name': 'Rendered Steel — Modern · B crisp',
    'bench': 'Autodesk Fusion 2025 UI refresh · Blender 4.x · Onshape · Shapr3D',
    'idea': 'The same forms and palette with flatter, more decisive planes: a 0.6 u corner, nearly flat faces with a wider value step between them, '
            'and a single hairline highlight on the lit edge. The sharper, more Fusion of the two.',
    'sheet': modern_sheet('B'),
}
DATED = [
    ('Multi-stop chrome', 'Cylinders and beads use 3–4 stop bands (rim dark, hot highlight at 30 %, falloff, dark rim): the Aqua / Vista chrome look.', '2 stops per face, 4–10 % apart: matte satin.'),
    ('Contact shadows', 'Every solid sits on a black 50 % radial ellipse: a skeuomorphic “object on a desk” cue that modern glyphs dropped around 2013.', 'No shadow at all; the shade face is the shadow.'),
    ('Outline + gradient', 'A 1 u dark contour gradient around shaded faces: the face values already define the edge, so the contour doubles it and makes the glyph look stamped.', 'No contour: faces separated by value alone (top ≈ .9 L, lit ≈ .63, shade ≈ .38).'),
    ('Specular strokes', 'A 0.8 u white 45–95 % highlight stroke on the front edges: the Windows-7 bevel, and at 28 pt it reads as a white seam.', 'None (A) or one 0.6 u hairline on the lit edge only (B).'),
    ('Small, fussy solids', 'Solids use 16–18 u of the 24 u live area with sharp corners, so a lot of rendering happens in few pixels and the shapes look busy and timid at once.', 'Solids fill up to 23 × 20 u with soft fillets; fewer, larger planes.'),
    ('Rendered beads', 'Sketch points are radial-gradient “pearls”: a glossy 3D detail on 2D line art, and the busiest thing on the sketch rail.', 'Sketch tools are clean line art with flat dots; no gradients.'),
    ('Too much blue', 'The accent material is saturated (S ≈ .66–.75) and the cylinder band runs it from navy to near white: the rail reads as glossy blue clip art.', 'One calm accent (S .50), only on the feature, own 2-stop shade.'),
]
RULE_LIT2 = ('<b>data-lit v2</b> (<code>data-lit="2"</code>; v1 glyphs keep today’s behaviour). Inside a data-lit="2" SVG a gradient <code>stop-color</code> is material: '
             '<b>(1) neutral stop</b> (S &lt; .12): keep its own hue and saturation (v1 made it hue-less; the modern steel is a faint cool grey); lightness '
             '<code>L′ = dark ? L : 0.10 + 0.70·L</code>, clamped .12–.92. <b>(2) chromatic stop</b>: bucket hue as today, saturation min(own, target), lightness '
             '<code>L′ = dark ? L : 0.10 + 0.70·L</code>, clamped .22–.86. <b>(3) flat</b> <code>fill</code> / <code>stroke</code> colours are ink and go through <code>_map</code> unchanged (arrows, sketch geometry, dots). '
             'Why the light-theme compression: with no outline, v1 keeps the lit top face at L .90 on a .91 rail, so the top of every solid melts into the paper. '
             'Compressed (crisp steel), the top lands at ≈ .75, the lit side at ≈ .54 and the shade side at ≈ .36: the same order and the same light direction, a darker material on paper, '
             'which is what Fusion and macOS do for light appearance. Dart: in <code>themedIcon</code>, read the root’s <code>data-lit</code> value and pass it to the stop-colour branch; about 6 more lines than v1.')
ALLOWED_EL = {'svg', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon', 'g', 'defs',
              'linearGradient', 'radialGradient', 'stop'}
PREFIX = {'mono': 'm', 'steel': 's', 'hybrid': 'h', 'modA': 'ra', 'modB': 'rb'}


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
            p = os.path.join(STUDY, DIRPATH.get(d, d), r + '.svg')
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
        'styles': STYLES, 'ruleLit': RULE_LIT, 'ruleLit2': RULE_LIT2, 'dated': DATED, 'rb': rbdata, 'ribbon': ribbon, 'lint': errs,
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
