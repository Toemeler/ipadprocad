// Before anything is built, a model that answers its own failed block with a
// question is sent back to fix it: the user asked for a part (AI lab, a
// whistle rolled back on a typo and the turn ended asking which whistle).
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_expr.dart';

const _document = AiDocument(id: 'doc', name: 'Plate', kind: 'part');

void main() {
  const bad = '```cad\n{"title":"Plate","actions":[{"op":"extrude",'
      '"distance":-5}]}\n```';
  const question = 'Which kind of plate do you want — round or square?';
  const good = '```cad\n{"title":"Plate","say":"Fertig.",'
      '"actions":[{"op":"extrude","distance":5}]}\n```';

  AiController controllerWith(List<String> replies, List<AiRequest> seen) {
    final c = AiController(backend: _Backend(replies, seen))
      ..initializeInMemory();
    addTearDown(c.dispose);
    c
      ..contextReader = ((id) async => {'id': id, 'name': 'Plate'})
      ..updateWorkspace(current: _document, documents: const [_document])
      ..actionRunner = ((batch, {onStep}) async {
        final ok = batch.every((a) => (a.args['distance'] as num? ?? 1) > 0);
        return AiActionReport(outcomes: [
          for (final a in batch)
            ok
                ? AiActionOutcome(a.op)
                : AiActionOutcome.failed(a.op, 'distance must be > 0')
        ], reverted: !ok);
      });
    return c;
  }

  test('a question after a failed first block is sent back', () async {
    final seen = <AiRequest>[];
    final c = controllerWith([bad, question, good], seen);
    c.updateDraft('Make a plate');
    await c.send();
    expect(seen, hasLength(3));
    expect(c.currentSession.messages.last.text, 'Fertig.');
  });

  test('a question about the user\'s own question is still an answer',
      () async {
    final seen = <AiRequest>[];
    final c = controllerWith([question], seen);
    c.updateDraft('What plate thickness would you suggest?');
    await c.send();
    expect(seen, hasLength(1));
  });

  test('a mistyped name is named', () {
    expect(aiNearestName('lib', ['L', 'lip', 'wall']), 'lip');
    expect(aiNearestName('xy', ['ab', 'cd']), isNull);
    expect(aiNearestName('wal', ['wall', 'walk']), isNull, reason: 'a tie');
  });
}

class _Backend implements AiBackend {
  _Backend(this.replies, this.seen);
  final List<String> replies;
  final List<AiRequest> seen;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    seen.add(request);
    final i = seen.length - 1;
    return AiReply(replies[i < replies.length ? i : replies.length - 1], 'test');
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
