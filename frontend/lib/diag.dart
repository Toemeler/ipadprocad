// Prototype — diagnostic formatting for the log.
//
// The point of these dumps is REPRODUCIBILITY: a dump must contain enough to
// rebuild the exact sketch (geometry + constraints) off-device and replay the
// failing solve. Keep the format terse and machine-readable.
//
// Lives apart from log.dart so the logger itself stays dependency-free and can
// run before anything else is initialised.
import 'dart:math' as math;

import 'constraints.dart';
import 'ffi/qcad_engine.dart' show Geo;
import 'snap.dart';

String _n(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v.isNegative ? '-Inf' : 'Inf';
  return v.toStringAsFixed(4);
}

String geoKind(Geo g) => switch (g.type) {
      Geo.line => 'line',
      Geo.circle => 'circle',
      Geo.arc => 'arc',
      Geo.polyline => 'polyline',
      _ => 'type${g.type}',
    };

/// True when every parameter of [g] is a real, finite number. A false here is
/// the difference between "the sketch looks wrong" and "the sketch is garbage
/// and Skia silently drops it" — which is what makes geometry vanish.
bool geoFinite(Geo g) {
  for (final v in g.data) {
    if (!v.isFinite) return false;
  }
  if (g.type == Geo.circle && g.data.length > 2 && g.data[2] <= 0) return false;
  if (g.type == Geo.arc && g.data.length > 2 && g.data[2] <= 0) return false;
  return true;
}

bool allFinite(List<Geo> gs) => gs.every(geoFinite);

String geoStr(int i, Geo g) =>
    '[$i] ${geoKind(g)} data=[${g.data.map(_n).join(', ')}]'
    '${geoFinite(g) ? '' : '   <<< NOT FINITE'}';

String ptRefStr(PRef p) =>
    p.ent == kProjCenter ? 'projCP' : 'e${p.ent}.p${p.pt}';

String conStr(int i, Constraint c) {
  final b = StringBuffer('[$i] ${c.type.name}');
  if (c.dimKind != null) b.write('/${c.dimKind}');
  if (c.pts.isNotEmpty) b.write(' pts=${c.pts.map(ptRefStr).join(',')}');
  if (c.ents.isNotEmpty) b.write(' ents=${c.ents.join(',')}');
  if (c.value != null) b.write(' value=${_n(c.value!)}');
  if (c.anchors.isNotEmpty) b.write(' anchors=[${c.anchors.map(_n).join(',')}]');
  if (c.driven) b.write(' DRIVEN');
  return b.toString();
}

/// Everything needed to replay the sketch off-device.
List<String> sketchDump(List<Geo> gs, List<Constraint> cs) => [
      'geometry (${gs.length}):',
      for (var i = 0; i < gs.length; i++) '  ${geoStr(i, gs[i])}',
      'constraints (${cs.length}):',
      for (var i = 0; i < cs.length; i++) '  ${conStr(i, cs[i])}',
    ];

/// A grip, plus the thing it actually refers to — the two disagree more often
/// than you would like (a circle owns ONE point but FOUR radius grips, so
/// grip.idx is only a point index while idx < ptCount).
String gripStr(Grip g, List<Geo> gs) {
  final owner = (g.entity >= 0 && g.entity < gs.length) ? gs[g.entity] : null;
  final pc = owner == null ? -1 : ptCount(owner);
  return 'grip(entity=${g.entity} idx=${g.idx} kind=${g.kind} '
      'pos=(${_n(g.pos.dx)},${_n(g.pos.dy)})) '
      'owner=${owner == null ? 'NONE' : geoKind(owner)} ptCount=$pc '
      'isPointRef=${pc >= 0 && g.idx < pc}';
}

/// Why a solve failed, named down to the individual constraint.
///
/// A failing solve used to log one line — "unsatisfied — sketch left
/// unchanged" — which says a sketch is broken without saying where, and left
/// every 2D report needing a round trip to ask which constraint. [resid] comes
/// from `constraintResidualsPer`, parallel to [cs].
///
/// Worst first, because a contradictory system usually has ONE constraint
/// carrying almost all of the error and a tail of innocent ones absorbing the
/// rest. Anything under [tol] is holding and is not listed.
List<String> solveFailureDump(
  List<Geo> gs,
  List<Constraint> cs,
  List<double> resid, {
  double tol = 1e-6,
  int maxNamed = 12,
}) {
  final idx = <int>[
    for (var i = 0; i < cs.length && i < resid.length; i++)
      if (resid[i] > tol) i
  ]..sort((a, b) => resid[b].compareTo(resid[a]));

  final out = <String>[
    'UNSATISFIED: ${idx.length} of ${cs.length} constraints are not held '
        '(tol=${_n(tol)})',
  ];
  if (idx.isEmpty) {
    // Every constraint holds, so the rejection came from the OTHER gate:
    // degenerate geometry. Say so rather than printing an empty list, which
    // reads like "nothing is wrong" next to a failure.
    out.add('  ...but every constraint is within tolerance — the solve was '
        'rejected for DEGENERATE GEOMETRY, not for a violated constraint. '
        'Look for the zero-length line / zero-radius arc below.');
  }
  for (final i in idx.take(maxNamed)) {
    out.add('  worst[${idx.indexOf(i)}] resid=${_n(resid[i])}  '
        '${conStr(i, cs[i])}');
    // The entities a violated constraint actually names, so the reader does
    // not have to cross-reference indices by hand.
    for (final p in cs[i].pts) {
      if (p.ent >= 0 && p.ent < gs.length) {
        out.add('      ${ptRefStr(p)} -> ${geoStr(p.ent, gs[p.ent])}');
      }
    }
    for (final e in cs[i].ents) {
      if (e >= 0 && e < gs.length) out.add('      ${geoStr(e, gs[e])}');
    }
  }
  if (idx.length > maxNamed) {
    out.add('  ...and ${idx.length - maxNamed} more');
  }
  final degenerate = <String>[
    for (var i = 0; i < gs.length; i++)
      if (!geoFinite(gs[i])) geoStr(i, gs[i])
  ];
  if (degenerate.isNotEmpty) {
    out.add('NON-FINITE entities (${degenerate.length}):');
    for (final d in degenerate) {
      out.add('  $d');
    }
  }
  return out;
}

/// Largest absolute coordinate — a cheap "did the sketch explode" probe.
double maxAbs(List<Geo> gs) {
  var m = 0.0;
  for (final g in gs) {
    for (final v in g.data) {
      if (v.isFinite) m = math.max(m, v.abs());
    }
  }
  return m;
}
