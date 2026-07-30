// M160 — a rollback that survives closing and re-opening the part.
//
// `openPart` calls `loadJson` and only THEN attaches the child sketches,
// because the sketch models live in their own files. While loadJson runs,
// `partTimeline` is therefore short by every unconsumed sketch row.
//
// Two decisions were being made against that short timeline:
//   * whether the End of Part marker is "at the end" — a marker genuinely
//     parked above the last feature looks like it covers everything when the
//     sketch rows are missing, so it was converted to the at-the-end sentinel
//     and the user's rollback was silently thrown away (a regression I
//     introduced in M154, which is what makes this worth a test rather than a
//     comment);
//   * `applyEndOfPart` itself, which decided `rolledBack` for a row set that
//     did not yet contain the sketches.
//
// Both now wait for `finishLoad`, called once the sketches are attached.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

Map<String, dynamic> _ex(String n, String sketch, int seq) => {
      'kind': 'extrude', 'name': n, 'seq': seq, 'body': 'Solid1',
      'sketch': sketch, 'output': seq == 1 ? 'new' : 'join',
      'profiles': [{'x': 0.0, 'y': 0.0, 'a': 100.0}], 'a': 5.0, 'b': 0.0,
    };

/// Replays what openPart does, in its order: loadJson, then attach the
/// sketches, then finishLoad.
PartModel _reopen(Map<String, dynamic> j, List<(String, int)> sketches) {
  final p = PartModel('P');
  p.loadJson(j);
  for (final (name, seq) in sketches) {
    p.childSketches
        .add(ChildSketch(SketchModel(name), 'xy', null, true, false, seq));
  }
  p.finishLoad();
  return p;
}

void main() {
  group('M160 — the marker is placed after the sketches arrive', () {
    test('a parked marker is still parked after a reopen', () {
      // Timeline once loaded: Extrusion1, Extrusion2, Sketch3 (unconsumed).
      // The marker sits above Extrusion2 — a real rollback.
      final p = _reopen({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0},
          {'name': 'Sketch3', 'plane': 'xy', 'seq': 4},
        ],
        'features': [_ex('Extrusion1', 'Sketch1', 1), _ex('Extrusion2', 'Sketch1', 3)],
        'eopNodes': 1,
        'seqNext': 5,
      }, [('Sketch1', 0), ('Sketch3', 4)]);

      expect(p.eopAfter, 1, reason: 'the park survived the load');
      expect(p.features.first.rolledBack, isFalse);
      expect(p.features.last.rolledBack, isTrue,
          reason: 'Extrusion2 is still below the marker');
      expect(p.sketchByName('Sketch3')!.rolledBack, isTrue,
          reason: 'and so is the sketch — applyEndOfPart saw it this time');
    });

    test('a marker parked at the LAST feature is not mistaken for the end', () {
      // The regression this file exists for. Features alone = 2 rows, so a
      // marker at 2 looks like "everything" until Sketch3 joins the timeline.
      final p = _reopen({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0},
          {'name': 'Sketch3', 'plane': 'xy', 'seq': 4},
        ],
        'features': [_ex('Extrusion1', 'Sketch1', 1), _ex('Extrusion2', 'Sketch1', 3)],
        'eopNodes': 2,
        'seqNext': 5,
      }, [('Sketch1', 0), ('Sketch3', 4)]);

      expect(p.eopAfter, 2, reason: 'NOT the at-the-end sentinel');
      expect(partIsRolledBack(p), isTrue);
      expect(p.features.any((f) => f.rolledBack), isFalse,
          reason: 'both features are above the marker');
      expect(p.sketchByName('Sketch3')!.rolledBack, isTrue,
          reason: 'only the sketch below it is rolled back');
    });

    test('a marker that really is at the end becomes the floating sentinel',
        () {
      final p = _reopen({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [_ex('Extrusion1', 'Sketch1', 1)],
        'eopNodes': 1,
        'seqNext': 2,
      }, [('Sketch1', 0)]);
      // Sketch1 is consumed, so the timeline is one row and the marker covers
      // it — that is the end, and it must float (M154).
      expect(p.eopAfter, kEopAtEnd);
      expect(partIsRolledBack(p), isFalse);
    });

    test('a document with no marker at all opens floating', () {
      final p = _reopen({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0}
        ],
        'features': [_ex('Extrusion1', 'Sketch1', 1)],
        'seqNext': 2,
      }, [('Sketch1', 0)]);
      expect(p.eopAfter, kEopAtEnd);
    });

    test('finishLoad is idempotent', () {
      final p = _reopen({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0},
          {'name': 'Sketch3', 'plane': 'xy', 'seq': 4},
        ],
        'features': [_ex('Extrusion1', 'Sketch1', 1), _ex('Extrusion2', 'Sketch1', 3)],
        'eopNodes': 2,
        'seqNext': 5,
      }, [('Sketch1', 0), ('Sketch3', 4)]);
      final before = p.eopAfter;
      p.finishLoad();
      p.finishLoad();
      expect(p.eopAfter, before);
      expect(p.sketchByName('Sketch3')!.rolledBack, isTrue);
    });

    test('the park round-trips through a save', () {
      final p = _reopen({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy', 'seq': 0},
          {'name': 'Sketch3', 'plane': 'xy', 'seq': 4},
        ],
        'features': [_ex('Extrusion1', 'Sketch1', 1), _ex('Extrusion2', 'Sketch1', 3)],
        'eopNodes': 1,
        'seqNext': 5,
      }, [('Sketch1', 0), ('Sketch3', 4)]);
      expect(p.toJson()['eopNodes'], 1);
      final again = _reopen(p.toJson(), [('Sketch1', 0), ('Sketch3', 4)]);
      expect(again.eopAfter, 1, reason: 'stable across repeated reopens');
    });
  });
}
