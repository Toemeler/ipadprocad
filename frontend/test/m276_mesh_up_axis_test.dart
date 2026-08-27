// M276 — which way is up, on the way in.
//
// "auch habe ich das gefühl das bei einem stl import das modell falsch gedreht
// ist und immer seitlich importiert wird. ist das so?"
//
// It was. Nothing on the import path touched the axes, so each file's own
// convention became the app's — and the conventions differ:
//
//   * the APP is Y-up. PartCamera.dir puts cos(pol) in Y, the renderer crosses
//     with (0, 1, 0), and the ViewCube's TOP is (0, 1, 0). The sketch planes
//     look like evidence for Z and are not: XY is the FRONT plane, its normal
//     pointing at the viewer, which is the SolidWorks convention.
//   * STL and 3MF are Z-up. The printer's bed is the XY plane, so a model
//     exported to be printed stands up in Z. Neither format records this — the
//     convention IS the information, which is why the rule is per format.
//   * OBJ is Y-up. It came out of graphics rather than manufacturing.
//
// So two of the three need a quarter turn and the third must not get one, and
// that is the whole milestone. These tests pin the turn, its direction, and
// the fact that it costs a soup nothing else.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/mesh_io.dart';

/// One triangle, given as nine raw coordinates.
Uint8List _binaryStl(List<List<double>> tris) {
  final b = BytesBuilder();
  b.add(Uint8List(80));
  final n = ByteData(4)..setUint32(0, tris.length, Endian.little);
  b.add(n.buffer.asUint8List());
  for (final t in tris) {
    final f = ByteData(50);
    for (var i = 0; i < 9; i++) {
      f.setFloat32(12 + i * 4, t[i], Endian.little);
    }
    b.add(f.buffer.asUint8List());
  }
  return b.toBytes();
}

Uint8List _obj(List<List<double>> tris) {
  final sb = StringBuffer();
  var i = 1;
  for (final t in tris) {
    for (var k = 0; k < 3; k++) {
      sb.writeln('v ${t[k * 3]} ${t[k * 3 + 1]} ${t[k * 3 + 2]}');
    }
    sb.writeln('f $i ${i + 1} ${i + 2}');
    i += 3;
  }
  return Uint8List.fromList(utf8.encode(sb.toString()));
}

/// A triangle standing UP in the file's own frame: two points on the ground
/// and an apex 10 above it, along the file's up axis.
List<List<double>> _zUpSpike() => [
      [0, 0, 0, 10, 0, 0, 0, 0, 10],
    ];

List<List<double>> _yUpSpike() => [
      [0, 0, 0, 10, 0, 0, 0, 10, 0],
    ];

void main() {
  group('the rule', () {
    test('STL and 3MF are Z-up, OBJ is Y-up', () {
      expect(meshUpAxisOf('stl'), MeshUpAxis.z);
      expect(meshUpAxisOf('3mf'), MeshUpAxis.z);
      expect(meshUpAxisOf('obj'), MeshUpAxis.y);
    });

    test('the turn is a quarter about +X: (x, y, z) -> (x, z, -y)', () {
      final v = Float64List.fromList([1, 2, 3, 0, 0, 1, 0, -1, 0]);
      rotateZUpToYUp(v);
      expect(v.sublist(0, 3), [1, 3, -2]);
      // The file's UP lands on the app's up...
      expect(v.sublist(3, 6), [0, 1, 0]);
      // ...and the file's FRONT (-Y, the side facing the printer's operator)
      // lands on +Z, which is what the ViewCube calls FRONT.
      expect(v.sublist(6, 9), [0, 0, 1]);
    });

    test('it is its own quarter turn four times over', () {
      final v = Float64List.fromList([3, -7, 11]);
      for (var i = 0; i < 4; i++) {
        rotateZUpToYUp(v);
      }
      expect(v, [3, -7, 11]);
    });

    test('a ragged tail is left alone rather than read past', () {
      final v = Float64List.fromList([0, 0, 1, 5]);
      rotateZUpToYUp(v);
      expect(v.sublist(0, 3), [0, 1, 0]);
      expect(v[3], 5);
    });
  });

  group('what the importer does with it', () {
    test('an STL spike ends up standing in Y, not lying in Z', () {
      // The bug, as a user would see it: a model that stood up in the slicer
      // arrived lying down.
      final m = loadMeshBytes(_binaryStl(_zUpSpike()), path: 'a.stl');
      final b = m.bounds!;
      expect(b[4], closeTo(10, 1e-6), reason: 'it reaches 10 UP (Y)');
      expect(b[5] - b[2], closeTo(0, 1e-6), reason: 'and is flat in Z');
      expect(m.uprightedFromZUp, isTrue);
    });

    test('an OBJ spike is left exactly as the file wrote it', () {
      final m = loadMeshBytes(_obj(_yUpSpike()), path: 'a.obj');
      final b = m.bounds!;
      expect(b[4], closeTo(10, 1e-6));
      expect(b[5] - b[2], closeTo(0, 1e-6));
      expect(m.uprightedFromZUp, isFalse,
          reason: 'OBJ is already Y-up; turning it would BREAK it');
    });

    test('the turn changes nothing else about the soup', () {
      final m = loadMeshBytes(_binaryStl(_zUpSpike()), path: 'a.stl');
      expect(m.format, 'stl');
      expect(m.triangleCount, 1);
      expect(m.vertexCount, 3);
      expect(m.droppedTriangles, 0);
      // A rigid turn cannot change a size.
      expect(m.diagonal, closeTo(loadMeshBytes(_obj(_zUpSpike()), path: 'a.obj')
          .diagonal, 1e-9));
    });

    test('the parsers themselves stay faithful to their formats', () {
      // parseStl returns what the FILE said; the convention is applied once,
      // on the app's own entry point. A test that asserted otherwise would be
      // pinning the conversion in the wrong place.
      final raw = parseStl(_binaryStl(_zUpSpike()));
      expect(raw.bounds![5], closeTo(10, 1e-6), reason: 'still up in Z');
      expect(raw.uprightedFromZUp, isFalse);
    });
  });
}
