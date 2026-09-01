// M320 — the kernel compile happens at launch, and rendered mode says so
// while it has not finished.
//
// Cycles' Metal backend ships no compiled kernels: it builds them from source
// on the device, which is minutes on a cold install and nothing on every
// launch after. The whole of that wait used to land on whoever first switched
// to rendered mode, as a spinner with no picture behind it — indistinguishable
// from a hung app.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_warmup.dart';

void main() {
  setUp(CyclesWarmup.instance.resetForTest);
  tearDown(CyclesWarmup.instance.resetForTest);

  group('without a renderer', () {
    test('there is nothing to prepare and nothing to say', () {
      // Every host test and every build before the Cycles libraries landed.
      // Not "compiling", not "failed" — absent, so nothing is drawn.
      CyclesWarmup.instance.start();
      expect(CyclesWarmup.instance.phase, CyclesWarmupPhase.absent);
      expect(CyclesWarmup.instance.ready, isFalse);
      expect(CyclesWarmup.instance.status, isEmpty);
    });

    test('starting twice is not two compiles', () {
      // The compile is the expensive thing in the whole feature; a second one
      // would be minutes of GPU work for an answer already being computed.
      CyclesWarmup.instance.start();
      CyclesWarmup.instance.start();
      expect(CyclesWarmup.instance.phase, CyclesWarmupPhase.absent);
    });
  });

  group('reporting', () {
    test('listeners hear every step, because that is the whole point', () {
      var beats = 0;
      void onChange() => beats++;
      CyclesWarmup.instance.addListener(onChange);

      CyclesWarmup.instance.setForTest(CyclesWarmupPhase.compiling,
          status: 'Loading render kernels (may take a few minutes the first '
              'time)');
      expect(beats, 1);
      expect(CyclesWarmup.instance.status, contains('Loading render kernels'));
      expect(CyclesWarmup.instance.ready, isFalse);

      CyclesWarmup.instance.setForTest(CyclesWarmupPhase.compiling,
          status: 'Rendering 1/1 sample', progress: 0.5);
      expect(beats, 2);
      expect(CyclesWarmup.instance.progress, 0.5);

      CyclesWarmup.instance.setForTest(CyclesWarmupPhase.ready);
      expect(beats, 3);
      expect(CyclesWarmup.instance.ready, isTrue);
      expect(CyclesWarmup.instance.status, isEmpty,
          reason: 'a finished warm-up has no step to report');

      CyclesWarmup.instance.removeListener(onChange);
      CyclesWarmup.instance.setForTest(CyclesWarmupPhase.compiling);
      expect(beats, 3, reason: 'a removed listener stays removed');
    });

    test('a failure keeps its reason, since nothing else will show it', () {
      CyclesWarmup.instance.setForTest(CyclesWarmupPhase.failed,
          status: 'no Metal device — this build renders on the GPU only');
      expect(CyclesWarmup.instance.ready, isFalse);
      expect(CyclesWarmup.instance.status, contains('no Metal device'));
    });

    test('progress is negative until Cycles is actually counting', () {
      // A progress bar sitting at zero for ninety seconds is worse than no
      // bar; the panel draws one only for a value in range.
      expect(CyclesWarmup.instance.progress, lessThan(0));
      CyclesWarmup.instance.setForTest(CyclesWarmupPhase.compiling,
          status: 'Loading render kernels');
      expect(CyclesWarmup.instance.progress, lessThan(0));
    });
  });
}
