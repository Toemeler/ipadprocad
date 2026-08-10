// M211 — WHICH SIDE OF THE FACE YOU ARE ON.
//
// "i cant project the shape of the slot on the right. its on the wrong side.
// there is no geometry. also the sketch shows the wrong side of the selected
// face" (bug20260805T230205)
//
// One session, two faults, both of them the same question answered wrongly:
// which side of a plane are we looking from?
//
//   * A PROJECTED ARC is a pair of angles and a direction, and the direction
//     comes from the 3D parameter t, which runs counter-clockwise about the
//     edge's own axis. Project it onto a plane that looks at that axis from
//     behind and the sweep mirrors — t increasing now walks clockwise on the
//     sketch. Both ProjKind.arc and Geo.arc mean "counter-clockwise from a0 to
//     a1", so reading the same two endpoints in the same order traced the
//     COMPLEMENT: the other arc of the same circle.
//
//     The device sketch was on the part's BOTTOM face, n=(0,-1,0). Tapping the
//     slot cap at sketch (18.07, 6.84) found nothing — log.txt: "Tap geometry
//     on another layer, or the X/Y axis." — while the cap the picker carried
//     ran through (8.99, 0), the mirror of the real one through (23.20, 0).
//     What the user did next says it plainly: a circle centred (16.10, 0.00)
//     with its rim snapped to (8.99, 0.00). They aimed at what was drawn.
//
//   * THE VIEW. `orientToDir` takes a direction, so it aims the camera and
//     says nothing about the roll — it keeps whatever the orbit left. The
//     sketch camera has no such freedom: `PartCamera.forSketch` pins screen x
//     to the frame's u. Picking the bottom face from an orbit at az≈-2.44 gave
//     a part camera with right≈(-0.77,0,0.64) against the frame's u=(1,0,0),
//     so the swing into the sketch turned the model most of a half turn and
//     the slot picked on the right came up on the left.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';

/// A type-2 (circle) analytic edge record, occt_capi.h layout.
List<double> _circleRec({
  required List<double> c,
  required List<double> xd,
  required List<double> yd,
  required double r,
  double t0 = 0,
  double t1 = 2 * math.pi,
}) {
  final v = List<double>.filled(16, 0);
  v[0] = 2;
  v.setRange(1, 4, c);
  v.setRange(4, 7, xd);
  v.setRange(7, 10, yd);
  v[10] = r;
  v[11] = t0;
  v[12] = t1;
  return v;
}

/// The far cap of the device's slot: centre (16.098, 0, 0), r 7.1035, lying in
/// the y=0 plane, axis +Y. t=0 is the +Z end, t=pi the -Z end, and the half
/// the arc covers is the one bulging towards +X, through (23.2015, 0, 0).
List<double> _slotCap() => _circleRec(
      c: [16.098, 0, 0],
      xd: [0, 0, 1],
      yd: [1, 0, 0],
      r: 7.1035,
      t0: 0,
      t1: math.pi,
    );

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m211');
  return app;
}

void main() {
  group('a projected arc is the arc that is really there', () {
    test('seen from BEHIND its axis, the cap still bulges towards +X', () {
      // The bottom face of the part: n = -Y, so u = +X, v = +Z.
      final fr = faceFrame(const Vec3(0, 0, 0), const Vec3(0, -1, 0));
      final e = analyticProjectedEdge(44, _slotCap(), 0, fr)!;
      expect(e.kind, ProjKind.arc);
      expect(e.defs[0].dx, closeTo(16.098, 1e-9));
      expect(e.radius, closeTo(7.1035, 1e-9));

      // The apex of the real cap, and its mirror image.
      const real = Offset(16.098 + 7.1035, 0);
      const mirror = Offset(16.098 - 7.1035, 0);
      final pts = e.displayPts;
      double near(Offset q) =>
          pts.map((p) => (p - q).distance).reduce(math.min);
      expect(near(real), lessThan(0.05),
          reason: 'the projected cap passes through (23.20, 0)');
      expect(near(mirror), greaterThan(1.0),
          reason: 'and NOT through (8.99, 0), which is the other half');

      // The tap from the log, to the millimetre.
      expect(pickPartEdge([e], const Offset(18.07, 6.84), 0.5), 44,
          reason: 'this is the click that reported "there is no geometry"');
      expect(pickPartEdge([e], mirror, 0.5), isNull);
    });

    test('seen from IN FRONT of its axis, nothing changed', () {
      // The same arc, projected onto a plane whose normal agrees with the
      // edge's axis. This case was always right and must stay right.
      final fr = faceFrame(const Vec3(0, 0, 0), const Vec3(0, 1, 0));
      final e = analyticProjectedEdge(44, _slotCap(), 0, fr)!;
      expect(e.kind, ProjKind.arc);
      final c = e.defs[0];
      final pts = e.displayPts;
      // u = -X here, so the real apex is at u = -(16.098 + 7.1035).
      final apex = Offset(c.dx - 7.1035, 0);
      expect(pts.map((p) => (p - apex).distance).reduce(math.min),
          lessThan(0.05));
      expect(pickPartEdge([e], Offset(c.dx + 7.1035, 0), 0.5), isNull);
    });

    test('the sketch entity carries the corrected sweep, not just the picker',
        () {
      final fr = faceFrame(const Vec3(0, 0, 0), const Vec3(0, -1, 0));
      final e = analyticProjectedEdge(44, _slotCap(), 0, fr)!;
      final g = geoForPartEdge(e, 'Layer 1');
      expect(g.type, Geo.arc);
      final a0 = g.data[3], a1 = g.data[4];
      var sweep = a1 - a0;
      while (sweep <= 0) {
        sweep += 2 * math.pi;
      }
      expect(sweep, closeTo(math.pi, 1e-9), reason: 'a half cap, not 3/4');
      // The midpoint of the drawn sweep is the apex the user tapped near.
      final mid = a0 + sweep / 2;
      expect(g.data[0] + g.data[2] * math.cos(mid), closeTo(23.2015, 1e-3));
      expect(g.data[1] + g.data[2] * math.sin(mid), closeTo(0, 1e-3));
    });

    test('a FULL circle is unaffected by the side it is seen from', () {
      final rec = _circleRec(
          c: [0, 5, 0], xd: [1, 0, 0], yd: [0, 0, 1], r: 3.3434);
      for (final n in const [Vec3(0, 1, 0), Vec3(0, -1, 0)]) {
        final e = analyticProjectedEdge(7, rec, 0, faceFrame(Vec3.zero, n))!;
        expect(e.kind, ProjKind.circle);
        expect(e.radius, closeTo(3.3434, 1e-9));
      }
    });
  });

  group('picking a face aims the camera the way the sketch will', () {
    /// dir/right/up of the camera the sketch editor will swing to.
    (Vec3, Vec3, Vec3) sketchBasis(PlaneFrame fr) {
      final c = PartCamera.forSketch(fr, const Size(800, 600), Offset.zero, 10);
      return (c.dir, c.right, c.up);
    }

    void expectSameBasis(PartCamera cam, PlaneFrame fr, String why) {
      final (d, r, u) = sketchBasis(fr);
      expect(cam.dir.dot(d), closeTo(1, 1e-6), reason: '$why: view direction');
      expect(cam.right.dot(r), closeTo(1, 1e-6), reason: '$why: screen x');
      expect(cam.up.dot(u), closeTo(1, 1e-6), reason: '$why: screen y');
    }

    test('the bottom face, from the orbit the device was actually in', () {
      final app = _app();
      final p = PartModel('Part1');
      // camDir=(-0.42,-0.76,-0.50) in the bundle, i.e. az = atan2(x,z).
      p.camera
        ..az = math.atan2(-0.42, -0.50)
        ..pol = math.acos(-0.76);
      final fr = faceFrame(const Vec3(0, 0, 0), const Vec3(0, -1, 0));
      expect(fr.n.dot(p.camera.dir), greaterThan(0),
          reason: 'the user was below, looking up at the bottom face');
      app.orientToSurface(p, fr);
      expectSameBasis(p.camera, fr, 'bottom face');
      expect(p.camera.right.dot(fr.u), closeTo(1, 1e-6),
          reason: "the frame's u is on screen x — nothing left to spin");
    });

    test('from every orbit, not one lucky one', () {
      final app = _app();
      final normals = [
        const Vec3(0, -1, 0),
        const Vec3(0, 1, 0),
        const Vec3(1, 0, 0),
        const Vec3(0, 0, -1),
        Vec3(0.3, 0.5, -0.81).normalized(), // a tilted face
      ];
      for (final n in normals) {
        for (var i = 0; i < 8; i++) {
          for (final pol in const [0.2, 0.9, 1.57, 2.4, 3.0]) {
            final p = PartModel('P');
            p.camera
              ..az = -math.pi + i * math.pi / 4
              ..pol = pol;
            final fr = faceFrame(n * 4, n);
            if (fr.n.dot(p.camera.dir) < 0) continue; // the far-side branch
            app.orientToSurface(p, fr);
            expectSameBasis(p.camera, fr, 'n=$n az=$i pol=$pol');
          }
        }
      }
    });

    test('a face pick leaves nothing for the swing to rotate', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      p.camera
        ..az = -2.44
        ..pol = 2.43;
      app.startPartSketch();
      final fr = faceFrame(const Vec3(0, 0, 0), const Vec3(0, -1, 0));
      app.facePicked(fr);
      expect(app.activeChild, isNotNull, reason: 'the sketch opened');
      expectSameBasis(p.camera, fr, 'after facePicked');
    });

    test('reopening a face sketch from the browser does not aim at the front',
        () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      app.startPartSketch();
      final fr = faceFrame(const Vec3(0, 0, 0), const Vec3(0, -1, 0));
      app.facePicked(fr);
      final name = app.activeChild!.name;
      app.finishPartSketch();
      // Somewhere else entirely, the way an orbit leaves it.
      p.camera
        ..az = 1.1
        ..pol = 0.7
        ..roll = 0.3;
      app.openChildSketch(name);
      expectSameBasis(p.camera, fr, 'after openChildSketch');
    });

    test('an origin-plane sketch still opens on its origin-plane view',
        () async {
      // M211 only changes the face/work-plane path; 'xy' and friends keep the
      // hard-coded targets every earlier test measures.
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      app.startPartSketch();
      app.planePicked('xz');
      final name = app.activeChild!.name;
      app.finishPartSketch();
      p.camera
        ..az = 1.1
        ..pol = 0.7;
      app.openChildSketch(name);
      final (a, pl) = planeCameraTarget('xz');
      expect(p.camera.az, closeTo(a, 1e-9));
      expect(p.camera.pol, closeTo(pl, 1e-9));
    });
  });
}
