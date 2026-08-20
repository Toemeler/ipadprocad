// Timing hook for the native_menu channels — same seam as the other two.
//
// A standalone plugin package cannot import the app's perf.dart (the
// dependency runs app -> plugin), so it calls these no-ops and the app
// installs the real recorders at startup. Zero imports here, deliberately.

/// Records a duration in milliseconds under [name].
typedef NmRecordFn = void Function(String name, double ms);

/// Counts [by] occurrences of [name].
typedef NmCountFn = void Function(String name, int by);

void _noRecord(String name, double ms) {}
void _noCount(String name, int by) {}

NmRecordFn nmRecord = _noRecord;
NmCountFn nmCount = _noCount;

/// Wires the plugin to the app's recorder. Called once from `main()`.
void installNativeMenuPerfHooks(
    {required NmRecordFn record, required NmCountFn count}) {
  nmRecord = record;
  nmCount = count;
}

/// Test hook: back to silence.
void resetNativeMenuPerfHooks() {
  nmRecord = _noRecord;
  nmCount = _noCount;
}
