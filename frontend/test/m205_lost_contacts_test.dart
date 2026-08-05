// M205 — THE POINTER THAT NEVER CAME UP.
//
// Four reports from the 2026-08-05 device session, one cause between them:
//
//   "I couldn't place anything and the viewport is jumping around anytime i
//    click anywhere. The whole movement is really fucked up idk why"
//   "i cant drag around any point. it seems stuck somehow and buggy"
//   "in a new sketch the movement was again working idk what happend"
//
// The gesture trace in `bug20260805T141441` has it exactly:
//
//     51623ms  DOWN   p38 mouse at(181.2,171.3)
//     52476ms  DOWN   p39 mouse at(609.4,296.8)
//     ...  45 seconds, neither pointer heard from again  ...
//     97390ms  CANCEL p39 touch at(0.0,0.0)
//     97390ms  CANCEL p38 touch at(0.0,0.0)
//
// Two contacts went down and were never lifted. The viewport counted pointers
// and treated "more than one" as pan/zoom, so from 51.6 s on, every tap was a
// third finger: no picks, no drags, no placing, and a view that moved whenever
// it was touched. The pair was finally released by the cancel storm the
// platform view emits when it takes a gesture — which is why the report filed
// three minutes later says it started working again on its own.
//
// [LivePointers] is the fix, and this is its contract. The tests below are the
// two rules and the property that makes the second one safe to be wrong about.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/touch.dart';

/// A clock we drive by hand, so "45 seconds later" costs no wall time.
class _Clock {
  int ms = 0;
  int call() => ms;
}

void main() {
  group('LivePointers: rule 1 — one device cannot be pressed twice', () {
    test('a second down on the SAME device evicts the first', () {
      final c = _Clock();
      final live = LivePointers(clock: c.call);
      live.down(38, 7, PointerDeviceKind.mouse);
      expect(live.count, 1);

      // Same trackpad, a new press: the old one cannot still be held.
      final lost = live.down(40, 7, PointerDeviceKind.mouse);
      expect(lost, [38]);
      expect(live.count, 1);
      expect(live.kindOf(40), PointerDeviceKind.mouse);
    });

    test('two different fingers both stay down', () {
      final live = LivePointers(clock: _Clock().call);
      live.down(1, 101, PointerDeviceKind.touch);
      final lost = live.down(2, 102, PointerDeviceKind.touch);
      expect(lost, isEmpty);
      expect(live.count, 2, reason: 'a real two-finger pinch must still pinch');
    });
  });

  group('LivePointers: rule 2 — silence means the contact is gone', () {
    test('the reported failure: two stuck pointers, then a fresh tap', () {
      final c = _Clock();
      final live = LivePointers(clock: c.call);

      c.ms = 51623;
      live.down(38, 380, PointerDeviceKind.mouse);
      c.ms = 52476;
      live.down(39, 390, PointerDeviceKind.mouse);
      expect(live.count, 2, reason: 'both really were down');

      // 45 seconds of use later the user taps. Under the old bare counter this
      // was contact number three and the viewport panned instead of picking.
      c.ms = 97000;
      final lost = live.down(99, 990, PointerDeviceKind.touch);
      expect(lost..sort(), [38, 39]);
      expect(live.count, 1, reason: 'the tap must arrive as the FIRST contact');
    });

    test('the watchdog clears them with no new contact at all', () {
      final c = _Clock();
      final live = LivePointers(clock: c.call);
      live.down(38, 380, PointerDeviceKind.mouse);
      live.down(39, 390, PointerDeviceKind.mouse);

      c.ms = LivePointers.staleMs ~/ 2;
      expect(live.pruneStale(), isEmpty, reason: 'not yet — still plausible');

      c.ms = LivePointers.staleMs * 2;
      expect(live.pruneStale()..sort(), [38, 39]);
      expect(live.isEmpty, isTrue);
    });

    test('a contact that keeps reporting is never evicted', () {
      final c = _Clock();
      final live = LivePointers(clock: c.call);
      live.down(1, 101, PointerDeviceKind.touch);
      // A motionless press still reports every frame; ten seconds of that must
      // not look like silence.
      for (var t = 0; t < 10000; t += 16) {
        c.ms = t;
        live.touch(1, 101, PointerDeviceKind.touch);
        expect(live.pruneStale(), isEmpty);
      }
      expect(live.count, 1);
    });
  });

  group('LivePointers: a wrong eviction heals itself', () {
    test('a move re-adopts a contact the watchdog dropped', () {
      final c = _Clock();
      final live = LivePointers(clock: c.call);
      live.down(1, 101, PointerDeviceKind.touch);
      c.ms = LivePointers.staleMs * 2;
      expect(live.pruneStale(), [1]);
      expect(live.isEmpty, isTrue);

      // It was a real finger after all. The very next thing it says puts it
      // back, so the cost of guessing wrong is one event, not a broken gesture.
      live.touch(1, 101, PointerDeviceKind.touch);
      expect(live.count, 1);
      expect(live.kindOf(1), PointerDeviceKind.touch);
    });

    test('an up for an evicted contact does not resurrect the tally', () {
      final c = _Clock();
      final live = LivePointers(clock: c.call);
      live.down(1, 101, PointerDeviceKind.touch);
      c.ms = LivePointers.staleMs * 2;
      live.pruneStale();
      live.remove(1);
      expect(live.isEmpty, isTrue);
    });
  });

  group('LivePointers: what the viewport asks it', () {
    test('soleKind is the kind of the ONE contact, else null', () {
      final live = LivePointers(clock: _Clock().call);
      expect(live.soleKind, isNull);
      live.down(1, 101, PointerDeviceKind.stylus);
      expect(live.soleKind, PointerDeviceKind.stylus);
      live.down(2, 102, PointerDeviceKind.touch);
      expect(live.soleKind, isNull, reason: 'two contacts have no sole kind');
      live.remove(2);
      expect(live.soleKind, PointerDeviceKind.stylus);
    });

    test('palm rejection asks stylusDown, and a lost Pencil stops rejecting',
        () {
      final c = _Clock();
      final live = LivePointers(clock: c.call);
      live.down(1, 101, PointerDeviceKind.stylus);
      expect(live.stylusDown, isTrue);
      // A Pencil whose lift was lost used to reject every finger in the sketch
      // for the rest of the session.
      c.ms = LivePointers.staleMs * 2;
      live.pruneStale();
      expect(live.stylusDown, isFalse);
    });
  });
}
