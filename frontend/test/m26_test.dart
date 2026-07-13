// M26 — Inventor's per-entity DOF colouring (carrier analysis).
//
// Confirmed Inventor behaviour (Autodesk forum, accepted answer by an
// Autodesk engineer after checking with the Inventor project team): a line is
// painted in the FULLY-CONSTRAINED colour as soon as its carrier — direction
// and perpendicular position — is fixed, even while no length dimension
// exists. The still-movable endpoint is a separate entity with its own state.
// Circles/arcs are the carrier (center, radius); free arc sweep endpoints do
// not keep the curve violet. A rectangle in Inventor is four lines, so each
// edge colours independently — our closed polyline must therefore be
// analysed (and painted) per edge.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/solver.dart';

Geo line(double x1, double y1, double x2, double y2) =>
    Geo(Geo.line, [x1, y1, x2, y2]);
Geo circle(double cx, double cy, double r) => Geo(Geo.circle, [cx, cy, r]);
Geo rect(double x, double y, double w, double h) => Geo(Geo.polyline, [
      1, 4, // closed, 4 vertices
      x, y, x + w, y, x + w, y + h, x, y + h,
    ]);

Constraint fixPt(int ent, int pt, double x, double y) =>
    Constraint(CType.fix, pts: [PRef(ent, pt)], anchors: [x, y]);
Constraint hor(int ent, int a, int b) =>
    Constraint(CType.horizontal, pts: [PRef(ent, a), PRef(ent, b)]);
Constraint ver(int ent, int a, int b) =>
    Constraint(CType.vertical, pts: [PRef(ent, a), PRef(ent, b)]);

void main() {
  group('carrier analysis (Inventor colouring)', () {
    test('line with fixed start + horizontal is WHITE with its length free',
        () {
      // The exact scenario from the Autodesk thread: first point grounded,
      // direction constrained, no length dimension. Inventor: line fully
      // constrained, endpoint still free.
      final gs = [line(0, 0, 50, 0)];
      final cs = [
        fixPt(0, 0, 0, 0),
        Constraint(CType.horizontal, ents: [0]),
      ];
      final a = analyzeSketch(gs, cs);
      expect(a.dof, 1, reason: 'only the length is left');
      expect(a.carrierFixed(0), isTrue,
          reason: 'direction + position fixed => white, length free');
      expect(a.freePoints.contains((0, 1)), isTrue,
          reason: 'the endpoint itself is still a free point (DOF arrow)');
    });

    test('line with ONLY a length dimension stays violet (carrier moves)',
        () {
      final gs = [line(0, 0, 50, 0)];
      final cs = [
        Constraint(CType.dimension,
            pts: [PRef(0, 0), PRef(0, 1)], dimKind: 'dist', value: 50),
      ];
      final a = analyzeSketch(gs, cs);
      expect(a.carrierFixed(0), isFalse,
          reason: 'the whole line can still translate and rotate');
    });

    test('unconstrained sketch: every carrier and point is loose', () {
      final a = analyzeSketch([line(0, 0, 10, 0), rect(0, 0, 4, 3)], []);
      expect(a.carrierFixed(0), isFalse);
      for (var seg = 0; seg < 4; seg++) {
        expect(a.carrierFixed(1, seg), isFalse);
      }
      expect(a.freePoints.length, 2 + 4);
    });

    test(
        'rectangle: fixed corner + H/V => the two edges THROUGH the corner '
        'go white immediately; the far edges follow their dimensions', () {
      // The user scenario. Bottom-left corner grounded, auto H/V on all
      // edges, width/height undimensioned (dof 2):
      //   bottom + left edge: pass through the fixed corner with a fixed
      //     direction -> carrier pinned -> WHITE, only their length is free.
      //   right + top edge: their carriers genuinely TRANSLATE when the
      //     width/height changes (the infinite line x=w moves with w) ->
      //     stay violet, exactly like Inventor, until a dimension pins them.
      final gs = [rect(0, 0, 40, 30)];
      final cs = [
        fixPt(0, 0, 0, 0),
        hor(0, 0, 1), // bottom
        ver(0, 1, 2), // right
        hor(0, 3, 2), // top
        ver(0, 0, 3), // left
      ];
      final a = analyzeSketch(gs, cs);
      expect(a.dof, 2, reason: 'width and height still undimensioned');
      expect(a.carrierFixed(0, 0), isTrue, reason: 'bottom: through corner');
      expect(a.carrierFixed(0, 3), isTrue, reason: 'left: through corner');
      expect(a.carrierFixed(0, 1), isFalse, reason: 'right rides on width');
      expect(a.carrierFixed(0, 2), isFalse, reason: 'top rides on height');
      // ...while the three unfixed vertices are still free points.
      expect(a.freePoints, containsAll([(0, 1), (0, 2), (0, 3)]));

      // width dimension -> the right edge's carrier locks (its length, the
      // height, is still free); the top edge still rides on the height.
      final cs2 = [
        ...cs,
        Constraint(CType.dimension,
            pts: [PRef(0, 0), PRef(0, 1)], dimKind: 'distx', value: 40),
      ];
      final a2 = analyzeSketch(gs, cs2);
      expect(a2.dof, 1);
      expect(a2.carrierFixed(0, 1), isTrue, reason: 'width pins the right');
      expect(a2.carrierFixed(0, 2), isFalse, reason: 'height still free');

      // height dimension -> everything white, sketch fully constrained.
      final cs3 = [
        ...cs2,
        Constraint(CType.dimension,
            pts: [PRef(0, 1), PRef(0, 2)], dimKind: 'disty', value: 30),
      ];
      final a3 = analyzeSketch(gs, cs3);
      expect(a3.fullyConstrained, isTrue);
      expect(a3.looseCarriers, isEmpty);
    });

    test('rectangle with H/V but NO grounded corner: everything violet', () {
      final gs = [rect(0, 0, 40, 30)];
      final cs = [hor(0, 0, 1), ver(0, 1, 2), hor(0, 3, 2), ver(0, 0, 3)];
      final a = analyzeSketch(gs, cs);
      for (var seg = 0; seg < 4; seg++) {
        expect(a.carrierFixed(0, seg), isFalse,
            reason: 'the whole rectangle can still translate');
      }
    });

    test('L-shape: two separate lines white edge-by-edge via shared corner',
        () {
      // corner of line1 coincident to the FREE end of line0; line0 grounded
      // at its start and horizontal, line1 vertical. Line0 is white (length
      // free), line1 is violet until its anchor chain closes: its carrier
      // hangs on line0's free endpoint... which can only slide ALONG line0,
      // i.e. along line1's perpendicular? No: line0 is horizontal, line1
      // vertical, the shared point sliding in x SHIFTS the vertical carrier.
      // So line1 must stay violet — exactly Inventor.
      final gs = [line(0, 0, 40, 0), line(40, 0, 40, 25)];
      final cs = [
        fixPt(0, 0, 0, 0),
        Constraint(CType.horizontal, ents: [0]),
        Constraint(CType.vertical, ents: [1]),
        Constraint(CType.coincident, pts: [PRef(0, 1), PRef(1, 0)]),
      ];
      final a = analyzeSketch(gs, cs);
      expect(a.carrierFixed(0), isTrue, reason: 'line0: only length free');
      expect(a.carrierFixed(1), isFalse,
          reason: 'line1 slides sideways with line0\'s free endpoint');
      // Now dimension line0's length: line1's carrier locks, its own length
      // stays free — both lines white, one dimension still needed.
      final cs2 = [
        ...cs,
        Constraint(CType.dimension,
            pts: [PRef(0, 0), PRef(0, 1)], dimKind: 'dist', value: 40),
      ];
      final a2 = analyzeSketch(gs, cs2);
      expect(a2.dof, 1);
      expect(a2.carrierFixed(0), isTrue);
      expect(a2.carrierFixed(1), isTrue,
          reason: 'anchored + vertical => white, only its length is free');
    });

    test('circle: fixed center, free radius => violet; radius dim => white',
        () {
      final gs = [circle(10, 10, 5)];
      final a = analyzeSketch(gs, [fixPt(0, 0, 10, 10)]);
      expect(a.carrierFixed(0), isFalse, reason: 'radius still moves');
      final a2 = analyzeSketch(gs, [
        fixPt(0, 0, 10, 10),
        Constraint(CType.dimension, ents: [0], dimKind: 'rad', value: 5),
      ]);
      expect(a2.carrierFixed(0), isTrue);
      expect(a2.dof, 0);
    });

    test('fully constrained sketch reports no loose carriers', () {
      final gs = [line(0, 0, 40, 0)];
      final cs = [
        fixPt(0, 0, 0, 0),
        Constraint(CType.horizontal, ents: [0]),
        Constraint(CType.dimension,
            pts: [PRef(0, 0), PRef(0, 1)], dimKind: 'dist', value: 40),
      ];
      final a = analyzeSketch(gs, cs);
      expect(a.fullyConstrained, isTrue);
      expect(a.looseCarriers, isEmpty);
      expect(a.freePoints, isEmpty);
    });

    test('carrierSegCount: per-edge for plain polylines only', () {
      expect(carrierSegCount(line(0, 0, 1, 0)), 1);
      expect(carrierSegCount(circle(0, 0, 1)), 1);
      expect(carrierSegCount(rect(0, 0, 4, 3)), 4); // closed: n edges
      expect(
          carrierSegCount(Geo(Geo.polyline, [0, 3, 0, 0, 1, 0, 2, 1])), 2);
      expect(
          carrierSegCount(Geo(Geo.polyline, [0, 3, 0, 0, 1, 0, 2, 1])
              .asSpline(Geo.splineCv)),
          1); // tagged curve = one piece
    });
  });
}
