// M125 — the End of Part marker must FLOAT at the bottom of the timeline.
//
// Reported from the device: "the first extrusion works great, but on the
// second extrusion the sketch is made below the EOP."
//
// `commitExtrude` parked the marker with `eopAfter = partTimeline(p).length`.
// That is the right POSITION at that instant and the wrong VALUE: it pins the
// marker to the row it happened to reach, and the timeline grows. After the
// first extrusion the part is one row long, so the marker sat at 1 — and the
// sketch for the second extrusion, appended as row 1, came out below it:
// greyed in the browser, `rolledBack`, not drawn.
//
// The fix is [kEopAtEnd]: "at the end" is a sentinel, never a row count. Every
// consumer already clamps to the timeline length, so nothing else changes.
//
// The same pinning happened on load (a part with no stored marker got the row
// count) and after a drag to the very bottom, so both are pinned here too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

// The part harness already exists in the M56 suite; importing it does not run
// its `main`, so the two files stay independent.
import 'm56_part_test.dart' show FakeKernel, addRectLines;

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m125_');
  app.partKernel = FakeKernel();
  return app;
}

/// Sketch a rectangle on [plane] and extrude it — one full round of the
/// workflow the report describes.
Future<void> _sketchAndExtrude(AppState app, String plane,
    {double w = 20, double h = 10}) async {
  app.startPartSketch();
  app.planePicked(plane);
  addRectLines(app.activeChild!, 0, 0, w, h, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  await app.applyExtrude();
}

/// Which rows sit below the marker — the rows the browser greys out and draws
/// the End of Part bar above.
List<String> _belowMarker(PartModel p) {
  final tl = partTimeline(p);
  final cut = p.eopAfter < tl.length ? p.eopAfter : tl.length;
  return [for (var i = cut; i < tl.length; i++) tl[i].name];
}

void main() {
  group('M125 — the marker floats at the end', () {
    test('the sketch for the SECOND extrusion is NOT below the marker',
        () async {
      final app = _app();
      expect(await app.createNamedPart('P'), isTrue);
      final p = app.currentPart!;

      await _sketchAndExtrude(app, 'xy');
      expect(partTimeline(p).map((n) => n.name).toList(), ['Extrusion1'],
          reason: 'Sketch1 was consumed, so it nests under its feature');
      expect(partIsRolledBack(p), isFalse);

      // The second round: start a sketch for the next extrusion.
      app.startPartSketch();
      app.planePicked('yz');
      final sk2 = app.activeChild!;

      final cs2 = p.sketchByName(sk2.name)!;
      expect(_belowMarker(p), isEmpty,
          reason: 'the reported bug: Sketch2 sat below the End of Part row');
      expect(cs2.rolledBack, isFalse,
          reason: 'a sketch you have just opened the editor for is not '
              'rolled back');

      // ... and it survives finishing and extruding.
      addRectLines(sk2, 0, 0, 5, 5, layer: app.editingLayer!);
      app.finishPartSketch();
      expect(cs2.rolledBack, isFalse);
      app.openExtrude();
      await app.applyExtrude();
      expect(p.features.length, 2);
      expect(p.features.any((f) => f.rolledBack), isFalse);
      expect(_belowMarker(p), isEmpty);
    });

    test('a THIRD round stays clean too', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      await _sketchAndExtrude(app, 'xy');
      await _sketchAndExtrude(app, 'yz', w: 8, h: 8);
      await _sketchAndExtrude(app, 'xz', w: 4, h: 4);
      expect(p.features.length, 3);
      expect(p.features.any((f) => f.rolledBack), isFalse);
      expect(_belowMarker(p), isEmpty);
    });

    test('a sketch created while the marker is PARKED admits itself', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      await _sketchAndExtrude(app, 'xy');
      await _sketchAndExtrude(app, 'yz', w: 8, h: 8);
      expect(partTimeline(p).length, 2);

      // Park the marker above the second extrusion — a real rollback.
      app.setEndOfPart(1);
      expect(partIsRolledBack(p), isTrue);
      expect(p.features.last.rolledBack, isTrue);

      // Now start new work. Inventor admits it: the marker moves down, exactly
      // as it already did for a new FEATURE (M91).
      app.startPartSketch();
      app.planePicked('xz');
      expect(p.sketchByName(app.activeChild!.name)!.rolledBack, isFalse);
      expect(_belowMarker(p), isEmpty);
      expect(p.features.any((f) => f.rolledBack), isFalse,
          reason: 'admitting the new row un-rolls what was suppressed');
    });

    test('parking the marker still works and still persists', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      await _sketchAndExtrude(app, 'xy');
      await _sketchAndExtrude(app, 'yz', w: 8, h: 8);

      app.setEndOfPart(1);
      expect(p.eopAfter, 1, reason: 'a genuine park keeps its row index');
      expect(p.toJson()['eopNodes'], 1);
      expect(_belowMarker(p), ['Extrusion2']);
    });

    test('dragging the marker to the BOTTOM leaves it floating', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      await _sketchAndExtrude(app, 'xy');
      await _sketchAndExtrude(app, 'yz', w: 8, h: 8);

      app.setEndOfPart(1);
      app.setEndOfPart(partTimeline(p).length); // dragged all the way down
      expect(p.eopAfter, kEopAtEnd,
          reason: 'the bottom is "the end", not "row 2"');
      expect(p.toJson().containsKey('eopNodes'), isFalse);

      // The next sketch is therefore still above it.
      app.startPartSketch();
      app.planePicked('xz');
      expect(_belowMarker(p), isEmpty);
    });
  });

  group('M125 — loading does not pin the marker either', () {
    test('a part saved with the marker at the end reopens floating', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [
          {'kind': 'extrude', 'name': 'Extrusion1', 'sketch': 'Sketch1'},
        ],
        // no 'eopNodes' — the marker was at the end when this was written
      });
      expect(p.eopAfter, kEopAtEnd);

      // A sketch added after reopening is above the marker, not below it.
      p.childSketches
          .add(ChildSketch(SketchModel('Sketch2'), 'xy', null, true, false, 9));
      applyEndOfPart(p);
      expect(p.sketchByName('Sketch2')!.rolledBack, isFalse);
      expect(_belowMarker(p), isEmpty);
    });

    test('a genuine park still loads as a park', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [
          {'kind': 'extrude', 'name': 'Extrusion1', 'sketch': 'Sketch1'},
          {'kind': 'extrude', 'name': 'Extrusion2', 'sketch': 'Sketch1'},
        ],
        'eopNodes': 1,
      });
      expect(p.eopAfter, 1);
      expect(p.features.first.rolledBack, isFalse);
      expect(p.features.last.rolledBack, isTrue);
    });

    test('a pre-M113 file whose marker was at the end reopens floating', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [
          {'kind': 'extrude', 'name': 'Extrusion1', 'sketch': 'Sketch1'},
          {'kind': 'extrude', 'name': 'Extrusion2', 'sketch': 'Sketch1'},
        ],
        'eop': 2, // old meaning: both features built == at the end
      });
      expect(p.eopAfter, kEopAtEnd);
      expect(p.features.any((f) => f.rolledBack), isFalse);
    });
  });
}
