// M473 — a DXF polyline survives Import DXF.
//
// Import recentres the incoming geometry on the origin, and the shift walked
// every entity's data two numbers at a time. A polyline's data is not all
// coordinates: it opens with [closed, vertexCount]. So the closed flag and the
// vertex count were "moved" by the recentring offset like a point — a closed
// LWPOLYLINE outline (the commonest thing in a DXF) came in as an open
// polyline with a nonsense vertex count, and the header pair was also counted
// into the bounding box, pulling the recentring off.
//
// Native backend only: DXF save/load lives in QCAD (set PROTOTYPE_NATIVE_DIR).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';

void main() {
  final probe = SketchModel('_probe');
  final real = probe.engine.isRealBackend;
  probe.dispose();
  final skip = real ? false : 'DXF needs the native backend';

  test('a closed polyline comes in closed, whole and centred', () {
    final dir = Directory.systemTemp.createTempSync('m473dxf');
    final author = SketchModel('_author');
    // a 100 x 40 outline far from the origin, plus a line beside it
    author.engine.addPolyline(
        [1000, 2000, 1100, 2000, 1100, 2040, 1000, 2040], closed: true);
    author.engine.addLine(1000, 1980, 1100, 1980);
    final path = '${dir.path}/outline.dxf';
    expect(author.engine.saveDxf(path), isTrue);
    author.dispose();

    final app = AppState();
    final s = SketchModel('t');
    app.sketches['t'] = s;
    app.curTab = 't';
    app.editingLayer = kDefaultLayer;
    expect(app.importDxf(path), isTrue);

    final poly = s.geometry.singleWhere((g) => g.type == Geo.polyline);
    expect(poly.data[0], 1, reason: 'still closed');
    expect(poly.data[1], 4, reason: 'still four vertices');
    expect(poly.data, hasLength(2 + 8));
    // the whole drawing (y 1980..2040, x 1000..1100) is centred on the origin
    final xs = [for (var k = 2; k < 10; k += 2) poly.data[k]];
    final ys = [for (var k = 3; k < 10; k += 2) poly.data[k]];
    expect(xs.reduce((a, b) => a < b ? a : b), closeTo(-50, 1e-6));
    expect(xs.reduce((a, b) => a > b ? a : b), closeTo(50, 1e-6));
    expect(ys.reduce((a, b) => a < b ? a : b), closeTo(-10, 1e-6));
    expect(ys.reduce((a, b) => a > b ? a : b), closeTo(30, 1e-6));
    final ln = s.geometry.singleWhere((g) => g.type == Geo.line);
    expect(ln.data, [
      closeTo(-50, 1e-6), closeTo(-30, 1e-6),
      closeTo(50, 1e-6), closeTo(-30, 1e-6),
    ]);
  }, skip: skip);
}
