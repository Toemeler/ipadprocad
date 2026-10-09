import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_build123d.dart';
import 'package:prototype/ai/ai_build123d_client.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart' show visibleSolids;

class Transport implements Build123dTransport {
  Transport(this.script);
  final Stream<Map<String, dynamic>> Function(Map<String, dynamic>) script;
  final jobs = <Map<String, dynamic>>[];
  void Function()? onCancel;
  @override
  Stream<Map<String, dynamic>> generate(Map<String, dynamic> job) {
    jobs.add(job);
    return script(job);
  }

  @override
  void cancel() => onCancel?.call();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  final skip = kernel.available ? false : 'needs PROTOTYPE_NATIVE_DIR';
  final step = base64Encode(
      File('test/fixtures/build123d/bracket.step').readAsBytesSync());
  Map<String, dynamic> event(String type, {List<String> problems = const []}) =>
      {
        'type': type,
        'step': step,
        'label': 'Bracket',
        'metrics': {
          'valid': true,
          'solids': 1,
          'size_mm': [40, 30, 20]
        },
        if (type == 'complete') 'problems': problems,
      };
  AiAction build(
          {String name = 'bracket', Map<String, dynamic> extra = const {}}) =>
      AiAction('build123d', {
        'part': name,
        'code':
            'import build123d as bd\nresult=bd.Box(40,30,20)\npublish(result,"Body")',
        ...extra
      });
  Future<(AppState, AiCad)> fresh() async {
    final ai = AiController()..initializeInMemory();
    final app = AppState(ai: ai)..partKernel = kernel;
    final dir = Directory.systemTemp.createTempSync('build123d-test-');
    app.docsDirForTest = dir;
    addTearDown(() {
      ai.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await app.createNamedPart('Bracket');
    return (app, AiCad(app)..wantsImages = false);
  }

  test('WASM STEP is live transient geometry, then one undoable model',
      () async {
    final (app, cad) = await fresh();
    final p = app.currentPart!;
    final transport = Transport((_) async* {
      yield event('preview');
      expect(p.aiPreviewSolids, hasLength(1));
      expect(visibleSolids(app, p), hasLength(1));
      expect(p.features, isEmpty);
      expect(partExportBodies(p), isEmpty);
      expect(p.toJson().containsKey('aiPreviewSolids'), isFalse);
      yield event('complete');
    });
    final report =
        await AiBuild123d(app, cad, transport: transport).run([build()]);
    expect(report.ok, isTrue, reason: report.encode());
    expect(p.aiPreviewSolids, isEmpty);
    expect(p.features, hasLength(1));
    final solid = currentBodySolid(p, p.bodyNames.single)!;
    expect(solid.volume, closeTo(22926.017763, 0.001));
    final bbox = solid.shape!.bbox()!;
    expect(bbox[3] - bbox[0], closeTo(40, 0.001));
    expect(bbox[4] - bbox[1], closeTo(20, 0.001));
    expect(bbox[5] - bbox[2], closeTo(30, 0.001));
    expect((build123dContext(p)['models'] as List).single['matchesTimeline'],
        isTrue);
    await app.undoPart();
    expect(p.features, isEmpty);
    expect(p.aiBuild123d, isEmpty);
    await app.redoPart();
    expect(p.features, hasLength(1));
    expect(currentBodySolid(p, p.bodyNames.single)!.volume,
        closeTo(22926.017763, 0.001));
    expect(p.aiBuild123d['bracket']!['code'], contains('build123d'));
  }, skip: skip);
  test('Python failure after preview preserves existing model and source',
      () async {
    final (app, cad) = await fresh();
    final good = Transport((_) async* {
      yield event('complete');
    });
    expect((await AiBuild123d(app, cad, transport: good).run([build()])).ok,
        isTrue);
    final before = jsonEncode(app.currentPart!.toJson());
    final bad = Transport((_) async* {
      yield event('preview');
      yield {
        'type': 'error',
        'error': 'fillet failed',
        'traceback': 'model.py line 12'
      };
    });
    final report = await AiBuild123d(app, cad, transport: bad).run([build()]);
    expect(report.ok, isFalse);
    expect(report.encode(), contains('model.py line 12'));
    expect(app.currentPart!.aiPreviewSolids, isEmpty);
    expect(jsonEncode(app.currentPart!.toJson()), before);
  }, skip: skip);
  test(
      'replace preserves native history and revisions reuse original input geometry',
      () async {
    final (app, cad) = await fresh();
    final native = await cad.run(const [
      AiAction('program', {
        'part': 'base',
        'steps': [
          {
            'box': {
              'size': [40, 20, 30],
              'base': [0, 0, 0]
            }
          }
        ]
      })
    ]);
    expect(native.ok, isTrue, reason: native.encode());
    final p = app.currentPart!;
    final body = p.bodyNames.single;
    final original = currentBodySolid(p, body)!.volume;
    final transport = Transport((_) async* {
      yield event('complete');
    });
    final engine = AiBuild123d(app, cad, transport: transport);
    final report = await engine.run([
      build(extra: {
        'inputs': [body],
        'replace': [body]
      })
    ]);
    expect(report.ok, isTrue, reason: report.encode());
    expect(partExportBodies(p), hasLength(1));
    expect(p.features, hasLength(2));
    expect(p.features.first.consumedByJoin, isTrue);
    expect(currentBodySolid(p, body)!.volume, lessThan(original));
    final input = transport.jobs.single['inputs'];
    expect((await engine.run([build()])).ok, isTrue);
    expect(transport.jobs.last['inputs'], input);
    expect(p.features, hasLength(2));
    final sourceFingerprint = p.aiBuild123d['bracket']!['fingerprint'];
    p.childSketches.single.face = planeFrame('xy');
    expect(build123dFingerprint(p, [body]), isNot(sourceFingerprint));
    final stale = await engine.run([build()]);
    expect(stale.ok, isFalse,
        reason: 'upstream sketch edits cannot be overwritten');
    await app.undoPart();
    await app.undoPart();
    expect(p.features, hasLength(1));
    expect(currentBodySolid(p, body)!.volume, closeTo(original, 0.001));
  }, skip: skip);
  test('manual edits prevent stale replay without overwriting the user',
      () async {
    final (app, cad) = await fresh();
    final transport = Transport((_) async* {
      yield event('complete');
    });
    final engine = AiBuild123d(app, cad, transport: transport);
    expect((await engine.run([build()])).ok, isTrue);
    final p = app.currentPart!;
    p.features.single.name = 'Manually renamed';
    final report = await engine.run([build()]);
    expect(report.ok, isFalse);
    expect(report.encode(), contains('edited manually'));
    expect(p.features.single.name, 'Manually renamed');
    expect(transport.jobs, hasLength(1));
  }, skip: skip);
  test('user edit during preview is retained and prevents commit', () async {
    final (app, cad) = await fresh();
    final p = app.currentPart!;
    final transport = Transport((_) async* {
      yield event('preview');
      p.solidN = 42;
      yield event('complete');
    });
    expect(
        (await AiBuild123d(app, cad, transport: transport).run([build()])).ok,
        isFalse);
    expect(p.features, isEmpty);
    expect(p.solidN, 42);
    expect(p.aiPreviewSolids, isEmpty);
  }, skip: skip);
  test('cancel removes only preview and terminates the active execution',
      () async {
    final (app, cad) = await fresh();
    final stream = StreamController<Map<String, dynamic>>();
    final transport = Transport((_) => stream.stream);
    transport.onCancel = () {
      stream.add({'type': 'error', 'error': 'cancelled'});
      unawaited(stream.close());
    };
    final engine = AiBuild123d(app, cad, transport: transport);
    final run = engine.run([build()]);
    stream.add(event('preview'));
    for (var i = 0; i < 100 && app.currentPart!.aiPreviewSolids.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(app.currentPart!.aiPreviewSolids, hasLength(1));
    await engine.abort();
    expect((await run).ok, isFalse);
    expect(app.currentPart!.features, isEmpty);
    expect(app.currentPart!.aiPreviewSolids, isEmpty);
  }, skip: skip);
  test('measured requirement failures reach the AI for repair', () async {
    final (app, cad) = await fresh();
    final transport = Transport((_) async* {
      yield event('complete', problems: ['height required 25, measured 20']);
    });
    final report =
        await AiBuild123d(app, cad, transport: transport).run([build()]);
    expect(report.ok, isTrue);
    expect(report.problems, hasLength(1));
    expect(report.problems.single, contains('height required'));
  }, skip: skip);
}
