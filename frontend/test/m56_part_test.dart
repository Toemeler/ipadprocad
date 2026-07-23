// M56 — 3D part layer: plane frames, profile-region detection, extrude
// semantics, session state machine and part persistence. The OCCT kernel is
// NOT linked on host, so a fake [PartKernel] exercises the state machinery
// while [OcctPartKernel] stays honest (available == false, no fake B-Rep).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/occt_engine.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/part_model.dart';

/// Records what the kernel was asked for and hands back a stub solid, so
/// the tests can assert the GEOMETRY HANDED DOWN without a 3D kernel.
class FakeKernel implements PartKernel {
  List<List<List<Offset>>>? lastGroups;
  double? lastHeight, lastTaper;
  List<double>? lastMat;
  bool fail = false;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    lastGroups = groups;
    lastHeight = height;
    lastTaper = taperDeg;
    lastMat = mat34;
    if (fail) return null;
    return KernelSolid(
        OcctMeshData(
            Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
            Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
            Int32List.fromList(const [0, 1, 2]),
            Int32List.fromList(const [0, 3]),
            Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
        height,
        null);
  }

  int fusions = 0;

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    fusions++;
    // combined stub: same degenerate mesh, volumes added — enough for the
    // join-fold tests to assert chain length and accumulated volume
    return KernelSolid(a.mesh, a.volume + b.volume, null);
  }

  int cuts = 0, intersects = 0;

  @override
  KernelSolid? cutSolids(KernelSolid base, KernelSolid tool) {
    if (fail) return null;
    cuts++;
    // distinct stub volume so fold tests can tell cut from join/intersect
    return KernelSolid(base.mesh, base.volume - tool.volume, null);
  }

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    intersects++;
    return KernelSolid(a.mesh, math.min(a.volume, b.volume), null);
  }

  @override
  bool exportStep(List<KernelSolid> solids, String path) => false;
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipadprocad_m56_');
  return app;
}

/// Draws a closed rectangle as FOUR separate lines (the M34 model), which is
/// exactly what the sketcher produces — the loop finder has to chain them.
void addRectLines(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  // through the ENGINE, like the sketcher does — that is what the DXF holds
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

void main() {
  group('plane frames', () {
    test(
        'every frame is right-handed and orthonormal (occt_transform '
        'rejects anything else)', () {
      for (final key in kPlaneKeys) {
        final f = planeFrame(key);
        expect(f.u.length, closeTo(1, 1e-12), reason: key);
        expect(f.v.length, closeTo(1, 1e-12), reason: key);
        expect(f.n.length, closeTo(1, 1e-12), reason: key);
        expect(f.u.dot(f.v), closeTo(0, 1e-12), reason: key);
        final c = f.u.cross(f.v);
        expect((c - f.n).length, closeTo(0, 1e-12),
            reason: 'u x v must equal n on $key');
      }
    });

    test(
        'mat34 places the sketch origin on the plane and offsets along '
        'the normal', () {
      final f = planeFrame('xz');
      final m = f.mat34(-2.5);
      // translation column = n * offset
      expect(m[3], closeTo(f.n.x * -2.5, 1e-12));
      expect(m[7], closeTo(f.n.y * -2.5, 1e-12));
      expect(m[11], closeTo(f.n.z * -2.5, 1e-12));
      // rotation columns are u, v, n
      expect(m[0], closeTo(f.u.x, 1e-12));
      expect(m[1], closeTo(f.v.x, 1e-12));
      expect(m[2], closeTo(f.n.x, 1e-12));
    });

    test('toWorld maps sketch axes onto the plane', () {
      final f = planeFrame('xy');
      final p = f.toWorld(const Offset(3, 4));
      expect(p.x, closeTo(3, 1e-12));
      expect(p.y, closeTo(4, 1e-12));
      expect(p.z, closeTo(0, 1e-12));
    });
  });

  group('extrude span (Inventor direction semantics)', () {
    test('default grows +normal from the plane', () {
      expect(extrudeSpan(ExtrudeDirection.defaultDir, 5, 3), (5.0, 0.0));
    });
    test('flipped grows -normal (same height, shifted start)', () {
      expect(extrudeSpan(ExtrudeDirection.flipped, 5, 3), (5.0, -5.0));
    });
    test('symmetric splits Distance A half above / half below', () {
      expect(extrudeSpan(ExtrudeDirection.symmetric, 6, 3), (6.0, -3.0));
    });
    test('asymmetric spans A above and B below', () {
      expect(extrudeSpan(ExtrudeDirection.asymmetric, 5, 3), (8.0, -3.0));
    });
  });

  group('profile detection', () {
    test('four separate lines chain into ONE counter-clockwise loop', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 20, 10);
      final loops = profileLoops(s);
      expect(loops.length, 1);
      expect(loops.first.area, closeTo(200, 1e-6));
      expect(loops.first.pts.length, 4);
      expect(loops.first.ents.length, 4, reason: 'all four lines contribute');
    });

    test('a circle is a loop on its own; area matches pi r^2', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      s.engine.setCurrentLayer('Layer 1');
      s.engine.addCircle(5, 5, 3);
      s.refresh();
      final loops = profileLoops(s);
      expect(loops.length, 1);
      expect(loops.first.area, closeTo(math.pi * 9, 0.05));
    });

    test('circle inside a rectangle is ONE region with a hole (Inventor)', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 20, 10);
      s.engine.setCurrentLayer('Layer 1');
      s.engine.addCircle(10, 5, 2);
      s.refresh();
      final regions = regionsFrom(profileLoops(s));
      // The circle is the rectangle's HOLE, not its own region, so a
      // rectangle-with-a-hole auto-selects and extrudes as a solid with a
      // bore — the whole point of this fix.
      expect(regions.length, 1, reason: 'the hole is not a separate region');
      final outer = regions.single;
      expect(outer.outer.area, closeTo(200, 0.5));
      expect(outer.holes.length, 1);
      expect(outer.holes.first.area, closeTo(math.pi * 4, 0.05));
    });

    test('an island inside a hole is a region again (even/odd nesting)', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 40, 40); // outer solid
      s.engine.setCurrentLayer('Layer 1');
      s.engine.addCircle(20, 20, 15); // big hole
      s.engine.addCircle(20, 20, 5); // island inside the hole -> solid again
      s.refresh();
      final regions = regionsFrom(profileLoops(s));
      // Two solid regions: the outer ring (with the big circle as its hole)
      // and the small island (depth 2 -> solid, no holes).
      expect(regions.length, 2);
      final ring = regions.firstWhere((r) => r.outer.area > 1000);
      expect(ring.holes.length, 1);
      expect(ring.holes.first.area, closeTo(math.pi * 225, 1.0));
      final island = regions.firstWhere((r) => r.outer.area < 1000);
      expect(island.holes, isEmpty);
      expect(island.outer.area, closeTo(math.pi * 25, 0.5));
    });

    test('a rectangle split by a diagonal yields TWO triangle faces', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 10, 10);
      s.engine.setCurrentLayer('Layer 1');
      s.engine.addLine(0, 0, 10, 10);
      s.refresh();
      final loops = profileLoops(s);
      expect(loops.length, 2);
      for (final l in loops) {
        expect(l.area, closeTo(50, 1e-6));
      }
    });

    test('construction and centerline geometry never forms a profile', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 10, 10);
      final g = s.geometry.removeLast();
      s.geometry.add(g.withStyle(Geo.styleConstruction));
      expect(profileLoops(s), isEmpty,
          reason: 'the loop is open once a side is construction');
    });

    test('geometry below End of Sketch is excluded', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 10, 10);
      expect(profileLoops(s).length, 1);
      s.eosAfter = 0; // roll Layer 1 back
      expect(profileLoops(s), isEmpty);
    });

    test('a dangling line does not poison the loop', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 10, 10);
      s.engine.setCurrentLayer('Layer 1');
      s.engine.addLine(10, 10, 18, 16);
      s.refresh();
      final loops = profileLoops(s);
      expect(loops.length, 1);
      expect(loops.first.area, closeTo(100, 1e-6));
    });

    test('regionAt uses filled material — a tap in a hole selects nothing', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      addRectLines(s, 0, 0, 20, 20);
      s.engine.setCurrentLayer('Layer 1');
      s.engine.addCircle(10, 10, 4);
      s.refresh();
      final regions = regionsFrom(profileLoops(s));
      // Tapping the ring material returns the rectangle-with-hole.
      final inRing = regionAt(regions, const Offset(2, 2))!;
      expect(inRing.outer.area, closeTo(400, 1e-6));
      expect(inRing.holes.length, 1);
      // Tapping the empty centre of the hole selects nothing (Inventor).
      expect(regionAt(regions, const Offset(10, 10)), isNull);
      // Outside everything: null.
      expect(regionAt(regions, const Offset(-5, -5)), isNull);
    });

    test('interiorPointOf lands inside a concave (L) profile', () {
      final s = SketchModel('t')..layers.add('Layer 1');
      const pts = [
        Offset(0, 0),
        Offset(40, 0),
        Offset(40, 10),
        Offset(10, 10),
        Offset(10, 30),
        Offset(0, 30),
      ];
      s.engine.setCurrentLayer('Layer 1');
      for (var i = 0; i < pts.length; i++) {
        final a = pts[i], b = pts[(i + 1) % pts.length];
        s.engine.addLine(a.dx, a.dy, b.dx, b.dy);
      }
      s.refresh();
      final l = profileLoops(s).single;
      expect(l.area, closeTo(600, 1e-6));
      expect(pointInPolygon(interiorPointOf(l), l.pts), isTrue);
    });
  });

  group('value parsing', () {
    test('accepts plain numbers, units and full expressions', () {
      expect(parseValueExpr('5'), 5);
      expect(parseValueExpr('5 mm'), 5);
      expect(parseValueExpr('12.5mm'), 12.5);
      expect(parseValueExpr('0.00 deg'), 0);
      expect(parseValueExpr('30 deg'), 30);
      expect(parseValueExpr('2*3+4'), 10);
      expect(parseValueExpr('  7,5 '), 7.5);
    });
    test('rejects nonsense', () {
      expect(parseValueExpr(''), isNull);
      expect(parseValueExpr('mm'), isNull);
      expect(parseValueExpr('abc'), isNull);
    });
  });

  group('kernel honesty', () {
    test(
        'the real OCCT kernel reports unavailable on host — never fakes '
        'a solid', () {
      final k = OcctPartKernel();
      expect(k.available, isFalse);
      expect(
          k.extrude([
            [
              [const Offset(0, 0), const Offset(1, 0), const Offset(1, 1)]
            ]
          ], 5, 0, planeFrame('xy').mat34(0)),
          isNull);
      expect(k.lastError, contains('no 3D kernel'));
    });
  });

  group('part flow', () {
    test('new part -> sketch on a plane -> finish -> extrude', () async {
      final app = makeApp();
      final fake = FakeKernel();
      app.partKernel = fake;

      expect(await app.createNamedPart('Part1'), isTrue);
      final part = app.currentPart!;
      expect(app.currentPart, isNotNull);
      expect(app.activeChild, isNull);

      // Start 2D Sketch reveals the planes and arms the pick
      app.startPartSketch();
      expect(app.pickPlane, isTrue);
      expect(part.vis['xy'], isTrue);

      // picking a plane creates the child sketch and enters edit mode
      app.planePicked('xy');
      expect(app.pickPlane, isFalse);
      expect(part.vis['xy'], isFalse, reason: 'planes hide again');
      expect(app.activeChild, isNotNull);
      expect(app.inEditMode, isTrue, reason: 'lands in a fresh Layer 1');
      expect(app.current, same(app.activeChild),
          reason: 'the 2D sketcher drives the child unchanged');
      expect(part.childSketches.single.plane, 'xy');

      // draw a 20x10 rectangle, finish the sketch
      addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      expect(app.activeChild, isNull);
      expect(app.currentPart, isNotNull, reason: 'back in the 3D part');

      // extrude it 5mm
      app.openExtrude();
      final sess = app.extrudeSession!;
      expect(sess.profiles.length, 1,
          reason: 'a single profile is pre-selected, like Inventor');
      app.setExtrude(exprA: '5 mm');
      expect(await app.applyExtrude(), isTrue);
      expect(app.extrudeSession, isNull);
      expect(part.features.length, 1);

      final f = part.features.single;
      expect(f.name, 'Extrusion1');
      expect(f.bodyName, 'Solid1');
      expect(f.distanceA, 5);
      expect(f.solid, isNotNull);
      expect(f.computeError, isNull);

      // the kernel got the real profile, height and placement
      expect(fake.lastHeight, 5);
      expect(fake.lastTaper, 0);
      expect(fake.lastGroups!.single.single.length, 4);
      expect(fake.lastMat, planeFrame('xy').mat34(0));
    });

    test('symmetric extrusion offsets the placement by half the height',
        () async {
      final app = makeApp();
      final fake = FakeKernel();
      app.partKernel = fake;
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('yz');
      addRectLines(app.activeChild!, 0, 0, 10, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      app.setExtrude(direction: ExtrudeDirection.symmetric, exprA: '8');
      expect(await app.applyExtrude(), isTrue);
      expect(fake.lastHeight, 8);
      expect(fake.lastMat, planeFrame('yz').mat34(-4));
    });

    test('a bad value is refused and creates nothing', () async {
      final app = makeApp();
      app.partKernel = FakeKernel();
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 10, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      app.setExtrude(exprA: '0');
      expect(await app.applyExtrude(), isFalse);
      expect(app.currentPart!.features, isEmpty);
      app.setExtrude(exprA: '5', exprTaper: '95 deg');
      expect(await app.applyExtrude(), isFalse);
      expect(app.currentPart!.features, isEmpty);
    });

    test('a kernel failure never leaves a half-built feature', () async {
      final app = makeApp();
      final fake = FakeKernel()..fail = true;
      app.partKernel = fake;
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 10, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      expect(await app.applyExtrude(), isFalse);
      expect(app.currentPart!.features, isEmpty);
    });

    test('editing the sketch recomputes the feature against the new shape',
        () async {
      final app = makeApp();
      final fake = FakeKernel();
      app.partKernel = fake;
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      final sk = app.activeChild!;
      addRectLines(sk, 0, 0, 20, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      await app.applyExtrude();
      expect(fake.lastGroups!.single.single.length, 4);

      // reopen, replace the rectangle with a bigger one, finish again
      app.openChildSketch(sk.name);
      expect(app.activeChild, same(sk));
      sk.engine.clearForReload();
      sk.geometry.clear();
      addRectLines(sk, 0, 0, 40, 10, layer: 'Layer 1');
      app.finishPartSketch();
      final pts = fake.lastGroups!.single.single;
      final maxX = pts.map((p) => p.dx).reduce(math.max);
      expect(maxX, closeTo(40, 1e-9),
          reason: 'the feature follows the edited sketch');
      expect(app.currentPart!.features.single.computeError, isNull);
    });

    test('deleting the profile marks the feature sick, honestly', () async {
      final app = makeApp();
      app.partKernel = FakeKernel();
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      final sk = app.activeChild!;
      addRectLines(sk, 0, 0, 10, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      await app.applyExtrude();
      app.openChildSketch(sk.name);
      sk.engine.clearForReload();
      sk.geometry.clear();
      app.finishPartSketch();
      final f = app.currentPart!.features.single;
      expect(f.solid, isNull);
      expect(f.computeError, isNotNull);
    });

    test('profiles of a second sketch cannot join the same extrusion',
        () async {
      final app = makeApp();
      app.partKernel = FakeKernel();
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 10, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      app.startPartSketch();
      app.planePicked('yz');
      addRectLines(app.activeChild!, 0, 0, 8, 8, layer: app.editingLayer!);
      app.finishPartSketch();

      final part = app.currentPart!;
      app.openExtrude();
      final first = part.childSketches.first;
      final regions = app.sessionRegions(first);
      app.toggleSessionProfile(first.model.name, regions.first);
      expect(app.extrudeSession!.profiles.length, 1);
      expect(app.extrudeSession!.sketchName, first.model.name,
          reason: 'the session locks to the first sketch picked');
      // a region of the OTHER sketch is refused
      final second = part.childSketches.last;
      app.toggleSessionProfile(
          second.model.name, app.sessionRegions(second).first);
      expect(app.extrudeSession!.profiles.length, 1);
      expect(app.extrudeSession!.sketchName, first.model.name);
    });

    test('Esc cancels the session, then the plane pick', () {
      final app = makeApp();
      app.partKernel = FakeKernel();
      app.createNamedPart('P');
      app.startPartSketch();
      expect(app.pickPlane, isTrue);
      app.escape3D();
      expect(app.pickPlane, isFalse);
    });
  });

  group('persistence', () {
    test('a part round-trips through disk with sketches and features',
        () async {
      final app = makeApp();
      app.partKernel = FakeKernel();
      await app.createNamedPart('Widget');
      app.startPartSketch();
      app.planePicked('xz');
      addRectLines(app.activeChild!, 0, 0, 30, 12, layer: app.editingLayer!);
      app.finishPartSketch();
      app.openExtrude();
      app.setExtrude(
          exprA: '7 mm',
          exprTaper: '3 deg',
          direction: ExtrudeDirection.flipped);
      await app.applyExtrude();
      await app.savePart('Widget');

      // gallery lists it as a PART
      await app.refreshSaved();
      final card = app.saved.firstWhere((s) => s.name == 'Widget');
      expect(card.kind, 'part');

      // drop it from the session and reload from disk
      final docs = app.saved;
      expect(docs, isNotEmpty);
      app.parts.remove('Widget')!.dispose();
      app.openTabs.clear();
      app.curTab = null;
      await app.openPart('Widget');

      final p = app.currentPart!;
      expect(p.childSketches.length, 1);
      expect(p.childSketches.single.plane, 'xz');
      expect(p.childSketches.single.model.geometry.length, 4,
          reason: 'the child sketch DXF round-trips');
      expect(p.features.length, 1);
      final f = p.features.single;
      expect(f.distanceA, 7);
      expect(f.taperDeg, 3);
      expect(f.direction, ExtrudeDirection.flipped);
      expect(f.exprA, '7 mm', reason: 'the typed expression is kept');
      expect(f.sketchName, p.childSketches.single.model.name);
    });

    test('parts and sketches share one namespace', () async {
      final app = makeApp();
      await app.createNamedPart('Shared');
      expect(app.docNameExists('Shared'), isTrue);
      expect(await app.createNamedSketch('Shared'), isFalse);
      expect(await app.createNamedPart('Shared'), isFalse);
    });

    test('deleting a part removes its files', () async {
      final app = makeApp();
      app.partKernel = FakeKernel();
      await app.createNamedPart('Gone');
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 5, 5, layer: app.editingLayer!);
      app.finishPartSketch();
      await app.savePart('Gone');
      await app.deletePart('Gone');
      await app.refreshSaved();
      expect(app.saved.where((s) => s.name == 'Gone'), isEmpty);
      expect(app.docNameExists('Gone'), isFalse);
    });
  });
}
