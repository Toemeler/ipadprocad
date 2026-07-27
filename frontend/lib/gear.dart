// Prototype — parametric involute gear generator (M61).
//
// A gear is stored EXACTLY like the ellipse: a polyline tagged Geo.gearTag that
// keeps only TWO defining vertices — [center, orientation handle] — followed by
// a parameter block. The full tooth outline is generated Dart-side by
// [gearCurve] and used for rendering, snapping, hit-testing and 3D extrusion,
// while the solver, the grips and the DXF round-trip only ever see the two
// points (the count field stays 2). Dragging the CENTER translates the whole
// gear; dragging the HANDLE (or dimensioning the rotation line's angle) rotates
// it. Because the shape is baked into [gearCurve] rather than solved, a gear
// never explodes the constraint system: the sketch gains exactly three degrees
// of freedom — centre x, centre y and orientation — so the user only has to
// dimension the middle point and one angle to fully constrain it.
//
// Geometry (metric module system, ISO 21771 / DIN 867 proportions, clearance
// c* = 0.25). All lengths in millimetres, angles in radians internally.
//
//   pitch radius     r  = m·z / 2
//   base radius      rb = r·cos α
//   external tip     ra = r + m·(1 + x)          root rf = r − m·(1.25 − x)
//   internal tip     ra = r − m·(1 − x)          root rf = r + m·(1.25 + x)
//
// The involute of the base circle at radius ρ ≥ rb has polar angle inv(αρ),
// αρ = acos(rb/ρ), inv(a) = tan a − a. The half tooth angle at radius ρ is
//   ψ(ρ) = ψp + inv α − inv(αρ),
// where ψp is the half tooth thickness angle at the pitch circle:
//   external ψp = (π/2 + 2x·tan α) / z,  internal ψp = (π/2 − 2x·tan α) / z.
// A tooth is symmetric about its centre line; below the base circle (low tooth
// counts) the flank is clamped to ψ(rb), which draws a short radial root fillet
// instead of an (undefined) involute — robust and visually clean.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'ffi/qcad_engine.dart';

/// The editable parameters of a gear. Serialised into the gearTag polyline's
/// data (past the two defining vertices) and into the .gears.json sidecar.
class GearParams {
  double module; // m (mm)
  int teeth; // z
  double pressureAngleDeg; // α (°), 20 standard
  double profileShift; // x (profile shift coefficient)
  bool internal; // ring gear (teeth point inward)
  double bore; // centre bore DIAMETER (mm); 0 = none
  bool fillet; // automatic root fillet + tip round
  double rootFilletCoef; // root fillet radius as a multiple of module
  double tipRoundCoef; // tip corner round as a multiple of module
  double cornerRadius; // explicit corner (root fillet) radius in mm; 0 = auto

  GearParams({
    this.module = 2.0,
    this.teeth = 20,
    this.pressureAngleDeg = 20.0,
    this.profileShift = 0.0,
    this.internal = false,
    this.bore = 0.0,
    this.fillet = true,
    this.rootFilletCoef = 0.38,
    this.tipRoundCoef = 0.12,
    this.cornerRadius = 0.0,
  });

  GearParams copy() => GearParams(
        module: module,
        teeth: teeth,
        pressureAngleDeg: pressureAngleDeg,
        profileShift: profileShift,
        internal: internal,
        bore: bore,
        fillet: fillet,
        rootFilletCoef: rootFilletCoef,
        tipRoundCoef: tipRoundCoef,
        cornerRadius: cornerRadius,
      );

  /// Every field that changes the generated outline, for cache keys. Must be
  /// updated whenever a shape-affecting parameter is added.
  String get signature => '$module|$teeth|$pressureAngleDeg|$profileShift|'
      '$internal|$bore|$fillet|$rootFilletCoef|$tipRoundCoef|$cornerRadius';

  // ---- derived radii ----
  double get pitchRadius => module * teeth / 2.0;
  double get baseRadius =>
      pitchRadius * math.cos(pressureAngleDeg * math.pi / 180.0);
  double get tipRadius => internal
      ? pitchRadius - module * (1.0 - profileShift)
      : pitchRadius + module * (1.0 + profileShift);
  double get rootRadius => internal
      ? pitchRadius + module * (1.25 + profileShift)
      : pitchRadius - module * (1.25 - profileShift);

  /// Largest radius any drawn point reaches (root for internal, tip for
  /// external) — used to size the centre cross so it overhangs the gear.
  double get outerRadius => math.max(tipRadius, rootRadius);

  /// Radius the orientation handle sits at (the pitch circle — THE gear
  /// reference). The rotation line runs from the centre to this point, so its
  /// angle is what the user dimensions.
  double get handleRadius => pitchRadius;

  /// The corner rounding actually applied at the tooth ROOT, in mm. An
  /// explicit [cornerRadius] wins; 0 falls back to the classic module-relative
  /// coefficient, which is what every pre-M63 sketch carries.
  double get rootFilletRadius =>
      cornerRadius > 0 ? cornerRadius : rootFilletCoef * module;

  /// The tip corner round, kept in the same proportion to the root fillet as
  /// the stock coefficients (0.12 : 0.38), so one setting drives both corners
  /// and the default value reproduces the previous shape exactly.
  double get tipRoundRadius => cornerRadius > 0
      ? cornerRadius * (tipRoundCoef / rootFilletCoef)
      : tipRoundCoef * module;

  /// True when these values can actually be drawn (a positive tooth with a
  /// sane count). Guards the dialog and the commit.
  bool get valid {
    if (teeth < (internal ? 3 : 4)) return false;
    if (module <= 0) return false;
    if (cornerRadius < 0) return false;
    if (pressureAngleDeg < 5 || pressureAngleDeg > 35) return false;
    if (rootRadius <= 0 || tipRadius <= 0) return false;
    if (internal) {
      // ring: the toothed inner boundary must sit inside the root ring
      if (tipRadius >= rootRadius) return false;
    } else {
      if (tipRadius <= rootRadius) return false;
    }
    return true;
  }

  // ---- codec: the values stored past the two defining vertices ----
  List<double> toBlock() => [
        module,
        teeth.toDouble(),
        pressureAngleDeg,
        profileShift,
        internal ? 1.0 : 0.0,
        bore,
        fillet ? 1.0 : 0.0,
        rootFilletCoef,
        tipRoundCoef,
        cornerRadius,
      ];

  static const blockLen = 10;

  static GearParams? fromBlock(List<double> b) {
    if (b.length < 6) return null; // tolerate pre-fillet blocks
    return GearParams(
      module: b[0],
      teeth: b[1].round(),
      pressureAngleDeg: b[2],
      profileShift: b[3],
      internal: b[4] != 0,
      bore: b[5],
      fillet: b.length > 6 ? b[6] != 0 : true,
      rootFilletCoef: b.length > 7 ? b[7] : 0.38,
      tipRoundCoef: b.length > 8 ? b[8] : 0.12,
      // appended in M63; absent in older sketches, where 0 = derive from the
      // coefficient exactly as before, so saved gears keep their shape.
      cornerRadius: b.length > 9 ? b[9] : 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'm': module,
        'z': teeth,
        'a': pressureAngleDeg,
        'x': profileShift,
        'int': internal,
        'bore': bore,
        'fil': fillet,
        'rfc': rootFilletCoef,
        'trc': tipRoundCoef,
        'cr': cornerRadius,
      };

  static GearParams fromJson(Map<String, dynamic> j) => GearParams(
        module: (j['m'] as num?)?.toDouble() ?? 2.0,
        teeth: (j['z'] as num?)?.toInt() ?? 20,
        pressureAngleDeg: (j['a'] as num?)?.toDouble() ?? 20.0,
        profileShift: (j['x'] as num?)?.toDouble() ?? 0.0,
        internal: j['int'] == true,
        bore: (j['bore'] as num?)?.toDouble() ?? 0.0,
        fillet: j['fil'] == null ? true : j['fil'] == true,
        rootFilletCoef: (j['rfc'] as num?)?.toDouble() ?? 0.38,
        tipRoundCoef: (j['trc'] as num?)?.toDouble() ?? 0.12,
        cornerRadius: (j['cr'] as num?)?.toDouble() ?? 0.0,
      );
}

double _inv(double a) => math.tan(a) - a;

/// The two defining points of a gearTag polyline: [center, orientation handle].
Offset gearCenter(Geo g) => Offset(g.data[2], g.data[3]);
Offset gearHandle(Geo g) => Offset(g.data[4], g.data[5]);

/// The parameter block stored past the two vertices, or null if malformed.
GearParams? gearParams(Geo g) {
  if (g.spline != Geo.gearTag) return null;
  // layout: [closed, count=2, cx, cy, hx, hy, <block...>]; the block is at
  // least the six original values (fillet fields tolerated as optional).
  if (g.data.length < 6 + 6) return null;
  return GearParams.fromBlock(g.data.sublist(6));
}

/// Orientation of the gear (radians): the direction from centre to handle.
double gearAngle(Geo g) {
  final c = gearCenter(g), h = gearHandle(g);
  final v = h - c;
  return v.distance < 1e-9 ? 0.0 : math.atan2(v.dy, v.dx);
}

/// Builds the compact gearTag polyline for [params], centred at [center] and
/// oriented at [angleRad] (tooth 0's centreline points this way, so the
/// rotation line to the handle points at the centre of tooth 0).
Geo buildGearGeo(Offset center, double angleRad, GearParams params,
    {String layer = kDefaultLayer}) {
  final rp = params.handleRadius;
  final handle = center + Offset(math.cos(angleRad), math.sin(angleRad)) * rp;
  return Geo(
    Geo.polyline,
    [
      1.0, // closed
      2.0, // count — the solver/grips/DXF see exactly these two points
      center.dx, center.dy,
      handle.dx, handle.dy,
      ...params.toBlock(),
    ],
    layer: layer,
    spline: Geo.gearTag,
    style: Geo.styleNormal,
  );
}

/// Canonical form: the handle is snapped back onto the pitch circle at its
/// current angle (its radial distance is a nuisance the solver/drag may nudge;
/// only its ANGLE means anything). Analogous to normalizedEllipse; called from
/// the single rebuild choke point so the stored handle never drifts off the
/// pitch radius. Returns [g] unchanged when it is not a valid gear.
Geo normalizedGear(Geo g) {
  final p = gearParams(g);
  if (p == null) return g;
  final c = gearCenter(g), h = gearHandle(g);
  final v = h - c;
  if (v.distance < 1e-9) return g; // degenerate: leave it, gearCurve falls back
  final ang = math.atan2(v.dy, v.dx);
  final rp = p.handleRadius;
  final hx = c.dx + math.cos(ang) * rp;
  final hy = c.dy + math.sin(ang) * rp;
  if ((hx - h.dx).abs() < 1e-9 && (hy - h.dy).abs() < 1e-9) return g;
  final d = List<double>.from(g.data);
  d[4] = hx;
  d[5] = hy;
  return g.withData(d);
}

/// The full baked tooth outline (a closed loop of points) for gearTag [g], in
/// world coordinates. This is the ONE place the involute geometry is realised;
/// render, snap, hit-test, 3D profiling and DXF baking all go through it.
///
/// Falls back to the two raw points if the parameters are missing/invalid so a
/// half-loaded or hand-edited entity can never throw inside the painter.
List<Offset> gearCurve(Geo g, {int flankSamples = 18}) {
  final p = gearParams(g);
  if (p == null || !p.valid) {
    return [gearCenter(g), gearHandle(g)];
  }
  final c = gearCenter(g), ang = gearAngle(g);
  // splineCurveFor() funnels EVERY paint, hit-test and snap query through here,
  // so without a cache the whole involute (z transcendental flank solves plus
  // 4z fillet constructions) was rebuilt many times per frame. The key is the
  // full geometric identity, so a dragged or re-parameterised gear misses and
  // rebuilds exactly once.
  final key = '${c.dx},${c.dy},$ang,$flankSamples,${p.signature}';
  final hit = _curveCache[key];
  if (hit != null) return hit;
  final curve = gearProfile(
    center: c,
    angle: ang,
    params: p,
    flankSamples: flankSamples,
  );
  if (_curveCache.length >= _curveCacheMax) _curveCache.clear();
  _curveCache[key] = curve;
  return curve;
}

/// Memo for [gearCurve]. Bounded and cleared wholesale — a sketch holds a
/// handful of gears, and dragging one only ever adds entries for that gear.
final Map<String, List<Offset>> _curveCache = {};
const int _curveCacheMax = 64;

/// Clears the gear outline memo. Only needed by tests that assert on rebuild
/// behaviour; normal code never has to invalidate, because the cache key is
/// the complete geometric identity of the gear.
void clearGearCurveCache() => _curveCache.clear();

/// Pure geometry: the closed involute outline for [params] centred at [center]
/// and rotated by [angle] (radians). Shared by [gearCurve] and the live dialog
/// preview so what you configure is exactly what lands in the sketch.
List<Offset> gearProfile({
  required Offset center,
  required double angle,
  required GearParams params,
  int flankSamples = 18,
}) {
  final z = params.teeth;
  final a = params.pressureAngleDeg * math.pi / 180.0;
  final r = params.pitchRadius;
  final rb = params.baseRadius;
  final ra = params.tipRadius;
  final rf = params.rootRadius;
  final internal = params.internal;
  final tanA = math.tan(a);
  final psiP = internal
      ? (math.pi / 2 - 2 * params.profileShift * tanA) / z
      : (math.pi / 2 + 2 * params.profileShift * tanA) / z;

  double psi(double rho) {
    final rr = rho < rb ? rb : rho;
    final ratio = (rb / rr).clamp(-1.0, 1.0);
    return psiP + _inv(a) - _inv(math.acos(ratio));
  }

  // the flank spans between the radius nearer the centre and the one farther:
  //   external: inner = root, outer = tip;  internal: inner = tip, outer = root
  final rIn = internal ? ra : rf;
  final rOut = internal ? rf : ra;
  final rLo = math.max(rb, rIn); // involute is only defined for ρ ≥ rb
  final belowBase = rIn < rb - 1e-9; // a short radial root fillet is needed
  final psiRoot = psi(rLo); // half angle at the inner (crest/root) end

  // Preview callers pass a low [flankSamples]; keep honouring that intent by
  // loosening the flank tolerance instead of thinning a polyline.
  final flankTol = flankSamples <= 12 ? 1e-2 : _flankTolMm;

  // ABSOLUTE-angle polar point translated to the gear centre.
  Offset at(double rho, double absAngle) => Offset(
        center.dx + rho * math.cos(absAngle),
        center.dy + rho * math.sin(absAngle),
      );

  // Exact involute point on the flank of the tooth centred at angle c.
  Offset invPt(double c, double sign, double rho) =>
      at(rho, c + sign * psi(rho));

  // One flank of the tooth centred at angle c: inner→outer at ±psi (outward),
  // reversed for outer→inner.
  //
  // The involute is NOT a circle, so sampling it as a polyline used to hand the
  // kernel ~18 straight edges per side (36 per tooth) — the dominant cost of an
  // extruded gear. Instead the flank is approximated by the FEWEST circular
  // arcs that stay within [flankTol] of the exact involute, and the points we
  // emit lie EXACTLY on those arcs. arcFitLoop (part_model.dart) then recovers
  // each arc as ONE exact bulge edge, so the B-Rep gets true cylindrical faces
  // instead of a facet fan. The refit is lossless by construction rather than a
  // guess: we choose the arcs, then sample them.
  List<Offset> flank(double c, double sign, bool outward) {
    final seq = <Offset>[];
    if (belowBase) seq.add(at(rIn, c + sign * psi(rb)));
    // dense exact involute reference used to size and check the arc chain
    const dense = 64;
    final ex = [
      for (var i = 0; i <= dense; i++)
        invPt(c, sign, rLo + (rOut - rLo) * i / dense)
    ];
    final bounds = _greedySpans(ex, flankTol, _maxFlankArcs);
    for (var k = 0; k + 1 < bounds.length; k++) {
      final i0 = bounds[k], i1 = bounds[k + 1];
      final pts = _arcSamples(ex[i0], ex[(i0 + i1) ~/ 2], ex[i1], _flankArcPts);
      // consecutive arcs share a vertex; drop the duplicate
      seq.addAll(k == 0 ? pts : pts.sublist(1));
    }
    return outward ? seq : seq.reversed.toList();
  }

  // an arc at radius rho from absolute angle a0 to a1 (a1 bumped +2π if behind),
  // INCLUSIVE of both endpoints so the fillet routine can see the corner.
  List<Offset> arc(double rho, double a0, double a1, int steps) {
    var hi = a1;
    if (hi < a0) hi += 2 * math.pi;
    return [
      for (var i = 0; i <= steps; i++) at(rho, a0 + (hi - a0) * i / steps)
    ];
  }

  // automatic tooth radii (Inventor rounds these too): a root fillet blending
  // the flank into the root, and a small round on the tip corners.
  final rootR = params.fillet ? params.rootFilletRadius : 0.0;
  final tipR = params.fillet ? params.tipRoundRadius : 0.0;

  final pitch = 2 * math.pi / z;
  final poOuter = psi(rOut);
  final gapR = belowBase ? rIn : rLo;

  // The outline as a cyclic sequence of FEATURES, each an open polyline that
  // ends where the next begins. Fillets are applied afterwards by trimming the
  // two adjacent features back to their tangent points — the previous code
  // inserted a fillet between untrimmed features and capped its setback at
  // 0.48x the neighbouring CHORD, which pinned every fillet to sub-chord size
  // and made the corner radius have no effect on the shape at all.
  final features = <List<Offset>>[];
  final radii = <double>[]; // fillet radius at the join FOLLOWING each feature
  for (var i = 0; i < z; i++) {
    final c = angle + i * pitch;
    final nc = angle + ((i + 1) % z) * pitch;
    features.add(flank(c, -1, true)); // right flank inner → outer
    radii.add(tipR);
    features.add(arc(rOut, c - poOuter, c + poOuter, 4)); // crest
    radii.add(tipR);
    features.add(flank(c, 1, false)); // left flank outer → inner
    radii.add(rootR);
    features.add(arc(gapR, c + psiRoot, nc - psiRoot, 6)); // root gap
    radii.add(rootR);
  }
  return _filletChain(features, radii);
}

/// Joins the cyclic [features] (each ending where the next begins) into one
/// closed loop, rounding every junction with a circular fillet of the matching
/// [radii] entry. Each fillet trims BOTH neighbours back to its tangent points,
/// measured along the feature, so a radius larger than one tessellation chord
/// works exactly as asked. A radius of 0 — or one the neighbours are too short
/// to accommodate — leaves a sharp corner.
List<Offset> _filletChain(List<List<Offset>> features, List<double> radii) {
  final n = features.length;
  // setback along the feature ENDING at join j, and along the one STARTING there
  final backOf = List<double>.filled(n, 0.0);
  final fwdOf = List<double>.filled(n, 0.0);
  final arcOf = List<List<Offset>>.filled(n, const []);

  for (var j = 0; j < n; j++) {
    final a = features[j], b = features[(j + 1) % n];
    final r = radii[j];
    if (r <= 1e-9 || a.length < 2 || b.length < 2) continue;
    final v = a.last;
    // tangents at the corner, from the adjoining chords
    final e1 = _unit(a[a.length - 2] - v); // back along the incoming feature
    final e2 = _unit(b[1] - v); //           forward along the outgoing one
    if (e1 == null || e2 == null) continue;
    final dot0 = (e1.dx * e2.dx + e1.dy * e2.dy).clamp(-1.0, 1.0);
    final half0 = math.acos(dot0) / 2;
    if (half0 < 1e-3 || half0 > math.pi / 2 - 1e-3) continue;
    // Never eat more than 45% of either neighbour: two fillets share a feature
    // (one at each end), so this keeps them from meeting in the middle. Clamp
    // the RADIUS to what that budget allows rather than clamping the setback
    // later — a setback clipped after the fact no longer matches the radius the
    // arc was built with, which is exactly what leaves a kink at the join.
    final capA = 0.45 * _polyLen(a), capB = 0.45 * _polyLen(b);
    final rFit = math.min(r, math.min(capA, capB) * math.tan(half0));
    if (rFit <= 1e-9) continue;
    var sa = rFit / math.tan(half0);
    var sb = sa;
    if (sa < 1e-9) continue;

    // The neighbours are CURVED, so a fillet built from the tangents AT THE
    // CORNER is not tangent where it actually meets them — for a radius of any
    // real size that leaves a visible kink. Converge instead: take the tangent
    // lines at the current tangent points, intersect them for the true corner,
    // and correct both setbacks. Half a dozen passes is plenty.
    Offset? o;
    Offset pa = v, pb = v;
    var rEff = 0.0, half = half0;
    var ok = false;
    for (var it = 0; it < 8; it++) {
      pa = _alongFromEnd(a, sa);
      pb = _alongFromStart(b, sb);
      final ta = _tangentFromEnd(a, sa); // forward along a, at pa
      final tb = _tangentFromStart(b, sb); // forward along b, at pb
      if (ta == null || tb == null) break;
      final vv = _lineIntersect(pa, ta, pb, tb);
      if (vv == null) break;
      final f1 = Offset(-ta.dx, -ta.dy), f2 = tb;
      final d = (f1.dx * f2.dx + f1.dy * f2.dy).clamp(-1.0, 1.0);
      half = math.acos(d) / 2;
      if (half < 1e-3 || half > math.pi / 2 - 1e-3) break;
      final need = rFit / math.tan(half);
      final da = (vv - pa).distance, db = (vv - pb).distance;
      final na = (sa + (need - da)).clamp(1e-9, capA);
      final nb = (sb + (need - db)).clamp(1e-9, capB);
      final moved = (na - sa).abs() + (nb - sb).abs();
      sa = na;
      sb = nb;
      rEff = math.min(need, math.min(da, db)) * math.tan(half);
      final bis = _unit(f1 + f2);
      if (bis == null) break;
      o = vv + bis * (rEff / math.sin(half));
      ok = true;
      if (moved < 1e-10) break;
    }
    if (!ok || o == null || rEff < 1e-9) continue;
    pa = _alongFromEnd(a, sa);
    pb = _alongFromStart(b, sb);
    // snap the endpoints onto the fillet circle so the join is exactly closed
    final oc = o;
    pa = oc + (_unit(pa - oc) ?? const Offset(1, 0)) * rEff;
    pb = oc + (_unit(pb - oc) ?? const Offset(1, 0)) * rEff;
    var a0 = math.atan2(pa.dy - oc.dy, pa.dx - oc.dx);
    final a1 = math.atan2(pb.dy - oc.dy, pb.dx - oc.dx);
    var d = a1 - a0;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    const steps = 6;
    backOf[j] = sa;
    fwdOf[j] = sb;
    arcOf[j] = [
      for (var i = 0; i <= steps; i++)
        Offset(oc.dx + rEff * math.cos(a0 + d * i / steps),
            oc.dy + rEff * math.sin(a0 + d * i / steps))
    ];
  }

  final out = <Offset>[];
  for (var f = 0; f < n; f++) {
    // trim this feature by the fillet at its START (join f-1) and its END (f)
    final startCut = fwdOf[(f - 1 + n) % n];
    final endCut = backOf[f];
    final body = _trimPoly(features[f], startCut, endCut);
    for (final p in body) {
      if (out.isEmpty || (out.last - p).distance > 1e-9) out.add(p);
    }
    for (final p in arcOf[f]) {
      if (out.isEmpty || (out.last - p).distance > 1e-9) out.add(p);
    }
  }
  // close: drop a final point coincident with the first
  while (out.length > 1 && (out.first - out.last).distance < 1e-9) {
    out.removeLast();
  }
  return out;
}

/// Forward unit tangent of [p] at arc length [s] measured back from its end.
Offset? _tangentFromEnd(List<Offset> p, double s) {
  var rem = s;
  for (var i = p.length - 1; i > 0; i--) {
    final seg = (p[i] - p[i - 1]).distance;
    if (rem <= seg) return _unit(p[i] - p[i - 1]);
    rem -= seg;
  }
  return p.length > 1 ? _unit(p[1] - p[0]) : null;
}

/// Forward unit tangent of [p] at arc length [s] measured from its start.
Offset? _tangentFromStart(List<Offset> p, double s) {
  var rem = s;
  for (var i = 0; i + 1 < p.length; i++) {
    final seg = (p[i + 1] - p[i]).distance;
    if (rem <= seg) return _unit(p[i + 1] - p[i]);
    rem -= seg;
  }
  return p.length > 1 ? _unit(p[p.length - 1] - p[p.length - 2]) : null;
}

/// Intersection of the line through [p1] with direction [d1] and the line
/// through [p2] with direction [d2]; null when they are (near) parallel.
Offset? _lineIntersect(Offset p1, Offset d1, Offset p2, Offset d2) {
  final den = d1.dx * d2.dy - d1.dy * d2.dx;
  if (den.abs() < 1e-12) return null;
  final t = ((p2.dx - p1.dx) * d2.dy - (p2.dy - p1.dy) * d2.dx) / den;
  if (!t.isFinite) return null;
  return Offset(p1.dx + d1.dx * t, p1.dy + d1.dy * t);
}

Offset? _unit(Offset v) {
  final l = v.distance;
  return l < 1e-12 ? null : Offset(v.dx / l, v.dy / l);
}

double _polyLen(List<Offset> p) {
  var s = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    s += (p[i + 1] - p[i]).distance;
  }
  return s;
}

/// Point at arc length [s] measured back from the end of [p].
Offset _alongFromEnd(List<Offset> p, double s) {
  var rem = s;
  for (var i = p.length - 1; i > 0; i--) {
    final seg = (p[i] - p[i - 1]).distance;
    if (rem <= seg) {
      final f = seg < 1e-12 ? 0.0 : rem / seg;
      return p[i] + (p[i - 1] - p[i]) * f;
    }
    rem -= seg;
  }
  return p.first;
}

/// Point at arc length [s] measured forward from the start of [p].
Offset _alongFromStart(List<Offset> p, double s) {
  var rem = s;
  for (var i = 0; i + 1 < p.length; i++) {
    final seg = (p[i + 1] - p[i]).distance;
    if (rem <= seg) {
      final f = seg < 1e-12 ? 0.0 : rem / seg;
      return p[i] + (p[i + 1] - p[i]) * f;
    }
    rem -= seg;
  }
  return p.last;
}

/// [p] with [head] of arc length removed from its start and [tail] from its
/// end, keeping the exact cut points as the new endpoints.
List<Offset> _trimPoly(List<Offset> p, double head, double tail) {
  if (head <= 1e-12 && tail <= 1e-12) return p;
  final total = _polyLen(p);
  if (head + tail >= total - 1e-12) {
    // nothing of the feature survives: collapse to the single mid point
    return [_alongFromStart(p, total / 2)];
  }
  final a = head > 1e-12 ? _alongFromStart(p, head) : p.first;
  final b = tail > 1e-12 ? _alongFromEnd(p, tail) : p.last;
  // keep the interior vertices strictly between the two cuts
  var acc = 0.0;
  final mid = <Offset>[];
  for (var i = 0; i + 1 < p.length; i++) {
    acc += (p[i + 1] - p[i]).distance;
    if (acc > head + 1e-12 && acc < total - tail - 1e-12) mid.add(p[i + 1]);
  }
  return [a, ...mid, b];
}


/// Resamples the densely sampled curve [dense] onto a chain of TRUE circular
/// arcs that stays within [tolMm] of it, returning points that lie EXACTLY on
/// those arcs.
///
/// This is the same treatment the gear flank gets, exposed because a spline
/// needs it for the identical reason: sampled as a plain polyline it reaches
/// the kernel as a fan of PLANAR facets, so an extruded spline is a prism of
/// flat strips. Each strip boundary is a real crease, so the v9 tangent filter
/// cannot remove it and the surface stays visibly faceted. Points on arcs
/// instead give arcFitLoop exact bulges, the prism gets cylindrical faces, and
/// consecutive faces are near-tangent so the filter hides the joins.
List<Offset> arcChainResample(List<Offset> dense,
    {double tolMm = 5e-3, int maxArcs = 64, int ptsPerArc = _flankArcPts}) {
  if (dense.length < 4) return dense;
  final bounds = _greedySpans(dense, tolMm, maxArcs);
  final out = <Offset>[];
  for (var k = 0; k + 1 < bounds.length; k++) {
    final i0 = bounds[k], i1 = bounds[k + 1];
    if (i1 - i0 < 2) continue;
    final pts = _arcSamples(dense[i0], dense[(i0 + i1) ~/ 2], dense[i1], ptsPerArc);
    for (final q in pts) {
      if (out.isEmpty || (out.last - q).distance > 1e-9) out.add(q);
    }
  }
  return out.length < 4 ? dense : out;
}

// ---------------------------------------------------------------------------
// involute → circular-arc chain
// ---------------------------------------------------------------------------

/// Max deviation (mm) an arc chain may have from the exact involute flank.
/// 1e-3 mm = 1 µm, far below anything a gear tolerance class cares about and
/// two orders below the kernel's own modelling tolerance.
const double _flankTolMm = 1e-3;

/// Never spend more than this many arcs on one flank (guards pathological
/// parameter combinations); 8 arcs reach ~0.1 µm on every profile measured.
const int _maxFlankArcs = 8;

/// Vertices emitted per flank arc. Four chords is one more than arcFitLoop's
/// minimum run (3), so an arc is always recoverable with margin to spare.
const int _flankArcPts = 5;

/// Centre and radius of the circle through three points, or null if collinear.
(Offset, double)? _circleThrough(Offset a, Offset b, Offset c) {
  final d =
      2 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
  if (d.abs() < 1e-14) return null;
  final a2 = a.dx * a.dx + a.dy * a.dy;
  final b2 = b.dx * b.dx + b.dy * b.dy;
  final c2 = c.dx * c.dx + c.dy * c.dy;
  final o = Offset(
      (a2 * (b.dy - c.dy) + b2 * (c.dy - a.dy) + c2 * (a.dy - b.dy)) / d,
      (a2 * (c.dx - b.dx) + b2 * (a.dx - c.dx) + c2 * (b.dx - a.dx)) / d);
  return (o, (a - o).distance);
}

/// Largest radial error when the span [i0]..[i1] of the dense exact curve [ex]
/// is replaced by the circle through its first, middle and last point.
double _spanDeviation(List<Offset> ex, int i0, int i1) {
  if (i1 - i0 < 2) return double.infinity;
  final fit = _circleThrough(ex[i0], ex[(i0 + i1) ~/ 2], ex[i1]);
  if (fit == null) return double.infinity;
  final (o, r) = fit;
  var worst = 0.0;
  for (var i = i0; i <= i1; i++) {
    final e = ((ex[i] - o).distance - r).abs();
    if (e > worst) worst = e;
  }
  return worst;
}

/// Span boundaries of the FEWEST arcs covering [ex] within [tol]. Each arc is
/// extended as far as the tolerance allows (binary search on the end index,
/// valid because the deviation grows monotonically with span length), which
/// needs noticeably fewer arcs than cutting the flank into equal pieces.
List<int> _greedySpans(List<Offset> ex, double tol, int maxArcs) {
  final dense = ex.length - 1;
  final bounds = <int>[0];
  var i0 = 0;
  while (i0 < dense) {
    if (bounds.length > maxArcs) {
      bounds.add(dense); // budget spent: one last arc covers the remainder
      break;
    }
    var lo = i0 + 2, hi = dense, best = math.min(i0 + 2, dense);
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_spanDeviation(ex, i0, mid) <= tol) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (best <= i0) best = math.min(i0 + 2, dense);
    bounds.add(best);
    i0 = best;
  }
  if (bounds.last != dense) bounds.add(dense);
  return bounds;
}

/// [count] points evenly spaced ON the circular arc that runs from [a] through
/// [m] to [b], inclusive of both ends. Falls back to the straight chord when
/// the three points are collinear, which stays correct (a straight flank
/// segment is a legitimate degenerate case) instead of throwing.
List<Offset> _arcSamples(Offset a, Offset m, Offset b, int count) {
  final fit = _circleThrough(a, m, b);
  if (fit == null) {
    return [
      for (var i = 0; i < count; i++)
        Offset(a.dx + (b.dx - a.dx) * i / (count - 1),
            a.dy + (b.dy - a.dy) * i / (count - 1))
    ];
  }
  final (o, r) = fit;
  final a0 = math.atan2(a.dy - o.dy, a.dx - o.dx);
  final am = math.atan2(m.dy - o.dy, m.dx - o.dx);
  final a1 = math.atan2(b.dy - o.dy, b.dx - o.dx);
  // sweep a0→a1 taking the branch that actually passes through m
  double norm(double d) {
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  final dm = norm(am - a0);
  var d = norm(a1 - a0);
  if (dm != 0 && d.sign != dm.sign) d += (dm > 0 ? 2 : -2) * math.pi;
  return [
    for (var i = 0; i < count; i++)
      Offset(o.dx + r * math.cos(a0 + d * i / (count - 1)),
          o.dy + r * math.sin(a0 + d * i / (count - 1)))
  ];
}


// ---------------------------------------------------------------------------
// planetary (epicyclic) gear sets (M61)
// ---------------------------------------------------------------------------
/// One member of a planetary set: the parameters plus where and how it sits.
class PlanetPlacement {
  final GearParams params;
  final Offset center; // relative to the system centre
  final double angle; // orientation (radians), tooth 0 direction
  final String role; // 'sun' | 'planet' | 'ring'
  const PlanetPlacement(this.params, this.center, this.angle, this.role);
}

/// A fully-specified planetary layout: sun + N planets + ring, phased so the
/// teeth mesh. All geometry is relative to a system centre at (0,0) rotated by
/// [systemAngle]; the caller translates it to where the user placed it.
class PlanetaryLayout {
  final List<PlanetPlacement> members;
  final int ringTeeth;
  final double centerDistance; // sun↔planet
  final bool assemblyOk; // equal spacing + meshing is exact
  final List<double> planetCarrierAngles; // absolute angles of planet centres
  const PlanetaryLayout(this.members, this.ringTeeth, this.centerDistance,
      this.assemblyOk, this.planetCarrierAngles);

  /// Radius the planet centres sit on. Identical to [centerDistance] by
  /// construction — buildPlanetaryLayout places every planet at
  /// `a·(cos φ, sin φ)` where `a` IS the sun↔planet centre distance. It is
  /// therefore derived, not stored: as a final field it was never initialised
  /// by the constructor, which failed compilation of the whole library and
  /// with it every test that imports the app (CI run #168: 44 failures from
  /// this one line).
  double get carrierRadius => centerDistance;

  PlanetPlacement get sun => members.firstWhere((m) => m.role == 'sun');
  PlanetPlacement get ring => members.firstWhere((m) => m.role == 'ring');
  Iterable<PlanetPlacement> get planets =>
      members.where((m) => m.role == 'planet');
}

/// The ring tooth count implied by a sun/planet pair (standard equal-module
/// epicyclic relation z_ring = z_sun + 2·z_planet).
int planetaryRingTeeth(int sunTeeth, int planetTeeth) =>
    sunTeeth + 2 * planetTeeth;

/// True when [n] equally-spaced planets can be assembled AND mesh
/// (the classic condition (z_sun + z_ring) divisible by n).
bool planetaryAssembles(int sunTeeth, int planetTeeth, int n) {
  if (n < 2) return false;
  final zr = planetaryRingTeeth(sunTeeth, planetTeeth);
  return (sunTeeth + zr) % n == 0;
}

/// Builds a meshing planetary layout. [base] supplies module / pressure angle /
/// profile shift / fillet settings (its `teeth`/`internal` are ignored — each
/// member gets its own). Planets are equally spaced; each gear is phased so its
/// teeth mesh with its neighbours (a tooth of one sits in a space of the other
/// along every line of centres).
PlanetaryLayout buildPlanetaryLayout({
  required GearParams base,
  required int sunTeeth,
  required int planetTeeth,
  required int planetCount,
  double systemAngle = 0.0,
}) {
  final m = base.module;
  final zr = planetaryRingTeeth(sunTeeth, planetTeeth);
  final a = m * (sunTeeth + planetTeeth) / 2.0; // centre distance
  final tp = 2 * math.pi / planetTeeth;
  final theta = systemAngle;

  GearParams mk(int z, bool internal) => GearParams(
        module: m,
        teeth: z,
        pressureAngleDeg: base.pressureAngleDeg,
        profileShift: base.profileShift,
        internal: internal,
        bore: internal ? 0.0 : base.bore,
        fillet: base.fillet,
        rootFilletCoef: base.rootFilletCoef,
        tipRoundCoef: base.tipRoundCoef,
      );

  final members = <PlanetPlacement>[];
  final carrierAngles = <double>[];
  // sun: tooth 0 at the system angle
  members.add(PlanetPlacement(mk(sunTeeth, false), Offset.zero, theta, 'sun'));
  // planets: equally spaced; a tooth SPACE faces the sun so it meshes
  for (var i = 0; i < planetCount; i++) {
    final phi = theta + i * (2 * math.pi / planetCount);
    carrierAngles.add(phi);
    final c = Offset(a * math.cos(phi), a * math.sin(phi));
    final thp = phi + math.pi - 0.5 * tp; // space toward the sun
    members.add(PlanetPlacement(mk(planetTeeth, false), c, thp, 'planet'));
  }
  // ring: internal, aligned so its inward teeth mesh with the planet spaces
  members.add(PlanetPlacement(mk(zr, true), Offset.zero, theta, 'ring'));

  return PlanetaryLayout(members, zr, a,
      planetaryAssembles(sunTeeth, planetTeeth, planetCount), carrierAngles);
}
