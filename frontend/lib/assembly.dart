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
// What is NOT here, and why: no assembly CONSTRAINTS and no joints. An
// occurrence therefore carries a translation and nothing else — no rotation,
// because a rotation you cannot constrain is a placement you cannot undo by
// mating two faces, and half a solver is worse than none. The ribbon says the
// same thing: Joint, Constrain and the Position commands are drawn and
// disabled (see _assemblyRibbon), rather than pretending.
//
// The consequence runs all the way through this file: a placement is a Vec3,
// so every renderer and hit-test can treat a component as "the source part's
// geometry, shifted". That is what lets the assembly reuse the part's
// renderers rather than fork them — on RealityKit it is a transform on the
// solid's holder Entity (M241, see reality_assembly.dart), and on the CPU
// painter it is a shifted camera (see shiftedCam in part_render.dart).
import 'dart:math' as math;

import 'doc_file.dart' show kAssemblyDocKind;
import 'part_model.dart';
import 'part_render.dart' show PlacedComponent;

/// One placed component: a REFERENCE to a part document plus where it sits.
///
/// The geometry is not copied. [part] is the source part loaded into memory,
/// owned by this occurrence and disposed with it — two occurrences of the same
/// part each hold their own [PartModel], which is wasteful and is the honest
/// shape for now: sharing one model between occurrences only pays off once
/// occurrences can differ (representations, iParts), and neither exists yet.
class AssemblyOccurrence {
  /// Unique within the assembly, and shown in the browser: "Bracket:1".
  final String id;

  /// Document name of the placed part.
  final String source;

  /// Placement, in millimetres from the assembly origin.
  Vec3 offset;

  /// Inventor grounds the FIRST component of an assembly, so the assembly has
  /// something to be built against. A grounded occurrence cannot be dragged.
  bool grounded;

  bool visible;

  /// The loaded source part, or null while it is still being read.
  PartModel? part;

  AssemblyOccurrence({
    required this.id,
    required this.source,
    Vec3? offset,
    this.grounded = false,
    this.visible = true,
    this.part,
  }) : offset = offset ?? Vec3.zero;

  /// The solids this occurrence draws, each with the FEATURE NAME that built
  /// it, in the SOURCE part's own coordinates. Callers add [offset] themselves
  /// — see the note in the file header.
  ///
  /// ONE definition of "what a component draws". The rule (visible, built,
  /// not folded away by a boolean, not below End of Part) is the part
  /// viewport's own, and it is stated here exactly once: the CPU painter, the
  /// RealityKit payload, the bounds walk and the picker all read it from here,
  /// so a component cannot be drawn by one and missed by another.
  Iterable<(String, KernelSolid)> get namedSolids sync* {
    final p = part;
    if (p == null) return;
    for (final f in p.features) {
      if (f.visible && f.solid != null && !f.consumedByJoin && !f.rolledBack) {
        yield (f.name, f.solid!);
      }
    }
  }

  /// [namedSolids] without the names, for the painters that do not need them.
  Iterable<KernelSolid> get solids sync* {
    for (final (_, s) in namedSolids) {
      yield s;
    }
  }

  bool get loaded => part != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'src': source,
        'x': offset.x,
        'y': offset.y,
        'z': offset.z,
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
      offset: Vec3(n('x'), n('y'), n('z')),
      grounded: j['grounded'] == true,
      visible: j['visible'] != false,
    );
  }

  void dispose() {
    part?.dispose();
    part = null;
  }
}

/// An assembly document.
class AssemblyModel {
  AssemblyModel(this.name);

  String name;

  final PartCamera camera = PartCamera();

  final List<AssemblyOccurrence> occurrences = [];

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

  void remove(AssemblyOccurrence o) {
    occurrences.remove(o);
    if (identical(selected, o)) selected = null;
    o.dispose();
  }

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
  }

  void dispose() {
    for (final o in occurrences) {
      o.dispose();
    }
    occurrences.clear();
    selected = null;
  }
}

/// What the painters draw: every VISIBLE occurrence that has geometry, as
/// (placement, solids). The order is the occurrence order; the painter sorts
/// by depth itself (see [paintAssemblySolids]), and the viewport needs the
/// occurrence order preserved so it can map a painter index back to a row.
List<PlacedComponent> placedComponents(AssemblyModel a) => [
      for (final o in a.occurrences)
        if (o.visible) (o.offset, o.solids.toList())
    ];

/// World bounds of everything drawable in [a] — every visible occurrence's
/// mesh, shifted by its placement — or null when the assembly is still empty.
///
/// The part-side twin is [partContentBounds]; this one is not memoised because
/// an assembly holds a handful of occurrences rather than a timeline of
/// features, and the walk is over meshes that are already in memory.
(Vec3, Vec3)? assemblyContentBounds(AssemblyModel a) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  var any = false;
  for (final o in a.occurrences) {
    if (!o.visible) continue;
    final d = o.offset;
    for (final s in o.solids) {
      final pos = s.mesh.positions;
      for (var i = 0; i + 2 < pos.length; i += 3) {
        final x = pos[i] + d.x, y = pos[i + 1] + d.y, z = pos[i + 2] + d.z;
        if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
        any = true;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (z < minZ) minZ = z;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        if (z > maxZ) maxZ = z;
      }
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
/// no geometry. Used to frame the view on a newly placed component and as the
/// cheap first pass of the drag hit-test.
(Vec3, Vec3)? occurrenceBounds(AssemblyOccurrence o) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  var any = false;
  final d = o.offset;
  for (final s in o.solids) {
    final pos = s.mesh.positions;
    for (var i = 0; i + 2 < pos.length; i += 3) {
      final x = pos[i] + d.x, y = pos[i + 1] + d.y, z = pos[i + 2] + d.z;
      if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
      any = true;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
  }
  if (!any) return null;
  return (Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
}

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
