// #57 / #64 — "the preview images in windows are still not made with flutter
// gpu 3d renderer".
//
// Filed twice, three days apart, which is the shape of a report that was
// understood and not acted on. It is M82's own rule, not a new one:
//
//   "M82 — ONE ENGINE. The still is produced by the same RealityKit renderer
//    that draws the live 3D viewport, so a body looks on the card exactly as
//    it looks in the viewport. The Dart CPU painter remains as the FALLBACK
//    for every place RealityKit is unavailable."
//
// That was written when there were exactly two renderers, and "every place
// RealityKit is unavailable" was the same set as "every place the CPU painter
// draws the viewport". M372 broke the equality by giving Windows, Linux and
// macOS a third renderer — flutter_scene on Flutter GPU — and the still did
// not follow it. The reporter's own log says both halves in one file:
//
//   3d: renderer: flutter_scene (Flutter GPU)
//
// the viewport on the GPU, and the card still painted by `paintPartSolids`.
// Two renderers that disagree about depth, lighting and silhouette, drawing
// the same part.
//
// WHAT THIS FILE CAN PIN, honestly, on a host with no GPU and no RealityKit:
// the ORDER. `AppState.stillEngines` is the preference list the two preview
// writers walk, and the bug is that Flutter GPU was not in it — not that any
// particular one of them draws here. So the list is the subject: what is in
// it, what order it is in, that the walk stops at the first engine that
// answers, and that each engine declines rather than throwing, which is what
// makes falling through to the painter safe.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_view/gpu_view.dart';
import 'package:prototype/app_state.dart';

/// An engine that answers with [bytes] and records that it was asked.
StillEngine _engine(String name, Uint8List? bytes, List<String> asked) => (
      name: name,
      render: ({
        required Map<String, dynamic> scene,
        required Map<String, dynamic> camera,
        required int width,
        required int height,
      }) async {
        asked.add(name);
        return bytes;
      },
    );

void main() {
  final original = AppState.stillEngines;
  tearDown(() {
    AppState.stillEngines = original;
    GpuView.setSupportedForTest(false);
  });

  group('THE REPORT: which engines may draw a gallery still', () {
    test('Flutter GPU is one of them', () {
      expect(AppState.stillEngines.map((e) => e.name), contains('gpu'),
          reason: 'the whole report: the viewport went to the GPU at M372 and '
              'the card stayed on the CPU painter');
    });

    test('and RealityKit is still preferred where there is one', () {
      // Not a tie to break on merit: on the iPad the still and the viewport
      // are both RealityKit, and M82 is that they are the same renderer.
      final names = AppState.stillEngines.map((e) => e.name).toList();
      expect(names.indexOf('reality'), 0);
      expect(names.indexOf('gpu'), 1);
    });
  });

  group('the walk down the list', () {
    test('stops at the first engine that produces a still', () async {
      final asked = <String>[];
      AppState.stillEngines = [
        _engine('first', Uint8List.fromList([1, 2, 3]), asked),
        _engine('second', Uint8List.fromList([4]), asked),
      ];
      expect(await AppState.renderStillForTest(), [1, 2, 3]);
      expect(asked, ['first'], reason: 'the second is never asked');
    });

    test('falls through an engine that is not here', () async {
      // `null` is how every engine says "not this build" — RealityKit off
      // iOS, Flutter GPU on a build without the project switch. The fall
      // through has to reach the next one rather than stop.
      final asked = <String>[];
      AppState.stillEngines = [
        _engine('absent', null, asked),
        _engine('present', Uint8List.fromList([9]), asked),
      ];
      expect(await AppState.renderStillForTest(), [9]);
      expect(asked, ['absent', 'present']);
    });

    test('and an engine that answers EMPTY is not a still either', () async {
      // The old call site guarded on `isNotEmpty` as well as null, because a
      // zero-byte PNG is a renderer that failed politely. Keep that: writing
      // it would leave a card with an empty file that never repairs.
      final asked = <String>[];
      AppState.stillEngines = [
        _engine('empty', Uint8List(0), asked),
        _engine('real', Uint8List.fromList([7]), asked),
      ];
      expect(await AppState.renderStillForTest(), [7]);
      expect(asked, ['empty', 'real']);
    });

    test('nothing at all is null, and the caller paints', () async {
      final asked = <String>[];
      AppState.stillEngines = [_engine('none', null, asked)];
      expect(await AppState.renderStillForTest(), isNull,
          reason: 'which is what sends _writePartPreview to paintPartSolids');
    });
  });

  group('the GPU engine declines instead of throwing', () {
    // The same promise RealityThumbnailer makes and m82_thumb_engine_test
    // pins for it. It is what lets the list above be a straight line.
    test('when this build has no Flutter GPU', () async {
      GpuView.setSupportedForTest(false);
      expect(
          await GpuThumbnailer.render(
              scene: const {}, camera: const {}, width: 380, height: 240),
          isNull);
    });

    test('and when it is claimed but cannot encode a pass', () async {
      // The probe answers "is Flutter GPU switched on in this build", which
      // is not "can this driver render off-screen". A host test is exactly
      // that machine: supported by the flag, no GPU behind it. It must come
      // back null — a still is decoration and must never take a save with it.
      GpuView.setSupportedForTest(true);
      expect(
          await GpuThumbnailer.render(
              scene: const {}, camera: const {}, width: 380, height: 240),
          isNull);
    });

    test('and a zero-sized request is declined before any of that', () async {
      GpuView.setSupportedForTest(true);
      expect(
          await GpuThumbnailer.render(
              scene: const {}, camera: const {}, width: 0, height: 240),
          isNull);
    });
  });
}
