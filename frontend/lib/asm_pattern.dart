// M248 — PATTERNS THAT BELONG TO THE ASSEMBLY.
//
// The part has had Rectangular, Circular, Sketch Driven and Mirror since M212,
// as one [PatternFeature] with four placement rules and one pure function that
// says where every copy goes ([patternOccurrences]). An assembly wants the
// same commands over COMPONENTS, and this file is what is genuinely different
// about them. It follows M247's shape deliberately — reuse the part's
// arithmetic unchanged, subclass its model class, and RE-SOLVE rather than
// bake — so the two milestones read as one idea applied twice.
//
// ---------------------------------------------------------------------------
// A. WHAT AN ASSEMBLY PATTERN IS
// ---------------------------------------------------------------------------
//
// Inventor's assembly pattern is a browser node whose ELEMENTS are ordinary
// occurrences: they render, they are picked, they can be suppressed one at a
// time, they cannot be deleted individually, and the count and spacing stay
// editable afterwards. That is what this builds, and the shape is:
//
//   * [AsmPattern] on [AssemblyModel.patterns] holds the seeds and the
//     parameters — and nothing else. It owns no geometry.
//   * Its instances are ORDINARY [AssemblyOccurrence]s in `a.occurrences`.
//     Not a parallel list, not a special case: they render, pick, drag-test,
//     constrain, save and load through every path that already exists, and
//     nothing downstream of this file knows a pattern was involved.
//   * Each instance carries a back-reference ([AssemblyOccurrence.patternOf],
//     [patternSeed], [patternElement]) so the pattern can find its own work
//     again and the browser can nest the rows under it.
//
// The alternative — a pattern that owns its copies and hands them to the
// renderer separately — was rejected for the reason M246 gives for
// localSolids: every renderer, picker, payload and solver would need a second
// code path for geometry that is in every respect an ordinary component.
//
// ---------------------------------------------------------------------------
// B. THE PARAMETERS MOVE, SO THEY ARE NOT BAKED
// ---------------------------------------------------------------------------
//
// A part pattern stores its direction as an [AxisRef] — world geometry, not a
// reference — and part_model.dart says why that is right THERE: the edge that
// produced it lives in the same document, and only an edit to that document
// can move it.
//
// In an assembly it is wrong for exactly M247's reason: the edge belongs to a
// COMPONENT and the solver moves components. A row of bolts laid out along a
// bracket's edge must follow the bracket. So the inputs are stored as
// [AsmRef]s — occurrence id plus geometry in that component's own frame — and
// the inherited AxisRef/PlaneRef fields are treated as a CACHE of the last
// re-solve, filled by [regenerateAsmPatterns] before the arithmetic runs.
// That is the same division AsmWorkPlane makes between `refs` and `frame`.
//
// ---------------------------------------------------------------------------
// C. AN ELEMENT IS DRIVEN, NOT SOLVED
// ---------------------------------------------------------------------------
//
// A pattern element's placement is a function of its seed's placement and the
// pattern's parameters. It therefore has NO degrees of freedom of its own, and
// the solver treats it exactly as it treats a grounded component: other things
// may be constrained TO it, and it never moves to satisfy them. Anything else
// would be two authorities writing one placement — the solver pulling an
// element off its grid, the next regeneration snapping it back.
//
// [regenerateAsmPatterns] runs on both sides of the solve (see
// AppState._solveAssembly): before, so a constraint that names an element sees
// it where the seed currently puts it; after, so the elements follow the seeds
// the solve just moved.
//
// ---------------------------------------------------------------------------
// D. WHAT HAPPENS TO CONSTRAINTS WHEN THE COUNT CHANGES
// ---------------------------------------------------------------------------
//
// An element's IDENTITY is (pattern, seed, element number), and it is stable:
// element 3 of Pattern1 is the same occurrence, with the same id and therefore
// the same relationships, however the count is edited around it. Growing a
// pattern from 4 to 6 adds elements 5 and 6 and touches nothing else;
// shrinking back to 4 removes those two again.
//
// So the only constraints that can be lost are ones naming an element that
// genuinely ceases to exist, and those go the way every relationship to a
// deleted component goes (AssemblyModel.remove). It is NOT silent:
// [AsmPatternEdit.doomedConstraints] counts them before the edit is applied,
// and the panel says how many will go while the count field still says the
// number that would do it.
//
// ---------------------------------------------------------------------------
// E. ASSOCIATIVE — BOLTS THAT FOLLOW A HOLE PATTERN
// ---------------------------------------------------------------------------
//
// Inventor's first Pattern Component tab takes a FEATURE PATTERN in a
// component and lays the copies out on it, so bolts follow the holes. M245
// made the link to the part live and the part's own [PatternFeature] is right
// there, in the model the occurrence borrows — so this is reachable, and it is
// built: [AsmPattern.driver] names (occurrence, feature name), and
// regeneration reads that feature's CURRENT parameters through the same
// [patternOccurrences] the part uses, then lifts each placement out of the
// component's frame into the assembly's.
//
// Change the hole count in the part, and the bolts follow on the next solve
// with no edit here at all. That is the payoff of rule 1 and it is why this
// file resolves rather than copies.
//
// OUT OF SCOPE, stated rather than half-built: Sketch Driven. An assembly has
// no sketches of its own, and driving one from a sketch inside a component is
// a different feature (it needs the sketch picked THROUGH the occurrence) that
// nothing in the ribbon offers.
import 'dart:math' as math;

import 'asm_constraints.dart';
import 'assembly.dart';
import 'part_model.dart';
import 'quat.dart';

/// Which of Inventor's three Pattern Component tabs, plus Mirror.
///
/// [PatternKind] itself, so [patternOccurrences] and the whole panel take an
/// assembly pattern with no second enum to keep in step. Sketch Driven never
/// appears here — see the file header.
const List<PatternKind> kAsmPatternKinds = [
  PatternKind.rectangular,
  PatternKind.circular,
  PatternKind.mirror,
];

/// An assembly-owned pattern of components.
///
/// EXTENDS [PatternFeature] rather than paralleling it, exactly as
/// [AsmWorkPlane] extends [WorkPlane]: the parameter set, the JSON, the
/// occurrence count and — the one that matters — [patternOccurrences] all take
/// it unchanged. What the subclass adds is only what an assembly needs: the
/// inputs as [AsmRef]s, the associative driver, and the last regeneration's
/// verdict.
///
/// [sources] is inherited and holds OCCURRENCE IDS rather than feature names.
/// It is the same thing in both documents — "the names of what is being
/// copied" — and giving the assembly its own list would have meant a second
/// copy of the seed handling in every method above.
class AsmPattern extends PatternFeature {
  AsmPattern({
    required String name,
    required PatternKind mode,
    List<String> sources = const [],
    this.refDirA,
    this.refDirB,
    this.refAxis,
    this.refPlane,
    this.driver,
    super.visible,
  }) : super(
          name: name,
          // An assembly has no bodies. The field is [PartFeature]'s and is
          // never read for an assembly pattern; the empty string is what says
          // so, rather than a plausible-looking 'Solid1' that would send a
          // reader looking for a body that does not exist.
          bodyName: '',
          mode: mode,
          sources: sources,
        );

  /// Direction A / B, the rotation axis and the mirror plane, as REFERENCES.
  ///
  /// The inherited [dirA] / [dirB] / [axis] / [mirrorPlane] are the resolved
  /// world geometry of these, refreshed by [regenerateAsmPatterns]. Reading
  /// them without a regeneration in between reads the previous solve, which is
  /// exactly what [AsmWorkPlane.frame] does and is stated there too.
  AsmRef? refDirA, refDirB, refAxis, refPlane;

  /// The associative driver: (occurrence id, the name of a [PatternFeature] in
  /// that component's part). Null for a pattern laid out by its own numbers.
  (String, String)? driver;

  /// Why the last regeneration could not place the elements, or null.
  ///
  /// Runtime only, like [AsmConstraint.error] and [AsmWorkPlane.error]: a
  /// document records what the user asked for, never the solver's opinion of
  /// it on some earlier launch.
  String? error;

  /// The occurrence ids of the seeds, which is what [sources] holds.
  List<String> get seeds => sources;

  bool get isAssociative => driver != null;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (refDirA != null) 'refDirA': refDirA!.toJson(),
        if (refDirB != null) 'refDirB': refDirB!.toJson(),
        if (refAxis != null) 'refAxis': refAxis!.toJson(),
        if (refPlane != null) 'refPlane': refPlane!.toJson(),
        if (driver != null) 'driver': [driver!.$1, driver!.$2],
      };

  /// [PatternFeature.fromJson]'s answer, re-housed.
  ///
  /// `kind` is deliberately left as the inherited 'pattern' so this can go
  /// through the part's own reader: every parameter it restores is a parameter
  /// this needs, and a second reader would be a second place for a field added
  /// to [PatternFeature] to be forgotten.
  static AsmPattern? fromJson(Map<String, dynamic> m) {
    if (m['name'] is! String) return null;
    final base = PatternFeature.fromJson(m);
    final drv = m['driver'];
    final p = AsmPattern(
      name: base.name,
      mode: base.mode,
      sources: base.sources,
      refDirA: AsmRef.fromJson(m['refDirA']),
      refDirB: AsmRef.fromJson(m['refDirB']),
      refAxis: AsmRef.fromJson(m['refAxis']),
      refPlane: AsmRef.fromJson(m['refPlane']),
      driver: drv is List && drv.length >= 2
          ? ('${drv[0]}', '${drv[1]}')
          : null,
      visible: base.visible,
    );
    // Everything the placement arithmetic reads, straight off the base — one
    // assignment per field would be one chance to forget the next one added.
    copyPatternParameters(base, p);
    return p;
  }
}

/// Copies every placement parameter of [from] onto [to].
///
/// One function, used by the JSON reader and by the panel's commit, so a
/// parameter added to [PatternFeature] cannot reach one path and miss the
/// other. Deliberately NOT the resolved [AxisRef]s — those are a cache.
void copyPatternParameters(PatternFeature from, PatternFeature to) {
  to
    ..mode = from.mode
    ..flipA = from.flipA
    ..flipB = from.flipB
    ..midplaneA = from.midplaneA
    ..midplaneB = from.midplaneB
    ..countA = from.countA
    ..countB = from.countB
    ..distanceA = from.distanceA
    ..distanceB = from.distanceB
    ..exprCountA = from.exprCountA
    ..exprCountB = from.exprCountB
    ..exprDistanceA = from.exprDistanceA
    ..exprDistanceB = from.exprDistanceB
    ..distributionA = from.distributionA
    ..distributionB = from.distributionB
    ..flipC = from.flipC
    ..countC = from.countC
    ..angleC = from.angleC
    ..exprCountC = from.exprCountC
    ..exprAngleC = from.exprAngleC
    ..distributionC = from.distributionC
    ..orientation = from.orientation
    ..compute = from.compute;
  to.irregularA
    ..clear()
    ..addAll(from.irregularA);
  to.irregularB
    ..clear()
    ..addAll(from.irregularB);
  to.irregularC
    ..clear()
    ..addAll(from.irregularC);
  to.suppressed
    ..clear()
    ..addAll(from.suppressed);
}

// ---------------------------------------------------------------------------
// the regeneration
// ---------------------------------------------------------------------------

/// Re-derives every pattern element in [a] from its pattern's inputs.
///
/// Called on both sides of every solve — see the file header, section C — and
/// cheap by construction: an assembly holds a handful of patterns and each is
/// a closed-form expression over the seed's current placement. There is no
/// memo and no dirty flag, for the reason [resolveAsmWorkFeatures] gives: one
/// that got out of step would leave elements drawn where the seed used to be,
/// which is the failure this whole design is arranged to prevent.
///
/// Returns the ids of the elements it REMOVED, so a caller that has to report
/// dropped relationships can.
Set<String> regenerateAsmPatterns(AssemblyModel a) {
  final removed = <String>{};
  // Creation order. A pattern cannot seed from a later pattern's elements
  // (AppState refuses it), so one pass is enough — the same argument
  // resolveAsmWorkFeatures makes for its `seq` walk.
  for (final p in a.patterns) {
    removed.addAll(_regenerateOne(a, p));
  }
  // An element whose PATTERN has gone is not an element, it is an orphan that
  // nothing can ever place again. This catches a hand-edited document and a
  // pattern deleted while its rows were still in the tree.
  final live = {for (final p in a.patterns) p.name};
  for (final o in [...a.occurrences]) {
    final of = o.patternOf;
    if (of != null && !live.contains(of)) {
      removed.add(o.id);
      a.remove(o);
    }
  }
  return removed;
}

Set<String> _regenerateOne(AssemblyModel a, AsmPattern p) {
  final want = _elementPlacements(a, p);
  final have = <(String, int), AssemblyOccurrence>{
    for (final o in a.occurrences)
      if (o.patternOf == p.name)
        (o.patternSeed ?? '', o.patternElement ?? 0): o
  };
  final removed = <String>{};
  for (final e in want) {
    final key = (e.seed.id, e.element);
    final existing = have.remove(key);
    if (existing != null) {
      // The IDENTITY is the key, not the placement: reusing the occurrence is
      // what keeps its id, its relationships and its browser row across an
      // edit to the count. See section D.
      existing.offset = e.at.at;
      existing.rot = e.at.rot;
      existing.reflect = e.at.reflect;
      existing.visible = e.visible;
      continue;
    }
    a.occurrences.add(AssemblyOccurrence(
      id: a.nextOccurrenceId(e.seed.source),
      source: e.seed.source,
      sourceKind: e.seed.sourceKind,
      offset: e.at.at,
      rot: e.at.rot,
      reflect: e.at.reflect,
      visible: e.visible,
      part: e.seed.part,
      sub: e.seed.sub,
      patternOf: p.name,
      patternSeed: e.seed.id,
      patternElement: e.element,
    ));
  }
  // Whatever the pattern no longer describes. `a.remove` takes the
  // relationships with it, which is the cost section D names and the panel
  // warns about before the edit lands.
  for (final gone in have.values) {
    removed.add(gone.id);
    a.remove(gone);
  }
  return removed;
}

/// One element the pattern wants: which seed it copies, its Inventor
/// occurrence number, and where it goes.
class AsmPatternElement {
  const AsmPatternElement(this.seed, this.element, this.at, this.visible);
  final AssemblyOccurrence seed;

  /// Inventor's numbering, counting the SEED as 1 — so these start at 2.
  final int element;
  final Placement at;

  /// False for an element the user suppressed. Suppressed rather than deleted,
  /// because Inventor's pattern elements cannot be deleted individually and
  /// because a deleted one would take its relationships with it every time the
  /// eye was clicked.
  final bool visible;
}

/// Where every element of [p] goes, in world coordinates.
///
/// The arithmetic itself is [patternOccurrences] — part_model.dart's, unchanged
/// and kernel-free. All this does is resolve the inputs to world geometry,
/// fill the inherited cache fields it reads, and lift each placement onto the
/// seed's own.
List<AsmPatternElement> _elementPlacements(AssemblyModel a, AsmPattern p) {
  final seeds = [
    for (final id in p.seeds)
      if (a.byId(id) case final o?)
        // A seed that is itself an element of this pattern would be a pattern
        // of its own output. It cannot be created (AppState refuses), and a
        // hand-edited document must not be able to hang the regeneration.
        if (o.patternOf != p.name) o
  ];
  if (seeds.isEmpty) {
    p.error = 'no component to pattern';
    return const [];
  }
  final driven = p.driver == null ? null : _driverFeature(a, p);
  if (p.driver != null && driven == null) {
    p.error = 'the driving feature is gone';
    return const [];
  }
  if (!_resolveInputs(a, p)) return const [];
  p.error = null;

  final out = <AsmPatternElement>[];
  for (final seed in seeds) {
    // The seed's own centre is what a circular pattern with Fixed orientation
    // travels round, so it is per-seed rather than per-pattern.
    final b = occurrenceBounds(seed);
    final centre = b == null ? seed.offset : (b.$1 + b.$2) * 0.5;
    final occs = driven == null
        ? patternOccurrences(p, refPoint: centre)
        : _drivenOccurrences(a, p, driven, centre);
    for (final o in occs) {
      if (p.mode == PatternKind.mirror) {
        final plane = p.mirrorPlane;
        if (plane == null) continue;
        out.add(AsmPatternElement(seed, o.index,
            mirrorPlacement(seed.placement, plane.point, plane.normal),
            !p.suppressed.contains(o.index)));
        continue;
      }
      final m = o.mat34;
      if (m == null) continue;
      out.add(AsmPatternElement(seed, o.index, _lift(m, seed.placement),
          !p.suppressed.contains(o.index)));
    }
  }
  return out;
}

/// The placement of a component moved by the world rigid transform [m].
///
/// [m] is a row-major 3x4 the part side already produces; the rotation half is
/// read back as a quaternion so it can compose with the seed's own. Any
/// reflection the seed carries rides along untouched — mirroring a mirrored
/// component in a rectangular pattern copies it as it is, which is what a
/// pattern means.
Placement _lift(List<double> m, Placement seed) {
  final r = quatFromMat34(m);
  return Placement(
      (r * seed.rot).normalized(),
      Vec3(
        m[0] * seed.at.x + m[1] * seed.at.y + m[2] * seed.at.z + m[3],
        m[4] * seed.at.x + m[5] * seed.at.y + m[6] * seed.at.z + m[7],
        m[8] * seed.at.x + m[9] * seed.at.y + m[10] * seed.at.z + m[11],
      ),
      seed.reflect);
}

/// The placement of [seed] reflected in the world plane through [at] with
/// normal [n].
///
/// THE IDENTITY THIS RESTS ON: S_n·R = R·S_(R⁻¹n) for any rotation R. So the
/// mirrored component keeps the seed's rotation exactly, its offset is the
/// plain reflection of the seed's offset, and the handedness is a reflection
/// in the source's OWN frame about R⁻¹n. See [Placement].
///
/// A seed that is ALREADY mirrored comes back un-mirrored, because two
/// reflections are a rotation — which is right: mirroring a left hand gives a
/// right hand.
Placement mirrorPlacement(Placement seed, Vec3 at, Vec3 normal) {
  final n = normal.normalized();
  if (n.length < 0.5) return seed;
  final offset = seed.at - n * (2 * (seed.at - at).dot(n));
  final flipped = Placement(seed.rot, offset, seed.rot.unrotate(n).normalized());
  // The seed's OWN handedness, composed in afterwards. For an unmirrored seed
  // this is the identity; for a mirrored one Placement.operator * annihilates
  // the two reflections into a rotation, which is what makes the mirror of a
  // left hand a right hand rather than a second flag nothing reads.
  return flipped * Placement(Quat.identity, Vec3.zero, seed.reflect);
}

/// Reads the rotation out of a row-major 3x4 rigid placement.
///
/// Shepperd's method, branching on the largest diagonal term: the naive
/// `w = sqrt(1 + trace)/2` form divides by something near zero for a half
/// turn, and a pattern of two at 180 degrees is the commonest circular pattern
/// there is.
Quat quatFromMat34(List<double> m) {
  double at(int r, int c) => m[r * 4 + c];
  final t = at(0, 0) + at(1, 1) + at(2, 2);
  if (t > 0) {
    final s = math.sqrt(t + 1.0) * 2;
    return Quat(0.25 * s, (at(2, 1) - at(1, 2)) / s, (at(0, 2) - at(2, 0)) / s,
            (at(1, 0) - at(0, 1)) / s)
        .normalized();
  }
  if (at(0, 0) > at(1, 1) && at(0, 0) > at(2, 2)) {
    final s = math.sqrt(1.0 + at(0, 0) - at(1, 1) - at(2, 2)) * 2;
    return Quat((at(2, 1) - at(1, 2)) / s, 0.25 * s, (at(0, 1) + at(1, 0)) / s,
            (at(0, 2) + at(2, 0)) / s)
        .normalized();
  }
  if (at(1, 1) > at(2, 2)) {
    final s = math.sqrt(1.0 + at(1, 1) - at(0, 0) - at(2, 2)) * 2;
    return Quat((at(0, 2) - at(2, 0)) / s, (at(0, 1) + at(1, 0)) / s, 0.25 * s,
            (at(1, 2) + at(2, 1)) / s)
        .normalized();
  }
  final s = math.sqrt(1.0 + at(2, 2) - at(0, 0) - at(1, 1)) * 2;
  return Quat((at(1, 0) - at(0, 1)) / s, (at(0, 2) + at(2, 0)) / s,
          (at(1, 2) + at(2, 1)) / s, 0.25 * s)
      .normalized();
}

/// Fills [p]'s inherited AxisRef / PlaneRef cache from its [AsmRef] inputs.
///
/// False when an input names something that is gone, with [AsmPattern.error]
/// set — the pattern then keeps the elements it last placed rather than
/// dropping them, for the reason resolveAsmWorkPlane keeps its last good
/// frame: an assembly mid-drag should not lose the user's work over a
/// transient.
bool _resolveInputs(AssemblyModel a, AsmPattern p) {
  AxisRef? axisOf(AsmRef? r, String label) {
    if (r == null) return null;
    final g = worldGeomOf(a, r);
    if (g.dir.length < 1e-9) return null;
    final d = g.dir.normalized();
    return AxisRef(g.at.x, g.at.y, g.at.z, d.x, d.y, d.z, label);
  }

  switch (p.mode) {
    case PatternKind.rectangular:
      if (p.driver != null) return true; // the part's feature carries its own
      final a1 = axisOf(p.refDirA, p.refDirA?.label ?? 'Direction');
      if (a1 == null) {
        p.error = 'direction 1 is gone';
        return false;
      }
      p.dirA = a1;
      p.dirB = axisOf(p.refDirB, p.refDirB?.label ?? 'Direction');
    case PatternKind.circular:
      if (p.driver != null) return true;
      final ax = axisOf(p.refAxis, p.refAxis?.label ?? 'Axis');
      if (ax == null) {
        p.error = 'the rotation axis is gone';
        return false;
      }
      p.axis = ax;
    case PatternKind.mirror:
      final r = p.refPlane;
      if (r == null) {
        p.error = 'no mirror plane';
        return false;
      }
      final g = worldGeomOf(a, r);
      if (g.dir.length < 1e-9) {
        p.error = 'the mirror plane is gone';
        return false;
      }
      // M244's trap: a plane record's own point is pl.Location(), the sketch
      // origin, which is routinely a quarter of a metre off the face. For a
      // MIRROR that is not cosmetic — the plane's position decides where the
      // copy lands — so the ANCHOR, projected onto the plane, is what is used.
      final n = g.dir.normalized();
      final o = a.byId(r.occurrence);
      final anchor = o == null ? r.anchor : o.toWorld(r.anchor);
      final on = anchor - n * ((anchor - g.at).dot(n));
      p.mirrorPlane = PlaneRef(on.x, on.y, on.z, n.x, n.y, n.z, r.label);
    case PatternKind.sketchDriven:
      p.error = 'sketch driven is not an assembly pattern';
      return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// associative: the part's own feature pattern
// ---------------------------------------------------------------------------

/// The [PatternFeature] [p]'s driver names, read LIVE out of the component's
/// borrowed model, or null when either is gone.
///
/// This is the whole of the associative feature: M245 made [o.part] the one
/// model for that document, so what comes back here is what the part currently
/// says — change the hole count in the part's own tab and the next solve lays
/// the bolts out again.
PatternFeature? driverFeatureOf(AssemblyModel a, String occurrence,
    String feature) {
  final o = a.byId(occurrence);
  final part = o?.part;
  if (part == null) return null;
  for (final f in part.features) {
    if (f.name == feature && f is PatternFeature) return f;
  }
  return null;
}

PatternFeature? _driverFeature(AssemblyModel a, AsmPattern p) =>
    driverFeatureOf(a, p.driver!.$1, p.driver!.$2);

/// Where the elements go when the layout comes from a PART's feature pattern.
///
/// The driving feature's directions are in the DRIVING COMPONENT's own frame,
/// and the copies have to be placed in the assembly's. So the feature is
/// evaluated where it lives — one call to the same [patternOccurrences] the
/// part uses, over a shallow copy with the seed's centre expressed locally —
/// and each resulting displacement is lifted out by the driver's placement.
///
/// The SEED does not have to be the driving component: bolts follow a bracket's
/// holes, and the bolt is not the bracket. That is why the reference point is
/// converted into the driver's frame rather than assumed to be its origin.
List<PatternOccurrence> _drivenOccurrences(AssemblyModel a, AsmPattern p,
    PatternFeature driven, Vec3 seedCentreWorld) {
  final host = a.byId(p.driver!.$1);
  if (host == null) return const [];
  final local = host.toLocal(seedCentreWorld);
  final placed = patternOccurrences(driven, refPoint: local);
  final out = <PatternOccurrence>[];
  for (final o in placed) {
    final m = o.mat34;
    // A feature MIRROR cannot drive an assembly pattern: it carries no
    // placement at all (part_model marks it `mirror: true` and takes the plane
    // from the feature), and reflecting a component off a plane that belongs
    // to another document is Mirror Component's job, not this one's.
    if (m == null) continue;
    if (p.suppressed.contains(o.index)) {
      // Suppression is the ASSEMBLY pattern's, not the part feature's: an
      // element switched off here must not switch off the hole it follows.
      out.add(o);
      continue;
    }
    out.add(PatternOccurrence(o.index, _liftMat34(m, host)));
  }
  return out;
}

/// [m], a rigid placement in [host]'s own frame, expressed in world.
///
/// world_move = H ∘ local_move ∘ H⁻¹, the ordinary change of basis. Written
/// out on the two halves rather than through a matrix type, because this is
/// the only place in the assembly layer that needs one and a 4x4 class for it
/// would be a maths library nobody else calls.
List<double> _liftMat34(List<double> m, AssemblyOccurrence host) {
  Vec3 lifted(Vec3 p) {
    final l = host.toLocal(p);
    final moved = Vec3(
      m[0] * l.x + m[1] * l.y + m[2] * l.z + m[3],
      m[4] * l.x + m[5] * l.y + m[6] * l.z + m[7],
      m[8] * l.x + m[9] * l.y + m[10] * l.z + m[11],
    );
    return host.toWorld(moved);
  }

  // The columns are read off the map itself — where the three unit vectors go
  // — rather than assembled from H·r·H⁻¹. It is the same answer for a rigid
  // host and it is also right for a MIRRORED one, where conjugating by a
  // reflection reverses the sense of the rotation; H·m·H⁻¹ still has
  // determinant +1 either way, so what comes back is a rigid placement.
  final t = lifted(Vec3.zero);
  final cx = lifted(const Vec3(1, 0, 0)) - t;
  final cy = lifted(const Vec3(0, 1, 0)) - t;
  final cz = lifted(const Vec3(0, 0, 1)) - t;
  return [
    cx.x, cy.x, cz.x, t.x, //
    cx.y, cy.y, cz.y, t.y, //
    cx.z, cy.z, cz.z, t.z, //
  ];
}
