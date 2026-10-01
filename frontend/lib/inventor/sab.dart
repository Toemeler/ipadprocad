// Autodesk ShapeManager (ASM, an ACIS fork) binary SAB, as embedded in the
// segments of an Inventor document. Port of tools/ipt/asm_sab.py.
//
// Header: "ASM BinaryFile4", 4 x int32, 3 strings (product, version, date),
// 3 doubles (unit in mm -- Inventor writes 10: model space is cm --, resabs,
// resnor). Then one record per entity: type name (ident + chained
// sub-idents), fields, terminator. Every entity begins attrib, id, history.
//
// Tags: 04 int32, 06 double, 07/08/09 string (u8/u16/u32 length), 0a TRUE,
// 0b FALSE, 0c pointer, 0d ident, 0e sub-ident, 0f '{', 10 '}', 11 end of
// record, 12 string (u8), 13/14 position/vector (3 doubles), 15 enum,
// 16 2 doubles.
import 'dart:convert';
import 'dart:typed_data';

class SabException implements Exception {
  final String message;
  SabException(this.message);
  @override
  String toString() => 'SabException: $message';
}

/// A reference to another record (index; -1 null).
class SabPtr {
  final int i;
  const SabPtr(this.i);
  @override
  String toString() => '\$$i';
}

/// A type name inside a record (a subtype's name, "nubs", "cone", ...).
class SabIdent {
  final String s;
  const SabIdent(this.s);
  @override
  String toString() => '@$s';
}

class SabEnum {
  final int v;
  const SabEnum(this.v);
}

class _Mark {
  final String s;
  const _Mark(this.s);
}

const sabOpen = _Mark('{');
const sabClose = _Mark('}');

class SabRecord {
  final int index;
  final String type;
  List<Object> fields;
  SabRecord(this.index, this.type, this.fields);

  List<int> get ptrs => [for (final v in fields) if (v is SabPtr) v.i];

  /// The record's id (second field), -1 when absent.
  int get id => fields.length > 1 && fields[1] is int ? fields[1] as int : -1;
}

class Sab {
  final Map<String, Object> header;
  final List<SabRecord> records;
  Sab(this.header, this.records);

  SabRecord operator [](int i) => records[i];
  Iterable<SabRecord> ofType(String t) => records.where((r) => r.type == t);
  double get unitMm => (header['unit_mm'] as double?) ?? 1.0;
}

int findSab(Uint8List data) {
  final a = _find(data, ascii.encode('ASM BinaryFile'));
  return a >= 0 ? a : _find(data, ascii.encode('ACIS BinaryFile'));
}

int _find(Uint8List b, List<int> pat) {
  outer:
  for (var i = 0; i + pat.length <= b.length; i++) {
    for (var k = 0; k < pat.length; k++) {
      if (b[i + k] != pat[k]) continue outer;
    }
    return i;
  }
  return -1;
}

class _Reader {
  final Uint8List b;
  final ByteData d;
  int p;
  _Reader(this.b, this.p) : d = ByteData.sublistView(b);

  /// Next value; null for the end-of-record tag.
  Object? value() {
    final t = b[p++];
    switch (t) {
      case 0x04:
        final v = d.getInt32(p, Endian.little);
        p += 4;
        return v;
      case 0x06:
        final v = d.getFloat64(p, Endian.little);
        p += 8;
        return v;
      case 0x07:
      case 0x12:
        final n = b[p];
        final s = latin1.decode(b.sublist(p + 1, p + 1 + n));
        p += 1 + n;
        return s;
      case 0x08:
        final n = d.getUint16(p, Endian.little);
        final s = latin1.decode(b.sublist(p + 2, p + 2 + n));
        p += 2 + n;
        return s;
      case 0x09:
        final n = d.getUint32(p, Endian.little);
        final s = latin1.decode(b.sublist(p + 4, p + 4 + n));
        p += 4 + n;
        return s;
      case 0x0a:
        return true;
      case 0x0b:
        return false;
      case 0x0c:
        final v = d.getInt32(p, Endian.little);
        p += 4;
        return SabPtr(v);
      case 0x0d:
        final n = b[p];
        final s = latin1.decode(b.sublist(p + 1, p + 1 + n));
        p += 1 + n;
        return SabIdent(s);
      case 0x0e:
        final n = b[p];
        final s = latin1.decode(b.sublist(p + 1, p + 1 + n));
        p += 1 + n;
        return SabIdent('$s-');
      case 0x0f:
        return sabOpen;
      case 0x10:
        return sabClose;
      case 0x11:
        return null;
      case 0x13:
      case 0x14:
        final v = Float64List(3);
        for (var i = 0; i < 3; i++) {
          v[i] = d.getFloat64(p + 8 * i, Endian.little);
        }
        p += 24;
        return v;
      case 0x15:
        final v = d.getInt32(p, Endian.little);
        p += 4;
        return SabEnum(v);
      case 0x16:
        final v = Float64List(2);
        v[0] = d.getFloat64(p, Endian.little);
        v[1] = d.getFloat64(p + 8, Endian.little);
        p += 16;
        return v;
      default:
        throw SabException('unknown SAB tag 0x${t.toRadixString(16)} at ${p - 1}');
    }
  }
}

Sab parseSab(Uint8List data, [int? start]) {
  final s = start ?? findSab(data);
  if (s < 0) throw SabException('no ASM/ACIS SAB found');
  final bf = _find(Uint8List.sublistView(data, s), ascii.encode('BinaryFile')) + s;
  final r = _Reader(data, bf + 11);
  final d = ByteData.sublistView(data);
  final ints = [for (var i = 0; i < 4; i++) d.getInt32(r.p + 4 * i, Endian.little)];
  r.p += 16;
  final strs = [for (var i = 0; i < 3; i++) r.value()];
  final dbl = [for (var i = 0; i < 3; i++) r.value()];
  final header = <String, Object>{
    'version': ints[0],
    'bodies': ints[2],
    'product': strs[0] as String,
    'asm': strs[1] as String,
    'date': strs[2] as String,
    'unit_mm': dbl[0] as double,
    'resabs': dbl[1] as double,
    'resnor': dbl[2] as double,
  };
  final records = <SabRecord>[];
  while (r.p < data.length) {
    var name = '';
    while (r.p < data.length && (data[r.p] == 0x0d || data[r.p] == 0x0e)) {
      name += (r.value() as SabIdent).s;
    }
    if (name.isEmpty) throw SabException('record without a type at ${r.p}');
    if (name.startsWith('End-of-') || name.startsWith('Begin-of-ASM-History')) break;
    final fields = <Object>[];
    while (true) {
      final v = r.value();
      if (v == null) break;
      fields.add(v);
    }
    records.add(SabRecord(records.length, name, fields));
  }
  _resolveRefs(records);
  return Sab(header, records);
}

/// `{ ref n }` stands for the n-th `{ type` block in file order (outer
/// first); replace each by a copy of the block it names.
void _resolveRefs(List<SabRecord> records) {
  final table = <(SabRecord, int, int)>[];
  for (final r in records) {
    final f = r.fields;
    final stack = <int?>[];
    for (var i = 0; i < f.length; i++) {
      if (identical(f[i], sabOpen)) {
        final next = i + 1 < f.length ? f[i + 1] : null;
        if (next is SabIdent && next.s == 'ref') {
          stack.add(null);
          continue;
        }
        table.add((r, i, -1));
        stack.add(table.length - 1);
      } else if (identical(f[i], sabClose)) {
        final e = stack.isEmpty ? null : stack.removeLast();
        if (e != null) table[e] = (table[e].$1, table[e].$2, i);
      }
    }
    var hasRef = false;
    for (final v in f) {
      if (v is SabIdent && v.s == 'ref') hasRef = true;
    }
    if (!hasRef) continue;
    final out = <Object>[];
    var i = 0;
    while (i < f.length) {
      if (identical(f[i], sabOpen) &&
          i + 3 < f.length &&
          f[i + 1] is SabIdent &&
          (f[i + 1] as SabIdent).s == 'ref' &&
          identical(f[i + 3], sabClose)) {
        final (src, a, b) = table[f[i + 2] as int];
        out.addAll(src.fields.sublist(a, b + 1));
        i += 4;
      } else {
        out.add(f[i]);
        i++;
      }
    }
    r.fields = out;
  }
}
