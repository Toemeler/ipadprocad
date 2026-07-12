// iPadProCAD — diagnostic formatting for the log.
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
