// iPadProCAD — shared 3D render helpers (M57).
//
// The orthographic turntable camera math (Cam3) and the shaded-solid painter
// (paintPartSolids) were born inside widgets/viewport3d.dart. They are lifted
// here, verbatim in behaviour, so a SECOND caller can reuse them: the gallery
// needs the very same picture rendered off-screen into a thumbnail PNG
// (AppState._writePartPreview) as the live viewport draws on screen.
//
// This file deliberately depends ONLY on part_model.dart (Vec3, PartCamera,
// KernelSolid) and Flutter painting — never on app_state.dart. viewport3d
// imports app_state, so if this shared code did too the import graph would
// close a cycle. Keeping the ExtrudeSession out of paintPartSolids (the caller
// pre-selects which solids to draw and passes the live preview explicitly) is
// what keeps it app_state-free.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'part_model.dart';

// Steel, same family as partCubeIcon — the committed-solid look.
const Color kSolidBase = Color(0xFF8C939A);
const Color kSolidEdge = Color(0xFF23272C);

/// Shared orthographic camera math (also used by the ViewCube/triad).
class Cam3 {
  final Vec3 dir, s, u; // view direction (camera at dir*D), right, up
  final double halfH, ox, oy;
  final Size size;
  Cam3(PartCamera c, this.size)
      : dir = c.dir,
        halfH = c.halfH,
        ox = c.ox,
        oy = c.oy,
        s = _basisS(c.dir),
        u = _basisU(c.dir);

  static Vec3 _fwd(Vec3 d) => d * -1;
  static Vec3 _basisS(Vec3 d) {
    final f = _fwd(d);
    var s = f.cross(const Vec3(0, 1, 0));
    if (s.length < 1e-9) s = f.cross(const Vec3(0, 0, 1));
    return s.normalized();
  }

  static Vec3 _basisU(Vec3 d) => _basisS(d).cross(_fwd(d)).normalized();

  double get aspect => size.width / size.height;

  Offset project(Vec3 w) {
    final x = (w.dot(s) - ox) / (halfH * aspect);
    final y = (w.dot(u) - oy) / halfH;
    return Offset((x * 0.5 + 0.5) * size.width,
        (1 - (y * 0.5 + 0.5)) * size.height);
  }

  /// Distance along the view ray — bigger = farther from the camera.
  double depth(Vec3 w) => w.dot(_fwd(dir));

  /// World point of pixel [p] on the camera plane through the origin.
  Vec3 unprojectOnCamPlane(Offset p) {
    final wx = ((p.dx / size.width) * 2 - 1) * halfH * aspect + ox;
    final wy = ((1 - p.dy / size.height) * 2 - 1) * halfH + oy;
    return s * wx + u * wy;
  }

  /// Intersection of the pixel ray with the plane n·X = 0, or null when
  /// looking edge-on.
  Vec3? rayOnPlane(Offset p, Vec3 n) {
    final o = unprojectOnCamPlane(p);
    final rd = _fwd(dir);
    final denom = n.dot(rd);
    if (denom.abs() < 1e-9) return null;
    final t = -n.dot(o) / denom;
    return o + rd * t;
  }
}

/// Depth-sorted shaded triangles + B-Rep edges for a set of solids (the
/// painter's algorithm — no GPU dependency, so it works both on screen and in
/// an off-screen [PictureRecorder]).
///
/// The caller decides WHICH solids to draw: the live viewport passes the
/// visible committed features minus the one being edited and hands the live
/// extrude preview in [previewSolid]; the gallery thumbnail passes every
/// visible solid and no preview. Because the selection happens outside, this
/// function never needs to know about ExtrudeSession — which is what keeps it
/// free of an app_state import.
void paintPartSolids(
  Canvas canvas,
  Cam3 cam,
  List<KernelSolid> solids, {
  KernelSolid? previewSolid,
}) {
  final items = <(double, void Function(Canvas))>[];
  void addSolid(KernelSolid s, {bool preview = false}) {
    final m = s.mesh;
    final light = (cam.dir + const Vec3(0.35, 0.55, 0.2)).normalized();
    for (var t = 0; t < m.indices.length; t += 3) {
      final i0 = m.indices[t] * 3,
          i1 = m.indices[t + 1] * 3,
          i2 = m.indices[t + 2] * 3;
      final w0 = Vec3(m.positions[i0], m.positions[i0 + 1], m.positions[i0 + 2]);
      final w1 = Vec3(m.positions[i1], m.positions[i1 + 1], m.positions[i1 + 2]);
      final w2 = Vec3(m.positions[i2], m.positions[i2 + 1], m.positions[i2 + 2]);
      final n = (w1 - w0).cross(w2 - w0).normalized();
      if (n.dot(cam.dir) <= 0) continue; // backface (camera sits at +dir)
      final shade = (0.42 + 0.58 * math.max(0, n.dot(light)))
          .clamp(0.0, 1.0)
          .toDouble();
      final col = Color.fromARGB(
          preview ? 165 : 255,
          (kSolidBase.red * shade).round(),
          (kSolidBase.green * shade).round(),
          (kSolidBase.blue * shade).round());
      final a = cam.project(w0), b = cam.project(w1), c = cam.project(w2);
      final depth = (cam.depth(w0) + cam.depth(w1) + cam.depth(w2)) / 3;
      items.add((depth, (cv) {
        cv.drawPath(
            Path()..addPolygon([a, b, c], true),
            Paint()
              ..color = col
              ..isAntiAlias = false);
      }));
    }
    for (var e = 0; e + 1 < m.edgeStarts.length; e++) {
      for (var k = m.edgeStarts[e]; k + 1 < m.edgeStarts[e + 1]; k++) {
        final p0 = Vec3(m.edgePoints[3 * k], m.edgePoints[3 * k + 1],
            m.edgePoints[3 * k + 2]);
        final p1 = Vec3(m.edgePoints[3 * k + 3], m.edgePoints[3 * k + 4],
            m.edgePoints[3 * k + 5]);
        final a = cam.project(p0), b = cam.project(p1);
        final depth = (cam.depth(p0) + cam.depth(p1)) / 2 - 0.35; // viewer bias
        items.add((depth, (cv) {
          cv.drawLine(
              a,
              b,
              Paint()
                ..strokeWidth = 1
                ..color =
                    preview ? kSolidEdge.withOpacity(0.6) : kSolidEdge);
        }));
      }
    }
  }

  for (final s in solids) {
    addSolid(s);
  }
  if (previewSolid != null) addSolid(previewSolid, preview: true);
  items.sort((a, b) => b.$1.compareTo(a.$1)); // far first
  for (final it in items) {
    it.$2(canvas);
  }
}
