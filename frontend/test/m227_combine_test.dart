// M227 — Inventor's Modify > Combine: a boolean between solid BODIES.
//
// Extrude has carried Join / Cut / Intersect since M62, but only against the
// body its own profile builds into. Once two bodies exist there was no way to
// say "take this one out of that one" — the operation Inventor keeps in Modify
// for exactly that case.
//
// The interesting part is not the boolean (the kernel has had all three since
// M62) but the DEPENDENCY: a Combine is the first feature that reads a body
// other than its own, and the rebuild key had no way to see that. This file
// pins the arithmetic and the key.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'm56_part_test.dart' show FakeKernel;

/// A part with two independent bodies, each one extrusion, built.
(PartModel, FakeKernel) _twoBodies() {
  final k = FakeKernel();
  final p = PartModel('P');
  p.childSketches.add(ChildSketch(_sketch('Sketch1'), 'xy'));
  for (final (name, body) in [('Extrusion1', 'Solid1'), ('Extrusion2', 'Solid2')]) {
    final f = ExtrudeFeature(
      name: name,
      bodyName: body,
      sketchName: 'Sketch1',
      profiles: [ProfileSel(10, 5, 200)],
      distanceA: 10,
    )..output = 'new';
    f.seq = p.nextSeq();
    p.appendFeature(f);
  }
  recomputeAllFeatures(p, k);
  return (p, k);
}

SketchModel _sketch(String name) {
  final s = SketchModel(name)..layers.add('Layer 1');
  s.engine.setCurrentLayer('Layer 1');
  s.engine.addLine(0, 0, 20, 0);
  s.engine.addLine(20, 0, 20, 10);
  s.engine.addLine(20, 10, 0, 10);
  s.engine.addLine(0, 10, 0, 0);
  s.refresh();
  return s;
}

CombineFeature _combine(PartModel p,
    {String op = 'cut', bool keepTool = false, List<String>? tools}) {
  final f = CombineFeature(
    name: 'Combine1',
    bodyName: 'Solid1',
    tools: tools ?? ['Solid2'],
    op: op,
    keepTool: keepTool,
  );
  f.seq = p.nextSeq();
  p.appendFeature(f);
  return f;
}

void main() {
  group('M227 — the boolean', () {
    test('cut takes the tool body out of the base', () {
      final (p, k) = _twoBodies();
      final f = _combine(p);
      recomputeAllFeatures(p, k);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(k.cuts, 1);
      expect(f.solid, isNotNull);
      final tool = p.features.firstWhere((x) => x.bodyName == 'Solid2');
      expect(tool.consumedByJoin, isTrue,
          reason: 'the tool is folded away — one body comes out');
      expect(p.bodyNames, ['Solid1']);
    });

    test('join and intersect reach the right kernel call', () {
      final (p1, k1) = _twoBodies();
      _combine(p1, op: 'join');
      recomputeAllFeatures(p1, k1);
      expect(k1.fusions, 1);

      final (p2, k2) = _twoBodies();
      _combine(p2, op: 'intersect');
      recomputeAllFeatures(p2, k2);
      expect(k2.intersects, 1);
    });

    test('Keep Toolbody leaves the tool standing', () {
      final (p, k) = _twoBodies();
      final f = _combine(p, keepTool: true);
      recomputeAllFeatures(p, k);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      final tool = p.features.firstWhere((x) => x.bodyName == 'Solid2');
      expect(tool.consumedByJoin, isFalse);
      expect(p.bodyNames, ['Solid1', 'Solid2']);
    });

    test('several tools fold in one after another', () {
      final k = FakeKernel();
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(_sketch('Sketch1'), 'xy'));
      for (final (name, body) in [
        ('Extrusion1', 'Solid1'),
        ('Extrusion2', 'Solid2'),
        ('Extrusion3', 'Solid3'),
      ]) {
        final f = ExtrudeFeature(
          name: name,
          bodyName: body,
          sketchName: 'Sketch1',
          profiles: [ProfileSel(10, 5, 200)],
        )..output = 'new';
        f.seq = p.nextSeq();
        p.appendFeature(f);
      }
      recomputeAllFeatures(p, k);
      final f = _combine(p, tools: ['Solid2', 'Solid3']);
      recomputeAllFeatures(p, k);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(k.cuts, 2, reason: 'one boolean per tool');
      expect(p.bodyNames, ['Solid1']);
    });
  });

  group('M227 — what it refuses', () {
    test('a body cannot be combined with itself', () {
      final (p, k) = _twoBodies();
      final f = _combine(p, tools: ['Solid1']);
      recomputeAllFeatures(p, k);
      expect(f.solid, isNull);
      expect(f.computeError, contains('with itself'));
    });

    test('no tool at all', () {
      final (p, k) = _twoBodies();
      final f = _combine(p, tools: []);
      recomputeAllFeatures(p, k);
      expect(f.solid, isNull);
      expect(f.computeError, contains('no tool body'));
    });

    test('a tool built LATER is not a tool yet', () {
      final (p, k) = _twoBodies();
      // Move the second body's extrusion after the combine.
      final f = _combine(p);
      final later = p.features.firstWhere((x) => x.bodyName == 'Solid2');
      later.seq = f.seq + 1;
      recomputeAllFeatures(p, k);

      expect(f.solid, isNull);
      expect(f.computeError, contains('nothing built before this feature'),
          reason: 'combining with a body from the future is not an answer');
    });

    test('a kernel that refuses reports the kernel, not a guess', () {
      final (p, k) = _twoBodies();
      final f = _combine(p);
      k.fail = true;
      recomputeAllFeatures(p, k, force: true);
      expect(f.solid, isNull);
      expect(f.computeError, isNotNull);
    });
  });

  group('M227 — the rebuild key sees the OTHER body', () {
    test('changing the tool body rebuilds the combine', () {
      final (p, k) = _twoBodies();
      final f = _combine(p);
      recomputeAllFeatures(p, k);
      expect(k.cuts, 1);
      final sig = f.builtSig;
      expect(sig, isNotNull);

      // A no-op pass must NOT redo the boolean.
      recomputeAllFeatures(p, k);
      expect(k.cuts, 1, reason: 'nothing changed, nothing rebuilds');

      // Now edit the TOOL body. Nothing in the combine's own numbers changed.
      final tool = p.features.whereType<ExtrudeFeature>()
          .firstWhere((x) => x.bodyName == 'Solid2');
      tool.distanceA = 25;
      recomputeAllFeatures(p, k);

      expect(k.cuts, 2,
          reason: 'the combine reads that body, so it has to run again — '
              'without inputBodies in the key it would keep the old solid');
      expect(f.builtSig, isNot(sig));
    });

    test('a feature that reads no other body is unaffected', () {
      final (p, k) = _twoBodies();
      final ex = p.features.first;
      expect(ex.inputBodies, isEmpty);
      final sig = ex.builtSig;
      recomputeAllFeatures(p, k);
      expect(ex.builtSig, sig, reason: 'the key of everything else is stable');
    });
  });

  group('M227 — it is a feature like the others', () {
    test('round-trips through JSON', () {
      final f = CombineFeature(
        name: 'Combine2',
        bodyName: 'Solid3',
        tools: ['Solid1', 'Solid2'],
        op: 'intersect',
        keepTool: true,
      );
      f.seq = 11;
      final back = PartFeature.fromJson(f.toJson()) as CombineFeature;
      expect(back.kind, 'combine');
      expect(back.bodyName, 'Solid3');
      expect(back.tools, ['Solid1', 'Solid2']);
      expect(back.op, 'intersect');
      expect(back.keepTool, isTrue);
      expect(back.seq, 11);
      expect(back.ownSig(), f.ownSig());
      expect(back.inputBodies, ['Solid1', 'Solid2']);
    });

    test('the key notices the operation and Keep Toolbody', () {
      final a = CombineFeature(name: 'C', bodyName: 'S1', tools: ['S2']);
      final b = CombineFeature(
          name: 'C', bodyName: 'S1', tools: ['S2'], op: 'join');
      final c = CombineFeature(
          name: 'C', bodyName: 'S1', tools: ['S2'], keepTool: true);
      expect(a.ownSig(), isNot(b.ownSig()));
      expect(a.ownSig(), isNot(c.ownSig()));
    });

    test('a pattern refuses it, like every body-changing feature', () {
      final (p, k) = _twoBodies();
      final f = _combine(p);
      recomputeAllFeatures(p, k);
      final pat = PatternFeature(
        name: 'Pattern1',
        bodyName: 'Solid1',
        mode: PatternKind.rectangular,
        sources: [f.name],
      );
      pat.seq = p.nextSeq();
      p.appendFeature(pat);
      recomputeAllFeatures(p, k);
      expect(pat.computeError, contains('changes the body'));
    });
  });
}

