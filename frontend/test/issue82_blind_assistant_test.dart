// ISSUE #82 — "the ai assistant took very very long and produced nothing, it
// made a lot of failures, there were errors and it completely didnt look how i
// wanted."
//
// One session, 9 minutes 49 seconds, 173,751 tokens, and what it handed over
// was a 46 x 22 x 4 mm rounded slab with four orphaned sketches. 839 ms of
// that turn was CAD kernel work — 0.14%. The rest was a model reasoning about
// facts the app had and did not say.
//
// Four of those facts, and the tests that keep them said:
//
//   1. WHERE THE PART IS. describe_shape gave the footprint's SIZE and the Y
//      range, never where the body sat in X and Z. All three origin planes
//      pass through the world origin, so the model took (0,0) for the middle.
//      The plate's middle was world z = -11. The countersink landed on the
//      edge and the cable clamp landed in open air.
//   2. WHICH WAY THE SKETCH AXES POINT. Defined in planeFrame, told to nobody.
//      The model derived it by extruding something and reading the bounding
//      box back: 128,592 characters of thinking in one round, and still wrong.
//   3. WHEN TO THINK. An open `must` latched reasoning_effort to high for the
//      rest of the conversation. 99.0% of output tokens went to reasoning.
//   4. WHAT IS ACTUALLY MADE. knowledge/ held 72 validated documents that no
//      line of Dart referenced and no build step shipped.
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_knowledge.dart';
import 'package:prototype/ai/shape_digest.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';

SketchModel _sketch(List<Geo> gs) => SketchModel('t')..geometry.addAll(gs);

void main() {
  group('the sketch says which way its own axes point', () {
    test('every origin plane states its mapping', () {
      expect(frameAxisNote(planeFrame('xz')),
          'sketch +x is world +X, sketch +y is world -Z, '
          'and it extrudes along +Y. Sketch (0,0) is the world origin.');
      expect(frameAxisNote(planeFrame('xy')),
          'sketch +x is world +X, sketch +y is world +Y, '
          'and it extrudes along +Z. Sketch (0,0) is the world origin.');
      // The one the session got wrong. It placed a Ø10.4 boss at sketch
      // (8.6, 0) believing +x was height; +x is -Z, so the boss came out
      // centred at world Y=0 — half of it below the build plate.
      expect(frameAxisNote(planeFrame('yz')),
          'sketch +x is world -Z, sketch +y is world +Y, '
          'and it extrudes along +X. Sketch (0,0) is the world origin.');
    });

    test('an offset plane says where its origin actually is', () {
      final f = planeFrame('xz');
      final offset =
          PlaneFrame('face', f.u, f.v, f.n, f.n * 4.0);
      expect(frameAxisNote(offset), contains('Sketch (0,0) is (0.00, 4.00, '
          '0.00)'));
    });
  });

  group('the shape digest says where the body is, not only how big', () {
    // The plate from the report: 46 x 22 footprint, 4 mm thick, drawn with
    // sketch_rounded_rect at (0, 11) on XZ — so it spans world z -22..0 and
    // its middle is z = -11, eleven millimetres from the origin.
    ShapeDigest plate() => ShapeDigest(
          body: 'Solid1',
          faces: const [],
          valid: true,
          volume: 3962.16,
          surfaceArea: 2490.7,
          min: const Vec3(-23, 0, -22),
          max: const Vec3(23, 4, 0),
          typeCounts: const {},
          analyticCoverage: 1,
          holes: const [],
          blends: const [],
          mirrors: const [],
          minWall: null,
          minWallBetween: null,
          notable: const [],
          sections: const [],
          sectionAxis: 'x',
          frontAreas: const [88, 990.5, 184],
          edgeCount: 24,
          sharpEdgeCount: 16,
          classifiedArea: 2490.7,
          exact: true,
        );

    test('the extent of every axis is stated', () {
      final t = plate().toText();
      expect(t, contains('extent x -23.00..23.00 · y 0.00..4.00 · '
          'z -22.00..0.00'));
    });

    test('the centre is stated, and that it is not the origin', () {
      final t = plate().toText();
      expect(t, contains('centre (0.00, 2.00, -11.00)'));
      expect(t, contains('WORLD ORIGIN IS NOT THE CENTRE'));
      expect(t, contains('x=0.00, z=-11.00'),
          reason: 'the number to actually use, so nothing has to be derived');
    });

    test('a body drawn around the origin says so instead of warning', () {
      final d = ShapeDigest(
        body: 'Solid1',
        faces: const [],
        valid: true,
        volume: 1000,
        surfaceArea: 600,
        min: const Vec3(-5, 0, -5),
        max: const Vec3(5, 10, 5),
        typeCounts: const {},
        analyticCoverage: 1,
        holes: const [],
        blends: const [],
        mirrors: const [],
        minWall: null,
        minWallBetween: null,
        notable: const [],
        sections: const [],
        sectionAxis: 'x',
        frontAreas: const [100, 100, 100],
        edgeCount: 12,
        sharpEdgeCount: 12,
        classifiedArea: 600,
        exact: true,
      );
      expect(d.toText(), contains('IS centred on the origin'));
      expect(d.toText(), isNot(contains('WORLD ORIGIN IS NOT')));
    });
  });

  group('a profile closed to three decimals is closed', () {
    test('the cable clip from the report now extrudes', () {
      // Verbatim from the session: an outer arc, an inner arc and two lines,
      // with the shared corners written to three decimals. The true arc
      // endpoints are at 12.6937, 2.7007 and 9.9675, 2.7001, so the corners
      // were 0.0008 mm and 0.0005 mm apart. At the old 1e-6 mm weld — one
      // nanometre — the sketch had no closed region, the extrude failed, and
      // the whole block was rolled back.
      final s = _sketch([
        Geo(Geo.arc, [8.25, 0, 5.2, _rad(31.29), _rad(328.71), 0]),
        Geo(Geo.line, [12.694, 2.7, 9.968, 2.7]),
        Geo(Geo.arc, [8.25, 0, 3.2, _rad(57.54), _rad(302.46), 0]),
        Geo(Geo.line, [9.968, -2.7, 12.694, -2.7]),
      ]);
      expect(arrangementLoops(s), isNotEmpty,
          reason: 'three decimal places is what an author writes, and it is '
              'already finer than anything this app can manufacture');
    });

    test('two real walls 20 um apart are still two walls', () {
      // The ceiling from M397 (#25): the weld must not close a gap that is a
      // genuine feature. 20 um is ten times the new radius.
      expect(kSketchWeldTol, lessThan(0.02 / 5),
          reason: 'M397 requires 20 um features to survive the weld');
      final s = _sketch([
        Geo(Geo.line, [0, 0, 10, 0]),
        Geo(Geo.line, [10, 0, 10, 10]),
        Geo(Geo.line, [10, 10, 0, 10]),
        Geo(Geo.line, [0, 10, 0, 0.02]),
      ]);
      final gap = nearestProfileGap(s);
      expect(gap, isNotNull, reason: 'a 20 um gap is still a gap');
      expect(gap!.gap, closeTo(0.02, 1e-9));
    });

    test('a genuinely open profile still reports its gap', () {
      final s = _sketch([
        Geo(Geo.line, [0, 0, 10, 0]),
        Geo(Geo.line, [10, 0, 10, 10]),
        Geo(Geo.line, [10, 10, 0, 10]),
        Geo(Geo.line, [0, 10, 0, 2]),
      ]);
      expect(nearestProfileGap(s)!.gap, closeTo(2, 1e-9));
      // Either end of the miss is the same place to send the model; the
      // finder reports the first loose end it measures (see M397).
      expect(nearestProfileGap(s)!.at,
          anyOf(const Offset(0, 0), const Offset(0, 2)));
    });
  });

  group('the loop is the reasoning', () {
    test('a round of the action loop never deliberates', () {
      expect(deepSeekReasoningEffort(thorough: false), 'low');
      expect(deepSeekReasoningEffort(thorough: true), 'low',
          reason: 'an open must describes the job, not this round — the '
              'latch it used to create never released, because brief_done '
              'does not fire mid-build');
    });

    test('an answer with nothing to test against still may', () {
      expect(
          deepSeekReasoningEffort(thorough: true, iterating: false), 'high');
      expect(
          deepSeekReasoningEffort(thorough: false, iterating: false), 'low');
    });

    test('a truncation retry keeps thinking less', () {
      expect(deepSeekReasoningEffort(thorough: true, attempt: 1), 'low');
      expect(deepSeekReasoningEffort(thorough: true, attempt: 2), 'none');
    });
  });

  group('the knowledge base reaches the model', () {
    final kb = AiKnowledge.forTest(const [
      KnowledgeDoc(
        id: 'fdm/geometry/holes-shafts-and-teardrops',
        title: 'Holes, shafts and teardrops',
        type: 'rules',
        process: 'fdm',
        triggers: ['hole', 'loch', 'bohrung', 'senkloch', 'countersink'],
        depends_on: ['fdm/geometry/overhangs-and-bridging'],
        confidence: 'high',
        body: 'a horizontal hole droops at the top',
      ),
      KnowledgeDoc(
        id: 'fdm/geometry/overhangs-and-bridging',
        title: 'Overhangs and bridging',
        type: 'rules',
        process: 'fdm',
        triggers: ['overhang', 'bridge'],
        depends_on: [],
        confidence: 'high',
        body: 'keep overhangs under 45 degrees',
      ),
      KnowledgeDoc(
        id: 'design/function/holders-clips-and-retention',
        title: 'Holders, clips and retention',
        type: 'recipe',
        process: 'design',
        triggers: ['holder', 'halter', 'kabelhalter', 'clip', 'klemme'],
        depends_on: [],
        confidence: 'high',
        body: 'a closed circle holds nothing',
      ),
      KnowledgeDoc(
        id: 'laser/start-here',
        title: 'Laser cutting — start here',
        type: 'basics',
        process: 'laser',
        triggers: ['laser', 'lasercut'],
        depends_on: [],
        confidence: 'high',
        body: 'mind the kerf',
      ),
    ]);

    test('the request from the report opens the documents it needed', () {
      final got = kb
          .select('Mach mir ein Designer Kabelhalter mit senkloch in der '
              'Mitte für eine senkschraube. Für fdm 3d druck')
          .map((d) => d.id)
          .toList();
      // "senkloch" is the compound that matters: German does not put a space
      // in it, so a whole-word matcher finds neither "senk" nor "loch" and
      // the one document about printed holes never opens.
      expect(got, contains('fdm/geometry/holes-shafts-and-teardrops'));
      // The document that says a closed bore holds no cable. The session
      // built exactly that.
      expect(got, contains('design/function/holders-clips-and-retention'));
      // Pulled in behind the hole rules, which declare it a prerequisite.
      expect(got, contains('fdm/geometry/overhangs-and-bridging'));
      expect(got, isNot(contains('laser/start-here')));
    });

    test('a German compound matches the morpheme inside it', () {
      expect(kb.select('ich brauche einen Kabelhalter').map((d) => d.id),
          contains('design/function/holders-clips-and-retention'));
    });

    test('a narrow change opens nothing at all', () {
      // The instructions promise that a narrow change is exactly that change.
      // One generic trigger is not a reason to spend four thousand characters
      // of the input window on printed-hole theory.
      expect(kb.select('Add a 5 mm hole there'), isEmpty);
      expect(kb.select('rename it to Bracket'), isEmpty);
      expect(kb.select(''), isEmpty);
    });

    test('a three-letter trigger cannot fire from inside a word', () {
      // "abs" must not match "absolute", which is why substring matching
      // starts at four characters.
      final tiny = AiKnowledge.forTest(const [
        KnowledgeDoc(
          id: 'fdm/materials/abs-asa',
          title: 'ABS and ASA',
          type: 'material',
          process: 'fdm',
          triggers: ['abs', 'asa'],
          depends_on: [],
          confidence: 'high',
          body: 'warps',
        ),
      ]);
      expect(tiny.select('make it absolutely flat'), isEmpty);
    });

    test('the menu names every document and how to open one', () {
      final menu = kb.indexText();
      for (final d in kb.documents) {
        expect(menu, contains(d.id));
      }
      expect(menu, contains('"op": "knowledge"'));
    });

    test('an empty corpus degrades to the assistant as it was', () {
      final none = AiKnowledge.forTest(const []);
      expect(none.isEmpty, isTrue);
      expect(none.select('anything at all'), isEmpty);
      expect(none.indexText(), isEmpty);
    });
  });
}

double _rad(double deg) => deg * 3.141592653589793 / 180;
