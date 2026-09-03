// M371 — what a measurement LOOKS like over the model.
//
// One painter for all three viewports. The 2D sketcher, the part and the
// assembly project differently and have nothing else in common, so this takes
// the projection as a closure — hand it `project` and it draws the same
// picture in all three, which is the only way "the measurement looks the same
// everywhere" can be true rather than aspired to.
//
// WHAT IT DRAWS, and why each part earns its ink:
//
//   * A HALO on every pick. Without it a two-pick measurement is a number
//     with no subject: you cannot tell which face of the four under the
//     cursor the panel is talking about. Drawn from the pick's own samples
//     where it has them, so a circular edge highlights as the circle it is.
//   * The DIMENSION LINE, with the extension lines and arrowheads a drawing
//     would have. Inventor draws the same figure, and it is what turns "82,5"
//     into "82,5 between THESE two things".
//   * The VALUE, in a chip on the line. On glass the panel is off to one side
//     and the eye is on the model; a number only in the panel makes you look
//     away from what you are measuring.
//
// EVERY SIZE IS IN POINTS, not in model units. A 2 mm chamfer and a 2 m beam
// get the same arrowheads, the same halo width and the same chip — which is
// what makes the annotation readable at any zoom, and is why the geometry
// comes in already projected rather than being scaled here.
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'measure.dart';
import 'part_model.dart' show Vec3;
import 'theme.dart';

/// Projects a world point to the viewport's own pixels.
typedef MeasureProject = Offset Function(Vec3);

/// Line weight of a pick's halo.
const double kMeasureHaloWidth = 5.0;

/// Line weight of the dimension line itself.
const double kMeasureLineWidth = 1.6;

/// Arrowhead length, in points.
const double kMeasureArrow = 9.0;

/// Draws the whole annotation for [s] — the picks, the dimension figure and
/// the value.
///
/// [project] maps a world point to this viewport's pixels. [size] is the
/// canvas, used only to keep the value chip on screen.
void paintMeasureOverlay(
  Canvas canvas,
  MeasureSession s,
  MeasureProject project,
  Size size,
) {
  for (final ref in s.picks) {
    _paintPickHalo(canvas, ref, project);
  }
  final r = s.reading;
  if (r == null) return;
  final marker = r.marker;
  if (marker == null) return;

  final label = _labelFor(r, s);
  switch (marker.kind) {
    case MeasureMarkerKind.span:
      _paintSpan(canvas, project(marker.a!), project(marker.b!), label, size);
      break;
    case MeasureMarkerKind.radial:
      _paintRadial(canvas, project(marker.a!), project(marker.b!), label, size);
      break;
    case MeasureMarkerKind.point:
      _paintPoint(canvas, project(marker.a!), label, size);
      break;
    case MeasureMarkerKind.angle:
      _paintAngle(
          canvas,
          project(marker.apex!),
          project(marker.apex! + marker.armA!),
          project(marker.apex! + marker.armB!),
          label,
          size);
      break;
  }
}

/// The value written on the model: the primary, in the primary unit.
///
/// The DUAL unit is deliberately not here. The chip sits over the geometry and
/// has to stay small enough not to hide what it measures; the second unit is a
/// line in the panel, where there is room for it.
String _labelFor(MeasureReading r, MeasureSession s) {
  final v = r.primary;
  final text =
      measureFormat(v, decimals: s.decimals, unit: MeasureUnitSystem.millimetre);
  return v.approximate ? '≈ $text' : text;
}

// ---------------------------------------------------------------------------
// the picks
// ---------------------------------------------------------------------------

/// A soft halo over one pick.
///
/// Two strokes, wide and translucent under narrow and solid, which is how
/// every selection highlight in this app is drawn and is what keeps a
/// highlighted edge legible over both a light face and a dark one.
void _paintPickHalo(Canvas canvas, MeasureRef ref, MeasureProject project) {
  final halo = Paint()
    ..color = T.accent.withValues(alpha: 0.30)
    ..style = PaintingStyle.stroke
    ..strokeWidth = kMeasureHaloWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final core = Paint()
    ..color = T.accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  final pts = ref.samples;
  if (pts.length >= 2) {
    final path = Path();
    path.moveTo(project(pts.first).dx, project(pts.first).dy);
    for (var i = 1; i < pts.length; i++) {
      final p = project(pts[i]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, halo);
    canvas.drawPath(path, core);
    return;
  }
  if (ref.hasSegment) {
    final a = project(ref.a!), b = project(ref.b!);
    canvas.drawLine(a, b, halo);
    canvas.drawLine(a, b, core);
    return;
  }
  // A face, a plane, a cylinder or a bare point: there is no curve to trace,
  // so the halo goes where the finger landed. A ring rather than a disc — a
  // filled dot on the exact spot you are measuring to would hide it.
  final at = ref.hitAt ?? ref.point ?? ref.planeAt ?? ref.axisAt;
  if (at == null) return;
  final p = project(at);
  canvas.drawCircle(p, 9, halo);
  canvas.drawCircle(p, 9, core);
  canvas.drawCircle(p, 1.6, Paint()..color = T.accent);
}

// ---------------------------------------------------------------------------
// the dimension figure
// ---------------------------------------------------------------------------

/// A dimension line between two points, with arrowheads and the value.
void _paintSpan(
    Canvas canvas, Offset a, Offset b, String label, Size size) {
  final pen = Paint()
    ..color = T.accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = kMeasureLineWidth
    ..strokeCap = StrokeCap.round;
  final len = (b - a).distance;
  if (len < 1e-6) {
    _paintPoint(canvas, a, label, size);
    return;
  }
  final u = (b - a) / len;
  canvas.drawLine(a, b, pen);
  // The ticks at the ends: short strokes ACROSS the line, which is what says
  // the measurement stops here rather than continuing.
  final n = Offset(-u.dy, u.dx);
  canvas.drawLine(a - n * 5, a + n * 5, pen);
  canvas.drawLine(b - n * 5, b + n * 5, pen);
  // Arrowheads point OUTWARD from the middle, the way a drawing's do, and
  // only when there is room for them between the ticks.
  if (len > 3 * kMeasureArrow) {
    _arrow(canvas, a, u, pen);
    _arrow(canvas, b, u * -1, pen);
  }
  _chip(canvas, (a + b) / 2, label, size);
}

/// A diameter or radius line across a round pick.
void _paintRadial(
    Canvas canvas, Offset a, Offset b, String label, Size size) {
  _paintSpan(canvas, a, b, label, size);
}

/// One highlighted point — a vertex reading, or two picks that coincide.
void _paintPoint(Canvas canvas, Offset p, String label, Size size) {
  final pen = Paint()
    ..color = T.accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = kMeasureLineWidth;
  canvas.drawCircle(p, 6, pen);
  canvas.drawCircle(p, 1.8, Paint()..color = T.accent);
  _chip(canvas, p + const Offset(0, -22), label, size);
}

/// The angle figure: two arms, an arc between them, the value on the arc.
///
/// The arms are drawn to a fixed PIXEL length rather than to wherever the
/// projected geometry ended up, so the figure is the same size on a chamfer
/// and on a beam. The arc is swept the short way between them, which is the
/// angle the reading is about.
void _paintAngle(Canvas canvas, Offset apex, Offset armA, Offset armB,
    String label, Size size) {
  final pen = Paint()
    ..color = T.accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = kMeasureLineWidth
    ..strokeCap = StrokeCap.round;
  final da = armA - apex, db = armB - apex;
  if (da.distance < 1e-6 || db.distance < 1e-6) return;
  const reach = 54.0;
  final ua = da / da.distance, ub = db / db.distance;
  canvas.drawLine(apex, apex + ua * reach, pen);
  canvas.drawLine(apex, apex + ub * reach, pen);

  const radius = 34.0;
  final a0 = math.atan2(ua.dy, ua.dx);
  var sweep = math.atan2(ub.dy, ub.dx) - a0;
  // Normalise into (-pi, pi] so the arc runs the short way round: the two
  // arms already point into the angle being measured, and an arc that went
  // the long way would draw the reflex angle under the reading.
  while (sweep <= -math.pi) {
    sweep += 2 * math.pi;
  }
  while (sweep > math.pi) {
    sweep -= 2 * math.pi;
  }
  canvas.drawArc(Rect.fromCircle(center: apex, radius: radius), a0, sweep,
      false, pen);
  // The chip sits on the BISECTOR, just outside the arc, which is where a
  // drawing puts the number and is the one place it cannot cover either arm.
  final mid = a0 + sweep / 2;
  _chip(
      canvas,
      apex + Offset(math.cos(mid), math.sin(mid)) * (radius + 18),
      label,
      size);
}

/// A filled arrowhead at [tip], pointing along [u].
void _arrow(Canvas canvas, Offset tip, Offset u, Paint pen) {
  final n = Offset(-u.dy, u.dx);
  final back = tip + u * kMeasureArrow;
  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(back.dx + n.dx * 3, back.dy + n.dy * 3)
    ..lineTo(back.dx - n.dx * 3, back.dy - n.dy * 3)
    ..close();
  canvas.drawPath(path, Paint()..color = pen.color);
}

/// The value, in a rounded chip centred on [at] and kept inside [size].
void _chip(Canvas canvas, Offset at, String label, Size size) {
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
          color: T.onAccent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  const padX = 8.0, padY = 4.0;
  final w = tp.width + padX * 2, h = tp.height + padY * 2;
  // Clamped rather than clipped: a dimension line can run off the edge of the
  // viewport at a steep zoom, and a number half off screen is a number nobody
  // can read.
  final left = (at.dx - w / 2)
      .clamp(4.0, math.max(4.0, size.width - w - 4))
      .toDouble();
  final top = (at.dy - h / 2)
      .clamp(4.0, math.max(4.0, size.height - h - 4))
      .toDouble();
  final box = Rect.fromLTWH(left, top, w, h);
  final rr = RRect.fromRectAndRadius(box, const Radius.circular(7));
  canvas.drawRRect(
      rr.shift(const Offset(0, 1)),
      Paint()
        ..color = T.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  canvas.drawRRect(rr, Paint()..color = T.accent);
  tp.paint(canvas, box.topLeft + const Offset(padX, padY));
}
