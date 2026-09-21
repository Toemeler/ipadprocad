// M446/M447 — orbiting to the question, and remembering what it is for.
//
// LOOK is the expensive channel and the last resort. The tests that matter
// are not "an image came back" but the honesty rules around it: a provider
// that cannot receive images is TOLD it did not receive one, a view carries
// the scale that makes it readable, and the op refuses rather than returning a
// blank frame when nothing can draw.
//
// THE BRIEF is the gap perception cannot close. Its tests are about the two
// distinctions that make it worth having: the user's own words are kept apart
// from the assistant's reading of them, and a recorded requirement is NOT
// rolled back when an unrelated extrusion later in the same block fails.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';

import 'support/shape_fixtures.dart';

void main() {
  // `look` renders through a PictureRecorder, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  final apps = <AppState>[];

  Future<AppState> partWithBox() async {
    final app = AppState()..partKernel = BoxKernel();
    app.docsDirForTest =
        Directory.systemTemp.createTempSync('prototype_m446_');
    apps.add(app);
    await app.createNamedPart('Bracket');
    final built = await AiCad(app).run([
      const AiAction('create_sketch', {'plane': 'xy'}),
      const AiAction('sketch_rect', {'width': 60, 'height': 40}),
      const AiAction('extrude', {'distance': 10}),
    ]);
    expect(built.ok, isTrue, reason: built.encode());
    return app;
  }

  tearDown(apps.clear);

  group('look', () {
    test('renders a view and returns it as an image', () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([const AiAction('look', {})]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.images, hasLength(1));
      expect(report.images.single.isImage, isTrue);
      expect(report.images.single.bytes, isNotEmpty);
    });

    test('carries the scale that makes an image readable', () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([const AiAction('look', {})]);
      final d = report.outcomes.single.detail!;
      expect(d['projection'], 'orthographic');
      expect(d['scaleNote'], contains('60.00 × 40.00 × 10.00 mm'));
      // The rule that keeps a picture from becoming a measurement.
      expect(d['note'], contains('never off this image'));
    });

    test('the angles are the model\'s to choose', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('look', {'az': 120, 'pol': 30})]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['azDeg'], 120);
      expect(report.outcomes.single.detail!['polDeg'], 30);
    });

    test('a pol AT the pole is nudged off it, and says so', () async {
      // M455 supersedes the refusal this used to assert. pol 0 is the view
      // from straight above — the most useful one for checking a footprint —
      // and refusing it (twice, in issues #73 and #77) made the model spend a
      // round discovering a rule it could not have guessed. The basis only
      // degenerates exactly AT the pole, which the app's own plane views have
      // always handled by nudging a thousandth of a radian off it.
      //
      // "not silently" is the part that still holds: the report says the
      // angle was moved and what it was moved to.
      final app = await partWithBox();
      final report =
          await AiCad(app).run([const AiAction('look', {'pol': 0})]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      expect(d['polDeg'], greaterThan(0));
      expect(d['polNote'], contains('along the up axis'));
    });

    test('looking is not a change and takes no undo entry', () async {
      final app = await partWithBox();
      final before = app.canUndoPart;
      await AiCad(app).run([const AiAction('look', {})]);
      expect(app.canUndoPart, before);
    });

    test('a part with nothing built refuses rather than drawing an empty '
        'frame', () async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m446_empty_');
      apps.add(app);
      await app.createNamedPart('Empty');
      final report = await AiCad(app).run([const AiAction('look', {})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('no built body'));
    });

    test('at most two views in a block', () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([
        const AiAction('look', {'az': 0}),
        const AiAction('look', {'az': 90}),
        const AiAction('look', {'az': 180}),
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.last.error, contains('at most two views'));
    });
  });

  group('a view only travels to a provider that can receive one', () {
    test('a text-only provider is told it has NOT seen the view', () {
      final image = AiAttachment.fromBytes(
          name: 'view.png',
          bytes: Uint8List.fromList(
              [137, 80, 78, 71, 13, 10, 26, 10, ...List.filled(40, 0)]));
      final report = AiActionReport(
          outcomes: const [AiActionOutcome('look')], images: [image]);
      final message = aiToolMessage(report, withImages: false);
      expect(message.attachments, isEmpty);
      final decoded = jsonDecode(message.text) as Map;
      expect(decoded['viewsNotSent'], contains('have NOT seen it'));
      expect(decoded['viewsNotSent'], contains('Do not describe it'));
    });

    test('a provider that can see images gets the attachment', () {
      final image = AiAttachment.fromBytes(
          name: 'view.png',
          bytes: Uint8List.fromList(
              [137, 80, 78, 71, 13, 10, 26, 10, ...List.filled(40, 0)]));
      final report = AiActionReport(
          outcomes: const [AiActionOutcome('look')], images: [image]);
      final message = aiToolMessage(report);
      expect(message.attachments, hasLength(1));
      expect(jsonDecode(message.text), isNot(contains('viewsNotSent')));
    });
  });

  group('the brief', () {
    test('keeps the user\'s words apart from the assistant\'s reading',
        () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([
        const AiAction('brief_note', {
          'text': 'The channel must clear a 6 mm cable.',
          'kind': 'must',
          'source': 'it has to fit my thick charging cable',
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final brief = app.ai.briefs.of(app.ai.document.id);
      expect(brief, hasLength(1));
      expect(brief.single.kind, AiRequirementKind.must);
      expect(brief.single.source, 'it has to fit my thick charging cable');
      // The formalisation and the evidence are different strings.
      expect(brief.single.text, isNot(brief.single.source));
    });

    test('an unlabelled note is an assumption, not a requirement', () async {
      final app = await partWithBox();
      await AiCad(app).run([
        const AiAction('brief_note', {'text': 'Probably wall-mounted.'})
      ]);
      expect(app.ai.briefs.of(app.ai.document.id).single.kind,
          AiRequirementKind.assumption);
    });

    test('survives a rolled-back block, because it is not geometry', () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([
        const AiAction('brief_note', {'text': 'Must clear 6 mm.', 'kind': 'must'}),
        const AiAction('extrude', {'distance': -1}),
      ]);
      expect(report.reverted, isTrue);
      // The extrusion is gone; what the user said is not.
      expect(app.ai.briefs.of(app.ai.document.id), hasLength(1));
    });

    test('brief_done closes one, and an unknown id is refused', () async {
      final app = await partWithBox();
      await AiCad(app).run([
        const AiAction('brief_note', {'text': 'Must clear 6 mm.', 'kind': 'must'})
      ]);
      final id = app.ai.briefs.of(app.ai.document.id).single.id;
      final ok = await AiCad(app).run([AiAction('brief_done', {'id': id})]);
      expect(ok.ok, isTrue, reason: ok.encode());
      expect(app.ai.briefs.of(app.ai.document.id).single.done, isTrue);

      final bad = await AiCad(app)
          .run([const AiAction('brief_done', {'id': 'nope'})]);
      expect(bad.ok, isFalse);
      expect(bad.outcomes.single.error, contains('no requirement'));
    });

    test('reads back as instructions not to re-ask', () {
      final briefs = AiBriefs();
      briefs.add(
          'doc',
          AiRequirement(
              text: 'Clear a 6 mm cable.',
              kind: AiRequirementKind.must,
              source: 'my thick cable'));
      final text = briefs.contextFor('doc')!;
      expect(text, contains('[must] Clear a 6 mm cable.'));
      expect(text, contains('user said: "my thick cable"'));
      expect(text, contains('Do not re-ask'));
      expect(text, contains('only the user can'));
    });

    test('a done requirement drops out of the working set', () {
      final briefs = AiBriefs();
      final r = briefs.add('doc', AiRequirement(text: 'Fits the desk.'));
      briefs.markDone('doc', r.id);
      expect(briefs.contextFor('doc'), contains('all 1 requirement(s)'));
    });

    test('it follows a document that is renamed', () {
      final briefs = AiBriefs();
      briefs.add('old', AiRequirement(text: 'Clear 6 mm.'));
      briefs.migrate('old', 'new');
      expect(briefs.of('old'), isEmpty);
      expect(briefs.of('new'), hasLength(1));
    });

    test('it is bounded, like everything else that rides the context', () {
      final briefs = AiBriefs();
      for (var i = 0; i < kAiMaxRequirements; i++) {
        briefs.add('doc', AiRequirement(text: 'Requirement $i'));
      }
      expect(() => briefs.add('doc', AiRequirement(text: 'one too many')),
          throwsA(isA<AiException>()));
    });

    test('it round-trips through the store', () {
      final briefs = AiBriefs();
      briefs.add(
          'doc',
          AiRequirement(
              text: 'Clear 6 mm.',
              kind: AiRequirementKind.must,
              source: 'thick cable'));
      final restored = AiBriefs()..loadJson(briefs.toJson());
      final r = restored.of('doc').single;
      expect(r.text, 'Clear 6 mm.');
      expect(r.kind, AiRequirementKind.must);
      expect(r.source, 'thick cable');
    });
  });

  group('the brief reaches the model', () {
    test('a recorded requirement rides in the next turn\'s context', () async {
      final backend = _Backend();
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      const document = AiDocument(id: 'doc', name: 'Bracket', kind: 'part');
      controller
        ..contextReader = ((id) async => {'id': id, 'name': 'Bracket'})
        ..updateWorkspace(current: document, documents: const [document]);
      controller.briefs.add(
          'doc',
          AiRequirement(
              text: 'Clear a 6 mm cable.', kind: AiRequirementKind.must));
      controller.updateDraft('Make it thinner');
      await controller.send();
      final context =
          jsonDecode(backend.requests.single.context) as Map<String, dynamic>;
      expect(context['brief'], contains('Clear a 6 mm cable.'));
    });

    test('a document with no brief adds nothing to the turn', () async {
      final backend = _Backend();
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      const document = AiDocument(id: 'doc', name: 'Bracket', kind: 'part');
      controller
        ..contextReader = ((id) async => {'id': id, 'name': 'Bracket'})
        ..updateWorkspace(current: document, documents: const [document]);
      controller.updateDraft('Hello');
      await controller.send();
      expect(jsonDecode(backend.requests.single.context),
          isNot(contains('brief')));
    });
  });
}

class _Backend implements AiBackend {
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
