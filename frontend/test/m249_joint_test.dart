// M249 — JOINT: the six types, and the freedom each one leaves.
//
// This is the file the milestone stands on, for a reason asm_joint.dart's
// header states and this one exercises: a joint's whole content is its DEGREES
// OF FREEDOM, and this app can measure them. AsmSolveReport.dof is 6 per free
// body minus the RANK OF THE REAL JACOBIAN — row-reduced, not counted — so
// "a rotational joint leaves exactly one" is an assertion rather than a
// comment, and the six numbers Autodesk publishes (0, 1, 1, 2, 3, 3) are
// checked against the solver rather than against the table they came from.
//
// The rest is what a DOF count cannot see:
//
//   * WHERE the joint put the component. Two joints can leave one freedom and
//     leave it in different places — Rotational leaves a turn and Slider
//     leaves a slide — so each type is also asked where it moved things to.
//   * THE ORIGIN. A joint origin is the point that was POINTED AT, not the
//     kernel's reference point for the surface. That is the single claim that
//     separates a joint from a mate, and it is invisible on screen: a plane
//     whose record point happens to lie on the face looks identical.
//   * AUTOMATIC. Inventor's four rules, in Inventor's order.
//   * THE CAPTURED TWIST, which is this app's stand-in for Inventor's Align
//     references and therefore the thing most likely to be wrong.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_joint.dart';
import 'package:prototype/asm_solver.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/quat.dart';
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

AssemblyModel asm(List<AssemblyOccurrence> os) {
  final a = AssemblyModel('A');
  a.occurrences.addAll(os);
  return a;
}

/// A planar joint origin: the plane's own record point deliberately AWAY from
/// the anchor, because that is the case a joint has to get right and a
/// constraint is entitled to ignore. See AsmRef.anchor.
AsmRef jplane(String occId, Vec3 anchor, Vec3 n, {Vec3? recordAt}) =>
    AsmRef(occId, AsmGeom.plane(recordAt ?? Vec3.zero, n), 'Face',
        anchor: anchor, extent: 10);

/// A circular-edge joint origin — the pick Automatic reads as Rotational.
AsmRef jcircle(String occId, Vec3 centre, Vec3 axisDir, {double r = 3}) =>
    AsmRef(
        occId,
        AsmGeom.axis(centre, axisDir,
            radius: r, source: WorkRefSource.circle),
        'Circular Edge',
        anchor: centre,
        extent: r);

/// A cylindrical-face joint origin — the pick Automatic reads as Cylindrical.
AsmRef jcylinder(String occId, Vec3 on, Vec3 axisDir, {double r = 3}) =>
    AsmRef(
        occId,
        AsmGeom.axis(Vec3.zero, axisDir,
            radius: r, source: WorkRefSource.revolved),
        'Cylindrical Face',
        anchor: on,
        extent: r);

/// A spherical-face joint origin — the pick Automatic reads as Ball.
AsmRef jsphere(String occId, Vec3 centre) => AsmRef(
    occId, AsmGeom.point(centre, source: WorkRefSource.sphere),
    'Spherical Face',
    anchor: centre);

AsmConstraint joint(AsmKind kind, AsmRef a, AsmRef b,
        {double gap = 0, AsmSolution? solution, double? twist}) =>
    AsmConstraint(
      name: '${constraintBaseName(kind)}:1',
      kind: kind,
      solution: solution ?? solutionsFor(kind).first,
      a: a,
      b: b,
      value: gap,
    )..twist = twist;

void expectVec(Vec3 got, Vec3 want, {double eps = 1e-3, String? reason}) {
  expect(got.x, closeTo(want.x, eps), reason: reason);
  expect(got.y, closeTo(want.y, eps), reason: reason);
  expect(got.z, closeTo(want.z, eps), reason: reason);
}

void main() {
  // -------------------------------------------------------------------------
  group('the table', () {
    // The numbers straight out of Inventor's Create Joints Reference, checked
    // against asm_joint's own arithmetic rather than typed twice. This is the
    // cheap half of the claim; the group below is the expensive half.
    test('every type claims the degrees of freedom Autodesk publishes', () {
      expect(jointDof(AsmKind.jointRigid), 0);
      expect(jointDof(AsmKind.jointRotational), 1);
      expect(jointDof(AsmKind.jointSlider), 1);
      expect(jointDof(AsmKind.jointCylindrical), 2);
      expect(jointDof(AsmKind.jointPlanar), 3);
      expect(jointDof(AsmKind.jointBall), 3);
    });

    test('a joint is a relationship like any other', () {
      for (final k in kJointKinds) {
        expect(isJointKind(k), isTrue);
        expect(tabOf(k), AsmTab.joint);
        // Positional: a joint is SOLVED, unlike the two motion kinds, which
        // are driven. Get this wrong and the solver would skip every joint.
        expect(joint(k, jplane('A:1', Vec3.zero, const Vec3(0, 0, 1)),
                jplane('B:1', Vec3.zero, const Vec3(0, 0, -1)))
            .isPositional, isTrue);
        expect(solutionsFor(k), hasLength(2));
        expect(valueKindOf(k), AsmValueKind.offset,
            reason: "Inventor's Gap is a distance");
      }
      // Inventor names a joint after its TYPE: the browser row reads
      // "Rotational:1", never "Joint:1".
      expect(constraintBaseName(AsmKind.jointRotational), 'Rotational');
      expect(nextConstraintName(const [], AsmKind.jointBall), 'Ball:1');
    });
  });

  // -------------------------------------------------------------------------
  group('the solver agrees with the table', () {
    /// Two boxes, the second free, jointed face to face. The moving one starts
    /// somewhere ARBITRARY so the joint has to do real work — a fixture that
    /// starts satisfied would pass for a solver that emits no equations at all.
    (AssemblyModel, AsmConstraint) rig(AsmKind kind,
        {double gap = 0, AsmRef? a, AsmRef? b, Quat? bRot, Vec3? bAt}) {
      final ga = occ('A:1', grounded: true);
      final gb = occ('B:1',
          at: bAt ?? const Vec3(17, -9, 23),
          rot: bRot ?? Quat.axisAngle(const Vec3(1, 2, 3), 0.7));
      final m = asm([ga, gb]);
      final c = joint(
        kind,
        a ?? jplane('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1),
            recordAt: const Vec3(-400, 300, 5)),
        b ?? jplane('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1),
            recordAt: const Vec3(900, -100, -5)),
        gap: gap,
      );
      m.constraints.add(c);
      return (m, c);
    }

    for (final kind in kJointKinds) {
      test('${constraintBaseName(kind)} leaves exactly ${jointDof(kind)}', () {
        // Ball is the one type with no axis to state, and it is made from two
        // sphere centres — the pick that offers no direction at all.
        final (m, c) = kind == AsmKind.jointBall
            ? rig(kind,
                a: jsphere('A:1', const Vec3(0, 0, 5)),
                b: jsphere('B:1', const Vec3(0, 0, -5)))
            : rig(kind);
        final r = solveAssembly(m);
        expect(r.sick, isEmpty,
            reason: 'a joint of two free-enough bodies must be satisfiable');
        // ONE free body, so six columns: the report's dof IS this joint's.
        expect(r.dof, jointDof(kind),
            reason: 'the rank of the real Jacobian must match the table');
        expect(r.fullyConstrained.contains('B:1'), jointDof(kind) == 0,
            reason: 'only Rigid takes every freedom away');
        expect(c.isSick, isFalse);
      });
    }

    test('Rigid brings the two origins together and holds them there', () {
      final (m, c) = rig(AsmKind.jointRigid);
      solveAssembly(m);
      final fa = worldJointFrameOf(m, c.a);
      final fb = worldJointFrameOf(m, c.b);
      expectVec(fb.origin, fa.origin,
          reason: 'the joint origins are the two points that were pointed at');
      // And the origin is NOT the plane's own record point, which was put
      // hundreds of millimetres away on purpose.
      expect((fa.origin - const Vec3(-400, 300, 5)).length, greaterThan(100),
          reason: 'a joint origin is the anchor, never the kernel record point');
    });

    test('the Gap separates the origins along the joint axis', () {
      final (m, c) = rig(AsmKind.jointRotational, gap: 7);
      solveAssembly(m);
      final fa = worldJointFrameOf(m, c.a);
      final fb = worldJointFrameOf(m, c.b);
      final d = fb.origin - fa.origin;
      expect(d.dot(fa.axis), closeTo(7, 1e-3));
      // ...and by nothing across it.
      expect((d - fa.axis * d.dot(fa.axis)).length, lessThan(1e-3));
    });

    test('the opposed solution faces the axes at each other, aligned does not',
        () {
      for (final (sol, sign) in const [
        (AsmSolution.opposed, -1.0),
        (AsmSolution.aligned, 1.0),
      ]) {
        final ga = occ('A:1', grounded: true);
        final gb = occ('B:1',
            at: const Vec3(30, 4, -8),
            rot: Quat.axisAngle(const Vec3(0, 1, 0), 1.1));
        final m = asm([ga, gb]);
        final c = joint(
          AsmKind.jointRotational,
          jcircle('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
          jcircle('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, 1)),
          solution: sol,
        );
        m.constraints.add(c);
        solveAssembly(m);
        final fa = worldJointFrameOf(m, c.a);
        final fb = worldJointFrameOf(m, c.b);
        expect(fb.axis.dot(fa.axis), closeTo(sign, 1e-3),
            reason: '$sol must decide which way the second axis points');
      }
    });

    test('Planar leaves the component ON the plane, free to slide across it',
        () {
      final (m, c) = rig(AsmKind.jointPlanar, gap: 2);
      solveAssembly(m);
      final fa = worldJointFrameOf(m, c.a);
      final fb = worldJointFrameOf(m, c.b);
      final d = fb.origin - fa.origin;
      // The one thing Planar fixes: how far apart along the normal.
      expect(d.dot(fa.axis), closeTo(2, 1e-3));
      // And the thing it does NOT: the component kept the in-plane offset it
      // started with rather than being pulled to the origin. That is what the
      // solver's minimum-motion preference is for, and it is the difference a
      // user sees between a Planar joint and a Rigid one.
      expect((d - fa.axis * d.dot(fa.axis)).length, greaterThan(1),
          reason: 'a planar joint must not close up the in-plane offset');
    });

    test('Cylindrical keeps the axes collinear and lets the shaft run', () {
      final ga = occ('A:1', grounded: true);
      final gb = occ('B:1',
          at: const Vec3(12, 9, 40),
          rot: Quat.axisAngle(const Vec3(1, 1, 0), 0.9));
      final m = asm([ga, gb]);
      final c = joint(
        AsmKind.jointCylindrical,
        jcylinder('A:1', const Vec3(0, 0, 0), const Vec3(0, 0, 1)),
        jcylinder('B:1', const Vec3(0, 0, 0), const Vec3(0, 0, 1)),
      );
      m.constraints.add(c);
      final r = solveAssembly(m);
      expect(r.dof, 2);
      final fa = worldJointFrameOf(m, c.a);
      final fb = worldJointFrameOf(m, c.b);
      final d = fb.origin - fa.origin;
      // Collinear: nothing across the axis. Along it, anything at all — which
      // is the translational freedom the type is named for.
      expect((d - fa.axis * d.dot(fa.axis)).length, lessThan(1e-3));
    });

    test('a joint to a component that has gone is reported sick, not crashed',
        () {
      final m = asm([occ('A:1', grounded: true), occ('B:1')]);
      final c = joint(
        AsmKind.jointRotational,
        jplane('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
        jplane('Ghost:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1)),
      );
      m.constraints.add(c);
      final r = solveAssembly(m);
      expect(r.sick[c.name], 'missingComponent');
    });

    test('a joint between two grounded components says so', () {
      final m = asm([
        occ('A:1', grounded: true),
        occ('B:1', at: const Vec3(50, 0, 0), grounded: true),
      ]);
      final c = joint(
        AsmKind.jointRigid,
        jplane('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
        jplane('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1)),
      );
      m.constraints.add(c);
      final r = solveAssembly(m);
      expect(r.sick[c.name], 'bothGrounded');
    });
  });

  // -------------------------------------------------------------------------
  group('the twist a Rigid or Slider joint holds', () {
    // Inventor holds the rotation about the joint axis against its Align 1 /
    // Align 2 references. This app has none and captures the angle the parts
    // already stood at instead (see AsmConstraint.twist), which makes two
    // things testable: the joint must be SATISFIABLE from any starting twist,
    // and it must actually hold the one it captured.

    /// Rigid-joints two boxes with [b] turned [turn] radians about the joint
    /// axis first, capturing the twist exactly as AppState does.
    (AssemblyModel, AsmConstraint) twisted(AsmKind kind, double turn) {
      final ga = occ('A:1', grounded: true);
      final gb = occ('B:1',
          at: const Vec3(0, 0, 20), rot: Quat.axisAngle(const Vec3(0, 0, 1), turn));
      final m = asm([ga, gb]);
      final a = jplane('A:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1));
      final b = jplane('B:1', const Vec3(0, 0, -5), const Vec3(0, 0, -1));
      final fa = worldJointFrameOf(m, a);
      final fb = worldJointFrameOf(m, b);
      final c = joint(kind, a, b,
          twist: jointTwistBetween(fa.ref, fb.ref, fa.axis));
      m.constraints.add(c);
      return (m, c);
    }

    test('a Rigid joint is satisfiable from any starting twist', () {
      for (final turn in const [0.0, 0.4, 1.9, -2.6, 3.0]) {
        final (m, c) = twisted(AsmKind.jointRigid, turn);
        final r = solveAssembly(m);
        expect(r.sick, isEmpty, reason: 'turn=$turn');
        expect(r.dof, 0, reason: 'turn=$turn');
        expect(c.isSick, isFalse);
      }
    });

    test('and it HOLDS that twist rather than snapping to zero', () {
      const turn = 0.9;
      final (m, c) = twisted(AsmKind.jointRigid, turn);
      solveAssembly(m);
      final fa = worldJointFrameOf(m, c.a);
      final fb = worldJointFrameOf(m, c.b);
      expect(jointTwistBetween(fa.ref, fb.ref, fa.axis), closeTo(c.twist!, 1e-3),
          reason: 'the joint holds the parts where it found them');
      // And that captured angle is not vacuously zero — otherwise this test
      // would pass for a joint that ignores the twist entirely.
      expect(c.twist!.abs(), greaterThan(0.1));
    });

    test('a Slider holds the twist too, and still slides', () {
      final (m, c) = twisted(AsmKind.jointSlider, 0.6);
      final r = solveAssembly(m);
      expect(r.sick, isEmpty);
      expect(r.dof, 1, reason: 'orientation locked, one translation left');
      final fa = worldJointFrameOf(m, c.a);
      final fb = worldJointFrameOf(m, c.b);
      // Nothing across the axis; along it, whatever the minimum-motion
      // preference left, which is the slide.
      final d = fb.origin - fa.origin;
      expect((d - fa.axis * d.dot(fa.axis)).length, lessThan(1e-3));
    });

    test('only the two types that need one carry a twist', () {
      for (final k in kJointKinds) {
        expect(jointLocks(k).twist,
            k == AsmKind.jointRigid || k == AsmKind.jointSlider,
            reason: '$k');
      }
    });

    test('the reference direction is derived in the LOCAL frame, so it is '
        'continuous as the body turns', () {
      // The trap this exists for: jointRefDir picks its seed by which
      // component of the axis is smallest, so it JUMPS as a world axis swings
      // past a diagonal. Derived from a world axis, the twist residual would
      // step and the solver would chase a Jacobian that lies. Derived locally
      // and placed, the frame is a smooth function of the pose — which is what
      // this walks a body through a half turn to show.
      final a = jplane('B:1', const Vec3(0, 0, 5), const Vec3(0, 0, 1));
      Vec3? last;
      for (var i = 0; i <= 40; i++) {
        final ang = i * math.pi / 40;
        final m = asm([occ('B:1', rot: Quat.axisAngle(const Vec3(1, 1, 0.3), ang))]);
        final f = worldJointFrameOf(m, a);
        expect(f.ref.dot(f.axis).abs(), lessThan(1e-9),
            reason: 'the reference must stay across the axis');
        if (last != null) {
          expect((f.ref - last).length, lessThan(0.25),
              reason: 'a jump here is a discontinuous residual at ang=$ang');
        }
        last = f.ref;
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Automatic', () {
    // Inventor's four rules, verbatim from the Create Joints Reference and in
    // its own order. Both origins have to agree; a mixed pair is "all other
    // origin selections", which is Rigid.
    test('two circular origins give Rotational', () {
      expect(
          resolveAutomaticJoint(
              jcircle('A:1', Vec3.zero, const Vec3(0, 0, 1)).geom,
              jcircle('B:1', Vec3.zero, const Vec3(0, 0, 1)).geom),
          AsmKind.jointRotational);
    });

    test('two points on a cylinder give Cylindrical', () {
      expect(
          resolveAutomaticJoint(
              jcylinder('A:1', Vec3.zero, const Vec3(0, 0, 1)).geom,
              jcylinder('B:1', Vec3.zero, const Vec3(0, 0, 1)).geom),
          AsmKind.jointCylindrical);
    });

    test('two points on a sphere give Ball', () {
      expect(
          resolveAutomaticJoint(
              jsphere('A:1', Vec3.zero).geom, jsphere('B:1', Vec3.zero).geom),
          AsmKind.jointBall);
    });

    test('everything else — including a mixed pair — gives Rigid', () {
      final flat = jplane('A:1', Vec3.zero, const Vec3(0, 0, 1)).geom;
      final circle = jcircle('B:1', Vec3.zero, const Vec3(0, 0, 1)).geom;
      final cyl = jcylinder('B:1', Vec3.zero, const Vec3(0, 0, 1)).geom;
      expect(resolveAutomaticJoint(flat, flat), AsmKind.jointRigid);
      expect(resolveAutomaticJoint(circle, flat), AsmKind.jointRigid);
      expect(resolveAutomaticJoint(circle, cyl), AsmKind.jointRigid,
          reason: 'a circular edge and a cylinder are not the same origin');
    });

    test('Slider and Planar are never chosen automatically', () {
      // Not an implementation detail: Automatic names four outcomes in the
      // documentation and these two are not among them.
      for (final pair in [
        (jplane('A:1', Vec3.zero, const Vec3(0, 0, 1)).geom,
            jplane('B:1', Vec3.zero, const Vec3(0, 0, -1)).geom),
        (jcircle('A:1', Vec3.zero, const Vec3(0, 0, 1)).geom,
            jcircle('B:1', Vec3.zero, const Vec3(0, 0, 1)).geom),
        (jsphere('A:1', Vec3.zero).geom, jsphere('B:1', Vec3.zero).geom),
        (jcylinder('A:1', Vec3.zero, const Vec3(0, 0, 1)).geom,
            jcylinder('B:1', Vec3.zero, const Vec3(0, 0, 1)).geom),
      ]) {
        final k = resolveAutomaticJoint(pair.$1, pair.$2);
        expect(k, isNot(AsmKind.jointSlider));
        expect(k, isNot(AsmKind.jointPlanar));
      }
    });

    test('a reference written before M247 still reads as circular', () {
      // AsmGeom.source arrived in M247; a document older than that carries an
      // axis WITH a radius and no source, and an axis with a radius is far
      // more often a circle than anything else.
      const old = AsmGeom(AsmGeomKind.axis, Vec3.zero, Vec3(0, 0, 1), radius: 4);
      expect(resolveAutomaticJoint(old, old), AsmKind.jointRotational);
    });
  });

  // -------------------------------------------------------------------------
  group('what a pick may be jointed by', () {
    test('every type but Ball needs a direction on both sides', () {
      final flat = jplane('A:1', Vec3.zero, const Vec3(0, 0, 1)).geom;
      const vertex = AsmGeom.point(Vec3.zero);
      for (final k in kJointKinds) {
        if (k == AsmKind.jointBall) {
          expect(kindAccepts(k, vertex, vertex), isTrue,
              reason: 'a ball joint is two points and nothing else');
          continue;
        }
        expect(kindAccepts(k, flat, flat), isTrue, reason: '$k');
        expect(kindAccepts(k, vertex, flat), isFalse, reason: '$k');
        expect(rejectionFor(k, vertex, flat), 'jointNeedsDirections');
      }
    });

    test('a Ball joint of two directionless picks still holds the origins',
        () {
      final m = asm([occ('A:1', grounded: true), occ('B:1', at: const Vec3(20, 5, 5))]);
      final c = joint(AsmKind.jointBall, jsphere('A:1', const Vec3(0, 0, 3)),
          jsphere('B:1', const Vec3(0, 0, -3)),
          // A gap with no axis names no direction, so it is IGNORED rather
          // than turned into a residual with no derivative — which the solver
          // could never satisfy and would report sick for ever.
          gap: 9);
      m.constraints.add(c);
      final r = solveAssembly(m);
      expect(r.sick, isEmpty);
      expect(r.dof, 3);
      expectVec(worldJointFrameOf(m, c.b).origin,
          worldJointFrameOf(m, c.a).origin);
    });
  });

  // -------------------------------------------------------------------------
  group('the document', () {
    test('a joint round-trips through JSON, twist and all', () {
      final c = joint(
        AsmKind.jointSlider,
        jplane('A:1', const Vec3(1, 2, 3), const Vec3(0, 0, 1)),
        jplane('B:1', const Vec3(4, 5, 6), const Vec3(0, 0, -1)),
        gap: 2.5,
        solution: AsmSolution.aligned,
        twist: 0.37,
      );
      final back = AsmConstraint.fromJson(c.toJson())!;
      expect(back.kind, AsmKind.jointSlider);
      expect(back.solution, AsmSolution.aligned);
      expect(back.value, 2.5);
      expect(back.twist, closeTo(0.37, 1e-12));
      expect(back.a.anchor.x, 1);
      expect(back.isJoint, isTrue);
    });

    test('a constraint writes no twist at all', () {
      // The byte-identity rule this file inherits: an assembly that has never
      // seen a joint must save exactly what it saved before joints existed.
      final c = AsmConstraint(
        name: 'Mate:1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: jplane('A:1', Vec3.zero, const Vec3(0, 0, 1)),
        b: jplane('B:1', Vec3.zero, const Vec3(0, 0, -1)),
      );
      expect(c.toJson().containsKey('twist'), isFalse);
    });

    test('copy() carries the twist', () {
      // copy() is what the browser's Edit path clones through; dropping the
      // twist there would silently un-rigid a Rigid joint.
      final c = joint(
        AsmKind.jointRigid,
        jplane('A:1', Vec3.zero, const Vec3(0, 0, 1)),
        jplane('B:1', Vec3.zero, const Vec3(0, 0, -1)),
        twist: 1.23,
      );
      expect(c.copy().twist, 1.23);
    });
  });
}
