// Hedged rounds: the same round asked twice at once; the second answer runs
// only when the first one's block is thrown away whole (AI lab lever, see
// docs/AI_LAB_LOG.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';

const _document = AiDocument(id: 'doc', name: 'Plate', kind: 'part');

void main() {
  AiController controllerWith(_Backend backend) {
    final c = AiController(backend: backend)..initializeInMemory();
    addTearDown(c.dispose);
    c
      ..contextReader = ((id) async => {'id': id, 'name': 'Plate'})
      ..updateWorkspace(current: _document, documents: const [_document])
      ..hedgeRounds = true;
    return c;
  }

  const good = '```cad\n{"title":"Plate","say":"Fertig.",'
      '"actions":[{"op":"extrude","distance":5}]}\n```';
  const bad = '```cad\n{"title":"Plate","actions":[{"op":"extrude",'
      '"distance":-5}]}\n```';

  test('a first block thrown away whole is replaced by the other answer',
      () async {
    final backend = _Backend((id) => id.endsWith('~b') ? good : bad);
    final ran = <List<AiAction>>[];
    final controller = controllerWith(backend)
      ..actionRunner = ((batch, {onStep}) async {
        ran.add(batch);
        final ok = batch.every((a) => (a.args['distance'] as num? ?? 1) > 0);
        return AiActionReport(
            outcomes: [
              for (final a in batch)
                ok
                    ? AiActionOutcome(a.op)
                    : AiActionOutcome.failed(a.op, 'distance must be > 0')
            ],
            reverted: !ok);
      });
    controller.updateDraft('Make a plate');
    await controller.send();
    expect(ran, hasLength(2), reason: 'the bad block, then the good one');
    expect(ran.last.single.args['distance'], 5);
    // The conversation shows the answer that ran.
    final texts = controller.currentSession.messages.map((m) => m.text);
    expect(texts.any((t) => t.contains('"distance":-5')), isFalse);
    expect(texts.last, 'Fertig.');
  });

  test('a first block that works leaves the other answer unused', () async {
    final backend = _Backend((id) => good);
    final ran = <List<AiAction>>[];
    final controller = controllerWith(backend)
      ..actionRunner = ((batch, {onStep}) async {
        ran.add(batch);
        return AiActionReport(
            outcomes: [for (final a in batch) AiActionOutcome(a.op)]);
      });
    controller.updateDraft('Make a plate');
    await controller.send();
    expect(ran, hasLength(1));
  });
}

class _Backend implements AiBackend {
  _Backend(this.reply);
  final String Function(String id) reply;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async =>
      AiReply(reply(request.id), 'test');

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
