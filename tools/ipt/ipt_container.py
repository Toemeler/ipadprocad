"""Reading the Inventor .ipt container.

An .ipt is an OLE2 compound file. What matters in it:

  \\x05<name>             OLE property sets (UTF-16, with name dictionaries):
                         Design Tracking, Summary Information (+ PNG thumbnail)
  RSeStorage/RSeSegInfo  the segment list: segment name -> stream suffix
  RSeStorage/B<suffix>   segment DATA:  16-byte GUID, 2 bytes, zstd frame
  RSeStorage/M<suffix>   segment META:  "RSe Meta Stream Version 8" header, zstd frame

Recent Inventor releases zstd-compress every segment; older ones stored them
raw. Both are handled: a stream without the zstd magic is returned as is.
"""
import datetime
import re
import struct
import uuid

import olefile
import zstandard

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'


def _zstd(raw):
    i = raw.find(ZSTD_MAGIC)
    if i < 0 or i > 512:
        return raw
    return zstandard.ZstdDecompressor().decompressobj().decompress(raw[i:])


def _u32(b, o):
    return struct.unpack_from('<I', b, o)[0]


def parse_property_set(b):
    """One OLE property set -> (fmtid, {name-or-id: value}). Handles the
    UTF-16 dictionaries Inventor writes, which generic readers get wrong."""
    fmtid = uuid.UUID(bytes_le=b[28:44])
    off = _u32(b, 44)
    n = _u32(b, off + 4)
    ids = [struct.unpack_from('<II', b, off + 8 + 8 * i) for i in range(n)]
    cp = 1200
    for pid, po in ids:
        if pid == 1:
            cp = struct.unpack_from('<H', b, off + po + 4)[0]
    names, vals = {}, {}
    for pid, po in ids:
        p = off + po
        if pid == 0:
            cnt = _u32(b, p)
            q = p + 4
            for _ in range(cnt):
                k, ln = _u32(b, q), _u32(b, q + 4)
                q += 8
                if cp == 1200:
                    s = b[q:q + ln * 2].decode('utf-16le').rstrip('\x00')
                    q = (q + ln * 2 + 3) & ~3
                else:
                    s = b[q:q + ln].decode('cp1252', 'replace').rstrip('\x00')
                    q += ln
                names[k] = s
            continue
        t = struct.unpack_from('<H', b, p)[0]
        d = p + 4
        if t == 2:
            v = struct.unpack_from('<h', b, d)[0]
        elif t == 3:
            v = struct.unpack_from('<i', b, d)[0]
        elif t == 5:
            v = struct.unpack_from('<d', b, d)[0]
        elif t == 11:
            v = bool(struct.unpack_from('<H', b, d)[0])
        elif t == 19:
            v = _u32(b, d)
        elif t == 30:
            ln = _u32(b, d)
            v = b[d + 4:d + 4 + ln].decode('cp1252', 'replace').rstrip('\x00')
        elif t == 31:
            ln = _u32(b, d)
            v = b[d + 4:d + 4 + ln * 2].decode('utf-16le').rstrip('\x00')
        elif t == 64:
            ft = struct.unpack_from('<Q', b, d)[0]
            v = (datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=ft // 10)
                 ).isoformat() if ft else None
        elif t == 71:
            ln = _u32(b, d)
            v = b[d + 4:d + 4 + ln]          # clipboard data, kept raw
        elif t == 72:
            v = str(uuid.UUID(bytes_le=b[d:d + 16]))
        else:
            v = None
        vals[pid] = v
    out = {}
    for pid, v in vals.items():
        if pid in (1, 0x80000000):
            continue
        out[names.get(pid, pid)] = v
    return fmtid, out


# Property ids Inventor uses in the Design Tracking set, by meaning.
_DESIGN_TRACKING = {
    4: 'creation_date', 5: 'part_number', 20: 'material', 32: 'category_or_process',
    41: 'designer', 67: 'app_version', 71: 'material_library_ref', 72: 'project',
}
_SUMMARY = {2: 'title', 3: 'subject', 4: 'author', 5: 'keywords', 6: 'comments',
            8: 'last_saved_by'}
_TRACKING_CONTROL = {16: 'last_saved_by', 17: 'last_saved'}


class IptFile:
    def __init__(self, path):
        self.path = path
        self.raw = open(path, 'rb').read()
        self.ole = olefile.OleFileIO(self.raw)
        self._segments = None

    # -- property sets -----------------------------------------------------
    def property_sets(self):
        out = {}
        for e in self.ole.listdir():
            if len(e) == 1 and e[0].startswith('\x05'):
                fmtid, props = parse_property_set(self.ole.openstream(e).read())
                name = props.pop('Property Set Name', str(fmtid))
                out[name] = props
        return out

    def metadata(self):
        """The properties a user would recognise, with stable key names."""
        ps = self.property_sets()
        md = {}
        dt = ps.get('Design Tracking Properties', {})
        for pid, key in _DESIGN_TRACKING.items():
            if dt.get(pid) not in (None, ''):
                md[key] = dt[pid]
        si = ps.get('Inventor Summary Information', {})
        for pid, key in _SUMMARY.items():
            if isinstance(si.get(pid), str) and si[pid]:
                md[key] = si[pid]
        tc = ps.get('Design Tracking Control', {})
        for pid, key in _TRACKING_CONTROL.items():
            if tc.get(pid) not in (None, ''):
                md[key] = tc[pid]
        ud = ps.get('Inventor User Defined Properties', {})
        custom = {k: v for k, v in ud.items() if isinstance(k, str)}
        if custom:
            md['custom'] = custom
        return md

    def thumbnail_png(self):
        si = self.property_sets().get('Inventor Summary Information', {})
        for v in si.values():
            if isinstance(v, bytes):
                i = v.find(b'\x89PNG\r\n\x1a\n')
                if i >= 0:
                    return v[i:]
        return None

    # -- segments ----------------------------------------------------------
    def segments(self):
        """{segment name: (data bytes, meta bytes)}, decompressed."""
        if self._segments is not None:
            return self._segments
        out = {}
        for e in self.ole.listdir():
            if len(e) == 2 and e[0] == 'RSeStorage' and e[1][0] == 'B':
                suffix = e[1][1:]
                data = _zstd(self.ole.openstream(e).read())
                meta_path = ['RSeStorage', 'M' + suffix]
                raw_meta = self.ole.openstream(meta_path).read() \
                    if self.ole.exists('/'.join(meta_path)) else b''
                meta = _zstd(raw_meta)
                # The meta stream's uncompressed header names its segment in
                # UTF-16 ("PmBRepSegment").
                head = raw_meta[:max(raw_meta.find(ZSTD_MAGIC), 0)] or raw_meta
                seg = _segment_name_from_meta(head) or suffix
                out[seg] = (data, meta)
        self._segments = out
        return out

    def brep_segment(self):
        return self.segments().get('PmBRepSegment', (None, None))[0]


def _segment_name_from_meta(meta):
    for m in re.finditer(rb'(?:[A-Za-z]\x00){4,}', meta):
        s = m.group().decode('utf-16le')
        if s.endswith('Segment'):
            return s
    return None
