// iPadProCAD — parametric involute gear generator (M61).
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
      );

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

  /// True when these values can actually be drawn (a positive tooth with a
  /// sane count). Guards the dialog and the commit.
  bool get valid {
    if (teeth < (internal ? 3 : 4)) return false;
    if (module <= 0) return false;
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
      ];

  static const blockLen = 9;

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
  return gearProfile(
    center: gearCenter(g),
    angle: gearAngle(g),
    params: p,
    flankSamples: flankSamples,
  );
}

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
  final n = flankSamples < 4 ? 4 : flankSamples;

  // ABSOLUTE-angle polar point translated to the gear centre.
  Offset at(double rho, double absAngle) => Offset(
        center.dx + rho * math.cos(absAngle),
        center.dy + rho * math.sin(absAngle),
      );

  // one flank of the tooth centred at angle c: inner→outer at ±psi (outward),
  // reversed for outer→inner.
  List<Offset> flank(double c, double sign, bool outward) {
    final seq = <Offset>[];
    if (belowBase) seq.add(at(rIn, c + sign * psi(rb)));
    for (var i = 0; i < n; i++) {
      final rho = rLo + (rOut - rLo) * i / (n - 1);
      seq.add(at(rho, c + sign * psi(rho)));
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
  final rootR = params.fillet ? params.rootFilletCoef * params.module : 0.0;
  final tipR = params.fillet ? params.tipRoundCoef * params.module : 0.0;

  final pts = <Offset>[];
  final pitch = 2 * math.pi / z;
  final poOuter = psi(rOut);
  final gapR = belowBase ? rIn : rLo;
  for (var i = 0; i < z; i++) {
    final c = angle + i * pitch;
    final nc = angle + ((i + 1) % z) * pitch;
    final rfr = flank(c, -1, true); // right flank inner → outer
    final crest = arc(rOut, c - poOuter, c + poOuter, 4);
    final lf = flank(c, 1, false); // left flank outer → inner
    final gap = arc(gapR, c + psiRoot, nc - psiRoot, 6);
    final nextRfr0 = flank(nc, -1, true).first; // next tooth's flank start
    // fillet arcs at the four corners of this tooth's span
    final tipA = _roundCorner(rfr[rfr.length - 2], rfr.last, crest[1], tipR);
    final tipB = _roundCorner(crest[crest.length - 2], crest.last, lf[1], tipR);
    final rootL = _roundCorner(lf[lf.length - 2], lf.last, gap[1], rootR);
    final rootN = _roundCorner(gap[gap.length - 2], gap.last, nextRfr0, rootR);
    // assemble (each fillet replaces its sharp corner vertex)
    pts.addAll(rfr.sublist(0, rfr.length - 1));
    pts.addAll(tipA);
    pts.addAll(crest.sublist(1, crest.length - 1));
    pts.addAll(tipB);
    pts.addAll(lf.sublist(1, lf.length - 1));
    pts.addAll(rootL);
    pts.addAll(gap.sublist(1, gap.length - 1));
    pts.addAll(rootN);
  }
  return pts;
}

/// Circular fillet of radius [r] tangent to the segment [pIn]→[v] and [v]→[pOut],
/// returned as a short poly-arc from the first tangent point to the second.
/// Returns just [v] when the radius is zero or the corner is (near) straight or
/// degenerate — so a fillet-off gear falls back to sharp corners for free.
List<Offset> _roundCorner(Offset pIn, Offset v, Offset pOut, double r,
    {int steps = 6}) {
  if (r <= 1e-9) return [v];
  final ax = v.dx - pIn.dx, ay = v.dy - pIn.dy;
  final bx = pOut.dx - v.dx, by = pOut.dy - v.dy;
  final la = math.sqrt(ax * ax + ay * ay), lb = math.sqrt(bx * bx + by * by);
  if (la < 1e-9 || lb < 1e-9) return [v];
  final e1 = Offset(-ax / la, -ay / la); // from v back along the incoming edge
  final e2 = Offset(bx / lb, by / lb); //   from v along the outgoing edge
  final dot = (e1.dx * e2.dx + e1.dy * e2.dy).clamp(-1.0, 1.0);
  final half = math.acos(dot) / 2; // half the interior angle at the corner
  if (half < 1e-3 || half > math.pi / 2 - 1e-3) return [v];
  var t = r / math.tan(half); // setback from the corner along each edge
  t = math.min(t, math.min(0.48 * la, 0.48 * lb));
  final rEff = t * math.tan(half);
  final a = Offset(v.dx + e1.dx * t, v.dy + e1.dy * t);
  var bis = Offset(e1.dx + e2.dx, e1.dy + e2.dy);
  final lbis = bis.distance;
  if (lbis < 1e-9) return [v];
  bis = Offset(bis.dx / lbis, bis.dy / lbis);
  final dist = rEff / math.sin(half); // corner → arc centre
  final o = Offset(v.dx + bis.dx * dist, v.dy + bis.dy * dist);
  final b = Offset(v.dx + e2.dx * t, v.dy + e2.dy * t);
  var a0 = math.atan2(a.dy - o.dy, a.dx - o.dx);
  final a1 = math.atan2(b.dy - o.dy, b.dx - o.dx);
  var d = a1 - a0;
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d < -math.pi) {
    d += 2 * math.pi;
  }
  return [
    for (var i = 0; i <= steps; i++)
      Offset(o.dx + rEff * math.cos(a0 + d * i / steps),
          o.dy + rEff * math.sin(a0 + d * i / steps))
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
