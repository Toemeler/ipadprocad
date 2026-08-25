// M247 — WORK FEATURES THAT BELONG TO THE ASSEMBLY.
//
// The part has had these since M151/M215: a work plane, a work axis and a
// work point, built by picking geometry and solved by work_features.dart. An
// assembly wants exactly the same three, and this file is the ONE thing that
// is genuinely different about them.
//
// ---------------------------------------------------------------------------
// THE DIFFERENCE: THE REFERENCES MOVE
// ---------------------------------------------------------------------------
//
// A part's work plane BAKES its frame at creation. work_features.dart says so
// in its "Honest scope note" and it is defensible there: the face it was built
// from is in the same document and only an edit to that document can move it.
//
// In an assembly it is not defensible at all. The face a work plane was built
// from belongs to a COMPONENT, and the constraint solver moves components —
// every drag, every new mate, every Update. A baked frame would be correct
// for exactly as long as nobody touched the assembly, and would then be
// silently, invisibly wrong: the plane still drawn where the component used
// to be. That is the failure this file exists to prevent, and it is the same
// one M242 states for constraint selections ("the difference between a
// constraint and a one-off snap").
//
// So an assembly work feature stores its inputs the way a constraint does —
// as [AsmRef]s, occurrence id plus geometry in that component's own frame —
// and RE-SOLVES its frame from them after every solve. [resolveAsmWorkFeatures]
// is that pass, and AppState._solveAssembly is the one place it is called
// from, so a work feature cannot go stale by a code path forgetting it.
//
// The consequence worth stating plainly: an assembly work feature is
// PARAMETRIC where its part twin is not. Move the bracket, and the plane you
// built on its face goes with it.
//
// ---------------------------------------------------------------------------
// WHAT IS REUSED, AND WHY THE CLASSES ARE SUBCLASSES
// ---------------------------------------------------------------------------
//
// Everything except the paragraph above. The methods, the prompts, the
// refusals and the arithmetic are work_features.dart's, unchanged — the
// assembly feeds it the same [WorkRef]s and takes the same answers. The
// picking is asm_pick.dart's, unchanged: [pickAsmRef] already reduces a tap
// to geometry in a component's frame, per PIECE rather than per component
// (M246), and already knows this tree's depth convention.
//
// [AsmWorkPlane] / [AsmWorkAxis] / [AsmWorkPoint] EXTEND the part's classes
// rather than paralleling them, so the browser rows, the eye, the selection
// highlight, the RealityKit plane payload and the HUD painter all take them
// with no second implementation and no `dynamic`. What the subclass adds is
// only what re-solving needs: the method, the stored inputs, and the last
// re-solve's verdict.
import 'asm_constraints.dart';
import 'assembly.dart';
import 'l10n/l.dart';
import 'part_model.dart';
import 'work_features.dart';

/// The current strings, read where they are needed — work_features.dart's own
/// seam, for its own reason: this file has no BuildContext and its sentences
/// reach the user as toasts raised by AppState.
AppL10n get _t => L.current;

/// The three lists an assembly's work features live in, in one place, so a
/// caller that wants "every work feature" cannot forget one.
Iterable<Object> asmWorkFeatures(AssemblyModel a) =>
    [...a.workPlanes, ...a.workAxes, ...a.workPoints];

// ---------------------------------------------------------------------------
// the features
// ---------------------------------------------------------------------------

/// An assembly-owned work plane.
///
/// [kind] carries the same four values a part's does, and for the same reason:
/// Offset and Midplane are not [WorkPlaneMethod]s. work_features.dart states
/// why — Offset is a drag with a live distance and an editable base, Midplane
/// picks plane keys — and adding them to that enum would give the part TWO
/// ways to build one plane. So [method] is null for those two and [kind] says
/// which, exactly as it does on the part side.
class AsmWorkPlane extends WorkPlane {
  AsmWorkPlane(
    String name,
    int seq,
    WorkPlaneKind kind,
    String def,
    PlaneFrame frame, {
    this.method,
    required this.refs,
    bool visible = true,
    double? offset,
    double? angle,
  }) : super(name, seq, kind, def, frame,
            visible: visible, offset: offset, angle: angle);

  /// Which pick-only method built this, or null for Offset and Midplane.
  final WorkPlaneMethod? method;

  /// The inputs, in the order they were picked.
  final List<AsmRef> refs;

  /// Why the last re-solve could not place it, or null when it is healthy.
  ///
  /// Runtime only, like [AsmConstraint.error]: a document records what the
  /// user asked for, never the solver's opinion of it on some earlier launch.
  /// The frame from the last SUCCESSFUL solve is kept, so a component that
  /// goes missing leaves a plane where it was rather than at the origin.
  String? error;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (method != null) 'method': method!.name,
        'refs': [for (final r in refs) r.toJson()],
      };

  static AsmWorkPlane? fromJson(Map<String, dynamic> m) {
    final base = WorkPlane.fromJson(m);
    if (base == null) return null;
    return AsmWorkPlane(
      base.name,
      base.seq,
      base.kind,
      base.def,
      base.frame,
      method: WorkPlaneMethod.values
          .where((e) => e.name == m['method'])
          .firstOrNull,
      refs: _refsFrom(m['refs']),
      visible: base.visible,
      offset: base.offset,
      angle: base.angle,
    );
  }
}

/// An assembly-owned work axis.
class AsmWorkAxis extends WorkAxis {
  AsmWorkAxis(super.name, super.seq, super.def, super.at, super.dir,
      {required this.method, required this.refs, super.visible});

  final WorkAxisMethod method;
  final List<AsmRef> refs;
  String? error;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'method': method.name,
        'refs': [for (final r in refs) r.toJson()],
      };

  static AsmWorkAxis? fromJson(Map<String, dynamic> m) {
    final base = WorkAxis.fromJson(m);
    if (base == null) return null;
    return AsmWorkAxis(base.name, base.seq, base.def, base.at, base.dir,
        method: WorkAxisMethod.values
                .where((e) => e.name == m['method'])
                .firstOrNull ??
            WorkAxisMethod.auto,
        refs: _refsFrom(m['refs']),
        visible: base.visible);
  }
}

/// An assembly-owned work point.
class AsmWorkPoint extends WorkPoint {
  AsmWorkPoint(super.name, super.seq, super.def, super.at,
      {required this.method,
      required this.refs,
      super.visible,
      super.grounded});

  final WorkPointMethod method;
  final List<AsmRef> refs;
  String? error;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'method': method.name,
        'refs': [for (final r in refs) r.toJson()],
      };

  static AsmWorkPoint? fromJson(Map<String, dynamic> m) {
    final base = WorkPoint.fromJson(m);
    if (base == null) return null;
    return AsmWorkPoint(base.name, base.seq, base.def, base.at,
        method: WorkPointMethod.values
                .where((e) => e.name == m['method'])
                .firstOrNull ??
            WorkPointMethod.auto,
        refs: _refsFrom(m['refs']),
        visible: base.visible,
        grounded: base.grounded);
  }
}

List<AsmRef> _refsFrom(Object? j) => [
      for (final e in (j as List? ?? const []))
        if (AsmRef.fromJson(e) case final r?) r
    ];

// ---------------------------------------------------------------------------
// AsmRef -> WorkRef: the bridge
// ---------------------------------------------------------------------------

/// What [r] currently stands for, in WORLD coordinates, as the work-feature
/// machinery's own vocabulary. Null when the component it names is gone.
///
/// This is where the re-solve gets its inputs, and where a fresh pick is
/// turned into one so that BOTH go through the same conversion — a pick that
/// solved one way at creation and another way on reload would be the worst
/// kind of bug to find.
WorkRef? workRefOf(AssemblyModel a, AsmRef r) {
  // A reference to another assembly work feature reads that feature's CURRENT
  // geometry, which is what makes a plane built on a plane follow the first
  // one. worldGeomOf already resolves it; this only has to not bake it.
  if (!r.isAssemblyOrigin && a.byId(r.occurrence) == null) return null;
  if (r.isWorkFeature && asmWorkGeom(a, r.feature!) == null) return null;
  final g = worldGeomOf(a, r);
  final o = r.isAssemblyOrigin ? null : a.byId(r.occurrence);
  final anchor = o == null ? r.anchor : o.toWorld(r.anchor);
  return _workRefFrom(g, r.label, r.extent, anchor);
}

/// The per-kind fallback for a reference written before [AsmGeom.source]
/// existed. A radius is the only thing that can tell a circular edge from a
/// straight one after the fact, and it is the distinction that matters most —
/// it is what "Through Center of Circular Edge" is picked by.
WorkRefSource _fallbackSource(AsmGeom g) => switch (g.kind) {
      AsmGeomKind.plane => WorkRefSource.plane,
      AsmGeomKind.axis =>
        g.radius > 1e-9 ? WorkRefSource.circle : WorkRefSource.axis,
      AsmGeomKind.point => WorkRefSource.vertex,
    };

WorkRef _workRefFrom(AsmGeom g, String label, double extent, Vec3 anchor) {
  switch (g.source ?? _fallbackSource(g)) {
    case WorkRefSource.plane:
      // M244's trap, and the reason the anchor travels at all: the plane's
      // own point is `pl.Location()`, which for an extruded face is the
      // SKETCH ORIGIN — on the plane, and routinely a quarter of a metre from
      // the face you tapped. Projecting the anchor onto the plane names the
      // same plane to the last bit (the arithmetic only ever uses n and n.at)
      // while putting the point ON the face, so a plane built "through" it is
      // drawn and framed where the user pointed.
      final n = g.dir.normalized();
      final on = anchor - n * ((anchor - g.at).dot(n));
      return WorkRef.plane(label, on, n);
    case WorkRefSource.circle:
      return WorkRef.circle(label, g.at, g.dir);
    case WorkRefSource.revolved:
      return g.radius > 1e-9
          // The tapped point is what chooses between the two tangent planes
          // through a point outside a cylinder (M224). Without it the tangent
          // methods refuse rather than guess, which is the right refusal but
          // the wrong answer when the pick did carry a side.
          ? WorkRef.cylinder(label, g.at, g.dir,
              radius: g.radius, hitAt: anchor)
          : WorkRef.revolvedFace(label, g.at, g.dir);
    case WorkRefSource.sphere:
      return WorkRef.sphere(label, g.at);
    case WorkRefSource.torus:
      return WorkRef.torus(label, g.at, g.dir);
    case WorkRefSource.edge:
      // An EDGE is finite, and its midpoint is what makes Inventor's "On
      // Vertex, Sketch Point, or Midpoint" reachable by pointing at one. The
      // ends are not stored — AsmGeom reduces an edge to a line — but the
      // anchor IS the midpoint and the extent IS the half-length, both
      // recorded by asm_pick for the highlight, so the segment comes back
      // exactly.
      if (extent > 1e-9) {
        final d = g.dir.normalized();
        return WorkRef.line(label, anchor - d * extent, anchor + d * extent);
      }
      return WorkRef.axis(label, g.at, g.dir, source: WorkRefSource.edge);
    case WorkRefSource.curve:
      return WorkRef.curveAt(label, g.at, g.dir);
    case WorkRefSource.axis:
      return WorkRef.axis(label, g.at, g.dir);
    case WorkRefSource.vertex:
      return WorkRef.point(label, g.at);
  }
}

/// The world geometry of the assembly work feature [id] (`wp:3`, `wa:1`,
/// `wpt:2`), or null when nothing in [a] carries that id.
///
/// This is what makes an assembly work feature CONSTRAINABLE: a constraint
/// stores the id and reads the current answer here, so mating to a work plane
/// that is itself built on a moving component keeps meaning the plane rather
/// than the place the plane happened to be.
AsmGeom? asmWorkGeom(AssemblyModel a, String id) {
  for (final w in a.workPlanes) {
    if (w.id == id) {
      return AsmGeom.plane(w.frame.origin, w.frame.n);
    }
  }
  for (final x in a.workAxes) {
    if (x.id == id) return AsmGeom.axis(x.at, x.dir);
  }
  for (final p in a.workPoints) {
    if (p.id == id) return AsmGeom.point(p.at);
  }
  return null;
}

// ---------------------------------------------------------------------------
// the re-solve
// ---------------------------------------------------------------------------

/// Re-derives every work feature in [a] from its stored inputs.
///
/// Called after every solve. Cheap by construction — an assembly holds a
/// handful of these and each is a closed-form expression over two or three
/// picks — so there is no memo and no dirty flag to get out of step.
///
/// ORDER: planes, then axes, then points, and within each list in `seq` order,
/// which is creation order. A work feature can be built on another one, and a
/// feature can only ever have been built on one that already existed, so
/// creation order IS dependency order and one pass is enough. It is also why
/// this walks `seq` rather than the list index: nothing reorders these lists
/// today, and a pass that quietly depended on that would break the day
/// something does.
void resolveAsmWorkFeatures(AssemblyModel a) {
  final planes = [...a.workPlanes]..sort((x, y) => x.seq.compareTo(y.seq));
  final axes = [...a.workAxes]..sort((x, y) => x.seq.compareTo(y.seq));
  final points = [...a.workPoints]..sort((x, y) => x.seq.compareTo(y.seq));
  for (final w in planes) {
    resolveAsmWorkPlane(a, w);
  }
  for (final x in axes) {
    resolveAsmWorkAxis(a, x);
  }
  for (final p in points) {
    resolveAsmWorkPoint(a, p);
  }
}

/// The world refs for [refs], or null when any input is gone.
///
/// All-or-nothing on purpose: a three-plane point built from two surviving
/// planes is not a point, and solving one from a shortened list would put it
/// somewhere plausible and wrong.
List<WorkRef>? asmWorkRefs(AssemblyModel a, List<AsmRef> refs) {
  final out = <WorkRef>[];
  for (final r in refs) {
    final w = workRefOf(a, r);
    if (w == null) return null;
    out.add(w);
  }
  return out;
}

void resolveAsmWorkPlane(AssemblyModel a, AsmWorkPlane w) {
  final refs = asmWorkRefs(a, w.refs);
  if (refs == null || refs.isEmpty) {
    w.error = 'reference lost';
    return;
  }
  final sol = solveAsmWorkPlane(w.kind, w.method, refs,
      offset: w.offset ?? 0, angleDeg: w.angle ?? 45);
  if (sol.outcome != WorkPickOutcome.complete) {
    // Keep the last good frame and say why. An assembly that is mid-drag can
    // put two planes momentarily parallel; throwing the plane away for that
    // would delete the user's work over a transient.
    w.error = sol.message;
    return;
  }
  w.error = null;
  final s = sol.solution!;
  w.def = s.def;
  w.frame = workPlaneFrameAt(s.at, s.n);
  // M162/M229 — the ONE number an offset or an angle plane carries stays
  // editable, which needs the base it is measured from. On the part side the
  // base is stored; here it is re-derived every solve, because the thing it
  // is measured from is exactly what moved.
  final basePlane = refs.firstWhere((r) => r.hasPlane, orElse: () => refs.first);
  if (basePlane.hasPlane) {
    w.base = workPlaneFrameAt(basePlane.planeAt!, basePlane.planeNormal!);
  }
  if (w.kind == WorkPlaneKind.angle) {
    final edge = refs.firstWhere(
        (r) => !identical(r, basePlane) && r.hasLine,
        orElse: () => basePlane);
    if (!identical(edge, basePlane) && edge.hasLine) {
      w.axisAt = edge.lineAt;
      w.axisDir = edge.lineDir;
    }
  }
}

void resolveAsmWorkAxis(AssemblyModel a, AsmWorkAxis x) {
  final refs = asmWorkRefs(a, x.refs);
  if (refs == null || refs.isEmpty) {
    x.error = 'reference lost';
    return;
  }
  final sol = solveWorkAxis(x.method, refs);
  if (sol.outcome != WorkPickOutcome.complete) {
    x.error = sol.message;
    return;
  }
  x.error = null;
  // The SIGN is the user's: "Through Two Points" runs first to second, and an
  // axis re-solved into the opposite direction would silently reverse every
  // pattern and revolve that took it. The solver preserves it, so this only
  // has to not undo it.
  x.at = sol.solution!.at;
  x.dir = sol.solution!.dir;
  x.def = sol.solution!.def;
}

void resolveAsmWorkPoint(AssemblyModel a, AsmWorkPoint p) {
  final refs = asmWorkRefs(a, p.refs);
  if (refs == null || refs.isEmpty) {
    p.error = 'reference lost';
    return;
  }
  final sol = solveWorkPoint(p.method, refs);
  if (sol.outcome != WorkPickOutcome.complete) {
    p.error = sol.message;
    return;
  }
  p.error = null;
  p.at = sol.solution!.at;
  p.def = sol.solution!.def;
}

// ---------------------------------------------------------------------------
// the two plane flows that are not WorkPlaneMethods
// ---------------------------------------------------------------------------

/// Every plane method the assembly offers, as one call.
///
/// [method] non-null is work_features.dart's, verbatim. Null means [kind] is
/// Offset or Midplane, the two the part reaches through a plane-key pick and a
/// drag (M151/M174) rather than through a WorkRef. The assembly reaches them
/// through the same WorkRef picks as everything else — there is no plane-key
/// vocabulary in an assembly, and inventing one so that two of thirteen
/// methods could take a different input would be the fork this milestone is
/// avoiding.
WorkAttempt<WorkPlaneSolution> solveAsmWorkPlane(
    WorkPlaneKind kind, WorkPlaneMethod? method, List<WorkRef> refs,
    {double offset = 10, double angleDeg = 45}) {
  if (method != null) {
    return solveWorkPlane(method, refs, angleDeg: angleDeg);
  }
  if (refs.isEmpty) return WorkAttempt.more(asmPlanePrompt(kind, 0));
  if (kind == WorkPlaneKind.midplane) return _asmMidplane(refs);
  return _asmOffsetPlane(refs.first, offset);
}

/// The prompt for the two flows above, in the shape [workPlanePrompt] has.
String asmPlanePrompt(WorkPlaneKind kind, int have) =>
    kind == WorkPlaneKind.midplane
        ? (have == 0
            ? _t.msgSelectFirstParallel
            : _t.msgSelectSecondParallel)
        : _t.msgSelectPlaneToOffsetFrom;

WorkAttempt<WorkPlaneSolution> _asmOffsetPlane(WorkRef r, double d) {
  if (!r.hasPlane) return WorkAttempt.no(_t.wfNotPlane(r.label));
  final def = 'Offset ${d.toStringAsFixed(2)} mm from ${r.label}';
  return WorkAttempt.ok(
      WorkPlaneSolution(
          r.planeAt! + r.planeNormal! * d, r.planeNormal!, def),
      def);
}

WorkAttempt<WorkPlaneSolution> _asmMidplane(List<WorkRef> refs) {
  for (final r in refs) {
    if (!r.hasPlane) return WorkAttempt.no(_t.wfNotPlane(r.label));
  }
  if (refs.length < 2) {
    return WorkAttempt.more(_t.msgSelectSecondParallel);
  }
  final a = refs[0], b = refs[1];
  final mid = midPlaneFrame(workPlaneFrameAt(a.planeAt!, a.planeNormal!),
      workPlaneFrameAt(b.planeAt!, b.planeNormal!));
  if (mid == null) return WorkAttempt.no(_t.msgNotParallel);
  final def = 'Midplane between ${a.label} and ${b.label}';
  return WorkAttempt.ok(WorkPlaneSolution(mid.origin, mid.n, def), def);
}
