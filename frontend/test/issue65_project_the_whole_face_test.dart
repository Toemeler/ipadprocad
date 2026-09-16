// #65 — "i couldnt project the whole face in one go".
//
// The face pick is not missing. M279 built it, and bug-2026-09-16T153121's log
// shows it firing and answering:
//
//   click: toolClick tool=Tool.project sketch=Sketch2 w=(-0.38,0.86) picks=0
//   ui: notice: 1 edge projected
//   project: projected 1 edges of a face onto "Layer 1"
//
// ONE edge, of a face with a whole boundary. So the pick resolved the face and
// `faceBoundaryEdges` then failed to find its edges.
//
// WHY. M279 derives "the edges of this face" from the mesh, and says so, and
// says why it is exact:
//
//   "a display edge belongs to the face when every point of its polyline is
//    one of those boundary vertices ... They are the same nodes — OCCT
//    tessellates an edge and the faces meeting it from one polygon"
//
// That last sentence is not true of this shim. occt_mesh_create discretises
// edges at their OWN parameters, deliberately, with a note of its own saying
// so (v11): a fixed fine deflection of 5e-3 for edges against whatever the
// triangle budget gives the faces, because "outlines are what the eye judges"
// and they must not go angular when the faces coarsen. Two independent
// discretisations of the same curve share their ENDPOINTS and nothing between.
//
// So a curved edge never matched, and a straight one matched only while the
// face triangulation happened not to subdivide its chord. What came back was
// whichever edges survived that coincidence — one, on the reporter's face.
//
// The header also said where the answer belongs:
//
//   "NOT from the kernel, and that is worth writing down because the kernel is
//    where it belongs. OCCT can answer edge -> faces exactly and cheaply
//    (TopExp::MapShapesAndAncestors), but the shim does not expose it, and
//    adding it means a new C entry point, a shim version bump and an ABI both
//    sides have to agree on."
//
// The shim was already calling MapShapesAndAncestors — the seam test needs it
// — and simply never exported the result. v30 does. The derivation stays for
// meshes that carry no adjacency, because "cannot answer" and "no edges" have
// to keep being different sentences.
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/face_project.dart';
import 'package:prototype/part_model.dart';

/// A plate with one hole, as the kernel meshes it — the shape M279's own
/// header uses to say what a face pick is for ("a plate with four holes comes
/// across as the outline plus four circles in one pick").
///
/// Face 0 is the top: four straight sides and one circle. The circle is the
/// case that matters, so it is built the way the kernel builds one — the edge
/// polyline finely subdivided, the triangulation's boundary coarsely, sharing
/// nothing but the point they start at.
({
  Float64List pos,
  Int32List idx,
  Int32List tf,
  Int32List starts,
  Float64List pts,
  Int32List ef,
}) _plateWithHole() {
  // Triangulation of face 0, coarse: the square's corners and a 6-gon hole.
  final pos = <double>[];
  void v(double x, double y, double z) => pos.addAll([x, y, z]);
  v(0, 0, 0); v(10, 0, 0); v(10, 10, 0); v(0, 10, 0); //      0..3 corners
  const hn = 6; // the hole, as the FACE sees it
  for (var i = 0; i < hn; i++) {
    final a = 2 * 3.141592653589793 * i / hn;
    v(5 + 2 * _cos(a), 5 + 2 * _sin(a), 0); //                 4..9
  }
  // Any triangulation will do — faceBoundaryEdges only reads triFaces here.
  final idx = Int32List.fromList([0, 1, 4, 1, 2, 5, 2, 3, 6, 3, 0, 7]);
  final tf = Int32List.fromList([0, 0, 0, 0]);

  // Display edges. Four straight sides, then the hole circle at the kernel's
  // OWN much finer subdivision (24 points against the face's 6).
  final starts = <int>[0];
  final pts = <double>[];
  var n = 0;
  void poly(List<List<double>> p) {
    for (final q in p) {
      pts.addAll(q);
      n++;
    }
    starts.add(n);
  }

  poly([[0, 0, 0], [10, 0, 0]]);
  poly([[10, 0, 0], [10, 10, 0]]);
  poly([[10, 10, 0], [0, 10, 0]]);
  poly([[0, 10, 0], [0, 0, 0]]);
  poly([
    for (var i = 0; i <= 24; i++)
      [
        5 + 2 * _cos(2 * 3.141592653589793 * i / 24),
        5 + 2 * _sin(2 * 3.141592653589793 * i / 24),
        0,
      ]
  ]);
  // An edge of the SIDE wall, which shares its two ends with the top face and
  // must not be taken: the case the "every point" rule was written for.
  poly([[10, 0, 0], [10, 0, -5]]);

  // What the kernel says: 6 display edges, two mesh-face slots each.
  // Edges 0..4 bound face 0 (the top); edge 5 does not.
  final ef = Int32List.fromList([
    0, 1, //  bottom side: top face + its wall
    0, 2, //
    0, 3, //
    0, 4, //
    0, 5, //  the hole circle: top face + the bore
    1, 6, //  the wall's own upright edge — not face 0
  ]);
  return (
    pos: Float64List.fromList(pos),
    idx: idx,
    tf: tf,
    starts: Int32List.fromList(starts),
    pts: Float64List.fromList(pts),
    ef: ef
  );
}

double _cos(double a) => _c(a);
double _sin(double a) => _c(a - 1.5707963267948966);
double _c(double a) {
  // A local cosine so the fixture needs no import beyond typed_data.
  var x = a % 6.283185307179586;
  if (x > 3.141592653589793) x -= 6.283185307179586;
  if (x < -3.141592653589793) x += 6.283185307179586;
  final x2 = x * x;
  return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720 +
      x2 * x2 * x2 * x2 / 40320;
}

void main() {
  group('THE REPORT: a face comes across whole', () {
    test('every edge of the face, curved ones included', () {
      final m = _plateWithHole();
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: m.starts,
          edgePoints: m.pts,
          edgeFaces: m.ef);

      expect(faceBoundaryEdges(mesh, 0), {0, 1, 2, 3, 4},
          reason: 'the outline AND the hole — which is what M279 promised and '
              'what "projected 1 edges of a face" was not');
    });

    test('and NOT an edge that merely touches it', () {
      final m = _plateWithHole();
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: m.starts,
          edgePoints: m.pts,
          edgeFaces: m.ef);
      expect(faceBoundaryEdges(mesh, 0), isNot(contains(5)));
      // ...and it IS an edge of the wall it belongs to.
      expect(faceBoundaryEdges(mesh, 1), contains(5));
    });

    test('the derivation alone could not see the curved edge', () {
      // The same fixture with the adjacency withheld, which is the state every
      // build before v30 was in. The hole circle is 25 points at its own
      // spacing against a 6-gon in the triangulation, so not one of its
      // segments is a boundary side and it is dropped — while the straight
      // sides, whose chords DO coincide, survive. That asymmetry is exactly
      // what "1 edge projected" on a real face looks like.
      final m = _plateWithHole();
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: m.starts,
          edgePoints: m.pts); // no edgeFaces

      expect(faceBoundaryEdges(mesh, 0), isNot(contains(4)),
          reason: 'THE BUG, pinned: the hole is invisible to the derivation');
    });
  });

  group('a mesh that cannot answer still says so', () {
    test('no face metadata at all is "unknown", not "no edges"', () {
      final m = _plateWithHole();
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: Int32List(0),
          edgeStarts: m.starts,
          edgePoints: m.pts,
          edgeFaces: m.ef);
      expect(faceBoundaryEdges(mesh, 0), isEmpty);
    });

    test('a negative face is refused before anything is read', () {
      final m = _plateWithHole();
      final mesh = meshForTest(
          positions: m.pos,
          indices: m.idx,
          triFaces: m.tf,
          edgeStarts: m.starts,
          edgePoints: m.pts,
          edgeFaces: m.ef);
      expect(faceBoundaryEdges(mesh, -1), isEmpty);
    });
  });

  group('#65, second half: "i also want to project using the select boxes"', () {
    // Three model edges laid out left to right, each 2 wide, 2 apart.
    List<PartEdge> edges() => [
          PartEdge(0, const [Offset(0, 0), Offset(2, 0)]),
          PartEdge(1, const [Offset(4, 0), Offset(6, 0)]),
          PartEdge(2, const [Offset(8, 0), Offset(10, 0)]),
        ];

    test('a WINDOW box takes only what is wholly inside', () {
      // Left-to-right in Inventor. Reaches edge 1 entirely and clips edge 2.
      final r = Rect.fromLTRB(3, -1, 9, 1);
      expect(partEdgesInRect(edges(), r, crossing: false), [1]);
    });

    test('a CROSSING box takes what it merely touches', () {
      final r = Rect.fromLTRB(3, -1, 9, 1);
      expect(partEdgesInRect(edges(), r, crossing: true), [1, 2]);
    });

    test('a box over nothing takes nothing', () {
      expect(
          partEdgesInRect(edges(), Rect.fromLTRB(20, 20, 30, 30),
              crossing: true),
          isEmpty);
    });

    test('and the result is SORTED, so the projection order is stable', () {
      // Reversed input: a box must not project in whatever order the edges
      // happened to arrive, or two identical drags name the curves
      // differently.
      final rev = edges().reversed.toList();
      expect(
          partEdgesInRect(rev, Rect.fromLTRB(-1, -1, 11, 1), crossing: false),
          [0, 1, 2]);
    });

    test('a box that grazes an endpoint still counts as crossing', () {
      // The rule is the sketch's own (polylineInRect), and this is the case
      // where "touches" and "contains" differ by one point.
      final r = Rect.fromLTRB(1, -1, 1.5, 1);
      expect(partEdgesInRect(edges(), r, crossing: true), [0]);
      expect(partEdgesInRect(edges(), r, crossing: false), isEmpty);
    });
  });
}
