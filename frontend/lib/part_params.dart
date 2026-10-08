// Part-wide parameters — Inventor's Parameters table (fx) for a PART.
//
// Sketch dimensions and sketch user parameters have been named values since
// M41/M43, but only inside their own sketch: an extrusion distance, a fillet
// radius or a pattern count could hold a number or arithmetic and nothing
// else. Inventor's table is part-wide: a user parameter "Thick" drives the
// plate's extrusion, the hole depth and the shell, and changing it rebuilds
// exactly what reads it.
//
// The pieces:
//  * [PartParam] — name, equation, unit, value; saved with the part (and so
//    with every undo snapshot, which is the part JSON).
//  * [partParamTable] — every name a part-level expression can use: the part
//    parameters, plus each sketch dimension / sketch user parameter whose name
//    is unique across the part (two sketches both holding a "d0" make the bare
//    name ambiguous, so neither is offered).
//  * [featureValueSlots] — the number fields of each feature (value + the
//    expression the user typed). [resolvePartExpressions] re-evaluates every
//    slot whose expression names a parameter and writes the value back, at
//    the start of every rebuild. Because each feature's [PartFeature.ownSig]
//    already hashes those VALUES, the incremental rebuild picks up exactly the
//    features whose resolved value moved and reuses everything else.
//  * child sketches see the part table through [SketchModel.outerParams], so
//    a sketch dimension can read "Width/2".
import 'dart:math' as math;

import 'app_state.dart' show SketchModel;
import 'constraints.dart' show CType;
import 'params.dart';
import 'part_model.dart';

/// The units a part parameter can carry. Values are stored in the base unit
/// of each (mm, degrees, unitless), like every other number in the app.
const List<String> kPartParamUnits = ['mm', 'deg', 'ul'];

class PartParam {
  String name;

  /// The equation, or null when the parameter is a plain number.
  String? expr;

  /// 'mm' | 'deg' | 'ul' — decides how bare literals in [expr] read.
  String unit;
  double value;
  PartParam(this.name, this.value, {this.expr, this.unit = 'mm'});

  bool get isAngle => unit == 'deg';

  Map<String, dynamic> toJson() => {
        'n': name,
        'v': value,
        if (expr != null) 'x': expr,
        if (unit != 'mm') 'u': unit,
      };

  static PartParam? fromJson(Object? o) {
    if (o is! Map) return null;
    final n = o['n'], v = o['v'];
    if (n is! String || v is! num) return null;
    final u = o['u'];
    return PartParam(n, v.toDouble(),
        expr: o['x'] as String?,
        unit: u is String && kPartParamUnits.contains(u) ? u : 'mm');
  }
}

/// [v] written back as an equation a user could have typed — used when a
/// reference is frozen to its value ('12 mm', '30 deg', '4').
String partValueText(double v, String unit) {
  var s = v.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s == '-0') s = '0';
  return unit == 'ul' ? s : '$s $unit';
}

// ------------------------------------------------------------ name table

/// name -> how many sketches of [p] define it (dimension or user param), and
/// the last value seen.
(Map<String, int>, Map<String, double>) _sketchNames(PartModel p) {
  final count = <String, int>{};
  final value = <String, double>{};
  for (final cs in p.childSketches) {
    final s = cs.model;
    final seen = <String>{};
    for (final c in s.constraints) {
      final n = c.paramName;
      if (c.type != CType.dimension || n == null || !seen.add(n)) continue;
      count[n] = (count[n] ?? 0) + 1;
      if (c.value != null) value[n] = c.value!;
    }
    for (final u in s.userParams) {
      if (!seen.add(u.name)) continue;
      count[u.name] = (count[u.name] ?? 0) + 1;
      value[u.name] = u.value;
    }
  }
  return (count, value);
}

/// Every name a part-level expression can reference, with its current base
/// value. See the file comment for the uniqueness rule.
Map<String, double> partParamTable(PartModel p) {
  final (count, value) = _sketchNames(p);
  return {
    for (final e in value.entries)
      if (count[e.key] == 1) e.key: e.value,
    for (final u in p.params) u.name: u.value,
  };
}

/// Sketch-level names defined in MORE than one sketch of [p] — referenced
/// bare from a feature they are ambiguous, and the error says so.
Set<String> ambiguousSketchNames(PartModel p) {
  final (count, _) = _sketchNames(p);
  return {
    for (final e in count.entries)
      if (e.value > 1 && !p.params.any((u) => u.name == e.key)) e.key
  };
}

/// Every name in use anywhere in [p] (part params, every sketch's dimensions
/// and user params) — a new name must avoid all of them.
Set<String> partNamesInUse(PartModel p) {
  final (count, _) = _sketchNames(p);
  return {...count.keys, for (final u in p.params) u.name};
}

PartParam? partParamByName(PartModel p, String name) {
  for (final u in p.params) {
    if (u.name == name) return u;
  }
  return null;
}

/// name -> the names its equation references, across the whole part: part
/// parameters and every sketch's dimensions and user parameters. A name two
/// sketches share gets the union of both (conservative for cycle checks).
Map<String, Set<String>> partDepGraph(PartModel p) {
  final g = <String, Set<String>>{};
  void add(String n, String? x) {
    if (x == null) return;
    (g[n] ??= <String>{}).addAll(exprRefs(x));
  }

  for (final cs in p.childSketches) {
    for (final c in cs.model.constraints) {
      if (c.type == CType.dimension && c.paramName != null) {
        add(c.paramName!, c.expr);
      }
    }
    for (final u in cs.model.userParams) {
      add(u.name, u.expr);
    }
  }
  for (final u in p.params) {
    add(u.name, u.expr);
  }
  return g;
}

/// True when giving [self] an equation that references [refs] closes a loop
/// through [graph].
bool refsCloseCycle(
    Map<String, Set<String>> graph, String self, Iterable<String> refs) {
  final seen = <String>{};
  bool reaches(String n) {
    if (n == self) return true;
    if (!seen.add(n)) return false;
    return (graph[n] ?? const <String>{}).any(reaches);
  }

  return refs.any(reaches);
}

/// Hands every child sketch of [p] a live view of the part table, so its
/// dimensions can read part parameters. Idempotent and cheap.
void linkPartParams(PartModel p) {
  for (final cs in p.childSketches) {
    cs.model.outerParams = () => partParamTable(p);
  }
}

/// Evaluates a part-level equation. Length domain first ('mm', 'cm' suffixes),
/// angle domain second ('deg', 'rad'), so '30 deg + Tilt' works in an angle
/// field and 'Width/2 mm' in a length field without the caller choosing.
double? evalScoped(String expr, Map<String, double> table,
    {bool angle = false}) {
  final t = expr.trim();
  if (t.isEmpty) return null;
  return evalExpr(t, table, angle: angle) ??
      evalExpr(t, table, angle: !angle);
}

/// True when [expr] names at least one parameter (as opposed to a plain
/// number or arithmetic on literals).
bool exprIsDriven(String expr) => exprRefs(expr).isNotEmpty;

// ------------------------------------------------------------ feature slots

/// One number field of a feature: the value the kernel reads and the text the
/// user typed for it.
class FeatureValueSlot {
  final String key;
  final String expr;
  final bool angle;

  /// A whole-number field (pattern counts): the value is rounded.
  final bool count;
  final double value;
  final void Function(double v) apply;
  final void Function(String e) setExpr;
  const FeatureValueSlot(this.key, this.expr, this.value, this.apply,
      this.setExpr,
      {this.angle = false, this.count = false});
}

/// Fillet set-0 radius as last resolved — which radii a driven exprRadius
/// owns (the other edge sets keep their own radius). Runtime only: it is
/// recorded on every resolve, and a part is always resolved against the same
/// table it was saved / snapshotted with before anything changes.
final Expando<double> _filletBase = Expando<double>('fillet expr base');

List<FeatureValueSlot> featureValueSlots(PartFeature f) {
  FeatureValueSlot s(String k, String e, double v, void Function(double) a,
          void Function(String) x,
          {bool angle = false, bool count = false}) =>
      FeatureValueSlot(k, e, v, a, x, angle: angle, count: count);
  return switch (f) {
    ExtrudeFeature() => [
        s('distanceA', f.exprA, f.distanceA, (v) => f.distanceA = v,
            (e) => f.exprA = e),
        s('distanceB', f.exprB, f.distanceB, (v) => f.distanceB = v,
            (e) => f.exprB = e),
        s('taper', f.exprTaper, f.taperDeg, (v) => f.taperDeg = v,
            (e) => f.exprTaper = e,
            angle: true),
      ],
    RevolveFeature() => [
        s('angleA', f.exprA, f.angleA, (v) => f.angleA = v,
            (e) => f.exprA = e,
            angle: true),
        s('angleB', f.exprB, f.angleB, (v) => f.angleB = v,
            (e) => f.exprB = e,
            angle: true),
      ],
    SweepFeature() => [
        s('taper', f.exprTaper, f.taperDeg, (v) => f.taperDeg = v,
            (e) => f.exprTaper = e,
            angle: true),
        s('twist', f.exprTwist, f.twistDeg, (v) => f.twistDeg = v,
            (e) => f.exprTwist = e,
            angle: true),
      ],
    CoilFeature() => [
        s('revolutions', f.exprRevolutions, f.revolutions,
            (v) => f.revolutions = v, (e) => f.exprRevolutions = e),
        s('height', f.exprHeight, f.height, (v) => f.height = v,
            (e) => f.exprHeight = e),
        s('pitch', f.exprPitch, f.pitch, (v) => f.pitch = v,
            (e) => f.exprPitch = e),
        s('taper', f.exprTaper, f.taperDeg, (v) => f.taperDeg = v,
            (e) => f.exprTaper = e,
            angle: true),
      ],
    HoleFeature() => [
        s('dia', f.exprDia, f.dia, (v) => f.dia = v, (e) => f.exprDia = e),
        s('depth', f.exprDepth, f.depth, (v) => f.depth = v,
            (e) => f.exprDepth = e),
        s('cbDia', f.exprCbDia, f.cbDia, (v) => f.cbDia = v,
            (e) => f.exprCbDia = e),
        s('cbDepth', f.exprCbDepth, f.cbDepth, (v) => f.cbDepth = v,
            (e) => f.exprCbDepth = e),
        s('csDia', f.exprCsDia, f.csDia, (v) => f.csDia = v,
            (e) => f.exprCsDia = e),
        s('csAngle', f.exprCsAngle, f.csAngle, (v) => f.csAngle = v,
            (e) => f.exprCsAngle = e,
            angle: true),
      ],
    ShellFeature() => [
        s('thickness', f.exprThickness, f.thickness, (v) => f.thickness = v,
            (e) => f.exprThickness = e),
      ],
    FilletFeature() => [
        s('radius', f.exprRadius, _filletBase[f] ?? _filletSet0(f), (v) {
          final base = _filletBase[f];
          final all = f.radii.every((r) => (r - f.radii.first).abs() < 1e-9);
          for (var i = 0; i < f.radii.length; i++) {
            if (all ||
                (base != null && (f.radii[i] - base).abs() < 1e-9)) {
              f.radii[i] = v;
            }
          }
          _filletBase[f] = v;
        }, (e) => f.exprRadius = e),
      ],
    ChamferFeature() => [
        s('distance1', f.exprD1, f.distance1, (v) => f.distance1 = v,
            (e) => f.exprD1 = e),
        s('distance2', f.exprD2, f.distance2, (v) => f.distance2 = v,
            (e) => f.exprD2 = e),
        s('angle', f.exprAngle, f.angleDeg, (v) => f.angleDeg = v,
            (e) => f.exprAngle = e,
            angle: true),
      ],
    PatternFeature() => [
        s('countA', f.exprCountA, f.countA.toDouble(),
            (v) => f.countA = v.round(), (e) => f.exprCountA = e,
            count: true),
        s('countB', f.exprCountB, f.countB.toDouble(),
            (v) => f.countB = v.round(), (e) => f.exprCountB = e,
            count: true),
        s('distanceA', f.exprDistanceA, f.distanceA, (v) => f.distanceA = v,
            (e) => f.exprDistanceA = e),
        s('distanceB', f.exprDistanceB, f.distanceB, (v) => f.distanceB = v,
            (e) => f.exprDistanceB = e),
        s('countC', f.exprCountC, f.countC.toDouble(),
            (v) => f.countC = v.round(), (e) => f.exprCountC = e,
            count: true),
        s('angleC', f.exprAngleC, f.angleC, (v) => f.angleC = v,
            (e) => f.exprAngleC = e,
            angle: true),
      ],
    _ => const [],
  };
}

double _filletSet0(PartFeature f) =>
    f is FilletFeature && f.radii.isNotEmpty ? f.radii.first : 0;

/// Re-evaluates the part's parameter equations (to a fixpoint, so chains
/// settle), then every feature field whose expression names a parameter, and
/// writes the resolved values onto the features. Returns the names of the
/// features whose value moved. A reference that cannot be evaluated (a name
/// that no longer exists) leaves the last value in place.
///
/// Called at the start of every rebuild, so the rebuild key — which hashes
/// the VALUES — sees exactly what changed.
List<String> resolvePartExpressions(PartModel p) {
  linkPartParams(p);
  for (var pass = 0; pass < 16; pass++) {
    final table = partParamTable(p);
    var moved = false;
    for (final u in p.params) {
      final x = u.expr;
      if (x == null) continue;
      final v = evalScoped(x, table, angle: u.isAngle);
      if (v != null && (v - u.value).abs() > 1e-12) {
        u.value = v;
        moved = true;
      }
    }
    if (!moved) break;
  }
  final table = partParamTable(p);
  final changed = <String>[];
  for (final f in p.features) {
    for (final slot in featureValueSlots(f)) {
      if (!exprIsDriven(slot.expr)) continue;
      var v = evalScoped(slot.expr, table, angle: slot.angle);
      if (v == null) continue;
      if (slot.count) {
        v = v.roundToDouble().clamp(1, kPatternMaxCount.toDouble());
      }
      if ((v - slot.value).abs() > 1e-12) {
        slot.apply(v);
        if (!changed.contains(f.name)) changed.add(f.name);
      }
    }
    if (f is FilletFeature) {
      _filletBase[f] ??= _filletSet0(f);
      if (!exprIsDriven(f.exprRadius)) _filletBase[f] = null;
    }
  }
  for (final w in p.workPlanes) {
    final x = w.valueExpr;
    if (x == null || !exprIsDriven(x) || !w.valueEditable) continue;
    final v = evalScoped(x, table, angle: w.kind == WorkPlaneKind.angle);
    final cur = w.value;
    if (v == null || (cur != null && (v - cur).abs() <= 1e-12)) continue;
    if (w.kind == WorkPlaneKind.angle) {
      w.setAngle(v);
    } else {
      w.setOffset(v);
    }
    changed.add(w.name);
  }
  return changed;
}

/// Every feature field (and work plane value) whose equation names [name] —
/// what a delete would cut loose. Used for the "still used by" report.
List<String> partParamUsers(PartModel p, String name) {
  final out = <String>[];
  for (final f in p.features) {
    if (featureValueSlots(f).any((s) => exprRefs(s.expr).contains(name))) {
      out.add(f.name);
    }
  }
  for (final w in p.workPlanes) {
    final x = w.valueExpr;
    if (x != null && exprRefs(x).contains(name)) out.add(w.name);
  }
  for (final u in p.params) {
    final x = u.expr;
    if (x != null && u.name != name && exprRefs(x).contains(name)) {
      out.add(u.name);
    }
  }
  for (final cs in p.childSketches) {
    final s = cs.model;
    final uses = s.constraints.any((c) =>
            c.type == CType.dimension &&
            c.expr != null &&
            exprRefs(c.expr!).contains(name)) ||
        s.userParams
            .any((u) => u.expr != null && exprRefs(u.expr!).contains(name));
    if (uses) out.add(s.name);
  }
  return out;
}

/// Turns every part-level equation that names something [p] no longer has
/// into the value it last had — feature fields become '12 mm', part
/// parameters become plain numbers. Same rule the sketch applies to its own
/// dimensions (an equation naming a ghost could never be recomputed, and its
/// edit box would refuse every save of the text it shows).
void freezeOrphanPartExpressions(PartModel p) {
  final names = partParamTable(p).keys.toSet();
  bool orphan(String x) => exprRefs(x).any((r) => !names.contains(r));
  for (final f in p.features) {
    for (final s in featureValueSlots(f)) {
      if (!orphan(s.expr)) continue;
      s.setExpr(partValueText(
          s.count ? s.value.roundToDouble() : s.value,
          s.count ? 'ul' : s.angle ? 'deg' : 'mm'));
    }
  }
  for (final w in p.workPlanes) {
    final x = w.valueExpr;
    if (x != null && orphan(x)) w.valueExpr = null;
  }
  for (final u in p.params) {
    final x = u.expr;
    if (x != null && orphan(x)) u.expr = null;
  }
}

/// Renames [from] to [to] in every equation of [p]: part parameters, feature
/// fields, work plane values and every child sketch's dimensions and user
/// parameters (word-boundary match, so renaming d1 leaves d10 alone).
void renamePartRefs(PartModel p, String from, String to) {
  final re = RegExp('\\b${RegExp.escape(from)}\\b');
  for (final u in p.params) {
    if (u.expr != null) u.expr = u.expr!.replaceAll(re, to);
  }
  for (final f in p.features) {
    for (final s in featureValueSlots(f)) {
      if (exprRefs(s.expr).contains(from)) s.setExpr(s.expr.replaceAll(re, to));
    }
  }
  for (final w in p.workPlanes) {
    if (w.valueExpr != null) w.valueExpr = w.valueExpr!.replaceAll(re, to);
  }
  for (final cs in p.childSketches) {
    final s = cs.model;
    for (final c in s.constraints) {
      if (c.expr != null && exprRefs(c.expr!).contains(from)) {
        c.expr = c.expr!.replaceAll(re, to);
      }
    }
    for (final u in s.userParams) {
      if (u.expr != null && exprRefs(u.expr!).contains(from)) {
        u.expr = u.expr!.replaceAll(re, to);
      }
    }
  }
}

/// The child sketches of [p] whose equations name a part-level parameter —
/// what must re-solve when the table changes.
List<SketchModel> sketchesReadingPart(PartModel p) {
  final part = {for (final u in p.params) u.name};
  final out = <SketchModel>[];
  for (final cs in p.childSketches) {
    final s = cs.model;
    final own = {
      for (final c in s.constraints)
        if (c.type == CType.dimension && c.paramName != null) c.paramName!,
      for (final u in s.userParams) u.name,
    };
    bool outer(String? x) =>
        x != null && exprRefs(x).any((r) => !own.contains(r) || part.contains(r));
    if (s.constraints.any((c) => c.type == CType.dimension && outer(c.expr)) ||
        s.userParams.any((u) => outer(u.expr))) {
      out.add(s);
    }
  }
  return out;
}

/// A name for a new part parameter: User_1, User_2, … avoiding every name the
/// part already uses.
String nextPartParamName(PartModel p) {
  final used = partNamesInUse(p);
  var i = 1;
  while (used.contains('User_$i')) {
    i++;
  }
  return 'User_$i';
}

