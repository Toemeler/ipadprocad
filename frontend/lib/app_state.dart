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
import 'params.dart';
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
  fillet, chamfer, point, project,
  // modify tools (operate on the geometry list, engine gets rebuilt)
  move, mcopy, mrotate, mscale, mstretch, moffset, trim, extendT, split,
  // constraint tools + dimension
  cCoincident, cCollinear, cConcentric, cFix, cParallel, cPerpendicular,
  cHorizontal, cVertical, cTangent, cSmooth, cSymmetric, cEqual, dimension,
  // pattern tools (M35, Inventor's Pattern panel) — modeless dialog + picks
  patRect, patCirc, mirror,
}

const patternTools = {Tool.patRect, Tool.patCirc, Tool.mirror};

/// Which input of the pattern dialog the next viewport tap feeds (the blue
/// selector button, exactly like Inventor's dialogs).
enum PatField { geometry, dir1, dir2, axis, mirrorLine }

/// Live state of an open pattern dialog (M35). One session per dialog; Esc /
/// Cancel discards it, OK / Done commits through [AppState.commitPattern].
class PatternSession {
  final Tool kind; // patRect | patCirc | mirror
  PatField active = PatField.geometry;
  final Set<int> geo = {}; // entities to pattern (multi-pick toggles)
  // rectangular
  int? dir1Ent, dir2Ent; // direction LINE entities
  bool flip1 = false, flip2 = false;
  int count1 = 3, count2 = 3;
  double spacing1 = 15, spacing2 = 15;
  // circular
  PRef? axisPt; // rotation axis: any vertex/center, incl. the projected CP
  bool flipC = false;
  int countC = 6;
  double angleC = 360;
  // mirror
  int? mirrorEnt; // the mirror LINE
  bool selfSym = false; // single spline crossing the line -> one symmetric spline
  // advanced (the ">>" row)
  bool expanded = false;
  bool associative = true;
  bool fitted = true;
  PatternSession(this.kind);
}

/// Live state of the modeless Fillet / Chamfer dialog (M36) — Inventor's
/// tiny "2D Fillet" / "2D Chamfer" windows: the tool stays armed, every two
/// picks make a corner, values are editable between corners. The FIRST
/// fillet of a value gets its radius dimension; later ones with the same
/// value get an equal constraint to the first (Inventor's exact behaviour;
/// changing the value starts a new "first"). Chamfer modes: 0 = equal
/// distance, 1 = two distances, 2 = distance + angle.
class FilletSession {
  final Tool kind; // fillet | chamfer
  double radius;
  int mode;
  double d1, d2, angle;
  int? firstIdx; // entity index of the current chain's first fillet/chamfer
  FilletSession(this.kind,
      {this.radius = 5, this.mode = 0, this.d1 = 5, this.d2 = 5,
      this.angle = 45});
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
  SketchModel(this.name) : engine = Engine.create() {
    // The empty just-created state is the undo baseline. openSketch calls
    // resetHistory() again AFTER loading from disk, so a loaded sketch's
    // baseline is the loaded state (loading is not an edit).
    resetHistory();
  }

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
      // ...and so is the PROJECTION tag (M32): dropping it here would turn a
      // yellow, source-tracking projection into an ordinary line on the
      // first rebuild.
      if (prev[i].proj != Geo.projNone) {
        next[i] = next[i].withProj(prev[i].proj, prev[i].projSeg);
      }
    }
    geometry = next;
  }
  void dispose() => engine.dispose();

  // ==== UNDO / REDO (per sketch, M39) ====================================
  // A snapshot JOURNAL of committed states, one entry per user gesture. Every
  // sketch owns its OWN two stacks — undo in one sketch can never touch
  // another, by construction rather than by bookkeeping. Snapshots are full
  // deep copies (geometry with copied data lists; constraints through the
  // battle-tested sidecar JSON codec, which round-trips every mutable field:
  // value, driven, textPos, anchors, tanBranch). Restoring is therefore EXACT
  // — no replay, no inverse operations, no drift — and a corrupted operation
  // can never poison history, because history only ever holds states that
  // were actually committed. Memory: a snapshot of a 100-entity sketch is a
  // few tens of KB; the journal is unbounded on purpose ("undo until the
  // start, nothing gets lost").
  final List<UndoSnap> _undoStack = [];
  final List<UndoSnap> _redoStack = [];

  /// True when there is an EARLIER state to go back to. The first journal
  /// entry is the baseline (the state the sketch was opened/created with),
  /// which is a restore TARGET, never popped — hence length > 1.
  bool get canUndo => _undoStack.length > 1;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoDepth => _undoStack.length;

  UndoSnap _takeSnap() => UndoSnap(
        [for (final g in geometry) g.withData(List<double>.of(g.data))],
        encodeConstraints(constraints),
        List<String>.of(layers),
        {...hiddenLayers},
        {...lockedLayers},
      );

  /// Records the CURRENT state as a journal entry. Called from the single
  /// mutation choke point (_rebuildEngine) plus the few state changes that
  /// bypass it (layer eye/lock, adding an empty layer). Identical consecutive
  /// states are collapsed, so an operation that rebuilds twice — or a rebuild
  /// that changed nothing — still costs exactly one (or zero) undo steps.
  void checkpoint() {
    final s = _takeSnap();
    if (_undoStack.isNotEmpty && s.sameAs(_undoStack.last)) return;
    _undoStack.add(s);
    _redoStack.clear(); // a new edit forks history: the redo branch dies
  }

  /// Starts history fresh with the current state as the baseline. Called once
  /// when the sketch is created/loaded — loading from disk is not an edit.
  void resetHistory() {
    _undoStack
      ..clear()
      ..add(_takeSnap());
    _redoStack.clear();
  }

  /// Moves one step back and returns the state to restore, or null.
  UndoSnap? undoStep() {
    if (!canUndo) return null;
    _redoStack.add(_undoStack.removeLast());
    return _undoStack.last;
  }

  /// Moves one step forward and returns the state to restore, or null.
  UndoSnap? redoStep() {
    if (!canRedo) return null;
    final s = _redoStack.removeLast();
    _undoStack.add(s);
    return s;
  }
}

/// One committed sketch state: everything the sidecars persist, deep-copied.
/// (View preferences — zoom, DOF colouring, the current tool — are NOT sketch
/// state and deliberately not part of undo, exactly like Inventor.)
class UndoSnap {
  final List<Geo> geometry;
  final String cons; // constraints, serialized (deep copy + cheap equality)
  final List<String> layers;
  final Set<String> hidden;
  final Set<String> locked;
  UndoSnap(this.geometry, this.cons, this.layers, this.hidden, this.locked);

  bool sameAs(UndoSnap o) {
    if (cons != o.cons ||
        geometry.length != o.geometry.length ||
        layers.length != o.layers.length ||
        hidden.length != o.hidden.length ||
        locked.length != o.locked.length) {
      return false;
    }
    for (var i = 0; i < layers.length; i++) {
      if (layers[i] != o.layers[i]) return false;
    }
    if (!hidden.containsAll(o.hidden) || !locked.containsAll(o.locked)) {
      return false;
    }
    for (var i = 0; i < geometry.length; i++) {
      final a = geometry[i], b = o.geometry[i];
      if (a.type != b.type ||
          a.layer != b.layer ||
          a.spline != b.spline ||
          a.style != b.style ||
          a.proj != b.proj ||
          a.projSeg != b.projSeg ||
          a.data.length != b.data.length) {
        return false;
      }
      for (var k = 0; k < a.data.length; k++) {
        if (a.data[k] != b.data[k]) return false;
      }
    }
    return true;
  }
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
          ensureParamNames(s); // M41: pre-M41 sidecars load nameless
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
        try {
          final pf = File('${_sketchDir.path}/$name.proj.json');
          if (pf.existsSync()) {
            final j =
                jsonDecode(pf.readAsStringSync()) as Map<String, dynamic>;
            j.forEach((k, v) {
              final i = int.tryParse(k);
              if (i != null && i >= 0 && i < s.geometry.length) {
                s.geometry[i] = v is List
                    ? s.geometry[i].withProj(
                        (v[0] as num).toInt(), (v[1] as num).toInt())
                    : s.geometry[i].withProj((v as num).toInt());
              }
            });
            syncProjections(s.geometry);
          }
        } catch (e) {
          Log.w('state', 'projection sidecar read failed: $e');
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
      // Undo baseline: the freshly created/loaded state is entry ZERO of the
      // journal — undo walks back to it but never past it, and loading from
      // disk is not an edit.
      s.resetHistory();
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

  // ==== UNDO / REDO (M39): restore side ==================================
  /// True while a snapshot is being restored: suppresses the checkpoint in
  /// _rebuildEngine so undo never journals itself.
  bool _restoringHistory = false;

  bool get canUndo => current?.canUndo ?? false;
  bool get canRedo => current?.canRedo ?? false;

  /// Ctrl+Z. Steps the CURRENT sketch one committed state back — every other
  /// sketch's history is untouched (the stacks live in the SketchModel).
  void undo() => _applyHistory((s) => s.undoStep(), 'undo');

  /// Ctrl+Shift+Z (and Ctrl+Y). Steps forward again.
  void redo() => _applyHistory((s) => s.redoStep(), 'redo');

  void _applyHistory(UndoSnap? Function(SketchModel) step, String what) {
    final s = current;
    if (s == null) return;
    if (dragGrip != null) return; // never rip the state out from under a drag
    final snap = step(s);
    if (snap == null) {
      toast(what == 'undo' ? 'Nothing to undo.' : 'Nothing to redo.');
      return;
    }
    Log.i('undo', '$what "${s.name}" -> depth=${s.undoDepth} '
        'geo=${snap.geometry.length} redo=${s.canRedo}');
    // Restoring is EXACT: no solve, no replay — the snapshot IS a state that
    // was committed and verified once already. Cancel every in-flight
    // interaction first: index-based tool/pattern/dimension picks would
    // dangle into geometry that is about to change wholesale.
    toolPoints.clear();
    pattern = null;
    filletSess = null;
    pendingDim = null;
    conPts.clear();
    conEnts.clear();
    conEntClicks.clear();
    conEdges.clear();
    modEntity = null;
    selection.clear();
    _restoringHistory = true;
    try {
      s.constraints
        ..clear()
        ..addAll(decodeConstraints(snap.cons));
      s.layers
        ..clear()
        ..addAll(snap.layers);
      s.hiddenLayers
        ..clear()
        ..addAll(snap.hidden);
      s.lockedLayers
        ..clear()
        ..addAll(snap.locked);
      // Editing a layer the restored state does not have (or has hidden or
      // locked again) cannot continue.
      final el = editingLayer;
      if (el != null &&
          (!s.layers.contains(el) ||
              s.hiddenLayers.contains(el) ||
              s.lockedLayers.contains(el))) {
        editingLayer = null;
        tool = Tool.none;
      }
      _rebuildEngine(
          s,
          [
            for (final g in snap.geometry)
              g.withData(List<double>.of(g.data)) // never alias the journal
          ]);
    } finally {
      _restoringHistory = false;
    }
    _reanalyze();
    Log.flush();
    notifyListeners();
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
    s.checkpoint(); // adding an (empty) layer never rebuilds -> journal here
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
    s.checkpoint(); // eye state rides the sidecar -> it is undoable state
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
    s.checkpoint(); // padlock state rides the sidecar -> undoable
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
      gs.setAll(0, remapProjectionsAfterRemove(gs, i));
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
  /// The most recent drag frame whose solve actually held the constraints.
  /// Committed on release so a drag that ends on an unsatisfiable cursor
  /// position keeps its last VALID position instead of snapping back to where
  /// the drag started (Inventor's behaviour).
  List<Geo>? _lastGoodDragGeo;
  Offset? boxStart, boxEnd; // world coords while box-selecting
  bool boxCrossing = false;
  Rect? lastBoxRect; // remembered for Stretch (Inventor semantics)
  int? modEntity; // entity picked in the first phase of Offset
  final bool autoConstrain = true; // always on (Inventor: no toggle button)
  bool showConstraints = false; // Constrain panel: Show Constraints toggle — OFF by default (M32)
  bool showDof = false; // Inventor: Degrees of Freedom glyphs — OFF by default (M32)
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
  /// Click position of each conEnts pick made by the CONSTRAINT tools —
  /// needed to resolve WHICH spline end / WHICH polyline edge takes part in
  /// a tangency (both spline ends can touch the same rectangle, so "nearest
  /// end to the other entity" can tie; the click disambiguates).
  final List<Offset> conEntClicks = [];
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

      final ok = solveConstraints(gs, s.constraints,
          dragged: {(grip.entity, grip.idx)}, iterations: 25);

      if (!allFinite(gs)) {
        Log.e('drag', 'display geometry NON-FINITE after solve — '
            'showing committed geometry instead');
        Log.block('drag', 'bad display geometry',
            sketchDump(gs, s.constraints));
        return s.geometry;
      }
      // The solve did not hold the constraints for this cursor position (a
      // diverged/degenerate frame). Showing it is exactly what made the slot
      // flicker — a zero-sweep cap blinks out, a blown-up radius smears across
      // the sketch. Hold the last good geometry instead; the grip simply does
      // not follow past the point the constraints can satisfy, which is what
      // Inventor does. The frame is throttled so this does not spam the log.
      if (!ok) {
        if (Log.every('drag-hold', 200)) {
          Log.d('drag', 'frame solve unsatisfied — holding last good geometry');
        }
        return _lastGoodDragGeo ?? s.geometry;
      }
      _lastGoodDragGeo = gs;
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
      // greyed-out geometry of OTHER layers is reference-only in edit mode:
      // not tappable, not selectable (Inventor). Projections live ON the
      // editing layer and stay selectable.
      if (inEditMode && !geoEditable(s.geometry[i])) continue;
      if (!geoVisible(s.geometry[i])) continue;
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
          // same scope rule as selectAt: other layers are not selectable
          if (inEditMode && !geoEditable(s.geometry[i])) continue;
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
    _lastGoodDragGeo = null;
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
        // SETTLE before committing. Drag frames run with a small iteration
        // budget, so the last shown frame can legally carry residuals up to
        // the render threshold (1e-2). Committing that unrefined state broke
        // everything downstream on the device: seam endpoints drifted past the
        // 1e-6 shared-endpoint tolerance, so every later solve bailed off the
        // native path, and arc angles left the drag unnormalized. One full
        // solve (80 iterations, nothing dragged) pulls the frame onto the
        // constraint manifold to machine precision; angle normalization keeps
        // arc parameters canonical without moving any endpoint.
        final gs = List<Geo>.from(displayGeometry(s));
        solveConstraints(gs, s.constraints);
        normalizeArcAngles(gs);
        _rebuildEngine(s, gs);
      } catch (err, st) {
        Log.e('drag', 'END: rebuild threw', err, st);
      }
      Log.block('drag', 'sketch after drag',
          sketchDump(s.geometry, s.constraints));
    }
    dragGrip = null;
    dragPos = null;
    _lastGoodDragGeo = null;
    Log.flush();
    snap = null;
    notifyListeners();
  }

  /// Binds the NEW endpoints a trim/split created (every piece endpoint that
  /// was not an endpoint of the original carrier [old]) the way Inventor does:
  /// point-on-point when it meets an existing point (a split's twin piece, a
  /// crossing endpoint), otherwise point-on-curve onto the entity whose
  /// interior it lies on (the cutter). Candidates run through the same
  /// over-constraint gate as manual constraints and are appended to [cons];
  /// the caller's atomic solve then verifies everything together.
  void _bindCutPoints(
      List<Geo> gs, Geo old, int piecesStart, List<Constraint> cons) {
    const tol = 1e-6;
    final oldEnds = <Offset>[];
    if (old.type == Geo.line) {
      oldEnds.addAll([getPt(old, 0), getPt(old, 1)]);
    } else if (old.type == Geo.arc) {
      oldEnds.addAll([getPt(old, 1), getPt(old, 2)]);
    } // a full circle has no endpoints: every cut point is new

    void tryAdd(Constraint c) {
      if (!wouldOverconstrain(gs, cons, c)) {
        cons.add(c);
      } else {
        Log.i('modify',
            'cut-bind ${conStr(-1, c)} DROPPED (would over-constrain)');
      }
    }

    for (var e = piecesStart; e < gs.length; e++) {
      final g = gs[e];
      final endIdx = g.type == Geo.line
          ? const [0, 1]
          : g.type == Geo.arc
              ? const [1, 2]
              : const <int>[];
      for (final p in endIdx) {
        final q = getPt(g, p);
        if (oldEnds.any((o) => (o - q).distance < tol)) continue;
        // remap may already have carried a POINT-ON-POINT coincidence onto
        // this point — that is the strongest bind, nothing to do. A mere
        // point-on-CURVE bind does NOT block: when a later cut makes an
        // endpoint STACK on this point, Inventor upgrades the sliding
        // on-curve bind to a rigid point-on-point (the device session left
        // stacked trim corners sliding apart because the old on-curve bind
        // both blocked and over-constrained the new point-on-point).
        final bound = cons.any((c) =>
            c.type == CType.coincident &&
            c.pts.length >= 2 &&
            c.pts.any((r) => r.ent == e && r.pt == p));
        if (bound) continue;
        // 1) meets an existing point exactly (split twin, crossing endpoint)
        Constraint? cand;
        for (var j = 0; j < gs.length && cand == null; j++) {
          if (j == e) continue;
          for (var pj = 0; pj < ptCount(gs[j]); pj++) {
            if ((getPt(gs[j], pj) - q).distance < tol) {
              cand =
                  Constraint(CType.coincident, pts: [PRef(j, pj), PRef(e, p)]);
              // The point-on-point SUBSUMES any point-on-curve bind of either
              // participant onto the other participant's entity (one equation
              // of it, making the pair redundant → the gate would reject the
              // stronger bind). Replace, don't stack: remove the subsumed
              // on-curve binds first.
              cons.removeWhere((c) {
                if (c.type != CType.coincident ||
                    c.pts.length != 1 ||
                    c.ents.length != 1) {
                  return false;
                }
                final r = c.pts[0];
                final onto = c.ents[0];
                final subsumed = (r.ent == e && r.pt == p && onto == j) ||
                    (r.ent == j && r.pt == pj && onto == e);
                if (subsumed) {
                  Log.i('modify',
                      'cut-bind upgrades ${conStr(-1, c)} -> point-on-point '
                      '(stacked endpoints)');
                }
                return subsumed;
              });
              break;
            }
          }
        }
        // 2) lies on the interior of another entity: the cutter
        if (cand == null) {
          for (var j = 0; j < gs.length; j++) {
            if (j == e || j >= piecesStart) continue; // never onto a sibling
            final t = gs[j];
            if (t.type == Geo.line) {
              final a = getPt(t, 0), b = getPt(t, 1);
              final ab = b - a;
              final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
              if (len2 < 1e-18) continue;
              final tp = ((q - a).dx * ab.dx + (q - a).dy * ab.dy) / len2;
              if (tp <= tol || tp >= 1 - tol) continue;
              if ((q - (a + ab * tp)).distance < tol) {
                cand = Constraint(CType.coincident,
                    pts: [PRef(e, p)], ents: [j]);
                break;
              }
            } else if (t.type == Geo.circle || t.type == Geo.arc) {
              final c0 = Offset(t.data[0], t.data[1]);
              if (((q - c0).distance - t.data[2]).abs() < tol) {
                cand = Constraint(CType.coincident,
                    pts: [PRef(e, p)], ents: [j]);
                break;
              }
            }
          }
        }
        if (cand != null) {
          Log.i('modify',
              'cut-bind ${conStr(-1, cand)} (Inventor trim/split coincidence)');
          tryAdd(cand);
        }
      }
    }
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
    // M41: expressions referencing driven (reference) parameters follow the
    // fresh measurements; guarded so the chase's own solves do not recurse.
    if (!_inExprChase) _chaseExpressions(s);
    analysis = analyzeSketch(s.geometry, s.constraints);
    // UNDO JOURNAL (M39): every committed mutation funnels through this
    // rebuild (the C-API is add-only), so this one call records the whole
    // app's edits — draw, drag, trim, fillet, patterns, dimensions,
    // constraints, layer rename/delete/move. Suppressed while RESTORING a
    // snapshot, or undo would journal itself.
    if (!_restoringHistory) s.checkpoint();
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
    // Pattern tools open their modeless dialog (M35). The current selection
    // seeds the Geometry pick set — Inventor pre-fills it the same way.
    if (patternTools.contains(t)) {
      final ps = PatternSession(t);
      final s = current;
      if (s != null) {
        ps.geo.addAll(selection.where((i) =>
            i >= 0 &&
            i < s.geometry.length &&
            geoEditable(s.geometry[i]) &&
            !s.geometry[i].isProjection));
      }
      pattern = ps;
      selection.clear();
    } else {
      pattern = null;
    }
    // Fillet/Chamfer open their modeless value dialog (M36). Last-used
    // values persist across sessions — Inventor remembers them too.
    if (t == Tool.fillet || t == Tool.chamfer) {
      filletSess = FilletSession(t,
          radius: lastFilletRadius,
          mode: lastChamferMode,
          d1: lastChamferD1,
          d2: lastChamferD2,
          angle: lastChamferAngle);
      filletNotify();
    } else {
      filletSess = null;
    }
    notifyListeners();
  }

  // ---- fillet / chamfer session (M36) ----
  FilletSession? filletSess;
  double lastFilletRadius = 5;
  int lastChamferMode = 0;
  double lastChamferD1 = 5, lastChamferD2 = 5, lastChamferAngle = 45;

  /// The dialog mutates the session and calls this: remembers the values,
  /// mirrors them into [toolParams] (the preview reads those), restarts the
  /// equal-chain when a value changed, repaints.
  void filletNotify() {
    final f = filletSess;
    if (f == null) return;
    if (f.kind == Tool.fillet) {
      if (f.radius != lastFilletRadius) f.firstIdx = null;
      lastFilletRadius = f.radius;
      toolParams = {'radius': f.radius};
    } else {
      if (f.d1 != lastChamferD1 || f.mode != lastChamferMode) {
        f.firstIdx = null;
      }
      lastChamferMode = f.mode;
      lastChamferD1 = f.d1;
      lastChamferD2 = f.d2;
      lastChamferAngle = f.angle;
      toolParams = {
        'mode': f.mode.toDouble(),
        'dist': f.d1,
        'dist2': f.d2,
        'ang': f.angle,
      };
    }
    notifyListeners();
  }

  /// Inventor's Esc behaviour: the first press ends the current chain / pick
  /// set but KEEPS the command running, the second exits the command, a
  /// further press clears the selection.
  void cancelTool() {
    snap = null;
    pendingDim = null;
    // A pattern dialog cancels as a WHOLE (Inventor: Esc = Cancel) — no
    // pick-chain step-back like the drawing tools.
    if (pattern != null) {
      pattern = null;
      tool = Tool.none;
      notifyListeners();
      return;
    }
    // The fillet/chamfer dialog also cancels as a whole — but only when no
    // first pick is pending (then Esc steps the pick back, like other tools).
    if (filletSess != null && toolPoints.isEmpty) {
      filletSess = null;
      tool = Tool.none;
      notifyListeners();
      return;
    }
    final hadPicks =
        toolPoints.isNotEmpty || conPts.isNotEmpty || conEnts.isNotEmpty ||
            modEntity != null;
    toolPoints.clear();
    conPts.clear();
    conEnts.clear();
    conEntClicks.clear();
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
    if (patternTools.contains(tool)) {
      _patternClick(s, w);
      notifyListeners();
      return;
    }
    if (modifyTools.contains(tool)) {
      _modifyClick(s, w);
      notifyListeners();
      return;
    }
    if (tool == Tool.project) {
      _projectClick(s, w);
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
    if (pattern != null) {
      commitPattern(); // Enter = OK / Done of the pattern dialog
      return;
    }
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

  /// Inventor's Project Geometry (M32). Click a LINE on another layer to
  /// project it into the editing layer as yellow, solver-pinned reference
  /// geometry that keeps tracking its source. Clicking near the X/Y axis
  /// (when no line is hit) projects that axis. Circles/arcs/splines are not
  /// projectable (Inventor projects them too — future work); the projected
  /// CENTER POINT exists by default anyway.
  /// Nearest visible entity under [w] across ALL layers — the projection
  /// source pick (and its hover highlight). _pickEntity is scoped to the
  /// editing layer on purpose, a projection source never is.
  int? pickVisibleAny(SketchModel s, Offset w) {
    var ent = -1;
    var bd = 10 / zoom;
    for (var i = 0; i < s.geometry.length; i++) {
      if (!geoVisible(s.geometry[i])) continue;
      final d = distToEntity(s.geometry[i], w);
      if (d < bd) {
        bd = d;
        ent = i;
      }
    }
    return ent >= 0 ? ent : null;
  }

  /// Is [ent] fully projected onto [lay]? (An edge projection of a polyline
  /// only covers ONE segment, the rest stays projectable and highlightable.)
  bool _isProjectedOnto(SketchModel s, int ent, String lay) =>
      s.geometry.any((g) =>
          g.isProjection && g.proj == ent && g.projSeg < 0 && g.layer == lay);

  void _projectClick(SketchModel s, Offset w) {
    final lay = editingLayer;
    if (lay == null) return;
    final picked = pickVisibleAny(s, w);
    int? src;
    var seg = -1;
    Geo? proto;
    if (picked != null) {
      final g = s.geometry[picked];
      if (g.layer == lay) {
        toast(g.isProjection
            ? 'Already projected onto this layer.'
            : 'Project picks geometry from OTHER layers.');
        return;
      }
      src = picked;
      if (g.type == Geo.polyline && !g.isSpline) {
        // a rectangle/polygon side projects as ONE LINE (Inventor projects
        // the clicked edge, not the loop) — resolved at the click (M34)
        final e = polySegmentAt(s, picked, w);
        if (e == null) {
          toast('Tap an edge of the polygon to project it.');
          return;
        }
        seg = e.$1.pt;
        proto = Geo(Geo.line, [
          getPt(g, e.$1.pt).dx,
          getPt(g, e.$1.pt).dy,
          getPt(g, e.$2.pt).dx,
          getPt(g, e.$2.pt).dy,
        ]);
      } else {
        proto = g;
      }
    } else {
      // no entity: near an axis? (the axes pass through the projected CP)
      final tol = 10 / zoom;
      if (w.dy.abs() <= tol) {
        src = Geo.projAxisX;
        proto = Geo(Geo.line, const [-kProjAxisSpan, 0, kProjAxisSpan, 0]);
      } else if (w.dx.abs() <= tol) {
        src = Geo.projAxisY;
        proto = Geo(Geo.line, const [0, -kProjAxisSpan, 0, kProjAxisSpan]);
      } else {
        toast('Tap geometry on another layer, or the X/Y axis.');
        return;
      }
    }
    for (final g in s.geometry) {
      if (g.isProjection &&
          g.proj == src &&
          g.projSeg == seg &&
          g.layer == lay) {
        toast('Already projected onto this layer.');
        return;
      }
    }
    // the projection is a same-type copy of the source — it keeps the
    // spline/ellipse tag and gets the proj tag on top (M33: all types;
    // M34: a polyline EDGE projects as a line tagged with its segment)
    final copy = proto.onLayer(lay).withProj(src, seg);
    final tags = List<Geo>.of(s.geometry)..add(copy);
    s.engine.setCurrentLayer(lay);
    final d = copy.data;
    switch (copy.type) {
      case Geo.line:
        s.engine.addLine(d[0], d[1], d[2], d[3]);
        break;
      case Geo.circle:
        s.engine.addCircle(d[0], d[1], d[2]);
        break;
      case Geo.arc:
        s.engine.addArc(d[0], d[1], d[2], d[3], d[4],
            reversed: d.length > 5 && d[5] != 0);
        break;
      case Geo.polyline:
        final n = d[1].toInt();
        s.engine.addPolyline(
            [
              for (var i = 0; i < n; i++) ...[d[2 + 2 * i], d[3 + 2 * i]]
            ],
            closed: d[0] != 0);
        break;
    }
    _committed(s, tags: tags);
    _solveAndRebuild(s);
    Log.i('project',
        'projected ${src >= 0 ? "entity $src (${proto.type})" : src == Geo.projAxisX ? "X axis" : "Y axis"} onto "$lay"');
  }

  // ---- sketch patterns (M35, Inventor's Pattern panel) ----
  /// The open pattern dialog's state, or null when no pattern tool is active.
  PatternSession? pattern;

  /// The dialog widget mutates the session directly (counts, flips, active
  /// selector, checkboxes) and calls this to repaint the preview.
  void patNotify() => notifyListeners();

  /// Viewport tap while a pattern dialog is open: feeds the ACTIVE selector,
  /// exactly like Inventor's dialogs (Geometry multi-pick toggles; Direction /
  /// Axis / Mirror Line replace their pick).
  void _patternClick(SketchModel s, Offset w) {
    final ps = pattern;
    if (ps == null) return;
    switch (ps.active) {
      case PatField.geometry:
        final i = _pickEntity(s, w);
        if (i == null) return;
        if (s.geometry[i].isProjection) {
          toast('Projected geometry cannot be patterned.');
          return;
        }
        if (!ps.geo.remove(i)) ps.geo.add(i); // tap toggles
        return;
      case PatField.dir1:
      case PatField.dir2:
        final i = _pickEntity(s, w);
        if (i == null || s.geometry[i].type != Geo.line) {
          toast('Pick a line to define the direction.');
          return;
        }
        if (ps.active == PatField.dir1) {
          ps.dir1Ent = i;
        } else {
          ps.dir2Ent = i;
        }
        return;
      case PatField.axis:
        // a point, vertex, circle/arc center — or the projected center point
        final p = _nearestPointRef(s, w);
        if (p == null) {
          toast('Pick a point or center to define the axis.');
          return;
        }
        ps.axisPt = p;
        return;
      case PatField.mirrorLine:
        final i = _pickEntity(s, w);
        if (i == null || s.geometry[i].type != Geo.line) {
          toast('Pick a line to mirror about.');
          return;
        }
        if (ps.geo.contains(i)) {
          toast('The mirror line cannot be part of the selection.');
          return;
        }
        ps.mirrorEnt = i;
        return;
    }
  }

  /// Unit direction of the line entity [e], honouring the flip toggle.
  Offset? _patDir(SketchModel s, int? e, bool flip) {
    if (e == null || e >= s.geometry.length) return null;
    final g = s.geometry[e];
    if (g.type != Geo.line) return null;
    final d = Offset(g.data[2] - g.data[0], g.data[3] - g.data[1]);
    if (d.distance < 1e-9) return null;
    final u = d / d.distance;
    return flip ? -u : u;
  }

  /// Step between neighbouring instances. Fitted = the entered value is the
  /// TOTAL span, evenly divided; unchecked = the value IS the step (Inventor's
  /// Fitted checkbox). A 360° circular span wraps, so fitted divides by count
  /// (not count-1) to keep the first and last element from coinciding.
  double _patStep(double value, int count, bool fitted, {bool wrap360 = false}) {
    if (!fitted || count <= 1) return value;
    if (wrap360) return value / count;
    return value / (count - 1);
  }

  /// The rigid transforms of every pattern instance EXCEPT the original,
  /// paired with the anchors that encode them for the associative constraint.
  /// Empty when the session's inputs are still incomplete.
  List<(Offset Function(Offset), List<double>)> _patTransforms(SketchModel s) {
    final ps = pattern;
    if (ps == null) return const [];
    final out = <(Offset Function(Offset), List<double>)>[];
    switch (ps.kind) {
      case Tool.patRect:
        final u1 = _patDir(s, ps.dir1Ent, ps.flip1);
        if (u1 == null) return const [];
        final u2 = _patDir(s, ps.dir2Ent, ps.flip2);
        final n1 = ps.count1.clamp(1, 64);
        final n2 = u2 == null ? 1 : ps.count2.clamp(1, 64);
        final s1 = _patStep(ps.spacing1, n1, ps.fitted);
        final s2 = _patStep(ps.spacing2, n2, ps.fitted);
        for (var k2 = 0; k2 < n2; k2++) {
          for (var k1 = 0; k1 < n1; k1++) {
            if (k1 == 0 && k2 == 0) continue;
            final d = u1 * (s1 * k1) +
                (u2 == null ? Offset.zero : u2 * (s2 * k2));
            out.add((
              translation(d),
              [patKindTranslate, d.dx, d.dy],
            ));
          }
        }
        return out;
      case Tool.patCirc:
        final ax = ps.axisPt;
        if (ax == null) return const [];
        if (isRealPt(ax, s.geometry) && ax.ent >= s.geometry.length) {
          return const [];
        }
        final c = refPt(s.geometry, ax);
        final n = ps.countC.clamp(2, 128);
        final full = (ps.angleC.abs() - 360).abs() < 1e-9;
        final stepDeg =
            _patStep(ps.angleC, n, ps.fitted, wrap360: full);
        final sign = ps.flipC ? -1.0 : 1.0;
        for (var k = 1; k < n; k++) {
          final a = sign * stepDeg * k * math.pi / 180;
          out.add((
            rotation(c, a),
            [patKindRotate, c.dx, c.dy, a],
          ));
        }
        return out;
      case Tool.mirror:
        final f = _mirrorFn(s, ps.mirrorEnt);
        if (f == null) return const [];
        return [(f, const [])]; // mirror is held by symmetric constraints
      default:
        return const [];
    }
  }

  /// Reflection about the mirror line entity, or null.
  Offset Function(Offset)? _mirrorFn(SketchModel s, int? e) {
    if (e == null || e >= s.geometry.length) return null;
    final g = s.geometry[e];
    if (g.type != Geo.line) return null;
    final a = Offset(g.data[0], g.data[1]);
    final d = Offset(g.data[2] - g.data[0], g.data[3] - g.data[1]);
    final len = d.distance;
    if (len < 1e-9) return null;
    final u = d / len;
    return (p) {
      final v = p - a;
      final t = v.dx * u.dx + v.dy * u.dy;
      final foot = a + u * t;
      return foot * 2 - p;
    };
  }

  /// Ghost copies of the pending pattern for the viewport preview.
  List<Geo> patternPreview() {
    final s = current;
    final ps = pattern;
    if (s == null || ps == null || ps.geo.isEmpty) return const [];
    final fs = _patTransforms(s);
    if (fs.isEmpty) return const [];
    final out = <Geo>[];
    for (final (f, _) in fs) {
      for (final i in ps.geo) {
        if (i >= s.geometry.length) continue;
        out.add(transformGeo(s.geometry[i], f));
      }
      if (out.length > 600) break; // keep the preview cheap
    }
    return out;
  }

  /// Commits the open pattern session. Returns true on success. [keepOpen]
  /// is Mirror's Apply button: commit, keep the dialog, clear the picks for
  /// the next mirror (Inventor's behaviour).
  bool commitPattern({bool keepOpen = false}) {
    final s = current;
    final ps = pattern;
    final lay = editingLayer;
    if (s == null || ps == null || lay == null) return false;
    ps.geo.removeWhere((i) => i < 0 || i >= s.geometry.length);
    if (ps.geo.isEmpty) {
      toast('Select geometry to pattern.');
      return false;
    }
    if (ps.kind == Tool.patRect && _patDir(s, ps.dir1Ent, false) == null) {
      toast('Pick a line under Direction 1.');
      return false;
    }
    if (ps.kind == Tool.patCirc && ps.axisPt == null) {
      toast('Pick the pattern axis.');
      return false;
    }
    if (ps.kind == Tool.mirror && _mirrorFn(s, ps.mirrorEnt) == null) {
      toast('Pick the mirror line.');
      return false;
    }
    if (ps.kind == Tool.mirror && ps.selfSym) {
      return _commitSelfSymmetric(s, ps, keepOpen);
    }
    final fs = _patTransforms(s);
    if (fs.isEmpty) {
      toast('The pattern has nothing to create.');
      return false;
    }
    final srcs = ps.geo.toList()..sort();
    final gs = List<Geo>.from(s.geometry);
    final consBefore = s.constraints.length; // for atomic rollback below
    var made = 0;
    for (final (f, anchors) in fs) {
      for (final src in srcs) {
        final copy = transformGeo(s.geometry[src], f)
            .onLayer(lay)
            .withStyle(s.geometry[src].style); // centerlines stay centerlines
        final copyIdx = gs.length;
        gs.add(copy);
        made++;
        if (!ps.associative) continue;
        if (ps.kind == Tool.mirror) {
          _addMirrorConstraints(s, gs, src, copyIdx, ps.mirrorEnt!);
        } else {
          // one pattern-element constraint slaves the copy to its source
          s.constraints.add(Constraint(CType.pattern,
              ents: [src, copyIdx], anchors: List<double>.from(anchors)));
        }
      }
    }
    Log.i('pattern',
        '${ps.kind.name}: $made copies of ${srcs.length} entities onto '
        '"$lay" (associative=${ps.associative}, fitted=${ps.fitted})');
    final ok = _solveAndRebuild(s, gs);
    if (!ok) {
      // roll back the constraints this commit appended; the geometry copies
      // were never adopted (gs is local), so the sketch is untouched
      s.constraints.removeRange(consBefore, s.constraints.length);
      toast('Pattern cannot be satisfied with the current constraints.');
      notifyListeners();
      return false;
    }
    toast('Pattern created ($made new elements).');
    if (keepOpen) {
      ps.geo.clear(); // Apply: ready for the next mirror pick set
      ps.active = PatField.geometry;
    } else {
      pattern = null;
      tool = Tool.none;
    }
    notifyListeners();
    return true;
  }

  /// Mirror associativity through the EXISTING symmetric constraint — exactly
  /// what Inventor documents ("Symmetric constraints are applied between the
  /// mirrored geometry"): every defining point of the copy is symmetric to
  /// its source point about the mirror line. Circles add radius equality
  /// (their single point is the center); arcs are covered by their three
  /// point refs (the redundant radius row is rank-neutral for the LM solver
  /// and the DOF analysis).
  void _addMirrorConstraints(
      SketchModel s, List<Geo> gs, int src, int copy, int axis) {
    final g = gs[src];
    switch (g.type) {
      case Geo.line:
        for (var p = 0; p < 2; p++) {
          s.constraints.add(Constraint(CType.symmetric,
              pts: [PRef(src, p), PRef(copy, p)], ents: [axis]));
        }
        break;
      case Geo.circle:
        s.constraints.add(Constraint(CType.symmetric,
            pts: [PRef(src, 0), PRef(copy, 0)], ents: [axis]));
        s.constraints.add(Constraint(CType.equal, ents: [src, copy]));
        break;
      case Geo.arc:
        for (var p = 0; p < 3; p++) {
          s.constraints.add(Constraint(CType.symmetric,
              pts: [PRef(src, p), PRef(copy, p)], ents: [axis]));
        }
        break;
      case Geo.polyline:
        final n = g.data[1].toInt();
        for (var p = 0; p < n; p++) {
          s.constraints.add(Constraint(CType.symmetric,
              pts: [PRef(src, p), PRef(copy, p)], ents: [axis]));
        }
        break;
    }
  }

  /// Self Symmetric (Mirror dialog, 2D): a single OPEN spline whose end sits
  /// on the mirror line becomes ONE spline symmetric about it — the defining
  /// points are extended by their reflections, each pair is held by a
  /// symmetric constraint, and the middle point is pinned onto the line.
  bool _commitSelfSymmetric(SketchModel s, PatternSession ps, bool keepOpen) {
    if (ps.geo.length != 1) {
      toast('Self Symmetric needs exactly one spline.');
      return false;
    }
    final e = ps.geo.first;
    final g = s.geometry[e];
    final isOpenSpline = g.type == Geo.polyline &&
        (g.spline == Geo.splineCv || g.spline == Geo.splineFit) &&
        g.data[0] == 0;
    if (!isOpenSpline) {
      toast('Self Symmetric needs an open spline.');
      return false;
    }
    final axis = ps.mirrorEnt!;
    final f = _mirrorFn(s, axis)!;
    final n = g.data[1].toInt();
    if (n < 2) return false;
    Offset pt(int i) => Offset(g.data[2 + 2 * i], g.data[3 + 2 * i]);
    // which END lies on the mirror line? (distance point<->reflection ~ 0)
    final tol = math.max(1e-6, 8 / zoom);
    final endOn = (pt(n - 1) - f(pt(n - 1))).distance <= tol;
    final startOn = (pt(0) - f(pt(0))).distance <= tol;
    if (!endOn && !startOn) {
      toast('The spline must end on the mirror line for Self Symmetric.');
      return false;
    }
    // normalize so the ON-LINE point is LAST
    final pts = [for (var i = 0; i < n; i++) pt(i)];
    final ordered = endOn ? pts : pts.reversed.toList();
    final ext = List<Offset>.from(ordered);
    for (var i = n - 2; i >= 0; i--) {
      ext.add(f(ordered[i]));
    }
    final data = <double>[0, ext.length.toDouble()];
    for (final p in ext) {
      data.addAll([p.dx, p.dy]);
    }
    final gs = List<Geo>.from(s.geometry);
    gs[e] = g.withData(data);
    final consBefore = s.constraints.length; // for atomic rollback below
    // pair i <-> 2n-2-i symmetric about the axis; middle point ON the line
    for (var i = 0; i < n - 1; i++) {
      s.constraints.add(Constraint(CType.symmetric,
          pts: [PRef(e, i), PRef(e, 2 * n - 2 - i)], ents: [axis]));
    }
    s.constraints.add(
        Constraint(CType.coincident, pts: [PRef(e, n - 1)], ents: [axis]));
    Log.i('pattern',
        'self-symmetric spline e$e: $n -> ${ext.length} defining points');
    if (!_solveAndRebuild(s, gs)) {
      s.constraints.removeRange(consBefore, s.constraints.length);
      toast('Self Symmetric cannot be satisfied with the current constraints.');
      notifyListeners();
      return false;
    }
    toast('Spline made self-symmetric.');
    if (keepOpen) {
      ps.geo.clear();
      ps.active = PatField.geometry;
    } else {
      pattern = null;
      tool = Tool.none;
    }
    notifyListeners();
    return true;
  }

  /// Zero-extent trim leftovers (a cut landing exactly on an endpoint leaves
  /// a length-0 stub) are dropped instead of littering the sketch — and
  /// instead of catching constraints that should die with the trimmed span.
  static bool _notDegenerate(Geo g) {
    switch (g.type) {
      case Geo.line:
        return (Offset(g.data[0], g.data[1]) - Offset(g.data[2], g.data[3]))
                .distance >
            1e-9;
      case Geo.arc:
        return (g.data[4] - g.data[3]).abs() > 1e-9 && g.data[2] > 1e-9;
      case Geo.polyline:
        return g.data[1] >= 2;
      default:
        return true;
    }
  }

  void _modifyClick(SketchModel s, Offset w) {
    final guard = _pickEntity(s, w);
    if (guard != null && s.geometry[guard].isProjection) {
      // projected geometry is pinned reference geometry — Inventor does not
      // let Move/Trim/etc. touch it in the layer it was projected into
      toast('Projected geometry cannot be modified here.');
      return;
    }
    switch (tool) {
      case Tool.trim:
        final i = _pickEntity(s, w);
        if (i == null) return;
        final old = s.geometry[i];
        final gs = List<Geo>.from(s.geometry)..removeAt(i);
        gs.setAll(0, remapProjectionsAfterRemove(gs, i));
        final piecesStart = gs.length;
        gs.addAll(trimEntity(s.geometry, i, w).where(_notDegenerate));
        // M36: keep every constraint/dimension the trim leaves standing —
        // point refs follow their surviving piece, entity refs land on the
        // nearest piece of the (unchanged) carrier. Only what was actually
        // cut away loses its constraints, exactly like Inventor.
        final remapped =
            remapAfterReplace(s.constraints, i, old, gs, piecesStart);
        // Inventor: the NEW endpoints a cut creates are constrained where they
        // landed — onto the cutting entity (point-on-curve) or onto the point
        // they meet. Without this the trimmed pieces are loose and drag apart,
        // which is exactly what the device session showed (trims only ever
        // REMOVED constraints, 55 -> 49).
        _bindCutPoints(gs, old, piecesStart, remapped);
        // Atomic: verify on the remapped copies BEFORE adopting them. A trim
        // whose surviving constraints cannot be satisfied (a remap edge case)
        // must not scramble the sketch — it is refused instead.
        if (!solveConstraints(gs, remapped)) {
          Log.w('modify', 'trim e$i REJECTED — result cannot be satisfied');
          toast('This trim would break the sketch constraints.');
          return;
        }
        Log.i('modify',
            'trim e$i: constraints ${s.constraints.length} -> ${remapped.length}');
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
        final old = s.geometry[i];
        final gs = List<Geo>.from(s.geometry)..removeAt(i);
        gs.setAll(0, remapProjectionsAfterRemove(gs, i));
        final piecesStart = gs.length;
        gs.addAll(parts);
        // M36: a split keeps EVERY point, so all point-referencing
        // constraints survive; entity refs go to the nearest piece.
        final remapped =
            remapAfterReplace(s.constraints, i, old, gs, piecesStart);
        // Inventor glues the two halves back together at the split point:
        // both pieces get a coincident there (and onto whatever the split
        // landed on), so a later drag moves them as connected geometry.
        _bindCutPoints(gs, old, piecesStart, remapped);
        if (!solveConstraints(gs, remapped)) {
          Log.w('modify', 'split e$i REJECTED — result cannot be satisfied');
          toast('This split would break the sketch constraints.');
          return;
        }
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
  PRef? _nearestPointRef(SketchModel s, Offset w,
      {Iterable<PRef> exclude = const []}) {
    bool excluded(PRef r) =>
        exclude.any((x) => x.ent == r.ent && x.pt == r.pt);
    PRef? best;
    var bd = 10 / zoom;
    // The projected center point is a real pick target in Inventor — you
    // dimension and constrain against it like any vertex. It has no slot in
    // the geometry list (negative sentinel), so offer it explicitly.
    final dOrigin = w.distance;
    if (dOrigin < bd && !excluded(const PRef(kProjCenter, 0))) {
      bd = dOrigin;
      best = const PRef(kProjCenter, 0);
    }
    for (var e = 0; e < s.geometry.length; e++) {
      if (!geoEditable(s.geometry[e])) continue; // other layers are read-only
      for (var p2 = 0; p2 < ptCount(s.geometry[e]); p2++) {
        if (excluded(PRef(e, p2))) continue;
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
    // The rank check above rejects REDUNDANT candidates; a candidate can still
    // be CONTRADICTORY (independent equation, no solution — e.g. tangent to a
    // circle that other constraints hold out of reach). The solve is the
    // arbiter: if it cannot satisfy the new system, take the constraint back
    // out — never leave the sketch with an unsatisfiable set.
    if (!_solveAndRebuild(s)) {
      s.constraints.remove(c);
      Log.i('constraint', 'REJECTED ${conStr(-1, c)} — cannot be satisfied');
      toast('This constraint cannot be satisfied with the current geometry.');
      return false;
    }
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

  /// Solves a copy of the sketch and rebuilds the engine from it. Returns
  /// false — WITHOUT touching the sketch — when the solve failed to hold the
  /// constraints, so callers can roll back whatever change made the system
  /// unsatisfiable instead of committing a diverged configuration.
  bool _solveAndRebuild(SketchModel s, [List<Geo>? base]) {
    final gs = List<Geo>.from(base ?? s.geometry);
    final ok = solveConstraints(gs, s.constraints);
    if (!ok) {
      Log.w('solve', 'solveAndRebuild: unsatisfied — sketch left unchanged');
      return false;
    }
    _rebuildEngine(s, gs);
    return true;
  }

  void _constraintClick(SketchModel s, Offset w) {
    // A second point pick must never resolve to the SAME point as the first —
    // when two entities' endpoints sit on top of each other (post-trim, shared
    // corners), the nearest hit for both taps is identical and the constraint
    // degenerates to e.p==e.p (device log: coincident e17.p1,e17.p1 rejected).
    // Excluding the first pick makes the second tap land on the OTHER
    // entity's point at that location, which is what the user is pointing at.
    final pt = conPts.isEmpty
        ? _nearestPointRef(s, w)
        : _nearestPointRef(s, w, exclude: conPts);
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
        conEntClicks.add(w);
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
            bool plainPoly(Geo g) =>
                g.type == Geo.polyline && g.spline == Geo.straight;
            if (!round(g1.type) && !round(g2.type) && !spl(g1) && !spl(g2)) {
              toast('Tangent needs at least one curved entity.');
              conEnts.clear();
              conEntClicks.clear();
              return;
            }
            if ((spl(g1) && g1.data[0] != 0) || (spl(g2) && g2.data[0] != 0)) {
              toast('Tangent to a CLOSED spline is not supported.');
              conEnts.clear();
              conEntClicks.clear();
              return;
            }
            if (spl(g1) || spl(g2) || plainPoly(g1) || plainPoly(g2)) {
              // Inventor's spline tangency acts at a spline ENDPOINT: the
              // end tangent (along the two defining points at that end for
              // both CV and fit splines) is aligned with the other entity.
              // WHICH end — and, when the partner is a rectangle/polygon,
              // WHICH edge — is resolved from the pick CLICKS: both spline
              // ends can sit on the same rectangle (real user sketch), so
              // "nearest end to the partner" can tie. Without a click record
              // (defensive) the old nearest-to-partner heuristic remains.
              final clicksOk = conEntClicks.length == conEnts.length;

              PRef endRef(int k) {
                final g = s.geometry[conEnts[k]];
                final n = g.data[1].toInt();
                if (clicksOk) {
                  final c = conEntClicks[k];
                  final d0 = (getPt(g, 0) - c).distance;
                  final d1 = (getPt(g, n - 1) - c).distance;
                  return PRef(conEnts[k], d0 <= d1 ? 0 : n - 1);
                }
                final other = s.geometry[conEnts[1 - k]];
                final d0 = distToEntity(other, getPt(g, 0));
                final d1 = distToEntity(other, getPt(g, n - 1));
                return PRef(conEnts[k], d0 <= d1 ? 0 : n - 1);
              }

              final pts = <PRef>[
                for (var k = 0; k < 2; k++)
                  if (spl(s.geometry[conEnts[k]])) endRef(k),
              ];
              // ...then the clicked-edge vertex pair of a plain-polyline
              // partner (rectangle/polygon side); without a click record,
              // the edge nearest to the curved partner's anchor.
              for (var k = 0; k < 2; k++) {
                final g = s.geometry[conEnts[k]];
                if (!plainPoly(g)) continue;
                final at = clicksOk
                    ? conEntClicks[k]
                    : pts.isNotEmpty
                        ? refPt(s.geometry, pts[0])
                        : getPt(s.geometry[conEnts[1 - k]], 0);
                final seg = polySegmentAt(s, conEnts[k], at);
                if (seg == null) {
                  toast('Tangent needs at least one curved entity.');
                  conEnts.clear();
                  conEntClicks.clear();
                  return;
                }
                pts
                  ..add(seg.$1)
                  ..add(seg.$2);
              }
              _addConstraint(s,
                  Constraint(CType.tangent, ents: List.of(conEnts), pts: pts));
              conEnts.clear();
              conEntClicks.clear();
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
              conEntClicks.clear();
              return;
            }
          }
          _addConstraint(s, Constraint(type, ents: List.of(conEnts)));
          conEnts.clear();
          conEntClicks.clear();
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
    conEntClicks.clear();
    conEdges.clear();
    if (s == null || d == null) {
      notifyListeners();
      return;
    }
    d.driven = driven;
    ensureParamNames(s);
    ensureParamName(s, d); // M41: every dimension is a named parameter
    d.value = driven
        ? measureDim(s.geometry, d)
        : (value ?? measureDim(s.geometry, d));
    s.constraints.add(d);
    if (!_solveAndRebuild(s)) {
      // A driving dimension whose value the geometry cannot reach must not
      // stay in the sketch half-satisfied. Take it back out.
      s.constraints.remove(d);
      toast('This value cannot be satisfied with the current constraints.');
    }
    notifyListeners();
  }

  /// M41 — confirms the pending dimension from the RAW edit-box text. The
  /// dimension is created either way (Inventor keeps it when you click
  /// away); the text is then applied as value/expression/rename on top.
  /// Returns true when the text was applied cleanly.
  bool confirmDimensionText(String raw) {
    final d = pendingDim;
    confirmDimension(null); // creates with the measured value + auto name
    final s = current;
    if (s == null || d == null || !s.constraints.contains(d)) return false;
    if (raw.trim().isEmpty) return true;
    return setDimensionText(d, raw);
  }

  void cancelDimension() {
    pendingDim = null;
    conPts.clear();
    conEnts.clear();
    conEntClicks.clear();
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
    // M41: an explicit numeric set clears any stored expression (Inventor:
    // typing a plain number over an equation replaces it).
    final snap = _snapshotDims(s);
    c.value = v;
    c.expr = null;
    // _solveAndRebuild leaves the sketch UNTOUCHED when the new value cannot
    // be satisfied — so a rollback is just restoring the numbers. (The old
    // implementation committed the diverged geometry first and then tried to
    // solve its way back, which was path-dependent and could leave the sketch
    // subtly displaced.)
    if (!_solveOnceThenChase(s)) {
      _restoreDims(snap);
      toast('Value cannot be satisfied with the current constraints.');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- M41 ----
  // Inventors parameter/expression system. Every dimension is a named
  // parameter (auto d0, d1, … — renamable via "Name = expr"); the edit box
  // accepts full expressions referencing other dimensions; the stored
  // expression re-evaluates whenever a referenced parameter changes; the
  // display shows only the calculated value (fx:-prefixed), the raw
  // expression reappears when the box is opened again.

  /// Smallest unused auto name d0, d1, … in [s] (Inventor's default names).
  String _newParamName(SketchModel s) {
    final used = {
      for (final c in s.constraints)
        if (c.paramName != null) c.paramName!
    };
    var i = 0;
    while (used.contains('d$i')) {
      i++;
    }
    return 'd$i';
  }

  /// The dimension's parameter name, assigning an auto name on first use.
  String ensureParamName(SketchModel s, Constraint c) =>
      c.paramName ??= _newParamName(s);

  /// Assigns auto names to every dimension that has none — pre-M41 sidecars
  /// load nameless, and expressions need stable names to reference.
  void ensureParamNames(SketchModel s) {
    for (final c in s.constraints) {
      if (c.type == CType.dimension) ensureParamName(s, c);
    }
  }

  /// name -> current base value (mm resp. deg) of every named dimension.
  Map<String, double> paramTable(SketchModel s) => {
        for (final c in s.constraints)
          if (c.type == CType.dimension &&
              c.paramName != null &&
              c.value != null)
            c.paramName!: c.value!,
      };

  Constraint? _dimByName(SketchModel s, String name) {
    for (final c in s.constraints) {
      if (c.type == CType.dimension && c.paramName == name) return c;
    }
    return null;
  }

  static bool _isAngleDim(Constraint c) =>
      c.dimKind == 'ang' || c.dimKind == 'ang3' || c.dimKind == 'ang4';

  /// True when making [c]'s expression reference [ref] would close a cycle
  /// (ref depends — transitively — on c).
  bool _wouldCycle(SketchModel s, Constraint c, String ref) {
    final seen = <String>{};
    bool dependsOnC(String name) {
      if (!seen.add(name)) return false;
      final d = _dimByName(s, name);
      if (d == null) return false;
      if (identical(d, c)) return true;
      if (d.expr == null) return false;
      return exprRefs(d.expr!).any(dependsOnC);
    }

    return dependsOnC(ref);
  }

  List<(Constraint, double?, String?)> _snapshotDims(SketchModel s) => [
        for (final c in s.constraints)
          if (c.type == CType.dimension) (c, c.value, c.expr)
      ];

  void _restoreDims(List<(Constraint, double?, String?)> snap) {
    for (final (c, v, e) in snap) {
      c.value = v;
      c.expr = e;
    }
  }

  /// Re-evaluates every expression-driven dimension against the current
  /// parameter table, iterating to a fixpoint so chains (d2 = d1*2,
  /// d3 = d2+5) settle in one call. Returns true when any value changed.
  /// Evaluation failures (deleted reference, bad expr) leave the value
  /// FROZEN — Inventor keeps the last good value and flags the expression
  /// red on the next edit.
  bool _applyExprValues(SketchModel s) {
    var changedAny = false;
    for (var pass = 0; pass < 8; pass++) {
      final table = paramTable(s);
      var changed = false;
      for (final c in s.constraints) {
        if (c.type != CType.dimension || c.expr == null || c.driven) continue;
        final v = evalExpr(c.expr!, table, angle: _isAngleDim(c));
        if (v != null && (c.value == null || (v - c.value!).abs() > 1e-9)) {
          c.value = v;
          changed = true;
        }
      }
      if (!changed) break;
      changedAny = true;
    }
    return changedAny;
  }

  bool _inExprChase = false;

  /// Solve, then chase expression dependencies to a fixpoint: driven
  /// (reference) dimensions re-measure after every solve, and expressions
  /// referencing THEM must follow — which needs another solve. Converges in
  /// one extra round for all practical sketches; capped defensively.
  bool _solveOnceThenChase(SketchModel s) {
    if (!_solveAndRebuild(s)) return false;
    _chaseExpressions(s);
    return true;
  }

  void _chaseExpressions(SketchModel s) {
    if (_inExprChase) return;
    _inExprChase = true;
    try {
      for (var i = 0; i < 3; i++) {
        if (!_applyExprValues(s)) return; // fixpoint — nothing moved
        final snap = _snapshotDims(s);
        if (!_solveAndRebuild(s)) {
          // an expression value the geometry cannot reach must not stick:
          // freeze everything back to the last consistent numbers
          _restoreDims(snap);
          Log.w('params', 'expression chase: unsatisfiable — values frozen');
          return;
        }
      }
    } finally {
      _inExprChase = false;
    }
  }

  /// Commits the raw edit-box text of a dimension — Inventors full edit box:
  /// plain number ("12", "1.5 cm"), expression ("d0/2 + 5"), or rename +
  /// either ("Width = d0/2"). Returns false (with a toast) when the entry is
  /// invalid or unsatisfiable; the caller keeps the editor open showing red.
  bool setDimensionText(Constraint c, String raw) {
    final s = current;
    if (s == null) return false;
    if (c.driven) {
      toast('This is a driven (reference) dimension — it cannot be edited.');
      return false;
    }
    ensureParamNames(s);
    final (name, body) = splitAssignment(raw);
    if (body.trim().isEmpty) return false;
    if (name != null) {
      if (!isValidParamName(name)) {
        toast('Invalid parameter name.');
        return false;
      }
      final other = _dimByName(s, name);
      if (other != null && !identical(other, c)) {
        toast('Parameter name "$name" is already in use.');
        return false;
      }
    }
    final angle = _isAngleDim(c);
    final refs = exprRefs(body);
    for (final r in refs) {
      if (_dimByName(s, r) == null) {
        toast('Unknown parameter "$r".');
        return false;
      }
      if (r == c.paramName || _wouldCycle(s, c, r)) {
        toast('Circular reference: "$r" depends on this dimension.');
        return false;
      }
    }
    final v = evalExpr(body, paramTable(s), angle: angle);
    if (v == null) {
      toast('Invalid expression.');
      return false;
    }
    final snap = _snapshotDims(s);
    final oldName = c.paramName;
    c.value = v;
    // a bare number is stored as a value — Inventor shows the fx: prefix
    // only for equation-driven dimensions
    c.expr = isPlainNumber(body) ? null : body.trim();
    if (name != null) c.paramName = name;
    if (name != null && oldName != null && oldName != name) {
      _renameRefs(s, oldName, name);
    }
    if (!_solveOnceThenChase(s)) {
      _restoreDims(snap);
      c.paramName = oldName;
      if (name != null && oldName != null && oldName != name) {
        _renameRefs(s, name, oldName);
      }
      toast('Value cannot be satisfied with the current constraints.');
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  /// Renames [from] to [to] inside every stored expression (word-boundary
  /// match, so renaming d1 does not maul d10).
  void _renameRefs(SketchModel s, String from, String to) {
    final re = RegExp('\\b${RegExp.escape(from)}\\b');
    for (final c in s.constraints) {
      if (c.expr != null) c.expr = c.expr!.replaceAll(re, to);
    }
  }

  /// Live validation for the edit box (Inventor colours bad syntax red while
  /// typing). Checks assignment form, syntax, known refs and cycles — without
  /// committing anything.
  bool dimTextValid(Constraint c, String raw) {
    final s = current;
    if (s == null) return false;
    final (name, body) = splitAssignment(raw);
    if (body.trim().isEmpty) return false;
    if (name != null) {
      if (!isValidParamName(name)) return false;
      final other = _dimByName(s, name);
      if (other != null && !identical(other, c)) return false;
    }
    final refs = exprRefs(body);
    for (final r in refs) {
      if (_dimByName(s, r) == null) return false;
      if (r == c.paramName || _wouldCycle(s, c, r)) return false;
    }
    return evalExpr(body, paramTable(s), angle: _isAngleDim(c)) != null;
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
    // Fillet/Chamfer (M36, Inventor-complete): trim the picked entities back
    // to the tangent points AND constrain the result — coincident at both
    // seams, tangent on both sides (fillet). The first fillet of a value
    // carries its radius dimension; subsequent ones get an equal constraint
    // to it. Chamfer: coincident seams; equal-distance chamfers chain equal
    // to the first, which carries a length dimension.
    if ((tool == Tool.fillet || tool == Tool.chamfer) &&
        toolPoints.length >= 2) {
      final f = filletSess ?? FilletSession(tool);
      final res = tool == Tool.fillet
          ? filletInventor(s.geometry, toolPoints[0], toolPoints[1], f.radius)
          : chamferInventor(s.geometry, toolPoints[0], toolPoints[1],
              mode: f.mode, d1: f.d1, d2: f.d2, angDeg: f.angle);
      toolPoints.clear();
      if (res == null) {
        toast(tool == Tool.fillet
            ? 'Pick two lines, arcs or circles that can meet.'
            : 'Pick two non-parallel lines.');
        return;
      }
      // Build the result on LOCAL copies so a fillet/chamfer that cannot be
      // satisfied leaves the sketch untouched (atomic operation). s.geometry
      // and s.constraints are only adopted once the solve verifies.
      final gs = List<Geo>.from(s.geometry);
      res.repl.forEach((i, g) => gs[i] = g);
      final newIdx = gs.length;
      gs.addAll(res.adds); // already carries the picked entities' layer
      final cons = List<Constraint>.from(s.constraints);

      // CRITICAL: the two picked edges usually meet at a shared corner held by
      // a coincidence (every rectangle/polygon corner is one). The fillet/
      // chamfer SPLITS that corner into two distinct tangent points joined by
      // the new arc/line, so the old corner coincidence must be dropped — left
      // in place it forces the new segment's two ends onto the same point
      // (length 0) while its dimension demands a real length, and the whole
      // sketch diverges. This was the "chamfer scrambles everything / line runs
      // over the fillet" bug. Only a DIRECT coincidence between the two moved
      // corner points is removed; unrelated coincidences are kept.
      final (e1, p1s) = res.seams[0];
      final (e2, p2s) = res.seams[1];
      if (p1s != null && p2s != null) {
        bool isRef(PRef r, int e, int p) => r.ent == e && r.pt == p;
        cons.removeWhere((c) =>
            c.type == CType.coincident &&
            c.pts.length == 2 &&
            ((isRef(c.pts[0], e1, p1s) && isRef(c.pts[1], e2, p2s)) ||
                (isRef(c.pts[0], e2, p2s) && isRef(c.pts[1], e1, p1s))));
      }

      // seams: glue the new arc/line to the trimmed ends + tangency (fillet)
      for (var k = 0; k < 2; k++) {
        final (ent, pt) = res.seams[k];
        if (pt != null) {
          cons.add(Constraint(CType.coincident,
              pts: [PRef(newIdx, res.jointPt(k)), PRef(ent, pt)]));
        }
        if (tool == Tool.fillet) {
          cons.add(Constraint(CType.tangent, ents: [newIdx, ent]));
        }
      }

      // Dimensions. Fillet: EVERY fillet carries its own radius dimension —
      // the user's spec ("fillets should have a dimension automatically, just
      // like chamfers — a radius measurement"), and it reads unambiguously on
      // canvas. The earlier equal-chain (first-of-a-value dimensioned, rest
      // chained) left most fillets without a visible measurement. Chamfer: the
      // two LEG extents (x and y of the chamfer line's endpoints), NOT the
      // diagonal — Inventor's "aligned dimensions of the setback distance".
      final g0 = res.adds.first;
      if (tool == Tool.fillet) {
        // text just outside the arc's midpoint, like Inventor's R-label
        final midAng = (g0.data[3] + g0.data[4]) / 2;
        cons.add(Constraint(CType.dimension,
            ents: [newIdx],
            dimKind: 'rad',
            value: f.radius,
            textPos: Offset(
                g0.data[0] + (g0.data[2] + 8) * math.cos(midAng),
                g0.data[1] + (g0.data[2] + 8) * math.sin(midAng))));
      } else {
        // chamfer: distx + disty on the two endpoints of the chamfer line
        final ax = g0.data[0], ay = g0.data[1], bx = g0.data[2], by = g0.data[3];
        cons.add(Constraint(CType.dimension,
            pts: [PRef(newIdx, 0), PRef(newIdx, 1)],
            dimKind: 'distx',
            value: (bx - ax).abs(),
            textPos: Offset((ax + bx) / 2, math.min(ay, by) - 6)));
        cons.add(Constraint(CType.dimension,
            pts: [PRef(newIdx, 0), PRef(newIdx, 1)],
            dimKind: 'disty',
            value: (by - ay).abs(),
            textPos: Offset(math.max(ax, bx) + 6, (ay + by) / 2)));
      }

      // Verify on the local copies. If the operation cannot be satisfied (or
      // produced a degenerate entity), roll back completely — the sketch, and
      // anything else in it (a slot built earlier), is left exactly as it was.
      final ok = solveConstraints(gs, cons);
      if (!ok) {
        Log.w('modify',
            '${tool.name} at e$e1/e$e2 REJECTED — result cannot be satisfied; '
            'rolling back');
        toast(tool == Tool.fillet
            ? 'That fillet would break the sketch — pick a valid corner or a '
                'smaller radius.'
            : 'That chamfer would break the sketch — pick a valid corner or '
                'smaller distances.');
        return; // s.geometry / s.constraints untouched
      }
      Log.i('modify',
          '${tool.name} at e$e1/e$e2 -> e$newIdx (dimensioned)');
      s.constraints
        ..clear()
        ..addAll(cons);
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
      final consAtCommitStart = s.constraints.length;
      // true for shapes that add their own deterministic constraint set —
      // those still need POINT bindings to pre-existing geometry (a corner on
      // the center point, on an old vertex, on an old edge), which used to be
      // inference's job and silently stopped for them when the deterministic
      // sets were introduced (M34/M36). See the binding block after the chain.
      var deterministicShape = false;
      final isRect = tool == Tool.rectTwoPoint ||
          tool == Tool.rect3P ||
          tool == Tool.rect2PC ||
          tool == Tool.rect3PC;
      if (isRect && placed.length == 4) {
        deterministicShape = true;
        // Inventor's rectangle: four LINES held together by constraints —
        // coincident at every corner, plus H/V (axis-aligned tools) or
        // perpendicular (the rotated 3-point tools; the 4th right angle is
        // implied and would only be redundant). Added deterministically here
        // instead of relying on inference.
        for (var k = 0; k < 4; k++) {
          s.constraints.add(Constraint(CType.coincident, pts: [
            PRef(firstNew + k, 1),
            PRef(firstNew + (k + 1) % 4, 0),
          ]));
        }
        if (tool == Tool.rectTwoPoint || tool == Tool.rect2PC) {
          for (var k = 0; k < 4; k++) {
            s.constraints.add(Constraint(
                k.isEven ? CType.horizontal : CType.vertical,
                ents: [firstNew + k]));
          }
        } else {
          for (var k = 0; k < 3; k++) {
            s.constraints.add(Constraint(CType.perpendicular,
                ents: [firstNew + k, firstNew + k + 1]));
          }
        }
      } else if ((tool == Tool.slotCC ||
              tool == Tool.slotOverall ||
              tool == Tool.slotCP) &&
          placed.length == 5) {
        deterministicShape = true;
        // Inventor's linear slot: [line1, line2, cap1, cap2, axis] where cap1
        // runs line1.p0 -> line2.p1 and cap2 runs line2.p0 -> line1.p1
        // (see _linearSlot); the AXIS (M40) is a construction line between
        // the two cap centers. Constraints: coincident + tangent at all four
        // seams, the cap radii equal, and the axis endpoints coincident on
        // the cap centers. Rail parallelism is IMPLIED by the
        // tangencies (measured with the app's own residuals: 14 equations
        // incl. parallel have rank 13 — parallel is a redundant row that
        // makes the LM normal equations singular and libslvs flag the
        // sketch inconsistent, which is what made slot drags flicker and
        // collapse). Inventor itself refuses redundant constraints ("You
        // cannot overconstrain a sketch"), so the minimal set IS the
        // Inventor-faithful one. Result: 13 independent equations on 18
        // params — exactly the 5 slot DOF (position, rotation, length,
        // radius) — plus the axis: 4 more params fully pinned by 4 more
        // equations (its two endpoints on the two distinct cap centers),
        // so the DOF count is unchanged and nothing goes redundant.
        final l1 = firstNew, l2 = firstNew + 1, c1 = firstNew + 2,
            c2 = firstNew + 3, ax = firstNew + 4;
        s.constraints.addAll([
          Constraint(CType.coincident, pts: [PRef(c1, 1), PRef(l1, 0)]),
          Constraint(CType.coincident, pts: [PRef(c1, 2), PRef(l2, 1)]),
          Constraint(CType.coincident, pts: [PRef(c2, 1), PRef(l2, 0)]),
          Constraint(CType.coincident, pts: [PRef(c2, 2), PRef(l1, 1)]),
          Constraint(CType.tangent, ents: [l1, c1]),
          Constraint(CType.tangent, ents: [l2, c1]),
          Constraint(CType.tangent, ents: [l1, c2]),
          Constraint(CType.tangent, ents: [l2, c2]),
          Constraint(CType.equal, ents: [c1, c2]),
          Constraint(CType.coincident, pts: [PRef(ax, 0), PRef(c1, 0)]),
          Constraint(CType.coincident, pts: [PRef(ax, 1), PRef(c2, 0)]),
        ]);
      } else if ((tool == Tool.slot3A || tool == Tool.slotCPA) &&
          placed.length == 4) {
        deterministicShape = true;
        // Inventor's arc slot: [outer, inner, capA, capB]; capA runs
        // outer.start -> inner.start, capB inner.end -> outer.end (see
        // _arcSlot). Rails concentric, coincident + tangent at the seams.
        // Cap-radius equality is IMPLIED (each cap radius is exactly
        // (R_outer - R_inner)/2 once it is tangent to both concentric rails
        // with its ends on them; measured: 15 equations incl. equal have
        // rank 14). The redundant row is dropped for the same reason as the
        // linear slot's parallel — 14 independent equations on 20 params =
        // the 6 arc-slot DOF (center, rail radius, cap radius, two sweeps).
        final o = firstNew, inn = firstNew + 1, ca = firstNew + 2,
            cb = firstNew + 3;
        s.constraints.addAll([
          Constraint(CType.concentric, ents: [o, inn]),
          Constraint(CType.coincident, pts: [PRef(ca, 1), PRef(o, 1)]),
          Constraint(CType.coincident, pts: [PRef(ca, 2), PRef(inn, 1)]),
          Constraint(CType.coincident, pts: [PRef(cb, 1), PRef(inn, 2)]),
          Constraint(CType.coincident, pts: [PRef(cb, 2), PRef(o, 2)]),
          Constraint(CType.tangent, ents: [o, ca]),
          Constraint(CType.tangent, ents: [inn, ca]),
          Constraint(CType.tangent, ents: [o, cb]),
          Constraint(CType.tangent, ents: [inn, cb]),
        ]);
      } else if (tool == Tool.circleTangent && placed.length == 1) {
        deterministicShape = true;
        // Inventor's tangent circle: TANGENT to each of the three picked
        // lines — the picks are the tool points themselves.
        for (final tp in toolPoints.take(3)) {
          final li = nearestLineIdx(gs, tp, exclude: firstNew);
          if (li != null) {
            s.constraints
                .add(Constraint(CType.tangent, ents: [firstNew, li]));
          }
        }
      } else if (tool == Tool.arcTangent && placed.length == 1) {
        deterministicShape = true;
        // Inventor's tangent arc: coincident on the source endpoint it
        // started from + tangent to that source (only when an arc actually
        // resulted — the degenerate straight case is just a line). Added
        // deterministically INSTEAD of inference, which would duplicate the
        // coincident from the endpoint snap.
        final src = _nearestPointRef(s, toolPoints.first);
        if (src != null && isRealPt(src, gs) && src.ent != firstNew) {
          s.constraints.add(Constraint(CType.coincident,
              pts: [PRef(firstNew, gs[firstNew].type == Geo.arc ? 1 : 0),
                  src]));
          if (gs[firstNew].type == Geo.arc &&
              gs[src.ent].type != Geo.polyline) {
            s.constraints
                .add(Constraint(CType.tangent, ents: [firstNew, src.ent]));
          }
        }
      } else if (autoConstrain) {
        for (var i = firstNew; i < gs.length; i++) {
          s.constraints.addAll(inferConstraints(gs, i));
        }
      }
      // Deterministic shapes still get POINT bindings to what was already
      // there — a rectangle corner drawn onto the projected center point, onto
      // an existing vertex, or onto an existing edge binds exactly like it
      // would for a plain line (Inventor behaviour; regressed when the
      // deterministic sets replaced inference for these shapes). Internal
      // relations are excluded via bindOnlyBefore, and every candidate passes
      // the same over-constraint gate as a manual constraint.
      if (deterministicShape && autoConstrain) {
        for (var i = firstNew; i < gs.length; i++) {
          for (final c
              in inferPointBindings(gs, i, bindOnlyBefore: firstNew)) {
            if (!wouldOverconstrain(gs, s.constraints, c)) {
              s.constraints.add(c);
            }
          }
        }
      }
      if (tool == Tool.ellipse &&
          placed.length == 1 &&
          placed[0].spline == Geo.ellipseTag) {
        _addEllipseAxes(s, gs, firstNew, layer);
      }
      // Constructions place their geometry ALREADY satisfying their auto-
      // constraints (residual ~1e-14), so this solve is a formality that tidies
      // last-digit noise. If it ever reports failure (a genuine bug upstream),
      // never throw the user's shape away: commit the as-drawn geometry and
      // drop the auto-constraints this commit added, loudly.
      final preSolve = List<Geo>.from(gs);
      final consBefore2 = consAtCommitStart;
      if (!solveConstraints(gs, s.constraints)) {
        Log.e('tool', 'construction auto-constraints unsatisfied for $tool — '
            'committing as drawn WITHOUT them');
        s.constraints.removeRange(consBefore2, s.constraints.length);
        _rebuildEngine(s, preSolve);
      } else {
        _rebuildEngine(s, gs);
      }
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
  void toggleCenterlineSelected() =>
      _toggleStyleSelected(Geo.styleCenterline, 'centerline');

  /// Inventor's Format > Construction (M40): converts the selection to
  /// construction linetype, or back to normal if everything selected already
  /// is construction. Works on any entity type — the geometry stays fully
  /// constrainable, dimensionable, snappable and draggable; only the
  /// rendering changes (thin + finely dashed).
  void toggleConstructionSelected() =>
      _toggleStyleSelected(Geo.styleConstruction, 'construction');

  void _toggleStyleSelected(int style, String what) {
    final s = current;
    if (s == null || selection.isEmpty) {
      toast('Select geometry first, then toggle $what.');
      return;
    }
    final gs = List<Geo>.from(s.geometry);
    // Inventor semantics: if ANY selected entity is not yet of this style,
    // the click converts TO it; only a uniformly-styled selection reverts.
    final convert =
        selection.any((i) => i < gs.length && gs[i].style != style);
    for (final i in selection) {
      if (i >= gs.length) continue;
      gs[i] = gs[i].withStyle(convert ? style : Geo.styleNormal);
    }
    Log.i('format',
        '$what ${convert ? "set" : "cleared"} on ${selection.length} entities');
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
    } else if (tool == Tool.project) {
      // project mode highlights the PROJECTABLE geometry under the cursor:
      // entities of OTHER layers that are not yet projected onto this one
      final e = pickVisibleAny(s, w);
      hoverEnt = e != null &&
              editingLayer != null &&
              s.geometry[e].layer != editingLayer &&
              !_isProjectedOnto(s, e, editingLayer!)
          ? e
          : null;
      // the halo painter draws PLAIN polylines edge-wise (hoverEdge) — a
      // rectangle got no highlight at all without this (device feedback)
      final seg = hoverEnt != null &&
              s.geometry[hoverEnt!].type == Geo.polyline &&
              !s.geometry[hoverEnt!].isSpline
          ? polySegmentAt(s, hoverEnt!, w)
          : null;
      hoverEdge = seg == null ? null : (seg.$1.ent, seg.$1.pt);
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
      // Projection tags (M32) ride in their own sidecar, same scheme.
      final prj = <String, dynamic>{};
      for (var i = 0; i < s.geometry.length; i++) {
        final g = s.geometry[i];
        if (g.isProjection) {
          // plain int for whole-entity/axis projections (backward-compatible
          // with M32 sidecars), [proj, projSeg] for edge projections
          prj['$i'] = g.projSeg >= 0 ? [g.proj, g.projSeg] : g.proj;
        }
      }
      final pf = File('${_sketchDir.path}/$name.proj.json');
      if (prj.isEmpty) {
        if (pf.existsSync()) pf.deleteSync();
      } else {
        pf.writeAsStringSync(jsonEncode(prj));
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
  // CONSTRUCTION style (M40): thinner + finely dashed, for every entity
  // type. The paint is CLONED — p is often a shared caller paint (selection
  // halo, hover) and must not be mutated.
  if (g.isConstruction) {
    p = Paint()
      ..color = p.color
      ..style = PaintingStyle.stroke
      ..strokeCap = p.strokeCap
      ..strokeWidth = math.max(0.7, p.strokeWidth * 0.55);
  }
  final cDash = g.isConstruction; // fine 5/4 dash on the curve itself
  switch (g.type) {
    case Geo.line:
      if (cDash) {
        _dashedSeg(canvas, map(g.data[0], g.data[1]),
            map(g.data[2], g.data[3]), p, dash: 5, gap: 4);
      } else if (g.isCenterline) {
        // centerline STYLE: same entity, dashed rendering (Inventor's toggle)
        _dashedSeg(canvas, map(g.data[0], g.data[1]),
            map(g.data[2], g.data[3]), p, dash: 10, gap: 5);
      } else {
        canvas.drawLine(
            map(g.data[0], g.data[1]), map(g.data[2], g.data[3]), p);
      }
      break;
    case Geo.circle:
      if (cDash) {
        final c = map(g.data[0], g.data[1]);
        final r = g.data[2] * scale;
        _dashedChain(canvas,
            [for (var i = 0; i <= 96; i++) c + Offset(
                r * math.cos(i * math.pi / 48),
                r * math.sin(i * math.pi / 48))], p);
      } else {
        canvas.drawCircle(map(g.data[0], g.data[1]), g.data[2] * scale, p);
      }
      break;
    case Geo.arc:
      final c = map(g.data[0], g.data[1]);
      final r = g.data[2] * scale;
      final a1 = g.data[3], a2 = g.data[4];
      // Defensive: an arc is normally 6 elements, but never let a short one
      // throw here — a RangeError in paintGeo aborts the whole CustomPainter
      // and blanks every entity after it. Treat a missing flag as not-reversed.
      final reversed = g.data.length > 5 && g.data[5] != 0;
      // Last line of defence against degenerate arcs (r <= 0 or ~zero sweep):
      // upstream gates should never let them through, but if one slips in,
      // draw a minimal visible dot instead of drawArc(sweep≈0), which renders
      // NOTHING and makes the entity look deleted (the slot-flicker symptom).
      if (!(r > 0)) {
        canvas.drawCircle(c, 1.5, p);
        break;
      }
      double norm(double x) {
        var v = x % (2 * math.pi);
        if (v < 0) v += 2 * math.pi;
        return v;
      }

      // world sweep: CCW (positive) if not reversed, CW (negative) otherwise
      var sweep = reversed ? -norm(a1 - a2) : norm(a2 - a1);
      if (sweep.abs() < 1e-6) {
        canvas.drawCircle(c, math.max(1.5, r.clamp(0, 3.0)), p);
        break;
      }
      // world angles are CCW with y-up; screen y is flipped -> negate both
      if (cDash) {
        final n = math.max(8, (r * sweep.abs() / 6).ceil());
        _dashedChain(canvas, [
          for (var i = 0; i <= n; i++)
            c + Offset(r * math.cos(-a1 - sweep * i / n),
                r * math.sin(-a1 - sweep * i / n))
        ], p);
      } else {
        canvas.drawArc(
            Rect.fromCircle(center: c, radius: r), -a1, -sweep, false, p);
      }
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
        final pts = [for (final w in curve) map(w.dx, w.dy)];
        if (cDash) {
          _dashedChain(canvas, pts, p);
          break;
        }
        final path = Path()..moveTo(pts[0].dx, pts[0].dy);
        for (var i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(path, p);
        break;
      }
      final vs = [
        for (var i = 0; i < n; i++) map(g.data[2 + 2 * i], g.data[3 + 2 * i])
      ];
      if (closed) vs.add(vs[0]);
      if (cDash) {
        _dashedChain(canvas, vs, p);
        break;
      }
      final path = Path()..moveTo(vs[0].dx, vs[0].dy);
      for (var i = 1; i < vs.length; i++) {
        path.lineTo(vs[i].dx, vs[i].dy);
      }
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
/// Fine 5/4 dash along a point chain with CONTINUOUS phase across the
/// vertices — construction circles/arcs/polylines/splines dash evenly instead
/// of restarting the pattern at every sample point.
void _dashedChain(Canvas c, List<Offset> pts, Paint p,
    {double dash = 5, double gap = 4}) {
  var phase = 0.0; // distance into the current dash+gap period
  final period = dash + gap;
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    final d = b - a;
    final len = d.distance;
    if (len < 1e-9) continue;
    final u = d / len;
    var t = 0.0;
    while (t < len) {
      final inDash = phase < dash;
      final left = inDash ? dash - phase : period - phase;
      final e = math.min(t + left, len);
      if (inDash) c.drawLine(a + u * t, a + u * e, p);
      phase = (phase + (e - t)) % period;
      t = e;
    }
  }
}

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
