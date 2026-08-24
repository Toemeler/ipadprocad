// M242 — the assembly constraint solver.
//
// This is the file that decides whether Constrain is a real tool or a
// convincing dialog. Everything else in the milestone — the picks, the
// preview, the browser rows — is plumbing around the question "did the
// components actually end up where the constraint says they should".
//
// So the assertions here are GEOMETRIC, not numeric-internals: after a mate,
// are the two faces coincident and facing each other; after an insert, is the
// bolt's axis the hole's axis; after dragging one link of a four-bar, is the
// linkage still a linkage. A test that checked the residual vector would pass
// for a solver that converged to the wrong answer.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_solver.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/quat.dart';

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

AsmRef plane(String occId, Vec3 at, Vec3 n) =>
    AsmRef(occId, AsmGeom.plane(at, n), 'Face');

AsmRef axis(String occId, Vec3 at, Vec3 d, {double r = 0}) =>
    AsmRef(occId, AsmGeom.axis(at, d, radius: r), r > 0 ? 'Cylindrical Face' : 'Edge');

AsmRef point(String occId, Vec3 at) =>
    AsmRef(occId, AsmGeom.point(at), 'Vertex');

AsmConstraint con(
  AsmKind kind,
  AsmRef a,
  AsmRef b, {
  AsmSolution? solution,
  AsmRef? c,
  double value = 0,
  String? name,
}) =>
    AsmConstraint(
      name: name ?? '${constraintBaseName(kind)}:1',
      kind: kind,
      solution: solution ?? solutionsFor(kind).first,
      a: a,
      b: b,
      c: c,
      value: value,
    );

/// The world geometry of a reference, after the solve moved things.
AsmGeom worldOf(AssemblyModel m, AsmRef r) {
  if (r.isAssemblyOrigin) return r.geom;
  final o = m.byId(r.occurrence)!;
  return AsmGeom(r.geom.kind, o.toWorld(r.geom.at), o.dirToWorld(r.geom.dir),
      radius: r.geom.radius);
}

void expectVec(Vec3 got, Vec3 want, {double eps = 1e-4, String? reason}) {
  expect(got.x, closeTo(want.x, eps), reason: reason);
  expect(got.y, closeTo(want.y, eps), reason: reason);
  expect(got.z, closeTo(want.z, eps), reason: reason);
}

void main() {
  // -------------------------------------------------------------------------
  group('the quaternion underneath it', () {
    test('fromTo turns one direction onto another, shortest way', () {
      for (final (from, to) in const [
        (Vec3(1, 0, 0), Vec3(0, 1, 0)),
        (Vec3(0, 0, 1), Vec3(1, 1, 1)),
        (Vec3(-3, 2, 7), Vec3(0.5, -9, 1)),
      ]) {
        final q = Quat.fromTo(from, to);
        expectVec(q.rotate(from.normalized()), to.normalized());
      }
    });

    test('the ANTIPARALLEL case is a half turn, not a NaN', () {
      // The case that has to be written down rather than discovered: the
      // cross product that normally gives the axis is zero here.
      const from = Vec3(0, 1, 0);
      final q = Quat.fromTo(from, const Vec3(0, -1, 0));
      final got = q.rotate(from);
      expect(got.x.isNaN, isFalse);
      expectVec(got, const Vec3(0, -1, 0));
      expect(q.angle, closeTo(math.pi, 1e-6));
    });

    test('a rotation composed with its inverse is nothing at all', () {
      final q = Quat.axisAngle(const Vec3(1, 2, 3), 1.1);
      final r = (q * q.conjugate).normalized();
      expect(r.isIdentity, isTrue);
      expectVec(q.unrotate(q.rotate(const Vec3(4, -5, 6))),
          const Vec3(4, -5, 6), eps: 1e-9);
    });

    test('composition applies the RIGHT one first', () {
      // a * b means "b, then a" — the matrix convention. Getting this
      // backwards would make every solver correction turn the wrong way.
      final a = Quat.axisAngle(const Vec3(0, 0, 1), math.pi / 2);
      final b = Quat.axisAngle(const Vec3(1, 0, 0), math.pi / 2);
      expectVec((a * b).rotate(const Vec3(0, 1, 0)),
          a.rotate(b.rotate(const Vec3(0, 1, 0))), eps: 1e-9);
    });

    test('it survives the document round trip', () {
      final q = Quat.axisAngle(const Vec3(1, -2, 0.5), 2.2);
      final back = Quat.fromJson(q.toJson());
      expectVec(back.rotate(const Vec3(1, 1, 1)), q.rotate(const Vec3(1, 1, 1)),
          eps: 1e-12);
      // Garbage must come back as "no rotation", never as a NaN that would
      // silently move a component to nowhere.
      expect(Quat.fromJson(null).isIdentity, isTrue);
      expect(Quat.fromJson([0, 0, 0, 0]).isIdentity, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('Mate', () {
    test('two planar faces end up coincident and facing each other', () {
      // A grounded block with its top face at y = 0 pointing up, and a loose
      // block 30 mm away whose bottom face points DOWN in its own frame.
      final m = asm([occ('Base:1', grounded: true), occ('Lid:1', at: const Vec3(37, 22, -9))]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('Base:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('Lid:1', Vec3.zero, const Vec3(0, -1, 0)),
      ));

      final r = solveAssembly(m);
      expect(r.converged, isTrue, reason: r.sick.toString());

      final a = worldOf(m, m.constraints.first.a);
      final b = worldOf(m, m.constraints.first.b);
      // Facing each other...
      expect(a.dir.normalized().dot(b.dir.normalized()), closeTo(-1, 1e-4));
      // ...and touching.
      expect((b.at - a.at).dot(a.dir.normalized()), closeTo(0, 1e-4));
    });

    test('the grounded component is the one that does NOT move', () {
      final m = asm([
        occ('Base:1', at: const Vec3(5, 5, 5), grounded: true),
        occ('Lid:1', at: const Vec3(40, 0, 0)),
      ]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('Base:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('Lid:1', Vec3.zero, const Vec3(0, -1, 0)),
      ));
      solveAssembly(m);
      expectVec(m.byId('Base:1')!.offset, const Vec3(5, 5, 5),
          reason: 'grounded means grounded');
      expect(m.byId('Lid:1')!.offset.y, isNot(closeTo(0, 1e-6)));
    });

    test('an offset holds the faces exactly that far apart', () {
      final m = asm([occ('Base:1', grounded: true), occ('Lid:1', at: const Vec3(0, 50, 0))]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('Base:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('Lid:1', Vec3.zero, const Vec3(0, -1, 0)),
        value: 12.5,
      ));
      expect(solveAssembly(m).converged, isTrue);
      final a = worldOf(m, m.constraints.first.a);
      final b = worldOf(m, m.constraints.first.b);
      expect((b.at - a.at).dot(a.dir.normalized()), closeTo(12.5, 1e-4));
    });

    test('Flush aligns the normals instead of opposing them', () {
      final m = asm([occ('Base:1', grounded: true), occ('Lid:1', at: const Vec3(0, 50, 0))]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('Base:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('Lid:1', Vec3.zero, const Vec3(0, -1, 0)),
        solution: AsmSolution.flush,
      ));
      expect(solveAssembly(m).converged, isTrue);
      final a = worldOf(m, m.constraints.first.a);
      final b = worldOf(m, m.constraints.first.b);
      expect(a.dir.normalized().dot(b.dir.normalized()), closeTo(1, 1e-4),
          reason: 'flush means the same way, not opposite');
    });

    test('two axes become one line', () {
      final m = asm([
        occ('Shaft:1', grounded: true),
        occ('Bore:1', at: const Vec3(20, 30, 40), rot: Quat.axisAngle(const Vec3(1, 1, 0), 0.7)),
      ]);
      m.constraints.add(con(
        AsmKind.mate,
        axis('Shaft:1', Vec3.zero, const Vec3(0, 0, 1)),
        axis('Bore:1', Vec3.zero, const Vec3(0, 0, 1)),
        solution: AsmSolution.flush, // parallel, not opposed
      ));
      expect(solveAssembly(m).converged, isTrue);
      final a = worldOf(m, m.constraints.first.a);
      final b = worldOf(m, m.constraints.first.b);
      expect(a.dir.normalized().dot(b.dir.normalized()).abs(), closeTo(1, 1e-4));
      // Collinear: the perpendicular separation is gone.
      final d = b.at - a.at;
      final ax = a.dir.normalized();
      expect((d - ax * d.dot(ax)).length, closeTo(0, 1e-3));
    });

    test('a point mates onto a plane at the offset', () {
      final m = asm([occ('Base:1', grounded: true), occ('Pin:1', at: const Vec3(9, 9, 9))]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('Base:1', Vec3.zero, const Vec3(0, 1, 0)),
        point('Pin:1', Vec3.zero),
        value: 3,
      ));
      expect(solveAssembly(m).converged, isTrue);
      expect(m.byId('Pin:1')!.toWorld(Vec3.zero).y, closeTo(3, 1e-4));
    });
  });

  // -------------------------------------------------------------------------
  group('Angle', () {
    test('undirected sets the magnitude of the angle', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1')]);
      m.constraints.add(con(
        AsmKind.angle,
        plane('A:1', Vec3.zero, const Vec3(1, 0, 0)),
        plane('B:1', Vec3.zero, const Vec3(1, 0, 0)),
        solution: AsmSolution.undirectedAngle,
        value: 30,
      ));
      expect(solveAssembly(m).converged, isTrue);
      final got = angleBetweenDeg(worldOf(m, m.constraints.first.a).dir,
          worldOf(m, m.constraints.first.b).dir);
      expect(got, closeTo(30, 1e-3));
    });

    test('an explicit reference vector fixes the SIGN of the angle', () {
      // Two runs of the same 40 degrees about opposite reference axes have to
      // land on opposite sides — that is the whole difference between a
      // directed angle and an undirected one.
      Vec3 solveWith(Vec3 refAxis) {
        final m = asm([occ('A:1', grounded: true), occ('B:1')]);
        m.constraints.add(con(
          AsmKind.angle,
          plane('A:1', Vec3.zero, const Vec3(1, 0, 0)),
          plane('B:1', Vec3.zero, const Vec3(1, 0, 0)),
          solution: AsmSolution.explicitVector,
          c: AsmRef(kAssemblyOrigin, AsmGeom.axis(Vec3.zero, refAxis), 'Z Axis'),
          value: 40,
        ));
        expect(solveAssembly(m).converged, isTrue,
            reason: 'ref $refAxis');
        return worldOf(m, m.constraints.first.b).dir.normalized();
      }

      final plus = solveWith(const Vec3(0, 0, 1));
      final minus = solveWith(const Vec3(0, 0, -1));
      expect(angleBetweenDeg(const Vec3(1, 0, 0), plus), closeTo(40, 1e-3));
      expect(angleBetweenDeg(const Vec3(1, 0, 0), minus), closeTo(40, 1e-3));
      // Same magnitude, opposite sense: the y components must differ in sign.
      expect(plus.y * minus.y, lessThan(0),
          reason: 'the reference vector did not steer the direction');
    });
  });

  // -------------------------------------------------------------------------
  group('Tangent', () {
    test('a cylinder rests ON a plane at exactly its radius', () {
      final m = asm([occ('Table:1', grounded: true), occ('Roller:1', at: const Vec3(0, 40, 0))]);
      m.constraints.add(con(
        AsmKind.tangent,
        plane('Table:1', Vec3.zero, const Vec3(0, 1, 0)),
        axis('Roller:1', Vec3.zero, const Vec3(1, 0, 0), r: 7),
        solution: AsmSolution.outside,
      ));
      expect(solveAssembly(m).converged, isTrue);
      final cyl = worldOf(m, m.constraints.first.b);
      // The axis sits one radius above the table...
      expect(cyl.at.y, closeTo(7, 1e-4));
      // ...and runs parallel to it.
      expect(cyl.dir.normalized().dot(const Vec3(0, 1, 0)).abs(),
          closeTo(0, 1e-4));
    });

    test('Inside puts it on the other side of the plane', () {
      final m = asm([occ('Table:1', grounded: true), occ('Roller:1', at: const Vec3(0, 40, 0))]);
      m.constraints.add(con(
        AsmKind.tangent,
        plane('Table:1', Vec3.zero, const Vec3(0, 1, 0)),
        axis('Roller:1', Vec3.zero, const Vec3(1, 0, 0), r: 7),
        solution: AsmSolution.inside,
      ));
      expect(solveAssembly(m).converged, isTrue);
      expect(worldOf(m, m.constraints.first.b).at.y, closeTo(-7, 1e-4));
    });

    test('two cylinders touch at the sum of their radii', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1', at: const Vec3(60, 5, 0))]);
      m.constraints.add(con(
        AsmKind.tangent,
        axis('A:1', Vec3.zero, const Vec3(0, 0, 1), r: 10),
        axis('B:1', Vec3.zero, const Vec3(0, 0, 1), r: 4),
        solution: AsmSolution.outside,
      ));
      expect(solveAssembly(m).converged, isTrue);
      final a = worldOf(m, m.constraints.first.a);
      final b = worldOf(m, m.constraints.first.b);
      final d = b.at - a.at;
      final ax = a.dir.normalized();
      expect((d - ax * d.dot(ax)).length, closeTo(14, 1e-3));
    });

    test('two planes cannot be tangent, and the model says so up front', () {
      // Inventor refuses this combination rather than producing a constraint
      // that is born sick, and so does the dialog — this is the rule it asks.
      const pl = AsmGeom.plane(Vec3.zero, Vec3(0, 1, 0));
      expect(kindAccepts(AsmKind.tangent, pl, pl), isFalse);
      expect(rejectionFor(AsmKind.tangent, pl, pl), 'tangentNeedsRound');
      const cyl = AsmGeom.axis(Vec3.zero, Vec3(1, 0, 0), radius: 3);
      expect(kindAccepts(AsmKind.tangent, pl, cyl), isTrue);
      expect(rejectionFor(AsmKind.tangent, pl, cyl), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('Insert', () {
    test('a bolt drops into a hole: axes collinear, edges together', () {
      final m = asm([
        occ('Plate:1', grounded: true),
        occ('Bolt:1',
            at: const Vec3(25, 40, -15),
            rot: Quat.axisAngle(const Vec3(1, 0.4, 0.2), 1.4)),
      ]);
      m.constraints.add(con(
        AsmKind.insert,
        // The hole's mouth: a circular edge at the origin, axis +Y.
        axis('Plate:1', Vec3.zero, const Vec3(0, 1, 0)),
        // The bolt's head-underside edge, axis +Y in its own frame.
        axis('Bolt:1', Vec3.zero, const Vec3(0, 1, 0)),
        solution: AsmSolution.opposed,
      ));
      expect(solveAssembly(m).converged, isTrue);
      final a = worldOf(m, m.constraints.first.a);
      final b = worldOf(m, m.constraints.first.b);
      expect(a.dir.normalized().dot(b.dir.normalized()), closeTo(-1, 1e-4),
          reason: 'opposed');
      expectVec(b.at, a.at, eps: 1e-3, reason: 'offset 0 means edge on edge');
    });

    test('the offset lifts the bolt head off the face', () {
      final m = asm([occ('Plate:1', grounded: true), occ('Bolt:1', at: const Vec3(0, 30, 0))]);
      m.constraints.add(con(
        AsmKind.insert,
        axis('Plate:1', Vec3.zero, const Vec3(0, 1, 0)),
        axis('Bolt:1', Vec3.zero, const Vec3(0, 1, 0)),
        solution: AsmSolution.opposed,
        value: 5,
      ));
      expect(solveAssembly(m).converged, isTrue);
      final a = worldOf(m, m.constraints.first.a);
      final b = worldOf(m, m.constraints.first.b);
      expect((b.at - a.at).dot(a.dir.normalized()), closeTo(5, 1e-3));
    });

    test('Insert leaves the bolt free to spin, and says so', () {
      // Inventor's own description: an insert constraint leaves one
      // rotational degree of freedom. That is a claim about the RANK of the
      // Jacobian, and it is worth checking that the solver agrees.
      final m = asm([occ('Plate:1', grounded: true), occ('Bolt:1', at: const Vec3(0, 30, 0))]);
      m.constraints.add(con(
        AsmKind.insert,
        axis('Plate:1', Vec3.zero, const Vec3(0, 1, 0)),
        axis('Bolt:1', Vec3.zero, const Vec3(0, 1, 0)),
      ));
      final r = solveAssembly(m);
      expect(r.dof, 1, reason: 'a bolt in a hole can still turn');
      expect(r.fullyConstrained, contains('Plate:1'));
      expect(r.fullyConstrained, isNot(contains('Bolt:1')));
    });
  });

  // -------------------------------------------------------------------------
  group('Symmetry', () {
    test('two components land mirrored about the plane', () {
      final m = asm([
        occ('L:1', at: const Vec3(-20, 0, 0), grounded: true),
        occ('R:1', at: const Vec3(3, 9, 4)),
      ]);
      m.constraints.add(con(
        AsmKind.symmetry,
        point('L:1', Vec3.zero),
        point('R:1', Vec3.zero),
        c: AsmRef(kAssemblyOrigin,
            const AsmGeom.plane(Vec3.zero, Vec3(1, 0, 0)), 'YZ Plane'),
      ));
      expect(solveAssembly(m).converged, isTrue);
      final l = m.byId('L:1')!.toWorld(Vec3.zero);
      final r = m.byId('R:1')!.toWorld(Vec3.zero);
      expectVec(r, Vec3(-l.x, l.y, l.z), eps: 1e-3);
    });
  });

  // -------------------------------------------------------------------------
  group('degrees of freedom', () {
    test('a loose component has six, and the count is exact', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1'), occ('C:1')]);
      expect(solveAssembly(m).dof, 12, reason: 'two free bodies, nothing held');
    });

    test('a plane mate removes exactly three', () {
      // Autodesk: a mate between planar faces "removes one degree of linear
      // translation and two degrees of angular rotation".
      final m = asm([occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 20, 0))]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('B:1', Vec3.zero, const Vec3(0, -1, 0)),
      ));
      expect(solveAssembly(m).dof, 3);
    });

    test('three mates fully constrain a block, and it is reported', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1', at: const Vec3(30, 30, 30))]);
      for (final (i, n) in const [
        (0, Vec3(0, 1, 0)),
        (1, Vec3(1, 0, 0)),
        (2, Vec3(0, 0, 1)),
      ]) {
        m.constraints.add(con(
          AsmKind.mate,
          plane('A:1', Vec3.zero, n),
          plane('B:1', Vec3.zero, n * -1),
          name: 'Mate:${i + 1}',
        ));
      }
      final r = solveAssembly(m);
      expect(r.converged, isTrue, reason: r.sick.toString());
      expect(r.dof, 0);
      expect(r.fullyConstrained, containsAll(['A:1', 'B:1']));
    });
  });

  // -------------------------------------------------------------------------
  group('sick constraints', () {
    test('a constraint between two grounded components cannot be met', () {
      final m = asm([
        occ('A:1', grounded: true),
        occ('B:1', at: const Vec3(0, 50, 0), grounded: true),
      ]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('B:1', Vec3.zero, const Vec3(0, -1, 0)),
      ));
      final r = solveAssembly(m);
      expect(r.converged, isFalse);
      expect(r.sick['Mate:1'], 'bothGrounded');
      expect(m.constraints.first.isSick, isTrue);
    });

    test('two mates that contradict each other leave one sick', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1')]);
      // The same face pair, held 0 mm apart AND 20 mm apart.
      m.constraints.add(con(
        AsmKind.mate,
        plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('B:1', Vec3.zero, const Vec3(0, -1, 0)),
        name: 'Mate:1',
      ));
      m.constraints.add(con(
        AsmKind.mate,
        plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('B:1', Vec3.zero, const Vec3(0, -1, 0)),
        value: 20,
        name: 'Mate:2',
      ));
      final r = solveAssembly(m);
      expect(r.converged, isFalse);
      expect(r.sick, isNotEmpty);
    });

    test('suppressing a constraint takes it out of the solve entirely', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 50, 0))]);
      final c = con(
        AsmKind.mate,
        plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('B:1', Vec3.zero, const Vec3(0, -1, 0)),
      )..suppressed = true;
      m.constraints.add(c);
      final r = solveAssembly(m);
      expectVec(m.byId('B:1')!.offset, const Vec3(0, 50, 0),
          reason: 'a suppressed constraint moves nothing');
      expect(r.dof, 6);
      expect(c.isSick, isFalse);
    });

    test('a healthy constraint clears the sick mark it used to carry', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1', at: const Vec3(0, 50, 0))]);
      final c = con(
        AsmKind.mate,
        plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('B:1', Vec3.zero, const Vec3(0, -1, 0)),
      )..error = 'left over from an earlier solve';
      m.constraints.add(c);
      solveAssembly(m);
      expect(c.isSick, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('dragging a mechanism', () {
    /// A slider: a block mated to a plane so it can only slide in that plane,
    /// dragged by a point on it.
    test('a dragged component follows the finger only where it is free', () {
      final m = asm([occ('Rail:1', grounded: true), occ('Slide:1')]);
      m.constraints.add(con(
        AsmKind.mate,
        plane('Rail:1', Vec3.zero, const Vec3(0, 1, 0)),
        plane('Slide:1', Vec3.zero, const Vec3(0, -1, 0)),
      ));
      solveAssembly(m);

      // Drag it sideways AND upwards. It must go sideways and stay put
      // vertically — the mate has taken that freedom away.
      final r = solveAssembly(m,
          drag: const AsmDrag('Slide:1', Vec3.zero, Vec3(30, 25, 0)));
      expect(r.converged, isTrue, reason: r.sick.toString());
      final p = m.byId('Slide:1')!.toWorld(Vec3.zero);
      expect(p.x, closeTo(30, 0.5), reason: 'free to slide');
      expect(p.y, closeTo(0, 1e-3), reason: 'the mate is hard, the drag is a wish');
    });

    test('a four-bar linkage stays a linkage while it is dragged', () {
      // Ground, crank, coupler, rocker — pinned in a loop with axis mates.
      // Every pin is a Z axis, so the whole thing is planar.
      final m = asm([
        occ('Ground:1', grounded: true),
        occ('Crank:1'),
        occ('Coupler:1'),
        occ('Rocker:1'),
      ]);
      // Pin positions in each body's OWN frame; the links overlap at their
      // ends, which is what a pin joint is.
      const z = Vec3(0, 0, 1);
      void pin(String name, String occA, Vec3 pa, String occB, Vec3 pb) {
        m.constraints.add(con(
          AsmKind.mate,
          axis(occA, pa, z),
          axis(occB, pb, z),
          solution: AsmSolution.flush,
          name: name,
        ));
      }

      pin('Mate:1', 'Ground:1', Vec3.zero, 'Crank:1', Vec3.zero);
      pin('Mate:2', 'Crank:1', const Vec3(20, 0, 0), 'Coupler:1', Vec3.zero);
      pin('Mate:3', 'Coupler:1', const Vec3(50, 0, 0), 'Rocker:1', Vec3.zero);
      pin('Mate:4', 'Rocker:1', const Vec3(40, 0, 0), 'Ground:1', const Vec3(45, 0, 0));

      final first = solveAssembly(m);
      expect(first.converged, isTrue, reason: first.sick.toString());

      // Now turn the crank a full revolution by dragging its far end round.
      // These link lengths satisfy Grashof (20 + 50 <= 45 + 40) with the
      // shortest link next to ground, so the crank really can go all the way
      // round — anything less than that would be the mechanism's fault, not
      // the solver's, and the test would be measuring the wrong thing.
      //
      // Two assertions per step, and both matter. That every pin is still a
      // pin is what a relaxation solver fails: it walks a closed loop apart.
      // That the tip REACHED the target is what says the linkage actually
      // followed rather than the solver finding peace by not moving.
      for (var step = 1; step <= 24; step++) {
        final ang = step * math.pi / 12;
        final target = Vec3(20 * math.cos(ang), 20 * math.sin(ang), 0);
        final r = solveAssembly(m,
            drag: AsmDrag('Crank:1', const Vec3(20, 0, 0), target));
        expect(r.converged, isTrue, reason: 'step $step: ${r.sick}');
        for (final c in m.constraints) {
          final ga = worldOf(m, c.a), gb = worldOf(m, c.b);
          final d = gb.at - ga.at;
          final ax = ga.dir.normalized();
          expect((d - ax * d.dot(ax)).length, lessThan(0.05),
              reason: '${c.name} came apart at step $step');
        }
        final tip = m.byId('Crank:1')!.toWorld(const Vec3(20, 0, 0));
        expect((tip - target).length, lessThan(1.0),
            reason: 'step $step: the crank did not follow to $target, '
                'it is at $tip');
      }
    });

    test('a fully constrained component does not follow a drag at all', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1')]);
      for (final (i, n) in const [
        (0, Vec3(0, 1, 0)),
        (1, Vec3(1, 0, 0)),
        (2, Vec3(0, 0, 1)),
      ]) {
        m.constraints.add(con(
          AsmKind.mate,
          plane('A:1', Vec3.zero, n),
          plane('B:1', Vec3.zero, n * -1),
          name: 'Mate:${i + 1}',
        ));
      }
      solveAssembly(m);
      final before = m.byId('B:1')!.offset;
      solveAssembly(m,
          drag: const AsmDrag('B:1', Vec3.zero, Vec3(100, 100, 100)));
      expectVec(m.byId('B:1')!.offset, before, eps: 1e-3,
          reason: 'nothing was free to give');
    });
  });

  // -------------------------------------------------------------------------
  group('motion constraints are DRIVEN, never solved', () {
    test('a gear pair turns the other gear, by the ratio', () {
      final m = asm([occ('Gear:1', grounded: true), occ('Gear:2')]);
      m.constraints.add(con(
        AsmKind.rotation,
        axis('Gear:1', Vec3.zero, const Vec3(0, 0, 1)),
        axis('Gear:2', Vec3.zero, const Vec3(0, 0, 1)),
        value: 2, // the driven gear turns twice per turn of the driver
      ));
      driveMotion(m, 'Gear:1', math.pi / 2);
      // Two turns per one, and the OTHER way round — meshed gears counter-rotate.
      final turned = m.byId('Gear:2')!.rot;
      expect(turned.angle, closeTo(math.pi, 1e-6));
      expect(turned.rotate(const Vec3(1, 0, 0)).x, closeTo(-1, 1e-6));
    });

    test('Reverse makes them turn the same way', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1')]);
      m.constraints.add(con(
        AsmKind.rotation,
        axis('A:1', Vec3.zero, const Vec3(0, 0, 1)),
        axis('B:1', Vec3.zero, const Vec3(0, 0, 1)),
        solution: AsmSolution.reverse,
        value: 1,
      ));
      driveMotion(m, 'A:1', 0.4);
      final v = m.byId('B:1')!.rot.rotate(const Vec3(1, 0, 0));
      expect(math.atan2(v.y, v.x), closeTo(0.4, 1e-6));
    });

    test('rack and pinion: the rack travels the given distance per turn', () {
      final m = asm([occ('Pinion:1', grounded: true), occ('Rack:1')]);
      m.constraints.add(con(
        AsmKind.rotationTranslation,
        axis('Pinion:1', Vec3.zero, const Vec3(0, 0, 1)),
        axis('Rack:1', Vec3.zero, const Vec3(1, 0, 0)),
        value: 30, // 30 mm per full turn
      ));
      driveMotion(m, 'Pinion:1', 2 * math.pi); // one full turn
      expect(m.byId('Rack:1')!.offset.x.abs(), closeTo(30, 1e-6));
    });

    test('a motion constraint never appears in the position solve', () {
      // Autodesk: motion constraints act only on open degrees of freedom and
      // cannot conflict with assembly constraints. So they must remove no
      // freedom and move nothing on their own.
      final m = asm([occ('A:1', grounded: true), occ('B:1', at: const Vec3(40, 0, 0))]);
      m.constraints.add(con(
        AsmKind.rotation,
        axis('A:1', Vec3.zero, const Vec3(0, 0, 1)),
        axis('B:1', Vec3.zero, const Vec3(0, 0, 1)),
        value: 1,
      ));
      final r = solveAssembly(m);
      expect(r.dof, 6, reason: 'a motion constraint removes no freedom');
      expectVec(m.byId('B:1')!.offset, const Vec3(40, 0, 0),
          reason: 'and repositions nothing');
      expect(r.sick, isEmpty);
    });

    test('a grounded driven component is left alone', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1', grounded: true)]);
      m.constraints.add(con(
        AsmKind.rotation,
        axis('A:1', Vec3.zero, const Vec3(0, 0, 1)),
        axis('B:1', Vec3.zero, const Vec3(0, 0, 1)),
        value: 1,
      ));
      expect(driveMotion(m, 'A:1', 1.0), isEmpty);
      expect(m.byId('B:1')!.rot.isIdentity, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('the document', () {
    test('constraints survive the round trip', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1')]);
      m.constraints.add(con(
        AsmKind.insert,
        axis('A:1', const Vec3(1, 2, 3), const Vec3(0, 1, 0), r: 4),
        axis('B:1', Vec3.zero, const Vec3(0, 1, 0)),
        solution: AsmSolution.aligned,
        value: 2.5,
        name: 'Insert:1',
      ));
      m.byId('B:1')!.rot = Quat.axisAngle(const Vec3(1, 1, 0), 0.9);

      final back = AssemblyModel('A')..loadJson(m.toJson());
      expect(back.constraints, hasLength(1));
      final c = back.constraints.first;
      expect(c.name, 'Insert:1');
      expect(c.kind, AsmKind.insert);
      expect(c.solution, AsmSolution.aligned);
      expect(c.value, 2.5);
      expect(c.a.geom.radius, 4);
      expectVec(c.a.geom.at, const Vec3(1, 2, 3), eps: 1e-12);
      // The ORIENTATION too — a component that came back unrotated would put
      // the whole assembly back at its unsolved state on every open.
      expectVec(back.byId('B:1')!.rot.rotate(const Vec3(1, 0, 0)),
          m.byId('B:1')!.rot.rotate(const Vec3(1, 0, 0)), eps: 1e-9);
    });

    test('deleting a component takes its constraints with it', () {
      final m = asm([occ('A:1', grounded: true), occ('B:1'), occ('C:1')]);
      m.constraints.add(con(AsmKind.mate, plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
          plane('B:1', Vec3.zero, const Vec3(0, -1, 0)), name: 'Mate:1'));
      m.constraints.add(con(AsmKind.mate, plane('A:1', Vec3.zero, const Vec3(1, 0, 0)),
          plane('C:1', Vec3.zero, const Vec3(-1, 0, 0)), name: 'Mate:2'));
      m.remove(m.byId('B:1')!);
      expect(m.constraints.map((c) => c.name), ['Mate:2']);
    });

    test('names count the way Inventor counts', () {
      final cs = <AsmConstraint>[];
      expect(nextConstraintName(cs, AsmKind.mate), 'Mate:1');
      cs.add(con(AsmKind.mate, plane('A:1', Vec3.zero, const Vec3(0, 1, 0)),
          plane('B:1', Vec3.zero, const Vec3(0, 1, 0)), name: 'Mate:1'));
      expect(nextConstraintName(cs, AsmKind.mate), 'Mate:2');
      expect(nextConstraintName(cs, AsmKind.insert), 'Insert:1');
    });
  });

  // -------------------------------------------------------------------------
  group('the dialog contract', () {
    test('every kind offers the solutions Inventor offers', () {
      expect(solutionsFor(AsmKind.mate), hasLength(2));
      expect(solutionsFor(AsmKind.angle), hasLength(3));
      expect(solutionsFor(AsmKind.tangent), hasLength(2));
      expect(solutionsFor(AsmKind.insert), hasLength(2));
      expect(solutionsFor(AsmKind.symmetry), hasLength(2));
      for (final k in AsmKind.values) {
        expect(solutionsFor(k), isNotEmpty,
            reason: 'the Solution group is never empty');
      }
    });

    test('the third pick button appears exactly where Inventor shows it', () {
      expect(selectionCountFor(AsmKind.mate, AsmSolution.mate), 2);
      expect(selectionCountFor(AsmKind.angle, AsmSolution.directedAngle), 2);
      expect(selectionCountFor(AsmKind.angle, AsmSolution.undirectedAngle), 2);
      expect(selectionCountFor(AsmKind.angle, AsmSolution.explicitVector), 3,
          reason: 'the reference vector is a third selection');
      expect(selectionCountFor(AsmKind.symmetry, AsmSolution.symmetric), 3,
          reason: 'symmetry needs the plane to be symmetric about');
    });

    test('the value field means different things on different tabs', () {
      expect(valueKindOf(AsmKind.mate), AsmValueKind.offset);
      expect(valueKindOf(AsmKind.angle), AsmValueKind.angle);
      expect(valueKindOf(AsmKind.rotation), AsmValueKind.ratio);
      expect(valueKindOf(AsmKind.rotationTranslation),
          AsmValueKind.distancePerTurn);
      expect(valueKindOf(AsmKind.transitional), AsmValueKind.none);
    });

    test('kinds are on the tabs Inventor puts them on', () {
      for (final k in kAssemblyKinds) {
        expect(tabOf(k), AsmTab.assembly);
      }
      for (final k in kMotionKinds) {
        expect(tabOf(k), AsmTab.motion);
      }
      expect(tabOf(AsmKind.transitional), AsmTab.transitional);
    });
  });
}
