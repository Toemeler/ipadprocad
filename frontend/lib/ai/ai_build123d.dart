import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart'
    show PlatformException, MissingPluginException;

import '../app_state.dart';
import '../part_model.dart';
import '../part_render.dart' show fitPartView;
import 'ai_actions.dart';
import 'ai_build123d_client.dart';
import 'ai_cad.dart';

String build123dFingerprint(PartModel part, Iterable<String> bodies) {
  final features =
      part.features.where((f) => bodies.contains(f.bodyName)).toList();
  final sketches = {for (final f in features) ...f.sketchNames};
  return sha256
      .convert(utf8.encode(jsonEncode({
        'features': [for (final f in features) f.toJson()],
        'sketches': [
          for (final s in part.childSketches)
            if (sketches.contains(s.model.name))
              {
                'name': s.model.name,
                'plane': s.plane,
                if (s.face != null) 'frame': s.face!.frameJson(),
                'geometry': [
                  for (final g in s.model.geometry)
                    {'type': g.type, 'data': g.data}
                ],
                'constraints': [
                  for (final c in s.model.constraints) c.toJson()
                ],
              }
        ],
      })))
      .toString();
}

Map<String, dynamic> build123dContext(PartModel part, {int maxChars = 32000}) {
  final sources = <Map<String, dynamic>>[];
  final omitted = <String>[];
  for (final entry in part.aiBuild123d.entries) {
    final record = entry.value;
    final bodies = (record['bodies'] as List? ?? const []).cast<String>();
    if (!part.features.any((f) => bodies.contains(f.bodyName))) continue;
    final source = {
      'part': entry.key,
      'code': record['code'],
      'checks': record['checks'],
      'bodies': bodies,
      'inputs': record['inputs'],
      'replace': record['replace'],
      'matchesTimeline':
          record['fingerprint'] == build123dFingerprint(part, bodies),
      'frame': 'Python: Z up; app geometry: Y up',
    };
    final size = jsonEncode(source).length;
    if (size > maxChars) {
      omitted.add(entry.key);
    } else {
      maxChars -= size;
      sources.add(source);
    }
  }
  return {
    'models': sources,
    if (omitted.isNotEmpty) 'sourceOmittedForSize': omitted
  };
}

/// Worker checkpoints are display-only. A terminal, natively validated result
/// becomes an ordinary imported feature with source and immutable STEP assets.
class AiBuild123d {
  AiBuild123d(this.app, this.cad, {Build123dTransport? transport})
      : transport = transport ?? Build123dClient();
  final AppState app;
  final AiCad cad;
  final Build123dTransport transport;
  bool _cancelled = false;
  Completer<void>? _running;

  Future<void> abort() async {
    if (_running == null) return;
    _cancelled = true;
    transport.cancel();
    await _running!.future;
  }

  String _documentStamp(PartModel part) {
    final authoring = part.toJson()..remove('cam');
    return sha256
        .convert(utf8.encode(jsonEncode({
          'part': authoring,
          'sketches': [
            for (final sketch in part.childSketches)
              {
                'name': sketch.model.name,
                'geometry': [
                  for (final g in sketch.model.geometry)
                    {'type': g.type, 'data': g.data}
                ],
                'constraints': [
                  for (final c in sketch.model.constraints) c.toJson()
                ]
              },
          ],
        })))
        .toString();
  }

  Future<AiActionReport> run(List<AiAction> actions,
      {AiProgress? onStep}) async {
    if (actions.length != 1 || actions.single.op != 'build123d') {
      return AiActionReport(outcomes: const [
        AiActionOutcome.failed('build123d',
            'Use exactly one build123d action; send inspection/brief actions separately.')
      ]);
    }
    final part = app.currentPart;
    final tab = app.curTab;
    if (part == null || tab == null || !app.partKernel.available) {
      return AiActionReport(outcomes: const [
        AiActionOutcome.failed(
            'build123d', 'Open a part with the native CAD kernel available.')
      ], blocked: 'part');
    }
    if (_running != null) {
      return AiActionReport(outcomes: const [
        AiActionOutcome.failed('build123d', 'A build is already running.')
      ]);
    }
    _running = Completer<void>();
    _cancelled = false;
    final done = _running!;
    Directory? temporary;
    PartSnap? beforeCommit;
    var committed = false;
    var fatalRuntime = false;
    final candidates = <KernelSolid>[];
    var imported = <KernelSolid>[];
    try {
      final action = actions.single;
      final name = action.text('part');
      final code = action.args['code'];
      if (name == null ||
          name.length > 80 ||
          code is! String ||
          code.isEmpty ||
          utf8.encode(code).length > 100000) {
        throw const FormatException(
            'part must be 1..80 characters; code must be 1..100000 UTF-8 bytes');
      }
      List<String> names(Object? raw) {
        if (raw == null) return [];
        if (raw is! List ||
            raw.length > 16 ||
            raw.any((v) => v is! String) ||
            raw.toSet().length != raw.length) {
          throw const FormatException(
              'inputs/replace must be unique existing body names');
        }
        return raw.cast<String>();
      }

      final previous = part.aiBuild123d[name];
      final inputs = names(action.args['inputs'] ?? previous?['inputs']);
      final replace = names(action.args['replace'] ?? previous?['replace']);
      if (replace.length > 1 || replace.any((body) => !inputs.contains(body))) {
        throw const FormatException(
            'replace supports one body also listed in inputs');
      }
      final oldBodies = names(previous?['bodies']);
      final oldFeatures = names(previous?['features']);
      if (previous != null &&
          previous['fingerprint'] != build123dFingerprint(part, oldBodies)) {
        throw const FormatException(
            'This generated model was edited manually. Import the current '
            'body and modify it under a NEW part name; stale Python cannot replace it.');
      }
      final stamp = _documentStamp(part);
      bool current() =>
          !_cancelled &&
          identical(app.currentPart, part) &&
          app.curTab == tab &&
          stamp == _documentStamp(part);
      temporary = Directory.systemTemp.createTempSync('build123d-');
      final payloadInputs = <String, String>{};
      final inputBytes = <String, Uint8List>{};
      final savedInputs = previous?['inputAssets'] as Map? ?? const {};
      for (final body in inputs) {
        final savedPath = savedInputs[body];
        if (savedPath is String) {
          final bytes = app.aiStoredStepBytes(part, savedPath);
          if (bytes == null)
            throw FormatException('Original input for "$body" is missing');
          inputBytes[body] = bytes;
          payloadInputs[body] = base64Encode(bytes);
          continue;
        }
        final solid = currentBodySolid(part, body);
        if (solid == null)
          throw FormatException('Existing body "$body" is unavailable');
        final input = File('${temporary.path}/input.step');
        if (!app.partKernel.exportStepBodies([(body, solid)], input.path)) {
          throw FormatException('Cannot export body "$body" for modelling');
        }
        final bytes = input.readAsBytesSync();
        if (bytes.length > 12 * 1024 * 1024)
          throw const FormatException('Input body exceeds 12 MiB');
        inputBytes[body] = bytes;
        payloadInputs[body] = base64Encode(bytes);
      }
      if (replace.isNotEmpty && previous == null) {
        final head = part.features
            .where((f) =>
                f.bodyName == replace.single &&
                f.solid != null &&
                !f.consumedByJoin &&
                !f.rolledBack)
            .toList();
        if (head.length != 1 || part.eopAfter != kEopAtEnd) {
          throw const FormatException(
              'Replacement requires a whole active body and End of Part at the end');
        }
      }
      final checks =
          action.args['checks'] ?? previous?['checks'] ?? <String, dynamic>{};
      if (checks is! Map)
        throw const FormatException('checks must be an object');
      Map<String, dynamic>? completed;
      Uint8List? finalBytes;
      var previews = 0;
      await for (final event in transport.generate({
        'part': name,
        'code': code,
        'checks': checks,
        'inputs': payloadInputs,
      })) {
        if (!current())
          throw const FormatException(
              'Build cancelled or document changed; result was not applied');
        if (event['type'] == 'error') {
          fatalRuntime = event['fatal'] == true;
          throw FormatException(
              '${event['error']}\n${event['traceback'] ?? ''}');
        }
        if (completed != null)
          throw const FormatException('Worker sent events after completion');
        final encoded = event['step'];
        if (encoded is! String || encoded.length > 17 * 1024 * 1024) {
          throw const FormatException('Invalid geometry checkpoint');
        }
        final bytes = base64Decode(encoded);
        if (bytes.length > 12 * 1024 * 1024)
          throw const FormatException('Geometry checkpoint exceeds 12 MiB');
        final file = File('${temporary.path}/checkpoint.step')
          ..writeAsBytesSync(bytes);
        imported = app.partKernel.importStepSolids(file.path);
        if (imported.isEmpty ||
            imported.any((s) =>
                !s.volume.isFinite ||
                s.volume <= 0 ||
                s.shape?.valid != true)) {
          throw FormatException(
              'Native CAD rejected generated geometry: ${app.partKernel.lastError}');
        }
        if (replace.isNotEmpty && imported.length != 1) {
          throw const FormatException(
              'Replacing an existing body requires exactly one result solid');
        }
        if (event['type'] == 'complete') {
          completed = event;
          finalBytes = bytes;
          candidates.addAll(imported);
          imported = [];
        } else if (event['type'] == 'preview') {
          part.clearAiPreview();
          part.aiPreviewSolids.addAll(imported);
          imported = [];
          part.aiPreviewReplacesBodies.addAll({...oldBodies, ...replace});
          if (++previews == 1 && partExportBodies(part).isEmpty) {
            fitPartView(
                part.camera, part.aiPreviewSolids, const Size(800, 600));
          }
          onStep?.call('build123d', previews, 0);
          app.ai.modellingCheckpoint(
              event['label'] is String
                  ? (event['label'] as String).substring(
                      0, (event['label'] as String).length.clamp(0, 120))
                  : 'Building model',
              previews);
          app.aiNotify();
          // Give both Flutter and the native renderer a frame between features.
          await Future<void>.delayed(const Duration(milliseconds: 16));
        } else {
          throw const FormatException('Unknown worker checkpoint');
        }
      }
      if (completed == null ||
          finalBytes == null ||
          candidates.isEmpty ||
          !current()) {
        throw const FormatException(
            'Worker did not finish a model for this document');
      }
      final problems = completed['problems'];
      if (problems is! List || problems.any((p) => p is! String)) {
        throw const FormatException('Invalid worker validation report');
      }
      beforeCommit = app.aiSnapshot(part);
      final path = app.aiStoreGeneratedStep(part, finalBytes);
      // Remove only the prior generated result. Earlier native authoring and
      // unrelated bodies remain intact. Fingerprint guard excludes manual edits.
      for (final feature in part.features
          .where((f) => oldFeatures.contains(f.name))
          .toList()) {
        feature.disposeSolid();
        part.features.remove(feature);
      }
      final bodies = <String>[];
      final features = <String>[];
      for (var i = 0; i < candidates.length; i++) {
        final body = replace.isNotEmpty
            ? replace.single
            : i < oldBodies.length
                ? oldBodies[i]
                : part.nextSolidName();
        final feature = ExtrudeFeature(
            name: part.nextFeatureName('Build123d'),
            bodyName: body,
            sketchName: '',
            profiles: const [],
            output: replace.isNotEmpty ? 'join' : 'new')
          ..imported = true
          ..importPath = path
          ..importIndex = i
          ..solid = candidates[i]
          ..seq = part.nextSeq();
        part.appendFeature(feature);
        bodies.add(body);
        features.add(feature.name);
      }
      candidates.clear(); // Ownership transferred into the ordinary timeline.
      part.clearAiPreview();
      applyEndOfPart(part);
      recomputeAllFeatures(part, app.partKernel);
      part.aiBuild123d[name] = {
        'code': code,
        'checks': checks,
        'inputAssets': {
          for (final input in inputBytes.entries)
            input.key: app.aiStoreGeneratedStep(part, input.value)
        },
        'inputs': inputs,
        'replace': replace,
        'bodies': bodies,
        'features': features,
        'fingerprint': build123dFingerprint(part, bodies),
        'metrics': completed['metrics'],
        'problems': problems,
      };
      part.dirty = true;
      await app.savePart(tab);
      app.aiJournal(beforeCommit);
      committed = true;
      app.aiNotify();
      final inspection = await cad
          .run(const [AiAction('look', {}), AiAction('describe_shape', {})]);
      return AiActionReport(
          outcomes: [
            AiActionOutcome('build123d', detail: {
              'part': name,
              'bodies': bodies,
              'features': features,
              'liveCheckpoints': previews,
              'validation': completed['metrics'],
              'inspection': inspection.toJson(),
              'nativeValidation': {
                'valid': true,
                'solids': bodies.length,
                'volumeMm3': bodies.fold<double>(
                    0, (sum, b) => sum + currentBodySolid(part, b)!.volume)
              },
            })
          ],
          problems: problems.cast<String>(),
          state: inspection.state,
          images: inspection.images);
    } catch (error) {
      if (beforeCommit != null && !committed) {
        await app.aiRestore(part, beforeCommit);
      }
      return AiActionReport(
          outcomes: [AiActionOutcome.failed('build123d', error.toString())],
          reverted: beforeCommit != null && !committed,
          blocked: fatalRuntime ||
                  error is PlatformException ||
                  error is MissingPluginException
              ? 'localRuntime'
              : null);
    } finally {
      for (final solid in [...imported, ...candidates]) {
        solid.dispose();
      }
      part.clearAiPreview();
      app.aiNotify();
      if (temporary?.existsSync() ?? false)
        temporary!.deleteSync(recursive: true);
      _running = null;
      done.complete();
    }
  }
}
