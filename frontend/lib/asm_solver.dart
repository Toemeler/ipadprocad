// M242 — the assembly constraint solver.
//
// WHY THIS IS A LEAST-SQUARES SOLVE AND NOT A RELAXATION
//
// The obvious cheap thing is per-constraint relaxation: walk the constraints,
// and for each one move the second component until it is satisfied. That
// PLACES parts perfectly well and is completely inadequate the moment you drag
// one. A four-bar linkage grabbed by a link needs every body to move together
// through the freedom that is left; a relaxation moves one body at a time and
// either locks up or walks the mechanism apart.
//
// So this is the same shape as the 2D sketch solver (lib/solver.dart): pack
// the unknowns, evaluate residuals, take a Levenberg-Marquardt step, repeat.
// The two share their linear algebra — rankAndPivots and solveDense are that
// file's, made public in M242 rather than written twice.
//
// THE UNKNOWNS ARE INCREMENTS, NOT COORDINATES
//
// A body's orientation is a unit quaternion, which is four numbers with one
// invariant — parametrise the solve with it directly and every step has to be
// re-normalised, which is exactly the drift PartCamera.setBasis has to
// re-orthogonalise away. Instead each free body contributes SIX unknowns, a
// translation and a rotation VECTOR, both increments from wherever the body
// currently is:
//
//     offset' = offset + dt
//     rot'    = exp(dw) * rot          (rotation about the body's own origin)
//
// A step is baked into the bodies and the unknowns reset to zero, so the
// linearisation is always taken at the current state and the quaternion is
// only ever multiplied by another unit quaternion. This is the standard
// on-manifold formulation and it is why the solve is stable through a drag
// that turns a component through half a revolution.
//
// MOTION CONSTRAINTS ARE NOT IN HERE
//
// Rotation and Rotation-Translation never appear as residuals. Autodesk is
// explicit that motion constraints operate only on OPEN degrees of freedom and
// cannot conflict with assembly constraints: a gear ratio is applied while you
// drag, not solved. [driveMotion] is that pass, and it runs before the solve —
// it proposes where the driven bodies should go, and the solve then honours
// the positional constraints over that proposal.
import 'dart:math' as math;

import 'asm_constraints.dart';
import 'assembly.dart';
import 'part_model.dart';
import 'part_render.dart' show kFaceCylinder, kFacePlane;
import 'quat.dart';
import 'solver.dart' show rankAndPivots, solveDense;

/// What the user is dragging, if anything.
///
/// The grip is stored in the body's OWN coordinates, so it keeps naming the
/// same physical point on the component however far the solve turns it.
class AsmDrag {
  const AsmDrag(this.occurrence, this.gripLocal, this.target);

  final String occurrence;
  final Vec3 gripLocal;

  /// Where the finger wants that point, in world coordinates.
  final Vec3 target;
}

/// What a solve found out.
class AsmSolveReport {
  const AsmSolveReport({
    required this.converged,
    required this.residual,
    required this.iterations,
    required this.dof,
    required this.fullyConstrained,
    required this.sick,
    required this.moved,
  });

  /// True when every active constraint is satisfied to tolerance.
  final bool converged;

  /// The largest single constraint residual left, in millimetre-equivalents
  /// (angular residuals are scaled — see [kAngularScale]).
  final double residual;

  final int iterations;

  /// Degrees of freedom left in the whole assembly: 6 per free body, minus
  /// the rank of the constraint Jacobian. This is the number Inventor puts
  /// behind its under-constrained reporting, and it is exact — the rank comes
  /// from row-reducing the real Jacobian, not from counting constraints.
  final int dof;

  /// Occurrences with no freedom left. Computed properly: a body is fully
  /// constrained exactly when its six columns are independent of every other
  /// column, so no null-space direction can move it.
  final Set<String> fullyConstrained;

  /// Constraint name -> reason key, for the ones that could not be met.
  final Map<String, String> sick;

  /// Occurrence ids the solve actually moved.
  final Set<String> moved;

  bool get hasSick => sick.isNotEmpty;

  static const empty = AsmSolveReport(
    converged: true,
    residual: 0,
    iterations: 0,
    dof: 0,
    fullyConstrained: <String>{},
    sick: <String, String>{},
    moved: <String>{},
  );
}

/// Millimetres per radian, for putting angular and positional residuals on one
/// scale.
///
/// Without this a 1 mm gap and a 1 radian twist weigh the same, and the solver
/// spends its effort closing gaps while leaving faces visibly askew. 50 mm is
/// about the size of the parts this app makes, so one degree of misalignment
/// costs roughly the same as a millimetre of gap — which is the trade a person
/// looking at the screen would make.
const double kAngularScale = 50.0;

/// How hard the solve resists moving anything.
///
/// Small, but not zero: with several bodies free, the constraints alone leave
/// a null space, and without a preference the solver is entitled to slide the
/// whole assembly along it. Penalising the increment picks the MINIMUM-MOTION
/// answer out of that space, which is what makes adding a mate move the one
/// component you expect and dragging a linkage look like a mechanism rather
/// than an explosion.
const double kMinimumMotionWeight = 2e-3;

/// How hard the drag pulls, relative to a constraint.
///
/// A drag is a WISH, never a command — the 2D solver's own words. Weighting it
/// well below a constraint is what makes a mechanism follow the finger only as
/// far as its freedom allows, and stop dead where it does not.
const double kDragWeight = 0.05;

/// Whether the solver may MOVE [o].
///
/// Two reasons it may not, and they are the same reason twice: something other
/// than the solver already decides where this body is.
///
///   * GROUNDED is Inventor's, and M240's — the assembly needs something to
///     be built against.
///   * M248 — a PATTERN ELEMENT is a function of its seed's placement and the
///     pattern's parameters. Letting the solve pull one off its grid would be
///     two authorities writing one placement: the solver moving it, the next
///     regeneration snapping it back. So it behaves exactly as a grounded
///     component does — other things may be constrained TO it, and it never
///     moves to satisfy them.
///
/// Consequently a pattern element has no degrees of freedom, which is what the
/// browser reports and what Inventor shows for one too.
bool asmBodyIsFree(AssemblyOccurrence o) =>
    !o.grounded && !o.isPatternElement;

/// One body's state during a solve.
class _Body {
  _Body(this.occ, this.free, this.col) : t = occ.offset, r = occ.rot;
  final AssemblyOccurrence occ;
  final bool free;

  /// Index of this body's first of six columns, or -1 when it cannot move.
  final int col;
  Vec3 t;
  Quat r;
}

/// Solves [a]'s constraints, moving its components.
///
/// Grounded occurrences never move. Everything else is free, INCLUDING
/// components no constraint touches — they contribute their six degrees of
/// freedom to [AsmSolveReport.dof], which is the honest answer to "how
/// constrained is this assembly".
AsmSolveReport solveAssembly(
  AssemblyModel a, {
  AsmDrag? drag,
  int maxIterations = 60,
  double tolerance = 1e-6,
}) {
  final active = [
    for (final c in a.constraints)
      if (!c.suppressed && c.isPositional) c
  ];
  // Nothing to solve is not nothing to REPORT: an assembly of loose parts has
  // six degrees of freedom each, and the browser should say so.
  final bodies = <String, _Body>{};
  var cols = 0;
  for (final o in a.occurrences) {
    final free = asmBodyIsFree(o);
    bodies[o.id] = _Body(o, free, free ? cols : -1);
    if (free) cols += 6;
  }
  if (cols == 0 || (active.isEmpty && drag == null)) {
    // Nothing can move — but that is not the same as nothing being wrong. A
    // constraint between two GROUNDED components is exactly this case, and it
    // is the one failure a user can act on directly, so it has to be reported
    // rather than silently declared converged.
    final sick = <String, String>{};
    for (final c in active) {
      final res = <double>[];
      _StaticCtx(a).constraintResiduals(c, res);
      if (_maxAbs(res) > 1e-4) sick[c.name] = _sickReason(c, a);
    }
    for (final c in a.constraints) {
      c.error = sick[c.name];
    }
    return AsmSolveReport(
      converged: sick.isEmpty,
      residual: 0,
      iterations: 0,
      dof: cols,
      fullyConstrained: {
        for (final o in a.occurrences)
          if (!asmBodyIsFree(o)) o.id
      },
      sick: sick,
      moved: const {},
    );
  }

  // Transitional picks WHICH face of the target body it rides once per solve,
  // not once per residual evaluation: switching faces mid-Jacobian would make
  // the derivative meaningless. See _chooseTransitionalFaces.
  final rides = _chooseTransitionalFaces(a, active, bodies);

  final ctx = _Ctx(bodies, active, rides, drag, cols);
  var iterations = _runLm(ctx, cols, maxIterations, tolerance);

  // THE POLISH PASS. A drag is a soft pull, so at the optimum it leaves the
  // constraints slightly bent — the balance point between "the finger wants
  // 25 mm" and "the mate wants zero" is a fraction of a millimetre off zero,
  // every time. Visually nothing, but it means a mate is never exactly met
  // while a drag is live, which would report every dragged component's
  // constraints as SICK and let a fully constrained part creep under the
  // finger.
  //
  // So the drag gets its say, and then the constraints get the last word: a
  // second pass with the pull removed, from wherever the first pass arrived.
  // The minimum-motion term is what keeps that from undoing the drag — it
  // settles onto the constraint manifold at the nearest point, which is the
  // one the finger asked for.
  if (drag != null) {
    iterations += _runLm(ctx.withoutDrag(), cols, maxIterations, tolerance);
  }

  // Write the solved state back to the document.
  final moved = <String>{};
  for (final b in bodies.values) {
    if (!b.free) continue;
    if ((b.t - b.occ.offset).length > 1e-9 ||
        (b.r * b.occ.rot.conjugate).angle > 1e-9) {
      moved.add(b.occ.id);
    }
    b.occ.offset = b.t;
    b.occ.rot = b.r.normalized();
  }

  // ---- health, per constraint --------------------------------------------
  final sick = <String, String>{};
  final zero = List<double>.filled(cols, 0.0);
  for (final c in active) {
    final res = <double>[];
    ctx.constraintResiduals(c, zero, res);
    if (_maxAbs(res) > math.max(tolerance, 1e-4)) {
      sick[c.name] = _sickReason(c, a);
    }
  }
  // A suppressed constraint is not sick, it is switched off; and one whose
  // component has gone IS sick and would never have produced a residual.
  for (final c in a.constraints) {
    if (c.suppressed) continue;
    if (!c.isPositional) continue;
    for (final id in c.occurrences) {
      if (!bodies.containsKey(id)) sick[c.name] = 'missingComponent';
    }
  }
  for (final c in a.constraints) {
    c.error = sick[c.name];
  }

  // ---- degrees of freedom -------------------------------------------------
  final (dof, fully) = _analyseFreedom(ctx, bodies, cols);

  return AsmSolveReport(
    converged: sick.isEmpty,
    residual: _maxAbs(ctx.residuals(List<double>.filled(cols, 0.0))),
    iterations: iterations,
    dof: dof,
    fullyConstrained: fully,
    sick: sick,
    moved: moved,
  );
}

/// One Levenberg-Marquardt run over [ctx], baking every accepted step into the
/// bodies. Returns how many iterations it took.
int _runLm(_Ctx ctx, int cols, int maxIterations, double tolerance) {
  final x = List<double>.filled(cols, 0.0);
  var lambda = 1e-3;
  var iterations = 0;
  for (var iter = 0; iter < maxIterations; iter++) {
    iterations = iter + 1;
    final r = ctx.residuals(x);
    if (_maxAbs(r) < tolerance) break;
    final before = _norm(r);
    final j = ctx.jacobian(x, r);
    // Normal equations with Levenberg damping on the diagonal.
    final ata = List.generate(cols, (_) => List<double>.filled(cols, 0.0));
    final atb = List<double>.filled(cols, 0.0);
    for (var row = 0; row < r.length; row++) {
      final jr = j[row];
      for (var p = 0; p < cols; p++) {
        final v = jr[p];
        if (v == 0) continue;
        atb[p] -= v * r[row];
        for (var q = p; q < cols; q++) {
          ata[p][q] += v * jr[q];
        }
      }
    }
    for (var p = 0; p < cols; p++) {
      for (var q = 0; q < p; q++) {
        ata[p][q] = ata[q][p];
      }
      ata[p][p] += lambda * (1 + ata[p][p]);
    }
    final dx = solveDense(ata, atb, cols);
    if (dx == null) {
      lambda *= 8;
      if (lambda > 1e9) break;
      continue;
    }
    final trial = [for (var i = 0; i < cols; i++) x[i] + dx[i]];
    if (_norm(ctx.residuals(trial)) < before) {
      // BAKE: fold the accepted increment into the bodies and start the next
      // linearisation from there. This is what keeps the rotation increment
      // small and the quaternion exactly unit — and it is why the comparison
      // above is against THIS iteration's residual rather than a running best:
      // the minimum-motion rows are measured from wherever the last bake left
      // things, so a norm from before a bake is not comparable with one after.
      ctx.bake(trial);
      for (var i = 0; i < cols; i++) {
        x[i] = 0;
      }
      lambda = math.max(1e-9, lambda / 3);
    } else {
      lambda *= 4;
      if (lambda > 1e9) break;
    }
  }
  return iterations;
}

/// Constraint residuals at an assembly's CURRENT state, with nothing free to
/// move. Used for the one case the solve short-circuits: every component
/// grounded, where there is still a right answer to "is this constraint met".
class _StaticCtx {
  _StaticCtx(this.model);
  final AssemblyModel model;

  void constraintResiduals(AsmConstraint c, List<double> out) {
    final ctx = _Ctx(
      {
        for (final o in model.occurrences) o.id: _Body(o, false, -1),
      },
      const [],
      const {},
      null,
      0,
    );
    ctx.constraintResiduals(c, const [], out);
  }
}

String _sickReason(AsmConstraint c, AssemblyModel a) {
  // Both ends pinned is the one failure a user can act on directly, and the
  // one the solver could never fix: nothing was free to move.
  final free = c.occurrences.where((id) {
    final o = a.byId(id);
    return o != null && asmBodyIsFree(o);
  });
  if (free.isEmpty) return 'bothGrounded';
  return 'cannotSatisfy';
}

/// Total DOF, and which bodies have none left.
///
/// The rank of the constraint Jacobian is how many independent freedoms the
/// constraints removed, so 6*bodies - rank is what is left. A body is fully
/// constrained exactly when adding its six columns raises the rank by six —
/// which means no null-space vector has any component in them, i.e. nothing
/// can move it.
(int, Set<String>) _analyseFreedom(
    _Ctx ctx, Map<String, _Body> bodies, int cols) {
  final zero = List<double>.filled(cols, 0.0);
  final rows = ctx.constraintJacobian(zero);
  if (rows.isEmpty) {
    return (cols, {
      for (final b in bodies.values)
        if (!b.free) b.occ.id
    });
  }
  final full = rankAndPivots(_copy(rows), rows.length, cols).$1;
  final fully = <String>{
    for (final b in bodies.values)
      if (!b.free) b.occ.id
  };
  for (final b in bodies.values) {
    if (!b.free) continue;
    // The same Jacobian with this body's six columns zeroed out.
    final without = _copy(rows);
    for (final row in without) {
      for (var k = 0; k < 6; k++) {
        row[b.col + k] = 0;
      }
    }
    final r2 = rankAndPivots(without, without.length, cols).$1;
    if (full - r2 >= 6) fully.add(b.occ.id);
  }
  return (cols - full, fully);
}

List<List<double>> _copy(List<List<double>> m) =>
    [for (final r in m) List<double>.of(r)];

// ---------------------------------------------------------------------------
// residual assembly
// ---------------------------------------------------------------------------
class _Ctx {
  _Ctx(this.bodies, this.constraints, this.rides, this.drag, this.cols);

  final Map<String, _Body> bodies;
  final List<AsmConstraint> constraints;

  /// Transitional constraint name -> the face of the target body it is riding
  /// for the duration of this solve, in that body's local coordinates.
  final Map<String, AsmGeom> rides;
  final AsmDrag? drag;
  final int cols;

  /// The same solve with the finger lifted — see the polish pass.
  _Ctx withoutDrag() => _Ctx(bodies, constraints, rides, null, cols);

  /// The body's pose with [x]'s increment applied, without baking it.
  ///
  /// M248 — a [Placement], because a MIRRORED component's pose is not a rigid
  /// transform. The six columns are unchanged: a mirrored body still has six
  /// degrees of freedom, and the reflection is a fixed property of the
  /// occurrence that the increment never touches. What it does change is the
  /// GEOMETRY the residuals see — a mirrored face's normal and a mirrored
  /// hole's axis come through reflected, which is what makes a mate to a
  /// mirrored bracket mean the face you are looking at.
  Placement _pose(_Body b, List<double> x) {
    if (!b.free || b.col < 0) return Placement(b.r, b.t, b.occ.reflect);
    final dt = Vec3(x[b.col], x[b.col + 1], x[b.col + 2]);
    final dw = Vec3(x[b.col + 3], x[b.col + 4], x[b.col + 5]);
    final ang = dw.length;
    final rr = ang < 1e-15 ? b.r : (Quat.axisAngle(dw, ang) * b.r);
    return Placement(rr, b.t + dt, b.occ.reflect);
  }

  void bake(List<double> x) {
    for (final b in bodies.values) {
      final p = _pose(b, x);
      b.r = p.rot.normalized();
      b.t = p.at;
    }
  }

  /// A reference's geometry in WORLD coordinates under [x].
  AsmGeom world(AsmRef ref, List<double> x) {
    if (ref.isAssemblyOrigin) return ref.geom;
    final b = bodies[ref.occurrence];
    if (b == null) return ref.geom;
    final p = _pose(b, x);
    return AsmGeom(
      ref.geom.kind,
      p.apply(ref.geom.at),
      p.applyDir(ref.geom.dir),
      radius: ref.geom.radius,
    );
  }

  List<double> residuals(List<double> x) {
    final out = <double>[];
    for (final c in constraints) {
      constraintResiduals(c, x, out);
    }
    // The drag: a soft pull on one point of one body.
    final d = drag;
    if (d != null) {
      final b = bodies[d.occurrence];
      if (b != null && b.free) {
        final p = _pose(b, x).apply(d.gripLocal);
        out.add((p.x - d.target.x) * kDragWeight);
        out.add((p.y - d.target.y) * kDragWeight);
        out.add((p.z - d.target.z) * kDragWeight);
      }
    }
    // Minimum motion.
    for (var i = 0; i < cols; i++) {
      // Rotation columns are scaled like the angular residuals, so the
      // preference is "turn as little as you translate", not "translate
      // freely and never turn".
      final s = (i % 6) >= 3 ? kAngularScale : 1.0;
      out.add(x[i] * s * kMinimumMotionWeight);
    }
    return out;
  }

  /// Only the CONSTRAINT rows — no drag, no minimum-motion. This is what the
  /// degrees-of-freedom count has to be taken from: the drag is a wish and the
  /// motion penalty is a preference, and neither removes any freedom.
  List<List<double>> constraintJacobian(List<double> x) {
    final base = <double>[];
    for (final c in constraints) {
      constraintResiduals(c, x, base);
    }
    if (base.isEmpty) return const [];
    final j = List.generate(base.length, (_) => List<double>.filled(cols, 0.0));
    final t = List<double>.of(x);
    for (var k = 0; k < cols; k++) {
      const h = 1e-7;
      t[k] = x[k] + h;
      final r2 = <double>[];
      for (final c in constraints) {
        constraintResiduals(c, t, r2);
      }
      t[k] = x[k];
      for (var i = 0; i < base.length; i++) {
        j[i][k] = (r2[i] - base[i]) / h;
      }
    }
    return j;
  }

  List<List<double>> jacobian(List<double> x, List<double> base) {
    final j = List.generate(base.length, (_) => List<double>.filled(cols, 0.0));
    final t = List<double>.of(x);
    for (var k = 0; k < cols; k++) {
      const h = 1e-7;
      t[k] = x[k] + h;
      final r2 = residuals(t);
      t[k] = x[k];
      for (var i = 0; i < base.length && i < r2.length; i++) {
        j[i][k] = (r2[i] - base[i]) / h;
      }
    }
    return j;
  }

  /// Appends [c]'s residuals to [out]. Every angular residual is multiplied by
  /// [kAngularScale] so the whole vector is in millimetre-equivalents.
  void constraintResiduals(
      AsmConstraint c, List<double> x, List<double> out) {
    final ga = world(c.a, x);
    final gb = world(c.b, x);
    switch (c.kind) {
      case AsmKind.mate:
        _mate(ga, gb, c.solution == AsmSolution.mate, c.value, out);
      case AsmKind.angle:
        _angle(c, ga, gb, x, out);
      case AsmKind.tangent:
        _tangent(ga, gb, c.solution == AsmSolution.outside, c.value, out);
      case AsmKind.insert:
        _insert(ga, gb, c.solution == AsmSolution.opposed, c.value, out);
      case AsmKind.symmetry:
        _symmetry(c, ga, gb, x, out);
      case AsmKind.transitional:
        _transitional(c, ga, x, out);
      case AsmKind.rotation:
      case AsmKind.rotationTranslation:
        break; // driven, never solved — see the file header
    }
  }

  // -- Mate / Flush ---------------------------------------------------------
  //
  // Mate puts the two selections face to face, Flush side by side with their
  // normals the same way. Which equations that means depends on what was
  // picked, and Inventor accepts any pair of plane / axis / point.
  void _mate(AsmGeom a, AsmGeom b, bool opposed, double offset,
      List<double> out) {
    final s = opposed ? -1.0 : 1.0;
    if (a.isPlane && b.isPlane) {
      _dirEquals(b.dir, a.dir * s, out);
      out.add((b.at - a.at).dot(a.dir.normalized()) - offset);
      return;
    }
    if (a.isAxis && b.isAxis) {
      _dirEquals(b.dir, a.dir * s, out);
      // Collinear: the perpendicular part of the separation is zero. The
      // offset is deliberately NOT applied — "how far apart along a shared
      // line" names no unique position, and Inventor's own offset for two
      // axes is the degenerate case nobody uses.
      _perpZero(b.at - a.at, a.dir, out);
      return;
    }
    if (a.isPoint && b.isPoint) {
      final d = b.at - a.at;
      out..add(d.x)..add(d.y)..add(d.z);
      return;
    }
    // plane + point (either way round): the point sits at `offset` from the
    // plane, measured along its normal.
    if (a.isPlane && b.isPoint) {
      out.add((b.at - a.at).dot(a.dir.normalized()) - offset);
      return;
    }
    if (a.isPoint && b.isPlane) {
      out.add((a.at - b.at).dot(b.dir.normalized()) - offset);
      return;
    }
    // plane + axis: the axis lies parallel to the plane, `offset` away.
    if (a.isPlane && b.isAxis) {
      out.add(b.dir.normalized().dot(a.dir.normalized()) * kAngularScale);
      out.add((b.at - a.at).dot(a.dir.normalized()) - offset);
      return;
    }
    if (a.isAxis && b.isPlane) {
      out.add(a.dir.normalized().dot(b.dir.normalized()) * kAngularScale);
      out.add((a.at - b.at).dot(b.dir.normalized()) - offset);
      return;
    }
    // axis + point: the point lies ON the axis.
    if (a.isAxis && b.isPoint) {
      _perpZero(b.at - a.at, a.dir, out);
      return;
    }
    if (a.isPoint && b.isAxis) {
      _perpZero(a.at - b.at, b.dir, out);
    }
  }

  // -- Angle ----------------------------------------------------------------
  void _angle(AsmConstraint c, AsmGeom a, AsmGeom b, List<double> x,
      List<double> out) {
    final u = a.dir.normalized(), v = b.dir.normalized();
    if (u.length < 0.5 || v.length < 0.5) return;
    final want = c.value * math.pi / 180;
    if (c.solution == AsmSolution.undirectedAngle) {
      // Unsigned: only the magnitude of the angle is fixed, so the part may
      // arrive from either side. One equation, and no reference needed.
      out.add((u.dot(v) - math.cos(want)) * kAngularScale);
      return;
    }
    // Directed and Explicit Reference Vector are the same equation; they
    // differ only in where the reference axis comes from. Directed captured
    // one when the constraint was made (see AppState.createConstraint), the
    // explicit solution takes the user's third pick.
    final ref = c.c == null ? u.cross(v) : world(c.c!, x).dir;
    var z = ref.normalized();
    if (z.length < 0.5) {
      out.add((u.dot(v) - math.cos(want)) * kAngularScale);
      return;
    }
    final signed = math.atan2(u.cross(v).dot(z), u.dot(v));
    var e = signed - want;
    // Wrap into (-pi, pi]: 359 degrees and -1 degree are the same place, and
    // without this the solver would take the long way round to get there.
    while (e > math.pi) {
      e -= 2 * math.pi;
    }
    while (e < -math.pi) {
      e += 2 * math.pi;
    }
    out.add(e * kAngularScale);
  }

  // -- Tangent --------------------------------------------------------------
  void _tangent(
      AsmGeom a, AsmGeom b, bool outside, double offset, List<double> out) {
    final s = outside ? 1.0 : -1.0;
    // cylinder against a plane, either way round.
    final (cyl, pl) = a.isCylinder && b.isPlane
        ? (a, b)
        : (b.isCylinder && a.isPlane ? (b, a) : (null, null));
    if (cyl != null && pl != null) {
      final n = pl.dir.normalized();
      // The axis runs parallel to the plane...
      out.add(cyl.dir.normalized().dot(n) * kAngularScale);
      // ...at exactly its own radius from it.
      out.add((cyl.at - pl.at).dot(n) - s * (cyl.radius + offset));
      return;
    }
    if (a.isCylinder && b.isCylinder) {
      // Parallel axes, centres apart by the sum (outside) or the difference
      // (inside) of the radii.
      _dirParallel(a.dir, b.dir, out);
      final want = outside
          ? a.radius + b.radius + offset
          : (a.radius - b.radius).abs() + offset;
      final perp = _perpComponent(b.at - a.at, a.dir);
      out.add(perp.length - want);
    }
  }

  // -- Insert ---------------------------------------------------------------
  //
  // A bolt in a hole: the two axes become one line and the two circular edges
  // sit `offset` apart along it. Opposed points the parts at each other, which
  // is the case that puts a bolt head down on a face.
  void _insert(
      AsmGeom a, AsmGeom b, bool opposed, double offset, List<double> out) {
    if (!a.isAxis || !b.isAxis) return;
    final s = opposed ? -1.0 : 1.0;
    _dirEquals(b.dir, a.dir * s, out);
    _perpZero(b.at - a.at, a.dir, out);
    out.add((b.at - a.at).dot(a.dir.normalized()) - offset);
  }

  // -- Symmetry -------------------------------------------------------------
  void _symmetry(AsmConstraint c, AsmGeom a, AsmGeom b, List<double> x,
      List<double> out) {
    final plane = c.c == null ? null : world(c.c!, x);
    if (plane == null || !plane.isPlane) return;
    final n = plane.dir.normalized();
    if (n.length < 0.5) return;
    final mirroredAt = a.at - n * (2 * (a.at - plane.at).dot(n));
    final d = b.at - mirroredAt;
    out..add(d.x)..add(d.y)..add(d.z);
    if (a.dir.length > 1e-9 && b.dir.length > 1e-9) {
      final md = a.dir.normalized() - n * (2 * a.dir.normalized().dot(n));
      // The asymmetric solution is the same mirror with the sense flipped —
      // the pair that faces the same way rather than towards each other.
      final s = c.solution == AsmSolution.asymmetric ? -1.0 : 1.0;
      _dirEquals(b.dir, md * s, out);
    }
  }

  // -- Transitional ---------------------------------------------------------
  //
  // The moving face stays tangent to whichever face of the other part it is
  // currently riding. [rides] chose that face once for this whole solve; the
  // sliding from one face to the next happens BETWEEN solves, which is what
  // makes a cam follower follow instead of jittering between two answers
  // inside one Jacobian.
  void _transitional(AsmConstraint c, AsmGeom a, List<double> x,
      List<double> out) {
    final ride = rides[c.name];
    if (ride == null) return;
    final b = bodies[c.b.occurrence];
    final face = b == null
        ? ride
        : () {
            final p = _pose(b, x);
            return AsmGeom(ride.kind, p.apply(ride.at), p.applyDir(ride.dir),
                radius: ride.radius);
          }();
    // Only the DISTANCE equation: the follower must stay in contact and is
    // free to slide and turn, which is the whole difference between this and
    // a tangent constraint.
    if (a.isCylinder && face.isPlane) {
      final n = face.dir.normalized();
      out.add((a.at - face.at).dot(n) - a.radius);
    } else if (a.isPlane && face.isCylinder) {
      final n = a.dir.normalized();
      out.add((face.at - a.at).dot(n) - face.radius);
    } else if (a.isPlane && face.isPlane) {
      out.add((face.at - a.at).dot(a.dir.normalized()));
    } else if (a.isCylinder && face.isCylinder) {
      out.add(_perpComponent(face.at - a.at, a.dir).length -
          (a.radius + face.radius));
    }
  }

  // -- residual helpers -----------------------------------------------------

  /// Three equations saying unit vector [have] equals unit vector [want].
  /// Rank two, which is correct — a direction has two degrees of freedom.
  void _dirEquals(Vec3 have, Vec3 want, List<double> out) {
    final h = have.normalized(), w = want.normalized();
    out
      ..add((h.x - w.x) * kAngularScale)
      ..add((h.y - w.y) * kAngularScale)
      ..add((h.z - w.z) * kAngularScale);
  }

  /// Parallel OR antiparallel — the cross product, which does not care about
  /// the sense. What tangency between two cylinders needs.
  void _dirParallel(Vec3 a, Vec3 b, List<double> out) {
    final c = a.normalized().cross(b.normalized());
    out
      ..add(c.x * kAngularScale)
      ..add(c.y * kAngularScale)
      ..add(c.z * kAngularScale);
  }

  /// The part of [v] perpendicular to [axis] must vanish — i.e. [v] lies
  /// along the axis.
  void _perpZero(Vec3 v, Vec3 axis, List<double> out) {
    final p = _perpComponent(v, axis);
    out..add(p.x)..add(p.y)..add(p.z);
  }

  static Vec3 _perpComponent(Vec3 v, Vec3 axis) {
    final d = axis.normalized();
    if (d.length < 0.5) return v;
    return v - d * v.dot(d);
  }
}

// ---------------------------------------------------------------------------
// Transitional: which face is being ridden
// ---------------------------------------------------------------------------

/// For every transitional constraint, the face of the target body whose
/// tangency is closest to being satisfied right now.
///
/// This is what makes a cam follower a cam follower: the constraint names one
/// face when it is created, and then rides whichever face of that body it has
/// slid onto. Chosen once per solve — see [_Ctx._transitional].
Map<String, AsmGeom> _chooseTransitionalFaces(
  AssemblyModel a,
  List<AsmConstraint> active,
  Map<String, _Body> bodies,
) {
  final out = <String, AsmGeom>{};
  for (final c in active) {
    if (c.kind != AsmKind.transitional) continue;
    final target = a.byId(c.b.occurrence);
    final mover = bodies[c.a.occurrence];
    if (target == null || mover == null) {
      out[c.name] = c.b.geom;
      continue;
    }
    final movingPlace = Placement(mover.r, mover.t, mover.occ.reflect);
    final movingWorld = AsmGeom(
      c.a.geom.kind,
      movingPlace.apply(c.a.geom.at),
      movingPlace.applyDir(c.a.geom.dir),
      radius: c.a.geom.radius,
    );
    AsmGeom bestLocal = c.b.geom;
    var bestErr = double.infinity;
    for (final f in localFacesOf(target)) {
      final w = AsmGeom(f.kind, target.toWorld(f.at), target.dirToWorld(f.dir),
          radius: f.radius);
      final e = _contactError(movingWorld, w);
      if (e < bestErr) {
        bestErr = e;
        bestLocal = f;
      }
    }
    out[c.name] = bestLocal;
  }
  return out;
}

double _contactError(AsmGeom moving, AsmGeom face) {
  if (moving.isCylinder && face.isPlane) {
    final n = face.dir.normalized();
    return ((moving.at - face.at).dot(n) - moving.radius).abs();
  }
  if (moving.isPlane && face.isCylinder) {
    final n = moving.dir.normalized();
    return ((face.at - moving.at).dot(n) - face.radius).abs();
  }
  if (moving.isPlane && face.isPlane) {
    return (face.at - moving.at).dot(moving.dir.normalized()).abs();
  }
  if (moving.isCylinder && face.isCylinder) {
    final d = face.at - moving.at;
    final ax = moving.dir.normalized();
    final perp = d - ax * d.dot(ax);
    return (perp.length - (moving.radius + face.radius)).abs();
  }
  return double.infinity;
}

/// Every planar and cylindrical face of [o]'s solids, in the source part's own
/// coordinates, read straight off the kernel's per-face surface records.
///
/// This is the only place in the assembly layer that opens a mesh. Everything
/// else works on [AsmGeom]s that a pick already reduced.
List<AsmGeom> localFacesOf(AssemblyOccurrence o) {
  final out = <AsmGeom>[];
  for (final (_, at, s) in o.localSolids) {
    // M246 — a subassembly's parts sit inside it, so a face record has to be
    // lifted by the piece's own transform before it means anything in the
    // component's frame. Identity for a part.
    //
    // M248 — and that transform can now be a REFLECTION (a mirrored
    // subassembly). A face record's normal is stored rather than derived from
    // the winding, so applyDir carries it correctly; nothing else here
    // changes.
    Vec3 up(Vec3 v) => at.apply(v);
    Vec3 upDir(Vec3 v) => at.applyDir(v);
    final info = s.mesh.faceInfos;
    final n = info.length ~/ 15;
    for (var f = 0; f < n; f++) {
      final base = f * 15;
      final type = info[base].round();
      final at = Vec3(info[base + 1], info[base + 2], info[base + 3]);
      final dir = Vec3(info[base + 4], info[base + 5], info[base + 6]);
      if (type == kFacePlane) {
        out.add(AsmGeom.plane(up(at), upDir(dir)));
      } else if (type == kFaceCylinder) {
        out.add(AsmGeom.axis(up(at), upDir(dir), radius: info[base + 10]));
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Motion — the drive pass
// ---------------------------------------------------------------------------

/// Applies the motion constraints that [mover] drives, given how far it just
/// turned.
///
/// Motion constraints are NOT solved (see the file header): Autodesk's own
/// documentation says they act only on open degrees of freedom and cannot
/// conflict with assembly constraints. So this runs BEFORE the solve and
/// proposes where the driven bodies should go; the solve then honours the real
/// constraints over that proposal, which is exactly the precedence Inventor
/// describes.
///
/// [turnedRadians] is the rotation the mover just underwent about the axis the
/// constraint names. Returns the occurrences it proposed a move for.
Set<String> driveMotion(
  AssemblyModel a,
  String moverId,
  double turnedRadians,
) {
  final touched = <String>{};
  if (turnedRadians.abs() < 1e-12) return touched;
  for (final c in a.constraints) {
    if (c.suppressed || c.isPositional) continue;
    // Only constraints this body drives, and only onto a body that can move.
    final drivenId = c.a.occurrence == moverId
        ? c.b.occurrence
        : (c.b.occurrence == moverId ? c.a.occurrence : null);
    if (drivenId == null) continue;
    final driven = a.byId(drivenId);
    if (driven == null || !asmBodyIsFree(driven)) continue;
    final drivenRef = c.a.occurrence == moverId ? c.b : c.a;
    final axisLocal = drivenRef.geom.dir;
    if (axisLocal.length < 1e-9) continue;
    final axisWorld = driven.dirToWorld(axisLocal).normalized();
    final sign = c.solution == AsmSolution.reverse ? 1.0 : -1.0;

    if (c.kind == AsmKind.rotation) {
      // A gear pair: the ratio is how many turns of the driven body one turn
      // of the driver makes. Inventor's default of 1 is a pair of equal gears.
      final ratio = c.value == 0 ? 1.0 : c.value;
      final delta = turnedRadians * ratio * sign;
      final pivot = driven.toWorld(drivenRef.geom.at);
      _turnAbout(driven, axisWorld, pivot, delta);
      touched.add(drivenId);
    } else if (c.kind == AsmKind.rotationTranslation) {
      // A rack and pinion: `value` is how far the rack travels per FULL turn
      // of the pinion, which is Autodesk's own wording for the field.
      final perTurn = c.value;
      driven.offset =
          driven.offset + axisWorld * (turnedRadians / (2 * math.pi) * perTurn * sign);
      touched.add(drivenId);
    }
  }
  return touched;
}

/// Turns [o] by [angle] about the world axis [axis] through [pivot].
void _turnAbout(AssemblyOccurrence o, Vec3 axis, Vec3 pivot, double angle) {
  final q = Quat.axisAngle(axis, angle);
  o.rot = (q * o.rot).normalized();
  o.offset = pivot + q.rotate(o.offset - pivot);
}

// ---------------------------------------------------------------------------
double _norm(List<double> v) {
  var s = 0.0;
  for (final e in v) {
    s += e * e;
  }
  return math.sqrt(s);
}

double _maxAbs(List<double> v) {
  var m = 0.0;
  for (final e in v) {
    final a = e.abs();
    if (a > m) m = a;
  }
  return m;
}
