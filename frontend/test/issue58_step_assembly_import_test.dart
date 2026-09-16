// #58 — "this step was an assembly, with other assemblys in the assembly and
// so on. but after import it was just one part with lots of solids. fix this."
//
// The kernel half is in occt_capi.cpp (v30) and cannot be exercised here: the
// shim is a prebuilt binary and the host has no OCCT. It was verified against
// the reporter's own littlejoint.stp by compiling occt_import_step_tree
// verbatim and running it, which produced exactly the tree this file's fake
// replays:
//
//   nodes=29 solids=8 defs=10
//   GELENK1KLEIN
//     Solid5:1  Solid5:2                    2 occurrences, 1 definition
//     Solid6:1 .. Solid6:6                  6 occurrences, 1 definition
//     base:1 { Solid1:1 Solid2:1 Solid3_1:1 Solid1:2 Solid2:2 }
//     base:2 { the same five }
//     achse8mm:1-2  radlein8mm:1-4  axis42mm:1-2
//
// So what this file pins is the DART half: given that tree, the import writes
// one document per PRODUCT and one occurrence per PLACEMENT — 26 occurrences
// over 8 part documents and one sub-assembly document placed twice — instead
// of one part with 26 bodies.
//
// It is also where the sequel is answered:
//
//   "if a part or a assembly is exactly the same as another in a assembly,
//    they should be linked. so when i longpress a assembly or a part in an
//    assembly i can press open and it opens it as a new file that i can save
//    and the original assembly is still linked to this new saved child"
//
// That is what an occurrence already IS (M245): `AssemblyOccurrence.source` is
// a document name, and every occurrence of one product resolves to the one
// model behind it. The link is not built here — it is what falls out of not
// flattening in the first place, and `base` placed twice is the case that
// proves it.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/quat.dart';

KernelSolid _stub(double volume) => KernelSolid(
    OcctMeshData(
        Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
        Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
        Int32List.fromList(const [0, 1, 2]),
        Int32List.fromList(const [0, 3]),
        Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
    volume,
    null);

/// A kernel that reads no files and replays one tree.
class _TreeKernel implements PartKernel {
  _TreeKernel(this.tree);
  final StepAssembly? tree;

  @override
  StepAssembly? importStepAssembly(String path) => tree;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => '';
  @override
  List<KernelSolid> importStepSolids(String path) => const [];

  @override
  noSuchMethod(Invocation i) => null;
}

/// littlejoint.stp's tree, as occt_import_step_tree returned it.
StepAssembly _littlejoint() {
  final pieces = <StepPiece>[];
  final solids = <KernelSolid?>[for (var i = 0; i < 8; i++) _stub(1.0 + i)];
  var at = Vec3.zero;
  void p(int parent, int def, int solid, String name) =>
      pieces.add(StepPiece(parent, def, solid, Quat.identity, at, name));

  p(-1, 0, -1, 'GELENK1KLEIN'); //                             0  root
  p(0, 1, 0, 'Solid5:1'); //                                   1
  p(0, 2, 1, 'Solid6:1'); //                                   2
  p(0, 1, 0, 'Solid5:2'); //                                   3
  p(0, 2, 1, 'Solid6:2'); //                                   4
  p(0, 2, 1, 'Solid6:3'); //                                   5
  p(0, 2, 1, 'Solid6:4'); //                                   6
  p(0, 2, 1, 'Solid6:5'); //                                   7
  p(0, 2, 1, 'Solid6:6'); //                                   8
  p(0, 3, -1, 'base:1'); //                                    9  sub-assembly
  p(9, 4, 2, 'Solid1:1');
  p(9, 5, 3, 'Solid2:1');
  p(9, 6, 4, 'Solid3_1:1');
  p(9, 4, 2, 'Solid1:2');
  p(9, 5, 3, 'Solid2:2');
  p(0, 3, -1, 'base:2'); //                                   15  the SAME sub
  p(15, 4, 2, 'Solid1:1');
  p(15, 5, 3, 'Solid2:1');
  p(15, 6, 4, 'Solid3_1:1');
  p(15, 4, 2, 'Solid1:2');
  p(15, 5, 3, 'Solid2:2');
  p(0, 7, 5, 'achse8mm:1');
  p(0, 7, 5, 'achse8mm:2');
  p(0, 8, 6, 'radlein8mm:1');
  p(0, 8, 6, 'radlein8mm:2');
  p(0, 8, 6, 'radlein8mm:3');
  p(0, 8, 6, 'radlein8mm:4');
  p(0, 9, 7, 'axis42mm:1');
  p(0, 9, 7, 'axis42mm:2');
  return StepAssembly(pieces, solids, 10);
}

AppState _app(StepAssembly? tree, String tag) => AppState()
  ..docsDirForTest = Directory.systemTemp.createTempSync(tag)
  ..volatileDirsForTest = const []
  ..partKernel = _TreeKernel(tree);

void main() {
  group('THE REPORT: a STEP assembly arrives as an assembly', () {
    test('one document per PRODUCT, one occurrence per PLACEMENT', () async {
      final app = _app(_littlejoint(), 'i58a');
      final placed = await app.importStepAssembly('littlejoint.stp');

      // 18 into the root (8 loose parts, `base` twice, and the 8 axles and
      // wheels) and 5 into the `base` document = 23.
      //
      // NOT 28, and the difference is the whole milestone: `base` holds five
      // components whatever it is placed into, so its children are written
      // ONCE. A flattening import would have made ten.
      expect(placed, 23);

      // 8 leaf definitions -> 8 part documents, NOT 26 bodies in one part.
      final docs = app.allDocumentNames();
      expect(docs, contains('GELENK1KLEIN'));
      expect(docs, contains('base'));
      for (final n in const [
        'Solid5',
        'Solid6',
        'Solid1',
        'Solid2',
        'Solid3_1',
        'achse8mm',
        'radlein8mm',
        'axis42mm',
      ]) {
        expect(docs, contains(n), reason: 'the product named "$n" in the file');
      }
    });

    test('and `base` is ONE document, placed twice — which is the link',
        () async {
      final app = _app(_littlejoint(), 'i58b');
      await app.importStepAssembly('littlejoint.stp');

      final root = app.assemblies['GELENK1KLEIN'];
      expect(root, isNotNull);
      final subs =
          root!.occurrences.where((o) => o.source == 'base').toList();
      expect(subs.length, 2, reason: 'base:1 and base:2');
      expect(subs.every((o) => o.isSubAssembly), isTrue);
      // THE SEQUEL, in one line: the two occurrences name the same document,
      // so opening it and editing it reaches both.
      expect(subs[0].source, subs[1].source);
    });

    test('the sub-assembly holds its own five components', () async {
      final app = _app(_littlejoint(), 'i58c');
      await app.importStepAssembly('littlejoint.stp');
      final base = app.assemblyModelForTest('base');
      expect(base, isNotNull);
      expect(base!.occurrences.length, 5);
      // Solid1 twice, Solid2 twice, Solid3_1 once — three documents, five
      // placements, which is the same rule one level down.
      final byDoc = <String, int>{};
      for (final o in base.occurrences) {
        byDoc[o.source] = (byDoc[o.source] ?? 0) + 1;
      }
      expect(byDoc['Solid1'], 2);
      expect(byDoc['Solid2'], 2);
      expect(byDoc['Solid3_1'], 1);
    });

    test('a flat file is left to the part importer', () async {
      // One product, one solid: a PART. Turning it into a one-component
      // assembly would be a worse answer than the import it already had, so
      // importStepAssembly declines and the caller falls through.
      final flat = StepAssembly(
        [const StepPiece(-1, 0, 0, Quat.identity, Vec3.zero, 'flange')],
        [_stub(1)],
        1,
      );
      expect(flat.isStructured, isFalse);
      final app = _app(flat, 'i58d');
      expect(await app.importStepAssembly('flange.stp'), 0);
    });

    test('a kernel that cannot read structure declines, it does not throw',
        () async {
      final app = _app(null, 'i58e');
      expect(await app.importStepAssembly('anything.stp'), 0);
    });
  });

  group('a document name is the PRODUCT, not the occurrence', () {
    test('the instance suffix comes off', () {
      expect(AppState.stepDocName('base:2', 'x'), 'base');
      expect(AppState.stepDocName('radlein8mm:14', 'x'), 'radlein8mm');
    });

    test('a colon that is not an instance suffix stays', () {
      // "Rev:A" is a name, not an occurrence — the number is what marks one.
      expect(AppState.stepDocName('Rev:A', 'x'), 'Rev_A');
    });

    test('characters the gallery will not take are replaced', () {
      expect(AppState.stepDocName('brack/et*1', 'x'), 'brack_et_1');
    });

    test('a product the file did not name falls back', () {
      expect(AppState.stepDocName('', 'Part'), 'Part');
      expect(AppState.stepDocName('   ', 'Part'), 'Part');
      expect(AppState.stepDocName(':3', 'Part'), 'Part');
    });
  });

  group('Quat.fromRotation — the placements are matrices', () {
    void roundTrip(Vec3 axis, double angle) {
      final q = Quat.axisAngle(axis, angle);
      // The matrix the kernel would hand over, row-major 3x4.
      final x = q.rotate(const Vec3(1, 0, 0));
      final y = q.rotate(const Vec3(0, 1, 0));
      final z = q.rotate(const Vec3(0, 0, 1));
      final m = <double>[
        x.x, y.x, z.x, 0, //
        x.y, y.y, z.y, 0, //
        x.z, y.z, z.z, 0, //
      ];
      final back = Quat.fromRotation(m);
      // A quaternion and its negation are the same rotation, so compare what
      // they DO rather than their components.
      for (final v in const [
        Vec3(1, 0, 0),
        Vec3(0, 1, 0),
        Vec3(0, 0, 1),
        Vec3(1, 2, 3),
      ]) {
        final a = q.rotate(v), b = back.rotate(v);
        expect((a - b).length, lessThan(1e-9),
            reason: 'axis $axis angle $angle on $v');
      }
    }

    test('the identity', () {
      roundTrip(const Vec3(0, 0, 1), 0);
    });

    test('quarter turns about each axis', () {
      roundTrip(const Vec3(1, 0, 0), math.pi / 2);
      roundTrip(const Vec3(0, 1, 0), math.pi / 2);
      roundTrip(const Vec3(0, 0, 1), math.pi / 2);
    });

    test('HALF turns, which is the branch that exists for them', () {
      // trace = -1 at a half turn, so reading w from the trace alone divides
      // by zero. Every part that was flipped over in an assembly is this case.
      roundTrip(const Vec3(1, 0, 0), math.pi);
      roundTrip(const Vec3(0, 1, 0), math.pi);
      roundTrip(const Vec3(0, 0, 1), math.pi);
      roundTrip(const Vec3(1, 1, 0), math.pi);
      roundTrip(const Vec3(1, 1, 1), math.pi);
    });

    test('a general rotation', () {
      roundTrip(const Vec3(0.3, -0.7, 0.4), 2.1);
      roundTrip(const Vec3(-1, 2, -0.5), -1.3);
    });

    test('a garbage matrix is the identity, not a NaN', () {
      expect(Quat.fromRotation(const [0, 0, 0, 0, 0, 0, 0, 0, 0]),
          Quat.identity);
      expect(Quat.fromRotation(const [1, 2, 3]), Quat.identity);
    });
  });
}
