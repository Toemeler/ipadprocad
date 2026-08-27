// M279 — projecting a whole face.
//
// "Im Moment kann ich mit dem Projizieren-Tool in einer Skizze nur einzelne
// Kanten projizieren. In Inventor kann ich auch ganze Flächen auswählen um
// jede Kante dieser Fläche zu projizieren."
//
// Inventor's Project Geometry takes edges, vertices, work features AND faces;
// a face brings across every edge of its boundary — the outer loop and every
// inner one, so a plate with four holes projects as the outline plus four
// circles in one pick.
//
// The interesting half is not the command, it is "which edges bound this
// face". OCCT can answer that exactly, and the shim does not expose it, so it
// is derived from the mesh the app already holds. These tests are about that
// derivation being EXACT rather than nearly right:
//
//   * a triangle side used by one triangle OF THIS FACE is on its boundary;
//     one used by two is interior. Integer pairs, no tolerance.
//   * an edge belongs to the face when EVERY point of it is a boundary vertex.
//     Every point, because the neighbouring face's edges touch this one at
//     both ends and endpoints alone would take them too.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/face_project.dart';
import 'package:prototype/part_model.dart';

/// A unit square in the z = 0 plane as ONE mesh face (two triangles), plus a
/// second face standing on its +x side so there is a neighbour to be confused
/// with.
///
///   face 0: (0,0,0) (1,0,0) (1,1,0) (0,1,0)      — flat, in z = 0
///   face 1: (1,0,0) (1,0,1) (1,1,1) (1,1,0)      — upright, in x = 1
///
/// The two share the edge (1,0,0)-(1,1,0), which is the case the "every point"
/// rule exists for.
({Float64List pos, Int32List idx, Int32List tf}) _twoFaces() {
  final pos = Float64List.fromList([
    0, 0, 0, // 0
    1, 0, 0, // 1
    1, 1, 0, // 2
    0, 1, 0, // 3
    1, 0, 1, // 4
    1, 1, 1, // 5
  ]);
  final idx = Int32List.fromList([
    0, 1, 2, 0, 2, 3, // face 0
    1, 4, 5, 1, 5, 2, // face 1
  ]);
  final tf = Int32List.fromList([0, 0, 1, 1]);
  return (pos: pos, idx: idx, tf: tf);
}

/// Display edges as flat polylines, given as lists of vertex indices into
/// [pos]. Mirrors the kernel's edgeStarts/edgePoints pair.
(Int32List, Float64List) _edges(Float64List pos, List<List<int>> polys) {
  final starts = <int>[0];
  final pts = <double>[];
  var n = 0;
  for (final p in polys) {
    for (final v in p) {
      pts.addAll([pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]]);
      n++;
    }
    starts.add(n);
  }
  return (Int32List.fromList(starts), Float64List.fromList(pts));
}

void main() {
  group('which edges bound a face', () {
    test('the four sides of the flat face, and not the upright one\'s', () {
      final m = _twoFaces();
      // 0: the shared side          1: the flat face's far side
      // 2: the upright face's top   3: a side of the flat face
      final (starts, pts) = _edges(m.pos, [
        [1, 2], // shared by both faces
        [0, 3], // flat face only
        [4, 5], // upright face only
        [0, 1], // flat face only
        [2, 3], // flat face only
      ]);
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: starts,
          edgePoints: pts);

      expect(faceBoundaryEdges(mesh, 0), {0, 1, 3, 4});
      expect(faceBoundaryEdges(mesh, 1), {0, 2});
    });

    test('an INTERIOR triangle side is not a boundary', () {
      // The diagonal 0-2 splits the flat square into its two triangles. It is
      // used twice within face 0, so it is not an edge of the face — and if
      // the count were ignored it would be projected as a stray diagonal
      // across the middle of the outline.
      final m = _twoFaces();
      final (starts, pts) = _edges(m.pos, [
        [0, 2], // the diagonal
      ]);
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: starts,
          edgePoints: pts);
      expect(faceBoundaryEdges(mesh, 0), isEmpty);
    });

    test('an edge that only TOUCHES the face is not taken', () {
      // The upright face's vertical side (1,0,0)-(1,0,1) starts on the flat
      // face's boundary and leaves it. Endpoints alone would accept it; every
      // point is the rule that does not.
      final m = _twoFaces();
      final (starts, pts) = _edges(m.pos, [
        [1, 4],
      ]);
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: starts,
          edgePoints: pts);
      expect(faceBoundaryEdges(mesh, 0), isEmpty);
      expect(faceBoundaryEdges(mesh, 1), {0});
    });

    test('a mesh with no face metadata answers "cannot tell", not "none"', () {
      // A fake or a legacy mesh. The caller must fall back to single-edge
      // picking rather than believe a face has no edges.
      final m = _twoFaces();
      final (starts, pts) = _edges(m.pos, [
        [0, 1],
      ]);
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: Int32List(0),
          edgeStarts: starts,
          edgePoints: pts);
      expect(faceBoundaryEdges(mesh, 0), isEmpty);
    });

    test('a face index nothing uses has no boundary', () {
      final m = _twoFaces();
      final (starts, pts) = _edges(m.pos, [
        [0, 1],
      ]);
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: starts,
          edgePoints: pts);
      expect(faceBoundaryEdges(mesh, 7), isEmpty);
    });
  });

  group('which face is under the cursor', () {
    // A sketch on the XY plane looks down +Z at the two-face fixture.
    final fr = planeFrame('xy');

    PartModel _part() {
      final m = _twoFaces();
      final (starts, pts) = _edges(m.pos, [
        [1, 2],
        [0, 3],
        [4, 5],
        [0, 1],
        [2, 3],
      ]);
      final p = PartModel('P');
      p.features.add(ExtrudeFeature(
          name: 'E1',
          bodyName: 'Solid1',
          sketchName: 'S',
          profiles: [ProfileSel(0, 0, 100)])
        ..solid = KernelSolid(
            meshForTest(
                positions: m.pos,
                indices: m.idx,
                triFaces: m.tf,
                edgeStarts: starts,
                edgePoints: pts),
            0,
            null));
      return p;
    }

    test('a point over the flat face finds it', () {
      final r = faceUnderPoint(_part(), fr, const Offset(0.3, 0.3));
      expect(r, isNotNull);
      expect(r!.face, 0);
      expect(r.feature, 0);
    });

    test('a point outside the model finds nothing', () {
      expect(faceUnderPoint(_part(), fr, const Offset(5, 5)), isNull);
    });

    test('the NEAREST face wins where two overlap', () {
      // Seen down +Z, the upright face at x = 1 is a line and the flat face is
      // the square — but the fixture's shared side is over both. A sketch
      // looks down its own normal at a solid, so the point is usually over the
      // front AND the back of the part, and only the near one is being
      // pointed at.
      final r = faceUnderPoint(_part(), fr, const Offset(1.0, 0.5));
      expect(r, isNotNull);
      // The upright face reaches z = 1 there, the flat one sits at z = 0.
      expect(r!.height, greaterThanOrEqualTo(0));
    });

    test('the face maps to part-wide edge indices', () {
      // partEdges numbers every display edge of every visible feature in one
      // run, and the projector addresses THAT number. A face's local set has
      // to be renumbered into it or the projection lands on another curve.
      final p = _part();
      final r = faceUnderPoint(p, fr, const Offset(0.3, 0.3))!;
      expect(partEdgeIndicesForFace(p, r), [0, 1, 3, 4]);
    });
  });
}
