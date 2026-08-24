// M242 — the COMMAND path of Abhängig machen: tap, dialog, solve, browser.
//
// m242_asm_solver_test.dart pins the mathematics. This pins everything between
// a finger and it, which is where the failures that a user would actually meet
// live:
//
//   * PICKING. A tap has to come back as geometry in the COMPONENT'S OWN
//     frame, or the constraint means "where that face used to be" and drifts
//     the first time the solver moves anything. This is the single most
//     load-bearing claim in the milestone and it cannot be seen on screen —
//     a wrong frame looks exactly right until the second solve.
//   * THE SESSION. Inventor's dialog advances its own arming, refuses two
//     picks on one component, keeps its settings across Apply and drops only
//     what you pointed at. Each of those is one line of state that a refactor
//     can quietly invert.
//   * THE PREVIEW. It moves the REAL components and Cancel has to put them
//     back. Nothing else in this app moves geometry it has not committed, so
//     there is no second implementation to compare against.
//   * THE BROWSER AND THE RIBBON, so the rows and the button that reach all
//     of the above cannot be wired to nothing.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_pick.dart';
import 'package:prototype/asm_solver.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/l10n/cad_terms.dart';
import 'package:prototype/widgets/constraint_dialog.dart';
import 'package:prototype/widgets/native_browser.dart';

// ---------------------------------------------------------------------------
// fakes
// ---------------------------------------------------------------------------

/// A box centred on the origin, WITH the v4 face metadata the picker reads.
///
/// m240's boxSolid deliberately carries none — it exists to be drawn and hit
/// tested as a shape. This one has to answer "which surface is that", so it
/// carries one 15-double record per face: a plane, its outward normal, and
/// the point the kernel would have put on it.
KernelSolid facedBox({double h = 10}) {
  final c = [
    [-h, -h, -h],
    [h, -h, -h],
    [h, h, -h],
    [-h, h, -h],
    [-h, -h, h],
    [h, -h, h],
    [h, h, h],
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
      n[0] * h, n[1] * h, n[2] * h, // a point ON it
      n[0], n[1], n[2], // outward normal
      0, 0, 0, // x-direction of the frame, unused here
      0, // radius
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
  )..solid = facedBox(h: h));
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

/// An app with an open assembly holding [os].
AppState asmApp(String tag, List<AssemblyOccurrence> os) {
  final app = freshApp(tag);
  final a = AssemblyModel('Gearbox');
  a.occurrences.addAll(os);
  app.assemblies['Gearbox'] = a;
  app.openTabs.add('Gearbox');
  app.curTab = 'Gearbox';
  return app;
}

/// Looking down +Z from the -Z side, 120 mm across.
Cam3 frontCam([Size size = const Size(800, 600)]) =>
    Cam3(PartCamera(az: 0, pol: 1.5707963267948966, halfH: 60), size);

/// The two languages' strings, so a test can name what the user reads without
/// having to be in that locale to do it.
final de = L.stringsFor(kDe);
final en = L.stringsFor(kEn);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => L.set(kDe));

  // -------------------------------------------------------------------------
  group('picking a reference', () {
    test('a face comes back in the COMPONENT\'S OWN coordinates', () {
      // The component sits 40 mm along +X. Its front face is at world
      // x = 40 + something and at LOCAL x = something — and it is the local
      // one that has to be stored, or the constraint stops naming this face
      // the moment the solver moves the part.
      final o = occ('Bracket:1', const Vec3(40, 0, 0));
      final a = AssemblyModel('A')..occurrences.add(o);
      final cam = frontCam();
      final pick = pickAsmRef(a, cam, cam.project(const Vec3(40, 0, 0)));
      expect(pick, isNotNull);
      expect(pick!.ref.occurrence, 'Bracket:1');
      expect(pick.ref.geom.isPlane, isTrue);
      // Local: on the box's own surface, so every coordinate is within its
      // own half-size. A world-space answer would carry the 40.
      expect(pick.ref.geom.at.x.abs(), lessThanOrEqualTo(10 + 1e-9),
          reason: 'stored geometry must be LOCAL, not world');
      // And the world form, which the preview and the marker need, does.
      expect(pick.world.at.x, closeTo(40 + pick.ref.geom.at.x, 1e-9));
    });

    test('a ROTATED component reports the same local face and a turned '
        'world one', () {
      // A quarter turn about Y takes the box's -Z face to face -X in world.
      // The stored geometry must not notice; the world form must.
      final turned = Quat.axisAngle(const Vec3(0, 1, 0), 1.5707963267948966);
      final o = occ('Bracket:1', Vec3.zero, rot: turned);
      final a = AssemblyModel('A')..occurrences.add(o);
      final cam = frontCam();
      final pick = pickAsmRef(a, cam, cam.project(Vec3.zero));
      expect(pick, isNotNull);
      final local = pick!.ref.geom, world = pick.world;
      // The local normal is one of the box's own six axes...
      expect(local.dir.length, closeTo(1, 1e-6));
      // ...and the world one is that normal, turned.
      final want = o.dirToWorld(local.dir);
      expect((world.dir - want).length, lessThan(1e-9));
    });

    test('a hidden component is not pickable, and neither is a missing one',
        () {
      final o = occ('Bracket:1', Vec3.zero);
      final a = AssemblyModel('A')..occurrences.add(o);
      final cam = frontCam();
      expect(pickAsmRef(a, cam, cam.project(Vec3.zero)), isNotNull);
      o.visible = false;
      expect(pickAsmRef(a, cam, cam.project(Vec3.zero)), isNull);
    });

    test('the assembly origin answers only when it is switched on', () {
      // Nothing else in the document, so if a plane answers at all it is
      // this one.
      final a = AssemblyModel('A');
      final cam = frontCam();
      expect(pickAsmRef(a, cam, const Offset(400, 300)), isNull,
          reason: 'an invisible origin plane is not on screen');
      a.vis['xy'] = true;
      final pick = pickAsmRef(a, cam, const Offset(400, 300));
      expect(pick, isNotNull);
      expect(pick!.ref.isAssemblyOrigin, isTrue);
      expect(pick.ref.occurrence, kAssemblyOrigin);
      expect(pick.ref.geom.isPlane, isTrue);
    });

    test('a component in FRONT wins over one behind it', () {
      // Which of the two is nearer is asked of Cam3.depth rather than
      // asserted by sign, the rule m240's own stacked-pick test set: the
      // renderer's convention is the one picking has to agree with.
      final a = AssemblyModel('A')
        ..occurrences.add(occ('A:1', const Vec3(0, 0, -30)))
        ..occurrences.add(occ('B:1', const Vec3(0, 0, 30)));
      final cam = frontCam();
      final nearer =
          cam.depth(const Vec3(0, 0, -30)) > cam.depth(const Vec3(0, 0, 30))
              ? 'A:1'
              : 'B:1';
      expect(pickAsmRef(a, cam, cam.project(Vec3.zero))?.ref.occurrence,
          nearer);
    });

    test('a tap on nothing is null, not the nearest thing on screen', () {
      final a = AssemblyModel('A')..occurrences.add(occ('A:1', Vec3.zero));
      expect(pickAsmRef(a, frontCam(), const Offset(3, 3)), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the Place Constraint session', () {
    AppState twoBoxes([String tag = 'ipc_m242_sess']) => asmApp(tag, [
          occ('Base:1', Vec3.zero, grounded: true),
          occ('Lid:1', const Vec3(40, 0, 0)),
        ]);

    AsmRef refOf(AppState app, String id, Vec3 at, Vec3 n) =>
        AsmRef(id, AsmGeom.plane(at, n), 'Face');

    test('it opens on Mate, with selection 1 armed', () {
      final app = twoBoxes();
      app.openConstraint();
      final s = app.constraintSession!;
      expect(s.kind, AsmKind.mate);
      expect(s.solution, AsmSolution.mate);
      expect(s.tab, AsmTab.assembly);
      expect(s.needed, 2);
      expect(s.armed, 0);
      expect(s.complete, isFalse);
      expect(app.constraintPicking, isTrue);
    });

    test('a pick fills the armed slot and the arming ADVANCES', () {
      final app = twoBoxes();
      app.openConstraint();
      final s = app.constraintSession!;
      final cam = frontCam();
      final a = app.currentAssembly!;

      final first = pickAsmRef(a, cam, cam.project(Vec3.zero))!;
      expect(app.pickConstraintRef(first), isTrue);
      expect(s.a, isNotNull);
      expect(s.armed, 1, reason: 'Inventor advances to selection 2');

      final second = pickAsmRef(a, cam, cam.project(const Vec3(40, 0, 0)))!;
      app.pickConstraintRef(second);
      expect(s.b, isNotNull);
      expect(s.complete, isTrue);
    });

    test('the second pick refuses the component the first came from', () {
      final app = twoBoxes();
      app.openConstraint();
      final s = app.constraintSession!;
      final cam = frontCam();
      final a = app.currentAssembly!;
      final one = pickAsmRef(a, cam, cam.project(Vec3.zero))!;
      app.pickConstraintRef(one);
      // The same component again: consumed (so the viewport does not also
      // treat it as a component grab) but NOT stored.
      expect(app.pickConstraintRef(one), isTrue);
      expect(s.b, isNull);
      expect(app.message, isNotNull, reason: 'and it says why');
    });

    test('tapping the armed button again CLEARS that selection', () {
      final app = twoBoxes();
      app.openConstraint();
      final s = app.constraintSession!;
      final cam = frontCam();
      app.pickConstraintRef(
          pickAsmRef(app.currentAssembly!, cam, cam.project(Vec3.zero))!);
      expect(s.a, isNotNull);
      app.armConstraintSelection(0);
      expect(s.armed, 0);
      app.armConstraintSelection(0);
      expect(s.a, isNull, reason: 're-picking selection 1 has to be possible');
    });

    test('Symmetry and an explicit reference vector ask for a THIRD', () {
      final app = twoBoxes();
      app.openConstraint();
      final s = app.constraintSession!;
      expect(s.needed, 2);
      app.setConstraintKind(AsmKind.symmetry);
      expect(s.needed, 3);
      app.setConstraintKind(AsmKind.angle);
      expect(s.needed, 2);
      app.setConstraintSolution(AsmSolution.explicitVector);
      expect(s.needed, 3);
      // And dropping back to a two-selection solution discards the third,
      // which would otherwise be silently written onto the constraint.
      app.setConstraintSolution(AsmSolution.undirectedAngle);
      expect(s.needed, 2);
      expect(s.c, isNull);
    });

    test('changing the TAB changes the type to that tab\'s first', () {
      final app = twoBoxes();
      app.openConstraint();
      final s = app.constraintSession!;
      app.setConstraintTab(AsmTab.motion);
      expect(s.kind, AsmKind.rotation);
      expect(valueKindOf(s.kind), AsmValueKind.ratio);
      app.setConstraintTab(AsmTab.transitional);
      expect(s.kind, AsmKind.transitional);
      app.setConstraintTab(AsmTab.assembly);
      expect(s.kind, AsmKind.mate);
    });

    test('Apply creates the constraint, names it Inventor\'s way, and '
        'clears only the picks', () {
      final app = twoBoxes();
      final a = app.currentAssembly!;
      app.openConstraint();
      final s = app.constraintSession!;
      s.a = refOf(app, 'Base:1', const Vec3(0, 0, 10), const Vec3(0, 0, 1));
      s.b = refOf(app, 'Lid:1', const Vec3(0, 0, -10), const Vec3(0, 0, -1));
      app.setConstraintValue(2);

      expect(app.applyConstraint(), isTrue);
      expect(a.constraints, hasLength(1));
      expect(a.constraints.single.name, 'Mate:1');
      expect(a.constraints.single.value, 2);
      // The dialog is still open and still on Mate with the offset it had —
      // Inventor keeps the settings across an Apply and drops the picks.
      expect(app.constraintSession, isNotNull);
      expect(s.kind, AsmKind.mate);
      expect(s.value, 2);
      expect(s.a, isNull);
      expect(s.b, isNull);
      expect(s.armed, 0);

      // A second one counts on.
      s.a = refOf(app, 'Base:1', const Vec3(10, 0, 0), const Vec3(1, 0, 0));
      s.b = refOf(app, 'Lid:1', const Vec3(-10, 0, 0), const Vec3(-1, 0, 0));
      app.applyConstraint();
      expect(a.constraints.last.name, 'Mate:2');
    });

    test('a pair this type cannot act on is refused, with a reason', () {
      final app = twoBoxes();
      app.openConstraint();
      final s = app.constraintSession!;
      app.setConstraintKind(AsmKind.tangent);
      // Two flat faces: Inventor refuses Tangent on them, because there is no
      // tangency between two planes.
      s.a = refOf(app, 'Base:1', const Vec3(0, 0, 10), const Vec3(0, 0, 1));
      s.b = refOf(app, 'Lid:1', const Vec3(0, 0, -10), const Vec3(0, 0, -1));
      expect(app.applyConstraint(), isFalse);
      expect(app.currentAssembly!.constraints, isEmpty);
      expect(app.constraintRejectionText('tangentNeedsRound'), isNotEmpty);
    });

    test('OK applies and closes; OK with nothing picked is a Cancel', () {
      final app = twoBoxes();
      app.openConstraint();
      app.okConstraint();
      expect(app.constraintSession, isNull);
      expect(app.currentAssembly!.constraints, isEmpty);

      app.openConstraint();
      final s = app.constraintSession!;
      s.a = refOf(app, 'Base:1', const Vec3(0, 0, 10), const Vec3(0, 0, 1));
      s.b = refOf(app, 'Lid:1', const Vec3(0, 0, -10), const Vec3(0, 0, -1));
      app.okConstraint();
      expect(app.constraintSession, isNull);
      expect(app.currentAssembly!.constraints, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('the preview', () {
    AppState pair() => asmApp('ipc_m242_prev', [
          occ('Base:1', Vec3.zero, grounded: true),
          occ('Lid:1', const Vec3(40, 0, 0)),
        ]);

    /// Fills both selections THROUGH the command, not by assignment: the
    /// preview refreshes on a pick, and a test that wrote the slots directly
    /// would be exercising a path the viewport never takes.
    void fillMate(AppState app) {
      app.pickConstraintRef(AsmPick(
          AsmRef('Base:1',
              const AsmGeom.plane(Vec3(0, 0, 10), Vec3(0, 0, 1)), 'Face'),
          const AsmGeom.plane(Vec3(0, 0, 10), Vec3(0, 0, 1)),
          0,
          const Vec3(0, 0, 10)));
      app.pickConstraintRef(AsmPick(
          AsmRef('Lid:1',
              const AsmGeom.plane(Vec3(0, 0, -10), Vec3(0, 0, -1)), 'Face'),
          const AsmGeom.plane(Vec3(40, 0, -10), Vec3(0, 0, -1)),
          0,
          const Vec3(40, 0, -10)));
    }

    test('it MOVES the component, and Cancel puts it back exactly', () {
      final app = pair();
      final lid = app.currentAssembly!.byId('Lid:1')!;
      final was = lid.offset;
      app.openConstraint();
      fillMate(app);
      expect((lid.offset - was).length, greaterThan(1e-6),
          reason: 'Show Preview is on by default, so the mate is shown');
      app.cancelConstraint();
      expect((lid.offset - was).length, lessThan(1e-9),
          reason: 'Cancel restores the committed placement exactly');
      expect(app.currentAssembly!.constraints, isEmpty);
    });

    test('with Show Preview off, nothing moves until Apply', () {
      final app = pair();
      final lid = app.currentAssembly!.byId('Lid:1')!;
      final was = lid.offset;
      app.openConstraint();
      app.toggleConstraintPreview();
      expect(app.constraintSession!.showPreview, isFalse);
      fillMate(app);
      expect((lid.offset - was).length, lessThan(1e-9));
      app.applyConstraint();
      expect((lid.offset - was).length, greaterThan(1e-6));
    });

    test('Predict fills the field with what the pair already measures', () {
      final app = pair();
      app.openConstraint();
      final s = app.constraintSession!;
      app.toggleConstraintPreview(); // measure the parts where they are
      fillMate(app);
      app.toggleConstraintPredict();
      expect(s.predict, isTrue);
      // Base's +Z face at z=10, Lid's -Z face at z=-10 and the lid is at
      // x=40 — measured along the first face's normal, they are 20 apart.
      expect(s.value, closeTo(-20, 1e-6));
      // And applying it therefore holds the lid where it is, which is the
      // whole point of the checkbox.
      final was = app.currentAssembly!.byId('Lid:1')!.offset;
      app.applyConstraint();
      final now = app.currentAssembly!.byId('Lid:1')!.offset;
      expect((now.z - was.z).abs(), lessThan(1e-6));
    });
  });

  // -------------------------------------------------------------------------
  group('editing, suppressing and deleting', () {
    AppState mated() {
      final app = asmApp('ipc_m242_edit', [
        occ('Base:1', Vec3.zero, grounded: true),
        occ('Lid:1', const Vec3(40, 0, 0)),
      ]);
      app.currentAssembly!.constraints.add(AsmConstraint(
        name: 'Mate:1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: AsmRef('Base:1',
            const AsmGeom.plane(Vec3(0, 0, 10), Vec3(0, 0, 1)), 'Face'),
        b: AsmRef('Lid:1',
            const AsmGeom.plane(Vec3(0, 0, -10), Vec3(0, 0, -1)), 'Face'),
      ));
      app.solveCurrentAssembly();
      return app;
    }

    test('Edit opens on the constraint and keeps its name', () {
      final app = mated();
      final c = app.currentAssembly!.constraints.single;
      app.openConstraint(edit: c);
      final s = app.constraintSession!;
      expect(s.editing, same(c));
      expect(s.kind, AsmKind.mate);
      expect(s.a, same(c.a));
      expect(s.name, 'Mate:1');
      app.setConstraintValue(5);
      app.okConstraint();
      final after = app.currentAssembly!.constraints;
      expect(after, hasLength(1), reason: 'edit replaces, never appends');
      expect(after.single.name, 'Mate:1');
      expect(after.single.value, 5);
    });

    test('Suppress switches it off and clears its verdict', () {
      final app = mated();
      final c = app.currentAssembly!.constraints.single;
      app.toggleConstraintSuppressed(c);
      expect(c.suppressed, isTrue);
      expect(c.error, isNull);
      // Suppressed constraints give the freedom back.
      expect(app.currentAssembly!.solveSummary.dof, 6);
      app.toggleConstraintSuppressed(c);
      expect(c.suppressed, isFalse);
      expect(app.currentAssembly!.solveSummary.dof, lessThan(6));
    });

    test('Delete removes it and gives the freedom back', () {
      final app = mated();
      final c = app.currentAssembly!.constraints.single;
      app.selectConstraint(c);
      app.deleteConstraint(c);
      expect(app.currentAssembly!.constraints, isEmpty);
      expect(app.currentAssembly!.selectedConstraint, isNull);
      expect(app.currentAssembly!.solveSummary.dof, 6);
    });

    test('deleting the COMPONENT takes its relationships with it', () {
      final app = mated();
      app.deleteOccurrence(app.currentAssembly!.byId('Lid:1')!);
      expect(app.currentAssembly!.constraints, isEmpty,
          reason: 'a constraint to a component that is gone is a dangling '
              'reference, not a constraint');
    });

    test('a constraint survives the document round trip', () async {
      final app = mated();
      app.currentAssembly!.constraints.single.value = 3.5;
      await app.saveAssembly('Gearbox');
      await app.closeTab('Gearbox');
      await app.openAssembly('Gearbox');
      final back = app.currentAssembly!.constraints;
      expect(back, hasLength(1));
      expect(back.single.name, 'Mate:1');
      expect(back.single.value, closeTo(3.5, 1e-9));
      expect(back.single.a.occurrence, 'Base:1');
    });
  });

  // -------------------------------------------------------------------------
  group('dragging', () {
    test('a LOOSE component is translated directly, exactly under the '
        'finger', () {
      final app = asmApp('ipc_m242_drag1', [occ('A:1', Vec3.zero)]);
      final o = app.currentAssembly!.byId('A:1')!;
      app.beginOccurrenceDrag(o, const Vec3(5, 5, 0));
      app.dragOccurrenceTo(const Vec3(25, 5, 0));
      // The GRIP lands on the target, so the body moved by exactly the delta.
      expect((o.toWorld(const Vec3(5, 5, 0)) - const Vec3(25, 5, 0)).length,
          lessThan(1e-9));
      expect(o.offset.x, closeTo(20, 1e-9));
    });

    test('an ATTACHED component goes through the solver and keeps its '
        'constraint', () {
      final app = asmApp('ipc_m242_drag2', [
        occ('Base:1', Vec3.zero, grounded: true),
        occ('Lid:1', const Vec3(0, 0, 20)),
      ]);
      final a = app.currentAssembly!;
      // Lid's -Z face on Base's +Z face: one plane mate, so the lid may
      // still slide in X and Y but not in Z.
      a.constraints.add(AsmConstraint(
        name: 'Mate:1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: AsmRef('Base:1',
            const AsmGeom.plane(Vec3(0, 0, 10), Vec3(0, 0, 1)), 'Face'),
        b: AsmRef('Lid:1',
            const AsmGeom.plane(Vec3(0, 0, -10), Vec3(0, 0, -1)), 'Face'),
      ));
      app.solveCurrentAssembly();
      final lid = a.byId('Lid:1')!;
      final zWas = lid.offset.z;

      app.beginOccurrenceDrag(lid, lid.toWorld(Vec3.zero));
      // Pull 30 mm sideways AND 30 mm along the axis the mate owns.
      app.dragOccurrenceTo(lid.offset + const Vec3(30, 0, 30));
      expect(lid.offset.x, closeTo(30, 0.5),
          reason: 'the direction it is free in follows the finger');
      expect(lid.offset.z, closeTo(zWas, 1e-3),
          reason: 'and the one the mate owns does not move at all');
      expect(a.constraints.single.isSick, isFalse,
          reason: 'the polish pass leaves the mate exactly met');
    });

    test('a GROUNDED component does not move, however hard it is pulled', () {
      final app = asmApp('ipc_m242_drag3',
          [occ('A:1', Vec3.zero, grounded: true)]);
      final o = app.currentAssembly!.byId('A:1')!;
      app.beginOccurrenceDrag(o, Vec3.zero);
      app.dragOccurrenceTo(const Vec3(50, 50, 50));
      expect(o.offset.length, lessThan(1e-12));
    });
  });

  // -------------------------------------------------------------------------
  group('motion is DRIVEN, not solved', () {
    test('turning the driver turns the driven one by the ratio', () {
      final app = asmApp('ipc_m242_motion', [
        occ('Pinion:1', Vec3.zero, grounded: true),
        occ('Gear:1', const Vec3(30, 0, 0)),
      ]);
      final a = app.currentAssembly!;
      a.constraints.add(AsmConstraint(
        name: 'Rotation:1',
        kind: AsmKind.rotation,
        solution: AsmSolution.forward,
        a: AsmRef('Pinion:1',
            const AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1), radius: 10), 'Axis'),
        b: AsmRef('Gear:1',
            const AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1), radius: 20), 'Axis'),
        value: 2,
      ));
      final gear = a.byId('Gear:1')!;
      expect(gear.rot.angle, closeTo(0, 1e-12));
      // A motion constraint is not an equation: solving alone must not move
      // anything.
      app.solveCurrentAssembly();
      expect(gear.rot.angle, closeTo(0, 1e-9));
      // Driving it does.
      final pinion = a.byId('Pinion:1')!;
      driveMotion(a, pinion.id, 0.5);
      expect(gear.rot.angle, closeTo(1.0, 1e-6),
          reason: 'ratio 2: half a turn of the driver is a full one here');
    });
  });

  // -------------------------------------------------------------------------
  group('the browser', () {
    AppState mated(String tag) {
      final app = asmApp(tag, [
        occ('Base:1', Vec3.zero, grounded: true),
        occ('Lid:1', const Vec3(40, 0, 0)),
      ]);
      app.currentAssembly!.constraints.add(AsmConstraint(
        name: 'Mate:1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: AsmRef('Base:1',
            const AsmGeom.plane(Vec3(0, 0, 10), Vec3(0, 0, 1)), 'Face'),
        b: AsmRef('Lid:1',
            const AsmGeom.plane(Vec3(0, 0, -10), Vec3(0, 0, -1)), 'Face'),
      ));
      return app;
    }

    test('the Relationships folder lists them once expanded', () {
      final app = mated('ipc_m242_tree1');
      var rows = buildBrowserRows(app, expanded: {});
      expect(rows.where((r) => r.id.startsWith(kIdConstraint)), isEmpty,
          reason: 'a collapsed folder lists nothing');

      rows = buildBrowserRows(app, expanded: {kIdRelationships});
      final rel = rows.where((r) => r.id.startsWith(kIdConstraint)).toList();
      expect(rel, hasLength(1));
      expect(rel.single.id, '${kIdConstraint}Mate:1',
          reason: 'the name carries a colon, so the row id must keep it whole');
      expect(rel.single.label, 'Mate:1');
    });

    test('a component with relationships is expandable, and nests them', () {
      final app = mated('ipc_m242_tree2');
      var rows = buildBrowserRows(app, expanded: {});
      final lid = rows.firstWhere((r) => r.id == '${kIdComponent}Lid:1');
      expect(lid.expandable, isTrue);
      rows = buildBrowserRows(app, expanded: {'${kIdComponent}Lid:1'});
      expect(rows.where((r) => r.id.startsWith(kIdConstraint)), hasLength(1));
    });

    test('a SICK constraint is marked, and a suppressed one is dimmed', () {
      final app = mated('ipc_m242_tree3');
      final c = app.currentAssembly!.constraints.single;
      // Both ends grounded: the one failure a user can act on directly.
      app.currentAssembly!.byId('Lid:1')!.grounded = true;
      app.solveCurrentAssembly();
      expect(c.isSick, isTrue);
      expect(app.constraintErrorText(c), isNotEmpty);
      var row = buildBrowserRows(app, expanded: {kIdRelationships})
          .firstWhere((r) => r.id.startsWith(kIdConstraint));
      expect(row.tint, 'red');

      app.toggleConstraintSuppressed(c);
      row = buildBrowserRows(app, expanded: {kIdRelationships})
          .firstWhere((r) => r.id.startsWith(kIdConstraint));
      expect(row.dim, isTrue);
      expect(row.tint, isNot('red'),
          reason: 'switched off is not the same as broken');
    });
  });

  // -------------------------------------------------------------------------
  group('the dialog', () {
    Future<AppState> pumpDialog(WidgetTester t, {AsmKind? kind}) async {
      final app = asmApp('ipc_m242_dlg', [
        occ('Base:1', Vec3.zero, grounded: true),
        occ('Lid:1', const Vec3(40, 0, 0)),
      ]);
      app.openConstraint();
      if (kind != null) app.setConstraintKind(kind);
      await t.binding.setSurfaceSize(const Size(1024, 768));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: app,
            builder: (_, __) => Stack(children: [ConstraintDialog(app: app)]),
          ),
        ),
      ));
      await t.pump();
      return app;
    }

    testWidgets('it is Inventor\'s four tabs and five assembly types',
        (t) async {
      L.set(kEn);
      await pumpDialog(t);
      final l = en;
      for (final label in [
        l.dlgPlaceConstraint,
        l.tabAsmAssembly,
        l.tabAsmMotion,
        l.tabAsmTransitional,
        l.tabAsmConstraintSet,
        l.grpAsmType,
        l.grpAsmSelections,
        l.grpAsmSolution,
        l.lblAsmOffset,
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      // Two numbered selection buttons for a Mate, and the OK/Cancel/Apply
      // row Inventor puts under everything.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text(l.ok), findsOneWidget);
      expect(find.text(l.cancel), findsOneWidget);
      expect(find.text(l.apply), findsOneWidget);
      expect(find.text('>>'), findsOneWidget);
    });

    testWidgets('the value label follows the TYPE', (t) async {
      L.set(kEn);
      final app = await pumpDialog(t);
      expect(find.text(en.lblAsmOffset), findsOneWidget);
      app.setConstraintKind(AsmKind.angle);
      await t.pump();
      expect(find.text(en.lblAsmAngle), findsOneWidget);
      expect(find.text(en.lblAsmOffset), findsNothing);
      app.setConstraintTab(AsmTab.motion);
      await t.pump();
      expect(find.text(en.lblAsmRatio), findsOneWidget);
    });

    testWidgets('Symmetry grows a THIRD selection button', (t) async {
      L.set(kEn);
      final app = await pumpDialog(t);
      expect(find.text('3'), findsNothing);
      app.setConstraintKind(AsmKind.symmetry);
      await t.pump();
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('>> reveals Name and Default to Undirected', (t) async {
      L.set(kEn);
      final app = await pumpDialog(t, kind: AsmKind.angle);
      expect(find.text(en.lblAsmName), findsNothing);
      await t.tap(find.text('>>'));
      await t.pump();
      expect(find.text(en.lblAsmName), findsOneWidget);
      expect(find.text(en.cbAsmDefaultUndirected), findsOneWidget);
      await t.tap(find.text(en.cbAsmDefaultUndirected));
      await t.pump();
      expect(app.defaultUndirectedAngle, isTrue);
      // And the preference acts: the NEXT angle opens undirected.
      app.setConstraintKind(AsmKind.mate);
      app.setConstraintKind(AsmKind.angle);
      expect(app.constraintSession!.solution, AsmSolution.undirectedAngle);
    });

    testWidgets('Cancel closes it', (t) async {
      L.set(kEn);
      final app = await pumpDialog(t);
      await t.tap(find.text(en.cancel));
      await t.pump();
      expect(app.constraintSession, isNull);
    });

    testWidgets('it renders in German too', (t) async {
      L.set(kDe);
      await pumpDialog(t);
      expect(find.text(de.dlgPlaceConstraint), findsOneWidget);
      expect(find.text(de.tabAsmAssembly), findsOneWidget);
      expect(find.text(de.lblAsmOffset), findsOneWidget);
      // No English left showing.
      expect(find.text('Place Constraint'), findsNothing);
      expect(find.text('Offset:'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('the type and solution names', () {
    test('every kind and every solution has a localised name, in both', () {
      for (final l in [de, en]) {
        for (final k in AsmKind.values) {
          expect(constraintLabel(l, k), isNotEmpty, reason: '$k');
        }
        for (final s in AsmSolution.values) {
          expect(solutionLabel(l, s), isNotEmpty, reason: '$s');
        }
      }
      // And German is not English: these are the two the user reads.
      expect(constraintLabel(de, AsmKind.insert),
          isNot(constraintLabel(en, AsmKind.insert)));
    });
  });
}
