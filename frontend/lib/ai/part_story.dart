/// ISSUE #89 — the timeline said in words, in the world the ops work in.
///
/// The assistant's document context carried the part as its SAVE FORMAT:
/// sketch frames as twelve bare numbers, profile centroids in each sketch's
/// own coordinates, `vis`, `cube`, `imate`, `seqNext` — and on an extrusion
/// whose extent is "to face", the stale distance `a: 5.0` that the extent
/// ignores. The model read that and spent a whole round on it: "the feet are
/// 5 mm high … area 18.5 mm² over 310 mm ≈ 0.06 mm wide? That can't be …
/// the profile y=339.7 > 310 — inconsistent". The feet were 8 mm wedges
/// running the full 310 mm. Nothing it was given said so in any form it
/// could read without doing the rebuild in its head.
///
/// This is the same timeline, one line per step, every position in world
/// millimetres and every direction as a world axis. It says what a step DID
/// — where its sketch is drawn, which way and how far it went, where its own
/// body reaches — and drops everything that is bookkeeping.
library;

import 'dart:ui' show Offset;

import '../ffi/qcad_engine.dart' show Geo;
import '../part_model.dart';
import '../snap.dart' show sampleEntity;
import 'ai_view_marks.dart' show faceSpan;

/// One line per sketch and feature, in timeline order. [profiles] counts a
/// sketch's closed regions (the app's own region finder, so the number is
/// the one extrude sees).
List<String> partStory(PartModel p,
    {required int Function(ChildSketch) profiles, int max = 60}) {
  final steps = <(int, String)>[
    for (final cs in p.childSketches) (cs.seq, _sketchLine(cs, profiles(cs))),
    for (final f in p.features) (f.seq, _featureLine(p, f)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final lines = [
    for (final s in steps.take(max))
      s.$2.length > 400 ? '${s.$2.substring(0, 399)}…' : s.$2
  ];
  if (steps.length > max) lines.add('… ${steps.length - max} more step(s)');
  return lines;
}

String _num(double v) {
  final r = (v * 100).roundToDouble() / 100;
  final t = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
  return t == '-0' ? '0' : t;
}

/// "the plane x=0" for a plane square to an axis, else its normal.
String _planeWords(PlaneFrame f) {
  final n = f.n;
  final axis = worldAxisName(n);
  final c = f.origin.dot(n);
  final at = switch (axis) {
    '+X' || '-X' => 'x=${_num(f.origin.x)}',
    '+Y' || '-Y' => 'y=${_num(f.origin.y)}',
    '+Z' || '-Z' => 'z=${_num(f.origin.z)}',
    _ => 'normal $axis, ${_num(c)} from the origin',
  };
  return 'the plane $at';
}

String _sketchLine(ChildSketch cs, int closed) {
  final f = sketchFrameOf(cs);
  final where = switch (cs.plane) {
    'xy' || 'yz' || 'xz' => 'on ${planeLabel(cs.plane)}, ${_planeWords(f)}',
    // A face sketch and an offset plane are both stored as 'face'; the
    // plane is what matters, and it is exact either way.
    'face' => 'on ${_planeWords(f)} (facing ${worldAxisName(f.n)})',
    _ => 'on a work plane, ${_planeWords(f)} (facing ${worldAxisName(f.n)})',
  };
  final geo = cs.model.geometry;
  final b = StringBuffer('${cs.model.name} — sketch $where · ');
  if (geo.isEmpty) {
    b.write('empty');
  } else {
    b.write('${geo.length} entit${geo.length == 1 ? "y" : "ies"}, '
        '$closed closed profile${closed == 1 ? "" : "s"}');
    Vec3? lo, hi;
    for (final g in geo) {
      for (final q in _samples(g)) {
        final w = f.toWorld(q);
        if (!w.x.isFinite || !w.y.isFinite || !w.z.isFinite) continue;
        lo = lo == null
            ? w
            : Vec3(_min(lo.x, w.x), _min(lo.y, w.y), _min(lo.z, w.z));
        hi = hi == null
            ? w
            : Vec3(_max(hi.x, w.x), _max(hi.y, w.y), _max(hi.z, w.z));
      }
    }
    if (lo != null && hi != null) b.write(', drawn over ${faceSpan(lo, hi)}');
  }
  if (cs.rolledBack) b.write(' (after End of Part — not built)');
  return b.toString();
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

List<Offset> _samples(Geo g) {
  try {
    return sampleEntity(g, arcSamples: 8);
  } catch (_) {
    return const [];
  }
}

ChildSketch? _sketch(PartModel p, String name) {
  for (final cs in p.childSketches) {
    if (cs.model.name == name) return cs;
  }
  return null;
}

String _featureLine(PartModel p, PartFeature f) {
  final op = switch (f.output) {
    'new' => 'NEW body ${f.bodyName}',
    'join' => 'ADDS to ${f.bodyName}',
    'cut' => 'CUTS from ${f.bodyName}',
    'intersect' => 'KEEPS only the overlap with ${f.bodyName}',
    _ => f.output,
  };
  final b = StringBuffer('${f.name} — ${f.typeLabel.toLowerCase()}');
  if (!f.modifiesBody) b.write(' $op');
  if (f.sketchName.isNotEmpty) b.write(' from ${f.sketchName}');
  final how = _how(p, f);
  if (how.isNotEmpty) b.write(', $how');
  // A sketch feature's own body is the tool: for a cut, exactly the region
  // it takes away. A body-modifying feature's is the whole body again, which
  // says nothing the part's extent does not.
  if (!f.modifiesBody && f.ownSurfaces.isNotEmpty) {
    var lo = f.ownSurfaces.first.lo, hi = f.ownSurfaces.first.hi;
    for (final s in f.ownSurfaces.skip(1)) {
      lo = Vec3(_min(lo.x, s.lo.x), _min(lo.y, s.lo.y), _min(lo.z, s.lo.z));
      hi = Vec3(_max(hi.x, s.hi.x), _max(hi.y, s.hi.y), _max(hi.z, s.hi.z));
    }
    b.write(' · its own body reaches ${faceSpan(lo, hi)}');
  }
  if (f.rolledBack) b.write(' (after End of Part — not built)');
  if (f.computeError != null) b.write(' · FAILED: ${f.computeError}');
  if (!f.visible) b.write(' (hidden)');
  return b.toString();
}

String _how(PartModel p, PartFeature f) {
  if (f is ExtrudeFeature) {
    final cs = _sketch(p, f.sketchName);
    final n = cs == null ? null : sketchFrameOf(cs).n;
    final along = n == null ? '' : worldAxisName(n);
    final back = n == null ? '' : worldAxisName(n * -1);
    final dir = switch (f.direction) {
      ExtrudeDirection.flipped => 'along $back',
      ExtrudeDirection.symmetric => 'both ways, $along and $back',
      ExtrudeDirection.asymmetric => '$along then $back',
      _ => 'along $along',
    };
    return switch (f.extent) {
      FeatureExtent.distance => f.direction == ExtrudeDirection.asymmetric
          ? '${_num(f.distanceA)} mm $along and ${_num(f.distanceB)} mm $back'
          : '${_num(f.distanceA)} mm $dir',
      FeatureExtent.toFace =>
        'up to the face at ${_faceAt(f.extentFace)}, $dir',
      FeatureExtent.toNext => 'to the next face, $dir',
      FeatureExtent.throughAll => 'through everything, $dir',
    };
  }
  if (f is RevolveFeature) return '${_num(f.sweepDeg)}° about its axis';
  if (f is HoleFeature) {
    final depth = f.extent == FeatureExtent.throughAll
        ? 'through'
        : '${_num(f.depth)} mm deep';
    return '${f.places.length} × Ø${_num(f.dia)}, $depth';
  }
  if (f is FilletFeature && f.radii.isNotEmpty) {
    return 'R${_num(f.radii.first)} on ${f.edges.length} edge(s)';
  }
  if (f is ChamferFeature) {
    return '${_num(f.distance1)} mm on ${f.edges.length} edge(s)';
  }
  if (f is ShellFeature) {
    return '${_num(f.thickness)} mm wall${f.outward ? " grown outward" : ""}, '
        '${f.faces.length} face(s) left open';
  }
  return '';
}

String _faceAt(FaceSel? s) {
  if (s == null) return '?';
  final n = Vec3(s.nx, s.ny, s.nz);
  return switch (worldAxisName(n)) {
    '+X' || '-X' => 'x=${_num(s.px)}',
    '+Y' || '-Y' => 'y=${_num(s.py)}',
    '+Z' || '-Z' => 'z=${_num(s.pz)}',
    _ => '(${_num(s.px)}, ${_num(s.py)}, ${_num(s.pz)})',
  };
}
