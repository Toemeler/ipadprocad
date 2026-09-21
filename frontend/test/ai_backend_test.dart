import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_models.dart';

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
          {String id = 'request', List<AiAttachment> attachments = const []}) =>
      AiRequest(
          id: id,
          instructions: 'Only inspect.',
          context: '{"name":"Bracket"}',
          messages: [
            AiMessage(
                role: 'user',
                text: 'Review the wall.',
                attachments: attachments)
          ]);

  test(
      'Gemini keeps credentials in headers and document data outside system instructions',
      () async {
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((r) async {
              expect(r.url.host, 'generativelanguage.googleapis.com');
              expect(r.url.query, isEmpty);
              expect(r.headers['x-goog-api-key'],
                  'test-key-not-a-real-credential');
              expect(r.followRedirects, isFalse);
              final body = jsonDecode(r.body) as Map;
              expect(jsonEncode(body['systemInstruction']),
                  isNot(contains('Bracket')));
              expect(jsonEncode(body['contents']), contains('Bracket'));
              return http.Response(
                  jsonEncode({
                    'candidates': [
                      {
                        'finishReason': 'STOP',
                        'content': {
                          'parts': [
                            {'thought': true, 'text': 'private reasoning'},
                            {'text': 'Review result'}
                          ]
                        }
                      }
                    ]
                  }),
                  200);
            }));
    addTearDown(backend.dispose);
    final reply = await backend.respond(
        const AiPreferences(provider: AiProvider.gemini, model: 'test-model'),
        request());
    expect(reply.text, 'Review result');
  });

  test(
      'Claude names binary files, preserves PDF/image types, and rejects incomplete output',
      () async {
    final pdf = AiAttachment.fromBytes(
        name: 'drawing.pdf',
        bytes: Uint8List.fromList(utf8.encode('%PDF-1.4')));
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((r) async {
              final body = jsonDecode(r.body) as Map;
              expect(body['system'], 'Only inspect.');
              expect(jsonEncode(body['messages']), contains('drawing.pdf'));
              final content = body['messages'][0]['content'] as List;
              expect(content.last['type'], 'document');
              expect(content.last['source']['media_type'], 'application/pdf');
              return http.Response(
                  jsonEncode({
                    'stop_reason': 'max_tokens',
                    'content': [
                      {'type': 'text', 'text': 'unfinished'}
                    ]
                  }),
                  200);
            }));
    addTearDown(backend.dispose);
    await expectLater(
        backend.respond(
            const AiPreferences(
                provider: AiProvider.anthropic, model: 'test-model'),
            request(attachments: [pdf])),
        // #70 — a reply stopped by the output budget is reported AS cut off.
        // "Ask for a smaller step" is actionable; a generic failure is not.
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'truncated')));
  });

  test('DeepSeek uses bearer auth, the chat-completions shape, and one system '
      'turn', () async {
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((r) async {
              expect(r.url.host, 'api.deepseek.com');
              expect(r.url.path, '/chat/completions');
              expect(r.headers['authorization'],
                  'Bearer test-key-not-a-real-credential');
              // The key must not be anywhere else, least of all in the URL,
              // which is the part that ends up in logs and proxies.
              expect(r.url.toString(),
                  isNot(contains('test-key-not-a-real-credential')));
              expect(r.followRedirects, isFalse);
              final body = jsonDecode(r.body) as Map;
              expect(body['model'], 'deepseek-chat');
              final messages = (body['messages'] as List).cast<Map>();
              expect(messages.first['role'], 'system');
              expect(messages.first['content'], isNot(contains('Bracket')));
              expect(messages.last['role'], 'user');
              expect(messages.last['content'], contains('Bracket'));
              expect(messages.last['content'], contains('Review the wall.'));
              return http.Response(
                  jsonEncode({
                    'choices': [
                      {
                        'finish_reason': 'stop',
                        'message': {
                          'role': 'assistant',
                          'reasoning_content': 'private reasoning',
                          'content': 'Review result'
                        }
                      }
                    ]
                  }),
                  200);
            }));
    addTearDown(backend.dispose);
    final reply = await backend.respond(
        const AiPreferences(
            provider: AiProvider.deepseek, model: 'deepseek-chat'),
        request());
    expect(reply.text, 'Review result');
    expect(reply.provider, contains('DeepSeek'));
    // The scratchpad is not the answer and is never shown as one.
    expect(reply.text, isNot(contains('private reasoning')));
  });

  test('DeepSeek refuses an image instead of dropping it silently', () async {
    final png = AiAttachment.fromBytes(
        name: 'view.png',
        bytes: Uint8List.fromList(
            [137, 80, 78, 71, 13, 10, 26, 10, ...List.filled(40, 0)]));
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((_) async {
              fail('no request may be sent for an unsupported attachment');
            }));
    addTearDown(backend.dispose);
    await expectLater(
        backend.respond(
            const AiPreferences(
                provider: AiProvider.deepseek, model: 'deepseek-chat'),
            request(attachments: [png])),
        throwsA(isA<AiException>()
            .having((e) => e.code, 'code', 'imagesUnsupported')));
  });

  test('a reasoning model gets an output budget its thinking cannot exhaust',
      () async {
    // #70 — deepseek-v4-pro spent the whole 4096-token allowance on
    // `reasoning_content` and returned finish_reason "length" with an EMPTY
    // message. The turn failed, the draft rolled back, and the user watched a
    // minute of "thinking" end in nothing.
    //
    // The answer then was a bigger number. The answer now is NO number: with
    // max_tokens absent, DeepSeek allows 8K in non-thinking mode and 64K in
    // thinking mode, so the 8192 this test used to assert was capping a
    // reasoning model at an eighth of its own ceiling — a smaller budget than
    // sending nothing at all.
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((r) async {
              final body = jsonDecode(r.body) as Map;
              expect(body.containsKey('max_tokens'), isFalse);
              return http.Response(
                  jsonEncode({
                    'choices': [
                      {
                        'finish_reason': 'stop',
                        'message': {'content': 'Done.'}
                      }
                    ]
                  }),
                  200);
            }));
    addTearDown(backend.dispose);
    final reply = await backend.respond(
        const AiPreferences(
            provider: AiProvider.deepseek, model: 'deepseek-v4-pro'),
        request());
    expect(reply.text, 'Done.');
  });

  test('a cut-off reply is reported AS cut off, not as a generic failure',
      () async {
    // Which code it is decides what the controller does about it: only
    // 'truncated' is retried with more room and less reasoning, and a generic
    // response error would put that recovery out of reach.
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'length',
                  'message': {'content': '', 'reasoning_content': 'long...'}
                }
              ]
            }),
            200)));
    addTearDown(backend.dispose);
    await expectLater(
        backend.respond(
            const AiPreferences(
                provider: AiProvider.deepseek, model: 'deepseek-v4-pro'),
            request()),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'truncated')));
  });

  test('DeepSeek treats a truncated completion as no answer, and says which',
      () async {
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'length',
                  'message': {'content': 'Half a sen'}
                }
              ]
            }),
            200)));
    addTearDown(backend.dispose);
    await expectLater(
        backend.respond(
            const AiPreferences(
                provider: AiProvider.deepseek, model: 'deepseek-chat'),
            request()),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'truncated')));
  });

  test('provider errors never expose response bodies or credentials', () async {
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((_) async => http.Response(
            'SECRET SERVER DETAIL test-key-not-a-real-credential', 401)));
    addTearDown(backend.dispose);
    await expectLater(
        backend.respond(
            const AiPreferences(provider: AiProvider.gemini, model: 'test'),
            request()),
        throwsA(isA<AiException>()
            .having((e) => e.code, 'code', 'credentials')
            .having((e) => e.toString(), 'safe message',
                isNot(contains('SECRET')))));
  });

  test('a cancelled request cannot deliver a late provider response', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient((_) {
              started.complete();
              return response.future;
            }));
    addTearDown(backend.dispose);
    final pending = backend.respond(
        const AiPreferences(provider: AiProvider.gemini, model: 'test'),
        request());
    final assertion = expectLater(pending,
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'cancelled')));
    await started.future;
    await backend.cancel('request');
    response.complete(http.Response(
        jsonEncode({
          'candidates': [
            {
              'finishReason': 'STOP',
              'content': {
                'parts': [
                  {'text': 'late'}
                ]
              }
            }
          ]
        }),
        200));
    await assertion;
  });

  test('request captures its message list before asynchronous work', () {
    final messages = [AiMessage(role: 'user', text: 'original')];
    final r =
        AiRequest(id: '1', instructions: '', context: '', messages: messages);
    messages.clear();
    expect(r.messages.single.text, 'original');
  });

  test(
      'attachment type comes from content, and binary masquerading as text is refused',
      () {
    expect(
        () => AiAttachment.fromBytes(
            name: 'fake.png', bytes: Uint8List.fromList([1, 2, 3])),
        throwsA(isA<AiException>()));
    expect(
        () => AiAttachment.fromBytes(
            name: 'fake.txt', bytes: Uint8List.fromList([65, 0, 66])),
        throwsA(isA<AiException>()));
    final text = AiAttachment.fromBytes(
        name: 'spec.md', bytes: Uint8List.fromList(utf8.encode('Wall: 3 mm')));
    expect(text.text, 'Wall: 3 mm');
    expect(AiAttachment.fromJson(text.toJson()).text, text.text);
  });
}
