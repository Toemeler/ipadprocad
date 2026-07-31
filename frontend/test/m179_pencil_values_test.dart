// M179 — the Pencil scrubs a number, it does not write on it; and a scrub
// drives the model while the finger is still down.
//
// Reported from the device, in one breath:
//   "with the pencil it always wants to use this handwrite to text input ...
//    this should never come on number input fields"
//   "while I drag left or right to change the number the sketch should live
//    apply the dimension, the extrusion should live display the height"
//
// Two halves, and they are the same interaction:
//
//   * iPadOS makes every text field a Scribble target, and Scribble claims the
//     Pencil stroke before any gesture in the Flutter tree sees it. On a number
//     field that steals exactly the gesture M172 put there. Value fields opt
//     out; text fields keep it.
//   * The scrub then has to be worth having: each detent applies a REAL value,
//     so the sketch re-solves and the extrude preview rebuilds under the
//     finger. What must NOT happen per detent is a journal entry or a message,
//     which is what AppState's live-edit bracket is for.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/properties_panel.dart';
import 'package:prototype/widgets/scrub_field.dart';
import 'package:prototype/widgets/work_plane_offset_field.dart';

AppState _sketchApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

int _drawLine(AppState app, Offset a, Offset b) {
  app.tool = Tool.line;
  app.toolClick(a);
  app.toolClick(b);
  app.tool = Tool.none;
  return app.current!.geometry.length - 1;
}

double _lineLen(AppState app, int e) {
  final g = app.current!.geometry[e];
  return (Offset(g.data[0], g.data[1]) - Offset(g.data[2], g.data[3])).distance;
}

Constraint _dimLine(AppState app, int e, String text) {
  final d = Constraint(CType.dimension,
      pts: [PRef(e, 0), PRef(e, 1)],
      dimKind: 'dist',
      textPos: const Offset(0, -10));
  app.pendingDim = d;
  app.confirmDimensionText(text);
  return d;
}

/// Every TextField in the widget tree, with its handwriting setting.
Iterable<bool> _handwriting(WidgetTester t) => t
    .widgetList<TextField>(find.byType(TextField))
    .map((f) => f.stylusHandwritingEnabled);

void main() {
  group('M179 — no handwriting on a number field', () {
    test('the rule has one home, and it says no', () {
      expect(kValueHandwriting, isFalse);
    });

    testWidgets('a feature dialog\'s value field refuses Scribble', (t) async {
      final app = AppState();
      final c = TextEditingController(text: '12');
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: panelValueField(c, 'mm', (_) {}, app: app),
        ),
      ));
      expect(_handwriting(t), everyElement(isFalse));
    });

    testWidgets('the work plane offset field refuses Scribble', (t) async {
      final app = AppState();
      final p = PartModel('P');
      final w = WorkPlane('Work Plane1', 1, WorkPlaneKind.offset,
          'Offset 10.00 mm from XY', offsetPlaneFrame(planeFrame('xy'), 10),
          base: planeFrame('xy'), offset: 10);
      p.workPlanes.add(w);
      app.parts['P'] = p;
      app.curTab = 'P';
      app.selectWorkPlane(w);
      app.workPlaneOffsetEditing = true;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [WorkPlaneOffsetField(app: app)]),
        ),
      ));
      expect(_handwriting(t), everyElement(isFalse));
    });

    test('every number field in the app opts out, not just the ones above', () {
      // A source scan, deliberately: the failure this guards against is a NEW
      // value field written next year that asks for the numeric pad and
      // forgets the other half. That one would look right in every widget test
      // ever written, and be wrong on the device only, with a Pencil in hand.
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        for (final call in _textFieldCalls(src)) {
          final numeric = call.args.contains('kValueKeyboard') ||
              call.args.contains('numberWithOptions');
          if (!numeric) continue; // a text field: Scribble is welcome there
          if (call.args.contains('stylusHandwritingEnabled')) continue;
          offenders.add('${f.path}: ${_firstLine(call.args)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'a number field must pass '
              'stylusHandwritingEnabled: kValueHandwriting');
    });
  });

  group('M179 — a live gesture is one edit, and it is quiet', () {
    test('the bracket counts, so a nested one cannot end it early', () {
      final app = AppState();
      expect(app.liveEditing, isFalse);
      app.beginLiveEdit();
      app.beginLiveEdit();
      app.endLiveEdit();
      expect(app.liveEditing, isTrue, reason: 'the outer bracket still holds');
      app.endLiveEdit();
      expect(app.liveEditing, isFalse);
    });

    test('an unbalanced end cannot switch the journal off for good', () {
      final app = AppState();
      app.endLiveEdit();
      app.endLiveEdit();
      expect(app.liveEditing, isFalse);
      app.beginLiveEdit();
      expect(app.liveEditing, isTrue,
          reason: 'a floored counter still opens on the next begin');
    });

    test('messages are held back while a value is being dragged', () {
      final app = AppState();
      app.beginLiveEdit();
      app.toast('Value cannot be satisfied with the current constraints.');
      expect(app.message, isNull);
      app.endLiveEdit();
      app.toast('said once, on release');
      expect(app.message, 'said once, on release');
    });

    test('edits inside the bracket cost no journal steps; the release costs one',
        () {
      final app = _sketchApp();
      final e = _drawLine(app, const Offset(0, 0), const Offset(40, 0));
      final d = _dimLine(app, e, '40');
      final before = app.current!.undoDepth;

      // Thirty detents of a drag: every one really solves.
      app.beginLiveEdit();
      for (var v = 41; v <= 70; v++) {
        app.setDimensionText(d, '$v');
      }
      expect(_lineLen(app, e), closeTo(70, 1e-6),
          reason: 'the sketch follows the drag, it does not wait for release');
      expect(app.current!.undoDepth, before,
          reason: 'a drag must not bury the journal under one step per detent');

      // Release: journalling back on, one commit, one step.
      app.endLiveEdit();
      app.setDimensionText(d, '70');
      expect(app.current!.undoDepth, before + 1);

      app.undo();
      expect(_lineLen(app, e), closeTo(40, 1e-6),
          reason: 'one Ctrl+Z takes the whole drag back');
    });

    test('revert puts back the state the drag never journalled over', () {
      final app = _sketchApp();
      final e = _drawLine(app, const Offset(0, 0), const Offset(40, 0));
      final d = _dimLine(app, e, '40');
      final depth = app.current!.undoDepth;

      app.beginLiveEdit();
      app.setDimensionText(d, '95');
      expect(_lineLen(app, e), closeTo(95, 1e-6));
      app.endLiveEdit();

      // Esc out of the box.
      app.revertToLastCheckpoint();
      expect(_lineLen(app, e), closeTo(40, 1e-6));
      expect(app.current!.undoDepth, depth,
          reason: 'reverting is not an edit, so it spends no journal step');
    });

    test('a dimension CREATED mid-drag goes away with the revert too', () {
      // Placing a dimension and dragging it to size is one gesture: the
      // dimension has to exist for the sketch to have anything to drive, and
      // Esc still has to mean "as if I never placed it".
      final app = _sketchApp();
      final e = _drawLine(app, const Offset(0, 0), const Offset(40, 0));
      final s = app.current!;
      final consBefore = s.constraints.length;

      app.beginLiveEdit();
      final d = _dimLine(app, e, '60'); // what the first detent does
      expect(s.constraints.contains(d), isTrue);
      expect(_lineLen(app, e), closeTo(60, 1e-6));
      app.endLiveEdit();

      app.revertToLastCheckpoint();
      expect(s.constraints.length, consBefore);
      expect(_lineLen(app, e), closeTo(40, 1e-6));
    });
  });

  group('M179 — the scrub gesture brackets itself', () {
    testWidgets('live while the finger is down, released when it lifts',
        (t) async {
      final app = AppState();
      app.zoom = 20; // 1 px = 0.05 mm -> 1 mm detents
      final c = TextEditingController(text: '10');
      final commits = <String>[];
      final liveDuringCommit = <bool>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ScrubField(
              app: app,
              controller: c,
              onCommit: (v) {
                commits.add(v);
                liveDuringCommit.add(app.liveEditing);
              },
              child: const SizedBox(width: 120, height: 30),
            ),
          ),
        ),
      ));

      expect(app.liveEditing, isFalse);
      final g = await t.startGesture(t.getCenter(find.byType(ScrubField)));
      for (var i = 0; i < 5; i++) {
        await g.moveBy(const Offset(20, 0));
        await t.pump();
      }
      expect(app.liveEditing, isTrue, reason: 'the drag holds the bracket');
      expect(commits.length, greaterThan(1),
          reason: 'every detent applies, not just the release');
      expect(liveDuringCommit.every((v) => v), isTrue,
          reason: 'nothing mid-drag may be journalled');

      await g.up();
      await t.pump();
      expect(app.liveEditing, isFalse);
      expect(liveDuringCommit.last, isFalse,
          reason: 'the release re-commits with the journal back on — that is '
              'the call that becomes the undo step');
      expect(commits.last, c.text);
    });

    testWidgets('a field torn down mid-drag releases the bracket', (t) async {
      final app = AppState();
      app.zoom = 20;
      final c = TextEditingController(text: '10');
      var show = true;
      late StateSetter setOuter;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (ctx, set) {
            setOuter = set;
            return Center(
              child: show
                  ? ScrubField(
                      app: app,
                      controller: c,
                      child: const SizedBox(width: 120, height: 30),
                    )
                  : const SizedBox(width: 120, height: 30),
            );
          }),
        ),
      ));

      final g = await t.startGesture(t.getCenter(find.byType(ScrubField)));
      await g.moveBy(const Offset(40, 0));
      await t.pump();
      expect(app.liveEditing, isTrue);

      setOuter(() => show = false);
      await t.pump();
      expect(app.liveEditing, isFalse,
          reason: 'a dialog closing mid-drag must not leave the journal off '
              'for the rest of the session');
      await g.up();
    });

    testWidgets('an expression is never scrubbed, and never brackets',
        (t) async {
      final app = AppState();
      final c = TextEditingController(text: 'd0 + 5');
      final commits = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ScrubField(
              app: app,
              controller: c,
              onCommit: commits.add,
              child: const SizedBox(width: 120, height: 30),
            ),
          ),
        ),
      ));
      await t.drag(find.byType(ScrubField), const Offset(90, 0));
      await t.pump();
      expect(c.text, 'd0 + 5', reason: 'scrubbing would destroy the formula');
      expect(commits, isEmpty);
      expect(app.liveEditing, isFalse);
    });
  });
}

class _Call {
  final String args;
  _Call(this.args);
}

/// The argument text of every `TextField(...)` in [src], paren-balanced.
Iterable<_Call> _textFieldCalls(String src) sync* {
  const needle = 'TextField(';
  var i = src.indexOf(needle);
  while (i >= 0) {
    var depth = 1;
    var j = i + needle.length;
    while (j < src.length && depth > 0) {
      final ch = src[j];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      j++;
    }
    yield _Call(src.substring(i + needle.length, j));
    i = src.indexOf(needle, j);
  }
}

String _firstLine(String args) {
  final t = args.trim().split('\n').first.trim();
  return t.length > 60 ? '${t.substring(0, 60)}…' : t;
}
