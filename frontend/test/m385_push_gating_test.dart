// M385 — nothing goes over the render channel that the far side already has.
//
// Issue #15: "Es ruckelt sehr und die App ist sehr langsam und unbrauchbar …
// panning und Orbit und Zoom sollen in jedem Fall smooth sein." The bundle
// says where it went. `rv.setCamera` — eight doubles — averaged 447 ms across
// the session and peaked at 5454 ms, LONGER than the 5444 ms `setScene` it was
// queued behind, and the raw pointer stream has a 2832 ms hole in the middle
// of a two-finger drag ending in `lost 2 contact(s)`: iOS taking the fingers
// away from an app that had stopped answering.
//
// The stall itself is native (a full outline re-stroke ran inside every camera
// push; see RealityPartView.refreshOutlines) and is pinned by the macOS build,
// not here. What IS host-testable is the other half — how much traffic Dart
// puts on that single-threaded channel in the first place:
//
//   * `_pushReality` runs from `build`, and `build` runs for every reason the
//     app has, so an opening menu re-sent the whole camera and overlay state
//     for no change at all;
//   * during an orbit the overlays never change, and every frame of the drag
//     sent them again anyway;
//   * and nothing coalesced, so a drag against a busy native side grew a
//     queue of camera payloads that were stale before they were read.
//
// [samePayload] is the gate the first two go through, so this pins its rules.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart' show PartCamera;
import 'package:prototype/reality_scene.dart';
import 'package:reality_view/reality_view.dart';

PartCamera _cam({double az = 0.7, double pol = 0.9, double halfH = 50}) =>
    PartCamera(az: az, pol: pol, halfH: halfH);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(1366, 1024);

  group('samePayload — the rule the gate uses', () {
    test('two payloads built from the same state are the same', () {
      // The point of the whole thing: a fresh map is built every frame, so
      // `==` is always false and would gate nothing.
      final a = cameraPayload(_cam(), size);
      final b = cameraPayload(_cam(), size);
      expect(identical(a, b), isFalse, reason: 'genuinely two maps');
      expect(samePayload(a, b), isTrue);
    });

    test('a camera that moved is not the same', () {
      final still = cameraPayload(_cam(), size);
      expect(samePayload(cameraPayload(_cam(az: 0.7001), size), still), isFalse,
          reason: 'an orbit of a ten-thousandth of a radian still has to '
              'travel — the gate is for pushes that changed NOTHING');
      expect(samePayload(cameraPayload(_cam(halfH: 50.1), size), still), isFalse,
          reason: 'a zoom');
    });

    test('a viewport that resized is not the same', () {
      expect(
          samePayload(cameraPayload(_cam(), const Size(1366, 1024)),
              cameraPayload(_cam(), const Size(1024, 1366))),
          isFalse,
          reason: 'the size is in the payload because the aspect is');
    });

    test('null is never the same as a payload', () {
      // How a fresh platform view is handled: it holds nothing, so the first
      // push to it must go through however equal it looks to the old one's.
      expect(samePayload(cameraPayload(_cam(), size), null), isFalse);
      expect(samePayload(null, null), isTrue);
    });

    test('it compares STRUCTURE, not identity, all the way down', () {
      Map<String, dynamic> overlays(bool hot) => {
            'planes': [
              {'key': 'xy', 'visible': true, 'hot': hot},
              {'key': 'yz', 'visible': false, 'hot': false},
            ],
            'cp': {'visible': false, 'hot': false},
            'selSketch': <String>[],
            'edgeAccent': <String, dynamic>{},
          };
      expect(samePayload(overlays(false), overlays(false)), isTrue);
      expect(samePayload(overlays(true), overlays(false)), isFalse,
          reason: 'a hover deep inside a nested list still has to travel');
    });

    test('a shorter list is not the same as a longer one', () {
      expect(samePayload({'a': const [1, 2]}, {'a': const [1, 2, 3]}), isFalse);
      expect(samePayload(const [1, 2], const [1, 2]), isTrue);
    });

    test('a key that is missing is not a key that is null', () {
      // `containsKey`, not `[]`: two maps of the same length where one has
      // 'hoverSketch': null and the other omits it describe different states,
      // and reading both as null would gate away the difference.
      expect(samePayload({'a': 1, 'hoverSketch': null}, {'a': 1, 'b': null}),
          isFalse);
    });

    test('typed buffers compare by content', () {
      // The accent polylines are Float32List slices — one hovered edge, so
      // element-wise is affordable, and comparing them by identity would send
      // the overlay payload on every frame of a hover that had not moved.
      Map<String, dynamic> accent(double last) => {
            'edgeAccent': {
              'lines': [
                Float32List.fromList([0, 0, 0, 1, 1, last])
              ]
            }
          };
      expect(samePayload(accent(1), accent(1)), isTrue);
      expect(samePayload(accent(1), accent(2)), isFalse);
    });
  });

  group('what the gate does to a session', () {
    test('an orbit re-sends the camera every frame and the overlays never',
        () {
      // The shape of the fix, in the terms the report used. Overlays carry
      // hover, visibility and selection — none of which an orbit touches.
      const overlays = {
        'planes': [
          {'key': 'xy', 'visible': false, 'hot': false}
        ],
        'selSketch': <String>[],
      };
      var cameras = 0, sent = 0;
      Map<String, dynamic>? lastCam;
      Map<String, dynamic>? lastOverlays;

      for (var frame = 0; frame < 60; frame++) {
        final cam = cameraPayload(_cam(az: 0.7 + frame * 0.01), size);
        if (!samePayload(cam, lastCam)) {
          lastCam = cam;
          cameras++;
        }
        if (!samePayload(overlays, lastOverlays)) {
          lastOverlays = overlays;
          sent++;
        }
      }

      expect(cameras, 60, reason: 'every frame of an orbit really did move');
      expect(sent, 1,
          reason: 'and the overlay state was pushed once, not sixty times, '
              'onto the same channel the camera has to get through');
    });

    test('a rebuild that changed nothing sends nothing', () {
      // A menu opening, a toast, an animation tick: `build` runs, the viewport
      // is asked to push, and there is nothing to say.
      final cam = cameraPayload(_cam(), size);
      var sent = 0;
      Map<String, dynamic>? last;
      for (var build = 0; build < 20; build++) {
        final next = cameraPayload(_cam(), size);
        if (!samePayload(next, last)) {
          last = next;
          sent++;
        }
      }
      expect(sent, 1);
      expect(samePayload(cam, last), isTrue);
    });
  });

  group('the channel does not grow a backlog', () {
    // A method channel delivers in order on ONE platform thread. While a push
    // is being handled, everything pushed after it queues — and in a drag
    // against a busy native side that queue is frames of an orbit that has
    // already finished, each of which will still be read, applied and drawn
    // before the one the finger is actually on.
    const id = 384;
    late List<double> applied;
    late Completer<void> gate;
    var blockNext = false;

    setUp(() {
      applied = [];
      gate = Completer<void>();
      blockNext = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('prototype/reality_view/$id'),
              (call) async {
        applied.add(((call.arguments as Map)['az'] as num).toDouble());
        // Stand in for a native side that is busy: the first call blocks
        // until the test lets it go, and the rest are quick.
        if (blockNext) {
          blockNext = false;
          await gate.future;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('prototype/reality_view/$id'), null);
    });

    test('a camera pushed while one is in flight replaces the one waiting',
        () async {
      final c = RealityViewController.forTest(id);
      blockNext = true;

      unawaited(c.setCamera(cameraPayload(_cam(az: 1), size)));
      await pumpEventQueue();
      expect(applied, const [1.0], reason: 'the first one is in the handler');

      // Three more frames of the drag arrive while it is stuck there.
      unawaited(c.setCamera(cameraPayload(_cam(az: 2), size)));
      unawaited(c.setCamera(cameraPayload(_cam(az: 3), size)));
      unawaited(c.setCamera(cameraPayload(_cam(az: 4), size)));
      await pumpEventQueue();
      expect(applied, const [1.0], reason: 'none of them jumped the queue');

      gate.complete();
      await pumpEventQueue();
      expect(applied, const [1.0, 4.0],
          reason: 'the newest is what the user is looking at; the two behind '
              'it describe a camera position that is already history, and '
              'applying them is work spent drawing the past');
    });

    test('overlays coalesce on their own queue, and land on the last state',
        () async {
      final c = RealityViewController.forTest(id);
      blockNext = true;
      unawaited(c.setOverlays({'az': 1}));
      await pumpEventQueue();
      unawaited(c.setOverlays({'az': 2}));
      unawaited(c.setOverlays({'az': 3}));
      gate.complete();
      await pumpEventQueue();

      // Safe ONLY because an overlay payload is complete state rather than a
      // delta: whatever is skipped, the last one describes the whole scene.
      expect(applied, const [1.0, 3.0]);
    });

    test('a quiet channel is not delayed by any of this', () async {
      final c = RealityViewController.forTest(id);
      await c.setCamera(cameraPayload(_cam(az: 1), size));
      await c.setCamera(cameraPayload(_cam(az: 2), size));
      expect(applied, const [1.0, 2.0],
          reason: 'nothing is dropped when nothing is contended');
    });
  });
}
