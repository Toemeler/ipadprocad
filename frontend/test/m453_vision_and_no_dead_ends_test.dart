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

  AiRequest request(
          {List<AiAttachment> attachments = const [],
          bool thorough = false,
          bool iterating = true}) =>
      AiRequest(
          id: 'request',
          instructions: 'Only inspect.',
          context: '{"name":"Bracket"}',
          thorough: thorough,
          iterating: iterating,
          messages: [
            AiMessage(
                role: 'user', text: 'Look at it.', attachments: attachments)
          ]);

  /// Runs one request against a fake DeepSeek and returns the body it sent.
  Future<Map<String, dynamic>> bodyFor(String model,
      {List<AiAttachment> attachments = const [],
      bool thorough = false,
      bool iterating = true}) async {
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
        request(
            attachments: attachments,
            thorough: thorough,
            iterating: iterating));
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
    // ISSUE #82 — THE LOOP IS THE REASONING, so a round of it never asks for
    // deliberation, whatever the brief says.
    //
    // This used to assert the opposite: an open `must` bought `high` on every
    // round. That latched on the first block of any whole-object request (the
    // instructions tell the model to record its musts before building) and
    // never released, because brief_done does not fire mid-build. The measured
    // cost in the reported session was 99.0% of all output tokens spent on
    // reasoning, and one round that took 180 seconds to emit 158 tokens of
    // content. The round BEFORE the latch engaged, at `low`, produced the only
    // correct feature of the session.
    test('a round of the action loop always thinks cheaply', () async {
      expect((await bodyFor(kDeepSeekDefaultModel))['reasoning_effort'], 'low');
      expect(
          (await bodyFor(kDeepSeekDefaultModel, thorough: true))
              ['reasoning_effort'],
          'low',
          reason: 'an open requirement describes the JOB, not this round — '
              'and the round can just build the thing and read the report');
    });

    test('an answer with no loop behind it may still deliberate', () async {
      // Edits disabled, or the closing reply after a blocked block: nothing
      // to test against, so thinking is the only instrument left.
      expect(
          (await bodyFor(kDeepSeekDefaultModel,
              thorough: true, iterating: false))['reasoning_effort'],
          'high');
      expect(
          (await bodyFor(kDeepSeekDefaultModel, iterating: false))
              ['reasoning_effort'],
          'low',
          reason: 'nothing outstanding is still nothing to think about');
    });

    test('a model without the controls is not sent them', () async {
      final body = await bodyFor('deepseek-v4-pro');
      expect(body.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('nothing caps the answer but the model itself', () {
    test('an ordinary turn sends no max_tokens at all', () async {
      // Sending 8192 was WORSE than sending nothing: DeepSeek's own default
      // with the field absent is 64K in thinking mode.
      final body = await bodyFor(kDeepSeekDefaultModel);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(aiOutputBudget(0), isNull);
    });

    test('only a retry names a number, and it is a large one', () {
      expect(aiOutputBudget(1), greaterThan(kAiMaxOutputTokens * 4));
      expect(aiOutputBudget(2), greaterThan(aiOutputBudget(1)!));
      expect(aiOutputBudget(2), lessThanOrEqualTo(kDeepSeekMaxOutputTokens));
    });

    test('a provider that requires the field still gets one', () {
      expect(aiRequiredOutputBudget(0), kAiMaxOutputTokens);
      expect(aiRequiredOutputBudget(2), greaterThan(aiRequiredOutputBudget(0)));
    });
  });

  group('the app decides thoroughness from its own record', () {
    test('a narrow change asks for no deliberation', () async {
      final backend = _Capturing();
      final controller = _controllerWith(backend);
      controller.updateDraft('Add a 5 mm hole');
      await controller.send();
      expect(backend.requests.single.thorough, isFalse);
    });

    test('an open requirement the model wrote buys it', () async {
      final backend = _Capturing();
      final controller = _controllerWith(backend);
      controller.briefs.add(
          'doc',
          AiRequirement(
              text: 'Must hold 200 ml.', kind: AiRequirementKind.must));
      controller.updateDraft('Make me a tea cup');
      await controller.send();
      expect(backend.requests.single.thorough, isTrue);
    });

    test('a satisfied requirement stops costing', () async {
      final backend = _Capturing();
      final controller = _controllerWith(backend);
      final r = controller.briefs.add('doc',
          AiRequirement(text: 'Must hold 200 ml.', kind: AiRequirementKind.must));
      controller.briefs.markDone('doc', r.id);
      controller.updateDraft('Now add a hole');
      await controller.send();
      expect(backend.requests.single.thorough, isFalse);
    });

    test('an assumption is not a reason to think harder', () async {
      final backend = _Capturing();
      final controller = _controllerWith(backend);
      controller.briefs.add('doc', AiRequirement(text: 'Probably 80 mm tall.'));
      controller.updateDraft('Add a hole');
      await controller.send();
      expect(backend.requests.single.thorough, isFalse);
    });
  });

  group('a cut-off reply is recovered, not reported', () {
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


/// Records the requests the controller builds.
class _Capturing implements AiBackend {
  final requests = <AiRequest>[];

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    requests.add(request);
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
