// M372 — the orthographic camera, which flutter_scene does not ship.
//
// `CameraProjection` is a one-method interface and the package's own
// documentation points at exactly this use: "applications can implement
// [CameraProjection] for orthographic or other projections". So this is the
// intended extension point rather than a way around a limitation.
//
// WHY ORTHOGRAPHIC AT ALL. Every CAD viewport is: two parallel edges of a
// bracket have to stay parallel on screen, a dimension has to measure the same
// at both ends of the part, and a face-on view has to be face-on. The app's
// whole camera model — PartCamera's az / pol / halfH / ox / oy / roll — is
// built on it, the ViewCube reads it, and the CPU painter and RealityKit both
// implement it. This is the third implementation of one camera, and it has to
// agree with the other two to the pixel or the ViewCube lies.
//
// WHAT ORTHOGRAPHIC COSTS in flutter_scene: ambient occlusion, screen-space
// reflections and temporal anti-aliasing are skipped, because their depth and
// normal pre-passes assume a perspective frustum (see Scene.render). None of
// the three is in the shaded viewport's picture — that look is flat lighting
// plus B-Rep edges, and the moment a picture wants ambient occlusion the app
// switches to Cycles, which computes it properly.
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A parallel projection of a box `2*halfWidth` by `2*halfHeight` by
/// `far - near`.
///
/// The half-width is derived from the render target's aspect ratio rather than
/// stored, so a resize changes what is visible horizontally and never the
/// scale — which is what "zoom is halfH" means everywhere else in the app.
class OrthographicProjection extends CameraProjection {
  OrthographicProjection({
    required this.halfHeight,
    required this.near,
    required this.far,
  });

  /// Half the world-space height the viewport shows. `PartCamera.halfH`.
  double halfHeight;

  /// The depth range, and it is worth bracketing TIGHTLY.
  ///
  /// An orthographic depth buffer is LINEAR, so a 0.01…1_000_000 range spreads
  /// its precision over a million millimetres — coarser than the edge ribbons
  /// and the face-highlight lift, which is what makes edges speckle, vanish
  /// when zoomed in, and coplanar surfaces fight. RealityPartView.cameraFit()
  /// brackets it the same way and for the same reason.
  double near;
  double far;

  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) {
    final h = halfHeight <= 0 ? 1.0 : halfHeight;
    final w = h * (aspectRatio <= 0 ? 1.0 : aspectRatio);
    // makeOrthographicMatrix is the standard right-handed GL form; Impeller's
    // clip space matches the one flutter_scene's perspective matrix targets,
    // and a camera built with the same handedness as PerspectiveProjection is
    // the only way the two can ever be swapped for a comparison.
    final m = makeOrthographicMatrix(-w, w, -h, h, near, far);
    if (jitter != null) {
      // Sub-pixel offset in clip space, the same shape the perspective path
      // applies. Unused today — TAA is off under an orthographic camera — but
      // honouring the parameter costs two multiplies and means this projection
      // is not quietly wrong if it is ever used with one.
      m.setEntry(0, 3, m.entry(0, 3) + jitter.x);
      m.setEntry(1, 3, m.entry(1, 3) + jitter.y);
    }
    return m;
  }
}

/// The app's camera, as flutter_scene wants it.
///
/// The BASIS is the part that has to be exact. It is the same construction as
/// `placeCamera` in RealityPartView.swift and `PartCamera.rightFor` in
/// part_model.dart, and the comment there is the reason it is written this way:
///
///   the right vector comes from the AZIMUTH, never from the direction.
///
/// With dir = (sin p · sin a, cos p, sin p · cos a), `fwd × (0,1,0)` is
/// (sin p · cos a, 0, −sin p · sin a), whose normalisation is (cos a, 0, −sin a)
/// for EVERY polar angle, because sin p cancels. No degenerate case at a pole,
/// continuous everywhere — and at a pole the direction alone cannot tell you
/// the azimuth at all, which is what made the sketch-entry swing snap before
/// the three implementations agreed.
class OrthographicCamera extends Camera {
  OrthographicCamera({
    required this.eye,
    required this.target,
    required this.upVector,
    required this.orthographic,
  });

  Vector3 eye;
  Vector3 target;
  Vector3 upVector;
  OrthographicProjection orthographic;

  @override
  Vector3 get position => eye;

  @override
  Vector3 get forward => (target - eye)..normalize();

  @override
  Vector3 get up => upVector;

  @override
  CameraProjection get projection => orthographic;

  @override
  Matrix4 getViewMatrix() => makeViewMatrix(eye, target, upVector);
}

/// The camera basis for one `az` / `pol` / `roll`, in world space.
///
/// Returned rather than applied, because the same three vectors size the
/// camera-facing edge ribbons and lift the coplanar overlays — RealityKit's
/// renderer uses them for exactly those two jobs.
({Vector3 dir, Vector3 right, Vector3 up}) cameraBasis({
  required double az,
  required double pol,
  required double roll,
}) {
  final sp = math.sin(pol), cp = math.cos(pol);
  final sa = math.sin(az), ca = math.cos(az);
  final dir = Vector3(sp * sa, cp, sp * ca);
  var right = Vector3(ca, 0, -sa);
  // fwd = -dir, and up completes a right-handed basis with it.
  var up = right.cross(-dir)..normalize();
  if (roll.abs() > 1e-9) {
    // M80 — roll about the view direction. az/pol pin the basis to world up,
    // which is right while orbiting and wrong for a sketch on a TILTED face:
    // that face's own u/v have to land on screen x/y, and they differ from the
    // derived basis by exactly this angle.
    final c = math.cos(roll), s = math.sin(roll);
    final r0 = right.clone(), u0 = up.clone();
    right = (r0 * c + u0 * s)..normalize();
    up = (u0 * c - r0 * s)..normalize();
  }
  return (dir: dir, right: right, up: up);
}
