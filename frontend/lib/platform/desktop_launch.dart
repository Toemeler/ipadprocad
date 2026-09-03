// Prototype — the document a desktop launch was asked to open.
//
// On the iPad a document arrives through the system: Files hands the app a
// security-scoped URL, or another app AirDrops one, and DocumentOpen.swift
// turns it into a path plus a bookmark. There is no such call on a desktop.
// The file manager launches the .desktop file's Exec line with the path as an
// argument (`Exec=prototype %f`), and argv is the whole of the mechanism.
//
// This is the seam between those two worlds. The runner hands argv to Dart's
// `main(List<String> args)`; this records what of it is a document, and
// `main()` opens it once AppState.init has finished. Two reasons it is a
// record rather than a direct call:
//
//   * init() is async and the gallery does not exist until it resolves.
//     Opening a document into a half-built AppState is how you get a document
//     that is open and not in the gallery.
//   * A test — and `flutter run`, and the perf harness — pass their own
//     arguments. Anything that is not an existing file must be ignored
//     SILENTLY here rather than turning into an error dialog at launch.
import 'dart:io' as io;

/// What the process was started with, and what of it is a document to open.
class DesktopLaunch {
  DesktopLaunch._();

  static List<String> _args = const <String>[];

  /// Called from `main(args)` before anything else looks at them.
  static void record(List<String> args) {
    _args = List<String>.unmodifiable(args);
  }

  /// The raw arguments, for the log and the bug bundle.
  static List<String> get arguments => _args;

  /// The FIRST argument that names a file that exists, or null.
  ///
  /// First rather than all of them: the .desktop file passes `%f`, one file,
  /// deliberately (see the comment there). A shell can still pass several, and
  /// opening the first is the behaviour that matches the single-document
  /// window the app actually is.
  ///
  /// Nothing here checks the EXTENSION. `AppState.openPath` already owns that
  /// decision — it is what tells one of our documents from a STEP to import
  /// from a file we cannot read — and duplicating the list here would be a
  /// second place for it to be wrong.
  static String? get document {
    for (final arg in _args) {
      if (arg.startsWith('-')) continue; // a flag, not a path
      try {
        if (io.File(arg).existsSync()) return io.File(arg).absolute.path;
      } catch (_) {
        // An argument that is not a usable path at all. Not an error: this
        // runs on every launch, including the ones nobody passed a file to.
      }
    }
    return null;
  }

  /// Tests only.
  static void resetForTest() => _args = const <String>[];
}
