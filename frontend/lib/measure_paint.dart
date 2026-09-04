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

import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// How much of a pick's ink a PREHIGHLIGHT gets (M374).
///
/// Low enough that a picked face beside a hovered one is unmistakably the
/// brighter of the two, high enough to read against a shaded model at a
/// glance — the prehighlight's whole job is to be seen without being looked
/// at.
const double kMeasureHoverFade = 0.45;

/// Alpha of the wash over a highlighted face or body.
///
/// Matches the sketch-plane prehighlight this app already draws
/// (`part_render.dart`, 0.42), because a measure highlight and a plane
/// highlight are the same statement — "this surface, the one under your
/// finger" — and two different tints for it would read as two different
/// things.
const double kMeasureWash = 0.42;

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
  // The PREHIGHLIGHT goes down first and dim (M374): it is a statement about
  // what the next tap would take, and it must never compete with the picks,
  // which are statements about what the reading IS.
  final h = s.hover;
  if (h != null) _paintPickHalo(canvas, h, project, dim: true);
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
void _paintPickHalo(Canvas canvas, MeasureRef ref, MeasureProject project,
    {bool dim = false}) {
  // One number separates a prehighlight from a pick, applied to every mark
  // this function makes. Anything else — a second colour, a dashed outline —
  // would have to be learnt; "the faint one is what you are about to take"
  // does not.
  final k = dim ? kMeasureHoverFade : 1.0;
  final halo = Paint()
    ..color = T.accent.withValues(alpha: 0.30 * k)
    ..style = PaintingStyle.stroke
    ..strokeWidth = kMeasureHaloWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final core = Paint()
    ..color = T.accent.withValues(alpha: k)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // A SURFACE pick — a face, a body, a component — highlights as the surface
  // it is: a wash over it and a stroke round its edge. This is the mark the
  // tool was missing, and its absence was not cosmetic. A ring at the tap
  // point says "something here was picked"; only the wash says WHICH of the
  // four faces meeting under your finger the panel is talking about.
  if (_paintSurface(canvas, ref, project, k)) return;

  final pts = ref.samples;
  if (pts.length >= 2) {
    final path = Path();
    path.moveTo(project(pts.first).dx, project(pts.first).dy);
    for (var i = 1; i < pts.length; i++) {
      final p = project(pts[i]);
      path.lineTo(p.dx, p.dy);
    }
    // A CLOSED sketch curve is being measured for its area as often as for
    // its length, and an outline alone cannot say which of two nested loops
    // the number belongs to. Filling it can — and it is the same wash a face
    // gets, because it is the same statement.
    if (ref.closed && pts.length >= 3) {
      path.close();
      canvas.drawPath(
          path, Paint()..color = T.accent.withValues(alpha: kMeasureWash * k));
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

/// Washes a face or a body and strokes its outline. Returns false when the
/// pick has no surface to draw, which sends the caller back to the curve and
/// point marks below.
///
/// A BODY's wash comes from the tessellation it already carries for the
/// distance solver, so picking a whole part costs no extra geometry. It is
/// drawn front-and-back without a depth test, which over a closed solid reads
/// as the tint over its silhouette — which is the statement, since the pick
/// really is the whole body.
bool _paintSurface(
    Canvas canvas, MeasureRef ref, MeasureProject project, double k) {
  final shape = ref.shape;
  final mesh = ref.mesh;
  final tris = shape?.patch ?? mesh?.triangles ?? const <Vec3>[];
  final loops = shape?.loops ?? mesh?.curves ?? const <List<Vec3>>[];
  if (tris.length < 3 && loops.isEmpty) return false;

  if (tris.length >= 3) {
    final pos = Float32List((tris.length ~/ 3) * 6);
    var i = 0;
    var lo = const Offset(double.infinity, double.infinity);
    var hi = const Offset(-double.infinity, -double.infinity);
    for (var t = 0; t + 2 < tris.length; t += 3) {
      for (var c = 0; c < 3; c++) {
        final p = project(tris[t + c]);
        pos[i++] = p.dx;
        pos[i++] = p.dy;
        lo = Offset(math.min(lo.dx, p.dx), math.min(lo.dy, p.dy));
        hi = Offset(math.max(hi.dx, p.dx), math.max(hi.dy, p.dy));
      }
    }
    // Through a LAYER, not straight onto the canvas. A cylinder projects its
    // far half onto its near one and a body projects all of itself onto
    // itself, so translucent triangles drawn one at a time pile up: the wash
    // comes out twice as dark exactly where the surface curves away, which
    // reads as shading that is not there. Painting them opaque into a layer
    // and fading the LAYER composites the overlap once, and the wash is then
    // the same weight everywhere — which is what makes it read as "this
    // surface is selected" rather than as a gradient.
    if (lo.dx.isFinite) {
      // Only the ALPHA of a layer paint is read when the layer composites —
      // its RGB is unused without a colour filter — so this reuses the accent
      // rather than writing a literal white that theme.dart does not own.
      canvas.saveLayer(Rect.fromPoints(lo, hi).inflate(1),
          Paint()..color = T.accent.withValues(alpha: kMeasureWash * k));
      canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos),
          BlendMode.srcOver, Paint()..color = T.accent);
      canvas.restore();
    }
  }

  final pen = Paint()
    ..color = T.accent.withValues(alpha: k)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final soft = Paint()
    ..color = T.accent.withValues(alpha: 0.28 * k)
    ..style = PaintingStyle.stroke
    ..strokeWidth = kMeasureHaloWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final loop in loops) {
    if (loop.length < 2) continue;
    final path = Path();
    final first = project(loop.first);
    path.moveTo(first.dx, first.dy);
    for (var j = 1; j < loop.length; j++) {
      final p = project(loop[j]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, soft);
    canvas.drawPath(path, pen);
  }
  return true;
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
