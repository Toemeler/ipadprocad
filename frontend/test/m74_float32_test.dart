// M74 — vertex buffers cross the platform channel as Float32.
//
// The kernel produces Float64 but the GPU only consumes Float32, so Swift was
// converting every vertex on every push (Payload.floats). Sending Float32
// halves the payload (~3.4 MB -> ~1.7 MB for a 54k-vertex gear) AND deletes
// that loop.
//
// The trap this pins down: Swift decodes solid buffers AND sketch polylines
// through the SAME Payload.floats. If one side still sent Float64, Swift
// would reinterpret those bytes as Float32 and render garbage - so every
// buffer that reaches Payload.floats must be Float32 together.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';

OcctMeshData mesh() => OcctMeshData(
      Float64List.fromList(const [1.5, 2.5, 3.5, 4, 5, 6]),
      Float64List.fromList(const [0, 0, 1, 0, 1, 0]),
      Int32List.fromList(const [0, 1, 2]),
      Int32List.fromList(const [0, 2]),
      Float64List.fromList(const [7, 8, 9, 10, 11, 12]),
    );

void main() {
  test('the Float32 views carry the same values', () {
    final m = mesh();
    expect(m.positions32, isA<Float32List>());
    expect(m.positions32.length, m.positions.length);
    for (var i = 0; i < m.positions.length; i++) {
      expect(m.positions32[i], closeTo(m.positions[i], 1e-6));
    }
    for (var i = 0; i < m.normals.length; i++) {
      expect(m.normals32[i], closeTo(m.normals[i], 1e-6));
    }
    for (var i = 0; i < m.edgePoints.length; i++) {
      expect(m.edgePoints32[i], closeTo(m.edgePoints[i], 1e-6));
    }
  });

  test('they are built once and reused', () {
    final m = mesh();
    expect(identical(m.positions32, m.positions32), isTrue,
        reason: 'converting per push would defeat the point');
    expect(identical(m.normals32, m.normals32), isTrue);
    expect(identical(m.edgePoints32, m.edgePoints32), isTrue);
  });

  test('and are half the bytes', () {
    final m = mesh();
    expect(m.positions32.lengthInBytes, m.positions.lengthInBytes ~/ 2);
  });

  test('empty buffers survive', () {
    final m = OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
        Int32List(0), Float64List(0));
    expect(m.positions32, isEmpty);
    expect(m.edgePoints32, isEmpty);
  });
}
