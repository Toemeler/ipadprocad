// M76 — projecting 3D model edges into a sketch.
//
// Inventor's semantics, which drive every assertion here:
//  * projected geometry is a LINK, not a copy: change the parent and it
//    follows;
//  * it is reference geometry - selectable, never edited, so the solver must
//    treat it as fixed (handled by the existing _withProjectionPins);
//  * an ORPHAN (source gone) does not vanish - it freezes as fixed curves.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';

/// A solid with two straight edges in the z=0 plane:
///   edge 0: (0,0,0)->(10,0,0)      edge 1: (0,5,0)->(0,5,4)
KernelSolid _solid() {
  final pts = Float64List.fromList(
      const [0, 0, 0, 10, 0, 0, /**/ 0, 5, 0, 0, 5, 4]);
  return KernelSolid(
      OcctMeshData(
        Float64List(0),
        Float64List(0),
        Int32List(0),
        Int32List.fromList(const [0, 2, 4]), // edgeStarts
        pts, // edgePoints
      ),
      1.0,
      null);
}

PlaneFrame _xy() => const PlaneFrame(
    'xy', Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1), Vec3.zero);

PartModel _part({bool visible = true, bool withSolid = true}) {
  final p = PartModel('Part1');
  final f = ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: 'Sketch1',
      profiles: const []);
  f.visible = visible;
  if (withSolid) f.solid = _solid();
  p.features.add(f);
  return p;
}

void main() {
  group('enumerating projectable edges', () {
    test('flattens every edge of every visible solid onto the plane', () {
      final e = partEdges(_part(), _xy());
      expect(e.length, 2);
      expect(e[0].index, 0);
      expect(e[0].pts, [const Offset(0, 0), const Offset(10, 0)]);
      // the second edge runs out of plane: orthogonal projection collapses it
      expect(e[1].pts, [const Offset(0, 5), const Offset(0, 5)]);
    });

    test('hidden and consumed features contribute nothing', () {
      expect(partEdges(_part(visible: false), _xy()), isEmpty);
      final p = _part();
      p.features.single.consumedByJoin = true;
      expect(partEdges(p, _xy()), isEmpty);
      expect(partEdges(_part(withSolid: false), _xy()), isEmpty);
    });
  });

  group('the projected entity', () {
    test('two points become a LINE tagged with its source edge', () {
      final g = geoForProjectedEdge(
          const [Offset(1, 2), Offset(3, 4)], 7, 'Layer 1');
      expect(g.type, Geo.line);
      expect(g.proj, Geo.projSolid);
      expect(g.projSeg, 7);
      expect(g.isProjection, isTrue);
      expect(g.data, [1.0, 2.0, 3.0, 4.0]);
    });

    test('more points become an OPEN polyline', () {
      final g = geoForProjectedEdge(
          const [Offset(0, 0), Offset(1, 0), Offset(1, 1)], 2, 'Layer 1');
      expect(g.type, Geo.polyline);
      expect(g.data[0], 0, reason: 'open, not closed');
      expect(g.data[1], 3);
      expect(g.proj, Geo.projSolid);
    });
  });

  group('staying in sync with the model', () {
    test('a moved source moves the projection', () {
      final p = _part();
      final gs = <Geo>[
        geoForProjectedEdge(
            const [Offset(0, 0), Offset(10, 0)], 0, 'Layer 1')
      ];
      // model changes: the edge now ends at x=20
      p.features.single.solid = KernelSolid(
          OcctMeshData(
            Float64List(0),
            Float64List(0),
            Int32List(0),
            Int32List.fromList(const [0, 2]),
            Float64List.fromList(const [0, 0, 0, 20, 0, 0]),
          ),
          1.0,
          null);
      expect(syncSolidProjections(gs, p, _xy()), isTrue);
      expect(gs.single.data, [0.0, 0.0, 20.0, 0.0]);
      expect(gs.single.proj, Geo.projSolid, reason: 'still linked');
    });

    test('an unchanged model reports no change', () {
      final p = _part();
      final gs = <Geo>[
        geoForProjectedEdge(
            const [Offset(0, 0), Offset(10, 0)], 0, 'Layer 1')
      ];
      expect(syncSolidProjections(gs, p, _xy()), isFalse);
    });

    test('an ORPHAN freezes in place instead of disappearing', () {
      final gs = <Geo>[
        geoForProjectedEdge(
            const [Offset(0, 0), Offset(10, 0)], 99, 'Layer 1')
      ];
      expect(syncSolidProjections(gs, _part(), _xy()), isTrue);
      expect(gs.length, 1, reason: 'Inventor keeps the curve');
      expect(gs.single.proj, Geo.projBroken);
      expect(gs.single.data, [0.0, 0.0, 10.0, 0.0],
          reason: 'frozen exactly where it was');
    });

    test('ordinary sketch geometry is left completely alone', () {
      final gs = <Geo>[
        const Geo(Geo.line, [0, 0, 1, 1]),
        const Geo(Geo.circle, [0, 0, 5]),
      ];
      expect(syncSolidProjections(gs, _part(), _xy()), isFalse);
      expect(gs[0].data, [0, 0, 1, 1]);
    });
  });

  group('picking', () {
    test('finds the nearest edge inside the tolerance, else null', () {
      final e = partEdges(_part(), _xy());
      expect(pickPartEdge(e, const Offset(5, 0.05), 0.5), 0);
      expect(pickPartEdge(e, const Offset(5, 9), 0.5), isNull);
      expect(pickPartEdge(const [], const Offset(0, 0), 1), isNull);
    });
  });
}
