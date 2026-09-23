// #92 — "Sobald der Prompt abgesendet wird will ich Arbeit sehen … es soll
// direkt arbeiten und max 5 sek oder so denken."
//
// One turn of the report: ten rounds, 278 s. Round 0 thought for 40.6 s
// before anything appeared; round 5 thought for 78.7 s and wrote a block of
// 14 actions that the 12-action cap then refused whole; round 3 lost 23.6 s
// to `"r_fl",` in its vars. `reasoning_effort: "low"` was already sent on
// every round — it is a hint, not a limit.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_models.dart';
import 'package:prototype/ai/ai_stream.dart';

String _sse(Map<String, dynamic> delta, {String? finish}) =>
    'data: ${jsonEncode({
          'id': 'x',
          'model': 'deepseek-flash',
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': finish}
          ]
        })}\n\n';

const _usage = 'data: {"choices":[],"usage":{"prompt_tokens":10,'
    '"completion_tokens":5,"completion_tokens_details":'
    '{"reasoning_tokens":3}}}\n\n';

AiRequest _request({void Function(AiStreamStage)? onStream}) => AiRequest(
    id: 'r1',
    instructions: 'Build.',
    context: '{}',
    messages: [AiMessage(role: 'user', text: 'make a spool')],
    onStream: onStream);

const _deepseek =
    AiPreferences(provider: AiProvider.deepseek, model: 'deepseek-flash');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            vault, (call) async => call.method == 'read' ? 'test-key' : null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null);
  });

  group('the stream is reassembled into one completion', () {
    test('reasoning, then the answer, then usage', () {
      final a = DeepSeekStreamAssembler();
      final stages = <AiStreamStage>[];
      for (final chunk in [
        _sse({'reasoning_content': 'Hmm. '}),
        _sse({'reasoning_content': 'A spool.'}),
        _sse({'content': '```cad\n'}),
        _sse({'content': '{}\n```'}, finish: 'stop'),
        _usage,
        'data: [DONE]\n\n',
      ]) {
        for (final line in const LineSplitter().convert(chunk)) {
          final s = a.addLine(line);
          if (s != null) stages.add(s);
        }
      }
      expect(stages, [AiStreamStage.thinking, AiStreamStage.writing]);
      expect(a.done, isTrue);
      final r = a.toResponse();
      final choice = (r['choices'] as List).single as Map;
      expect(choice['finish_reason'], 'stop');
      expect((choice['message'] as Map)['content'], '```cad\n{}\n```');
      expect((choice['message'] as Map)['reasoning_content'], 'Hmm. A spool.');
      expect((r['usage'] as Map)['prompt_tokens'], 10);
    });

    test('a plain JSON body — something ignored `stream` — still reads', () {
      final a = DeepSeekStreamAssembler();
      for (final line in const LineSplitter().convert(jsonEncode({
        'choices': [
          {
            'message': {'content': 'hi'},
            'finish_reason': 'stop'
          }
        ]
      }))) {
        a.addLine(line);
      }
      expect(a.streamed, isFalse);
      expect(((a.toResponse()['choices'] as List).single as Map)['message'],
          {'content': 'hi'});
    });
  });

  group('the thinking budget', () {
    test(
        'a round still only thinking past the budget is asked again, '
        'without thinking, and the panel hears each stage', () async {
      final bodies = <Map>[];
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient.streaming((req, body) async {
                final sent = jsonDecode(await utf8.decodeStream(body)) as Map;
                bodies.add(sent);
                final out = StreamController<List<int>>();
                () async {
                  if (sent['reasoning_effort'] != 'none') {
                    // Thinks forever, one chunk every 20 ms.
                    for (var i = 0; i < 200 && !out.isClosed; i++) {
                      out.add(utf8.encode(
                          _sse({'reasoning_content': 'more thought '})));
                      await Future<void>.delayed(
                          const Duration(milliseconds: 20));
                    }
                  } else {
                    out.add(utf8
                        .encode(_sse({'content': 'Done.'}, finish: 'stop')));
                    out.add(utf8.encode('data: [DONE]\n\n'));
                  }
                  await out.close();
                }();
                return http.StreamedResponse(out.stream, 200);
              }))
        ..thinkingBudget = const Duration(milliseconds: 150);
      addTearDown(backend.dispose);
      final stages = <AiStreamStage>[];
      final clock = Stopwatch()..start();
      final reply =
          await backend.respond(_deepseek, _request(onStream: stages.add));
      expect(reply.text, 'Done.');
      expect(clock.elapsed, lessThan(const Duration(seconds: 3)),
          reason: 'cut at the budget, not left to think for 4 s');
      expect(bodies, hasLength(2));
      expect(bodies.first['stream'], isTrue);
      expect(bodies.first['reasoning_effort'], 'low');
      expect(bodies.last['reasoning_effort'], 'none');
      expect(stages, [AiStreamStage.thinking, AiStreamStage.writing]);
    });

    test('a round that starts its answer in time is never cut', () async {
      var requests = 0;
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient.streaming((req, body) async {
                await body.drain<void>();
                requests++;
                final out = StreamController<List<int>>();
                () async {
                  out.add(utf8.encode(_sse({'reasoning_content': 'quick'})));
                  await Future<void>.delayed(const Duration(milliseconds: 30));
                  // Answering: a slow answer is fine, the budget is on thinking.
                  for (var i = 0; i < 10; i++) {
                    out.add(utf8.encode(_sse({'content': 'x'})));
                    await Future<void>.delayed(
                        const Duration(milliseconds: 30));
                  }
                  out.add(utf8.encode(_sse({}, finish: 'stop')));
                  out.add(utf8.encode('data: [DONE]\n\n'));
                  await out.close();
                }();
                return http.StreamedResponse(out.stream, 200);
              }))
        ..thinkingBudget = const Duration(milliseconds: 150);
      addTearDown(backend.dispose);
      final reply = await backend.respond(_deepseek, _request());
      expect(reply.text, 'xxxxxxxxxx');
      expect(requests, 1);
    });

    test('the budget is five seconds, and the model is told about it', () {
      expect(kAiThinkingBudget, const Duration(seconds: 5));
      expect(kAiActionInstructions, contains('THINK FOR SECONDS'));
    });
  });

  group('a JSON slip does not cost a round', () {
    test('the block from round 3: a key with no value', () {
      final b = parseAiActions('```cad\n{"title": "Spule", "vars": {"r_bore": '
          '0.425, "r_fl", "r_drum": 1.25}, "actions": '
          '[{"op": "describe_part"}]}\n```');
      expect(b.parseError, isNull);
      expect(b.actions.map((a) => a.op), ['vars', 'describe_part']);
      expect(b.actions.first.args, {'r_bore': 0.425, 'r_drum': 1.25});
      expect(b.notes.single, contains('"r_fl"'));
    });

    test('a trailing comma', () {
      final b = parseAiActions(
          '```cad\n{"actions": [{"op": "describe_part"},]}\n```');
      expect(b.parseError, isNull);
      expect(b.actions.single.op, 'describe_part');
      expect(b.notes.single, contains('trailing comma'));
    });

    test('anything that changes what the block says is still refused', () {
      for (final bad in [
        '[1 2]',
        '{"a": }',
        '{"a": 1,, "b": 2}',
        '{"a": "unterminated}',
        '{"a": [1, 2}',
        '{"a": 1} {"b": 2}',
      ]) {
        expect(aiRepairJson(bad), isNull, reason: bad);
      }
      expect(aiRepairJson('{"a": 1}'), isNull,
          reason: 'nothing to repair is not a repair');
    });
  });

  group('a block over the cap runs what fits', () {
    test('the first 12 run, the rest go back to be sent next', () {
      final ops = [
        for (var i = 0; i < 14; i++) '{"op": "describe_part", "n": $i}'
      ].join(',');
      final b = parseAiActions('```cad\n{"title": "t", "say": "Fertig.", '
          '"actions": [$ops]}\n```');
      expect(b.parseError, isNull);
      expect(b.actions, hasLength(kAiMaxActionsPerBlock));
      expect(b.notes.single, contains('"n":12'));
      expect(b.notes.single, contains('"n":13'));
      expect(b.say, isNull, reason: 'only part of the block ran');
    });

    test('notes and ticks do not count against the cap', () {
      final ops = [
        for (var i = 0; i < 12; i++) '{"op": "describe_part"}',
        for (var i = 0; i < 4; i++) '{"op": "brief_note", "text": "n$i"}',
      ].join(',');
      final b = parseAiActions('```cad\n{"actions": [$ops]}\n```');
      expect(b.actions, hasLength(16));
      expect(b.notes, isEmpty);
    });

    test('the model is told what the parser changed', () {
      final r =
          AiActionReport(outcomes: const []).withNotes(const ['held back: x']);
      expect(r.encode(), contains('held back: x'));
    });
  });
}
