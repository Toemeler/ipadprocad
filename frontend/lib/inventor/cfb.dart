// OLE2 Compound File Binary ([MS-CFB]) reader — the container of every
// Inventor document. Read only; version 3 (512-byte sectors) and version 4
// (4096-byte sectors).
import 'dart:convert';
import 'dart:typed_data';

class CfbException implements Exception {
  final String message;
  CfbException(this.message);
  @override
  String toString() => 'CfbException: $message';
}

const _kEndOfChain = 0xFFFFFFFE;
const _kFree = 0xFFFFFFFF;

class CfbEntry {
  final String name;
  final int type; // 1 storage, 2 stream, 5 root
  final int left, right, child;
  final Uint8List clsid;
  final int start, size;
  String path = '';
  CfbEntry(this.name, this.type, this.left, this.right, this.child, this.clsid,
      this.start, this.size);
  bool get isStream => type == 2;
}

class CfbFile {
  final Uint8List data;
  late final int _sectorSize, _miniSectorSize, _miniCutoff;
  late final List<int> _fat, _miniFat;
  late final List<CfbEntry> entries;
  late final Uint8List _miniStream;

  CfbFile(this.data) {
    const sig = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    if (data.length < 512) throw CfbException('file too small');
    for (var i = 0; i < 8; i++) {
      if (data[i] != sig[i]) throw CfbException('not an OLE compound file');
    }
    final h = ByteData.sublistView(data, 0, 512);
    _sectorSize = 1 << h.getUint16(30, Endian.little);
    _miniSectorSize = 1 << h.getUint16(32, Endian.little);
    final nFat = h.getUint32(44, Endian.little);
    final firstDir = h.getUint32(48, Endian.little);
    _miniCutoff = h.getUint32(56, Endian.little);
    final firstMiniFat = h.getUint32(60, Endian.little);
    var difatSector = h.getUint32(68, Endian.little);
    // the FAT's own sector list: 109 in the header, the rest in DIFAT sectors
    final fatSectors = <int>[];
    for (var i = 0; i < 109 && fatSectors.length < nFat; i++) {
      fatSectors.add(h.getUint32(76 + 4 * i, Endian.little));
    }
    var guard = 0;
    while (fatSectors.length < nFat && difatSector < _kEndOfChain) {
      final off = _off(difatSector);
      final per = _sectorSize ~/ 4 - 1;
      for (var i = 0; i < per && fatSectors.length < nFat; i++) {
        fatSectors.add(_u32(off + 4 * i));
      }
      difatSector = _u32(off + 4 * per);
      if (++guard > 1 << 20) throw CfbException('DIFAT loop');
    }
    _fat = <int>[];
    for (final s in fatSectors) {
      final off = _off(s);
      for (var i = 0; i < _sectorSize ~/ 4; i++) {
        _fat.add(_u32(off + 4 * i));
      }
    }
    final miniFatBytes = firstMiniFat < _kEndOfChain ? _chain(firstMiniFat, null) : Uint8List(0);
    final md = ByteData.sublistView(miniFatBytes);
    _miniFat = [for (var i = 0; i + 4 <= miniFatBytes.length; i += 4) md.getUint32(i, Endian.little)];
    final dir = _chain(firstDir, null);
    entries = [];
    for (var o = 0; o + 128 <= dir.length; o += 128) {
      final d = ByteData.sublistView(dir, o, o + 128);
      final nameLen = d.getUint16(64, Endian.little);
      final nameBytes = nameLen >= 2 ? dir.sublist(o, o + nameLen - 2) : Uint8List(0);
      final name = _utf16(nameBytes);
      final size = _sectorSize == 512
          ? d.getUint32(120, Endian.little)
          : d.getUint32(120, Endian.little) + d.getUint32(124, Endian.little) * 0x100000000;
      entries.add(CfbEntry(
          name,
          d.getUint8(66),
          d.getUint32(68, Endian.little),
          d.getUint32(72, Endian.little),
          d.getUint32(76, Endian.little),
          dir.sublist(o + 80, o + 96),
          d.getUint32(116, Endian.little),
          size));
    }
    if (entries.isEmpty || entries[0].type != 5) throw CfbException('no root entry');
    final root = entries[0];
    _miniStream = root.start < _kEndOfChain ? _chain(root.start, root.size) : Uint8List(0);
    _walk(root.child, '', 0);
  }

  int _off(int sector) {
    final o = (sector + 1) * _sectorSize;
    if (o + _sectorSize > data.length + _sectorSize) throw CfbException('sector out of range');
    return o;
  }

  int _u32(int o) => data[o] | (data[o + 1] << 8) | (data[o + 2] << 16) | (data[o + 3] << 24);

  Uint8List _chain(int start, int? size) {
    final out = BytesBuilder(copy: false);
    var s = start;
    var guard = 0;
    while (s < _kEndOfChain) {
      if (s >= _fat.length && _fat.isNotEmpty) throw CfbException('chain out of FAT');
      final o = _off(s);
      final end = o + _sectorSize > data.length ? data.length : o + _sectorSize;
      out.add(Uint8List.sublistView(data, o, end));
      if (_fat.isEmpty) break;
      s = _fat[s];
      if (++guard > data.length ~/ _sectorSize + 2) throw CfbException('FAT loop');
    }
    final b = out.takeBytes();
    return size == null || size >= b.length ? b : Uint8List.sublistView(b, 0, size);
  }

  Uint8List _miniChain(int start, int size) {
    final out = BytesBuilder(copy: false);
    var s = start;
    var guard = 0;
    while (s < _kEndOfChain && s != _kFree) {
      final o = s * _miniSectorSize;
      if (o + _miniSectorSize > _miniStream.length) throw CfbException('mini sector out of range');
      out.add(Uint8List.sublistView(_miniStream, o, o + _miniSectorSize));
      s = s < _miniFat.length ? _miniFat[s] : _kEndOfChain;
      if (++guard > _miniFat.length + 1) throw CfbException('mini FAT loop');
    }
    final b = out.takeBytes();
    return size >= b.length ? b : Uint8List.sublistView(b, 0, size);
  }

  void _walk(int sid, String parent, int depth) {
    if (sid >= entries.length || sid == _kFree || depth > 64) return;
    final e = entries[sid];
    e.path = parent.isEmpty ? e.name : '$parent/${e.name}';
    _walk(e.left, parent, depth + 1);
    _walk(e.right, parent, depth + 1);
    if (e.type == 1) _walk(e.child, e.path, depth + 1);
  }

  static String _utf16(Uint8List b) {
    final codes = <int>[for (var i = 0; i + 1 < b.length; i += 2) b[i] | (b[i + 1] << 8)];
    return String.fromCharCodes(codes);
  }

  Iterable<CfbEntry> get streams => entries.where((e) => e.isStream && e.path.isNotEmpty);

  CfbEntry? find(String path) {
    for (final e in entries) {
      if (e.path == path) return e;
    }
    return null;
  }

  Uint8List read(CfbEntry e) {
    if (!e.isStream) throw CfbException('${e.path} is not a stream');
    if (e.size == 0) return Uint8List(0);
    return e.size < _miniCutoff ? _miniChain(e.start, e.size) : _chain(e.start, e.size);
  }

  Uint8List? readPath(String path) {
    final e = find(path);
    return e == null ? null : read(e);
  }

  /// Root storage CLSID, as the usual GUID string.
  String get rootClsid => guidString(entries[0].clsid);
}

String guidString(Uint8List b) {
  String hex(int v, int n) => v.toRadixString(16).padLeft(n, '0');
  final d = ByteData.sublistView(b);
  return '${hex(d.getUint32(0, Endian.little), 8)}-${hex(d.getUint16(4, Endian.little), 4)}-'
      '${hex(d.getUint16(6, Endian.little), 4)}-'
      '${[for (var i = 8; i < 10; i++) hex(b[i], 2)].join()}-'
      '${[for (var i = 10; i < 16; i++) hex(b[i], 2)].join()}';
}

/// Latin-1 safe helper used by callers that decode 8-bit strings.
String latin1String(Uint8List b) => latin1.decode(b, allowInvalid: true);
