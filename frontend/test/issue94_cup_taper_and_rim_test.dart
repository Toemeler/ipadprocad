// #94 — "es war besser aber es ist sehr viel schief gelaufen". Build 5b90367.
//
// "make a simple fdm pla cup 250ml … ohne Henkel, konisch … einen einfachen
// Henkel, eckig":
//
//   * The cup came out upside down: taper -5.94 on a Ø60 base, meant to open
//     to Ø78, narrowed instead. The instructions never said which sign is
//     which. The handle, placed against where the wall would have been, then
//     touched the cup only at its foot and stood off it at the top.
//   * The rim fillet used "rings" and also rounded the foot and the floor;
//     the foot chamfer then used "outer" and failed on the filleted rim.
//     There was no way to say "the rim" or "the foot".
//   * Every round thought for exactly 5 s, was cut, and was asked again —
//     6.5 s and a 30k-token resend per round, for the no-thinking answer it
//     ended up with anyway.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_models.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

import 'support/shape_fixtures.dart';

/// A box 60 × 40 (Y, up) × h with three edges: at the foot, halfway, at the
/// top.
class _Heights extends BoxKernel {
  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => const [
        OcctEdgeInfo(1, 1, 30, 0, 0, 1, 0, 0, 60, 0, 2, 90, 1),
        OcctEdgeInfo(2, 1, 60, 20, 0, 0, 0, 1, 10, 0, 2, 90, 1),
        OcctEdgeInfo(3, 1, 30, 40, 0, 1, 0, 0, 60, 0, 2, 90, 1),
      ];
}

String _sse(Map<String, dynamic> delta, {String? finish}) =>
    'data: ${jsonEncode({
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': finish}
          ]
        })}\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('taper says which way it went', () {
    test('the instructions give the sign', () {
      expect(kAiActionInstructions, contains('POSITIVE'));
      expect(kAiActionInstructions,
          contains('opens wider at the top is a positive taper'));
    });

    test('a negative taper is reported as narrowing', () async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_94_');
      await app.createNamedPart('Cup');
      final r = await AiCad(app).run(const [
        AiAction('create_sketch', {'plane': 'xz'}),
        AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 60}),
        AiAction('extrude', {'distance': 86.5, 'taper': -5.94}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final d = r.outcomes.last.detail!;
      expect(d['taper'], -5.94);
      expect(d['taperNote'], contains('SMALLER'));
    });
  });

  group('the rim and the foot can be named', () {
    Future<AppState> part() async {
      final app = AppState()..partKernel = _Heights();
      app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_94_');
      await app.createNamedPart('Cup');
      final r = await AiCad(app).run(const [
        AiAction('create_sketch', {'plane': 'xz'}),
        AiAction('sketch_rect', {'width': 60, 'height': 10}),
        AiAction('extrude', {'distance': 10}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      return app;
    }

    for (final (sel, y) in const [
      ('top', 40.0),
      ('rim', 40.0),
      ('bottom', 0.0)
    ]) {
      test('"$sel" takes only the edge at y=$y', () async {
        final app = await part();
        final r = await AiCad(app).run([
          AiAction('fillet', {'radius': 1, 'edges': sel})
        ]);
        expect(r.ok, isTrue, reason: r.encode());
        expect(r.outcomes.single.detail!['edges'], 1);
      });
    }

    test('the instructions point a rim and a foot at them', () {
      expect(kAiActionInstructions, contains('never "rings"'));
    });
  });

  group('a turn cut once is not cut again', () {
    const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              vault, (call) async => call.method == 'read' ? 'k' : null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(vault, null);
    });

    test('the second round of the turn goes straight to no thinking', () async {
      final efforts = <String?>[];
      final backend = DeviceAiBackend(
          clientFactory: () => MockClient.streaming((req, body) async {
                final sent = jsonDecode(await utf8.decodeStream(body)) as Map;
                efforts.add(sent['reasoning_effort'] as String?);
                final out = StreamController<List<int>>();
                () async {
                  if (sent['reasoning_effort'] != 'none') {
                    for (var i = 0; i < 200 && !out.isClosed; i++) {
                      out.add(utf8.encode(_sse({'reasoning_content': '…'})));
                      await Future<void>.delayed(
                          const Duration(milliseconds: 20));
                    }
                  } else {
                    out.add(
                        utf8.encode(_sse({'content': 'ok'}, finish: 'stop')));
                    out.add(utf8.encode('data: [DONE]\n\n'));
                  }
                  await out.close();
                }();
                return http.StreamedResponse(out.stream, 200);
              }))
        ..thinkingBudget = const Duration(milliseconds: 100);
      // Pins the thinking path itself, which the app no longer
      // takes by default (AI lab v7).
      backend.neverThink = false;
      addTearDown(backend.dispose);
      AiRequest round(int n) => AiRequest(
          id: 'turn-1',
          instructions: 'Build.',
          context: '{}',
          round: n,
          messages: [AiMessage(role: 'user', text: 'cup')]);
      const prefs =
          AiPreferences(provider: AiProvider.deepseek, model: 'deepseek-flash');
      await backend.respond(prefs, round(0));
      expect(efforts, ['low', 'none'], reason: 'cut, then asked again');
      await backend.respond(prefs, round(1));
      expect(efforts, ['low', 'none', 'none'],
          reason: 'round 1 of the same turn is not made to think and wait');
      await backend.respond(
          prefs,
          AiRequest(
              id: 'turn-2',
              instructions: 'Build.',
              context: '{}',
              messages: [AiMessage(role: 'user', text: 'cup')]));
      expect(efforts[3], 'low', reason: 'a new turn may think again');
    });
  });
}
