// Whether this test run has the native libraries (OCCT kernel, SolveSpace,
// renderer) linked in — a developer machine with PROTOTYPE_NATIVE_DIR set, or
// a device run. Tests that pin down how the app behaves WITHOUT them (every
// CI host) skip there instead of failing on a machine that is better off.
import 'dart:io';

final bool kNativeHost =
    (Platform.environment['PROTOTYPE_NATIVE_DIR'] ?? '').isNotEmpty;

const String kNativeHostSkip =
    'pins the behaviour of a host WITHOUT the native libraries';
