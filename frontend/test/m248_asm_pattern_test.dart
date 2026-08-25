// M248 — Pattern Component / Mirror Component / Copy Component.
//
// Three commands, and only one of them is hard. Pattern and Copy place more
// occurrences of the same documents at rigid transforms this tree already
// knows how to draw; MIRROR does not, and this file leads with the reason:
//
//   A REFLECTION IS NOT A RIGID TRANSFORM. It has determinant −1, a
//   quaternion cannot hold one, and every consumer in the assembly layer was
//   written assuming a proper rotation. The specific way that goes wrong is
//   WINDING: cross(p1−p0, p2−p0) comes out pointing INTO a mirrored solid, so
//   the renderer's front test (n·dir < 0) selects the back faces and the
//   picker answers with geometry on the far side. Both look nearly right —
//   the silhouette is correct, the position is correct, and only the shading
//   and the tap say otherwise. That is what the first group here pins.
//
// The two rules the design is built on, from the device:
//
//   1. EVERY INSTANCE IS LINKED DIRECTLY TO THE PART, mirrored ones included.
//      There is no mirrored part document; an instance is an ordinary
//      occurrence of the same PartModel, so M245's live link carries an edit
//      to every copy.
//   2. THE MIRROR IS LOCAL TO THIS ASSEMBLY — a property of the occurrence,
//      recorded in the .pas file and nowhere else.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_solver.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/l10n/cad_terms.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/reality_payload.dart';
import 'package:prototype/widgets/viewport_assembly.dart';

// ---------------------------------------------------------------------------
// fakes
// ---------------------------------------------------------------------------

/// A CHIRAL solid: a box with one corner cut away, so its mirror image is not
/// the same shape however it is turned.
///
/// A box would pass every test in this file while the mirror did nothing at
/// all — which is exactly the trap, since a mirrored box is a box.
KernelSolid chiralBox({double h = 10}) {
  // Eight corners, with +X+Y+Z pulled in to a third of the way. The face
  // records are honest planes for the six box faces; the cut corner is
  // carried by the vertex positions, which is all the winding tests need.
  final c = [
    [-h, -h, -h],
    [h, -h, -h],
    [h, h, -h],
    [-h, h, -h],
    [-h, -h, h],
    [h, -h, h],
    [h / 3, h / 3, h], // the cut corner
    [-h, h, h],
  ];
  const quads = [
    [0, 3, 2, 1], // -Z
    [4, 5, 6, 7], // +Z
    [0, 1, 5, 4], // -Y
    [3, 7, 6, 2], // +Y
    [0, 4, 7, 3], // -X
    [1, 2, 6, 5], // +X
  ];
  const normals = [
    [0.0, 0.0, -1.0],
    [0.0, 0.0, 1.0],
    [0.0, -1.0, 0.0],
    [0.0, 1.0, 0.0],
    [-1.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
  ];
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  final triFaces = <int>[];
  final infos = <double>[];
  for (var f = 0; f < quads.length; f++) {
    final base = pos.length ~/ 3;
    for (final vi in quads[f]) {
      pos.addAll(c[vi]);
      nor.addAll(normals[f]);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    triFaces.addAll([f, f]);
    final n = normals[f];
    infos.addAll([
      0, // plane
      n[0] * h, n[1] * h, n[2] * h,
      n[0], n[1], n[2],
      0, 0, 0,
      0,
      0, 0, 0, 0,
    ]);
  }
  return KernelSolid(
    OcctMeshData(
      Float64List.fromList(pos),
      Float64List.fromList(nor),
      Int32List.fromList(idx),
      Int32List.fromList([0]),
      Float64List(0),
      triFaces: Int32List.fromList(triFaces),
      faceInfos: Float64List.fromList(infos),
    ),
    8 * h * h * h,
    null,
  );
}

PartModel boxPart(String name, {double h = 10}) {
  final p = PartModel(name);
  p.features.add(ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: 'Sketch1',
    profiles: [ProfileSel(0, 0, 10)],
    direction: ExtrudeDirection.defaultDir,
    distanceA: 2 * h,
    distanceB: 0,
    extent: FeatureExtent.distance,
  )..solid = chiralBox(h: h));
  return p;
}

AssemblyOccurrence occ(String id, Vec3 at,
        {bool grounded = false, Quat rot = Quat.identity, double h = 10}) =>
    AssemblyOccurrence(
        id: id,
        source: id.split(':').first,
        part: boxPart(id.split(':').first, h: h),
        offset: at,
        grounded: grounded)
      ..rot = rot;

AppState freshApp(String tag) =>
    AppState()..docsDirForTest = Directory.systemTemp.createTempSync(tag);

AppState asmApp(String tag, List<AssemblyOccurrence> os) {
  final app = freshApp(tag);
  final a = AssemblyModel('Gearbox');
  a.occurrences.addAll(os);
  app.assemblies['Gearbox'] = a;
  app.openTabs.add('Gearbox');
  app.curTab = 'Gearbox';
  return app;
}

Cam3 frontCam([Size size = const Size(800, 600)]) =>
    Cam3(PartCamera(az: 0, pol: 1.5707963267948966, halfH: 90), size);

/// Reflection of [p] in the world plane through [at] with unit normal [n].
Vec3 reflectWorld(Vec3 p, Vec3 at, Vec3 n) => p - n * (2 * (p - at).dot(n));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => L.set(kDe));

  // -------------------------------------------------------------------------
  group('a reflection is not a rigid transform', () {
    const nx = Vec3(1, 0, 0);

    test('Placement round-trips a mirrored point', () {
      final p = Placement(
          Quat.axisAngle(const Vec3(0, 0, 1), 0.7), const Vec3(3, -4, 5), nx);
      const local = Vec3(2, 3, 4);
      final world = p.apply(local);
      final back = p.unapply(world);
      expect(back.x, closeTo(local.x, 1e-12));
      expect(back.y, closeTo(local.y, 1e-12));
      expect(back.z, closeTo(local.z, 1e-12));
    });

    test('it preserves lengths and reverses handedness', () {
      final p = Placement(
          Quat.axisAngle(const Vec3(1, 2, 3), 1.1), const Vec3(0, 0, 0), nx);
      const a = Vec3(1, 0, 0), b = Vec3(0, 1, 0);
      // Orthogonal: lengths and angles survive.
      expect(p.applyDir(a).length, closeTo(1, 1e-12));
      expect(p.applyDir(a).dot(p.applyDir(b)).abs(), lessThan(1e-12));
      // But the cross product comes out the OTHER WAY. This is the whole
      // defect: a normal derived from the winding points into the solid.
      final crossThenMap = p.applyDir(a.cross(b));
      final mapThenCross = p.applyDir(a).cross(p.applyDir(b));
      expect(crossThenMap.dot(mapThenCross), lessThan(0),
          reason: 'det = -1: cross(Sa, Sb) = -S cross(a, b)');
      // And [windingNormal] is the one place that sign is put back.
      final fixed = p.windingNormal(a.cross(b));
      expect(fixed.dot(mapThenCross), greaterThan(0));
    });

    test('a rigid placement leaves windingNormal alone', () {
      final p = Placement(Quat.axisAngle(const Vec3(0, 1, 0), 0.3),
          const Vec3(1, 1, 1));
      const v = Vec3(0, 0, 1);
      final a = p.windingNormal(v), b = p.applyDir(v);
      expect((a - b).length, lessThan(1e-12));
    });

    test('two reflections compose back into a ROTATION', () {
      // Mirroring a mirrored subassembly is right-handed again — and it has to
      // come out as a rotation, not as a second flag nobody reads.
      final outer = Placement(Quat.identity, Vec3.zero, nx);
      final inner = Placement(
          Quat.axisAngle(const Vec3(0, 0, 1), 0.9), const Vec3(5, 0, 0),
          const Vec3(0, 1, 0));
      final both = outer * inner;
      expect(both.mirrored, isFalse,
          reason: 'S·S is a rotation; a flag left set would draw it inside-out');
      // ...and it is the SAME map, checked on a point.
      const l = Vec3(2, -3, 1);
      final direct = outer.apply(inner.apply(l));
      final composed = both.apply(l);
      expect((direct - composed).length, lessThan(1e-9));
    });

    test('a mirror composed over a rigid inner placement stays a mirror', () {
      final outer = Placement(
          Quat.axisAngle(const Vec3(0, 1, 0), 0.4), const Vec3(1, 2, 3), nx);
      final inner = Placement(
          Quat.axisAngle(const Vec3(1, 0, 0), 0.6), const Vec3(7, 0, -2));
      final both = outer * inner;
      expect(both.mirrored, isTrue);
      const l = Vec3(1, 5, -4);
      final direct = outer.apply(inner.apply(l));
      expect((direct - both.apply(l)).length, lessThan(1e-9));
    });

    test('the mirror of an occurrence is the world reflection of its points',
        () {
      // The claim that makes AppState.mirrorComponent one line of arithmetic:
      // reflecting across the world plane (p0, n) keeps `rot`, reflects the
      // offset, and sets reflect = rot⁻¹n.
      final o = occ('Bracket:1', const Vec3(30, 5, -2),
          rot: Quat.axisAngle(const Vec3(0, 1, 1), 0.8));
      const p0 = Vec3(10, 0, 0), n = Vec3(1, 0, 0);
      final m = AssemblyOccurrence(
        id: 'Bracket:2',
        source: 'Bracket',
        part: o.part,
        offset: reflectWorld(o.offset, p0, n),
        rot: o.rot,
        reflect: o.rot.unrotate(n).normalized(),
      );
      for (final l in const [
        Vec3(0, 0, 0),
        Vec3(10, 0, 0),
        Vec3(3, -7, 2),
        Vec3(-1, 4, 9),
      ]) {
        final want = reflectWorld(o.toWorld(l), p0, n);
        final got = m.toWorld(l);
        expect((want - got).length, lessThan(1e-9),
            reason: 'local $l should land on its own reflection');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('a mirrored component is not drawn inside-out', () {
    /// Every triangle of [o] the renderer calls FRONT, by index.
    Set<int> frontTris(AssemblyOccurrence o, Cam3 cam) {
      final out = <int>{};
      for (final (_, at, s) in o.worldSolids) {
        final sc = placedCam(cam, at);
        final scene =
            buildSceneSolid(s, sc, depthBias: cam.depth(at.at), mirrored: at.mirrored);
        for (var i = 0; i < scene.tris.length; i++) {
          if (scene.tris[i].front) out.add(i);
        }
      }
      return out;
    }

    /// Every triangle whose WORLD outward normal actually faces [cam],
    /// computed the long way round: the mesh point transformed, then crossed.
    Set<int> facingTris(AssemblyOccurrence o, Cam3 cam) {
      final out = <int>{};
      for (final (_, at, s) in o.worldSolids) {
        final m = s.mesh;
        for (var t = 0; t + 2 < m.indices.length; t += 3) {
          Vec3 v(int k) {
            final i = m.indices[t + k] * 3;
            return at.apply(
                Vec3(m.positions[i], m.positions[i + 1], m.positions[i + 2]));
          }

          final n = (v(1) - v(0)).cross(v(2) - v(0));
          if (n.length < 1e-12) continue;
          if (n.normalized().dot(cam.dir) < 0) out.add(t ~/ 3);
        }
      }
      return out;
    }

    test('the front faces are the ones a viewer would see', () {
      final cam = frontCam();
      final plain = occ('Bracket:1', const Vec3(-30, 0, 0));
      final mirrored = occ('Bracket:2', const Vec3(30, 0, 0))
        ..reflect = const Vec3(1, 0, 0);
      // The control: without a mirror the two agree trivially.
      expect(frontTris(plain, cam), facingTris(plain, cam));
      // The claim. Note facingTris transforms the VERTICES and crosses after,
      // so it is right by construction whatever the handedness — it is the
      // renderer's shortcut (cross in local space, test against the placed
      // camera) that needed the sign.
      expect(frontTris(mirrored, cam), facingTris(mirrored, cam),
          reason: 'a mirrored component drawn with the un-flipped test shows '
              'its back faces: silhouette right, shading wrong');
      expect(frontTris(mirrored, cam), isNotEmpty);
      expect(frontTris(mirrored, cam).length,
          lessThan(mirrored.part!.features.first.solid!.mesh.indices.length ~/ 3),
          reason: 'not ALL of them either — that would be no culling at all');
    });

    test('the picker finds a mirrored component where it is drawn', () {
      final cam = frontCam();
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(-40, 0, 0)))
        ..occurrences.add(occ('Bracket:2', const Vec3(40, 0, 0))
          ..reflect = const Vec3(1, 0, 0));
      final hit = pickOccurrence(
          a, cam, cam.project(a.occurrences[1].toWorld(Vec3.zero)));
      expect(hit?.id, 'Bracket:2',
          reason: 'the facing test has to flip with the winding, or the tap '
              'falls through the mirrored component');
    });
  });

  // -------------------------------------------------------------------------
  group('the document and the device', () {
    test('the mirror survives a save and a reload', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(5, 0, 0))
          ..reflect = const Vec3(0, 0, 1));
      final b = AssemblyModel('Gearbox')..loadJson(a.toJson());
      expect(b.occurrences.single.reflect, isNotNull);
      expect(b.occurrences.single.reflect!.z, closeTo(1, 1e-12));
    });

    test('an assembly with no mirror writes exactly what it wrote before', () {
      final j = occ('Bracket:1', const Vec3(5, 0, 0)).toJson();
      expect(j.containsKey('mir'), isFalse);
    });

    test('a degenerate stored normal is refused rather than silently ignored',
        () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', Vec3.zero));
      final j = a.toJson();
      (j['occurrences'] as List).first['mir'] = [0, 0, 0];
      final b = AssemblyModel('Gearbox')..loadJson(j.cast<String, dynamic>());
      expect(b.occurrences.single.reflect, isNull);
    });

    test('the RealityKit payload sends REFLECTED buffers, not a scale', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(5, 0, 0))
          ..reflect = const Vec3(1, 0, 0));
      final scene = buildAssemblyScenePayload(a);
      final solid = (scene['solids'] as List).single as Map;
      final mesh = a.occurrences.single.part!.features.first.solid!.mesh;
      // The placement stays RIGID — the renderer is unchanged, which is the
      // whole reason the flip is in the geometry.
      expect(solid.containsKey('mirror'), isFalse);
      // x is negated (the plane's normal is +X), y and z are not.
      final pos = solid['positions'] as Float32List;
      expect(pos[0], closeTo(-mesh.positions32[0], 1e-5));
      expect(pos[1], closeTo(mesh.positions32[1], 1e-5));
      expect(mesh.positions32[0].abs(), greaterThan(1e-3),
          reason: 'the fixture must not be trivial');
      // ...and reflecting the positions turned every triangle inside out, so
      // the indices come back reversed.
      final sent = solid['indices'] as Int32List;
      expect(sent.length, mesh.indices.length);
      expect(sent[0], mesh.indices[0]);
      expect(sent[1], mesh.indices[2]);
      expect(sent[2], mesh.indices[1]);
      expect(mesh.indices[1], isNot(mesh.indices[2]));
      // The B-Rep edges travel reflected too, or the outline would sit on the
      // component the mirror came from.
      expect(solid['edgePts'], isNot(same(mesh.edgePoints32)));
    });

    test('reflecting a buffer never touches the shared mesh', () {
      final src = Float32List.fromList([1, 2, 3, -4, 5, 6]);
      final out = reflectedPoints(src, const Vec3(1, 0, 0));
      expect(out[0], closeTo(-1, 1e-6));
      expect(out[1], closeTo(2, 1e-6));
      expect(src[0], closeTo(1, 1e-6),
          reason: 'every un-mirrored occurrence draws from this list');
    });

    test('reversing a winding never touches the shared buffer', () {
      final src = Int32List.fromList([0, 1, 2, 3, 4, 5]);
      final out = reversedWinding(src);
      expect(out, isNot(same(src)));
      expect(src, orderedEquals([0, 1, 2, 3, 4, 5]),
          reason: 'every other occurrence of the part draws from this list');
    });

    test('mirroring a component moves the SCENE signature, not just the '
        'placement', () {
      // A mirrored solid travels with its winding reversed, so it cannot be
      // expressed by re-placing a mesh the renderer already holds.
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(5, 0, 0)));
      final before = assemblySceneSignature(a);
      a.occurrences.single.reflect = const Vec3(1, 0, 0);
      expect(assemblySceneSignature(a), isNot(before));
    });
  });

  // -------------------------------------------------------------------------
  group('the solver sees the reflection', () {
    test('a mirrored face normal reaches the residuals reflected', () {
      // The face record's normal is STORED, not derived from the winding, so
      // it lifts through the reflection unchanged in kind: what changes is
      // where it points.
      final o = occ('Bracket:1', Vec3.zero)..reflect = const Vec3(1, 0, 0);
      final faces = localFacesOf(o);
      expect(faces, isNotEmpty);
      // The +X face of the part becomes the -X face of the component.
      final plusX = faces.firstWhere((f) => f.at.x > 5);
      expect(o.dirToWorld(const Vec3(1, 0, 0)).x, closeTo(-1, 1e-12));
      expect(plusX.dir.length, closeTo(1, 1e-9));
    });

    test('a mirrored body still has six degrees of freedom', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', Vec3.zero)
          ..reflect = const Vec3(1, 0, 0));
      final r = solveAssembly(a);
      expect(r.dof, 6,
          reason: 'the reflection is a fixed property, not a coordinate');
    });

    test('the solver moves a mirrored component the way it moves any other',
        () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Base:1', Vec3.zero, grounded: true))
        ..occurrences.add(occ('Bracket:1', const Vec3(60, 0, 0))
          ..reflect = const Vec3(1, 0, 0));
      // Mate the mirrored bracket's -X face (which is its part's +X face,
      // reflected) to the base's +X face.
      a.constraints.add(AsmConstraint(
        name: 'Mate1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: const AsmRef('Base:1', AsmGeom.plane(Vec3(10, 0, 0), Vec3(1, 0, 0)),
            'Face'),
        b: const AsmRef('Bracket:1',
            AsmGeom.plane(Vec3(10, 0, 0), Vec3(1, 0, 0)), 'Face'),
      ));
      final r = solveAssembly(a);
      expect(r.converged, isTrue, reason: r.sick.toString());
      expect(a.occurrences[1].reflect, isNotNull,
          reason: 'and it is still mirrored afterwards');
    });
  });
}
