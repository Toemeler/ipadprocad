// M451 — "the individual steps take way too long and used way too many
// tokens". Measured, not guessed.
//
// From the trace in the issue #72 bundle, for one plate with two holes and
// two fillets: 54,637 input tokens, 9,662 output tokens of which 8,906 were
// reasoning, and 3 m 44 s wall clock. The app's own share of that was
// 0.3–0.5 s per block. Every other second, and every token, went on provider
// round trips — so the only levers that matter are how MANY rounds there are
// and how much is resent on each one.
//
// Three costs, three tests.
//
//   RESENT STATE. Every block's report carried a full snapshot of the
//   document, and every one of those snapshots stayed in the conversation and
//   was resent on every later round. Six rounds in, the model was paying for
//   six descriptions of a part that only one of them still described — which
//   is also the single most confusing thing that transcript contained.
//
//   A ROUND TRIP TO SAY "DONE". The closing sentence was its own round: 8.4 s
//   and 365 tokens, 327 of them reasoning, about work already finished.
//
//   ONE ACTION PER ROUND. The instruction added in #70 asked for "one or two
//   actions" a block, which bought visible progress by spending a round trip
//   on each. A step is one block; a block is not one action.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';

const _document = AiDocument(id: 'doc', name: 'Holder', kind: 'part');

void main() {
  AiController controllerWith(_Backend backend) {
    final c = AiController(backend: backend)..initializeInMemory();
    addTearDown(c.dispose);
    c
      ..contextReader = ((id) async => {'id': id, 'name': 'Holder'})
      ..updateWorkspace(current: _document, documents: const [_document]);
    return c;
  }

  AiMessage tool(Map<String, dynamic> body) =>
      AiMessage(role: 'tool', text: jsonEncode(body));

  group('superseded state is not resent', () {
    test('only the newest tool message keeps its snapshot', () {
      final turns = [
        AiMessage(role: 'user', text: 'Make a plate'),
        tool({
          'actionResults': [
            {'op': 'extrude', 'ok': true}
          ],
          'partAfter': {'features': 1, 'size': 'old'}
        }),
        tool({
          'actionResults': [
            {'op': 'fillet', 'ok': true}
          ],
          'partAfter': {'features': 2, 'size': 'new'}
        }),
      ];
      final sent = aiCompactTurns(turns);
      expect(sent, hasLength(3));
      final first = jsonDecode(sent[1].text) as Map;
      final last = jsonDecode(sent[2].text) as Map;
      expect(first.containsKey('partAfter'), isFalse);
      expect(first['superseded'], contains('has changed since'));
      expect(last['partAfter'], isNotNull, reason: 'the newest state stands');
    });

    test('what was DONE is never removed, only what it looked like', () {
      final sent = aiCompactTurns([
        tool({
          'actionResults': [
            {'op': 'extrude', 'ok': false, 'error': 'distance must be > 0'}
          ],
          'partAfter': {'features': 1},
          'reverted': true,
        }),
        tool({'actionResults': const []}),
      ]);
      final kept = jsonDecode(sent.first.text) as Map;
      expect(kept['reverted'], isTrue);
      expect((kept['actionResults'] as List).single,
          containsPair('error', 'distance must be > 0'));
    });

    test('a silhouette and a shape read go the same way', () {
      final sent = aiCompactTurns([
        tool({
          'actionResults': [
            {'op': 'look', 'ok': true}
          ],
          'silhouette': '#' * 900,
          'shape': 'SHAPE Solid1 — bbox 140 × 70 × 8',
        }),
        tool({'actionResults': const []}),
      ]);
      expect(sent.first.text.length, lessThan(300));
      for (final key in kAiSupersededKeys) {
        expect(jsonDecode(sent.first.text), isNot(contains(key)));
      }
    });

    test('a tool message that is not a report is left exactly alone', () {
      final odd = AiMessage(role: 'tool', text: 'not json at all');
      final sent = aiCompactTurns([odd, AiMessage(role: 'tool', text: '{}')]);
      expect(sent.first.text, 'not json at all');
    });

    test('the identity of a compacted message survives', () {
      final original = tool({
        'actionResults': const [],
        'partAfter': {'features': 1}
      });
      final sent = aiCompactTurns([original, tool({'actionResults': const []})]);
      expect(sent.first.id, original.id);
      expect(sent.first.createdAt, original.createdAt);
    });

    test('the loop sends the compacted conversation, and stores the full one',
        () async {
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Plate","actions":[{"op":"extrude"}]}\n```'
              : i == 1
                  ? '```cad\n{"title":"Round","actions":[{"op":"fillet"}]}\n```'
                  : 'Done.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
              outcomes: [for (final a in batch) AiActionOutcome(a.op)],
              state: {'features': 1, 'trace': 'SNAPSHOT'},
            ));
      controller.updateDraft('Make a plate');
      await controller.send();

      // The third request carries two tool messages; only the newer one may
      // still contain a snapshot.
      final sent = backend.requests.last.messages
          .where((m) => m.role == 'tool')
          .toList();
      expect(sent, hasLength(2));
      expect(sent.first.text, isNot(contains('SNAPSHOT')));
      expect(sent.last.text, contains('SNAPSHOT'));
      // Nothing was taken out of the conversation the user and a bug report
      // read back.
      final stored = controller.currentSession.messages
          .where((m) => m.role == 'tool')
          .toList();
      expect(stored.every((m) => m.text.contains('SNAPSHOT')), isTrue);
    });
  });

  group('a finished block does not cost another round trip', () {
    test('"say" closes the turn when the block fully succeeded', () async {
      final backend = _Backend((i) async => AiReply(
          '```cad\n{"title":"Rounding","say":"Fertig: R2 an allen Kanten.",'
          '"actions":[{"op":"fillet","radius":2}]}\n```',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]));
      controller.updateDraft('Round the edges');
      await controller.send();
      expect(backend.requests, hasLength(1),
          reason: 'the closing sentence must not be its own round trip');
      expect(controller.currentSession.messages.last.role, 'assistant');
      expect(controller.currentSession.messages.last.text,
          'Fertig: R2 an allen Kanten.');
    });

    test('a block that failed loses its "say" and answers properly', () async {
      var rounds = 0;
      final backend = _Backend((i) async {
        rounds++;
        return AiReply(
            i == 0
                ? '```cad\n{"title":"Rounding","say":"Fertig!",'
                    '"actions":[{"op":"fillet","radius":2}]}\n```'
                : 'Das Verrunden ist fehlgeschlagen: keine Kante passte.',
            'test');
      });
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(outcomes: [
              const AiActionOutcome.failed('fillet', 'no edge matched')
            ]));
      controller.updateDraft('Round the edges');
      await controller.send();
      expect(rounds, 2);
      expect(controller.currentSession.messages.last.text,
          isNot(contains('Fertig!')));
    });

    test('a rolled-back block loses its "say" too', () async {
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Two steps","say":"Fertig!",'
                  '"actions":[{"op":"extrude"},{"op":"fillet"}]}\n```'
              : 'Zurückgenommen.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)],
            reverted: true));
      controller.updateDraft('Build it');
      await controller.send();
      expect(backend.requests, hasLength(2));
    });

    test('a block with no "say" behaves exactly as before', () async {
      final backend = _Backend((i) async => AiReply(
          i == 0
              ? '```cad\n{"title":"Plate","actions":[{"op":"extrude"}]}\n```'
              : 'Fertig.',
          'test'));
      final controller = controllerWith(backend)
        ..actionRunner = ((batch, {onStep}) async => AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]));
      controller.updateDraft('Make a plate');
      await controller.send();
      expect(backend.requests, hasLength(2));
    });

    test('the parser reads a say off the block', () {
      final block = parseAiActions('```cad\n{"title":"T","say":"Done.",'
          '"actions":[{"op":"look"}]}\n```');
      expect(block.say, 'Done.');
      expect(block.title, 'T');
      // And it is not shown as the reply text — the app decides when it is
      // used, from the result.
      expect(
          aiReplyWithoutActions('```cad\n{"say":"Done.","actions":[]}\n```'),
          isEmpty);
    });
  });

  _images();

  group('the model is told what a round trip costs', () {
    test('a step is one block, not one action', () async {
      final backend = _Backend((_) async => const AiReply('Done.', 'test'));
      final controller = controllerWith(backend)
        ..actionRunner =
            ((batch, {onStep}) async => AiActionReport(outcomes: const []));
      controller.updateDraft('Make a plate');
      await controller.send();
      final sent = backend.requests.single.instructions;
      expect(sent, contains('EVERY BLOCK COSTS THE USER 10 TO 50 SECONDS'));
      expect(sent, contains('are one step'));
      // #82 — "THINK BRIEFLY" became the stronger claim it was always trying
      // to make: the app runs a block in milliseconds and reports exactly what
      // happened, so predicting that is strictly slower AND worse information.
      expect(sent, contains('DO NOT THINK. BUILD, LOOK, CORRECT'));
      expect(sent, contains('saying you have finished'));
      // The #70 advice that bought visible progress with a round trip each.
      expect(sent, isNot(contains('one or two actions')));
    });

    test('and that old reports no longer carry the truth', () async {
      final backend = _Backend((_) async => const AiReply('Done.', 'test'));
      final controller = controllerWith(backend)
        ..actionRunner =
            ((batch, {onStep}) async => AiActionReport(outcomes: const []));
      controller.updateDraft('Make a plate');
      await controller.send();
      expect(backend.requests.single.instructions, contains('superseded'));
    });
  });
}

class _Backend implements AiBackend {
  _Backend(this.reply);
  final FutureOr<AiReply> Function(int round) reply;
  final requests = <AiRequest>[];

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    final round = requests.length;
    requests.add(AiRequest(
        id: request.id,
        instructions: request.instructions,
        context: request.context,
        messages: request.messages.toList()));
    return reply(round);
  }

  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<bool> hasKey(AiProvider provider) async => false;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// M452 — the eye was shut by a flag, not by the provider.
//
// I told the user DeepSeek could not receive images. What I had actually
// checked was this app's own hard-coded `supportsImages: provider !=
// deepseek`. DeepSeek's V4 line is natively multimodal — V4.1-Flash lists
// `image` among its input modalities — so the flag, not the API, is what
// dropped every rendered view on the floor and then told the model it had not
// seen one.
//
// The lesson the test encodes: image support is a property of the MODEL. A
// provider-wide boolean was wrong the day the provider shipped a vision
// model, and would be wrong again the next time.
void _images() {
  group('DeepSeek image support follows the model', () {
    test('a vision-capable model takes images', () {
      expect(deepSeekTakesImages('deepseek-flash'), isTrue);
      expect(deepSeekTakesImages('DeepSeek-V4.1-Flash'), isTrue);
      expect(deepSeekTakesImages('deepseek-v4-flash-vision-exp'), isTrue);
    });

    test('a text-only model does not', () {
      expect(deepSeekTakesImages('deepseek-chat'), isFalse);
      expect(deepSeekTakesImages('deepseek-reasoner'), isFalse);
      // Retired ids that the service reroutes server-side are NOT assumed to
      // accept multimodal content under the old name: the rerouting is
      // documented, accepting image parts under it is not.
      expect(deepSeekTakesImages('deepseek-v4-pro'), isFalse);
    });
  });
}
