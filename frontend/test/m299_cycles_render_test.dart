// M299 — when the Cycles image is shown, and when it is a lie.
//
// M344 rewrote the answer, so this file is worth reading as two rules rather
// than one.
//
// THE OLD RULE was that any change makes the image a lie, because the
// replacement was four seconds away and "a wrong picture that lingers for four
// seconds is read as the answer".
//
// THE NEW ONE splits that in two, and the split is the whole file:
//
//   * a CAMERA change keeps the image. The replacement is forty milliseconds
//     away, an image of where the camera was one frame ago is what a frame IS,
//     and taking it down would be a flicker on every frame of an orbit rather
//     than honesty;
//   * a MODEL change drops it at once. A path-traced picture of a model you
//     have since edited is a picture of a DIFFERENT model, and there is no
//     frame rate at which showing it is right.
//
// And a third thing the old file could not express: which of the two happened
// decides what has to be sent to the renderer. A camera move is twelve floats;
// a model change is every vertex in the document. Getting that backwards does
// not produce a wrong picture, it produces a stuttering one, which is far
// harder to notice and to attribute.
//
// None of it needs a renderer, which is the point — the C++ first runs on a
// device, and none of this arithmetic should have to wait for it.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_live.dart';
import 'package:prototype/cycles_render.dart';

CyclesKey _key(
        {String scene = 's1', String cam = 'c1', int w = 100, int h = 80}) =>
    CyclesKey(scene, cam, w, h);

CyclesLiveFrame _frame({
  int w = 100,
  int h = 80,
  int samples = 8,
  int target = 256,
  bool done = false,
  bool denoised = true,
}) =>
    CyclesLiveFrame(
      rgba: Uint8List(w * h * 4),
      width: w,
      height: h,
      samples: samples,
      target: target,
      done: done,
      denoised: denoised,
    );

void main() {
  group('what a request asks for', () {
    test('the first one is a whole scene', () {
      final r = CyclesRender();
      expect(r.phase, CyclesPhase.idle);
      final (push, repaint) = r.request(_key());
      expect(push, CyclesPush.scene);
      expect(repaint, isTrue);
      expect(r.phase, CyclesPhase.rendering);
      expect(r.busy, isTrue);
    });

    test('the same key again asks for nothing', () {
      // `offer` runs from build, on every frame of every drag. An idempotent
      // request is what keeps that from re-uploading the model sixty times a
      // second.
      final r = CyclesRender();
      r.request(_key());
      expect(r.request(_key()), (CyclesPush.nothing, false));
      expect(r.wants(_key()), isTrue);
    });

    test('a camera move asks for a VIEW, not a scene', () {
      // The entire performance argument of the live renderer. Getting this
      // wrong renders the same picture and re-uploads every vertex to do it.
      final r = CyclesRender();
      r.request(_key());
      final (push, _) = r.request(_key(cam: 'c2'));
      expect(push, CyclesPush.view);
    });

    test('a resize asks for a view too', () {
      // The image size is part of the view: the geometry has not changed, only
      // how many pixels are being asked of it.
      final r = CyclesRender();
      r.request(_key());
      expect(r.request(_key(w: 640)).$1, CyclesPush.view);
      expect(r.request(_key(w: 640, h: 400)).$1, CyclesPush.view);
    });

    test('a model change asks for a scene', () {
      final r = CyclesRender();
      r.request(_key());
      expect(r.request(_key(scene: 's2')).$1, CyclesPush.scene);
    });

    test('a model change that also moves the camera asks for a scene', () {
      // Both halves at once — switching document, say. The expensive push has
      // to win: a view sent against the old geometry would render the new
      // camera on the old model.
      final r = CyclesRender();
      r.request(_key());
      expect(r.request(_key(scene: 's2', cam: 'c2')).$1, CyclesPush.scene);
    });

    test('leaving the mode asks for a stop, once', () {
      final r = CyclesRender();
      r.request(_key());
      expect(r.request(null), (CyclesPush.stop, true));
      expect(r.phase, CyclesPhase.idle);
      // And a second null is not a second shutdown: `offer` runs every frame,
      // and a renderer told to stop sixty times a second would never be off.
      expect(r.request(null), (CyclesPush.nothing, false));
    });
  });

  group('what survives a change', () {
    test('a camera move KEEPS the image on screen', () {
      // M344's departure from M299, and the reason for it: the replacement is
      // one frame away, so taking this down would be a flicker on every frame
      // of an orbit.
      final r = CyclesRender();
      r.request(_key());
      r.accept(_frame());
      expect(r.image, isNotNull);
      r.request(_key(cam: 'c2'));
      expect(r.image, isNotNull,
          reason: 'an image of the previous camera is what a frame is');
    });

    test('a model change takes it down at once', () {
      final r = CyclesRender();
      r.request(_key());
      r.accept(_frame());
      r.request(_key(scene: 's2'));
      expect(r.image, isNull,
          reason: 'a picture of a model that no longer exists is not a frame, '
              'it is the wrong answer');
    });

    test('leaving the mode takes it down', () {
      final r = CyclesRender();
      r.request(_key());
      r.accept(_frame());
      r.request(null);
      expect(r.image, isNull);
      expect(r.phase, CyclesPhase.idle);
    });

    test('a resize keeps it, because it is the same model', () {
      // The old image is the wrong SIZE, which BoxFit handles, and the right
      // model, which nothing else can fix.
      final r = CyclesRender();
      r.request(_key());
      r.accept(_frame());
      r.request(_key(w: 640));
      expect(r.image, isNotNull);
    });
  });

  group('converging', () {
    test('every frame replaces the last and the count climbs', () {
      final r = CyclesRender();
      r.request(_key());
      expect(r.accept(_frame(samples: 4)), isTrue);
      expect(r.image!.samples, 4);
      expect(r.phase, CyclesPhase.rendering);
      expect(r.accept(_frame(samples: 32)), isTrue);
      expect(r.image!.samples, 32);
      expect(r.busy, isTrue);
    });

    test('the finished frame stops the spinner', () {
      final r = CyclesRender();
      r.request(_key());
      r.accept(_frame(samples: 256, target: 256, done: true, denoised: false));
      expect(r.phase, CyclesPhase.shown);
      expect(r.busy, isFalse);
      // And it is the RAW path trace: the filter fades out before the target,
      // so what the user settles on is the renderer and not a filter constant.
      expect(r.image!.denoised, isFalse);
    });

    test('moving the camera after it converged starts it again', () {
      final r = CyclesRender();
      r.request(_key());
      r.accept(_frame(samples: 256, done: true));
      expect(r.phase, CyclesPhase.shown);
      r.request(_key(cam: 'c2'));
      expect(r.phase, CyclesPhase.rendering);
      expect(r.busy, isTrue);
    });

    test('a frame that arrives with the mode off is dropped', () {
      // The renderer is asynchronous and the mode is a switch. A frame in
      // flight when it is thrown must not put a picture back on screen.
      final r = CyclesRender();
      r.request(_key());
      r.request(null);
      expect(r.accept(_frame()), isFalse);
      expect(r.image, isNull);
    });

    test('a frame smaller than it claims to be is dropped', () {
      // The pixels cross an isolate boundary and are handed straight to
      // decodeImageFromPixels, which reads width*height*4 bytes from them.
      final r = CyclesRender();
      r.request(_key());
      expect(
          r.accept(CyclesLiveFrame(
            rgba: Uint8List(10),
            width: 100,
            height: 80,
            samples: 1,
            target: 256,
            done: false,
            denoised: true,
          )),
          isFalse);
      expect(r.image, isNull);
    });
  });

  group('failure', () {
    test('is reported and keeps whatever was on screen', () {
      // A session that dies after producing a picture leaves a TRUE picture of
      // the model up. Taking it down would turn one failure into two.
      final r = CyclesRender();
      r.request(_key());
      r.accept(_frame());
      expect(r.fail('no Metal device'), isTrue);
      expect(r.phase, CyclesPhase.failed);
      expect(r.error, 'no Metal device');
      expect(r.image, isNotNull);
    });

    test('the same failure twice is not two repaints', () {
      final r = CyclesRender();
      r.request(_key());
      expect(r.fail('boom'), isTrue);
      expect(r.fail('boom'), isFalse);
    });

    test('a new request clears the error', () {
      final r = CyclesRender();
      r.request(_key());
      r.fail('boom');
      r.request(_key(scene: 's2'));
      expect(r.error, isEmpty);
      expect(r.phase, CyclesPhase.rendering);
    });
  });

  group('without a renderer', () {
    test('nothing happens at all', () {
      // Every host test, and every build before the Cycles libraries land.
      final r = CyclesRender(available: false);
      expect(r.request(_key()), (CyclesPush.nothing, false));
      expect(r.accept(_frame()), isFalse);
      expect(r.fail('boom'), isFalse);
      expect(r.phase, CyclesPhase.idle);
      expect(r.image, isNull);
      expect(r.busy, isFalse);
    });
  });

  group('the first render of a run', () {
    test('is remembered across a reset, because it is a fact about Metal', () {
      // The kernels are compiled once per PROCESS, not once per document. A
      // fresh session per document that promised the long wait again would be
      // telling the user the app had hung.
      final r = CyclesRender();
      expect(r.everRendered, isFalse);
      r.request(_key());
      r.accept(_frame());
      expect(r.everRendered, isTrue);
      r.reset();
      expect(r.everRendered, isTrue);
      expect(r.image, isNull);
      expect(r.phase, CyclesPhase.idle);
    });
  });

  group('the key', () {
    test('names every input that changes the picture', () {
      const a = CyclesKey('s', 'c', 10, 10);
      expect(a, const CyclesKey('s', 'c', 10, 10));
      expect(a == const CyclesKey('s2', 'c', 10, 10), isFalse);
      expect(a == const CyclesKey('s', 'c2', 10, 10), isFalse);
      expect(a == const CyclesKey('s', 'c', 11, 10), isFalse);
      expect(a == const CyclesKey('s', 'c', 10, 11), isFalse);
    });

    test('knows when two keys are the same MODEL', () {
      const a = CyclesKey('s', 'c', 10, 10);
      expect(a.sameScene(const CyclesKey('s', 'c2', 900, 600)), isTrue);
      expect(a.sameScene(const CyclesKey('s2', 'c', 10, 10)), isFalse);
    });
  });
}
