import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_models.dart';
import 'package:prototype/ai/ai_stream.dart' show AnthropicStreamAssembler;

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
              expect(body['system'][0]['text'], 'Only inspect.');
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

  group('Claude on a thinking model', () {
    String sse(List<Map<String, dynamic>> events) => [
          for (final e in events)
            'event: ${e['type']}\ndata: ${jsonEncode(e)}\n'
        ].join('\n');

    List<Map<String, dynamic>> reply(String text,
            {String stop = 'end_turn', bool thinking = true}) =>
        [
          {
            'type': 'message_start',
            'message': {
              'id': 'msg_1',
              'model': 'claude-opus-5-5',
              'usage': {'input_tokens': 10, 'cache_read_input_tokens': 7}
            }
          },
          if (thinking) ...[
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'thinking', 'thinking': ''}
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'thinking_delta', 'thinking': 'plan the cup'}
            },
            {'type': 'content_block_stop', 'index': 0},
          ],
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {'type': 'text', 'text': ''}
          },
          for (final part in [
            text.substring(0, text.length ~/ 2),
            text.substring(text.length ~/ 2)
          ])
            {
              'type': 'content_block_delta',
              'index': 1,
              'delta': {'type': 'text_delta', 'text': part}
            },
          {'type': 'content_block_stop', 'index': 1},
          {
            'type': 'message_delta',
            'delta': {'stop_reason': stop},
            'usage': {'output_tokens': 42}
          },
          {'type': 'message_stop'},
        ];

    test(
        'thinks adaptively, streams, caches the instructions and opts into '
        'fallbacks — on every round of the loop', () async {
      final bodies = <Map>[];
      final headers = <Map<String, String>>[];
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((r) async {
                bodies.add(jsonDecode(r.body) as Map);
                headers.add(r.headers);
                return http.Response(sse(reply('Built the cup.')), 200,
                    headers: {'content-type': 'text/event-stream'});
              }));
      addTearDown(backend.dispose);
      final stages = <AiStreamStage>[];
      final texts = <String>[];
      final r = await backend.respond(
          const AiPreferences(
              provider: AiProvider.anthropic, model: 'claude-opus-5-5'),
          AiRequest(
              id: 'loop',
              instructions: 'Only inspect.',
              context: '{}',
              messages: [AiMessage(role: 'user', text: 'a cup')],
              round: 3,
              iterating: true,
              onStream: stages.add,
              onText: texts.add));
      expect(r.text, 'Built the cup.');
      expect(stages, [AiStreamStage.thinking, AiStreamStage.writing]);
      expect(texts.last, 'Built the cup.');
      final body = bodies.single;
      // neverThink is a DeepSeek lever: Claude is never asked to stop.
      expect(body['thinking'], {'type': 'adaptive', 'display': 'summarized'});
      expect(body['output_config'], {'effort': 'high'});
      expect(body['stream'], isTrue);
      expect(body['max_tokens'], greaterThanOrEqualTo(64000));
      expect(body['system'][0]['cache_control'], {'type': 'ephemeral'});
      expect(body['cache_control'], {'type': 'ephemeral'});
      expect(body['fallbacks'], 'default');
      expect(
          headers.single['anthropic-beta'], 'server-side-fallback-2026-07-01');
      // The thinking itself is never the answer.
      expect(r.text, isNot(contains('plan the cup')));
    });

    test('a cut-off reply retries with more room and less effort', () async {
      final bodies = <Map>[];
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((r) async {
                bodies.add(jsonDecode(r.body) as Map);
                return http.Response(
                    sse(reply('half', stop: 'max_tokens')), 200);
              }));
      addTearDown(backend.dispose);
      await expectLater(
          backend.respond(
              const AiPreferences(
                  provider: AiProvider.anthropic, model: 'claude-opus-5-5'),
              AiRequest(
                  id: 'x',
                  instructions: 'i',
                  context: '{}',
                  attempt: 1,
                  messages: [AiMessage(role: 'user', text: 'a cup')])),
          throwsA(
              isA<AiException>().having((e) => e.code, 'code', 'truncated')));
      expect(bodies.single['max_tokens'], 128000);
      expect(bodies.single['output_config'], {'effort': 'medium'});
    });

    test('an older Claude model gets no parameters it would reject', () async {
      final bodies = <Map>[];
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((r) async {
                bodies.add(jsonDecode(r.body) as Map);
                return http.Response(sse(reply('ok', thinking: false)), 200);
              }));
      addTearDown(backend.dispose);
      await backend.respond(
          const AiPreferences(
              provider: AiProvider.anthropic, model: 'claude-haiku-4-5'),
          request());
      expect(bodies.single.containsKey('thinking'), isFalse);
      expect(bodies.single.containsKey('output_config'), isFalse);
      expect(bodies.single.containsKey('fallbacks'), isFalse);
    });

    test('text a refused first model wrote before a fallback is dropped', () {
      final asm = AnthropicStreamAssembler();
      for (final line in sse([
        {
          'type': 'message_start',
          'message': {'id': 'm', 'usage': {}}
        },
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''}
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'partial'}
        },
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {'type': 'fallback'}
        },
        {
          'type': 'content_block_start',
          'index': 2,
          'content_block': {'type': 'text', 'text': ''}
        },
        {
          'type': 'content_block_delta',
          'index': 2,
          'delta': {'type': 'text_delta', 'text': 'whole answer'}
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'}
        },
      ]).split('\n')) {
        asm.addLine(line);
      }
      expect(asm.content, 'whole answer');
      final r = asm.toResponse();
      expect(r['stop_reason'], 'end_turn');
    });

    test('model capability gates', () {
      expect(claudeTakesAdaptiveThinking('claude-opus-5-5'), isTrue);
      expect(claudeTakesAdaptiveThinking('claude-sonnet-4-6'), isTrue);
      expect(claudeTakesAdaptiveThinking('claude-haiku-5-5'), isTrue);
      expect(claudeTakesAdaptiveThinking('claude-haiku-4-5'), isFalse);
      expect(claudeTakesAdaptiveThinking('claude-sonnet-4-5'), isFalse);
      expect(claudeTakesAdaptiveThinking('claude-opus-4-20250514'), isFalse);
      expect(claudeTakesFallbacks('claude-opus-5-5'), isTrue);
      expect(claudeTakesFallbacks('claude-opus-5'), isTrue);
      expect(claudeTakesFallbacks('claude-fable-5-1'), isTrue);
      expect(claudeTakesFallbacks('claude-sonnet-5-5'), isTrue);
      expect(claudeTakesFallbacks('claude-sonnet-5'), isFalse);
      expect(claudeTakesFallbacks('claude-haiku-5-5'), isFalse);
      expect(claudeTakesFallbacks('claude-opus-4-8'), isFalse);
    });
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
