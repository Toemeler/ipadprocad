// M455 — issues #73 to #81: the sketcher could not draw a curve, and every
// refusal was a dead end.
//
// The op set stopped at rectangle, circle, polygon and line. Across the nine
// reported sessions the model reached for sketch_polygon 34 times — every one
// of them a curve it had no way to draw. That is the "handle which looks like
// circles but isn't really" (#73), it is why the 3D fillet on that handle then
// failed (there is no circular edge to blend, only a fan of facets), and it is
// why the cable holder came out as a closed Ø8 hole in a plate with no way to
// get a cable into it (#80).
//
// The other half is recovery. A fillet that was refused said "no radius in
// this size range builds" and stopped; an empty edge selection said "no edge
// matched" and stopped; a top view said "pol must be between 0 and 180" and
// stopped; a dropped connection ended the turn outright (#81). Each of those
// cost a round trip, or the whole turn, for information the app already had.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';

import 'support/shape_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apps = <AppState>[];
  tearDown(apps.clear);

  Future<AppState> sketching() async {
    final app = AppState()..partKernel = BoxKernel();
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m455_');
    apps.add(app);
    await app.createNamedPart('Clip');
    final made = await AiCad(app).run([
      const AiAction('create_sketch', {'plane': 'xz'})
    ]);
    expect(made.ok, isTrue, reason: made.encode());
    return app;
  }

  List<Geo> geometryOf(AppState app) =>
      app.currentPart!.childSketches.last.model.geometry;

  group('the sketcher can draw a curve', () {
    test('an arc about a centre is a real arc, not facets', () async {
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_arc',
            {'x': 0, 'y': 0, 'radius': 10, 'start_deg': 0, 'end_deg': 180})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final g = geometryOf(app).single;
      expect(g.type, Geo.arc);
      expect(g.data[2], 10);
      expect(g.data[4] - g.data[3], closeTo(math.pi, 1e-9));
      expect(report.outcomes.single.detail!['sweepDeg'], 180);
    });

    test('an arc through three points finds its own centre', () async {
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_arc', {
          'x1': -5, 'y1': 0, 'x2': 0, 'y2': 5, 'x3': 5, 'y3': 0,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final g = geometryOf(app).single;
      expect(g.type, Geo.arc);
      expect(g.data[0], closeTo(0, 1e-9));
      expect(g.data[1], closeTo(0, 1e-9));
      expect(g.data[2], closeTo(5, 1e-9));
    });

    test('three collinear points are refused, not silently bent', () async {
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_arc',
            {'x1': 0, 'y1': 0, 'x2': 5, 'y2': 0, 'x3': 10, 'y3': 0})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('collinear'));
    });

    test('a slot is two sides and two true semicircles', () async {
      // The shape of a cable channel, and the one #80 could not draw.
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_slot',
            {'x1': -15, 'y1': 0, 'x2': 15, 'y2': 0, 'width': 8})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final g = geometryOf(app);
      expect(g, hasLength(4));
      expect(g.where((e) => e.type == Geo.line).length, 2);
      expect(g.where((e) => e.type == Geo.arc).length, 2);
      for (final arc in g.where((e) => e.type == Geo.arc)) {
        expect(arc.data[2], closeTo(4, 1e-9));
      }
      final d = report.outcomes.single.detail!;
      expect(d['lengthOverall'], 38);
      expect(d['width'], 8);
    });

    test('a slot closes into exactly one profile', () async {
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_slot',
            {'x1': 0, 'y1': 0, 'x2': 20, 'y2': 0, 'width': 6})
      ]);
      // If the four pieces did not meet, the extrude would have nothing.
      expect(report.outcomes.single.detail!['closedProfiles'], 1,
          reason: report.encode());
    });

    test('a slot whose ends coincide is refused with the right advice',
        () async {
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_slot',
            {'x1': 4, 'y1': 4, 'x2': 4, 'y2': 4, 'width': 6})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('sketch_circle'));
    });

    test('a rounded rectangle is arcs, not four later fillets', () async {
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_rounded_rect', {
          'width': 40, 'height': 20, 'radius': 4, 'centered': true,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final g = geometryOf(app);
      expect(g.where((e) => e.type == Geo.arc).length, 4);
      expect(g.where((e) => e.type == Geo.line).length, 4);
      expect(report.outcomes.single.detail!['closedProfiles'], 1);
    });

    test('a corner radius that cannot fit says what does', () async {
      final app = await sketching();
      final report = await AiCad(app).run([
        const AiAction('sketch_rounded_rect',
            {'width': 40, 'height': 20, 'radius': 15})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('10.00'));
    });

    test('the model is told not to fake a curve with a polygon', () {
      expect(kAiActionInstructions, contains('STRAIGHT SEGMENTS ONLY'));
      expect(kAiActionInstructions, contains('sketch_slot'));
      expect(kAiActionInstructions, contains('DRAW THE PROFILE PROPERLY'));
    });
  });

  group('a view from straight above is a view, not an error', () {
    Future<AppState> withBody() async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m455v_');
      apps.add(app);
      await app.createNamedPart('Plate');
      final built = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 60, 'height': 40}),
        const AiAction('extrude', {'distance': 8}),
      ]);
      expect(built.ok, isTrue, reason: built.encode());
      return app;
    }

    test('pol 0 is nudged off the pole and says so', () async {
      final app = await withBody();
      final report = await AiCad(app).run([const AiAction('look', {'pol': 0})]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      expect(d['polDeg'], greaterThan(0));
      expect(d['polDeg'], lessThan(1));
      expect(d['polNote'], contains('along the up axis'));
    });

    test('pol 180 works too', () async {
      final app = await withBody();
      final report =
          await AiCad(app).run([const AiAction('look', {'pol': 180})]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['polDeg'], lessThan(180));
    });

    test('an ordinary angle is untouched and unremarked', () async {
      final app = await withBody();
      final report =
          await AiCad(app).run([const AiAction('look', {'pol': 55})]);
      expect(report.outcomes.single.detail!['polDeg'], 55);
      expect(report.outcomes.single.detail!.containsKey('polNote'), isFalse);
    });
  });

  group('a refused selection says what is there', () {
    test('an empty match names the edges and the selectors', () async {
      final app = AppState()..partKernel = BoxKernel(rings: const [5]);
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m455e_');
      apps.add(app);
      await app.createNamedPart('Plate');
      await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 60, 'height': 40}),
        const AiAction('extrude', {'distance': 8}),
      ]);
      final report = await AiCad(app).run([
        const AiAction('fillet', {'radius': 1, 'near': [[900, 900, 900]]})
      ]);
      expect(report.ok, isFalse);
      final error = report.outcomes.single.error!;
      expect(error, contains('3 live edges'));
      expect(error, contains('circular'));
      expect(error, contains('outer'));
    });
  });

  group('"on top" means the top face, and only the top face', () {
    test('a signed axis excludes the face pointing the other way', () async {
      // #74/#75: the hook went on the side and stayed there after being
      // corrected. Asking for "+y" used to return the top AND the bottom.
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m455t_');
      apps.add(app);
      await app.createNamedPart('Holder');
      await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 60, 'height': 40}),
        const AiAction('extrude', {'distance': 8}),
      ]);
      final both = await AiCad(app)
          .run([const AiAction('faces_where', {'axis': 'y'})]);
      final up = await AiCad(app)
          .run([const AiAction('faces_where', {'axis': '+y'})]);
      final down = await AiCad(app)
          .run([const AiAction('faces_where', {'axis': '-y'})]);
      expect(both.outcomes.single.detail!['matched'], 2);
      expect(up.outcomes.single.detail!['matched'], 1);
      expect(down.outcomes.single.detail!['matched'], 1);
    });

    test('"where: top" says it in the words the user used', () async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m455w_');
      apps.add(app);
      await app.createNamedPart('Holder');
      await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 60, 'height': 40}),
        const AiAction('extrude', {'distance': 8}),
      ]);
      final top = await AiCad(app)
          .run([const AiAction('faces_where', {'where': 'top'})]);
      expect(top.ok, isTrue, reason: top.encode());
      expect(top.outcomes.single.detail!['matched'], 1);
      final bad = await AiCad(app)
          .run([const AiAction('faces_where', {'where': 'sideways'})]);
      expect(bad.ok, isFalse);
      expect(bad.outcomes.single.error, contains('top, bottom'));
    });
  });

  group('a dropped connection does not end the turn', () {
    test('the request goes out again and the answer arrives', () async {
      final backend = _Flaky(failures: 2);
      const document = AiDocument(id: 'doc', name: 'Cup', kind: 'part');
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      controller
        ..contextReader = ((id) async => {'id': id})
        ..updateWorkspace(current: document, documents: const [document]);
      controller.updateDraft('Make a cup');
      await controller.send();
      expect(backend.calls, 3);
      expect(controller.error, isNull);
      expect(controller.currentSession.messages.last.text, 'Done.');
    });

    test('it gives up rather than retrying forever', () async {
      final backend = _Flaky(failures: 99);
      const document = AiDocument(id: 'doc', name: 'Cup', kind: 'part');
      final controller = AiController(backend: backend)..initializeInMemory();
      addTearDown(controller.dispose);
      controller
        ..contextReader = ((id) async => {'id': id})
        ..updateWorkspace(current: document, documents: const [document]);
      controller.updateDraft('Make a cup');
      await controller.send();
      expect(backend.calls, kAiMaxNetworkRetries + 1);
      expect(controller.error, const AiException('network').message);
      // And the draft comes back, so nothing the user typed is lost.
      expect(controller.currentSession.draft, 'Make a cup');
    });
  });

  group('the model is told to work with what is there', () {
    test('edit rather than delete and rebuild', () {
      expect(kAiActionInstructions, contains('WORK WITH WHAT IS THERE'));
      expect(kAiActionInstructions, contains('use edit_feature'));
    });

    test('put it where the user said, and check it works', () {
      expect(kAiActionInstructions, contains('BUILD IT WHERE THE USER SAID'));
      expect(kAiActionInstructions, contains('DOES THE THING ACTUALLY WORK'));
      expect(kAiActionInstructions, contains('nothing can get into it'));
    });

    test('and to be ambitious rather than safe', () {
      expect(kAiActionInstructions, contains('BE AMBITIOUS AND BE PATIENT'));
    });
  });
}

/// Fails with a network error [failures] times, then answers.
class _Flaky implements AiBackend {
  _Flaky({required this.failures});
  final int failures;
  int calls = 0;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider, label: 'Test', available: true);

  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    calls++;
    if (calls <= failures) throw const AiException('network');
    return const AiReply('Done.', 'test');
  }

  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<bool> hasKey(AiProvider provider) async => true;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}
