// Issue #89 — "das ergebniss ist komplett falsch und kapput".
//
// "Make this lamp 1 mm sheet metal, open at the bottom." Fifteen requests,
// 44 000 reasoning tokens, one round of 43 000 characters, and a result with
// its +X wall cut away. The model had a picture on nine of the requests. What
// it did not have was any way to connect the picture to the things it acts
// on, and the text beside the picture was the save format:
//
//   - A VIEW WITH NO NAMES. Every op names a face "F12"; the picture named
//     nothing, so the model took face ids from centroids and normals and did
//     the geometry in its head ("F6 at y=334 pointing down with area 3100 —
//     that's odd").
//   - A TIMELINE IN THE SAVE FORMAT. Frames as twelve numbers, profile
//     centroids in sketch space, and on a to-face extrusion the stale
//     distance `a: 5.0` ("a=5.0 and exprA says 5mm. Confusing").
//   - TWO BOXES. Every block's report measured the mesh, describe_shape the
//     B-Rep, describe_part the mesh plus sketch curves; they disagreed by
//     200 mm and the report told it to centre features on the wrong one.
//
// Each group below pins one of those, on the paths the app actually uses.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_view_marks.dart';
import 'package:prototype/ai/ai_workspace.dart';
import 'package:prototype/ai/part_story.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';

import 'support/shape_fixtures.dart';

const _deg = math.pi / 180;

/// [m] moved by (x, y, z), its face ids shifted by [faceBase] so two boxes in
/// one mesh keep distinct faces.
OcctMeshData _moved(OcctMeshData m, double x, double y, double z,
    {int faceBase = 0}) {
  final p = Float64List.fromList(m.positions);
  for (var i = 0; i < p.length; i += 3) {
    p[i] += x;
    p[i + 1] += y;
    p[i + 2] += z;
  }
  final info = Float64List.fromList(m.faceInfos);
  for (var f = 0; f * 15 < info.length; f++) {
    info[f * 15 + 1] += x;
    info[f * 15 + 2] += y;
    info[f * 15 + 3] += z;
  }
  return OcctMeshData(p, m.normals, m.indices, m.edgeStarts, m.edgePoints,
      triFaces: Int32List.fromList([for (final t in m.triFaces) t + faceBase]),
      faceInfos: info);
}

OcctMeshData _merged(List<OcctMeshData> parts) {
  final pos = <double>[], nor = <double>[], idx = <int>[], tri = <int>[];
  final info = <double>[];
  for (final m in parts) {
    final base = pos.length ~/ 3;
    pos.addAll(m.positions);
    nor.addAll(m.normals);
    idx.addAll([for (final i in m.indices) i + base]);
    tri.addAll(m.triFaces);
    info.addAll(m.faceInfos);
  }
  return OcctMeshData(Float64List.fromList(pos), Float64List.fromList(nor),
      Int32List.fromList(idx), Int32List.fromList([0]), Float64List(0),
      triFaces: Int32List.fromList(tri), faceInfos: Float64List.fromList(info));
}

Cam3 _cam(OcctMeshData m, double azDeg, double polDeg,
    [Size size = const Size(512, 512)]) {
  final cam = fitViewCamera([KernelSolid(m, 1, null)], size,
      az: azDeg * _deg, pol: polDeg.clamp(0.06, 179.94) * _deg);
  return Cam3(cam, size);
}

Future<Uint8List> _blankPng(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF));
  final img = await rec.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bytes!.buffer.asUint8List();
}

Future<(int, int, Uint8List)> _rgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final out = (img.width, img.height, data!.buffer.asUint8List());
  img.dispose();
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apps = <AppState>[];
  tearDown(apps.clear);

  Future<AppState> partWithBox() async {
    final app = AppState()..partKernel = BoxKernel();
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_i89_');
    apps.add(app);
    await app.createNamedPart('Lamp');
    final report = await AiCad(app).run([
      const AiAction('create_sketch', {'plane': 'xy'}),
      const AiAction(
          'sketch_rect', {'x': 0, 'y': 0, 'width': 60, 'height': 40}),
      const AiAction('extrude', {'distance': 10}),
    ]);
    expect(report.ok, isTrue, reason: report.encode());
    return app;
  }

  group('every face the picture shows carries the id the ops take', () {
    test('the gallery corner names the three faces turned toward the eye', () {
      // boxMesh faces: 0 -Z, 1 +Z, 2 -Y, 3 +Y, 4 -X, 5 +X.
      final m = boxMesh(40, 336, 310);
      final marks = faceMarks(m, _cam(m, 45, 55));
      expect({for (final k in marks) k.text}, {'F5 +X', 'F3 +Y', 'F1 +Z'});
    });

    test(
        'from below, only the underside — the view the model used to check '
        '"is the bottom open" and got a grey bar', () {
      final m = boxMesh(50, 336, 310);
      final marks = faceMarks(m, _cam(m, 0, 180));
      expect([for (final k in marks) k.text], ['F2 -Y']);
    });

    test('a face hidden behind another gets no label', () {
      // A plate facing +Z with a smaller block behind it. Seen from +Z the
      // block's own +Z face is covered by the plate.
      final plate = boxMesh(100, 100, 10);
      final block = _moved(boxMesh(20, 20, 20), 40, 40, -30, faceBase: 6);
      final m = _merged([plate, block]);
      final marks = faceMarks(m, _cam(m, 0, 90));
      expect([for (final k in marks) k.face], [1]);
    });

    test('a face behind ANOTHER body is not labelled either', () {
      // Face ids are per body, so only one body is labelled; the others
      // still stand in front of it.
      final plate = boxMesh(100, 100, 10);
      final block = _moved(boxMesh(20, 20, 20), 40, 40, -30);
      final cam = _cam(_merged([plate, block]), 0, 90);
      expect(faceMarks(block, cam), isNotEmpty);
      expect(faceMarks(block, cam, occluders: [plate]), isEmpty);
    });

    test('a label sits on its own face, in the middle of a strip', () {
      // A long bar seen from below: the underside is a strip, and every cell
      // along its middle is equally far from its sides. The label goes at
      // the middle of the strip, not at whichever end was scanned first.
      final m = boxMesh(20, 20, 300);
      final cam = _cam(m, 0, 180);
      final mark = faceMarks(m, cam).single;
      final centre = cam.project(const Vec3(10, 0, 150));
      expect((mark.at - centre).distance, lessThan(cam.size.height * 0.08));
    });

    test('a round face says its diameter', () {
      final m = ringMesh(30, 10, 8);
      final texts = [for (final k in faceMarks(m, _cam(m, 0, 90))) k.text];
      expect(texts, contains('F1 Ø60'));
    });

    test('the labels are drawn onto the picture at its own scale', () async {
      final m = boxMesh(40, 336, 310);
      final cam = _cam(m, 45, 55);
      final marks = faceMarks(m, cam);
      // The native renderer draws at the device scale: 880 px for a 512
      // view on the reporter's iPad.
      final plain = await _blankPng(880, 880);
      final drawn = await drawFaceMarks(plain, cam, marks);
      expect(drawn, isNotNull);
      final (w, h, px) = await _rgba(drawn!);
      expect((w, h), (880, 880));
      // Something is drawn under each label.
      final k = 880 / 512;
      for (final mark in marks) {
        final i = ((mark.at.dy * k).round() * w + (mark.at.dx * k).round()) * 4;
        expect(px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255, isFalse,
            reason: '${mark.text} left the picture blank where it sits');
      }
    });

    test(
        'a picture of other proportions is left unlabelled rather than '
        'labelled through the wrong mapping', () async {
      final m = boxMesh(40, 40, 40);
      final cam = _cam(m, 45, 55);
      final wide = await _blankPng(900, 500);
      expect(await drawFaceMarks(wide, cam, faceMarks(m, cam)), isNull);
    });

    test(
        'look says which faces it shows, who made them, and how to use '
        'the labels', () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([
        const AiAction('look', {'az': 45, 'pol': 55})
      ]);
      final d = report.outcomes.single.detail!;
      expect(d['facesInView'], contains('+Y (Extrusion1)'));
      expect(d['note'], contains('face ids'));
      expect(report.images, isNotEmpty);
    });

    test('the view after a block that changed the part names its faces too',
        () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction(
            'sketch_rect', {'x': 0, 'y': 0, 'width': 10, 'height': 10}),
        const AiAction('extrude', {'distance': 5, 'operation': 'join'}),
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.state!['facesInView'], contains('F'));
      expect(report.state!['viewNote'], contains('yellow labels'));
    });
  });

  group('a face row says where the face is and what made it', () {
    test('faces_where answers with the span and the feature', () async {
      final app = await partWithBox();
      final report = await AiCad(app).run([
        const AiAction('faces_where', {'where': 'top'})
      ]);
      final row = (report.outcomes.single.detail!['faces'] as List).single
          as Map<String, dynamic>;
      expect(row['facing'], '+Y');
      expect(row['madeBy'], 'Extrusion1');
      // BoxKernel's box is 60 × 40 × height, so its top is y = 40.
      expect(row['spans'], 'x 0..60 · y=40 · z 0..10');
    });

    test('a span prints a flat axis as the plane it is', () {
      expect(faceSpan(const Vec3(0, 0, -310), const Vec3(0, 336, 0)),
          'x=0 · y 0..336 · z -310..0');
      expect(faceSpan(const Vec3(40, 2.5, -270), const Vec3(50, 334, -40)),
          'x 40..50 · y 2.5..334 · z -270..-40');
    });
  });

  group('the context tells the timeline in words', () {
    test('a part arrives as steps in world terms, not as its save format',
        () async {
      final app = await partWithBox();
      final workspace = AiWorkspace(app);
      addTearDown(workspace.dispose);
      final context = await workspace
          .readContext(AiWorkspace.identity(app.library['Lamp']!));
      final timeline = (context['timeline'] as List).cast<String>();
      expect(timeline, hasLength(2));
      expect(
          timeline[0],
          startsWith('Sketch1 — sketch on XY Plane, the plane z=0 · 1 entity, '
              '1 closed profile, drawn over x 0..60 · y 0..40 · z=0'));
      expect(
          timeline[1],
          startsWith('Extrusion1 — extrusion NEW body Solid1 from Sketch1, '
              '10 mm along +Z'));
      final raw = context['content'].toString();
      for (final noise in ['imate', 'cube', 'seqNext', 'faceRef', 'exprB']) {
        expect(raw, isNot(contains(noise)));
      }
    });

    test(
        'an extrusion up to a face says so, and not the distance it '
        'ignores', () async {
      final app = await partWithBox();
      final p = app.currentPart!;
      final f = p.features.single as ExtrudeFeature;
      // #89's Extrusion2: extent "to face" at z = 0, flipped, with the unused
      // default distance of 5 mm still stored.
      f.distanceA = 5;
      f.direction = ExtrudeDirection.flipped;
      f.extent = FeatureExtent.toFace;
      f.extentFace = FaceSel(0, 0, 0, 0, 0, 1);
      final line = partStory(p, profiles: (_) => 1)[1];
      expect(line, contains('up to the face at z=0, along -Z'));
      expect(line, isNot(contains('5 mm')));
    });
  });

  group('one bounding box in every report', () {
    test('describe_part measures the material, not the sketches beside it',
        () async {
      final app = await partWithBox();
      // A sketch drawn far off the body and never extruded. describe_part
      // used the viewport's box, which includes it, while describe_shape and
      // the block reports measured the body.
      final drew = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xy'}),
        const AiAction(
            'sketch_rect', {'x': 500, 'y': 500, 'width': 10, 'height': 10}),
      ]);
      expect(drew.ok, isTrue, reason: drew.encode());
      final report =
          await AiCad(app).run([const AiAction('describe_part', {})]);
      final box = (report.outcomes.single.detail!['part']
          as Map<String, dynamic>)['boundingBoxMm'] as Map<String, dynamic>;
      expect(box['max'], [60, 40, 10]);
    });
  });
}
