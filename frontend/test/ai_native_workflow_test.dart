import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_program_source.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

String _program({int height = 10, bool say = false}) => '```cad\n${jsonEncode({
          'title': 'Building adapter',
          'part': 'adapter',
          'vars': {'width': 40, 'height': height, 'depth': 'width/2'},
          'steps': [
            {
              'box': {
                'size': ['width', 'height', 'depth'],
                'base': [0, 0, 0]
              }
            }
          ],
          'expect': {
            'size': [40, 10, 20],
            'pieces': 1
          },
          if (say) 'say': 'Built correctly.',
        })}\n```';

const _done =
    '```cad\n{"title":"Checked adapter","say":"Adapter checked."}\n```';

class _Backend implements AiBackend {
  _Backend(this.answer);
  final Future<AiReply> Function(AiRequest, int) answer;
  final requests = <AiRequest>[];
  @override
  Future<AiReply> respond(AiPreferences p, AiRequest r) {
    requests.add(r);
    return answer(r, requests.length - 1);
  }

  @override
  Future<AiCapabilities> capabilities(AiPreferences p) async => AiCapabilities(
      provider: p.provider,
      available: true,
      supportsImages: true,
      maxInputBytes: 1000000,
      label: 'test');
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<bool> hasKey(AiProvider p) async => true;
  @override
  Future<void> saveKey(AiProvider p, String key) async {}
  @override
  Future<void> removeKey(AiProvider p) async {}
  @override
  Future<AiAttachment?> pasteImage() async => null;
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  final skip = kernel.available ? false : 'needs PROTOTYPE_NATIVE_DIR';

  Future<(AppState, AiCad)> fresh({_Backend? backend}) async {
    final ai = AiController(backend: backend)..initializeInMemory();
    final app = AppState(ai: ai)..partKernel = kernel;
    final dir = Directory.systemTemp.createTempSync('native_workflow_');
    app.docsDirForTest = dir;
    addTearDown(() async {
      ai.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await app.createNamedPart('Adapter');
    // Existing saved native programs still have a direct executor. Exercise
    // that compatibility path explicitly; new desktop sessions use build123d.
    app.ai.build123dMode = false;
    return (app, AiCad(app)..wantsImages = false);
  }

  test('local build123d mode offers Python and reviews its built result',
      () async {
    final backend = _Backend((r, i) async => AiReply(
        i == 0
            ? '```cad\n${jsonEncode({
                    "title": "Bracket",
                    "say": "Built!",
                    "actions": [
                      {
                        "op": "build123d",
                        "part": "bracket",
                        "code":
                            "import build123d as bd\nresult=bd.Box(40,30,20)"
                      }
                    ]
                  })}\n```'
            : _done,
        'test'));
    final (app, _) = await fresh(backend: backend);
    app.ai.build123dMode = true;
    app.ai.actionRunner =
        (actions, {onStep}) async => AiActionReport(outcomes: [
              for (final a in actions) AiActionOutcome(a.op)
            ], state: {
              'sizeMm': [40, 20, 30]
            }, images: [
              AiAttachment.fromBytes(
                  name: 'built.png',
                  bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]))
            ]);
    app.ai.viewReader = null;
    app.ai.updateDraft('Make a bracket');
    await app.ai.send();
    expect(backend.requests, hasLength(2));
    expect(backend.requests.first.instructions,
        contains('REAL build123d 0.11.1 Python'));
    expect(backend.requests.first.instructions, contains('publish'));
    expect(backend.requests.last.messages.last.text,
        contains('Review this built result'));
    expect(backend.requests.last.messages.last.attachments.single.name,
        'built.png');
    expect(app.ai.currentSession.messages.last.text, 'Adapter checked.');
  }, skip: skip);

  test('explicit legacy native programs are reviewed before say', () async {
    final backend = _Backend(
        (r, i) async => AiReply(i == 0 ? _program(say: true) : _done, 'test'));
    final (app, _) = await fresh(backend: backend);
    // Render delivery is tested independently of the platform's GPU surface.
    app.ai.actionRunner =
        (actions, {onStep}) async => AiActionReport(outcomes: [
              for (final a in actions) AiActionOutcome(a.op)
            ], state: {
              'sizeMm': [40, 10, 20]
            }, images: [
              AiAttachment.fromBytes(
                  name: 'built.png',
                  bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]))
            ]);
    app.ai.updateDraft('Make an adapter 40 x 10 x 20 mm');
    await app.ai.send();
    expect(backend.requests, hasLength(2));
    expect(backend.requests.first.instructions, contains('loft {plane:'));
    expect(backend.requests.first.instructions, contains('BUILD -> INSPECT'));
    final review = backend.requests.last.messages.last;
    expect(review.role, 'tool');
    expect(review.attachments.single.name, 'built.png');
    expect(review.text, contains('Review this built result'));
    expect(app.ai.currentSession.messages.last.text, 'Adapter checked.');
  }, skip: skip);

  test('measured failure is repaired and the repaired part is reviewed',
      () async {
    final backend = _Backend((r, i) async => AiReply(
        i == 0
            ? _program(height: 8, say: true)
            : i == 1
                ? _program(say: true)
                : _done,
        'test'));
    final (app, cad) = await fresh(backend: backend);
    app.ai.actionRunner = cad.run;
    app.ai.viewReader = null;
    app.ai.updateDraft('Make an adapter 40 x 10 x 20 mm');
    await app.ai.send();
    expect(backend.requests, hasLength(3));
    expect(backend.requests[1].messages.last.text, contains('problems'));
    expect(
        backend.requests[2].messages.last.text, isNot(contains('"problems":')));
    final p = app.currentPart!;
    expect(p.solidBodies(), hasLength(1));
    final solid = currentBodySolid(p, p.solidBodies().single.$1)!;
    expect(solid.volume, closeTo(8000, 0.01));
    expect(solid.shape!.valid, isTrue);
    expect(app.ai.currentSession.messages.last.text, 'Adapter checked.');
  }, skip: skip);

  test('source survives save/load, remains symbolic, and append edits use it',
      () async {
    final (app, cad) = await fresh();
    final result = await cad.run(parseAiActions(_program()).actions);
    expect(result.ok, isTrue, reason: result.encode());
    final p = app.currentPart!;
    final saved = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
    final reopened = PartModel('Adapter')..loadJson(saved);
    expect(reopened.aiPrograms, p.aiPrograms);
    final source = p.aiPrograms['adapter']!['source'] as Map;
    expect((source['vars'] as Map)['depth'], 'width/2');
    expect((((source['steps'] as List).first as Map)['box'] as Map)['size'],
        ['width', 'height', 'depth']);
    expect(
        aiProgramSourceMatches(p, 'adapter', p.aiPrograms['adapter']!), isTrue);
    // A new executor has no in-memory program state.
    final edit = await (AiCad(app)..wantsImages = false).run(const [
      AiAction('program', {
        'part': 'adapter',
        'steps': [
          {
            'hole': {
              'at': [0, 10, 0],
              'into': '-y',
              'd': 4
            }
          },
        ],
        'expect': {
          'holes': [
            {'d': 4, 'count': 1}
          ]
        }
      }),
    ]);
    expect(edit.ok, isTrue, reason: edit.encode());
    expect(edit.problems, isEmpty, reason: edit.encode());
    expect(p.solidBodies(), hasLength(1));
    expect(currentBodySolid(p, p.solidBodies().single.$1)!.volume,
        closeTo(8000 - 40 * 3.141592653589793, 0.1));
    expect(((p.aiPrograms['adapter']!['source'] as Map)['steps'] as List),
        hasLength(2));
  }, skip: skip);

  test('timeline edits invalidate source and cannot be silently overwritten',
      () async {
    final (app, cad) = await fresh();
    await cad.run(parseAiActions(_program()).actions);
    final p = app.currentPart!;
    final edit = await cad.run(const [
      AiAction('edit_feature', {'feature': 'p_adapter_2', 'distance': 12}),
    ]);
    expect(edit.ok, isTrue, reason: edit.encode());
    final context = aiProgramContext(p);
    expect((context['programs'] as List).single['matchesTimeline'], isFalse);
    final replace = await cad.run(parseAiActions(_program()).actions);
    expect(replace.ok, isFalse);
    expect(replace.encode(), contains('edited in the timeline'));
    expect(currentBodySolid(p, p.solidBodies().single.$1)!.volume,
        closeTo(9600, 0.1));
  }, skip: skip);

  test('source and geometry undo together; failed rebuild restores both',
      () async {
    final (app, cad) = await fresh();
    await cad.run(parseAiActions(_program()).actions);
    final p = app.currentPart!;
    final before = jsonEncode(p.aiPrograms);
    final failed = await cad.run(const [
      AiAction('program', {
        'part': 'adapter',
        'steps': [
          {
            'box': {
              'size': [40, 10, 20],
              'base': [0, 0, 0]
            }
          },
          {'unknown_feature': {}},
        ],
      })
    ]);
    expect(failed.reverted, isTrue);
    expect(jsonEncode(p.aiPrograms), before);
    expect(currentBodySolid(p, p.solidBodies().single.$1)!.volume,
        closeTo(8000, 0.1));
    await app.undoPart();
    expect(p.aiPrograms, isEmpty);
    expect(p.features, isEmpty);
    await app.redoPart();
    expect(jsonEncode(p.aiPrograms), before);
    expect(p.solidBodies(), hasLength(1));
  }, skip: skip);

  test('aborting a streamed preview restores the pre-stream document',
      () async {
    final (app, cad) = await fresh();
    await cad.streamProgram('preview', {
      'w': 20
    }, [
      {
        'box': {
          'size': ['w', 10, 20],
          'base': [0, 0, 0]
        }
      },
    ]);
    expect(app.currentPart!.features, isNotEmpty);
    await cad.abortStreamProgram();
    expect(app.currentPart!.features, isEmpty);
    expect(app.currentPart!.aiPrograms, isEmpty);
    final built = await cad.run(parseAiActions(_program()).actions);
    expect(built.ok, isTrue, reason: built.encode());
    expect(app.currentPart!.solidBodies(), hasLength(1));
  }, skip: skip);

  test('provider failure cleans up streamed work before returning', () async {
    final backend = _Backend((r, i) async {
      r.onText!(_program());
      throw const AiException('provider');
    });
    final (app, _) = await fresh(backend: backend);
    app.ai.updateDraft('Make an adapter');
    await app.ai.send();
    expect(app.currentPart!.features, isEmpty);
    expect(app.currentPart!.aiPrograms, isEmpty);
    expect(app.ai.anyRequestBusy, isFalse);
  }, skip: skip);

  test('cancellation restores the preview before an immediate new request',
      () async {
    final entered = Completer<void>();
    final cancelledReply = Completer<AiReply>();
    final backend = _Backend((r, i) async {
      if (i == 0) {
        r.onText!(_program());
        entered.complete();
        return cancelledReply.future;
      }
      return AiReply(i == 1 ? _program(say: true) : _done, 'test');
    });
    final (app, _) = await fresh(backend: backend);
    app.ai.updateDraft('Make an adapter');
    final first = app.ai.send();
    await entered.future;
    app.ai.cancel();
    app.ai.updateDraft('Make the replacement adapter');
    await app.ai.send();
    cancelledReply.complete(const AiReply('Late cancelled answer', 'test'));
    await first;
    final p = app.currentPart!;
    expect(p.solidBodies(), hasLength(1));
    expect(p.aiPrograms.keys, ['adapter']);
    expect(app.ai.currentSession.messages.last.text, 'Adapter checked.');
    expect(app.ai.anyRequestBusy, isFalse);
  }, skip: skip);

  test('combined assumption actions and a program both execute', () {
    final b = parseAiActions('```cad\n${jsonEncode({
          'part': 'plate',
          'actions': [
            {
              'op': 'brief_note',
              'text': 'Assumed 2 mm wall',
              'kind': 'assumption'
            }
          ],
          'steps': [
            {
              'box': {
                'size': [20, 2, 20],
                'base': [0, 0, 0]
              }
            }
          ],
        })}\n```');
    expect(b.parseError, isNull);
    expect(b.actions.map((a) => a.op), ['brief_note', 'program']);
  });

  test('loft makes an editable, valid transition with the expected volume',
      () async {
    final (app, cad) = await fresh();
    final r = await cad.run(const [
      AiAction('program', {
        'part': 'transition',
        'steps': [
          {
            'loft': {
              'plane': 'xz',
              'ruled': true,
              'sections': [
                {
                  'at': 0,
                  'outline': {
                    'rect': [-20, -20, 20, 20]
                  }
                },
                {
                  'at': 30,
                  'outline': {
                    'rect': [-10, -10, 10, 10]
                  }
                },
              ]
            }
          },
        ],
        'expect': {
          'size': [40, 30, 40],
          'pieces': 1,
          'volume': 28000
        },
      })
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(r.problems, isEmpty, reason: r.encode());
    final p = app.currentPart!;
    expect(p.features.single, isA<LoftFeature>());
    expect(p.childSketches, hasLength(2));
    expect(currentBodySolid(p, p.solidBodies().single.$1)!.volume,
        closeTo(28000, 1));
  }, skip: skip);

  test('unknown and unmeasurable checks cannot silently pass', () async {
    final (app, cad) = await fresh();
    final block = parseAiActions(_program()).actions;
    final a = block.last;
    final r = await cad.run([
      block.first,
      AiAction('program', {
        ...a.args,
        'expect': {
          'holeSpacing': 20,
          'size': [40, 10]
        }
      }),
    ]);
    expect(r.ok, isTrue, reason: 'valid part stays available for repair');
    expect(r.problems.join(), contains('supported expectation'));
    expect(r.problems.join(), contains('size specification'));
  }, skip: skip);
}
