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
import 'package:prototype/asm_pattern.dart';
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
      // But the cross product comes out the OTHER WAY, and the emphasis is
      // the whole of the milestone's winding trap: it is cross-AFTER-mapping
      // that reverses. Mapping the local cross product is still the outward
      // normal, because an orthogonal map carries outward to outward.
      final crossThenMap = p.applyDir(a.cross(b));
      final mapThenCross = p.applyDir(a).cross(p.applyDir(b));
      expect(crossThenMap.dot(mapThenCross), lessThan(0),
          reason: 'det = -1: cross(Sa, Sb) = -S cross(a, b)');
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
        final scene = buildSceneSolid(s, sc, depthBias: cam.depth(at.at));
        for (var i = 0; i < scene.tris.length; i++) {
          if (scene.tris[i].front) out.add(i);
        }
      }
      return out;
    }

    /// Every triangle a viewer would actually see, computed from the mesh's
    /// STORED outward normals rather than from any winding at all.
    ///
    /// This is the reference the renderer has to agree with, and it is chosen
    /// for being independent of the thing under test: a reflection is
    /// orthogonal, so it carries a stored outward normal to a stored outward
    /// normal, and no sign is involved anywhere in it. It is also what the
    /// SHADING reads — which is what gave the defect away on screen when an
    /// earlier draft of this file used transformed-vertex cross products as
    /// the reference, got the sign wrong there, and "confirmed" a renderer
    /// that was drawing back faces.
    Set<int> facingTris(AssemblyOccurrence o, Cam3 cam) {
      final out = <int>{};
      for (final (_, at, s) in o.worldSolids) {
        final m = s.mesh;
        for (var t = 0; t + 2 < m.indices.length; t += 3) {
          final i = m.indices[t] * 3;
          if (i + 2 >= m.normals.length) continue;
          final n = at.applyDir(
              Vec3(m.normals[i], m.normals[i + 1], m.normals[i + 2]));
          if (n.length < 1e-12) continue;
          // The painter's sign, which is now the app's ONE sign: the eye is
          // at `+dir * D`, so a face the viewer can see has `n·dir > 0` (see
          // Cam3, and the pickers, which have always answered this way).
          //
          // M372 — this used to read `< 0`, matching the painter as it was
          // then and carrying a note that flipping it alone would break the
          // comparison. buildSceneSolid was flipped; this follows. The pair
          // still asks the same question — whether a mirrored component
          // agrees with an unmirrored one — and is still blind to which
          // absolute side is drawn, so it kept passing while both were wrong.
          if (n.normalized().dot(cam.dir) > 0) out.add(t ~/ 3);
        }
      }
      return out;
    }

    test('the front faces are the ones a viewer would see', () {
      // A TILTED camera, and it has to be tilted.
      //
      // frontCam looks straight down -Z at an axis-aligned box, so its four
      // side faces are exactly perpendicular to the view and the sign of
      // `n·dir` on them is floating-point noise — the winding normal and the
      // stored normal can disagree about a face that is edge-on to the camera
      // and both be right. This test compares two independent answers to
      // "which faces are front", so it has to ask about faces that HAVE one.
      //
      // (M372 — it did not, and it passed for years because the noise happened
      // to land the same way on both sides of the comparison. Flipping the
      // renderer's sign to the app's real one was enough to separate them.)
      final cam = Cam3(PartCamera(az: 0.6, pol: 1.2, halfH: 90),
          const Size(800, 600));
      final plain = occ('Bracket:1', const Vec3(-30, 0, 0));
      final mirrored = occ('Bracket:2', const Vec3(30, 0, 0))
        ..reflect = const Vec3(1, 0, 0);
      // The control: without a mirror the two agree.
      expect(frontTris(plain, cam), facingTris(plain, cam));
      // The claim: they agree on a mirrored component too, with the test
      // UNCHANGED. See placedCam — the winding reverses in world space and the
      // renderer works in the component's own, so the two never meet.
      expect(frontTris(mirrored, cam), facingTris(mirrored, cam),
          reason: 'a sign here selects the BACK faces of a mirrored '
              'component: right silhouette, wrong shading');
      expect(frontTris(mirrored, cam), isNotEmpty);
      expect(frontTris(mirrored, cam).length,
          lessThan(mirrored.part!.features.first.solid!.mesh.indices.length ~/ 3),
          reason: 'not ALL of them either — that would be no culling at all');
    });

    test('a mirrored component is lit like its original, not like its inside',
        () {
      // The SHADING is what actually gave the defect away, so it is what this
      // pins: the average brightness of a mirrored component's visible faces
      // has to be in the same range as its original's. Drawing back faces
      // instead lights normals that point away from the light and the whole
      // component goes dark — obvious in a render, invisible to a test that
      // only counts triangles.
      final cam = frontCam();
      double meanShade(AssemblyOccurrence o) {
        var sum = 0.0;
        var n = 0;
        for (final (_, at, s) in o.worldSolids) {
          final sc = placedCam(cam, at);
          for (final tri in buildSceneSolid(s, sc).tris) {
            if (!tri.front) continue;
            sum += (tri.sa + tri.sb + tri.sc) / 3;
            n++;
          }
        }
        return n == 0 ? 0 : sum / n;
      }

      final plain = occ('Bracket:1', const Vec3(-30, 0, 0));
      final mirrored = occ('Bracket:2', const Vec3(30, 0, 0))
        ..reflect = const Vec3(1, 0, 0);
      expect((meanShade(mirrored) - meanShade(plain)).abs(), lessThan(0.12),
          reason: 'a mirror is the same solid seen the other way round; it '
              'must not come out a different brightness');
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

  // -------------------------------------------------------------------------
  group('a pattern places ORDINARY occurrences', () {
    AssemblyModel patterned({int count = 4, double step = 25}) {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bolt:1', Vec3.zero, grounded: true));
      a.patterns.add(AsmPattern(
        name: 'RectangularPattern1',
        mode: PatternKind.rectangular,
        sources: ['Bolt:1'],
        refDirA: const AsmRef(kAssemblyOrigin,
            AsmGeom.axis(Vec3.zero, Vec3(1, 0, 0)), 'X Axis'),
      )
        ..countA = count
        ..distanceA = step
        ..distributionA = PatternDistribution.spacing);
      return a;
    }

    test('the elements are in a.occurrences and nothing special-cases them',
        () {
      final a = patterned();
      regenerateAsmPatterns(a);
      // Four occurrences INCLUDING the seed, which is Inventor's count.
      expect(a.occurrences, hasLength(4));
      expect(a.elementsOf('RectangularPattern1'), hasLength(3));
      // They render, because placedComponents is what every painter reads and
      // it has no idea a pattern exists.
      expect(placedComponents(a), hasLength(4));
      // They are picked, by the same pick that finds any other component.
      final cam = frontCam();
      final third = a.elementsOf('RectangularPattern1')[1];
      expect(pickOccurrence(a, cam, cam.project(third.toWorld(Vec3.zero)))?.id,
          third.id);
      // And they keep the LIVE LINK: it is the same PartModel, not a copy.
      expect(identical(third.part, a.occurrences.first.part), isTrue,
          reason: 'rule 1 — every instance is linked directly to the part');
    });

    test('they land on the grid the parameters describe', () {
      final a = patterned(count: 4, step: 25);
      regenerateAsmPatterns(a);
      final xs = a.elementsOf('RectangularPattern1')
          .map((e) => e.offset.x)
          .toList();
      expect(xs, [closeTo(25, 1e-9), closeTo(50, 1e-9), closeTo(75, 1e-9)]);
    });

    test('they FOLLOW the seed when it moves', () {
      final a = patterned();
      regenerateAsmPatterns(a);
      a.occurrences.first.offset = const Vec3(0, 40, 0);
      regenerateAsmPatterns(a);
      for (final e in a.elementsOf('RectangularPattern1')) {
        expect(e.offset.y, closeTo(40, 1e-9),
            reason: 'a baked element would still be on the old row');
      }
    });

    test('the direction follows the component it was picked on', () {
      // M247's claim, applied to a pattern: the inputs are references, not
      // baked geometry, so turning the component the direction came from turns
      // the row. A pattern that baked its AxisRef would keep the old row.
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Rail:1', Vec3.zero, grounded: true))
        ..occurrences.add(occ('Bolt:1', Vec3.zero));
      a.patterns.add(AsmPattern(
        name: 'RectangularPattern1',
        mode: PatternKind.rectangular,
        sources: ['Bolt:1'],
        refDirA: const AsmRef(
            'Rail:1', AsmGeom.axis(Vec3.zero, Vec3(1, 0, 0)), 'Edge'),
      )
        ..countA = 2
        ..distanceA = 30);
      regenerateAsmPatterns(a);
      expect(a.elementsOf('RectangularPattern1').single.offset.x,
          closeTo(30, 1e-9));
      // A quarter turn about Z takes the rail's +X to +Y.
      a.occurrences.first.rot =
          Quat.axisAngle(const Vec3(0, 0, 1), math.pi / 2);
      regenerateAsmPatterns(a);
      final e = a.elementsOf('RectangularPattern1').single;
      expect(e.offset.y, closeTo(30, 1e-9));
      expect(e.offset.x.abs(), lessThan(1e-9));
    });

    test('a circular pattern turns each element with the axis', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bolt:1', const Vec3(40, 0, 0), grounded: true));
      a.patterns.add(AsmPattern(
        name: 'CircularPattern1',
        mode: PatternKind.circular,
        sources: ['Bolt:1'],
        refAxis: const AsmRef(kAssemblyOrigin,
            AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1)), 'Z Axis'),
      )
        ..countC = 4
        ..angleC = 360
        ..distributionC = PatternDistribution.distance
        ..orientation = PatternOrient.rotational);
      regenerateAsmPatterns(a);
      final els = a.elementsOf('CircularPattern1');
      expect(els, hasLength(3));
      // A quarter turn puts the first at (0, 40, 0)...
      expect(els[0].offset.x.abs(), lessThan(1e-9));
      expect(els[0].offset.y, closeTo(40, 1e-9));
      // ...and it is TURNED, not merely carried: its own +X points at +Y.
      expect(els[0].dirToWorld(const Vec3(1, 0, 0)).y, closeTo(1, 1e-9));
      // Fixed orientation carries it round without turning it.
      a.patterns.single.orientation = PatternOrient.fixed;
      regenerateAsmPatterns(a);
      final fixed = a.elementsOf('CircularPattern1')[0];
      expect(fixed.offset.y, closeTo(40, 1e-9));
      expect(fixed.dirToWorld(const Vec3(1, 0, 0)).x, closeTo(1, 1e-9));
    });

    test('an element is DRIVEN, so it has no degrees of freedom', () {
      final a = patterned();
      regenerateAsmPatterns(a);
      final r = solveAssembly(a);
      // The seed is grounded and the three elements are driven, so nothing in
      // this assembly is free.
      expect(r.dof, 0);
      expect(r.fullyConstrained, hasLength(4));
      for (final e in a.elementsOf('RectangularPattern1')) {
        expect(asmBodyIsFree(e), isFalse);
      }
    });

    test('a drag never pulls an element off its grid', () {
      final a = patterned();
      regenerateAsmPatterns(a);
      final e = a.elementsOf('RectangularPattern1').first;
      final was = e.offset;
      solveAssembly(a,
          drag: AsmDrag(e.id, Vec3.zero, const Vec3(0, 0, 500)));
      expect((e.offset - was).length, lessThan(1e-9),
          reason: 'two authorities writing one placement is the failure this '
              'prevents');
    });
  });

  // -------------------------------------------------------------------------
  group('the count stays editable, and says what it costs', () {
    AssemblyModel withConstraintOnElement() {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bolt:1', Vec3.zero, grounded: true))
        ..occurrences.add(occ('Nut:1', const Vec3(0, 100, 0)));
      a.patterns.add(AsmPattern(
        name: 'RectangularPattern1',
        mode: PatternKind.rectangular,
        sources: ['Bolt:1'],
        refDirA: const AsmRef(kAssemblyOrigin,
            AsmGeom.axis(Vec3.zero, Vec3(1, 0, 0)), 'X Axis'),
      )
        ..countA = 4
        ..distanceA = 25);
      regenerateAsmPatterns(a);
      return a;
    }

    test('an element keeps its id, and therefore its relationships, when the '
        'count grows', () {
      final a = withConstraintOnElement();
      final ids = a.elementsOf('RectangularPattern1').map((e) => e.id).toList();
      a.patterns.single.countA = 6;
      regenerateAsmPatterns(a);
      final after = a.elementsOf('RectangularPattern1').map((e) => e.id);
      expect(after, containsAll(ids),
          reason: 'element 3 is element 3 however the count is edited');
      expect(a.elementsOf('RectangularPattern1'), hasLength(5));
    });

    test('shrinking takes the highest elements, and their relationships, and '
        'says so', () {
      final a = withConstraintOnElement();
      final last = a.elementsOf('RectangularPattern1').last;
      a.constraints.add(AsmConstraint(
        name: 'Mate1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: AsmRef(last.id,
            const AsmGeom.plane(Vec3(0, 10, 0), Vec3(0, 1, 0)), 'Face'),
        b: const AsmRef('Nut:1',
            AsmGeom.plane(Vec3(0, -10, 0), Vec3(0, -1, 0)), 'Face'),
      ));
      final kept = a.elementsOf('RectangularPattern1')[0].id;
      a.patterns.single.countA = 2;
      final removed = regenerateAsmPatterns(a);
      expect(removed, contains(last.id));
      expect(a.byId(kept), isNotNull, reason: 'element 2 is untouched');
      expect(a.constraints, isEmpty,
          reason: 'a relationship to a component that is gone is not a '
              'relationship — and the panel says how many went');
    });

    test('suppressing an element hides it rather than deleting it', () {
      final a = withConstraintOnElement();
      a.patterns.single.suppressed.add(3);
      regenerateAsmPatterns(a);
      final els = a.elementsOf('RectangularPattern1');
      expect(els, hasLength(3), reason: 'still three, one of them dark');
      expect(els.firstWhere((e) => e.patternElement == 3).visible, isFalse);
      // ...and restoring it brings it back, with its own id.
      a.patterns.single.suppressed.remove(3);
      regenerateAsmPatterns(a);
      expect(a.elementsOf('RectangularPattern1')
          .firstWhere((e) => e.patternElement == 3)
          .visible, isTrue);
    });

    test('deleting the pattern deletes its elements', () {
      final a = withConstraintOnElement();
      a.removePattern('RectangularPattern1');
      expect(a.elementsOf('RectangularPattern1'), isEmpty);
      expect(a.occurrences.map((o) => o.id), ['Bolt:1', 'Nut:1']);
    });

    test('deleting the SEED deletes the pattern with it', () {
      final a = withConstraintOnElement();
      a.remove(a.byId('Bolt:1')!);
      expect(a.patterns, isEmpty);
      expect(a.occurrences.map((o) => o.id), ['Nut:1']);
    });

    test('an orphaned element is swept up rather than left unplaceable', () {
      final a = withConstraintOnElement();
      a.patterns.clear(); // a hand-edited document
      regenerateAsmPatterns(a);
      expect(a.occurrences.map((o) => o.id), ['Bolt:1', 'Nut:1']);
    });
  });

  // -------------------------------------------------------------------------
  group('Mirror Component', () {
    test('the copy is a mirrored occurrence of the SAME part', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(30, 0, 0),
            grounded: true));
      a.patterns.add(AsmPattern(
        name: 'Mirror1',
        mode: PatternKind.mirror,
        sources: ['Bracket:1'],
        refPlane: const AsmRef(kAssemblyOrigin,
            AsmGeom.plane(Vec3.zero, Vec3(1, 0, 0)), 'YZ Plane'),
      ));
      regenerateAsmPatterns(a);
      final m = a.elementsOf('Mirror1').single;
      expect(m.offset.x, closeTo(-30, 1e-9));
      expect(m.mirrored, isTrue);
      expect(identical(m.part, a.occurrences.first.part), isTrue,
          reason: 'rule 1 — no mirrored part document');
      // Every point of the seed lands on its own reflection.
      for (final l in const [Vec3(0, 0, 0), Vec3(5, -3, 2), Vec3(-8, 1, 9)]) {
        final want = reflectWorld(
            a.occurrences.first.toWorld(l), Vec3.zero, const Vec3(1, 0, 0));
        expect((m.toWorld(l) - want).length, lessThan(1e-9));
      }
    });

    test('the mirror plane is anchored on the FACE, not on the record point',
        () {
      // M244's trap, and for a mirror it is not cosmetic: the plane's position
      // decides where the copy lands. facedBox's record point sits ON the
      // plane but 250 mm to one side, exactly as OCCT's does; a mirror that
      // used it would still be right, so this pins the case where it is NOT —
      // an anchor that has to be projected back onto the plane.
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(30, 0, 0),
            grounded: true))
        ..occurrences.add(occ('Wall:1', Vec3.zero, grounded: true));
      a.patterns.add(AsmPattern(
        name: 'Mirror1',
        mode: PatternKind.mirror,
        sources: ['Bracket:1'],
        // The record point is 250 mm off along the plane; the anchor is on it.
        refPlane: const AsmRef('Wall:1',
            AsmGeom.plane(Vec3(0, 250, 0), Vec3(1, 0, 0)), 'Face',
            anchor: Vec3(0, 0, 0)),
      ));
      regenerateAsmPatterns(a);
      expect(a.elementsOf('Mirror1').single.offset.x, closeTo(-30, 1e-9));
    });

    test('mirroring a mirrored component gives back a right hand', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(30, 0, 0),
            grounded: true)
          ..reflect = const Vec3(0, 0, 1));
      a.patterns.add(AsmPattern(
        name: 'Mirror1',
        mode: PatternKind.mirror,
        sources: ['Bracket:1'],
        refPlane: const AsmRef(kAssemblyOrigin,
            AsmGeom.plane(Vec3.zero, Vec3(1, 0, 0)), 'YZ Plane'),
      ));
      regenerateAsmPatterns(a);
      expect(a.elementsOf('Mirror1').single.mirrored, isFalse);
    });

    test('a mirrored element renders the right way out', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bracket:1', const Vec3(30, 0, 0),
            grounded: true));
      a.patterns.add(AsmPattern(
        name: 'Mirror1',
        mode: PatternKind.mirror,
        sources: ['Bracket:1'],
        refPlane: const AsmRef(kAssemblyOrigin,
            AsmGeom.plane(Vec3.zero, Vec3(1, 0, 0)), 'YZ Plane'),
      ));
      regenerateAsmPatterns(a);
      final cam = frontCam();
      final m = a.elementsOf('Mirror1').single;
      final placed = placedComponents(a);
      expect(placed, hasLength(2));
      expect(pickOccurrence(a, cam, cam.project(m.toWorld(Vec3.zero)))?.id,
          m.id);
    });
  });

  // -------------------------------------------------------------------------
  group('associative — bolts that follow a hole pattern', () {
    /// A bracket whose part carries a four-hole rectangular pattern.
    AssemblyModel bolted({int holes = 4, double step = 20}) {
      final bracket = occ('Bracket:1', Vec3.zero, grounded: true);
      bracket.part!.features.add(PatternFeature(
        name: 'HolePattern1',
        bodyName: 'Solid1',
        mode: PatternKind.rectangular,
        sources: const ['Hole1'],
        dirA: AxisRef(0, 0, 0, 1, 0, 0),
        countA: holes,
        distanceA: step,
        distributionA: PatternDistribution.spacing,
      ));
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(bracket)
        ..occurrences.add(occ('Bolt:1', Vec3.zero, grounded: true));
      a.patterns.add(AsmPattern(
        name: 'RectangularPattern1',
        mode: PatternKind.rectangular,
        sources: ['Bolt:1'],
        driver: ('Bracket:1', 'HolePattern1'),
      ));
      return a;
    }

    test('the bolts land on the holes', () {
      final a = bolted();
      regenerateAsmPatterns(a);
      final xs = a
          .elementsOf('RectangularPattern1')
          .map((e) => e.offset.x)
          .toList();
      expect(xs, [closeTo(20, 1e-9), closeTo(40, 1e-9), closeTo(60, 1e-9)]);
    });

    test('changing the PART changes the assembly, with no edit here', () {
      // The payoff of rule 1: M245 made o.part the one model for that
      // document, so this is literally the part being edited in its own tab.
      final a = bolted();
      regenerateAsmPatterns(a);
      expect(a.elementsOf('RectangularPattern1'), hasLength(3));
      final hp = a.byId('Bracket:1')!.part!.features
          .whereType<PatternFeature>()
          .single;
      hp.countA = 6;
      regenerateAsmPatterns(a);
      expect(a.elementsOf('RectangularPattern1'), hasLength(5),
          reason: 'the bolts follow the holes because the link is live');
    });

    test('the layout is lifted out of the HOST component frame', () {
      // The bolt is not the bracket, so the displacement has to be expressed
      // in the assembly's frame rather than assumed to be at the bracket's
      // origin. Turn the bracket and the row of bolts turns with it.
      final a = bolted();
      a.byId('Bracket:1')!.rot =
          Quat.axisAngle(const Vec3(0, 0, 1), math.pi / 2);
      regenerateAsmPatterns(a);
      final e = a.elementsOf('RectangularPattern1').first;
      expect(e.offset.y, closeTo(20, 1e-9));
      expect(e.offset.x.abs(), lessThan(1e-9));
    });

    test('a driver that has gone is reported, not guessed at', () {
      final a = bolted();
      regenerateAsmPatterns(a);
      a.byId('Bracket:1')!.part!.features.removeWhere(
          (f) => f is PatternFeature);
      regenerateAsmPatterns(a);
      expect(a.patterns.single.error, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the document', () {
    test('a pattern and its elements survive a round trip', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bolt:1', Vec3.zero, grounded: true));
      a.patterns.add(AsmPattern(
        name: 'RectangularPattern1',
        mode: PatternKind.rectangular,
        sources: ['Bolt:1'],
        refDirA: const AsmRef(kAssemblyOrigin,
            AsmGeom.axis(Vec3.zero, Vec3(1, 0, 0)), 'X Axis'),
      )
        ..countA = 3
        ..distanceA = 25
        ..suppressed.add(3));
      regenerateAsmPatterns(a);
      final b = AssemblyModel('Gearbox')..loadJson(a.toJson());
      expect(b.patterns, hasLength(1));
      final p = b.patterns.single;
      expect(p.countA, 3);
      expect(p.distanceA, closeTo(25, 1e-9));
      expect(p.suppressed, contains(3));
      expect(p.refDirA?.geom.dir.x, closeTo(1, 1e-9));
      // The ELEMENTS come back too, under their own ids, because the
      // relationships on them name those ids.
      expect(b.elementsOf('RectangularPattern1'), hasLength(2));
      expect(b.elementsOf('RectangularPattern1').first.patternElement, 2);
    });

    test('an assembly with no patterns writes what it wrote before', () {
      final a = AssemblyModel('Gearbox')
        ..occurrences.add(occ('Bolt:1', Vec3.zero));
      expect(a.toJson().containsKey('patterns'), isFalse);
      expect(
          (a.toJson()['occurrences'] as List).first.containsKey('pat'), isFalse);
    });
  });
}
