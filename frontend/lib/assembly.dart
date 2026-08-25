// M240 — the ASSEMBLY document.
//
// Inventor has three document kinds and the app had two: a 2D sketch (.pts)
// and a 3D part (.ptp). This adds the third, the assembly (.pas, Inventor's
// .iam), and it is deliberately the SMALLEST thing that is a real document:
//
//   * an occurrence list — which part is placed, how many times, and where
//   * a camera, so the view survives a tab switch and a save
//   * origin plane / axis visibility, exactly like a part's
//
// M240 shipped with no assembly CONSTRAINTS, and therefore with no rotation:
// a placement was a Vec3, because a rotation you cannot constrain is a
// placement you cannot undo by mating two faces, and half a solver is worse
// than none.
//
// M242 built the other half. An occurrence now carries a full rigid
// transform — a [Quat] and a Vec3 — and the assembly carries a list of
// [AsmConstraint]s that asm_solver.dart drives to zero. The Relationships
// folder lists them, Place Constraint creates them, and dragging a component
// goes through the solver so a mechanism follows the finger.
//
// M245 made the link to the source LIVE: an occurrence borrows the one model
// per document rather than owning a copy, so editing the part updates every
// assembly that places it. See AssemblyOccurrence.
//
// M246 let an occurrence place an ASSEMBLY. Inventor's rule is what makes
// that small: a subassembly is ONE RIGID BODY in its parent. The solver still
// sees one body per occurrence and the parent's constraints still act on the
// whole thing; what changes is only the geometry, and only in one way —
//
//     a component used to be  "these solids, at this placement"
//     a component is now      "these solids, EACH at its own placement"
//
// which is true of a part too (every feature at the identity) and is the only
// shape that can also describe a subassembly. [AssemblyOccurrence.localSolids]
// is where that is written down, once, and every renderer, picker and payload
// reads it from there.
//
// What none of that changed is the thing that makes this file small: a
// placement is still a TRANSFORM APPLIED TO THE SOURCE, never a copy of its
// geometry. Every renderer and hit-test treats a component as "the source,
// placed", which is what lets the assembly reuse the part's renderers rather
// than fork them — on RealityKit it is position + orientation on the solid's
// holder Entity (M241/M242, see reality_assembly.dart), and on the CPU
// painter it is a placed camera (see placedCam in part_render.dart).
import 'dart:math' as math;

import 'asm_constraints.dart';
import 'asm_work_features.dart';
import 'doc_file.dart' show kAssemblyDocKind;
import 'part_model.dart';
import 'quat.dart';
import 'part_render.dart' show PlacedComponent;

/// One placed component: a REFERENCE to a part document plus where it sits.
///
/// M245 — THE GEOMETRY IS BORROWED, NEVER OWNED.
///
/// M240 gave each occurrence its own [PartModel], loaded from disk when the
/// assembly opened. That made a component a SNAPSHOT: edit the part, and the
/// assembly went on drawing whatever the part had looked like when the
/// document was last opened. It is not what a component is.
///
/// [part] is now a reference to the ONE model for that document, handed over
/// by [AppState.linkOccurrences]. When the part is open in its own tab that
/// is literally the model being edited, so an extrusion added there is in
/// every assembly that places the part the moment you look — no reload, no
/// second kernel build, no copy of the mesh. When it is not open it is the
/// shared read-only load AppState keeps for exactly this.
///
/// The consequence for this class is one line long and worth stating: it must
/// not dispose what it did not allocate. See [dispose].
class AssemblyOccurrence {
  /// Unique within the assembly, and shown in the browser: "Bracket:1".
  final String id;

  /// Document name of what is placed.
  final String source;

  /// M246 — WHICH KIND of document [source] names.
  ///
  /// Inventor places parts and subassemblies through one command and lists
  /// them in one tree, and so does this. The kind is recorded rather than
  /// looked up because a component whose document has been DELETED still has
  /// to say what it was: "the part is gone" and "the subassembly is gone" are
  /// different sentences, and neither can be derived from a file that is not
  /// there.
  ///
  /// [kAssemblyDocKind] or 'part'. Absent on a document written before this
  /// existed, which then reads as a part — which is what all of them were.
  final String sourceKind;

  bool get isSubAssembly => sourceKind == kAssemblyDocKind;

  /// Placement, in millimetres from the assembly origin.
  Vec3 offset;

  /// M242 — the component's ORIENTATION.
  ///
  /// M240 left this out and said why: a rotation you cannot constrain is a
  /// placement you cannot undo by mating two faces. Constrain exists now, so
  /// the reason is gone — Mate, Angle and Insert all turn a component, and a
  /// solver that could only translate would satisfy almost nothing.
  ///
  /// The pair (rot, offset) is a rigid transform: world = rot * local + offset.
  /// [toWorld] and [dirToWorld] are the only two ways to apply it, so nowhere
  /// else has to remember which comes first.
  Quat rot;

  /// Inventor grounds the FIRST component of an assembly, so the assembly has
  /// something to be built against. A grounded occurrence cannot be dragged.
  bool grounded;

  bool visible;

  /// The source part's model — BORROWED, not owned. Null while it is still
  /// being read, when the part has been deleted from the gallery, and always
  /// when this occurrence places an assembly.
  ///
  /// Written by [AppState.linkOccurrences], which is the only thing that
  /// knows where a document's model lives.
  PartModel? part;

  /// M246 — the SUBASSEMBLY this occurrence places, borrowed the same way.
  ///
  /// Exactly one of [part] and [sub] is ever set. Both are written by
  /// [AppState.linkOccurrences] and neither is owned here — the model may be
  /// the one open in its own tab, which is what makes a change to a
  /// subassembly appear in its parent.
  AssemblyModel? sub;

  AssemblyOccurrence({
    required this.id,
    required this.source,
    this.sourceKind = 'part',
    Vec3? offset,
    Quat? rot,
    this.grounded = false,
    this.visible = true,
    this.part,
    this.sub,
  })  : offset = offset ?? Vec3.zero,
        rot = rot ?? Quat.identity;

  /// The world position of a point given in the SOURCE PART's coordinates.
  Vec3 toWorld(Vec3 local) => rot.rotate(local) + offset;

  /// The world direction of a direction given in the source part's
  /// coordinates. No translation — a direction has no position.
  Vec3 dirToWorld(Vec3 local) => rot.rotate(local);

  /// The inverse of [toWorld]: a world point in the source part's coordinates.
  ///
  /// This is what a PICK goes through. The user taps a face in world space and
  /// the constraint has to remember it in the part's own space, or the
  /// reference would stop pointing at that face the moment the component
  /// moved — which is the whole difference between a constraint and a
  /// one-off snap.
  Vec3 toLocal(Vec3 world) => rot.unrotate(world - offset);

  Vec3 dirToLocal(Vec3 world) => rot.unrotate(world);

  /// Everything this occurrence draws, in ITS OWN coordinates: a path that
  /// names the piece, the rigid transform that places it inside the
  /// component, and the solid.
  ///
  /// ONE definition of "what a component draws". The rule for a part (visible,
  /// built, not folded away by a boolean, not below End of Part) is the part
  /// viewport's own, and it is stated here exactly once: the CPU painter, the
  /// RealityKit payload, the bounds walk and the picker all read it from here,
  /// so a component cannot be drawn by one and missed by another.
  ///
  /// M246 — the inner transform is what a SUBASSEMBLY needs and a part never
  /// does. A part's features are all in the part's own space, so every one of
  /// them comes back at the identity. A subassembly's components are not: each
  /// sits somewhere inside it, and that placement composes with this
  /// occurrence's own. The recursion is what makes a subassembly of a
  /// subassembly work, and it terminates because a cycle can never be created
  /// — see AppState.placeComponent.
  ///
  /// The PATH is what keeps ids unique down the tree: "Extrusion1" for a part,
  /// "Gearbox:1/Extrusion1" one level down. The renderer keys its entity cache
  /// on it, and two occurrences of one subassembly carry the same inner names.
  Iterable<(String, Quat, Vec3, KernelSolid)> get localSolids sync* {
    final p = part;
    if (p != null) {
      for (final f in p.features) {
        if (f.visible && f.solid != null && !f.consumedByJoin && !f.rolledBack) {
          yield (f.name, Quat.identity, Vec3.zero, f.solid!);
        }
      }
      return;
    }
    final a = sub;
    if (a == null) return;
    for (final child in a.occurrences) {
      if (!child.visible) continue;
      for (final (path, r, t, solid) in child.localSolids) {
        // world_of_this_component = child_transform * inner_transform
        yield ('${child.id}/$path', (child.rot * r).normalized(),
            child.toWorld(t), solid);
      }
    }
  }

  /// [localSolids] placed in WORLD coordinates, which is what every painter,
  /// picker and payload actually wants.
  Iterable<(String, Quat, Vec3, KernelSolid)> get worldSolids sync* {
    for (final (path, r, t, solid) in localSolids) {
      yield (path, (rot * r).normalized(), toWorld(t), solid);
    }
  }

  bool get loaded => part != null || sub != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'src': source,
        // Omitted for a part, so a document holding only parts is byte-
        // identical to one written before subassemblies existed.
        if (isSubAssembly) 'kind': kAssemblyDocKind,
        'x': offset.x,
        'y': offset.y,
        'z': offset.z,
        // Omitted when there is none, so a document written before M242 and
        // one written after are byte-identical for an unrotated component.
        if (!rot.isIdentity) 'rot': rot.toJson(),
        'grounded': grounded,
        'visible': visible,
      };

  static AssemblyOccurrence? fromJson(Map j) {
    final id = j['id'] as String?;
    final src = j['src'] as String?;
    if (id == null || src == null) return null;
    double n(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return AssemblyOccurrence(
      id: id,
      source: src,
      sourceKind: j['kind'] == kAssemblyDocKind ? kAssemblyDocKind : 'part',
      offset: Vec3(n('x'), n('y'), n('z')),
      rot: Quat.fromJson(j['rot']),
      grounded: j['grounded'] == true,
      visible: j['visible'] != false,
    );
  }

  /// Drops the reference and NOTHING ELSE.
  ///
  /// The model belongs to AppState — it is very often the one open in the
  /// part's own tab — so disposing it here would take the kernel solids out
  /// from under the editor. Two occurrences of one part share one model, so
  /// it would not even be safe among occurrences.
  void dispose() {
    part = null;
    sub = null;
  }
}

/// An assembly document.
class AssemblyModel {
  AssemblyModel(this.name);

  String name;

  final PartCamera camera = PartCamera();

  final List<AssemblyOccurrence> occurrences = [];

  /// M242 — the RELATIONSHIPS: Inventor's assembly constraints, in the order
  /// they were placed. This is what the Relationships folder lists and what
  /// the solver drives to zero.
  final List<AsmConstraint> constraints = [];

  /// M247 — the assembly's OWN work features, in creation order.
  ///
  /// They belong to the .pas document and to no part in it: a work plane
  /// mating two components is not a feature of either. Three parallel lists
  /// for the reason [PartModel] gives for its three — they are not timeline
  /// nodes, they share one `seq` numbering, and the browser interleaves them
  /// by it.
  ///
  /// Unlike a part's, these are PARAMETRIC: each stores the picks it was
  /// built from as [AsmRef]s and is re-derived after every solve. See
  /// asm_work_features.dart for why that is not optional here.
  final List<AsmWorkPlane> workPlanes = [];
  final List<AsmWorkAxis> workAxes = [];
  final List<AsmWorkPoint> workPoints = [];

  /// The next free work-feature `seq`, shared across all three lists so a
  /// plane, an axis and a point never collide on a browser row id.
  ///
  /// Scanned rather than counted, so deleting the newest feature and making
  /// another does not hand out its number twice; and derived rather than
  /// stored, because an assembly holds a handful of these and a counter that
  /// had to be serialised is one more thing a hand-edited file can get wrong.
  int nextWorkSeq() {
    var n = 0;
    for (final s in [
      for (final w in workPlanes) w.seq,
      for (final x in workAxes) x.seq,
      for (final p in workPoints) p.seq,
    ]) {
      if (s > n) n = s;
    }
    return n + 1;
  }

  /// The last solve's verdict, for the browser and the status line. Runtime
  /// only — a document records what the user asked for, never how it went.
  AsmSolveSummary solveSummary = const AsmSolveSummary.empty();

  /// Origin plane / axis / centre-point visibility, same keys and same default
  /// as a part's: everything off until the browser's eye turns it on.
  final Map<String, bool> vis = {
    for (final k in kPlaneKeys) k: false,
    'x': false,
    'y': false,
    'z': false,
    'cp': false,
  };

  /// The occurrence currently selected in the viewport or the browser.
  AssemblyOccurrence? selected;

  /// M241 — the assembly's STRUCTURE generation.
  ///
  /// Bumped whenever something changes that the heavy RealityKit push has to
  /// see: a component placed or deleted, hidden or shown, grounded, or a drag
  /// ENDING (the origin planes are sized to the assembly's contents, so they
  /// are stale until the drag settles). Deliberately NOT bumped while a drag
  /// is in flight — a placement travels on the light push, and moving this
  /// would rebuild every mesh and plane sixty times a second to express a
  /// translation the renderer can apply itself. See assemblySceneSignature.
  int gen = 0;

  void bump() => gen++;

  /// Set when something happened that the CAMERA should react to — placing a
  /// component. The viewport clears it on the next frame.
  ///
  /// A flag rather than a call, because framing needs the viewport's SIZE and
  /// [AppState] has none: the widget is the only thing that knows how big the
  /// picture is. Not serialised — a saved camera is the user's, and reframing
  /// a document on open would throw away the view they left it in.
  bool needsFit = false;

  bool get isEmpty => occurrences.isEmpty;

  /// A fresh occurrence id for [source], counting the way Inventor does:
  /// "Bracket:1", then "Bracket:2".
  String nextOccurrenceId(String source) {
    var n = 1;
    while (occurrences.any((o) => o.id == '$source:$n')) {
      n++;
    }
    return '$source:$n';
  }

  AssemblyOccurrence? byId(String id) {
    for (final o in occurrences) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// M245 — renames an occurrence, carrying its relationships with it.
  ///
  /// Only a part RENAME reaches here: an occurrence is named after the
  /// document it instantiates, so when that document is renamed the
  /// occurrence has to move with it or the browser goes on showing the old
  /// name and the next placement collides with it. Every constraint that
  /// names the old id is re-pointed in the same pass — a relationship to an
  /// occurrence that no longer exists is one the solver reports sick for
  /// ever.
  void rename(AssemblyOccurrence o, String newId, String newSource) {
    if (newId == o.id && newSource == o.source) return;
    final was = o.id;
    final i = occurrences.indexOf(o);
    if (i < 0) return;
    final moved = AssemblyOccurrence(
      id: newId,
      source: newSource,
      sourceKind: o.sourceKind,
      offset: o.offset,
      rot: o.rot,
      grounded: o.grounded,
      visible: o.visible,
      part: o.part,
      sub: o.sub,
    );
    occurrences[i] = moved;
    if (identical(selected, o)) selected = moved;
    for (final c in constraints) {
      if (c.a.occurrence == was) c.a = _repoint(c.a, newId);
      if (c.b.occurrence == was) c.b = _repoint(c.b, newId);
      final third = c.c;
      if (third != null && third.occurrence == was) {
        c.c = _repoint(third, newId);
      }
    }
  }

  static AsmRef _repoint(AsmRef r, String occurrence) => AsmRef(
      occurrence, r.geom, r.label,
      anchor: r.anchor, extent: r.extent, feature: r.feature);

  void remove(AssemblyOccurrence o) {
    occurrences.remove(o);
    if (identical(selected, o)) selected = null;
    // A constraint to a component that is gone is not a constraint, it is a
    // dangling reference the solver would have to keep reporting as sick.
    // Inventor deletes them with the component, and says so in its prompt.
    constraints.removeWhere((c) => c.touches(o.id));
    // M247 — and the same for a work feature built on it. A plane whose face
    // has left the document cannot be re-derived, so keeping it would leave a
    // row that is permanently in error and a plane frozen at wherever the
    // component last was. Anything built ON that plane goes too, which is why
    // this loops until nothing more falls.
    _dropWorkFeaturesTouching({o.id});
    if (selectedConstraint != null &&
        !constraints.contains(selectedConstraint)) {
      selectedConstraint = null;
    }
    o.dispose();
  }

  /// Removes every work feature that depends, directly or through another
  /// work feature, on one of [gone] — and every constraint left naming one.
  ///
  /// Transitive because a work feature is a legitimate input to another one:
  /// dropping a plane without dropping the axis built on it would leave the
  /// axis permanently unresolvable, which is the dangling row this is here to
  /// prevent.
  void _dropWorkFeaturesTouching(Set<String> gone) {
    var again = true;
    while (again) {
      again = false;
      bool doomed(List<AsmRef> refs) => refs.any((r) =>
          (!r.isAssemblyOrigin && gone.contains(r.occurrence)) ||
          (r.feature != null && gone.contains(r.feature)));
      void sweep<T>(List<T> list, List<AsmRef> Function(T) refsOf,
          String Function(T) idOf) {
        list.removeWhere((f) {
          if (!doomed(refsOf(f))) return false;
          gone.add(idOf(f));
          again = true;
          return true;
        });
      }

      sweep<AsmWorkPlane>(workPlanes, (w) => w.refs, (w) => w.id);
      sweep<AsmWorkAxis>(workAxes, (x) => x.refs, (x) => x.id);
      sweep<AsmWorkPoint>(workPoints, (p) => p.refs, (p) => p.id);
    }
    constraints.removeWhere((c) => [c.a, c.b, if (c.c != null) c.c!]
        .any((r) => r.feature != null && gone.contains(r.feature)));
    if (selectedConstraint != null &&
        !constraints.contains(selectedConstraint)) {
      selectedConstraint = null;
    }
  }

  /// M247 — deletes one work feature, and whatever was built on it.
  void removeWorkFeature(String id) => _dropWorkFeaturesTouching({id});

  /// The constraint highlighted in the browser, if any.
  AsmConstraint? selectedConstraint;

  AsmConstraint? constraintNamed(String name) {
    for (final c in constraints) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Every constraint that touches [occurrenceId] — what Inventor nests under
  /// a component in the browser.
  List<AsmConstraint> constraintsOn(String occurrenceId) =>
      [for (final c in constraints) if (c.touches(occurrenceId)) c];

  Map<String, dynamic> toJson() => {
        'kind': kAssemblyDocKind,
        'name': name,
        'camera': {
          'az': camera.az,
          'pol': camera.pol,
          'halfH': camera.halfH,
          'ox': camera.ox,
          'oy': camera.oy,
          'roll': camera.roll,
        },
        'vis': vis,
        'occurrences': [for (final o in occurrences) o.toJson()],
        if (constraints.isNotEmpty)
          'constraints': [for (final c in constraints) c.toJson()],
        // M247 — written only when there are some, so an assembly without
        // work features is byte-identical to one saved before they existed.
        if (workPlanes.isNotEmpty)
          'workPlanes': [for (final w in workPlanes) w.toJson()],
        if (workAxes.isNotEmpty)
          'workAxes': [for (final x in workAxes) x.toJson()],
        if (workPoints.isNotEmpty)
          'workPoints': [for (final p in workPoints) p.toJson()],
      };

  /// Reads [j] into this model. Occurrences come back WITHOUT their geometry —
  /// loading a part is async and needs the kernel, so AppState does that pass
  /// after this one (see AppState.openAssembly).
  void loadJson(Map<String, dynamic> j) {
    final c = j['camera'];
    if (c is Map) {
      double n(String k, double dflt) => (c[k] as num?)?.toDouble() ?? dflt;
      camera.az = n('az', math.pi / 4);
      camera.pol = n('pol', 0.955);
      camera.halfH = PartCamera.clampHalfH(n('halfH', 27));
      camera.ox = n('ox', 0);
      camera.oy = n('oy', 0);
      camera.roll = n('roll', 0);
    }
    final v = j['vis'];
    if (v is Map) {
      for (final e in v.entries) {
        if (vis.containsKey(e.key) && e.value is bool) {
          vis[e.key as String] = e.value as bool;
        }
      }
    }
    for (final o in occurrences) {
      o.dispose();
    }
    occurrences.clear();
    for (final o in (j['occurrences'] as List? ?? const [])) {
      if (o is! Map) continue;
      final occ = AssemblyOccurrence.fromJson(o);
      if (occ != null) occurrences.add(occ);
    }
    constraints.clear();
    selectedConstraint = null;
    for (final c in (j['constraints'] as List? ?? const [])) {
      final con = AsmConstraint.fromJson(c);
      // A constraint whose components are not in this document is dropped
      // rather than kept as a permanent sick row: it can only have come from
      // a file edited by hand or truncated, and there is nothing to repair it
      // against. A constraint to a component that is MISSING FROM DISK is a
      // different case and does survive — see AppState._loadAssemblyModel.
      if (con == null) continue;
      if (con.occurrences.any((id) => byId(id) == null)) continue;
      constraints.add(con);
    }
    workPlanes.clear();
    workAxes.clear();
    workPoints.clear();
    for (final w in (j['workPlanes'] as List? ?? const [])) {
      if (w is! Map) continue;
      final f = AsmWorkPlane.fromJson(w.cast<String, dynamic>());
      if (f != null) workPlanes.add(f);
    }
    for (final x in (j['workAxes'] as List? ?? const [])) {
      if (x is! Map) continue;
      final f = AsmWorkAxis.fromJson(x.cast<String, dynamic>());
      if (f != null) workAxes.add(f);
    }
    for (final p in (j['workPoints'] as List? ?? const [])) {
      if (p is! Map) continue;
      final f = AsmWorkPoint.fromJson(p.cast<String, dynamic>());
      if (f != null) workPoints.add(f);
    }
    // A work feature whose component is not in this document is dropped for
    // the same reason a constraint is: there is nothing to re-derive it
    // against, and it can only have come from a file edited by hand.
    _dropWorkFeaturesTouching({
      for (final w in workPlanes)
        for (final r in w.refs)
          if (!r.isAssemblyOrigin && byId(r.occurrence) == null) r.occurrence,
      for (final x in workAxes)
        for (final r in x.refs)
          if (!r.isAssemblyOrigin && byId(r.occurrence) == null) r.occurrence,
      for (final p in workPoints)
        for (final r in p.refs)
          if (!r.isAssemblyOrigin && byId(r.occurrence) == null) r.occurrence,
    });
  }

  void dispose() {
    for (final o in occurrences) {
      o.dispose();
    }
    occurrences.clear();
    constraints.clear();
    workPlanes.clear();
    workAxes.clear();
    workPoints.clear();
    selected = null;
    selectedConstraint = null;
  }
}

/// What the last solve concluded, kept on the model so the browser and the
/// ribbon can read it without re-solving.
class AsmSolveSummary {
  const AsmSolveSummary({
    required this.dof,
    required this.fullyConstrained,
    required this.sickCount,
  });

  const AsmSolveSummary.empty()
      : dof = 0,
        fullyConstrained = const <String>{},
        sickCount = 0;

  /// Degrees of freedom left in the assembly.
  final int dof;

  /// Occurrences with none left.
  final Set<String> fullyConstrained;

  final int sickCount;

  bool get allConstrained => dof == 0;
}

/// What the painters draw: every VISIBLE occurrence, as the world-placed
/// pieces it is made of.
///
/// The order is the occurrence order; the painter sorts by depth itself (see
/// [paintAssemblySolids]), and the viewport needs the occurrence order
/// preserved so it can map a painter index back to a row.
List<PlacedComponent> placedComponents(AssemblyModel a) => [
      for (final o in a.occurrences)
        if (o.visible)
          PlacedComponent([
            for (final (_, r, t, s) in o.worldSolids) (r, t, s),
          ])
    ];

/// M242 — a stored reference's geometry in WORLD coordinates, right now.
///
/// An [AsmRef] names geometry in its component's own frame precisely so that
/// it keeps meaning the same thing when the component moves; everything that
/// has to DRAW it, measure it or report it needs the world form, and this is
/// the one place that conversion is written.
///
/// A reference to a component that is gone falls back to its local geometry
/// unchanged. That is the honest answer — there is no placement to apply —
/// and it keeps the browser and the dialog rendering a row that the solve
/// separately reports as sick, rather than crashing on it.
AsmGeom worldGeomOf(AssemblyModel a, AsmRef r) {
  // M247 — an assembly WORK FEATURE moves, so its reference names it by id
  // and reads the current answer rather than the frame it had when it was
  // picked. See AsmRef.feature. A feature that has been deleted falls back to
  // the stored geometry, which is what keeps a browser row rendering while
  // the solve separately reports the constraint sick.
  final wf = r.feature;
  if (wf != null) {
    final live = asmWorkGeom(a, wf);
    if (live != null) return live;
  }
  if (r.isAssemblyOrigin) return r.geom;
  final o = a.byId(r.occurrence);
  if (o == null) return r.geom;
  return AsmGeom(
    r.geom.kind,
    o.toWorld(r.geom.at),
    r.geom.dir.length < 1e-12 ? Vec3.zero : o.dirToWorld(r.geom.dir),
    radius: r.geom.radius,
  );
}

/// World bounds of everything drawable in [a] — every visible occurrence's
/// mesh, shifted by its placement — or null when the assembly is still empty.
///
/// The part-side twin is [partContentBounds]; this one is not memoised because
/// an assembly holds a handful of occurrences rather than a timeline of
/// features, and the walk is over meshes that are already in memory.
(Vec3, Vec3)? assemblyContentBounds(AssemblyModel a) => _boundsOf([
      for (final o in a.occurrences)
        if (o.visible) ...o.worldSolids
    ]);

/// World bounds of a list of placed solids, or null when there are none.
///
/// M246 — one walk, because a piece now carries its OWN transform inside its
/// component (a subassembly's parts are not at its origin) and composing that
/// with the component's in two separate loops is two chances to get it wrong.
(Vec3, Vec3)? _boundsOf(List<(String, Quat, Vec3, KernelSolid)> pieces) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  var any = false;
  for (final (_, r, t, s) in pieces) {
    final pos = s.mesh.positions;
    for (var i = 0; i + 2 < pos.length; i += 3) {
      final w = r.rotate(Vec3(pos[i], pos[i + 1], pos[i + 2])) + t;
      if (!w.x.isFinite || !w.y.isFinite || !w.z.isFinite) continue;
      any = true;
      if (w.x < minX) minX = w.x;
      if (w.y < minY) minY = w.y;
      if (w.z < minZ) minZ = w.z;
      if (w.x > maxX) maxX = w.x;
      if (w.y > maxY) maxY = w.y;
      if (w.z > maxZ) maxZ = w.z;
    }
  }
  if (!any) return null;
  return (Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
}

/// Padded bounds the assembly's origin planes and axes are drawn to — the same
/// rule a part's use, applied to the assembly's own contents.
(Vec3, Vec3) assemblyOriginExtent(AssemblyModel a) =>
    paddedOriginExtent(assemblyContentBounds(a));

/// The rectangle origin plane [key] occupies in the assembly, in its own
/// (u, v) coordinates: (uMin, uMax, vMin, vMax).
(double, double, double, double) assemblyPlaneRect(
        AssemblyModel a, String key) =>
    planeRectInBounds(assemblyOriginExtent(a), planeFrame(key));

/// How far origin axis [dir] reaches in the assembly: (lo, hi) along it.
(double, double) assemblyAxisSpan(AssemblyModel a, Vec3 dir) {
  final (lo, hi) = assemblyOriginExtent(a);
  return boxSpanAlong(lo, hi, dir);
}

/// World bounds of ONE occurrence, placement included, or null when it holds
/// no geometry. Used to frame the view on a newly placed component, to size
/// the constraint highlight, and as the cheap first pass of the drag hit-test.
(Vec3, Vec3)? occurrenceBounds(AssemblyOccurrence o) =>
    _boundsOf(o.worldSolids.toList());

/// Where a NEWLY placed occurrence goes.
///
/// Inventor drops the first component on the origin and then has you place
/// each further one with the cursor. There is no placement cursor yet, so the
/// next best thing that is never wrong: set it down clear of everything
/// already in the assembly, one gap to the +X side, so two placements of the
/// same part are two visible components rather than one solid drawn twice.
Vec3 nextPlacement(AssemblyModel a, (Vec3, Vec3)? incoming) {
  final have = assemblyContentBounds(a);
  if (have == null || incoming == null) return Vec3.zero;
  final (lo, hi) = have;
  final (ilo, ihi) = incoming;
  final width = ihi.x - ilo.x;
  // A gap of a fifth of the wider of the two, floored so tiny parts still
  // separate visibly and capped so a large one does not fly off screen.
  final gap = math.max(2.0, math.min(25.0, math.max(width, hi.x - lo.x) * 0.2));
  return Vec3(hi.x + gap - ilo.x, -ilo.y + lo.y, -ilo.z + lo.z);
}
