// M278 — a 3MF the app called "no model", and the ZIP64 records behind it.
//
// "The mesh to cad converter doesn't handle 3mf files, it didn't work with
// this one."
//
// The converter never saw the file. A 3MF is a ZIP container, and this one's
// classic end-of-central-directory record holds 0xFFFFFFFF where the directory
// offset belongs — the ZIP64 sentinel. The reader took it literally, started
// its walk 4 GB past the end of a 250 KB file, found nothing, and the 3MF
// reader reported "no model" for a container whose model was sitting at the
// conventional path all along.
//
// THE PART WORTH REMEMBERING: the file is a quarter of a megabyte. ZIP64 is
// not only for archives past 4 GB — several writers, this slicer among them,
// emit the records unconditionally. Treating ZIP64 as the exotic case means
// treating a large share of real 3MF files as broken.
//
// The fixtures are built here rather than checked in as a binary, because the
// bug is in the CONTAINER and a test that cannot state the container's bytes
// cannot pin it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/mesh_io.dart';

const int _sentinel = 0xFFFFFFFF;

/// The smallest 3MF that describes one triangle, standing up in the file's own
/// Z-up world so the M276 turn is visible in the result.
String _model() => '<?xml version="1.0" encoding="utf-8"?>'
    '<model unit="millimeter">'
    '<resources><object id="1" type="model"><mesh>'
    '<vertices>'
    '<vertex x="0" y="0" z="0"/>'
    '<vertex x="10" y="0" z="0"/>'
    '<vertex x="0" y="0" z="7"/>'
    '</vertices>'
    '<triangles><triangle v1="0" v2="1" v3="2"/></triangles>'
    '</mesh></object></resources>'
    '<build><item objectid="1"/></build></model>';

/// A ZIP holding one STORED entry.
///
/// [zip64] decides whether the sizes and offsets go in the fixed records or are
/// replaced by sentinels with the real values in the extended-information
/// field. [onlyOffset] builds the case the spec allows and writers rarely
/// produce: the sizes fit, the local-header OFFSET does not, so the extra field
/// carries ONE value and reading it as a fixed layout picks up the wrong one.
Uint8List _zip(String name, String content,
    {required bool zip64, bool onlyOffset = false}) {
  final nameB = utf8.encode(name);
  final data = utf8.encode(content);
  final b = BytesBuilder();

  void u16(BytesBuilder t, int v) =>
      t.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  void u32(BytesBuilder t, int v) =>
      t.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u64(BytesBuilder t, int v) =>
      t.add(Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little));

  // ---- local file header
  final localAt = 0;
  u32(b, 0x04034b50);
  u16(b, 20); // version needed
  u16(b, 0); // flags
  u16(b, 0); // stored
  u32(b, 0); // time+date
  u32(b, 0); // crc — never checked by the reader
  u32(b, data.length);
  u32(b, data.length);
  u16(b, nameB.length);
  u16(b, 0); // no local extra
  b.add(nameB);
  b.add(data);

  // ---- central directory
  final cdAt = b.length;
  final sizeIsSentinel = zip64 && !onlyOffset;
  final offIsSentinel = zip64;
  final extra = BytesBuilder();
  if (zip64) {
    final body = BytesBuilder();
    if (sizeIsSentinel) {
      u64(body, data.length); // uncompressed
      u64(body, data.length); // compressed
    }
    if (offIsSentinel) u64(body, localAt);
    u16(extra, 0x0001);
    u16(extra, body.length);
    extra.add(body.toBytes());
  }
  final extraB = extra.toBytes();

  u32(b, 0x02014b50);
  u16(b, 20); // version made by
  u16(b, 20); // version needed
  u16(b, 0); // flags
  u16(b, 0); // stored
  u32(b, 0); // time+date
  u32(b, 0); // crc
  u32(b, sizeIsSentinel ? _sentinel : data.length); // compressed
  u32(b, sizeIsSentinel ? _sentinel : data.length); // uncompressed
  u16(b, nameB.length);
  u16(b, extraB.length);
  u16(b, 0); // comment
  u16(b, 0); // disk
  u16(b, 0); // internal attrs
  u32(b, 0); // external attrs
  u32(b, offIsSentinel ? _sentinel : localAt);
  b.add(nameB);
  b.add(extraB);
  final cdSize = b.length - cdAt;

  if (zip64) {
    // ---- ZIP64 end of central directory RECORD
    final z64At = b.length;
    u32(b, 0x06064b50);
    u64(b, 44); // size of the rest of this record
    u16(b, 45); // version made by
    u16(b, 45); // version needed
    u32(b, 0); // this disk
    u32(b, 0); // disk with cd
    u64(b, 1); // entries on this disk
    u64(b, 1); // entries total
    u64(b, cdSize);
    u64(b, cdAt);
    // ---- ZIP64 LOCATOR, immediately before the classic record
    u32(b, 0x07064b50);
    u32(b, 0); // disk holding the record
    u64(b, z64At);
    u32(b, 1); // total disks
  }

  // ---- classic end of central directory
  u32(b, 0x06054b50);
  u16(b, 0);
  u16(b, 0);
  u16(b, zip64 ? 0xFFFF : 1);
  u16(b, zip64 ? 0xFFFF : 1);
  u32(b, zip64 ? _sentinel : cdSize);
  u32(b, zip64 ? _sentinel : cdAt);
  u16(b, 0); // no comment
  return b.toBytes();
}

MeshSoup _read(Uint8List zip) => loadMeshBytes(zip, path: 'a.3mf');

void main() {
  group('the container', () {
    test('a PLAIN zip still reads, exactly as before', () {
      // The regression guard on the fix: the ordinary path must not have moved.
      final m = _read(_zip('3D/3dmodel.model', _model(), zip64: false));
      expect(m.format, '3mf');
      expect(m.triangleCount, 1);
      expect(m.vertexCount, 3);
    });

    test('a ZIP64 container reads — the reported file', () {
      final m = _read(_zip('3D/3dmodel.model', _model(), zip64: true));
      expect(m.triangleCount, 1);
      expect(m.vertexCount, 3);
    });

    test('...and the two produce the SAME mesh', () {
      // The container is packaging. Which records it used must not be visible
      // in the geometry.
      final a = _read(_zip('3D/3dmodel.model', _model(), zip64: false));
      final b = _read(_zip('3D/3dmodel.model', _model(), zip64: true));
      expect(b.vertices, a.vertices);
      expect(b.triangles, a.triangles);
    });

    test('the extended field is POSITIONAL, not a fixed layout', () {
      // The case where only the local-header offset overflowed, so the extra
      // field holds ONE value. Reading it as "uncompressed, compressed,
      // offset" would take the offset out of the uncompressed slot and land
      // the reader somewhere in the middle of the file.
      final m = _read(_zip('3D/3dmodel.model', _model(),
          zip64: true, onlyOffset: true));
      expect(m.triangleCount, 1);
      expect(m.vertexCount, 3);
    });

    test('a model NOT at the conventional path is still found', () {
      final m = _read(_zip('3D/somethingelse.model', _model(), zip64: true));
      expect(m.triangleCount, 1);
    });

    test('something that is not an archive at all is refused, not crashed', () {
      expect(
          _reasonOf(() => _read(Uint8List.fromList(List.filled(200, 7)))),
          MeshFailure.notAnArchive);
    });
  });

  group('what came out of the reported file', () {
    test('a Z-up 3MF is turned upright, like an STL', () {
      // The bookmark that prompted this is 2 mm thick and lies flat on the
      // printer's bed, i.e. 2 mm tall in the file's Z. After the M276 turn it
      // is 2 mm tall in the app's Y and flat on the app's floor.
      final m = _read(_zip('3D/3dmodel.model', _model(), zip64: true));
      expect(m.uprightedFromZUp, isTrue);
      final b = m.bounds!;
      // The triangle's apex was at z = 7 in the file.
      expect(b[4], closeTo(7, 1e-9), reason: 'it reaches 7 UP (Y)');
      expect(b[3] - b[0], closeTo(10, 1e-9), reason: 'and 10 wide in X');
    });
  });
}

MeshFailure? _reasonOf(void Function() f) {
  try {
    f();
    return null;
  } on MeshLoadException catch (e) {
    return e.reason;
  }
}
