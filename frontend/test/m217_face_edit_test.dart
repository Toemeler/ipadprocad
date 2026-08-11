// M217 — Delete Face and Direct Edit.
//
// The kernel half (BRepAlgoAPI_Defeaturing, the prism-and-boolean face move)
// is C++ and is pinned by smoke [34]. What is pinned HERE is everything that
// decides WHICH faces the kernel is asked about, which is where a face edit
// actually goes wrong: a fingerprint that cannot find its face after a rebuild
// silently edits the wrong one, and that is a wrong part that looks right.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';

/// A one-face mesh: a unit square at z = [z], normal +Z, area 1.
///
/// Built by hand rather than from a kernel because that is the point — the
/// re-matching has to work off the mesh alone.
OcctMeshData squareMesh(
    {double z = 0,
    double x = 0,
    int kind = kFacePlane,
    int topo = 1,
    double size = 1}) {
  final p = Float64List.fromList([
    x, 0, z, x + size, 0, z, x + size, size, z, //
    x, 0, z, x + size, size, z, x, size, z,
  ]);
  final n = Float64List.fromList(List<double>.generate(
      p.length, (i) => i % 3 == 2 ? 1.0 : 0.0));
  return OcctMeshData(
    p,
    n,
    Int32List.fromList([0, 1, 2, 3, 4, 5]),
    Int32List.fromList([0]),
    Float64List(0),
    triFaces: Int32List.fromList([0, 0]),
    faceInfos: Float64List.fromList([
      kind.toDouble(), x, 0, z, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0,
    ]),
    faceIds: Int32List.fromList([topo]),
  );
}

void main() {
  group('facesOf — the live face list', () {
    test('reports centroid, area, normal and the TOPOLOGICAL index', () {
      final f = facesOf(squareMesh(z: 3, topo: 7)).single;
      expect(f.topoIndex, 7, reason: 'the kernel is addressed by this one');
      expect(f.meshIndex, 0, reason: 'picking produces this one');
      expect(f.area, closeTo(1, 1e-9));
      expect(f.centre.z, closeTo(3, 1e-9));
      expect(f.centre.x, closeTo(0.5, 1e-9));
      expect(f.normal.z, closeTo(1, 1e-9));
    });

    test('a mesh with no face identity yields nothing rather than guesses', () {
      final bare = OcctMeshData(
          Float64List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Float64List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]),
          Int32List.fromList([0, 1, 2]),
          Int32List.fromList([0]),
          Float64List(0));
      expect(facesOf(bare), isEmpty);
    });

    test('the centroid is AREA-weighted, not vertex-averaged', () {
      // Two triangles of very different size sharing a face: the centre must
      // sit where the material is.
      final p = Float64List.fromList([
        0, 0, 0, 10, 0, 0, 10, 10, 0, // big
        0, 0, 0, 0, 0.1, 0, 0.1, 0.1, 0, // sliver
      ]);
      final m = OcctMeshData(
        p,
        Float64List.fromList(
            List<double>.generate(p.length, (i) => i % 3 == 2 ? 1.0 : 0.0)),
        Int32List.fromList([0, 1, 2, 3, 4, 5]),
        Int32List.fromList([0]),
        Float64List(0),
        triFaces: Int32List.fromList([0, 0]),
        faceInfos: Float64List.fromList(
            [0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0]),
        faceIds: Int32List.fromList([1]),
      );
      final f = facesOf(m).single;
      expect(f.centre.x, greaterThan(5),
          reason: 'the big triangle dominates; a vertex average would not');
    });
  });

  group('FacePick — surviving a rebuild', () {
    test('finds its face again after the body was rebuilt', () {
      final before = facesOf(squareMesh(z: 0)).single;
      final sel = FacePick(before.centre.x, before.centre.y, before.centre.z,
          before.normal.x, before.normal.y, before.normal.z, before.area,
          before.kind);
      // Same face, but the rebuild handed it a different topological index.
      final after = facesOf(squareMesh(z: 0, topo: 42));
      final (ids, lost) = resolveFaces([sel], after);
      expect(lost, 0);
      expect(ids, [42], reason: 'the NEW index, not the one first picked');
    });

    test('re-anchors so the next rebuild measures from where the face IS', () {
      final sel = FacePick(0.5, 0.5, 0, 0, 0, 1, 1, kFacePlane);
      // The face moved 4 mm in z (a Direct Edit upstream).
      resolveFaces([sel], facesOf(squareMesh(z: 4)));
      expect(sel.cz, closeTo(4, 1e-9),
          reason: 'without re-anchoring the drift compounds every rebuild');
    });

    test('a face whose TYPE changed is not the same face', () {
      final sel = FacePick(0.5, 0.5, 0, 0, 0, 1, 1, kFacePlane);
      final (ids, lost) =
          resolveFaces([sel], facesOf(squareMesh(kind: kFaceCylinder)));
      expect(ids, isEmpty);
      expect(lost, 1, reason: 'planar became cylindrical: a different face');
    });

    test('a face whose normal flipped is not the same face', () {
      final sel = FacePick(0.5, 0.5, 0, 0, 0, -1, 1, kFacePlane);
      final (ids, lost) = resolveFaces([sel], facesOf(squareMesh()));
      expect(ids, isEmpty);
      expect(lost, 1);
    });

    test('two selections never resolve to the SAME live face', () {
      // Two faces 10 mm apart; both fingerprints sit nearer the first.
      final live = [
        ...facesOf(squareMesh(x: 0, topo: 1)),
        ...facesOf(squareMesh(x: 10, topo: 2)),
      ];
      final a = FacePick(0.5, 0.5, 0, 0, 0, 1, 1, kFacePlane);
      final b = FacePick(0.6, 0.5, 0, 0, 0, 1, 1, kFacePlane);
      final (ids, lost) = resolveFaces([a, b], live);
      expect(ids.toSet().length, ids.length,
          reason: 'one live face cannot serve two selections');
      expect(lost, 0);
    });

    test('a partly-surviving set keeps the survivors', () {
      final live = facesOf(squareMesh(topo: 5));
      final good = FacePick(0.5, 0.5, 0, 0, 0, 1, 1, kFacePlane);
      final gone = FacePick(0.5, 0.5, 0, 0, 0, 1, 1, kFaceCylinder);
      final (ids, lost) = resolveFaces([good, gone], live);
      expect(ids, [5],
          reason: 'Inventor keeps editing the faces that survived');
      expect(lost, 1, reason: 'and the loss is counted, never silent');
    });
  });

  group('features serialize', () {
    test('Delete Face round-trips', () {
      final f = DeleteFaceFeature(
          name: 'Delete Face1',
          bodyName: 'Solid1',
          faces: [FacePick(1, 2, 3, 0, 0, 1, 4, kFaceCylinder)]);
      f.seq = 9;
      final back = PartFeature.fromJson(f.toJson()) as DeleteFaceFeature;
      expect(back.name, 'Delete Face1');
      expect(back.seq, 9);
      expect(back.faces.single.cx, 1);
      expect(back.faces.single.kind, kFaceCylinder);
      expect(back.modifiesBody, isTrue);
      expect(back.output, 'modify');
    });

    test('Direct Edit round-trips, op and delta included', () {
      final f = DirectEditFeature(
          name: 'Direct1',
          bodyName: 'Solid1',
          faces: [FacePick(0, 0, 0, 0, 0, 1, 1, kFacePlane)],
          op: DirectOp.size,
          dx: 0,
          dy: 0,
          dz: 5);
      final back = PartFeature.fromJson(f.toJson()) as DirectEditFeature;
      expect(back.op, DirectOp.size);
      expect(back.dz, 5);
      expect(back.typeLabel, 'Size Faces');
    });

    test('Scale writes its factor and reads it back', () {
      final f = DirectEditFeature(
          name: 'Scale1',
          bodyName: 'Solid1',
          faces: const [],
          op: DirectOp.scale,
          dx: 0,
          dy: 0,
          dz: 0,
          factor: 2.5);
      expect(f.toJson()['f'], 2.5);
      final back = PartFeature.fromJson(f.toJson()) as DirectEditFeature;
      expect(back.factor, 2.5);
      expect(back.typeLabel, 'Scale Body');
    });

    test('the rebuild signature moves when the edit does', () {
      DirectEditFeature make(double dz) => DirectEditFeature(
          name: 'D',
          bodyName: 'S',
          faces: [FacePick(0, 0, 0, 0, 0, 1, 1, kFacePlane)],
          op: DirectOp.move,
          dx: 0,
          dy: 0,
          dz: dz);
      expect(make(1).ownSig(), isNot(make(2).ownSig()),
          reason: 'otherwise editing the distance leaves the solid cached');
    });
  });

  group('session', () {
    test('a face tapped twice is deselected, not added twice', () {
      final s = FaceEditSession(FaceEditKind.delete);
      final sel = FacePick(0, 0, 0, 0, 0, 1, 1, kFacePlane);
      // mirrors AppState.toggleFacePick's contract
      void toggle(FacePick f, int idx) {
        final at = s.meshIndices.indexOf(idx);
        if (at >= 0) {
          s.meshIndices.removeAt(at);
          s.faces.removeAt(at);
        } else {
          s.meshIndices.add(idx);
          s.faces.add(f);
        }
      }

      toggle(sel, 3);
      expect(s.faces.length, 1);
      toggle(sel, 3);
      expect(s.faces, isEmpty, reason: 'the only way to undo a mis-pick');
    });

    test('every kind has a label and Scale knows it needs no faces', () {
      for (final k in FaceEditKind.values) {
        expect(faceEditLabel(k), isNotEmpty);
      }
      expect(FaceEditSession(FaceEditKind.scale).isScale, isTrue);
      expect(FaceEditSession(FaceEditKind.delete).isScale, isFalse);
    });
  });

  group('mesh centre for Scale', () {
    test('is the bounding-box centre, so a body does not fly across the scene',
        () {
      // A square 10 mm off the origin: scaling about the WORLD origin would
      // translate it, which reads as the command having moved the part.
      final c = meshCentreOf(squareMesh(x: 10, z: 4));
      expect(c.x, closeTo(10.5, 1e-9));
      expect(c.z, closeTo(4, 1e-9));
    });

    test('an empty mesh does not produce NaN', () {
      final c = meshCentreOf(OcctMeshData(Float64List(0), Float64List(0),
          Int32List(0), Int32List.fromList([0]), Float64List(0)));
      expect(c.x, 0);
    });
  });

  group('the kernel interface refuses honestly without a kernel', () {
    test('a fake that models none of this returns null, not a wrong solid', () {
      final k = _NoFaceKernel();
      final solid = KernelSolid(squareMesh(), 1, null);
      expect(k.deleteFaces(solid, [1]), isNull);
      expect(k.moveFaces(solid, [1], const Vec3(0, 0, 1)), isNull);
      expect(k.scaleSolid(solid, Vec3.zero, 2), isNull);
    });
  });
}

class _NoFaceKernel implements PartKernel {
  @override
  bool get available => false;
  @override
  String get info => 'none';
  @override
  String get lastError => 'no kernel';
  @override
  KernelSolid? deleteFaces(KernelSolid base, List<int> faceIds) => null;
  @override
  KernelSolid? moveFaces(KernelSolid base, List<int> faceIds, Vec3 delta) =>
      null;
  @override
  KernelSolid? scaleSolid(KernelSolid base, Vec3 centre, double factor) => null;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}
