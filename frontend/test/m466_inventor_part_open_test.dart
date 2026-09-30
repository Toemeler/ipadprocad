// M466 — a part converted from Inventor (tools/ipt) opens as Inventor built it.
//
// Needs the native kernel (PROTOTYPE_NATIVE_DIR) and a converted document
// (IPT_PTP_FIXTURE: a .ptp written by tools/ipt/ipt2ptp.py --full). Both are
// machine-local, so the test skips without them.
//
// What it pins down:
//   * every sketch loads with its geometry and constraints;
//   * every feature of the tree is there, in Inventor's order;
//   * the bodies are Inventor's exact bodies (the stored results), not a
//     rebuild -- which this kernel cannot always match;
//   * no feature reports an error just because a result stands in for it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/solver.dart';

import 'support/native_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = Platform.environment['IPT_PTP_FIXTURE'] ?? '';

  test('an Inventor part opens with its tree and its exact bodies', () async {
    if (!kNativeHost || fixture.isEmpty || !File(fixture).existsSync()) {
      return markTestSkipped('needs PROTOTYPE_NATIVE_DIR and IPT_PTP_FIXTURE');
    }
    final bytes = File(fixture).readAsBytesSync();
    final doc = DocFile.decode(bytes)!;
    final meta = jsonDecode(utf8.decode(doc.entries['meta.json']!)) as Map;
    final info = jsonDecode(utf8.decode(doc.entries['inventor/source.json']!)) as Map;

    final app = AppState()..partKernel = OcctPartKernel();
    expect(app.partKernel.available, isTrue);
    final dir = Directory.systemTemp.createTempSync('prototype_m466_');
    app.docsDirForTest = dir;
    const name = 'Inventor';
    File('${dir.path}/$name.$kPartExt').writeAsBytesSync(bytes);
    await app.refreshSaved();
    await app.openPart(name);
    final p = app.currentPart!;

    // the sketches, with what they were written with -- and where: a face
    // sketch carries its face, and opening must not move it
    final sk = [for (final s in meta['sketches'] as List) (s as Map)['name']];
    expect([for (final c in p.childSketches) c.model.name], sk);
    for (final s in meta['sketches'] as List) {
      final row = s as Map;
      if (row['frame'] == null) continue;
      final cs = p.childSketches.firstWhere((c) => c.model.name == row['name']);
      final fr = PlaneFrame.fromFrameJson(row['frame'] as List)!;
      expect((cs.face!.origin - fr.origin).length, lessThan(1e-9),
          reason: '${row['name']} stays on its face');
      expect(cs.faceRef, isNotNull, reason: '${row['name']} knows its face');
    }
    for (final c in p.childSketches) {
      final cons = jsonDecode(utf8.decode(
          doc.entries['sketches/${c.model.name}.cons.json']!)) as List;
      expect(c.model.constraints.length, cons.length,
          reason: '${c.model.name}: every constraint loads');
      expect(c.model.geometry, isNotEmpty);
      // The sketch is exactly as Inventor solved it: the app's solver must
      // accept it as it stands and move nothing.
      final before = [for (final g in c.model.geometry) List<double>.of(g.data)];
      final gs = List.of(c.model.geometry);
      expect(solveConstraints(gs, c.model.constraints), isTrue,
          reason: '${c.model.name}: the solver accepts the sketch');
      var moved = 0.0;
      for (var i = 0; i < gs.length; i++) {
        for (var k = 0; k < before[i].length && k < gs[i].data.length; k++) {
          final d = (gs[i].data[k] - before[i][k]).abs();
          if (d > moved) moved = d;
        }
      }
      expect(moved, lessThan(1e-6), reason: '${c.model.name}: nothing moves');
    }

    // the tree, in order
    final names = [for (final f in meta['features'] as List) (f as Map)['name']];
    expect([for (final f in p.features) f.name], names);
    for (final f in p.features) {
      expect(f.computeError, isNull, reason: '${f.name}: ${f.computeError}');
    }

    // the bodies are Inventor's
    final bodies = info['bodies'] as List;
    final withResult = [for (final f in p.features) if (f.resultCache != null) f];
    expect(withResult.length, bodies.length);
    for (final f in withResult) {
      expect(f.solid, isNotNull, reason: '${f.name} shows its stored result');
      expect(identical(f.solid, f.resultCache!.solid), isTrue);
      expect(f.resultCache!.sig, isNot('*'), reason: 'keyed on first open');
    }
  });
}
