// M275 — the ViewCube's geometry, as arithmetic rather than as a widget.
//
// Inventor's ViewCube is a 26-way control: six faces, twelve edges, eight
// corners, each snapping the camera to its own direction. That is not a lot of
// code, but all of it has to agree with itself — the region the pointer is
// over, the region that lights up, and the direction a tap sends the camera
// are three answers to ONE question, and every ViewCube bug this app has had
// came from two of them being worked out in different places.
//
// So the whole of it is here, pure, and the widget only draws what it is told.
//
// ---------------------------------------------------------------------------
// The bug this file was extracted to fix
// ---------------------------------------------------------------------------
//
// The picker built its ray from the LIVE camera — pan, zoom and roll included
// — and then scaled the result to the cube's own half-height. Scaling fixes
// the zoom and does nothing about the PAN: `unprojectOnCamPlane` adds ox/oy in
// world millimetres, so a view panned 50 mm with halfH 27 displaced the hit
// ray by 50 * 0.86 / 27 = 1.6 cube widths. The cube was drawn in one place and
// picked in another, and the further you panned the worse it got. That is the
// "the hover barely works" report, and it is why cubeCamera exists: ONE camera
// for the picture and the pick, built from the orientation alone.
//
// The roll went the other way — the picker applied it, the painter ignored it
// — so a rolled view picked a cube that was not the one on screen. Both use
// the roll now, because a cube that does not roll with the model is lying
// about which way is up.
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'part_model.dart';
import 'part_render.dart';
import 'quat.dart';

/// Where the outer band starts, as a fraction of the half-face.
///
/// A face runs -0.5..0.5 in its own (u, v). Beyond this the pointer is on an
/// EDGE strip or a CORNER piece rather than the face itself, which is what
/// gives the cube its 3x3 look. 0.28 leaves the middle square a little over
/// half the face — Inventor's proportions, and the reason the face is still
/// the easy thing to hit with a finger.
const double kCubeBand = 0.28;

/// The cube's own half-height, in the units its unit cube is drawn in.
const double kCubeHalfH = 0.86;

/// The six faces, in CUBE SPACE. See [CubeHit] for what that means once the
/// user has redefined which way is front.
const List<(String, Vec3)> kCubeFaces = [
  ('RIGHT', Vec3(1, 0, 0)),
  ('LEFT', Vec3(-1, 0, 0)),
  ('TOP', Vec3(0, 1, 0)),
  ('BOTTOM', Vec3(0, -1, 0)),
  ('FRONT', Vec3(0, 0, 1)),
  ('BACK', Vec3(0, 0, -1)),
];

/// A face's two in-plane axes, right-handed with [n].
(Vec3, Vec3) faceBasis(Vec3 n) {
  final up = n.y.abs() > 0.9 ? const Vec3(0, 0, 1) : const Vec3(0, 1, 0);
  final u = up.cross(n).normalized();
  final v = n.cross(u).normalized();
  return (u, v);
}

/// The camera the cube is DRAWN and PICKED with.
///
/// Orientation only: the cube always sits at its own fixed size in its own
/// corner, so the document's zoom and pan have no business in it. Roll IS
/// carried — see the header.
PartCamera cubeCamera(PartCamera c) =>
    PartCamera(az: c.az, pol: c.pol, roll: c.roll, halfH: kCubeHalfH);

/// What the pointer is over.
///
/// [axes] holds one, two or three of the six face normals IN CUBE SPACE: one
/// for a face, two for an edge, three for a corner. It is what the painter
/// needs to light the right cells, and keeping the parts rather than only
/// their sum is the difference between highlighting an edge strip and
/// highlighting two whole faces.
class CubeHit {
  final List<Vec3> axes;

  /// The direction to put the camera in, in WORLD space.
  final Vec3 dir;

  const CubeHit(this.axes, this.dir);

  bool get isFace => axes.length == 1;
  bool get isEdge => axes.length == 2;
  bool get isCorner => axes.length == 3;

  /// The face label when this is a face hit, else null.
  String? get faceLabel {
    if (!isFace) return null;
    for (final (label, n) in kCubeFaces) {
      if (n.dot(axes.first) > 0.9) return label;
    }
    return null;
  }
}

/// What the pointer at [px] is over, or null when it misses the cube.
///
/// [orient] is the document's cube orientation — the rotation taking CUBE
/// space to WORLD space, which is the identity until the user redefines front
/// or top. The ray is brought into cube space, the hit is worked out there
/// against an axis-aligned unit cube (which is the only reason the slab test
/// stays four lines), and only the answer goes back to world.
CubeHit? cubePick(PartCamera c, Offset px, double sizePx,
    {Quat orient = Quat.identity}) {
  final cam = Cam3(cubeCamera(c), Size(sizePx, sizePx));
  final inv = orient.conjugate;
  final o = inv.rotate(cam.unprojectOnCamPlane(px));
  final rd = inv.rotate(cam.dir * -1);
  var tmin = -1e9, tmax = 1e9;
  Vec3 nEnter = Vec3.zero;
  for (final ax in [
    (const Vec3(1, 0, 0), o.x, rd.x),
    (const Vec3(0, 1, 0), o.y, rd.y),
    (const Vec3(0, 0, 1), o.z, rd.z)
  ]) {
    final (n, oc, dc) = ax;
    if (dc.abs() < 1e-9) {
      if (oc.abs() > 0.5) return null;
      continue;
    }
    var t1 = (-0.5 - oc) / dc, t2 = (0.5 - oc) / dc;
    // THE ENTRY NORMAL, AND THE BUG THIS FILE WAS EXTRACTED TO FIX.
    //
    // t1 is where the ray crosses the -0.5 plane and t2 the +0.5 plane, so
    // which of them is the ENTRY depends on the sign of dc — and the entry's
    // outward normal does too, but it is already written correctly here:
    // travelling along +n you enter through the -n face, and vice versa.
    //
    // The version this replaces flipped `nn` inside the swap below, which
    // corrects a sign that was never wrong and leaves nEnter as the FAR face
    // every time. The consequences were exactly the report: the painter only
    // draws front faces, so a face hit lit NOTHING, and an edge hit lit the
    // neighbour instead of the strip. Swap the parameters, never the normal.
    final nn = n * (dc > 0 ? -1.0 : 1.0);
    if (t1 > t2) {
      final t = t1;
      t1 = t2;
      t2 = t;
    }
    if (t1 > tmin) {
      tmin = t1;
      nEnter = nn;
    }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return null;
  }
  if (nEnter.length < 0.5) return null;
  final hit = o + rd * tmin;
  final (u, v) = faceBasis(nEnter);
  final du = hit.dot(u), dv = hit.dot(v);
  final axes = <Vec3>[nEnter];
  if (du.abs() > kCubeBand) axes.add(u * (du < 0 ? -1.0 : 1.0));
  if (dv.abs() > kCubeBand) axes.add(v * (dv < 0 ? -1.0 : 1.0));
  var sum = Vec3.zero;
  for (final a in axes) {
    sum = sum + a;
  }
  return CubeHit(axes, orient.rotate(sum.normalized()));
}

/// The 3x3 cell of face [n] that [hit] covers, as (cu, cv) in {-1, 0, 1} — or
/// null when this face is not part of the hit at all.
///
/// This is what makes an edge light up as an EDGE. A pick two faces wide is
/// one strip on each of them, not two whole faces, and the strips are found by
/// asking each face which of the hit's other axes lie in its own plane.
(int, int)? cubeCell(CubeHit hit, Vec3 n) {
  var onFace = false;
  for (final a in hit.axes) {
    if (a.dot(n) > 0.9) onFace = true;
  }
  if (!onFace) return null;
  final (u, v) = faceBasis(n);
  var cu = 0, cv = 0;
  for (final a in hit.axes) {
    if (a.dot(n) > 0.9) continue;
    final du = a.dot(u), dv = a.dot(v);
    if (du.abs() > 0.9) cu = du > 0 ? 1 : -1;
    if (dv.abs() > 0.9) cv = dv > 0 ? 1 : -1;
  }
  return (cu, cv);
}

/// The (uMin, uMax, vMin, vMax) of cell [cu], [cv] within a face.
(double, double, double, double) cubeCellRect(int cu, int cv) {
  (double, double) span(int c) => switch (c) {
        -1 => (-0.5, -kCubeBand),
        1 => (kCubeBand, 0.5),
        _ => (-kCubeBand, kCubeBand),
      };
  final (u0, u1) = span(cu);
  final (v0, v1) = span(cv);
  return (u0, u1, v0, v1);
}

// ---------------------------------------------------------------------------
// Redefining which way is front
// ---------------------------------------------------------------------------

/// The cube orientation that makes the CURRENT view [c] the given cube face.
///
/// [cubeNormal] is the face that should end up pointing at the camera and
/// [cubeUp] the cube direction that should end up pointing up the screen. The
/// result is the rotation from cube space to world space, i.e. what every
/// other function here takes as `orient`.
///
/// Built from two [Quat.fromTo]s rather than from a matrix, because the second
/// one is the whole subtlety: aligning the normal alone leaves the cube free
/// to spin about the view direction, and "Set Current View as Front" that
/// leaves the cube rolled at a random angle is worse than not having it.
Quat cubeOrientFor(PartCamera c, Vec3 cubeNormal, Vec3 cubeUp) {
  final d = c.dir.normalized();
  final q1 = Quat.fromTo(cubeNormal, d);
  final upNow = q1.rotate(cubeUp);
  final want = c.up.normalized();
  // Both are perpendicular to d, so the signed angle about d takes one onto
  // the other exactly.
  final ang = math.atan2(d.dot(upNow.cross(want)), upNow.dot(want));
  return (Quat.axisAngle(d, ang) * q1).normalized();
}

/// "Set Current View as Front": the FRONT face turns to the camera, and what
/// is up the screen now stays up.
Quat cubeOrientFront(PartCamera c) =>
    cubeOrientFor(c, const Vec3(0, 0, 1), const Vec3(0, 1, 0));

/// "Set Current View as Top": the TOP face turns to the camera.
///
/// The second axis is -FRONT, not TOP's own up, and that is Inventor's
/// convention rather than an arbitrary pick: looking down at the top of a
/// model, the front of it is at the BOTTOM of the screen. Getting this wrong
/// gives a cube whose FRONT is behind you the moment you leave the top view.
Quat cubeOrientTop(PartCamera c) =>
    cubeOrientFor(c, const Vec3(0, 1, 0), const Vec3(0, 0, -1));
