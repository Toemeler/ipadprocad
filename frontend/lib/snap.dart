// iPadProCAD — object snapping, grip editing and box-select geometry.
//
// Snapping (Inventor-style, priority ordered): endpoint > midpoint >
// center > quadrant > on-curve, plus horizontal/vertical alignment guides
// relative to the reference point (the previous pick) and the origin.
// Box select follows Inventor exactly: dragging left->right is a WINDOW
// select (only entities fully inside, solid blue rectangle), dragging
// right->left is a CROSSING select (everything touched, dashed green).
import 'dart:math' as math;
import 'dart:ui';

import 'ffi/qcad_engine.dart';

// ---------------------------------------------------------------------------
// snapping
// ---------------------------------------------------------------------------
class Snap {
  final Offset pos;
  final String kind; // endpoint|midpoint|center|quadrant|vertex|on|origin|align
  final List<Offset> alignRefs; // origins of H/V alignment guides
  const Snap(this.pos, this.kind, [this.alignRefs = const []]);
}

/// Snaps [w] against [geos] with tolerance [tol] (world units). [ref] is the
/// previous picked point for H/V alignment. [exclude] suppresses snapping to
/// one specific point (the grip currently being dragged).
Snap? computeSnap(List<Geo> geos, Offset w, double tol,
    {Offset? ref, Offset? exclude}) {
  bool excluded(Offset q) =>
      exclude != null && (q - exclude).distance < 1e-9;

  Snap? best;
  var bestD = tol;
  void offer(Offset q, String kind, [double bias = 1.0]) {
    if (excluded(q)) return;
    final d = (w - q).distance * bias;
    if (d < bestD) {
      bestD = d;
      best = Snap(q, kind);
    }
  }

  for (final g in geos) {
    switch (g.type) {
      case Geo.line:
        final a = Offset(g.data[0], g.data[1]), b = Offset(g.data[2], g.data[3]);
        offer(a, 'endpoint');
        offer(b, 'endpoint');
        offer((a + b) / 2, 'midpoint', 1.05);
        break;
      case Geo.circle:
        final c = Offset(g.data[0], g.data[1]);
        final r = g.data[2];
        offer(c, 'center', 1.05);
        for (final q in _quadrants(c, r)) {
          offer(q, 'quadrant', 1.1);
        }
        break;
      case Geo.arc:
        final c = Offset(g.data[0], g.data[1]);
        final r = g.data[2];
        offer(c + Offset(math.cos(g.data[3]), math.sin(g.data[3])) * r,
            'endpoint');
        offer(c + Offset(math.cos(g.data[4]), math.sin(g.data[4])) * r,
            'endpoint');
        offer(c, 'center', 1.05);
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        for (var i = 0; i < n; i++) {
          offer(Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]), 'vertex');
        }
        for (var i = 0; i + 1 < n; i++) {
          final a = Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]);
          final b = Offset(g.data[4 + 2 * i], g.data[5 + 2 * i]);
          offer((a + b) / 2, 'midpoint', 1.1);
        }
        break;
    }
  }
  offer(Offset.zero, 'origin');
  if (best != null) return best;

  // H/V alignment guides (dotted lines in Inventor) against ref and origin
  final refs = [if (ref != null) ref, Offset.zero];
  double x = w.dx, y = w.dy;
  final ax = <Offset>[], ay = <Offset>[];
  for (final q in refs) {
    if ((w.dx - q.dx).abs() < tol && ax.isEmpty) {
      x = q.dx;
      ax.add(q);
    }
    if ((w.dy - q.dy).abs() < tol && ay.isEmpty) {
      y = q.dy;
      ay.add(q);
    }
  }
  if (ax.isNotEmpty || ay.isNotEmpty) {
    return Snap(Offset(x, y), 'align', [...ax, ...ay]);
  }

  // on-curve (nearest point on an entity)
  Snap? on;
  var onD = tol;
  void offerOn(Offset q) {
    final d = (w - q).distance;
    if (d < onD) {
      onD = d;
      on = Snap(q, 'on');
    }
  }

  for (final g in geos) {
    switch (g.type) {
      case Geo.line:
        offerOn(closestOnSegment(w, Offset(g.data[0], g.data[1]),
            Offset(g.data[2], g.data[3])));
        break;
      case Geo.circle:
        final c = Offset(g.data[0], g.data[1]);
        final d = w - c;
        if (d.distance > 1e-9) offerOn(c + d / d.distance * g.data[2]);
        break;
      case Geo.arc:
        final c = Offset(g.data[0], g.data[1]);
        final d = w - c;
        if (d.distance < 1e-9) break;
        final ang = math.atan2(d.dy, d.dx);
        if (_angleOnArc(ang, g.data[3], g.data[4], g.data[5] != 0)) {
          offerOn(c + d / d.distance * g.data[2]);
        }
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        for (var i = 0; i + 1 < n; i++) {
          offerOn(closestOnSegment(
              w,
              Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]),
              Offset(g.data[4 + 2 * i], g.data[5 + 2 * i])));
        }
        break;
    }
  }
  return on;
}

List<Offset> _quadrants(Offset c, double r) => [
      c + Offset(r, 0),
      c + Offset(0, r),
      c + Offset(-r, 0),
      c + Offset(0, -r)
    ];

Offset closestOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return a;
  var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  return a + ab * t;
}

bool _angleOnArc(double a, double a1, double a2, bool reversed) {
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  final sweep = reversed ? norm(a1 - a2) : norm(a2 - a1);
  final rel = reversed ? norm(a1 - a) : norm(a - a1);
  return rel <= sweep + 1e-9;
}

// ---------------------------------------------------------------------------
// grips (draggable sketch points)
// ---------------------------------------------------------------------------
class Grip {
  final int entity; // index into geometry list
  final int idx; // meaning depends on entity type
  final Offset pos;
  final String kind; // end|center|vertex|radius
  const Grip(this.entity, this.idx, this.pos, this.kind);
}

List<Grip> gripsOf(List<Geo> geos) {
  final out = <Grip>[];
  for (var e = 0; e < geos.length; e++) {
    final g = geos[e];
    switch (g.type) {
      case Geo.line:
        out.add(Grip(e, 0, Offset(g.data[0], g.data[1]), 'end'));
        out.add(Grip(e, 1, Offset(g.data[2], g.data[3]), 'end'));
        break;
      case Geo.circle:
        final c = Offset(g.data[0], g.data[1]);
        out.add(Grip(e, 0, c, 'center'));
        var i = 1;
        for (final q in _quadrants(c, g.data[2])) {
          out.add(Grip(e, i++, q, 'radius'));
        }
        break;
      case Geo.arc:
        final c = Offset(g.data[0], g.data[1]);
        out.add(Grip(e, 0, c, 'center'));
        out.add(
            Grip(e, 1, c + Offset(math.cos(g.data[3]), math.sin(g.data[3])) * g.data[2], 'end'));
        out.add(
            Grip(e, 2, c + Offset(math.cos(g.data[4]), math.sin(g.data[4])) * g.data[2], 'end'));
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        for (var i = 0; i < n; i++) {
          out.add(Grip(e, i, Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]),
              'vertex'));
        }
        break;
    }
  }
  return out;
}

/// Returns [g] with [grip] moved to [to].
Geo moveGrip(Geo g, Grip grip, Offset to) {
  final d = List<double>.from(g.data);
  switch (g.type) {
    case Geo.line:
      if (grip.idx == 0) {
        d[0] = to.dx;
        d[1] = to.dy;
      } else {
        d[2] = to.dx;
        d[3] = to.dy;
      }
      break;
    case Geo.circle:
      if (grip.kind == 'center') {
        d[0] = to.dx;
        d[1] = to.dy;
      } else {
        d[2] = math.max(1e-6, (to - Offset(d[0], d[1])).distance);
      }
      break;
    case Geo.arc:
      if (grip.idx == 0) {
        d[0] = to.dx;
        d[1] = to.dy;
      } else {
        final c = Offset(d[0], d[1]);
        final v = to - c;
        if (v.distance > 1e-9) {
          d[2] = v.distance;
          d[grip.idx == 1 ? 3 : 4] = math.atan2(v.dy, v.dx);
        }
      }
      break;
    case Geo.polyline:
      d[2 + 2 * grip.idx] = to.dx;
      d[3 + 2 * grip.idx] = to.dy;
      break;
  }
  return g.withData(d); // KEEPS the layer
}

// ---------------------------------------------------------------------------
// selection (tap + box)
// ---------------------------------------------------------------------------
/// Samples an entity into a point chain for hit/box tests.
List<Offset> sampleEntity(Geo g, {int arcSamples = 32}) {
  switch (g.type) {
    case Geo.line:
      return [Offset(g.data[0], g.data[1]), Offset(g.data[2], g.data[3])];
    case Geo.circle:
      final c = Offset(g.data[0], g.data[1]);
      return [
        for (var i = 0; i <= arcSamples; i++)
          c +
              Offset(math.cos(2 * math.pi * i / arcSamples),
                      math.sin(2 * math.pi * i / arcSamples)) *
                  g.data[2]
      ];
    case Geo.arc:
      final c = Offset(g.data[0], g.data[1]);
      double norm(double x) {
        var v = x % (2 * math.pi);
        if (v < 0) v += 2 * math.pi;
        return v;
      }

      final rev = g.data[5] != 0;
      final sweep = rev ? -norm(g.data[3] - g.data[4]) : norm(g.data[4] - g.data[3]);
      return [
        for (var i = 0; i <= arcSamples; i++)
          c +
              Offset(math.cos(g.data[3] + sweep * i / arcSamples),
                      math.sin(g.data[3] + sweep * i / arcSamples)) *
                  g.data[2]
      ];
    case Geo.polyline:
      final n = g.data[1].toInt();
      final pts = [
        for (var i = 0; i < n; i++)
          Offset(g.data[2 + 2 * i], g.data[3 + 2 * i])
      ];
      if (g.data[0] != 0 && n > 1) pts.add(pts.first);
      return pts;
  }
  return const [];
}

double distToEntity(Geo g, Offset p) {
  final pts = sampleEntity(g);
  var best = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    final d = (p - closestOnSegment(p, pts[i], pts[i + 1])).distance;
    if (d < best) best = d;
  }
  return best;
}

bool _segIntersectsRect(Offset a, Offset b, Rect r) {
  if (r.contains(a) || r.contains(b)) return true;
  bool segseg(Offset p1, Offset p2, Offset p3, Offset p4) {
    double cross(Offset o, Offset q, Offset s) =>
        (q.dx - o.dx) * (s.dy - o.dy) - (q.dy - o.dy) * (s.dx - o.dx);
    final d1 = cross(p3, p4, p1),
        d2 = cross(p3, p4, p2),
        d3 = cross(p1, p2, p3),
        d4 = cross(p1, p2, p4);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
  }

  final tl = r.topLeft, tr = r.topRight, br = r.bottomRight, bl = r.bottomLeft;
  return segseg(a, b, tl, tr) ||
      segseg(a, b, tr, br) ||
      segseg(a, b, br, bl) ||
      segseg(a, b, bl, tl);
}

/// Inventor semantics: window (crossing == false) selects only entities
/// FULLY inside; crossing selects everything the rectangle touches.
bool entityInRect(Geo g, Rect r, {required bool crossing}) {
  final pts = sampleEntity(g);
  if (pts.isEmpty) return false;
  if (crossing) {
    for (final p in pts) {
      if (r.contains(p)) return true;
    }
    for (var i = 0; i + 1 < pts.length; i++) {
      if (_segIntersectsRect(pts[i], pts[i + 1], r)) return true;
    }
    return false;
  }
  for (final p in pts) {
    if (!r.contains(p)) return false;
  }
  return true;
}
