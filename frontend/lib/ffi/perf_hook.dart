// Timing hooks for the FFI modules — a dependency seam, not a convenience.
//
// occt_engine.dart and qcad_engine.dart both state the same invariant in their
// header: they depend only on `dart:ffi` / `package:ffi`, so a compile error in
// the app can never reach them and they stay testable on the host without a
// Flutter binding. Importing `perf.dart` there would break that outright —
// perf.dart pulls in dart:io and package:flutter/scheduler.
//
// So the FFI modules call THESE, which do nothing by default. `main.dart`
// installs the real implementations at startup ([installFfiPerfHooks]). An
// un-wired binary — a host unit test, a `dart` script — still runs, still
// links, and simply records nothing.
//
// This file must keep zero imports. That is the whole point of it.

/// Signature of a timing span: run [body] under [name], return its value.
typedef FfiSpanFn = T Function<T>(String name, T Function() body);

/// Signature of an event counter.
typedef FfiCountFn = void Function(String name, int by);

T _noSpan<T>(String name, T Function() body) => body();
void _noCount(String name, int by) {}

/// Times [body] under [name]. A no-op until [installFfiPerfHooks] runs.
FfiSpanFn ffiSpan = _noSpan;

/// Counts [by] occurrences of [name]. A no-op until [installFfiPerfHooks] runs.
FfiCountFn ffiCount = _noCount;

/// Wires the FFI modules to the real recorder. Called once from `main()`.
void installFfiPerfHooks({required FfiSpanFn span, required FfiCountFn count}) {
  ffiSpan = span;
  ffiCount = count;
}

/// Test hook: back to doing nothing, so one test's recorder cannot leak into
/// the next test's numbers.
void resetFfiPerfHooks() {
  ffiSpan = _noSpan;
  ffiCount = _noCount;
}
