// Tests for the M21 dimension pick matrix: buildDimensionAt must map every
// Inventor pick combination onto the right dimension kind and point refs.

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';

Geo line(double x1, double y1, double x2, double y2) =>
    Geo(Geo.line, [x1, y1, x2, y2]);
Geo circle(double cx, double cy, double r) => Geo(Geo.circle, [cx, cy, r]);
Geo arc(double cx, double cy, double r) =>
    Geo(Geo.arc, [cx, cy, r, 0, 1.5, 0]);

void main() {
  late AppState app;
  late SketchModel s;

  setUp(() {
    app = AppState();
    s = SketchModel('t');
    app.conPts.clear();
    app.conEnts.clear();
  });

  Constraint? build(Offset at) => app.buildDimensionAt(s, at);

  test('line alone -> length between its endpoints', () {
    s.geometry = [line(0, 0, 100, 0)];
    app.conEnts.add(0);
    final d = build(const Offset(50, 20))!;
    expect(d.dimKind, anyOf('dist', 'distx', 'disty'));
    expect(d.pts, hasLength(2));
    expect(d.value, closeTo(100, 1e-9));
  });

  test('circle alone -> diameter; arc alone -> radius', () {
    s.geometry = [circle(0, 0, 10), arc(50, 0, 7)];
    app.conEnts.add(0);
    expect(build(Offset.zero)!.dimKind, 'dia');
    app.conEnts
      ..clear()
      ..add(1);
    expect(build(Offset.zero)!.dimKind, 'rad');
  });

  test('line + point -> perpendicular point-to-line distance', () {
    s.geometry = [line(0, 0, 100, 0), circle(30, 7, 5)];
    app.conEnts.add(0);
    app.conPts.add(PRef(1, 0)); // circle center
    final d = build(const Offset(30, 10))!;
    expect(d.dimKind, 'pline');
    expect(d.pts[0], PRef(1, 0)); //     measured point first
    expect(d.value, closeTo(7, 1e-9));
  });

  test('circle + point -> distance point <-> center', () {
    s.geometry = [circle(0, 0, 5), line(30, 40, 60, 40)];
    app.conEnts.add(0);
    app.conPts.add(PRef(1, 0));
    final d = build(const Offset(15, 20))!;
    expect(d.dimKind, anyOf('dist', 'distx', 'disty'));
    expect(d.pts, containsAll([PRef(0, 0), PRef(1, 0)]));
  });

  test('circle + circle -> center-to-center distance', () {
    s.geometry = [circle(0, 0, 5), circle(30, 40, 5)];
    app.conEnts.addAll([0, 1]);
    final d = build(const Offset(15, 20))!;
    expect(d.dimKind, anyOf('dist', 'distx', 'disty'));
    expect(d.pts, [PRef(0, 0), PRef(1, 0)]);
  });

  test('circle + line -> perpendicular distance center <-> line', () {
    s.geometry = [circle(30, 12, 5), line(0, 0, 100, 0)];
    app.conEnts.addAll([0, 1]);
    final d = build(const Offset(30, 6))!;
    expect(d.dimKind, 'pline');
    expect(d.pts[0], PRef(0, 0)); // the center is the measured point
    expect(d.value, closeTo(12, 1e-9));
  });

  test('two intersecting lines -> angle', () {
    s.geometry = [line(0, 0, 100, 0), line(0, 0, 0, 100)];
    app.conEnts.addAll([0, 1]);
    final d = build(const Offset(20, 20))!;
    expect(d.dimKind, 'ang');
    expect(d.value, closeTo(90, 1e-9));
  });

  test('two parallel lines -> linear distance, not angle', () {
    s.geometry = [line(0, 0, 100, 0), line(0, 25, 100, 25)];
    app.conEnts.addAll([0, 1]);
    final d = build(const Offset(50, 12))!;
    expect(d.dimKind, 'pline');
    expect(d.value, closeTo(25, 1e-9));
  });

  test('two points -> distance', () {
    s.geometry = [line(0, 0, 30, 40)];
    app.conPts.addAll([PRef(0, 0), PRef(0, 1)]);
    final d = build(const Offset(100, 0))!; // far right -> vertical distance
    expect(d.dimKind, anyOf('dist', 'distx', 'disty'));
    expect(measureDim(s.geometry, d), d.value);
  });

  test('three points -> angle at the middle (vertex) pick', () {
    s.geometry = [line(10, 0, 0, 0), line(0, 0, 0, 10)];
    app.conPts.addAll([PRef(0, 0), PRef(0, 1), PRef(1, 1)]);
    final d = build(const Offset(5, 5))!;
    expect(d.dimKind, 'ang3');
    expect(d.value, closeTo(90, 1e-9));
  });
}
