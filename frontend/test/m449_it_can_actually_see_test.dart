// M449 — issue #72: the part came out rotated, with no floor and rounds in
// the wrong places, and the assistant said it was finished.
//
// The user's read was exactly right, and each half of it is a separate,
// findable defect rather than a matter of the model trying harder.
//
//   IT COULD NOT SEE. `look` renders a PNG. Apple's on-device model and
//   DeepSeek's chat models cannot receive one, so on those providers the op
//   rendered a picture, dropped it, and told the model "you have NOT seen
//   it". Every time. The fix is a view made of characters, which every
//   provider can read.
//
//   IT WAS NEVER TOLD WHICH WAY IS UP. This app is Y-up; Fusion, SolidWorks
//   and Onshape are Z-up. Nothing in the prompt or the context said so, so a
//   base plate sketched on "xy" came out standing on its edge — and no number
//   in the digest contradicted it, because a bounding box does not say which
//   of its three numbers is the height.
//
//   IT COULD NOT TELL A HOLE FROM A POCKET. The through/blind test cast a ray
//   from the bore's MESH CENTROID, which lies on the bore wall, a million
//   millimetres away and tangent to the cylinder — then read the result
//   backwards. It printed "depth unknown" for the two holes that made the
//   shaker holder a plate with two ways to drop a shaker through it.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ai/ai_view.dart';
import 'package:prototype/ai/shape_digest.dart';

import 'support/shape_fixtures.dart';

const _deg = math.pi / 180;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apps = <AppState>[];
  tearDown(apps.clear);

  group('a view the model can read on any provider', () {
    test('a plate lying flat and the same plate on its edge do not look '
        'alike', () {
      // The bug, reduced: both have the numbers 140, 70 and 8. Only the
      // silhouette says which way up it is.
      final flat = renderTextView(
          boxMesh(140, 8, 70).positions, boxMesh(140, 8, 70).indices,
          azRad: 0, polRad: 90 * _deg)!;
      final onEdge = renderTextView(
          boxMesh(140, 70, 8).positions, boxMesh(140, 70, 8).indices,
          azRad: 0, polRad: 90 * _deg)!;
      expect(flat.widthMm, closeTo(140, 0.01));
      expect(flat.heightMm, closeTo(8, 0.01));
      expect(onEdge.widthMm, closeTo(140, 0.01));
      expect(onEdge.heightMm, closeTo(70, 0.01));
      expect(flat.art, isNot(onEdge.art));
    });

    test('it names the frame it was taken in', () {
      final m = boxMesh(40, 10, 20);
      final view = renderTextView(m.positions, m.indices,
          azRad: 0, polRad: 90 * _deg)!;
      final text = view.toText();
      expect(text, contains('screen right = +X'));
      expect(text, contains('screen up = +Y'));
      expect(text, contains('not a measurement'));
    });

    test('a bore you can see through reads as an opening', () {
      // Looking straight down the bore's own axis.
      final m = ringMesh(30, 10, 8);
      final view =
          renderTextView(m.positions, m.indices, azRad: 0, polRad: 0)!;
      expect(view.openings, 1, reason: view.art);
      expect(view.art, contains('o'));
      expect(view.toText(), contains('go right through the body'));
    });

    test('the same bore seen from the side is not an opening', () {
      final m = ringMesh(30, 10, 8);
      final view = renderTextView(m.positions, m.indices,
          azRad: 0, polRad: 90 * _deg)!;
      expect(view.openings, 0, reason: view.art);
    });

    test('it draws material, and the grid is bounded', () {
      final m = boxMesh(200, 200, 200);
      final view = renderTextView(m.positions, m.indices,
          azRad: 45 * _deg, polRad: 55 * _deg, cols: 999)!;
      expect(view.cols, lessThanOrEqualTo(kTextViewMaxCols));
      expect(view.rows, lessThanOrEqualTo(30));
      expect(view.cells.where((c) => c).length, greaterThan(view.cells.length ~/ 3));
      expect(view.islands, 1);
    });

    test('an empty mesh renders nothing rather than a blank frame', () {
      expect(renderTextView(boxMesh(1, 1, 1).positions,
              boxMesh(1, 1, 1).indices.sublist(0, 0),
              azRad: 0, polRad: 0),
          isNull);
    });
  });

  group('a bore is through or it has a floor — never "unknown"', () {
    // t is measured along the bore's own axis. The plate runs 0..8; the
    // material spans come from a ray cast along that axis.
    test('a hole with nothing beyond either end is through', () {
      final v = classifyBore(t0: 0, t1: 8, hits: const [], haveShape: true);
      expect(v.through, isTrue);
      expect(v.depth, 8);
    });

    test('a pocket with material behind its far end is blind', () {
      // The plate is solid from 0 to 3; the bore runs 3..8.
      final v =
          classifyBore(t0: 3, t1: 8, hits: const [0, 3], haveShape: true);
      expect(v.through, isFalse);
      expect(v.depth, 5);
    });

    test('a pocket entered from the other side is blind too', () {
      // Bore 0..5, material 5..8 behind it.
      final v =
          classifyBore(t0: 0, t1: 5, hits: const [5, 8], haveShape: true);
      expect(v.through, isFalse);
    });

    test('the depth is known even with no kernel to cast a ray with', () {
      final v = classifyBore(t0: 0, t1: 8, hits: const [], haveShape: false);
      expect(v.through, isNull);
      expect(v.depth, 8);
      // The old code called this "depth unknown" and told the model nothing.
    });

    test('an unpaired grazing crossing does not invent a span to infinity', () {
      expect(solidSpans(const [4.0]), isEmpty);
      expect(solidSpans(const [0.0, 3.0, 5.0]), hasLength(1));
      expect(insideSpans(solidSpans(const [0.0, 3.0]), 1.5, 1e-9), isTrue);
      expect(insideSpans(solidSpans(const [0.0, 3.0]), 4.0, 1e-9), isFalse);
    });
  });

  group('the digest says which way up the part is', () {
    test('the stance line names the height, not just three numbers', () {
      final d = computeShapeDigest(solidOf(boxMesh(140, 70, 8), 78400));
      final text = d.toText();
      expect(text, contains('stance up is +Y'));
      expect(text, contains('70.00 mm tall'));
      expect(text, contains('footprint 140.0 (X) × 8.00 (Z)'));
    });

    test('the same plate laid flat reports an 8 mm height', () {
      final d = computeShapeDigest(solidOf(boxMesh(140, 8, 70), 78400));
      expect(d.toText(), contains('8.00 mm tall'));
      expect(d.toText(), contains('footprint 140.0 (X) × 70.00 (Z)'));
    });

    test('a bore reports its length, and says it does not know the rest',
        () {
      final d = computeShapeDigest(solidOf(ringMesh(30, 10, 8), 20106));
      final text = d.toText();
      expect(text, contains('Ø20.00'));
      expect(text, contains('8.00 mm long'));
      // No kernel is linked to this fixture, and saying so is the honest
      // answer — as against the old "depth unknown", which read as "there is
      // nothing to know here".
      expect(text, contains('no kernel linked'));
      expect(text, isNot(contains('depth unknown')));
    });
  });

  group('a blend says what it actually rounded', () {
    Future<AppState> plate({List<double> rings = const []}) async {
      final app = AppState()..partKernel = BoxKernel(rings: rings);
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m449_');
      apps.add(app);
      await app.createNamedPart('Holder');
      final built = await AiCad(app).run([
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('sketch_rect', {'width': 140, 'height': 70}),
        const AiAction('extrude', {'distance': 8}),
      ]);
      expect(built.ok, isTrue, reason: built.encode());
      return app;
    }

    test('it names the circular edges, which are the mouths of the bores',
        () async {
      // The bug: `{"edges": "horizontal"}` caught ten edges, two of them the
      // Ø25 bore mouths, and the model was told only "edges: 10".
      final app = await plate(rings: const [12.5]);
      final report =
          await AiCad(app).run([const AiAction('fillet', {'radius': 2})]);
      expect(report.ok, isTrue, reason: report.encode());
      final rounded =
          report.outcomes.single.detail!['rounded'] as Map<String, dynamic>;
      expect(rounded['straight'], 2);
      expect(rounded['circular'], contains('1× Ø25.00'));
      expect(rounded['warning'], contains("that hole's"));
    });

    test('"outer" leaves the bore mouths alone', () async {
      final app = await plate(rings: const [12.5]);
      final report = await AiCad(app)
          .run([const AiAction('fillet', {'radius': 2, 'edges': 'outer'})]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      expect(d['edges'], 2);
      expect((d['rounded'] as Map)['circular'], isNull);
    });

    test('"holes" is only those mouths', () async {
      final app = await plate(rings: const [12.5, 12.5]);
      final report = await AiCad(app)
          .run([const AiAction('fillet', {'radius': 1, 'edges': 'holes'})]);
      expect(report.outcomes.single.detail!['edges'], 2);
      expect((report.outcomes.single.detail!['rounded'] as Map)['straight'],
          isNull);
    });

    test('a part with no circular edges says so by omission', () async {
      final app = await plate();
      final report =
          await AiCad(app).run([const AiAction('fillet', {'radius': 2})]);
      final rounded = report.outcomes.single.detail!['rounded'] as Map;
      expect(rounded['circular'], isNull);
      expect(rounded['warning'], isNull);
    });
  });

  group('the model is told which way is up', () {
    test('the action instructions state the frame and both consequences', () {
      expect(kAiActionInstructions, contains('THE WORLD FRAME'));
      expect(kAiActionInstructions, contains('Y-UP'));
      expect(kAiActionInstructions, contains('XZ is the GROUND plane'));
      expect(kAiActionInstructions, contains('standing on its edge'));
    });

    test('and told to check the stance and the holes before finishing', () {
      expect(kAiActionInstructions, contains('does it say THROUGH?'));
      expect(kAiActionInstructions, contains('needs a FLOOR'));
      expect(kAiActionInstructions, contains('is that bore\'s MOUTH'));
    });
  });
}
