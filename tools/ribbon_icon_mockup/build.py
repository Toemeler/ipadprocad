#!/usr/bin/env python3
"""Build docs/ribbon_icons_mockup.html: every ribbon icon of the app, placed in
static mockups of the ribbon (named + compact), its overflow menus and flyouts,
plus an icon atlas and computed audit notes.

Stdlib only.

    python3 tools/ribbon_icon_mockup/build.py ICONS_JSON LABELS_JSON OUT_HTML [--arb PATH]

ICONS_JSON   output of dump.dart: {"maps": {MAP: {key: svg}}, "singles": {name: svg}}
LABELS_JSON  {key: english string}. frontend/lib/l10n/app_en.arb itself works.
--arb        app_en.arb used to fill any label key LABELS_JSON lacks
             (default: frontend/lib/l10n/app_en.arb next to this repo checkout).

The ribbon layout below is transcribed from frontend/lib/widgets/ribbon.dart.
It is a static description: when the ribbon changes, update RIBBONS/FLYOUTS.
"""
import argparse
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ARB = os.path.normpath(os.path.join(HERE, '..', '..', 'frontend', 'lib', 'l10n', 'app_en.arb'))

# --------------------------------------------------------------------------
# Ribbon content (ribbon.dart). Icon refs are "MAP.key" or a single's name.
# --------------------------------------------------------------------------


def split(icon, label, fly=None, active=False):
    """_Big: big button with the 46px flyout chip under it (min width 62)."""
    return {'k': 'split', 'icon': icon, 'label': label, 'fly': fly, 'active': active}


def wide(icon, label, w, dis=False, active=False):
    """_BigWide: big button, no chip, min width w."""
    return {'k': 'wide', 'icon': icon, 'label': label, 'w': w, 'dis': dis, 'active': active}


def row(icon, label, fly=None, dis=False, glyph=None):
    """_SmallRow: 18px icon + 12.5px label + 14px chip column."""
    return {'icon': icon, 'label': label, 'fly': fly, 'dis': dis, 'glyph': glyph}


def col(*rows, pad=8):
    """smallStack; pad = the Padding(left: leftPad) the call site wraps it in (named mode only)."""
    return {'k': 'col', 'rows': list(rows), 'pad': pad}


def over(icon, label, dis=False):
    return {'icon': icon, 'label': label, 'dis': dis}


def panel(label, body, over_items=None, arrow=False, cond=None):
    return {'label': label, 'body': body, 'over': over_items, 'arrow': arrow, 'cond': cond}


CONS = [('coincident', 'conCoincident'), ('collinear', 'conCollinear'), ('concentric', 'conConcentric'),
        ('lock', 'conLock'), ('parallel', 'conParallel'), ('perp', 'conPerpendicular'),
        ('horiz', 'conHorizontal'), ('vert', 'conVertical'), ('tangent', 'conTangent'),
        ('symmetric', 'conSymmetric'), ('equal', 'conEqual')]

MEASURE = panel('panelMeasure', [wide('MS.measure', 'btnMeasure', 62)])
APPEARANCE = panel('panelAppearance', [{'k': 'appearance', 'state': 'shaded'}])


def work_features():
    return panel('panelWorkFeatures',
                 [split('WF.plane', 'btnPlane', fly='plane'),
                  col(row('WF.axis', 'btnAxis', fly='axis'), row('WF.point', 'btnPoint', fly='point'))],
                 over_items=[over('WF.ucs', 'btnUcs', dis=True)])


RIBBONS = [
    {'id': 'home', 'title': 'Home', 'note': 'Shown with no document open.',
     'panels': [panel('panelSketch', [wide('newSketchIcon', 'btnCreateNewSketch', 78)])]},
    {'id': 'sketch', 'title': 'Sketch', 'note': 'Layer edit mode of a sketch document. Line is drawn in its active (running) state. In a part\'s sketch Exit reads “Finish Sketch”.',
     'panels': [
         panel('panelLayer', [wide('layerBigIcon', 'btnStartNewLayer', 70)]),
         panel('panelCreate', [
             split('IC.line34', 'btnLine', fly='line', active=True),
             split('IC.circle34', 'btnCircle', fly='circle'),
             split('IC.arc34', 'btnArc', fly='arc'),
             split('IC.rect34', 'btnRectangle', fly='rect'),
             col(row('IC.fillet18', 'btnFillet', fly='fillet'), row('IC.text18', 'btnText', fly='text'),
                 row('IC.point18', 'btnPoint'), pad=8)]),
         panel(' ', [wide('IC.projgeo', 'btnProjectGeometry', 76)]),
         panel('panelPattern', [col(row('IC.patrect', 'btnRectangular'), row('IC.patcirc', 'btnCircular'),
                                    row('IC.patmir', 'btnMirror'), pad=2)]),
         panel('panelConstrain', [{'k': 'dim', 'icon': 'CN.dim', 'label': 'btnDimension'}, {'k': 'cons'}],
               over_items=[over('CN.smooth', 'btnSmoothG2'), over('CN.conset', 'btnConstraintSettings'),
                           over('CN.showcons', 'btnShowConstraints')]),
         panel('panelInsert', [col(row('IN.image', 'btnImage'), row('IN.acad', 'btnAcad'), pad=0),
                               col(row('IN.constr', 'btnConstruction'),
                                   row('IN.constr', 'btnParameters', glyph='fx'), pad=0),
                               col(row('IN.gear', 'btnGear'), pad=0)],
               over_items=[over('IN.points', 'btnPointsTool', True), over('IN.sphere', 'btnCenterline'),
                           over('IN.center', 'btnCenterPoint', True), over('IN.driven', 'btnDrivenDimension', True),
                           over('IN.showfmt', 'btnShowFormat', True)]),
         panel('panelModify', [col(row('MD.trim', 'btnTrim'), row('MD.split', 'btnSplitCurve'),
                                   row('MD.moffset', 'btnOffsetCurve'), pad=2)],
               over_items=[over('MD.extend', 'btnExtend'), over('MD.move', 'flyMoveB'), over('MD.copy', 'btnCopy'),
                           over('MD.mrotate', 'flyRotateB'), over('MD.mscale', 'flyScaleB'),
                           over('MD.stretch', 'btnStretch')]),
         panel('panelView', [wide('WF.plane', 'btnSliceGraphics', 74)],
               cond='only when there is a solid to slice'),
         MEASURE,
         panel('panelExit', [wide('finishIcon', 'btnFinish', 64)]),
     ]},
    {'id': 'part', 'title': 'Part', 'note': 'Appearance shown in Shaded + Edges with a body selected; with nothing selected the material chip reads “Nothing selected”, dimmed.',
     'panels': [
         panel('panelReturn', [wide('returnIcon', 'btnReturn', 64)], cond='only during in-place edit'),
         panel('panelSketch', [wide('newSketchIcon', 'btnStart2dSketch', 70)]),
         panel('panelCreate', [wide('CR.extrude', 'btnExtrude', 58), wide('CR.revolve', 'btnRevolve', 58),
                               col(row('CR.sweep', 'btnSweep'), row('CR.loft', 'btnLoft'), row('CR.coil', 'btnCoil'))],
               over_items=[over('CR.emboss', 'btnEmboss', True), over('CR.derive', 'btnDerive', True),
                           over('CR.decal', 'btnDecal', True)]),
         panel('panelModify', [wide('MO.fillet', 'btnFillet', 58),
                               col(row('MO.chamfer', 'btnChamfer'), row('MO.deleteface', 'btnDeleteFace'),
                                   row('MO.hole', 'btnHole')),
                               col(row('MO.direct', 'btnDirect', fly='direct'), pad=0)],
               over_items=[over('MO.shell', 'btnShell'), over('MO.draft', 'btnDraft', True),
                           over('MO.thread', 'btnThread', True), over('MO.combine', 'btnCombine'),
                           over('MO.thicken', 'btnThickenOffset', True), over('MO.split', 'btnSplit')]),
         work_features(),
         panel('panelPattern', [col(row('PT.rect', 'btnRectangular'), row('PT.circ', 'btnCircular'),
                                    row('PT.sketch', 'btnSketchDriven'), pad=2),
                                col(row('PT.mirror', 'btnMirror'))]),
         MEASURE,
         APPEARANCE,
     ]},
    {'id': 'assembly', 'title': 'Assembly', 'note': 'Component, Position and Relationships draw a ▼ with no menu behind it. Show Sick is drawn disabled (all relationships healthy). Appearance as on the Part tab, with a component selected.',
     'panels': [
         panel('panelComponent', [split('AS.place', 'btnPlace'), wide('AS.create', 'btnCreateComponent', 58)],
               arrow=True),
         panel('panelPosition', [col(row('AS.freemove', 'btnFreeMove'), row('AS.freerotate', 'btnFreeRotate'), pad=2)],
               arrow=True),
         panel('panelRelationships', [wide('AS.joint', 'btnJoint', 52), wide('AS.constrain', 'btnConstrain', 62),
                                      col(row('AS.show', 'btnShowRelationships'),
                                          row('AS.showsick', 'btnShowSick', dis=True),
                                          row('AS.hideall', 'btnHideAll'))],
               arrow=True),
         panel('panelPattern', [col(row('PT.rect', 'btnPatternComponent'), row('PT.mirror', 'btnMirror'),
                                    row('AS.copy', 'btnCopy'), pad=2)]),
         work_features(),
         MEASURE,
         APPEARANCE,
     ]},
]

# _buildFlyouts (ribbon.dart). (icon id, bold key, subtitle key or '')
FLYOUTS = {
    'line': [('fline', 'flyLineB', 'flyLineSub'), ('fmidline', 'flyLineB', 'flyMidlineSub'),
             ('fsplinecv', 'flySplineB', 'flySplineCvSub'), ('fsplinei', 'flySplineB', 'flySplineInterpSub'),
             ('fsplinefree', 'flySplineB', 'flySplineFreeSub'), ('feqcurve', 'flyEqCurveB', 'flyEqCurveB'),
             ('fbridge', 'flyBridgeB', 'flyBridgeB')],
    'circle': [('fcirclecp', 'flyCircleB', 'flyCenterPointSub'), ('fcircletan', 'flyCircleB', 'flyTangentSub'),
               ('fellipse', 'flyEllipseB', 'flyEllipseB')],
    'arc': [('farc3', 'flyArcB', 'flyThreePointSub'), ('farctan', 'flyArcB', 'flyTangentSub'),
            ('farccp', 'flyArcB', 'flyCenterPointSub')],
    'rect': [('frect2p', 'flyRectB', 'flyTwoPointSub'), ('frect3p', 'flyRectB', 'flyThreePointSub'),
             ('frect2pc', 'flyRectB', 'flyTwoPointCenterSub'), ('frect3pc', 'flyRectB', 'flyThreePointCenterSub'),
             ('fslotcc', 'flySlotB', 'flySlotCcSub'), ('fslotov', 'flySlotB', 'flySlotOverallSub'),
             ('fslotcp', 'flySlotB', 'flyCenterPointSub'), ('fslot3a', 'flySlotB', 'flySlot3aSub'),
             ('fslotcpa', 'flySlotB', 'flySlotCpaSub'), ('fpolygon', 'flyPolygonB', 'flyPolygonB')],
    'fillet': [('ffillet', 'flyFilletB', ''), ('fchamfer', 'flyChamferB', '')],
    'text': [('ftext', 'flyTextB', ''), ('fgtext', 'flyGeomTextB', '')],
    'direct': [('deMove', 'flyMoveB', ''), ('deSize', 'flySizeB', ''), ('deScale', 'flyScaleB', ''),
               ('deRotate', 'flyRotateB', ''), ('deDelete', 'flyDeleteB', '')],
    'axis': [('waAuto', 'flyAxisB', ''), ('waLine', 'flyAxisOnLineB', ''), ('waParPt', 'flyAxisParPtB', ''),
             ('wa2Pt', 'flyAxisTwoPtB', ''), ('wa2Pl', 'flyAxisTwoPlB', ''), ('waNormPt', 'flyAxisNormPtB', ''),
             ('waCirc', 'flyAxisCircB', ''), ('waRev', 'flyAxisRevB', '')],
    'point': [('wptAuto', 'flyPointB', ''), ('wptGround', 'flyPointGroundB', ''),
              ('wptVertex', 'flyPointVertexB', ''), ('wpt3Pl', 'flyPointThreePlB', ''),
              ('wpt2Ln', 'flyPointTwoLnB', ''), ('wptPlLn', 'flyPointPlLnB', ''), ('wptLoop', 'flyPointLoopB', ''),
              ('wptTorus', 'flyPointTorusB', ''), ('wptSphere', 'flyPointSphereB', '')],
    'plane': [('plane', 'flyPlaneB', ''), ('offset', 'flyPlaneOffsetB', ''),
              ('parallelpt', 'flyPlaneParallelPtB', ''), ('midplane2', 'flyPlaneMid2B', ''),
              ('midtorus', 'flyPlaneMidTorusB', ''), ('angleedge', 'flyPlaneAngleEdgeB', ''),
              ('threepts', 'flyPlaneThreePtsB', ''), ('twoedges', 'flyPlaneTwoEdgesB', ''),
              ('tansurfedge', 'flyPlaneTanSurfEdgeB', ''), ('tansurfpt', 'flyPlaneTanSurfPtB', ''),
              ('tanparallel', 'flyPlaneTanParallelB', ''), ('normalaxis', 'flyPlaneNormalAxisB', ''),
              ('normalcurve', 'flyPlaneNormalCurveB', '')],
}

# The drawn-but-unwired icons each fallback row was meant to show.
INTENDED = dict(zip(['waAuto', 'waLine', 'waParPt', 'wa2Pt', 'wa2Pl', 'waNormPt', 'waCirc', 'waRev'],
                    ['AX.' + k for k in ['axis', 'onedge', 'axparallel', 'twopts', 'intersect', 'normalplane',
                                         'centeredge', 'revolved']]))
INTENDED.update(zip(['wptAuto', 'wptGround', 'wptVertex', 'wpt3Pl', 'wpt2Ln', 'wptPlLn', 'wptLoop', 'wptTorus',
                     'wptSphere'],
                    ['PN.' + k for k in ['point', 'grounded', 'vertex', 'int3planes', 'int2lines', 'intplaneline',
                                         'centerloop', 'centertorus', 'centersphere']]))

MAP_DESC = {
    'IC': 'Sketch Create: the 34px big buttons, 18px small rows, the 26px flyout variants, Project Geometry and the sketch Pattern rows.',
    'CN': 'Sketch Constrain: Dimension, the constraint grid and the Constrain ▼ overflow.',
    'IN': 'Sketch Insert panel and its ▼ overflow.',
    'MD': 'Sketch Modify panel and its ▼ overflow.',
    'PD': 'Pattern / chamfer dialog glyphs. Not referenced anywhere in frontend/lib outside svg_icons.dart and the icon preview.',
    'VW': 'Appearance values (display mode, section, renderer, floor). Drawn only in compact mode; the named panel uses text chips.',
    'MS': 'Measure (sketch, part and assembly ribbons).',
    'CR': 'Part Create panel and its ▼ overflow.',
    'MO': 'Part Modify panel and its ▼ overflow.',
    'WF': 'Work Features big/small buttons (part and assembly); WF.plane also serves as Slice Graphics.',
    'PT': 'Part Pattern; PT.rect and PT.mirror are reused by the assembly Pattern panel.',
    'PL': 'Work Plane flyout variants (resolved via the IC ?? PL fallback chain).',
    'AX': 'Work Axis flyout variants (ribbon.dart flyIconOf maps waAuto… onto these keys).',
    'PN': 'Work Point flyout variants (ribbon.dart flyIconOf maps wptAuto… onto these keys).',
    'AS': 'Assembly ribbon: Component, Position, Relationships and Pattern › Copy.',
    'AC': 'Assembly Constrain and Joint dialogs (constraint_dialog.dart, joint_dialog.dart).',
}

# Where icons outside the ribbon are used (grep of frontend/lib, icon_preview.dart excluded).
EXTRA_USES = {
    'layerRowIcon': ['Model browser'],
    'sketchCubeIcon': ['Model browser', 'Tab bar', 'Home view'],
    'sharedSketchCubeIcon': ['Model browser'],
    'treeCubeIcon': ['Model browser'], 'treeRootCubeIcon': ['Model browser'], 'treeFolderIcon': ['Model browser'],
    'xAxisIcon': ['Model browser'], 'yAxisIcon': ['Model browser'], 'zAxisIcon': ['Model browser'],
    'centerPointIcon': ['Model browser'], 'endOfSketchIcon': ['Model browser'],
    'homeTabIcon': ['Tab bar', 'Viewport'], 'tabHomeIcon': ['Tab bar'],
    'asmSickIcon': ['Model browser'], 'asmConstraintIcon': ['Model browser'], 'asmSuppressedIcon': ['Model browser'],
    'assemblyMenuIcon': ['Place picker menu (non-iOS)', 'Home view'],
    'assemblyCubeIcon': ['Model browser', 'Tab bar', 'Home view'],
    'componentCubeIcon': ['Model browser'], 'groundedPinIcon': ['Model browser'], 'asmPatternIcon': ['Model browser'],
    'relationshipsIcon': ['Model browser'], 'representationsIcon': ['Model browser'],
    'viewRepActiveIcon': ['Model browser'], 'viewRepIcon': ['Model browser'], 'viewRepLockedIcon': ['Model browser'],
    'inPlaceReturnIcon': ['Model browser'], 'partCubeIcon': ['Tab bar', 'Home view', 'part_render.dart'],
    'derivedCubeIcon': ['Model browser'], 'planeIcon': ['Model browser'], 'sketch2dMenuIcon': ['Home view'],
    'part3dMenuIcon': ['Place picker menu (non-iOS)', 'Home view'],
}
MAP_EXTRA_USES = {'AC': 'Assembly constraint / joint dialogs'}

APPEARANCE_ICONS = ['VW.shaded', 'VW.rendered', 'VW.floor', 'VW.engine', 'VW.section']
EXTRA_LABEL_KEYS = ['viewFloor', 'sectionNone', 'rendererRealtime', 'rendererRaytraced', 'viewShadedEdges',
                    'viewRendered', 'matSteel']

HEX6 = re.compile(r'#([0-9a-fA-F]{6})\b')


def resolve(icons, ref):
    if '.' in ref:
        m, k = ref.split('.', 1)
        return icons['maps'].get(m, {}).get(k)
    return icons['singles'].get(ref)


def fly_resolve(icons, key):
    if key in icons['maps']['IC']:
        return 'IC.' + key, False
    # mirrors flyIconOf in frontend/lib/widgets/ribbon.dart: IC, DE, AX / PN (INTENDED), PL
    if key in icons['maps'].get('DE', {}):
        return 'DE.' + key, False
    if key in INTENDED:
        return INTENDED[key], False
    if key in icons['maps']['PL']:
        return 'PL.' + key, False
    return 'IC.line34', True


def usage_index(icons, labels):
    """ref -> list of (where, named render size px)."""
    uses = collections.defaultdict(list)
    for rb in RIBBONS:
        for p in rb['panels']:
            where = '%s › %s' % (rb['title'], labels.get(p['label'], p['label']).strip() or '(untitled)')
            for it in p['body']:
                if it['k'] in ('split', 'wide', 'dim'):
                    uses[it['icon']].append((where, 34, it['label']))
                elif it['k'] == 'col':
                    for r in it['rows']:
                        if r['glyph']:
                            continue
                        uses[r['icon']].append((where, 18, r['label']))
                elif it['k'] == 'cons':
                    for k, lk in CONS:
                        uses['CN.' + k].append((where + ' grid', 18, lk))
                elif it['k'] == 'appearance':
                    for ref in APPEARANCE_ICONS:
                        uses[ref].append((where + ' (compact only)', 28, None))
            for o in p['over'] or []:
                uses[o['icon']].append((where + ' ▼ menu', 18, o['label']))
    for fid, items in FLYOUTS.items():
        for key, b, sub in items:
            ref, fb = fly_resolve(icons, key)
            uses[ref].append(('%s flyout%s' % (fid.capitalize(), ' (fallback)' if fb else ''), 26, (b, sub)))
    # dedupe preserving order (Measure/Appearance/Work Features appear on several tabs)
    out = {}
    for ref, lst in uses.items():
        seen, ded = set(), []
        for u in lst:
            if u not in seen:
                seen.add(u)
                ded.append(u)
        out[ref] = ded
    return out


def labels_of(it_labels, used_keys):
    return {k: it_labels[k] for k in sorted(used_keys) if k in it_labels}


def collect_label_keys():
    keys = set(EXTRA_LABEL_KEYS)
    for rb in RIBBONS:
        for p in rb['panels']:
            keys.add(p['label'])
            for it in p['body']:
                if 'label' in it:
                    keys.add(it['label'])
                for r in it.get('rows', []):
                    keys.add(r['label'])
            for o in p['over'] or []:
                keys.add(o['label'])
    for items in FLYOUTS.values():
        for _, b, s in items:
            keys.update([b, s])
    keys.update(k for _, k in CONS)
    keys.discard('')
    keys.discard(' ')
    return keys


def audit(icons, uses, labels):
    allic = [('%s.%s' % (m, k), s) for m, v in icons['maps'].items() for k, s in v.items()]
    allic += list(icons['singles'].items())
    vb = collections.Counter()
    vb_of = {}
    for ref, s in allic:
        m = re.search(r'viewBox="([^"]*)"', s)
        parts = m.group(1).split() if m else []
        size = parts[2] if len(parts) == 4 and parts[2] == parts[3] else (m.group(1) if m else 'none')
        vb[size] += 1
        vb_of[ref] = m.group(1) if m else None
    buckets = collections.OrderedDict((k, vb.get(k, 0)) for k in ['34', '26', '18', '16'])
    other = {k: v for k, v in vb.items() if k not in buckets}
    hex_all = []
    for _, s in allic:
        hex_all += HEX6.findall(s)
    distinct_ci = sorted(set('#' + h.upper() for h in hex_all))
    distinct_cs = set(hex_all)
    short_hex = collections.defaultdict(list)
    for ref, s in allic:
        for h in re.findall(r'#[0-9a-fA-F]+\b', s):
            if len(h) != 7:
                short_hex[h].append(ref)
    texts = []
    for ref, s in allic:
        if '<text' in s:
            texts.append({'ref': ref, 'fonts': sorted(set(re.findall(r'font-family="([^"]*)"', s))),
                          'glyphs': re.findall(r'<text[^>]*>([^<]*)</text>', s)})
    fixed = [ref for ref, s in allic if 'data-fixed' in s]
    by_svg = collections.defaultdict(list)
    for ref, s in allic:
        by_svg[s].append(ref)
    dups = [refs for refs in by_svg.values() if len(refs) > 1]
    fallback_rows = {fid: sum(1 for k, _, _ in items if fly_resolve(icons, k)[1]) for fid, items in FLYOUTS.items()}
    fallback_rows = {k: v for k, v in fallback_rows.items() if v}
    reused = {}
    for ref, lst in uses.items():
        names = []
        for _, _, lab in lst:
            if lab is None:
                continue
            name = (' '.join(labels[x] for x in lab if x and x in labels) if isinstance(lab, tuple)
                    else labels.get(lab, lab)).replace('\n', ' ')
            if name not in names:
                names.append(name)
        if len(names) > 1:
            reused[ref] = names
    # every named-mode placement whose render size differs from the icon's own viewBox
    scaled = []
    for ref, lst in sorted(uses.items()):
        vbs = vb_of.get(ref)
        if not vbs:
            continue
        n = float(vbs.split()[2])
        sizes = sorted(set(sz for w, sz, _ in lst if 'compact only' not in w))
        for sz in sizes:
            if abs(sz - n) > 0.01:
                scaled.append({'ref': ref, 'vb': n, 'px': sz, 'factor': round(sz / n, 3)})
    ribbon_refs = set(uses)
    unreferenced = []
    for ref, _ in allic:
        if ref in ribbon_refs:
            continue
        if ref in EXTRA_USES or ref.split('.')[0] in MAP_EXTRA_USES:
            continue
        unreferenced.append(ref)
    return {
        'total': len(allic),
        'perMap': {m: len(v) for m, v in icons['maps'].items()},
        'singles': len(icons['singles']),
        'viewBox': buckets, 'viewBoxOther': other,
        'hexOccurrences': len(hex_all), 'distinctHex': len(distinct_ci), 'distinctHexCaseSensitive': len(distinct_cs),
        'hexList': distinct_ci, 'shortHex': short_hex,
        'textIcons': texts, 'fixed': fixed, 'duplicates': dups,
        'fallbackRows': fallback_rows, 'reused': reused, 'scaled': scaled, 'unreferenced': unreferenced,
        'viewBoxOf': vb_of,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('icons')
    ap.add_argument('labels')
    ap.add_argument('out')
    ap.add_argument('--arb', default=DEFAULT_ARB)
    a = ap.parse_args()
    icons = json.load(open(a.icons, encoding='utf-8'))
    labels = {k: v for k, v in json.load(open(a.labels, encoding='utf-8')).items() if isinstance(v, str)}
    keys = collect_label_keys()
    missing = [k for k in keys if k not in labels]
    if missing and os.path.exists(a.arb):
        arb = json.load(open(a.arb, encoding='utf-8'))
        for k in missing:
            if isinstance(arb.get(k), str):
                labels[k] = arb[k]
    still = sorted(k for k in keys if k not in labels)
    if still:
        print('warning: no English string for: ' + ', '.join(still), file=sys.stderr)
    # every icon reference in the spec must resolve
    bad = []
    for rb in RIBBONS:
        for p in rb['panels']:
            refs = [it.get('icon') for it in p['body']] + [r['icon'] for it in p['body'] for r in it.get('rows', [])]
            refs += [o['icon'] for o in p['over'] or []]
            bad += [r for r in refs if r and resolve(icons, r) is None]
    bad += [r for r in list(INTENDED.values()) + APPEARANCE_ICONS if resolve(icons, r) is None]
    if bad:
        sys.exit('unresolved icon refs: ' + ', '.join(sorted(set(bad))))

    uses = usage_index(icons, labels)
    aud = audit(icons, uses, labels)
    data = {
        'icons': icons, 'labels': labels_of(labels, keys), 'ribbons': RIBBONS, 'cons': CONS,
        'flyouts': FLYOUTS, 'intended': INTENDED, 'mapDesc': MAP_DESC,
        'uses': {k: [[w, sz] for w, sz, _ in v] for k, v in uses.items()},
        'extraUses': EXTRA_USES, 'mapExtraUses': MAP_EXTRA_USES, 'appearanceIcons': APPEARANCE_ICONS,
        'audit': aud,
    }
    blob = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    html = TEMPLATE.replace('/*__DATA__*/null', blob)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, 'w', encoding='utf-8') as f:
        f.write(html)
    print('wrote %s (%d bytes, %d icons)' % (a.out, len(html), aud['total']))
    print('viewBox: %s other: %s' % (dict(aud['viewBox']), aud['viewBoxOther']))
    print('distinct hex: %d (case-insensitive), %d case-sensitive, %d occurrences; short: %s' % (
        aud['distinctHex'], aud['distinctHexCaseSensitive'], aud['hexOccurrences'],
        {k: len(v) for k, v in aud['shortHex'].items()}))
    print('text icons: %s' % [(t['ref'], t['fonts']) for t in aud['textIcons']])
    print('duplicates: %s' % aud['duplicates'])
    print('fallback rows: %s' % aud['fallbackRows'])
    print('unreferenced: %s' % aud['unreferenced'])
    print('scaled placements: %d' % len(aud['scaled']))
    print('one glyph, several commands: %s' % aud['reused'])


TEMPLATE = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ribbon Icon Mockup</title>
<style>
:root {
  --pg-bg: #f6f5f2; --pg-card: #ffffff; --pg-text: #1d1f21; --pg-dim: #62666b; --pg-line: #e2dfd9;
  --pg-accent: #0f6a70; --pg-warn-bg: #fdf0d8; --pg-warn: #8a4b00; --pg-code: #efede8;
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --pg-bg: #161514; --pg-card: #1f1d1b; --pg-text: #e9e5de; --pg-dim: #a39c91; --pg-line: #34302b;
    --pg-accent: #4fc1ba; --pg-warn-bg: #3b2b12; --pg-warn: #f2c27a; --pg-code: #2a2724;
  }
}
:root[data-theme="dark"] {
  --pg-bg: #161514; --pg-card: #1f1d1b; --pg-text: #e9e5de; --pg-dim: #a39c91; --pg-line: #34302b;
  --pg-accent: #4fc1ba; --pg-warn-bg: #3b2b12; --pg-warn: #f2c27a; --pg-code: #2a2724;
}
* { box-sizing: border-box; }
html, body { margin: 0; overflow-x: hidden; }
body { background: var(--pg-bg); color: var(--pg-text); font: 14px/1.5 var(--font); }
main { max-width: 1280px; margin: 0 auto; padding: 0 16px 64px; }
header.top { padding: 28px 0 8px; }
h1 { font-size: 22px; margin: 0 0 4px; letter-spacing: -.01em; }
h2 { font-size: 17px; margin: 36px 0 10px; display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
h2 small, .sub { color: var(--pg-dim); font-weight: 400; font-size: 13px; }
h3 { font-size: 15px; margin: 28px 0 2px; }
p { margin: 6px 0; }
code { font-family: var(--mono); font-size: 12px; background: var(--pg-code); padding: 1px 4px; border-radius: 3px; }
.lede { color: var(--pg-dim); max-width: 760px; }
nav.toc { display: flex; gap: 14px; flex-wrap: wrap; font-size: 13px; margin: 8px 0 0; }
nav.toc a { color: var(--pg-accent); text-decoration: none; }

/* ---- controls ---- */
.controls { position: sticky; top: 0; z-index: 10; background: var(--pg-bg); border-bottom: 1px solid var(--pg-line);
  padding: 10px 0; display: flex; flex-wrap: wrap; gap: 10px 22px; align-items: center; }
.ctl { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--pg-dim); }
.seg { display: inline-flex; border: 1px solid var(--pg-line); border-radius: 7px; overflow: hidden; background: var(--pg-card); }
.seg button { font: inherit; font-size: 13px; color: var(--pg-text); background: none; border: 0; padding: 5px 11px; cursor: pointer; }
.seg button + button { border-left: 1px solid var(--pg-line); }
.seg button[aria-pressed="true"] { background: var(--pg-accent); color: #fff; }
.ctl input { accent-color: var(--pg-accent); }

/* ---- mockup palette (set from JS) ---- */
.mock { background: var(--m-bg); border-radius: 8px; overflow: hidden; border: 1px solid var(--pg-line); color: var(--m-text); }
.scroller { overflow-x: auto; overflow-y: hidden; }
.zoom { position: relative; zoom: var(--z, 1); width: max-content; }
.band { display: flex; align-items: stretch; background: var(--m-panel); width: max-content; border-bottom: 1px solid var(--m-sep);
  font-family: var(--font); color: var(--m-text); line-height: 1.2; }
.annot { position: relative; height: 34px; }
.annot .cond { position: absolute; top: 3px; border-top: 1px dashed var(--m-dim); color: var(--m-dim); font-size: 10.5px;
  padding: 3px 2px 0; text-align: center; line-height: 1.25; }
.panel { display: flex; flex-direction: column; }
.panel + .panel { border-left: 1px solid var(--m-psep); }
.pbody { flex: 1; display: flex; align-items: stretch; }
.named .pbody { padding: 6px 10px 2px 10px; }
.ptitle { display: flex; justify-content: center; align-items: center; font-size: 12px; color: var(--m-dim); padding: 3px 0 5px; white-space: nowrap; line-height: 1.2; }
.ptitle .tri { font-size: 8px; margin-left: 6px; }
.compact .pbody { padding: 3px 4px; align-items: center; justify-content: center; gap: 2px; }
.compact .ptitle { height: 15px; padding: 0; font-size: 10px; }
.compact .ptitle .tri { font-size: 10px; margin: 0; }

/* icons */
.ico { display: inline-block; position: relative; flex: none; line-height: 0; }
.ico > svg { width: 100%; height: 100%; display: block; overflow: visible; }
.ico.dis > svg, .dis > .ico > svg, .fxg.dis { opacity: .38; }
.ico.broken { outline: 2px solid #ff2d55; }
.bounds .ico { outline: 1px solid rgba(255, 45, 140, .75); outline-offset: 0; }
.bounds .ico::after { content: ""; position: absolute; inset: 0; pointer-events: none;
  background:
    linear-gradient(to right, transparent calc(50% - .5px), rgba(255,45,140,.75) calc(50% - .5px), rgba(255,45,140,.75) calc(50% + .5px), transparent calc(50% + .5px)),
    linear-gradient(to bottom, transparent calc(50% - .5px), rgba(255,45,140,.75) calc(50% - .5px), rgba(255,45,140,.75) calc(50% + .5px), transparent calc(50% + .5px)); }

/* named buttons */
.b { border: 1px solid transparent; border-radius: 2px; }
.b.act { background: var(--m-actbg); border-color: var(--m-actol); }
.big { display: flex; flex-direction: column; align-items: center; }
.big .bcol { display: flex; flex-direction: column; align-items: center; }
.blbl { margin-top: 3px; padding: 0 5px; font-size: 11.5px; line-height: 1.15; white-space: pre; text-align: center; }
.dis .blbl, .dis .slbl { color: var(--m-dim); }
.chip { display: flex; align-items: center; justify-content: center; flex: none; }
.pill { display: flex; align-items: center; justify-content: center; background: var(--m-h6); border: 1px solid var(--m-b10); border-radius: 6px; }
.pill svg { display: block; fill: var(--m-dim); }
.stack { display: flex; flex-direction: column; justify-content: center; gap: 2px; }
.srow { height: 26px; display: flex; align-items: center; }
.shit { display: flex; align-items: center; padding: 0 4px; border-radius: 2px; border: 1px solid transparent; }
.shit .slot { width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; }
.slbl { margin-left: 6px; font-size: 12.5px; white-space: nowrap; line-height: 1.2; }
.fxg { color: var(--m-accent); font-size: 14px; line-height: 1; font-style: italic; font-weight: 700; white-space: nowrap; }
.cgrid { display: grid; grid-template-columns: repeat(4, 30px); grid-auto-rows: 27px; gap: 1px; align-self: center; margin-left: 6px; }
.cgrid .b { display: flex; align-items: center; justify-content: center; }

/* appearance (named) */
.appcol { display: inline-flex; flex-direction: column; justify-content: center; gap: 4px; align-self: center; }
.achip { display: flex; align-items: center; padding: 6px 6px 6px 8px; background: var(--m-h6); border: 1px solid var(--m-b10); border-radius: 6px; font-size: 12px; white-space: nowrap; }
.achip .al { flex: 1; }
.achip .tri { font-size: 8px; color: var(--m-dim); margin-left: 6px; }
.achip .acc { color: var(--m-accent); }
.sw { display: inline-block; border-radius: 50%; border: .5px solid var(--m-sep); flex: none; }
.floor { display: flex; align-items: center; font-size: 11px; white-space: nowrap; }
.floor .box { width: 13px; height: 13px; border-radius: 2px; display: flex; align-items: center; justify-content: center; margin-right: 5px; }

/* compact cells */
.cell { width: 36px; height: 36px; border-radius: 6px; border: 1px solid transparent; position: relative; display: flex; align-items: center; justify-content: center; flex: none; }
.cell.act { background: var(--m-actbg); border-color: var(--m-actol); }
.cell .cmark { position: absolute; right: 2px; bottom: 0; font-size: 9px; line-height: 1; color: var(--m-dim); }
.cell.dis .cmark { opacity: .4; }
.cgrid2 { display: flex; flex-direction: column; gap: 2px; align-items: center; }
.cgrid2 > div { display: flex; gap: 2px; }

/* menus */
.menus { border-top: 1px solid var(--m-sep); }
.menus-in { line-height: 1.2; display: flex; flex-wrap: wrap; gap: 22px 28px; padding: 14px 16px 18px; align-items: flex-start; }
.mblk { margin: 0; }
.mblk figcaption { font-size: 11.5px; color: var(--m-dim); margin-bottom: 6px; font-family: var(--font); }
.omenu { display: inline-flex; flex-direction: column; min-width: 170px; max-width: 320px; background: var(--m-fly); border: 1px solid var(--m-sep); font-family: var(--font); }
.orow { display: flex; align-items: center; padding: 7px 14px 7px 10px; border-bottom: 1px solid var(--m-h6); background: var(--m-fly); }
.orow:last-child { border-bottom: 0; }
.orow .olbl { margin-left: 10px; font-size: 12.5px; line-height: 1.25; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.orow.dis .olbl { color: var(--m-dim); }
.orow.tall { height: 40px; padding: 0 16px; border: 0; }
.fmenu { display: grid; align-items: stretch; font-family: var(--font); }
.frow { display: flex; align-items: center; background: var(--m-fly); padding: 7px 14px 7px 10px; border-left: 1px solid var(--m-sep); border-right: 1px solid var(--m-sep); border-bottom: 1px solid var(--m-h6); min-width: 186px; max-width: 320px; }
.frow.one { padding: 8px 14px 8px 10px; }
.frow.first { background: var(--m-flyhov); border-top: 1px solid var(--m-sep); }
.frow.last { border-bottom: 1px solid var(--m-sep); }
.frow .ft { margin-left: 10px; display: flex; flex-direction: column; white-space: nowrap; }
.frow .fb { font-size: 12.5px; line-height: 1.25; }
.frow:not(.one) .fb { font-weight: 600; }
.frow .fs { font-size: 12px; line-height: 1.25; color: var(--m-dim); }
.fann { display: flex; align-items: center; gap: 8px; padding-left: 12px; font-size: 11.5px; color: var(--m-dim); white-space: nowrap; }
.badge { background: #f7c948; color: #3a2a00; border-radius: 4px; padding: 1px 6px; font-weight: 600; font-size: 10.5px; font-family: var(--font); }
.intended { display: inline-flex; padding: 2px; border: 1px dashed var(--m-dim); border-radius: 3px; }
.fann code { background: none; padding: 0; color: var(--m-text); font-size: 11px; }

/* atlas */
.agrid { align-items: start; display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 10px; margin-top: 10px; }
.acard { background: var(--pg-card); border: 1px solid var(--pg-line); border-radius: 8px; overflow: hidden; display: flex; flex-direction: column; min-width: 0; }
.acard .stage { background: var(--m-panel); display: flex; align-items: flex-end; justify-content: center; gap: 18px; padding: 14px 10px 12px; min-height: 96px; }
.acard .stage .sz { display: flex; flex-direction: column; align-items: center; gap: 4px; font-size: 10px; color: var(--m-dim); }
.acard .cap { padding: 7px 9px 9px; font-size: 11.5px; line-height: 1.35; overflow-wrap: anywhere; }
.acard .key { font-family: var(--mono); font-size: 12px; font-weight: 600; }
.acard .vb { color: var(--pg-dim); font-family: var(--mono); font-size: 11px; }
.acard ul { margin: 4px 0 0; padding: 0 0 0 14px; color: var(--pg-dim); }
.acard .warn { color: var(--pg-warn); }
.mapdesc { color: var(--pg-dim); margin: 0; font-size: 13px; }

/* audit */
.audit { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; }
.acell { background: var(--pg-card); border: 1px solid var(--pg-line); border-radius: 8px; padding: 12px 14px; min-width: 0; overflow-wrap: anywhere; }
.acell h4 { margin: 0 0 6px; font-size: 13.5px; }
.acell .big-n { font-size: 26px; font-weight: 650; line-height: 1.1; font-variant-numeric: tabular-nums; }
.acell ul { margin: 6px 0 0; padding-left: 18px; }
.acell li { margin: 2px 0; }
.bar { display: grid; grid-template-columns: 52px 1fr 34px; align-items: center; gap: 8px; font-size: 12.5px; margin: 3px 0; font-variant-numeric: tabular-nums; }
.bar span.track { background: var(--pg-code); height: 10px; border-radius: 5px; overflow: hidden; }
.bar span.fill { display: block; height: 100%; background: var(--pg-accent); }
.swatches { display: flex; flex-wrap: wrap; gap: 3px; margin-top: 8px; }
.swatches i { width: 16px; height: 16px; border-radius: 3px; display: inline-block; border: 1px solid rgba(128,128,128,.35); }
.acell .iconrow { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; align-items: center; }
.acell .iconrow .tile { background: var(--m-panel); padding: 5px; border-radius: 4px; display: inline-flex; }
table.t { border-collapse: collapse; font-size: 12.5px; width: 100%; }
table.t td, table.t th { text-align: left; padding: 3px 6px 3px 0; border-bottom: 1px solid var(--pg-line); vertical-align: top; }
footer { color: var(--pg-dim); font-size: 12px; margin-top: 40px; }
@media (max-width: 600px) { h1 { font-size: 19px; } .controls { gap: 8px 14px; } }
</style>
</head>
<body>
<main>
<header class="top">
  <h1>Ribbon icon mockup</h1>
  <p class="lede">Every ribbon icon of the app, placed in static copies of the ribbon (<code>widgets/ribbon.dart</code>), with all overflow menus and flyouts drawn open underneath. It is the baseline for the icon redesign. Icons are recoloured with a JavaScript port of <code>icon_theme.dart</code>; hover any glyph to see its key.</p>
  <nav class="toc"><a href="#rb-home">Home</a><a href="#rb-sketch">Sketch</a><a href="#rb-part">Part</a><a href="#rb-assembly">Assembly</a><a href="#atlas">Icon atlas</a><a href="#audit">Audit notes</a></nav>
</header>
<div class="controls" role="toolbar" aria-label="Mockup controls">
  <div class="ctl">Palette <span class="seg" data-ctl="pal"><button data-v="ember">Ember</button><button data-v="chalk">Chalk</button><button data-v="source">Source (unmapped)</button></span></div>
  <div class="ctl">Labels <span class="seg" data-ctl="mode"><button data-v="named">Named</button><button data-v="compact">Compact</button></span></div>
  <div class="ctl">Zoom <span class="seg" data-ctl="zoom"><button data-v="1">1×</button><button data-v="1.5">1.5×</button><button data-v="2">2×</button></span></div>
  <label class="ctl"><input type="checkbox" id="bounds"> Show icon bounds</label>
</div>
<div id="ribbons"></div>
<section id="atlas"><h2>Icon atlas <small id="atlas-count"></small></h2>
  <p class="lede">Each icon at its native viewBox size and at 2×, on the palette's panel colour. "Used in" lists the placements in the mockups above (with the size the ribbon draws it at in named mode) plus known uses outside the ribbon.</p>
  <div id="atlas-body"></div>
</section>
<section id="audit"><h2>Audit notes <small>computed from the icon data at build time</small></h2>
  <div class="audit" id="audit-body"></div>
</section>
<footer>Generated by <code>tools/ribbon_icon_mockup/build.py</code> from <code>frontend/lib/svg_icons.dart</code> and <code>app_en.arb</code>. Static transcription of <code>ribbon.dart</code>; the ribbon spec lives in build.py.</footer>
</main>
<script>
const DATA = /*__DATA__*/null;

// ---------------------------------------------------------------- palettes
const PAL = {
  ember: { bg: '#24211D', panel: '#2C2823', fly: '#1B1815', flyHov: '#35302A', text: '#EDE6D9', dim: '#A09686',
    sep: '#141210', panelSep: '#3A342D', accent: '#2FA9A2', h6: 'rgba(255,255,255,0.059)', h7: 'rgba(255,255,255,0.071)',
    b10: 'rgba(255,255,255,0.102)', actBg: '#3E3831', actOl: '#4E8C88', solid: '#9A9384', dark: true,
    ink: '#EDE6D9', ok: '#4E9B4A', projRef: '#D98A4A', err: '#F0675F' },
  chalk: { bg: '#EDEBE6', panel: '#F5F4F0', fly: '#FFFFFF', flyHov: '#F1EFEA', text: '#1C1E20', dim: '#5C6165',
    sep: '#D9D6CF', panelSep: '#E3E0D9', accent: '#0F6A70', h6: 'rgba(0,0,0,0.039)', h7: 'rgba(0,0,0,0.051)',
    b10: 'rgba(0,0,0,0.102)', actBg: '#D9E9E7', actOl: '#4E9490', solid: '#C0C4C7', dark: false,
    ink: '#1C1E20', ok: '#26762F', projRef: '#A0561F', err: '#AB2A3C' },
};
PAL.source = Object.assign({}, PAL.ember, { unmapped: true });

// ------------------------------------------- Flutter HSLColor, ported 1:1
function hexRgb(h) { const v = parseInt(h.replace('#', ''), 16); return [(v >> 16) & 255, (v >> 8) & 255, v & 255]; }
function hslFrom(hex) {
  const [R, G, B] = hexRgb(hex).map(x => x / 255);
  const max = Math.max(R, G, B), min = Math.min(R, G, B), delta = max - min;
  let hue;
  if (max === 0) hue = 0;
  else if (max === R) hue = 60 * ((((G - B) / delta) % 6 + 6) % 6);   // Dart % is non-negative
  else if (max === G) hue = 60 * (((B - R) / delta) + 2);
  else hue = 60 * (((R - G) / delta) + 4);
  if (Number.isNaN(hue)) hue = 0;
  const l = (max + min) / 2;
  const s = l === 1 ? 0 : Math.min(1, Math.max(0, delta / (1 - Math.abs(2 * l - 1))));
  return { h: hue, s: Number.isNaN(s) ? 0 : s, l };
}
function hslToHex({ h, s, l }) {
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const secondary = chroma * (1 - Math.abs(((h / 60) % 2) - 1));
  const match = l - chroma / 2;
  let r, g, b;
  if (h < 60) [r, g, b] = [chroma, secondary, 0];
  else if (h < 120) [r, g, b] = [secondary, chroma, 0];
  else if (h < 180) [r, g, b] = [0, chroma, secondary];
  else if (h < 240) [r, g, b] = [0, secondary, chroma];
  else if (h < 300) [r, g, b] = [secondary, 0, chroma];
  else [r, g, b] = [chroma, 0, secondary];
  const c = x => Math.round((x + match) * 255).toString(16).padStart(2, '0');
  return '#' + c(r) + c(g) + c(b);
}
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
// icon_theme.dart _map
function mapHex(rrggbb, p) {
  const src = hslFrom(rrggbb);
  const light = !p.dark;
  if (src.s < 0.12) {
    const l = light ? 1 - src.l : src.l;
    const ink = hslFrom(p.ink);
    return hslToHex({ h: ink.h, s: 0.04, l: clamp(l, 0.12, 0.92) });
  }
  const h = src.h;
  let target;
  if (h >= 175 && h < 265) target = p.accent;
  else if (h >= 75 && h < 175) target = p.ok;
  else if (h >= 18 && h < 75) target = p.projRef;
  else target = p.err;
  const t = hslFrom(target);
  const l = light ? clamp(0.16 + src.l * 0.30, 0.16, 0.46) : clamp(src.l, 0.32, 0.82);
  return hslToHex({ h: t.h, l, s: clamp(t.s * 0.85 + src.s * 0.15, 0.25, 0.95) });
}

// ------------------------------------------------------------------ state
const state = { pal: 'ember', mode: 'named', zoom: '1', bounds: false };
try { const s = JSON.parse(localStorage.getItem('ribbonMockup') || '{}'); Object.assign(state, s); } catch (e) {}
const save = () => { try { localStorage.setItem('ribbonMockup', JSON.stringify(state)); } catch (e) {} };
let P = PAL[state.pal] || PAL.ember;
const themeCache = {};

const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const L = k => (k in DATA.labels ? DATA.labels[k] : k);
const flat = s => s.replace(/\n/g, ' ');
function svgOf(ref) {
  const i = ref.indexOf('.');
  return i > 0 ? (DATA.icons.maps[ref.slice(0, i)] || {})[ref.slice(i + 1)] : DATA.icons.singles[ref];
}
function themed(svg) {
  if (P.unmapped || svg.includes('data-fixed')) return svg;
  const cache = themeCache[state.pal] || (themeCache[state.pal] = new Map());
  let out = cache.get(svg);
  if (!out) { out = svg.replace(/#([0-9a-fA-F]{6})\b/g, (m, g) => mapHex(g, P)); cache.set(svg, out); }
  return out;
}
function ico(ref, size, cls = '', title = ref) {
  const s = svgOf(ref);
  if (!s) { console.error('missing icon', ref); return `<span class="ico broken" style="width:${size}px;height:${size}px" title="missing ${esc(ref)}"></span>`; }
  return `<span class="ico${cls ? ' ' + cls : ''}" style="width:${size}px;height:${size}px" title="${esc(title)}">${themed(s)}</span>`;
}
const arrow = sz => `<svg width="${sz}" height="${sz}" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 10l5 5 5-5z"/></svg>`;
function dropChip(w) {   // _DropChip
  const narrow = w < 24;
  return `<div class="chip" style="width:${w}px;height:26px"><div class="pill" style="width:${w}px;height:${narrow ? 24 : 20}px">${arrow(narrow ? 14 : 18)}</div></div>`;
}
const fxGlyph = dis => `<span class="fxg${dis ? ' dis' : ''}">fx</span>`;
const hasFly = id => !!id && !!DATA.flyouts[id];

// ------------------------------------------------------------ named band
function namedItem(it) {
  switch (it.k) {
    case 'split': return `<div class="b big${it.active ? ' act' : ''}" style="min-width:62px"><div class="bcol" style="padding-top:4px">${ico(it.icon, 34)}<div class="blbl">${esc(L(it.label))}</div>${dropChip(46)}</div></div>`;
    case 'wide': return `<div class="b big${it.active ? ' act' : ''}${it.dis ? ' dis' : ''}" style="min-width:${it.w}px"><div class="bcol" style="padding:6px 0 4px">${ico(it.icon, 34)}<div class="blbl">${esc(L(it.label))}</div></div></div>`;
    case 'dim': return `<div class="b big" style="min-width:66px"><div class="bcol" style="padding-top:4px">${ico(it.icon, 34)}<div class="blbl">${esc(L(it.label))}</div></div></div>`;
    case 'col': return `<div class="stack" style="padding-left:${it.pad}px">${it.rows.map(namedRow).join('')}</div>`;
    case 'cons': {
      const cells = DATA.cons.map(([k, lk]) => `<div class="b" title="${esc(L(lk))}">${ico('CN.' + k, 18, '', 'CN.' + k + ' — ' + L(lk))}</div>`);
      return `<div class="cgrid">${cells.join('')}<div></div></div>`;
    }
    case 'appearance': return namedAppearance(it.state);
  }
  return '';
}
function namedRow(r) {
  const glyph = r.glyph ? fxGlyph(r.dis) : ico(r.icon, 18, r.dis ? 'dis' : '');
  const chip = r.fly && !r.dis ? dropChip(14) : '<span style="width:14px;flex:none"></span>';
  return `<div class="srow${r.dis ? ' dis' : ''}"><div class="shit"><span class="slot">${glyph}</span><span class="slbl">${esc(L(r.label))}</span></div>${chip}</div>`;
}
function namedAppearance(st) {
  const rendered = st === 'rendered';
  const tri = '<span class="tri">▼</span>';
  const parts = [
    `<div class="achip"><span class="sw" style="width:14px;height:14px;background:${P.solid}"></span><span class="al" style="margin-left:8px;min-width:90px">${esc(L('matSteel'))}</span>${tri}</div>`,
    `<div class="achip"><span class="al" style="min-width:112px">${esc(L(rendered ? 'viewRendered' : 'viewShadedEdges'))}</span>${tri}</div>`,
  ];
  if (rendered) {
    parts.push(`<div class="floor"><span class="box" style="background:${P.accent};border:1px solid ${P.accent}"><svg width="10" height="10" viewBox="0 0 24 24"><path fill="#fff" d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg></span>${esc(L('viewFloor'))}</div>`);
    parts.push(`<div class="achip"><span class="al" style="min-width:112px">${esc(L('rendererRealtime'))}</span>${tri}</div>`);
  }
  parts.push(`<div class="achip"><span class="al" style="min-width:112px">${esc(L('sectionNone'))}</span>${tri}</div>`);
  return `<div class="appcol">${parts.join('')}</div>`;
}

// ---------------------------------------------------------- compact band
function cell(glyph, o = {}) {
  return `<div class="cell${o.act ? ' act' : ''}${o.dis ? ' dis' : ''}" title="${esc(flat(o.tip || ''))}">${glyph}${o.fly ? '<span class="cmark">▾</span>' : ''}</div>`;
}
function compactItems(it) {
  switch (it.k) {
    case 'split': return [cell(ico(it.icon, 28), { act: it.active, fly: hasFly(it.fly), tip: L(it.label) })];
    case 'wide': return [cell(ico(it.icon, 28, it.dis ? 'dis' : ''), { act: it.active, dis: it.dis, tip: L(it.label) })];
    case 'dim': return [cell(ico(it.icon, 28), { tip: L(it.label) })];
    case 'col': return it.rows.map(r => cell(r.glyph ? fxGlyph(r.dis) : ico(r.icon, 28, r.dis ? 'dis' : ''),
      { dis: r.dis, fly: hasFly(r.fly) && !r.dis, tip: L(r.label) }));
    case 'cons': {
      const n = DATA.cons.length, rows = 2, runStart = i => Math.floor(n / rows) * i + Math.min(i, n % rows);
      let html = '<div class="cgrid2">';
      for (let r = 0; r < rows; r++) {
        html += '<div>' + DATA.cons.slice(runStart(r), runStart(r + 1)).map(([k, lk]) => cell(ico('CN.' + k, 28), { tip: L(lk) })).join('') + '</div>';
      }
      return [html + '</div>'];
    }
    case 'appearance': {
      const rendered = it.state === 'rendered';
      const out = [cell(`<span class="sw" style="width:28px;height:28px;background:${P.solid}"></span>`, { fly: true, tip: 'Material' }),
        cell(ico(rendered ? 'VW.rendered' : 'VW.shaded', 28), { fly: true, tip: 'Display mode' })];
      if (rendered) {
        out.push(cell(ico('VW.floor', 28), { fly: true, act: true, tip: L('viewFloor') }));
        out.push(cell(ico('VW.engine', 28), { fly: true, tip: L('rendererRealtime') }));
      }
      out.push(cell(ico('VW.section', 28), { fly: true, tip: L('sectionNone') }));
      return out;
    }
  }
  return [];
}

// ---------------------------------------------------------------- panels
function panelHtml(p) {
  const hasOver = p.arrow || !!p.over;
  const named = state.mode === 'named';
  const body = named ? p.body.map(namedItem).join('') : p.body.flatMap(compactItems).join('');
  let title;
  if (named) title = `<div class="ptitle"><span>${esc(L(p.label))}</span>${hasOver ? '<span class="tri">▼</span>' : ''}</div>`;
  else title = `<div class="ptitle" title="${esc(L(p.label))}">${hasOver ? '<span class="tri">▼</span>' : ''}</div>`;
  return `<div class="panel"${p.cond ? ` data-cond="${esc(p.cond)}"` : ''}><div class="pbody">${body}</div>${title}</div>`;
}
function bandHtml(panels) { return `<div class="band ${state.mode}">${panels.map(panelHtml).join('')}</div>`; }

// ----------------------------------------------------------------- menus
function overMenu(items) {
  return `<div class="omenu">${items.map(o => `<div class="orow${o.dis ? ' dis' : ''}">${ico(o.icon, 18)}<span class="olbl">${esc(L(o.label))}</span></div>`).join('')}</div>`;
}
const intendedBy = {};
function resolveFly(key) {
  if (DATA.icons.maps.IC[key]) return ['IC.' + key, false];
  if (DATA.icons.maps.PL[key]) return ['PL.' + key, false];
  return ['IC.line34', true];
}
function flyMenu(id) {
  const items = DATA.flyouts[id];
  const anyFb = items.some(([k]) => resolveFly(k)[1]);
  const rows = items.map(([key, b, sub], i) => {
    const [ref, fb] = resolveFly(key);
    const one = !sub;
    const cls = ['frow', one ? 'one' : '', i === 0 ? 'first' : '', i === items.length - 1 ? 'last' : ''].join(' ');
    const row = `<div class="${cls}">${ico(ref, 26, '', ref + ' (id ' + key + ')')}<div class="ft"><span class="fb">${esc(L(b))}</span>${one ? '' : `<span class="fs">${esc(L(sub))}</span>`}</div></div>`;
    if (!anyFb) return row;
    let ann = '';
    if (fb) {
      const want = DATA.intended[key];
      ann = `<span class="badge">falls back to Line icon</span>` + (want
        ? `<span>intended</span><span class="intended">${ico(want, 26)}</span><code>${esc(want)}</code>`
        : `<span>no drawn icon exists for <code>${esc(key)}</code></span>`);
    }
    return row + `<div class="fann">${ann}</div>`;
  });
  return `<div class="fmenu" style="grid-template-columns:${anyFb ? 'max-content max-content' : 'max-content'}">${rows.join('')}</div>`;
}
function placeMenu() {
  const rows = [['part3dMenuIcon', 'Part1'], ['assemblyMenuIcon', 'Subassembly1']];
  return `<div class="omenu">${rows.map(([r, n]) => `<div class="orow tall">${ico(r, 18)}<span class="olbl">${n}</span></div>`).join('')}</div>`;
}
function menusFor(rb) {
  const blocks = [];
  const seenFly = new Set();
  for (const p of rb.panels) {
    const title = L(p.label).trim() || '(untitled)';
    if (p.over) blocks.push([`${title} ▼ overflow`, overMenu(p.over)]);
    for (const it of p.body) {
      const flys = it.k === 'col' ? it.rows.map(r => r.fly) : [it.fly];
      for (const f of flys) if (f && !seenFly.has(f)) { seenFly.add(f); blocks.push([`${title} › ${flat(L(flyBtnLabel(p, f)))} flyout`, flyMenu(f)]); }
    }
  }
  if (rb.id === 'part' || rb.id === 'assembly') {
    blocks.push(['Appearance, rendered-mode state (the renderer chip only when Cycles is available)', `<div class="band ${state.mode}">${panelHtml({ label: 'panelAppearance', body: [{ k: 'appearance', state: 'rendered' }] })}</div>`]);
  }
  if (rb.id === 'assembly') blocks.push(['Place › document picker (non-iOS fallback; example names)', placeMenu()]);
  return blocks;
}
function flyBtnLabel(p, f) {
  for (const it of p.body) {
    if (it.fly === f) return it.label;
    for (const r of it.rows || []) if (r.fly === f) return r.label;
  }
  return f;
}

// ---------------------------------------------------------------- render
function renderRibbons() {
  const z = state.zoom;
  const out = DATA.ribbons.map(rb => {
    const menus = menusFor(rb);
    return `<section class="rb" id="rb-${rb.id}"><h2>${esc(rb.title)} <small>${esc(rb.note || '')}</small></h2>
      <div class="mock">
        <div class="scroller"><div class="zoom" style="--z:${z}">${bandHtml(rb.panels)}<div class="annot"></div></div></div>
        ${menus.length ? `<div class="scroller menus"><div class="zoom" style="--z:${z};width:${100 / z}%"><div class="menus-in">${menus.map(([c, h]) => `<figure class="mblk"><figcaption>${esc(c)}</figcaption>${h}</figure>`).join('')}</div></div></div>` : ''}
      </div></section>`;
  });
  document.getElementById('ribbons').innerHTML = out.join('');
  document.querySelectorAll('.rb .zoom').forEach(zm => {
    const band = zm.querySelector(':scope > .band'), annot = zm.querySelector(':scope > .annot');
    if (!band || !annot) return;
    const conds = band.querySelectorAll('.panel[data-cond]');
    if (!conds.length) { annot.remove(); return; }
    conds.forEach(pn => {
      const d = document.createElement('div');
      d.className = 'cond';
      d.style.left = pn.offsetLeft + 'px';
      d.style.width = Math.max(pn.offsetWidth, 140) + 'px';
      d.textContent = 'conditional: ' + pn.dataset.cond;
      d.title = d.textContent;
      annot.appendChild(d);
    });
  });
}

function usesOf(ref) {
  const counts = new Map();
  for (const [w, sz] of DATA.uses[ref] || []) { const k = `${w} · ${sz}px`; counts.set(k, (counts.get(k) || 0) + 1); }
  const out = [...counts].map(([k, c]) => c > 1 ? `${k} (${c} rows)` : k);
  for (const u of DATA.extraUses[ref] || []) out.push(u);
  const m = ref.split('.')[0];
  if (ref.includes('.') && DATA.mapExtraUses[m]) out.push(DATA.mapExtraUses[m]);
  return out;
}
function renderAtlas() {
  const groups = Object.keys(DATA.icons.maps).map(m => [m, Object.keys(DATA.icons.maps[m]).map(k => m + '.' + k), DATA.mapDesc[m] || '']);
  groups.push(['Singles', Object.keys(DATA.icons.singles), 'Stand-alone constants: ribbon big buttons, the model browser tree, the tab bar and the home view.']);
  const intendedFor = {}; for (const [k, v] of Object.entries(DATA.intended)) intendedFor[v] = k;
  let n = 0;
  const html = groups.map(([m, refs, desc]) => {
    const cards = refs.map(ref => {
      n++;
      const vb = DATA.audit.viewBoxOf[ref] || '';
      const size = parseFloat((vb.split(/\s+/)[2]) || 24);
      let uses = usesOf(ref).map(u => `<li>${esc(u)}</li>`);
      if (intendedFor[ref]) uses.push(`<li class="warn">unwired; meant for flyout id <code>${esc(intendedFor[ref])}</code></li>`);
      if (!uses.length) uses = ['<li class="warn">not referenced by the app (icon preview only)</li>'];
      const key = ref.includes('.') ? ref : ref;
      return `<div class="acard"><div class="stage"><div class="sz">${ico(ref, size)}<span>1×</span></div><div class="sz">${ico(ref, size * 2)}<span>2×</span></div></div>
        <div class="cap"><div class="key">${esc(key)}</div><div class="vb">viewBox ${esc(vb)}</div><ul>${uses.join('')}</ul></div></div>`;
    }).join('');
    return `<h3 id="map-${m}">${esc(m)} <span class="sub">${refs.length} icons</span></h3><p class="mapdesc">${esc(desc)}</p><div class="agrid">${cards}</div>`;
  }).join('');
  document.getElementById('atlas-body').innerHTML = html;
  document.getElementById('atlas-count').textContent = n + ' icons';
}

function mappedColours(p) {
  const set = new Set();
  const all = [...Object.values(DATA.icons.maps).flatMap(m => Object.values(m)), ...Object.values(DATA.icons.singles)];
  for (const s of all) {
    if (s.includes('data-fixed')) { (s.match(/#[0-9a-fA-F]{6}\b/g) || []).forEach(h => set.add(h.toUpperCase())); continue; }
    (s.match(/#([0-9a-fA-F]{6})\b/g) || []).forEach(h => set.add(mapHex(h.slice(1), p).toUpperCase()));
  }
  return set.size;
}
function renderAudit() {
  const A = DATA.audit;
  const cells = [];
  const mapsCount = Object.values(A.perMap).reduce((a, b) => a + b, 0);
  cells.push(`<div class="acell"><h4>Inventory</h4><div class="big-n">${A.total}</div><p>${mapsCount} icons in ${Object.keys(A.perMap).length} maps + ${A.singles} single constants.</p>
    <p class="sub">${Object.entries(A.perMap).map(([m, c]) => `${m} ${c}`).join(' · ')}</p></div>`);
  const max = Math.max(...Object.values(A.viewBox), ...Object.values(A.viewBoxOther));
  const bar = (k, v) => `<div class="bar"><span>${esc(k)}</span><span class="track"><span class="fill" style="width:${(v / max * 100).toFixed(1)}%"></span></span><span>${v}</span></div>`;
  const otherTotal = Object.values(A.viewBoxOther).reduce((a, b) => a + b, 0);
  cells.push(`<div class="acell"><h4>viewBox sizes</h4>${Object.entries(A.viewBox).map(([k, v]) => bar(k + '×' + k, v)).join('')}${bar('other', otherTotal)}
    <p class="sub">Other: ${Object.entries(A.viewBoxOther).map(([k, v]) => `${k}×${k} (${v})`).join(', ') || 'none'}. Five grids for one ribbon; only 34 and 18 are sizes the named ribbon actually draws at (26 in flyouts, 28 in compact mode).</p></div>`);
  const byFactor = {};
  A.scaled.forEach(s => { const k = `${s.vb} → ${s.px}px (×${s.factor})`; (byFactor[k] = byFactor[k] || []).push(s.ref); });
  cells.push(`<div class="acell"><h4>Drawn at a size other than their viewBox</h4><div class="big-n">${A.scaled.length}</div><p>icon placements in the named ribbon, its menus and flyouts are scaled (compact mode scales every icon to 28px on top of this).</p>
    <table class="t">${Object.entries(byFactor).map(([k, refs]) => `<tr><td style="white-space:nowrap">${esc(k)}</td><td>${refs.length}: ${refs.map(esc).join(', ')}</td></tr>`).join('')}</table></div>`);
  const shortList = Object.entries(A.shortHex).map(([h, refs]) => `<code>${esc(h)}</code> in ${refs.length} icon(s): ${refs.map(r => esc(r) + (A.fixed.includes(r) ? ' (data-fixed, not recoloured anyway)' : '')).join(', ')}`);
  cells.push(`<div class="acell"><h4>Colours</h4><div class="big-n">${A.distinctHex}</div><p>distinct <code>#rrggbb</code> values (case-insensitive; ${A.distinctHexCaseSensitive} if case is counted), ${A.hexOccurrences} occurrences. After mapping: Ember ${mappedColours(PAL.ember)}, Chalk ${mappedColours(PAL.chalk)} distinct.</p>
    ${shortList.length ? `<p>Short hex literals the recolourer's 6-digit regex skips (they stay as-is on every palette): ${shortList.join('; ')}.</p>` : ''}
    <div class="swatches">${A.hexList.map(h => `<i style="background:${h}" title="${h}"></i>`).join('')}</div></div>`);
  cells.push(`<div class="acell"><h4>&lt;text&gt; glyphs</h4><div class="big-n">${A.textIcons.length}</div><p>icons draw letters with SVG <code>&lt;text&gt;</code> in ${[...new Set(A.textIcons.flatMap(t => t.fonts))].map(f => `<code>${esc(f)}</code>`).join(' / ')}. Segoe UI does not ship on iPadOS (Georgia does), so the Segoe UI glyphs depend on the platform's fallback.</p>
    <table class="t">${A.textIcons.map(t => `<tr><td><span class="tile" style="background:var(--m-panel);display:inline-flex;padding:3px;border-radius:3px">${ico(t.ref, 26)}</span></td><td><code>${esc(t.ref)}</code><br><span class="sub">${t.fonts.map(esc).join(', ')}: “${t.glyphs.map(esc).join('”, “')}”</span></td></tr>`).join('')}</table></div>`);
  const fbTotal = Object.values(A.fallbackRows).reduce((a, b) => a + b, 0);
  cells.push(`<div class="acell"><h4>Flyout fallback bug</h4><div class="big-n">${fbTotal}</div><p>flyout rows resolve through <code>IC[id] ?? PL[id] ?? IC['line34']</code> and match nothing, so they all draw the Line icon: ${Object.entries(A.fallbackRows).map(([k, v]) => `${esc(k)} ${v}`).join(', ')}.</p>
    <p>The <b>AX</b> (${A.perMap.AX}) and <b>PN</b> (${A.perMap.PN}) maps hold the drawings these rows were meant to show; nothing in the app reads them. Direct (deMove…) has no drawn icons at all.</p></div>`);
  const reuse = Object.entries(A.reused).filter(([r]) => r !== 'IC.line34');
  cells.push(`<div class="acell"><h4>One glyph, several commands</h4><table class="t">${reuse.map(([r, names]) => `<tr><td><span style="background:var(--m-panel);display:inline-flex;padding:3px;border-radius:3px">${ico(r, 22)}</span></td><td><code>${esc(r)}</code><br><span class="sub">${names.map(esc).join(' · ')}</span></td></tr>`).join('')}</table>
    <ul><li><code>WF.plane</code> doubles as Sketch › View › Slice Graphics.</li><li><code>PT.rect</code> / <code>PT.mirror</code> are shared by the Part and Assembly Pattern panels.</li><li><code>IN.constr</code> is passed as the icon of the Parameters row and never drawn: the italic "fx" text replaces it.</li><li><code>IC.line34</code> also stands in for the ${fbTotal} fallback flyout rows.</li></ul></div>`);
  cells.push(`<div class="acell"><h4>Identical SVG under different keys</h4><div class="big-n">${A.duplicates.length}</div><p>group(s) of keys whose SVG strings are byte-identical.</p>
    <table class="t">${A.duplicates.map(g => `<tr><td><span style="background:var(--m-panel);display:inline-flex;padding:3px;border-radius:3px">${ico(g[0], 22)}</span></td><td>${g.map(r => `<code>${esc(r)}</code>`).join(' = ')}</td></tr>`).join('')}</table></div>`);
  cells.push(`<div class="acell"><h4>Not referenced by the app</h4><div class="big-n">${A.unreferenced.length}</div><p>icons that appear in no ribbon, menu, flyout, dialog, browser or tab (only in the in-app icon preview):</p><div class="iconrow">${A.unreferenced.map(r => `<span class="tile" title="${esc(r)}">${ico(r, 22)}</span>`).join('')}</div><p class="sub">${A.unreferenced.map(esc).join(', ')}</p></div>`);
  cells.push(`<div class="acell"><h4>Recolour exemptions and gaps</h4><p><code>data-fixed</code> (never recoloured): ${A.fixed.map(r => `<code>${esc(r)}</code>`).join(', ')}.</p>
    <p>The Appearance panel draws its <code>VW</code> icons only in compact mode; with names on it is text chips plus a swatch, so the five VW glyphs never appear in the default ribbon.</p>
    <p>Overflow-menu rows dim only the label when disabled; the 18px icon stays at full strength (<code>_OverRow</code>).</p></div>`);
  document.getElementById('audit-body').innerHTML = cells.join('');
}

function applyPalette() {
  P = PAL[state.pal] || PAL.ember;
  const r = document.documentElement.style;
  const m = { bg: P.bg, panel: P.panel, fly: P.fly, flyhov: P.flyHov, text: P.text, dim: P.dim, sep: P.sep, psep: P.panelSep,
    accent: P.accent, h6: P.h6, h7: P.h7, b10: P.b10, actbg: P.actBg, actol: P.actOl };
  for (const [k, v] of Object.entries(m)) r.setProperty('--m-' + k, v);
}
function syncControls() {
  document.querySelectorAll('.seg').forEach(seg => {
    const key = seg.dataset.ctl;
    seg.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === String(state[key]))));
  });
  document.getElementById('bounds').checked = !!state.bounds;
  document.body.classList.toggle('bounds', !!state.bounds);
}
function renderAll() { applyPalette(); syncControls(); renderRibbons(); renderAtlas(); renderAudit(); }

document.querySelectorAll('.seg').forEach(seg => seg.addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  state[seg.dataset.ctl] = b.dataset.v; save();
  if (seg.dataset.ctl === 'mode' || seg.dataset.ctl === 'zoom') { syncControls(); renderRibbons(); } else renderAll();
}));
document.getElementById('bounds').addEventListener('change', e => { state.bounds = e.target.checked; save(); syncControls(); });
renderAll();
</script>
</body>
</html>
'''


if __name__ == '__main__':
    main()
