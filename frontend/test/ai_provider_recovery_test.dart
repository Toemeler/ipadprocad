import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_store.dart';
import 'package:prototype/ai/ai_trace.dart';
import 'package:prototype/ai/ai_trace_store.dart';

const prefs =
    AiPreferences(provider: AiProvider.deepseek, model: 'deepseek-flash');
const part = AiDocument(id: 'mug', name: 'Tasse', kind: 'part');

String completion(String text, String? finish) => 'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': text},
              'finish_reason': finish
            }
          ],
        })}\n\ndata: [DONE]\n\n';

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

  for (final finish in ['aborted', 'insufficient_system_resource', null]) {
    test('retries $finish and never runs partial modelling code', () async {
      var requests = 0;
      var actions = 0;
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((_) async {
                requests++;
                return http.Response(
                    requests == 1
                        ? completion(
                            '```cad\n{"actions":[{"op":"build123d",'
                            '"part":"mug","code":"result=broken"}]}\n```',
                            finish)
                        : completion(
                            'Welche Größe soll die Tasse haben?', 'stop'),
                    200,
                    headers: {
                      'content-type': 'text/event-stream; charset=utf-8'
                    });
              }));
      final controller = AiController(backend: backend)
        ..initializeInMemory()
        ..build123dMode = true;
      addTearDown(controller.dispose);
      controller.updateWorkspace(current: part, documents: const [part]);
      controller.contextReader = (id) async => {'id': id, 'name': 'Tasse'};
      controller.actionRunner = (batch, {onStep}) async {
        actions++;
        return AiActionReport(outcomes: const []);
      };
      await controller.configure(provider: prefs.provider, model: prefs.model);
      controller.updateDraft('mach mir eine Tasse mit Henkel');
      await controller.send();
      expect(requests, 2);
      expect(actions, 0,
          reason: 'aborted Python must never reach the CAD runner');
      expect(controller.error, isNull);
      expect(controller.currentSession.messages.last.text,
          'Welche Größe soll die Tasse haben?');
      expect(AiTrace.events.any((e) => e.kind == 'turn.network.retry'), isTrue);
      expect(AiTrace.dump().join('\n'), contains('finish_reason=$finish'));
    });
  }

  test('repeated provider aborts stop after bounded retries', () async {
    var requests = 0;
    final controller = AiController(
        backend: DeviceAiBackend(
            clientFactory: () => MockClient((_) async {
                  requests++;
                  return http.Response(completion('partial', 'aborted'), 200);
                })))
      ..initializeInMemory();
    addTearDown(controller.dispose);
    controller.updateWorkspace(current: part, documents: const [part]);
    controller.contextReader = (id) async => {'id': id, 'name': 'Tasse'};
    await controller.configure(provider: prefs.provider, model: prefs.model);
    controller.updateDraft('mach mir eine Tasse mit Henkel');
    await controller.send();
    expect(requests, 1 + kAiMaxNetworkRetries);
    expect(controller.currentSession.errorCode, 'network');
    expect(controller.currentSession.draft, 'mach mir eine Tasse mit Henkel');
    expect(controller.currentSession.messages, isEmpty);
  });

  for (final entry in {
    'invalid_api_key': 'credentials',
    'insufficient_balance': 'billing',
    'rate_limit_exceeded': 'quota',
    'server_error': 'network'
  }.entries) {
    test('HTTP 200 stream error ${entry.key} keeps its real classification',
        () async {
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient((_) async => http.Response(
              'event: error\ndata: ${jsonEncode({
                    'error': {'code': entry.key, 'message': 'provider detail'},
                  })}\n\n',
              200)));
      addTearDown(backend.dispose);
      await expectLater(
          backend.respond(
              prefs,
              AiRequest(
                  id: 'r',
                  instructions: 'Build.',
                  context: '{}',
                  messages: [AiMessage(role: 'user', text: 'a mug')])),
          throwsA(
              isA<AiException>().having((e) => e.code, 'code', entry.value)));
      expect(AiTrace.dump().join('\n'), contains('provider detail'));
    });
  }

  test('SSE metadata and UTF-8 packet boundaries keep a complete reply',
      () async {
    final body = 'id: r\nevent: message\n: keep-alive\n\n'
        '${completion('Tasse mit Henkel – fertig', 'stop')}';
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient.streaming((_, request) async {
              await request.drain<void>();
              return http.StreamedResponse(
                  Stream.fromIterable(utf8.encode(body).map((b) => [b])), 200);
            }));
    addTearDown(backend.dispose);
    final reply = await backend.respond(
        prefs,
        AiRequest(
            id: 'r',
            instructions: 'Build.',
            context: '{}',
            messages: [AiMessage(role: 'user', text: 'a mug')]));
    expect(reply.text, 'Tasse mit Henkel – fertig');
  });

  test('a failed turn and provider response survive restart and deletion',
      () async {
    final directory = Directory.systemTemp.createTempSync('ai-recovery-');
    addTearDown(() => directory.deleteSync(recursive: true));
    DeviceAiBackend backend() => DeviceAiBackend(
        clientFactory: () => MockClient((_) async =>
            http.Response(completion('incomplete', 'tool_calls'), 200)));
    final first = AiController(backend: backend());
    await first.initialize(AiStore(directory));
    first.updateWorkspace(current: part, documents: const [part]);
    first.contextReader = (id) async => {'id': id, 'name': 'Tasse'};
    await first.configure(provider: prefs.provider, model: prefs.model);
    first.updateDraft('mach mir eine Tasse mit Henkel');
    await first.send();
    await first.flush();
    final failedAt =
        AiTrace.events.lastWhere((e) => e.kind == 'turn.failed').at;
    first.dispose();
    // Finish the close before simulating a process losing all memory.
    await first.flush();
    AiTrace.clear();
    final second = AiController(backend: backend());
    await second.initialize(AiStore(directory));
    second.updateWorkspace(current: part, documents: const [part]);
    second.contextReader = (id) async => {'id': id, 'name': 'Tasse'};
    expect(second.currentSession.errorCode, 'response');
    expect(second.currentSession.draft, 'mach mir eine Tasse mit Henkel');
    expect(
        AiTrace.events.lastWhere((e) => e.kind == 'turn.failed').at, failedAt);
    expect(AiTrace.dump().join('\n'), contains('incomplete'));
    await second.deleteAllConversations();
    second.dispose();
    await second.flush();
    AiTrace.clear();
    final journal = AiTraceStore(directory);
    await journal.open();
    expect(AiTrace.events, isEmpty);
    await journal.close();
  });

  test('corrupt trace journal does not disable the assistant', () async {
    final directory = Directory.systemTemp.createTempSync('ai-corrupt-trace-');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/ai_trace.json').writeAsStringSync('{broken');
    final controller = AiController(backend: DeviceAiBackend());
    await controller.initialize(AiStore(directory));
    expect(controller.isReady, isTrue);
    expect(controller.error, isNull);
    await controller.flush();
    controller.dispose();
    await controller.flush();
  });

  test('stopping during retry backoff prevents a new provider request',
      () async {
    var requests = 0;
    final controller = AiController(
        backend: DeviceAiBackend(
            clientFactory: () => MockClient((_) async {
                  requests++;
                  return http.Response(completion('partial', 'aborted'), 200);
                })))
      ..initializeInMemory();
    addTearDown(controller.dispose);
    controller.updateWorkspace(current: part, documents: const [part]);
    controller.contextReader = (id) async => {'id': id, 'name': 'Tasse'};
    await controller.configure(provider: prefs.provider, model: prefs.model);
    controller.updateDraft('Tasse');
    final turn = controller.send();
    while (!AiTrace.events.any((e) => e.kind == 'turn.network.retry')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    controller.cancel();
    await turn;
    expect(requests, 1);
    expect(controller.anyRequestBusy, isFalse);
  });

  test(
      'journal restores token totals and never saves credentials or image bytes',
      () async {
    final directory = Directory.systemTemp.createTempSync('ai-journal-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final journal = AiTraceStore(directory);
    await journal.open();
    AiTrace.record('probe', data: {
      'authorization': 'secret-key',
      'image': {'data': 'A' * 4096},
    });
    AiTrace.usage(
        provider: 'deepseek',
        model: prefs.model,
        requestId: 'r',
        usage: {'input': 123, 'output': 40, 'reasoning': 5, 'cacheRead': 80});
    await journal.close();
    final disk = journal.file.readAsStringSync();
    expect(disk, isNot(contains('secret-key')));
    expect(disk, isNot(contains('A' * 4096)));
    AiTrace.clear();
    final restored = AiTraceStore(directory);
    await restored.open();
    expect(AiTrace.totals.single.input, 123);
    expect(AiTrace.totals.single.output, 40);
    expect(AiTrace.totals.single.reasoning, 5);
    expect(AiTrace.totals.single.cacheRead, 80);
    expect(AiTrace.totals.single.requests, 1);
    await restored.close();
  });
}
