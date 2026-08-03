// Prototype — a minimal ZIP writer, so a bug report is ONE file.
//
// No package for this deliberately. `archive` would do it, but a bug reporter
// that only works when a pub fetch succeeded is a bug reporter that is missing
// exactly when the build is in trouble. Everything here is dart:io: raw
// deflate comes from ZLibCodec(raw: true), which is the same DEFLATE stream
// ZIP method 8 wants, and the rest is forty bytes of header arithmetic.
//
// Scope: stored + deflated entries, no directories, no zip64, no encryption.
// A diagnostic bundle is a handful of text files and a JSON document; it will
// never approach the 4 GB where zip64 starts to matter.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// CRC-32 (IEEE 802.3), the checksum every ZIP entry carries.
class Crc32 {
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final t = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[i] = c;
    }
    return t;
  }

  static int compute(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class _Entry {
  _Entry(this.name, this.crc, this.compressed, this.uncompressed, this.method,
      this.offset);
  final String name;
  final int crc, compressed, uncompressed, method, offset;
}

/// General purpose bit 11, the "language encoding flag" (EFS) from APPNOTE
/// 6.3.0: this entry's name is UTF-8.
///
/// Not optional. Without it a reader is entitled to decode names as CP437,
/// and GNU unzip does exactly that — a sketch called "Skizze-Übergröße" came
/// out under a mangled name and the file simply was not where the bundle said
/// it was. It cost a CI failure to find because the container that wrote the
/// test happened to have an unzip that guessed UTF-8, and the runner's did
/// not. Names here are always UTF-8, so the flag is always set.
const int _kUtf8NameFlag = 0x0800;

/// Builds a ZIP archive in memory.
///
/// Usage: [addFile] for each member, then [finish] for the bytes.
class ZipWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);
  final List<_Entry> _entries = [];
  final DateTime _stamp;

  ZipWriter({DateTime? stamp}) : _stamp = stamp ?? DateTime.now();

  /// MS-DOS packed time/date, which is what the format stores.
  int get _dosTime =>
      (_stamp.hour << 11) | (_stamp.minute << 5) | (_stamp.second ~/ 2);
  int get _dosDate =>
      (((_stamp.year - 1980).clamp(0, 127)) << 9) |
      (_stamp.month << 5) |
      _stamp.day;

  static Uint8List _u16(int v) {
    final b = Uint8List(2);
    ByteData.view(b.buffer).setUint16(0, v & 0xFFFF, Endian.little);
    return b;
  }

  static Uint8List _u32(int v) {
    final b = Uint8List(4);
    ByteData.view(b.buffer).setUint32(0, v & 0xFFFFFFFF, Endian.little);
    return b;
  }

  /// Adds [bytes] under [name]. Compresses unless that makes it bigger, which
  /// happens on tiny or already-compressed members.
  void addFile(String name, List<int> bytes) {
    final nameBytes = utf8.encode(name);
    final crc = Crc32.compute(bytes);
    List<int> payload;
    int method;
    try {
      final deflated = ZLibCodec(raw: true, level: 6).encode(bytes);
      if (deflated.length < bytes.length) {
        payload = deflated;
        method = 8; // DEFLATE
      } else {
        payload = bytes;
        method = 0; // STORE
      }
    } catch (_) {
      // A compressor failure must not lose the report.
      payload = bytes;
      method = 0;
    }

    final offset = _out.length;
    _out
      ..add(_u32(0x04034b50)) // local file header
      ..add(_u16(20)) // version needed
      ..add(_u16(_kUtf8NameFlag))
      ..add(_u16(method))
      ..add(_u16(_dosTime))
      ..add(_u16(_dosDate))
      ..add(_u32(crc))
      ..add(_u32(payload.length))
      ..add(_u32(bytes.length))
      ..add(_u16(nameBytes.length))
      ..add(_u16(0)) // extra length
      ..add(nameBytes)
      ..add(payload);

    _entries
        .add(_Entry(name, crc, payload.length, bytes.length, method, offset));
  }

  /// Adds [text] as a UTF-8 member.
  void addText(String name, String text) => addFile(name, utf8.encode(text));

  /// The finished archive.
  Uint8List finish() {
    final cdStart = _out.length;
    for (final e in _entries) {
      final nameBytes = utf8.encode(e.name);
      _out
        ..add(_u32(0x02014b50)) // central directory header
        ..add(_u16(20)) // version made by
        ..add(_u16(20)) // version needed
        ..add(_u16(_kUtf8NameFlag))
        ..add(_u16(e.method))
        ..add(_u16(_dosTime))
        ..add(_u16(_dosDate))
        ..add(_u32(e.crc))
        ..add(_u32(e.compressed))
        ..add(_u32(e.uncompressed))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0)) // extra
        ..add(_u16(0)) // comment
        ..add(_u16(0)) // disk number start
        ..add(_u16(0)) // internal attrs
        ..add(_u32(0)) // external attrs
        ..add(_u32(e.offset))
        ..add(nameBytes);
    }
    final cdSize = _out.length - cdStart;
    _out
      ..add(_u32(0x06054b50)) // end of central directory
      ..add(_u16(0)) // this disk
      ..add(_u16(0)) // disk with cd
      ..add(_u16(_entries.length))
      ..add(_u16(_entries.length))
      ..add(_u32(cdSize))
      ..add(_u32(cdStart))
      ..add(_u16(0)); // comment length
    return _out.takeBytes();
  }
}
