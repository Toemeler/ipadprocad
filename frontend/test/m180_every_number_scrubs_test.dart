// M180 — every single number in the app is draggable.
//
// M172 gave three fields a scrub and left the rest tapping-only, which made
// "can I drag this one?" a question the user had to ask each time and get
// wrong most of it: the pattern counts, the 2D fillet radius, every gear
// parameter, the parametric text height, the Parameters window and the polygon
// prompt all just sat there. A gesture that works on some numbers is worse
// than one that works on none, because there is no way to tell which is which
// without trying.
//
// So the contract these tests pin is a blunt one, and it is meant to be:
//   * NO numeric field in lib/ exists outside a ScrubField, and
//   * the detent follows what the number MEASURES — a tooth count steps by a
//     whole tooth, a pressure angle by a degree, a profile shift by a tenth,
//     and only a LENGTH follows the zoom, because only a length has anything
//     to do with what a pixel is worth.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/gear.dart';
import 'package:prototype/inserts.dart';
import 'package:prototype/scrub.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/gear_dialog.dart';
import 'package:prototype/widgets/parameters_dialog.dart';
import 'package:prototype/widgets/pattern_dialog.dart';
import 'package:prototype/widgets/scrub_field.dart';
import 'package:prototype/widgets/text_editor_window.dart';

AppState _sketchApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

Future<void> _pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(1400, 1200));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: w)),
  ));
  await t.pump();
  // The test font is a monospaced stand-in whose glyphs are much wider than
  // the real one's, so labels that fit on the device overflow their rows here.
  // Those are diagnostics about a font that does not ship; discard them rather
  // than let them fail a test about something else entirely.
  while (t.takeException() != null) {}
}

/// A VALUE field, by the keyboard it asks for.
///
/// M206 changed what that is. It used to be one of the numeric keyboards —
/// plain, signed, decimal, all sharing one index. It is now
/// [kValueKeyboard] == TextInputType.none, because the app draws its own pad
/// and asks the system for nothing (see value_pad.dart). The M180 contract
/// below is unchanged; only the probe for "this is a number field" moved.
bool _isNumeric(TextField f) {
  // Explicitly nullable local: whether TextField declares this one nullable
  // has changed across Flutter versions, and CI does not run the SDK this was
  // written against.
  final TextInputType? k = f.keyboardType;
  return k?.index == kValueKeyboard.index ||
      k?.index == TextInputType.number.index;
}

/// Fails naming the field when a numeric TextField has no ScrubField over it.
void _everyNumberScrubs(WidgetTester t, String where) {
  final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
  expect(fields, isNotEmpty, reason: '$where: nothing was pumped');
  var numeric = 0;
  for (final f in fields) {
    if (!_isNumeric(f)) continue;
    // A DISABLED field is greyed because the feature does not use it yet, and
    // a number moving under the finger while the model ignores it would be
    // worse than one that does not move. Deliberately not scrubbable.
    if (f.enabled == false) continue;
    numeric++;
    expect(
        find.ancestor(
            of: find.byWidget(f), matching: find.byType(ScrubField)),
        findsAtLeast(1),
        reason: '$where: a number field with no scrub — '
            'label "${f.decoration?.labelText ?? f.controller?.text}"');
  }
  expect(numeric, greaterThan(0), reason: '$where: no numeric field found');
}

void main() {
  group('M180 — the detent follows what the number measures', () {
    test('only a length asks the zoom', () {
      // 1 px = 1 mm zoomed out, 1 px = 0.01 mm zoomed in.
      expect(scrubStepFor(ScrubKind.length, 1.0),
          isNot(scrubStepFor(ScrubKind.length, 0.01)));
      for (final k in [ScrubKind.angle, ScrubKind.count, ScrubKind.ratio]) {
        expect(scrubStepFor(k, 1.0), scrubStepFor(k, 0.01),
            reason: '$k must not move when the view does');
      }
    });

    test('a count steps by exactly one', () {
      expect(scrubStepFor(ScrubKind.count, 12.0), 1.0);
      expect(scrubDecimals(scrubStepFor(ScrubKind.count, 12.0)), 0,
          reason: 'half a tooth does not exist, so it must not be shown');
    });

    test('an angle steps by a degree, a ratio by a tenth', () {
      expect(scrubStepFor(ScrubKind.angle, 0.05), 1.0);
      expect(scrubStepFor(ScrubKind.ratio, 0.05), 0.1);
      expect(scrubDecimals(scrubStepFor(ScrubKind.ratio, 0.05)), 1);
    });

    test('a fixed detent costs exactly the travel a notch is meant to', () {
      // The whole feel depends on a notch costing about the same wherever you
      // drag. A length's step is SNAPPED to the 1-2-5 ladder, so it lands
      // between one and two notches' worth of travel; the fixed kinds have no
      // ladder to snap to and must therefore hit the number exactly.
      for (final k in [ScrubKind.angle, ScrubKind.count, ScrubKind.ratio]) {
        final travel =
            scrubStepFor(k, 0.05) / scrubUnitsPerPixel(k, 0.05);
        expect(travel, closeTo(kPxPerStep, 1e-9), reason: '$k');
      }
      for (final upp in [0.002, 0.01, 0.05, 0.4, 3.0]) {
        final travel = scrubStepFor(ScrubKind.length, upp) /
            scrubUnitsPerPixel(ScrubKind.length, upp);
        expect(travel, greaterThanOrEqualTo(kPxPerStep - 1e-9));
        expect(travel, lessThan(5 * kPxPerStep),
            reason: 'a notch must never become a swipe across the screen');
      }
    });

    test('one notch of a count field moves it by one, from any start', () {
      final upp = scrubUnitsPerPixel(ScrubKind.count, 0.05);
      const step = kCountScrubStep;
      expect(scrubbedValue(6, kPxPerStep, step, upp), 7);
      expect(scrubbedValue(6, -kPxPerStep, step, upp), 5);
      expect(scrubbedValue(6, 3 * kPxPerStep, step, upp), 9);
      expect(scrubbedValue(6, 2, step, upp), 6, reason: 'inside the notch');
    });

    test('the unit a field already prints decides its kind', () {
      expect(scrubKindForUnit('mm'), ScrubKind.length);
      expect(scrubKindForUnit('deg'), ScrubKind.angle);
      expect(scrubKindForUnit('°'), ScrubKind.angle);
      expect(scrubKindForUnit('ul'), ScrubKind.ratio);
      expect(scrubKindForUnit(null), ScrubKind.length);
    });
  });

  group('M180 — the range a drag may not leave', () {
    /// Drags [dx] across a count field starting at 4, clamped to 1..8.
    Future<String> dragCount(WidgetTester t, double dx) async {
      final app = AppState();
      final c = TextEditingController(text: '4');
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ScrubField(
              app: app,
              controller: c,
              kind: ScrubKind.count,
              min: 1,
              max: 8,
              child: const SizedBox(width: 200, height: 40),
            ),
          ),
        ),
      ));
      await t.drag(find.byType(ScrubField), Offset(dx, 0));
      await t.pump();
      return c.text;
    }

    testWidgets('a few notches move it a few whole steps', (t) async {
      expect(await dragCount(t, 3 * kPxPerStep), '7');
      expect(await dragCount(t, -2 * kPxPerStep), '2');
    });

    testWidgets('dragging to the moon stops at the ceiling, not past it',
        (t) async {
      expect(await dragCount(t, 400), '8');
      expect(await dragCount(t, -400), '1',
          reason: 'a pattern of zero occurrences is not a value to show');
    });
  });

  group('M180 — no number is left un-draggable', () {
    testWidgets('the rectangular pattern dialog', (t) async {
      final app = _sketchApp();
      app.pattern = PatternSession(Tool.patRect);
      await _pump(t, PatternDialog(app: app));
      _everyNumberScrubs(t, 'rectangular pattern');
    });

    testWidgets('the circular pattern dialog', (t) async {
      final app = _sketchApp();
      app.pattern = PatternSession(Tool.patCirc);
      await _pump(t, PatternDialog(app: app));
      _everyNumberScrubs(t, 'circular pattern');
    });

    testWidgets('the 2D fillet dialog', (t) async {
      final app = _sketchApp();
      app.filletSess = FilletSession(Tool.fillet);
      app.tool = Tool.fillet;
      await _pump(t, FilletChamferDialog(app: app));
      _everyNumberScrubs(t, '2D fillet');
    });

    testWidgets('the 2D chamfer dialog, in all three modes', (t) async {
      for (var mode = 0; mode < 3; mode++) {
        final app = _sketchApp();
        app.filletSess = FilletSession(Tool.chamfer, mode: mode);
        app.tool = Tool.chamfer;
        await _pump(t, FilletChamferDialog(app: app));
        _everyNumberScrubs(t, '2D chamfer mode $mode');
      }
    });

    testWidgets('the gear dialog, external and planetary', (t) async {
      for (final kind in [GearKind.external, GearKind.planetary]) {
        final app = _sketchApp();
        app.gear = GearSession(kind: kind, params: GearParams());
        await _pump(t, GearDialog(app: app, onDrag: (_) {}));
        _everyNumberScrubs(t, 'gear ($kind)');
      }
    });

    testWidgets('the Parameters window', (t) async {
      final app = _sketchApp();
      app.tool = Tool.line;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 0));
      app.tool = Tool.none;
      final e = app.current!.geometry.length - 1;
      app.pendingDim = Constraint(CType.dimension,
          pts: [PRef(e, 0), PRef(e, 1)],
          dimKind: 'dist',
          textPos: const Offset(0, -10));
      app.confirmDimensionText('40');
      app.addUserParam();
      await _pump(t, ParametersDialog(app: app, onDrag: (_) {}));
      // The Equation cells keep the TEXT keyboard on purpose (M171: formulas
      // need letters), so there is no numeric field to look for — what has to
      // be true is that every editable cell sits under a scrub, which declines
      // by itself the moment the cell holds a formula rather than a number.
      expect(find.byType(ScrubField), findsAtLeast(2),
          reason: 'the dimension row and the user-parameter row');
    });

    testWidgets('the parametric text window', (t) async {
      final app = _sketchApp();
      app.beginTextEdit(SketchText('Hello', 0, 0), isNew: true);
      await _pump(t, TextEditorWindow(app: app, onDrag: (_) {}));
      _everyNumberScrubs(t, 'text window');
    });

    test('and nowhere else in lib/ either', () {
      // The dialogs above are pumped; the modal prompts (polygon sides, the
      // equation curve's range) cannot be, and a value field written next year
      // will be in neither list. So: any FILE that holds a numeric field must
      // hold a ScrubField too. Coarse on purpose — it is the net under the
      // specific tests, not a replacement for them.
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (!src.contains('TextField(')) continue; // theme.dart defines it
        final numeric =
            RegExp(r'kValueKeyboard|numberWithOptions').hasMatch(src);
        if (numeric && !src.contains('ScrubField')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'a file with a number field and no scrub in sight');
    });
  });
}
