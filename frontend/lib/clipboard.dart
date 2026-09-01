// M345 — the clipboard: one payload, every document kind.
//
// WHAT THIS FILE IS
// -----------------
// The MODEL of a copy, and the two pure operations on it: taking a copy out of
// a sketch, and merging one back into a sketch. Nothing here touches AppState,
// the kernel, the disk or a widget — which is what lets the interesting half
// of copy/paste (what happens to constraints, layers, parameters and
// projections when geometry moves between two documents) be tested without a
// device, a part or a kernel.
//
// The COMMANDS — what Ctrl+C means in a part, where a body lands when it is
// pasted into an assembly, which plane a pasted sketch goes on — live in
// app_state.dart with every other command in this app.
//
// WHY ONE PAYLOAD AND NOT A STACK
// -------------------------------
// A system clipboard holds one thing. So does this: `AppState.clipboard` is a
// single [ClipContent] and a copy replaces whatever was in it. The app is a
// CAD editor, not a shelf — the alternative (a named library of copied
// geometry) is a different feature with a browser of its own, and inventing
// half of it here would have given the app two places where geometry waits.
//
// WHY THE PAYLOAD IS TYPED
// ------------------------
// Paste has to decide what a copy MEANS in the document it lands in: sketch
// geometry pasted into a part is a new sketch on a plane, a body pasted into
// an assembly is a component, the same body pasted into a part is a body. A
// stringly-typed blob would have pushed that decision into a chain of
// `if (looksLike…)`; a sealed class makes the matrix in [AppState.paste] a
// switch the compiler checks.
import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset, Rect;

import 'constraints.dart';
import 'ffi/qcad_engine.dart';
import 'inserts.dart';
import 'modify.dart' show transformGeo, translation;
import 'params.dart';
import 'quat.dart' show Placement;

/// One image in a clip, together with the file it is drawn from.
///
/// A [SketchImage] names its file RELATIVE to the document it lives in, so a
/// copy that carried only the record would paste a picture the target document
/// has no file for. The absolute path travels with it; the paste copies the
/// bytes into the target document and rewrites the name.
class ClipImage {
  const ClipImage(this.image, this.path);

  /// The record, as it stood in the source sketch.
  final SketchImage image;

  /// Absolute path of the file it draws, or null when it could not be found
  /// (a document deleted since the copy). Such an image is dropped on paste
  /// rather than pasted as a grey rectangle.
  final String? path;
}

/// What is on the clipboard. See the file header for why this is typed.
sealed class ClipContent {
  const ClipContent();

  /// What the copy is called where the user can see it — the toast after a
  /// copy, and the Paste row in a menu. Never a type name: "Sketch3", not
  /// "SketchClip".
  String get label;

  /// How many things were copied, for the toast. 1 for everything that is one
  /// thing; the entity count for a piece of a sketch.
  int get count => 1;
}

/// Geometry out of a sketch: a selection, or the whole of one.
///
/// The coordinates are the SOURCE SKETCH'S OWN. That is the decision the rest
/// of the paste path is built on, and it is the CAD answer rather than the
/// text-editor one: a profile copied from one plane onto another has to land
/// where its holes still line up, and "wherever the cursor happens to be" is
/// exactly what loses that. [AppState.pasteHere] is the deliberate exception,
/// and it says so in its name.
class SketchClip extends ClipContent {
  const SketchClip({
    required this.geometry,
    required this.constraints,
    required this.layers,
    required this.sourceDoc,
    required this.sourceSketch,
    required this.whole,
    this.userParams = const [],
    this.texts = const [],
    this.images = const [],
    this.hidden = const {},
    this.locked = const {},
    this.plane,
  });

  /// Deep copies. Indices inside [constraints] are LOCAL to this list.
  final List<Geo> geometry;
  final List<Constraint> constraints;

  /// Only for a [whole] clip: a partial copy leaves the sketch's parameters,
  /// texts and pictures where they are, because a selection of entities says
  /// nothing about which of them the user also meant.
  final List<UserParam> userParams;
  final List<SketchText> texts;
  final List<ClipImage> images;

  /// The layers the copied geometry sits on, in the source's order, plus (for
  /// a whole clip) their eye and padlock state.
  final List<String> layers;
  final Set<String> hidden;
  final Set<String> locked;

  /// Where it came from — for the toast, and for the name a new document made
  /// out of this clip is offered.
  final String sourceDoc;
  final String sourceSketch;

  /// True when the whole sketch was copied, false for a selection.
  final bool whole;

  /// The plane key of the child sketch this came out of ('xy', 'yz', 'xz',
  /// [kWorkPlaneKey], 'face'), or null for a standalone 2D document. Carried
  /// so that pasting a sketch back into a part can default to the plane it was
  /// drawn on when the user pastes without naming one.
  final String? plane;

  @override
  String get label => whole ? sourceSketch : '$sourceSketch ($count)';

  @override
  int get count => geometry.length;

  /// The bounding box of the copied geometry's DEFINING POINTS, or null when
  /// there is nothing with a point in it. Used to offset a paste that would
  /// otherwise land exactly on top of the original.
  Rect? get bounds {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final g in geometry) {
      for (final p in _pointsOf(g)) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }
    if (minX > maxX) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// One solid body, on its way into another part or an assembly.
///
/// It carries a STEP file rather than a live B-Rep, and that is the whole
/// design. A copied body has to survive the document it came out of being
/// closed, edited or deleted — which a pointer into that document's kernel
/// objects does not — and the paste has to produce a body the target document
/// can still read after a restart, which is exactly what an imported body is
/// (M111). So the copy writes the STEP once, and every paste reads it.
class BodyClip extends ClipContent {
  const BodyClip({
    required this.sourceDoc,
    required this.bodyName,
    required this.stepPath,
    this.volume = 0,
  });

  final String sourceDoc;
  final String bodyName;

  /// Absolute path of the STEP written when the copy was taken.
  final String stepPath;
  final double volume;

  @override
  String get label => bodyName;
}

/// One placed assembly component, on its way into an assembly.
///
/// Like Inventor's own Copy Components, this copies the OCCURRENCE and not the
/// document: the paste places a second occurrence of the same part, which is
/// what makes a copied component follow edits to the part it is an instance
/// of. Relationships are not copied — a constraint mates two named components
/// and a copy of one end of it is not constrained to anything.
class ComponentClip extends ClipContent {
  const ComponentClip({
    required this.source,
    required this.sourceKind,
    required this.placement,
    required this.sourceAssembly,
  });

  /// The document the component is an instance of, and whether that document
  /// is a part or a subassembly.
  final String source;
  final String sourceKind;

  /// Where it sat, so the copy arrives with the same orientation (and, for a
  /// mirrored component, the same handedness).
  final Placement placement;

  final String sourceAssembly;

  @override
  String get label => source;
}

/// A whole document off the gallery: a sketch, a part or an assembly.
///
/// What a paste of one means depends on where it lands — a duplicate in the
/// gallery, a placed component in an assembly — which is precisely why the
/// clipboard holds the NAME and the kind rather than a copy of the bytes.
class DocumentClip extends ClipContent {
  const DocumentClip(this.name, this.kind);

  final String name;

  /// 'sketch', 'part' or the assembly kind — the same vocabulary the gallery
  /// cards use.
  final String kind;

  @override
  String get label => name;
}

// ---------------------------------------------------------------------------
// Taking a copy out of a sketch.
// ---------------------------------------------------------------------------

/// The defining points of [g] — what the bounds and the offset are measured
/// on. A circle contributes its centre and its rim's extremes; everything else
/// contributes the points a grip can grab.
List<Offset> _pointsOf(Geo g) {
  switch (g.type) {
    case Geo.line:
      return [Offset(g.data[0], g.data[1]), Offset(g.data[2], g.data[3])];
    case Geo.circle:
    case Geo.arc:
      final c = Offset(g.data[0], g.data[1]);
      final r = g.data[2];
      return [c - Offset(r, r), c + Offset(r, r)];
    case Geo.polyline:
      final n = g.data.length >= 2 ? g.data[1].toInt() : 0;
      return [
        for (var i = 0; i < n && 3 + 2 * i < g.data.length; i++)
          Offset(g.data[2 + 2 * i], g.data[3 + 2 * i])
      ];
  }
  return const [];
}

/// A projection whose source did not come along is no longer a projection.
///
/// M32's yellow, source-tracking geometry is defined by an index into the
/// sketch it lives in (or, for [Geo.projSolid], into the part's edge list). A
/// copy that kept the tag would arrive pointing at whatever entity happens to
/// occupy that slot in the target — the one outcome worse than losing the
/// link. The two AXIS projections are the exception and are kept: every sketch
/// has an X and a Y axis, so the reference still means what it said.
Geo _rehomeProjection(Geo g, Map<int, int> remap) {
  if (!g.isProjection) return g;
  if (g.proj == Geo.projAxisX || g.proj == Geo.projAxisY) return g;
  final to = remap[g.proj];
  if (g.proj >= 0 && to != null) return g.withProj(to, g.projSeg);
  return g.withProj(Geo.projNone);
}

/// True when every reference in [c] points inside [keep].
///
/// [kProjCenter] (and any other negative sentinel) is not an entity and is
/// always in: the projected centre point exists in every sketch, so a
/// coincidence against it means the same thing in the target as it did in the
/// source — which is what grounds a pasted profile instead of leaving it
/// floating.
bool _constraintFits(Constraint c, Set<int> keep) {
  for (final p in c.pts) {
    if (p.ent >= 0 && !keep.contains(p.ent)) return false;
  }
  for (final e in c.ents) {
    if (e >= 0 && !keep.contains(e)) return false;
  }
  return true;
}

Constraint _remapConstraint(Constraint c, Map<int, int> remap) => Constraint(
      c.type,
      pts: [for (final p in c.pts) PRef(p.ent < 0 ? p.ent : remap[p.ent]!, p.pt)],
      ents: [for (final e in c.ents) e < 0 ? e : remap[e]!],
      value: c.value,
      dimKind: c.dimKind,
      textPos: c.textPos,
      driven: c.driven,
      anchors: List<double>.of(c.anchors),
      tanBranch: c.tanBranch,
      paramName: c.paramName,
      expr: c.expr,
    );

/// Takes a copy of [entities] out of [geometry]/[constraints].
///
/// [entities] null means the whole sketch. Everything is deep-copied: the
/// clipboard must not alias a document that is about to be edited (or
/// deleted), and a paste must be repeatable — the same clip pasted three times
/// produces three independent sets of geometry.
///
/// A constraint survives only when EVERY entity it names came along. That is
/// the same rule Inventor applies and the only safe one: a dimension whose
/// other end was not copied has nothing to measure to, and re-pointing it at
/// whatever sits at that index in the target is how a paste silently deforms a
/// drawing.
SketchClip sketchClip({
  required List<Geo> geometry,
  required List<Constraint> constraints,
  required List<String> layers,
  required String sourceDoc,
  required String sourceSketch,
  Set<int>? entities,
  List<UserParam> userParams = const [],
  List<SketchText> texts = const [],
  List<ClipImage> images = const [],
  Set<String> hidden = const {},
  Set<String> locked = const {},
  String? plane,
}) {
  final whole = entities == null;
  final keep = <int>{
    for (var i = 0; i < geometry.length; i++)
      if (whole || entities.contains(i)) i
  };
  final ordered = keep.toList()..sort();
  final remap = <int, int>{
    for (var i = 0; i < ordered.length; i++) ordered[i]: i
  };
  final gs = <Geo>[
    for (final i in ordered)
      _rehomeProjection(geometry[i].withData(List<double>.of(geometry[i].data)),
          remap)
  ];
  final cs = <Constraint>[
    for (final c in constraints)
      if (_constraintFits(c, keep)) _remapConstraint(c, remap)
  ];
  final used = {for (final g in gs) g.layer};
  return SketchClip(
    geometry: gs,
    constraints: cs,
    layers: [for (final l in layers) if (whole || used.contains(l)) l],
    sourceDoc: sourceDoc,
    sourceSketch: sourceSketch,
    whole: whole,
    userParams: whole
        ? [for (final u in userParams) UserParam(u.name, u.value, u.expr)]
        : const [],
    texts: whole
        ? [
            for (final t in texts)
              SketchText(t.template, t.x, t.y,
                  height: t.height, font: t.font, layer: t.layer)
          ]
        : const [],
    images: whole ? List<ClipImage>.of(images) : const [],
    hidden: whole ? {...hidden} : const {},
    locked: whole ? {...locked} : const {},
    plane: plane,
  );
}

// ---------------------------------------------------------------------------
// Merging a copy back into a sketch.
// ---------------------------------------------------------------------------

/// What a paste produced: the target's new lists, and what it had to give up.
class SketchPaste {
  const SketchPaste({
    required this.geometry,
    required this.constraints,
    required this.pasted,
    required this.texts,
    required this.renamedParams,
    required this.droppedExpressions,
  });

  /// The target sketch's geometry and constraints AFTER the paste.
  final List<Geo> geometry;
  final List<Constraint> constraints;

  /// Indices of the pasted entities in [geometry] — what the paste selects, so
  /// the next gesture moves what just arrived and nothing else.
  final List<int> pasted;

  /// Texts to append to the target (already offset).
  final List<SketchText> texts;

  /// Parameter names the paste had to change because the target already used
  /// them, old -> new. Reported rather than silent: a dimension that was d3
  /// and is now d7 is a thing the user can be looking for.
  final Map<String, String> renamedParams;

  /// Expressions that could not come along, because they referenced a
  /// parameter that was not copied and does not exist in the target. The
  /// dimension keeps its VALUE — it just stops being computed.
  final int droppedExpressions;
}

/// Rebuilds a constraint's [Constraint.anchors] from the geometry it now
/// pins, instead of translating the numbers.
///
/// A Fix on an ENTITY anchors the raw parameter list of that entity, whose
/// layout differs per type (a circle's third number is a radius, an arc's
/// fourth and fifth are angles). Translating that list by hand is a table of
/// special cases waiting to be got wrong; re-reading it off the geometry that
/// has ALREADY been translated is the same answer with nothing to maintain.
Constraint _reanchor(Constraint c, List<Geo> gs, Offset delta) {
  if (c.type == CType.fix) {
    final anchors = <double>[];
    if (c.pts.isNotEmpty && c.pts[0].ent >= 0 && c.pts[0].ent < gs.length) {
      final q = getPt(gs[c.pts[0].ent], c.pts[0].pt);
      anchors.addAll([q.dx, q.dy]);
    } else if (c.ents.isNotEmpty && c.ents[0] >= 0 && c.ents[0] < gs.length) {
      anchors.addAll(gs[c.ents[0]].data);
    } else {
      anchors.addAll(c.anchors);
    }
    return Constraint(c.type,
        pts: c.pts,
        ents: c.ents,
        value: c.value,
        dimKind: c.dimKind,
        textPos: c.textPos,
        driven: c.driven,
        anchors: anchors,
        tanBranch: c.tanBranch,
        paramName: c.paramName,
        expr: c.expr);
  }
  // A sketch pattern's anchors are its TRANSFORM: [0, dx, dy] for a
  // rectangular one — a translation of both ends leaves it unchanged — and
  // [1, cx, cy, angle] for a circular one, whose centre travels with the
  // geometry it turns.
  if (c.type == CType.pattern && c.anchors.length >= 4 && c.anchors[0] == 1) {
    final an = List<double>.of(c.anchors);
    an[1] += delta.dx;
    an[2] += delta.dy;
    return Constraint(c.type,
        pts: c.pts,
        ents: c.ents,
        value: c.value,
        dimKind: c.dimKind,
        textPos: c.textPos,
        driven: c.driven,
        anchors: an,
        tanBranch: c.tanBranch,
        paramName: c.paramName,
        expr: c.expr);
  }
  return c;
}

final RegExp _identInExpr = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

/// Merges [clip] into a target sketch.
///
/// [delta] moves the copy; zero (the default) keeps the source's coordinates —
/// see [SketchClip] for why that is the default and not "at the cursor".
///
/// [layer] forces every pasted entity onto one layer, which is what a paste
/// into a sketch that is being EDITED does: the user has a layer open, and
/// geometry arriving on layers they cannot see is geometry they will report as
/// missing. Null keeps each entity's own layer, which is what a paste into a
/// sketch that has just been CREATED for it does.
///
/// [takenNames] is every parameter name already spoken for in the target
/// (dimensions and user parameters). A collision renames the INCOMING one —
/// never the target's, which other expressions in that document may reference.
SketchPaste mergeSketchClip({
  required List<Geo> geometry,
  required List<Constraint> constraints,
  required SketchClip clip,
  Offset delta = Offset.zero,
  String? layer,
  Set<String> takenNames = const {},
}) {
  final base = geometry.length;
  final moved = delta == Offset.zero
      ? [for (final g in clip.geometry) g.withData(List<double>.of(g.data))]
      : [for (final g in clip.geometry) transformGeo(g, translation(delta))];
  final placed = [
    for (final g in moved) layer == null ? g : g.onLayer(layer)
  ];

  // Parameter names: rename what collides, then rewrite the expressions that
  // referenced the old name. Done in two passes because an expression may
  // reference a dimension that is renamed after it.
  final taken = {...takenNames};
  final renamed = <String, String>{};
  for (final c in clip.constraints) {
    final name = c.paramName;
    if (name == null) continue;
    if (!taken.contains(name)) {
      taken.add(name);
      continue;
    }
    var i = 0;
    while (taken.contains('d$i')) {
      i++;
    }
    renamed[name] = 'd$i';
    taken.add('d$i');
  }

  var dropped = 0;
  final cs = <Constraint>[];
  for (final c in clip.constraints) {
    final shifted = Constraint(
      c.type,
      pts: [for (final p in c.pts) PRef(p.ent < 0 ? p.ent : p.ent + base, p.pt)],
      ents: [for (final e in c.ents) e < 0 ? e : e + base],
      value: c.value,
      dimKind: c.dimKind,
      textPos: c.textPos == null ? null : c.textPos! + delta,
      driven: c.driven,
      anchors: List<double>.of(c.anchors),
      tanBranch: c.tanBranch,
      paramName: c.paramName == null
          ? null
          : (renamed[c.paramName] ?? c.paramName),
      expr: c.expr,
    );
    // The expression comes along only if every name in it will resolve in the
    // target: the names that travelled with the clip (possibly renamed) and
    // the names the target already has. Otherwise the dimension keeps its
    // value and stops being computed — a number that is wrong the moment
    // something else changes is worse than a number that is simply a number.
    final ex = shifted.expr;
    if (ex != null) {
      final refs = exprRefs(ex);
      final resolvable = refs.every((r) =>
          renamed.containsKey(r) ||
          taken.contains(r) ||
          takenNames.contains(r));
      if (!resolvable) {
        shifted.expr = null;
        dropped++;
      } else if (renamed.isNotEmpty) {
        shifted.expr = ex.replaceAllMapped(
            _identInExpr, (m) => renamed[m[0]] ?? m[0]!);
      }
    }
    cs.add(shifted);
  }

  final gs = [...geometry, ...placed];
  // Projection indices are relative to the clip; shift them the same way the
  // constraint references were shifted.
  for (var i = 0; i < placed.length; i++) {
    final g = gs[base + i];
    if (g.isProjection && g.proj >= 0) {
      gs[base + i] = g.withProj(g.proj + base, g.projSeg);
    }
  }
  return SketchPaste(
    geometry: gs,
    constraints: [
      ...constraints,
      for (final c in cs) _reanchor(c, gs, delta),
    ],
    pasted: [for (var i = 0; i < placed.length; i++) base + i],
    texts: [
      for (final t in clip.texts)
        SketchText(t.template, t.x + delta.dx, t.y + delta.dy,
            height: t.height,
            font: t.font,
            layer: layer ?? t.layer)
    ],
    renamedParams: renamed,
    droppedExpressions: dropped,
  );
}
