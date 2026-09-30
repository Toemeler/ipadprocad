"""Object-level access to an RSe segment (the DC segment in particular).

Framing, established on PmBRepSegment and PmDCSegment:
  data  = 18-byte segment header, then objects back to back
  meta  = u32 object count + 1, u16, u32, u32, u32 n, then n x u32
          (0x80000000 | size); object i spans size_i + 9 bytes
References between objects are u32 with the high bit set; the low bits are
the object index + 1.

Objects carry no class tag. What is known about a class is recognised from
its content (see find_parameters and friends).
"""
import re
import struct

REF = 0x80000000


class Segment:
    def __init__(self, data, meta):
        self.data, self.meta = data, meta
        n = struct.unpack_from('<I', meta, 14)[0]
        self.sizes = [struct.unpack_from('<I', meta, 18 + 4 * i)[0] & 0xffffff for i in range(n)]
        self.starts = []
        p = 18
        for s in self.sizes:
            self.starts.append(p)
            p += s + 9
        self.n = n

    def obj(self, i):
        s = self.starts[i]
        e = self.starts[i + 1] if i + 1 < self.n else len(self.data)
        return self.data[s:e]

    def index_at(self, offset):
        import bisect
        return bisect.bisect_right(self.starts, offset) - 1

    def refs(self, i):
        """Object indices referenced from object i (any alignment)."""
        b = self.obj(i)
        out = []
        for o in range(0, len(b) - 3):
            v = struct.unpack_from('<I', b, o)[0]
            if v & REF and 0 < (v & 0x7fffffff) <= self.n and b[o + 3] == 0x80:
                out.append((o, (v & 0x7fffffff) - 1))
        return out

    def strings(self, i, minlen=2):
        """(offset, text) of every u32-length-prefixed UTF-16 string in object i."""
        b = self.obj(i)
        out = []
        for m in re.finditer(rb'(?:[\x20-\x7e\xa0-\xff]\x00){%d,}' % minlen, b):
            s = m.start()
            if s >= 4:
                ln = struct.unpack_from('<I', b, s - 4)[0]
                t = m.group().decode('utf-16le')
                if 0 < ln <= len(t):
                    out.append((s - 4, t[:ln]))
        return out


def find_parameters(seg):
    """Inventor model parameters: {name: (object index, value in internal
    units -- cm for lengths, rad for angles)}."""
    out = {}
    pat = re.compile(rb'\x5c\x0b\x00\x00([\x01-\x20])\x00\x00\x00')
    for m in pat.finditer(seg.data):
        a = m.start() - 16
        i = seg.index_at(a)
        if seg.starts[i] != a:
            continue
        ln = m.group(1)[0]
        b = seg.obj(i)
        try:
            name = b[24:24 + 2 * ln].decode('utf-16le')
        except UnicodeDecodeError:
            continue
        vo = 24 + 2 * ln + 12
        if vo + 16 > len(b):
            continue
        v1, v2 = struct.unpack_from('<dd', b, vo)
        out.setdefault(name, []).append((i, v1, v2))
    return out
