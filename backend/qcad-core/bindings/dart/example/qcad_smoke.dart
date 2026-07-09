// iPadProCAD — Dart FFI usage example (mirrors the native C smoke test).
//
// This is illustrative. To run on desktop you must build a *shared* library
// from the wrapper (the CI ships a static lib/XCFramework for iOS), e.g.:
//
//   # add a SHARED variant of qcadcapi, or wrap the archives into a .so, then:
//   dart run example/qcad_smoke.dart /path/to/libipadprocad.so
//
// On iOS this is not needed — use QcadBindings.process().

import 'dart:io';
import 'dart:math' as math;

import '../qcad_ffi.dart';

void main(List<String> args) {
  final bindings = args.isNotEmpty
      ? QcadBindings.open(args.first)
      : QcadBindings.process();

  stdout.writeln('version: ${bindings.version()}');

  final doc = QcadDocument(bindings);
  doc.addLine(0, 0, 100, 50);
  doc.addCircle(50, 50, 25);
  doc.addArc(0, 0, 40, 0, math.pi / 2);
  doc.addPolyline([0, 0, 10, 0, 10, 10, 0, 10], closed: true);

  stdout.writeln('entity count: ${doc.entityCount}');
  stdout.writeln('bbox: ${doc.boundingBox()}');

  final path = '${Directory.systemTemp.path}/ipadprocad_dart_smoke.dxf';
  final saved = doc.saveDxf(path);
  stdout.writeln('saved DXF ($path): $saved');

  final reloaded = QcadDocument(bindings);
  reloaded.loadDxf(path);
  stdout.writeln('reloaded entity count: ${reloaded.entityCount}');

  final ok = doc.entityCount == 4 && reloaded.entityCount == 4;
  stdout.writeln(ok ? '\nDART SMOKE: PASS' : '\nDART SMOKE: FAIL');

  reloaded.dispose();
  doc.dispose();
  exit(ok ? 0 : 1);
}
