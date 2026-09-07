// M384 — an imported body comes back as the SAME solid it was, every time.
//
// Issue #14: "this is an imported file. but on the second opening most of the
// parts is gone." The whale was converted from an STL, and the conversion
// handed back one shape holding several closed volumes. That became ONE
// feature, and it was written to STEP as one shape — while `openPart` reads
// the file back through `importStepSolids`, which EXPLODES it into solids. The
// single feature was given `solids[0]` and the rest were disposed, so the body
// came back as whichever fragment happened to explode first: 126 faces of 365,
// a flat sliver where a whale had been.
//
// Underneath that was a second, quieter version of the same mistake. Features
// were matched to solids BY POSITION in the surviving feature list, so
// deleting the second of four imported bodies silently re-bound the third and
// fourth to different geometry on the next open.
//
// Both are fixed by the same idea: a feature records WHICH solid of the file
// it is, and the import takes its bodies from the file it just wrote — through
// the very call the reopen makes, so the two orders cannot disagree.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_store.dart';
import 'package:prototype/ffi/occt_engine.dart' show MeshToBrepReport;
import 'package:prototype/part_model.dart';

import 'm345_clipboard_test.dart' show FileKernel, stubSolid;

/// A kernel that also CONVERTS a mesh, so the STL route can be walked here.
///
/// [FileKernel] already writes and re-reads a "STEP" (JSON, one volume per
/// solid, because M55 forbids faking a B-Rep). This adds the one call the mesh
/// route needs and, crucially, lets a test say that the converted shape holds
/// SEVERAL volumes — which is the whole of issue #14 and cannot be expressed
/// through a single `KernelSolid`.
class MeshKernel extends FileKernel {
  /// The volumes the conversion "found". More than one means a compound.
  List<double> converted = const [1.0];

  @override
  MeshImportOutcome meshToBrep(Float64List xyz, Int32List triangles,
      {double tolFraction = 0, int mode = 1, int maxFacetedTriangles = 0}) {
    // The shape handed back is ONE solid object whose volume is the total —
    // exactly what OCCT returns for a compound, and exactly what used to
    // become one feature.
    return MeshImportOutcome(
        stubSolid(converted.fold(0.0, (a, b) => a + b)),
        const MeshToBrepReport.empty(),
        null);
  }

  /// Writing the converted shape writes every volume it stands for, so the
  /// read back explodes into that many solids — the asymmetry issue #14 was.
  @override
  bool exportStep(List<KernelSolid> solids, String path) {
    if (refuseExport) return false;
    exports++;
    File(path).writeAsStringSync(jsonEncode(converted));
    return true;
  }
}

/// A SAVED part document holding [volumes] as one imported "STEP", written
/// through the app's own import and save so the on-disk shape is the real one,
/// then edited to look the way an older build (or a deletion) would have left
/// it.
///
/// [edit] receives the feature list out of the document's meta.json and
/// returns what should be there instead — dropping `importIndex` to make a
/// pre-M384 document, dropping a feature to make a deleted body.
Future<Directory> _saved(
  List<double> volumes,
  List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) edit,
) async {
  final docs = Directory.systemTemp.createTempSync('m383');
  final src = Directory.systemTemp.createTempSync('m383_step');
  try {
    final step = File('${src.path}/src.step')
      ..writeAsStringSync(jsonEncode(volumes));
    final a = AppState()
      ..docsDirForTest = docs
      ..volatileDirsForTest = const [];
    a.partKernel = FileKernel();
    await a.createNamedPart('imported');
    await a.importStepIntoPart(step.path);
    await a.savePart('imported');
  } finally {
    src.deleteSync(recursive: true);
  }

  final path = '${docs.path}/imported.$kPartExt';
  final doc = readDoc(path)!;
  final meta = jsonDecode(utf8.decode(doc.entries[kMetaEntry]!)) as Map;
  meta['features'] = edit([
    for (final f in (meta['features'] as List)) (f as Map).cast<String, dynamic>()
  ]);
  writeDoc(
      path,
      DocFile(doc.kind, {
        ...doc.entries,
        kMetaEntry: Uint8List.fromList(utf8.encode(jsonEncode(meta))),
      }));
  return docs;
}

/// Rewrites the "STEP" stashed INSIDE the saved document, so the file the
/// reopen reads holds [volumes] — a source that changed under a document.
void _shortenStep(Directory docs, List<double> volumes) {
  final path = '${docs.path}/imported.$kPartExt';
  final doc = readDoc(path)!;
  final key = doc.entries.keys.firstWhere((k) => k.endsWith('.step'));
  writeDoc(
      path,
      DocFile(doc.kind, {
        ...doc.entries,
        key: Uint8List.fromList(utf8.encode(jsonEncode(volumes))),
      }));
}

/// The feature list of the saved document, as it is on disk.
List<Map<String, dynamic>> _savedFeatures(Directory docs) {
  final doc = readDoc('${docs.path}/imported.$kPartExt')!;
  final meta = jsonDecode(utf8.decode(doc.entries[kMetaEntry]!)) as Map;
  return [
    for (final f in (meta['features'] as List)) (f as Map).cast<String, dynamic>()
  ];
}

/// Every feature, with the index a pre-M384 document could not record.
List<Map<String, dynamic>> _asLegacy(List<Map<String, dynamic>> fs) =>
    [for (final f in fs) {...f}..remove('importIndex')];

/// The imported features of the open part, in timeline order.
List<ExtrudeFeature> _imports(AppState a) => [
      for (final f in a.currentPart!.features)
        if (f is ExtrudeFeature && f.imported) f
    ];

void main() {
  // openPart and importMeshIntoPart both reach a platform channel (the preview
  // repair, the import-choice sheet), which needs a binding even where the
  // channel then answers nothing.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late Directory docs;
  tearDown(() {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<AppState> reopen(Directory d) async {
    final a = AppState()
      ..docsDirForTest = d
      ..volatileDirsForTest = const [];
    a.partKernel = FileKernel();
    await a.openPart('imported');
    return a;
  }

  group('a file with more solids than the document claims', () {
    test('issue #14: a legacy one-feature document keeps every body',
        () async {
      // Exactly the whale: a file the kernel explodes into three, and a
      // pre-M384 document that kept only the first feature — which is what
      // the mesh route used to write, since it made ONE feature for a shape
      // holding three closed volumes.
      docs = await _saved(const [10, 20, 30], (fs) => [_asLegacy(fs).first]);
      final a = await reopen(docs);
      final got = _imports(a);

      expect(got.length, 3,
          reason: 'the two solids nobody claimed used to be disposed in '
              'silence, which is how most of the model disappeared');
      expect([for (final f in got) f.solid?.volume], const [10.0, 20.0, 30.0],
          reason: 'in the file\'s own explode order');
      expect(got.first.name, 'Import1',
          reason: 'the feature that was already there keeps its identity');
      expect([for (final f in got) f.importIndex], const [0, 1, 2],
          reason: 'every one of them now says which solid it is');
      expect([for (final f in got) f.bodyName].toSet().length, 3,
          reason: 'a recovered body is its own body, not a second driver of '
              'one that already exists');
      // And the repair is DURABLE: the document is marked dirty, so the next
      // save writes the recovered bodies down and the adoption happens once
      // rather than on every open.
      await a.savePart('imported');
      expect([for (final f in _savedFeatures(docs)) f['importIndex']],
          const [0, 1, 2]);
    });

    test('recovering a body does not move the End of Part marker', () async {
      // A rollback is something the user parked in the document. Appending
      // through PartModel.appendFeature would drag the marker down past each
      // recovered body — right for a body somebody just made, and a silent
      // undo of their rollback here.
      docs = await _saved(const [10, 20, 30], (fs) => [_asLegacy(fs).first]);
      final path = '${docs.path}/imported.$kPartExt';
      final doc = readDoc(path)!;
      final meta = jsonDecode(utf8.decode(doc.entries[kMetaEntry]!)) as Map;
      meta['eopNodes'] = 0; // parked ABOVE the only feature there is
      writeDoc(
          path,
          DocFile(doc.kind, {
            ...doc.entries,
            kMetaEntry: Uint8List.fromList(utf8.encode(jsonEncode(meta))),
          }));

      final a = await reopen(docs);
      final got = _imports(a);

      expect(got.length, 3, reason: 'the geometry still comes back');
      expect(a.currentPart!.eopAfter, 0, reason: 'and the rollback stands');
      expect(got.every((f) => f.rolledBack), isTrue,
          reason: 'every row is below the marker, including the recovered '
              'ones — which is what the marker being at 0 means');
    });

    test('a document that CAN say leaves a deleted body deleted', () async {
      // Post-M384: three solids in the file, but the user deleted the middle
      // body. The indices say so, so nothing may resurrect it.
      docs = await _saved(const [10, 20, 30], (fs) => [fs[0], fs[2]]);
      final a = await reopen(docs);
      final got = _imports(a);

      expect(got.length, 2, reason: 'the deletion stands');
      expect([for (final f in got) f.solid?.volume], const [10.0, 30.0],
          reason: 'and the survivors are still their OWN solids — by position '
              'Import3 would have come back as the 20 it never was');
    });
  });

  group('binding is by index, not by position', () {
    test('deleting a body does not re-aim the ones after it', () async {
      docs = await _saved(
          const [10, 20, 30, 40], (fs) => [fs[0], fs[2], fs[3]]);
      final a = await reopen(docs);

      expect([for (final f in _imports(a)) f.solid?.volume],
          const [10.0, 30.0, 40.0],
          reason: 'by position these would have been 10, 20 and 30');
    });

    test('a solid the file no longer has is reported, not guessed', () async {
      // Two bodies were imported; the file now holds one. (Written with two,
      // then the source shortened underneath the document.)
      docs = await _saved(const [10, 20], (fs) => fs);
      _shortenStep(docs, const [10]);
      final a = await reopen(docs);
      final got = _imports(a);

      expect(got[0].solid?.volume, 10.0);
      expect(got[1].solid, isNull);
      expect(got[1].computeError, isNotNull,
          reason: 'a body that cannot be found says so rather than borrowing '
              'its neighbour\'s geometry');
    });

    test('the index survives a save and a reopen', () async {
      docs = await _saved(const [10, 20], _asLegacy);
      // First open backfills the indices onto the legacy features…
      final first = await reopen(docs);
      expect([for (final f in _imports(first)) f.importIndex], const [0, 1]);
      await first.savePart('imported');

      // …and the document now carries them.
      expect([for (final f in _savedFeatures(docs)) f['importIndex']],
          const [0, 1]);

      final second = await reopen(docs);
      expect([for (final f in _imports(second)) f.solid?.volume],
          const [10.0, 20.0]);
    });
  });

  group('the mesh route writes what the reopen will read', () {
    late Directory src;
    setUp(() => src = Directory.systemTemp.createTempSync('m383_src'));
    tearDown(() {
      if (src.existsSync()) src.deleteSync(recursive: true);
    });

    /// The smallest STL the reader accepts: one triangle, binary.
    File _stl() {
      final b = BytesBuilder()
        ..add(List<int>.filled(80, 0))
        ..add((ByteData(4)..setUint32(0, 1, Endian.little))
            .buffer
            .asUint8List());
      final d = ByteData(50);
      const tri = <double>[0, 0, 0, 10, 0, 0, 0, 10, 0];
      for (var i = 0; i < 9; i++) {
        d.setFloat32(12 + i * 4, tri[i], Endian.little);
      }
      b.add(d.buffer.asUint8List());
      return File('${src.path}/thing.stl')..writeAsBytesSync(b.toBytes());
    }

    test('a conversion holding three volumes becomes three bodies', () async {
      docs = Directory.systemTemp.createTempSync('m383_mesh');
      final a = AppState()
        ..docsDirForTest = docs
        ..volatileDirsForTest = const [];
      final k = MeshKernel()..converted = const [10, 20, 30];
      a.partKernel = k;
      await a.createNamedPart('mesh');

      final n = await a.importMeshIntoPart(_stl().path);

      expect(n, 3,
          reason: 'the converted shape held three closed volumes, and the '
              'STEP beside the part holds three — so the document must too, '
              'or the reopen loses two of them');
      final got = _imports(a);
      expect([for (final f in got) f.solid?.volume], const [10.0, 20.0, 30.0]);
      expect([for (final f in got) f.importIndex], const [0, 1, 2]);
      expect([for (final f in got) f.name].toSet().length, 3,
          reason: 'three features, three names');
      expect(k.imports, 1,
          reason: 'the bodies come from the file that was just written, '
              'through the call openPart makes — not from a second explode '
              'of the in-memory shape, which could order them differently');
    });

    test('and they survive the reopen unchanged', () async {
      docs = Directory.systemTemp.createTempSync('m383_mesh2');
      final a = AppState()
        ..docsDirForTest = docs
        ..volatileDirsForTest = const [];
      a.partKernel = MeshKernel()..converted = const [10, 20, 30];
      await a.createNamedPart('mesh');
      await a.importMeshIntoPart(_stl().path);
      await a.savePart('mesh');

      final b = AppState()
        ..docsDirForTest = docs
        ..volatileDirsForTest = const [];
      b.partKernel = FileKernel();
      await b.openPart('mesh');

      expect([for (final f in _imports(b)) f.solid?.volume],
          const [10.0, 20.0, 30.0],
          reason: 'the second opening is the one issue #14 was about');
    });

    test('a conversion that writes no solid still leaves the body there',
        () async {
      docs = Directory.systemTemp.createTempSync('m383_mesh3');
      final a = AppState()
        ..docsDirForTest = docs
        ..volatileDirsForTest = const [];
      a.partKernel = MeshKernel()..converted = const [];
      await a.createNamedPart('mesh');

      final n = await a.importMeshIntoPart(_stl().path);

      expect(n, 1,
          reason: 'a file the reader finds nothing in must leave the session '
              'exactly as it was, not empty — the converted shape is only '
              'released once something has replaced it');
      expect(_imports(a).single.solid, isNotNull);
    });
  });
}
