// M414 — "why is the workplane green on windows, and it seems it is way
// bigger than the stuff that is there" (#39).
//
// A PLANE IS NOT SIZED BY WHAT IS DRAWN ON IT. The extent walk counts visible
// sketch geometry (M83, and rightly: the first sketch exists before the first
// solid), but a sketch drawn on a WORK plane then sized the work plane it was
// drawn on. In the report that made a plane 343 x 664 mm around a part 50 x
// 352 mm, all of the difference coming from lines on the plane itself — and a
// plane that covers the viewport is a plane the pointer is always hovering,
// which is where the green came from.
//
// What is pinned here:
//   * a sketch ON a work plane does not size that work plane;
//   * it still sizes an ORIGIN plane — M83's rule is untouched;
//   * a sketch on ANOTHER plane still counts towards the work plane;
//   * a work plane with nothing but its own sketch still frames the sketch,
//     rather than collapsing to the empty-part cube;
//   * the RealityKit payload carries the same rectangle the painter and the
//     hit test use (M83's lesson: they must not drift apart);
//   * the memo answers the same thing twice and notices a real change.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';

/// A solid whose mesh is a single triangle at the given world corners — enough
/// for the bounds walk, which only reads positions.
KernelSolid _tri(List<double> pts) => KernelSolid(
      OcctMeshData(
        Float64List.fromList(pts),
        Float64List.fromList(List<double>.filled(pts.length, 0)),
        Int32List.fromList([0, 1, 2]),
        Int32List.fromList([0]),
        Float64List(0),
      ),
      1,
      null,
    );

/// A part occupying x 0..60, y 0..40, z 0..5, with an XY-parallel work plane
/// 10 mm up. The plane's own axes are u = +X, v = +Y.
PartModel _part({bool withSolid = true}) {
  final p = PartModel('P');
  if (withSolid) {
    p.features.add(ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: 'Sketch1',
      profiles: const [],
    )..solid = _tri([0, 0, 0, 60, 0, 5, 60, 40, 5]));
  }
  final base = planeFrame('xy');
  p.workPlanes.add(WorkPlane('Work Plane1', 1, WorkPlaneKind.offset,
      'Offset from XY', offsetPlaneFrame(base, 10),
      base: base, offset: 10));
  return p;
}

/// A visible sketch carrying one long line, on [plane] (with [face] when that
/// is 'face').
void _sketchOn(PartModel p, String plane,
    {PlaneFrame? face, List<double> line = const [0, 0, 400, 300]}) {
  final m = SketchModel('S${p.childSketches.length + 1}');
  m.geometry.add(Geo(Geo.line, line));
  p.childSketches.add(ChildSketch(m, plane, face));
}

PlaneFrame get _wpFrame => offsetPlaneFrame(planeFrame('xy'), 10);

void main() {
  group('a sketch on the plane does not size the plane', () {
    test('the work plane keeps the rectangle it had without the sketch', () {
      final p = _part();
      final bare = workPlaneRect(p, p.workPlanes.single.frame);
      _sketchOn(p, 'face', face: _wpFrame);
      expect(workPlaneRect(p, p.workPlanes.single.frame), bare,
          reason: 'the line on the plane is 400 x 300 and changes nothing');
    });

    test('and it is the PART it frames, not the empty-part default', () {
      final p = _part();
      _sketchOn(p, 'face', face: _wpFrame);
      final (uMin, uMax, vMin, vMax) =
          workPlaneRect(p, p.workPlanes.single.frame);
      final padX = 60 * kOriginExtentPadFrac, padY = 40 * kOriginExtentPadFrac;
      expect(uMax - uMin, closeTo(60 + 2 * padX, 1e-9));
      expect(vMax - vMin, closeTo(40 + 2 * padY, 1e-9));
    });

    test('a sketch on ANOTHER plane still counts', () {
      final p = _part();
      final bare = workPlaneRect(p, p.workPlanes.single.frame);
      _sketchOn(p, 'xy'); // z = 0, not the plane at z = 10
      final grown = workPlaneRect(p, p.workPlanes.single.frame);
      expect(grown.$2, greaterThan(bare.$2),
          reason: 'that drawing IS part of the model the plane frames');
    });

    test('an ORIGIN plane is unchanged: M83 still counts its sketch', () {
      final p = _part();
      final bare = originPlaneRect(p, 'xy');
      _sketchOn(p, 'xy');
      expect(originPlaneRect(p, 'xy').$2, greaterThan(bare.$2));
    });
  });

  group('the fallback', () {
    test('a plane whose sketch is all there is still frames the sketch', () {
      final p = _part(withSolid: false);
      _sketchOn(p, 'face', face: _wpFrame);
      final (uMin, uMax, _, _) = workPlaneRect(p, p.workPlanes.single.frame);
      expect(uMax - uMin, greaterThan(2 * kOriginExtentDefault),
          reason: 'measuring nothing would give the 10 mm default cube');
      expect(uMax, greaterThan(300));
    });

    test('an empty part gives the default cube, as it always did', () {
      final p = _part(withSolid: false);
      final (uMin, uMax, vMin, vMax) =
          workPlaneRect(p, p.workPlanes.single.frame);
      expect(uMin, -kOriginExtentDefault);
      expect(uMax, kOriginExtentDefault);
      expect(vMin, -kOriginExtentDefault);
      expect(vMax, kOriginExtentDefault);
    });
  });

  group('drawn, sent and clickable are one rectangle', () {
    test('the payload carries exactly workPlaneRect', () {
      final app = AppState();
      final p = _part();
      _sketchOn(p, 'face', face: _wpFrame);
      final w = (buildScenePayload(app, p)['planes'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((m) => m['key'] == 'wp:1');
      final (uMin, uMax, vMin, vMax) =
          workPlaneRect(p, p.workPlanes.single.frame);
      expect(w['uMin'], uMin);
      expect(w['uMax'], uMax);
      expect(w['vMin'], vMin);
      expect(w['vMax'], vMax);
    });
  });

  group('the memo', () {
    test('the same question twice is one walk, a real change is not', () {
      final p = _part();
      _sketchOn(p, 'face', face: _wpFrame);
      final f = p.workPlanes.single.frame;
      final first = partContentBoundsOffPlane(p, f);
      expect(p.offPlaneCache.length, 1);
      expect(partContentBoundsOffPlane(p, f), first);
      expect(p.offPlaneCache.length, 1);
      // A bigger solid must invalidate.
      p.features.first.solid = _tri([0, 0, 0, 600, 0, 5, 600, 400, 5]);
      final grown = partContentBoundsOffPlane(p, f);
      expect(grown!.$2.x, greaterThan(first!.$2.x));
    });

    test('two planes get two entries, not one shared answer', () {
      final p = _part();
      final a = p.workPlanes.single.frame;
      final b = offsetPlaneFrame(planeFrame('xy'), 25);
      partContentBoundsOffPlane(p, a);
      partContentBoundsOffPlane(p, b);
      expect(p.offPlaneCache.length, 2);
    });
  });

  group('coplanarity', () {
    test('same plane either way round, different offset is a different plane',
        () {
      final f = _wpFrame;
      expect(framesCoplanar(f, f), isTrue);
      final flipped = PlaneFrame('face', f.u, f.v * -1, f.n * -1, f.origin);
      expect(framesCoplanar(f, flipped), isTrue,
          reason: 'a flipped normal is the same plane in space');
      expect(framesCoplanar(f, offsetPlaneFrame(planeFrame('xy'), 10.001)),
          isFalse);
      expect(framesCoplanar(f, planeFrame('yz')), isFalse);
    });
  });
}
