// M155 — body-name collisions across a save/load, and the second sketch that
// could not be picked.
//
// Both came out of a real device session (Part1.part.json, build 684d35e).
//
// NAMES. That file lists bodies Solid1, Solid2 and Solid3 and was saved with
// `"solidN": 1`. `nextSolidName()` was `'Solid${++solidN}'`, trusting a
// counter that revolve/sweep/loft/coil never bumped — they take their body
// name from their own dialog, which uses the non-consuming `peekSolidName`.
// Re-open that part, add a body, and it is handed "Solid2" a second time:
// two features then silently drive one body, which is a part that comes back
// different after a close and re-open.
//
// PICKING. `openExtrude` always sets `sketchName` to the newest sketch, and
// the viewport put that sketch first in its pick order and then `break`ed if
// the tap missed it — so with two sketches the second was unreachable.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m155_');
  app.partKernel = FakeKernel();
  return app;
}

Map<String, dynamic> _extrude(String name, String sketch, String body,
        {required int seq, String output = 'new'}) =>
    {
      'kind': 'extrude',
      'name': name,
      'seq': seq,
      'body': body,
      'sketch': sketch,
      'output': output,
      'profiles': [
        {'x': 0.0, 'y': 0.0, 'a': 100.0}
      ],
      'a': 5.0,
      'b': 0.0,
    };

void main() {
  group('M155 — body names survive a save and load', () {
    test('the counter is repaired from the document on open', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      // Exactly the shape of the reported file: three bodies, counter at 1.
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [
          _extrude('Extrusion1', 'Sketch1', 'Solid1', seq: 1),
          _extrude('Extrusion2', 'Sketch1', 'Solid2', seq: 3),
          _extrude('Extrusion3', 'Sketch1', 'Solid3', seq: 5),
        ],
        'featureN': 3,
        'solidN': 1, // the drifted counter, as actually written to disk
        'seqNext': 6,
      });
      expect(p.solidN, 3, reason: 'repaired from the bodies that exist');
      expect(p.nextSolidName(), 'Solid4',
          reason: 'must not hand out Solid2 a second time');
    });

    test('a fresh name never collides even with a lying counter', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [
          _extrude('Extrusion1', 'Sketch1', 'Solid1', seq: 1),
          _extrude('Extrusion2', 'Sketch1', 'Solid7', seq: 3),
        ],
        'solidN': 0,
        'seqNext': 4,
      });
      final taken = {for (final f in p.features) f.bodyName};
      final fresh = p.nextSolidName();
      expect(taken.contains(fresh), isFalse, reason: 'never an existing body');
      expect(p.nextSolidName(), isNot(fresh), reason: 'and never twice');
    });

    test('claimBodyName keeps the counter ahead of a dialog-set name', () {
      final p = PartModel('P');
      expect(p.nextSolidName(), 'Solid1');
      p.claimBodyName('Solid5'); // what a revolve dialog does
      expect(p.nextSolidName(), 'Solid6');
      p.claimBodyName('Body'); // a renamed body is not a counter
      expect(p.nextSolidName(), 'Solid7');
    });

    test('the counter round-trips through toJson/loadJson', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [
          _extrude('Extrusion1', 'Sketch1', 'Solid1', seq: 1),
          _extrude('Extrusion2', 'Sketch1', 'Solid2', seq: 3),
        ],
        'solidN': 1,
        'seqNext': 4,
      });
      final again = PartModel('P')
        ..childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'))
        ..loadJson(p.toJson());
      expect(again.solidN, 2, reason: 'the repair is what gets saved');
      expect(again.nextSolidName(), 'Solid3');
    });

    test('Extrusion numbering is repaired too', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [
          _extrude('Extrusion1', 'Sketch1', 'Solid1', seq: 1),
          _extrude('Extrusion4', 'Sketch1', 'Solid1', seq: 3, output: 'join'),
        ],
        'featureN': 1, // behind its own contents
        'seqNext': 4,
      });
      expect(p.nextFeatureName(), 'Extrusion5',
          reason: 'Extrusion2 would be free, but never a name already used');
      expect(p.features.any((f) => f.name == 'Extrusion5'), isFalse);
    });
  });

  group('M155 — a second sketch can be picked for an extrusion', () {
    /// The exact rule the viewport now uses to stop searching further sketches.
    bool lockedTo(ExtrudeSession s, String sketchName) =>
        s.sketchName == sketchName && !s.autoPicked && s.profiles.isNotEmpty;

    Future<AppState> twoSketches() async {
      final app = _app();
      await app.createNamedPart('P');
      for (final plane in ['xy', 'yz']) {
        app.startPartSketch();
        app.planePicked(plane);
        addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
        app.finishPartSketch();
      }
      return app;
    }

    test('the freshly opened dialog is not locked to the newest sketch',
        () async {
      final app = await twoSketches();
      final p = app.currentPart!;
      app.openExtrude();
      final s = app.extrudeSession!;
      expect(s.sketchName, p.childSketches.last.model.name,
          reason: 'it still pre-selects the newest sketch, as before');
      expect(lockedTo(s, s.sketchName!), isFalse,
          reason: 'the reported bug: this was always true, so the search '
              'broke on the first pass and no other sketch was reachable');
    });

    test('picking a profile in the OTHER sketch switches to it', () async {
      final app = await twoSketches();
      final p = app.currentPart!;
      final first = p.childSketches.first;
      app.openExtrude();
      final s = app.extrudeSession!;
      expect(s.sketchName, isNot(first.model.name));

      final regs = app.sessionRegions(first);
      expect(regs, isNotEmpty, reason: 'the first sketch has a closed profile');
      app.toggleSessionProfile(first.model.name, regs.first);

      expect(s.sketchName, first.model.name, reason: 'the extrusion moved');
      expect(s.profiles.length, 1);
      expect(s.autoPicked, isFalse);
    });

    test('once the user has picked, the session IS locked to that sketch',
        () async {
      final app = await twoSketches();
      final p = app.currentPart!;
      final first = p.childSketches.first;
      app.openExtrude();
      final s = app.extrudeSession!;
      app.toggleSessionProfile(first.model.name, app.sessionRegions(first).first);
      expect(lockedTo(s, first.model.name), isTrue,
          reason: 'an explicit pick still refuses to cross sketches');

      // ... and crossing is refused, exactly as before.
      final other = p.childSketches.last;
      app.toggleSessionProfile(other.model.name, app.sessionRegions(other).first);
      expect(s.sketchName, first.model.name, reason: 'the pick was rejected');
      expect(s.profiles.length, 1);
    });

    test('an empty session is never locked, so any sketch can start it',
        () async {
      final app = await twoSketches();
      app.openExtrude();
      final s = app.extrudeSession!;
      app.clearSessionProfiles();
      expect(lockedTo(s, s.sketchName ?? ''), isFalse);
    });
  });
}
