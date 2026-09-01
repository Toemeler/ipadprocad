// M306 — the launch check that turns the worst failure mode into a log line.
//
// Cycles' Metal backend compiles its kernels FROM SOURCE on the device, so an
// app that ships the nine static libraries and not the kernel tree links,
// launches, shows a working viewport, and then fails at the first render
// inside a shader compiler — with an error that names nothing anyone can act
// on. The whole point of cycles_boot is that this is discovered at launch and
// reported as a sentence containing the missing file's path.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_boot.dart';

void main() {
  group('the resource root', () {
    test('is a sibling of the executable, not the bundle root', () {
      // Cycles' own fallback is path_dirname(this_program_path()), which would
      // make the resource root Runner.app itself and put the kernel tree in
      // the bundle root. Ours is one directory down, so nothing else in the
      // bundle can collide with a directory named `source`.
      expect(cyclesResourceRoot('/var/containers/Runner.app/Runner'),
          '/var/containers/Runner.app/cycles');
    });

    test('is null when there is no executable path to work from', () {
      // Every host test, and any platform where resolvedExecutable is empty.
      expect(cyclesResourceRoot(''), isNull);
      expect(cyclesResourceRoot('Runner'), isNull);
      expect(cyclesResourceRoot('/Runner'), isNull);
    });
  });

  group('the probe file', () {
    test('is the Metal kernel entry point, under source/', () {
      // path_get("source") is path_join(<root>, "source"), and the include the
      // Metal device asks for is "kernel/device/metal/kernel.metal". If the
      // two disagree, nothing renders and nothing says why.
      expect(cyclesKernelProbe('/a/cycles'),
          '/a/cycles/source/kernel/device/metal/kernel.metal');
    });
  });

  group('readiness', () {
    test('is false on a build with no renderer, which is every host test', () {
      resetCyclesForTest();
      initCycles();
      expect(cyclesReady, isFalse);
    });

    test('a second call cannot leave a stale true behind', () {
      resetCyclesForTest(ready: true);
      expect(cyclesReady, isTrue);
      initCycles();
      expect(cyclesReady, isFalse,
          reason: 'initCycles clears before it decides');
    });
  });
}
