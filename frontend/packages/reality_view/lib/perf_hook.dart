// Timing hook for the reality_view channel — same seam as ffi/perf_hook.dart.
//
// This is a standalone plugin package: it cannot import the app's perf.dart
// (the dependency runs the other way, app -> plugin). So it calls these, which
// do nothing by default, and the app installs the real recorders at startup.
//
// Zero imports here, deliberately, so the plugin stays as free-standing as it
// was before it learned to report its own cost.

/// Records a duration in milliseconds under [name].
typedef RvRecordFn = void Function(String name, double ms);

/// Counts [by] occurrences of [name].
typedef RvCountFn = void Function(String name, int by);

void _noRecord(String name, double ms) {}
void _noCount(String name, int by) {}

RvRecordFn rvRecord = _noRecord;
RvCountFn rvCount = _noCount;

/// Wires the plugin to the app's recorder. Called once from `main()`.
void installRealityViewPerfHooks(
    {required RvRecordFn record, required RvCountFn count}) {
  rvRecord = record;
  rvCount = count;
}

/// Test hook: back to silence.
void resetRealityViewPerfHooks() {
  rvRecord = _noRecord;
  rvCount = _noCount;
}
