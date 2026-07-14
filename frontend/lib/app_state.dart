// iPadProCAD — application state (tabs, layers, edit mode, active tool) and
// persistence (DXF per sketch + preview PNG in the app Documents directory).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'constraints.dart';
import 'diag.dart';
import 'ffi/qcad_engine.dart';
import 'log.dart';
import 'modify.dart';
import 'snap.dart';
import 'solver.dart';
import 'spline.dart';
import 'theme.dart';
import 'tools.dart';

/// Drawing tools. M6: the ENTIRE Create panel draws real backend geometry
/// (splines/ellipse/equation curves sampled to polylines — spline support in
/// the core is deferred, see HANDOFF). Text/Geometry Text stay UI-only until
/// the core's text module is enabled.
enum Tool {
  none,
  line, lineMid, splineCV, splineInterp, eqCurve, bridge,
  circleCenter, circleTangent, ellipse,
  arcThreePoint, arcTangent, arcCenter,
  rectTwoPoint, rect3P, rect2PC, rect3PC,
  slotCC, slotOverall, slotCP, slot3A, slotCPA, polygon,
  fillet, chamfer, point,
  // modify tools (operate on the geometry list, engine gets rebuilt)
  move, mcopy, mrotate, mscale, mstretch, moffset, trim, extendT, split,
  // constraint tools + dimension
  cCoincident, cCollinear, cConcentric, cFix, cParallel, cPerpendicular,
  cHorizontal, cVertical, cTangent, cSmooth, cSymmetric, cEqual, dimension,
}

const constraintTools = {
  Tool.cCoincident, Tool.cCollinear, Tool.cConcentric, Tool.cFix,
  Tool.cParallel, Tool.cPerpendicular, Tool.cHorizontal, Tool.cVertical,
  Tool.cTangent, Tool.cSmooth, Tool.cSymmetric, Tool.cEqual,
};

const modifyTools = {
  Tool.move, Tool.mcopy, Tool.mrotate, Tool.mscale, Tool.mstretch,
  Tool.moffset, Tool.trim, Tool.extendT, Tool.split,
};

class SketchModel {
  final String name;
  Engine engine; // non-final: rebuilt after grip edits (C-API is add-only)
  List<Geo> geometry = [];
  final List<Constraint> constraints = [];
  final List<String> layers = []; // "Layer 1".."Layer N"
  /// Layers the eye in the model browser has switched off. Visibility is a VIEW
  /// property only — hidden geometry keeps its index, so constraint refs (which
  /// are index-based) stay valid. It is never filtered out of the geometry list.
  final Set<String> hiddenLayers = {};
  /// Layers the padlock in the model browser has locked. A locked layer is
  /// still drawn (unlike a hidden one) but cannot be edited: no tool activates
  /// on it, its geometry cannot be picked, dragged, trimmed, constrained or
  /// dimensioned, and it cannot be the current editing layer. Like visibility,
  /// this is app state that rides in the sidecar, not sketch geometry.
  final Set<String> lockedLayers = {};
  bool dirty = false;
  SketchModel(this.name) : engine = Engine.create();

  void refresh({List<Geo>? tagSource}) {
    // The backend has no spline type (R_NO_OPENNURBS), so it hands splines back
    // as plain polylines. The tag is app state (like the layer eye), so reapply
    // it by index — _rebuildEngine pushes geometry in order and allGeometry
    // returns it in the same order, so index i is the same entity across the
    // round-trip. (Save/load restores the tag from the sidecar the same way.)
    //
    // [tagSource] is the list the engine was just rebuilt FROM. It must be
    // used whenever the rebuild ADDED or REORDERED entities: restoring from
    // the previous s.geometry (the pre-commit state) silently stripped the
    // spline tag off every FRESHLY COMMITTED spline — the new entity's index
    // did not exist in the old list — which is why a spline turned into a
    // straight control polygon the moment Enter placed it.
    final prev = tagSource ?? geometry;
    // copy: an engine is free to hand out an unmodifiable list (the Dart
    // fallback does), and the re-tagging below writes into it
    final next = List<Geo>.of(engine.allGeometry());
    for (var i = 0; i < next.length && i < prev.length; i++) {
      if (prev[i].spline != Geo.straight && next[i].type == Geo.polyline) {
        next[i] = next[i].asSpline(prev[i].spline);
      }
      // the line STYLE (centerline) is app state exactly like the spline tag —
      // dropping it here rendered every centerline solid after the first edit
      if (prev[i].style != Geo.styleNormal) {
        next[i] = next[i].withStyle(prev[i].style);
      }
    }
    geometry = next;
  }
  void dispose() => engine.dispose();
}

class SavedSketchInfo {
  final String name;
  final DateTime modified;
  final File? preview;
  const SavedSketchInfo(this.name, this.modified, this.preview);
}

class AppState extends ChangeNotifier {
  // ---- navigation (home / tabs), 1:1 with the mock behaviour ----
  bool get isHome => curTab == null;
  final List<String> openTabs = [];
  String? curTab;
  int _newN = 0;
  int layerCounterOf(SketchModel s) => s.layers.length;

  final Map<String, SketchModel> sketches = {};

  // ---- layer edit mode ----
  String? editingLayer; // layer name currently in edit mode (of current tab)
  bool get inEditMode => editingLayer != null;

  // ---- active drawing tool + in-progress points (world coords) ----
  Tool tool = Tool.none;
  final List<Offset> toolPoints = [];
  Offset? hoverWorld;
  /// Entity under the cursor, and — for a polyline — the exact edge under it.
  /// Inventor highlights whatever the next click would pick; without this the
  /// user had to guess what they were about to select.
  int? hoverEnt;
  (int, int)? hoverEdge;

  // ---- viewport transform ----
  double zoom = 1.0;
  Offset pan = Offset.zero; // world offset of viewport centre

  // ---- persistence ----
  Directory? _docsDir;
  List<SavedSketchInfo> saved = [];
  String backendInfo = '';
  bool backendReal = false;

  Future<void> init() async {
    try {
      _docsDir = await Log.stepAsync('state',
          'getApplicationDocumentsDirectory (platform channel)',
          () => getApplicationDocumentsDirectory());
      Log.i('state', 'docs dir = ${_docsDir!.path}');
    } catch (e, st) {
      Log.e('state', 'docs dir failed, using systemTemp', e, st);
      _docsDir = Directory.systemTemp;
    }
    // Move the log into the SAME Documents directory as the sketches, so it is
    // actually reachable in Files > On My iPad > ipadprocad > logs. The early
    // logger uses $HOME (empty on some iOS builds -> temp dir, not file-shared).
    Log.retarget(_docsDir!.path);
    final probe = Log.step('state', 'Engine.create (backend probe)',
        () => Engine.create());
    backendReal = probe.isRealBackend;
    backendInfo = probe.version;
    probe.dispose();
    // Honest FFI smoke marker (M2-Restschuld): a real round trip through the
    // engine that is actually in use, reported truthfully.
    final smoke = Log.step('state', 'Engine.create (smoke)',
        () => Engine.create());
    smoke.addLine(0, 0, 10, 5);
    smoke.addCircle(5, 5, 2);
    final n = smoke.allGeometry().length;
    smoke.dispose();
    Log.i('smoke', n == 2
        ? 'DART SMOKE: PASS (backend=${backendReal ? "qcad-ffi" : "dart-fallback"}, $backendInfo)'
        : 'DART SMOKE: FAIL (geometry round-trip broke, backend=$backendInfo)');
    await Log.stepAsync('state', 'refreshSaved', () => refreshSaved());
    notifyListeners();
    Log.i('state', 'AppState.init done (backendReal=$backendReal)');
  }

  Directory get _sketchDir {
    final d = Directory('${_docsDir!.path}/sketches');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  File _dxfFile(String name) => File('${_sketchDir.path}/$name.dxf');
  File _pngFile(String name) => File('${_sketchDir.path}/$name.png');

  Future<void> refreshSaved() async {
    final list = <SavedSketchInfo>[];
    if (_docsDir != null && _sketchDir.existsSync()) {
      for (final f in _sketchDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dxf')) continue;
        final name = f.uri.pathSegments.last.replaceAll('.dxf', '');
        final png = _pngFile(name);
        list.add(SavedSketchInfo(
            name, f.lastModifiedSync(), png.existsSync() ? png : null));
      }
    }
    list.sort((a, b) => b.modified.compareTo(a.modified));
    saved = list;
  }

  // The six design dummies from the mock — shown only while nothing real has
  // been saved yet (first-launch design parity).
  static const dummyCards = [
    ('Bracket_v2', '24/06/2026 17:27'),
    ('Flange', '07/07/2026 10:18'),
    ('Plate_120x80', '07/07/2026 10:26'),
    ('Gasket', '29/06/2026 15:18'),
    ('Shaft_Profile', '28/06/2026 19:51'),
    ('Cam_Outline', '24/06/2026 15:50'),
  ];

  // ---- tab / home behaviour (exactly like the mock JS) ----
  void goHome() {
    curTab = null;
    finishEdit(save: true);
    _reanalyze();
    notifyListeners();
  }

  Future<void> openSketch(String name) async {
    if (!sketches.containsKey(name)) {
      final s = SketchModel(name);
      // load from disk if present
      final f = _dxfFile(name);
      if (f.existsSync()) {
        s.engine.loadDxf(f.path);
        s.refresh();
        final cf = File('${_sketchDir.path}/$name.cons.json');
        if (cf.existsSync()) {
          s.constraints.addAll(decodeConstraints(cf.readAsStringSync()));
        }
        // Spline tags: the DXF has no spline (R_NO_OPENNURBS), so a spline came
        // back from refresh() as a plain polyline. Re-tag by index (entities
        // load in save order, same as the constraint sidecar assumes).
        try {
          final sf = File('${_sketchDir.path}/$name.splines.json');
          if (sf.existsSync()) {
            final j = jsonDecode(sf.readAsStringSync()) as Map<String, dynamic>;
            j.forEach((k, v) {
              final i = int.tryParse(k);
              final kind = (v as num).toInt();
              if (i != null &&
                  i >= 0 &&
                  i < s.geometry.length &&
                  s.geometry[i].type == Geo.polyline) {
                s.geometry[i] = s.geometry[i].asSpline(kind);
              }
            });
          }
        } catch (e) {
          Log.w('state', 'spline sidecar read failed: $e');
        }
        try {
          final stf = File('${_sketchDir.path}/$name.styles.json');
          if (stf.existsSync()) {
            final j =
                jsonDecode(stf.readAsStringSync()) as Map<String, dynamic>;
            j.forEach((k, v) {
              final i = int.tryParse(k);
              if (i != null && i >= 0 && i < s.geometry.length) {
                s.geometry[i] = s.geometry[i].withStyle((v as num).toInt());
              }
            });
          }
        } catch (e) {
          Log.w('state', 'style sidecar read failed: $e');
        }
        // Layers survive in TWO places: the entity->layer binding travels in
        // the DXF (group code 8), while the display order plus empty layers and
        // the eye/lock state ride in a small sidecar. Prefer the sidecar's
        // ORDER (what the user arranged in the browser), then adopt any layer
        // that exists only in the geometry (an imported DXF, or a sketch made
        // before layers were bound).
        List<String> ordered = const [];
        final hidden = <String>{}, locked = <String>{};
        try {
          final lf = File('${_sketchDir.path}/$name.layers.json');
          if (lf.existsSync()) {
            final j = jsonDecode(lf.readAsStringSync()) as Map<String, dynamic>;
            ordered = [
              for (final l in (j['layers'] as List? ?? const [])) l as String
            ];
            hidden.addAll((j['hidden'] as List? ?? const []).cast<String>());
            locked.addAll((j['locked'] as List? ?? const []).cast<String>());
          }
        } catch (e) {
          Log.w('state', 'layer sidecar read failed: $e');
        }
        s.layers
          ..clear()
          ..addAll(ordered);
        s.hiddenLayers.addAll(hidden);
        s.lockedLayers.addAll(locked);
        _syncLayers(s); // append any geometry-only layers the sidecar missed
        _pruneEmptyBaseLayer(s); // never show an empty phantom "0"
        Log.i('layer', 'loaded "$name": layers=${s.layers} '
            'hidden=${s.hiddenLayers} locked=${s.lockedLayers}');
        analysis = analyzeSketch(s.geometry, s.constraints);
      }
      sketches[name] = s;
    }
    if (!openTabs.contains(name)) openTabs.add(name);
    curTab = name;
    _reanalyze();
    notifyListeners();
  }

  /// [analysis] is cached per solve and belongs to [current]. Switching to an
  /// ALREADY OPEN tab used to leave the previous sketch's analysis in place —
  /// which mis-coloured the DOF state and (since grips are now filtered by it)
  /// would lock the wrong points. Recompute whenever the current sketch changes.
  void _reanalyze() {
    final s = current;
    analysis = s == null ? null : analyzeSketch(s.geometry, s.constraints);
  }

  void createNewSketch() {
    _newN++;
    var name = 'Sketch$_newN';
    while (sketches.containsKey(name) || _dxfFile(name).existsSync()) {
      _newN++;
      name = 'Sketch$_newN';
    }
    openSketch(name);
  }

  Future<void> closeTab(String name) async {
    await saveSketch(name);
    openTabs.remove(name);
    if (curTab == name) {
      if (openTabs.isNotEmpty) {
        curTab = openTabs.last;
      } else {
        curTab = null;
        editingLayer = null;
      }
      _reanalyze();
    }
    notifyListeners();
  }

  SketchModel? get current => curTab == null ? null : sketches[curTab];

  // ---- layers / edit mode (mock: new layer starts edit immediately) ----
  void startNewLayer() {
    final s = current;
    if (s == null) return;
    // Next free "Layer N": counting s.layers.length breaks once layers are
    // renamed or deleted, or when the base "0" is present, and would hand out a
    // name that already exists.
    var n = 1;
    while (s.layers.contains('Layer $n')) {
      n++;
    }
    final name = 'Layer $n';
    s.layers.add(name);
    s.dirty = true;
    enterEdit(name);
  }

  bool layerVisible(String name) =>
      current?.hiddenLayers.contains(name) != true;

  /// True when [g] should be drawn / picked / snapped at all.
  bool geoVisible(Geo g) => layerVisible(g.layer);

  /// You may only TOUCH what you are editing. Being in Layer 2 must not let you
  /// trim, drag, constrain or dimension geometry that lives on Layer 1 — the
  /// layer is the editing scope, not just a paint colour. A locked layer is
  /// never editable even while it is the one in edit mode (belt and braces:
  /// [enterEdit] already refuses to enter a locked layer).
  bool geoEditable(Geo g) =>
      inEditMode && g.layer == editingLayer && !layerLocked(g.layer);

  /// True while [name] is locked (padlock in the model browser).
  bool layerLocked(String name) =>
      current?.lockedLayers.contains(name) == true;

  /// The mandatory DXF layer "0" is not a user-created layer; it always exists
  /// in the document. It may hold geometry (an old sketch or an imported DXF),
  /// but it cannot be renamed or deleted — same rule as AutoCAD.
  bool isBaseLayer(String name) => name == kDefaultLayer;

  /// A constraint (incl. dimensions) belongs to the layers of the entities it
  /// references. It is only shown when ALL of them are visible — otherwise a
  /// hidden layer would leave its dimensions floating in mid-air.
  bool constraintVisible(SketchModel s, Constraint c) {
    for (final p in c.pts) {
      if (p.ent < 0 || p.ent >= s.geometry.length) continue; // projected CP
      if (!geoVisible(s.geometry[p.ent])) return false;
    }
    for (final e in c.ents) {
      if (e < 0 || e >= s.geometry.length) continue;
      if (!geoVisible(s.geometry[e])) return false;
    }
    return true;
  }

  /// Layers that exist in the geometry but not in the layer list (sketches from
  /// before layers were bound, or a DXF from elsewhere). Without this their
  /// entities would have no row in the model browser and therefore no eye.
  void _syncLayers(SketchModel s) {
    for (final g in s.geometry) {
      if (!s.layers.contains(g.layer)) {
        Log.i('layer', 'adopting layer "${g.layer}" found in the geometry');
        s.layers.add(g.layer);
      }
    }
  }

  void toggleLayerVisible(String name) {
    final s = current;
    if (s == null) return;
    if (s.hiddenLayers.remove(name)) {
      Log.i('layer', 'show "$name"');
    } else {
      s.hiddenLayers.add(name);
      Log.i('layer', 'hide "$name"');
      // You cannot edit what you cannot see.
      if (editingLayer == name) finishEdit(save: true);
    }
    selection.removeWhere((i) =>
        i < s.geometry.length && !layerVisible(s.geometry[i].layer));
    s.dirty = true;
    notifyListeners();
  }

  void enterEdit(String layerName) {
    final s = current;
    if (s == null || !s.layers.contains(layerName)) return;
    if (layerLocked(layerName)) {
      toast('“$layerName” is locked — unlock it to edit.');
      return;
    }
    // Entering a layer that is switched off would let you draw into something
    // you cannot see; turn the eye back on first so what you draw is visible.
    if (!layerVisible(layerName)) {
      s.hiddenLayers.remove(layerName);
    }
    editingLayer = layerName;
    notifyListeners();
  }

  void finishEdit({bool save = true}) {
    if (editingLayer == null && tool == Tool.none) return;
    editingLayer = null;
    tool = Tool.none;
    toolPoints.clear();
    if (save && curTab != null) saveSketch(curTab!);
    notifyListeners();
  }

  /// Lock / unlock a layer. Locking the layer currently being edited drops you
  /// out of edit mode first (you cannot edit a locked layer). Selection is
  /// cleared of anything on the now-locked layer.
  void toggleLayerLocked(String name) {
    final s = current;
    if (s == null || !s.layers.contains(name)) return;
    if (s.lockedLayers.remove(name)) {
      Log.i('layer', 'unlock "$name"');
    } else {
      s.lockedLayers.add(name);
      Log.i('layer', 'lock "$name"');
      if (editingLayer == name) finishEdit(save: true);
      selection.removeWhere(
          (i) => i < s.geometry.length && s.geometry[i].layer == name);
    }
    s.dirty = true;
    notifyListeners();
  }

  /// Rename [oldName] to [newName]. The base layer "0" cannot be renamed. The
  /// new name must be non-empty and not already in use. Every entity on the old
  /// layer is re-stamped so the geometry follows the rename (and survives the
  /// next DXF round-trip on the new name), and the eye/lock/edit state moves
  /// across with it.
  bool renameLayer(String oldName, String newName) {
    final s = current;
    if (s == null) return false;
    newName = newName.trim();
    if (isBaseLayer(oldName)) {
      toast('The default layer “0” can’t be renamed.');
      return false;
    }
    if (isBaseLayer(newName)) {
      toast('“0” is reserved for the default layer.');
      return false;
    }
    if (!s.layers.contains(oldName)) return false;
    if (newName.isEmpty) return false;
    if (newName == oldName) return true;
    if (s.layers.contains(newName)) {
      toast('A layer named “$newName” already exists.');
      return false;
    }
    final gs = [
      for (final g in s.geometry) g.layer == oldName ? g.onLayer(newName) : g
    ];
    final idx = s.layers.indexOf(oldName);
    s.layers[idx] = newName;
    if (s.hiddenLayers.remove(oldName)) s.hiddenLayers.add(newName);
    if (s.lockedLayers.remove(oldName)) s.lockedLayers.add(newName);
    if (editingLayer == oldName) editingLayer = newName;
    Log.i('layer', 'rename "$oldName" -> "$newName"');
    _rebuildEngine(s, gs);
    if (curTab != null) saveSketch(curTab!);
    return true;
  }

  /// Delete a whole layer and everything on it. The base layer "0" cannot be
  /// deleted. All entities on the layer are removed and the index-based
  /// constraints are remapped (constraints that referenced the deleted geometry
  /// are dropped). Returns the number of entities removed.
  int deleteLayer(String name) {
    final s = current;
    if (s == null) return 0;
    if (isBaseLayer(name)) {
      toast('The default layer “0” can’t be deleted.');
      return 0;
    }
    if (!s.layers.contains(name)) return 0;

    // Remove the entities on this layer highest-index-first so each removal
    // keeps the lower indices — and the surviving constraints — valid.
    final victims = <int>[
      for (var i = 0; i < s.geometry.length; i++)
        if (s.geometry[i].layer == name) i
    ]..sort((a, b) => b.compareTo(a));
    final gs = List<Geo>.from(s.geometry);
    var cons = List<Constraint>.from(s.constraints);
    for (final i in victims) {
      gs.removeAt(i);
      cons = remapAfterRemove(cons, i);
    }
    s.constraints
      ..clear()
      ..addAll(cons);

    s.layers.remove(name);
    s.hiddenLayers.remove(name);
    s.lockedLayers.remove(name);
    if (editingLayer == name) editingLayer = null;
    selection.clear();
    Log.i('layer', 'delete "$name" (removed ${victims.length} entities)');
    _rebuildEngine(s, gs);
    if (curTab != null) saveSketch(curTab!);
    return victims.length;
  }

  /// Move the currently selected geometry onto [target]. This is how a sketch
  /// whose geometry is stranded on the wrong layer (e.g. everything on the
  /// default "0") gets sorted out: select it, then move it. Does nothing if
  /// nothing is selected or the target is locked.
  int moveSelectionToLayer(String target) {
    final s = current;
    if (s == null || !s.layers.contains(target)) return 0;
    if (selection.isEmpty) {
      toast('Select geometry first, then move it to a layer.');
      return 0;
    }
    if (layerLocked(target)) {
      toast('“$target” is locked.');
      return 0;
    }
    final sel = selection.where((i) => i >= 0 && i < s.geometry.length).toSet();
    final gs = [
      for (var i = 0; i < s.geometry.length; i++)
        sel.contains(i) ? s.geometry[i].onLayer(target) : s.geometry[i]
    ];
    Log.i('layer', 'move ${sel.length} entities -> "$target"');
    _rebuildEngine(s, gs);
    _pruneEmptyBaseLayer(s);
    selection.clear();
    if (curTab != null) saveSketch(curTab!);
    notifyListeners();
    return sel.length;
  }

  /// The mandatory "0" is not a user layer. Surface it only while it actually
  /// holds geometry; once it is emptied (e.g. its contents moved elsewhere)
  /// drop it from the browser so it never lingers as a phantom row.
  void _pruneEmptyBaseLayer(SketchModel s) {
    if (editingLayer == kDefaultLayer) return;
    if (s.geometry.any((g) => g.layer == kDefaultLayer)) return;
    if (s.layers.remove(kDefaultLayer)) {
      s.hiddenLayers.remove(kDefaultLayer);
      s.lockedLayers.remove(kDefaultLayer);
      Log.i('layer', 'dropped empty base layer "0" from the browser');
    }
  }

  // ---- selection / snapping / grip editing (M6) ----
  final Set<int> selection = {};
  Snap? snap; // current snap under the cursor (for the marker + guides)
  Grip? dragGrip;
  Offset? dragPos;
  Offset? boxStart, boxEnd; // world coords while box-selecting
  bool boxCrossing = false;
  Rect? lastBoxRect; // remembered for Stretch (Inventor semantics)
  int? modEntity; // entity picked in the first phase of Offset
  final bool autoConstrain = true; // always on (Inventor: no toggle button)
  bool showConstraints = true; // Constrain panel: Show Constraints toggle
  bool showDof = true; // Inventor: Degrees of Freedom glyphs
  SketchAnalysis? analysis; // DOF + which points may still move
  String? message; // transient notice (over-constrained warnings)

  void toggleShowDof() {
    showDof = !showDof;
    notifyListeners();
  }

  void toast(String m) {
    message = m;
    Log.i('ui', 'notice: $m');
    notifyListeners();
    Future.delayed(const Duration(seconds: 4), () {
      if (message == m) {
        message = null;
        notifyListeners();
      }
    });
  }

  void toggleAutoConstrain() {
    // Auto-constraints are always on now; no-op kept for any residual caller.
    notifyListeners();
  }

  void toggleShowConstraints() {
    showConstraints = !showConstraints;
    notifyListeners();
  }
  // constraint tool pick buffers
  final List<PRef> conPts = [];
  final List<int> conEnts = [];
  /// Polyline EDGES picked as line-like dimension participants (each edge is
  /// its two vertex refs). A rectangle side has no line-entity index, so it
  /// cannot live in conEnts — without this, point->edge and line->edge picks
  /// were dead clicks.
  final List<(PRef, PRef)> conEdges = [];
  // dimension being placed, waiting for its value dialog (viewport shows it)
  Constraint? pendingDim;

  /// Geometry with an in-progress grip drag applied (painter reads this).
  List<Geo> displayGeometry(SketchModel s) {
    if (dragGrip == null || dragPos == null) return s.geometry;
    // NB: this runs INSIDE CustomPainter.paint. A throw here aborts the whole
    // paint, so every entity after it stays unpainted and the sketch looks like
    // it vanished. Likewise NaN/Inf: Skia drops those paths silently. Neither
    // may ever escape this method.
    try {
      final grip = dragGrip!;
      final gs = List<Geo>.from(s.geometry);
      if (grip.entity < 0 || grip.entity >= gs.length) {
        Log.e('drag', 'grip points at entity ${grip.entity}, '
            'geometry has ${gs.length} — ignoring drag');
        return s.geometry;
      }
      final before = gs[grip.entity];
      gs[grip.entity] = moveGrip(before, grip, dragPos!);

      if (Log.every('drag-frame', 150)) {
        Log.d('drag',
            'frame ${gripStr(grip, s.geometry)} '
            'to=(${dragPos!.dx.toStringAsFixed(3)},'
            '${dragPos!.dy.toStringAsFixed(3)}) '
            '=> ${geoStr(grip.entity, gs[grip.entity])}');
      }
      if (!geoFinite(gs[grip.entity])) {
        Log.e('drag', 'moveGrip produced NON-FINITE geometry');
        Log.block('drag', 'moveGrip', [
          gripStr(grip, s.geometry),
          'before: ${geoStr(grip.entity, before)}',
          'after : ${geoStr(grip.entity, gs[grip.entity])}',
        ]);
        return s.geometry;
      }

      solveConstraints(gs, s.constraints,
          dragged: {(grip.entity, grip.idx)}, iterations: 25);

      if (!allFinite(gs)) {
        Log.e('drag', 'display geometry NON-FINITE after solve — '
            'showing committed geometry instead');
        Log.block('drag', 'bad display geometry',
            sketchDump(gs, s.constraints));
        return s.geometry;
      }
      return gs;
    } catch (err, st) {
      Log.e('drag', 'displayGeometry THREW — this would have blanked the '
          'viewport; showing committed geometry instead', err, st);
      Log.block('drag', 'sketch at throw',
          sketchDump(s.geometry, s.constraints));
      return s.geometry;
    }
  }

  void setSnap(Snap? sn) {
    snap = sn;
    notifyListeners();
  }

  void selectAt(Offset w, double tol) {
    final s = current;
    if (s == null) return;
    var bestI = -1;
    var bestD = tol;
    for (var i = 0; i < s.geometry.length; i++) {
      final d = distToEntity(s.geometry[i], w);
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    selection.clear();
    if (bestI >= 0) selection.add(bestI);
    notifyListeners();
  }

  void boxSelectUpdate(Offset start, Offset end) {
    boxStart = start;
    boxEnd = end;
    boxCrossing = end.dx < start.dx; // Inventor: right-to-left = crossing
    notifyListeners();
  }

  void boxSelectFinish() {
    final s = current;
    if (s != null && boxStart != null && boxEnd != null) {
      final r = Rect.fromPoints(boxStart!, boxEnd!);
      if (r.width > 1e-9 && r.height > 1e-9) {
        lastBoxRect = r;
        selection.clear();
        for (var i = 0; i < s.geometry.length; i++) {
          if (!geoVisible(s.geometry[i])) continue;
          if (entityInRect(s.geometry[i], r, crossing: boxCrossing)) {
            selection.add(i);
          }
        }
      }
    }
    boxStart = boxEnd = null;
    notifyListeners();
  }

  void clearSelection() {
    selection.clear();
    notifyListeners();
  }

  // grip drag lifecycle -------------------------------------------------
  void beginGripDrag(Grip g) {
    final a = analysis;
    final s0 = current;
    // Fresh throttles so the first frames of every drag are always recorded.
    for (final k in const [
      'drag-frame', 'solve', 'lm-ok', 'lm-fail',
      'slvs-ok', 'slvs-verify', 'slvs-bail'
    ]) {
      Log.resetThrottle(k);
    }
    Log.i('drag',
        'BEGIN ${s0 == null ? '(no sketch)' : gripStr(g, s0.geometry)}');
    if (s0 != null) {
      Log.i('drag',
          'dof=${a?.dof} freePoints={'
          '${a?.freePoints.map((f) => 'e${f.$1}.p${f.$2}').join(',') ?? '?'}}');
      Log.block('drag', 'sketch at drag start',
          sketchDump(s0.geometry, s0.constraints));
    }
    // Second line of defence (the viewport already filters the hit-test): a
    // point with no remaining freedom must not move by hand. Radius grips
    // (idx >= ptCount) are not point refs and stay draggable.
    if (a != null &&
        s0 != null &&
        g.entity < s0.geometry.length &&
        g.idx < ptCount(s0.geometry[g.entity]) &&
        !a.freePoints.contains((g.entity, g.idx))) {
      Log.i('drag', 'REFUSED: that point is fully constrained');
      return;
    }
    dragGrip = g;
    dragPos = g.pos;
    notifyListeners();
  }

  void updateGripDrag(Offset w) {
    dragPos = w;
    notifyListeners();
  }

  void endGripDrag() {
    final s = current;
    if (s != null && dragGrip != null && dragPos != null) {
      Log.i('drag',
          'END ${gripStr(dragGrip!, s.geometry)} '
          'at=(${dragPos!.dx.toStringAsFixed(3)},'
          '${dragPos!.dy.toStringAsFixed(3)})');
      try {
        _rebuildEngine(s, displayGeometry(s));
      } catch (err, st) {
        Log.e('drag', 'END: rebuild threw', err, st);
      }
      Log.block('drag', 'sketch after drag',
          sketchDump(s.geometry, s.constraints));
    }
    dragGrip = null;
    dragPos = null;
    Log.flush();
    snap = null;
    notifyListeners();
  }

  /// The C-API is add-only, so edits rebuild the document from scratch.
  void _rebuildEngine(SketchModel s, List<Geo> gsIn) {
    // Ellipses stay CANONICAL: after a grip drag or a solve, the minor vertex
    // may have drifted off the perpendicular — the renderer orthogonalizes,
    // but the stored point would float off the curve. Snap it back onto the
    // minor axis here, the one place every edit funnels through.
    final gs = [
      for (final g in gsIn)
        g.spline == Geo.ellipseTag ? normalizedEllipse(g) : g
    ];
    Log.i('engine', 'rebuild with ${gs.length} entities');
    s.engine.dispose();
    s.engine = Engine.create();
    for (final l in s.layers) {
      s.engine.setCurrentLayer(l); // make sure every layer exists in the doc
    }
    for (final g in gs) {
      // The layer must be set BEFORE the entity is added: the C-API binds the
      // entity to the CURRENT layer, and that binding is what survives the DXF
      // round-trip. An entity carrying a layer this sketch does not know is a
      // bug in some transform that dropped it — say so instead of silently
      // parking it on layer 0.
      if (!s.layers.contains(g.layer)) {
        Log.w('layer',
            'entity on unknown layer "${g.layer}" (sketch has ${s.layers}): '
            '${geoStr(-1, g)}');
      }
      s.engine.setCurrentLayer(g.layer);
      switch (g.type) {
        case Geo.line:
          s.engine.addLine(g.data[0], g.data[1], g.data[2], g.data[3]);
          break;
        case Geo.circle:
          s.engine.addCircle(g.data[0], g.data[1], g.data[2]);
          break;
        case Geo.arc:
          s.engine.addArc(g.data[0], g.data[1], g.data[2], g.data[3], g.data[4],
              reversed: g.data.length > 5 && g.data[5] != 0);
          break;
        case Geo.polyline:
          final n = g.data[1].toInt();
          s.engine.addPolyline(
              [for (var i = 0; i < n; i++) ...[g.data[2 + 2 * i], g.data[3 + 2 * i]]],
              closed: g.data[0] != 0);
          break;
      }
    }
    _committed(s, tags: gs);
    _refreshDriven(s);
    analysis = analyzeSketch(s.geometry, s.constraints);
    Log.i('engine',
        'rebuild done, geometry=${s.geometry.length}, dof=${analysis?.dof}');
  }

  // ---- tools ----
  void selectTool(Tool t) {
    // A sketch entity has to live on a layer, and the only way to know WHICH
    // layer is to be editing one. So no tool outside edit mode — that is what
    // keeps "every line belongs to exactly one layer" true by construction
    // instead of by hope.
    if (t != Tool.none && !inEditMode) {
      Log.i('tool', 'BLOCKED $t — not editing a layer');
      toast('Enter a layer to sketch: double-tap it in the model browser.');
      return;
    }
    tool = t;
    toolPoints.clear();
    notifyListeners();
  }

  /// Inventor's Esc behaviour: the first press ends the current chain / pick
  /// set but KEEPS the command running, the second exits the command, a
  /// further press clears the selection.
  void cancelTool() {
    snap = null;
    pendingDim = null;
    final hadPicks =
        toolPoints.isNotEmpty || conPts.isNotEmpty || conEnts.isNotEmpty ||
            modEntity != null;
    toolPoints.clear();
    conPts.clear();
    conEnts.clear();
    conEdges.clear();
    modEntity = null;
    if (tool != Tool.none && hadPicks) {
      notifyListeners(); // command stays active for the next chain
      return;
    }
    if (tool != Tool.none) {
      tool = Tool.none;
      notifyListeners();
      return;
    }
    selection.clear();
    notifyListeners();
  }

  // Dialog-provided tool parameters (polygon sides, fillet radius, equation
  // string + range, ...). Set by the ribbon before selectTool.
  Map<String, double> toolParams = {};
  String toolExpr = '';

  /// Handles a committed click at world coordinates for the active tool.
  /// Fixed-point tools commit automatically once enough points are picked;
  /// variable tools (splines) commit via [finishVariableTool] (Enter).
  void toolClick(Offset w) {
    final s = current;
    Log.i('click', 'toolClick tool=$tool sketch=${s?.name} '
        'w=(${w.dx.toStringAsFixed(2)},${w.dy.toStringAsFixed(2)}) '
        'picks=${toolPoints.length}');
    if (s == null || tool == Tool.none) return;
    if (!inEditMode) {
      Log.w('tool', 'toolClick with tool=$tool but NOT in edit mode — ignored');
      cancelTool();
      return;
    }
    if (modifyTools.contains(tool)) {
      _modifyClick(s, w);
      notifyListeners();
      return;
    }
    if (constraintTools.contains(tool)) {
      _constraintClick(s, w);
      notifyListeners();
      return;
    }
    if (tool == Tool.dimension) {
      _dimensionClick(s, w);
      notifyListeners();
      return;
    }
    final meta = toolMeta[tool];
    // Variable tools (splines): clicking back on the START point closes the
    // curve and commits IMMEDIATELY — that is Inventor's gesture, and it is
    // far more robust than "place a point that happens to coincide, then
    // remember to press Enter". Needs >= 3 DISTINCT points for a closed curve.
    if (meta != null && meta.fixed == null && toolPoints.length >= 3) {
      final first = toolPoints.first;
      // the click is snapped upstream, so exact equality is the normal case;
      // the world tolerance catches a click with snapping toggled off
      if ((w - first).distance < math.max(1e-9, 8 / zoom)) {
        toolPoints.add(first); // EXACT start -> buildToolGeometry closes it
        _commitTool(s);
        notifyListeners();
        return;
      }
    }
    toolPoints.add(w);
    if (meta?.fixed != null && toolPoints.length >= meta!.fixed!) {
      _commitTool(s);
    }
    notifyListeners();
  }

  /// Enter: commits a variable-length tool (splines) if it has enough points.
  void finishVariableTool() {
    final s = current;
    final meta = toolMeta[tool];
    if (s == null || meta == null || meta.fixed != null) return;
    if (toolPoints.length >= meta.minVar) _commitTool(s);
    notifyListeners();
  }

  // ---- modify tools (M6) ----
  int? _pickEntity(SketchModel s, Offset w) {
    var best = -1;
    var bd = 10 / zoom;
    for (var i = 0; i < s.geometry.length; i++) {
      if (!geoEditable(s.geometry[i])) continue; // other layers are read-only
      final d = distToEntity(s.geometry[i], w);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  void _modifyClick(SketchModel s, Offset w) {
    switch (tool) {
      case Tool.trim:
        final i = _pickEntity(s, w);
        if (i == null) return;
        final gs = List<Geo>.from(s.geometry)
          ..removeAt(i)
          ..addAll(trimEntity(s.geometry, i, w));
        final remapped = remapAfterRemove(s.constraints, i);
        s.constraints
          ..clear()
          ..addAll(remapped);
        _rebuildEngine(s, gs);
        selection.clear();
        return;
      case Tool.extendT:
        final i = _pickEntity(s, w);
        if (i == null) return;
        final e = extendEntity(s.geometry, i, w);
        if (e == null) return;
        final gs = List<Geo>.from(s.geometry)..[i] = e;
        _rebuildEngine(s, gs);
        return;
      case Tool.split:
        final i = _pickEntity(s, w);
        if (i == null) return;
        final parts = splitEntity(s.geometry, i, w);
        if (parts == null) return;
        final gs = List<Geo>.from(s.geometry)
          ..removeAt(i)
          ..addAll(parts);
        final remapped = remapAfterRemove(s.constraints, i);
        s.constraints
          ..clear()
          ..addAll(remapped);
        _rebuildEngine(s, gs);
        selection.clear();
        return;
      case Tool.moffset:
        if (modEntity == null) {
          modEntity = _pickEntity(s, w);
          return;
        }
        final o = offsetEntity(s.geometry[modEntity!], w);
        if (o != null) {
          _rebuildEngine(s, [...s.geometry, o]); // offset ADDS a copy
        }
        modEntity = null;
        return;
      case Tool.move:
      case Tool.mcopy:
      case Tool.mrotate:
      case Tool.mscale:
      case Tool.mstretch:
        if (selection.isEmpty) {
          // pick phase: taps (de)select entities until something is selected
          final i = _pickEntity(s, w);
          if (i != null) selection.add(i);
          return;
        }
        toolPoints.add(w);
        final need = (tool == Tool.mrotate || tool == Tool.mscale) ? 3 : 2;
        if (toolPoints.length < need) return;
        final f = _modifyTransform();
        if (f != null) {
          final gs = List<Geo>.from(s.geometry);
          if (tool == Tool.mcopy) {
            for (final i in selection) {
              gs.add(transformGeo(s.geometry[i], f));
            }
          } else if (tool == Tool.mstretch && lastBoxRect != null) {
            final d = toolPoints[1] - toolPoints[0];
            for (final i in selection) {
              gs[i] = stretchGeo(s.geometry[i], lastBoxRect!, d);
            }
          } else {
            for (final i in selection) {
              gs[i] = transformGeo(s.geometry[i], f);
            }
          }
          _rebuildEngine(s, gs);
        }
        toolPoints.clear();
        return;
      default:
        return;
    }
  }

  /// The transform described by the picked points of the active modify tool.
  Offset Function(Offset)? _modifyTransform() {
    switch (tool) {
      case Tool.move:
      case Tool.mcopy:
      case Tool.mstretch:
        if (toolPoints.length < 2) return null;
        return translation(toolPoints[1] - toolPoints[0]);
      case Tool.mrotate:
        if (toolPoints.length < 3) return null;
        final c = toolPoints[0];
        final a1 = math.atan2(
            toolPoints[1].dy - c.dy, toolPoints[1].dx - c.dx);
        final a2 = math.atan2(
            toolPoints[2].dy - c.dy, toolPoints[2].dx - c.dx);
        return rotation(c, a2 - a1);
      case Tool.mscale:
        if (toolPoints.length < 3) return null;
        final c = toolPoints[0];
        final r1 = (toolPoints[1] - c).distance;
        final r2 = (toolPoints[2] - c).distance;
        if (r1 < 1e-9) return null;
        return scaling(c, r2 / r1);
      default:
        return null;
    }
  }

  /// Ghost preview of the pending modify transform at [hover].
  List<Geo> modifyGhost(SketchModel s, Offset hover) {
    if (!modifyTools.contains(tool)) return const [];
    if (tool == Tool.moffset && modEntity != null) {
      final o = offsetEntity(s.geometry[modEntity!], hover);
      return o == null ? const [] : [o];
    }
    if (selection.isEmpty || toolPoints.isEmpty) return const [];
    final probe = [...toolPoints, hover];
    final saved = List<Offset>.from(toolPoints);
    toolPoints
      ..clear()
      ..addAll(probe);
    final f = _modifyTransform();
    toolPoints
      ..clear()
      ..addAll(saved);
    if (f == null) return const [];
    if (tool == Tool.mstretch && lastBoxRect != null) {
      final d = hover - toolPoints[0];
      return [
        for (final i in selection) stretchGeo(s.geometry[i], lastBoxRect!, d)
      ];
    }
    return [for (final i in selection) transformGeo(s.geometry[i], f)];
  }

  // ---- constraints + dimensions (M7) ----
  PRef? _nearestPointRef(SketchModel s, Offset w) {
    PRef? best;
    var bd = 10 / zoom;
    // The projected center point is a real pick target in Inventor — you
    // dimension and constrain against it like any vertex. It has no slot in
    // the geometry list (negative sentinel), so offer it explicitly.
    final dOrigin = w.distance;
    if (dOrigin < bd) {
      bd = dOrigin;
      best = const PRef(kProjCenter, 0);
    }
    for (var e = 0; e < s.geometry.length; e++) {
      if (!geoEditable(s.geometry[e])) continue; // other layers are read-only
      for (var p2 = 0; p2 < ptCount(s.geometry[e]); p2++) {
        final d = (getPt(s.geometry[e], p2) - w).distance;
        if (d < bd) {
          bd = d;
          best = PRef(e, p2);
        }
      }
    }
    return best;
  }

  /// Adds a geometric constraint unless it would over-constrain the sketch —
  /// Inventor shows exactly this warning and discards the constraint.
  bool _addConstraint(SketchModel s, Constraint c) {
    if (c.type == CType.fix) {
      // Fix/Lock is NOT an ordinary geometric constraint: it grounds geometry
      // exactly WHERE IT IS, so its equations are satisfied the moment they are
      // added and can never contradict what already holds (libslvs does not even
      // model it as an equation — it just marks the params fixed). Inventor
      // therefore always allows it; the only nonsense is locking twice.
      //
      // Running it through wouldOverconstrain rejected it whenever the target
      // had fewer free DOF left than Fix contributes equations (2 per point) —
      // e.g. a corner already coincident with the projected center point, or an
      // edge that is already horizontal + dimensioned. That was the "sometimes
      // I cannot apply Locked" bug.
      if (_alreadyFixed(s, c)) {
        Log.i('constraint', 'REJECTED ${conStr(-1, c)} — already locked');
        toast('This geometry is already locked.');
        return false;
      }
    } else if (wouldOverconstrain(s.geometry, s.constraints, c)) {
      Log.i('constraint',
          'REJECTED ${conStr(-1, c)} — would over-constrain');
      toast('Adding this constraint will over-constrain the sketch.');
      return false;
    }
    Log.i('constraint', 'ADD ${conStr(s.constraints.length, c)}');
    s.constraints.add(c);
    _solveAndRebuild(s);
    Log.i('constraint', 'after solve: dof=${analysis?.dof}');
    return true;
  }

  /// True when the same point (or the entity owning it) already carries a Fix.
  bool _alreadyFixed(SketchModel s, Constraint c) {
    final p = c.pts.isNotEmpty ? c.pts.first : null;
    final e = c.ents.isNotEmpty ? c.ents.first : null;
    for (final x in s.constraints) {
      if (x.type != CType.fix) continue;
      if (p != null) {
        if (x.pts.any((q) => q.ent == p.ent && q.pt == p.pt)) return true;
        if (x.ents.contains(p.ent)) return true; // whole owner locked
      }
      if (e != null && x.ents.contains(e)) return true;
    }
    return false;
  }

  void _solveAndRebuild(SketchModel s, [List<Geo>? base]) {
    final gs = List<Geo>.from(base ?? s.geometry);
    solveConstraints(gs, s.constraints);
    _rebuildEngine(s, gs);
  }

  void _constraintClick(SketchModel s, Offset w) {
    final pt = _nearestPointRef(s, w);
    final ent = _pickEntity(s, w);
    switch (tool) {
      case Tool.cCoincident:
        // First pick is always a point. The second pick decides the flavour:
        // another point -> point-on-point, a line -> point-on-line.
        if (conPts.isEmpty) {
          if (pt == null) return;
          conPts.add(pt);
          return;
        }
        if (pt != null) {
          _addConstraint(
              s, Constraint(CType.coincident, pts: [conPts[0], pt]));
          conPts.clear();
        } else if (ent != null && s.geometry[ent].type == Geo.line) {
          _addConstraint(s,
              Constraint(CType.coincident, pts: [conPts[0]], ents: [ent]));
          conPts.clear();
        }
        return;
      case Tool.cHorizontal:
      case Tool.cVertical:
        final t = tool == Tool.cHorizontal ? CType.horizontal : CType.vertical;
        // Inventor: a line -> immediately; two points -> aligned points
        if (ent != null && s.geometry[ent].type == Geo.line && conPts.isEmpty) {
          _addConstraint(s, Constraint(t, ents: [ent]));
          return;
        }
        if (pt == null) return;
        conPts.add(pt);
        if (conPts.length == 2) {
          _addConstraint(s, Constraint(t, pts: List.of(conPts)));
          conPts.clear();
        }
        return;
      case Tool.cFix:
        // Fix grounds geometry WHERE IT IS, so the anchor is captured now.
        if (pt != null) {
          final q = getPt(s.geometry[pt.ent], pt.pt);
          _addConstraint(s,
              Constraint(CType.fix, pts: [pt], anchors: [q.dx, q.dy]));
        } else if (ent != null) {
          _addConstraint(s,
              Constraint(CType.fix, ents: [ent],
                  anchors: List<double>.from(s.geometry[ent].data)));
        }
        return;
      case Tool.cSymmetric:
        // two points, then the symmetry axis line
        if (conPts.length < 2) {
          if (pt != null) conPts.add(pt);
          return;
        }
        if (ent == null || s.geometry[ent].type != Geo.line) return;
        _addConstraint(s,
            Constraint(CType.symmetric, pts: List.of(conPts), ents: [ent]));
        conPts.clear();
        return;
      case Tool.cCollinear:
      case Tool.cConcentric:
      case Tool.cParallel:
      case Tool.cPerpendicular:
      case Tool.cTangent:
      case Tool.cSmooth:
      case Tool.cEqual:
        if (ent == null) return;
        if (conEnts.isNotEmpty && conEnts[0] == ent) return;
        conEnts.add(ent);
        if (conEnts.length == 2) {
          const map = {
            Tool.cCollinear: CType.collinear,
            Tool.cConcentric: CType.concentric,
            Tool.cParallel: CType.parallel,
            Tool.cPerpendicular: CType.perpendicular,
            Tool.cTangent: CType.tangent,
            Tool.cSmooth: CType.smooth,
            Tool.cEqual: CType.equal,
          };
          final type = map[tool]!;
          if (type == CType.tangent) {
            final g1 = s.geometry[conEnts[0]];
            final g2 = s.geometry[conEnts[1]];
            bool round(int t) => t == Geo.arc || t == Geo.circle;
            bool spl(Geo g) =>
                g.type == Geo.polyline &&
                (g.spline == Geo.splineCv || g.spline == Geo.splineFit);
            if (!round(g1.type) && !round(g2.type) && !spl(g1) && !spl(g2)) {
              toast('Tangent needs at least one curved entity.');
              conEnts.clear();
              return;
            }
            if (spl(g1) || spl(g2)) {
              // Inventor's spline tangency acts at a spline ENDPOINT: the
              // end tangent (along the two defining points at that end for
              // both CV and fit splines) is made parallel to the line /
              // perpendicular to the radius / parallel to the other spline's
              // end tangent. Which end takes part is resolved HERE, at click
              // time: the end nearer to the other picked entity. A closed
              // spline has no ends.
              if ((spl(g1) && g1.data[0] != 0) ||
                  (spl(g2) && g2.data[0] != 0)) {
                toast('Tangent to a CLOSED spline is not supported.');
                conEnts.clear();
                return;
              }
              PRef endRef(int splE, int otherE) {
                final g = s.geometry[splE];
                final n = g.data[1].toInt();
                final other = s.geometry[otherE];
                final d0 = distToEntity(other, getPt(g, 0));
                final d1 = distToEntity(other, getPt(g, n - 1));
                return PRef(splE, d0 <= d1 ? 0 : n - 1);
              }

              final endPts = <PRef>[
                if (spl(g1)) endRef(conEnts[0], conEnts[1]),
                if (spl(g2)) endRef(conEnts[1], conEnts[0]),
              ];
              _addConstraint(
                  s,
                  Constraint(CType.tangent,
                      ents: List.of(conEnts), pts: endPts));
              conEnts.clear();
              return;
            }
          }
          if (type == CType.smooth) {
            // G2 means equal curvature; a straight line has none, so Inventor's
            // Smooth only makes sense between two curved entities.
            final t1 = s.geometry[conEnts[0]].type;
            final t2 = s.geometry[conEnts[1]].type;
            bool curved(int t) => t == Geo.arc || t == Geo.circle;
            if (!curved(t1) || !curved(t2)) {
              toast('Smooth (G2) needs two curved entities.');
              conEnts.clear();
              return;
            }
          }
          _addConstraint(s, Constraint(type, ents: List.of(conEnts)));
          conEnts.clear();
        }
        return;
      default:
        return;
    }
  }

  /// Inventor's dimension pick matrix. Every click either EXTENDS the pick
  /// set (when the clicked point/entity forms a valid combination with what
  /// is already picked) or PLACES the dimension at the click position.
  ///
  /// Supported combinations (all of Inventor's 2D sketch General Dimension
  /// cases for line/circle/arc/point geometry):
  ///   line                      length (aligned / horizontal / vertical,
  ///                             chosen by placement — as before)
  ///   circle | arc              diameter | radius
  ///   point + point             distance (aligned / H / V by placement)
  ///   line + point              perpendicular point-to-line distance
  ///   line + line               angle; if (near-)parallel: linear distance
  ///   circle|arc + point        distance point <-> center
  ///   circle|arc + circle|arc   distance center <-> center
  ///   circle|arc + line         perpendicular distance center <-> line
  ///   point + point + point     angle (second pick is the vertex)
  ///   polyline edge             its two vertices (as before), which then
  ///                             also combine with a third point into ang3
  void _dimensionClick(SketchModel s, Offset w) {
    if (pendingDim != null) return; // value dialog is open
    final ent = _pickEntity(s, w);
    final pt = _nearestPointRef(s, w);

    bool isCurve(int e) {
      // circles, arcs — and ELLIPSES: an ellipse participates in distance
      // dimensions through its center (vertex 0), exactly like a circle.
      final g = s.geometry[e];
      return g.type == Geo.circle ||
          g.type == Geo.arc ||
          g.spline == Geo.ellipseTag;
    }

    bool isLine(int e) => s.geometry[e].type == Geo.line;

    // What the pick set currently holds. conEnts keeps lines/circles/arcs,
    // conPts keeps point refs — mixed sets are now allowed.
    final nE = conEnts.length, nP = conPts.length;

    // ---- try to EXTEND the pick set ------------------------------------
    // A point pick ALWAYS wins over an entity pick when both are under the
    // cursor: Inventor highlights the vertex marker over the edge. Line
    // length is still one click on the BODY (away from the endpoints).
    final preferPoint = pt != null;

    if (preferPoint && !conPts.contains(pt)) {
      // ...but a line's OWN endpoint does not extend {that line} into a
      // point-to-line dimension (it would measure 0); the click places.
      final ownPoint = nE == 1 && nP == 0 && pt.ent == conEnts[0];
      final ok = !ownPoint &&
          conEdges.isEmpty && // pt+edge / line+edge are complete: click places
          ((nE == 0 && nP < 2) || //   1st/2nd point of pt-pt / ang3
              (nE == 0 && nP == 2) || // 3rd point -> 3-point angle
              (nE == 1 && nP == 0)); // line/curve + point
      if (ok) {
        conPts.add(pt);
        return;
      }
    }

    if (ent != null && !conEnts.contains(ent)) {
      final g = s.geometry[ent];
      if (g.type == Geo.polyline && g.spline != Geo.ellipseTag) {
        // A rectangle / polygon / slot is ONE closed polyline, so clicking an
        // edge picks the polyline. Resolve the click to the segment under the
        // cursor. As the FIRST pick, the edge is its two vertices: that is a
        // real DRIVING length dimension via the point-to-point path
        // (aligned/H/V at placement), and the pair combines with a further
        // point pick to a 3-point angle. Picked AFTER a point, a line, a
        // curve, or another edge, the edge acts as a LINE (Inventor): those
        // combinations used to be dead clicks, because an edge has no
        // line-entity index for conEnts — they now go to conEdges.
        // A SPLINE's "segments" are control-polygon edges, not geometry —
        // their length is meaningless, so a spline never picks an edge.
        if (!g.isSpline && conEdges.isEmpty) {
          final seg = polySegmentAt(s, ent, w);
          if (seg != null) {
            if (nE == 0 && nP == 0) {
              conPts
                ..add(seg.$1)
                ..add(seg.$2);
              return;
            }
            // point + edge -> perpendicular distance; line/curve + edge ->
            // distance or angle; edge + edge (the first one is the picked
            // conPts pair) -> angle / parallel gap
            final edgeExtends = (nE == 1 && nP == 0) || //  line/curve + edge
                (nE == 0 && nP == 1) || //                  point + edge
                (nE == 0 && nP == 2 && pickedEdge != null); // edge + edge
            if (edgeExtends &&
                !(nP == 1 && conPts[0].ent == ent) && // own vertex: place
                !(nP == 2 &&
                    pickedEdge != null &&
                    conPts[0].ent == ent &&
                    seg.$1.pt == conPts[0].pt &&
                    seg.$2.pt == conPts[1].pt)) { //   same edge again: place
              conEdges.add(seg);
              return;
            }
          }
        }
      } else if (nP == 0 && nE == 0 && conEdges.isEmpty) {
        conEnts.add(ent); //                   first pick: line/circle/arc
        return;
      } else if (nP == 0 && nE == 1 && conEdges.isEmpty) {
        // second entity: any line/circle/arc pairing is dimensionable
        conEnts.add(ent);
        return;
      } else if (nP == 1 && nE == 0 && conEdges.isEmpty &&
          (isLine(ent) || isCurve(ent))) {
        conEnts.add(ent); //                   point + line/curve
        return;
      } else if (nE == 0 && conEdges.length == 1 &&
          (nP == 0 || (nP == 2 && pickedEdge != null)) &&
          (isLine(ent) || isCurve(ent))) {
        // ...the mirrored order: edge first (as conPts pair), then a
        // line/curve entity — same combinations as above
        conEnts.add(ent);
        return;
      }
      // silently fall through to placement — matches Inventor, where a click
      // that cannot extend the selection places the pending dimension
    }

    // ---- otherwise this click PLACES the dimension ---------------------
    if (nE + nP + conEdges.length == 0) {
      return; // nothing picked yet, click hit empty space
    }
    _placeDimension(s, w);
  }

  /// The two vertex refs of the polyline segment of [ent] nearest to [w].
  (PRef, PRef)? polySegmentAt(SketchModel s, int ent, Offset w) {
    if (ent < 0 || ent >= s.geometry.length) return null;
    final g = s.geometry[ent];
    if (g.type != Geo.polyline) return null;
    final n = g.data[1].toInt();
    if (n < 2) return null;
    final segs = g.data[0] != 0 ? n : n - 1; // closed -> the last edge exists
    var best = -1;
    var bd = double.infinity;
    for (var i = 0; i < segs; i++) {
      final a = getPt(g, i), b = getPt(g, (i + 1) % n);
      final d = (w - closestOnSegment(w, a, b)).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (best < 0) return null;
    return (PRef(ent, best), PRef(ent, (best + 1) % n));
  }

  /// The polyline edge the active tool currently holds picked (two adjacent
  /// vertices of one polyline) — the viewport keeps it highlighted.
  (int, int)? get pickedEdge {
    final s = current;
    if (s == null || conPts.length != 2) return null;
    final a = conPts[0], b = conPts[1];
    if (a.ent != b.ent || a.ent < 0 || a.ent >= s.geometry.length) return null;
    final g = s.geometry[a.ent];
    if (g.type != Geo.polyline) return null;
    final n = g.data[1].toInt();
    if (n > 0 && (a.pt + 1) % n == b.pt) return (a.ent, a.pt);
    return null;
  }

  /// Inventor's placement rule for a two-point dimension: drag ABOVE/BELOW
  /// the pair's bounding box -> horizontal distance, drag LEFT/RIGHT of it ->
  /// vertical distance, drag out along the pair's direction (diagonal
  /// region / near the normal) -> aligned. This is decided per placement
  /// position, so sweeping the preview around the two points cycles through
  /// all three variants exactly like Inventor.
  String _distKind(SketchModel s, PRef a, PRef b, Offset at) {
    final pa = refPt(s.geometry, a);
    final pb = refPt(s.geometry, b);
    final d = pb - pa;
    if (d.distance < 1e-9) return 'dist';
    final minX = math.min(pa.dx, pb.dx), maxX = math.max(pa.dx, pb.dx);
    final minY = math.min(pa.dy, pb.dy), maxY = math.max(pa.dy, pb.dy);
    final insideX = at.dx >= minX && at.dx <= maxX;
    final insideY = at.dy >= minY && at.dy <= maxY;
    if (insideX && !insideY) return 'distx'; // above/below -> horizontal
    if (insideY && !insideX) return 'disty'; // left/right  -> vertical
    // diagonal quadrants / degenerate: fall back to the normal test —
    // within 30 deg of the pair's normal reads as aligned, otherwise pick
    // the axis the cursor pulled towards
    final n = Offset(-d.dy, d.dx) / d.distance;
    final v = at - (pa + pb) / 2;
    if (v.distance < 1e-9) return 'dist';
    final vn = v / v.distance;
    if ((vn.dx * n.dx + vn.dy * n.dy).abs() > 0.866) return 'dist';
    return v.dy.abs() >= v.dx.abs() ? 'distx' : 'disty';
  }

  void _placeDimension(SketchModel s, Offset w) {
    final d = buildDimensionAt(s, w);
    if (d == null) return;
    pendingDim = d;
  }

  /// Builds the dimension implied by the current pick set, placed at [w].
  /// Shared by placement and by the live cursor preview.
  Constraint? buildDimensionAt(SketchModel s, Offset w) {
    bool isCurve(int e) {
      // circles, arcs — and ELLIPSES: an ellipse participates in distance
      // dimensions through its center (vertex 0), exactly like a circle.
      final g = s.geometry[e];
      return g.type == Geo.circle ||
          g.type == Geo.arc ||
          g.spline == Geo.ellipseTag;
    }

    // A curve participates in distance dimensions through its CENTER point
    // (Inventor's default; tangent-edge variants are a possible later
    // refinement). getPt(circle/arc, 0) is the center.
    PRef center(int e) => PRef(e, 0);

    Constraint? d;
    if (conEdges.length == 1) {
      // ---- a polyline EDGE participates as a line -----------------------
      final (ea, eb) = conEdges[0];
      bool edgeParallelTo(Offset da) {
        final de = refPt(s.geometry, eb) - refPt(s.geometry, ea);
        final m = da.distance * de.distance;
        if (m < 1e-12) return false;
        return (da.dx * de.dy - da.dy * de.dx).abs() / m < 0.0087;
      }

      if (conPts.length == 1 && conEnts.isEmpty) {
        // point + edge -> perpendicular point-to-edge distance
        d = Constraint(CType.dimension,
            pts: [conPts[0], ea, eb], dimKind: 'pline', textPos: w);
      } else if (conEnts.length == 1) {
        final e = conEnts[0];
        if (isCurve(e)) {
          // circle/arc/ellipse + edge -> distance center <-> edge
          d = Constraint(CType.dimension,
              pts: [center(e), ea, eb], dimKind: 'pline', textPos: w);
        } else {
          // line + edge: parallel -> linear gap, otherwise angle (ang4:
          // the edge has no line-entity ref, so the angle runs over points)
          final g = s.geometry[e];
          final dl = getPt(g, 1) - getPt(g, 0);
          d = edgeParallelTo(dl)
              ? Constraint(CType.dimension,
                  pts: [PRef(e, 0), ea, eb], dimKind: 'pline', textPos: w)
              : Constraint(CType.dimension,
                  pts: [PRef(e, 0), PRef(e, 1), ea, eb],
                  dimKind: 'ang4',
                  textPos: w);
        }
      } else if (conPts.length == 2) {
        // edge + edge (the first edge is the picked vertex pair)
        final a0 = conPts[0], a1 = conPts[1];
        final da = refPt(s.geometry, a1) - refPt(s.geometry, a0);
        d = edgeParallelTo(da)
            ? Constraint(CType.dimension,
                pts: [a0, ea, eb], dimKind: 'pline', textPos: w)
            : Constraint(CType.dimension,
                pts: [a0, a1, ea, eb], dimKind: 'ang4', textPos: w);
      }
    } else if (conEnts.length == 2) {
      final e1 = conEnts[0], e2 = conEnts[1];
      final c1 = isCurve(e1), c2 = isCurve(e2);
      if (c1 && c2) {
        // circle/arc + circle/arc -> center-to-center distance
        final a = center(e1), b = center(e2);
        d = Constraint(CType.dimension,
            pts: [a, b], dimKind: _distKind(s, a, b, w), textPos: w);
      } else if (c1 || c2) {
        // circle/arc + line -> perpendicular distance center <-> line
        final ce = c1 ? e1 : e2, le = c1 ? e2 : e1;
        d = Constraint(CType.dimension,
            pts: [center(ce), PRef(le, 0), PRef(le, 1)],
            dimKind: 'pline',
            textPos: w);
      } else if (_linesParallel(s, e1, e2)) {
        // two (near-)parallel lines -> linear distance, like Inventor. The
        // measured point is an endpoint of the SECOND pick; driving this
        // value together with a Parallel constraint fully defines the gap.
        d = Constraint(CType.dimension,
            pts: [PRef(e2, 0), PRef(e1, 0), PRef(e1, 1)],
            dimKind: 'pline',
            textPos: w);
      } else {
        d = Constraint(CType.dimension,
            ents: List.of(conEnts), dimKind: 'ang', textPos: w);
      }
    } else if (conEnts.length == 1 && conPts.length == 1) {
      final e = conEnts[0];
      if (isCurve(e)) {
        // point + circle/arc -> distance point <-> center
        final a = conPts[0], b = center(e);
        d = Constraint(CType.dimension,
            pts: [a, b], dimKind: _distKind(s, a, b, w), textPos: w);
      } else {
        // point + line -> perpendicular point-to-line distance
        d = Constraint(CType.dimension,
            pts: [conPts[0], PRef(e, 0), PRef(e, 1)],
            dimKind: 'pline',
            textPos: w);
      }
    } else if (conEnts.length == 1) {
      final g = s.geometry[conEnts[0]];
      if (g.type == Geo.circle) {
        d = Constraint(CType.dimension,
            ents: List.of(conEnts), dimKind: 'dia', textPos: w);
      } else if (g.type == Geo.arc) {
        d = Constraint(CType.dimension,
            ents: List.of(conEnts), dimKind: 'rad', textPos: w);
      } else if (g.type == Geo.line) {
        final a = PRef(conEnts[0], 0), b = PRef(conEnts[0], 1);
        d = Constraint(CType.dimension,
            pts: [a, b], dimKind: _distKind(s, a, b, w), textPos: w);
      }
    } else if (conPts.length == 3) {
      // 3-point angle, second pick is the vertex (Inventor's order)
      d = Constraint(CType.dimension,
          pts: List.of(conPts), dimKind: 'ang3', textPos: w);
    } else if (conPts.length == 2) {
      d = Constraint(CType.dimension,
          pts: List.of(conPts),
          dimKind: _distKind(s, conPts[0], conPts[1], w),
          textPos: w);
    }
    if (d == null) return null;
    d.value = measureDim(s.geometry, d);
    return d;
  }

  /// Whether two line entities are parallel within Inventor's snap tolerance
  /// (~0.5 deg) — decides linear distance vs. angle for a line+line pick.
  bool _linesParallel(SketchModel s, int e1, int e2) {
    final g1 = s.geometry[e1], g2 = s.geometry[e2];
    final d1 = getPt(g1, 1) - getPt(g1, 0);
    final d2 = getPt(g2, 1) - getPt(g2, 0);
    final m = d1.distance * d2.distance;
    if (m < 1e-12) return false;
    final sinA = (d1.dx * d2.dy - d1.dy * d2.dx).abs() / m;
    return sinA < 0.0087; // sin(0.5 deg)
  }

  /// The dimension that would be placed if the user clicked at [hover] now —
  /// used to draw a live preview that follows the cursor (Inventor style).
  Constraint? dimensionPreview(Offset hover) {
    if (tool != Tool.dimension || pendingDim != null) return null;
    final s = current;
    if (s == null) return null;
    if (conEnts.isEmpty && conPts.length < 2 && conEdges.isEmpty) return null;
    return buildDimensionAt(s, hover);
  }

  /// Constraints that WOULD be applied if the current preview were committed
  /// — Inventor shows these as symbols next to the cursor while sketching.
  List<CType> inferredHints(SketchModel s, Offset hover) {
    if (!autoConstrain || tool == Tool.none || toolPoints.isEmpty) {
      return const [];
    }
    if (modifyTools.contains(tool) || constraintTools.contains(tool)) {
      return const [];
    }
    final geos = buildToolGeometry(tool, [...toolPoints, hover],
        existing: s.geometry, params: toolParams, expr: toolExpr);
    if (geos == null || geos.isEmpty) return const [];
    final gs = [...s.geometry, ...geos];
    final out = <CType>[];
    for (var i = s.geometry.length; i < gs.length; i++) {
      for (final c in inferConstraints(gs, i)) {
        if (!out.contains(c.type)) out.add(c.type);
      }
    }
    return out;
  }

  /// Trim hover preview: the entity plus what would survive the cut, so the
  /// viewport can paint the doomed span red (Inventor's trim highlight).
  (Geo, List<Geo>)? trimPreview(Offset w) {
    final s = current;
    if (s == null || tool != Tool.trim) return null;
    final i = _pickEntity(s, w);
    if (i == null) return null;
    return (s.geometry[i], trimEntity(s.geometry, i, w));
  }

  /// True when the pending dimension would over-constrain the sketch — the
  /// viewport then offers Inventor's driven (reference) dimension.
  bool get pendingDimRedundant {
    final s = current;
    final d = pendingDim;
    if (s == null || d == null) return false;
    return wouldOverconstrain(s.geometry, s.constraints, d);
  }

  /// Called by the viewport once the user confirmed the dimension.
  /// [driven] keeps it as a reference dimension (shown in parentheses).
  void confirmDimension(double? value, {bool driven = false}) {
    final s = current;
    final d = pendingDim;
    pendingDim = null;
    conPts.clear();
    conEnts.clear();
    conEdges.clear();
    if (s == null || d == null) {
      notifyListeners();
      return;
    }
    d.driven = driven;
    d.value = driven
        ? measureDim(s.geometry, d)
        : (value ?? measureDim(s.geometry, d));
    s.constraints.add(d);
    _solveAndRebuild(s);
    notifyListeners();
  }

  void cancelDimension() {
    pendingDim = null;
    conPts.clear();
    conEnts.clear();
    conEdges.clear();
    notifyListeners();
  }

  /// SCREEN rects of the dimension labels as the painter last drew them
  /// (filled during paint, read by the viewport's tap hit-test). For 'dist'
  /// kinds the label is drawn at a recomputed spot, not at textPos — this is
  /// the only place that knows where the text really is.
  final List<(Constraint, Rect)> dimLabelRects = [];

  /// Edits an existing dimension's value (tap on its text, no tool active).
  Constraint? dimensionAt(Offset w, double tol) {
    final s = current;
    if (s == null) return null;
    for (final c in s.constraints) {
      if (c.type == CType.dimension &&
          c.textPos != null &&
          (c.textPos! - w).distance < tol) {
        return c;
      }
    }
    return null;
  }

  void setDimensionValue(Constraint c, double v) {
    final s = current;
    if (s == null) return;
    if (c.driven) {
      toast('This is a driven (reference) dimension — it cannot be edited.');
      return;
    }
    final old = c.value;
    c.value = v;
    _solveAndRebuild(s);
    // a driving dimension must actually be reachable; if the solver could not
    // satisfy it, roll back instead of leaving the sketch mangled
    if ((measureDim(s.geometry, c) - v).abs() > 1e-3) {
      c.value = old;
      _solveAndRebuild(s);
      toast('Value cannot be satisfied with the current constraints.');
    }
    notifyListeners();
  }

  /// Driven dimensions track the geometry, so refresh their measured values.
  void _refreshDriven(SketchModel s) {
    for (final c in s.constraints) {
      if (c.type == CType.dimension && c.driven) {
        c.value = measureDim(s.geometry, c);
      }
    }
  }

  void _commitTool(SketchModel s) {
    // Fillet/Chamfer edit the two picked lines as well: Inventor trims them
    // back to the tangent points instead of leaving the corner sticking out.
    if ((tool == Tool.fillet || tool == Tool.chamfer) &&
        toolPoints.length >= 2) {
      final res = filletChamferFull(s.geometry, toolPoints[0], toolPoints[1],
          radius: toolParams[tool == Tool.fillet ? 'radius' : 'dist'] ?? 5,
          chamfer: tool == Tool.chamfer);
      toolPoints.clear();
      if (res == null) {
        toast('Pick two non-parallel lines that meet.');
        return;
      }
      final gs = List<Geo>.from(s.geometry);
      res.$2.forEach((i, g) => gs[i] = g);
      gs.addAll(res.$1); // already carries the picked lines' layer

      solveConstraints(gs, s.constraints);
      _rebuildEngine(s, gs);
      return;
    }
    final geos = buildToolGeometry(tool, List.of(toolPoints),
        existing: s.geometry, params: toolParams, expr: toolExpr);
    if (geos != null) {
      // The ONE place new geometry enters the sketch — stamp the layer here and
      // nothing can ever be layerless. toolClick already refuses to run outside
      // edit mode, so editingLayer is non-null.
      final layer = editingLayer;
      if (layer == null) {
        Log.e('layer', 'commit with no editing layer — dropping the geometry');
        toolPoints.clear();
        return;
      }
      final placed = [for (final g in geos) g.onLayer(layer)];
      Log.i('layer', 'commit ${placed.length} entities onto "$layer"');
      final gs = List<Geo>.from(s.geometry)..addAll(placed);
      final firstNew = s.geometry.length;
      if (autoConstrain) {
        for (var i = firstNew; i < gs.length; i++) {
          s.constraints.addAll(inferConstraints(gs, i));
        }
      }
      if (tool == Tool.ellipse &&
          placed.length == 1 &&
          placed[0].spline == Geo.ellipseTag) {
        _addEllipseAxes(s, gs, firstNew, layer);
      }
      solveConstraints(gs, s.constraints);
      _rebuildEngine(s, gs);
    }
    // CAD-style chaining for plain lines: next line starts at the endpoint
    if (tool == Tool.line && toolPoints.length >= 2) {
      final last = toolPoints.last;
      toolPoints
        ..clear()
        ..add(last);
    } else {
      toolPoints.clear();
    }
  }

  /// Inventor's Format > Centerline toggle: flips the line style of the
  /// current selection. Mixed selections turn INTO centerlines first (like
  /// Inventor); a second toggle turns them back.
  void toggleCenterlineSelected() {
    final s = current;
    if (s == null || selection.isEmpty) return;
    final gs = List<Geo>.from(s.geometry);
    final toCenter =
        selection.any((i) => i < gs.length && gs[i].style == Geo.styleNormal);
    for (final i in selection) {
      if (i >= gs.length) continue;
      gs[i] = gs[i]
          .withStyle(toCenter ? Geo.styleCenterline : Geo.styleNormal);
    }
    _rebuildEngine(s, gs);
    notifyListeners();
  }

  /// Creates the two AXIS CENTERLINES of a freshly committed ellipse and
  /// binds them to it, Inventor-style: real line entities (movable,
  /// dimensionable, constrainable), rendered dashed via the centerline
  /// style, and kept on the ellipse by the solver —
  ///   coincident(axis end A, ellipse quadrant vertex) x2
  ///   midpoint(ellipse CENTER on axis line)           x2
  /// Together that is 8 LINEAR equations for the 8 new line parameters, so
  /// the axes are fully determined by the ellipse and never over-constrain
  /// it. (An earlier symmetric-about-the-other-axis formulation coupled the
  /// two axes nonlinearly and reliably trapped the LM solver in a local
  /// minimum ~0.3% off; midpoint is linear and slvs-native, SH_MIDPOINT.)
  /// Dragging an axis endpoint therefore drives the ellipse through the
  /// solver, and both axes are legitimate dimension/constraint targets.
  void _addEllipseAxes(
      SketchModel s, List<Geo> gs, int ellipseIdx, String layer) {
    final e = gs[ellipseIdx];
    final c = Offset(e.data[2], e.data[3]);
    final ma = Offset(e.data[4], e.data[5]);
    final mi = Offset(e.data[6], e.data[7]);
    final major = Geo(
            Geo.line, [ma.dx, ma.dy, (c * 2 - ma).dx, (c * 2 - ma).dy])
        .onLayer(layer)
        .withStyle(Geo.styleCenterline);
    final minor = Geo(
            Geo.line, [mi.dx, mi.dy, (c * 2 - mi).dx, (c * 2 - mi).dy])
        .onLayer(layer)
        .withStyle(Geo.styleCenterline);
    final iMaj = gs.length, iMin = gs.length + 1;
    gs..add(major)..add(minor);
    s.constraints.addAll([
      Constraint(CType.coincident, pts: [PRef(iMaj, 0), PRef(ellipseIdx, 1)]),
      Constraint(CType.coincident, pts: [PRef(iMin, 0), PRef(ellipseIdx, 2)]),
      Constraint(CType.midpoint,
          pts: [PRef(ellipseIdx, 0)], ents: [iMaj]),
      Constraint(CType.midpoint,
          pts: [PRef(ellipseIdx, 0)], ents: [iMin]),
    ]);
    Log.i('layer', 'ellipse axes committed as centerlines ($iMaj, $iMin)');
  }

  void _committed(SketchModel s, {List<Geo>? tags}) {
    s.refresh(tagSource: tags);
    _syncLayers(s);
    s.dirty = true;
  }

  void setHover(Offset? w) {
    hoverWorld = w;
    final s = current;
    if (s == null || w == null) {
      hoverEnt = null;
      hoverEdge = null;
    } else {
      hoverEnt = _pickEntity(s, w);
      final seg = hoverEnt == null ? null : polySegmentAt(s, hoverEnt!, w);
      hoverEdge = seg == null ? null : (seg.$1.ent, seg.$1.pt);
    }
    notifyListeners();
  }

  void panBy(Offset screenDelta) {
    pan -= Offset(screenDelta.dx / zoom, -screenDelta.dy / zoom);
    notifyListeners();
  }

  void zoomBy(double factor, {Offset? aroundWorld}) {
    final z = (zoom * factor).clamp(0.02, 200.0);
    if (aroundWorld != null) {
      pan = aroundWorld + (pan - aroundWorld) * (zoom / z);
    }
    zoom = z;
    notifyListeners();
  }

  // ---- save / load / preview ----
  Future<bool> saveSketch(String name) async {
    final s = sketches[name];
    if (s == null || _docsDir == null) return false;
    final ok = s.engine.saveDxf(_dxfFile(name).path);
    try {
      File('${_sketchDir.path}/$name.cons.json')
          .writeAsStringSync(encodeConstraints(s.constraints));
    } catch (e) {
      Log.w('state', 'constraint sidecar write failed: $e');
    }
    try {
      // Spline tags ride in a sidecar keyed by entity index (the vertices
      // themselves round-trip through the DXF as a polyline).
      final spl = <String, int>{};
      for (var i = 0; i < s.geometry.length; i++) {
        if (s.geometry[i].spline != Geo.straight) {
          spl['$i'] = s.geometry[i].spline;
        }
      }
      final sf = File('${_sketchDir.path}/$name.splines.json');
      if (spl.isEmpty) {
        if (sf.existsSync()) sf.deleteSync();
      } else {
        sf.writeAsStringSync(jsonEncode(spl));
      }
      // Line styles (centerlines) ride in their own sidecar, same scheme.
      final sty = <String, int>{};
      for (var i = 0; i < s.geometry.length; i++) {
        if (s.geometry[i].style != Geo.styleNormal) {
          sty['$i'] = s.geometry[i].style;
        }
      }
      final stf = File('${_sketchDir.path}/$name.styles.json');
      if (sty.isEmpty) {
        if (stf.existsSync()) stf.deleteSync();
      } else {
        stf.writeAsStringSync(jsonEncode(sty));
      }
    } catch (e) {
      Log.w('state', 'spline sidecar write failed: $e');
    }
    try {
      // Empty layers have no geometry to carry them through the DXF, so the
      // display order plus the eye/lock state live in a small sidecar. The
      // mandatory base "0" is persisted only while it actually holds geometry,
      // so an emptied "0" never comes back as a phantom row.
      final hasBaseGeo = s.geometry.any((g) => g.layer == kDefaultLayer);
      final persistLayers = [
        for (final l in s.layers)
          if (!(l == kDefaultLayer && !hasBaseGeo)) l
      ];
      File('${_sketchDir.path}/$name.layers.json').writeAsStringSync(jsonEncode({
        'version': 2,
        'layers': persistLayers,
        'hidden': s.hiddenLayers.toList(),
        'locked': s.lockedLayers.toList(),
      }));
    } catch (e) {
      Log.w('state', 'layer sidecar write failed: $e');
    }
    await _writePreview(name, s);
    s.dirty = false;
    await refreshSaved();
    notifyListeners();
    return ok;
  }

  Future<void> _writePreview(String name, SketchModel s) async {
    try {
      const w = 380.0, h = 240.0;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
      // same dark radial feel as the mock card thumb
      canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = T.viewport);
      final geos = s.geometry;
      if (geos.isNotEmpty) {
        // fit bbox
        double minx = 1e30, miny = 1e30, maxx = -1e30, maxy = -1e30;
        void pt(double x, double y) {
          minx = math.min(minx, x);
          miny = math.min(miny, y);
          maxx = math.max(maxx, x);
          maxy = math.max(maxy, y);
        }

        for (final g in geos) {
          switch (g.type) {
            case Geo.line:
              pt(g.data[0], g.data[1]);
              pt(g.data[2], g.data[3]);
              break;
            case Geo.circle:
            case Geo.arc:
              pt(g.data[0] - g.data[2], g.data[1] - g.data[2]);
              pt(g.data[0] + g.data[2], g.data[1] + g.data[2]);
              break;
            case Geo.polyline:
              final n = g.data[1].toInt();
              for (var i = 0; i < n; i++) {
                pt(g.data[2 + 2 * i], g.data[3 + 2 * i]);
              }
              break;
          }
        }
        final dx = maxx - minx, dy = maxy - miny;
        final scale = 0.85 *
            math.min(w / (dx <= 0 ? 1 : dx), h / (dy <= 0 ? 1 : dy));
        Offset map(double x, double y) => Offset(
            w / 2 + (x - (minx + maxx) / 2) * scale,
            h / 2 - (y - (miny + maxy) / 2) * scale);
        final p = Paint()
          ..color = const Color(0xFFC4C9CE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        for (final g in geos) {
          paintGeo(canvas, g, map, scale, p);
        }
      }
      final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        await _pngFile(name).writeAsBytes(bytes.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('preview write failed: $e');
    }
  }
}

/// Shared geometry painter used by viewport and preview generation.
void paintGeo(Canvas canvas, Geo g, Offset Function(double, double) map,
    double scale, Paint p) {
  switch (g.type) {
    case Geo.line:
      if (g.isCenterline) {
        // centerline STYLE: same entity, dashed rendering (Inventor's toggle)
        _dashedSeg(canvas, map(g.data[0], g.data[1]),
            map(g.data[2], g.data[3]), p, dash: 10, gap: 5);
      } else {
        canvas.drawLine(
            map(g.data[0], g.data[1]), map(g.data[2], g.data[3]), p);
      }
      break;
    case Geo.circle:
      canvas.drawCircle(map(g.data[0], g.data[1]), g.data[2] * scale, p);
      break;
    case Geo.arc:
      final c = map(g.data[0], g.data[1]);
      final r = g.data[2] * scale;
      final a1 = g.data[3], a2 = g.data[4];
      // Defensive: an arc is normally 6 elements, but never let a short one
      // throw here — a RangeError in paintGeo aborts the whole CustomPainter
      // and blanks every entity after it. Treat a missing flag as not-reversed.
      final reversed = g.data.length > 5 && g.data[5] != 0;
      double norm(double x) {
        var v = x % (2 * math.pi);
        if (v < 0) v += 2 * math.pi;
        return v;
      }

      // world sweep: CCW (positive) if not reversed, CW (negative) otherwise
      final sweep = reversed ? -norm(a1 - a2) : norm(a2 - a1);
      // world angles are CCW with y-up; screen y is flipped -> negate both
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), -a1, -sweep, false, p);
      break;
    case Geo.polyline:
      final closed = g.data[0] != 0;
      final n = g.data[1].toInt();
      if (n < 2) break;
      if (g.isSpline) {
        // A spline is a polyline of control/fit points — draw the smooth curve
        // through/of them, not the control polygon.
        final curve = splineCurveFor(g);
        if (curve.length < 2) break;
        final s0 = map(curve[0].dx, curve[0].dy);
        final path = Path()..moveTo(s0.dx, s0.dy);
        for (var i = 1; i < curve.length; i++) {
          final o = map(curve[i].dx, curve[i].dy);
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, p);
        break;
      }
      final path = Path()
        ..moveTo(map(g.data[2], g.data[3]).dx, map(g.data[2], g.data[3]).dy);
      for (var i = 1; i < n; i++) {
        final o = map(g.data[2 + 2 * i], g.data[3 + 2 * i]);
        path.lineTo(o.dx, o.dy);
      }
      if (closed) path.close();
      canvas.drawPath(path, p);
      break;
  }
}

/// Circumcircle arc through 3 points -> (center, r, startAngle, endAngle,
/// reversed) or null if collinear.
(Offset, double, double, double, bool)? arcFrom3Points(
    Offset a, Offset b, Offset c) {
  final d = 2 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
  if (d.abs() < 1e-9) return null;
  final ux = ((a.dx * a.dx + a.dy * a.dy) * (b.dy - c.dy) +
          (b.dx * b.dx + b.dy * b.dy) * (c.dy - a.dy) +
          (c.dx * c.dx + c.dy * c.dy) * (a.dy - b.dy)) /
      d;
  final uy = ((a.dx * a.dx + a.dy * a.dy) * (c.dx - b.dx) +
          (b.dx * b.dx + b.dy * b.dy) * (a.dx - c.dx) +
          (c.dx * c.dx + c.dy * c.dy) * (b.dx - a.dx)) /
      d;
  final center = Offset(ux, uy);
  final r = (a - center).distance;
  double ang(Offset p) => math.atan2(p.dy - center.dy, p.dx - center.dx);
  final a1 = ang(a), am = ang(b), a2 = ang(c);
  double norm(double x) {
    var v = x % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    return v;
  }

  // does the CCW sweep a1->a2 pass through am?
  final ccwToMid = norm(am - a1), ccwToEnd = norm(a2 - a1);
  final reversed = !(ccwToMid <= ccwToEnd);
  return (center, r, a1, a2, reversed);
}

/// Dashed segment (screen coords) — paintGeo lives here (app_state) so the
/// sketch-preview PNG renderer can reuse it, hence its own dash helper.
void _dashedSeg(Canvas c, Offset a, Offset b, Paint p,
    {double dash = 6, double gap = 4}) {
  final d = b - a;
  final len = d.distance;
  if (len < 1e-6) return;
  final u = d / len;
  var t = 0.0;
  while (t < len) {
    final e = math.min(t + dash, len);
    c.drawLine(a + u * t, a + u * e, p);
    t = e + gap;
  }
}
