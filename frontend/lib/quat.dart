// M242 — unit quaternions, for the one thing the app did not need until now:
// an ORIENTATION that is a value.
//
// Everything 3D in this app so far rotates a vector and forgets: the trackball
// composes a camera basis in place (PartCamera.orbitScreen), a revolve builds
// one 3x4 matrix and hands it to the kernel (PlaneFrame.mat34Rotated). Neither
// needs to STORE a rotation, compose two of them, or interpolate.
//
// An assembly component does. Its placement is a rigid transform that is
// saved to the document, pushed to RealityKit, composed with corrections by
// the constraint solver dozens of times per solve, and re-normalised after all
// that. A 3x3 basis drifts out of orthonormality under repeated composition
// and has to be re-orthogonalised by hand (PartCamera.setBasis does exactly
// that, and says so); a quaternion is four numbers with one invariant, and
// restoring it is a divide.
//
// Deliberately minimal: this is not a maths library, it is the six operations
// the solver and the renderer actually perform.
import 'dart:math' as math;

import 'part_model.dart' show Vec3;

/// A rotation, as a unit quaternion (w + xi + yj + zk).
class Quat {
  final double w, x, y, z;
  const Quat(this.w, this.x, this.y, this.z);

  /// No rotation.
  static const identity = Quat(1, 0, 0, 0);

  /// Rotation of [angle] radians about the (not necessarily unit) axis [axis].
  factory Quat.axisAngle(Vec3 axis, double angle) {
    final n = axis.normalized();
    if (n.length < 0.5) return identity; // a degenerate axis is no rotation
    final h = angle / 2;
    final s = math.sin(h);
    return Quat(math.cos(h), n.x * s, n.y * s, n.z * s);
  }

  /// The SHORTEST rotation taking unit vector [from] onto unit vector [to].
  ///
  /// This is the solver's workhorse: every orientation constraint reduces to
  /// "make this direction point that way", and the shortest such rotation is
  /// the one that disturbs the rest of the component least — which is what
  /// makes an iterative solve settle instead of spinning.
  ///
  /// The ANTIPARALLEL case is the one that has to be written down rather than
  /// discovered: the shortest rotation is then a half turn about ANY axis
  /// perpendicular to the pair, and the cross product that would normally
  /// give the axis is zero. Picking a perpendicular explicitly is the
  /// difference between a mate that flips cleanly and one that produces NaN.
  factory Quat.fromTo(Vec3 from, Vec3 to) {
    final a = from.normalized(), b = to.normalized();
    if (a.length < 0.5 || b.length < 0.5) return identity;
    final d = a.dot(b).clamp(-1.0, 1.0);
    if (d > 1 - 1e-12) return identity; // already there
    if (d < -1 + 1e-12) {
      return Quat.axisAngle(_anyPerpendicular(a), math.pi);
    }
    final c = a.cross(b);
    // The half-angle form: (1 + cos, axis * sin) normalised. Fewer transcendental
    // calls than acos + axisAngle, and better conditioned near d = 1.
    return Quat(1 + d, c.x, c.y, c.z).normalized();
  }

  /// Any unit vector perpendicular to [v]. Cross with whichever world axis
  /// [v] is least aligned with, so the result never collapses.
  static Vec3 _anyPerpendicular(Vec3 v) {
    final ax = v.x.abs(), ay = v.y.abs(), az = v.z.abs();
    final other = (ax <= ay && ax <= az)
        ? const Vec3(1, 0, 0)
        : (ay <= az ? const Vec3(0, 1, 0) : const Vec3(0, 0, 1));
    return v.cross(other).normalized();
  }

  double get lengthSquared => w * w + x * x + y * y + z * z;

  Quat normalized() {
    final l = math.sqrt(lengthSquared);
    if (l < 1e-12) return identity;
    return Quat(w / l, x / l, y / l, z / l);
  }

  /// The inverse rotation. Unit quaternions invert by conjugation, so this is
  /// exact rather than a division — which is why the solver can undo a
  /// correction without accumulating error.
  Quat get conjugate => Quat(w, -x, -y, -z);

  /// [this] then [other]... NO: `a * b` applies b FIRST, then a — the same
  /// order matrices compose in, so `parent * child` reads the way it does
  /// everywhere else in graphics.
  Quat operator *(Quat o) => Quat(
        w * o.w - x * o.x - y * o.y - z * o.z,
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
      );

  /// Rotates [v].
  Vec3 rotate(Vec3 v) {
    // v + 2q_v x (q_v x v + w v) — the standard form, three cross products
    // and no matrix build.
    final qv = Vec3(x, y, z);
    final t = qv.cross(v) * 2;
    return v + t * w + qv.cross(t);
  }

  /// Rotates [v] by the INVERSE. Exact for a unit quaternion.
  Vec3 unrotate(Vec3 v) => conjugate.rotate(v);

  /// The rotation angle in radians, always in [0, pi].
  double get angle => 2 * math.acos(w.abs().clamp(0.0, 1.0));

  /// Spherical-linear interpolation, used to ease a component into place.
  static Quat slerp(Quat a, Quat b, double t) {
    var cos = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    var end = b;
    // Take the SHORT way round: q and -q are the same rotation, so flipping
    // the far one keeps a preview from spinning most of a turn to arrive
    // where it already nearly was.
    if (cos < 0) {
      cos = -cos;
      end = Quat(-b.w, -b.x, -b.y, -b.z);
    }
    if (cos > 1 - 1e-9) {
      return Quat(a.w + (end.w - a.w) * t, a.x + (end.x - a.x) * t,
              a.y + (end.y - a.y) * t, a.z + (end.z - a.z) * t)
          .normalized();
    }
    final theta = math.acos(cos.clamp(-1.0, 1.0));
    final s = math.sin(theta);
    final wa = math.sin((1 - t) * theta) / s, wb = math.sin(t * theta) / s;
    return Quat(a.w * wa + end.w * wb, a.x * wa + end.x * wb,
            a.y * wa + end.y * wb, a.z * wa + end.z * wb)
        .normalized();
  }

  List<double> toJson() => [w, x, y, z];

  static Quat fromJson(Object? j) {
    if (j is! List || j.length < 4) return identity;
    double n(int i) => (j[i] as num?)?.toDouble() ?? 0;
    final q = Quat(n(0), n(1), n(2), n(3));
    return q.lengthSquared < 1e-12 ? identity : q.normalized();
  }

  /// True when this is the identity to within [eps] of angle.
  bool get isIdentity => w.abs() > 1 - 1e-12;

  @override
  String toString() => 'Quat($w, $x, $y, $z)';
}

/// M248 — a placement that MAY REVERSE HANDEDNESS.
///
/// Everything placed in an assembly used to be a (rotation, translation) pair,
/// and every consumer was entitled to assume a proper rotation. Mirror
/// Component breaks that assumption and nothing else does: a reflection has
/// determinant −1, and a quaternion — four numbers on the unit sphere — cannot
/// hold one however it is normalised.
///
/// THE SHAPE, and why this one. The reflection is applied FIRST, in the
/// source's own frame:
///
///     world = rot.rotate(flip(local)) + at
///
/// so [rot] stays a proper rotation, the quaternion algebra, the slerp and the
/// solver's exponential map are untouched, and the sign lives in exactly one
/// place. [reflect] is the unit normal of the reflection plane THROUGH THE
/// SOURCE'S OWN ORIGIN, which is all a handedness flip needs — where the
/// mirror plane sat in the world is already spent, in [at].
///
/// That works out unusually well for the caller that creates one. Mirroring a
/// component across the world plane (p0, n) gives
///
///     rot' = rot          (unchanged!)
///     at'  = reflect_(p0,n)(at)
///     reflect' = rot.unrotate(n)
///
/// because S_n·R = R·S_(Rᵀn) for any rotation R — see AppState.mirrorComponent.
///
/// WINDING, and where it does and does not bite. An orthogonal map carries a
/// stored outward normal correctly — [applyDir] is right for a face record —
/// but it REVERSES TRIANGLE WINDING, so a normal computed as
/// cross(p1−p0, p2−p0) OF THE TRANSFORMED VERTICES points into the solid.
///
/// The emphasis is the whole of it. Every CPU consumer in this tree works in
/// the source's own space against a placed camera (see part_render.placedCam),
/// where the mesh is untouched and the test is unchanged; putting a sign in
/// one of them selects the BACK faces of a mirrored component, which draws
/// with the right silhouette and the wrong shading. That was tried, and only
/// rendering one found it. The path where the trap is real is RealityKit's,
/// because the GPU transforms the vertices before it culls — see
/// reality_payload.solidPayload, which is where the reversal is done.
class Placement {
  const Placement(this.rot, this.at, [this.reflect]);

  static const identity = Placement(Quat.identity, Vec3.zero);

  final Quat rot;
  final Vec3 at;

  /// Unit normal of the reflection plane, in the SOURCE's own frame and
  /// through its own origin. Null for an ordinary rigid placement, which is
  /// every placement in the app except a mirrored component.
  final Vec3? reflect;

  bool get mirrored => reflect != null;

  /// [v] reflected in the source's own frame — the identity when there is no
  /// reflection, and an involution when there is (which is what lets
  /// [unapply] undo [apply] without a second stored normal).
  Vec3 flip(Vec3 v) {
    final m = reflect;
    return m == null ? v : v - m * (2 * v.dot(m));
  }

  /// A point of the source, in the frame this placement places it into.
  Vec3 apply(Vec3 local) => rot.rotate(flip(local)) + at;

  /// A direction of the source. No translation — a direction has no position.
  ///
  /// Correct for a STORED outward normal (a face record's), and correct for a
  /// cross product taken in the SOURCE's own frame: a reflection is
  /// orthogonal, so it maps outward normals to outward normals either way.
  /// What reverses is a cross product of already-transformed vertices — see
  /// the winding note above.
  Vec3 applyDir(Vec3 local) => rot.rotate(flip(local));

  /// The inverse of [apply].
  Vec3 unapply(Vec3 world) => flip(rot.unrotate(world - at));

  /// The inverse of [applyDir].
  Vec3 unapplyDir(Vec3 world) => flip(rot.unrotate(world));

  /// `a * b` applies b FIRST, then a — the order [Quat.operator *] composes
  /// in, and the order matrices do.
  ///
  /// The reflection bookkeeping is the whole reason this is not two lines.
  /// Writing S_m for the reflection with unit normal m,
  ///
  ///     R1·S_m1·R2·S_m2 = R1·R2·S_(R2⁻¹m1)·S_m2
  ///
  /// using S_m·R = R·S_(R⁻¹m). So an outer reflection travels INWARD through
  /// the inner rotation, and two reflections then annihilate into a rotation:
  /// S_a·S_b is the rotation whose quaternion is the pure product a·b. That
  /// last line is what makes mirroring a mirrored subassembly come back
  /// right-handed instead of accumulating a second flag nothing reads.
  Placement operator *(Placement inner) {
    final m1 = reflect, m2 = inner.reflect;
    final at2 = apply(inner.at);
    if (m1 == null) {
      return Placement((rot * inner.rot).normalized(), at2, m2);
    }
    // The outer reflection, expressed in the inner rotation's source frame.
    final a = inner.rot.unrotate(m1).normalized();
    if (m2 == null) {
      return Placement((rot * inner.rot).normalized(), at2, a);
    }
    return Placement(
        (rot * inner.rot * _reflectionPair(a, m2)).normalized(), at2);
  }

  /// M250 — the placement that UNDOES this one.
  ///
  /// EDIT IN PLACE is what needs it, and nothing else does. To draw the rest
  /// of the assembly around the component being edited, every OTHER
  /// component's world placement has to be re-expressed in THIS component's
  /// own frame, which is `edited.placement.inverse * other.placement`. Without
  /// it the surrounding components arrive in world coordinates and the part
  /// viewport — which works in the part's own frame — draws them wherever the
  /// assembly happened to put them, which for a component placed 200 mm along
  /// +X is off the edge of the screen.
  ///
  /// The reflection is the whole reason this is not one line. Writing S_m for
  /// the reflection in unit normal m and R for the rotation, this placement is
  /// v ↦ R·S_m(v) + t, so
  ///
  ///     P⁻¹(w) = S_m(R⁻¹(w − t)) = R⁻¹·S_(R·m)(w − t)
  ///
  /// by the same S_m·R = R·S_(R⁻¹m) identity [operator *] uses, read with R⁻¹
  /// in place of R. So the inverse is an ORDINARY placement: its rotation is
  /// R⁻¹, its reflection normal is m turned out into the world frame, and its
  /// translation is where the world origin lands under those two. A mirrored
  /// component therefore inverts to a mirrored placement rather than to
  /// something no consumer could hold, which is what keeps
  /// `p.inverse * p == identity` true for the mirrored case as well as the
  /// rigid one — see the M250 tests, which assert exactly that.
  Placement get inverse {
    final r = rot.conjugate;
    final m = reflect == null ? null : rot.rotate(reflect!).normalized();
    // applyDir of the inverse, before its translation is known — which is all
    // that is needed to work the translation out.
    final back = Placement(r, Vec3.zero, m);
    return Placement(r, back.applyDir(at) * -1, m);
  }

  /// The rotation that two reflections compose to: S_a·S_b.
  ///
  /// A reflection in the unit normal n is v ↦ n·v·n in the quaternion
  /// algebra, so S_a(S_b(v)) = (ab)·v·(ba) = q·v·q* with q = ab — the pure
  /// quaternion product, which is (−a·b, a×b). Two coincident planes give
  /// (−1, 0) — the identity rotation, since q and −q are the same rotation.
  static Quat _reflectionPair(Vec3 a, Vec3 b) {
    final c = a.cross(b);
    return Quat(-a.dot(b), c.x, c.y, c.z).normalized();
  }

  @override
  String toString() =>
      'Placement($rot, $at${reflect == null ? '' : ', mirror $reflect'})';
}
