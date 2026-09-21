// M443 — a bug report about the assistant now contains the assistant.
//
// Every test here is a question a report could not previously answer:
// how many tokens, what was it thinking, what did the provider actually say
// when it refused, what did the app send, and which ops did it run.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_trace.dart';
import 'package:prototype/bug_report.dart';

const _part =
    AiDocument(id: '/parts/bracket.ptp', name: 'Bracket', kind: 'part');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    AiTrace.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            vault,
            (call) async => call.method == 'read'
                ? 'test-key-not-a-real-credential'
                : null);
  });
  tearDown(() {
    AiTrace.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null);
  });

  AiRequest request({String id = 'request'}) => AiRequest(
        id: id,
        instructions: 'Only inspect.',
        context: '{"name":"Bracket"}',
        sessionId: 'session-1',
        round: 0,
        messages: [AiMessage(role: 'user', text: 'How thick is the wall?')],
      );

  AiTraceEvent? firstOf(String kind) {
    for (final e in AiTrace.events) {
      if (e.kind == kind) return e;
    }
    return null;
  }

  group('the recorder', () {
    test('keeps prompts, blanks credentials and describes binary payloads', () {
      final scrubbed = AiTrace.scrub({
        'system': 'You are the CAD design assistant in Prototype.',
        'api_key': 'sk-do-not-keep-this',
        'x-goog-api-key': 'also-not-this',
        'messages': [
          {
            'content': [
              {'type': 'text', 'text': 'How thick is the wall?'},
              {
                'type': 'image',
                'source': {
                  'media_type': 'image/png',
                  'data': 'A' * 4096,
                }
              }
            ]
          }
        ],
      }) as Map<String, dynamic>;

      // The prompt is the point of the file and survives whole.
      expect(jsonEncode(scrubbed), contains('How thick is the wall?'));
      expect(scrubbed['system'],
          'You are the CAD design assistant in Prototype.');
      // A credential never reaches the bundle, whatever it is called.
      expect(scrubbed['api_key'], '<redacted>');
      expect(scrubbed['x-goog-api-key'], '<redacted>');
      expect(jsonEncode(scrubbed), isNot(contains('sk-do-not-keep-this')));
      // ...and 4 KB of base64 becomes a sentence, not 4 KB.
      final image = ((scrubbed['messages'] as List).first
          as Map)['content'] as List;
      final source = (image.last as Map)['source'] as Map;
      expect(source['media_type'], 'image/png');
      expect('${source['data']}', contains('binary payload'));
      expect('${source['data']}'.length, lessThan(120));
    });

    test('drops the oldest events rather than growing without bound', () {
      for (var i = 0; i < AiTrace.capacity + 50; i++) {
        AiTrace.record('probe', data: {'i': i});
      }
      expect(AiTrace.events.length, AiTrace.capacity);
      expect(AiTrace.dropped, 50);
      expect(AiTrace.events.first.data['i'], 50);
      // ...and the dump says so, so nobody reads the first surviving event as
      // the first request of the session.
      expect(AiTrace.dump().first, contains('50 earlier event(s) dropped'));
    });
  });

  group('what a provider round now leaves behind', () {
    test('Claude: tokens, thinking, stop reason and the reply', () async {
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((r) async => http.Response(
              jsonEncode({
                'stop_reason': 'end_turn',
                'usage': {
                  'input_tokens': 1234,
                  'output_tokens': 56,
                  'cache_read_input_tokens': 900,
                  'cache_creation_input_tokens': 12,
                },
                'content': [
                  {
                    'type': 'thinking',
                    'thinking': 'The digest gives a minimum wall of 2.0 mm.'
                  },
                  {'type': 'text', 'text': 'The thinnest wall is 2.0 mm.'}
                ],
              }),
              200,
              headers: {'content-type': 'application/json'})));
      addTearDown(backend.dispose);

      final reply = await backend.respond(
          const AiPreferences(
              provider: AiProvider.anthropic, model: 'claude-test'),
          request());
      expect(reply.text, 'The thinnest wall is 2.0 mm.');

      // TOKENS — normalised, and added to the session totals.
      final usage = firstOf('usage')!;
      expect(usage.data['input'], 1234);
      expect(usage.data['output'], 56);
      expect(usage.data['cacheRead'], 900);
      expect(usage.data['cacheWrite'], 12);
      expect(AiTrace.totals.single.input, 1234);
      expect(AiTrace.totalsJson['output'], 56);

      // THINKING — filtered out of the answer, kept in the trace.
      final thinking = firstOf('thinking')!;
      expect(thinking.data['stopReason'], 'end_turn');
      expect('${thinking.data['text']}', contains('minimum wall of 2.0 mm'));

      // THE REQUEST, as the wire saw it, with the credential nowhere in it.
      final sent = firstOf('http.request')!;
      expect(sent.data['endpoint'], 'https://api.anthropic.com/v1/messages');
      expect(jsonEncode(sent.data['body']), contains('How thick is the wall?'));
      expect(jsonEncode(sent.toJson()),
          isNot(contains('test-key-not-a-real-credential')));

      // ...and the stitching that makes a flat list readable as a round.
      expect(sent.sessionId, 'session-1');
      expect(sent.round, 0);
      expect(firstOf('reply')!.data['text'], 'The thinnest wall is 2.0 mm.');
    });

    test("a refusal keeps the provider's own words, not just a code", () async {
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((r) async => http.Response(
              '{"error":{"type":"rate_limit_error",'
              '"message":"tier 1 limit of 50 requests per minute"}}',
              429)));
      addTearDown(backend.dispose);

      await expectLater(
          backend.respond(
              const AiPreferences(
                  provider: AiProvider.anthropic, model: 'claude-test'),
              request()),
          throwsA(isA<AiException>()
              .having((e) => e.code, 'code', 'quota')));

      final failure = firstOf('http.error')!;
      expect(failure.data['status'], 429);
      expect('${failure.data['body']}',
          contains('tier 1 limit of 50 requests per minute'));
      expect(failure.data['elapsedMs'], isA<int>());
      // The code the user was shown is recorded beside the reason for it.
      expect(firstOf('error')!.data['code'], 'quota');
    });

    test('DeepSeek reasoning is recorded even though it is never shown',
        () async {
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((r) async => http.Response(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {
                      'reasoning_content': 'Wall = 10 - 2*4 = 2 mm.',
                      'content': '2 mm.',
                    }
                  }
                ],
                'usage': {
                  'prompt_tokens': 800,
                  'completion_tokens': 20,
                  'completion_tokens_details': {'reasoning_tokens': 300},
                  'prompt_cache_hit_tokens': 640,
                },
              }),
              200)));
      addTearDown(backend.dispose);

      final reply = await backend.respond(
          const AiPreferences(
              provider: AiProvider.deepseek, model: 'deepseek-chat'),
          request());
      // Still not shown to the user...
      expect(reply.text, '2 mm.');
      // ...and now recoverable from a bug report.
      expect('${firstOf('thinking')!.data['text']}', contains('10 - 2*4'));
      expect(firstOf('usage')!.data['reasoning'], 300);
      expect(firstOf('usage')!.data['cacheRead'], 640);
    });
  });

  group('the conversation the bundle carries', () {
    test('every turn including the app\'s own, with no attachment bytes',
        () async {
      final backend = _ScriptedBackend([
        'Building it.\n```cad\n{"actions":[{"op":"create_sketch",'
            '"plane":"xy"}]}\n```',
        'Done — the sketch exists.',
      ]);
      final controller = AiController(backend: backend)..initializeInMemory();
      controller.contextReader =
          (id) async => <String, dynamic>{'id': id, 'name': 'Bracket'};
      controller.actionRunner =
          (batch, {onStep}) async => AiActionReport(outcomes: [
            for (final a in batch) AiActionOutcome(a.op, detail: {'made': 1})
          ]);
      addTearDown(controller.dispose);
      controller.updateWorkspace(current: _part, documents: const [_part]);
      controller.addAttachment(AiAttachment.fromBytes(
          name: 'reference.png',
          bytes: Uint8List.fromList(
              [137, 80, 78, 71, 13, 10, 26, 10, ...List.filled(900, 7)])));
      controller.updateDraft('Add a 60x40 plate');
      await controller.send();

      final export = controller.exportSessions();
      final encoded = jsonEncode(export);
      final messages =
          ((export['sessions'] as List).first as Map)['messages'] as List;
      final roles = [for (final m in messages) (m as Map)['role']];
      // The user's ask, the model's answer, the APP's report of what the block
      // did, and the model's answer to that.
      expect(roles, ['user', 'assistant', 'tool', 'assistant']);
      expect(encoded, contains('Add a 60x40 plate'));
      expect(encoded, contains('create_sketch'));
      // The attachment is described, never carried: #46 was a bundle that
      // could not be uploaded because one member was too big.
      expect(encoded, contains('reference.png'));
      expect(encoded, contains('"bytes":908'));
      expect(encoded, isNot(contains(base64Encode(List.filled(60, 7)))));

      // ...and the same conversation as prose, which is what a person opens.
      final transcript = controller.transcript().join('\n');
      expect(transcript, contains('USER'));
      expect(transcript, contains('APP (what the block actually did)'));
      expect(transcript, contains('Add a 60x40 plate'));
      expect(transcript, contains('[attached reference.png, image/png,'));

      // The trace stitched the two rounds together.
      expect(
          AiTrace.events.where((e) => e.kind == 'round').length, 2);
      expect(firstOf('turn.begin')!.data['userText'], 'Add a 60x40 plate');
      expect(firstOf('actions.parsed')!.data['count'], 1);
      expect(firstOf('actions.report')!.data['applied'], 1);
      expect(firstOf('turn.end')!.data['rounds'], 2);

      // Which provider, which model, whether it could edit at all.
      final diagnostics = controller.diagnostics();
      expect(diagnostics['canEditModel'], isTrue);
      expect(diagnostics['currentSessionMessages'], 4);
      expect(diagnostics['sessions'], 1);
    });

    test('reading the diagnostics does not manufacture a session', () {
      final controller = AiController(backend: _ScriptedBackend(const []))
        ..initializeInMemory();
      addTearDown(controller.dispose);
      controller.updateWorkspace(current: _part, documents: const [_part]);
      expect(controller.diagnostics()['sessions'], 0);
      expect(controller.exportSessions()['sessionCount'], 0);
      expect(controller.transcript().first, contains('no assistant'));
    });

    test('deleting every conversation also forgets the trace', () async {
      AiTrace.record('turn.begin', data: {'userText': 'a private question'});
      final controller = AiController(backend: _ScriptedBackend(const []))
        ..initializeInMemory();
      addTearDown(controller.dispose);
      await controller.deleteAllConversations();
      expect(AiTrace.events, isEmpty);
      expect(AiTrace.dump().join('\n'), isNot(contains('private question')));
    });
  });

  group('the bundle', () {
    Map<String, String> bundle({List<String> notes = const []}) => buildBundle(
          description: 'the assistant said the diameter is 5 mm',
          when: DateTime.utc(2026, 9, 21, 9, 30),
          env: const {'build': 'test'},
          part: null,
          aiDiagnosticsJson: '{"provider":"apple","available":true}',
          aiTranscriptText: 'USER\nwhat is this part?',
          aiSessionsJson: '{"sessionCount":1}',
          aiTraceText: 'TOKENS  anthropic · claude-test: 1 request(s)',
          aiTraceJson: '{"events":[]}',
          aiNotes: notes,
        );

    test('carries the assistant members and says what each one is for', () {
      final files = bundle();
      expect(files.keys,
          containsAll(<String>[
            'ai/diagnostics.json',
            'ai/transcript.txt',
            'ai/sessions.json',
            'ai/trace.txt',
            'ai/trace.json',
          ]));
      expect(files['ai/transcript.txt'], contains('what is this part?'));
      final report = files['report.md']!;
      // The contents page sends the reader to the right file first.
      expect(report, contains('`ai/diagnostics.json`'));
      expect(report, contains('READ THIS FIRST'));
      expect(report, contains('`ai/trace.txt`'));
      expect(report, contains('why did it say that'));
    });

    test('states the assistant findings in their own section', () {
      final report = bundle(notes: [
        'PROVIDER UNAVAILABLE: Apple Intelligence — Turn on Apple '
            'Intelligence in the device Settings',
        'LAST TURN FAILED: quota in session "Bracket review"',
      ])['report.md']!;
      expect(report, contains('## Assistant'));
      expect(report, contains('- PROVIDER UNAVAILABLE: Apple Intelligence'));
      expect(report, contains('- LAST TURN FAILED: quota'));
      // The model's own triage stays where it was; the two do not merge.
      expect(report.indexOf('## Triage'),
          lessThan(report.indexOf('## Assistant')));
    });

    test('a bundle from a build with no assistant data is still well formed',
        () {
      final files = buildBundle(
        description: 'unrelated',
        when: DateTime.utc(2026, 9, 21),
        env: const {},
        part: null,
      );
      expect(files.containsKey('ai/trace.txt'), isFalse);
      expect(files['report.md'], isNot(contains('## Assistant')));
      expect(files.containsKey('report.md'), isTrue);
    });
  });
}

/// Replies from a fixed script, so the action loop can be driven without a
/// provider. Anything past the end of the script is a plain closing answer.
class _ScriptedBackend implements AiBackend {
  _ScriptedBackend(this.replies);
  final List<String> replies;
  int sent = 0;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider,
          label: 'Test provider',
          available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async =>
      AiReply(
          sent < replies.length ? replies[sent++] : 'Nothing further.', 'test');

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
