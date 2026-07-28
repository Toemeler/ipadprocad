// M91 — the browser as a TIMELINE, and the End of Part marker.
//
// Three behaviours are pinned:
//   * creation order rules the top level: a sketch made after an extrusion
//     appears BELOW it, not in a sketches block above everything;
//   * a shared sketch's top-level copy is pinned directly above the feature
//     that consumes it (Inventor: "a copy of the sketch displays above its
//     parent feature") — not at its own creation slot;
//   * End of Part rolls features back exactly as End of Sketch rolls layers
//     back, and a pre-M91 document opens with nothing rolled back and its old
//     browser order intact.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

ChildSketch _sketch(PartModel p, String name) {
  final cs = ChildSketch(SketchModel(name), 'xy', null, true, false, p.nextSeq());
  p.childSketches.add(cs);
  return cs;
}

ExtrudeFeature _feature(PartModel p, String name, String sketch) {
  final f = ExtrudeFeature(
    name: name,
    bodyName: 'Solid1',
    sketchName: sketch,
    profiles: const [],
  )..seq = p.nextSeq();
  p.features.add(f);
  p.eopAfter = partBuildOrder(p).length;
  applyEndOfPart(p);
  return f;
}

List<String> _rows(PartModel p) => [for (final n in partTimeline(p)) n.name];

void main() {
  group('the top level is chronological', () {
    test('a sketch made after an extrusion sits BELOW it', () {
      final p = PartModel('P');
      _sketch(p, 'Sketch1');
      _feature(p, 'Extrusion1', 'Sketch1');
      _sketch(p, 'Sketch2'); // made last -> bottom
      // Sketch1 was consumed, so it nests under Extrusion1 and is not a
      // top-level row at all.
      expect(_rows(p), ['Extrusion1', 'Sketch2']);
    });

    test('several unconsumed sketches keep their own order', () {
      final p = PartModel('P');
      _sketch(p, 'Sketch1');
      _feature(p, 'Extrusion1', 'Sketch1');
      _sketch(p, 'Sketch2');
      _sketch(p, 'Sketch3');
      expect(_rows(p), ['Extrusion1', 'Sketch2', 'Sketch3']);
    });

    test('an unconsumed sketch made FIRST stays above the extrusion', () {
      final p = PartModel('P');
      _sketch(p, 'Loose');
      _sketch(p, 'Sketch1');
      _feature(p, 'Extrusion1', 'Sketch1');
      expect(_rows(p), ['Loose', 'Extrusion1']);
    });
  });

  group('a shared sketch sits directly above its extrusion', () {
    test('pinned to the consumer, not to its own creation slot', () {
      final p = PartModel('P');
      final cs = _sketch(p, 'Sketch1'); // made FIRST
      _sketch(p, 'Sketch2');
      _feature(p, 'Extrusion1', 'Sketch1'); // made LAST, consumes Sketch1
      cs.shared = true;
      // By creation order alone Sketch1 would be first; sharing pins it
      // immediately above Extrusion1 instead.
      expect(_rows(p), ['Sketch2', 'Sketch1', 'Extrusion1']);
    });

    test('the pinned row is flagged as the shared copy', () {
      final p = PartModel('P');
      final cs = _sketch(p, 'Sketch1');
      _feature(p, 'Extrusion1', 'Sketch1');
      cs.shared = true;
      final nodes = partTimeline(p);
      expect(nodes.first.sketch, same(cs));
      expect(nodes.first.sharedCopy, isTrue);
      expect(nodes[1].isFeature, isTrue);
    });

    test('unsharing removes the top-level copy again', () {
      final p = PartModel('P');
      final cs = _sketch(p, 'Sketch1')..shared = true;
      _feature(p, 'Extrusion1', 'Sketch1');
      expect(_rows(p), ['Sketch1', 'Extrusion1']);
      cs.shared = false;
      expect(_rows(p), ['Extrusion1']);
    });
  });

  group('End of Part', () {
    PartModel _three() {
      final p = PartModel('P');
      for (var i = 1; i <= 3; i++) {
        _sketch(p, 'Sketch$i');
        _feature(p, 'Extrusion$i', 'Sketch$i');
      }
      return p;
    }

    test('a fresh part has nothing rolled back', () {
      final p = _three();
      expect(partIsRolledBack(p), isFalse);
      expect(p.features.where((f) => f.rolledBack), isEmpty);
    });

    test('moving it up suppresses everything below', () {
      final p = _three();
      p.eopAfter = 1;
      applyEndOfPart(p);
      final order = partBuildOrder(p);
      expect(order[0].rolledBack, isFalse);
      expect(order[1].rolledBack, isTrue);
      expect(order[2].rolledBack, isTrue);
      expect(partIsRolledBack(p), isTrue);
    });

    test('moving it to the top suppresses everything', () {
      final p = _three();
      p.eopAfter = 0;
      applyEndOfPart(p);
      expect(p.features.every((f) => f.rolledBack), isTrue);
    });

    test('moving it back to the end restores every feature', () {
      final p = _three();
      p.eopAfter = 0;
      applyEndOfPart(p);
      p.eopAfter = partBuildOrder(p).length;
      applyEndOfPart(p);
      expect(p.features.any((f) => f.rolledBack), isFalse);
    });

    test('a new feature lands ABOVE a parked marker, which moves down', () {
      final p = _three();
      p.eopAfter = 1;
      applyEndOfPart(p);
      _feature(p, 'Extrusion4', 'Sketch1'); // helper does what AppState does
      expect(p.eopAfter, partBuildOrder(p).length);
      expect(p.features.any((f) => f.rolledBack), isFalse);
    });

    test('it is only written to disk when it is NOT at the end', () {
      final p = _three();
      expect(p.toJson().containsKey('eop'), isFalse);
      p.eopAfter = 1;
      expect(p.toJson()['eop'], 1);
    });
  });

  group('pre-M91 documents', () {
    test('load with the old order and no rollback', () {
      // No 'seq' and no 'eop' anywhere — sketches were listed before features.
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      p.childSketches.add(ChildSketch(SketchModel('Sketch2'), 'xy'));
      p.loadJson({
        'sketches': [
          {'name': 'Sketch1', 'plane': 'xy'},
          {'name': 'Sketch2', 'plane': 'xy'},
        ],
        'features': [
          {'kind': 'extrude', 'name': 'Extrusion1', 'sketch': 'Sketch1'},
        ],
      });
      // Sketch1 is consumed and nests; Sketch2 keeps its old place ABOVE the
      // extrusion, because that is where the author last saw it.
      expect(_rows(p), ['Sketch2', 'Extrusion1']);
      expect(partIsRolledBack(p), isFalse);
    });
  });
}
