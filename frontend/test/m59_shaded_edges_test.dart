// M59 — Inventor "Shaded with Edges" pipeline + sketch consumption/browser.
//
// Two halves:
//  1. Render math (no Flutter binding needed): analytic edge béziers,
//     projectVec linearity, DisplayEdge record parsing, hidden-line
//     occlusion, visible-run grouping, cylinder silhouettes, and Gouraud
//     shade structure — all against the SHARED synthetic v4 cylinder mesh.
//  2. App flow: creating a feature CONSUMES its sketch (visibility off), the
//     browser nests it under the feature, the eye toggles it back, and the
//     'vis' state round-trips through the part sidecar.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/occt_engine.dart';
import 'package:ipadprocad/part_model.dart';
import 'package:ipadprocad/part_render.dart';

import 'synth_mesh.dart';

// ---- a fake kernel that hands back the REAL synthetic v4 cylinder mesh ----
class CylKernel implements PartKernel {
  bool fail = false;
  int fusions = 0;

  @override
  bool get available => true;
  @override
  String get info => 'cyl-fake';
  @override
  String get lastError => 'fake failure';

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    if (fail) return null;
    // radius from the profile bbox; height from the extrude
    var maxR = 5.0;
    for (final p in groups.first.first) {
      maxR = math.max(maxR, p.distance);
    }
    return KernelSolid(synthCylinderMesh(maxR, height, 0.5),
        math.pi * maxR * maxR * height, null);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    fusions++;
    return KernelSolid(a.mesh, a.volume + b.volume, null);
  }

  @override
  bool exportStep(List<KernelSolid> solids, String path) => false;
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipadprocad_m59_');
  app.partKernel = CylKernel();
  return app;
}

void addRectLines(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// Drives create → sketch on a plane → rectangle → extrude, returns the app.
Future<AppState> buildExtrudedPart({String plane = 'xy'}) async {
  final app = makeApp();
  await app.createNamedPart('Part1');
  app.startPartSketch();
  app.planePicked(plane);
  addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: '5 mm');
  await app.applyExtrude();
  return app;
}

// A camera looking down +X (so the cylinder's +Z axis is vertical on screen).
Cam3 sideCam(Size size) {
  final cam = PartCamera()..orientToDir(Vec3(1, 0, 0)); // look along +X
  cam
    ..halfH = 40
    ..ox = 0
    ..oy = 2.5;
  return Cam3(cam, size);
}

void main() {
  const size = Size(800, 600);

  group('M59 render math', () {
    test('solidOccluder hides overlay points behind the solid, keeps front',
        () {
      final cam = sideCam(size);
      final solid = KernelSolid(synthCylinderMesh(10, 5, 0.5), 1, null);
      final occ = solidOccluder([solid], cam);
      // camera looks along +X: x=+10 is nearest (visible), x=-10 farthest
      // (behind the barrel). A sketch/plane point there must be hidden.
      final front = Vec3(10, 0, 2.5);
      final back = Vec3(-10, 0, 2.5);
      expect(occ.hidden(cam.project(front), cam.depth(front)), isFalse);
      expect(occ.hidden(cam.project(back), cam.depth(back)), isTrue);
    });

    test('a point in front of the whole solid is never occluded', () {
      final cam = sideCam(size);
      final solid = KernelSolid(synthCylinderMesh(10, 5, 0.5), 1, null);
      final occ = solidOccluder([solid], cam);
      // camera looks along +X (depth grows toward -X); a point well in FRONT
      // of the nearest surface (x > +10) must always be visible — this is a
      // sketch/plane sitting between the camera and the model.
      final inFront = Vec3(25, 0, 2.5);
      expect(occ.hidden(cam.project(inFront), cam.depth(inFront)), isFalse,
          reason: 'a sketch in front of the model is drawn over it');
      // and a point on the near surface itself (the front of the barrel at
      // x=+10) is visible — its own face does not swallow it (bias).
      final onNearFace = Vec3(10, 0, 2.5);
      expect(
          occ.hidden(cam.project(onNearFace), cam.depth(onNearFace)), isFalse,
          reason: 'a sketch on the front face stays visible');
    });

    test('empty occluder list hides nothing', () {
      final cam = sideCam(size);
      final occ = solidOccluder(const [], cam);
      expect(occ.hidden(cam.project(Vec3(-10, 0, 2.5)), 999), isFalse);
    });

    test('projectVec is the exact linear part of project', () {
      final cam = sideCam(size);
      final origin = cam.project(Vec3.zero);
      for (final v in [
        Vec3(3, 0, 0),
        Vec3(0, 7, 0),
        Vec3(0, 0, -4),
        Vec3(2, -5, 9),
      ]) {
        final viaProject = cam.project(v) - origin;
        final viaVec = cam.projectVec(v);
        expect((viaProject.dx - viaVec.dx).abs(), lessThan(1e-9));
        expect((viaProject.dy - viaVec.dy).abs(), lessThan(1e-9));
      }
      // and it is linear: projectVec(a+b) == projectVec(a)+projectVec(b)
      final a = Vec3(1, 2, 3), b = Vec3(-4, 5, -6);
      final sum = cam.projectVec(a + b);
      final parts = cam.projectVec(a) + cam.projectVec(b);
      expect((sum.dx - parts.dx).abs(), lessThan(1e-9));
      expect((sum.dy - parts.dy).abs(), lessThan(1e-9));
    });

    test('genArcCubics traces a projected circle within a fraction of a pixel',
        () {
      // project the bottom rim (world circle r=10 in z=0) and compare the
      // béziers to the true projected ellipse.
      final cam = sideCam(size);
      const r = 10.0;
      final c = cam.project(Vec3.zero);
      final ax = cam.projectVec(Vec3(r, 0, 0)); // cos axis (world +X)
      final ay = cam.projectVec(Vec3(0, r, 0)); // sin axis (world +Y)
      final cps = genArcCubics(c, ax, ay, 0, 2 * math.pi);
      final nSeg = (cps.length - 1) ~/ 3;
      expect((cps.length - 1) % 3, 0);
      Offset cubic(Offset p0, Offset p1, Offset p2, Offset p3, double u) {
        final mt = 1 - u;
        return p0 * (mt * mt * mt) +
            p1 * (3 * mt * mt * u) +
            p2 * (3 * mt * u * u) +
            p3 * (u * u * u);
      }

      Offset truePt(double t) =>
          cam.project(Vec3(r * math.cos(t), r * math.sin(t), 0));
      var maxErr = 0.0;
      for (var s = 0; s < nSeg; s++) {
        final ta = 2 * math.pi / nSeg * s, tb = 2 * math.pi / nSeg * (s + 1);
        for (var i = 0; i <= 16; i++) {
          final u = i / 16;
          final approx = cubic(
              cps[s * 3], cps[s * 3 + 1], cps[s * 3 + 2], cps[s * 3 + 3], u);
          maxErr =
              math.max(maxErr, (approx - truePt(ta + (tb - ta) * u)).distance);
        }
      }
      expect(maxErr, lessThan(0.25),
          reason: 'analytic rim within a quarter pixel of the true ellipse');
    });

    test('visibleRuns groups consecutive true samples', () {
      expect(visibleRuns([]).isEmpty, isTrue);
      expect(visibleRuns([true, true, true]), [(0, 2)]);
      expect(visibleRuns([false, false]).isEmpty, isTrue);
      expect(visibleRuns([true, false, true, true, false, true]),
          [(0, 0), (2, 3), (5, 5)]);
      expect(visibleRuns([false, true, true]), [(1, 2)]);
    });

    test('DisplayEdge.of reads analytic circles and falls back to polylines',
        () {
      final m = synthCylinderMesh(10, 5, 0.5);
      final edges = DisplayEdge.of(m);
      expect(edges.length, m.edgeCount);
      // both rims parse as full circles r=10
      final circles = edges.where((e) => e.type == kEdgeCircle).toList();
      expect(circles.length, 2);
      for (final e in circles) {
        expect(e.ax.length, closeTo(10, 1e-9));
        expect(e.ay.length, closeTo(10, 1e-9));
        expect((e.t1 - e.t0).abs(), closeTo(2 * math.pi, 1e-9));
        // a sampled point lies on the circle
        final p = e.pointAt(e.t0 + (e.t1 - e.t0) * 0.3);
        expect(math.sqrt((p - e.c).dot(p - e.c)), closeTo(10, 1e-6));
      }
      // a mesh WITHOUT v4 data → every edge is a polyline fallback
      final legacy = synthCylinderMesh(10, 5, 0.5, v4: false);
      final le = DisplayEdge.of(legacy);
      expect(le.every((e) => e.type == kEdgeOther), isTrue);
      expect(le.every((e) => e.polyEnd > e.polyStart), isTrue);
    });

    test('buildSceneSolid produces smooth per-vertex shades on the barrel', () {
      final cam = sideCam(size);
      final solid = KernelSolid(synthCylinderMesh(10, 5, 0.5), 1, null);
      final scene = buildSceneSolid(solid, cam);
      expect(scene.tris, isNotEmpty);
      // every triangle carries a face id in range and per-corner shades in
      // [0,1]; barrel corners must vary (Gouraud), caps must be uniform.
      final barrelShades = <double>{};
      for (final t in scene.tris) {
        expect(t.faceId, inInclusiveRange(0, 2));
        for (final s in [t.sa, t.sb, t.sc]) {
          expect(s, inInclusiveRange(0.0, 1.0));
        }
        if (t.faceId == synthBarrelFace) {
          barrelShades
            ..add(t.sa)
            ..add(t.sb)
            ..add(t.sc);
        }
        if (t.faceId == synthTopFace) {
          // a flat cap: all three corner normals equal → equal shade
          expect(t.sa, closeTo(t.sb, 1e-9));
          expect(t.sb, closeTo(t.sc, 1e-9));
        }
      }
      expect(barrelShades.length, greaterThan(4),
          reason: 'the curved barrel shades across a range of values');
    });

    test('SceneOccluders hides the back rim and keeps the front rim', () {
      final cam = sideCam(size);
      final solid = KernelSolid(synthCylinderMesh(10, 5, 0.5), 1, null);
      final scene = buildSceneSolid(solid, cam);
      final occ = SceneOccluders([scene]);
      // The camera looks ALONG +X (depth grows toward -X), so the barrel
      // point at x=+10 is NEAREST (visible) and the one at x=-10 is FARTHEST
      // (occluded by the barrel in front of it).
      final near = Vec3(10, 0, 2.5);
      final far = Vec3(-10, 0, 2.5);
      expect(occ.hidden(cam.project(near), cam.depth(near)), isFalse,
          reason: 'near rim point is visible');
      expect(occ.hidden(cam.project(far), cam.depth(far)), isTrue,
          reason: 'far rim point is behind the barrel');
    });

    test('cylinderSilhouettes returns the two axis-parallel flank lines', () {
      final cam = sideCam(size);
      final m = synthCylinderMesh(10, 5, 0.5);
      // face 0 is the barrel
      final rec = m.faceInfos.sublist(0, 15);
      final sil = cylinderSilhouettes(rec, cam);
      expect(sil.length, 2, reason: 'full barrel shows two generators');
      for (final (p, q) in sil) {
        // generator is axis-parallel (world +Z): x,y constant, z spans 0..h
        expect(p.x, closeTo(q.x, 1e-9));
        expect(p.y, closeTo(q.y, 1e-9));
        expect({p.z, q.z}, containsAll(<double>[0, 5]));
        // it sits on the flanks perpendicular to the view (+X): x≈0, |y|≈10
        expect(p.x.abs(), lessThan(1e-9));
        expect(p.y.abs(), closeTo(10, 1e-9));
      }
      // looking straight down the axis yields no silhouette
      // an axial view (down the +Z axis) shows no silhouette generators
      final axialSrc = PartCamera()..orientToDir(Vec3(0, 0, 1));
      expect(cylinderSilhouettes(rec, Cam3(axialSrc, size)).isEmpty, isTrue);
    });
  });

  group('M59 sketch consumption + browser nesting', () {
    test('creating the feature consumes its sketch (visibility off)', () async {
      final app = await buildExtrudedPart();
      final part = app.currentPart!;
      final cs = part.childSketches.single;
      final f = part.features.single;
      expect(firstConsumerOf(part, cs.model.name), same(f),
          reason: 'the extrusion is the sketch consumer');
      expect(cs.visible, isFalse, reason: 'consumption hides the sketch');
    });

    test('the eye toggles a consumed sketch back on and persists it', () async {
      final app = await buildExtrudedPart();
      final part = app.currentPart!;
      final cs = part.childSketches.single;
      expect(cs.visible, isFalse);
      app.toggleSketchVisible(cs);
      expect(cs.visible, isTrue);

      // saved sidecar carries the per-sketch 'vis' flag
      await app.savePart('Part1');
      final file = _partFile(app, 'Part1');
      expect(file.existsSync(), isTrue, reason: 'part sidecar written');
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final sketches = _sketchList(decoded);
      expect(sketches.single['vis'], isTrue,
          reason: 'toggled-on sketch persists as visible');
    });

    test('firstConsumerOf finds only the first feature to use a sketch', () {
      final part = PartModel('P');
      final skModel = SketchModel('Sketch1');
      part.childSketches.add(ChildSketch(skModel, 'xy'));
      final f1 = ExtrudeFeature(
          name: 'Extrusion1',
          bodyName: 'Solid1',
          sketchName: 'Sketch1',
          profiles: const []);
      final f2 = ExtrudeFeature(
          name: 'Extrusion2',
          bodyName: 'Solid2',
          sketchName: 'Sketch1',
          profiles: const []);
      part.features.addAll([f1, f2]);
      expect(firstConsumerOf(part, 'Sketch1'), same(f1));
      expect(firstConsumerOf(part, 'nope'), isNull);
    });

    test('a legacy sidecar (no vis) hides consumed sketches on load', () async {
      final app = await buildExtrudedPart();
      final part = app.currentPart!;
      final name = part.name;
      // hand-write a sidecar WITHOUT the per-sketch 'vis' key (pre-M59)
      await app.savePart(name);
      final file = _partFile(app, name);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final s in (json['sketches'] as List)) {
        (s as Map).remove('vis');
      }
      file.writeAsStringSync(jsonEncode(json));

      // reopen in a fresh app sharing the docs dir; consumed sketch loads hidden
      final app2 = makeApp()..docsDirForTest = app.docsDirForTest;
      await app2.openPart(name);
      final cs = app2.currentPart!.childSketches.single;
      expect(cs.visible, isFalse,
          reason: 'legacy consumed sketch defaults to hidden');
    });
  });
}

// ---- sidecar helpers (schema-tolerant) ------------------------------------
// Part sidecar lives in the per-part sketch dir as "<name>.part.json".
File _partFile(AppState app, String name) {
  // mirror AppState._partJson: <docs>/sketches/<name>.part.json
  final dir = Directory('${app.docsDirForTest!.path}/sketches');
  return File('${dir.path}/$name.part.json');
}

List<Map<String, dynamic>> _sketchList(Map<String, dynamic> json) => [
      for (final s in (json['sketches'] as List? ?? const []))
        (s as Map).cast<String, dynamic>()
    ];
