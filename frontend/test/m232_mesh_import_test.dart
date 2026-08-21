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
import 'package:prototype/doc_ref.dart';
import 'package:prototype/ffi/occt_engine.dart';
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

String? _refusalFor(void Function() f) {
  try {
    f();
    return null;
  } on MeshLoadException catch (e) {
    return e.message;
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
      final m = parse3mf(
          _zip({'[Content_Types].xml': '<Types/>', '3D/3dmodel.model': _modelXml()}));
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

  group('a broken file says what is wrong with THAT file', () {
    test('every refusal is a sentence, not a stack trace', () {
      expect(_refusalFor(() => loadMeshBytes(Uint8List(0), path: 'a.stl')),
          contains('empty'));
      expect(
          _refusalFor(
              () => loadMeshBytes(Uint8List.fromList([1]), path: 'a.zip')),
          isNotNull);
      expect(_refusalFor(() => parse3mf(Uint8List.fromList(utf8.encode('no')))),
          contains('archive'));
      expect(
          _refusalFor(
              () => parseObj(Uint8List.fromList(utf8.encode('v 0 0 0\n')))),
          contains('no faces'));
      expect(_refusalFor(() => parse3mf(_zip({'a.txt': 'hello'}))),
          contains('no model'));
      expect(
          _refusalFor(() =>
              parseStl(Uint8List.fromList(utf8.encode('solid x\nendsolid x\n')))),
          contains('no usable triangles'));
    });

    test('a missing file is refused rather than thrown at', () {
      expect(_refusalFor(() => loadMeshFile('/nowhere/at/all.stl')),
          contains('no longer exists'));
    });

    test('an unknown unit is refused rather than guessed', () {
      // Guessing a unit silently rescales somebody's part.
      expect(
          _refusalFor(() =>
              parse3mf(_zip({'3D/3dmodel.model': _modelXml(unit: 'furlong')}))),
          contains('unknown unit'));
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
