// The `program` op: a whole part in world coordinates, replaced when resent,
// with expectations the app measures. Runs on the real kernel.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_models.dart';
import 'package:prototype/ai/printability.dart';
import 'package:prototype/ai/shape_digest.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  final skip = kernel.available ? false : 'needs PROTOTYPE_NATIVE_DIR';

  Future<(AppState, AiCad)> fresh() async {
    final app = AppState(ai: AiController())..partKernel = kernel;
    app.docsDirForTest = Directory.systemTemp.createTempSync('prog_');
    await app.createNamedPart('P');
    return (app, AiCad(app));
  }

  List<double> box(AppState app, String body) =>
      currentBodySolid(app.currentPart!, body)!.shape!.bbox()!;

  test('bare expressions in a block are read as expressions, silently', () {
    final b = parseAiActions('```cad\n{"title": "T", "vars": {"D": 40, "t": 2},\n'
        ' "part": "p", "steps": [{"cylinder": {"base": [0, 0, 0], "d": D, '
        '"h": D/2 - t * (1 + 0.5)}}]}\n```');
    expect(b.parseError, isNull);
    expect(b.notes, isEmpty, reason: 'writing a formula is not a mistake');
    final prog = b.actions.last;
    expect(prog.op, 'program');
    final cyl = ((prog.args['steps'] as List).first as Map)['cylinder'] as Map;
    expect(cyl['d'], 'D');
    expect(cyl['h'], 'D/2 - t * (1 + 0.5)');
    expect(cyl['base'], [0, 0, 0]);
  });

  test('JSON slips a model makes in formulas are repaired', () {
    // Names quoted inside a formula, a stray quote after a number, and a
    // closing brace that matches nothing (genA program-mode errors).
    final b = parseAiActions('```cad\n{"title": "T", "vars": {"a": 4, "b": 2},\n'
        ' "part": "p", "steps": [{"box": {"size": [7", -("a"-"b"), 3]}}]}}\n```');
    expect(b.parseError, isNull);
    final prog = b.actions.last;
    final bx = ((prog.args['steps'] as List).first as Map)['box'] as Map;
    expect(bx['size'], [7, '-(a-b)', 3]);
    // A sign quoted on its own, -"name", and a step left one "}" short
    // (genB program-mode errors).
    final c = parseAiActions('```cad\n{"title": "T", "vars": {"bore": 4},\n'
        ' "part": "p", "steps": [{"box": {"min": [0, "-"bore", -"bore"], '
        '"max": [9, 9, 9]}, {"sphere": {"center": [0, 0, 0], "d": 4}}]}\n```');
    expect(c.parseError, isNull);
    final steps = c.actions.last.args['steps'] as List;
    expect(steps, hasLength(2));
    expect(((steps.first as Map)['box'] as Map)['min'], [0, '-bore', '-bore']);
  });

  test('a shape may stand alone until a later one joins it; loose at the '
      'end is a problem', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'table',
        'steps': [
          {'box': {'size': [4, 20, 4], 'base': [0, 0, 0]}},
          {'box': {'size': [4, 20, 4], 'base': [30, 0, 0]}},
          {'box': {'min': [-2, 20, -2], 'max': [32, 23, 2]}},
        ],
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(r.problems.join(), isNot(contains('pieces')));
    final loose = await cad.run([
      const AiAction('program', {
        'part': 'table',
        'steps': [
          {'box': {'size': [4, 20, 4], 'base': [0, 0, 0]}},
          {'box': {'size': [4, 20, 4], 'base': [30, 0, 0]}},
        ],
      })
    ]);
    expect(loose.ok, isTrue, reason: loose.encode());
    expect(loose.problems.join(), contains('pieces'));
    // WHERE the loose piece is: that is what it takes to fix it.
    expect(loose.problems.join(), contains('loose: x 28.0..32.0, y 0.0..20.0'));
    // A second name adds a part, and says what else is there; steps: []
    // removes one.
    final second = await cad.run([
      const AiAction('program', {
        'part': 'table2',
        'steps': [
          {'box': {'min': [50, 0, 0], 'max': [60, 5, 5]}},
        ],
      })
    ]);
    expect(second.outcomes.last.detail!['otherParts'], contains('table'));
    final gone = await cad.run([
      const AiAction('program', {'part': 'table', 'steps': []})
    ]);
    expect(gone.ok, isTrue, reason: gone.encode());
    expect(app.currentPart!.solidBodies().length, 1);
  }, skip: skip);

  test('in a program a cut is never turned round, and a missed copy is named',
      () async {
    final (app, cad) = await fresh();
    // A box cut ABOVE a 4 mm disc removes nothing: it is refused, not flipped
    // down through the disc.
    final above = await cad.run([
      const AiAction('program', {
        'part': 'coaster',
        'steps': [
          {'cylinder': {'base': [0, 0, 0], 'd': 90, 'h': 4}},
          {'box': {'size': [72, 8, 72], 'center': [0, 8.8, 0]}, 'mode': 'cut'},
        ],
      })
    ]);
    // Skipped and reported, and the rest of the part is built.
    expect(above.ok, isTrue, reason: above.encode());
    expect(above.problems.join(), contains('was skipped'));
    expect(above.problems.join(), contains('The body spans x -45.0..45.0'));
    // Options written next to the shape key count; copy 4 of 5 misses (copy 3 sits on the edge and still cuts).
    final holes = await cad.run([
      const AiAction('program', {
        'part': 'dish',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [50, 5, 30]}},
          {'hole': {'at': [10, 5, 15], 'into': '-y', 'd': 4},
            'repeat': {'count': 5, 'step': [20, 0, 0]}},
        ],
      })
    ]);
    expect(holes.ok, isTrue, reason: holes.encode());
    expect(holes.problems.join(), contains('step 2, copy 4 of 5 (hole)'));
  }, skip: skip);

  test('a part name with a hyphen or spaces is used, not refused', () {
    expect(aiProgramPartName('Tisch-Haken'), 'Tisch_Haken');
    expect(aiProgramPartName(' 3 way clip '), 'p3_way_clip');
    expect(aiProgramPartName(null), 'part');
  });

  test('expect section: the openings at a height are counted', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'tray',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [62, 20, 42]}},
          {'box': {'min': [2, 2, 2], 'max': [20, 21, 20]}, 'mode': 'cut',
            'repeat': {'count': 3, 'step': [20, 0, 0]}},
          {'box': {'min': [2, 2, 22], 'max': [20, 21, 40]}, 'mode': 'cut',
            'repeat': {'count': 3, 'step': [20, 0, 0]}},
        ],
        'expect': {'section': [{'y': 15, 'openings': 6}, {'y': 1, 'openings': 6}]},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final checks = (r.outcomes.last.detail!['expect'] as List).cast<Map>();
    expect(checks[0]['ok'], isTrue, reason: '$checks');
    expect(checks[1]['ok'], isFalse, reason: 'the floor has no openings');
    expect(r.problems.join(), contains('openings in the section at y = 1.0'));
  }, skip: skip);

  test('a hole drilled away from the part is drilled the other way', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'plate',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [30, 3, 30]}},
          // On the top face, but pointing up, away from the plate.
          {'hole': {'at': [15, 3, 15], 'into': '+y', 'd': 4}},
        ],
        'expect': {'holes': [{'d': 4, 'count': 1}]},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(r.problems, isEmpty, reason: r.encode());
  }, skip: skip);

  test('a groove is not a hole; the report shows sections', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'flange',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [40, 6, 20]}},
          // A full hole, and a "hole" whose axis runs along the edge.
          {'hole': {'at': [10, 6, 10], 'into': '-y', 'd': 4}},
          {'cylinder': {'base': [30, 0, 0], 'd': 4, 'h': 6}, 'mode': 'cut'},
        ],
        'expect': {'holes': [{'d': 4, 'count': 2}]},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final d = r.outcomes.last.detail!;
    final holes = (d['expect'] as List).cast<Map>().single;
    expect(holes['ok'], isFalse, reason: '$holes');
    expect(holes['got'], {'count': 1, 'not round all the way': 1});
    final sections = (d['sections'] as List).cast<String>();
    expect(sections, hasLength(5));
    expect(sections.first, contains('1 opening'));
  }, skip: skip);

  test('a program ON an existing body changes it, and only its own work is '
      'replaced', () async {
    final (app, cad) = await fresh();
    // The user's body, made without a program.
    final made = await cad.run([
      const AiAction('create_sketch', {'plane': 'xz'}),
      const AiAction('sketch_rect', {'width': 50, 'height': 40, 'centered': true}),
      const AiAction('extrude', {'distance': 30}),
    ]);
    expect(made.ok, isTrue, reason: made.encode());
    final p = app.currentPart!;
    final user = p.solidBodies().single.$1;
    final full = currentBodySolid(p, user)!.volume;
    for (final t in [2, 1]) {
      final r = await cad.run([
        AiAction('program', {
          'part': 'open',
          'on': user,
          'steps': [
            {'shell': {'t': t, 'open': 'bottom'}},
            {'hole': {'at': [0, 30, 0], 'into': '-y', 'd': 6}},
          ],
        })
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(p.solidBodies().map((b) => b.$1), [user], reason: 'no copy');
    }
    final thin = currentBodySolid(p, user)!.volume;
    expect(thin, lessThan(full * 0.2));
    final gone = await cad.run([
      const AiAction('program', {'part': 'open', 'steps': []})
    ]);
    expect(gone.ok, isTrue, reason: gone.encode());
    expect(currentBodySolid(p, user)!.volume, closeTo(full, 1e-6));
    final wrong = await cad.run([
      const AiAction('program', {
        'part': 'x', 'on': 'Nope',
        'steps': [{'box': {'size': [1, 1, 1], 'center': [0, 0, 0]}}],
      })
    ]);
    expect(wrong.encode(), contains('the bodies are $user'));
  }, skip: skip);

  test('the shape context says where each round feature is', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'motor',
        'steps': [
          {'cylinder': {'base': [0, 0, 0], 'd': 20, 'h': 10}},
          {'cylinder': {'base': [5, 10, 0], 'd': 4, 'h': 6}},
          {'hole': {'at': [-5, 10, 0], 'into': '-y', 'd': 3, 'depth': 4}},
        ],
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final text = shapeContextFor(
        app.currentPart!, app.partKernel, ShapeDigestCache());
    expect(text, contains('Ø4.00 shaft/boss on the Y axis at x 5.00, z 0.00, y 10.00..16.00'));
    expect(text, contains('Ø3.00 hole/bore on the Y axis at x -5.00, z 0.00, y 6.00..10.00'));
  }, skip: skip);

  test('through-holes hold no water; a cup does', () async {
    final (app, cad) = await fresh();
    final plate = await cad.run([
      const AiAction('program', {
        'part': 'plate',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [60, 4, 60]}},
          {'hole': {'at': [10, 4, 10], 'into': '-y', 'd': 5},
            'repeat': {'count': 5, 'step': [10, 0, 0]}},
        ],
      })
    ]);
    expect(plate.outcomes.last.detail!['holdsMl'], isNull,
        reason: 'water runs straight through');
    final cup = await cad.run([
      const AiAction('program', {
        'part': 'cup',
        'steps': [
          {'cylinder': {'base': [100, 0, 0], 'd': 70, 'h': 76}},
          {'shell': {'t': 2, 'open': 'top'}},
        ],
      })
    ]);
    // π·33²·74 mm³ = 253 ml.
    expect(cup.outcomes.last.detail!['holdsMl'], closeTo(253, 253 * 0.02));
  }, skip: skip);

  test("DeepSeek's own tool-call markup is read as the action it names", () {
    const reply = '<｜｜DSML｜｜ calls> <｜｜DSML｜｜ invoke name="describe_shape">'
        '<｜｜DSML｜｜ parameter name="body" string="true">Solid1</｜｜DSML｜｜ parameter>'
        ' </｜｜DSML｜｜ invoke> </｜｜DSML｜｜ calls>';
    final b = parseAiActions(reply);
    expect(b.parseError, isNull);
    expect(b.actions.single.op, 'describe_shape');
    expect(b.actions.single.args['body'], 'Solid1');
    expect(aiReplyWithoutActions(reply), isEmpty);
  });

  test('named numbers past the cap push out the oldest, not the block',
      () async {
    final (app, cad) = await fresh();
    for (var round = 0; round < 3; round++) {
      final r = await cad.run([
        AiAction('vars', {for (var i = 0; i < 40; i++) 'v${round}_$i': i}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
    }
    // The newest are all there; the oldest round was dropped.
    final r = await cad.run([
      const AiAction('program', {
        'part': 'b',
        'steps': [
          {'box': {'size': ['v2_39', 'v1_39', 10], 'base': [0, 0, 0]}},
        ],
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
  }, skip: skip);

  test('a smooth profile passes through its points and shells', () async {
    final pts = <List<num>>[[0, 0], [30, 0], [40, 30], [22, 80], [26, 100], [0, 100]];
    final sm = aiSmoothProfile(pts);
    for (final q in pts) {
      expect(sm.any((p) => p[0] == q[0] && p[1] == q[1]), isTrue,
          reason: 'passes through $q');
    }
    expect(sm.length, greaterThan(pts.length));
    final (app, cad) = await fresh();
    final sw = Stopwatch()..start();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'vase',
        'steps': [
          {'revolve': {'profile': [[0, 0], [30, 0], [40, 30], [22, 80],
            [26, 100], [0, 100]], 'smooth': true}},
          {'shell': {'t': 2, 'open': 'top'}},
        ],
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(r.problems, isEmpty, reason: r.encode());
    expect(sw.elapsedMilliseconds, lessThan(8000));
  }, skip: skip);

  test('a stray body a program made can be removed by its body name; "on" '
      'in every step counts', () async {
    final (app, cad) = await fresh();
    await cad.run([
      const AiAction('program', {'part': 'a', 'steps': [
        {'box': {'min': [0, 0, 0], 'max': [10, 10, 10]}},
      ]})
    ]);
    await cad.run([
      const AiAction('program', {'part': 'b', 'steps': [
        {'box': {'min': [20, 0, 0], 'max': [30, 10, 10]}},
      ]})
    ]);
    final p = app.currentPart!;
    final bodyB = p.solidBodies().last.$1;
    final gone = await cad.run([
      AiAction('program', {'part': bodyB, 'steps': []})
    ]);
    expect(gone.ok, isTrue, reason: gone.encode());
    expect(p.solidBodies(), hasLength(1));
    final bodyA = p.solidBodies().single.$1;
    final cut = await cad.run([
      AiAction('program', {'part': 'holes', 'steps': [
        {'cylinder': {'on': bodyA, 'base': [5, 10, 5], 'd': 3, 'h': -4, 'mode': 'cut'}},
      ]})
    ]);
    expect(cut.ok, isTrue, reason: cut.encode());
    expect(p.solidBodies(), hasLength(1), reason: 'cut into A, not a new body');
  }, skip: skip);

  test('a new name for the same part again is its new version', () async {
    final (app, cad) = await fresh();
    for (final name in ['Mug', 'Mug2']) {
      final r = await cad.run([
        AiAction('program', {'part': name, 'steps': [
          {'cylinder': {'base': [0, 0, 0], 'd': 70, 'h': name == 'Mug' ? 90 : 95}},
          {'shell': {'t': 2, 'open': 'top'}},
        ]})
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      if (name == 'Mug2') {
        expect(r.outcomes.last.detail!['replacedVersion'], contains('Mug'));
      }
    }
    expect(app.currentPart!.solidBodies(), hasLength(1));
    final b = box(app, app.currentPart!.solidBodies().single.$1);
    expect(b[4] - b[1], closeTo(95, 1e-6));
  }, skip: skip);

  test('smoothing keeps sharp corners and never makes a profile cross '
      'itself (a cup section with its rim hung the kernel)', () async {
    final section = <List<num>>[[0, 0], [38.4, 0], [39.0, 0.6], [36.66, 33.6],
      [34.32, 59.52], [35.0, 94.0], [35.0, 93.6], [32.6, 93.6], [32.6, 2.4],
      [0, 2.4]];
    final sm = aiSmoothProfile(section);
    for (final q in section) {
      expect(sm.any((p) => p[0] == q[0] && p[1] == q[1]), isTrue);
    }
    final (app, cad) = await fresh();
    final sw = Stopwatch()..start();
    final r = await cad.run([
      AiAction('program', {'part': 'Cup2', 'steps': [
        {'revolve': {'profile': section, 'smooth': true}},
        {'fillet': {'r': 1.2, 'edges': 'top'}},
        {'chamfer': {'d': 0.6, 'edges': 'bottom'}},
      ]})
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(sw.elapsedMilliseconds, lessThan(15000));
  }, skip: skip);

  test('a repeated shape streamed in is one pattern, and the final block '
      'does not build it again', () async {
    final (app, cad) = await fresh();
    final steps = <Map<String, dynamic>>[
      {'cylinder': {'base': [0, 0, 0], 'axis': 'y', 'd': 30.0, 'h': 15.0}},
      {'box': {'size': [30.0, 10.4, 2.4], 'center': [8.1, 5.5, 0.0]},
        'mode': 'cut', 'repeat': {'count': 12, 'around': [0, 0], 'angle': 30}},
    ];
    await cad.streamProgram('k', const {}, steps.sublist(0, 1));
    await cad.streamProgram('k', const {}, steps);
    final r = await cad.run([AiAction('program', {'part': 'k', 'steps': steps})]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(app.currentPart!.features.map((f) => f.kind).toList(),
        ['extrude', 'extrude', 'pattern']);
    expect(r.outcomes.last.detail!['volumeMm3'], closeTo(9318.24, 0.1));
  }, skip: skip);

  test('a clamp bore that wraps most of the way round is a hole; a groove '
      'is not', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'clamp',
        'steps': [
          {'cylinder': {'base': [0, 0, 0], 'axis': 'z', 'd': 30, 'h': 12}},
          {'cylinder': {'base': [0, 0, 0], 'axis': 'z', 'd': 22.6, 'h': 12}, 'mode': 'cut'},
          // A slot opens the ring on one side: about 300° still wraps.
          {'box': {'min': [-4, 5, 0], 'max': [4, 20, 12]}, 'mode': 'cut'},
        ],
        'expect': {'holes': [{'d': 22.6, 'count': 1}]},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final holes = (r.outcomes.last.detail!['expect'] as List).cast<Map>().single;
    expect(holes['ok'], isTrue, reason: '$holes');
  }, skip: skip);

  test('a channel running sideways is listed under bores and checked by '
      'an upright section', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'clip',
        'steps': [
          {'box': {'min': [0, 0, -8], 'max': [30, 3, 8]}},
          {'cylinder': {'base': [0, 9, 0], 'axis': 'x', 'd': 12, 'h': 30}},
          {'cylinder': {'base': [0, 9, 0], 'axis': 'x', 'd': 6.6, 'h': 30}, 'mode': 'cut'},
          {'box': {'min': [0, 11, -2.4], 'max': [30, 16, 2.4]}, 'mode': 'cut'},
        ],
        'expect': {
          'holes': [{'d': 6.6, 'count': 1}],
          'section': [{'x': 15, 'openings': 0}],
        },
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final d = r.outcomes.last.detail!;
    final bores = (d['bores'] as List).cast<String>();
    expect(bores.single, contains('Ø6.6 along x'), reason: '$bores');
    expect(bores.single, contains('open along one side'), reason: '$bores');
    for (final c in (d['expect'] as List).cast<Map>()) {
      expect(c['ok'], isTrue, reason: '$c');
    }
  }, skip: skip);

  test('a smooth cup: closed along the axis, drawn in tangent arcs, shelled '
      'open at the top, its rim blended by a point at its centre', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'cup',
        'steps': [
          // The profile ends ON the axis at the top only: closed along it.
          {'revolve': {'axis': 'y', 'smooth': true, 'profile': [
            [26, 0], [30, 2.4], [30, 6], [31, 33.6], [33, 67.2],
            [37.5, 88.3], [39, 92], [39, 96], [0, 96]]}},
          {'shell': {'t': 2.4, 'open': 'top'}},
          {'fillet': {'r': 1, 'edges': 'outer', 'near': [[0, 96, 0]]}},
        ],
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final d = r.outcomes.last.detail!;
    expect(d['notes'] ?? const [], isNot(contains(contains('straight segments'))));
    expect(d['holdsMl'], greaterThan(250));
    expect(r.problems, isEmpty, reason: r.problems.join("\n"));
    final sections = (d['sections'] as List).cast<String>();
    // No hidden cone inside: one area at mid height.
    expect(sections[2], isNot(contains('separate areas')), reason: '$sections');
  }, skip: skip);

  test('flat faces of a revolved part look the way they face', () async {
    final (app, cad) = await fresh();
    await cad.run([
      const AiAction('program', {
        'part': 'r',
        'steps': [
          {'revolve': {'axis': 'y', 'start': [0, 0], 'segments': [
            {'to': [10, 0]}, {'to': [10, 20], 'through': [14, 10]},
            {'to': [0, 20]}]}},
        ],
      })
    ]);
    final found = await cad.run([
      const AiAction('faces_where', {'type': 'plane'})
    ]);
    final faces = (found.outcomes.last.detail!['faces'] as List).cast<Map>();
    final facing = {for (final f in faces) (f['at'] as List)[1].round(): f['facing']};
    expect(facing, {0: '-Y', 20: '+Y'});
  }, skip: skip);

  test('a handle whose heights are too close for printable legs says what '
      'span it needs', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'mug',
        'steps': [
          {'cylinder': {'base': [0, 0, 0], 'd': 70, 'h': 90}},
          {'shell': {'t': 2.4, 'open': 'top'}},
          {'handle': {'side': '+x', 'from_y': 30, 'to_y': 60, 'reach': 25, 'size': 10}},
        ],
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final notes = (r.outcomes.last.detail!['notes'] as List).cast<String>();
    expect(notes.join(), contains('to_y - from_y ≥'));
  }, skip: skip);

  test('for a filament printer a round handle moves its ends apart until '
      'its legs print without support', () async {
    final (app, cad) = await fresh();
    app.ai.currentSession.messages
        .add(AiMessage(role: 'user', text: 'a mug, fdm'));
    final r = await cad.run([
      const AiAction('program', {
        'part': 'mug',
        'steps': [
          {'cylinder': {'base': [0, 0, 0], 'd': 70, 'h': 90}},
          {'shell': {'t': 2.4, 'open': 'top'}},
          {'handle': {'side': '+x', 'from_y': 30, 'to_y': 60, 'reach': 22, 'size': 10}},
        ],
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final notes = (r.outcomes.last.detail!['notes'] as List).cast<String>();
    expect(notes.join(), contains('its ends moved'));
    expect(r.problems.where((l) => l.contains('Not printable')), isEmpty,
        reason: r.problems.join('\n'));
  }, skip: skip);

  test('a program for an existing part that starts by drilling is added to '
      'the part, with or without "on" naming its own body', () async {
    final (app, cad) = await fresh();
    final first = await cad.run([
      const AiAction('program', {
        'part': 'block',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [40, 10, 30]}},
        ],
      })
    ]);
    var body = first.outcomes.last.detail!['body'] as String;
    for (final withOn in [false, true]) {
      final on = withOn ? body : null;
      final r = await cad.run([
        AiAction('program', {
          'part': 'block',
          if (on != null) 'on': on,
          'steps': [
            {'hole': {'at': [10, 10, 15], 'into': '-y', 'd': 5}},
          ],
        })
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final d = r.outcomes.last.detail!;
      expect(d['appended'], contains('added after'));
      expect(d['volumeMm3'], closeTo(40 * 10 * 30 - math.pi * 6.25 * 10, 1));
      body = d['body'] as String;
    }
  }, skip: skip);

  test('slips that mean one thing are read as that thing: swapped box '
      'corners, a repeated point, a wrapped path, an outline up the wall',
      () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'a',
        'steps': [
          {'box': {'min': [0, 0, 10], 'max': [20, 5, 0]}},
          {'extrude': {'plane': 'xy', 'at': 0, 'distance': 10, 'outline': {
            'path': {'start': [0, 5], 'segments': [
              {'to': [20, 5]}, {'to': [20, 5]}, {'to': [10, 12]}]}}}},
        ],
      }),
      const AiAction('program', {
        'part': 'cup',
        'steps': [
          {'revolve': {'base': [50, 0, 0], 'profile': [[20, 0], [20, 40]]}},
          {'shell': {'t': 2, 'open': 'top'}},
        ],
      }),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final a = r.outcomes[0].detail!;
    expect(a['volumeMm3'], closeTo(20 * 5 * 10 + 20 * 7 / 2 * 10, 0.5));
    final cup = r.outcomes[1].detail!;
    expect(cup['holdsMl'], closeTo(math.pi * 18 * 18 * 38 / 1000, 0.5));
  }, skip: skip);

  test('a horizontal screw hole prints as a bridge; a wide one does not',
      () async {
    final (app, cad) = await fresh();
    await cad.run([
      const AiAction('program', {
        'part': 'wall',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [30, 40, 4]}},
          {'hole': {'at': [15, 25, 4], 'into': '-z', 'd': 5.5}},
          {'hole': {'at': [15, 10, 4], 'into': '-z', 'd': 12}},
        ],
      }),
      const AiAction('program', {
        'part': 'ring',
        'steps': [
          {'box': {'min': [50, 0, 0], 'max': [110, 60, 4]}},
          {'hole': {'at': [80, 30, 4], 'into': '-z', 'd': 40}},
        ],
      }),
    ]);
    final p = app.currentPart!;
    List<String> of(String part) => overhangReport(currentBodySolid(
            p, p.features.lastWhere((f) => f.name.startsWith('p_${part}_')).bodyName)!
        .mesh);
    expect(of('wall'), isEmpty);
    expect(of('ring'), isNotEmpty);
  }, skip: skip);

  test('overhangs are reported for what this request builds, not for the '
      'bodies already there', () async {
    final (app, cad) = await fresh();
    final msgs = app.ai.currentSession.messages;
    msgs.add(AiMessage(role: 'user', text: 'a T shape, fdm'));
    final t = await cad.run([
      const AiAction('program', {
        'part': 'tee',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [4, 20, 4]}},
          {'box': {'min': [-10, 20, 0], 'max': [14, 24, 4]}},
        ],
      })
    ]);
    expect(t.problems.join(), contains('Not printable'));
    msgs.add(AiMessage(role: 'user', text: 'now a plain block beside it'));
    final b = await cad.run([
      const AiAction('program', {
        'part': 'block',
        'steps': [
          {'box': {'min': [40, 0, 0], 'max': [60, 10, 10]}},
        ],
      })
    ]);
    expect(b.problems.join(), isNot(contains('Not printable')),
        reason: b.problems.join('\n'));
  }, skip: skip);

  test('no steps with a new expect measures the part again and keeps it',
      () async {
    final (app, cad) = await fresh();
    await cad.run([
      const AiAction('program', {
        'part': 'box',
        'steps': [
          {'box': {'min': [0, 0, 0], 'max': [10, 10, 10]}},
        ],
        'expect': {'size': [12, 10, 10]},
      })
    ]);
    final r = await cad.run([
      const AiAction('program', {
        'part': 'box',
        'steps': [],
        'expect': {'size': [10, 10, 10]},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(r.outcomes.last.detail!['unchanged'], isNotNull);
    expect(app.currentPart!.solidBodies(), isNotEmpty);
    expect(r.problems.join(), isNot(contains('expected size')));
  }, skip: skip);

  test('a new part is told where it stands against the other bodies', () async {
    final (app, cad) = await fresh();
    await cad.run([
      const AiAction('program', {'part': 'motor', 'steps': [
        {'cylinder': {'base': [0, 0, 0], 'd': 20, 'h': 10}},
        {'cylinder': {'base': [0, 10, 0], 'd': 4, 'h': 6}},
      ]})
    ]);
    Future<String> wheelAt(double y) async {
      final r = await cad.run([
        AiAction('program', {'part': 'wheel', 'steps': [
          {'cylinder': {'base': [30, y, 0], 'd': 16, 'h': 4}},
          {'hole': {'at': [30, y + 4, 0], 'into': '-y', 'd': 4}},
        ]})
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      return (r.outcomes.last.detail!['relations'] as List).join(' | ');
    }

    final far = await wheelAt(0);
    expect(far, contains('x: yours starts'));
    final above = await cad.run([
      const AiAction('program', {'part': 'wheel', 'steps': [
        {'cylinder': {'base': [0, 20, 0], 'd': 16, 'h': 4}},
        {'hole': {'at': [0, 24, 0], 'into': '-y', 'd': 4}},
      ]})
    ]);
    final a = (above.outcomes.last.detail!['relations'] as List).join(' | ');
    expect(a, contains('axes 0.0 mm apart'));
    expect(a, contains('they do not meet'));
    final r = await cad.run([
      const AiAction('program', {'part': 'wheel', 'steps': [
        {'cylinder': {'base': [0, 12, 0], 'd': 16, 'h': 4}},
        {'hole': {'at': [0, 16, 0], 'into': '-y', 'd': 4}},
      ]})
    ]);
    final near = (r.outcomes.last.detail!['relations'] as List).join(' | ');
    expect(near, contains('axes 0.0 mm apart'));
    expect(near, contains('sharing 4.0'));
  }, skip: skip);

  test('a case program starts from enclose round what is there', () async {
    final (app, cad) = await fresh();
    await cad.run([
      const AiAction('program', {'part': 'board', 'steps': [
        {'box': {'min': [0, 0, 0], 'max': [40, 5, 30]}},
      ]})
    ]);
    final r = await cad.run([
      const AiAction('program', {'part': 'case', 'steps': [
        {'enclose': {'wall': 2, 'clearance': 1, 'rim': 3}},
        {'hole': {'at': [20, 5, -3], 'into': '+z', 'd': 4}},
      ]})
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(r.problems.where((p) => p.contains('runs into')), isEmpty,
        reason: r.encode());
  }, skip: skip);

  test('an ngon is a regular polygon by its across-flats size', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {'part': 'knob', 'steps': [
        {'cylinder': {'base': [0, 0, 0], 'd': 30, 'h': 15}},
        {'extrude': {'plane': 'xz', 'at': 0, 'outline': {'ngon': [0, 0, 6, 10]},
          'distance': 5}, 'mode': 'cut'},
      ], 'expect': {'section': [{'y': 2, 'openings': 1}]}})
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final sec = (r.outcomes.last.detail!['expect'] as List).cast<Map>().single;
    final b = ((sec['got'] as Map)['each [x0, z0, x1, z1]'] as List).single as List;
    final w = (b[2] as num) - (b[0] as num), h = (b[3] as num) - (b[1] as num);
    // Flats along u (x): across corners on x, across flats (10) on z.
    expect(w, closeTo(10 / math.cos(math.pi / 6), 0.05));
    expect(h, closeTo(10, 0.05));
  }, skip: skip);

  test('a program is read step by step while it streams in', () {
    const full = 'Sure.\n```cad\n{"title": "T", "vars": {"D": 40, "h": D/2},\n'
        ' "part": "cup", "steps": [{"revolve": {"profile": [[0,0],[D/2,0],'
        '[D/2,h],[0,h]]}}, {"shell": {"t": 2, "open": "top"}}, '
        '{"fillet": {"r": 1, "edges": "top"}}], "expect": {"pieces": 1}}\n```';
    // Cut anywhere: only whole steps come back, in order.
    var seen = 0;
    for (var n = 0; n <= full.length; n++) {
      final r = aiStreamedProgram(full.substring(0, n));
      if (r == null) continue;
      expect(r.$1, 'cup');
      expect(r.$3.length, greaterThanOrEqualTo(seen));
      seen = r.$3.length;
    }
    final r = aiStreamedProgram(full)!;
    expect(r.$2['h'], 'D/2');
    expect(r.$3, hasLength(3));
    expect(r.$3[1]['shell'], {'t': 2, 'open': 'top'});
  });

  test('shapes land where the world coordinates say, in every plane', () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'probe',
        'steps': [
          {'box': {'min': [10, 0, 20], 'max': [30, 5, 40]}},
          // An xz outline at y 5: (x, z) as written.
          {'extrude': {'plane': 'xz', 'at': 5, 'distance': 3,
            'outline': {'circle': [25, 35, 4]}}},
          // A cylinder along +x from x 30.
          {'cylinder': {'base': [30, 2.5, 30], 'axis': 'x', 'd': 3, 'h': 6}},
          // An xy outline at z 40, a 2 x 2 square at x 12..14, y 1..3, out +z.
          {'extrude': {'plane': 'xy', 'at': 40, 'distance': 2,
            'outline': [[12, 1], [14, 1], [14, 3], [12, 3]]}},
          // A yz outline at x 10, going -x.
          {'extrude': {'plane': 'yz', 'at': 10, 'distance': -2,
            'outline': {'rect': [1, 22, 3, 24]}}},
        ],
        'expect': {'pieces': 1},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final b = box(app, r.outcomes.last.detail!['body'] as String);
    expect(b[0], closeTo(8, 1e-3)); // the yz extrude reaches x 8
    expect(b[3], closeTo(36, 1e-3)); // the x cylinder reaches x 36
    expect(b[4], closeTo(8, 1e-3)); // the xz boss reaches y 8
    expect(b[5], closeTo(42, 1e-3)); // the xy extrude reaches z 42
    expect(b[2], closeTo(20, 1e-3));
  }, skip: skip);

  test('a program sent again replaces the part', () async {
    final (app, cad) = await fresh();
    for (final h in [10, 20]) {
      final r = await cad.run([
        AiAction('program', {
          'part': 'block',
          'steps': [
            {'box': {'size': [10, h, 10], 'base': [0, 0, 0]}},
          ],
        })
      ]);
      expect(r.ok, isTrue, reason: r.encode());
    }
    final p = app.currentPart!;
    expect(p.solidBodies().length, 1);
    final b = box(app, p.solidBodies().first.$1);
    expect(b[4] - b[1], closeTo(20, 1e-6));
  }, skip: skip);

  test('a vessel: revolve, shell, handle, a countersunk hole, expectations',
      () async {
    final (app, cad) = await fresh();
    final r = await cad.run([
      const AiAction('program', {
        'part': 'cup',
        'steps': [
          {'revolve': {'profile': [[0, 0], [35, 0], [38, 90], [0, 90]]}},
          {'shell': {'t': 2.4, 'open': 'top'}},
          {'handle': {'side': '+x', 'from_y': 20, 'to_y': 70, 'reach': 24}},
          {'fillet': {'r': 1, 'edges': 'top'}},
        ],
        'expect': {'holdsMl': 300, 'pieces': 1, 'size': [null, 90, 76]},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final checks = (r.outcomes.last.detail!['expect'] as List).cast<Map>();
    expect(checks.firstWhere((c) => c['what'] == 'pieces')['ok'], isTrue);
    // 300 ml is not what this cup holds: the report says so, as a problem.
    final holds = checks.firstWhere((c) => c['what'] == 'holdsMl');
    expect(holds['ok'], isFalse);
    expect(r.problems.join(), contains('expected holdsMl'));
  }, skip: skip);

  test('relations: a part placed on another body by its anchors', () async {
    final (app, cad) = await fresh();
    await cad.run([
      const AiAction('program', {
        'part': 'base',
        'steps': [
          {'box': {'min': [-20, 0, -10], 'max': [20, 8, 10]}},
        ],
      })
    ]);
    final r = await cad.run([
      const AiAction('program', {
        'part': 'post',
        'steps': [
          {'cylinder': {'base': ['base.cx', 'base.ymax', 'base.cz'], 'd': 6, 'h': 12}},
          {'hole': {'at': ['base.cx', 'base.ymax + 12', 'base.cz'], 'd': 3,
            'depth': 5, 'countersink': [5]}},
        ],
        'expect': {'clear_of': ['base'], 'holes': [{'d': 3, 'count': 1}]},
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final checks = (r.outcomes.last.detail!['expect'] as List).cast<Map>();
    expect(checks.every((c) => c['ok'] == true), isTrue, reason: '$checks');
    final b = box(app, r.outcomes.last.detail!['body'] as String);
    expect(b[1], closeTo(8, 1e-6));
    expect(b[4], closeTo(20, 1e-6));
  }, skip: skip);
}
