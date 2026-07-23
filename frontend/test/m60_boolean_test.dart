// M60 — Cut/Intersect booleans, the live boolean preview, and the closed-
// spline extrude fix. The OCCT kernel is NOT linked on host, so a fake
// [PartKernel] with DISTINCT stub volumes per op exercises the fold and
// preview machinery; the spline fix is pure Dart (profile loop cleaning) and
// is verified directly.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/occt_engine.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/part_model.dart';

/// Distinct stub volumes so a fold/preview can prove WHICH op ran:
///   join → a+b, cut → a−b, intersect → min(a,b). extrude returns a solid
/// whose volume is the extrude height (so callers pick heights to tell solids
/// apart). Records the last groups handed down for the spline test.
class FakeKernel implements PartKernel {
  bool fail = false;
  int fusions = 0, cuts = 0, intersects = 0;
  List<List<List<Offset>>>? lastGroups;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  KernelSolid _solid(OcctMeshData? mesh, double vol) => KernelSolid(
      mesh ??
          OcctMeshData(
              Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
              Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
              Int32List.fromList(const [0, 1, 2]),
              Int32List.fromList(const [0, 3]),
              Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
      vol,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    lastGroups = groups;
    return fail ? null : _solid(null, height);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    fusions++;
    return _solid(a.mesh, a.volume + b.volume);
  }

  @override
  KernelSolid? cutSolids(KernelSolid base, KernelSolid tool) {
    if (fail) return null;
    cuts++;
    return _solid(base.mesh, base.volume - tool.volume);
  }

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    intersects++;
    return _solid(a.mesh, math.min(a.volume, b.volume));
  }

  @override
  bool exportStep(List<KernelSolid> solids, String path) => false;
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipadprocad_m60_');
  app.partKernel = FakeKernel();
  return app;
}

FakeKernel kernelOf(AppState app) => app.partKernel as FakeKernel;

void addRectLines(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// A closed interpolation-spline polyline (the case that used to fail).
Geo closedFitSpline(List<Offset> ctrl, {String layer = 'Layer 1'}) => Geo(
      Geo.polyline,
      [1.0, ctrl.length.toDouble(), for (final p in ctrl) ...[p.dx, p.dy]],
      spline: Geo.splineFit,
      layer: layer,
    );

double _minEdge(List<Offset> loop) {
  var m = double.infinity;
  for (var i = 0; i < loop.length; i++) {
    final e = (loop[(i + 1) % loop.length] - loop[i]).distance;
    if (e < m) m = e;
  }
  return m;
}

/// Base part: 20x10 rectangle on XY extruded [height]. Leaves Solid1 committed
/// and the extrude session closed.
Future<AppState> buildBase({String height = '8 mm'}) async {
  final app = makeApp();
  await app.createNamedPart('Part1');
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: height);
  await app.applyExtrude();
  return app;
}

/// Adds a second sketch (a small rectangle on XY) and opens the extrude panel
/// with that profile pre-picked, ready for a boolean.
void armSecondProfile(AppState app) {
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 4, 2, 12, 8, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
}

void main() {
  group('closed-spline extrude fix (loop cleaning)', () {
    test('dedupeClosedLoop drops a zero-length closing edge', () {
      final loop = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 10),
        const Offset(0, 10),
        const Offset(0, 0), // duplicate of the first -> degenerate closer
      ];
      final clean = dedupeClosedLoop(loop);
      expect(clean.length, 4);
      expect(_minEdge(clean), greaterThan(1e-9));
    });

    test('dedupeClosedLoop is a no-op on a clean polygon', () {
      final sq = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 10),
        const Offset(0, 10),
      ];
      expect(dedupeClosedLoop(sq).length, 4);
    });

    test('a closed fit spline yields ONE clean, extrudable profile loop', () {
      // A closed interpolation spline: its last sample lands exactly on the
      // start (Catmull-Rom at t=1 == p[0]), which used to leave a zero-length
      // closing edge that the OCCT wire builder rejected.
      final ctrl = const [
        Offset(0, 0),
        Offset(30, 5),
        Offset(45, 30),
        Offset(20, 45),
        Offset(-10, 35),
        Offset(-20, 15),
      ];
      final s = SketchModel('t')..layers.add('Layer 1');
      s.geometry.add(closedFitSpline(ctrl));
      final loops = profileLoops(s);
      expect(loops.length, 1, reason: 'the closed spline is a profile loop');
      final loop = loops.single;
      expect(loop.area, greaterThan(0));
      expect(_minEdge(loop.pts), greaterThan(1e-9),
          reason: 'no degenerate closing edge after cleaning');

      // the arc-fit control loop the shim actually receives must be clean too
      final segs = arcFitLoop(loop.pts);
      expect(_minEdge([for (final sg in segs) sg.p]), greaterThan(1e-9));

      // and a kernel accepts it (was returning null / "wire failed" before)
      final k = FakeKernel();
      final solid = k.extrude([
        [loop.pts]
      ], 5, 0, planeFrame('xy').mat34(0));
      expect(solid, isNotNull);
      expect(_minEdge(k.lastGroups!.first.first), greaterThan(1e-9));
    });
  });

  group('combineSolids picks the right op', () {
    final mat = planeFrame('xy').mat34(0);
    final square = [
      const Offset(0, 0),
      const Offset(10, 0),
      const Offset(10, 10),
      const Offset(0, 10)
    ];
    test('join / cut / intersect / new', () {
      final k = FakeKernel();
      final a = k.extrude([
        [square]
      ], 8, 0, mat)!; // volume 8
      final b = k.extrude([
        [square]
      ], 3, 0, mat)!; // volume 3
      expect(combineSolids(k, 'join', a, b)!.volume, 11);
      expect(combineSolids(k, 'cut', a, b)!.volume, 5);
      expect(combineSolids(k, 'intersect', a, b)!.volume, 3);
      expect(combineSolids(k, 'new', a, b), isNull);
      expect(k.fusions, 1);
      expect(k.cuts, 1);
      expect(k.intersects, 1);
    });
  });

  group('boolean fold in recomputeAllFeatures', () {
    Future<AppState> secondFeature(String output) async {
      final app = await buildBase(height: '8 mm');
      armSecondProfile(app);
      app.setExtrude(exprA: '3 mm', output: output);
      await app.applyExtrude();
      return app;
    }

    test('Cut subtracts and consumes the base into one body', () async {
      final app = await secondFeature('cut');
      final p = app.currentPart!;
      expect(p.features.length, 2);
      expect(p.features[0].bodyName, p.features[1].bodyName,
          reason: 'cut adopts the existing body');
      expect(p.features[0].consumedByJoin, isTrue);
      expect(p.features[1].consumedByJoin, isFalse);
      expect(p.features[1].solid!.volume, closeTo(5, 1e-9)); // 8 - 3
      expect(kernelOf(app).cuts, greaterThanOrEqualTo(1));
    });

    test('Intersect keeps the overlap volume', () async {
      final app = await secondFeature('intersect');
      final p = app.currentPart!;
      expect(p.features[1].solid!.volume, closeTo(3, 1e-9)); // min(8,3)
      expect(kernelOf(app).intersects, greaterThanOrEqualTo(1));
    });

    test('Join unions the volumes', () async {
      final app = await secondFeature('join');
      final p = app.currentPart!;
      expect(p.features[1].solid!.volume, closeTo(11, 1e-9)); // 8 + 3
      expect(kernelOf(app).fusions, greaterThanOrEqualTo(1));
    });

    test('New Solid stays a separate body (no boolean)', () async {
      final app = await secondFeature('new');
      final p = app.currentPart!;
      expect(p.features[0].bodyName == p.features[1].bodyName, isFalse);
      expect(p.features[0].consumedByJoin, isFalse);
      expect(p.features[1].consumedByJoin, isFalse);
      expect(p.features[1].solid!.volume, closeTo(3, 1e-9)); // its own prism
    });
  });

  group('live boolean preview', () {
    test('base feature has no boolean target (Cut/Intersect dimmed)', () async {
      final app = makeApp();
      await app.createNamedPart('Part1');
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      expect(app.extrudeHasBooleanTarget, isFalse);
    });

    test('Cut preview shows the CUT result and hides the target body',
        () async {
      final app = await buildBase(height: '8 mm');
      armSecondProfile(app);
      expect(app.extrudeHasBooleanTarget, isTrue);
      app.setExtrude(exprA: '3 mm', output: 'cut');
      final s = app.extrudeSession!;
      expect(s.preview, isNotNull);
      expect(s.preview!.volume, closeTo(5, 1e-9)); // 8 - 3, the real cut
      expect(s.previewReplacesBody, 'Solid1');
    });

    test('Join preview shows the union', () async {
      final app = await buildBase(height: '8 mm');
      armSecondProfile(app);
      app.setExtrude(exprA: '3 mm', output: 'join');
      final s = app.extrudeSession!;
      expect(s.preview!.volume, closeTo(11, 1e-9));
      expect(s.previewReplacesBody, 'Solid1');
    });

    test('New Solid preview is a standalone prism (no body hidden)', () async {
      final app = await buildBase(height: '8 mm');
      armSecondProfile(app);
      app.setExtrude(exprA: '3 mm', output: 'new');
      final s = app.extrudeSession!;
      expect(s.preview!.volume, closeTo(3, 1e-9)); // just the new prism
      expect(s.previewReplacesBody, isNull);
    });

    test('switching Cut→New updates the preview and clears the hidden body',
        () async {
      final app = await buildBase(height: '8 mm');
      armSecondProfile(app);
      app.setExtrude(exprA: '3 mm', output: 'cut');
      expect(app.extrudeSession!.previewReplacesBody, 'Solid1');
      app.setExtrude(output: 'new');
      expect(app.extrudeSession!.previewReplacesBody, isNull);
      expect(app.extrudeSession!.preview!.volume, closeTo(3, 1e-9));
    });
  });

  group('dialog contract', () {
    test('setExtrude accepts all four boolean outputs', () async {
      final app = await buildBase();
      armSecondProfile(app);
      for (final o in const ['join', 'cut', 'intersect', 'new']) {
        app.setExtrude(output: o);
        expect(app.extrudeSession!.output, o);
      }
    });
  });
}
