// iPadProCAD — Heads-Up Display (Dynamic Input), Inventor-faithful.
//
// Inventor shows floating value boxes near the cursor while a create tool is
// running (Line, Circle, Arc, Rectangle, Point, Slot, ...). As the cursor
// moves the boxes update live; TYPING a value locks that field (a persistent
// driving dimension is created for it on commit), Tab moves to the next box,
// Enter/click places the geometry. A field you never type into is driven by
// the cursor and gets NO dimension — exactly what the user described.
//
// This file is the single source of truth for, per (tool, phase):
//   * which input fields exist and their order  -> hudFieldsFor
//   * the live measured value of a field         -> hudMeasure
//   * the cursor position that honours the locks -> hudConstrain
// The dimension a locked field turns into on commit lives in app_state
// (_hudBuildDims), because it needs the freshly-placed entity indices.
//
// "phase" == number of points already committed (toolPoints.length). A
// two-point tool draws its fields at phase 1 (anchor placed, second point
// live); a three-point slot uses phase 1 for the axis and phase 2 for width.
import 'dart:math' as math;
import 'dart:ui';

import 'app_state.dart' show Tool;

/// The physical quantity a HUD field carries. Each maps to a driving dimension
/// on commit (x/y pair into two origin-relative linear dims). Some quantities
/// (ellipse axes, polygon radius) currently only size the preview geometry and
/// do not yet emit a persistent dimension — see _hudBuildDims in app_state.
enum HudKind {
  width,
  height,
  diameter,
  radius,
  length,
  angle,
  x,
  y,
  axisA,
  axisB,
  slotWidth,
}

class HudField {
  final HudKind kind;
  final String label; // short glyph in the box: W H Ø R L A X Y a b
  final bool angular; // formatted in degrees
  const HudField(this.kind, this.label, {this.angular = false});
}

// ---- small geometry helpers ------------------------------------------------
const double _deg = math.pi / 180.0;
double _r2d(double r) => r * 180.0 / math.pi;
double _sign(double v) => v < 0 ? -1.0 : 1.0;

/// CCW-positive angle in [0,360) swept from a0 to a1 (radians in, degrees out).
double _sweepDeg(double a0, double a1) {
  var d = (a1 - a0) % (2 * math.pi);
  if (d < 0) d += 2 * math.pi;
  return _r2d(d);
}

/// Unit vector + length of (b-a). unit is (1,0) if the two points coincide.
(Offset, double) _unit(Offset a, Offset b) {
  final v = b - a;
  final l = v.distance;
  return (l < 1e-12 ? const Offset(1, 0) : v / l, l);
}

/// Signed perpendicular component of (p-a) about the axis a->b (left normal).
double _perp(Offset a, Offset b, Offset p) {
  final (un, _) = _unit(a, b);
  final vn = Offset(-un.dy, un.dx);
  final rel = p - a;
  return rel.dx * vn.dx + rel.dy * vn.dy;
}

/// Keep the along-axis component of [cur] about a->b but force the
/// perpendicular magnitude to [lockedPerp] (preserving which side of the axis
/// the cursor is on). Used by the width/extent phases (rect3P, ellipse, slots).
Offset _applyPerp(Offset a, Offset b, Offset cur, double? lockedPerp) {
  final (un, l) = _unit(a, b);
  if (l < 1e-12) return cur;
  final vn = Offset(-un.dy, un.dx);
  final rel = cur - a;
  final along = rel.dx * un.dx + rel.dy * un.dy;
  final perp = rel.dx * vn.dx + rel.dy * vn.dy;
  final w = lockedPerp ?? perp.abs();
  return a + un * along + vn * (_sign(perp) * w);
}

/// Tools whose FIRST live segment is polar: anchor at pts[0], the second point
/// defined by a length + angle from it (Line, 3-point Rectangle's first edge,
/// all three linear slots' axis).
bool _isPolarFirst(Tool t) =>
    t == Tool.line ||
    t == Tool.rect3P ||
    t == Tool.slotCC ||
    t == Tool.slotOverall ||
    t == Tool.slotCP;

/// The ordered input fields for [t] at [phase] committed points. An empty list
/// means this tool/phase has no dynamic input (splines, tangent circle, ...).
List<HudField> hudFieldsFor(Tool t, int phase) {
  switch (t) {
    case Tool.point:
      return phase == 0
          ? const [HudField(HudKind.x, 'X'), HudField(HudKind.y, 'Y')]
          : const [];
    case Tool.line:
      return phase == 1
          ? const [
              HudField(HudKind.length, 'L'),
              HudField(HudKind.angle, 'A', angular: true),
            ]
          : const [];
    case Tool.circleCenter:
      return phase == 1
          ? const [HudField(HudKind.diameter, '\u00D8')]
          : const [];
    case Tool.rectTwoPoint:
    case Tool.rect2PC:
      return phase == 1
          ? const [HudField(HudKind.width, 'W'), HudField(HudKind.height, 'H')]
          : const [];
    case Tool.rect3P:
      if (phase == 1) {
        return const [
          HudField(HudKind.length, 'L'),
          HudField(HudKind.angle, 'A', angular: true),
        ];
      }
      return phase == 2 ? const [HudField(HudKind.width, 'W')] : const [];
    case Tool.slotCC:
    case Tool.slotOverall:
    case Tool.slotCP:
      if (phase == 1) {
        return const [
          HudField(HudKind.length, 'L'),
          HudField(HudKind.angle, 'A', angular: true),
        ];
      }
      return phase == 2 ? const [HudField(HudKind.slotWidth, 'W')] : const [];
    case Tool.arcCenter:
      if (phase == 1) return const [HudField(HudKind.radius, 'R')];
      return phase == 2
          ? const [HudField(HudKind.angle, 'A', angular: true)]
          : const [];
    case Tool.ellipse:
      if (phase == 1) return const [HudField(HudKind.axisA, 'a')];
      return phase == 2 ? const [HudField(HudKind.axisB, 'b')] : const [];
    case Tool.polygon:
      return phase == 1 ? const [HudField(HudKind.radius, 'R')] : const [];
    default:
      return const [];
  }
}

/// Live measured value of field [i] from the raw (snapped) cursor. Fills the
/// boxes the user has not typed into.
double hudMeasure(Tool t, List<Offset> pts, Offset cur, int i) {
  final fields = hudFieldsFor(t, pts.length);
  if (i < 0 || i >= fields.length) return 0;
  final kind = fields[i].kind;
  final phase = pts.length;

  // absolute pointer input (Point tool)
  if (t == Tool.point) return kind == HudKind.x ? cur.dx : cur.dy;

  // polar first segment (length + angle)
  if (_isPolarFirst(t) && phase == 1) {
    final (u, l) = _unit(pts[0], cur);
    return kind == HudKind.angle
        ? ((_r2d(math.atan2(u.dy, u.dx)) % 360) + 360) % 360
        : l;
  }

  switch (kind) {
    case HudKind.diameter:
      return 2 * (cur - pts[0]).distance;
    case HudKind.radius:
    case HudKind.axisA:
      // arc radius (phase1), ellipse semi-major, polygon circumradius
      return (cur - pts[0]).distance;
    case HudKind.width:
      if (t == Tool.rect2PC) return 2 * (cur.dx - pts[0].dx).abs();
      if (t == Tool.rectTwoPoint) return (cur.dx - pts[0].dx).abs();
      return _perp(pts[0], pts[1], cur).abs(); // rect3P phase2
    case HudKind.height:
      return t == Tool.rect2PC
          ? 2 * (cur.dy - pts[0].dy).abs()
          : (cur.dy - pts[0].dy).abs();
    case HudKind.axisB:
      return _perp(pts[0], pts[1], cur).abs();
    case HudKind.slotWidth:
      return 2 * _perp(pts[0], pts[1], cur).abs();
    case HudKind.angle:
      // arcCenter phase2: CCW sweep from the start point
      final a0 = math.atan2(pts[1].dy - pts[0].dy, pts[1].dx - pts[0].dx);
      final a1 = math.atan2(cur.dy - pts[0].dy, cur.dx - pts[0].dx);
      return _sweepDeg(a0, a1);
    default:
      return 0;
  }
}

/// The cursor position preview + commit should use, applying the locked field
/// values in [locked] (field index -> value). Absent fields stay cursor-driven.
Offset hudConstrain(
    Tool t, List<Offset> pts, Offset cur, Map<int, double> locked) {
  if (locked.isEmpty) return cur;
  final fields = hudFieldsFor(t, pts.length);
  final phase = pts.length;
  double? lockOf(HudKind k) {
    final i = fields.indexWhere((f) => f.kind == k);
    return i < 0 ? null : locked[i];
  }

  if (t == Tool.point) {
    return Offset(lockOf(HudKind.x) ?? cur.dx, lockOf(HudKind.y) ?? cur.dy);
  }

  if (_isPolarFirst(t) && phase == 1) {
    final p0 = pts[0];
    final (u, l) = _unit(p0, cur);
    final la = lockOf(HudKind.angle), ll = lockOf(HudKind.length);
    final ang = la != null ? la * _deg : math.atan2(u.dy, u.dx);
    final r = ll ?? l;
    return p0 + Offset(math.cos(ang), math.sin(ang)) * r;
  }

  if (t == Tool.circleCenter) {
    final c = pts[0];
    final (u, d) = _unit(c, cur);
    final ld = lockOf(HudKind.diameter);
    return c + u * (ld != null ? ld / 2 : d);
  }

  if (t == Tool.arcCenter && phase == 1) {
    final c = pts[0];
    final (u, d) = _unit(c, cur);
    final lr = lockOf(HudKind.radius);
    return c + u * (lr ?? d);
  }
  if (t == Tool.arcCenter && phase == 2) {
    final c = pts[0], start = pts[1];
    final la = lockOf(HudKind.angle);
    if (la == null) return cur;
    final r = (start - c).distance;
    final a0 = math.atan2(start.dy - c.dy, start.dx - c.dx);
    final aEnd = a0 + la * _deg; // CCW positive, matches the arc builder
    return c + Offset(math.cos(aEnd), math.sin(aEnd)) * r;
  }

  if ((t == Tool.ellipse && phase == 1) || t == Tool.polygon) {
    final c = pts[0];
    final (u, d) = _unit(c, cur);
    final lr = lockOf(t == Tool.ellipse ? HudKind.axisA : HudKind.radius);
    return c + u * (lr ?? d);
  }

  if (t == Tool.rectTwoPoint) {
    final a = pts[0];
    final w = lockOf(HudKind.width), h = lockOf(HudKind.height);
    return Offset(w != null ? a.dx + _sign(cur.dx - a.dx) * w : cur.dx,
        h != null ? a.dy + _sign(cur.dy - a.dy) * h : cur.dy);
  }
  if (t == Tool.rect2PC) {
    final c = pts[0];
    final w = lockOf(HudKind.width), h = lockOf(HudKind.height);
    final hx = w != null ? w / 2 : (cur.dx - c.dx).abs();
    final hy = h != null ? h / 2 : (cur.dy - c.dy).abs();
    return c + Offset(_sign(cur.dx - c.dx) * hx, _sign(cur.dy - c.dy) * hy);
  }

  if (t == Tool.rect3P && phase == 2) {
    return _applyPerp(pts[0], pts[1], cur, lockOf(HudKind.width));
  }
  if (t == Tool.ellipse && phase == 2) {
    return _applyPerp(pts[0], pts[1], cur, lockOf(HudKind.axisB));
  }
  if ((t == Tool.slotCC || t == Tool.slotOverall || t == Tool.slotCP) &&
      phase == 2) {
    final w = lockOf(HudKind.slotWidth);
    return _applyPerp(pts[0], pts[1], cur, w == null ? null : w / 2);
  }

  return cur;
}
