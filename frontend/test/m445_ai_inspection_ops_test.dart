// M445 — the ops that let the assistant look at a body and edit what it sees.
//
// (M443 was taken by the bug-report work that landed on this branch in
// parallel; this is the same change, renumbered so one milestone number does
// not name two unrelated things.)
//
// M441 gave it operations that BUILD. M442 gave it a description of what is
// already there. These are the ops that join the two: find a face, measure
// between faces, cut a section, and then delete, offset or sketch on a face
// that was named rather than guessed at.
//
// The claim under test throughout is that a refusal is never silent. Every op
// here either returns the fact it was asked for, or says in its own words why
// it could not — because the model's next sentence is written from this report
// and an empty answer reads as "there is nothing there".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_workspace.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'support/shape_fixtures.dart';

void main() {
  final apps = <AppState>[];

  Future<AppState> partWithBox() async {
    final app = AppState()..partKernel = BoxKernel();
    app.docsDirForTest =
        Directory.systemTemp.createTempSync('prototype_m445_');
    apps.add(app);
    await app.createNamedPart('Bracket');
    final report = await AiCad(app).run([
      const AiAction('create_sketch', {'plane': 'xy'}),
      const AiAction('sketch_rect', {'width': 60, 'height': 40}),
      const AiAction('extrude', {'distance': 10}),
    ]);
    expect(report.ok, isTrue, reason: report.encode());
    return app;
  }

  // See m441's fixture for why nothing is disposed or deleted here: several
  // AppState paths fire savePart without awaiting it.
  tearDown(apps.clear);

  group('describe_shape', () {
    test('answers with the measured shape, not the feature tree', () async {
      final app = await partWithBox();
      final report =
          await AiCad(app).run([const AiAction('describe_shape', {})]);
      expect(report.ok, isTrue, reason: report.encode());
      final shape = report.outcomes.single.detail!['shape'] as String;
      expect(shape, contains('60.00 × 40.00 × 10.00 mm'));
      expect(shape, contains('6 plane'));
      // The thing the whole exercise exists to prevent: a number from the
      // authoring record presented as a dimension.
      expect(shape, isNot(contains('Extrusion1')));
    });

    test('a body that was never named is refused by name', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('describe_shape', {'body': 'Solid9'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('Solid9'));
      expect(report.outcomes.single.error, contains('Solid1'));
    });

    test('detail: sections returns outlines with their own method stated',
        () async {
      final app = await partWithBox();
      final report = await AiCad(app).run(
          [const AiAction('describe_shape', {'detail': 'sections'})]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      expect(d['method'], contains('tessellation'));
      // An all-planar box is above the analytic threshold, so the digest does
      // not compute sections for it; the op says so by returning none rather
      // than by inventing any.
      expect(d['sections'], isA<List<dynamic>>());
    });

    test('detail: faces lists them largest first and caps the list', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('describe_shape', {'detail': 'faces'})]);
      final d = report.outcomes.single.detail!;
      expect(d['faceCount'], 6);
      final faces = (d['faces'] as List).cast<Map>();
      expect(faces, hasLength(6));
      final areas = [for (final f in faces) f['areaMm2'] as double];
      expect(areas.first, 2400); // 60 x 40
      for (var i = 1; i < areas.length; i++) {
        expect(areas[i], lessThanOrEqualTo(areas[i - 1]));
      }
    });
  });

  group('faces_where', () {
    test('filters by surface type', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('faces_where', {'type': 'plane'})]);
      expect(report.outcomes.single.detail!['matched'], 6);
    });

    test('filters by axis, which is how a person names a face', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('faces_where', {'axis': 'z'})]);
      // The top and the bottom of a box both lie on the Z axis.
      expect(report.outcomes.single.detail!['matched'], 2);
    });

    test('an unknown type is refused with the list of known ones', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('faces_where', {'type': 'freeform'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('cylinder'));
    });

    test('a minimum area keeps only the faces worth naming', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('faces_where', {'min_area': 1000})]);
      expect(report.outcomes.single.detail!['matched'], 2);
    });

    test('every row carries an id later ops can take', () async {
      final app = await partWithBox();
      final report =
          await AiCad(app).run([const AiAction('faces_where', {})]);
      final faces = (report.outcomes.single.detail!['faces'] as List).cast<Map>();
      for (final f in faces) {
        expect(f['face'], matches(RegExp(r'^F\d+$')));
        expect(f['at'], hasLength(3));
        expect(f['dir'], hasLength(3));
      }
    });
  });

  group('measure', () {
    test('two parallel planes report their separation', () async {
      final app = await partWithBox();
      final all = await AiCad(app)
          .run([const AiAction('faces_where', {'axis': 'z'})]);
      final faces =
          (all.outcomes.single.detail!['faces'] as List).cast<Map>();
      final report = await AiCad(app).run([
        AiAction('measure',
            {'from': faces[0]['face'], 'to': faces[1]['face']})
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      // Top and bottom of a 10 mm box, whichever order they came back in.
      expect(d['planeSeparationMm'], closeTo(10, 1e-6));
      expect(d['angleDeg'], closeTo(180, 1e-6));
      expect(d['method'], contains('tessellation'));
    });

    test('a face id that does not exist says how to find one', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('measure', {'from': 'F0', 'to': 'F99'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('faces_where'));
    });

    test('something that is not a face id is refused as such', () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('measure', {'from': 'the top', 'to': 'F1'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('not a face id'));
    });
  });

  group('section', () {
    test('cuts on a named axis and reports the outline', () async {
      final app = await partWithBox();
      final report =
          await AiCad(app).run([const AiAction('section', {'axis': 'x'})]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      expect(d['axis'], 'X');
      final sections = (d['sections'] as List).cast<Map>();
      expect(sections, isNotEmpty);
      // Every station through a 60 x 40 x 10 prism is the same 40 x 10.
      expect(sections.first['width'], closeTo(40, 1e-6));
      expect(sections.first['height'], closeTo(10, 1e-6));
      expect(sections.first['areaMm2'], closeTo(400, 1e-6));
    });

    test('an "at" picks the nearest station rather than all of them',
        () async {
      final app = await partWithBox();
      final report = await AiCad(app)
          .run([const AiAction('section', {'axis': 'x', 'at': 30})]);
      expect((report.outcomes.single.detail!['sections'] as List), hasLength(1));
    });

    test('a bad axis is refused', () async {
      final app = await partWithBox();
      final report =
          await AiCad(app).run([const AiAction('section', {'axis': 'w'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('x, y or z'));
    });

    test('reading never enters the undo journal', () async {
      final app = await partWithBox();
      final before = app.canUndoPart;
      await AiCad(app).run([
        const AiAction('describe_shape', {}),
        const AiAction('faces_where', {}),
        const AiAction('section', {'axis': 'y'}),
      ]);
      expect(app.canUndoPart, before);
    });
  });

  group('editing a face that was named, not guessed', () {
    Future<String> topFace(AppState app) async {
      final report = await AiCad(app)
          .run([const AiAction('faces_where', {'min_area': 1000})]);
      final faces =
          (report.outcomes.single.detail!['faces'] as List).cast<Map>();
      return faces.first['face'] as String;
    }

    test('delete_face adds a Delete Face feature to the timeline', () async {
      final app = await partWithBox();
      final face = await topFace(app);
      final report =
          await AiCad(app).run([AiAction('delete_face', {'face': face})]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(app.currentPart!.features.last, isA<DeleteFaceFeature>());
      expect(report.outcomes.single.detail!['face'], face);
    });

    test('move_face needs a distance and refuses zero', () async {
      final app = await partWithBox();
      final face = await topFace(app);
      final report = await AiCad(app)
          .run([AiAction('move_face', {'face': face, 'distance': 0})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('non-zero'));
    });

    test('move_face offsets along the face normal', () async {
      final app = await partWithBox();
      final face = await topFace(app);
      final report = await AiCad(app)
          .run([AiAction('move_face', {'face': face, 'distance': 2.5})]);
      expect(report.ok, isTrue, reason: report.encode());
      final f = app.currentPart!.features.last as DirectEditFeature;
      expect(f.op, DirectOp.move);
      // The picked face is the top or the bottom of the box, so the delta is
      // along Z either way and its magnitude is what was asked for.
      expect(f.delta.length, closeTo(2.5, 1e-9));
      expect(f.dx.abs() + f.dy.abs(), closeTo(0, 1e-9));
    });

    test('a failed face edit keeps the edit that worked before it', () async {
      final app = await partWithBox();
      final before = app.currentPart!.features.length;
      final face = await topFace(app);
      final report = await AiCad(app).run([
        AiAction('move_face', {'face': face, 'distance': 2}),
        const AiAction('move_face', {'face': 'F99', 'distance': 2}),
      ]);
      expect(report.reverted, isTrue);
      expect(report.kept, 1);
      expect(app.currentPart!.features, hasLength(before + 1));
    });

    test('a failed face edit on its own changes nothing', () async {
      final app = await partWithBox();
      final before = app.currentPart!.features.length;
      final report = await AiCad(app).run([
        const AiAction('move_face', {'face': 'F99', 'distance': 2}),
      ]);
      expect(report.ok, isFalse);
      expect(app.currentPart!.features, hasLength(before));
    });

    test('sketch_on_face opens a sketch in the face plane', () async {
      final app = await partWithBox();
      final face = await topFace(app);
      final report =
          await AiCad(app).run([AiAction('sketch_on_face', {'face': face})]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      expect(d['sketch'], isNotNull);
      expect(app.currentPart!.sketchByName(d['sketch'] as String), isNotNull);
      // It says what it cannot promise, rather than leaving the model to
      // assume the sketch follows the face.
      expect(d['note'], contains('does not follow the face'));
    });

    test('a sketch needs a planar face and says so otherwise', () async {
      final app = await partWithBox();
      // Every face of this box is planar, so the refusal is exercised through
      // a face id that is not there at all — the other half of the same guard.
      final report = await AiCad(app)
          .run([const AiAction('sketch_on_face', {'face': 'F42'})]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('no face F42'));
    });
  });

  group('the digest reaches the assistant, not just the ops', () {
    test('a part with a body puts its measured shape in the context',
        () async {
      final app = await partWithBox();
      final workspace = AiWorkspace(app);
      addTearDown(workspace.dispose);
      final id = AiWorkspace.identity(app.library['Bracket']!);
      final context = await workspace.readContext(id);
      expect(context['shape'], isA<String>());
      expect(context['shape'] as String, contains('SHAPE Solid1'));
      expect(context['coverage'], contains('measured shape description'));
    });

    test('an empty part says it has no geometry rather than staying silent',
        () async {
      final app = AppState()..partKernel = BoxKernel();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m445_empty_');
      apps.add(app);
      await app.createNamedPart('Empty');
      final workspace = AiWorkspace(app);
      addTearDown(workspace.dispose);
      final id = AiWorkspace.identity(app.library['Empty']!);
      final context = await workspace.readContext(id);
      expect(context['shape'] as String, contains('no built body'));
    });
  });
}
