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

  group('the attempt breadcrumb', () {
    // The warm-up runs at launch and calls into a renderer. When it took the
    // process down (build 619: a null dereference in the shim's world setup,
    // reached for the first time BY the warm-up), it did so on every single
    // start — an app that could not be opened at all, in exchange for a
    // feature nobody had asked for yet.
    test('gives up after the allowed number of attempts', () {
      expect(kCyclesWarmupAttempts, greaterThanOrEqualTo(2),
          reason: 'a user killing the app mid-compile looks exactly like a '
              'crash and must not cost them the feature on the first one');
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

  // M383 — the rule that decides whether a warm-up happens at all, and which
  // was silently wrong on two platforms for a whole release.
  //
  // The reasoning was right — a build whose kernels are compiled in has
  // nothing to warm — and the action taken on it was to start no warm-up,
  // which left the phase at `absent`. `absent` does not mean "ready", it means
  // THERE IS NO RENDERER, and rendered mode is gated on `ready`. So Windows
  // and Linux shipped a working path tracer behind a warm-up panel that could
  // never finish: "it always says loading but it will never load and render".
  group('what launch should do about the warm-up', () {
    test('nothing at all when the build has no renderer', () {
      for (final needs in [true, false]) {
        expect(
            cyclesWarmupPlan(haveRenderer: false, needsKernelSource: needs),
            CyclesWarmupPlan.nothing,
            reason: 'needsKernelSource: $needs');
      }
    });

    test('compile where the kernels are built on the device', () {
      // Metal, and only Metal — the case this whole file is about.
      expect(
          cyclesWarmupPlan(haveRenderer: true, needsKernelSource: true),
          CyclesWarmupPlan.compile);
    });

    test('and SAY SO where they came compiled in', () {
      // The one that was missing. Not `nothing` — that is the answer for a
      // build with no renderer, and it is the answer that hid one.
      expect(
          cyclesWarmupPlan(haveRenderer: true, needsKernelSource: false),
          CyclesWarmupPlan.alreadyWarm);
      expect(
          cyclesWarmupPlan(haveRenderer: true, needsKernelSource: false),
          isNot(CyclesWarmupPlan.nothing));
    });

    test('markReady without a renderer stays absent rather than lying', () {
      // On a host test there is no FFI, and claiming the kernels are ready
      // would put rendered mode in front of a renderer that is not there.
      CyclesWarmup.instance.markReady();
      expect(CyclesWarmup.instance.phase, CyclesWarmupPhase.absent);
      expect(CyclesWarmup.instance.ready, isFalse);
    });

    test('and it is a once, like start', () {
      CyclesWarmup.instance.markReady();
      CyclesWarmup.instance.markReady();
      expect(CyclesWarmup.instance.phase, CyclesWarmupPhase.absent);
    });
  });
}
