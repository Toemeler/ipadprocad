// OFFSET CHAIN — Inventor's Offset with "Loop Select" + "Constrain Offset"
// (both ON by default). One pick offsets the WHOLE connected run of edges, not
// just the clicked one: a rectangle (four separate lines) offsets as one loop,
// a connected line+arc profile offsets together, and the copy is wired like
// Inventor — coincident at every offset corner, each offset line parallel to
// its source / each offset arc concentric with its source, and one editable
// offset distance the run follows uniformly. A chain stops at a branch (a
// vertex where more than one other edge meets), matching Inventor/Abaqus.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/modify.dart';
import 'package:ipadprocad/solver.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

Geo line(double x1, double y1, double x2, double y2) =>
    Geo(Geo.line, [x1, y1, x2, y2]);

void main() {
  group('offset chain discovery (Loop Select)', () {
    test('open run of two connected lines chains BOTH', () {
      final gs = [line(0, 0, 10, 0), line(10, 0, 10, 10)];
      final ch = offsetChainAt(gs, 0, const Offset(5, -2), {0, 1});
      expect(ch, isNotNull);
      expect(ch!.sources.toSet(), {0, 1});
      expect(ch.closed, isFalse);
      expect(ch.offsets, hasLength(2));
    });

    test('closed rectangle (four lines) chains the WHOLE loop', () {
      final gs = [
        line(0, 0, 10, 0),
        line(10, 0, 10, 10),
        line(10, 10, 0, 10),
        line(0, 10, 0, 0),
      ];
      final ch = offsetChainAt(gs, 0, const Offset(5, -2), {0, 1, 2, 3});
      expect(ch, isNotNull);
      expect(ch!.sources.toSet(), {0, 1, 2, 3});
      expect(ch.closed, isTrue);
    });

    test('a BRANCH (3 edges at a vertex) stops the chain', () {
      // lines 0,1 are collinear through (10,0); line 2 branches upward there.
      final gs = [
        line(0, 0, 10, 0),
        line(10, 0, 20, 0),
        line(10, 0, 10, 10),
      ];
      final ch = offsetChainAt(gs, 0, const Offset(5, -2), {0, 1, 2});
      expect(ch, isNotNull);
      // seed's free end is (0,0) (nothing there) and its other end (10,0) is a
      // 3-way junction — the chain cannot continue confidently, so only the
      // seed offsets.
      expect(ch!.sources, [0]);
      expect(ch.closed, isFalse);
    });

    test('offset geometry is a uniform parallel copy (rectangle, outward)', () {
      final gs = [
        line(0, 0, 10, 0), // bottom
        line(10, 0, 10, 10), // right
        line(10, 10, 0, 10), // top
        line(0, 10, 0, 0), // left
      ];
      // pick below the bottom edge -> outward offset of 2
      final ch = offsetChainAt(gs, 0, const Offset(5, -2), {0, 1, 2, 3});
      expect(ch, isNotNull);
      expect(ch!.offsetDist, closeTo(2, 1e-6));
      // source line 0 is the seed => offsets[0] is its parallel copy
      final o0 = ch.offsets[0];
      expect(o0.type, Geo.line);
      // horizontal at y = -2, mitred corners extend past [0,10] to [-2,12]
      expect(o0.data[1], closeTo(-2, 1e-6));
      expect(o0.data[3], closeTo(-2, 1e-6));
      expect(o0.data[0], closeTo(-2, 1e-6));
      expect(o0.data[2], closeTo(12, 1e-6));
    });
  });

  group('offset chain wiring (Constrain Offset)', () {
    test('rectangle offsets as a constrained loop in ONE operation', () {
      final app = makeApp();
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(100, 40));
      app.toolClick(const Offset(140, 70));
      final s = app.current!;
      expect(s.geometry, hasLength(4));
      final coBefore =
          s.constraints.where((c) => c.type == CType.coincident).length;

      // offset: pick the bottom edge, then click below it (outward, dist 10)
      app.tool = Tool.moffset;
      app.toolClick(const Offset(120, 40)); // pick
      app.toolClick(const Offset(120, 30)); // side

      // four new lines: the whole rectangle offset at once
      expect(s.geometry, hasLength(8));
      expect(s.geometry.every((g) => g.type == Geo.line), isTrue);

      // wired like Inventor: +4 corner coincidences, +4 parallels to source
      final co =
          s.constraints.where((c) => c.type == CType.coincident).length;
      final par =
          s.constraints.where((c) => c.type == CType.parallel).length;
      expect(co - coBefore, 4);
      expect(par, 4);

      // one editable offset distance the rest follow (equidistant); the loop's
      // redundant final gap is a driven reference measure, not a driver.
      final plines =
          s.constraints.where((c) => c.dimKind == 'pline').toList();
      expect(plines, hasLength(4));
      final drivers = plines.where((c) => !c.driven).toList();
      final refs = plines.where((c) => c.driven).toList();
      expect(refs, hasLength(1), reason: 'closed loop => one reference gap');
      final named = drivers.firstWhere((c) => c.paramName != null);
      expect(drivers.where((c) => c.expr == named.paramName).isNotEmpty, isTrue,
          reason: 'the other gaps follow the driver by expression');

      // the constrained result actually solves and leaves the offset with a
      // single free distance DOF on top of the (free) source rectangle.
      final an = analyzeSketch(s.geometry, s.constraints);
      expect(an.dof, 5, reason: '4 (source rect) + 1 (offset distance)');
    });

    test('offset holds together and stays uniform under a solve', () {
      final app = makeApp();
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 30));
      final s = app.current!;
      app.tool = Tool.moffset;
      app.toolClick(const Offset(20, 0)); // pick bottom edge
      app.toolClick(const Offset(20, -6)); // outward by 6

      // every offset line is parallel to some source line and offset by 6:
      // the four new lines (indices 4..7) form a rectangle 6 larger all round.
      final newLines = s.geometry.sublist(4);
      expect(newLines, hasLength(4));
      // horizontal offset lines sit at y = -6 and y = 36; verticals at x = -6
      // and x = 46 (within solver tolerance).
      final ys = <double>[];
      final xs = <double>[];
      for (final g in newLines) {
        if ((g.data[1] - g.data[3]).abs() < 1e-3) {
          ys.add(g.data[1]); // horizontal
        } else if ((g.data[0] - g.data[2]).abs() < 1e-3) {
          xs.add(g.data[0]); // vertical
        }
      }
      ys.sort();
      xs.sort();
      expect(ys, hasLength(2));
      expect(xs, hasLength(2));
      expect(ys.first, closeTo(-6, 1e-2));
      expect(ys.last, closeTo(36, 1e-2));
      expect(xs.first, closeTo(-6, 1e-2));
      expect(xs.last, closeTo(46, 1e-2));
    });
  });
}
