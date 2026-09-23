// #91 — "the design is always the same and not creative".
//
// Two cup conversations, days apart, built the same cup to the tenth of a
// millimetre: Ø64, 2.4 mm wall, 200 ml (in the second one nobody had said
// 200 ml), a Ø11 D handle, R1 rim, 0.6 mm foot. The mug worked example (#87)
// carried three complete blocks down to the closing message, and the header
// every opened document sits under said "design to it". So the model did.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_knowledge.dart';

AiKnowledge _shipped() {
  final j = jsonDecode(File('assets/knowledge/kb.json').readAsStringSync())
      as Map<String, dynamic>;
  return AiKnowledge.forTest([
    for (final d in (j['documents'] as List).cast<Map>())
      KnowledgeDoc.fromJson(d.cast<String, dynamic>())
  ]);
}

void main() {
  final mug = _shipped().byId('fdm/examples/mug-with-handle')!;

  test('an opened worked example says it is not the design', () {
    final text = AiKnowledge.render([mug]);
    expect(text, contains(AiKnowledge.kExampleFraming));
    expect(text.indexOf(AiKnowledge.kExampleFraming),
        lessThan(text.indexOf(mug.body)),
        reason: 'read before the example, not after it');
  });

  test('a rules document is not framed as an example', () {
    final rules = _shipped().byId('fdm/geometry/overhangs-and-bridging')!;
    expect(AiKnowledge.render([rules]),
        isNot(contains(AiKnowledge.kExampleFraming)));
  });

  test('the mug example hands over no finished answer', () {
    expect(mug.body, isNot(contains('"say"')),
        reason: 'the closing message was copied word for word');
    expect(mug.body, contains("Make it this user's cup"));
    for (final form in ['tapered', 'faceted', 'ear', 'revolve']) {
      expect(mug.body, contains(form), reason: 'offers $form');
    }
    // What makes it print survives the rewrite.
    expect(mug.body, contains('30° from horizontal'));
    expect(mug.body, contains('18 mm'));
  });

  test('the instructions ask for a design, and no longer define a cup as a '
      'cylinder', () {
    expect(kAiActionInstructions, contains('GIVE IT A DESIGN'));
    expect(kAiActionInstructions,
        isNot(contains('A cup is a solid cylinder shelled')));
  });
}
