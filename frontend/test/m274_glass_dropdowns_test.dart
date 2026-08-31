// M274 — the appearance dropdowns sit on the glass ribbon as a wash, not a hole.
//
// The report: "the dropdowns color and rendered or with edges is somehow dark
// and doesnt really fit in the liquidglass ribbon."
//
// The two appearance chips (Material, Display mode) were drawn as an OPAQUE
// dark "field" well with a near-black `sep` seam. On the translucent ribbon
// that reads as two holes punched through the glass, not as controls ON the
// glass. The rest of the bar already had the right idiom — `_DropChip` is a
// translucent hover wash with a translucent hairline — so the fix is to make
// the two dropdowns the same surface, not a third one.
//
// This test does not judge "does it look right". It pins the one thing a
// regression would quietly break: at rest the chips are TRANSLUCENT washes
// (`hover6` fill, `border10` hairline), not the opaque `field`/`sep` pair.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/ribbon.dart';

AppState _partApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m274');
  app.parts['p'] = PartModel('Part1');
  app.curTab = 'p';
  return app;
}

Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(const Size(1366, 1024));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
  await t.pump();
}

/// The two dropdown chips (Material, Display mode) are the only widgets in the
/// ribbon that carry a literal '▼' `Text` *inside a rounded-6 chip*. `_DropChip`
/// draws its chevron as an `Icon`, and the panel-title overflow '▼' lives in an
/// unrounded header row, so neither can be caught by this discriminator.
List<BoxDecoration> _chipDecorations(WidgetTester t) {
  final out = <BoxDecoration>[];
  for (final e in find.text('▼').evaluate()) {
    final c = e.findAncestorWidgetOfExactType<Container>();
    final d = c?.decoration;
    if (d is BoxDecoration && d.borderRadius == BorderRadius.circular(6)) {
      out.add(d);
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(T.resetForTest);
  tearDown(T.resetForTest);

  testWidgets('the appearance dropdowns are a translucent wash, not the dark well',
      (t) async {
    await _pump(t, _partApp());

    final decos = _chipDecorations(t);
    // Material + Display mode + Section (M291). An exact count on purpose: a
    // chip added to this panel must arrive wearing the same treatment, and a
    // >= would let the next one in wearing the old dark well.
    expect(decos.length, 3);

    for (final d in decos) {
      final fill = d.color!;
      final edge = d.border!.top.color;
      // The old treatment was an OPAQUE near-black well with a near-black
      // seam. The fix must not merely relabel it.
      expect(fill, isNot(T.field));
      expect(edge, isNot(T.sep));
      // The new treatment: the same translucent wash every other chip on the
      // bar already uses, resting and hoverable as one surface.
      expect(fill, T.hover6);
      expect(edge, T.border10);
      // And translucent in fact — the ribbon must show through.
      expect((fill.toARGB32() >> 24) & 0xFF, lessThan(0xFF));
      expect((edge.toARGB32() >> 24) & 0xFF, lessThan(0xFF));
    }
  });
}
