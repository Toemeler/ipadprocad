"""Prototype part (.ptp) -> Autodesk Inventor part (.ipt).

    py ptp2ipt.py Handyhalterung.ptp [-o out.ipt]

A .ptp made by ipt2ptp carries the Inventor original. While the part's
geometry is what it was when it was imported -- same bodies, same STEP
sources, no features added or removed -- that original IS the part, and it
is written back byte for byte: every sketch, feature, parameter and
appearance Inventor had comes back with it.

Once the geometry was edited in the app, the original no longer describes
it, and a new .ipt would need Inventor's feature database written from
scratch -- which this tool cannot do. It refuses rather than writing a file
that would silently show the OLD part in Inventor; export STEP from the app
instead (Inventor opens STEP with the exact geometry).
"""
import argparse
import hashlib
import json
import os
import sys

import ptp_format
from ipt2ptp import geometry_fingerprint


class NotRoundTrippable(Exception):
    pass


def convert(ptp_path, out_path=None, log=print):
    kind, entries = ptp_format.decode(open(ptp_path, 'rb').read())
    if kind != 'part':
        raise NotRoundTrippable(f'{ptp_path} is a {kind} document; only parts map to .ipt')
    src = entries.get('inventor/source.ipt')
    info_b = entries.get('inventor/source.json')
    if src is None or info_b is None:
        raise NotRoundTrippable(
            'this part was not converted from an .ipt, so there is no Inventor part to '
            'write back. Export it as STEP instead; Inventor opens STEP exactly.')
    info = json.loads(info_b.decode('utf-8'))
    if hashlib.sha256(src).hexdigest() != info.get('source_sha256'):
        raise NotRoundTrippable('the embedded Inventor original is damaged (checksum mismatch)')
    meta = json.loads(entries['meta.json'].decode('utf-8'))
    if 'features' in info:
        # full-tree conversion (ipt2ptp/2): the tree must be the one imported
        # and every stored Inventor result still valid
        feats = meta.get('features', [])
        now = [[f.get('name'), f.get('kind'), f.get('body')] for f in feats]
        cached_now = {f.get('name') for f in feats if isinstance(f.get('cache'), dict)}
        edited = now != info['features'] or not set(info.get('cached', [])) <= cached_now
    else:
        edited = geometry_fingerprint(meta, entries) != info.get('geometry_sha256')
    if edited:
        raise NotRoundTrippable(
            'the part was edited after it was imported from Inventor (bodies, features or '
            'their sources changed), so the Inventor original no longer matches it. '
            'Writing that original would show the OLD part in Inventor. Export STEP instead.')
    out_path = out_path or os.path.splitext(ptp_path)[0] + '.ipt'
    with open(out_path, 'wb') as f:
        f.write(src)
    log(f"wrote {out_path} ({len(src)} bytes, identical to {info.get('source_name')})")
    return out_path


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('ptp')
    ap.add_argument('-o', '--out')
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding='utf-8')
    try:
        convert(a.ptp, a.out)
    except NotRoundTrippable as e:
        print(f'cannot convert: {e}', file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
