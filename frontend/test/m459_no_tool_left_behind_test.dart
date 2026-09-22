// M459 — the coverage gate.
//
// "The AI should be able to use every single 2D and 3D tool available in the
// app." M456 to M458 closed the gap that existed. This file is what keeps it
// closed: it reads the app's OWN registries — the Tool enum the sketcher
// dispatches on, the constraint enum, and the feature kinds the timeline can
// hold — and fails when one of them has no way for the assistant to reach it.
//
// Without this, the answer decays the moment somebody adds a tool. With it,
// adding one and forgetting the assistant is a red test naming the tool.
//
// Two tools are DELIBERATELY not reachable and are named here so that
// "excluded" is a decision with a reason rather than an oversight.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart' show Tool;
import 'package:prototype/constraints.dart' show CType;

void main() {
  /// Sketch tools the assistant reaches through a named op rather than
  /// through `sketch_tool`, so the catalogue does not need to list them.
  const byNamedOp = <Tool, String>{
    Tool.text: 'sketch_text',
    Tool.gear: 'sketch_gear',
    Tool.project: 'sketch_project',
    Tool.move: 'sketch_modify action=move',
    Tool.mcopy: 'sketch_modify action=copy',
    Tool.mrotate: 'sketch_modify action=rotate',
    Tool.mscale: 'sketch_modify action=scale',
    Tool.mstretch: 'sketch_modify action=stretch',
    Tool.moffset: 'sketch_modify action=offset',
    Tool.trim: 'sketch_modify action=trim',
    Tool.extendT: 'sketch_modify action=extend',
    Tool.split: 'sketch_modify action=split',
    Tool.mirror: 'sketch_modify action=mirror',
    Tool.patRect: 'sketch_pattern kind=rect',
    Tool.patCirc: 'sketch_pattern kind=circ',
    Tool.dimension: 'sketch_dimension',
    Tool.cCoincident: 'sketch_constrain type=coincident',
    Tool.cCollinear: 'sketch_constrain type=collinear',
    Tool.cConcentric: 'sketch_constrain type=concentric',
    Tool.cFix: 'sketch_constrain type=fix',
    Tool.cParallel: 'sketch_constrain type=parallel',
    Tool.cPerpendicular: 'sketch_constrain type=perpendicular',
    Tool.cHorizontal: 'sketch_constrain type=horizontal',
    Tool.cVertical: 'sketch_constrain type=vertical',
    Tool.cTangent: 'sketch_constrain type=tangent',
    Tool.cSmooth: 'sketch_constrain type=smooth',
    Tool.cSymmetric: 'sketch_constrain type=symmetric',
    Tool.cEqual: 'sketch_constrain type=equal',
  };

  /// The exclusions, each with the reason it is one.
  const excluded = <Tool, String>{
    Tool.none: 'not a tool — the absence of one',
    Tool.splineFree:
        'a freehand STROKE, fitted from a drag. Its committed output is an '
        'ordinary interpolation spline (tools.dart says so), which the '
        'assistant reaches as "spline" — there is no gesture to replay.',
  };

  group('every 2D tool is reachable', () {
    test('no Tool is left without a way in', () {
      final missing = <String>[];
      for (final t in Tool.values) {
        if (excluded.containsKey(t)) continue;
        if (byNamedOp.containsKey(t)) continue;
        if (AiCadSketch.tools.containsValue(t)) continue;
        missing.add(t.name);
      }
      expect(missing, isEmpty,
          reason: 'the assistant cannot reach these sketch tools: '
              '${missing.join(", ")}. Add them to AiCadSketch.tools, or to a '
              'named op, or to `excluded` with the reason.');
    });

    test('the instructions SPELL every tool name, not "among them"', () {
      // A name the model is never shown is a name it has to guess, and a
      // guessed name is a refusal. The prose used to say "the five slot
      // forms" without naming one of them, so slot_overall was unaskable in
      // practice. Every key of the catalogue now appears verbatim.
      final unnamed = [
        for (final n in AiCadSketch.tools.keys)
          if (!kAiActionInstructions.contains(n)) n
      ];
      expect(unnamed, isEmpty,
          reason: 'sketch_tool accepts these and the instructions never say '
              'so: ${unnamed.join(", ")}');
    });

    test('and every sketch_modify action, and every constraint', () {
      const actions = [
        'move', 'copy', 'rotate', 'scale', 'mirror', 'offset', 'trim',
        'split', 'extend',
      ];
      for (final a in actions) {
        expect(kAiActionInstructions, contains(a), reason: 'action $a');
      }
      final unnamed = [
        for (final k in AiCadConstrain.kinds.keys)
          if (!kAiActionInstructions.contains(k)) k
      ];
      expect(unnamed, isEmpty, reason: 'constraints: ${unnamed.join(", ")}');
    });

    test('every exclusion carries a reason', () {
      for (final entry in excluded.entries) {
        expect(entry.value.length, greaterThan(20),
            reason: '${entry.key.name} is excluded without saying why');
      }
    });

    test('the named-op map points at ops that exist', () {
      for (final entry in byNamedOp.entries) {
        final op = entry.value.split(' ').first;
        expect(kAiOps, contains(op),
            reason: '${entry.key.name} claims to be reachable via "$op"');
      }
    });
  });

  group('every constraint is reachable', () {
    test('no CType is left without a name', () {
      final missing = <String>[];
      for (final t in CType.values) {
        // `dimension` is its own op; `pattern` is a binding the app creates
        // for its own sketch patterns, never something a user asks for.
        if (t == CType.dimension || t == CType.pattern) continue;
        if (!AiCadConstrain.kinds.containsValue(t)) missing.add(t.name);
      }
      expect(missing, isEmpty,
          reason: 'not reachable: ${missing.join(", ")}');
    });
  });

  group('every 3D feature is reachable', () {
    // The kinds PartFeature.kind can return, and the op that makes each.
    const featureOps = <String, String>{
      'extrude': 'extrude',
      'revolve': 'revolve',
      'hole': 'hole',
      'sweep': 'sweep',
      'loft': 'loft',
      'coil': 'coil',
      'split': 'split_body',
      'combine': 'combine',
      'pattern': 'pattern',
      'fillet': 'fillet',
      'chamfer': 'chamfer',
      'deleteface': 'delete_face',
      'direct': 'move_face',
      'shell': 'shell',
    };

    test('each feature kind has an op that builds it', () {
      for (final entry in featureOps.entries) {
        expect(kAiOps, contains(entry.value),
            reason: '${entry.key} has no op');
      }
    });

    test('all three direct-edit modes are reachable', () {
      // DirectOp has move, size and scale. Only move used to be.
      for (final op in const ['move_face', 'size_face', 'scale_body']) {
        expect(kAiOps, contains(op), reason: op);
      }
    });

    test('the list above is the WHOLE list — part_model.dart is asked', () {
      // featureOps is written out by hand, so on its own it would go stale
      // the day somebody adds a feature class. Read the kinds straight out
      // of the model instead: every `String get kind => '...'` in
      // part_model.dart is a feature the timeline can hold, and each one
      // needs an op or a named reason.
      final src = File('lib/part_model.dart').readAsStringSync();
      final kinds = RegExp(r"String get kind => '([a-z]+)'")
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet();
      expect(kinds.length, greaterThan(10),
          reason: 'the pattern stopped matching; this test is now blind');
      final unreachable = [
        for (final k in kinds)
          if (k != 'derive' && !featureOps.containsKey(k)) k
      ];
      expect(unreachable, isEmpty,
          reason: 'part_model.dart can build these features and the '
              'assistant cannot ask for them: ${unreachable.join(", ")}. '
              'Give each one an op and add it to featureOps.');
    });

    test('derive is the one feature with no op, and this says so', () {
      // DeriveFeature links geometry from ANOTHER document. The assistant
      // works in one document at a time and cannot pick a second one, so an
      // op for it would be an argument it could never fill. Named here so
      // the absence is a decision.
      expect(kAiOps, isNot(contains('derive')));
    });
  });

  group('every op the protocol declares is dispatched and described', () {
    test('none falls through to the generic status word', () {
      final generic = [
        for (final op in kAiOps)
          if (AiActivity(AiPhase.working, op: op).work == AiWork.working) op
      ];
      expect(generic, isEmpty,
          reason: 'these would show "Working…" and nothing more: '
              '${generic.join(", ")}');
    });

    test('every op appears in the instructions the model is given', () {
      // An op the model is never told about is an op it will never use.
      final undocumented = [
        for (final op in kAiOps)
          if (!kAiActionInstructions.contains(op)) op
      ];
      expect(undocumented, isEmpty,
          reason: 'not in the instructions: ${undocumented.join(", ")}');
    });
  });
}
