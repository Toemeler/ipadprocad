// M453 — the render actually goes out, and a reply that ran out of room is
// the app's problem, not the user's.
//
// TWO CLAIMS, BOTH FROM THE SAME SESSION.
//
//   V4.1-Flash HAS VISION AND V4-PRO DOES NOT. So "can this provider see" is
//   the wrong question; "can this MODEL see" is the right one, and the answer
//   has to reach the wire — a capability flag that says yes while the body
//   builder still flattens everything to one string is the same bug with an
//   extra step. These tests read the request that would actually be sent.
//
//   "ASK FOR A SMALLER STEP" SHOULD NEVER BE SHOWN. It was the app handing
//   the user a budget the app itself chose. A reply cut off mid-thought is
//   recoverable without them: more room, less reasoning, try again. What the
//   user sees is the recovered answer.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';

/// A 1x1 PNG header — enough for the attachment to classify as an image.
final _png = Uint8List.fromList(
    [137, 80, 78, 71, 13, 10, 26, 10, ...List.filled(40, 0)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            vault,
            (call) async => call.method == 'read'
                ? 'test-key-not-a-real-credential'
                : null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null);
  });

  AiRequest request({List<AiAttachment> attachments = const [], int? round}) =>
      AiRequest(
          id: 'request',
          instructions: 'Only inspect.',
          context: '{"name":"Bracket"}',
          round: round,
          messages: [
            AiMessage(
                role: 'user', text: 'Look at it.', attachments: attachments)
          ]);

  /// Runs one request against a fake DeepSeek and returns the body it sent.
  Future<Map<String, dynamic>> bodyFor(String model,
      {List<AiAttachment> attachments = const [], int? round}) async {
    late Map<String, dynamic> sent;
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((r) async {
              sent = jsonDecode(r.body) as Map<String, dynamic>;
              return http.Response(
                  jsonEncode({
                    'choices': [
                      {
                        'finish_reason': 'stop',
                        'message': {'content': 'ok'}
                      }
                    ]
                  }),
                  200);
            }));
    addTearDown(backend.dispose);
    await backend.respond(
        AiPreferences(provider: AiProvider.deepseek, model: model),
        request(attachments: attachments, round: round));
    return sent;
  }

  group('the render reaches a model that can see it', () {
    test('an image rides as OpenAI content parts', () async {
      final body = await bodyFor(kDeepSeekDefaultModel, attachments: [
        AiAttachment.fromBytes(name: 'view.png', bytes: _png)
      ]);
      final turn = (body['messages'] as List).last as Map;
      final parts = turn['content'] as List;
      final image = parts.firstWhere((p) => p['type'] == 'image_url') as Map;
      expect((image['image_url'] as Map)['url'],
          startsWith('data:image/png;base64,'));
      // The words still travel with it, in one text part.
      final text = parts.firstWhere((p) => p['type'] == 'text') as Map;
      expect(text['text'], contains('Look at it.'));
    });

    test('a turn with no image stays a plain string', () async {
      final body = await bodyFor(kDeepSeekDefaultModel);
      expect((body['messages'] as List).last['content'], isA<String>());
    });

    test('a text-only model refuses the image instead of dropping it',
        () async {
      // Silently flattening it away is how the assistant came to describe a
      // view it had never been sent.
      await expectLater(
          bodyFor('deepseek-v4-pro',
              attachments: [
                AiAttachment.fromBytes(name: 'view.png', bytes: _png)
              ]),
          throwsA(isA<AiException>()
              .having((e) => e.code, 'code', 'imagesUnsupported')));
    });

    test('capabilities agree with what the body builder will do', () async {
      final backend = DeviceAiBackend(clientFactory: () => MockClient(
          (_) async => http.Response('{}', 200)));
      addTearDown(backend.dispose);
      final flash = await backend.capabilities(AiPreferences(
          provider: AiProvider.deepseek, model: kDeepSeekDefaultModel));
      final pro = await backend.capabilities(const AiPreferences(
          provider: AiProvider.deepseek, model: 'deepseek-v4-pro'));
      expect(flash.supportsImages, isTrue);
      expect(pro.supportsImages, isFalse);
    });
  });

  group('thinking reaches the wire', () {
    test('full effort on the first round, low after', () async {
      expect((await bodyFor(kDeepSeekDefaultModel, round: 0))['reasoning_effort'],
          'high');
      expect((await bodyFor(kDeepSeekDefaultModel, round: 3))['reasoning_effort'],
          'low');
    });

    test('a model without the controls is not sent them', () async {
      final body = await bodyFor('deepseek-v4-pro', round: 0);
      expect(body.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('a cut-off reply is recovered, not reported', () {
    test('the budget and the reasoning both move on a retry', () {
      expect(aiOutputBudget(0), kAiMaxOutputTokens);
      expect(aiOutputBudget(1), greaterThan(aiOutputBudget(0)));
      expect(aiOutputBudget(2), greaterThan(aiOutputBudget(1)));
      expect(deepSeekReasoningEffort(0, 0), 'high');
      expect(deepSeekReasoningEffort(0, 1), 'low');
      expect(deepSeekReasoningEffort(0, 2), 'none');
    });

    test('the user gets the answer, never the apology', () async {
      final backend = _Truncating(truncateFirst: 1);
      final controller = _controllerWith(backend);
      controller.updateDraft('Make me an espresso cup');
      await controller.send();
      expect(backend.attempts, [0, 1]);
      expect(controller.error, isNull);
      expect(controller.currentSession.messages.last.text, 'Done.');
    });

    test('it gives up eventually rather than retrying forever', () async {
      final backend = _Truncating(truncateFirst: 99);
      final controller = _controllerWith(backend);
      controller.updateDraft('Make me an espresso cup');
      await controller.send();
      expect(backend.attempts, [0, 1, 2],
          reason: 'bounded by kAiMaxTruncationRetries');
      expect(controller.error, isNotNull);
    });

    test('a retry that fails differently reports the ORIGINAL truncation',
        () async {
      // A provider that rejects the larger allowance must not turn "the reply
      // was cut off" into "quota exceeded", which describes nothing that
      // happened to this turn.
      final backend = _Truncating(truncateFirst: 1, thenThrow: 'quota');
      final controller = _controllerWith(backend);
      controller.updateDraft('Make me an espresso cup');
      await controller.send();
      expect(controller.error, const AiException('truncated').message);
    });

    test('the message no longer tells the user to do the app\'s job', () {
      final text = const AiException('truncated').message;
      expect(text.toLowerCase(), isNot(contains('smaller')));
    });
  });
}

AiController _controllerWith(AiBackend backend) {
  const document = AiDocument(id: 'doc', name: 'Cup', kind: 'part');
  final c = AiController(backend: backend)..initializeInMemory();
  addTearDown(c.dispose);
  c
    ..contextReader = ((id) async => {'id': id, 'name': 'Cup'})
    ..updateWorkspace(current: document, documents: const [document]);
  return c;
}

/// Truncates the first [truncateFirst] attempts, then answers — or throws
/// [thenThrow] instead, to model a provider that rejects the larger request.
class _Truncating implements AiBackend {
  _Truncating({required this.truncateFirst, this.thenThrow});
  final int truncateFirst;
  final String? thenThrow;
  final attempts = <int>[];

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    attempts.add(request.attempt);
    if (request.attempt < truncateFirst) {
      throw const AiException('truncated');
    }
    if (thenThrow != null) throw AiException(thenThrow!);
    return const AiReply('Done.', 'test');
  }

  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<bool> hasKey(AiProvider provider) async => true;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}
