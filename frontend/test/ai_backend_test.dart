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
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'response')));
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
