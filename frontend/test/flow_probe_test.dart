// End-to-end pick-flow tests through AppState.toolClick — the exact flows
// from the M24 bug report: line + ellipse center, ellipse as pick target,
// and Inventor's aligned/horizontal/vertical choice by placement position.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';

AppState makeApp(List<Geo> tagged) {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  for (final g in tagged) {
    switch (g.type) {
      case Geo.line:
        s.engine.addLine(g.data[0], g.data[1], g.data[2], g.data[3]);
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        s.engine.addPolyline(
            [for (var i = 0; i < n; i++) ...[g.data[2 + 2 * i], g.data[3 + 2 * i]]],
            closed: g.data[0] != 0);
        break;
    }
  }
  s.refresh(tagSource: tagged);
  app.tool = Tool.dimension;
  return app;
}

final ellipse =
    Geo(Geo.polyline, [1, 3, 50, 40, 90, 40, 50, 55]).asSpline(Geo.ellipseTag);

void main() {
  test('line + ellipse CENTER -> perpendicular point-to-line distance', () {
    final app = makeApp([Geo(Geo.line, [0, 0, 100, 0]), ellipse]);
    app.toolClick(const Offset(50, 0)); //  line body
    app.toolClick(const Offset(50, 40)); // ellipse center (snapped exactly)
    expect(app.conPts, [PRef(1, 0)]);
    app.toolClick(const Offset(70, 20)); // place
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(40, 1e-9));
  });

  test('line + ellipse BODY -> center-to-line distance (curve pick)', () {
    final app = makeApp([Geo(Geo.line, [0, 0, 100, 0]), ellipse]);
    app.toolClick(const Offset(50, 0)); //  line body
    app.toolClick(const Offset(90, 40)); // on the ellipse curve (major vertex
    //                                      region — entity, no point nearby?
    //                                      major vertex IS a point: use a
    //                                      point-free spot on the curve)
    // (50,55) is the minor vertex — also a point. Take a curve point between
    // quadrants instead:
    app.cancelTool();
    app.tool = Tool.dimension;
    app.toolClick(const Offset(50, 0));
    // point on the ellipse at 45deg: c + (a*cos45, b*sin45)
    app.toolClick(Offset(50 + 40 * 0.7071, 40 + 15 * 0.7071));
    expect(app.conEnts, [0, 1], reason: 'ellipse picked as a curve entity');
    app.toolClick(const Offset(70, 20));
    expect(app.pendingDim?.dimKind, 'pline');
    expect(app.pendingDim?.value, closeTo(40, 1e-6),
        reason: 'measures center <-> line, like a circle');
  });

  test('two points: placement above -> horizontal, right -> vertical, '
      'diagonal -> aligned', () {
    Constraint place(Offset at) {
      final app = makeApp([Geo(Geo.line, [0, 0, 30, 40])]);
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(30, 40));
      app.toolClick(at);
      return app.pendingDim!;
    }

    final above = place(const Offset(15, 90));
    expect(above.dimKind, 'distx');
    expect(above.value, closeTo(30, 1e-9)); // horizontal distance

    final right = place(const Offset(90, 20));
    expect(right.dimKind, 'disty');
    expect(right.value, closeTo(40, 1e-9)); // vertical distance

    final left = place(const Offset(-30, 20)); // left of the box
    expect(left.dimKind, 'disty');

    final diag = place(const Offset(-17, 44)); // out along the pair's normal
    expect(diag.dimKind, 'dist');
    expect(diag.value, closeTo(50, 1e-9)); // aligned
  });
}
