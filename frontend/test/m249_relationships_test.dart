// M249 — the rest of the Relationships panel: Joint's COMMAND path, the three
// visibility commands, and Drive.
//
// m249_joint_test.dart pins the joint mathematics. This pins everything
// between a finger and it, plus the two commands that have no mathematics at
// all and are therefore easy to leave half-wired:
//
//   * THE JOINT SESSION. Place Joint and Place Constraint share one session
//     (ConstraintSession.jointType says why), so every claim about arming,
//     picking and Apply that M242 made for one now has to hold for the other —
//     including the parts that differ, which is Automatic re-deciding the type
//     on every pick.
//   * THE GLYPHS. Show / Show Sick / Hide All control whether a relationship
//     is DRAWN, so the drawing has to exist and has to happen on BOTH render
//     paths. On iOS RealityKit owns the scene and _AssemblyPainter never runs;
//     a glyph drawn only there is perfectly visible on a host test and
//     invisible on the iPad, which is the trap this tree has hit before and
//     the reason for the source assertion at the end.
//   * DRIVE. The solver's drive pass has existed since M242 with nothing to
//     step it. What is testable is that a sweep moves the value, that a MOTION
//     sweep turns the driven body through driveMotion, that the timer actually
//     ticks, and that closing puts the assembly back.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_joint.dart';
import 'package:prototype/asm_pick.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/widgets/viewport_assembly.dart';
import 'package:prototype/work_features.dart' show WorkRefSource;

// ---------------------------------------------------------------------------
// fixtures
// ---------------------------------------------------------------------------

AssemblyOccurrence occ(String id,
        {Vec3 at = Vec3.zero, Quat? rot, bool grounded = false}) =>
    AssemblyOccurrence(
      id: id,
      source: id.split(':').first,
      offset: at,
      rot: rot,
      grounded: grounded,
    );

AppState asmApp(String tag, List<AssemblyOccurrence> os) {
  final app = AppState()
    ..docsDirForTest = Directory.systemTemp.createTempSync(tag);
  final a = AssemblyModel('Gearbox');
  a.occurrences.addAll(os);
  app.assemblies['Gearbox'] = a;
  app.openTabs.add('Gearbox');
  app.curTab = 'Gearbox';
  return app;
}

AsmRef circle(String occId, Vec3 centre, Vec3 dir, {double r = 3}) => AsmRef(
    occId,
    AsmGeom.axis(centre, dir, radius: r, source: WorkRefSource.circle),
    'Circular Edge',
    anchor: centre,
    extent: r);

AsmRef face(String occId, Vec3 anchor, Vec3 n, {Vec3? recordAt}) => AsmRef(
    occId, AsmGeom.plane(recordAt ?? Vec3.zero, n), 'Face',
    anchor: anchor, extent: 8);

/// A pick, as the viewport would hand one to the session.
AsmPick pick(AssemblyModel m, AsmRef ref) =>
    AsmPick(ref, worldGeomOf(m, ref), 0, worldAnchorOf(m, ref));

AsmConstraint mate(String a, String b, {double value = 0}) => AsmConstraint(
      name: 'Mate:1',
      kind: AsmKind.mate,
      solution: AsmSolution.mate,
      a: face(a, const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
      b: face(b, const Vec3(0, 0, -5), const Vec3(0, 0, -1)),
      value: value,
    );

/// A canvas that records nothing but the fact that it was drawn on.
///
/// Enough to answer the only question a glyph test can honestly ask without a
/// golden: did the painter put anything on the canvas at all. Whether the
/// picture is RIGHT is a question for the eye, and M244..M248 each answered it
/// with a throwaway golden that was read and deleted.
class _CountingCanvas implements Canvas {
  int ops = 0;
  final Set<Symbol> members = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    ops++;
    members.add(invocation.memberName);
    return null;
  }
}

Cam3 frontCam([Size size = const Size(800, 600)]) =>
    Cam3(PartCamera(az: 0, pol: 1.5707963267948966, halfH: 60), size);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => L.set(kEn));

  // -------------------------------------------------------------------------
  group('Place Joint, the command', () {
    test('the ribbon button opens a JOINT session, not a constraint one', () {
      final app = asmApp('m249a', [occ('A:1', grounded: true), occ('B:1')]);
      app.openJoint();
      final s = app.constraintSession!;
      expect(s.isJoint, isTrue);
      expect(s.tab, AsmTab.joint);
      expect(s.jointType, AsmJointType.automatic,
          reason: "Inventor opens on Automatic, which is what makes one pick "
              'pair enough');
      // And the viewport must treat it as a collecting command, or a tap would
      // drag the component instead of naming an origin.
      expect(app.constraintPicking, isTrue);
    });

    test('Automatic decides the type from the two origins, as they land', () {
      final app = asmApp('m249b', [occ('A:1', grounded: true), occ('B:1')]);
      final m = app.currentAssembly!;
      app.openJoint();
      final s = app.constraintSession!;
      // With nothing picked it reads as Rigid — Automatic's own fallback.
      expect(s.kind, AsmKind.jointRigid);
      app.pickConstraintRef(pick(m, circle('A:1', const Vec3(0, 0, 5),
          const Vec3(0, 0, 1))));
      app.pickConstraintRef(pick(m, circle('B:1', const Vec3(0, 0, -5),
          const Vec3(0, 0, 1))));
      expect(s.kind, AsmKind.jointRotational,
          reason: 'two circular origins are a hinge');
      // Re-picking the second origin as a flat face demotes it to Rigid, which
      // is the case that proves the resolution is live rather than once.
      app.armConstraintSelection(1);
      app.pickConstraintRef(
          pick(m, face('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1))));
      expect(s.kind, AsmKind.jointRigid);
    });

    test('choosing a type by hand overrides Automatic and sticks', () {
      final app = asmApp('m249c', [occ('A:1', grounded: true), occ('B:1')]);
      final m = app.currentAssembly!;
      app.openJoint();
      app.setJointType(AsmJointType.planar);
      final s = app.constraintSession!;
      expect(s.kind, AsmKind.jointPlanar);
      app.pickConstraintRef(pick(m, circle('A:1', const Vec3(0, 0, 5),
          const Vec3(0, 0, 1))));
      app.pickConstraintRef(pick(m, circle('B:1', const Vec3(0, 0, -5),
          const Vec3(0, 0, 1))));
      expect(s.kind, AsmKind.jointPlanar,
          reason: 'two circular origins would be Rotational under Automatic; '
              'a hand-chosen type must not be second-guessed');
    });

    test('Apply commits ONE relationship, named after its type', () {
      final app = asmApp('m249d', [
        occ('A:1', grounded: true),
        occ('B:1', at: const Vec3(40, 12, 3)),
      ]);
      final m = app.currentAssembly!;
      app.openJoint();
      app.pickConstraintRef(pick(m, circle('A:1', const Vec3(0, 0, 5),
          const Vec3(0, 0, 1))));
      app.pickConstraintRef(pick(m, circle('B:1', const Vec3(0, 0, -5),
          const Vec3(0, 0, 1))));
      expect(app.applyConstraint(), isTrue);
      // ONE row, not the two or three constraints the same joint would have
      // taken by hand. That is the claim of the command.
      expect(m.constraints, hasLength(1));
      final c = m.constraints.single;
      expect(c.name, 'Rotational:1');
      expect(c.isJoint, isTrue);
      // And it does what it says: one turn left, and the component moved.
      final r = app.solveCurrentAssembly()!;
      expect(r.dof, 1);
      expect(m.byId('B:1')!.offset.x, isNot(closeTo(40, 1e-6)),
          reason: 'the joint had to bring the component to the origin it names');
    });

    test('a Rigid joint captures its twist; a Rotational one does not', () {
      for (final (type, wantsTwist) in const [
        (AsmJointType.rigid, true),
        (AsmJointType.slider, true),
        (AsmJointType.rotational, false),
        (AsmJointType.cylindrical, false),
      ]) {
        final app = asmApp('m249e', [
          occ('A:1', grounded: true),
          occ('B:1',
              at: const Vec3(0, 0, 30),
              rot: Quat.axisAngle(const Vec3(0, 0, 1), 0.8)),
        ]);
        final m = app.currentAssembly!;
        app.openJoint();
        app.setJointType(type);
        app.pickConstraintRef(
            pick(m, face('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1))));
        app.pickConstraintRef(
            pick(m, face('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1))));
        expect(app.applyConstraint(), isTrue);
        final c = m.constraints.single;
        expect(c.twist != null, wantsTwist, reason: '$type');
        if (wantsTwist) {
          expect(c.twist!.abs(), greaterThan(0.1),
              reason: '$type must hold the angle the parts were already at, '
                  'not snap them to zero');
        }
      }
    });

    test('Cancel puts the components back where the preview found them', () {
      final app = asmApp('m249f', [
        occ('A:1', grounded: true),
        occ('B:1', at: const Vec3(40, 12, 3)),
      ]);
      final m = app.currentAssembly!;
      final was = m.byId('B:1')!.offset;
      app.openJoint();
      app.pickConstraintRef(pick(m, circle('A:1', const Vec3(0, 0, 5),
          const Vec3(0, 0, 1))));
      app.pickConstraintRef(pick(m, circle('B:1', const Vec3(0, 0, -5),
          const Vec3(0, 0, 1))));
      // The preview has moved it by now — that is what a preview is.
      expect((m.byId('B:1')!.offset - was).length, greaterThan(1));
      app.cancelConstraint();
      expect((m.byId('B:1')!.offset - was).length, lessThan(1e-9));
      expect(m.constraints, isEmpty);
      expect(app.constraintSession, isNull);
    });

    test('editing a joint re-opens the Joint dialog on its own type', () {
      final app = asmApp('m249g', [occ('A:1', grounded: true), occ('B:1')]);
      final m = app.currentAssembly!;
      final c = AsmConstraint(
        name: 'Slider:1',
        kind: AsmKind.jointSlider,
        solution: AsmSolution.aligned,
        a: face('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
        b: face('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1)),
        value: 3,
      );
      m.constraints.add(c);
      app.openJoint(edit: c);
      final s = app.constraintSession!;
      expect(s.isJoint, isTrue);
      expect(s.jointType, AsmJointType.slider);
      expect(s.solution, AsmSolution.aligned);
      expect(s.value, 3);
      expect(s.a, same(c.a));
    });
  });

  // -------------------------------------------------------------------------
  group('Show / Show Sick / Hide All', () {
    AppState twoJointed(String tag) {
      final app = asmApp(tag, [
        occ('A:1', grounded: true),
        occ('B:1', at: const Vec3(0, 0, 30)),
        occ('C:1', at: const Vec3(60, 0, 0)),
      ]);
      app.currentAssembly!.constraints.add(mate('A:1', 'B:1'));
      return app;
    }

    test('Show with a component selected draws that component\'s '
        'relationships', () {
      final app = twoJointed('m249h');
      final m = app.currentAssembly!;
      app.selectOccurrence(m.byId('B:1'));
      app.showRelationships();
      expect(m.shownRelationships, {'Mate:1'});
      expect(m.visibleRelationships, hasLength(1));
      expect(app.showRelationshipsPicking, isFalse,
          reason: 'the selection answered the question, so nothing is armed');
    });

    test('Show with nothing selected ARMS and waits, Inventor-style', () {
      final app = twoJointed('m249i');
      final m = app.currentAssembly!;
      app.selectOccurrence(null);
      app.showRelationships();
      expect(app.showRelationshipsPicking, isTrue);
      expect(m.shownRelationships, isEmpty);
      // "then select the component" — which is what the viewport calls.
      expect(app.showRelationshipsOf('B:1'), isTrue);
      expect(m.shownRelationships, {'Mate:1'});
      expect(app.showRelationshipsPicking, isFalse);
    });

    test('tapping Show again disarms it', () {
      final app = twoJointed('m249j');
      app.selectOccurrence(null);
      app.showRelationships();
      expect(app.showRelationshipsPicking, isTrue);
      app.showRelationships();
      expect(app.showRelationshipsPicking, isFalse,
          reason: 'an armed command on a touch device needs a way out that is '
              'not the Escape key');
    });

    test('a component with no relationships says so and shows nothing', () {
      final app = twoJointed('m249k');
      final m = app.currentAssembly!;
      expect(app.showRelationshipsOf('C:1'), isFalse);
      expect(m.shownRelationships, isEmpty);
    });

    test('Show Sick picks out exactly the ones the solver could not meet', () {
      final app = asmApp('m249l', [
        occ('A:1', grounded: true),
        occ('B:1', at: const Vec3(0, 0, 30)),
        occ('D:1', at: const Vec3(90, 0, 0), grounded: true),
      ]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1'));
      // Two grounded components, and two planes that are 7 mm apart: nothing
      // was free to move, so the solver cannot close the gap. (Coincident
      // planes would be satisfied where they stand and report healthy, which
      // is right and would make this test pass for no reason.)
      m.constraints.add(AsmConstraint(
        name: 'Mate:2',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: face('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
        b: face('D:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1),
            recordAt: const Vec3(0, 0, 7)),
      ));
      app.solveCurrentAssembly();
      expect(m.hasSickRelationships, isTrue);
      app.showSickRelationships();
      expect(m.shownRelationships, {'Mate:2'},
          reason: 'the healthy one is not what Show Sick is for');
    });

    test('Show Sick on a healthy assembly shows nothing at all', () {
      final app = twoJointed('m249m');
      final m = app.currentAssembly!;
      app.solveCurrentAssembly();
      expect(m.hasSickRelationships, isFalse);
      app.showSickRelationships();
      expect(m.shownRelationships, isEmpty);
    });

    test('an armed Show never swallows a tap meant for a dialog', () {
      // Show is a ribbon TOGGLE and nothing cancels it, unlike the three
      // modeless dialogs, which cancel one another. So the viewport checks it
      // LAST among the armed commands — and this is the assertion that says
      // the order in the source is the deliberate one.
      final src =
          File('lib/widgets/viewport_assembly.dart').readAsStringSync();
      final show = src.indexOf('app.showRelationshipsPicking)');
      final constraint = src.indexOf('if (app.constraintPicking)');
      final work = src.indexOf('if (app.asmPickWorkGeometry)');
      final pattern = src.indexOf('if (app.asmPatternPicking &&');
      expect(show, greaterThan(constraint));
      expect(show, greaterThan(work));
      expect(show, greaterThan(pattern));
    });

    test('Hide All clears the set and disarms Show', () {
      final app = twoJointed('m249n');
      final m = app.currentAssembly!;
      app.showRelationshipsOf('B:1');
      app.showRelationships(); // arms, since nothing is selected
      app.hideAllRelationships();
      expect(m.shownRelationships, isEmpty);
      expect(app.showRelationshipsPicking, isFalse);
    });

    test('a suppressed relationship stops drawing, and comes back', () {
      final app = twoJointed('m249o');
      final m = app.currentAssembly!;
      app.showRelationshipsOf('B:1');
      final c = m.constraints.single;
      app.toggleConstraintSuppressed(c);
      expect(m.visibleRelationships, isEmpty,
          reason: 'a switched-off relationship draws nothing');
      expect(m.shownRelationships, {'Mate:1'},
          reason: 'suppressing is not un-showing: the set is untouched');
      app.toggleConstraintSuppressed(c);
      expect(m.visibleRelationships, hasLength(1));
    });

    test('a deleted relationship simply stops drawing', () {
      // The reason the set holds NAMES: nothing has to remember to clean it
      // up, and a stale entry can never resurrect an object.
      final app = twoJointed('m249p');
      final m = app.currentAssembly!;
      app.showRelationshipsOf('B:1');
      app.deleteConstraint(m.constraints.single);
      expect(m.visibleRelationships, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('the glyphs', () {
    test('nothing is drawn until Show says so', () {
      final app = twoBoxes('m249q');
      final m = app.currentAssembly!;
      final canvas = _CountingCanvas();
      paintRelationshipGlyphs(canvas, frontCam(), m);
      expect(canvas.ops, 0);
      app.showRelationshipsOf('B:1');
      paintRelationshipGlyphs(canvas, frontCam(), m);
      expect(canvas.ops, greaterThan(0),
          reason: 'Show has to put something on the canvas or the command '
              'controls nothing');
      // A badge at each end, and a leader between them.
      expect(canvas.members, contains(#drawRRect));
      expect(canvas.members, contains(#drawLine));
    });

    test('every joint kind has a mark of its own', () {
      // A missing case in the mark table would throw inside paint(), which
      // Flutter turns into a red box rather than a failure — so it is asked
      // here, where it is a failure.
      final app = twoBoxes('m249r');
      final m = app.currentAssembly!;
      for (final k in [...kJointKinds, ...kAssemblyKinds, ...kMotionKinds,
        AsmKind.transitional]) {
        m.constraints
          ..clear()
          ..add(AsmConstraint(
            name: 'X',
            kind: k,
            solution: solutionsFor(k).first,
            a: face('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
            b: face('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1)),
          ));
        m.shownRelationships
          ..clear()
          ..add('X');
        final canvas = _CountingCanvas();
        paintRelationshipGlyphs(canvas, frontCam(), m);
        expect(canvas.ops, greaterThan(0), reason: '$k');
      }
    });

    test('they are drawn from BOTH render paths', () {
      // THE TRAP. On iOS RealityKit owns the scene and _AssemblyPainter never
      // runs, so a glyph drawn only there is perfectly visible on this host
      // and invisible on the iPad. Both painters have to call it, and a source
      // check is the only thing that can say so without a device — the same
      // reason m115_ribbon_icons_test reads the ribbon's source.
      final src =
          File('lib/widgets/viewport_assembly.dart').readAsStringSync();
      final calls = RegExp(r'paintRelationshipGlyphs\(canvas')
          .allMatches(src)
          .length;
      expect(calls, 2,
          reason: '_MissingPartPainter (iOS HUD) and _AssemblyPainter (host) '
              'must each draw the glyphs');
    });
  });

  // -------------------------------------------------------------------------
  group('Drive', () {
    test('only relationships with something to sweep can be driven', () {
      AsmConstraint of(AsmKind k) => AsmConstraint(
            name: 'X',
            kind: k,
            solution: solutionsFor(k).first,
            a: face('A:1', Vec3.zero, const Vec3(0, 0, 1)),
            b: face('B:1', Vec3.zero, const Vec3(0, 0, -1)),
          );
      for (final k in const [
        AsmKind.mate,
        AsmKind.angle,
        AsmKind.tangent,
        AsmKind.insert,
        AsmKind.rotation,
        AsmKind.rotationTranslation,
        AsmKind.jointRotational,
      ]) {
        expect(canDriveConstraint(of(k)), isTrue, reason: '$k');
      }
      for (final k in const [AsmKind.symmetry, AsmKind.transitional]) {
        expect(canDriveConstraint(of(k)), isFalse,
            reason: '$k has neither a value nor a shaft');
      }
    });

    test('it opens on the value the relationship already has, plus ten', () {
      final app = asmApp('m249s',
          [occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 0, 30))]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1', value: 4));
      app.openDrive(m.constraints.single);
      final s = app.driveSession!;
      expect(s.motion, isFalse);
      expect(s.start, 4);
      expect(s.end, 14, reason: "Autodesk: \"the default is the Start value "
          'plus ten"');
      expect(s.phase, 0);
    });

    test('sweeping to the end moves the value and re-solves', () {
      final app = asmApp('m249t',
          [occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 0, 30))]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1'));
      app.solveCurrentAssembly();
      final gapWas = m.byId('B:1')!.offset.z;
      app.openDrive(m.constraints.single);
      app.driveToEnd(atEnd: true);
      expect(m.constraints.single.value, closeTo(10, 1e-9));
      expect(m.byId('B:1')!.offset.z, isNot(closeTo(gapWas, 1e-6)),
          reason: 'the sweep has to move the assembly, not just a number');
    });

    test('closing restores both the value and the placements', () {
      final app = asmApp('m249u',
          [occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 0, 30))]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1'));
      app.solveCurrentAssembly();
      final was = m.byId('B:1')!.offset;
      app.openDrive(m.constraints.single);
      app.driveToEnd(atEnd: true);
      app.closeDrive();
      expect(m.constraints.single.value, 0,
          reason: 'a drive is a preview of motion, never an edit');
      expect((m.byId('B:1')!.offset - was).length, lessThan(1e-6));
      expect(app.driveSession, isNull);
    });

    test('a MOTION drive turns the driver, and the gear pair follows', () {
      // The half M242 never had a UI for. A Rotation constraint's own value is
      // a RATIO, which animates nothing; what a drive sweeps is the driver's
      // rotation, and asm_solver.driveMotion is what carries it across.
      final app = asmApp('m249v', [
        occ('A:1', grounded: false),
        occ('B:1', at: const Vec3(30, 0, 0)),
      ]);
      final m = app.currentAssembly!;
      m.constraints.add(AsmConstraint(
        name: 'Rotation:1',
        kind: AsmKind.rotation,
        solution: AsmSolution.forward,
        a: AsmRef('A:1', const AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1)), 'Axis'),
        b: AsmRef('B:1', const AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1)), 'Axis'),
        value: 2,
      ));
      app.openDrive(m.constraints.single);
      final s = app.driveSession!;
      expect(s.motion, isTrue);
      expect(s.end, 360, reason: 'one full turn of the driver');
      // A QUARTER turn of the driver, deliberately: sweeping the whole 360
      // would leave both bodies back where they started (a full turn is the
      // identity quaternion) and the test would read as "nothing moved".
      app.setDriveField(end: 90);
      app.driveToEnd(atEnd: true);
      final driver = m.byId('A:1')!.rot.angle;
      final driven = m.byId('B:1')!.rot.angle;
      expect(driver, closeTo(math.pi / 2, 1e-3),
          reason: 'the drive turns the shaft the constraint names first');
      // TWICE as far, because the ratio is 2. This is the gear pair working —
      // asm_solver.driveMotion carrying the turn across, which is the pass
      // M242 built and never gave a way to run.
      expect(driven, closeTo(math.pi, 1e-2),
          reason: 'driveMotion has to turn the second shaft by the ratio');
      app.closeDrive();
    });

    test('deleting the relationship being driven closes the dialog', () {
      final app = asmApp('m249y',
          [occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 0, 30))]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1'));
      app.openDrive(m.constraints.single);
      app.driveToEnd(atEnd: true);
      app.deleteConstraint(m.constraints.single);
      expect(app.driveSession, isNull,
          reason: 'a dialog open on a relationship that is gone is open on '
              'nothing');
      expect(m.constraints, isEmpty);
    });

    test('opening Place Joint closes a running Drive', () {
      // Two authorities over one placement — the failure asm_solver documents
      // for pattern elements — applied to two dialogs: a drive on a timer must
      // not be moving components while another panel is previewing against a
      // snapshot of them.
      final app = asmApp('m249z',
          [occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 0, 30))]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1'));
      app.openDrive(m.constraints.single);
      app.openJoint();
      expect(app.driveSession, isNull);
      expect(app.constraintSession!.isJoint, isTrue);
      // ...and the reverse, which openDrive has done since it was written.
      app.openDrive(m.constraints.single);
      expect(app.constraintSession, isNull);
      app.closeDrive();
    });

    testWidgets('the timer actually steps the sweep', (t) async {
      final app = asmApp('m249w',
          [occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 0, 30))]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1'));
      app.openDrive(m.constraints.single);
      app.setDriveField(pauseDelay: 0.02, increment: 1);
      app.playDrive();
      expect(app.driveSession!.phase, 0);
      // Five ticks of a tenth-of-a-range step: a fifth of the way.
      await t.pump(const Duration(milliseconds: 120));
      final after = app.driveSession!.phase;
      expect(after, greaterThan(0),
          reason: 'the sweep has to advance on its own, or the ▶ button is a '
              'picture');
      expect(after, lessThan(1));
      app.pauseDrive();
      // Nothing may still be pending, or a periodic timer would outlive the
      // test — which is exactly what AppState.dispose exists to prevent.
      app.closeDrive();
      app.dispose();
    });

    testWidgets('the sweep stops at the end of its last cycle', (t) async {
      final app = asmApp('m249x',
          [occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 0, 30))]);
      final m = app.currentAssembly!;
      m.constraints.add(mate('A:1', 'B:1'));
      app.openDrive(m.constraints.single);
      app.setDriveField(pauseDelay: 0.02, byTotalSteps: true, totalSteps: 4);
      app.playDrive();
      await t.pump(const Duration(milliseconds: 400));
      expect(app.driveSession!.playing, isFalse,
          reason: 'one cycle of Start/End ends at End and stops');
      expect(app.driveSession!.phase, 1);
      app.closeDrive();
      app.dispose();
    });
  });
}

/// Two boxes with one mate between them, for the glyph group.
AppState twoBoxes(String tag) {
  final app = asmApp(tag, [
    occ('A:1', grounded: true),
    occ('B:1', at: const Vec3(0, 0, 30)),
  ]);
  app.currentAssembly!.constraints.add(mate('A:1', 'B:1'));
  return app;
}
