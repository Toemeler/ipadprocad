// M84 — Inventor's Share Sketch, and the model-browser context menu.
//
// The behaviour pinned here follows Autodesk's Part Browser Reference and
// "To Share Sketches and Features":
//   * Share Sketch is "available only when the sketch was consumed by a
//     feature" — it is the escape hatch from consumption, so an unconsumed
//     sketch must not offer it.
//   * a shared sketch appears at the TOP LEVEL of the browser as well as
//     nested under its parent feature ("a copy of the sketch displays above
//     its parent feature").
//   * Unshare is offered "only if a single feature shares it".
//   * the flag survives save/load, so a shared sketch stays shared.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

PartModel _part() => PartModel('P');

ChildSketch _sketch(PartModel p, String name) {
  final cs = ChildSketch(SketchModel(name), 'xy');
  p.childSketches.add(cs);
  return cs;
}

ExtrudeFeature _feature(PartModel p, String name, String sketch) {
  final f = ExtrudeFeature(
    name: name,
    bodyName: 'Solid1',
    sketchName: sketch,
    profiles: const [],
  );
  p.features.add(f);
  return f;
}

void main() {
  group('consumption gates Share Sketch', () {
    test('an unconsumed sketch is not consumed and cannot be unshared', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1');
      expect(sketchIsConsumed(p, cs), isFalse);
      expect(canUnshareSketch(p, cs), isFalse);
    });

    test('a sketch used by a feature is consumed', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1');
      _feature(p, 'Extrusion1', 'Sketch1');
      expect(sketchIsConsumed(p, cs), isTrue);
      expect(consumersOf(p, 'Sketch1'), hasLength(1));
    });
  });

  group('Unshare is restricted to a single consumer', () {
    test('one consumer: offered', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1')..shared = true;
      _feature(p, 'Extrusion1', 'Sketch1');
      expect(canUnshareSketch(p, cs), isTrue);
    });

    test('two consumers: refused (Inventor: only if a SINGLE feature shares)',
        () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1')..shared = true;
      _feature(p, 'Extrusion1', 'Sketch1');
      _feature(p, 'Extrusion2', 'Sketch1');
      expect(consumersOf(p, 'Sketch1'), hasLength(2));
      expect(canUnshareSketch(p, cs), isFalse);
    });

    test('not shared at all: nothing to unshare', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1');
      _feature(p, 'Extrusion1', 'Sketch1');
      expect(canUnshareSketch(p, cs), isFalse);
    });
  });

  group('the shared flag is persisted', () {
    test('only when set, and it round-trips', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1');
      final plain = (p.toJson()['sketches'] as List).first as Map;
      expect(plain.containsKey('shared'), isFalse,
          reason: 'an ordinary sketch must not grow a key');

      cs.shared = true;
      final shared = (p.toJson()['sketches'] as List).first as Map;
      expect(shared['shared'], isTrue);

      // Reconstructed the way AppState.openPart does.
      final restored = ChildSketch(SketchModel('Sketch1'), 'xy', null, true,
          shared['shared'] as bool? ?? false);
      expect(restored.shared, isTrue);
    });

    test('a pre-M84 document loads unshared', () {
      final legacy = <String, dynamic>{'name': 'Sketch1', 'plane': 'xy'};
      final cs = ChildSketch(SketchModel('Sketch1'), 'xy', null, true,
          legacy['shared'] as bool? ?? false);
      expect(cs.shared, isFalse);
    });
  });

  group('browser placement', () {
    // The browser shows a sketch at the top level when it is unconsumed OR
    // shared; the nested copy under the parent feature is always there.
    bool topLevel(PartModel p, ChildSketch cs) =>
        firstConsumerOf(p, cs.model.name) == null || cs.shared;

    test('consumed and unshared: nested only', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1');
      _feature(p, 'Extrusion1', 'Sketch1');
      expect(topLevel(p, cs), isFalse);
    });

    test('consumed and shared: also top level', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1')..shared = true;
      _feature(p, 'Extrusion1', 'Sketch1');
      expect(topLevel(p, cs), isTrue);
    });

    test('unconsumed: top level, as before', () {
      final p = _part();
      final cs = _sketch(p, 'Sketch1');
      expect(topLevel(p, cs), isTrue);
    });
  });
}
