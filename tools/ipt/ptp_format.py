"""The app's packed document container (.ptp / .pts / .pas), byte-compatible
with frontend/lib/doc_file.dart:

  magic  8 bytes  "PROTOv1\\n"
  u32    little-endian length of the index
  index  UTF-8 JSON {"v":1,"kind":..,"entries":[{"n":..,"o":..,"l":..}]}
  blobs  raw bytes, concatenated, entries sorted by name
"""
import json
import struct

MAGIC = b'PROTOv1\n'


def _json(obj):
    # Dart's jsonEncode: compact, non-ASCII written as UTF-8, '/' unescaped.
    return json.dumps(obj, separators=(',', ':'), ensure_ascii=False)


def encode(kind, entries):
    names = sorted(entries)
    index, off = [], 0
    for n in names:
        index.append({'n': n, 'o': off, 'l': len(entries[n])})
        off += len(entries[n])
    head = _json({'v': 1, 'kind': kind, 'entries': index}).encode('utf-8')
    return MAGIC + struct.pack('<I', len(head)) + head + b''.join(entries[n] for n in names)


def decode(data):
    if data[:8] != MAGIC:
        raise ValueError('not a Prototype document (bad magic)')
    hlen = struct.unpack_from('<I', data, 8)[0]
    head = json.loads(data[12:12 + hlen].decode('utf-8'))
    base = 12 + hlen
    entries = {}
    for e in head.get('entries', []):
        n = e['n'].replace('\\', '/').lstrip('/')
        entries[n] = data[base + e['o']:base + e['o'] + e['l']]
    return head.get('kind', 'part'), entries


def part_json(meta):
    return _json(meta).encode('utf-8')
