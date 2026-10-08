// M495 — desktop UX flows, part 2: found by driving the real Linux app like a
// first-time Inventor user (mouse + keyboard), one group per finding.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon.dart';

import 'm56_part_test.dart' show FakeKernel;

Future<void> _pumpRibbon(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
  await t.pump();
}

List<String> _tips(WidgetTester t) => [
      for (final w in t.widgetList<Tooltip>(find.byType(Tooltip)))
        if (w.message != null) w.message!
    ];

void main() {
  group('ribbon tooltips name the single-key commands', () {
    // The part letters (S/E/R/H/F/M) and the sketch letters (L/C/R/D) were
    // undiscoverable: the tooltip said "Extrusion", Inventor's says
    // "Extrude (E)".
    setUp(RibbonDock.resetForTest);
    tearDown(RibbonLabels.resetForTest);

    testWidgets('part: Extrusion (E), Bohrung (H), …', (t) async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m495_');
      app.partKernel = FakeKernel();
      await t.runAsync(() async {
        expect(await app.createNamedPart('P'), isTrue);
      });
      await _pumpRibbon(t, app);
      final tips = _tips(t);
      for (final want in [
        'Extrusion (E)',
        'Drehung (R)',
        'Verrundung (F)',
        'Bohrung (H)',
        'Messen (M)',
      ]) {
        expect(tips, contains(want), reason: 'tooltips: $tips');
      }
      expect(tips.any((s) => s.endsWith('(S)')), isTrue,
          reason: 'Start 2D Sketch names S');
    });

    testWidgets('sketch: Linie (L), Kreis (C), Rechteck (R), Bemaßung (D)',
        (t) async {
      final app = AppState();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m495_');
      app.sketches['t'] = SketchModel('t');
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      await _pumpRibbon(t, app);
      final tips = _tips(t);
      for (final want in [
        'Linie (L)',
        'Kreis (C)',
        'Rechteck (R)',
        'Bemaßung (D)',
      ]) {
        expect(tips, contains(want), reason: 'tooltips: $tips');
      }
    });
  });
}
