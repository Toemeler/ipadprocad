// M408 — #32: "the plane which was made somehow does not appear in the model
// browser. idk why. also only tested on windows".
//
// Nothing was wrong with the plane. It was in the document, it was drawn in
// the viewport, and it had no row anywhere — because off iOS the browser is
// [ModelBrowser], the Flutter tree, and that tree has never listed a work
// feature at all. Planes have been in the NATIVE tree since M169 and axes and
// points since M215; the twin was simply never taught. On an iPad the report
// could not have happened, which is why "also only tested on windows" is the
// whole diagnosis.
//
// What is pinned here is the tree the desktop actually shows, and the three
// rules it borrows from the native one:
//
//   * all three kinds appear, by name;
//   * they are interleaved by `seq`, so a plane made after Extrusion1 and
//     before Extrusion2 is listed between them — not gathered into a block;
//   * they stay ABOVE End of Part, which never rolls one back.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/model_browser.dart';
import 'package:prototype/l10n/l.dart';

import 'm56_part_test.dart' show FakeKernel;

AppState _app() {
  final app = AppState()..partKernel = FakeKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m403_');
  final p = PartModel('P');
  app.parts['P'] = p;
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

/// The reported feature: a midplane, committed the way [AppState] commits one.
WorkPlane _plane(PartModel p, String name, int seq) => WorkPlane(
    name,
    seq,
    WorkPlaneKind.constructed,
    'Midplane between Face and Face',
    workPlaneFrameAt(const Vec3(25, 168, -155), const Vec3(0, 0, 1)));

Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(const Size(1600, 900));
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AnimatedBuilder(
              animation: app, builder: (_, __) => ModelBrowser(app: app)))));
  await t.pump();
}

/// The vertical order of [labels] as the tree lays them out, top to bottom.
List<String> _order(WidgetTester t, List<String> labels) {
  final found = <(double, String)>[];
  for (final l in labels) {
    final f = find.text(l);
    if (f.evaluate().isEmpty) continue;
    found.add((t.getTopLeft(f.first).dy, l));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, l) in found) l];
}

void main() {
  setUp(() => L.set(kEn));
  tearDown(() => L.set(kDe));

  testWidgets('THE REPORT: a work plane has a row', (t) async {
    final app = _app();
    final p = app.currentPart!;
    p.workPlanes.add(_plane(p, 'Work Plane1', 7));
    await _pump(t, app);
    expect(find.text('Work Plane1'), findsOneWidget,
        reason: 'the plane was in the document and nowhere in the tree');
  });

  testWidgets('axes and points too — all three kinds were missing',
      (t) async {
    final app = _app();
    final p = app.currentPart!;
    p.workPlanes.add(_plane(p, 'Work Plane1', 1));
    p.workAxes.add(WorkAxis('Work Axis1', 2, 'Through Two Points', Vec3.zero,
        const Vec3(0, 0, 1)));
    p.workPoints
        .add(WorkPoint('Work Point1', 3, 'Grounded', Vec3.zero, grounded: true));
    await _pump(t, app);
    expect(find.text('Work Plane1'), findsOneWidget);
    expect(find.text('Work Axis1'), findsOneWidget);
    expect(find.text('Work Point1'), findsOneWidget);
  });

  testWidgets('one stream in seq order, not a block grouped by kind',
      (t) async {
    // M215's rule, which is the reason the native tree emits all three from
    // one sorted list: an axis made before a plane is listed before it.
    final app = _app();
    final p = app.currentPart!;
    p.workAxes.add(WorkAxis('Work Axis1', 1, 'Through Two Points', Vec3.zero,
        const Vec3(0, 0, 1)));
    p.workPlanes.add(_plane(p, 'Work Plane1', 2));
    p.workPoints.add(WorkPoint('Work Point1', 3, 'Grounded', Vec3.zero));
    await _pump(t, app);
    expect(_order(t, ['Work Axis1', 'Work Plane1', 'Work Point1']),
        ['Work Axis1', 'Work Plane1', 'Work Point1']);
  });

  testWidgets('and it stays above End of Part', (t) async {
    // A work feature is never rolled back, so it can never be listed below the
    // marker — the native tree emits the leftovers before the trailing marker
    // for exactly this reason.
    final app = _app();
    final p = app.currentPart!;
    p.workPlanes.add(_plane(p, 'Work Plane1', 7));
    await _pump(t, app);
    final eop = L.current.nodeEndOfPart;
    expect(_order(t, ['Work Plane1', eop]), ['Work Plane1', eop]);
  });

  testWidgets('a tap on the row selects the plane, and taps again to clear',
      (t) async {
    // M254's gesture, which the native row has and this one did not exist to
    // have. It is also the cheapest proof the row is wired to the document
    // rather than being a label.
    final app = _app();
    final p = app.currentPart!;
    final w = _plane(p, 'Work Plane1', 7);
    p.workPlanes.add(w);
    await _pump(t, app);
    // Past the double-tap window: the row carries a double-tap too (start a
    // sketch on the plane), so a single tap is held until that has been ruled
    // out — the same wait a feature row has always had.
    Future<void> tapRow() async {
      await t.tap(find.text('Work Plane1'));
      await t.pump(const Duration(milliseconds: 400));
    }

    await tapRow();
    expect(app.selectedWorkPlane, same(w));
    await tapRow();
    expect(app.selectedWorkPlane, isNull);
  });
}
