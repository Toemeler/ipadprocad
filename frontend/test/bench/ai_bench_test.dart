// THE ASSISTANT BENCHMARK — does a change make the assistant better or worse?
//
// Every fix to the assistant before this was checked by unit tests that
// asserted on the PROMPT'S WORDING, and by the next bug report. Neither says
// whether a cable holder comes out right. This does: it runs the real
// controller loop, against a real provider, on the real OpenCascade kernel,
// for the requests users actually made (#82-#85), and scores the part the
// app measures at the end — never the model's account of it.
//
//   AI_BENCH=live   AI_BENCH_PROVIDER=deepseek AI_BENCH_MODEL=deepseek-flash
//   AI_BENCH_KEY=... PROTOTYPE_NATIVE_DIR=build/native
//   flutter test test/bench/ai_bench_test.dart
//
//   AI_BENCH=replay PROTOTYPE_NATIVE_DIR=build/native
//   flutter test test/bench/ai_bench_test.dart
//
// `replay` answers with each scenario's canned reply sequence instead of a
// model. It needs no key and is deterministic: it proves the harness, the
// ops and the checks, and is what CI runs on every change. `live` is what
// you run before and after a prompt or protocol change, and compare.
// AI_BENCH_ONLY=cup,cable-clip narrows the set; AI_BENCH_OUT=path.json writes
// the report there. Without AI_BENCH set, or without the kernel, it SKIPS.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_store.dart';
import 'package:prototype/ai/ai_trace.dart';
import 'package:prototype/ai/mesh_topology.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

/// Answers from a script instead of a model.
class _ReplayBackend implements AiBackend {
  _ReplayBackend(this.replies);
  final List<String> replies;
  var _next = 0;

  @override
  Future<AiCapabilities> capabilities(AiPreferences preferences) async =>
      AiCapabilities(
          provider: preferences.provider,
          label: 'Replay',
          available: true,
          supportsImages: false);
  @override
  Future<bool> hasKey(AiProvider provider) async => true;
  @override
  Future<void> saveKey(AiProvider provider, String key) async {}
  @override
  Future<void> removeKey(AiProvider provider) async {}
  @override
  Future<AiReply> respond(AiPreferences preferences, AiRequest request) async {
    // Past the end of the script the "model" says it is done, which is what
    // a finished turn looks like.
    final text = _next < replies.length ? replies[_next++] : 'Fertig.';
    return AiReply(text, 'replay');
  }

  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}

AiProvider _provider(String name) => AiProvider.values.firstWhere(
    (p) => p.name == name,
    orElse: () => throw ArgumentError('AI_BENCH_PROVIDER "$name" is not one '
        'of ${AiProvider.values.map((p) => p.name).join(", ")}'));

/// What the app measured about the finished part.
Map<String, dynamic> _measure(AppState app) {
  final p = app.currentPart!;
  var volume = 0.0, pieces = 0;
  double? x0, y0, z0, x1, y1, z1;
  for (final (name, _) in p.solidBodies()) {
    final s = currentBodySolid(p, name);
    if (s == null) continue;
    volume += s.volume;
    pieces += meshComponentCount(s.mesh);
    final pos = s.mesh.positions;
    for (var i = 0; i + 2 < pos.length; i += 3) {
      x0 = x0 == null || pos[i] < x0 ? pos[i] : x0;
      y0 = y0 == null || pos[i + 1] < y0 ? pos[i + 1] : y0;
      z0 = z0 == null || pos[i + 2] < z0 ? pos[i + 2] : z0;
      x1 = x1 == null || pos[i] > x1 ? pos[i] : x1;
      y1 = y1 == null || pos[i + 1] > y1 ? pos[i + 1] : y1;
      z1 = z1 == null || pos[i + 2] > z1 ? pos[i + 2] : z1;
    }
  }
  final size = x0 == null ? const [0.0, 0.0, 0.0] : [x1! - x0, y1! - y0!, z1! - z0!];
  final box = size[0] * size[1] * size[2];
  return {
    'bodies': p.solidBodies().length,
    'pieces': pieces,
    'volumeMm3': volume,
    'sizeMm': size,
    'fill': box > 0 ? volume / box : 0,
    'features': [for (final f in p.features) f.kind],
    'sick': [
      for (final f in p.features)
        if (!f.rolledBack && f.computeError != null) f.name
    ],
  };
}

/// Every check that failed, as a sentence. Empty is a pass.
List<String> _check(Map<String, dynamic> m, Map<String, dynamic> c) {
  final out = <String>[];
  final size = (m['sizeMm'] as List).cast<double>();
  if (c['bodies'] != null && m['bodies'] != c['bodies']) {
    out.add('bodies ${m['bodies']} != ${c['bodies']}');
  }
  if (c['pieces'] != null && m['pieces'] != c['pieces']) {
    out.add('pieces ${m['pieces']} != ${c['pieces']}');
  }
  if (c['noSick'] == true && (m['sick'] as List).isNotEmpty) {
    out.add('features that do not build: ${m['sick']}');
  }
  if (c['maxFill'] != null && (m['fill'] as double) > (c['maxFill'] as num)) {
    out.add('fills ${(m['fill'] as double).toStringAsFixed(2)} of its box — '
        'a slab, not the part (max ${c['maxFill']})');
  }
  final big = size.fold<double>(0, (a, b) => b > a ? b : a);
  if (c['sizeMax'] != null && big > (c['sizeMax'] as num)) {
    out.add('largest size ${big.toStringAsFixed(1)} > ${c['sizeMax']}');
  }
  if (c['sizeMin'] != null && big < (c['sizeMin'] as num)) {
    out.add('largest size ${big.toStringAsFixed(1)} < ${c['sizeMin']}');
  }
  final ranges = c['size'];
  if (ranges is Map) {
    for (final (i, axis) in const [(0, 'x'), (1, 'y'), (2, 'z')]) {
      final r = ranges[axis];
      if (r is List && (size[i] < (r[0] as num) || size[i] > (r[1] as num))) {
        out.add('$axis size ${size[i].toStringAsFixed(2)} outside $r');
      }
    }
  }
  final near = c['volumeNear'];
  if (near is Map) {
    final want = (near['value'] as num).toDouble();
    final tol = (near['tolerance'] as num).toDouble();
    final got = m['volumeMm3'] as double;
    if ((got - want).abs() > want * tol) {
      out.add('volume ${got.toStringAsFixed(0)} mm³, expected '
          '${want.toStringAsFixed(0)} ±${(tol * 100).toStringAsFixed(0)}%');
    }
  }
  if (c['minFeatures'] != null &&
      (m['features'] as List).length < (c['minFeatures'] as num)) {
    out.add('only ${(m['features'] as List).length} features');
  }
  final kinds = c['featureKinds'];
  if (kinds is List) {
    for (final k in kinds.cast<String>()) {
      final any = k.split('|');
      if (!(m['features'] as List).any(any.contains)) {
        out.add('no ${any.join(" or ")} feature');
      }
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final mode = env['AI_BENCH'];
  final kernel = OcctPartKernel();
  final skip = mode == null
      ? 'set AI_BENCH=replay or AI_BENCH=live to run the assistant benchmark'
      : !kernel.available
          ? 'the benchmark needs the real kernel — set PROTOTYPE_NATIVE_DIR'
          : (mode == 'live' && (env['AI_BENCH_KEY'] ?? '').isEmpty)
              ? 'AI_BENCH=live needs AI_BENCH_KEY'
              : false;
  final spec = jsonDecode(
          File('test/bench/scenarios.json').readAsStringSync())
      as Map<String, dynamic>;
  final only = (env['AI_BENCH_ONLY'] ?? '')
      .split(',')
      .where((s) => s.trim().isNotEmpty)
      .toSet();
  final scenarios = [
    for (final s in (spec['scenarios'] as List).cast<Map<String, dynamic>>())
      if (only.isEmpty || only.contains(s['id'])) s
  ];
  final results = <Map<String, dynamic>>[];

  for (final s in scenarios) {
    test('${s['id']} (#${s['issue']})', () async {
      final live = mode == 'live';
      final backend = live
          ? DeviceAiBackend(keyReader: (_) async => env['AI_BENCH_KEY'])
          : _ReplayBackend((s['replay'] as List).cast<String>());
      final controller = AiController(backend: backend);
      final app = AppState(ai: controller)..partKernel = kernel;
      final dir = Directory.systemTemp.createTempSync('prototype_bench_');
      app.docsDirForTest = dir;
      await app.createNamedPart('Bench');
      await controller.initialize(AiStore(Directory('${dir.path}/ai')));
      await controller.configure(
          provider: live
              ? _provider(env['AI_BENCH_PROVIDER'] ?? 'deepseek')
              : AiProvider.deepseek,
          model: live ? (env['AI_BENCH_MODEL'] ?? 'deepseek-flash') : 'replay',
          allowEdits: true);
      final setup = [
        for (final a in (s['setup'] as List? ?? const []).cast<Map>())
          AiAction(a['op'] as String,
              {for (final e in a.entries) if (e.key != 'op') '${e.key}': e.value})
      ];
      if (setup.isNotEmpty) {
        final r = await AiCad(app).run(setup);
        expect(r.ok, isTrue, reason: 'setup: ${r.encode()}');
      }
      AiTrace.clear();
      final clock = Stopwatch()..start();
      final answers = (s['answers'] as List? ?? const []).cast<String>();
      var said = 0;
      controller.updateDraft(s['prompt'] as String);
      await controller.send();
      // A model that asks what the part is for gets the answer a user gave.
      while (said < answers.length &&
          controller.currentSession.messages.isNotEmpty &&
          controller.currentSession.messages.last.role == 'assistant' &&
          aiReplyIsQuestion(controller.currentSession.messages.last.text)) {
        controller.updateDraft(answers[said++]);
        await controller.send();
      }
      clock.stop();
      final events = AiTrace.events;
      var input = 0, output = 0, reasoning = 0;
      for (final e in events.where((e) => e.kind == 'usage')) {
        input += (e.data['input'] as num?)?.toInt() ?? 0;
        output += (e.data['output'] as num?)?.toInt() ?? 0;
        reasoning += (e.data['reasoning'] as num?)?.toInt() ?? 0;
      }
      final m = _measure(app);
      final failures = _check(m, (s['checks'] as Map).cast<String, dynamic>());
      final result = {
        'id': s['id'],
        'issue': s['issue'],
        'mode': mode,
        if (live) 'provider': env['AI_BENCH_PROVIDER'] ?? 'deepseek',
        if (live) 'model': env['AI_BENCH_MODEL'] ?? 'deepseek-flash',
        'pass': failures.isEmpty,
        'failures': failures,
        'rounds': events.where((e) => e.kind == 'round').length,
        'blocks': events.where((e) => e.kind == 'actions.report').length,
        'rolledBack': events.where((e) => e.kind == 'cad.reverted').length,
        'seconds': clock.elapsedMilliseconds / 1000,
        'tokens': {'input': input, 'output': output, 'reasoning': reasoning},
        'part': m,
        'error': controller.currentSession.errorCode,
      };
      results.add(result);
      // Printed per scenario so a long live run shows progress.
      // ignore: avoid_print
      print('BENCH ${jsonEncode(result)}');
      expect(failures, isEmpty, reason: jsonEncode(result));
    }, skip: skip, timeout: const Timeout(Duration(minutes: 30)));
  }

  tearDownAll(() {
    if (results.isEmpty) return;
    final passed = results.where((r) => r['pass'] == true).length;
    final summary = {
      'at': DateTime.now().toUtc().toIso8601String(),
      'mode': mode,
      'passed': passed,
      'of': results.length,
      'rounds': results.fold<int>(0, (a, r) => a + (r['rounds'] as int)),
      'seconds':
          results.fold<double>(0, (a, r) => a + (r['seconds'] as double)),
      'scenarios': results,
    };
    final out = env['AI_BENCH_OUT'];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(summary));
    }
    // ignore: avoid_print
    print('BENCH SUMMARY $passed/${results.length} passed, '
        '${summary['rounds']} rounds, '
        '${(summary['seconds'] as double).toStringAsFixed(1)} s');
  });
}
