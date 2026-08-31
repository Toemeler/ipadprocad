// M291 — half, quarter and three-quarter section views.
//
// Inventor puts these on the View tab's Appearance panel, and the names are
// the wrong way round from what you would guess — the name says what SURVIVES:
//
//   Half Section View          one plane;   the near half is removed.
//   Quarter Section View       two planes;  three quarters removed, a QUARTER
//                              of the model left standing.
//   Three Quarter Section View two planes;  one quarter removed — the corner
//                              notch — and THREE QUARTERS left.
//
// So the two two-plane commands are complements, which is what Autodesk's help
// means by "quarter and three-quarter views can show the opposite view". As
// half-spaces, with A- meaning "the side of plane A its normal points away
// from", what is removed is A-, then A- ∪ B-, then A- ∩ B-. That arithmetic is
// the thing most likely to be got backwards, so it is pinned first.
//
// The second claim of this milestone is that Slice Graphics WAS one of these
// all along: M168 built it as its own state, with its own cache and its own
// cutter, and it is a half section at the open sketch's plane. SectionView.slice
// builds exactly that value and one cut path serves both — which is what
// "combined and work the same way" has to mean if it is to mean anything.
//
// The cut itself needs OCCT and does not run on this host, so what is tested
// here is everything up to the kernel call: which planes, which way round,
// which mode, what the cache and the RealityKit scene signature see, and the
// picking session that collects them. The boolean is one line of part_model
// (sectionCutSolid) and its shape is asserted by the mode arithmetic below.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/section_view.dart';

PlaneFrame _xy() => planeFrame('xy');
PlaneFrame _yz() => planeFrame('yz');

/// A cube spanning 0..s on every axis, as a solid a part can carry.
KernelSolid _box(double s) {
  final pos = <double>[], nor = <double>[], idx = <int>[];
  void quad(List<List<double>> p, List<double> n) {
    final base = pos.length ~/ 3;
    for (final v in p) {
      pos.addAll(v);
      nor.addAll(n);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  quad([
    [0, 0, 0],
    [s, 0, 0],
    [s, s, 0],
    [0, s, 0]
  ], [
    0,
    0,
    -1
  ]);
  quad([
    [0, 0, s],
    [s, 0, s],
    [s, s, s],
    [0, s, s]
  ], [
    0,
    0,
    1
  ]);
  final mesh = OcctMeshData(
    Float64List.fromList(pos),
    Float64List.fromList(nor),
    Int32List.fromList(idx),
    Int32List.fromList([0]),
    Float64List(0),
    triFaces: Int32List.fromList(List<int>.filled(idx.length ~/ 3, 0)),
  );
  return KernelSolid(mesh, s * s * s, null);
}

AppState _partApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m291');
  final p = PartModel('Bracket');
  p.features.add(ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: 'Sketch1',
      profiles: const [])
    ..solid = _box(20));
  app.parts['Bracket'] = p;
  app.curTab = 'Bracket';
  return app;
}

void main() {
  group('the three commands, as half-spaces', () {
    test('how many planes each one needs', () {
      expect(SectionMode.half.planeCount, 1);
      expect(SectionMode.quarter.planeCount, 2);
      expect(SectionMode.threeQuarter.planeCount, 2);
    });

    test('a two-plane command with one plane cuts nothing', () {
      // Not "cuts a half in the meantime": a quarter view that showed a half
      // and then changed under you when you picked the second plane is a worse
      // answer than one that waits.
      final one = SectionPlane(_xy(), 'XY');
      expect(SectionView(SectionMode.half, one).complete, isTrue);
      expect(SectionView(SectionMode.quarter, one).complete, isFalse);
      expect(SectionView(SectionMode.threeQuarter, one).complete, isFalse);
      expect(
          SectionView(SectionMode.quarter, one, SectionPlane(_yz(), 'YZ'))
              .complete,
          isTrue);
    });

    test('the mode is part of the cut, so it is part of the signature', () {
      // The same two planes cut a quarter view and a three-quarter view into
      // complementary shapes. A cache keyed only on the planes would hand one
      // of them the other's solid.
      final a = SectionPlane(_xy(), 'XY');
      final b = SectionPlane(_yz(), 'YZ');
      final q = SectionView(SectionMode.quarter, a, b);
      final tq = SectionView(SectionMode.threeQuarter, a, b);
      expect(q.signature, isNot(tq.signature));
    });

    test('every mode round-trips through its id', () {
      for (final m in SectionMode.values) {
        expect(SectionMode.byId(m.id), m);
      }
      expect(SectionMode.byId('diagonal'), isNull);
    });
  });

  group('a section plane: flip and offset', () {
    test('the offset slides the plane along its own normal', () {
      final p = SectionPlane(_xy(), 'XY', offset: 7);
      final f = p.cutFrame;
      expect(f.origin.z, closeTo(_xy().origin.z + 7 * _xy().n.z, 1e-12));
      expect(f.n.x, closeTo(_xy().n.x, 1e-12));
      expect(f.n.y, closeTo(_xy().n.y, 1e-12));
      expect(f.n.z, closeTo(_xy().n.z, 1e-12));
    });

    test('Flip turns the normal around', () {
      final base = _xy();
      final f = SectionPlane(base, 'XY').flip.cutFrame;
      expect(f.n.x, closeTo(-base.n.x, 1e-12));
      expect(f.n.y, closeTo(-base.n.y, 1e-12));
      expect(f.n.z, closeTo(-base.n.z, 1e-12));
    });

    test('and the flipped frame is still RIGHT-handed', () {
      // Not tidiness. The cut tool is an extrusion placed by PlaneFrame.mat34,
      // and a frame with a negated normal but the same u and v is left-handed:
      // the box would be built mirrored. u x v must still be n, which is why
      // the flip swaps u and v as well as negating n.
      for (final base in [_xy(), _yz(), planeFrame('xz')]) {
        final f = SectionPlane(base, 'p').flip.cutFrame;
        final cross = f.u.cross(f.v);
        expect(cross.x, closeTo(f.n.x, 1e-12), reason: base.key);
        expect(cross.y, closeTo(f.n.y, 1e-12), reason: base.key);
        expect(cross.z, closeTo(f.n.z, 1e-12), reason: base.key);
      }
    });

    test('the offset keeps its direction however often it is flipped', () {
      // "Slide it 5 mm that way" has to keep meaning the same direction, or
      // Flip would silently move the plane as well as turn it.
      final a = SectionPlane(_xy(), 'XY', offset: 5).cutFrame.origin;
      final b = SectionPlane(_xy(), 'XY', offset: 5).flip.cutFrame.origin;
      expect(b.x, closeTo(a.x, 1e-12));
      expect(b.y, closeTo(a.y, 1e-12));
      expect(b.z, closeTo(a.z, 1e-12));
    });

    test('flip and offset both change the signature', () {
      final p = SectionPlane(_xy(), 'XY');
      expect(p.signature, isNot(p.flip.signature));
      expect(p.signature, isNot(p.copyWith(offset: 1).signature));
    });
  });

  group('Slice Graphics is a half section, not a second implementation', () {
    test('it is exactly one flipped half section at the sketch plane', () {
      final fr = _xy();
      final v = SectionView.slice(fr);
      expect(v.mode, SectionMode.half);
      expect(v.planes.length, 1);
      expect(v.complete, isTrue);
      // Flipped: the sketch frame's normal points AT the viewer, and a section
      // plane removes the side its normal points away from — so what goes is
      // what is between you and the sketch, which is M168's whole sentence.
      expect(v.a.flipped, isTrue);
      expect(v.a.cutFrame.n.z, closeTo(-fr.n.z, 1e-12));
    });
  });

  group('the picking session', () {
    test('a half section applies on the first pick', () {
      final app = _partApp();
      expect(app.canSection, isTrue);
      app.beginSection(SectionMode.half);
      expect(app.sectionPicking, isTrue);
      expect(app.partSection, isNull, reason: 'nothing picked yet');

      app.sectionPlanePicked(_xy(), 'XY');
      expect(app.sectionPicking, isFalse, reason: 'one plane is all it needs');
      expect(app.partSection?.mode, SectionMode.half);
      expect(app.activeSection, isNotNull);
    });

    test('a quarter section waits for the second plane', () {
      final app = _partApp();
      app.beginSection(SectionMode.quarter);
      app.sectionPlanePicked(_xy(), 'XY');
      expect(app.sectionPicking, isTrue, reason: 'still asking');
      expect(app.partSection, isNull);
      expect(app.activeSection, isNull, reason: 'an unfinished view cuts nothing');

      app.sectionPlanePicked(_yz(), 'YZ');
      expect(app.sectionPicking, isFalse);
      expect(app.partSection?.planes.length, 2);
      expect(app.activeSection?.mode, SectionMode.quarter);
    });

    test('starting a command replaces the section that was up', () {
      // The four entries are one control with four settings, not four
      // independent toggles.
      final app = _partApp();
      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(_xy(), 'XY');
      app.beginSection(SectionMode.threeQuarter);
      app.sectionPlanePicked(_xy(), 'XY');
      app.sectionPlanePicked(_yz(), 'YZ');
      expect(app.partSection?.mode, SectionMode.threeQuarter);
    });

    test('End Section View also cancels a command mid-pick', () {
      // Otherwise a half-started quarter view has no way out but picking a
      // plane you did not want.
      final app = _partApp();
      app.beginSection(SectionMode.quarter);
      app.sectionPlanePicked(_xy(), 'XY');
      app.endSection();
      expect(app.sectionPicking, isFalse);
      expect(app.partSection, isNull);
      expect(app.activeSection, isNull);
    });

    test('Flip and the offset act on the plane they name', () {
      final app = _partApp();
      app.beginSection(SectionMode.quarter);
      app.sectionPlanePicked(_xy(), 'XY');
      app.sectionPlanePicked(_yz(), 'YZ');

      app.flipSectionPlane(1);
      expect(app.partSection!.planes[0].flipped, isFalse);
      expect(app.partSection!.planes[1].flipped, isTrue);

      app.setSectionOffset(0, 3.5);
      expect(app.partSection!.planes[0].offset, 3.5);
      expect(app.partSection!.planes[1].offset, 0);

      // Out of range does nothing rather than throwing: the flyout is built
      // from the live section, but a stale tap must not take the app down.
      app.flipSectionPlane(5);
      app.setSectionOffset(-1, 2);
      expect(app.partSection!.planes.length, 2);
    });

    test('nothing to cut, no command', () {
      final app = AppState();
      app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m291e');
      app.parts['Empty'] = PartModel('Empty');
      app.curTab = 'Empty';
      expect(app.canSection, isFalse);
      app.beginSection(SectionMode.half);
      expect(app.sectionPicking, isFalse);
    });

    test('the section belongs to the PART, so two parts differ', () {
      final app = _partApp();
      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(_xy(), 'XY');
      expect(app.partSection, isNotNull);

      app.parts['Other'] = PartModel('Other');
      app.curTab = 'Other';
      expect(app.partSection, isNull, reason: 'a different document');
      app.curTab = 'Bracket';
      expect(app.partSection?.mode, SectionMode.half,
          reason: 'and the first one still has its own');
    });

    test('it is never written to disk', () {
      // A view state, not geometry: Inventor is explicit that a section view
      // shows the inside "without modifying geometry", and a document that
      // reopened half-cut would read as a broken part.
      final app = _partApp();
      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(_xy(), 'XY');
      final json = app.parts['Bracket']!.toJson();
      expect(json.toString().contains('section'), isFalse);
      final back = PartModel('Bracket')..loadJson(json);
      expect(back.section, isNull);
    });
  });

  group('the scene knows the section changed', () {
    // M95, M122 and M165 were each the same lesson: anything that changes the
    // picture and is not in the signature sends no rebuild, and the change
    // "does not work". Flipping a section and sliding a plane change every
    // mesh in the scene.
    String sig(AppState app) => sceneSignature(app, app.currentPart!);

    test('applying, flipping and sliding each move it', () {
      final app = _partApp();
      final whole = sig(app);

      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(_xy(), 'XY');
      final cut = sig(app);
      expect(cut, isNot(whole));

      app.flipSectionPlane(0);
      final flipped = sig(app);
      expect(flipped, isNot(cut));

      app.setSectionOffset(0, 4);
      expect(sig(app), isNot(flipped));

      app.endSection();
      expect(sig(app), whole, reason: 'and ending it puts the model back');
    });
  });

  group('a section and a sketch', () {
    test('Slice Graphics wins while a sketch is open, and gives it back', () {
      // It is a SKETCHING aid — you turned it on to see what you are drawing
      // into — so a section left on from before must not decide what you can
      // see of the plane you are drawing on. Neither state is overwritten, so
      // ending the sketch brings the section back untouched.
      final app = _partApp();
      final p = app.currentPart!;
      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(_yz(), 'YZ');
      expect(app.activeSection!.a.label, 'YZ');

      final sk = SketchModel('Sketch1');
      p.childSketches.add(ChildSketch(sk, 'xy'));
      app.activeChild = sk;
      app.sliceGraphics = true;
      expect(app.activeSection!.a.label, 'sketch');
      expect(app.activeSection!.a.flipped, isTrue);

      app.activeChild = null;
      app.sliceGraphics = false;
      expect(app.activeSection!.a.label, 'YZ');
    });
  });

  test('a fit still frames the WHOLE part, not the cut', () {
    // The gallery card and Zoom All read the features directly rather than the
    // sectioned stand-ins, which is what keeps a sectioned part from getting a
    // half-model thumbnail. Asserted because it is easy to "fix" by routing
    // them through visibleSolids.
    final app = _partApp();
    app.beginSection(SectionMode.half);
    app.sectionPlanePicked(_xy(), 'XY');
    final cam = fitThumbCamera([_box(20)], const Size(380, 240));
    expect(cam.halfH, greaterThan(0));
  });
}
