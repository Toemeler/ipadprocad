// The `program` op: a whole part in world coordinates, replaced when resent,
// with expectations the app measures. Runs on the real kernel.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
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
    expect(above.ok, isFalse);
    expect(above.encode(), contains('The body spans x -45.0..45.0'));
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
    expect(holes.ok, isFalse);
    expect(holes.encode(), contains('step 2, copy 4 of 5 (hole)'));
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
