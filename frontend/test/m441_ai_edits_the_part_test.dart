// M441 — the assistant models, instead of describing what it would model.
//
// Three layers, three kinds of test, and the split is deliberate.
//
//   PROTOCOL (`ai_actions.dart`) — pure text in, typed actions out. Tested
//   without an app at all, because a parser that guesses at a malformed block
//   is a parser that guesses at geometry.
//
//   EXECUTION (`ai_cad.dart`) — actions against a real AppState with a stub
//   kernel. This is where the claims that matter live: a block is one
//   transaction, a failed block leaves NOTHING behind, and the report says
//   what the document actually contains rather than what was asked for.
//
//   THE LOOP (`AiController.send`) — that a reply carrying a block is executed
//   and the RESULT goes back to the model before it answers the user. Without
//   this the model writes its summary blind, which is the failure mode the
//   whole design exists to prevent.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A kernel that builds something for every operation, so the tests measure
/// the APP's bookkeeping rather than OCCT's. Volume carries the extruded
/// height, which is enough to tell one build from another.
class _StubKernel implements PartKernel {
  int extrudes = 0, fillets = 0;

  @override
  bool get available => true;
  @override
  String get info => 'stub';
  @override
  String get lastError => 'stub failure';

  KernelSolid _mk(double v) => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return _mk(height);
  }

  @override
  KernelSolid? revolve(List<List<List<Offset>>> groups, double angleDeg,
          double axPx, double axPy, double axDx, double axDy,
          List<double> mat34) =>
      _mk(angleDeg);

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) => _mk(3);
  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) => _mk(4);
  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) => _mk(5);
  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> e, List<double> r,
      {List<double> radii2 = const [], BlendReport? report}) {
    fillets++;
    return _mk(6);
  }

  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => [
        OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 20, 0, 2, 90, 1),
        OcctEdgeInfo(2, 1, 10, 0, 0, 0, 1, 0, 20, 0, 2, 90, 1),
      ];

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  final temporary = <Directory>[];
  final apps = <AppState>[];

  Future<AppState> emptyPart() async {
    final app = AppState()..partKernel = _StubKernel();
    final dir = Directory.systemTemp.createTempSync('prototype_m441_');
    temporary.add(dir);
    apps.add(app);
    app.docsDirForTest = dir;
    await app.createNamedPart('Bracket');
    return app;
  }

  /// The three actions that make a solid from nothing.
  List<AiAction> makeBlock({double distance = 10}) => [
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_rect',
            {'x': 0, 'y': 0, 'width': 60, 'height': 40}),
        AiAction('extrude', {'distance': distance}),
      ];

  // No dispose, and no directory delete — the same shape every other AppState
  // fixture in this suite uses (m128_end_of_part_test and friends).
  //
  // It is not laziness. Several AppState paths fire `savePart` WITHOUT
  // awaiting it — `renameFeature` is one — so a write can still be in flight
  // when the test body returns. Disposing the notifier or deleting its
  // directory underneath that write surfaces as an unhandled async error, and
  // the test runner attributes it to whichever test happens to be running
  // next. That is exactly how this file first went red in CI: three failures,
  // none of them in the code under test, all of them passing in isolation.
  tearDown(() {
    apps.clear();
    temporary.clear();
  });

  group('the protocol', () {
    test('a fenced block parses to typed actions and leaves the prose alone',
        () {
      const reply = 'I will start with the base plate.\n\n'
          '```cad\n'
          '{"actions": [{"op": "create_sketch", "plane": "xy"},\n'
          '             {"op": "sketch_rect", "width": 60, "height": 40}]}\n'
          '```\n\n'
          'Then we can talk about the ribs.';
      final block = parseAiActions(reply);
      expect(block.parseError, isNull);
      expect(block.actions.map((a) => a.op),
          ['create_sketch', 'sketch_rect']);
      expect(block.actions[1].number('width'), 60);
      final shown = aiReplyWithoutActions(reply);
      expect(shown, contains('base plate'));
      expect(shown, contains('ribs'));
      expect(shown, isNot(contains('sketch_rect')));
    });

    test('an op that does not exist is refused, not ignored', () {
      final block = parseAiActions(
          '```cad\n{"actions":[{"op":"run_shell","cmd":"rm -rf /"}]}\n```');
      expect(block.actions, isEmpty);
      expect(block.parseError, contains('run_shell'));
    });

    test('a malformed block reports itself rather than half-executing', () {
      final block = parseAiActions('```cad\n{"actions": [{"op": \n```');
      expect(block.actions, isEmpty);
      expect(block.parseError, isNotNull);
    });

    test('an oversized block runs what fits and hands the rest back (#92)',
        () {
      // Was "refused whole" — which threw away a 79-second round in #92 for
      // being two actions over. The cap still holds; the overflow is now
      // returned to the model to send next instead of discarding all of it.
      final actions = [
        for (var i = 0; i < kAiMaxActionsPerBlock + 1; i++)
          '{"op":"describe_part"}'
      ].join(',');
      final block = parseAiActions('```cad\n{"actions":[$actions]}\n```');
      expect(block.actions, hasLength(kAiMaxActionsPerBlock));
      expect(block.parseError, isNull);
      expect(block.notes.single, contains('$kAiMaxActionsPerBlock'));
    });

    test('a reply with no block is not an action block', () {
      final block = parseAiActions('Use a 3 mm wall. ```dart\nvoid main(){}\n```');
      expect(block.isEmpty, isTrue);
    });

    test('a number may be written with its unit, and only its unit', () {
      const withUnit = AiAction('extrude', {'distance': '12 mm'});
      expect(withUnit.number('distance'), 12);
      // An inch is not silently 25.4 mm: a converted number nobody asked for
      // is how a part comes out the wrong size with no line to blame.
      const inches = AiAction('extrude', {'distance': '2 in'});
      expect(inches.number('distance'), isNull);
    });
  });

  group('execution', () {
    test('sketch, rectangle and extrude build a real feature', () async {
      final app = await emptyPart();
      final report = await AiCad(app).run(makeBlock());
      expect(report.ok, isTrue, reason: report.encode());
      final part = app.currentPart!;
      expect(part.childSketches, hasLength(1));
      expect(part.features, hasLength(1));
      final feature = part.features.single as ExtrudeFeature;
      expect(feature.distanceA, 10);
      expect(feature.profiles, hasLength(1));
      expect(feature.solid, isNotNull);
      // The sketch is consumed by the feature that used it, exactly as it is
      // when a person draws one.
      expect(part.childSketches.single.visible, isFalse);
      // And it is not born below the End of Part marker.
      expect(feature.rolledBack, isFalse);
    });

    test('the report carries measured facts, not the arguments', () async {
      final app = await emptyPart();
      final report = await AiCad(app).run(makeBlock(distance: 7));
      final extrude = report.outcomes.last;
      expect(extrude.ok, isTrue);
      expect(extrude.detail!['feature'], 'Extrusion1');
      expect(extrude.detail!['volumeMm3'], 7); // the stub's build, not the ask
      // M451 — the state that rides on a block is the SHORT one: the whole
      // timeline used to ride on every block and then be resent on every
      // later round, six copies deep. What it must still carry is enough to
      // know something changed and how big the part now is.
      final state = report.state!;
      expect(state['newest'], 'Extrusion1 (extrude)');
      expect(state['features'], 1);
      expect(state['bodies'], ['Solid1']);

      // The timeline itself is one op away, and is current when it arrives.
      final read =
          await AiCad(app).run([const AiAction('describe_part', {})]);
      final part = read.outcomes.single.detail!['part'] as Map<String, dynamic>;
      expect((part['features'] as List).single['distance'], 7);
      expect(part['units'], {'length': 'mm', 'angle': 'deg'});
    });

    test('a failure before any feature built rolls the whole block back',
        () async {
      final app = await emptyPart();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_rect', {'width': 10, 'height': 10}),
        const AiAction('extrude', {'distance': -5}),
      ]);
      expect(report.reverted, isTrue);
      expect(report.kept, 0);
      expect(report.ok, isFalse);
      expect(report.outcomes.last.error, contains('distance'));
      // Nothing of the block survives — not the sketch drawn for the step
      // that failed.
      final part = app.currentPart!;
      expect(part.features, isEmpty);
      expect(part.childSketches, isEmpty);
    });

    // #83 — a block no longer fails as a whole. What built before the failure
    // stays, so the model does not spend a round trip rebuilding it; what the
    // failed step drew goes. The report says exactly where the line is.
    test('a failure after a feature keeps the feature and says so', () async {
      final app = await emptyPart();
      final report = await AiCad(app).run([
        ...makeBlock(),
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('extrude', {'distance': -5}),
      ]);
      expect(report.reverted, isTrue);
      expect(report.partial, isTrue);
      expect(report.kept, makeBlock().length);
      expect(report.ok, isFalse);
      final part = app.currentPart!;
      expect(part.features, hasLength(1));
      expect(part.childSketches, hasLength(1),
          reason: 'the sketch opened for the failed step is rolled back');
      expect(report.toJson()['note'], contains('stay there'));
      // And one undo still takes the whole block back.
      await app.undoPart();
      expect(app.currentPart!.features, isEmpty);
    });

    test('a successful block is one undo step', () async {
      final app = await emptyPart();
      await AiCad(app).run(makeBlock());
      expect(app.currentPart!.features, hasLength(1));
      expect(app.canUndoPart, isTrue);
      await app.undoPart();
      expect(app.currentPart!.features, isEmpty);
      expect(app.currentPart!.childSketches, isEmpty);
    });

    test('an extrude with no closed profile says so and changes nothing',
        () async {
      final app = await emptyPart();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction('sketch_line', {'x1': 0, 'y1': 0, 'x2': 10, 'y2': 0}),
        const AiAction('extrude', {'distance': 5}),
      ]);
      expect(report.reverted, isTrue);
      expect(report.outcomes.last.error, contains('closed profile'));
      expect(app.currentPart!.childSketches, isEmpty);
    });

    test('editing a feature changes it and rebuilds', () async {
      final app = await emptyPart();
      await AiCad(app).run(makeBlock());
      final report = await AiCad(app).run([
        const AiAction('edit_feature', {'feature': 'Extrusion1', 'distance': 25})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final feature = app.currentPart!.features.single as ExtrudeFeature;
      expect(feature.distanceA, 25);
      expect(feature.extent, FeatureExtent.distance);
      expect(report.outcomes.single.detail!['changed'], {'distance': 25.0});
    });

    test('editing a feature that is not there names the ones that are',
        () async {
      final app = await emptyPart();
      await AiCad(app).run(makeBlock());
      final report = await AiCad(app).run([
        const AiAction('edit_feature', {'feature': 'Boss3', 'distance': 4})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('Extrusion1'));
    });

    test('rename and delete reach the timeline', () async {
      final app = await emptyPart();
      await AiCad(app).run(makeBlock());
      final renamed = await AiCad(app).run([
        const AiAction(
            'rename_feature', {'feature': 'Extrusion1', 'name': 'Base plate'})
      ]);
      expect(renamed.ok, isTrue);
      expect(app.currentPart!.features.single.name, 'Base plate');
      final deleted = await AiCad(app).run(
          [const AiAction('delete_feature', {'feature': 'Base plate'})]);
      expect(deleted.ok, isTrue);
      expect(app.currentPart!.features, isEmpty);
      // ONE undo entry for the delete, not the executor's plus the app's.
      await app.undoPart();
      expect(app.currentPart!.features, hasLength(1));
    });

    test('a fillet selects live edges geometrically', () async {
      final app = await emptyPart();
      await AiCad(app).run(makeBlock());
      final report = await AiCad(app).run(
          [const AiAction('fillet', {'radius': 2, 'edges': 'all'})]);
      expect(report.ok, isTrue, reason: report.encode());
      final fillet = app.currentPart!.features.last as FilletFeature;
      expect(fillet.edges, hasLength(2));
      expect(fillet.radii, everyElement(2.0));
      expect((app.partKernel as _StubKernel).fillets, greaterThan(0));
    });

    test('a near point that matches nothing selects nothing', () async {
      final app = await emptyPart();
      await AiCad(app).run(makeBlock());
      final report = await AiCad(app).run([
        const AiAction('fillet', {
          'radius': 2,
          'near': [
            [900, 900, 900]
          ]
        })
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('matched'));
    });

    test('describe_part reads without changing anything', () async {
      final app = await emptyPart();
      await AiCad(app).run(makeBlock());
      final before = app.currentPart!.features.single.name;
      final report =
          await AiCad(app).run([const AiAction('describe_part', {})]);
      expect(report.ok, isTrue);
      final part = report.outcomes.single.detail!['part'] as Map;
      expect((part['features'] as List).single['name'], before);
      expect(part['coverage'], contains('No strength'));
      // A read alone must not enter the undo journal.
      expect(app.canUndoPart, isTrue); // from the block above, not from this
      await app.undoPart();
      expect(app.currentPart!.features, isEmpty);
    });

    test('with no part open, nothing is attempted', () async {
      final app = AppState()..partKernel = _StubKernel();
      apps.add(app);
      final report = await AiCad(app).run(makeBlock());
      expect(report.blocked, 'noPart');
      expect(report.outcomes, isEmpty);
    });
  });

  group('the loop', () {
    test('a block is executed and its result goes back before the answer',
        () async {
      final backend = _ScriptedBackend([
        'Building the plate.\n```cad\n'
        '{"actions":[{"op":"describe_part"}]}\n```',
        'The part is empty, so I started from scratch.',
      ]);
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      const document =
          AiDocument(id: 'doc', name: 'Bracket', kind: 'part');
      controller
        ..contextReader = ((id) async => {'id': id, 'name': 'Bracket'})
        ..updateWorkspace(current: document, documents: const [document]);
      final ran = <List<AiAction>>[];
      controller.actionRunner = (batch, {onStep}) async {
        ran.add(batch);
        return AiActionReport(outcomes: [
          const AiActionOutcome('describe_part', detail: {'featureCount': 0})
        ]);
      };
      controller.updateDraft('Make me a plate');
      await controller.send();

      expect(ran, hasLength(1));
      expect(ran.single.single.op, 'describe_part');
      final roles = controller.currentSession.messages.map((m) => m.role);
      // After a block that only READ, a prose reply is asked once whether it
      // is the end (the AI lab's tapered cup: measured, "I'll fix the
      // height", stopped) — so the model gets one more chance to build.
      expect(roles, ['user', 'assistant', 'tool', 'assistant', 'tool', 'assistant']);
      // The SECOND request must carry the report: a model that answers before
      // seeing what happened is guessing.
      expect(backend.requests, hasLength(3));
      expect(backend.requests[1].messages.map((m) => m.role),
          contains('tool'));
      expect(backend.requests[1].messages.last.text, contains('featureCount'));
      expect(controller.currentSession.messages.last.text,
          contains('from scratch'));
    });

    test('a session that cannot edit is never told that it can', () async {
      final backend = _ScriptedBackend(['Here is what I would change.']);
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      const document = AiDocument(id: 'doc', name: 'Bracket', kind: 'part');
      controller
        ..contextReader = ((id) async => {'id': id, 'name': 'Bracket'})
        ..updateWorkspace(current: document, documents: const [document]);
      controller.updateDraft('Make the plate 3 mm thicker');
      await controller.send();
      expect(controller.canEditModel, isFalse);
      final sent = backend.requests.first;
      expect(sent.instructions, contains('cannot create, edit'));
      expect(sent.instructions, isNot(contains('```cad')));
      expect(jsonDecode(sent.context)['cadEditsAvailable'], isFalse);
    });

    test('with a runner attached the protocol is in the instructions',
        () async {
      final backend = _ScriptedBackend(['Done.']);
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      const document = AiDocument(id: 'doc', name: 'Bracket', kind: 'part');
      controller
        ..contextReader = ((id) async => {'id': id, 'name': 'Bracket'})
        ..updateWorkspace(current: document, documents: const [document])
        ..actionRunner =
            ((batch, {onStep}) async => AiActionReport(outcomes: const []));
      controller.updateDraft('Make a plate');
      await controller.send();
      final sent = backend.requests.first;
      expect(sent.instructions, contains('```cad'));
      expect(sent.instructions, isNot(contains('cannot create, edit')));
      expect(jsonDecode(sent.context)['cadEditsAvailable'], isTrue);
    });

    test('a model that only emits blocks is stopped, not looped forever',
        () async {
      final backend = _ScriptedBackend.repeating(
          'Working.\n```cad\n{"actions":[{"op":"describe_part"}]}\n```');
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      const document = AiDocument(id: 'doc', name: 'Bracket', kind: 'part');
      controller
        ..contextReader = ((id) async => {'id': id, 'name': 'Bracket'})
        ..updateWorkspace(current: document, documents: const [document])
        ..actionRunner = ((batch, {onStep}) async =>
            AiActionReport(outcomes: const [AiActionOutcome('describe_part')]));
      controller.updateDraft('Go');
      await controller.send();
      expect(backend.requests.length, kAiMaxActionRounds + 1);
      // The last round is asked WITHOUT the protocol, so the model has to
      // answer in words instead of emitting a block nobody will run.
      expect(backend.requests.last.instructions, isNot(contains('```cad')));
    });
  });
}

/// Replies in order; the last one repeats if the loop asks again.
class _ScriptedBackend implements AiBackend {
  _ScriptedBackend(this.replies) : _repeat = false;
  _ScriptedBackend.repeating(String reply)
      : replies = [reply],
        _repeat = true;
  final List<String> replies;
  final bool _repeat;
  final requests = <AiRequest>[];

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    // The request holds live references to the controller's list; the loop
    // appends to it between rounds, so keep a frozen copy of this round.
    requests.add(AiRequest(
        id: request.id,
        instructions: request.instructions,
        context: request.context,
        messages: request.messages.toList()));
    final i = requests.length - 1;
    final text = _repeat
        ? replies.first
        : replies[i < replies.length ? i : replies.length - 1];
    return AiReply(text, 'test');
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
