// iPadProCAD — application state (tabs, layers, edit mode, active tool) and
// persistence (DXF per sketch + preview PNG in the app Documents directory).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'constraints.dart';
import 'ffi/qcad_engine.dart';
import 'log.dart';
import 'modify.dart';
import 'snap.dart';
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
  bool dirty = false;
  SketchModel(this.name) : engine = Engine.create();

  void refresh() => geometry = engine.allGeometry();
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
      }
      sketches[name] = s;
    }
    if (!openTabs.contains(name)) openTabs.add(name);
    curTab = name;
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
    }
    notifyListeners();
  }

  SketchModel? get current => curTab == null ? null : sketches[curTab];

  // ---- layers / edit mode (mock: new layer starts edit immediately) ----
  void startNewLayer() {
    final s = current;
    if (s == null) return;
    final n = s.layers.length + 1;
    final name = 'Layer $n';
    s.layers.add(name);
    s.dirty = true;
    enterEdit(name);
  }

  void enterEdit(String layerName) {
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

  // ---- selection / snapping / grip editing (M6) ----
  final Set<int> selection = {};
  Snap? snap; // current snap under the cursor (for the marker + guides)
  Grip? dragGrip;
  Offset? dragPos;
  Offset? boxStart, boxEnd; // world coords while box-selecting
  bool boxCrossing = false;
  Rect? lastBoxRect; // remembered for Stretch (Inventor semantics)
  int? modEntity; // entity picked in the first phase of Offset
  bool autoConstrain = true; // Constrain panel: Automatic toggle
  bool showConstraints = true; // Constrain panel: Show Constraints toggle

  void toggleAutoConstrain() {
    autoConstrain = !autoConstrain;
    notifyListeners();
  }

  void toggleShowConstraints() {
    showConstraints = !showConstraints;
    notifyListeners();
  }
  // constraint tool pick buffers
  final List<PRef> conPts = [];
  final List<int> conEnts = [];
  // dimension being placed, waiting for its value dialog (viewport shows it)
  Constraint? pendingDim;

  /// Geometry with an in-progress grip drag applied (painter reads this).
  List<Geo> displayGeometry(SketchModel s) {
    if (dragGrip == null || dragPos == null) return s.geometry;
    final gs = List<Geo>.from(s.geometry);
    gs[dragGrip!.entity] = moveGrip(gs[dragGrip!.entity], dragGrip!, dragPos!);
    // keep constraints satisfied while dragging; the dragged point is pinned
    solveConstraints(gs, s.constraints,
        pinned: {(dragGrip!.entity, dragGrip!.idx)}, iterations: 25);
    return gs;
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
      _rebuildEngine(s, displayGeometry(s));
    }
    dragGrip = null;
    dragPos = null;
    snap = null;
    notifyListeners();
  }

  /// The C-API is add-only, so edits rebuild the document from scratch.
  void _rebuildEngine(SketchModel s, List<Geo> gs) {
    Log.i('engine', 'rebuild with ${gs.length} entities');
    s.engine.dispose();
    s.engine = Engine.create();
    for (final g in gs) {
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
    _committed(s);
    Log.i('engine', 'rebuild done, geometry=${s.geometry.length}');
  }

  // ---- tools ----
  void selectTool(Tool t) {
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
    toolPoints.add(w);
    final meta = toolMeta[tool];
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
    for (var e = 0; e < s.geometry.length; e++) {
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
        if (pt == null) return;
        conPts.add(pt);
        if (conPts.length == 2) {
          s.constraints
              .add(Constraint(CType.coincident, pts: List.of(conPts)));
          conPts.clear();
          _solveAndRebuild(s);
        }
        return;
      case Tool.cHorizontal:
      case Tool.cVertical:
        final t = tool == Tool.cHorizontal ? CType.horizontal : CType.vertical;
        // Inventor: a line -> immediately; two points -> aligned points
        if (ent != null && s.geometry[ent].type == Geo.line && conPts.isEmpty) {
          s.constraints.add(Constraint(t, ents: [ent]));
          _solveAndRebuild(s);
          return;
        }
        if (pt == null) return;
        conPts.add(pt);
        if (conPts.length == 2) {
          s.constraints.add(Constraint(t, pts: List.of(conPts)));
          conPts.clear();
          _solveAndRebuild(s);
        }
        return;
      case Tool.cFix:
        if (pt != null) {
          s.constraints.add(Constraint(CType.fix, pts: [pt]));
        } else if (ent != null) {
          s.constraints.add(Constraint(CType.fix, ents: [ent]));
        }
        return;
      case Tool.cSymmetric:
        // two points, then the symmetry axis line
        if (conPts.length < 2) {
          if (pt != null) conPts.add(pt);
          return;
        }
        if (ent == null || s.geometry[ent].type != Geo.line) return;
        s.constraints.add(Constraint(CType.symmetric,
            pts: List.of(conPts), ents: [ent]));
        conPts.clear();
        _solveAndRebuild(s);
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
          s.constraints.add(Constraint(map[tool]!, ents: List.of(conEnts)));
          conEnts.clear();
          _solveAndRebuild(s);
        }
        return;
      default:
        return;
    }
  }

  void _dimensionClick(SketchModel s, Offset w) {
    if (pendingDim != null) return; // value dialog is open
    final ent = _pickEntity(s, w);
    final pt = _nearestPointRef(s, w);
    // Phase 1 — build the pick set. A second LINE turns a length dimension
    // into an angle dimension, exactly like Inventor.
    if (conPts.isEmpty && ent != null && !conEnts.contains(ent)) {
      final g = s.geometry[ent];
      final firstIsLine =
          conEnts.isEmpty || s.geometry[conEnts[0]].type == Geo.line;
      if (conEnts.isEmpty ||
          (conEnts.length == 1 && g.type == Geo.line && firstIsLine)) {
        conEnts.add(ent);
        return;
      }
    }
    if (conEnts.isEmpty && conPts.length < 2 && pt != null) {
      conPts.add(pt);
      return;
    }
    // Phase 2 — this click places the dimension.
    _placeDimension(s, w);
  }

  /// Inventor picks the dimension type from where you place it: roughly
  /// along the geometry's normal = aligned, above/below = horizontal
  /// distance, left/right = vertical distance.
  String _distKind(SketchModel s, PRef a, PRef b, Offset at) {
    final pa = getPt(s.geometry[a.ent], a.pt);
    final pb = getPt(s.geometry[b.ent], b.pt);
    final d = pb - pa;
    if (d.distance < 1e-9) return 'dist';
    final n = Offset(-d.dy, d.dx) / d.distance;
    final v = at - (pa + pb) / 2;
    if (v.distance < 1e-9) return 'dist';
    final vn = v / v.distance;
    final alongNormal = (vn.dx * n.dx + vn.dy * n.dy).abs();
    if (alongNormal > 0.866) return 'dist'; // within 30 deg of the normal
    return v.dy.abs() >= v.dx.abs() ? 'distx' : 'disty';
  }

  void _placeDimension(SketchModel s, Offset w) {
    Constraint? d;
    if (conEnts.length == 2) {
      d = Constraint(CType.dimension,
          ents: List.of(conEnts), dimKind: 'ang', textPos: w);
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
    } else if (conPts.length == 2) {
      d = Constraint(CType.dimension,
          pts: List.of(conPts),
          dimKind: _distKind(s, conPts[0], conPts[1], w),
          textPos: w);
    }
    if (d == null) return;
    d.value = measureDim(s.geometry, d);
    pendingDim = d;
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

  /// Called by the viewport once the user confirmed the dimension value.
  void confirmDimension(double? value) {
    final s = current;
    final d = pendingDim;
    pendingDim = null;
    conPts.clear();
    conEnts.clear();
    if (s == null || d == null) {
      notifyListeners();
      return;
    }
    d.value = value ?? measureDim(s.geometry, d);
    s.constraints.add(d);
    _solveAndRebuild(s);
    notifyListeners();
  }

  void cancelDimension() {
    pendingDim = null;
    conPts.clear();
    conEnts.clear();
    notifyListeners();
  }

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
    c.value = v;
    _solveAndRebuild(s);
    notifyListeners();
  }

  void _commitTool(SketchModel s) {
    final geos = buildToolGeometry(tool, List.of(toolPoints),
        existing: s.geometry, params: toolParams, expr: toolExpr);
    if (geos != null) {
      final gs = List<Geo>.from(s.geometry)..addAll(geos);
      if (autoConstrain) {
        for (var i = s.geometry.length; i < gs.length; i++) {
          s.constraints.addAll(inferConstraints(gs, i));
        }
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

  void _committed(SketchModel s) {
    s.refresh();
    s.dirty = true;
  }

  void setHover(Offset? w) {
    hoverWorld = w;
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
      canvas.drawLine(map(g.data[0], g.data[1]), map(g.data[2], g.data[3]), p);
      break;
    case Geo.circle:
      canvas.drawCircle(map(g.data[0], g.data[1]), g.data[2] * scale, p);
      break;
    case Geo.arc:
      final c = map(g.data[0], g.data[1]);
      final r = g.data[2] * scale;
      final a1 = g.data[3], a2 = g.data[4];
      final reversed = g.data[5] != 0;
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
      final path = Path()..moveTo(map(g.data[2], g.data[3]).dx, map(g.data[2], g.data[3]).dy);
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
