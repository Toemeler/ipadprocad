"""Autodesk Inventor part (.ipt) -> Prototype part (.ptp).

    py ipt2ptp.py Handyhalterung.ipt [-o out.ptp]

What the .ptp gets:
  meta.json                 one imported body per Inventor solid body, named
                            as in Inventor (the app's own STEP-import form)
  imports/<name>.step       the exact B-rep of every body (see acis_to_step)
  preview.png               Inventor's thumbnail
  inventor/source.ipt       the original file, byte for byte
  inventor/source.json      metadata, model tree, and the fingerprint
                            ptp2ipt uses to tell whether the part was edited

What it does NOT get: Inventor's feature history (sketches, extrusions,
fillets). The bodies are exact but arrive as imported solids.
"""
import argparse
import hashlib
import json
import math
import os
import re
import sys

import acis_to_step
import asm_sab
import ptp_format
from ipt_container import IptFile

CONVERTER = 'ipt2ptp/1'


def _sha(b):
    return hashlib.sha256(b).hexdigest()


def model_tree(ipt):
    """Node names of the Inventor browser, in file order."""
    seg = ipt.segments().get('PmBrowserSegment')
    if not seg:
        return []
    names = []
    for m in re.finditer(rb'(?:[\x20-\x7e\xa0-\xff]\x00){2,}', seg[0]):
        s = m.group().decode('utf-16le')
        if s not in names and not s.startswith(('Pm', 'Nb', 'NB', 'Am', 'UCx')):
            names.append(s)
    return names


def body_names(ipt, n):
    """Inventor's names for the solid bodies, in B-rep body order.

    The browser lists the bodies under "Solid Bodies" by name; Inventor's
    default names are "Solid<n>" or localised ("Volumenkörper<n>"). The
    B-rep keeps bodies in creation order, which is the order they appear in
    the DC segment's name table."""
    seg = ipt.segments().get('PmDCSegment')
    found = []
    if seg:
        pat = re.compile(r'^(Solid|Volumenkörper|Volumen|Corps|Cuerpo|Corpo|Body|Körper)\s?\d+$')
        for m in re.finditer(rb'(?:[\x20-\x7e\xa0-\xff]\x00){3,}', seg[0]):
            s = m.group().decode('utf-16le')
            if pat.match(s) and s not in found:
                found.append(s)
    out = []
    for i in range(n):
        out.append(found[i] if i < len(found) else f'Solid{i + 1}')
    # never two bodies with one name
    seen = set()
    for i, s in enumerate(out):
        while s in seen:
            s += "'"
        out[i] = s
        seen.add(s)
    return out


def _camera(sab):
    """An isometric camera fitted to the part, the app's fitViewCamera rule."""
    topo = acis_to_step.Topo(sab)
    unit = sab.header.get('unit_mm', 1.0)
    az, pol = math.pi / 4, 0.955
    s = (math.cos(az), 0.0, -math.sin(az))
    d = (math.sin(pol) * math.sin(az), math.cos(pol), math.sin(pol) * math.cos(az))
    nd = (-d[0], -d[1], -d[2])
    u = (s[1] * nd[2] - s[2] * nd[1], s[2] * nd[0] - s[0] * nd[2], s[0] * nd[1] - s[1] * nd[0])
    ul = math.sqrt(sum(x * x for x in u))
    u = tuple(x / ul for x in u)
    pts = [tuple(c * unit for c in topo.vertex_point(r.index))
           for r in sab.records if r.type == 'vertex']
    if not pts:
        return {'az': az, 'pol': pol, 'h': 27.0, 'ox': 0.0, 'oy': 0.0}
    ss = [sum(a * b for a, b in zip(p, s)) for p in pts]
    uu = [sum(a * b for a, b in zip(p, u)) for p in pts]
    hx, hy = (max(ss) - min(ss)) / 2, (max(uu) - min(uu)) / 2
    half = max(hy, hx) / 0.82
    return {'az': az, 'pol': pol, 'h': half if half > 1e-6 else 27.0,
            'ox': (max(ss) + min(ss)) / 2, 'oy': (max(uu) + min(uu)) / 2}


def import_feature(name, body, seq, path, index):
    # Key order is ExtrudeFeature.toJson()'s, so the app re-saves it unchanged.
    return {
        'kind': 'extrude', 'name': name, 'seq': seq, 'body': body,
        'visible': True, 'output': 'new',
        'imported': True, 'importPath': path, 'importIndex': index,
        'sketch': '', 'profiles': [], 'dir': 'default',
        'a': 5.0, 'b': 5.0, 'taper': 0.0,
        'exprA': '5 mm', 'exprB': '5 mm', 'exprTaper': '0.00 deg',
        'imate': False, 'match': True, 'extent': 'distance',
    }


def geometry_fingerprint(meta, entries):
    """What decides whether the part still IS the Inventor part: the
    feature list (kind, body, source, index, output, visibility) and the
    bytes of every STEP it reads. Camera, sketch visibility and the like
    are left out -- they do not change the geometry."""
    feats = []
    for f in meta.get('features', []):
        feats.append({k: f.get(k) for k in
                      ('kind', 'body', 'output', 'imported', 'importPath', 'importIndex', 'visible')})
    steps = {}
    for f in feats:
        p = f.get('importPath')
        if p and p not in steps:
            steps[p] = _sha(entries.get(p, b''))
    extra = {k: meta[k] for k in ('eopNodes',) if k in meta}
    blob = json.dumps({'features': feats, 'steps': steps, 'extra': extra}, sort_keys=True)
    return _sha(blob.encode())


def convert(ipt_path, out_path=None, log=print):
    ipt = IptFile(ipt_path)
    name = os.path.splitext(os.path.basename(ipt_path))[0]
    brep = ipt.brep_segment()
    if brep is None:
        raise SystemExit(f'{ipt_path}: no PmBRepSegment -- not a part file?')
    sab = asm_sab.parse(brep)
    nbodies = len(sab.of_type('body'))
    names = body_names(ipt, nbodies)
    md = ipt.metadata()
    step, solid_names, report = acis_to_step.brep_to_step(
        sab, names=names, product=md.get('part_number') or name, author=md.get('author', ''))
    step_bytes = step.encode('ascii')
    step_entry = f'imports/{name}.step'

    features = [import_feature(f'Import{i + 1}', solid_names[i], i, step_entry, i)
                for i in range(len(solid_names))]
    meta = {
        'version': 1, 'type': 'part',
        'vis': {k: False for k in ('yz', 'xz', 'xy', 'x', 'y', 'z', 'cp')},
        'cam': _camera(sab),
        'sketches': [],
        'features': features,
        'featureN': len(features), 'solidN': len(features), 'seqNext': len(features),
    }
    entries = {
        'meta.json': ptp_format.part_json(meta),
        step_entry: step_bytes,
        'inventor/source.ipt': ipt.raw,
    }
    thumb = ipt.thumbnail_png()
    if thumb:
        entries['preview.png'] = thumb
    info = {
        'converter': CONVERTER,
        'source_name': os.path.basename(ipt_path),
        'source_sha256': _sha(ipt.raw),
        'geometry_sha256': geometry_fingerprint(meta, entries),
        'asm': sab.header.get('asm'),
        'inventor_units_mm': sab.header.get('unit_mm'),
        'metadata': md,
        'model_tree': model_tree(ipt),
        'bodies': report['bodies'],
    }
    entries['inventor/source.json'] = json.dumps(info, indent=2, ensure_ascii=False).encode('utf-8')

    out_path = out_path or os.path.splitext(ipt_path)[0] + '.ptp'
    with open(out_path, 'wb') as f:
        f.write(ptp_format.encode('part', entries))
    for b in report['bodies']:
        log(f"  body {b['name']!r}: {b['faces']} faces, {b['edges']} edges, "
            f"{b['vertices']} vertices, {'closed' if b['closed'] else 'OPEN'}")
    log(f'wrote {out_path}')
    return out_path, info


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('ipt')
    ap.add_argument('-o', '--out')
    ap.add_argument('--step', help='also write the STEP file here')
    ap.add_argument('--bodies-only', action='store_true',
                    help='exact bodies as imported solids, no feature tree')
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding='utf-8')
    if not a.bodies_only:
        import ipt_convert
        try:
            ipt_convert.convert(a.ipt, a.out)
            return
        except ipt_convert.ConversionError as e:
            print(f'full feature tree not convertible ({e}); writing exact bodies instead')
    out, info = convert(a.ipt, a.out)
    if a.step:
        _, entries = ptp_format.decode(open(out, 'rb').read())
        for n, b in entries.items():
            if n.startswith('imports/'):
                open(a.step, 'wb').write(b)


if __name__ == '__main__':
    main()
