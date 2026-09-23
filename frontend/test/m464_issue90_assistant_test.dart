// M464 (#90) — the assistant's half of "a lot of different things went
// wrong".
//
//   * "mach solid 2 unsichtbar" — the assistant had no way to hide anything,
//     said so, and the conversation ended in delete_feature on a body the
//     user only wanted out of the way. set_visible is that way.
//   * It deleted the gear as Extrusion1 then Extrusion2, so for one rebuild
//     Extrusion2 was a join onto nothing. A run of deletes goes last first.
//   * It read "Solid1" as "the motor" and spent three rounds measuring motor
//     plus boss. Every block now says what each body is made of.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_actions.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

class _Kernel implements PartKernel {
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
          double taperDeg, List<double> mat34) =>
      _mk(height);
  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      _mk(a.volume + b.volume);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

List<AiAction> _plate({String op = 'new', double y = 0}) => [
      const AiAction('create_sketch', {'plane': 'xy'}),
      AiAction('sketch_rect', {'x': 0, 'y': y, 'width': 60, 'height': 40}),
      AiAction('extrude', {'distance': 10, 'operation': op}),
    ];

void main() {
  Future<AppState> part() async {
    final app = AppState()..partKernel = _Kernel();
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m464_');
    await app.createNamedPart('Gear');
    return app;
  }

  group('set_visible', () {
    test('is an op, a change, and spelled out in the instructions', () {
      expect(kAiOps, contains('set_visible'));
      expect(kAiReadOnlyOps, isNot(contains('set_visible')));
      expect(kAiActionInstructions, contains('set_visible'));
      expect(kAiActionInstructions, contains('ausblenden'));
    });

    test('hides and shows a whole body without losing it', () async {
      final app = await part();
      await AiCad(app).run(_plate());
      await AiCad(app).run(_plate(op: 'new', y: 50));
      final p = app.currentPart!;
      final body = p.features.last.bodyName;
      final vol = p.features.last.solid!.volume;

      final hid = await AiCad(app).run([
        AiAction('set_visible', {'body': body, 'visible': false})
      ]);
      expect(hid.ok, isTrue, reason: hid.encode());
      expect(
          p.features.where((f) => f.bodyName == body).every((f) => !f.visible),
          isTrue);
      expect(p.features.length, 2, reason: 'hidden, not deleted');
      expect(p.features.last.solid!.volume, vol);
      expect(hid.encode(), contains('hidden'),
          reason: 'the state brief says the body is hidden');

      final shown = await AiCad(app).run([
        AiAction('set_visible', {'body': body, 'visible': 'true'})
      ]);
      expect(shown.ok, isTrue);
      expect(p.features.last.visible, isTrue);
    });

    test('one feature by name', () async {
      final app = await part();
      await AiCad(app).run(_plate());
      final r = await AiCad(app).run([
        const AiAction(
            'set_visible', {'feature': 'Extrusion1', 'visible': false})
      ]);
      expect(r.ok, isTrue);
      expect(app.currentPart!.features.single.visible, isFalse);
    });

    test('says what is wrong with a bad call', () async {
      final app = await part();
      await AiCad(app).run(_plate());
      final noFlag = await AiCad(app).run([
        const AiAction('set_visible', {'body': 'Solid1'})
      ]);
      expect(noFlag.ok, isFalse);
      final both = await AiCad(app).run([
        const AiAction('set_visible',
            {'body': 'Solid1', 'feature': 'Extrusion1', 'visible': false})
      ]);
      expect(both.ok, isFalse);
      final missing = await AiCad(app).run([
        const AiAction('set_visible', {'body': 'Solid9', 'visible': false})
      ]);
      expect(missing.ok, isFalse);
      expect(missing.outcomes.single.error, contains('Solid1'),
          reason: 'names the bodies that do exist');
    });
  });

  group('a run of deletes goes last first', () {
    test('reordered by timeline position, everything else in place', () async {
      final app = await part();
      await AiCad(app).run(_plate());
      await AiCad(app).run(_plate(op: 'join', y: 50));
      final p = app.currentPart!;
      final out = AiCad.deletesLastFirst(p, const [
        AiAction('describe_part', {}),
        AiAction('delete_feature', {'feature': 'Extrusion1'}),
        AiAction('delete_feature', {'feature': 'Extrusion2'}),
        AiAction('describe_shape', {}),
      ]);
      expect(out.map((a) => a.op).toList(), [
        'describe_part',
        'delete_feature',
        'delete_feature',
        'describe_shape'
      ]);
      expect(out[1].text('feature'), 'Extrusion2');
      expect(out[2].text('feature'), 'Extrusion1');
    });

    test('a delete naming nothing keeps the order the model gave', () async {
      final app = await part();
      await AiCad(app).run(_plate());
      final given = const [
        AiAction('delete_feature', {'feature': 'Nope'}),
        AiAction('delete_feature', {'feature': 'Extrusion1'}),
      ];
      final out = AiCad.deletesLastFirst(app.currentPart!, given);
      expect(out.map((a) => a.text('feature')), ['Nope', 'Extrusion1']);
    });

    test('the block deletes both and leaves nothing failing', () async {
      final app = await part();
      await AiCad(app).run(_plate());
      await AiCad(app).run(_plate(op: 'join', y: 50));
      final r = await AiCad(app).run(const [
        AiAction('delete_feature', {'feature': 'Extrusion1'}),
        AiAction('delete_feature', {'feature': 'Extrusion2'}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      expect(app.currentPart!.features, isEmpty);
      expect(r.encode(), isNot(contains('nowFailing')));
    });
  });

  group('every block says what each body is made of', () {
    test('features in build order, with what they did', () async {
      final app = await part();
      await AiCad(app).run(_plate());
      final r = await AiCad(app).run(_plate(op: 'join', y: 50));
      expect(r.ok, isTrue, reason: r.encode());
      final enc = r.encode();
      expect(enc, contains('bodyMakeup'));
      expect(enc,
          contains('Extrusion1 (extrude new) + Extrusion2 (extrude join)'));
    });
  });
}
