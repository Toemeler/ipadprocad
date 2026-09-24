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
