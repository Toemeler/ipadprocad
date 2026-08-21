// M232 — Open accepts a mesh: STL, OBJ, 3MF.
//
// What is pinned here is the DART half — reading the file and deciding what to
// do with it. That half is worth pinning on its own because it is where every
// format quirk lives, and because none of it needs a linked kernel: the
// geometry half (segment, fit surfaces, sew a solid) is C++ and is pinned by
// backend/occt/tests/mesh_recon_test.cpp, which reconstructs solids OCCT built
// and compares topology and volume against the known answer.
//
// The cases below are the ones real files actually hit:
//
//   * a BINARY STL whose 80-byte header begins with the word "solid" — the
//     usual "starts with solid means ASCII" test calls this one wrong, and
//     several slicers write exactly that
//   * an OBJ with quads, negative indices and per-vertex colours
//   * a 3MF with components and a build transform, which is how MakerWorld
//     ships anything assembled from repeated parts, and with a unit that is
//     not millimetres
//   * files that are broken, which must produce a sentence about THEIR file
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_ref.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/mesh_io.dart';

/// A unit cube as 12 triangles, corner at the origin, side [s].
List<List<double>> _cubeTris(double s) {
  final v = <List<double>>[];
  List<double> p(double x, double y, double z) => [x * s, y * s, z * s];
  final c = [
    p(0, 0, 0), p(1, 0, 0), p(1, 1, 0), p(0, 1, 0),
    p(0, 0, 1), p(1, 0, 1), p(1, 1, 1), p(0, 1, 1),
  ];
  for (final q in [
    [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
    [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
  ]) {
    v.add([...c[q[0]], ...c[q[1]], ...c[q[2]]]);
    v.add([...c[q[0]], ...c[q[2]], ...c[q[3]]]);
  }
  return v;
}

Uint8List _binaryStl(List<List<double>> tris, {String header = 'binary'}) {
  final b = BytesBuilder();
  final h = Uint8List(80);
  h.setRange(0, header.length, utf8.encode(header));
  b.add(h);
  b.add((ByteData(4)..setUint32(0, tris.length, Endian.little))
      .buffer
      .asUint8List());
  for (final t in tris) {
    final d = ByteData(50);
    // Facet normals left at zero on purpose: real files often have them wrong,
    // and the reader must not be reading them.
    for (var i = 0; i < 9; i++) {
      d.setFloat32(12 + i * 4, t[i], Endian.little);
    }
    b.add(d.buffer.asUint8List());
  }
  return b.toBytes();
}

Uint8List _asciiStl(List<List<double>> tris) {
  final sb = StringBuffer('solid thing\n');
  for (final t in tris) {
    sb.writeln('  facet normal 0 0 0');
    sb.writeln('    outer loop');
    for (var i = 0; i < 3; i++) {
      sb.writeln('      vertex ${t[i * 3]} ${t[i * 3 + 1]} ${t[i * 3 + 2]}');
    }
    sb.writeln('    endloop');
    sb.writeln('  endfacet');
  }
  sb.writeln('endsolid thing');
  return Uint8List.fromList(utf8.encode(sb.toString()));
}

int _crc32(List<int> bytes) {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[i] = c;
  }
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = t[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// The smallest ZIP that a 3MF reader has to cope with. Mirrors
/// zip_writer.dart: stored or raw-deflated, central directory, EOCD.
Uint8List _zip(Map<String, String> files, {bool deflate = true}) {
  final out = BytesBuilder(), central = BytesBuilder();
  final offsets = <int>[], metas = <List<int>>[];
  files.forEach((name, content) {
    final raw = utf8.encode(content);
    final payload = deflate ? ZLibCodec(raw: true, level: 6).encode(raw) : raw;
    final method = deflate ? 8 : 0;
    offsets.add(out.length);
    metas.add([_crc32(raw), payload.length, raw.length, method]);
    final nb = utf8.encode(name);
    final lh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint32(14, _crc32(raw), Endian.little)
      ..setUint32(18, payload.length, Endian.little)
      ..setUint32(22, raw.length, Endian.little)
      ..setUint16(26, nb.length, Endian.little);
    out.add(lh.buffer.asUint8List());
    out.add(nb);
    out.add(payload);
  });
  final cdStart = out.length;
  var i = 0;
  files.forEach((name, _) {
    final nb = utf8.encode(name);
    final m = metas[i];
    final ch = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, m[3], Endian.little)
      ..setUint32(16, m[0], Endian.little)
      ..setUint32(20, m[1], Endian.little)
      ..setUint32(24, m[2], Endian.little)
      ..setUint16(28, nb.length, Endian.little)
      ..setUint32(42, offsets[i], Endian.little);
    central.add(ch.buffer.asUint8List());
    central.add(nb);
    i++;
  });
  final cd = central.toBytes();
  out.add(cd);
  out.add((ByteData(22)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint16(8, files.length, Endian.little)
        ..setUint16(10, files.length, Endian.little)
        ..setUint32(12, cd.length, Endian.little)
        ..setUint32(16, cdStart, Endian.little))
      .buffer
      .asUint8List());
  return out.toBytes();
}

String _modelXml(
    {String unit = 'millimeter', bool components = false, bool build = true}) {
  final verts = StringBuffer(), tris = StringBuffer();
  const c = [
    [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
    [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1],
  ];
  for (final p in c) {
    verts.write('<vertex x="${p[0]}" y="${p[1]}" z="${p[2]}"/>');
  }
  for (final q in [
    [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
    [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
  ]) {
    tris.write('<triangle v1="${q[0]}" v2="${q[1]}" v3="${q[2]}"/>');
    tris.write('<triangle v1="${q[0]}" v2="${q[2]}" v3="${q[3]}"/>');
  }
  final obj1 = '<object id="1" type="model"><mesh><vertices>$verts</vertices>'
      '<triangles>$tris</triangles></mesh></object>';
  final obj2 = components
      ? '<object id="2" type="model"><components>'
          '<component objectid="1" transform="1 0 0 0 1 0 0 0 1 10 0 0"/>'
          '<component objectid="1"/></components></object>'
      : '';
  final items = build
      ? (components
          ? '<build><item objectid="2"/></build>'
          : '<build><item objectid="1" '
              'transform="2 0 0 0 2 0 0 0 2 5 5 5"/></build>')
      : '';
  return '<?xml version="1.0" encoding="UTF-8"?>\n<!-- a comment -->\n'
      '<model unit="$unit" '
      'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">'
      '<resources>$obj1$obj2</resources>$items</model>';
}

/// A 3MF that names far more geometry than it contains.
///
/// `<components>` point at other objects, so [levels] tiers of [fanout] turn
/// one cube into fanout^levels copies of it from a file of a few kilobytes.
/// This is the mesh equivalent of a zip bomb and a real 3MF can do it by
/// accident — an assembly of an assembly of a fastener.
String _bombXml({int fanout = 60, int levels = 3}) {
  final verts = StringBuffer(), tris = StringBuffer();
  const c = [
    [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
    [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1],
  ];
  for (final p in c) {
    verts.write('<vertex x="${p[0]}" y="${p[1]}" z="${p[2]}"/>');
  }
  for (final q in [
    [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
    [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
  ]) {
    tris.write('<triangle v1="${q[0]}" v2="${q[1]}" v3="${q[2]}"/>');
    tris.write('<triangle v1="${q[0]}" v2="${q[2]}" v3="${q[3]}"/>');
  }
  final objs = StringBuffer('<object id="1" type="model"><mesh>'
      '<vertices>$verts</vertices>'
      '<triangles>$tris</triangles></mesh></object>');
  for (var lvl = 2; lvl <= levels + 1; lvl++) {
    objs.write('<object id="$lvl" type="model"><components>');
    for (var i = 0; i < fanout; i++) {
      objs.write('<component objectid="${lvl - 1}"/>');
    }
    objs.write('</components></object>');
  }
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<model unit="millimeter">'
      '<resources>$objs</resources>'
      '<build><item objectid="${levels + 1}"/></build></model>';
}

/// The [MeshFailure] a reader refuses with, or null if it did not refuse.
MeshFailure? _refusalFor(void Function() f) {
  try {
    f();
    return null;
  } on MeshLoadException catch (e) {
    return e.reason;
  }
}

/// The `detail` carried alongside the refusal, if any.
String? _detailFor(void Function() f) {
  try {
    f();
    return null;
  } on MeshLoadException catch (e) {
    return e.detail;
  }
}

/// The `count` carried alongside the refusal, if any.
int? _detailCountFor(void Function() f) {
  try {
    f();
    return null;
  } on MeshLoadException catch (e) {
    return e.count;
  }
}

void main() {
  group('STL', () {
    test('binary: welds a triangle soup back into 8 corners', () {
      final m = parseStl(_binaryStl(_cubeTris(10)));
      expect(m.format, 'stl');
      expect(m.triangleCount, 12);
      expect(m.vertexCount, 8);
      expect(m.droppedTriangles, 0);
      expect(m.diagonal, closeTo(17.320508, 1e-5));
      expect(m.bounds, isNotNull);
      expect(m.bounds![3], closeTo(10, 1e-9));
    });

    test('a BINARY file whose header starts with "solid" is not read as ASCII',
        () {
      // The reason parseStl decides by SIZE and not by the header. Several
      // slicers put a product name there, and "solid" is a common first word.
      final m = parseStl(
          _binaryStl(_cubeTris(10), header: 'solid exported by a slicer'));
      expect(m.triangleCount, 12);
      expect(m.vertexCount, 8);
    });

    test('ascii', () {
      final m = parseStl(_asciiStl(_cubeTris(10)));
      expect(m.triangleCount, 12);
      expect(m.vertexCount, 8);
    });

    test('degenerate triangles are dropped and counted', () {
      final tris = _cubeTris(10)..add([1, 1, 1, 1, 1, 1, 2, 2, 2]);
      final m = parseStl(_binaryStl(tris));
      expect(m.triangleCount, 12);
      expect(m.droppedTriangles, 1);
    });
  });

  group('OBJ', () {
    test('quads fan out, negative indices resolve against the current length',
        () {
      const src = '# a comment\n'
          'o thing\n'
          'v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\n'
          'vt 0 0\nvn 0 0 1\n'
          'f 1/1/1 2/1/1 3/1/1 4/1/1\n'
          'f -4 -3 -2\n';
      final m = parseObj(Uint8List.fromList(utf8.encode(src)));
      expect(m.format, 'obj');
      expect(m.vertexCount, 4);
      expect(m.triangleCount, 3, reason: 'the quad fans to 2, plus 1');
      expect(m.triangles.sublist(6, 9), [0, 1, 2]);
    });

    test('vertex colours after xyz do not become coordinates', () {
      const src = 'v 0 0 0 1.0 0.5 0.25\nv 1 0 0 1 1 1\nv 0 1 0 0 0 0\n'
          'f 1 2 3\n';
      final m = parseObj(Uint8List.fromList(utf8.encode(src)));
      expect(m.vertexCount, 3);
      expect(m.triangleCount, 1);
      expect(m.vertices[3], closeTo(1.0, 1e-12));
    });
  });

  group('3MF', () {
    test('deflated, and the build transform is applied', () {
      final m = parse3mf(_zip({
        '[Content_Types].xml': '<Types/>',
        '3D/3dmodel.model': _modelXml(),
      }));
      expect(m.format, '3mf');
      expect(m.triangleCount, 12);
      expect(m.vertexCount, 8);
      final b = m.bounds!;
      expect(b[0], closeTo(5, 1e-9), reason: 'scaled x2, translated by 5');
      expect(b[3], closeTo(7, 1e-9));
    });

    test('stored entries (method 0) read too', () {
      expect(
          parse3mf(_zip({'3D/3dmodel.model': _modelXml()}, deflate: false))
              .triangleCount,
          12);
    });

    test('components are instanced, each with its own transform', () {
      final m =
          parse3mf(_zip({'3D/3dmodel.model': _modelXml(components: true)}));
      expect(m.triangleCount, 24, reason: 'the cube appears twice');
      expect(m.vertexCount, 16);
      expect(m.bounds![0], closeTo(0, 1e-9));
      expect(m.bounds![3], closeTo(11, 1e-9), reason: 'one shifted by 10');
    });

    test('a unit that is not millimetres is converted, not ignored', () {
      final m = parse3mf(
          _zip({'3D/3dmodel.model': _modelXml(unit: 'inch', build: false)}));
      expect(m.unitScale, closeTo(25.4, 1e-9));
      expect(m.bounds![3], closeTo(25.4, 1e-9));
    });

    test('a file with no <build> still yields its objects', () {
      expect(
          parse3mf(_zip({'3D/3dmodel.model': _modelXml(build: false)}))
              .triangleCount,
          12);
    });

    test('the model is found even off the conventional path', () {
      expect(
          parse3mf(_zip({'stuff/other.model': _modelXml(build: false)}))
              .triangleCount,
          12);
    });
  });

  group('a broken file is refused with a REASON, not a sentence', () {
    // mesh_io.dart carries codes rather than prose: the app is German (M234)
    // and every user-visible string lives in the ARB, so a reader that held
    // English sentences would be a reader nobody could translate.
    test('each reader names the right failure', () {
      expect(_refusalFor(() => loadMeshBytes(Uint8List(0), path: 'a.stl')),
          MeshFailure.empty);
      expect(
          _refusalFor(
              () => loadMeshBytes(Uint8List.fromList([1]), path: 'a.zip')),
          MeshFailure.unsupportedKind);
      expect(_refusalFor(() => parse3mf(Uint8List.fromList(utf8.encode('no')))),
          MeshFailure.notAnArchive);
      expect(
          _refusalFor(
              () => parseObj(Uint8List.fromList(utf8.encode('v 0 0 0\n')))),
          MeshFailure.noGeometry);
      expect(_refusalFor(() => parse3mf(_zip({'a.txt': 'hello'}))),
          MeshFailure.noModel);
      expect(
          _refusalFor(() => parseStl(
              Uint8List.fromList(utf8.encode('solid x\nendsolid x\n')))),
          MeshFailure.noGeometry);
      expect(_refusalFor(() => loadMeshFile('/nowhere/at/all.stl')),
          MeshFailure.missing);
    });

    test('an unknown unit is refused rather than guessed, and names it', () {
      // Guessing a unit silently rescales somebody's part.
      final f = _zip({'3D/3dmodel.model': _modelXml(unit: 'furlong')});
      expect(_refusalFor(() => parse3mf(f)), MeshFailure.unknownUnit);
      expect(_detailFor(() => parse3mf(f)), 'furlong');
    });

    test('a face naming a vertex that is not there says which one', () {
      final src = Uint8List.fromList(
          utf8.encode('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 99\n'));
      expect(_refusalFor(() => parseObj(src)), MeshFailure.badIndex);
      expect(_detailFor(() => parseObj(src)), '99');
    });

    test('a truncated record is truncated, not empty', () {
      // A vertex with two coordinates: the file is damaged, and saying "no
      // geometry" would send the user looking for the wrong problem.
      final src = Uint8List.fromList(utf8.encode(
          'solid x\n facet normal 0 0 0\n  outer loop\n'
          '   vertex 0 0 0\n   vertex 1 0\n'));
      expect(_refusalFor(() => parseStl(src)), MeshFailure.truncated);
    });

    test('toString is for the log, and carries both parts', () {
      final e = MeshLoadException(MeshFailure.unknownUnit, detail: 'furlong');
      expect(e.toString(), contains('unknownUnit'));
      expect(e.toString(), contains('furlong'));
    });
  });

  group('a mesh too big to handle is refused, not attempted', () {
    // Both limits exist to prevent a CRASH, not a wait: reading is
    // readAsBytesSync and converting is single-threaded on the UI thread.

    test('an oversized file is refused before it is read', () {
      final dir = Directory.systemTemp.createTempSync('m232_big');
      try {
        // Sparse: length without the bytes. If the guard read the file first
        // this test would allocate a third of a gigabyte to find that out.
        final f = File('${dir.path}/huge.stl');
        final raf = f.openSync(mode: FileMode.write);
        raf.setPositionSync(kMaxMeshFileBytes + 1);
        raf.writeByteSync(0);
        raf.closeSync();
        expect(f.lengthSync(), greaterThan(kMaxMeshFileBytes));

        expect(_refusalFor(() => loadMeshFile(f.path)),
            MeshFailure.fileTooLarge);
        // Reported in whole megabytes, so the message can name a number the
        // user recognises from the Files app.
        expect(_detailCountFor(() => loadMeshFile(f.path)),
            kMaxMeshFileBytes ~/ (1024 * 1024));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('a 3MF that names more geometry than it holds is stopped early', () {
      // 60^3 cubes = 2,592,000 triangles from about four kilobytes of XML.
      // The guard has to fire DURING the flatten; if it only checked the
      // finished mesh, the allocation it exists to prevent would already have
      // happened.
      final z = _zip({'3D/3dmodel.model': _bombXml()});
      expect(z.length, lessThan(64 * 1024), reason: 'a small file');
      expect(_refusalFor(() => parse3mf(z)), MeshFailure.tooManyTriangles);
    });

    test('the byte cap leaves room for a mesh at the triangle cap', () {
      // A binary STL is 50 bytes a triangle plus an 84-byte header. If the
      // byte cap were the smaller of the two, a mesh at exactly the triangle
      // limit could not be read at all and the triangle message would never be
      // reachable for that format — the user would be told the file is too
      // big when the real limit is the conversion.
      expect(kMaxMeshFileBytes,
          greaterThanOrEqualTo(kMaxMeshTriangles * 50 + 84));
    });
  });

  group('Open accepts them', () {
    test('isMeshPath, case-insensitively', () {
      expect(isMeshPath('/a/b.STL'), isTrue);
      expect(isMeshPath('/a/b.obj'), isTrue);
      expect(isMeshPath('/a/b.3mf'), isTrue);
      expect(isMeshPath('/a/b.step'), isFalse);
    });

    test('openActionFor imports a mesh, like a STEP', () {
      // A mesh is a SOURCE, never a document opened in place: it becomes a new
      // part in the app folder and the original is left alone.
      for (final ext in kMeshExtensions) {
        expect(openActionFor('/elsewhere/thing.$ext', '/app'),
            OpenAction.import,
            reason: ext);
      }
      expect(openActionFor('/elsewhere/thing.gcode', '/app'),
          OpenAction.unsupported);
    });

    test('round trip through a real file on disk', () async {
      final dir = await Directory.systemTemp.createTemp('m232');
      try {
        final f = File('${dir.path}/cube.stl');
        f.writeAsBytesSync(_binaryStl(_cubeTris(4)));
        final m = loadMeshFile(f.path);
        expect(m.triangleCount, 12);
        expect(m.vertexCount, 8);
        expect(m.diagonal, closeTo(6.928203, 1e-5));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('the whole way through Open', () {
    // The host has no OCCT linked, so the conversion itself cannot run here —
    // that half is pinned in backend/occt/tests/mesh_recon_test.cpp against
    // real geometry. What CAN be pinned here is everything around it, and the
    // refusal path is worth more than it looks: it is the one that runs when a
    // user opens a mesh on a build that cannot convert it, and the one where a
    // half-made document would be left behind.
    late Directory docs;

    setUp(() => docs = Directory.systemTemp.createTempSync('m232_open'));
    tearDown(() {
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    AppState app() => AppState()
      ..docsDirForTest = docs
      ..volatileDirsForTest = const [];

    test('a mesh outside the app folder takes the import route', () {
      expect(openActionFor('${docs.path}/thing.stl', docs.path),
          OpenAction.import,
          reason: 'a mesh is a SOURCE, never one of our documents, so even one '
              'sitting in the app folder is imported rather than opened');
    });

    test('opening one without a kernel says so, in the UI language', () async {
      final src = Directory.systemTemp.createTempSync('m232_src');
      try {
        final f = File('${src.path}/cube.stl')
          ..writeAsBytesSync(_binaryStl(_cubeTris(10)));
        final a = app();
        final name = await a.openPath(f.path);

        expect(name, isNull, reason: 'nothing was imported');
        // The localised sentence, not a hardcoded English one. Comparing
        // against L.current rather than a literal keeps this test honest in
        // both languages.
        expect(a.message, L.current.msgNoKernelMesh);
      } finally {
        src.deleteSync(recursive: true);
      }
    });

    test('a failed import leaves no half-made document behind', () async {
      final src = Directory.systemTemp.createTempSync('m232_src');
      try {
        File('${src.path}/bracket.stl')
            .writeAsBytesSync(_binaryStl(_cubeTris(10)));
        final a = app();
        await a.openPath('${src.path}/bracket.stl');

        // importAsNewDocument creates the part BEFORE it knows the conversion
        // will work. A blank "bracket" in the gallery would be worse than the
        // refusal, because the user would have to go and find out it is empty.
        final left = [
          for (final e in docs.listSync())
            if (e is File) e.uri.pathSegments.last
        ];
        expect(left.where((n) => n.startsWith('bracket')), isEmpty,
            reason: 'left behind: $left');
        expect(a.docNameExists('bracket'), isFalse);
      } finally {
        src.deleteSync(recursive: true);
      }
    });

    test('the original file is never touched', () async {
      final src = Directory.systemTemp.createTempSync('m232_src');
      try {
        final f = File('${src.path}/cube.stl')
          ..writeAsBytesSync(_binaryStl(_cubeTris(10)));
        final before = f.readAsBytesSync();
        await app().openPath(f.path);
        expect(f.existsSync(), isTrue);
        expect(f.readAsBytesSync(), before);
      } finally {
        src.deleteSync(recursive: true);
      }
    });
  });

  group('the conversion report', () {
    test('an empty report reads as all-zero rather than crashing', () {
      const r = MeshToBrepReport.empty();
      expect(r.planes, 0);
      expect(r.cylinders, 0);
      expect(r.closed, isFalse);
      expect(r.analyticFaces, 0);
      expect(r.fitRms, 0);
      expect(r.describe(), contains('0 patch'));
    });
  });
}
