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
