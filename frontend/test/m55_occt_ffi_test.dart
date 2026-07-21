// M55 — OCCT FFI binding, host-side tests.
//
// On the host test runner the occt_* symbols are NOT linked into the
// process, so the real-kernel path can only be exercised on device / in the
// IPA smoke. What CAN be pinned down here, and matters:
//   1. The probe misses gracefully (no throw), is cached, and reports
//      unavailability honestly.
//   2. occtSmokeLine() never claims PASS without a kernel — it must say
//      SKIP with backend=occt-none (the anti-fake-checkmark rule).
//   3. Pure-Dart input validation of extrudePolygon's preconditions is
//      testable via the argument contract without a kernel.
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/ffi/occt_engine.dart';

void main() {
  setUp(OcctFfi.resetForTest);

  test('probe misses gracefully on host and is cached', () {
    final a = OcctFfi.instance();
    expect(a, isNull, reason: 'occt_* symbols are not linked on host');
    expect(OcctFfi.available, isFalse);
    // Second call takes the cached path; must not re-throw or flip.
    expect(OcctFfi.instance(), isNull);
  });

  test('smoke line is honest without a kernel: SKIP, never PASS', () {
    final line = occtSmokeLine();
    expect(line, startsWith('DART SMOKE: SKIP'));
    expect(line, contains('backend=occt-none'));
    expect(line, isNot(contains('PASS')));
  });

  test('OcctCounts formats compactly for log lines', () {
    expect(const OcctCounts(6, 12, 8).toString(), 'F6/E12/V8');
  });
}
