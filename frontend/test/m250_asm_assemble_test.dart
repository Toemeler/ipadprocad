// M250 — the rest of the Assemble tab: Create Component, Free Move, Free
// Rotate, and the Representations folder.
//
// What is worth pinning here, and what each of these would look like if it
// broke silently:
//
//   * PLACEMENT.INVERSE. Edit in place expresses every other component in the
//     edited part's own frame, and there is no second way to check that
//     arithmetic — a wrong inverse draws the assembly somewhere plausible but
//     wrong, and only a person who knew where the bracket really sat would
//     notice. Asserted against the identity, mirrored case included.
//
//   * THE CONTEXT excludes the component being edited. Including it would
//     draw the part twice, in the same place, doubling every edge — which
//     reads as "the renderer got heavier" rather than as a bug.
//
//   * CREATE COMPONENT places the new part ON the plane that was picked, with
//     its own XY coincident with it. That is what makes the sketch that opens
//     next land on the right plane, and it is the one piece of geometry in the
//     command.
//
//   * FREE MOVE DOES NOT SOLVE, and the next solve puts the component back.
//     That is Inventor's behaviour and it is the whole difference between the
//     command and the drag the viewport has had since M242. A Free Move that
//     went through the solver would look identical until you tried to use it.
//
//   * A VIEW REPRESENTATION is written back when you LEAVE it. Without that,
//     going back to Default restores whatever Default held the first time it
//     was written, and the command reads as broken.
//
//   * THE .PAS FILE is byte-identical for an assembly that never touches
//     representations. Every milestone in this file's history has kept that
//     promise and this one has to as well.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_pick.dart';
import 'package:prototype/asm_reps.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/widgets/native_browser.dart';
import 'package:prototype/widgets/ribbon.dart';

// ---------------------------------------------------------------------------
// fakes — the same shapes m240 and m248 use, kept local for the reason they
// are there: a test file that imported another test file's helpers would make
// one suite's refactor break the other's.
// ---------------------------------------------------------------------------

KernelSolid boxSolid({double h = 10}) {
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
  const faces = [
    [0, 3, 2, 1],
    [4, 5, 6, 7],
    [0, 1, 5, 4],
    [3, 7, 6, 2],
    [0, 4, 7, 3],
    [1, 2, 6, 5],
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
  for (var f = 0; f < faces.length; f++) {
    final base = pos.length ~/ 3;
    for (final vi in faces[f]) {
      pos.addAll(c[vi]);
      nor.addAll(normals[f]);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }
  return KernelSolid(
    OcctMeshData(
      Float64List.fromList(pos),
      Float64List.fromList(nor),
      Int32List.fromList(idx),
      Int32List.fromList([0]),
      Float64List(0),
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
  )..solid = boxSolid(h: h));
  return p;
}

AssemblyOccurrence occ(String id, Vec3 at,
        {bool grounded = false, Quat rot = Quat.identity, Vec3? reflect}) =>
    AssemblyOccurrence(
      id: id,
      source: id.split(':').first,
      part: boxPart(id.split(':').first),
      offset: at,
      rot: rot,
      reflect: reflect,
      grounded: grounded,
    );

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

/// A pick of a PLANE, built by hand: the assembly's own XY plane through
/// [at], with the outward normal [n].
///
/// Built rather than ray-cast, because what Create Component does with a pick
/// is the thing under test and pickAsmRef has its own suite (M242/M246).
AsmPick planePick(Vec3 at, Vec3 n) => AsmPick(
      AsmRef(kAssemblyOrigin, AsmGeom.plane(at, n), 'XY Plane'),
      AsmGeom.plane(at, n),
      0,
      at,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => L.set(kDe));

  // -------------------------------------------------------------------------
  group('a placement can be undone', () {
    test('inverse round-trips a point, rigid and mirrored', () {
      final rnd = math.Random(250);
      Vec3 rv() => Vec3(rnd.nextDouble() * 40 - 20, rnd.nextDouble() * 40 - 20,
          rnd.nextDouble() * 40 - 20);
      for (var i = 0; i < 200; i++) {
        final p = Placement(Quat.axisAngle(rv(), rnd.nextDouble() * 6), rv(),
            i.isEven ? null : rv().normalized());
        final v = rv();
        expect((p.inverse.apply(p.apply(v)) - v).length, lessThan(1e-9),
            reason: 'point $i');
        final d = rv();
        expect((p.inverse.applyDir(p.applyDir(d)) - d).length, lessThan(1e-9),
            reason: 'direction $i');
      }
    });

    test('inverse * placement is the identity, mirror included', () {
      for (final p in [
        Placement(Quat.axisAngle(const Vec3(1, 2, 3), 0.7), const Vec3(5, 6, 7)),
        Placement(Quat.axisAngle(const Vec3(0, 1, 0), 2.1), const Vec3(-3, 4, 9),
            const Vec3(1, 0, 0)),
      ]) {
        final id = p.inverse * p;
        // Two reflections annihilate into a rotation, so the identity here
        // must carry no mirror at all — a composed placement that still held
        // one would be a left-handed "identity", which is exactly the bug
        // Placement.operator* was written to make impossible.
        expect(id.mirrored, isFalse);
        expect(id.at.length, lessThan(1e-9));
        expect(id.rot.angle, lessThan(1e-6));
      }
    });

    test('a mirrored placement inverts to a mirrored one', () {
      final p = Placement(Quat.axisAngle(const Vec3(0, 0, 1), 1.0),
          const Vec3(10, 0, 0), const Vec3(1, 0, 0));
      expect(p.inverse.mirrored, isTrue,
          reason: 'handedness cannot be undone by a rigid transform');
    });
  });

  // -------------------------------------------------------------------------
  group('the in-place context', () {
    test('is every OTHER component, in the edited one\'s frame', () {
      final a = AssemblyModel('Gearbox');
      final edited = occ('Bracket:1', const Vec3(100, 0, 0));
      final other = occ('Lid:1', const Vec3(130, 0, 0));
      a.occurrences.addAll([edited, other]);

      final ctx = inPlaceContext(a, edited);
      expect(ctx.map((c) => c.$1).toList(), ['Lid:1/Extrusion1'],
          reason: 'the component being edited is drawn by the part viewport '
              'from its own model; drawing it here would double every edge');
      // The lid sits 30 mm along +X of the bracket, so in the bracket's own
      // frame that is exactly where it must land.
      final at = ctx.single.$2;
      expect(at.at.x, closeTo(30, 1e-9));
      expect(at.at.y, closeTo(0, 1e-9));
      expect(at.at.z, closeTo(0, 1e-9));
    });

    test('composes the edited component\'s ROTATION away', () {
      final a = AssemblyModel('Gearbox');
      // The bracket is turned a quarter turn about +Z and sits at the origin;
      // the lid is 20 mm along world +X. In the bracket's own frame the lid is
      // therefore 20 mm along the bracket's LOCAL -Y... which is what the
      // inverse rotation has to produce, and what a forgotten one would not.
      final edited = occ('Bracket:1', Vec3.zero,
          rot: Quat.axisAngle(const Vec3(0, 0, 1), math.pi / 2));
      final other = occ('Lid:1', const Vec3(20, 0, 0));
      a.occurrences.addAll([edited, other]);
      final at = inPlaceContext(a, edited).single.$2;
      expect(at.at.x, closeTo(0, 1e-9));
      expect(at.at.y, closeTo(-20, 1e-9));
      expect(at.at.z, closeTo(0, 1e-9));
    });

    test('is per PIECE for a subassembly, not per component', () {
      final sub = AssemblyModel('Gearbox');
      sub.occurrences.add(occ('Pinion:1', const Vec3(7, 0, 0)));
      final a = AssemblyModel('Machine');
      final edited = occ('Bracket:1', Vec3.zero);
      final holder = AssemblyOccurrence(
          id: 'Gearbox:1',
          source: 'Gearbox',
          sourceKind: 'assembly',
          sub: sub,
          offset: const Vec3(50, 0, 0));
      a.occurrences.addAll([edited, holder]);
      final ctx = inPlaceContext(a, edited);
      expect(ctx.single.$1, 'Gearbox:1/Pinion:1/Extrusion1');
      // 50 for the subassembly, 7 for the pinion inside it. One transform for
      // the whole component would have put it at 50 — see M246.
      expect(ctx.single.$2.at.x, closeTo(57, 1e-9));
    });

    test('skips a hidden component', () {
      final a = AssemblyModel('Gearbox');
      final edited = occ('Bracket:1', Vec3.zero);
      final other = occ('Lid:1', const Vec3(30, 0, 0))..visible = false;
      a.occurrences.addAll([edited, other]);
      expect(inPlaceContext(a, edited), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('Create Component', () {
    test('the dialog opens, toggles and pre-fills a free name', () {
      final app = asmApp('ipc_m250_create_dlg', []);
      app.openCreateComponent();
      expect(app.createComponentSession, isNotNull);
      expect(app.createComponentSession!.name, 'Part1');
      expect(app.createComponentSession!.constrainSketchPlane, isFalse,
          reason: "Inventor's default for the checkbox is OFF");
      app.openCreateComponent();
      expect(app.createComponentSession, isNull, reason: 'it is a toggle');
    });

    test('OK on a taken name refuses and keeps the dialog up', () async {
      final app = asmApp('ipc_m250_create_taken', []);
      await app.createNamedPart('Bracket', open: false);
      app.curTab = 'Gearbox';
      app.openCreateComponent();
      app.createComponentSession!.name = 'Bracket';
      expect(app.beginCreateComponentPick(), isFalse);
      expect(app.createComponentSession, isNotNull,
          reason: 'the field to fix it in must still be there');
      expect(app.asmCreatePicking, isFalse);
    });

    test('places the new part ON the picked plane, grounded when first',
        () async {
      final app = asmApp('ipc_m250_create', []);
      app.openCreateComponent();
      app.createComponentSession!.name = 'Web';
      expect(app.beginCreateComponentPick(), isTrue);
      expect(app.asmCreatePicking, isTrue);

      // A plane 12 mm up, facing +Y.
      const n = Vec3(0, 1, 0);
      const hit = Vec3(3, 12, -4);
      expect(await app.createComponentOn(planePick(hit, n)), isTrue);

      final a = app.assemblies['Gearbox']!;
      final made = a.byId('Web:1');
      expect(made, isNotNull, reason: 'placed as an ordinary occurrence');
      expect(made!.grounded, isTrue,
          reason: 'Inventor grounds the first component of an assembly');
      // Its origin is where the finger landed, and its own +Z is the plane's
      // normal — which is what makes the sketch that opens next land on the
      // plane that was picked.
      expect((made.offset - hit).length, lessThan(1e-9));
      final z = made.dirToWorld(const Vec3(0, 0, 1));
      expect((z - n).length, lessThan(1e-9));
      expect(app.isPartName('Web'), isTrue, reason: 'a real document');
      expect(app.createComponentSession, isNull, reason: 'the command is done');
    });

    test('the checkbox adds a Flush between the sketch plane and the pick',
        () async {
      final app = asmApp('ipc_m250_create_flush', [occ('Base:1', Vec3.zero)]);
      app.openCreateComponent();
      app.createComponentSession!
        ..name = 'Web'
        ..constrainSketchPlane = true;
      app.beginCreateComponentPick();
      await app.createComponentOn(planePick(const Vec3(0, 0, 5), const Vec3(0, 0, 1)));

      final a = app.assemblies['Gearbox']!;
      expect(a.constraints, hasLength(1));
      final c = a.constraints.single;
      expect(c.kind, AsmKind.mate);
      expect(c.solution, AsmSolution.flush,
          reason: "Inventor's Create In-Place applies a FLUSH");
      expect(c.a.occurrence, 'Web:1');
      // The new component's own XY plane, in ITS OWN frame — so it keeps
      // meaning that plane after the solver moves the component.
      expect(c.a.geom.at.length, lessThan(1e-12));
      expect((c.a.geom.dir - const Vec3(0, 0, 1)).length, lessThan(1e-9));
    });

    test('unticked, it adds no constraint at all', () async {
      final app = asmApp('ipc_m250_create_noflush', [occ('Base:1', Vec3.zero)]);
      app.openCreateComponent();
      app.createComponentSession!.name = 'Web';
      app.beginCreateComponentPick();
      await app.createComponentOn(
          planePick(const Vec3(0, 0, 5), const Vec3(0, 0, 1)));
      expect(app.assemblies['Gearbox']!.constraints, isEmpty);
    });

    test('a pick that is not a plane is refused and the command stays armed',
        () async {
      final app = asmApp('ipc_m250_create_edge', [occ('Base:1', Vec3.zero)]);
      app.openCreateComponent();
      app.createComponentSession!.name = 'Web';
      app.beginCreateComponentPick();
      final edge = AsmPick(
        AsmRef('Base:1', AsmGeom.axis(Vec3.zero, const Vec3(1, 0, 0)), 'Edge'),
        AsmGeom.axis(Vec3.zero, const Vec3(1, 0, 0)),
        0,
        Vec3.zero,
      );
      expect(await app.createComponentOn(edge), isFalse);
      expect(app.asmCreatePicking, isTrue,
          reason: 'a mis-tap costs that tap and nothing else');
      expect(app.isPartName('Web'), isFalse,
          reason: 'nothing was written for a pick that was refused');
    });
  });

  // -------------------------------------------------------------------------
  group('edit in place', () {
    test('opens the part, and the assembly is around it', () async {
      final app = asmApp('ipc_m250_inplace',
          [occ('Bracket:1', Vec3.zero), occ('Lid:1', const Vec3(30, 0, 0))]);
      final a = app.assemblies['Gearbox']!;
      app.parts['Bracket'] = a.byId('Bracket:1')!.part!;
      app.parts['Lid'] = a.byId('Lid:1')!.part!;

      expect(await app.enterInPlaceEdit(a.byId('Bracket:1')!), isTrue);
      expect(app.curTab, 'Bracket');
      expect(app.isEditingInPlace, isTrue);
      expect(app.inPlaceEdit!.assembly, 'Gearbox');
      expect(app.inPlaceEdit!.occurrence, 'Bracket:1');
      expect(app.inPlaceContextPieces.map((c) => c.$1).toList(),
          ['Lid:1/Extrusion1']);

      await app.leaveInPlaceEdit();
      expect(app.curTab, 'Gearbox');
      expect(app.isEditingInPlace, isFalse);
      expect(app.inPlaceContextPieces, isEmpty);
    });

    test('a subassembly is refused, out loud', () async {
      final app = asmApp('ipc_m250_inplace_sub', []);
      final a = app.assemblies['Gearbox']!;
      final sub = AssemblyOccurrence(
          id: 'Inner:1',
          source: 'Inner',
          sourceKind: 'assembly',
          sub: AssemblyModel('Inner'));
      a.occurrences.add(sub);
      expect(await app.enterInPlaceEdit(sub), isFalse);
      expect(app.message, isNotNull, reason: 'a silent refusal reads as a bug');
      expect(app.isEditingInPlace, isFalse);
    });

    test('the edit does not outlive its tab', () async {
      final app = asmApp('ipc_m250_inplace_tab',
          [occ('Bracket:1', Vec3.zero), occ('Lid:1', const Vec3(30, 0, 0))]);
      final a = app.assemblies['Gearbox']!;
      app.parts['Bracket'] = a.byId('Bracket:1')!.part!;
      app.parts['Lid'] = a.byId('Lid:1')!.part!;
      await app.enterInPlaceEdit(a.byId('Bracket:1')!);
      // Any of a dozen paths can change the tab; the edit has to notice
      // without every one of them having remembered to say so.
      app.curTab = 'Gearbox';
      expect(app.inPlaceEdit, isNull);
      expect(app.inPlaceContextPieces, isEmpty);
    });

    test('the view is carried in and back out again', () async {
      final app = asmApp('ipc_m250_inplace_cam',
          [occ('Bracket:1', const Vec3(40, 0, 0))]);
      final a = app.assemblies['Gearbox']!;
      app.parts['Bracket'] = a.byId('Bracket:1')!.part!;
      a.camera
        ..az = 0.9
        ..pol = 1.1
        ..halfH = 55
        ..ox = 3
        ..oy = -2;
      final before = [a.camera.az, a.camera.pol, a.camera.halfH];
      await app.enterInPlaceEdit(a.byId('Bracket:1')!);
      final p = app.parts['Bracket']!;
      // The component is not rotated, so the part camera looks the same way —
      // and its pan is shifted by where the component sits, which is exactly
      // what placedCam does for the renderer.
      expect(p.camera.halfH, closeTo(55, 1e-9));
      expect(p.camera.ox, closeTo(3 - 40 * a.camera.right.x, 1e-6));

      // Orbit while inside, then Return: the assembly picks the view up.
      p.camera.halfH = 21;
      await app.leaveInPlaceEdit();
      expect(a.camera.halfH, closeTo(21, 1e-9));
      expect(a.camera.az, closeTo(before[0], 1e-6));
      expect(a.camera.pol, closeTo(before[1], 1e-6));
    });

    test('the RealityKit scene signature moves when the context does',
        () async {
      final app = asmApp('ipc_m250_inplace_sig',
          [occ('Bracket:1', Vec3.zero), occ('Lid:1', const Vec3(30, 0, 0))]);
      final a = app.assemblies['Gearbox']!;
      app.parts['Bracket'] = a.byId('Bracket:1')!.part!;
      app.parts['Lid'] = a.byId('Lid:1')!.part!;
      await app.enterInPlaceEdit(a.byId('Bracket:1')!);
      final p = app.parts['Bracket']!;
      final withCtx = sceneSignature(app, p);
      expect(withCtx, contains(kInPlaceContextId),
          reason: 'the surrounding components are part of the STRUCTURE');
      // Hiding a component of the parent has to reach the heavy push, or the
      // assembly stays on screen after it has been switched off.
      a.byId('Lid:1')!.visible = false;
      expect(sceneSignature(app, p), isNot(withCtx));
    });
  });

  // -------------------------------------------------------------------------
  group('Free Move and Free Rotate', () {
    test('the two commands toggle and exclude each other', () {
      final app = asmApp('ipc_m250_pos', [occ('Bracket:1', Vec3.zero)]);
      app.startFreeMove();
      expect(app.asmPositionMode, AsmPositionMode.move);
      app.startFreeRotate();
      expect(app.asmPositionMode, AsmPositionMode.rotate,
          reason: 'one armed command at a time');
      app.startFreeRotate();
      expect(app.asmPositionMode, isNull, reason: 'the same button cancels');
    });

    test('Place Constraint disarms them', () {
      final app = asmApp('ipc_m250_pos_x', [occ('Bracket:1', Vec3.zero)]);
      app.startFreeMove();
      app.openConstraint();
      expect(app.asmPositionMode, isNull);
    });

    test('a free move overrides the relationships, and a solve takes it back',
        () {
      final app = asmApp('ipc_m250_free', [
        occ('Base:1', Vec3.zero, grounded: true),
        occ('Lid:1', const Vec3(0, 0, 20)),
      ]);
      final a = app.assemblies['Gearbox']!;
      // Pin the lid's origin to the base's, so the solver has an opinion about
      // where it belongs.
      a.constraints.add(AsmConstraint(
        name: 'Mate:1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: AsmRef('Base:1', AsmGeom.point(Vec3.zero), 'Point'),
        b: AsmRef('Lid:1', AsmGeom.point(Vec3.zero), 'Point'),
      ));

      app.startFreeMove();
      final lid = a.byId('Lid:1')!;
      app.beginOccurrenceDrag(lid, lid.toWorld(Vec3.zero));
      app.dragOccurrenceTo(const Vec3(0, 0, 45));
      expect(lid.offset.z, closeTo(45, 1e-6),
          reason: 'Free Move puts it where you put it, solver or no solver');

      // Anything that solves is the "update" Inventor means, and it puts the
      // component back where its relationships say it belongs.
      app.cancelAsmPosition();
      app.beginOccurrenceDrag(lid, lid.toWorld(Vec3.zero));
      app.dragOccurrenceTo(const Vec3(0, 0, 45));
      expect(lid.offset.length, lessThan(1.0),
          reason: 'through the solver the mate wins');
    });

    test('the same drag WITHOUT the command goes through the solver', () {
      final app = asmApp('ipc_m250_solved', [
        occ('Base:1', Vec3.zero, grounded: true),
        occ('Lid:1', const Vec3(0, 0, 20)),
      ]);
      final a = app.assemblies['Gearbox']!;
      a.constraints.add(AsmConstraint(
        name: 'Mate:1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: AsmRef('Base:1', AsmGeom.point(Vec3.zero), 'Point'),
        b: AsmRef('Lid:1', AsmGeom.point(Vec3.zero), 'Point'),
      ));
      final lid = a.byId('Lid:1')!;
      app.beginOccurrenceDrag(lid, lid.toWorld(Vec3.zero));
      app.dragOccurrenceTo(const Vec3(0, 0, 45));
      expect(lid.offset.length, lessThan(1.0));
    });

    test('the rotate glyph is on the selection, and not on a grounded one', () {
      final app = asmApp('ipc_m250_glyph', [
        occ('Base:1', Vec3.zero, grounded: true),
        occ('Lid:1', const Vec3(0, 0, 20)),
      ]);
      final a = app.assemblies['Gearbox']!;
      expect(app.freeRotateTarget, isNull, reason: 'nothing armed');
      app.startFreeRotate();
      a.selected = a.byId('Base:1');
      expect(app.freeRotateTarget, isNull,
          reason: 'a grounded component has no degrees of freedom to spend');
      a.selected = a.byId('Lid:1');
      expect(app.freeRotateTarget, same(a.byId('Lid:1')));
      final (centre, r) = app.freeRotateGlyph!;
      // The bounds centre, which for this box is the component's origin.
      expect((centre - const Vec3(0, 0, 20)).length, lessThan(1e-9));
      expect(r, closeTo(10 * math.sqrt(3), 1e-6));
    });

    test('a turn rotates about the frozen pivot', () {
      final app = asmApp(
          'ipc_m250_turn', [occ('Lid:1', const Vec3(0, 0, 20))]);
      final a = app.assemblies['Gearbox']!;
      final lid = a.byId('Lid:1')!;
      app.startFreeRotate();
      a.selected = lid;
      app.beginOccurrenceTurn(lid);
      app.turnOccurrenceBy(const Vec3(1, 0, 0), math.pi / 2);
      // The pivot is the component's own centre, so a half-quarter turn about
      // it must not move the component: a turn that walked the part across the
      // screen is the failure the frozen pivot exists to prevent.
      expect((lid.offset - const Vec3(0, 0, 20)).length, lessThan(1e-9));
      expect(lid.rot.angle, closeTo(math.pi / 2, 1e-6));
      app.endOccurrenceTurn();
    });

    test('a grounded component refuses to turn', () {
      final app = asmApp('ipc_m250_turn_ground',
          [occ('Base:1', Vec3.zero, grounded: true)]);
      final a = app.assemblies['Gearbox']!;
      final base = a.byId('Base:1')!;
      app.startFreeRotate();
      a.selected = base;
      app.beginOccurrenceTurn(base);
      app.turnOccurrenceBy(const Vec3(1, 0, 0), 1.0);
      expect(base.rot.isIdentity, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('view representations', () {
    AppState twoUp(String tag) => asmApp(tag, [
          occ('Base:1', Vec3.zero, grounded: true),
          occ('Lid:1', const Vec3(0, 0, 20)),
        ]);

    test('a fresh assembly is on Default, and lists only it', () {
      final a = twoUp('ipc_m250_vr_fresh').assemblies['Gearbox']!;
      expect(a.activeViewRep, kDefaultViewRep);
      expect(a.viewRepNames, [kDefaultViewRep]);
      expect(a.viewReps, isEmpty,
          reason: 'Default is the live state until there is a reason to write '
              'it down');
    });

    test('New captures what is on screen and becomes active', () {
      final app = twoUp('ipc_m250_vr_new');
      final a = app.assemblies['Gearbox']!;
      a.byId('Lid:1')!.visible = false;
      a.camera.halfH = 44;
      expect(app.newViewRep(), 'View1');
      expect(a.activeViewRep, 'View1');
      final rep = a.viewRepNamed('View1')!;
      expect(rep.visible('Lid:1'), isFalse);
      expect(rep.visible('Base:1'), isTrue);
      expect(rep.halfH, closeTo(44, 1e-9));
    });

    test('leaving an unlocked representation writes it back', () {
      final app = twoUp('ipc_m250_vr_back');
      final a = app.assemblies['Gearbox']!;
      a.camera.halfH = 30;
      app.newViewRep(); // View1, at halfH 30 — and Default captured on the way
      a.camera.halfH = 90;
      app.activateViewRep(kDefaultViewRep);
      // Default was captured when View1 was made, so it holds the 30 — and
      // View1 has picked up the 90 that was on screen when we left it.
      expect(a.camera.halfH, closeTo(30, 1e-9));
      expect(a.viewRepNamed('View1')!.halfH, closeTo(90, 1e-9));
    });

    test('a locked one is applied and never written', () {
      final app = twoUp('ipc_m250_vr_lock');
      final a = app.assemblies['Gearbox']!;
      a.camera.halfH = 30;
      app.newViewRep();
      app.toggleViewRepLocked('View1');
      a.camera.halfH = 90;
      app.activateViewRep(kDefaultViewRep);
      expect(a.viewRepNamed('View1')!.halfH, closeTo(30, 1e-9),
          reason: 'that is what the padlock is for');
      app.activateViewRep('View1');
      expect(a.camera.halfH, closeTo(30, 1e-9));
    });

    test('Update on a locked one refuses out loud', () {
      final app = twoUp('ipc_m250_vr_locked_update');
      final a = app.assemblies['Gearbox']!;
      app.newViewRep();
      app.toggleViewRepLocked('View1');
      a.camera.halfH = 77;
      app.updateViewRep('View1');
      expect(a.viewRepNamed('View1')!.halfH, isNot(closeTo(77, 1e-9)));
      expect(app.message, isNotNull);
    });

    test('activating restores component visibility', () {
      final app = twoUp('ipc_m250_vr_vis');
      final a = app.assemblies['Gearbox']!;
      // Default holds the lid VISIBLE, because that is what was on screen when
      // View1 was made and Default was written down. Hiding it afterwards is a
      // change to View1, which is the active representation — that is what
      // "unlocked" means, and it is why the two now differ.
      app.newViewRep();
      a.byId('Lid:1')!.visible = false;
      app.activateViewRep(kDefaultViewRep);
      expect(a.byId('Lid:1')!.visible, isTrue);
      app.activateViewRep('View1');
      expect(a.byId('Lid:1')!.visible, isFalse);
    });

    test('Default keeps whatever was on screen when it was written down', () {
      final app = twoUp('ipc_m250_vr_default_state');
      final a = app.assemblies['Gearbox']!;
      // Hidden BEFORE the first New: Default is the live state until something
      // makes it necessary to write it down, so what it captures is this.
      // Inventor's unlocked Default behaves the same way, and it is the reason
      // people lock representations they care about.
      a.byId('Lid:1')!.visible = false;
      app.newViewRep();
      app.activateViewRep(kDefaultViewRep);
      expect(a.byId('Lid:1')!.visible, isFalse);
    });

    test('a component placed after the rep was saved stays visible', () {
      final app = twoUp('ipc_m250_vr_later');
      final a = app.assemblies['Gearbox']!;
      app.newViewRep();
      a.occurrences.add(occ('Shim:1', const Vec3(0, 40, 0)));
      app.activateViewRep(kDefaultViewRep);
      app.activateViewRep('View1');
      expect(a.byId('Shim:1')!.visible, isTrue,
          reason: 'a representation records overrides, not a census');
    });

    test('Default cannot be renamed or deleted', () {
      final app = twoUp('ipc_m250_vr_default');
      final a = app.assemblies['Gearbox']!;
      app.newViewRep();
      expect(app.renameViewRep(kDefaultViewRep, 'Whatever'), isFalse);
      app.deleteViewRep(kDefaultViewRep);
      expect(a.viewRepNamed(kDefaultViewRep), isNotNull);
    });

    test('rename carries the active flag with it', () {
      final app = twoUp('ipc_m250_vr_rename');
      final a = app.assemblies['Gearbox']!;
      app.newViewRep();
      expect(app.renameViewRep('View1', 'Exploded'), isTrue);
      expect(a.activeViewRep, 'Exploded');
      expect(app.renameViewRep('Exploded', kDefaultViewRep), isFalse,
          reason: 'two rows nothing could tell apart');
    });

    test('deleting the active one falls back to Default', () {
      final app = twoUp('ipc_m250_vr_del');
      final a = app.assemblies['Gearbox']!;
      app.newViewRep();
      app.deleteViewRep('View1');
      expect(a.activeViewRep, kDefaultViewRep);
      expect(a.viewRepNamed('View1'), isNull);
    });

    test('deleting a component takes its hidden entry with it', () {
      final app = twoUp('ipc_m250_vr_drop');
      final a = app.assemblies['Gearbox']!;
      a.byId('Lid:1')!.visible = false;
      app.newViewRep();
      a.remove(a.byId('Lid:1')!);
      expect(a.viewRepNamed('View1')!.hidden.containsKey('Lid:1'), isFalse,
          reason: 'nextOccurrenceId hands "Lid:1" straight back out, and a '
              'stale entry would make the next one arrive invisible');
    });

    test('a pattern element is not part of a representation', () {
      final app = twoUp('ipc_m250_vr_pat');
      final a = app.assemblies['Gearbox']!;
      final el = occ('Lid:2', const Vec3(0, 0, 40))
        ..patternOf = 'RectangularPattern1'
        ..patternElement = 2
        ..visible = false;
      a.occurrences.add(el);
      app.newViewRep();
      expect(a.viewRepNamed('View1')!.hidden.containsKey('Lid:2'), isFalse,
          reason: 'what a pattern suppresses belongs to the pattern');
      el.visible = true;
      app.activateViewRep(kDefaultViewRep);
      app.activateViewRep('View1');
      expect(el.visible, isTrue, reason: 'the rep must not un-suppress it');
    });

    test('they survive the round trip, and cost nothing when unused',
        () async {
      final app = twoUp('ipc_m250_vr_json');
      final a = app.assemblies['Gearbox']!;
      // Untouched: the document must be byte-identical to one written before
      // representations existed.
      expect(jsonEncode(a.toJson()), isNot(contains('viewRep')));

      a.byId('Lid:1')!.visible = false;
      a.camera.halfH = 66;
      app.newViewRep();
      app.toggleViewRepLocked('View1');
      final json = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;

      final back = AssemblyModel('Gearbox');
      back.occurrences.add(occ('Base:1', Vec3.zero));
      back.occurrences.add(occ('Lid:1', const Vec3(0, 0, 20)));
      back.loadJson(json);
      expect(back.activeViewRep, 'View1');
      final rep = back.viewRepNamed('View1')!;
      expect(rep.locked, isTrue);
      expect(rep.visible('Lid:1'), isFalse);
      expect(rep.halfH, closeTo(66, 1e-9));
    });

    test('an active name with nothing behind it falls back to Default', () {
      final a = AssemblyModel('Gearbox');
      a.loadJson({
        'viewReps': [
          {'name': 'View1'}
        ],
        'viewRep': 'Ghost',
      });
      expect(a.activeViewRep, kDefaultViewRep,
          reason: 'the document is always looking at something');
    });

    test('a duplicate name in a hand-edited file is dropped', () {
      final a = AssemblyModel('Gearbox');
      a.loadJson({
        'viewReps': [
          {'name': 'View1'},
          {'name': 'View1'},
        ],
      });
      expect(a.viewReps, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('the browser', () {
    test('Representations opens onto View, Position and Level of Detail', () {
      final app = asmApp('ipc_m250_tree', [occ('Base:1', Vec3.zero)]);
      final rows = buildBrowserRows(app, expanded: const {kIdRepresentations});
      final ids = rows.map((r) => r.id).toList();
      expect(
          ids,
          containsAllInOrder(
              [kIdRepresentations, kIdViewReps, kIdPositionalReps, kIdLodReps]));
      final pos = rows.firstWhere((r) => r.id == kIdPositionalReps);
      expect(pos.dim, isTrue,
          reason: 'listed and honestly empty — asm_reps.dart says why');
      expect(pos.expandable, isFalse,
          reason: 'a chevron that opens onto nothing is worse than none');
    });

    test('View lists the representations with the active one ticked', () {
      final app = asmApp('ipc_m250_tree_vr', [occ('Base:1', Vec3.zero)]);
      app.newViewRep();
      final rows = buildBrowserRows(app,
          expanded: const {kIdRepresentations, kIdViewReps});
      final reps = [
        for (final r in rows)
          if (r.id.startsWith(kIdViewRep)) r
      ];
      expect(reps.map((r) => r.label).toList(), [kDefaultViewRep, 'View1']);
      expect(reps.last.selected, isTrue);
      expect(reps.last.symbol, 'checkmark.circle.fill');
      expect(reps.first.selected, isFalse);
      // Default carries no Rename and no Delete.
      final defaultItems = [
        for (final group in reps.first.menu)
          for (final i in group) i.id
      ];
      expect(defaultItems, isNot(contains('vrDelete')));
      expect(defaultItems, contains('vrActivate'));
    });

    test('a part being edited in place shows the way back', () async {
      final app = asmApp('ipc_m250_tree_inplace', [occ('Bracket:1', Vec3.zero)]);
      final a = app.assemblies['Gearbox']!;
      app.parts['Bracket'] = a.byId('Bracket:1')!.part!;
      await app.enterInPlaceEdit(a.byId('Bracket:1')!);
      final rows = buildBrowserRows(app, expanded: const {});
      final back = rows.firstWhere((r) => r.id == kIdInPlaceReturn);
      expect(back.label, 'Gearbox');
    });

    test('a component offers Edit in Place; a subassembly does not', () {
      final sub = AssemblyOccurrence(
          id: 'Inner:1',
          source: 'Inner',
          sourceKind: 'assembly',
          sub: AssemblyModel('Inner'));
      final app = asmApp('ipc_m250_tree_menu', [occ('Base:1', Vec3.zero), sub]);
      final rows = buildBrowserRows(app, expanded: const {});
      List<String> menuOf(String id) => [
            for (final g in rows.firstWhere((r) => r.id == id).menu)
              for (final i in g) i.id
          ];
      expect(menuOf('${kIdComponent}Base:1'), contains('cpEditInPlace'));
      expect(menuOf('${kIdComponent}Inner:1'), isNot(contains('cpEditInPlace')));
    });
  });

  // -------------------------------------------------------------------------
  group('the part ribbon', () {
    testWidgets('grows a Return panel only while editing in place',
        (t) async {
      L.set(kEn);
      resetFlyoutCacheForTest();
      final app = asmApp('ipc_m250_ribbon', [occ('Bracket:1', Vec3.zero)]);
      final a = app.assemblies['Gearbox']!;
      app.parts['Bracket'] = a.byId('Bracket:1')!.part!;

      await t.binding.setSurfaceSize(const Size(1366, 1024));
      // runAsync, and it is not optional: openPart and enterInPlaceEdit both
      // touch the FILE SYSTEM, and a testWidgets body runs under FakeAsync
      // where a real I/O future never completes. Awaiting one directly hangs
      // the test until the ten-minute timeout — which is how this was found.
      await t.runAsync(() => app.openPart('Bracket'));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
      await t.pump();
      expect(find.text('Return'), findsNothing,
          reason: 'an ordinary part is not being edited inside anything');

      app.curTab = 'Gearbox';
      await t.runAsync(() => app.enterInPlaceEdit(a.byId('Bracket:1')!));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
      await t.pump();
      expect(find.text('Return'), findsOneWidget);
      addTearDown(() => L.set(kDe));
    });
  });
}
