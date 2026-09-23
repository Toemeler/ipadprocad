// ISSUE #87 — "there were errors and it is not fdm printable or a good
// design". A teacup: a handle built as an extruded slab whose top arm printed
// in mid-air, three blocks lost to a fillet that could not find the rim, one
// to a sketch name the model guessed, and reference material that never
// mentioned cups because the build turn's message was only "fdm 200ml".
//
// The geometry side is proven on the real kernel in ai_real_kernel_test.dart
// and end to end in the benchmark's `teacup` scenario, whose replay is the
// knowledge document's own recipe. This file pins what needs no kernel.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_knowledge.dart';
import 'package:prototype/ai/ai_store.dart';
import 'package:prototype/app_state.dart';

import 'support/shape_fixtures.dart';

AiKnowledge _shippedCorpus() {
  final j = jsonDecode(File('assets/knowledge/kb.json').readAsStringSync())
      as Map<String, dynamic>;
  return AiKnowledge.forTest([
    for (final d in (j['documents'] as List).cast<Map>())
      KnowledgeDoc.fromJson(d.cast<String, dynamic>())
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the reference material a teacup gets', () {
    test('the whole request opens the mug recipe and the overhang rules', () {
      final ids = _shippedCorpus()
          .select('make me a teacup with a handle fdm 200ml')
          .map((d) => d.id)
          .toList();
      expect(ids, contains('fdm/examples/mug-with-handle'));
      expect(ids, contains('fdm/geometry/overhangs-and-bridging'));
    });

    test('"fdm 200ml" on its own does not — which is why the query now '
        'carries the conversation', () {
      final ids =
          _shippedCorpus().select('fdm 200ml').map((d) => d.id).toList();
      expect(ids, isNot(contains('fdm/examples/mug-with-handle')));
    });

    test('the recipe is sized to the owner\'s 30° overhang limit', () {
      final doc = _shippedCorpus().byId('fdm/examples/mug-with-handle')!;
      expect(doc.body, contains('30° from horizontal'));
      expect(doc.body, isNot(contains('"sketch_tool", "tool": "spline"')),
          reason: 'the handle is a leg, an arc and a leg, not a spline');
    });
  });

  group('the build turn is matched on what the user asked for', () {
    test('the second message still opens the cup documents', () async {
      final seen = <String>[];
      final backend = _Backend((r) async {
        seen.add(r.instructions);
        return AiReply(
            seen.length == 1
                ? 'How will it be made, and what capacity?'
                : 'Fertig.',
            'test');
      });
      final c = AiController(backend: backend);
      await c.initialize(_store());
      c.updateDraft('make me a teacup with a handle');
      await c.send();
      c.updateDraft('fdm 200ml');
      await c.send();
      expect(seen, hasLength(2));
      expect(seen.last, contains('fdm/examples/mug-with-handle — '),
          reason: 'the document is OPENED for the build turn, not just '
              'listed in the menu');
    });
  });

  group('sketches the model names itself', () {
    Future<AppState> part() async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_87_');
      await app.createNamedPart('Work');
      return app;
    }

    test('an id is the sketch\'s name, so a later action can say it', () async {
      final app = await part();
      final r = await AiCad(app).run(const [
        AiAction('create_sketch', {'plane': 'xz', 'id': 'base'}),
        AiAction('create_sketch', {'plane': 'xy', 'id': 'handle_path'}),
        AiAction('sketch_rect', {'sketch': 'base', 'width': 10, 'height': 10}),
        AiAction('extrude', {'sketch': 'base', 'distance': 5}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(app.currentPart!.sketchByName('handle_path'), isNotNull);
    });

    test('the same id redraws an unused sketch, and is refused for a used one',
        () async {
      final app = await part();
      final cad = AiCad(app);
      await cad.run(const [
        AiAction('create_sketch', {'plane': 'xz', 'id': 'draft'}),
        AiAction('create_sketch', {'plane': 'xz', 'id': 'draft'}),
      ]);
      expect(app.currentPart!.childSketches.length, 1);
      await cad.run(const [
        AiAction('sketch_rect', {'sketch': 'draft', 'width': 10, 'height': 10}),
        AiAction('extrude', {'sketch': 'draft', 'distance': 5}),
      ]);
      final r = await cad.run(const [
        AiAction('create_sketch', {'plane': 'xz', 'id': 'draft'}),
      ]);
      expect(r.ok, isFalse);
      expect(r.outcomes.single.error, contains('already used by'));
    });
  });
}

AiStore _store() =>
    AiStore(Directory.systemTemp.createTempSync('prototype_87_store_'));

class _Backend implements AiBackend {
  _Backend(this.reply);
  final Future<AiReply> Function(AiRequest) reply;
  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);
  @override
  Future<bool> hasKey(AiProvider provider) async => true;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) =>
      reply(request);
  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}
