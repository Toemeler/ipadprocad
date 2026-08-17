// M221 — "I cant select the inner circle to also extrude somehow."
//
// Reported against build `1a0bb61` (M210), where it was left explicitly
// UNFIXED: the region decomposition was proven correct — two nested circles do
// yield two pickable regions, and `regionAt` at the centre does return the
// disc — so the fault had to be somewhere on the way from the tap to the
// region, and that path was never narrowed down. It is two faults.
//
// 1. THE ANCHOR. A selection is stored as a POINT plus an area, and that point
//    was `interiorPointOf(region.outer)` — the interior point of the outer
//    LOOP, which knows nothing about the hole cut out of it. For a ring the
//    centroid is inside the outer loop, so that is the answer: the middle of
//    the hole. Which is also, to the last bit, what the disc sitting in that
//    hole answers. The two regions were therefore stored under ONE anchor:
//      - `toggleSessionProfile` found the disc's anchor already in the list
//        and did nothing — the reported symptom, in either order;
//      - `hasProfileAt` painted the ring as selected when the disc was;
//      - `resolveProfiles` matched by nearest anchor, so with both at distance
//        0 it took whichever region came first — a ring could rebuild as a
//        plain disc.
//
// 2. THE OVERLAY. With a child sketch open, Viewport2D covers the whole
//    viewport and never forwards a tap to a 3D pick. Opening Extrude did not
//    close it, so the panel appeared over a surface that swallowed every pick.
//    (`openChildSketch` has always done the mirror — it cancels an open
//    extrude.) The device log behind the report shows exactly this: the user
//    was in Sketch7 the whole time.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

List<Offset> _circle(double r, {int n = 96, Offset c = Offset.zero}) => [
      for (var i = 0; i < n; i++)
        c +
            Offset(r * math.cos(2 * math.pi * i / n),
                r * math.sin(2 * math.pi * i / n))
    ];

double _area(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].dx * p[j].dy - p[j].dx * p[i].dy;
  }
  return a.abs() / 2;
}

Offset _centroid(List<Offset> p) {
  var x = 0.0, y = 0.0;
  for (final q in p) {
    x += q.dx;
    y += q.dy;
  }
  return Offset(x / p.length, y / p.length);
}

ProfileLoop _loop(int id, List<Offset> pts) =>
    ProfileLoop(id, pts, _area(pts), _centroid(pts), {id});

/// The reported drawing: two concentric circles, Ø30 and Ø10.
List<ProfileRegion> _ringAndDisc() =>
    regionsFrom([_loop(0, _circle(15)), _loop(1, _circle(5))]);

ProfileRegion _ring(List<ProfileRegion> rs) =>
    rs.firstWhere((r) => r.holes.isNotEmpty);
ProfileRegion _disc(List<ProfileRegion> rs) =>
    rs.firstWhere((r) => r.holes.isEmpty);

SketchModel _ringSketch(String name) {
  final s = SketchModel(name)..layers.add('Layer 1');
  s.engine.setCurrentLayer('Layer 1');
  s.engine.addCircle(0, 0, 15);
  s.engine.addCircle(0, 0, 5);
  s.refresh();
  return s;
}

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m221_');
  app.partKernel = FakeKernel();
  return app;
}

/// A part carrying one finished sketch with the two concentric circles.
Future<AppState> _ringPart() async {
  final app = _app();
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  final sk = app.activeChild!;
  sk.engine.setCurrentLayer(app.editingLayer!);
  sk.engine.addCircle(0, 0, 15);
  sk.engine.addCircle(0, 0, 5);
  sk.refresh();
  app.finishPartSketch();
  return app;
}

void main() {
  group('M221 — a ring and the disc in its hole are two profiles', () {
    test('the two regions used to share one anchor', () {
      final rs = _ringAndDisc();
      expect(rs.length, 2, reason: 'the decomposition was never the problem');
      final ring = _ring(rs), disc = _disc(rs);

      // The old rule, kept here as the record of what went wrong.
      final oldRing = interiorPointOf(ring.outer);
      final oldDisc = interiorPointOf(disc.outer);
      expect((oldRing - oldDisc).distance, lessThan(1e-9),
          reason: 'both loops are centred on the origin, so the outer loop’s '
              'interior point is the same point for both regions');

      final a = regionAnchor(ring), b = regionAnchor(disc);
      expect((a - b).distance, greaterThan(1),
          reason: 'the anchors must be able to tell the regions apart');
    });

    test('the ring’s anchor lies in its MATERIAL', () {
      final rs = _ringAndDisc();
      final ring = _ring(rs);
      final a = regionAnchor(ring);
      expect(pointInPolygon(a, ring.outer.pts), isTrue);
      expect(ring.holes.any((h) => pointInPolygon(a, h.pts)), isFalse,
          reason: 'an anchor inside the hole is not on the ring at all');
      // ... and it is in the annulus, 5 < r < 15, with room on BOTH sides.
      // The first version of regionAnchor answered (0, 5) here — exactly on
      // the hole's rim: a scan row running tangent to the hole crosses it zero
      // times, so the hole never split that row and the span looked like the
      // whole chord. A point on a boundary is the one point whose
      // inside/outside answer the next tessellation may reverse, so the rule
      // is clearance, not width. (Caught by CI, not by reasoning.)
      expect(a.distance, greaterThan(5));
      expect(a.distance, lessThan(15));
      expect((a.distance - 5).abs(), greaterThan(1),
          reason: 'not hugging the hole');
      expect((a.distance - 15).abs(), greaterThan(1),
          reason: 'not hugging the outer edge either');
      // The disc keeps the cheap answer: nothing is cut out of it.
      expect((regionAnchor(_disc(rs)) - Offset.zero).distance, lessThan(1e-9));
    });

    test('a rectangle with a centred hole behaves the same', () {
      // The case already pinned in m56_part_test: the rectangle’s centroid is
      // the circle’s centre, so this collided too.
      final rect = _loop(0, [
        const Offset(0, 0),
        const Offset(20, 0),
        const Offset(20, 10),
        const Offset(0, 10),
      ]);
      final hole = _loop(1, _circle(2, c: const Offset(10, 5)));
      final rs = regionsFrom([rect, hole]);
      final ring = _ring(rs);
      final a = regionAnchor(ring);
      expect(pointInPolygon(a, ring.outer.pts), isTrue);
      expect(pointInPolygon(a, ring.holes.single.pts), isFalse);
      expect((a - regionAnchor(_disc(rs))).distance, greaterThan(1));
    });

    test('an L profile is unaffected — no holes, same answer as before', () {
      final l = _loop(0, [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 3),
        const Offset(3, 3),
        const Offset(3, 10),
        const Offset(0, 10),
      ]);
      final r = ProfileRegion(l, const []);
      expect(regionAnchor(r), interiorPointOf(l));
      expect(pointInPolygon(regionAnchor(r), l.pts), isTrue);
    });
  });

  group('M221 — a stored selection finds its own region again', () {
    test('each anchor resolves back to the region it came from', () {
      final rs = _ringAndDisc();
      final ring = _ring(rs), disc = _disc(rs);
      final ringSel = ProfileSel(
          regionAnchor(ring).dx, regionAnchor(ring).dy, ring.outer.area);
      final discSel = ProfileSel(
          regionAnchor(disc).dx, regionAnchor(disc).dy, disc.outer.area);
      expect(regionForSel(rs, ringSel)!.outer.id, ring.outer.id);
      expect(regionForSel(rs, discSel)!.outer.id, disc.outer.id);
    });

    test('a selection SAVED before M221 still finds its ring', () {
      // What such a document holds: the centre (which is inside the disc) and
      // the ring’s area. Nearest-anchor alone would hand it to the disc.
      final rs = _ringAndDisc();
      final ring = _ring(rs);
      final legacy = ProfileSel(0, 0, ring.outer.area);
      expect(regionForSel(rs, legacy)!.outer.id, ring.outer.id,
          reason: 'the area is what tells them apart across the change');
    });

    test('resolveProfiles migrates the anchor, and the ring keeps its hole',
        () {
      final p = PartModel('P');
      p.appendChildSketch(ChildSketch(_ringSketch('Sketch1'), 'xy'));
      final regions = regionsFrom(profileLoops(p.childSketches.single.model));
      final ring = _ring(regions);

      final sel = ProfileSel(0, 0, ring.outer.area); // the old document
      final (groups, frame, err) = resolveProfiles(p, 'Sketch1', [sel]);
      expect(err, isNull);
      expect(frame, isNotNull);
      expect(groups!.single.length, 2,
          reason: 'outer loop plus its hole — a ring, not a disc');
      expect(Offset(sel.ax, sel.ay).distance, greaterThan(5),
          reason: 'the anchor was rewritten into the material');

      // Stable: resolving again does not move it any further.
      final before = Offset(sel.ax, sel.ay);
      resolveProfiles(p, 'Sketch1', [sel]);
      expect((Offset(sel.ax, sel.ay) - before).distance, lessThan(1e-9));
    });

    test('a disc selection resolves to the disc alone', () {
      final p = PartModel('P');
      p.appendChildSketch(ChildSketch(_ringSketch('Sketch1'), 'xy'));
      final regions = regionsFrom(profileLoops(p.childSketches.single.model));
      final disc = _disc(regions);
      final a = regionAnchor(disc);
      final (groups, _, err) =
          resolveProfiles(p, 'Sketch1', [ProfileSel(a.dx, a.dy, disc.outer.area)]);
      expect(err, isNull);
      expect(groups!.single.length, 1, reason: 'no hole in the disc');
    });
  });

  group('M221 — picking the inner circle after the ring', () {
    test('both regions can be selected — the reported case', () async {
      final app = await _ringPart();
      final cs = app.currentPart!.childSketches.single;
      app.openExtrude();
      final s = app.extrudeSession!;
      expect(s.profiles, isEmpty, reason: 'two regions, so nothing auto-picks');

      final rs = app.sessionRegions(cs);
      app.toggleSessionProfile(cs.model.name, _ring(rs));
      expect(s.profiles.length, 1);
      app.toggleSessionProfile(cs.model.name, _disc(rs));
      expect(s.profiles.length, 2,
          reason: 'the second pick was read as re-picking the first, and the '
              'inner circle could never be added');
    });

    test('the other order works too', () async {
      final app = await _ringPart();
      final cs = app.currentPart!.childSketches.single;
      app.openExtrude();
      final rs = app.sessionRegions(cs);
      app.toggleSessionProfile(cs.model.name, _disc(rs));
      app.toggleSessionProfile(cs.model.name, _ring(rs));
      expect(app.extrudeSession!.profiles.length, 2);
    });

    test('shift-click removes only the one under the finger', () async {
      final app = await _ringPart();
      final cs = app.currentPart!.childSketches.single;
      app.openExtrude();
      final rs = app.sessionRegions(cs);
      final ring = _ring(rs), disc = _disc(rs);
      app.toggleSessionProfile(cs.model.name, ring);
      app.toggleSessionProfile(cs.model.name, disc);
      app.toggleSessionProfile(cs.model.name, disc, remove: true);

      final s = app.extrudeSession!;
      expect(s.profiles.length, 1);
      expect(regionForSel(rs, s.profiles.single)!.outer.id, ring.outer.id,
          reason: 'the ring is what is left');
    });

    test('the highlight asks the same question the pick answered', () async {
      final app = await _ringPart();
      final cs = app.currentPart!.childSketches.single;
      app.openExtrude();
      final rs = app.sessionRegions(cs);
      app.toggleSessionProfile(cs.model.name, _disc(rs));
      final s = app.extrudeSession!;
      // This is the call the viewport paints with.
      expect(s.hasProfileAt(regionAnchor(_disc(rs))), isTrue);
      expect(s.hasProfileAt(regionAnchor(_ring(rs))), isFalse,
          reason: 'the ring was never picked and must not light up');
    });
  });

  group('M221 — a 3D command takes the viewport back', () {
    test('Extrude finishes an open sketch and aims at THAT sketch', () async {
      final app = await _ringPart();
      final name = app.currentPart!.childSketches.single.model.name;
      app.openChildSketch(name);
      expect(app.activeChild, isNotNull, reason: 'the sketch is open again');

      app.openExtrude();
      expect(app.activeChild, isNull,
          reason: 'the 2D overlay swallowed every profile pick while it was up');
      expect(app.extrudeSession, isNotNull);
      expect(app.extrudeSession!.sketchName, name,
          reason: 'the sketch the command was started from is the one meant');
    });

    test('with a second, newer sketch the OPEN one still wins', () async {
      final app = await _ringPart();
      final first = app.currentPart!.childSketches.single.model.name;
      // A newer sketch, which is what the panel defaults to otherwise.
      app.startPartSketch();
      app.planePicked('yz');
      addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
      app.finishPartSketch();
      expect(app.currentPart!.childSketches.length, 2);

      app.openChildSketch(first);
      app.openExtrude();
      expect(app.extrudeSession!.sketchName, first);
    });

    test('a fillet closes it too — its picks are 3D picks', () async {
      final app = await _ringPart();
      app.openChildSketch(app.currentPart!.childSketches.single.model.name);
      app.openFillet();
      expect(app.activeChild, isNull);
      expect(app.edgeSession, isNotNull);
    });

    test('with no sketch open nothing changes', () async {
      final app = await _ringPart();
      expect(app.activeChild, isNull);
      app.openExtrude();
      expect(app.extrudeSession!.sketchName,
          app.currentPart!.childSketches.last.model.name,
          reason: 'still the newest sketch, exactly as before');
    });
  });
}
