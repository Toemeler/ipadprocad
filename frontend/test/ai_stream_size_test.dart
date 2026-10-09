import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_models.dart';
import 'package:prototype/ai/ai_stream.dart';
import 'package:prototype/ai/ai_trace.dart';

/// Real chat-completion framing: repeated metadata for every tiny text delta.
/// A modest script can therefore exceed the old 2 MiB wire-size cap.
String framed(String text, {String? finish}) => 'data: ${jsonEncode({
          'id': 'chatcmpl-0123456789abcdef0123456789abcdef',
          'object': 'chat.completion.chunk',
          'created': 1791581547,
          'model': 'deepseek-flash',
          'system_fingerprint': 'fp_0123456789abcdef',
          'choices': [
            {
              'index': 0,
              'delta': {'content': text},
              'logprobs': null,
              'finish_reason': finish
            }
          ],
          'usage': null,
        })}\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    AiTrace.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            vault, (call) async => call.method == 'read' ? 'test-key' : null);
  });
  tearDown(() {
    AiTrace.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null);
  });

  test('a modest Python answer survives more than 2 MiB of SSE framing',
      () async {
    final code = 'import build123d as bd\n'
        '${'# Parameter documentation for this part.\n' * 400}'
        'result = bd.Box(40,30,20)\npublish(result,"Body")';
    final answer = '```cad\n${jsonEncode({
          'title': 'Build the part',
          'actions': [
            {'op': 'build123d', 'part': 'part', 'code': code}
          ]
        })}\n```';
    final packets = [
      for (var i = 0; i < answer.length; i += 2)
        utf8.encode(
            framed(answer.substring(i, (i + 2).clamp(0, answer.length)))),
      utf8.encode(framed('', finish: 'stop')),
      utf8.encode('data: {"choices":[],"usage":{"prompt_tokens":100,'
          '"completion_tokens":8000}}\n\ndata: [DONE]\n\n'),
    ];
    final wireBytes = packets.fold<int>(0, (n, packet) => n + packet.length);
    expect(wireBytes, greaterThan(2097325),
        reason: 'the physical-iPad failure threshold');
    expect(answer.length, lessThan(20000));
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient.streaming((_, body) async {
              await body.drain<void>();
              return http.StreamedResponse(Stream.fromIterable(packets), 200);
            }));
    addTearDown(backend.dispose);
    final reply = await backend.respond(
        const AiPreferences(
            provider: AiProvider.deepseek, model: 'deepseek-flash'),
        AiRequest(
            id: 'mug',
            instructions: 'Use build123d.',
            context: '{}',
            messages: [AiMessage(role: 'user', text: 'make a mug')]));
    expect(reply.text, answer);
    expect(AiTrace.events.where((e) => e.kind == 'http.oversize'), isEmpty);
    expect(
        AiTrace.events
            .singleWhere((e) => e.kind == 'http.response')
            .data['bodyBytes'],
        greaterThan(2 * 1024 * 1024));
    expect(AiTrace.totals.single.output, 8000);
  });

  test('decoded reasoning still has a memory limit', () async {
    final packet = utf8.encode('data: ${jsonEncode({
          'choices': [
            {
              'delta': {'reasoning_content': 'r' * 700000},
              'finish_reason': null
            }
          ]
        })}\n\n');
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient.streaming((_, body) async {
              await body.drain<void>();
              return http.StreamedResponse(
                  Stream.fromIterable([packet, packet, packet, packet]), 200);
            }));
    addTearDown(backend.dispose);
    await expectLater(
        backend.respond(
            const AiPreferences(
                provider: AiProvider.deepseek, model: 'deepseek-chat'),
            AiRequest(
                id: 'oversize',
                instructions: 'Build.',
                context: '{}',
                messages: [AiMessage(role: 'user', text: 'a part')])),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'response')));
    final guard =
        AiTrace.events.singleWhere((e) => e.kind == 'http.oversize').data;
    expect(guard['dimension'], 'retainedChars');
    expect(guard['reasoningChars'], greaterThan(kAiStreamRetainedChars));
    expect(guard['answerChars'], 0);
  });

  test('an unterminated line is bounded before the decoder buffers it',
      () async {
    final packet = utf8.encode(':' + 'x' * 700000);
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient.streaming((_, body) async {
              await body.drain<void>();
              return http.StreamedResponse(
                  Stream.fromIterable([packet, packet, packet, packet]), 200);
            }));
    addTearDown(backend.dispose);
    await expectLater(
        backend.respond(
            const AiPreferences(
                provider: AiProvider.deepseek, model: 'deepseek-flash'),
            AiRequest(
                id: 'long-line',
                instructions: 'Build.',
                context: '{}',
                messages: [AiMessage(role: 'user', text: 'a part')])),
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'response')));
    final guard =
        AiTrace.events.singleWhere((e) => e.kind == 'http.oversize').data;
    expect(guard['dimension'], 'lineBytes');
    expect(guard['retainedChars'], 0);
  });

  test(
      'wire limits count actual UTF-8 bytes and cannot be bypassed by comments',
      () async {
    final chunk = utf8.encode(': ${'ö' * 25}\r\n');
    var bytes = 0;
    await expectLater(
        aiStreamLines(Stream.fromIterable([chunk, chunk, chunk]),
                onBytes: (n) => bytes = n, maxWireBytes: 100)
            .toList(),
        throwsA(isA<AiStreamLimit>()
            .having((e) => e.dimension, 'dimension', 'wireBytes')));
    expect(bytes, chunk.length * 2);
  });

  test('short CRLF lines and split multibyte text preserve packet boundaries',
      () async {
    final bytes = utf8.encode(': ping\r\ndata: ä\n\ndata: [DONE]\r\n');
    final lines = await aiStreamLines(
            Stream.fromIterable(bytes.map((b) => [b])),
            onBytes: (_) {},
            maxLineBytes: 15)
        .toList();
    expect(lines, [': ping', 'data: ä', '', 'data: [DONE]']);
  });
}
