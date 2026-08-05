// M198 — a fillet may not eat past the far end of an edge.
//
//   "the fillet is still made even when it goes over the next corner this
//    should not be possible. if the width is 4.6 like here only a 4.6 radius
//    should be possible at all"
//
// What made it possible: an UNDIMENSIONED rectangle can satisfy any radius by
// GROWING. bug20260805T112635 is the proof — R5 fillets on a 4.6-wide
// rectangle, every constraint satisfied, and the sketch spanning ±6257.4281
// units. The solver was doing exactly what it was asked; nobody had told it
// that eating past the far end of an edge is not a solution.
//
// The numbers below are the ones from that bundle.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/diag.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/tools.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

/// The device's shape: a rectangle 4.6 wide and 10.6 tall, corner at
/// (-16.9037, 12) — entities 12..15 of the bundle.
AppState narrowRect() {
  final app = makeApp();
  app.tool = Tool.rectTwoPoint;
  app.toolClick(const Offset(-16.9037, 12));
  app.toolClick(const Offset(-12.3037, 22.5969));
  app.tool = Tool.none;
  return app;
}

void main() {
  test('the geometry under test is 4.6 wide, as reported', () {
    final s = narrowRect().current!;
    final w = (getPt(s.geometry[0], 1) - getPt(s.geometry[0], 0)).distance;
    expect(w, closeTo(4.6, 1e-3));
  });

  test('THE REPORT: R5 on a 4.6 edge is refused, and nothing moves', () {
    final app = narrowRect();
    final s = app.current!;
    final before = [for (final g in s.geometry) List<double>.from(g.data)];

    app.filletSess = FilletSession(Tool.fillet, radius: 5);
    app.tool = Tool.fillet;
    app.toolClick(const Offset(-15, 12)); // bottom edge
    app.toolClick(const Offset(-16.9037, 14)); // left edge

    expect(s.geometry, hasLength(4), reason: 'no arc, no stubs, nothing');
    for (var i = 0; i < 4; i++) {
      expect(s.geometry[i].data, before[i],
          reason: 'the rectangle must not have grown to make room');
    }
  });

  test('the shape cannot be stretched to fit an impossible radius', () {
    // The failure in the bundle was not a wrong number, it was a 2718x one:
    // ±6257 from a rectangle 4.6 wide. Whatever else changes, the extent of
    // the sketch must stay in the neighbourhood it was drawn in.
    final app = narrowRect();
    final s = app.current!;
    app.filletSess = FilletSession(Tool.fillet, radius: 5);
    app.tool = Tool.fillet;
    app.toolClick(const Offset(-15, 12));
    app.toolClick(const Offset(-16.9037, 14));
    expect(maxAbs(s.geometry), lessThan(100),
        reason: 'the device log showed 6257.4281 here');
  });

  test('a radius that FITS is still made', () {
    // The guard must not turn into "fillets no longer work". 2 is comfortably
    // inside 4.6.
    final app = narrowRect();
    final s = app.current!;
    app.filletSess = FilletSession(Tool.fillet, radius: 2);
    app.tool = Tool.fillet;
    app.toolClick(const Offset(-15, 12));
    app.toolClick(const Offset(-16.9037, 14));
    expect(s.geometry.any((g) => g.type == Geo.arc), isTrue);
    expect(s.geometry.length, greaterThan(4));
  });

  test('the refusal knows what WOULD fit, and it is the reported number', () {
    // "if the width is 4.6 like here only a 4.6 radius should be possible at
    // all" — so that is what the app offers back.
    final s = narrowRect().current!;
    final most = filletMaxRadius(
        s.geometry, const Offset(-15, 12), const Offset(-16.9037, 14), 5);
    expect(most, isNotNull);
    expect(most!, closeTo(4.6, 0.01));
  });

  test('the limit is the SHORTER of the two edges', () {
    // 4.6 wide, 10.6 tall: the width is what decides.
    final s = narrowRect().current!;
    final most = filletMaxRadius(
        s.geometry, const Offset(-15, 12), const Offset(-16.9037, 14), 20);
    expect(most!, closeTo(4.6, 0.01),
        reason: 'not 10.6 — a corner is only as big as its smallest edge');
  });

  test('the preview refuses too, so nothing is drawn that cannot commit', () {
    // buildToolGeometry is the same call the viewport paints with. A preview
    // that shows an arc the commit will refuse is a lie about what a tap does.
    final s = narrowRect().current!;
    final tooBig = buildToolGeometry(
        Tool.fillet, [const Offset(-15, 12), const Offset(-16.9037, 14)],
        existing: s.geometry, params: {'radius': 5});
    expect(tooBig, anyOf(isNull, isEmpty));
    final ok = buildToolGeometry(
        Tool.fillet, [const Offset(-15, 12), const Offset(-16.9037, 14)],
        existing: s.geometry, params: {'radius': 2});
    expect(ok, isNotNull);
    expect(ok!.first.type, Geo.arc);
  });

  test('a fillet that EXTENDS two lines to meet is still allowed', () {
    // The rule is about running past the FAR end, not about the corner end.
    // Inventor lengthens two lines that do not quite meet, and so do we — the
    // bundle's complaint was never about that.
    final app = makeApp();
    final s = app.current!;
    s.engine.addLine(0, 0, 30, 0);
    s.engine.addLine(50, 20, 50, 60); // stops short of the corner at (50,0)
    s.refresh();
    app.filletSess = FilletSession(Tool.fillet, radius: 5);
    app.tool = Tool.fillet;
    app.toolClick(const Offset(15, 0));
    app.toolClick(const Offset(50, 40));
    expect(s.geometry.any((g) => g.type == Geo.arc), isTrue,
        reason: 'the tangent point sits beyond the corner end, which is an '
            'extension and not an overrun');
  });

  test('the second corner of a rectangle knows the first one shortened it', () {
    // 4.6 x 10.6: after an R2 on one corner the left edge has 8.6 left, so an
    // R9 on the corner above it must be refused even though 9 < 10.6.
    final app = narrowRect();
    final s = app.current!;
    app.filletSess = FilletSession(Tool.fillet, radius: 2);
    app.tool = Tool.fillet;
    app.toolClick(const Offset(-15, 12)); // bottom
    app.toolClick(const Offset(-16.9037, 14)); // left
    final after = s.geometry.length;

    app.filletSess = FilletSession(Tool.fillet, radius: 9);
    app.toolClick(const Offset(-16.9037, 20)); // left, up top
    app.toolClick(const Offset(-15, 22.5969)); // top
    expect(s.geometry, hasLength(after),
        reason: 'the left edge is only 8.6 long now');
  });
}
