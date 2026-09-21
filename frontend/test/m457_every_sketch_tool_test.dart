// M457 — the assistant draws with the app's own 2D tools.
//
// The friendly ops (rect, circle, arc, slot, rounded rect, polygon, line,
// point) take the arguments a person would say out loud and cover most of
// what a model reaches for. They were also the ONLY thing it could reach, so
// an ellipse, a spline, a tangent arc, a regular hexagon, a chamfer between
// two lines or an involute gear were all out — and a model with no ellipse
// draws a polygon that looks like one.
//
// `sketch_tool` closes that by calling [buildToolGeometry], the app's single
// source of truth for what every 2D tool draws. The viewport preview and the
// commit path both call it, so the assistant now draws with the app's tools
// rather than with a re-implementation of them, and a tool added later is
// reachable without touching the AI layer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/tools.dart' show toolMeta;

import 'support/shape_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apps = <AppState>[];
  tearDown(apps.clear);

  Future<AppState> sketch([List<AiAction> then = const []]) async {
    final app = AppState()..partKernel = BoxKernel();
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m457_');
    apps.add(app);
    await app.createNamedPart('Draw');
    final made = await AiCad(app)
        .run([const AiAction('create_sketch', {'plane': 'xz'}), ...then]);
    expect(made.ok, isTrue, reason: made.encode());
    return app;
  }

  List<Geo> geometryOf(AppState app) =>
      app.currentPart!.childSketches.last.model.geometry;

  group('every drawing tool the app has is reachable', () {
    // One case per tool, with picks that actually describe the shape. This is
    // the list that makes "every single 2D tool" checkable rather than
    // asserted: if a tool is added to the app and not to the map, the
    // catalogue test below fails.
    const cases = <String, List<List<double>>>{
      'line': [[0, 0], [20, 0]],
      'line_midpoint': [[10, 0], [20, 0]],
      'spline': [[0, 0], [10, 10], [20, 0]],
      'spline_control': [[0, 0], [10, 10], [20, 0]],
      'bridge': [[0, 0], [20, 5]],
      'circle': [[0, 0], [10, 0]],
      'ellipse': [[0, 0], [20, 0], [0, 10]],
      'arc_3point': [[0, 0], [10, 10], [20, 0]],
      'arc_centre': [[0, 0], [10, 0], [0, 10]],
      'rect': [[0, 0], [40, 20]],
      'rect_3point': [[0, 0], [40, 0], [40, 20]],
      'rect_centre': [[0, 0], [20, 10]],
      'rect_centre_3point': [[0, 0], [20, 0], [20, 10]],
      'slot_centres': [[0, 0], [30, 0], [0, 5]],
      'slot_overall': [[0, 0], [30, 0], [0, 5]],
      'slot_centre_point': [[0, 0], [15, 0], [0, 5]],
      'slot_3arc': [[0, 0], [15, 10], [30, 0], [0, 5]],
      'polygon_regular': [[0, 0], [15, 0]],
      'point': [[5, 5]],
    };

    for (final entry in cases.entries) {
      test('${entry.key} draws', () async {
        final app = await sketch();
        final report = await AiCad(app).run([
          AiAction('sketch_tool',
              {'tool': entry.key, 'points': entry.value, 'sides': 6})
        ]);
        expect(report.ok, isTrue, reason: report.encode());
        expect(geometryOf(app), isNotEmpty);
        expect(report.outcomes.single.detail!['tool'], entry.key);
      });
    }

    test('a regular hexagon is six lines and its construction circle', () async {
      // The app's polygon tool, which sketch_polygon (a point list) is not.
      final app = await sketch();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool', {
          'tool': 'polygon_regular',
          'points': [[0, 0], [20, 0]],
          'sides': 6,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['entities'], 7);
      expect(report.outcomes.single.detail!['closedProfiles'], 1);
    });

    test('an ellipse is one entity and a closed profile', () async {
      final app = await sketch();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool',
            {'tool': 'ellipse', 'points': [[0, 0], [30, 0], [0, 12]]})
      ]);
      expect(report.outcomes.single.detail!['closedProfiles'], 1,
          reason: report.encode());
    });
  });

  group('the tools that need geometry already there', () {
    /// A square, so there are corners to fillet and chamfer.
    Future<AppState> square() => sketch([
          const AiAction('sketch_tool',
              {'tool': 'rect', 'points': [[0, 0], [40, 40]]})
        ]);

    test('a 2D fillet rounds a corner AND trims what it joins', () async {
      // The whole point: buildToolGeometry hands back only the arc, and an
      // arc laid on top of two untrimmed lines is not a rounded corner — the
      // region finder sees no closed profile at all.
      final app = await square();
      final before = geometryOf(app).length;
      final report = await AiCad(app).run([
        const AiAction('sketch_tool', {
          'tool': 'fillet',
          'points': [[20, 0], [40, 20]],
          'radius': 6,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      final d = report.outcomes.single.detail!;
      expect(d['added'], greaterThan(0));
      expect(d['trimmed'], 2, reason: 'both lines must be shortened');
      expect(d['closedProfiles'], 1, reason: 'it is still a closed shape');
      expect(geometryOf(app).length, greaterThan(before));
      expect(geometryOf(app).any((g) => g.type == Geo.arc), isTrue);
    });

    test('a 2D chamfer cuts the corner off', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool', {
          'tool': 'chamfer',
          'points': [[20, 0], [40, 20]],
          'distance': 5,
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(report.outcomes.single.detail!['trimmed'], 2);
      expect(report.outcomes.single.detail!['closedProfiles'], 1);
    });

    test('a fillet with nothing near the picks says what the picks mean',
        () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool', {
          'tool': 'fillet',
          'points': [[900, 900], [950, 950]],
          'radius': 4,
        })
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error,
          contains('pick the two entities'));
    });

    test('a zero radius is refused before the kernel sees it', () async {
      final app = await square();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool',
            {'tool': 'fillet', 'points': [[20, 0], [40, 20]], 'radius': 0})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('must be > 0'));
    });

    test('a circle tangent to three entities', () async {
      final app = await sketch([
        const AiAction('sketch_tool',
            {'tool': 'line', 'points': [[0, 0], [60, 0]]}),
        const AiAction('sketch_tool',
            {'tool': 'line', 'points': [[0, 0], [0, 60]]}),
        const AiAction('sketch_tool',
            {'tool': 'line', 'points': [[60, 0], [60, 60]]}),
      ]);
      final report = await AiCad(app).run([
        const AiAction('sketch_tool', {
          'tool': 'circle_tangent',
          'points': [[30, 1], [1, 30], [59, 30]],
        })
      ]);
      expect(report.ok, isTrue, reason: report.encode());
      expect(geometryOf(app).where((g) => g.type == Geo.circle).length, 1);
    });
  });

  group('refusals name what was available', () {
    test('an unknown tool lists the ones that exist', () async {
      final app = await sketch();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool', {'tool': 'squircle', 'points': [[0, 0]]})
      ]);
      expect(report.ok, isFalse);
      final error = report.outcomes.single.error!;
      expect(error, contains('ellipse'));
      expect(error, contains('polygon_regular'));
      expect(error, contains('points)'));
    });

    test('too few points says how many the tool needs', () async {
      final app = await sketch();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool', {'tool': 'ellipse', 'points': [[0, 0]]})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('3 points'));
      expect(report.outcomes.single.error, contains('gave 1'));
    });

    test('degenerate picks are refused, not committed and explained later',
        () async {
      final app = await sketch();
      final report = await AiCad(app).run([
        const AiAction('sketch_tool',
            {'tool': 'rect', 'points': [[5, 5], [5, 5]]})
      ]);
      expect(report.ok, isFalse);
      expect(report.outcomes.single.error, contains('coincident'));
    });
  });

  group('the catalogue is the app\'s, not a copy of it', () {
    test('every tool in the map is one buildToolGeometry knows', () {
      // The map is names -> Tool. If a name pointed at a tool the geometry
      // builder does not handle, the op would fail at run time with "could
      // not be built" and no clue why.
      for (final entry in AiCadSketch.tools.entries) {
        expect(toolMeta.containsKey(entry.value), isTrue,
            reason: '${entry.key} has no pick metadata');
      }
    });

    test('the catalogue names every one with its pick count', () {
      final text = AiCadSketch.catalogue;
      for (final name in AiCadSketch.tools.keys) {
        expect(text, contains(name));
      }
      expect(text, contains('2 points'));
      expect(text, contains('or more'));
    });

    test('and the instructions point at it', () {
      expect(kAiActionInstructions, contains('sketch_tool'));
    });
  });
}
