// M104 — picking B-Rep edges in 3D.
//
// The whole point of part_pick.dart living outside the widget is that this
// runs without a device: the "camera" here is two closures, so every
// tie-break can be set up exactly and asserted.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_pick.dart';

/// A mesh carrying only edges — pickEdge never looks at triangles.
///
/// [edges] is a list of polylines in world space; [topo] the topological id
/// of each (0 = "not mapped", which the picker must refuse).
OcctMeshData _edgeMesh(List<List<Vec3>> edges,
    {List<int>? topo, List<int>? kinds, List<double>? radii}) {
  final starts = <int>[0];
  final pts = <double>[];
  for (final e in edges) {
    for (final p in e) {
      pts.addAll([p.x, p.y, p.z]);
    }
    starts.add(pts.length ~/ 3);
  }
  final curves = Float64List(16 * edges.length);
  for (var i = 0; i < edges.length; i++) {
    curves[16 * i] = (kinds == null ? 1 : kinds[i]).toDouble();
    curves[16 * i + 10] = radii == null ? 0 : radii[i];
  }
  return OcctMeshData(
    Float64List(0),
    Float64List(0),
    Int32List(0),
    Int32List.fromList(starts),
    Float64List.fromList(pts),
    edgeCurves: curves,
    edgeIds: Int32List.fromList(
        topo ?? [for (var i = 0; i < edges.length; i++) i + 1]),
  );
}

/// Orthographic "camera" looking down -Z: screen = (x, y), depth = -z, so a
/// LARGER z is nearer. Simple enough that every expectation below is obvious.
Offset _proj(Vec3 v) => Offset(v.x, v.y);
double _depth(Vec3 v) => -v.z;

void main() {
  group('hit and miss', () {
    test('a tap on the edge hits it', () {
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ]);
      final hit = pickEdge([m], _proj, _depth, const Offset(50, 0));
      expect(hit, isNotNull);
      expect(hit!.displayEdge, 0);
      expect(hit.topoEdge, 1);
      expect(hit.pixels, closeTo(0, 1e-9));
    });

    test('a tap just inside the tolerance still hits', () {
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ]);
      expect(pickEdge([m], _proj, _depth, const Offset(50, 13)), isNotNull);
    });

    test('a tap outside the tolerance misses', () {
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ]);
      expect(pickEdge([m], _proj, _depth, const Offset(50, 40)), isNull);
    });

    test('a tap past the END of the segment measures to the endpoint', () {
      // not to the infinite line — otherwise every edge would extend forever
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ]);
      expect(pickEdge([m], _proj, _depth, const Offset(140, 0)), isNull);
      expect(pickEdge([m], _proj, _depth, const Offset(108, 0)), isNotNull);
    });

    test('an edge with no topological id is refused', () {
      // Without the id there is nothing to hand occt_fillet_edges; offering
      // the edge would produce a fillet on an arbitrary one.
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ], topo: [0]);
      expect(pickEdge([m], _proj, _depth, const Offset(50, 0)), isNull);
    });

    test('an empty mesh list is a miss, not a crash', () {
      expect(pickEdge(const [], _proj, _depth, Offset.zero), isNull);
    });
  });

  group('tie-breaking', () {
    test('the NEARER edge wins even when it is further in pixels', () {
      // This is the whole reason depth beats pixels: a near silhouette and a
      // far edge project within a few pixels of each other constantly.
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)], // far  (z = 0)
        [Vec3(0, 6, 50), Vec3(100, 6, 50)], // near (z = 50), 6 px away
      ]);
      final hit = pickEdge([m], _proj, _depth, const Offset(50, 0));
      expect(hit, isNotNull);
      expect(hit!.displayEdge, 1, reason: 'the visible edge must win');
    });

    test('at equal depth the closer one in pixels wins', () {
      final m = _edgeMesh([
        [Vec3(0, 10, 0), Vec3(100, 10, 0)],
        [Vec3(0, 2, 0), Vec3(100, 2, 0)],
      ]);
      final hit = pickEdge([m], _proj, _depth, const Offset(50, 0));
      expect(hit!.displayEdge, 1);
    });

    test('picks across several meshes and reports which one', () {
      final a = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ]);
      final b = _edgeMesh([
        [Vec3(0, 0, 80), Vec3(100, 0, 80)]
      ]);
      final hit = pickEdge([a, b], _proj, _depth, const Offset(50, 0));
      expect(hit!.meshIndex, 1, reason: 'mesh b is nearer');
    });
  });

  group('fingerprint', () {
    test('the midpoint is the ARC-LENGTH middle, not the middle index', () {
      // Points bunched at the start, as a discretiser does on a curve. The
      // middle INDEX is at x = 3; the middle by length is at x = 50.
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(2, 0, 0), Vec3(3, 0, 0),
         Vec3(100, 0, 0)]
      ]);
      final hit = pickEdge([m], _proj, _depth, const Offset(50, 0));
      expect(hit!.mid.x, closeTo(50, 1e-9));
      expect(hit.length, closeTo(100, 1e-9));
    });

    test('toSel stores the midpoint, never the tap location', () {
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ]);
      // tap near one END
      final hit = pickEdge([m], _proj, _depth, const Offset(5, 0));
      expect(hit!.point.x, closeTo(5, 1e-9), reason: 'the hit is where I tapped');
      final sel = hit.toSel();
      expect(sel.mx, closeTo(50, 1e-9),
          reason: 'the FINGERPRINT is the midpoint — bestMatch compares '
              'against occt_shape_edge_info, whose anchor is the midpoint');
      expect(sel.length, closeTo(100, 1e-9));
    });

    test('the stored fingerprint re-matches the same edge', () {
      // end to end: pick, store, then resolve against a live edge list
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(100, 0, 0)]
      ]);
      final sel = pickEdge([m], _proj, _depth, const Offset(20, 0))!.toSel();
      final live = [
        OcctEdgeInfo(1, 1, 50, 0, 0, 1, 0, 0, 100, 0, 2),
        OcctEdgeInfo(2, 1, 50, 80, 0, 1, 0, 0, 100, 0, 2),
      ];
      expect(sel.bestMatch(live)?.index, 1);
    });

    test('curve type and radius come through', () {
      final m = _edgeMesh([
        [Vec3(0, 0, 0), Vec3(10, 0, 0)]
      ], kinds: [2], radii: [7.5]);
      final sel = pickEdge([m], _proj, _depth, const Offset(5, 0))!.toSel();
      expect(sel.kind, 2);
      expect(sel.radius, closeTo(7.5, 1e-9));
    });
  });

  group('selection state', () {
    test('tapping an edge twice removes it (Inventor toggle)', () {
      final app = AppState();
      app.beginPickEdges();
      final sel = EdgeSel(0, 0, 0, 10, 1, 0);
      app.toggleEdgePick(4, sel);
      expect(app.edgeIsPicked(4), isTrue);
      expect(app.pickedEdges.length, 1);
      app.toggleEdgePick(4, sel);
      expect(app.edgeIsPicked(4), isFalse);
      expect(app.pickedEdges, isEmpty);
    });

    test('nothing is selected unless the pick is armed', () {
      final app = AppState();
      app.toggleEdgePick(4, EdgeSel(0, 0, 0, 10, 1, 0));
      expect(app.pickedEdges, isEmpty);
    });

    test('cancelling clears the whole set', () {
      final app = AppState();
      app.beginPickEdges();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 10, 1, 0));
      app.toggleEdgePick(2, EdgeSel(1, 0, 0, 10, 1, 0));
      expect(app.pickedEdges.length, 2);
      app.cancelPickEdges();
      expect(app.pickingEdges, isFalse);
      expect(app.pickedEdges, isEmpty);
      expect(app.pickedEdgeIds, isEmpty);
    });

    test('the id list and the fingerprint list stay in step', () {
      final app = AppState();
      app.beginPickEdges();
      for (var i = 1; i <= 3; i++) {
        app.toggleEdgePick(i, EdgeSel(i.toDouble(), 0, 0, 10, 1, 0));
      }
      app.toggleEdgePick(2, EdgeSel(2, 0, 0, 10, 1, 0)); // remove the middle
      expect(app.pickedEdgeIds, [1, 3]);
      expect(app.pickedEdges.map((e) => e.mx).toList(), [1.0, 3.0],
          reason: 'radii are indexed against this list');
    });
  });
}
