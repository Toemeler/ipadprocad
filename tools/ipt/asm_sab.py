"""Autodesk ShapeManager (ASM) binary SAB, as embedded in an Inventor
PmBRepSegment. ASM is a fork of ACIS; its binary form is ACIS SAB.

Header:  "ASM BinaryFile4", 4 x int32 (version, records, bodies, flags),
         3 strings (product, ASM version, date), 3 doubles (unit in mm,
         resabs, resnor). Inventor writes unit = 10.0: model space is cm.

Then one record per entity until an "End-of-..." marker. A record is its
type name (ident, optionally followed by chained sub-idents, e.g.
"ATTRIB_CUSTOM" + "attrib"), its fields, and a terminator. Every entity
starts with: attribute pointer, id (int), history pointer.

Tags:
  04 int32  06 double  07/08/09 string (u8/u16/u32 length)  0a TRUE  0b FALSE
  0c pointer  0d ident  0e sub-ident  0f '{'  10 '}'  11 end of record
  12 string (u8 length)  13 position (3 doubles)  14 vector (3 doubles)
  15 enum (int32)  16 2 doubles
"""
import struct


class Ptr(int):
    """A reference to another record, by index; -1 is null."""
    def __repr__(self):
        return f'${int(self)}'


class Ident(str):
    """A type name inside a record (e.g. the subtype of a spline surface)."""
    def __repr__(self):
        return '@' + str(self)


class Logical:
    __slots__ = ('v',)

    def __init__(self, v):
        self.v = v

    def __bool__(self):
        return self.v

    def __repr__(self):
        return 'T' if self.v else 'F'


class Enum(int):
    def __repr__(self):
        return f'enum:{int(self)}'


class Open:
    def __repr__(self):
        return '{'


class Close:
    def __repr__(self):
        return '}'


OPEN, CLOSE = Open(), Close()
TRUE, FALSE = Logical(True), Logical(False)


class Record:
    __slots__ = ('index', 'type', 'fields', 'offset')

    def __init__(self, index, type_, fields, offset):
        self.index, self.type, self.fields, self.offset = index, type_, fields, offset

    @property
    def id(self):
        return self.fields[1] if len(self.fields) > 1 else -1

    def ptrs(self):
        return [int(v) for v in self.fields if isinstance(v, Ptr)]

    def top(self):
        """Fields outside any { } subtype block."""
        depth, out = 0, []
        for v in self.fields:
            if v is OPEN:
                depth += 1
            elif v is CLOSE:
                depth -= 1
            elif depth == 0:
                out.append(v)
        return out

    def __repr__(self):
        return f'-{self.index} {self.type} ' + ' '.join(map(repr, self.fields))


class SabError(ValueError):
    pass


def _value(b, p):
    t = b[p]
    p += 1
    if t == 0x04:
        return struct.unpack_from('<i', b, p)[0], p + 4
    if t == 0x06:
        return struct.unpack_from('<d', b, p)[0], p + 8
    if t in (0x07, 0x12):
        n = b[p]
        return b[p + 1:p + 1 + n].decode('latin1'), p + 1 + n
    if t == 0x08:
        n = struct.unpack_from('<H', b, p)[0]
        return b[p + 2:p + 2 + n].decode('latin1'), p + 2 + n
    if t == 0x09:
        n = struct.unpack_from('<I', b, p)[0]
        return b[p + 4:p + 4 + n].decode('latin1'), p + 4 + n
    if t == 0x0a:
        return TRUE, p
    if t == 0x0b:
        return FALSE, p
    if t == 0x0c:
        return Ptr(struct.unpack_from('<i', b, p)[0]), p + 4
    if t == 0x0d:
        n = b[p]
        return Ident(b[p + 1:p + 1 + n].decode('latin1')), p + 1 + n
    if t == 0x0e:
        n = b[p]
        return Ident(b[p + 1:p + 1 + n].decode('latin1') + '-'), p + 1 + n
    if t == 0x0f:
        return OPEN, p
    if t == 0x10:
        return CLOSE, p
    if t == 0x11:
        return None, p
    if t in (0x13, 0x14):
        return struct.unpack_from('<3d', b, p), p + 24
    if t == 0x15:
        return Enum(struct.unpack_from('<i', b, p)[0]), p + 4
    if t == 0x16:
        return struct.unpack_from('<2d', b, p), p + 16
    raise SabError(f'unknown SAB tag 0x{t:02x} at offset {p - 1}')


class Sab:
    def __init__(self, header, records, end_offset):
        self.header, self.records, self.end_offset = header, records, end_offset

    def __getitem__(self, i):
        return self.records[i]

    def of_type(self, name):
        return [r for r in self.records if r.type == name]


def find(data):
    i = data.find(b'ASM BinaryFile')
    if i < 0:
        i = data.find(b'ACIS BinaryFile')
    return i


def parse(data, start=None):
    if start is None:
        start = find(data)
    if start < 0:
        raise SabError('no ASM/ACIS SAB found')
    p = data.index(b'BinaryFile', start) + len('BinaryFile') + 1
    version, nrec, nbody, flags = struct.unpack_from('<4i', data, p)
    p += 16
    strs = []
    for _ in range(3):
        v, p = _value(data, p)
        strs.append(v)
    dbl = []
    for _ in range(3):
        v, p = _value(data, p)
        dbl.append(v)
    header = dict(version=version, records=nrec, bodies=nbody, flags=flags,
                  product=strs[0], asm=strs[1], date=strs[2],
                  unit_mm=dbl[0], resabs=dbl[1], resnor=dbl[2],
                  magic=data[start:data.index(b'BinaryFile', start) + 11].decode('latin1'))
    records = []
    while p < len(data):
        off = p
        name = ''
        while data[p] in (0x0d, 0x0e):
            v, p = _value(data, p)
            name += v
        if not name:
            raise SabError(f'record without a type at offset {p}')
        if name.startswith('End-of-') or name.startswith('Begin-of-ASM-History'):
            header['end'] = name
            break
        fields = []
        while True:
            v, p = _value(data, p)
            if v is None:
                break
            fields.append(v)
        records.append(Record(len(records), name, fields, off))
    _resolve_subtype_refs(records)
    return Sab(header, records, p)


def _resolve_subtype_refs(records):
    """ACIS writes a shared subtype object (a blend surface two faces use,
    say) once, and later occurrences as `{ ref n }`: n counts every `{ type`
    block in file order, outer before inner. Replace each ref by a copy of
    the block it names, so a record always carries its own geometry."""
    table = []
    for r in records:
        f = r.fields
        stack = []
        for i, v in enumerate(f):
            if v is OPEN:
                if i + 1 < len(f) and f[i + 1] == 'ref':
                    stack.append(None)
                    continue
                entry = [r, i, None]
                table.append(entry)
                stack.append(entry)
            elif v is CLOSE:
                e = stack.pop()
                if e is not None:
                    e[2] = i
        # expand this record's refs now: they only ever point backwards
        if any(v == 'ref' and isinstance(v, Ident) for v in f):
            out, i = [], 0
            while i < len(f):
                if f[i] is OPEN and i + 3 < len(f) and f[i + 1] == 'ref' and f[i + 3] is CLOSE:
                    src, a, b = table[f[i + 2]]
                    out.extend(src.fields[a:b + 1])
                    i += 4
                else:
                    out.append(f[i])
                    i += 1
            r.fields = out
