// M440 — the mesh import returns whether or not a frame ever arrives.
//
// M440 made the busy card come down when the model is ON SCREEN rather than
// when the kernel returns, which is right: the bar used to vanish with the
// features not yet appended and the part not rebuilt, so the user watched an
// unchanged screen after being told it was finished. The way it waits is
// `await WidgetsBinding.instance.endOfFrame`, as the last statement before
// `importMeshIntoPart` returns.
//
// That await is only as reliable as the frame it waits for, and a frame is not
// something the import can promise. `endOfFrame` schedules one when the
// binding is idle — enough in the app, and exactly nothing under
// `AutomatedTestWidgetsFlutterBinding`, where `scheduleFrame` is inert and a
// frame happens only when a test pumps. So an import driven straight off
// AppState waited forever, and because the await is the last thing before the
// return it took the import's own Future with it: `mesh: done` in the log, and
// every caller stopped behind it.
//
// That is not a test-only shape. A real app in the background has stopped
// producing frames too, so an import that finishes while the user is away
// would not return until they came back to it.
//
// M384's three mesh cases are what actually caught this — they drive AppState
// directly, and all three sat at 30 s apiece, which is what red main was made
// of. They are a slow and indirect way to say it, though: nothing in that file
// mentions frames, so the next person to touch the card would have had to
// work out why a solid-binding suite was hanging. This file says it in one
// place, and fails in a second rather than in ninety.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';

import 'm384_import_solid_binding_test.dart' show MeshKernel;

/// The smallest STL the reader accepts: one triangle, binary. Same fixture as
/// M384's, which is the suite this property was found through.
File _stl(Directory dir) {
  final b = BytesBuilder()
    ..add(List<int>.filled(80, 0))
    ..add((ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List());
  final d = ByteData(50);
  const tri = <double>[0, 0, 0, 10, 0, 0, 0, 10, 0];
  for (var i = 0; i < 9; i++) {
    d.setFloat32(12 + i * 4, tri[i], Endian.little);
  }
  b.add(d.buffer.asUint8List());
  return File('${dir.path}/thing.stl')..writeAsBytesSync(b.toBytes());
}

void main() {
  // The import reaches for a platform channel (the import-choice sheet) and
  // for `WidgetsBinding.instance` itself, so the binding has to exist even
  // though nothing here pumps it. That is precisely the state under test: a
  // binding that is initialized and will never produce a frame.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('importMeshIntoPart completes with nothing pumping frames', () async {
    final docs = Directory.systemTemp.createTempSync('m440_docs');
    final src = Directory.systemTemp.createTempSync('m440_src');
    addTearDown(() {
      if (docs.existsSync()) docs.deleteSync(recursive: true);
      if (src.existsSync()) src.deleteSync(recursive: true);
    });

    final a = AppState()
      ..docsDirForTest = docs
      ..volatileDirsForTest = const [];
    a.partKernel = MeshKernel()..converted = const [10, 20, 30];
    await a.createNamedPart('mesh');

    // No binding pumps here — this is a plain `test`, so `scheduleFrame` is
    // inert and `endOfFrame` will not complete on its own. The bound on the
    // wait is the whole assertion; without it this never returns.
    //
    // Five seconds is far above the one the import actually waits
    // (`_kFramePresentWait`) and far below the 30 s the runner would take to
    // call it a timeout — so a failure here reads as "the import hung", which
    // is what it would be, rather than as a slow machine.
    final n = await a
        .importMeshIntoPart(_stl(src).path)
        .timeout(const Duration(seconds: 5));

    expect(n, 3,
        reason: 'and it returns the bodies it made, not merely a value — the '
            'wait being bounded must not cost the result the caller came for');
  });
}
