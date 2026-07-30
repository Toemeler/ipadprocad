// M154 — the End of Part marker must FLOAT at the bottom of the timeline.
//
// Reported from the device: "the first extrusion works great, but on the
// second extrusion the sketch is made below the EOP."
//
// Two leftovers of the row-count era caused it. `PartModel.appendFeature`
// already parks the marker correctly, but `commitExtrude` then overwrote its
// result with `eopAfter = partTimeline(p).length` — the right POSITION at that
// instant and the wrong VALUE, because the timeline grows. After the first
// extrusion the part is one row long (the sketch is consumed and nests under
// its feature), so the marker sat on row 1; the next sketch was appended as
// row 1, landed exactly on the cut and came out `rolledBack`: greyed in the
// browser, not drawn in 3D, while its editor was already open.
//
// And sketches had no equivalent of `appendFeature` at all, so the same thing
// happened whenever the marker was genuinely parked mid-tree.
//
// `loadJson` had the same pattern, which meant a SAVED part was affected on
// open rather than only after its first extrusion.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

// The part harness already exists in the M56 suite; importing it does not run
// its `main`, so the two files stay independent.
import 'm56_part_test.dart' show FakeKernel, addRectLines;

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m154_');
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

/// The rows the browser greys out and draws the End of Part bar above.
List<String> _belowMarker(PartModel p) {
  final tl = partTimeline(p);
  final cut = p.eopAfter < tl.length ? p.eopAfter : tl.length;
  return [for (var i = cut; i < tl.length; i++) tl[i].name];
}

void main() {
  group('M154 — the marker floats at the end', () {
    test('the sketch for the SECOND extrusion is NOT below the marker',
        () async {
      final app = _app();
      expect(await app.createNamedPart('P'), isTrue);
      final p = app.currentPart!;

      await _sketchAndExtrude(app, 'xy');
      expect(p.eopAtEnd, isTrue,
          reason: 'commitExtrude must leave the marker AT THE END, not on '
              'the row count it happens to have reached');

      // The second round: start a sketch for the next extrusion.
      app.startPartSketch();
      app.planePicked('yz');
      final cs2 = p.sketchByName(app.activeChild!.name)!;

      expect(_belowMarker(p), isEmpty,
          reason: 'the reported bug: Sketch2 sat below the End of Part row');
      expect(cs2.rolledBack, isFalse,
          reason: 'a sketch whose editor has just opened is not rolled back');

      // ... and it survives finishing and extruding.
      addRectLines(app.activeChild!, 0, 0, 5, 5, layer: app.editingLayer!);
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
      expect(p.eopAtEnd, isFalse);
      expect(p.features.last.rolledBack, isTrue);

      // Now start new work. Inventor admits it: the marker moves past the new
      // row, exactly as `appendFeature` does for a new feature.
      app.startPartSketch();
      app.planePicked('xz');
      expect(p.sketchByName(app.activeChild!.name)!.rolledBack, isFalse,
          reason: 'you cannot sit in the editor of a suppressed sketch');
      expect(_belowMarker(p), isEmpty);
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

      app.startPartSketch();
      app.planePicked('xz');
      expect(_belowMarker(p), isEmpty);
    });
  });

  group('M154 — loading does not pin the marker either', () {
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
      p.appendChildSketch(
          ChildSketch(SketchModel('Sketch2'), 'xy', null, true, false, 9));
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
