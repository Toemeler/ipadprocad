// M403 — #35: "when i set a new view as front, the placing of the bottom plane
// in rendered mode should change too".
//
// The ViewCube's orientation is the document's answer to "which way is up",
// and every view off the cube has honoured it since M399. The rendered floor
// did not: a horizontal quad at the model's lowest world Y. Redefine front and
// the part stands on a plane that cuts through it at an angle — the one thing
// left in the picture still using the old up.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_view.dart';
import 'package:prototype/part_model.dart' show Vec3;
import 'package:prototype/quat.dart';

/// One triangle, 10 units tall, sitting on the plane {p · up == low}.
List<CyclesMesh> wedge(Vec3 up, double low) {
  final a = cyclesPerpTo(up), b = a.cross(up);
  final base = up * low;
  final p0 = base - a * 5 - b * 5;
  final p1 = base + a * 5 - b * 5;
  final p2 = base + a * 5 + b * 5 + up * 10;
  return [
    (
      Float32List.fromList(
          [p0.x, p0.y, p0.z, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z]),
      null,
      Int32List.fromList([0, 1, 2]),
      null,
    )
  ];
}

/// The floor's plane, as (unit normal, offset) taken from the mesh itself.
(Vec3, double) planeOf(CyclesMesh f) {
  final v = f.$1;
  Vec3 at(int i) => Vec3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2]);
  final n = (at(1) - at(0)).cross(at(2) - at(0)).normalized();
  return (n, at(0).dot(n));
}

void main() {
  test('with the default up, nothing about the floor changes', () {
    // The identity case is every document that has never redefined front, and
    // it has to come out bit for bit what it always did.
    final f = cyclesFloorMesh(wedge(const Vec3(0, 1, 0), 20),
        argb: 0xFF808080, lookingDown: true)!;
    final ys = [for (var i = 1; i < f.$1.length; i += 3) f.$1[i]];
    expect(ys.every((y) => y == ys.first), isTrue, reason: 'level');
    expect(ys.first, lessThan(20.0));
    expect(ys.first, greaterThan(19.9));
    final (n, _) = planeOf(f);
    expect(n.y, closeTo(1, 1e-6));
  });

  test('a redefined front stands the floor up with the model', () {
    // "Set Current View as Front" from the top view turns the model's up onto
    // world +Z. The floor has to follow, or the part hangs in the air beside
    // a plane it never touches.
    const up = Vec3(0, 0, 1);
    final f = cyclesFloorMesh(wedge(up, -3),
        argb: 0xFF808080, lookingDown: true, up: up)!;
    final (n, d) = planeOf(f);
    expect(n.z, closeTo(1, 1e-6), reason: 'the normal points at the model');
    expect(n.x.abs(), lessThan(1e-6));
    expect(n.y.abs(), lessThan(1e-6));
    expect(d, lessThan(-3.0), reason: 'just under the lowest point');
    expect(d, greaterThan(-3.1));
  });

  test('and on a diagonal up, which is what an arbitrary front gives', () {
    final up = const Vec3(1, 1, 0).normalized();
    final f = cyclesFloorMesh(wedge(up, 7),
        argb: 0xFF808080, lookingDown: true, up: up)!;
    final (n, d) = planeOf(f);
    expect(n.dot(up), closeTo(1, 1e-5),
        reason: 'the floor is perpendicular to the model us up');
    expect(d, lessThan(7.0));
    expect(d, greaterThan(6.9));
    // Every corner is in that plane, not merely the three the normal came from.
    final v = f.$1;
    for (var i = 0; i + 2 < v.length; i += 3) {
      expect(Vec3(v[i], v[i + 1], v[i + 2]).dot(n), closeTo(d, 1e-4));
    }
  });

  test('the up axis is the cube orientation, applied to +Y', () {
    // Identity means world up, which is every document that has never been
    // told otherwise.
    expect(Quat.identity.rotate(const Vec3(0, 1, 0)).y, closeTo(1, 1e-9));
    // A quarter turn about X takes +Y onto -Z: what "the top is now the
    // front" does to the model's up.
    final q = Quat.axisAngle(const Vec3(1, 0, 0), -1.5707963267948966);
    final up = q.rotate(const Vec3(0, 1, 0)).normalized();
    expect(up.z, closeTo(-1, 1e-6));
    // And the floor built from it is perpendicular to it.
    final f = cyclesFloorMesh(wedge(up, 0),
        argb: 0xFF808080, lookingDown: true, up: up)!;
    final (n, _) = planeOf(f);
    expect(n.dot(up), closeTo(1, 1e-5));
  });
}
