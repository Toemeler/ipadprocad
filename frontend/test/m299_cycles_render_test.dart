// M299 — when the Cycles image is shown, and when it is a lie.
//
// RealityKit's rendered mode draws every frame; a path tracer cannot. So
// "rendered mode uses Cycles" means the viewport keeps drawing while you move,
// a render starts when you stop, and the result is shown over it — until
// anything changes, at which point the image is of a model that is no longer
// on screen and has to go.
//
// That last rule is the whole of this file. A path-traced picture of a model
// you have since edited is not a nicer picture of your model, it is a picture
// of a DIFFERENT model, and leaving it up is worse than not rendering at all.
// Every test here is a way that could happen: the camera moves mid-render, the
// geometry changes, the viewport resizes, the mode goes off, the render fails.
//
// None of it needs a renderer, which is the point — the C++ first runs on a
// device, and none of this arithmetic should have to wait for it.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_render.dart';

CyclesKey _key({String scene = 's1', String cam = 'c1', int w = 100, int h = 80}) =>
    CyclesKey(scene, cam, w, h);

Uint8List _pixels(int w, int h) => Uint8List(w * h * 4);

/// A renderer the test drives by hand: each call parks on a completer.
class _Fake {
  final List<Completer<Uint8List?>> calls = [];
  final List<CyclesKey> keys = [];

  Future<Uint8List?> render(CyclesKey k) {
    keys.add(k);
    final c = Completer<Uint8List?>();
    calls.add(c);
    return c.future;
  }

  void land({Uint8List? pixels, int at = -1}) {
    final c = calls[at < 0 ? calls.length - 1 : at];
    c.complete(pixels);
  }
}

void main() {
  group('the happy path', () {
    test('a request renders and the image is shown', () async {
      final fake = _Fake();
      final r = CyclesRender(renderer: fake.render, samples: 32);
      expect(r.phase, CyclesPhase.idle);

      r.request(_key());
      expect(r.phase, CyclesPhase.pending);
      expect(r.busy, isTrue);

      final f = r.pump();
      expect(r.phase, CyclesPhase.rendering);
      fake.land(pixels: _pixels(100, 80));
      await f;

      expect(r.phase, CyclesPhase.shown);
      expect(r.busy, isFalse);
      expect(r.image, isNotNull);
      expect(r.image!.key, _key());
      expect(r.image!.samples, 32);
    });

    test('the same scene asked for twice renders once', () async {
      // request() is called on every rebuild. A path tracer that restarted on
      // every frame would never finish one.
      final fake = _Fake();
      final r = CyclesRender(renderer: fake.render, samples: 32);
      r.request(_key());
      final f = r.pump();
      r.request(_key());
      expect(r.pump(), isNull, reason: 'nothing new to start');
      fake.land(pixels: _pixels(100, 80));
      await f;
      expect(fake.calls.length, 1);
    });
  });

  group('the image goes the instant the scene does', () {
    test('a camera move clears it immediately, not when the next one lands',
        () async {
      // The failure this exists to prevent: a wrong picture that lingers for
      // four seconds is read as the answer.
      final fake = _Fake();
      final r = CyclesRender(renderer: fake.render, samples: 32);
      r.request(_key(cam: 'c1'));
      final f = r.pump();
      fake.land(pixels: _pixels(100, 80));
      await f;
      expect(r.image, isNotNull);

      r.request(_key(cam: 'c2'));
      expect(r.image, isNull, reason: 'it is a picture of the old camera');
      expect(r.phase, CyclesPhase.pending);
    });

    test('so does an edit, and so does a resize', () async {
      for (final moved in [_key(scene: 's2'), _key(w: 120)]) {
        final fake = _Fake();
        final r = CyclesRender(renderer: fake.render, samples: 32);
        r.request(_key());
        final f = r.pump();
        fake.land(pixels: _pixels(100, 80));
        await f;
        expect(r.image, isNotNull);
        r.request(moved);
        expect(r.image, isNull, reason: '$moved');
      }
    });

    test('leaving rendered mode clears it', () async {
      final fake = _Fake();
      final r = CyclesRender(renderer: fake.render, samples: 32);
      r.request(_key());
      final f = r.pump();
      fake.land(pixels: _pixels(100, 80));
      await f;
      r.request(null);
      expect(r.image, isNull);
      expect(r.phase, CyclesPhase.idle);
      expect(r.busy, isFalse);
    });
  });

  group('a render that finishes into a scene that moved', () {
    test('is discarded, and the wanted one is left queued', () async {
      // Seconds of work land into a viewport the user has since orbited. The
      // result is correct for a camera nobody is looking through.
      final fake = _Fake();
      final r = CyclesRender(renderer: fake.render, samples: 32);
      r.request(_key(cam: 'c1'));
      final f = r.pump();
      r.request(_key(cam: 'c2'));   // moved while rendering
      fake.land(pixels: _pixels(100, 80));  // c1's result arrives
      await f;

      expect(r.image, isNull, reason: 'c1 is not what is on screen');
      expect(r.phase, CyclesPhase.pending, reason: 'c2 still wants rendering');

      final f2 = r.pump();
      expect(fake.keys.last, _key(cam: 'c2'));
      fake.land(pixels: _pixels(100, 80));
      await f2;
      expect(r.image!.key, _key(cam: 'c2'));
    });

    test('and if the mode went off meanwhile, it goes idle', () async {
      final fake = _Fake();
      final r = CyclesRender(renderer: fake.render, samples: 32);
      r.request(_key());
      final f = r.pump();
      r.request(null);
      fake.land(pixels: _pixels(100, 80));
      await f;
      expect(r.phase, CyclesPhase.idle);
      expect(r.image, isNull);
    });
  });

  group('failure', () {
    test('a null result is reported, not shown as a blank image', () async {
      final fake = _Fake();
      final r = CyclesRender(renderer: fake.render, samples: 32);
      r.request(_key());
      final f = r.pump();
      fake.land(pixels: null);
      await f;
      expect(r.phase, CyclesPhase.failed);
      expect(r.image, isNull);
      expect(r.error, isNotEmpty);
    });

    test('a thrown renderer does not take the app with it', () async {
      final r = CyclesRender(
          renderer: (k) async => throw StateError('kernel compile failed'),
          samples: 32);
      r.request(_key());
      await r.pump();
      expect(r.phase, CyclesPhase.failed);
      expect(r.error, contains('kernel compile failed'));
    });
  });

  group('a build with no renderer', () {
    test('does nothing at all', () {
      // Every build until the libraries land, and every host test forever.
      // Rendered mode must be exactly the RealityKit view it is today.
      final fake = _Fake();
      final r = CyclesRender(
          renderer: fake.render, samples: 32, available: false);
      expect(r.request(_key()), isFalse);
      expect(r.pump(), isNull);
      expect(r.phase, CyclesPhase.idle);
      expect(r.image, isNull);
      expect(r.busy, isFalse);
      expect(fake.calls, isEmpty);
    });
  });

  group('the key names every input', () {
    test('two scenes that differ anywhere are different keys', () {
      const base = CyclesKey('s', 'c', 10, 10);
      expect(base, const CyclesKey('s', 'c', 10, 10));
      expect(base, isNot(const CyclesKey('s2', 'c', 10, 10)));
      expect(base, isNot(const CyclesKey('s', 'c2', 10, 10)));
      expect(base, isNot(const CyclesKey('s', 'c', 11, 10)));
      expect(base, isNot(const CyclesKey('s', 'c', 10, 11)));
    });
  });
}
