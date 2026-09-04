// Prototype — application state (tabs, layers, edit mode, active tool) and
// persistence (DXF per sketch + preview PNG in the app Documents directory).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:native_menu/native_busy.dart' show NativeBusy;
import 'package:native_menu/native_menu.dart'
    show MeshImportChoice, MeshStage, NativeMenu;
import 'package:path_provider/path_provider.dart';
import 'package:reality_view/reality_view.dart' show RealityThumbnailer;

import 'asm_constraints.dart';
import 'asm_joint.dart';
import 'asm_pick.dart';
import 'asm_pattern.dart';
import 'asm_reps.dart';
import 'asm_solver.dart';
import 'asm_work_features.dart';
import 'assembly.dart';
import 'backdrop.dart';
import 'quat.dart';
import 'reality_assembly.dart';
import 'constraints.dart';
import 'diag.dart';
import 'face_project.dart';
import 'clipboard.dart';
import 'cycles_session.dart';
import 'display_mode.dart';
import 'doc_file.dart';
import 'doc_ref.dart';
import 'doc_store.dart';
import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart';
import 'freehand.dart';
import 'gear.dart';
import 'icon_preview.dart';
import 'hud.dart';
import 'l10n/cad_terms.dart';
import 'l10n/fmt.dart';
import 'l10n/l.dart';
import 'l10n/locale_store.dart';
import 'log.dart';
import 'mesh_io.dart';
import 'perf.dart';
import 'modify.dart';
import 'params.dart';
import 'part_model.dart';
import 'section_view.dart';
import 'materials.dart';
import 'measure.dart';
import 'part_render.dart';
import 'preview_matte.dart';
// PURE payload builders only — importing reality_scene.dart here would close a
// cycle (it imports this file). See lib/reality_payload.dart.
import 'reality_payload.dart';
import 'inserts.dart';
import 'snap.dart';
import 'solver.dart';
import 'spline.dart';
import 'text_geometry.dart';
import 'theme.dart';
import 'tools.dart';
import 'vector_font.dart';
import 'render_engine.dart';
import 'render_samples.dart';
import 'ribbon_dock.dart';
import 'sync/lan_sync.dart';
import 'sync/sync_store.dart';
import 'work_features.dart';

/// Drawing tools. M6: the ENTIRE Create panel draws real backend geometry
/// (splines/ellipse/equation curves sampled to polylines — spline support in
/// the core is deferred, see HANDOFF). Text/Geometry Text stay UI-only until
/// the core's text module is enabled.
enum Tool {
  none,
  text, // M44: parametric sketch text (handled in the viewport, not toolClick)
  line,
  lineMid,
  splineCV,
  splineInterp,
  splineFree, // M87 — draw freely with pencil/finger, then fit
  eqCurve,
  bridge,
  circleCenter,
  circleTangent,
  ellipse,
  arcThreePoint,
  arcTangent,
  arcCenter,
  rectTwoPoint,
  rect3P,
  rect2PC,
  rect3PC,
  slotCC,
  slotOverall,
  slotCP,
  slot3A,
  slotCPA,
  polygon,
  fillet,
  chamfer,
  point,
  gear, // M61: parametric involute gear (external / internal), placed by a tap
  project,
  // modify tools (operate on the geometry list, engine gets rebuilt)
  move,
  mcopy,
  mrotate,
  mscale,
  mstretch,
  moffset,
  trim,
  extendT,
  split,
  // constraint tools + dimension
  cCoincident,
  cCollinear,
  cConcentric,
  cFix,
  cParallel,
  cPerpendicular,
  cHorizontal,
  cVertical,
  cTangent,
  cSmooth,
  cSymmetric,
  cEqual,
  dimension,
  // pattern tools (M35, Inventor's Pattern panel) — modeless dialog + picks
  patRect,
  patCirc,
  mirror,
}

/// M85 — which ribbon flyout group a tool belongs to.
///
/// This lived as a private `_toolGroup` inside widgets/ribbon.dart, used only
/// for the active highlight. It moves here because [AppState.selectTool] now
/// also needs it: the split button remembers the last variant per group, and
/// that must be recorded wherever a tool starts (flyout, keyboard shortcut,
/// long-press quick menu), not only where the ribbon happens to be involved.
const Map<Tool, String> toolFlyoutGroup = {
  Tool.line: 'line',
  Tool.lineMid: 'line',
  Tool.splineCV: 'line',
  Tool.splineInterp: 'line',
  Tool.splineFree: 'line',
  Tool.eqCurve: 'line',
  Tool.bridge: 'line',
  Tool.circleCenter: 'circle',
  Tool.circleTangent: 'circle',
  Tool.ellipse: 'circle',
  Tool.arcThreePoint: 'arc',
  Tool.arcTangent: 'arc',
  Tool.arcCenter: 'arc',
  Tool.rectTwoPoint: 'rect',
  Tool.rect3P: 'rect',
  Tool.rect2PC: 'rect',
  Tool.rect3PC: 'rect',
  Tool.slotCC: 'rect',
  Tool.slotOverall: 'rect',
  Tool.slotCP: 'rect',
  Tool.slot3A: 'rect',
  Tool.slotCPA: 'rect',
  Tool.polygon: 'rect',
  Tool.fillet: 'fillet',
  Tool.chamfer: 'fillet',
  Tool.point: 'point',
};

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
  bool selfSym =
      false; // single spline crossing the line -> one symmetric spline
  // advanced (the ">>" row)
  bool expanded = false;
  bool associative = true;
  bool fitted = true;
  PatternSession(this.kind);
}

/// Kind of gear the dialog is currently building.
enum GearKind { external, internal, planetary }

/// Live state of the modeless Gear dialog (M61). Like a [PatternSession] it
/// floats over the viewport while the Gear tool is armed: the parameters drive
/// a LIVE preview (both in the dialog and as a ghost following the cursor), and
/// the gear is placed by a viewport tap or the Insert button. [editing] holds
/// the entity index when re-opening an existing single gear (Insert then
/// REPLACES it in place instead of adding a new one).
/// M87 — live state of the FREEHAND spline: the raw stroke plus the fit
/// parameters the modeless dialog edits.
///
/// The raw stroke is kept for the whole session and never overwritten, so the
/// Points and Smoothing sliders are non-destructive: every change re-fits from
/// the original ink, in both directions. Only [fitFreehandStroke]'s OUTPUT is
/// thrown away and rebuilt.
class FreehandSession {
  /// Ink as it was drawn, world coordinates.
  final List<Offset> raw = [];

  /// True while the pointer is still down — the viewport paints the raw ink;
  /// once false the dialog is open and the fitted spline is previewed.
  bool drawing = true;

  int points = kFreehandDefaultPoints;
  double smoothing = 0.35;

  /// M207 — both of these were dialog toggles that defaulted to on, and the
  /// device asked for them to stop being toggles: "close if ends meet should
  /// be standard and snap ends to points also, and not be a toggle in the
  /// dialog." They are what a freehand stroke means — ends that meet close the
  /// curve, ends that land on a point belong to it — so they are constants,
  /// and the fit window is two rows shorter.
  static const bool snapClosed = true;
  static const bool snapToPoints = true;

  FreehandSession();
}

class GearSession {
  GearKind kind;
  GearParams params; // module / α / x / fillet / bore (+ teeth for single)
  // planetary-only
  int sunTeeth;
  int planetTeeth;
  int planetCount;
  Offset center; // where Insert / the ghost currently sits (world)
  double angleDeg; // orientation (from +X, degrees)
  bool placedOnce; // a tap has set the centre at least once
  int? editing; // entity index being edited (single gears only)
  GearSession({
    this.kind = GearKind.external,
    GearParams? params,
    this.sunTeeth = 20,
    this.planetTeeth = 16,
    this.planetCount = 4,
    this.center = Offset.zero,
    this.angleDeg = 0,
    this.placedOnce = false,
    this.editing,
  }) : params = params ?? GearParams();

  double get angleRad => angleDeg * math.pi / 180.0;
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
      {this.radius = 5,
      this.mode = 0,
      this.d1 = 5,
      this.d2 = 5,
      this.angle = 45});
}

const constraintTools = {
  Tool.cCoincident,
  Tool.cCollinear,
  Tool.cConcentric,
  Tool.cFix,
  Tool.cParallel,
  Tool.cPerpendicular,
  Tool.cHorizontal,
  Tool.cVertical,
  Tool.cTangent,
  Tool.cSmooth,
  Tool.cSymmetric,
  Tool.cEqual,
};

const modifyTools = {
  Tool.move,
  Tool.mcopy,
  Tool.mrotate,
  Tool.mscale,
  Tool.mstretch,
  Tool.moffset,
  Tool.trim,
  Tool.extendT,
  Tool.split,
};

class SketchModel {
  final String name;
  Engine engine; // non-final: rebuilt after grip edits (C-API is add-only)
  List<Geo> geometry = [];
  final List<Constraint> constraints = [];

  /// M43 — user parameters (Inventors fx table): named values usable in any
  /// dimension expression. Sketch state: sidecar + undo journal.
  final List<UserParam> userParams = [];

  /// M44 — parametric texts and inserted images (sidecars + undo journal).
  final List<SketchText> texts = [];
  final List<SketchImage> images = [];
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

  /// M51 — the End-of-Sketch marker (Inventor's End of Part), as the number of
  /// layers ABOVE it: layers[0..eosAfter-1] are live, layers[eosAfter..] are
  /// ROLLED BACK — dimmed in the browser, not drawn, not picked, not snapped
  /// and not editable, exactly like features below Inventor's EOP. Every
  /// mutation of [layers] keeps this in step (insert above the marker,
  /// decrement on delete-above). Internally a SENTINEL: null means "tracking
  /// the end" — a marker nobody has placed follows plain layers.add() (legacy
  /// tests, DXF import) instead of silently rolling new layers back. It
  /// solidifies into a number the moment it is placed anywhere else, and
  /// melts back to tracking when moved to the end. Rides the sidecar and the
  /// undo journal like the eye/lock state.
  int? _eosRaw;
  int get eosAfter => (_eosRaw ?? layers.length).clamp(0, layers.length);
  set eosAfter(int v) =>
      _eosRaw = v >= layers.length ? null : v.clamp(0, layers.length);

  /// Inserts [name] just ABOVE the marker (Inventor: new features land over
  /// the EOP) and keeps the marker's position stable.
  void insertLayerAboveMarker(String name) {
    final at = eosAfter;
    layers.insert(at, name);
    if (_eosRaw != null) _eosRaw = at + 1;
  }

  /// Bookkeeping for a layer removed at index [li]: an explicitly placed
  /// marker keeps sitting after the same layers; a tracking marker needs
  /// nothing (it IS the end).
  void noteLayerRemovedAt(int li) {
    final raw = _eosRaw;
    if (raw != null && li >= 0 && li < raw) _eosRaw = raw - 1;
  }

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
      // A gear was pushed to the backend as its BAKED outline (many vertices)
      // but its in-memory form is the compact [centre, handle] + parameter
      // block. Keep the compact form verbatim — adopting the baked polyline
      // would lose the parameters and turn the gear into a dumb loop.
      if (prev[i].spline == Geo.gearTag && next[i].type == Geo.polyline) {
        next[i] = prev[i];
        continue;
      }
      // M209 — the POINT tag rides on a CIRCLE carrier (the core has no point
      // type), so the polyline-only rule below drops it on the first refresh
      // and the point turns straight back into the ring it stands in for.
      if (prev[i].spline == Geo.pointTag && next[i].type == Geo.circle) {
        next[i] = next[i].asSpline(Geo.pointTag);
      }
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

  /// M221, DIAGNOSTIC ONLY — how many states the journal holds.
  ///
  /// The comment above says the journal is unbounded on purpose. That is a
  /// deliberate design choice and this getter does not challenge it; it makes
  /// the consequence *visible*. The duration of a checkpoint has been measured
  /// since M211 (`app.checkpoint`, ~0.14 ms) but the memory it retains never
  /// has, so "undo until the start" has always been a promise with no number
  /// attached to it.
  int get journalDepth => _undoStack.length + _redoStack.length;

  /// M221, DIAGNOSTIC ONLY — an ESTIMATE of the bytes the journal retains.
  ///
  /// Deliberately an estimate, and named so. Dart exposes no per-object
  /// retained size, so this counts what is actually variable: 8 bytes per
  /// double of geometry, 2 bytes per UTF-16 code unit of the serialised
  /// strings, and a flat 64 bytes of object overhead per snapshot and per
  /// Geo. It will be wrong in absolute terms; it is correct in SHAPE, which
  /// is what a growth question needs — the interesting result is bytes per
  /// checkpoint and whether that stays constant as a session runs.
  int get journalBytes {
    var b = 0;
    for (final s in [..._undoStack, ..._redoStack]) {
      b += 64;
      for (final g in s.geometry) {
        b += 64 + g.data.length * 8;
      }
      b += (s.cons.length + s.uparams.length + s.texts.length +
              s.images.length) * 2;
      for (final l in s.layers) {
        b += l.length * 2;
      }
      for (final h in s.hidden) {
        b += h.length * 2;
      }
      for (final l in s.locked) {
        b += l.length * 2;
      }
    }
    return b;
  }
  int get undoDepth => _undoStack.length;

  UndoSnap _takeSnap() => UndoSnap(
        [for (final g in geometry) g.withData(List<double>.of(g.data))],
        encodeConstraints(constraints),
        encodeUserParams(userParams),
        encodeTexts(texts),
        encodeImages(images),
        List<String>.of(layers),
        {...hiddenLayers},
        {...lockedLayers},
        eosAfter,
      );

  /// M182 — public capture of the current committed state, used by the
  /// PART-level journal (a part snapshot stores every child sketch as one of
  /// these). Same deep-copy semantics as [_takeSnap].
  UndoSnap captureSnap() => _takeSnap();

  /// M182 — restores this sketch from [snap]: geometry, constraints,
  /// parameters, texts, images, layers, eye/lock and End of Sketch. EXACT,
  /// like the 2D undo restore — no replay, no solve. The caller pushes the
  /// geometry into the engine afterwards (AppState owns that), and should
  /// [resetHistory] so the restored state becomes the new undo baseline.
  void applySnap(UndoSnap snap) {
    constraints
      ..clear()
      ..addAll(decodeConstraints(snap.cons));
    userParams
      ..clear()
      ..addAll(decodeUserParams(snap.uparams));
    texts
      ..clear()
      ..addAll(decodeTexts(snap.texts));
    images
      ..clear()
      ..addAll(decodeImages(snap.images));
    layers
      ..clear()
      ..addAll(snap.layers);
    hiddenLayers
      ..clear()
      ..addAll(snap.hidden);
    lockedLayers
      ..clear()
      ..addAll(snap.locked);
    eosAfter = snap.eos.clamp(0, layers.length);
    geometry = [for (final g in snap.geometry) g.withData(List<double>.of(g.data))];
  }

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

  /// M179 — the state the journal is SITTING on, without stepping anywhere.
  /// A live gesture suppresses checkpoints, so during one this is the sketch
  /// as it was before the gesture began.
  UndoSnap? get pinnedSnap => _undoStack.isEmpty ? null : _undoStack.last;

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
  final String uparams; // M43: user parameters, serialized like constraints
  final String texts; // M44: parametric texts
  final String images; // M44: inserted images
  final List<String> layers;
  final Set<String> hidden;
  final Set<String> locked;
  final int eos; // M51: End-of-Sketch marker position
  UndoSnap(this.geometry, this.cons, this.uparams, this.texts, this.images,
      this.layers, this.hidden, this.locked, this.eos);

  bool sameAs(UndoSnap o) {
    if (eos != o.eos ||
        cons != o.cons ||
        uparams != o.uparams ||
        texts != o.texts ||
        images != o.images ||
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

/// M182 — one entry of the PART-level undo journal: everything that makes a
/// part document, captured BEFORE a destructive operation (delete feature /
/// delete body / delete below EOP / delete sketch) so the operation can be
/// undone exactly. The part's own JSON (features, work planes, counters, End
/// of Part, camera, origin visibility) plus one [UndoSnap] per child sketch —
/// the SAME deep-copy codec the 2D journal uses, so restore is exact and
/// needs no replay.
class PartSnap {
  final Map<String, dynamic> partJson;
  final List<String> sketchNames;
  final List<UndoSnap> sketchSnaps;

  PartSnap(this.partJson, this.sketchNames, this.sketchSnaps);
}

class SavedSketchInfo {
  final String name;
  final DateTime modified;
  final File? preview;

  /// 'sketch' | 'part' — the gallery shows a steel cube for parts.
  final String kind;
  const SavedSketchInfo(this.name, this.modified, this.preview,
      [this.kind = 'sketch']);
}

/// Live state of the modeless Extrusion properties panel (M56) — one
/// session per open dialog, exactly like [PatternSession]. Esc / Cancel
/// discards it, OK / + commits through [AppState.applyExtrude].
/// Live state of the Fillet / Chamfer panel.
///
/// ONE session type for both: Inventor presents them as separate commands,
/// but they differ only in which numbers sit under the edge list, and two
/// near-identical sessions would be two places to keep the edge handling in
/// step. [kind] selects the fields.
class EdgeFeatureSession {
  EdgeFeatureSession(this.kind, {this.editing});

  final String kind; // 'fillet' | 'chamfer'
  final BodyModifyFeature? editing; // null = creating

  // fillet — Inventor's "edge sets": one radius each, several per feature.
  // "All fillets and rounds created in a single operation become a single
  // feature", and within that feature each set carries its own radius.
  List<String> exprRadii = ['2 mm'];

  /// M144 — optional END radius per set, for a VARIABLE-radius fillet. Blank
  /// (the default) means that set is constant, so a plain fillet is unaffected
  /// and nothing extra is written to the file.
  List<String> exprRadii2 = [''];

  /// Inventor's Select Mode toggles, persisted onto the feature.
  bool allFillets = false, allRounds = false;

  /// Backwards-compatible view of the FIRST set's radius, still what a
  /// single-set fillet means and what gets persisted as exprRadius.
  String get exprRadius => exprRadii.isEmpty ? '2 mm' : exprRadii.first;

  // chamfer
  int mode = 0; // 0 equal distance, 1 two distances, 2 distance and angle
  String exprD1 = '1 mm';
  String exprD2 = '1 mm';
  String exprAngle = '45.00 deg';
  bool flip = false;
  bool edgeChain = true;

  KernelSolid? preview;
  String? previewError;

  /// Body the preview REPLACES on screen. A fillet does not add material, it
  /// modifies a body, so the original must be hidden while the preview is up
  /// or the un-filleted edges show through it.
  String? previewReplacesBody;

  bool get isFillet => kind == 'fillet';

  void disposePreview() {
    preview?.dispose();
    preview = null;
    previewReplacesBody = null;
  }
}

/// M248 — the live state of the ASSEMBLY's Pattern / Mirror commands.
///
/// EXTENDS [PartPatternSession] rather than paralleling it, for the reason
/// [AsmPattern] extends [PatternFeature]: the panel, the rail, the counts, the
/// distributions, the irregular rows, the suppression set and every one of
/// AppState's `pattern*` mutators are the part's and are wanted unchanged. It
/// rides in the same [AppState.patternSession] field, so there is ONE open
/// command at a time and one place that closes it.
///
/// What it adds is the two things an assembly needs and a part cannot use: the
/// placement inputs as [AsmRef]s (they MOVE — see asm_pattern.dart, section B)
/// and the associative driver.
///
/// [features] is inherited and holds OCCURRENCE IDS. Same list, same
/// multi-pick, same chips in the panel — "the names of what is being copied"
/// reads the same in both documents.
class AsmPatternSession extends PartPatternSession {
  AsmPatternSession(super.mode, {AsmPattern? editing}) : super(editing: editing);

  @override
  AsmPattern? get editing => super.editing as AsmPattern?;

  AsmRef? refDirA, refDirB, refAxis, refPlane;

  /// (occurrence id, the name of a [PatternFeature] in that component's part).
  (String, String)? driver;

  /// The name the pattern will carry. Fixed when the session opens, because
  /// the LIVE PREVIEW places its elements through the ordinary regeneration
  /// and they have to keep finding the same pattern between keystrokes.
  String name = '';

  /// The pattern's parameters as they were before an EDIT started, so Cancel
  /// can put them back. Null when creating.
  AsmPattern? restore;

  /// The assembly's relationships as they were when the command opened.
  ///
  /// The preview places the pattern FOR REAL, so shrinking the count really
  /// does destroy the elements above it — and, with them, every constraint
  /// that named one. That is the cost asm_pattern.dart section D names, and
  /// this is what keeps it undoable: Cancel puts the pattern back, the
  /// regeneration puts the elements back under their own ids, and this puts
  /// the relationships back on them.
  final List<AsmConstraint> constraintsBefore = [];

  void readFromAsm(AsmPattern f) {
    readFrom(f);
    refDirA = f.refDirA;
    refDirB = f.refDirB;
    refAxis = f.refAxis;
    refPlane = f.refPlane;
    driver = f.driver;
    name = f.name;
  }
}

/// M250 — which of Inventor's two POSITION commands is armed.
///
/// Both make the viewport move the component ITSELF rather than asking the
/// solver where it may go — see the Free Move / Free Rotate section of
/// [AppState] for what that means and why it is Inventor's behaviour rather
/// than a shortcut. [move] translates, [rotate] turns; neither has a
/// "nothing armed" member, because that is what a null [AppState.asmPositionMode]
/// already says.
enum AsmPositionMode { move, rotate }

/// M250 — the live state of Inventor's Create In-Place Component dialog.
///
/// Two fields, because two of Inventor's six rows survive the honest-scope cut
/// (see the Create Component section of [AppState] for the other four and why
/// each is absent), plus the flag that says the dialog is done and the command
/// is out in the viewport looking for a plane.
class CreateComponentSession {
  CreateComponentSession(this.name);

  /// Inventor's "New Component Name". Pre-filled with the same suggestion the
  /// gallery's New Part offers, so OK on an untouched dialog always works.
  String name;

  /// Inventor's "Constrain sketch plane to the selected face or plane", and
  /// its default: OFF. Ticked, it applies a FLUSH between the new component
  /// and what was picked, so the new part follows the thing it was built on.
  bool constrainSketchPlane = false;

  /// True once OK has been taken and the plane is being collected.
  bool picking = false;
}

/// M255 — the live state of Inventor's MAKE PART dialog.
///
/// WHAT INVENTOR'S HOLDS (Make Part, from a solid body's context menu in a
/// multi-body part). Researched the same way M250's was and with the same
/// caveat: help.autodesk.com is blocked from this network, so the field list
/// comes from search summaries and the LAYOUT is inferred, not transcribed.
///
///     Solid Body               which bodies go into the new part
///     New Part Name            the file name of the part being made
///     Template                 which .ipt template to build it from
///     New File Location        which folder to write it to
///     Insert in target assembly / Target Assembly Name
///                              the assembly the new part is placed into
///     BOM Structure            Normal / Phantom / Reference / Purchased
///
/// WHAT THIS ONE HOLDS. The body is not a row here because the command was
/// STARTED on one — it is the row you long-pressed, and re-choosing it inside
/// the dialog would be asking a question that has already been answered.
/// Template, New File Location and BOM Structure are absent for exactly the
/// reasons the Create Component section sets out at length: one part kind, one
/// gallery, no BOM, and a disabled row for a concept the app does not have is
/// worse than no row.
///
/// That leaves the two that are real, and both are names the user types:
/// [partName] and [assemblyName].
class MakePartSession {
  MakePartSession(this.body, this.partName, this.assemblyName);

  /// The solid body in the CURRENT part this was started on. Not editable —
  /// see above.
  final String body;

  /// Inventor's "New Part Name". Must be free across the whole gallery.
  String partName;

  /// Inventor's target assembly. May name an assembly that already EXISTS, and
  /// that is the point: decomposing a multi-body part means running this once
  /// per body into the SAME assembly, which is how Inventor's Make Components
  /// does all of them at once.
  String assemblyName;
}

/// M250 — which component of which assembly the open part tab is standing in
/// for.
///
/// Three names rather than three objects, deliberately: a document can be
/// closed, renamed or deleted from a dozen places, and a held [PartModel] or
/// [AssemblyOccurrence] would outlive its document and go on being drawn.
/// [AppState.inPlaceEdit] resolves all three on every read and answers null
/// the moment any of them stops existing.
class InPlaceEdit {
  const InPlaceEdit(this.assembly, this.occurrence, this.part);

  /// The parent assembly document's name.
  final String assembly;

  /// The occurrence id inside it — "Bracket:1".
  final String occurrence;

  /// The part document open in the tab.
  final String part;
}

/// Which selector of the pattern panel the next pick feeds — Inventor's
/// blue-outlined field. [none] means the panel is not waiting for anything
/// and a tap in the viewport is an ordinary tap again.
enum PatternField {
  none,
  features,
  solid,
  dirA,
  dirB,
  axis,
  plane,
  pointSketch,
  basePoint,
  // M213 — Inventor's Extents (where a row STARTS on its path) and its
  // Variable Orientation (the face a sketch-driven pattern follows).
  startA,
  startB,
  orientFace,
}

/// Live state of the open pattern panel (M212): Rectangular, Circular,
/// Sketch Driven and Mirror.
///
/// ONE session for all four, for the same reason [ExtrudeSession] serves five
/// commands: they share the feature selection, the solid/feature switch, the
/// creation method, the preview and the commit, and differ only in which
/// selectors and numbers sit in the middle. [mode] is what selects those.
///
/// The panel is MODELESS — it floats over the viewport while you keep picking
/// geometry — so the values live here as the strings the user typed, and are
/// parsed on the way into the feature.
class PartPatternSession {
  PartPatternSession(this.mode, {this.editing});

  final PatternKind mode;

  /// The feature being edited, or null when creating.
  final PatternFeature? editing;

  /// The selector a viewport (or browser) pick feeds.
  PatternField active = PatternField.features;

  /// Inventor's Input Geometry: a set of FEATURES, or the whole solid.
  bool patternSolid = false;

  /// Picked feature names, in pick order.
  final List<String> features = [];

  /// The body the pattern acts on — the one the picked features build.
  String bodyName = '';

  // ---- rectangular ----
  AxisRef? dirA, dirB;
  bool flipA = false, flipB = false, midplaneA = false, midplaneB = false;
  String exprCountA = '2', exprCountB = '2';
  String exprDistanceA = '25 mm', exprDistanceB = '25 mm';
  PatternDistribution distributionA = PatternDistribution.spacing;
  PatternDistribution distributionB = PatternDistribution.spacing;

  /// M213 — a row can run along a CURVE instead of a straight direction. A
  /// path REPLACES the direction of its own row, which is why picking one
  /// clears the other: showing both would leave the panel saying two
  /// different things about where the occurrences go.
  CurveSel? pathA, pathB;
  double startA = 0, startB = 0;
  bool startPickedA = false, startPickedB = false;

  /// Inventor 2026's Irregular Distance / Angle: step index -> its own offset.
  final Map<int, double> irregularA = {}, irregularB = {}, irregularC = {};

  // ---- circular ----
  AxisRef? axis;
  bool flipC = false;
  String exprCountC = '6', exprAngleC = '360.00 deg';

  /// Inventor's circular Distribution defaults to the TOTAL angle (Fitted),
  /// which is what makes the out-of-the-box "6 at 360 deg" a bolt circle.
  PatternDistribution distributionC = PatternDistribution.distance;
  PatternOrient orientation = PatternOrient.rotational;

  // ---- sketch driven ----
  String pointSketch = '';
  bool basePicked = false;
  double baseX = 0, baseY = 0;

  /// Inventor's Variable Orientation — the face the occurrences follow.
  FaceSel? orientFace;

  // ---- mirror ----
  PlaneRef? plane;
  bool removeOriginal = false;

  // ---- shared ----
  PatternCompute compute = PatternCompute.identical;
  final Set<int> suppressed = {};

  KernelSolid? preview;
  String? previewError;

  /// The body the preview REPLACES on screen. A pattern reshapes a body
  /// rather than adding one, so the original must be hidden while the panel
  /// is up or the un-patterned body would show through the preview — the same
  /// rule the fillet panel follows.
  String? previewReplacesBody;

  /// Seeds the session from an existing feature, for "edit this pattern".
  void readFrom(PatternFeature f) {
    patternSolid = f.patternSolid;
    features
      ..clear()
      ..addAll(f.sources);
    bodyName = f.bodyName;
    dirA = f.dirA?.copy();
    dirB = f.dirB?.copy();
    flipA = f.flipA;
    flipB = f.flipB;
    midplaneA = f.midplaneA;
    midplaneB = f.midplaneB;
    exprCountA = f.exprCountA;
    exprCountB = f.exprCountB;
    exprDistanceA = f.exprDistanceA;
    exprDistanceB = f.exprDistanceB;
    distributionA = f.distributionA;
    distributionB = f.distributionB;
    axis = f.axis?.copy();
    flipC = f.flipC;
    exprCountC = f.exprCountC;
    exprAngleC = f.exprAngleC;
    distributionC = f.distributionC;
    orientation = f.orientation;
    pointSketch = f.pointSketch;
    basePicked = f.basePicked;
    baseX = f.baseX;
    baseY = f.baseY;
    orientFace = f.orientFace;
    pathA = f.pathA;
    pathB = f.pathB;
    startA = f.startA;
    startB = f.startB;
    startPickedA = f.startA != 0;
    startPickedB = f.startB != 0;
    irregularA
      ..clear()
      ..addAll(f.irregularA);
    irregularB
      ..clear()
      ..addAll(f.irregularB);
    irregularC
      ..clear()
      ..addAll(f.irregularC);
    plane = f.mirrorPlane?.copy();
    removeOriginal = f.removeOriginal;
    compute = f.compute;
    suppressed
      ..clear()
      ..addAll(f.suppressed);
    active = PatternField.none;
  }

  /// Label for the Direction/Axis/Plane pick fields.
  String get dirALabel => dirA?.label ?? L.current.lblSelectDirPlaceholder;
  String get dirBLabel => dirB?.label ?? L.current.lblSelectDirPlaceholder;
  String get axisLabel => axis?.label ?? L.current.lblSelectDirPlaceholder;
  String get planeLabel =>
      plane?.label ?? L.current.lblMirrorPlanePlaceholder;

  void disposePreview() {
    preview?.dispose();
    preview = null;
    previewReplacesBody = null;
  }
}

/// Live state of the Extrude AND Revolve panels.
///
/// One session for both: of its fields only exprTaper/iMate/matchShape are
/// extrude-only and only the axis + Full are revolve-only — profiles, the
/// sketch lock, direction, output, body, extents, preview and the auto-pick
/// are identical. A parallel RevolveSession would have duplicated all of
/// that, which is the pattern this codebase has already been bitten by.
///
/// The name is kept because it appears across main, ribbon, viewport3d and
/// the tests; [kind] is what actually selects the behaviour.
/// M225 — the live state of the Hole panel.
///
/// Deliberately NOT a variant of [ExtrudeSession], which serves five commands
/// that all pick PROFILES and differ only in the numbers underneath. A hole
/// picks POINTS and derives its profile from a diameter; folding it in would
/// mean every one of those five carrying a placement list it can never use.
class HoleSession {
  HoleFeature? editing;
  String? sketchName;
  final List<HolePlace> places = [];
  String exprDia = '6 mm';
  String exprDepth = '10 mm';
  FeatureExtent extent = FeatureExtent.distance;
  bool flip = false;
  // M226 — the shape at the mouth.
  HoleType type = HoleType.simple;
  String exprCbDia = '11 mm';
  String exprCbDepth = '6 mm';
  String exprCsDia = '12 mm';
  String exprCsAngle = '90 deg';
}

/// M242 — the live state of Place Constraint.
///
/// Inventor's dialog is modeless and collects its inputs by POINTING: the
/// numbered selection buttons arm the viewport, a tap fills the armed slot
/// and the arming advances. Everything the dialog shows is here, and nothing
/// here is a widget — the panel reads it, the viewport writes to it through
/// [AppState.pickConstraintRef], and the browser's Edit command opens one
/// pre-filled.
class ConstraintSession {
  ConstraintSession({this.editing});

  /// The constraint being edited, or null when a new one is being placed.
  /// Editing keeps the same name and the same row in the browser, which is
  /// what makes Edit different from delete-and-place-again.
  final AsmConstraint? editing;

  AsmTab tab = AsmTab.assembly;
  AsmKind kind = AsmKind.mate;
  AsmSolution solution = AsmSolution.mate;

  /// M249 — the Place Joint dialog's Type list, when this session is a JOINT.
  ///
  /// One session class for two commands, because they collect identically: the
  /// numbered selection buttons, the arming, the preview, the placement
  /// snapshot, Apply-keeps-the-settings and the viewport's pick routing are
  /// the same machinery for both, and a second copy of it would be a second
  /// place for "a tap fills the armed slot" to drift. [tab] is what says which
  /// dialog is on screen — see [AsmTab.joint].
  ///
  /// [AsmJointType.automatic] stays selected while it is chosen: [kind] then
  /// holds whatever the current pair resolves to, so the dialog can show the
  /// user what Automatic decided BEFORE they commit — which is the one thing
  /// Inventor's own Automatic does not, and is free here.
  AsmJointType jointType = AsmJointType.automatic;

  bool get isJoint => tab == AsmTab.joint;

  /// The selections, in the dialog's own numbering: 1, 2 and (for Symmetry
  /// and an explicit reference vector) 3.
  AsmRef? a, b, c;

  /// Offset in mm, angle in degrees, ratio, or mm per turn — [valueKindOf]
  /// says which.
  double value = 0;

  /// Empty means "name it the way Inventor would" — see [nextConstraintName].
  String name = '';

  /// Which selection button is lit: 0, 1 or 2. Advances on every pick, and
  /// stops advancing once every slot is full so a stray tap in the viewport
  /// cannot silently rewrite selection 1.
  int armed = 0;

  /// Inventor's three dialog checkboxes.
  bool showPreview = true;
  bool predict = false;
  bool pickPartFirst = false;

  /// The `>>` expander, which reveals Name and Default to Undirected.
  bool expanded = false;

  /// Inventor's "Default to Undirected": the next Angle constraint opens on
  /// the undirected solution instead of the directed one. Kept on the session
  /// AND mirrored onto [AppState.defaultUndirectedAngle], because it is a
  /// preference that outlives the dialog.
  bool defaultUndirected = false;

  /// Why the current pair cannot be constrained this way, as an l10n key from
  /// [rejectionFor]. Null when they can.
  String? rejection;

  /// How many selections this kind and solution take.
  int get needed => selectionCountFor(kind, solution);

  bool get complete => a != null && b != null && (needed < 3 || c != null);

  AsmRef? slot(int i) => switch (i) { 0 => a, 1 => b, _ => c };

  void setSlot(int i, AsmRef? r) {
    switch (i) {
      case 0:
        a = r;
      case 1:
        b = r;
      default:
        c = r;
    }
  }

  /// The first empty slot, or -1 when they are all full. This is what makes
  /// the arming advance the way Inventor's does.
  int get firstEmpty {
    for (var i = 0; i < needed; i++) {
      if (slot(i) == null) return i;
    }
    return -1;
  }
}

/// M249 — the live state of Inventor's DRIVE dialog.
///
/// "The Drive dialog box opens when you right-click a relationship in the
/// browser and select Drive", and it animates that relationship's value from a
/// Start to an End. Which is the UI M242 owed the motion constraints: the
/// solver's drive pass (asm_solver.driveMotion) has been there and tested
/// since — "motion is DRIVEN, not solved" — with nothing on screen to run it.
///
/// TWO KINDS OF SWEEP, chosen by what is being driven, because a motion
/// constraint has no value worth animating:
///
///   POSITIONAL  a Mate's offset, an Angle's angle, a joint's gap. The value
///               is set and the assembly re-solved, which is Inventor's own
///               behaviour exactly.
///   MOTION      a Rotation or Rotation-Translation constraint carries a RATIO
///               or a distance per turn, and sweeping either of those animates
///               nothing — it changes the gearing while the gears stand still.
///               So what is swept is the DRIVER's own rotation, in degrees,
///               through [AppState.turnOccurrence]: turning the first shaft is
///               what makes the drive pass move the second one, and that is
///               what a gear pair is for.
class DriveSession {
  DriveSession(this.constraint, {required this.motion, required this.value0});

  final AsmConstraint constraint;

  /// True when this sweeps the driver's rotation rather than the constraint's
  /// value — see the class comment.
  final bool motion;

  /// The value the constraint had when the dialog opened, restored on close.
  /// A drive is a preview of motion, not an edit.
  final double value0;

  double start = 0;
  double end = 0;

  /// Inventor's Increment group: a step SIZE, or a total number of steps.
  bool byTotalSteps = false;
  double increment = 1;
  int totalSteps = 10;

  /// "In Pause Delay, set the time in seconds between steps."
  double pauseDelay = 0.05;

  /// Inventor's Repetition group: Start/End "runs once and returns to the
  /// beginning"; Start/End/Start "runs once forward, then once backward".
  bool roundTrip = false;
  int cycles = 1;

  // ---- runtime ------------------------------------------------------------

  /// Where the sweep is, as a fraction of Start -> End. A fraction rather than
  /// a value because it makes a backwards sweep (End below Start) the same
  /// arithmetic as a forwards one, and the turn-round at each extreme a
  /// comparison against 0 and 1 rather than against whichever end is larger.
  double phase = 0;

  bool playing = false;

  /// True while the sweep is running back towards Start — only ever set by the
  /// Start/End/Start repetition.
  bool reverse = false;

  /// How many complete repetitions have finished.
  int cycle = 0;

  double get current => start + phase * (end - start);

  /// The step, as a fraction of the whole sweep. Never zero: a zero step is a
  /// timer that fires for ever and animates nothing.
  double get phaseStep {
    final span = (end - start).abs();
    if (byTotalSteps) return 1.0 / math.max(1, totalSteps);
    if (span < 1e-9) return 1;
    return math.max(1e-4, increment.abs() / span);
  }
}

/// M228 — the live state of the Split panel.
class SplitSession {
  SplitFeature? editing;
  PlaneFrame? frame;
  String label = '';
  bool flip = false;
  String? bodyName;
}

/// M227 — the live state of the Combine panel.
class CombineSession {
  CombineFeature? editing;

  /// The body being kept. Inventor asks for it first, and so does this.
  String? baseBody;
  final List<String> tools = [];
  String op = 'cut';
  bool keepTool = false;
}

/// M256 — the Output boolean a feature's geometry asks for.
///
/// [current] is the boolean in force; [inside] is the fraction of the
/// feature's own solid that lies INSIDE the body it is aimed at, 0..1.
/// Returns the boolean to switch to, or null to leave it where it is.
///
/// Requested from the device: "es soll immer zuerst hinzufügen ausgewählt
/// sein. aber wenn ich in die extrusion umkehre soll automatisch auf wegnehmen
/// geschaltet werden wenn ein Grossteil der extrusion im gleichen teil wäre.
/// ich will es immer noch umschalten können aber es soll intelligent
/// funktionieren." Join is still where every feature starts; this is what
/// notices that the extrusion has been turned around into the body it sits on.
///
/// TWO THRESHOLDS, NOT ONE. A single 0.5 would flip back and forth while a
/// distance is dragged through it, and a control that changes under the finger
/// twice a second is worse than one that never changes at all. Leaving Join
/// takes 0.6 and coming back takes 0.4: a dead band that a real gesture —
/// reversing the direction, or pushing a distance in past the far wall —
/// crosses once and decisively.
///
/// ONLY JOIN AND CUT TAKE PART. Nothing about where the material sits implies
/// "keep only the overlap" or "start a second body", so Intersect and New
/// Solid are never suggested and never overruled.
///
/// THE CASE IT DELIBERATELY DOES NOT CATCH: a cut typed with a big overshoot.
/// A hole driven 20 mm into a 5 mm plate is only a quarter buried, and by the
/// measure asked for — "wenn ein Grossteil der extrusion im gleichen teil
/// wäre" — a quarter is not a Grossteil. Volume alone cannot tell that tool
/// from a boss standing off a recessed face, because both read as "mostly
/// outside"; separating them needs a ray from the sketch plane, which is a
/// kernel call this deliberately does not make. Through All and a matched
/// distance — what that hole is usually drawn with — both come out near 1 and
/// switch. The overshoot stays one tap, which is the tap the user asked to
/// keep.
String? suggestedOutput(String current, double inside) {
  if (!inside.isFinite) return null;
  if (current == 'join' && inside >= 0.6) return 'cut';
  if (current == 'cut' && inside <= 0.4) return 'join';
  return null;
}

class ExtrudeSession {
  /// 'extrude' | 'revolve' | 'sweep' | 'loft' | 'coil'.
  ///
  /// One session for all five: they share profiles, the sketch lock,
  /// direction, output, body, preview and the auto-pick. Only the numbers
  /// under the geometry differ, which is what [kind] selects.
  String kind = 'extrude';
  bool get isRevolve => kind == 'revolve';
  bool get isSweep => kind == 'sweep';
  bool get isLoft => kind == 'loft';
  bool get isCoil => kind == 'coil';

  /// True when the panel drives one profile through a path or helix rather
  /// than a straight or rotational extent.
  bool get isSwept => isSweep || isCoil;

  // ---- sweep only ----
  CurveSel? path;
  int orientation = 0;
  String exprTaperSweep = '0 deg', exprTwist = '0 deg';

  // ---- loft only ----
  /// Sections in pick order, each with the sketch it came from.
  final List<String> loftSketches = [];
  final List<ProfileSel> loftSections = [];
  bool loftRuled = false, loftClosed = false, loftMergeTangent = false;
  bool loftSolid = true;

  // ---- coil only ----
  int coilMethod = 0;
  String exprRevolutions = '5 ul',
      exprHeight = '8 mm',
      exprPitch = '2 mm',
      exprCoilTaper = '0.00 deg';
  bool coilClockwise = false, coilCloseStart = false, coilCloseEnd = false;

  // ---- revolve only ----
  /// Axis in SKETCH coordinates: a point plus a direction. Stored as geometry
  /// rather than as a reference to the sketch entity that produced it, for
  /// the same reason RevolveFeature does — the line can be deleted or
  /// redrawn, the axis it defined is what the feature depends on.
  double axPx = 0, axPy = 0, axDx = 0, axDy = 1;
  bool axisPicked = false;
  String axisLabel = '';
  bool full = true;

  /// The feature being edited, or null when creating. Widened to
  /// [PartFeature] in M137 so the same session can carry a revolve.
  PartFeature? editing;
  String? sketchName; // locked to ONE sketch by the first profile pick
  final List<ProfileSel> profiles = [];
  ExtrudeDirection direction = ExtrudeDirection.defaultDir;
  String exprA = '5 mm', exprB = '5 mm', exprTaper = '0.00 deg';
  String bodyName = '';
  bool iMate = false, matchShape = true;
  // Inventor Output boolean: 'join' | 'cut' | 'intersect' | 'new'.
  String output = 'join';

  /// M256 — set the moment the user touches the Output control.
  ///
  /// See [outputIsTheirs]: the suggestion is a starting point, never an
  /// argument with the user.
  bool outputLocked = false;

  /// True while [output] is nobody's business but the user's — they have
  /// chosen it by hand, or the feature being EDITED already carries one that
  /// they chose when they made it.
  ///
  /// One getter rather than a flag set in five openers: revolve, sweep, loft
  /// and coil each have their own edit branch, and a rule that has to be
  /// remembered in each of them is a rule the sixth one will miss.
  bool get outputIsTheirs => outputLocked || editing != null;

  /// M257 — set the moment the user picks a target body by hand.
  bool bodyLocked = false;

  /// True while [bodyName] is nobody's business but the user's. Same rule and
  /// the same reason as [outputIsTheirs]: an existing feature's target is a
  /// decision already made, and a pick is an argument this code does not have.
  bool get bodyIsTheirs => bodyLocked || editing != null;

  /// M132 — Inventor's Extents. Distance uses [exprA]; the other three
  /// resolve against the body at recompute time.
  FeatureExtent extent = FeatureExtent.distance;
  FaceSel? extentFace; // set iff extent == toFace
  KernelSolid? preview;
  String? previewError;

  /// When the live [preview] is the RESULT of a boolean (join/cut/intersect)
  /// against an existing body, this is that body's name — the viewport hides
  /// the old body so the boolean result stands in for it, instead of drawing
  /// both. Null when the preview is a standalone new prism.
  String? previewReplacesBody;

  /// True while the only selection is [AppState.openExtrude]'s convenience
  /// pre-pick, so an explicit pick in ANOTHER sketch may replace it.
  bool autoPicked = false;

  bool hasProfileAt(Offset p) =>
      profiles.any((s) => (Offset(s.ax, s.ay) - p).distance < 1e-6);

  void disposePreview() {
    preview?.dispose();
    preview = null;
    previewReplacesBody = null;
  }
}

class AppState extends ChangeNotifier {
  /// Scratch used only while parsing a part sidecar: sketch name -> stored
  /// visibility (null = key absent in a legacy file).
  final Map<String, bool?> _loadedSketchVis = {};

  // ---- navigation (home / tabs), 1:1 with the mock behaviour ----
  bool get isHome => curTab == null;
  final List<String> openTabs = [];
  String? curTab;

  // ---- M260: is the user moving the VIEW right now? ------------------------
  //
  // iOS 26 expects chrome to yield to content: the system tab bar minimises
  // while a view scrolls and comes back when it stops. A CAD viewport never
  // scrolls, so the equivalent gesture is the one that actually covers the
  // model — a finger orbiting, panning or zooming it. This latch is that
  // signal, and the bottom bar folds down to the open document while it holds.
  //
  // It is an EDGE, not a poll. An orbit sends sixty of these a second and
  // exactly two of them notify: the first, and the one the timer fires at the
  // end. Anything cheaper than that would have to live below the notifier, and
  // anything more eager would rebuild the app once per frame of every drag.

  /// How long the latch holds after the last camera move.
  ///
  /// Long enough that the gap between two orbit events of one drag never
  /// reaches it — those arrive per frame, ~16 ms apart — and short enough that
  /// the bar is back before a hand leaves the glass. Settable so the debounce
  /// can be pinned in a test without waiting on a real clock.
  static Duration engageLinger = const Duration(milliseconds: 450);

  bool _engaged = false;
  Timer? _engageTimer;

  /// True while the camera is under a finger.
  bool get viewEngaged => _engaged;

  /// Called by the viewports on every camera move. Idempotent, and cheap
  /// enough to sit on the orbit path: one timer reset, one bool test.
  void engageView() {
    _engageTimer?.cancel();
    _engageTimer = Timer(engageLinger, endViewEngagement);
    if (_engaged) return;
    _engaged = true;
    notifyListeners();
  }

  /// Drops the latch now. The timer's own target, and called directly by the
  /// tests so the STATE and the DEBOUNCE can be pinned apart.
  void endViewEngagement() {
    _engageTimer?.cancel();
    _engageTimer = null;
    if (!_engaged) return;
    _engaged = false;
    notifyListeners();
  }

  int _newN = 0;
  int layerCounterOf(SketchModel s) => s.layers.length;

  final Map<String, SketchModel> sketches = {};

  // ---- M56: 3D part documents ----
  final Map<String, PartModel> parts = {};

  /// The child sketch currently open INSIDE a part — while set, [current]
  /// returns it, so the entire 2D sketcher (ribbon edit branch, browser,
  /// viewport, tools, solver) drives the child sketch unchanged.
  SketchModel? activeChild;

  /// "Start 2D Sketch" armed: the 3D viewport waits for a plane tap.
  bool pickPlane = false;

  ExtrudeSession? extrudeSession;

  /// The 3D kernel seam. The app wires the real OCCT kernel; host tests
  /// inject a fake — the app itself never fakes a B-Rep (M55 rule).
  PartKernel partKernel = OcctPartKernel();
  final Map<String, List<ProfileRegion>> _regionCache = {};

  // ---- layer edit mode ----
  String? editingLayer; // layer name currently in edit mode (of current tab)
  bool get inEditMode => editingLayer != null;

  // ---- active drawing tool + in-progress points (world coords) ----
  Tool tool = Tool.none;

  /// M85 — Inventor's SPLIT BUTTON memory: the variant last chosen from a
  /// flyout, per flyout group ('line', 'circle', 'arc', 'rect', 'fillet').
  ///
  /// The ribbon face (icon + label) and the button BODY both follow this, so
  /// picking Slot from the Rectangle flyout leaves a Slot button behind
  /// instead of snapping back to Rectangle — and the next tap starts Slot,
  /// not Rectangle. Written centrally in [selectTool], so a keyboard shortcut
  /// updates the face exactly like a flyout pick.
  ///
  /// Session state on purpose: it is not part of the document, so it is not
  /// serialised and never makes a sketch dirty.
  final Map<String, Tool> ribbonPick = {};
  final List<Offset> toolPoints = [];
  Offset? hoverWorld;

  // ---- HUD / Dynamic Input (Inventor's heads-up value boxes) ----
  // Per-PHASE input state (reset whenever a point is placed): which locked
  // values apply to the current phase's fields, the box the user is typing
  // into, and the raw text buffer. See hud.dart for the field schema.
  final Map<int, double> hudLocked = {}; // field index -> locked value
  int hudFocus = 0; // index of the box accepting keystrokes
  String hudInput = ''; // digits typed into the focused box (before Tab/commit)
  // Locked values accumulated ACROSS phases, keyed by quantity, consumed at
  // commit to emit the persistent driving dimensions.
  final Map<HudKind, double> hudCommitDims = {};

  /// Whether the HUD is live: a create tool with input fields for the current
  /// phase, inside a sketch. (Dialog-driven tools have their own panels.)
  bool get hudActive =>
      inEditMode &&
      tool != Tool.none &&
      hudFieldsFor(tool, toolPoints.length).isNotEmpty;

  /// The locks in force for the live preview: committed locks plus the value
  /// currently being typed (so the shape follows the digits as they are keyed,
  /// before Tab — exactly like Inventor).
  Map<int, double> get _hudEffectiveLocks {
    final m = Map<int, double>.from(hudLocked);
    final typed = Fmt.num(hudInput);
    if (typed != null) m[hudFocus] = typed;
    return m;
  }

  /// Apply the current locks to a raw cursor/click point.
  Offset hudApply(Offset raw) =>
      hudActive ? hudConstrain(tool, toolPoints, raw, _hudEffectiveLocks) : raw;

  /// Box contents for the painter: (label, text, locked, focused, angular).
  List<(String, String, bool, bool, bool)> hudDisplays(Offset raw) {
    final fields = hudFieldsFor(tool, toolPoints.length);
    final eff = hudApply(raw);
    final out = <(String, String, bool, bool, bool)>[];
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final locked = hudLocked.containsKey(i);
      final focused = i == hudFocus;
      String text;
      if (locked) {
        text = _hudFmt(hudLocked[i]!, f.angular);
      } else if (focused && hudInput.isNotEmpty) {
        text = hudInput; // show the raw buffer with no reformatting
      } else {
        text = _hudFmt(hudMeasure(tool, toolPoints, eff, i), f.angular);
      }
      out.add((f.label, text, locked, focused, f.angular));
    }
    return out;
  }

  static String _hudFmt(double v, bool angular) {
    final s = v.abs() < 1e-9 ? 0.0 : v; // kill -0
    final r = (s * 100).roundToDouble() / 100;
    var t = r.toStringAsFixed(2);
    if (t.endsWith('.00'))
      t = t.substring(0, t.length - 3);
    else if (t.endsWith('0')) t = t.substring(0, t.length - 1);
    return angular ? '$t\u00B0' : t;
  }

  void _hudResetPhase() {
    hudLocked.clear();
    hudInput = '';
    hudFocus = 0;
  }

  void _hudResetAll() {
    _hudResetPhase();
    hudCommitDims.clear();
  }

  // ---- HUD keyboard handlers (wired from the viewport) ----
  /// A digit / '.' / '-' typed into the focused box.
  void hudType(String ch) {
    if (!hudActive) return;
    if (ch == '-') {
      // toggle sign only as the leading character
      hudInput =
          hudInput.startsWith('-') ? hudInput.substring(1) : '-$hudInput';
    } else if (ch == '.') {
      if (!hudInput.contains('.')) hudInput += hudInput.isEmpty ? '0.' : '.';
    } else {
      hudInput += ch;
    }
    notifyListeners();
  }

  void hudBackspace() {
    if (!hudActive || hudInput.isEmpty) return;
    hudInput = hudInput.substring(0, hudInput.length - 1);
    notifyListeners();
  }

  /// Clears the box being typed (Esc's first job while a value is pending).
  bool hudClearInput() {
    if (!hudActive || hudInput.isEmpty) return false;
    hudInput = '';
    notifyListeners();
    return true;
  }

  /// Tab: lock the current box (if a value is pending) and move to the next.
  void hudTab() {
    if (!hudActive) return;
    final fields = hudFieldsFor(tool, toolPoints.length);
    if (fields.isEmpty) return;
    final typed = Fmt.num(hudInput);
    if (typed != null) hudLocked[hudFocus] = typed;
    hudInput = '';
    hudFocus = (hudFocus + 1) % fields.length;
    notifyListeners();
  }

  /// Shift-Tab / arrow left/up: same lock-and-move, one field backwards.
  void hudTabBack() {
    if (!hudActive) return;
    final fields = hudFieldsFor(tool, toolPoints.length);
    if (fields.isEmpty) return;
    final typed = Fmt.num(hudInput);
    if (typed != null) hudLocked[hudFocus] = typed;
    hudInput = '';
    hudFocus = (hudFocus - 1 + fields.length) % fields.length;
    notifyListeners();
  }

  /// Enter: lock the pending box, then place the point at the effective cursor
  /// (the same as clicking there). Commits the shape if it completes it.
  void hudEnter() {
    if (!hudActive) return;
    final typed = Fmt.num(hudInput);
    if (typed != null) hudLocked[hudFocus] = typed;
    hudInput = '';
    final raw = hoverWorld ?? (toolPoints.isNotEmpty ? toolPoints.last : null);
    if (raw == null) return;
    toolClick(raw); // routes through the HUD-aware placement below
  }

  /// Fold this phase's locked fields into [hudCommitDims] just before a point
  /// is committed, so the final commit knows every dimension to create.
  void _hudAccumulate() {
    final fields = hudFieldsFor(tool, toolPoints.length);
    hudLocked.forEach((i, v) {
      if (i >= 0 && i < fields.length) hudCommitDims[fields[i].kind] = v;
    });
  }

  /// M45 — last known viewport pixel size and the last pointer position in
  /// world coords, so Insert (from the ribbon, which has no view metrics) can
  /// place content AT THE CURSOR and size it relative to the current view.
  Size viewportSize = const Size(1024, 768);
  Offset lastPointerWorld = Offset.zero;

  /// World width currently spanned by the viewport.
  double get viewWidthWorld => viewportSize.width / zoom;

  /// Where new inserted content should go: the last pointer position if we
  /// have one in view, else the view centre (pan).
  Offset get insertAnchor => lastPointerWorld;

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

  /// Test-only: point the sketch/sidecar directory at a scratch path without
  /// the platform channel (host `flutter test` has no path provider).
  @visibleForTesting
  set docsDirForTest(Directory? d) => _docsDir = d;

  /// Test-only: the active docs directory, for asserting on written files.
  @visibleForTesting
  Directory? get docsDirForTest => _docsDir;

  /// Where documents (and therefore logs and bug bundles) live. Null until
  /// [init] has resolved it. Public because the bug reporter has to write
  /// next to the logs, and reaching for the test-only accessor to do that
  /// would be a lie about who the API is for.
  Directory? get docsDir => _docsDir;

  /// Where preferences live: settings.json and anything that belongs to it,
  /// such as the gallery's backdrop picture (M270). Null until [init] has
  /// resolved the documents directory. Dot-prefixed, so nothing in here is
  /// ever mistaken for a document — see [_cacheRoot].
  Directory? get settingsDir => _docsDir == null ? null : _cacheRoot;
  List<SavedSketchInfo> saved = [];
  String backendInfo = '';
  bool backendReal = false;

  Future<void> init() async {
    try {
      _docsDir = await Log.stepAsync(
          'state',
          'getApplicationDocumentsDirectory (platform channel)',
          () => getApplicationDocumentsDirectory());
      Log.i('state', 'docs dir = ${_docsDir!.path}');
    } catch (e, st) {
      Log.e('state', 'docs dir failed, using systemTemp', e, st);
      _docsDir = Directory.systemTemp;
    }
    // Move the log into the SAME Documents directory as the sketches, so it is
    // actually reachable in Files > On My iPad > prototype > logs. The early
    // logger uses $HOME (empty on some iOS builds -> temp dir, not file-shared).
    Log.retarget(_docsDir!.path);
    Perf.retarget(_docsDir!.path);
    // M234 — adopt the remembered language.
    //
    // HERE and not in main(): init() is fired and deliberately not awaited so
    // the first frame does not wait on a platform channel, and putting a
    // settings read in front of runApp would undo that. The cost is that an
    // English user can see one German frame at launch; the alternative is a
    // measurable launch regression in an app whose launch time is a tracked
    // number, and one frame is the cheaper of the two.
    L.attachStore(LocaleStore(_cacheRoot));
    // M237 — previews written before this milestone have the viewport colour
    // BAKED IN, so every one of them stayed charcoal under the cream scheme.
    // They are derived data, so the repair is to throw them away and draw them
    // again; the new ones are transparent and will never need this twice.
    _migratePreviews();
    // M236 — the appearance choice is remembered in the same file, off the
    // launch path for the same reason. Until this runs the app follows the
    // iPad's own setting, which is also the default, so the worst case is one
    // frame in the system scheme before an explicit override is adopted.
    T.attachStore(ThemeStore(_cacheRoot));
    // M270 — and so is the gallery's backdrop, in the same file for the same
    // reason. It is read AFTER the appearance because "match appearance" is
    // its default, and adopting it before there is an appearance to match
    // would show one frame of the wrong ground.
    Backdrops.attachStore(BackdropStore(_cacheRoot));
    // M284 — the ribbon band's dock, in the same file for the same reason. It
    // is read after the appearance and backdrop so its default (the flush top
    // band) never paints over a scheme that has not been adopted yet.
    RibbonDock.attachStore(RibbonStore(_cacheRoot));
    // M349 — the band's other preference, out of the same file and read in
    // the same breath: whether it writes the name under each command.
    RibbonLabels.attachStore(RibbonStore(_cacheRoot));
    RenderEngines.attachStore(RenderEngineStore(_cacheRoot));
    // M367 — and how many samples that renderer aims at. Same file,
    // same shape, read in the same breath: which renderer draws the
    // viewport and how hard it works on the picture are one decision the
    // user makes in two halves.
    RenderSamples.attachStore(RenderSamplesStore(_cacheRoot));
    // M348 — the live icon preview's host, in the same file for the same
    // reason. Empty unless someone has typed one in, and while it is empty
    // every icon in the app is the one it was built with.
    IconPreview.attachStore(IconPreviewStore(_cacheRoot));
    // M373 — SHARING, and it goes last of the preference stores on purpose:
    // adopting a code STARTS a mirror that may write into this very
    // directory, and everything that reads it has to have read it first.
    //
    // The mirror is pointed at the two directories rather than asked to find
    // them: `_docsDir` is a container on the iPad and an XDG path on a
    // desktop, and nothing about the network layer should have to know that.
    LanSync.instance.attach(
      documents: _docsDir!,
      preferences: _cacheRoot,
    );
    LanSync.instance.onApplied = _adoptSynced;
    ShareCodes.attachStore(SyncStore(_cacheRoot));
    final probe = Log.step(
        'state', 'Engine.create (backend probe)', () => Engine.create());
    backendReal = probe.isRealBackend;
    backendInfo = probe.version;
    probe.dispose();
    // Honest FFI smoke marker (M2-Restschuld): a real round trip through the
    // engine that is actually in use, reported truthfully.
    final smoke =
        Log.step('state', 'Engine.create (smoke)', () => Engine.create());
    smoke.addLine(0, 0, 10, 5);
    smoke.addCircle(5, 5, 2);
    final n = smoke.allGeometry().length;
    smoke.dispose();
    Log.i(
        'smoke',
        n == 2
            ? 'DART SMOKE: PASS (backend=${backendReal ? "qcad-ffi" : "dart-fallback"}, $backendInfo)'
            : 'DART SMOKE: FAIL (geometry round-trip broke, backend=$backendInfo)');
    // M55 — same honest-marker idea for the 3D kernel: a real box through the
    // linked OCCT shim, verified against the smoke_occt.c numbers. On host
    // (symbols not linked) this reports SKIP, never a fake PASS.
    Log.i('smoke', Log.step('state', 'occt smoke', () => occtSmokeLine()));
    // M177 — before anything lists documents: convert the pre-single-file
    // layout, and recall which documents were opened from outside the app.
    Log.step('state', 'migrateLegacyDocuments', () => migrateLegacyDocuments());
    Log.step('state', 'loadRemembered', () => _loadRemembered());
    await Log.stepAsync(
        'state', 'reacquireExternals', () => reacquireExternals());
    await Log.stepAsync('state', 'refreshSaved', () => refreshSaved());
    notifyListeners();
    Log.i('state', 'AppState.init done (backendReal=$backendReal)');
  }

  // ---- M177: where documents live ----
  //
  // A document is ONE FILE in the app folder (or wherever the user opened it
  // from). Everything it contains is unpacked into a private staging folder
  // under .cache, which the existing readers and writers work against exactly
  // as they always have. The staging folder holds nothing that is not in the
  // document: it can be deleted at any moment and is rebuilt on next open.

  /// Everything the app writes that is NOT a document. Dot-prefixed so the
  /// gallery's folder scan never sees it and Files hides it.
  Directory get _cacheRoot {
    final d = Directory('${_docsDir!.path}/.cache');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// The unpacked working copy of document [name].
  Directory _stage(String name) {
    final d = Directory('${_cacheRoot.path}/docs/$name');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Where the gallery's thumbnails are extracted to.
  ///
  /// The preview lives INSIDE the document, but the gallery hands a `File` to
  /// `Image.file`, so one is pulled out here. Keyed by path, not name, so an
  /// external "Bracket" cannot show an internal "Bracket"'s picture.
  File _thumbFile(DocRef ref) {
    final d = Directory('${_cacheRoot.path}/thumbs');
    if (!d.existsSync()) d.createSync(recursive: true);
    final key = ref.path.hashCode.toUnsigned(32).toRadixString(16);
    return File('${d.path}/${ref.name}_$key.png');
  }

  /// The documents the gallery knows about, by name.
  final Map<String, DocRef> library = {};

  /// The document [name] refers to — from the library, or by looking in the
  /// app folder when the library has not been built yet.
  ///
  /// The second half matters: [openSketch], [savePart] and the name checks can
  /// all run before the first [refreshSaved], and a document that is plainly
  /// sitting in the folder must not be invisible to them just because nothing
  /// has listed it yet.
  DocRef? _findDoc(String name) {
    final known = library[name];
    if (known != null) return known;
    if (_docsDir == null) return null;
    for (final ext in kDocExtensions) {
      final path = '${_docsDir!.path}/$name.$ext';
      if (File(path).existsSync()) {
        final ref = DocRef(name, kindOfPath(path), path, DocSource.internal);
        library[name] = ref;
        return ref;
      }
    }
    return null;
  }

  /// The file document [name] is stored in, or null when it has never been
  /// saved. This IS the document — one file, wherever the user keeps it.
  String? pathOfDocument(String name) => _findDoc(name)?.path;

  /// Test-only: the unpacked working copy of [name], for asserting on what a
  /// document contains without unpacking it by hand.
  @visibleForTesting
  Directory stageDirForTest(String name) => _stage(name);

  /// Remembered EXTERNAL documents, in the order they were last opened.
  final List<DocRef> _remembered = [];

  static const String _kRememberedFile = 'externals.json';

  File get _rememberedPath => File('${_cacheRoot.path}/$_kRememberedFile');

  /// Test-only: recall the remembered externals, as [init] does on launch.
  @visibleForTesting
  void loadRememberedForTest() => _loadRemembered();

  /// Re-opens the door to every remembered external document.
  ///
  /// A path is not a durable handle to a file outside the app's container:
  /// the sandbox grant dies with the process, and the user is free to move or
  /// rename the file in Files between launches. Resolving the bookmark
  /// re-acquires access AND says where the file is now, so a document the user
  /// tidied into another folder is still the same document rather than a dead
  /// gallery row.
  ///
  /// A document that cannot be resolved is LEFT ALONE, not forgotten: iCloud
  /// may simply not have it downloaded yet, and dropping the entry would lose
  /// the user's link to their own file permanently.
  Future<void> reacquireExternals() async {
    if (_remembered.isEmpty) return;
    var moved = 0;
    for (var i = 0; i < _remembered.length; i++) {
      final ref = _remembered[i];
      final bm = ref.bookmark;
      if (bm == null) continue;
      final got = await NativeMenu.resolveDocument(bm);
      final now = got?['path'];
      if (now == null) {
        Log.w('doc', 'could not re-open "${ref.name}" (${ref.path})');
        continue;
      }
      final fresh = got?['bookmark'];
      if (now != ref.path || fresh != null) {
        _remembered[i] = DocRef(ref.name, ref.kind, now, ref.source,
            ref.lastOpened, fresh ?? ref.bookmark);
        if (now != ref.path) {
          moved++;
          Log.i('doc', '"${ref.name}" moved: ${ref.path} -> $now');
        }
      }
    }
    if (moved > 0) _saveRemembered();
  }

  void _loadRemembered() {
    _remembered
      ..clear()
      ..addAll(decodeRemembered(
          _rememberedPath.existsSync() ? _rememberedPath.readAsStringSync() : null));
  }

  void _saveRemembered() {
    try {
      _rememberedPath.writeAsStringSync(encodeRemembered(_remembered));
    } catch (e) {
      Log.w('doc', 'could not remember external documents: $e');
    }
  }

  /// The file a document is stored in. Internal by default; an external
  /// document keeps the path it was opened from, which is the whole point.
  String docPath(String name, {bool part = false, String? kind}) {
    final known = _findDoc(name);
    if (known != null) return saveTargetFor(known, _docsDir!.path);
    return '${_docsDir!.path}/$name.'
        '${extForKind(kind ?? (part ? 'part' : 'sketch'))}';
  }

  File _dxfFile(String name) => File('${_stage(name).path}/sketch.dxf');

  /// M112 — the layer construction geometry is exported onto. "Defpoints" is
  /// the long-standing AutoCAD convention for a layer that is visible on
  /// screen but never plotted or machined.
  static const String kDxfConstructionLayer = 'Defpoints';
  File _pngFile(String name) => File('${_stage(name).path}/$kPreviewEntry');

  /// Makes sure [name]'s staging folder holds the document's contents.
  ///
  /// Cheap when the stage is already warm: the document is unpacked once per
  /// session, not once per read.
  final Set<String> _staged = {};

  void _ensureStaged(String name) {
    if (_staged.contains(name)) return;
    final ref = _findDoc(name);
    if (ref != null) {
      final doc = readDoc(ref.path);
      if (doc != null) {
        unpackDoc(doc, Directory('${_cacheRoot.path}/docs/$name'));
      }
    }
    _staged.add(name);
  }

  /// Packs [name]'s staging folder into its document file.
  bool _commitStage(String name, String kind) {
    final ref = _findDoc(name) ??
        DocRef(name, kind, docPath(name, kind: kind), DocSource.internal);
    final target = saveTargetFor(ref, _docsDir!.path);
    final ok = writeDoc(target, packDir(_stage(name), kind));
    if (!ok) {
      Log.e('doc', 'could not write "$name" to $target', null, null);
      return false;
    }
    library[name] = DocRef(name, kind, target, ref.source, DateTime.now());
    _staged.add(name);
    // The thumbnail cache is keyed by path, so it goes stale on every save.
    try {
      final t = _thumbFile(library[name]!);
      final png = _pngFile(name);
      if (png.existsSync()) {
        png.copySync(t.path);
      } else if (t.existsSync()) {
        t.deleteSync();
      }
    } catch (_) {}
    return true;
  }

  // ---- M177: document files. One file per document makes delete, rename and
  // duplicate three one-line filesystem operations instead of a walk over a
  // list of sidecar suffixes that a new sidecar could silently fall out of.

  /// Removes [name]'s document file, thumbnail and staging folder.
  void _deleteDocFile(String name) {
    final ref = _findDoc(name);
    try {
      if (ref != null) {
        final f = File(ref.path);
        if (f.existsSync()) f.deleteSync();
        final t = _thumbFile(ref);
        if (t.existsSync()) t.deleteSync();
        _remembered.removeWhere((e) => e.path == ref.path);
        _saveRemembered();
      }
    } catch (e) {
      Log.w('doc', 'delete "$name" failed: $e');
    }
    library.remove(name);
    _dropStage(name);
  }

  /// Moves [from]'s document file to [to]. An external document is renamed
  /// WHERE IT LIVES — moving it into the app folder behind the user's back
  /// would be the same betrayal as saving an internal copy.
  bool _renameDocFile(String from, String to) {
    final ref = _findDoc(from);
    if (ref == null) return false;
    final ext = extForKind(ref.kind);
    final dir = ref.source == DocSource.external
        ? (ref.path.contains('/')
            ? ref.path.substring(0, ref.path.lastIndexOf('/'))
            : '.')
        : _docsDir!.path;
    final target = '$dir/$to.$ext';
    try {
      final src = File(ref.path);
      if (!src.existsSync()) return false;
      src.renameSync(target);
      final t = _thumbFile(ref);
      if (t.existsSync()) t.deleteSync();
    } catch (e) {
      Log.w('doc', 'rename "$from" failed: $e');
      return false;
    }
    final moved = DocRef(to, ref.kind, target, ref.source, DateTime.now());
    library.remove(from);
    library[to] = moved;
    if (ref.source == DocSource.external) {
      _remembered.removeWhere((e) => e.path == ref.path);
      _remembered.insert(0, moved);
      _saveRemembered();
    }
    _dropStage(from);
    return true;
  }

  /// Copies [name]'s document to [copy] inside the app folder. A duplicate is
  /// always internal: it is a new document of the user's own, not a second
  /// claim on someone else's file.
  bool _duplicateDocFile(String name, String copy) {
    final ref = _findDoc(name);
    if (ref == null) return false;
    final ext = extForKind(ref.kind);
    final target = '${_docsDir!.path}/$copy.$ext';
    try {
      final src = File(ref.path);
      if (!src.existsSync()) return false;
      src.copySync(target);
    } catch (e) {
      Log.w('doc', 'duplicate "$name" failed: $e');
      return false;
    }
    library[copy] = DocRef(copy, ref.kind, target, DocSource.internal);
    return true;
  }

  // ---- M177: migrating the pre-single-file layout ----
  //
  // Before M177 a sketch was a .dxf plus eleven sidecars in `sketches/`, and a
  // part was a `<name>.part.json` beside a `parts/<name>/` tree. Those are
  // documents people have made; the migration's only job is to not lose one.
  //
  // The ordering is the whole design: every legacy document is read, packed
  // and WRITTEN, each new file is re-read to prove it parses, and only then is
  // the old layout set aside — by RENAMING the folder, never deleting it. If
  // anything at all fails, the old folder stays exactly where it is and the
  // migration is simply attempted again next launch.

  /// Legacy sketch/part storage, pre-M177.
  Directory get _legacyDir => Directory('${_docsDir!.path}/sketches');

  /// Where the legacy folder is parked once every document is out of it.
  Directory get _legacyBackupDir =>
      Directory('${_docsDir!.path}/.cache/pre-m177-backup');

  /// Converts the pre-M177 layout into .ptp / .pts documents.
  ///
  /// Returns the number of documents migrated. Safe to call on every launch:
  /// with no legacy folder it does nothing.
  int migrateLegacyDocuments() {
    final legacy = _legacyDir;
    if (!legacy.existsSync()) return 0;
    List<FileSystemEntity> listing;
    try {
      listing = legacy.listSync();
    } catch (e) {
      Log.e('migrate', 'could not read the legacy folder', e, null);
      return 0;
    }

    final parts = <String>[];
    final sketchNames = <String>[];
    for (final e in listing.whereType<File>()) {
      final f = e.uri.pathSegments.last;
      if (f.endsWith('.part.json')) {
        parts.add(f.substring(0, f.length - '.part.json'.length));
      } else if (f.endsWith('.dxf') && !f.endsWith('.export.dxf')) {
        sketchNames.add(f.substring(0, f.length - '.dxf'.length));
      }
    }
    // A name that is both is a part: the part.json is the document, the dxf
    // beside it would be an export left over from a share.
    sketchNames.removeWhere(parts.contains);
    if (parts.isEmpty && sketchNames.isEmpty) {
      _parkLegacyFolder();
      return 0;
    }

    Log.i('migrate',
        'pre-M177 layout: ${parts.length} part(s), ${sketchNames.length} sketch(es)');
    var done = 0;
    var failed = 0;
    for (final name in [...parts, ...sketchNames]) {
      final isPart = parts.contains(name);
      final target =
          '${_docsDir!.path}/$name.${isPart ? kPartExt : kSketchExt}';
      if (File(target).existsSync()) {
        // Already migrated on an earlier launch that could not park the
        // folder. Not an error, and NOT something to overwrite.
        done++;
        continue;
      }
      try {
        final stage = Directory('${_cacheRoot.path}/migrate/$name');
        if (stage.existsSync()) stage.deleteSync(recursive: true);
        stage.createSync(recursive: true);
        if (isPart) {
          _stageLegacyPart(legacy, name, stage);
        } else {
          _stageLegacySketch(legacy, name, stage);
        }
        if (!writeDoc(target, packDir(stage, isPart ? 'part' : 'sketch'))) {
          throw StateError('write failed');
        }
        // Prove it before anything old is touched.
        if (readDocHeader(target)?.entry(
                isPart ? kMetaEntry : '$kSketchBase.dxf') ==
            null) {
          throw StateError('the written document does not read back');
        }
        stage.deleteSync(recursive: true);
        done++;
        Log.i('migrate', 'migrated ${isPart ? "part" : "sketch"} "$name"');
      } catch (e, st) {
        failed++;
        Log.e('migrate', 'could not migrate "$name"', e, st);
        try {
          final half = File(target);
          if (half.existsSync()) half.deleteSync();
        } catch (_) {}
      }
    }
    if (failed == 0) {
      _parkLegacyFolder();
    } else {
      Log.w('migrate',
          '$failed document(s) did not migrate — the old folder is untouched '
              'and the migration runs again on the next launch');
    }
    return done;
  }

  /// Moves the legacy folder out of the gallery's way. RENAMED, never deleted:
  /// if the migration got something subtly wrong, the originals are still
  /// there to go back to.
  void _parkLegacyFolder() {
    try {
      final backup = _legacyBackupDir;
      if (backup.existsSync()) backup.deleteSync(recursive: true);
      backup.parent.createSync(recursive: true);
      _legacyDir.renameSync(backup.path);
      Log.i('migrate', 'pre-M177 folder kept at ${backup.path}');
    } catch (e) {
      Log.w('migrate', 'could not park the legacy folder: $e');
    }
  }

  void _stageLegacySketch(Directory legacy, String name, Directory stage) {
    for (final suffix in sketchFileSuffixes) {
      final src = File('${legacy.path}/$name$suffix');
      if (!src.existsSync()) continue;
      // The preview was <name>.png; inside a document it is preview.png.
      final dst = suffix == '.png'
          ? '${stage.path}/$kPreviewEntry'
          : '${stage.path}/$kSketchBase$suffix';
      src.copySync(dst);
    }
    _stageLegacyImages(legacy, File('${stage.path}/$kSketchBase.images.json'),
        stage);
  }

  void _stageLegacyPart(Directory legacy, String name, Directory stage) {
    File('${legacy.path}/$name.part.json').copySync('${stage.path}/$kMetaEntry');
    final png = File('${legacy.path}/$name.png');
    if (png.existsSync()) png.copySync('${stage.path}/$kPreviewEntry');

    final childDir = Directory('${legacy.path}/parts/$name/sketches');
    if (childDir.existsSync()) {
      final dst = Directory('${stage.path}/sketches')
        ..createSync(recursive: true);
      for (final f in childDir.listSync().whereType<File>()) {
        f.copySync('${dst.path}/${f.uri.pathSegments.last}');
        _stageLegacyImages(legacy, f, stage);
      }
    }
    // Imported STEP files lived in "<part>_imports/" beside the sketches;
    // _resolveImport also matches on base name, so moving them into the
    // document's own imports/ keeps every stored path working.
    final imports = Directory('${legacy.path}/${name}_imports');
    if (imports.existsSync()) {
      final dst = Directory('${stage.path}/imports')
        ..createSync(recursive: true);
      for (final f in imports.listSync().whereType<File>()) {
        f.copySync('${dst.path}/${f.uri.pathSegments.last}');
      }
    }
  }

  /// Copies the image files an images.json sidecar refers to into the document.
  ///
  /// Images used to sit loose in the shared folder, so a document was never
  /// self-contained. Without this a migrated sketch would open with its
  /// pictures missing.
  void _stageLegacyImages(Directory legacy, File sidecar, Directory stage) {
    if (!sidecar.existsSync()) return;
    try {
      for (final img in decodeImages(sidecar.readAsStringSync())) {
        final src = File('${legacy.path}/${img.file}');
        if (!src.existsSync()) continue;
        final dst = Directory('${stage.path}/images')
          ..createSync(recursive: true);
        src.copySync('${dst.path}/${img.file}');
      }
    } catch (e) {
      Log.w('migrate', 'image migration failed: $e');
    }
  }

  /// Drops [name]'s staging folder (after a delete or rename).
  void _dropStage(String name) {
    _staged.remove(name);
    try {
      final d = Directory('${_cacheRoot.path}/docs/$name');
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// M373 — a peer's files have landed. Take what can be taken.
  ///
  /// TWO RULES, and the second one is the important one.
  ///
  ///   * PREFERENCES are re-read and applied live. They are small, they have
  ///     no unsaved state, and a scheme that changed on the iPad should be the
  ///     scheme here — that is the whole promise of "settings are synced".
  ///   * A DOCUMENT THAT IS OPEN IS NOT RELOADED. The bytes are on disk and
  ///     the next save from this device will win, but nothing is pulled out
  ///     from under someone who is drawing. A mirror that reloaded the model
  ///     under an open sketch would lose work in the one case the user could
  ///     not have anticipated, and "the device you are working on keeps its
  ///     work" is a rule anyone can hold in their head.
  ///
  /// The gallery is refreshed either way, so a document that arrived from
  /// another device is simply there.
  void _adoptSynced(Set<String> paths) {
    final prefs = paths.where((p) => p.startsWith('settings/')).toList();
    final docs = paths.where((p) => !p.startsWith('settings/')).toList();
    if (prefs.isNotEmpty) reloadPreferences();
    if (docs.isEmpty) return;
    final open = <String>{
      for (final n in openTabs) n,
    };
    // A path that is no longer on disk arrived as a DELETE rather than as a
    // file. The two need saying apart in the log, because "adopted Bracket.ptp"
    // and "Bracket.ptp is gone" are opposite events and the log is the first
    // place anyone looks when a document they wanted has vanished.
    final gone = docs
        .where((p) => !File('${_docsDir!.path}/$p').existsSync())
        .toList();
    if (gone.isNotEmpty) {
      Log.i('sync', 'removed here too: ${gone.join(", ")}');
    }
    final reopened = docs
        .map((p) => p.contains('.') ? p.substring(0, p.lastIndexOf('.')) : p)
        .where(open.contains)
        .toList();
    if (reopened.isNotEmpty) {
      // An OPEN document is not closed under the user's hands, whether what
      // arrived was a new version or a deletion. The tab keeps what is in
      // memory; saving it again puts it back on every device, which is the
      // same last-writer-wins rule the mirror uses everywhere else and the
      // only behaviour that cannot lose work someone is in the middle of.
      Log.i('sync',
          'left ${reopened.join(", ")} alone — open here, and this device wins');
    }
    unawaited(refreshSaved());
  }

  /// Re-reads `settings.json` and applies what changed.
  ///
  /// The same six stores AppState.init attaches, asked to adopt the file
  /// again. Each one is a ValueNotifier behind a store, so re-attaching is how
  /// a preference becomes live — there is no separate "apply" path to keep in
  /// step, which is the point.
  void reloadPreferences() {
    if (_docsDir == null) return;
    try {
      T.attachStore(ThemeStore(_cacheRoot));
      L.attachStore(LocaleStore(_cacheRoot));
      Backdrops.attachStore(BackdropStore(_cacheRoot));
      RibbonDock.attachStore(RibbonStore(_cacheRoot));
      RibbonLabels.attachStore(RibbonStore(_cacheRoot));
      RenderEngines.attachStore(RenderEngineStore(_cacheRoot));
      RenderSamples.attachStore(RenderSamplesStore(_cacheRoot));
      IconPreview.attachStore(IconPreviewStore(_cacheRoot));
      Log.i('sync', 'adopted the settings from a peer');
    } catch (e) {
      Log.w('sync', 'could not adopt the settings: $e');
    }
  }

  Future<void> refreshSaved() async {
    final list = <SavedSketchInfo>[];
    library.clear();
    if (_docsDir != null) {
      final names = <String>[];
      try {
        for (final e in _docsDir!.listSync()) {
          final n = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (e is File) names.add(n);
        }
      } catch (e) {
        Log.w('doc', 'app folder scan failed: $e');
      }
      final refs = mergedLibrary(
        scanAppFolder(names, _docsDir!.path),
        _remembered,
        stillExists: (p) {
          try {
            return File(p).existsSync();
          } catch (_) {
            // Unreachable is NOT gone: an iOS security-scoped path can be
            // temporarily out of reach and must keep its place in the gallery.
            return true;
          }
        },
      );
      for (final r in refs) {
        // Two documents can carry the same name (one internal, one opened from
        // elsewhere). The gallery is keyed by name, so the internal one wins
        // and the external keeps a disambiguated label.
        var label = r.name;
        if (library.containsKey(label)) {
          if (r.source == DocSource.internal) {
            library[label] = r;
            continue;
          }
          label = '${r.name} (${_folderLabel(r.path)})';
          if (library.containsKey(label)) continue;
        }
        library[label] = DocRef(label, r.kind, r.path, r.source, r.lastOpened);
      }
      for (final entry in library.entries) {
        final r = entry.value;
        DateTime modified;
        try {
          modified = File(r.path).lastModifiedSync();
        } catch (_) {
          modified = r.lastOpened ?? DateTime.fromMillisecondsSinceEpoch(0);
        }
        // M272 — the document's OWN kind, all three of them. It used to be
        // `isPart ? 'part' : 'sketch'`, which quietly filed every assembly
        // under sketch: the card's blank state drew a sketch cube for an
        // assembly, and the gallery had no way to say which was which even
        // though _Card has handled all three kinds since M240.
        list.add(SavedSketchInfo(entry.key, modified, _thumbFor(r), r.kind));
      }
    }
    list.sort((a, b) => b.modified.compareTo(a.modified));
    saved = list;
    // NOT awaited: the gallery must appear now. The repair decodes a handful
    // of PNGs, fixes the ones that carry a palette, and asks for a repaint if
    // any did.
    unawaited(_repairThumbGrounds(list));
  }

  /// The folder an external document sits in, for disambiguating two
  /// documents that share a name.
  static String _folderLabel(String path) {
    final parts = path.split('/')..removeLast();
    return parts.isEmpty ? 'elsewhere' : parts.last;
  }

  /// The gallery thumbnail for [ref], extracted from the document when the
  /// cached copy is missing or older than the document itself.
  File? _thumbFor(DocRef ref) {
    final t = _thumbFile(ref);
    try {
      final src = File(ref.path);
      if (!src.existsSync()) return t.existsSync() ? t : null;
      if (t.existsSync() &&
          !t.lastModifiedSync().isBefore(src.lastModifiedSync())) {
        return t;
      }
      // Header + one blob: listing a gallery of parts never reads a payload.
      final bytes = readDocEntry(ref.path, kPreviewEntry);
      if (bytes == null || bytes.isEmpty) {
        if (t.existsSync()) t.deleteSync();
        return null;
      }
      t.writeAsBytesSync(bytes);
      return t;
    } catch (e) {
      Log.w('doc', 'thumbnail for "${ref.name}" failed: $e');
      return t.existsSync() ? t : null;
    }
  }

  // ---- sketch-level file management (gallery context menu) ----

  /// EVERY file that belongs to one sketch, relative to its staging folder.
  ///
  /// M177 — kept because [_writeLegacySketchStage] still has to recognise the
  /// old on-disk layout during migration, and because the names inside a
  /// document are exactly these. The base is the constant "sketch": what a
  /// document is CALLED is the file name, so nothing inside it has to change
  /// when it is renamed.
  static const List<String> sketchFileSuffixes = [
    '.dxf',
    '.png',
    '.cons.json',
    '.params.json',
    '.texts.json',
    '.images.json',
    '.splines.json',
    '.gears.json',
    '.styles.json',
    '.proj.json',
    '.layers.json',
  ];

  bool sketchNameExists(String name) =>
      sketches.containsKey(name) || _findDoc(name)?.isPart == false;

  /// Null when [raw] is a usable sketch name, otherwise the reason. Names are
  /// used verbatim as file names, so anything that could escape the sketch
  /// directory has to be refused here.
  String? validateSketchName(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return L.current.valNameEmpty;
    if (n.length > 60) return L.current.valNameTooLong;
    if (RegExp(r'[/\\:]').hasMatch(n)) return L.current.valNameBadChars;
    if (n.startsWith('.')) return L.current.valNameLeadingDot;
    return null;
  }

  Future<void> deleteSketch(String name) async {
    if (_docsDir == null) return;
    // Drop it from the SESSION first. finishEdit/goHome/closeTab all autosave,
    // so a still-open model would happily write the sketch back to disk after
    // the files were removed.
    openTabs.remove(name);
    sketches.remove(name);
    if (curTab == name) {
      curTab = openTabs.isNotEmpty ? openTabs.last : null;
      if (curTab == null) editingLayer = null;
      _reanalyze();
    }
    _deleteDocFile(name);
    await refreshSaved();
    notifyListeners();
  }

  /// Renames a sketch and all of its sidecars. Returns false (and changes
  /// nothing) when the name is invalid or taken.
  ///
  /// [SketchModel.name] is final, so an OPEN sketch is flushed to disk, dropped
  /// from the session and re-opened from the renamed files. That is correct and
  /// cheap, at the price of that sketch's undo journal — the same trade the
  /// load path already makes.
  Future<bool> renameSketch(String from, String to) async {
    if (_docsDir == null) return false;
    final target = to.trim();
    if (target == from) return true;
    if (validateSketchName(target) != null) return false;
    if (sketchNameExists(target)) return false;

    final tabIndex = openTabs.indexOf(from);
    final wasCurrent = curTab == from;
    final otherCurrent = wasCurrent ? null : curTab;

    if (sketches.containsKey(from)) {
      await saveSketch(from);
      openTabs.remove(from);
      sketches.remove(from);
      if (wasCurrent) curTab = null;
    }

    final moved = _renameDocFile(from, target);

    if (moved && tabIndex >= 0) {
      await openSketch(target); // reloads from the renamed files
      // openSketch appends and focuses; put the tab back where it was.
      openTabs.remove(target);
      openTabs.insert(math.min(tabIndex, openTabs.length), target);
      if (!wasCurrent) {
        curTab = otherCurrent;
        _reanalyze();
      }
    }
    await refreshSaved();
    notifyListeners();
    return moved;
  }

  /// Copies a sketch to "<name> copy" (then " copy 2", …). Returns the new name.
  Future<String?> duplicateSketch(String name) async {
    if (_docsDir == null) return null;
    if (sketches.containsKey(name)) await saveSketch(name);
    if (_findDoc(name) == null) return null;

    var copy = '$name copy';
    var n = 2;
    while (docNameExists(copy)) {
      copy = '$name copy $n';
      n++;
    }
    if (!_duplicateDocFile(name, copy)) return null;
    await refreshSaved();
    notifyListeners();
    return copy;
  }

  /// Absolute path of the DXF to hand to the share sheet / Files exporter.
  /// Flushes an open sketch first so the exported file is never stale.
  Future<String?> sketchExportPath(String name) async {
    if (_docsDir == null) return null;
    if (sketches.containsKey(name)) await saveSketch(name);
    _ensureStaged(name);
    final f = _dxfFile(name);
    if (!f.existsSync()) return null;

    // M177 — the DXF inside a document is called "sketch.dxf", because what a
    // document is CALLED is its file name. The share sheet has to hand over
    // "<name>.dxf", so the export is always a copy under a proper name.
    final exportDir = Directory('${_cacheRoot.path}/export');
    if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
    final named = File('${exportDir.path}/$name.dxf');

    final model = await _loadSketchIn(_stage(name), name, base: kSketchBase);
    try {
      return _writeExportDxf(model, named, storage: f);
    } catch (e) {
      Log.w('export', 'export copy failed: $e');
      try {
        f.copySync(named.path);
        return named.path;
      } catch (_) {
        return null;
      }
    } finally {
      if (!sketches.containsKey(name)) model.dispose();
    }
  }

  /// Writes [model] to [out] as the EXPORT copy and returns its path, or null
  /// when nothing could be written. [storage] is the sketch's own DXF where
  /// one exists — the cheapest correct answer when there is nothing to
  /// protect, and the fallback when the rebuild fails.
  ///
  /// M112 — EXPORT A COPY, not the storage file.
  ///
  /// Construction and centreline geometry is only construction because of a
  /// Dart-side style tag that rides in a SIDECAR; the DXF itself has no such
  /// flag, so handing over the storage file exports scaffolding as REAL
  /// geometry. Anyone manufacturing from it cuts the construction lines. That
  /// was the one thing blocking this from being production-ready.
  ///
  /// The fix is the standard convention: construction geometry goes onto
  /// "Defpoints", which every CAD package treats as non-plotting. The
  /// geometry is still there — you can see it, snap to it, and re-import it —
  /// it just cannot be mistaken for the part.
  ///
  /// M218 — shared with [childSketchExportPath]: a sketch inside a part is a
  /// sketch, and the rule that keeps scaffolding out of a manufactured part
  /// cannot be one the gallery has and the 3D viewport has not.
  String? _writeExportDxf(SketchModel model, File out, {File? storage}) {
    final gs = model.geometry;
    final needsSplit = gs.any((g) => g.isConstruction || g.isCenterline);
    // M220 — TEXT IS GEOMETRY, and the storage file does not contain it.
    //
    // A text lives in a sidecar (it is one anchor plus a template, not a
    // thousand points — see text_geometry.dart), so the sketch's own DXF has
    // never held a single letter. Handing that file over would export a
    // drawing with the text missing, which is exactly the thing Inventor does
    // not do: there, a text IS in the exported DXF, as curves. So the moment
    // the sketch carries one, the export takes the rebuild path below and the
    // letters go into the file as closed polylines.
    final texts = textGeometry(model);
    if (!needsSplit &&
        texts.isEmpty &&
        storage != null &&
        storage.existsSync()) {
      storage.copySync(out.path); // nothing to protect: ship it under its name
      return out.path;
    }
    final tmp = SketchModel('_export');
    try {
      tmp.layers
        ..clear()
        ..addAll(model.layers);
      if (needsSplit && !tmp.layers.contains(kDxfConstructionLayer)) {
        tmp.layers.add(kDxfConstructionLayer);
      }
      _rebuildEngine(tmp, [
        for (final g in gs)
          (g.isConstruction || g.isCenterline)
              ? g.onLayer(kDxfConstructionLayer)
              : g,
        ...texts,
      ]);
      if (tmp.engine.saveDxf(out.path)) return out.path;
      Log.w('export', 'export copy failed; falling back to storage file');
    } finally {
      tmp.dispose();
    }
    if (storage != null && storage.existsSync()) {
      storage.copySync(out.path);
      return out.path;
    }
    return null;
  }

  // (Removed the six first-launch design-dummy cards: a fresh install now
  // shows an empty gallery with a "new sketch" prompt instead of fake sketches
  // that could not be opened.)

  // ---- tab / home behaviour (exactly like the mock JS) ----
  void goHome() {
    final leaving = curTab;
    if (leaving != null && parts.containsKey(leaving)) {
      cancel3DCommands(); // M230 — not just the extrude one
      pickPlane = false;
      activeChild = null;
    }
    // Leave edit mode WITHOUT its conditional save, then persist the document
    // unconditionally (incl. its preview) via flushCurrentDocument. Doing the
    // save through finishEdit alone missed two cases: a sketch viewed but not
    // edited (finishEdit early-returns), and a part (no preview was written at
    // all). flush runs before curTab is cleared, so it sees the document.
    finishEdit(save: false);
    flushCurrentDocument();
    curTab = null;
    selectedBody = null;
    browserHoverBody = null;
    _reanalyze();
    notifyListeners();
  }

  /// Persist the currently-open document — sketch OR part — INCLUDING its
  /// preview image, unconditionally. Unlike [finishEdit] this never early-
  /// returns on "not in edit mode", which is exactly the case that used to
  /// leave a stale sketch thumbnail (or, for a brand-new part, none) behind.
  /// A no-op when nothing is open. Called on every path OUT of a document:
  /// goHome, closeTab, and app suspend/detach (see main.dart).
  Future<void> flushCurrentDocument() async {
    final name = curTab;
    if (name == null) return;
    if (assemblies.containsKey(name)) {
      await saveAssembly(name);
    } else if (parts.containsKey(name)) {
      await savePart(name);
    } else if (sketches.containsKey(name)) {
      await saveSketch(name);
    }
  }

  /// Saves the open document and says WHERE it went.
  ///
  /// M177 — this is what Ctrl+S calls. It used to call [saveSketch]
  /// unconditionally, which meant Ctrl+S in a PART saved nothing at all and
  /// still said "Save failed" rather than what had happened. And a document
  /// opened from outside the app is written back to the file it came from:
  /// the whole promise of Open is that Save lands where you opened from.
  Future<void> saveCurrentDocument() async {
    final name = curTab;
    if (name == null) return;
    final ref = _findDoc(name);
    final ok = assemblies.containsKey(name)
        ? await saveAssembly(name)
        : parts.containsKey(name)
            ? await savePart(name)
            : sketches.containsKey(name)
                ? await saveSketch(name)
                : false;
    if (!ok) {
      toast(L.current.msgCouldNotSave(name));
      return;
    }
    final saved = library[name] ?? ref;
    toast(saved != null && saved.source == DocSource.external
        ? L.current.msgSavedTo(_folderLabel(saved.path))
        : L.current.msgSavedNamed(name));
  }

  // ---- M177: Open ----

  /// Opens whatever the user picked: one of ours from anywhere, or a STEP or
  /// DXF to convert. Returns the gallery name it ended up under.
  ///
  /// ONE verb. The button says "Open" because from where the user stands
  /// there is one action; which of the four things happens follows from the
  /// file, not from a menu they have to get right first.
  Future<String?> openPath(String path, {String? bookmark}) async {
    if (_docsDir == null) return null;
    final action =
        openActionFor(path, _docsDir!.path, volatileDirs: _volatileDirs);
    Log.milestone('doc', 'open "$path" -> ${action.name}');
    switch (action) {
      case OpenAction.unsupported:
        toast(L.current.msgCannotOpenKind);
        return null;
      case OpenAction.import:
        return importAsNewDocument(path);
      case OpenAction.adopt:
        return adoptDocument(path);
      case OpenAction.openExternal:
        if (readDocHeader(path) == null) {
          toast(L.current.msgNotAPrototypeDoc);
          return null;
        }
        final ref = DocRef(docNameOf(path)!, isPartPath(path) ? 'part' : 'sketch',
            path, DocSource.external, DateTime.now(), bookmark);
        _remembered.removeWhere((e) => e.path == path);
        _remembered.insert(0, ref);
        _saveRemembered();
        continue open;
      open:
      case OpenAction.openInternal:
        await refreshSaved();
        final label = _labelForPath(path);
        if (label == null) {
          toast(L.current.msgCouldNotOpenDoc);
          return null;
        }
        // The file on disk may have changed since it was last staged — it is
        // the user's own file in their own folder, after all.
        _dropStage(label);
        await openDocument(label);
        return label;
    }
  }

  /// Folders whose contents the system may empty at any time.
  ///
  /// The iOS file picker hands a picked file over as a COPY in tmp rather than
  /// opening the original in place, so without this the app would remember a
  /// path that is about to disappear and save the user's edits into it.
  List<String> get _volatileDirs =>
      _volatileDirsOverride ??
      [
        // Dart's systemTemp is NSTemporaryDirectory() on iOS, which is exactly
        // where the ordinary file picker leaves its copies.
        Directory.systemTemp.path,
        '${_docsDir!.path}/.cache',
      ];

  List<String>? _volatileDirsOverride;

  /// Test-only. The host suite keeps its scratch folders under systemTemp, so
  /// without this every "opened from elsewhere" fixture would look like a
  /// picker copy.
  @visibleForTesting
  set volatileDirsForTest(List<String>? dirs) => _volatileDirsOverride = dirs;

  /// Takes a copy handed over by the system into the app folder and opens it
  /// there. Returns the name it landed under.
  Future<String?> adoptDocument(String path) async {
    if (readDocHeader(path) == null) {
      toast(L.current.msgNotAPrototypeDoc);
      return null;
    }
    final ext = extForKind(kindOfPath(path));
    final base = docNameOf(path)!;
    var name = base;
    for (var i = 2; docNameExists(name); i++) {
      name = '$base $i';
    }
    try {
      File(path).copySync('${_docsDir!.path}/$name.$ext');
    } catch (e, st) {
      Log.e('doc', 'could not take "$path" into the app folder', e, st);
      toast(L.current.msgCouldNotOpenDoc);
      return null;
    }
    Log.i('doc', 'adopted "$path" as "$name"');
    await refreshSaved();
    await openDocument(name);
    return name;
  }

  /// The gallery name the document at [path] is listed under.
  String? _labelForPath(String path) {
    for (final e in library.entries) {
      if (e.value.path == path) return e.key;
    }
    return null;
  }

  /// Converts a STEP, DXF or mesh file into a NEW document in the app folder.
  ///
  /// The original is never touched and never referenced: a foreign file is a
  /// source, not a document, and the app folder is where the user's documents
  /// belong. Returns the new document's name.
  Future<String?> importAsNewDocument(String path) async {
    var base = path.split('/').last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    var name = base.isEmpty ? 'Imported' : base;
    for (var i = 2; docNameExists(name); i++) {
      name = '$base $i';
    }
    final lower = path.toLowerCase();
    try {
      if (lower.endsWith('.step') || lower.endsWith('.stp')) {
        if (!await createNamedPart(name)) return null;
        await importStepIntoPart(path);
        await savePart(name);
      } else if (lower.endsWith('.dxf')) {
        if (!await createNamedSketch(name)) return null;
        importDxf(path);
        await saveSketch(name);
      } else if (isMeshPath(path)) {
        if (!await createNamedPart(name)) return null;
        if (await importMeshIntoPart(path) == 0) {
          // The toast from importMeshIntoPart already said what was wrong.
          // Drop the empty part rather than leaving a blank document behind.
          await deleteDocument(name);
          return null;
        }
        await savePart(name);
      } else {
        toast(L.current.msgCannotOpenKind);
        return null;
      }
    } catch (e, st) {
      Log.e('import', 'import of "$path" failed', e, st);
      toast(L.current.msgCouldNotImportFile);
      return null;
    }
    Log.i('doc', 'imported "$path" as "$name"');
    return name;
  }

  /// Forgets an external document — the file itself is left alone.
  Future<void> forgetExternal(String name) async {
    final ref = _findDoc(name);
    if (ref == null || ref.source != DocSource.external) return;
    _remembered.removeWhere((e) => e.path == ref.path);
    _saveRemembered();
    _dropStage(name);
    await refreshSaved();
    notifyListeners();
  }

  /// True when [name] is listed from outside the app folder.
  bool isExternal(String name) => _findDoc(name)?.source == DocSource.external;

  /// Timed with a Stopwatch across the await, not with Perf.span: this is
  /// async, and span measures a synchronous body — wrapping the future
  /// would time how long it took to CREATE it, i.e. report that opening a
  /// document is free. Same reason as savePart/saveSketch.
  Future<void> openSketch(String name) async {
    final sw = Stopwatch()..start();
    try {
      await _openSketchInner(name);
    } finally {
      Perf.record('io.openSketch', sw.elapsedMicroseconds / 1000.0);
    }
  }

  Future<void> _openSketchInner(String name) async {
    if (!sketches.containsKey(name)) {
      final s = SketchModel(name);
      _ensureStaged(name);
      // load from disk if present
      final f = _dxfFile(name);
      if (f.existsSync()) {
        s.engine.loadDxf(f.path);
        s.refresh();
        final cf = File('${_stage(name).path}/$kSketchBase.cons.json');
        if (cf.existsSync()) {
          s.constraints.addAll(decodeConstraints(cf.readAsStringSync()));
          ensureParamNames(s); // M41: pre-M41 sidecars load nameless
        }
        try {
          final pf = File('${_stage(name).path}/$kSketchBase.params.json');
          if (pf.existsSync()) {
            s.userParams.addAll(decodeUserParams(pf.readAsStringSync()));
          }
        } catch (e) {
          Log.w('state', 'user-param sidecar read failed: $e');
        }
        try {
          final tf = File('${_stage(name).path}/$kSketchBase.texts.json');
          if (tf.existsSync())
            s.texts.addAll(decodeTexts(tf.readAsStringSync()));
          final imf = File('${_stage(name).path}/$kSketchBase.images.json');
          if (imf.existsSync()) {
            s.images.addAll(decodeImages(imf.readAsStringSync()));
          }
        } catch (e) {
          Log.w('state', 'text/image sidecar read failed: $e');
        }
        // Spline tags: the DXF has no spline (R_NO_OPENNURBS), so a spline came
        // back from refresh() as a plain polyline. Re-tag by index (entities
        // load in save order, same as the constraint sidecar assumes).
        try {
          final sf = File('${_stage(name).path}/$kSketchBase.splines.json');
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
        // Gears: the DXF gave back each gear as its baked outline polyline. The
        // .splines.json above re-tagged it gearTag; here we restore the COMPACT
        // editable form (centre, handle + parameter block) stored in the gear
        // sidecar, so the reloaded gear drags and edits like a live gear.
        try {
          final gf = File('${_stage(name).path}/$kSketchBase.gears.json');
          if (gf.existsSync()) {
            final j = jsonDecode(gf.readAsStringSync()) as Map<String, dynamic>;
            j.forEach((k, v) {
              final i = int.tryParse(k);
              if (i == null || i < 0 || i >= s.geometry.length) return;
              List<double>? data;
              if (v is Map && v['d'] is List) {
                data =
                    (v['d'] as List).map((e) => (e as num).toDouble()).toList();
              }
              if (data != null && data.length >= 6 + 6) {
                final prev = s.geometry[i];
                s.geometry[i] = Geo(Geo.polyline, data,
                    layer: prev.layer, spline: Geo.gearTag, style: prev.style);
              }
            });
          }
        } catch (e) {
          Log.w('state', 'gear sidecar read failed: $e');
        }
        try {
          final stf = File('${_stage(name).path}/$kSketchBase.styles.json');
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
          final pf = File('${_stage(name).path}/$kSketchBase.proj.json');
          if (pf.existsSync()) {
            final j = jsonDecode(pf.readAsStringSync()) as Map<String, dynamic>;
            j.forEach((k, v) {
              final i = int.tryParse(k);
              if (i != null && i >= 0 && i < s.geometry.length) {
                s.geometry[i] = v is List
                    ? s.geometry[i]
                        .withProj((v[0] as num).toInt(), (v[1] as num).toInt())
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
        var eos = -1; // -1: pre-M51 sidecar -> marker at the end
        try {
          final lf = File('${_stage(name).path}/$kSketchBase.layers.json');
          if (lf.existsSync()) {
            final j = jsonDecode(lf.readAsStringSync()) as Map<String, dynamic>;
            ordered = [
              for (final l in (j['layers'] as List? ?? const [])) l as String
            ];
            hidden.addAll((j['hidden'] as List? ?? const []).cast<String>());
            locked.addAll((j['locked'] as List? ?? const []).cast<String>());
            eos = (j['eos'] as num?)?.toInt() ?? -1;
          }
        } catch (e) {
          Log.w('state', 'layer sidecar read failed: $e');
        }
        s.layers
          ..clear()
          ..addAll(ordered);
        s.hiddenLayers.addAll(hidden);
        s.lockedLayers.addAll(locked);
        // The marker BEFORE syncing/pruning: both keep it in step themselves
        // (_syncLayers inserts adopted layers above it, prune shifts it).
        s.eosAfter = eos < 0 ? s.layers.length : eos;
        _syncLayers(s); // append any geometry-only layers the sidecar missed
        _pruneEmptyBaseLayer(s); // never show an empty phantom "0"
        Log.i(
            'layer',
            'loaded "$name": layers=${s.layers} '
                'hidden=${s.hiddenLayers} locked=${s.lockedLayers} '
                'eos=${s.eosAfter}');
      }
      sketches[name] = s;
      // Undo baseline: the freshly created/loaded state is entry ZERO of the
      // journal — undo walks back to it but never past it, and loading from
      // disk is not an edit.
      s.resetHistory();
    }
    if (!openTabs.contains(name)) openTabs.add(name);
    if (curTab != name) {
      selectedBody = null; // a selection belongs to ONE part
      browserHoverBody = null;
    }
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
    analysis =
        s == null ? null : _analysisCache.of(s.geometry, s.constraints);
  }

  // ==== UNDO / REDO (M39): restore side ==================================
  /// True while a snapshot is being restored: suppresses the checkpoint in
  /// _rebuildEngine so undo never journals itself.
  bool _restoringHistory = false;

  // ==== LIVE EDITS (M179) ================================================
  // A scrub (M172) applies a REAL value on every detent, so the sketch solves
  // and the preview rebuilds while the finger is still down — that is the
  // whole point, and it is what Inventor does. Two things must not happen per
  // detent, though:
  //
  //   * a journal entry. One drag across a dimension would otherwise bury the
  //     undo stack under forty steps of the same edit, and Ctrl+Z would walk
  //     back through them one notch at a time.
  //   * a toast. "Value cannot be satisfied" is worth saying once, on release;
  //     said thirty times while dragging past an unreachable range it is a
  //     strobe.
  //
  // Both are suppressed BETWEEN [beginLiveEdit] and [endLiveEdit], and the
  // release then re-commits the final value with everything back on — so the
  // gesture costs exactly one undo step and says whatever it has to say once.
  int _liveEdits = 0;

  /// True between [beginLiveEdit] and [endLiveEdit].
  bool get liveEditing => _liveEdits > 0;

  void beginLiveEdit() => _liveEdits++;

  /// Counted rather than boolean: a widget torn down mid-drag calls this from
  /// dispose, and an unbalanced call must not leave the journal switched off
  /// for the rest of the session — hence the floor at zero.
  void endLiveEdit() {
    if (_liveEdits > 0) _liveEdits--;
  }

  bool get canUndo => current?.canUndo ?? false;
  bool get canRedo => current?.canRedo ?? false;

  /// Ctrl+Z. Steps the CURRENT sketch one committed state back — every other
  /// sketch's history is untouched (the stacks live in the SketchModel).
  void undo() => _applyHistory((s) => s.undoStep(), 'undo');

  /// Ctrl+Shift+Z (and Ctrl+Y). Steps forward again.
  void redo() => _applyHistory((s) => s.redoStep(), 'redo');

  /// M179 — puts the sketch back to the last COMMITTED state without spending
  /// a journal step. Esc out of a value that a live scrub has already applied:
  /// the drag drove the geometry (and may have had to CREATE the dimension it
  /// was driving), and none of it was journalled, so the entry the journal is
  /// still sitting on is exactly "before the drag". Restoring it is therefore
  /// both the old value and the old geometry, exactly — which re-typing the
  /// old number could only approximate, since a re-solve may settle elsewhere.
  void revertToLastCheckpoint() =>
      _applyHistory((s) => s.pinnedSnap, 'revert');

  void _applyHistory(UndoSnap? Function(SketchModel) step, String what) =>
      Perf.span('history.$what', () => _applyHistoryInner(step, what));

  void _applyHistoryInner(UndoSnap? Function(SketchModel) step, String what) {
    final s = current;
    if (s == null) return;
    if (dragGrip != null) return; // never rip the state out from under a drag
    final snap = step(s);
    if (snap == null) {
      toast(what == 'undo'
          ? L.current.msgNothingToUndo
          : L.current.msgNothingToRedo);
      return;
    }
    Log.i(
        'undo',
        '$what "${s.name}" -> depth=${s.undoDepth} '
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
      s.userParams
        ..clear()
        ..addAll(decodeUserParams(snap.uparams));
      s.texts
        ..clear()
        ..addAll(decodeTexts(snap.texts));
      s.images
        ..clear()
        ..addAll(decodeImages(snap.images));
      s.layers
        ..clear()
        ..addAll(snap.layers);
      s.hiddenLayers
        ..clear()
        ..addAll(snap.hidden);
      s.lockedLayers
        ..clear()
        ..addAll(snap.locked);
      s.eosAfter = snap.eos.clamp(0, s.layers.length);
      // Editing a layer the restored state does not have (or has hidden,
      // locked, or rolled back below End of Sketch again) cannot continue.
      final el = editingLayer;
      if (el != null &&
          (!s.layers.contains(el) ||
              s.hiddenLayers.contains(el) ||
              s.lockedLayers.contains(el) ||
              s.layers.indexOf(el) >= s.eosAfter)) {
        editingLayer = null;
        tool = Tool.none;
      }
      _rebuildEngine(s, [
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

  /// Next free "SketchN" — the value the new-sketch prompt starts with, so the
  /// user can just hit Create.
  String suggestedSketchName() {
    var n = _newN + 1;
    while (sketchNameExists('Sketch$n')) {
      n++;
    }
    return 'Sketch$n';
  }

  /// Creates [name], opens it, and drops STRAIGHT into a fresh layer in edit
  /// mode — an empty sketch with no layer can do nothing at all (drawing tools
  /// refuse outside the edit scope, M16), so landing there was always a dead
  /// end the user had to click out of.
  Future<bool> createNamedSketch(String name) async {
    final clean = name.trim();
    if (validateSketchName(clean) != null) return false;
    // one gallery, two document kinds: a part named "X" blocks a sketch "X"
    if (docNameExists(clean)) return false;
    await openSketch(clean);
    startNewLayer(); // -> enterEdit()
    return true;
  }

  Future<void> closeTab(String name) async {
    if (assemblies.containsKey(name)) {
      await saveAssembly(name);
      assemblies.remove(name)?.dispose();
      _evictUnplacedSources();
    } else if (parts.containsKey(name)) {
      if (curTab == name) {
        cancel3DCommands(); // M230
        pickPlane = false;
        activeChild = null;
        finishEdit(save: false);
      }
      await savePart(name);
      final model = parts.remove(name);
      // M245 — an assembly still placing this part is still drawing this
      // model. Hand it to the shared map instead of disposing it: the
      // occurrences already point at it, so the transfer is invisible to
      // them, and disposing would blank every component of it.
      if (model != null) {
        if (_placedSources().contains(name)) {
          _componentModels[name] = model;
        } else {
          model.dispose();
        }
      }
    } else {
      await saveSketch(name);
    }
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

  SketchModel? get current =>
      activeChild ?? (curTab == null ? null : sketches[curTab]);

  /// The open 3D part (null when the current tab is a plain 2D sketch).
  PartModel? get currentPart => curTab == null ? null : parts[curTab];

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
    // Inventor: a new feature lands just ABOVE the End of Part marker, never
    // below it — with everything below staying rolled back.
    s.insertLayerAboveMarker(name);
    s.dirty = true;
    s.checkpoint(); // adding an (empty) layer never rebuilds -> journal here
    enterEdit(name);
  }

  bool layerVisible(String name) =>
      current?.hiddenLayers.contains(name) != true;

  /// M51 — true while [name] sits BELOW the End-of-Sketch marker. Rolled-back
  /// layers are Inventor's features below the EOP: dimmed in the browser, not
  /// drawn, not picked, not snapped, no grips, not editable. Their entities
  /// stay in the geometry list (constraint refs are index-based) and their
  /// constraints stay in the system — since nothing rolled back can ever be
  /// grabbed or re-targeted, they act as immovable anchors and moving the
  /// marker is instant and perfectly lossless in both directions.
  bool layerRolledBack(String name) {
    final s = current;
    if (s == null) return false;
    final i = s.layers.indexOf(name);
    return i >= 0 && i >= s.eosAfter.clamp(0, s.layers.length);
  }

  /// True when [g] should be drawn / picked / snapped at all.
  bool geoVisible(Geo g) => layerVisible(g.layer) && !layerRolledBack(g.layer);

  /// You may only TOUCH what you are editing. Being in Layer 2 must not let you
  /// trim, drag, constrain or dimension geometry that lives on Layer 1 — the
  /// layer is the editing scope, not just a paint colour. A locked layer is
  /// never editable even while it is the one in edit mode (belt and braces:
  /// [enterEdit] already refuses to enter a locked layer).
  bool geoEditable(Geo g) =>
      inEditMode && g.layer == editingLayer && !layerLocked(g.layer);

  /// True while [name] is locked (padlock in the model browser).
  bool layerLocked(String name) => current?.lockedLayers.contains(name) == true;

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
        // Above the End-of-Sketch marker: adopted geometry (legacy sketches,
        // imported DXF) must come in LIVE, not silently rolled back.
        s.insertLayerAboveMarker(g.layer);
      }
    }
  }

  void toggleLayerVisible(String name) {
    final s = current;
    if (s == null) return;
    if (layerRolledBack(name)) return; // no eye below End of Sketch
    if (s.hiddenLayers.remove(name)) {
      Log.i('layer', 'show "$name"');
    } else {
      s.hiddenLayers.add(name);
      Log.i('layer', 'hide "$name"');
      // You cannot edit what you cannot see.
      if (editingLayer == name) finishEdit(save: true);
    }
    selection.removeWhere(
        (i) => i < s.geometry.length && !layerVisible(s.geometry[i].layer));
    s.dirty = true;
    s.checkpoint(); // eye state rides the sidecar -> it is undoable state
    notifyListeners();
  }

  void enterEdit(String layerName) {
    final s = current;
    if (s == null || !s.layers.contains(layerName)) return;
    if (layerRolledBack(layerName)) {
      // Inventor: features below the EOP are unavailable until the marker is
      // dragged back down past them.
      toast(L.current.msgLayerBelowEos(layerName));
      return;
    }
    if (layerLocked(layerName)) {
      toast(L.current.msgLayerLockedEdit(layerName));
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
    if (save && curTab != null) {
      if (parts.containsKey(curTab)) {
        savePart(curTab!);
      } else {
        saveSketch(curTab!);
      }
    }
    notifyListeners();
  }

  /// Lock / unlock a layer. Locking the layer currently being edited drops you
  /// out of edit mode first (you cannot edit a locked layer). Selection is
  /// cleared of anything on the now-locked layer.
  void toggleLayerLocked(String name) {
    final s = current;
    if (s == null || !s.layers.contains(name)) return;
    if (layerRolledBack(name)) return; // no padlock below End of Sketch
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
      toast(L.current.msgDefaultLayerNoRename);
      return false;
    }
    if (isBaseLayer(newName)) {
      toast(L.current.msgZeroReserved);
      return false;
    }
    if (!s.layers.contains(oldName)) return false;
    if (newName.isEmpty) return false;
    if (newName == oldName) return true;
    if (s.layers.contains(newName)) {
      toast(L.current.msgLayerExists(newName));
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
      toast(L.current.msgDefaultLayerNoDelete);
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

    final li = s.layers.indexOf(name);
    s.layers.remove(name);
    s.noteLayerRemovedAt(li); // marker keeps sitting after the same layers
    s.hiddenLayers.remove(name);
    s.lockedLayers.remove(name);
    if (editingLayer == name) editingLayer = null;
    selection.clear();
    Log.i('layer', 'delete "$name" (removed ${victims.length} entities)');
    _rebuildEngine(s, gs);
    if (curTab != null) saveSketch(curTab!);
    return victims.length;
  }

  /// M193 — delete the selected geometry.
  ///
  /// Until now the only way a sketch could lose an entity was [deleteLayer]:
  /// there was no per-entity delete anywhere — not on a key, not in a menu,
  /// not on a button. Drawing a wrong line meant undoing back past everything
  /// after it, or throwing the layer away.
  ///
  /// Scope, like every other edit: only geometry on the layer being edited
  /// ([geoEditable]) can go. Outside edit mode nothing is deletable at all —
  /// the layer IS the editing scope (M17), and a delete that reached across
  /// layers would be the one operation that ignored it.
  ///
  /// Removal runs HIGHEST INDEX FIRST so each removal leaves the lower indices
  /// — and every constraint that refers to them — valid; [remapAfterRemove]
  /// drops the constraints and dimensions that pointed AT the deleted entity.
  /// Exactly the arithmetic [deleteLayer] uses, for exactly the same reason.
  /// One [_rebuildEngine] at the end makes the whole thing one undo step.
  ///
  /// Returns the number of entities removed.
  int deleteSelection() {
    final s = current;
    if (s == null) return 0;
    if (!inEditMode) {
      toast(L.current.msgEnterLayerToEdit);
      return 0;
    }
    final victims = <int>[
      for (final i in selection)
        if (i >= 0 && i < s.geometry.length && geoEditable(s.geometry[i])) i
    ]..sort((a, b) => b.compareTo(a));
    if (victims.isEmpty) {
      toast(L.current.msgSelectThenDelete);
      return 0;
    }
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
    // Nothing may keep pointing into the geometry that is about to shift: the
    // selection is index-based, and so is the live snap marker.
    selection.clear();
    snap = null;
    Log.i('edit', 'delete ${victims.length} selected entities');
    _rebuildEngine(s, gs);
    if (curTab != null) saveSketch(curTab!);
    notifyListeners();
    return victims.length;
  }

  /// True when [deleteSelection] would actually remove something — what the
  /// Delete button and the quick menu ask before offering themselves.
  bool get canDeleteSelection {
    final s = current;
    if (s == null || !inEditMode) return false;
    return selection.any(
        (i) => i >= 0 && i < s.geometry.length && geoEditable(s.geometry[i]));
  }

  /// Move the currently selected geometry onto [target]. This is how a sketch
  /// whose geometry is stranded on the wrong layer (e.g. everything on the
  /// default "0") gets sorted out: select it, then move it. Does nothing if
  /// nothing is selected or the target is locked.
  int moveSelectionToLayer(String target) {
    final s = current;
    if (s == null || !s.layers.contains(target)) return 0;
    if (selection.isEmpty) {
      toast(L.current.msgSelectThenMoveToLayer);
      return 0;
    }
    if (layerLocked(target)) {
      toast(L.current.msgLayerLocked(target));
      return 0;
    }
    if (layerRolledBack(target)) {
      toast(L.current.msgTargetBelowEos(target));
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
    final li = s.layers.indexOf(kDefaultLayer);
    if (s.layers.remove(kDefaultLayer)) {
      s.noteLayerRemovedAt(li);
      s.hiddenLayers.remove(kDefaultLayer);
      s.lockedLayers.remove(kDefaultLayer);
      Log.i('layer', 'dropped empty base layer "0" from the browser');
    }
  }

  // ==== M51 — End-of-Sketch marker (Inventor's End of Part) ==============

  /// Moves the marker so that [after] layers stay live above it. Everything
  /// below rolls back (dimmed, not drawn, not picked); dragging it back down
  /// restores everything unchanged — the move itself never touches geometry
  /// or constraints, so it is instant and lossless. One undoable step, like
  /// the eye/lock toggles.
  void setEndOfSketch(int after) {
    final s = current;
    if (s == null) return;
    final v = after.clamp(0, s.layers.length);
    if (v == s.eosAfter) return;
    s.eosAfter = v;
    Log.i('layer', 'End of Sketch -> after $v of ${s.layers.length} layers');
    // You cannot keep editing what just rolled back.
    final el = editingLayer;
    if (el != null && layerRolledBack(el)) finishEdit(save: true);
    selection.removeWhere(
        (i) => i < s.geometry.length && !geoVisible(s.geometry[i]));
    snap = null;
    s.dirty = true;
    s.checkpoint(); // marker position rides the sidecar -> undoable state
    notifyListeners();
  }

  /// Inventor's "Delete All Features Below EOP": removes every layer below
  /// the marker WITH its entities in one atomic operation (one undo step).
  /// Entities stranded below on the protected base layer "0" are deleted too
  /// (the row itself is pruned once empty). Index-based constraint refs are
  /// remapped exactly like [deleteLayer]. Returns the number of entities
  /// removed.
  int deleteBelowEndOfSketch() {
    final s = current;
    if (s == null) return 0;
    final eos = s.eosAfter.clamp(0, s.layers.length);
    final below = s.layers.sublist(eos);
    if (below.isEmpty) {
      toast(L.current.msgNothingBelowEos);
      return 0;
    }
    final names = below.toSet();
    final victims = <int>[
      for (var i = 0; i < s.geometry.length; i++)
        if (names.contains(s.geometry[i].layer)) i
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
    for (final name in below) {
      if (isBaseLayer(name)) continue; // "0" is never deleted, only emptied
      s.layers.remove(name);
      s.hiddenLayers.remove(name);
      s.lockedLayers.remove(name);
    }
    s.eosAfter = s.layers.length; // marker back at the end, nothing below
    selection.clear();
    Log.i(
        'layer',
        'delete below End of Sketch: ${below.length} layers, '
            '${victims.length} entities');
    _rebuildEngine(s, gs); // one rebuild = one undo step, like deleteLayer
    _pruneEmptyBaseLayer(s); // an emptied "0" never lingers as a phantom row
    if (curTab != null) saveSketch(curTab!);
    return victims.length;
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

  /// The sketch as it stood when the current drag began — the state the user
  /// was looking at when they put their finger down.
  ///
  /// M208: "the drag broke it" is measured against this snapshot, by
  /// [collapsedSince].
  /// A frame is compared with the frame before it, which is right for a branch
  /// flip (a jump) and blind to a slot cap sliding to zero radius over a
  /// hundred frames, because no single step of that is a break. Against the
  /// start of the gesture it is one.
  List<Geo>? _dragStartGeo;

  // ---- the display-geometry memo (S4) ----
  //
  // ONE SOLVE PER DRAG POSITION. See [displayGeometry] for why this exists.
  // Four guards and the answer they protect; each guard closes one way the
  // answer could change underneath the cache:
  //
  //   _dgSketch  identity — a tab switch puts a different sketch in play
  //   _dgGrip    identity — beginGripDrag allocates a NEW Grip, so a second
  //                         drag never inherits the first one's frame
  //   _dgPos     value    — the cursor moving is the whole point (Offset has
  //                         value equality, so this compares coordinates)
  //   _dgSource  identity — SketchModel.geometry is ASSIGNED wholesale by the
  //                         rebuild path and by undo, never patched in place,
  //                         so identity catches both
  //
  // What would slip past all four: an in-place mutation of the same list, at
  // the same cursor position, during the same drag. No such path exists while
  // a grip drag is live — drag frames work on copies, and the only writer is
  // the commit in endGripDrag, which runs AFTER its own displayGeometry call
  // and then nulls dragGrip. Pinned by s4_display_geometry_once_test.dart
  // rather than left as an argument.
  SketchModel? _dgSketch;
  Grip? _dgGrip;
  Offset? _dgPos;
  List<Geo>? _dgSource;
  List<Geo>? _dgResult;
  Offset? boxStart, boxEnd; // world coords while box-selecting
  bool boxCrossing = false;
  Rect? lastBoxRect; // remembered for Stretch (Inventor semantics)
  int? modEntity; // entity picked in the first phase of Offset
  final bool autoConstrain = true; // always on (Inventor: no toggle button)
  bool showConstraints =
      false; // Constrain panel: Show Constraints toggle — OFF by default (M32)
  bool showDof =
      false; // Inventor: Degrees of Freedom glyphs — OFF by default (M32)
  SketchAnalysis? analysis; // DOF + which points may still move
  /// Memo for [analysis]. The DOF analysis runs on every rebuild, every solve
  /// and every tab switch (PERFORMANCE_PROFILE 5.5.3) on a quantity that only
  /// changes when the geometry or the constraints do; this reuses the answer
  /// when they have not. It cannot hit during a drag — see
  /// [SketchAnalysisCache].
  final _analysisCache = SketchAnalysisCache();
  String? message; // transient notice (over-constrained warnings)

  void toggleShowDof() {
    showDof = !showDof;
    notifyListeners();
  }

  void toast(String m) {
    // M179 — a scrub applies a value per detent, so a value the constraints
    // cannot reach would say so per detent. Dragging past the limit is normal;
    // the release re-commits with messages back on and says it once.
    if (liveEditing) {
      Log.i('ui', 'notice (held back during live edit): $m');
      return;
    }
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

  // =========================================================================
  // M56 — 3D PART DOCUMENTS: persistence, child-sketch flow, Extrude
  // =========================================================================

  Directory _partSketchDir(String name) {
    final d = Directory('${_stage(name).path}/sketches');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Where a part's imported STEP files are stashed inside its document.
  Directory _partImportDir(String name) {
    final d = Directory('${_stage(name).path}/imports');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  File _partJson(String name) => File('${_stage(name).path}/$kMetaEntry');

  /// Absolute path of an imported STEP inside part [name]'s document, or null.
  ///
  /// Pre-M177 documents recorded the path as "<part>_imports/<file>" against
  /// the shared sketch folder; migration moves those files into the document's
  /// own imports/ folder, so both spellings are resolved by BASE NAME as well.
  /// A stored path is a reference to geometry the user imported — failing to
  /// find it costs them a body, so it is worth looking twice.
  String? _resolveImport(String name, String rel) {
    final stage = _stage(name).path;
    for (final cand in [
      '$stage/$rel',
      '$stage/imports/${rel.split('/').last}',
    ]) {
      if (File(cand).existsSync()) return cand;
    }
    return null;
  }

  bool isPartName(String name) =>
      parts.containsKey(name) || _findDoc(name)?.isPart == true;

  bool partNameExists(String name) => isPartName(name);

  /// Sketches and parts share one gallery, so names must be unique ACROSS
  /// both kinds — a "Bracket" part next to a "Bracket" sketch would be two
  /// cards with one label.
  bool docNameExists(String name) =>
      sketchNameExists(name) || partNameExists(name) || isAssemblyName(name);

  String suggestedPartName() {
    var n = 1;
    while (docNameExists('Part$n')) {
      n++;
    }
    return 'Part$n';
  }

  /// Opens whatever [name] is — part or sketch (gallery cards + tab bar).
  Future<void> openDocument(String name) async {
    if (isAssemblyName(name)) return openAssembly(name);
    if (isPartName(name)) return openPart(name);
    return openSketch(name);
  }

  /// M250 — [open] false CREATES the document without making it current.
  ///
  /// Create Component needs exactly that: the new part has to exist before it
  /// can be placed, and the ASSEMBLY has to stay the current tab until it has
  /// been. Switching here and back would put an empty part on screen for the
  /// length of the save that follows — the await is a frame boundary, so it
  /// really would be seen.
  Future<bool> createNamedPart(String name, {bool open = true}) async {
    final clean = name.trim();
    if (validateSketchName(clean) != null) return false;
    if (docNameExists(clean)) return false;
    final p = PartModel(clean);
    parts[clean] = p;
    if (open) {
      if (!openTabs.contains(clean)) openTabs.add(clean);
      curTab = clean;
      activeChild = null;
      editingLayer = null;
      tool = Tool.none;
      _reanalyze();
    }
    await savePart(clean);
    return true;
  }

  /// Timed with a Stopwatch across the await, not with Perf.span: this is
  /// async, and span measures a synchronous body — wrapping the future
  /// would time how long it took to CREATE it, i.e. report that opening a
  /// document is free. Same reason as savePart/saveSketch.
  Future<void> openPart(String name) async {
    final sw = Stopwatch()..start();
    try {
      await _openPartInner(name);
    } finally {
      Perf.record('io.openPart', sw.elapsedMicroseconds / 1000.0);
    }
  }

  Future<void> _openPartInner(String name) async {
    if (!parts.containsKey(name)) {
      // M245 — an open assembly may already hold this part's model. PROMOTE
      // it rather than reading the file again: the editor and every component
      // of it then share one object, which is what makes an edit here appear
      // in the assembly with nothing to propagate.
      final shared = _componentModels.remove(name);
      parts[name] = shared ?? await _loadPartModel(name);
    }
    // M255 — a derived body reads ANOTHER document, which may be loaded by
    // nothing at all: unlike a component, it is not placed anywhere. This is
    // the same loop the assemblies use — _placedSources() counts a derive
    // origin as something the session needs — so it loads the origin, and the
    // origin's own origin up the chain, and links everything when it lands.
    //
    // Guarded rather than unconditional: opening a part with no derived body
    // in the session must not grow an await and a directory scan.
    if (_loadedDeriveFeatures().any((f) => _sourceModel(f.sourceDoc) == null)) {
      await _loadPlacedSources();
    }
    linkOccurrences();
    // The load above ran the fold before this model was reachable, so a
    // derived body in it failed with "the origin is not loaded". Everything is
    // reachable now; read it.
    refreshDerived();
    // M237 — the still inside this document may predate the transparent
    // format, in which case its gallery card is a charcoal rectangle on a
    // cream shelf. The model is loaded and the kernel is warm right here, so
    // this is the cheapest honest moment to redraw it. Once per document.
    unawaited(_repairPreview(name));
    if (!openTabs.contains(name)) openTabs.add(name);
    if (curTab != name) {
      selectedBody = null; // a selection belongs to ONE part
      browserHoverBody = null;
    }
    curTab = name;
    activeChild = null;
    editingLayer = null;
    tool = Tool.none;
    _reanalyze();
    notifyListeners();
  }

  /// M214 — reads a part off disk and builds its geometry, and NOTHING else.
  ///
  /// Split out of [openPart] because "I need this part's solids" and "the user
  /// wants to look at this part" are two different requests, and until M214
  /// only the second one existed. Exporting a part from the gallery went
  /// through [openPart], so sharing a part ALSO added it to the tab bar, made
  /// it the current document, cleared the active tool and rebuilt the
  /// viewport — the whole app navigated into the part you meant to hand to
  /// someone. ([partExportStep] even had a `wasLoaded` local, computed and
  /// never read: the intent to undo that was written down and never finished.)
  ///
  /// The sketch side has always had this (`sketchExportPath` loads a headless
  /// model via `_loadSketchIn`); this is the part-side equivalent.
  ///
  /// The result is NOT registered in [parts]. A caller that wants it in the
  /// session puts it there; a caller that just needs geometry disposes it.
  Future<PartModel> _loadPartModel(String name) async {
    final p = PartModel(name);
    _ensureStaged(name);
    try {
      final f = _partJson(name);
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        p.loadJson(j);
        for (final sk in (j['sketches'] as List? ?? const [])) {
          final m = sk as Map;
          final model =
              await _loadSketchIn(_partSketchDir(name), m['name'] as String);
          p.childSketches.add(ChildSketch(
              model,
              m['plane'] as String? ?? 'xy',
              PlaneFrame.fromFrameJson(m['frame'] as List?),
              true, // real visibility is applied below from 'vis'
              m['shared'] as bool? ?? false,
              (m['seq'] as num?)?.toInt() ?? 0,
              // M153 — absent on pre-M153 documents, which then keep the
              // old frozen behaviour rather than being re-anchored onto a
              // face nobody chose.
              m['faceRef'] is Map
                  ? SketchFaceSel.fromJson(
                      (m['faceRef'] as Map).cast<String, dynamic>())
                  : null));
          _loadedSketchVis[model.name] =
              m.containsKey('vis') ? m['vis'] as bool? ?? true : null;
        }
      }
    } catch (e, st) {
      Log.e('part', 'open "$name" failed', e, st);
    }
    // M160 — the child sketches are attached above, AFTER loadJson ran, so
    // only now is the timeline complete enough to place the End of Part
    // marker and decide what it rolls back.
    p.finishLoad();
    // Legacy sidecars (pre-M59) have no per-sketch 'vis': apply the
    // Inventor default — consumed sketches load hidden.
    for (final cs in p.childSketches) {
      final consumed = firstConsumerOf(p, cs.model.name) != null;
      final stored = _loadedSketchVis[cs.model.name];
      cs.visible = stored ?? !consumed;
    }
    _loadedSketchVis.clear();
    // M112 — imported bodies are re-read from their STEP file. Their B-Rep
    // is deliberately NOT serialised (the file is the source of truth), so
    // without this an imported body would come back empty and the part would
    // silently lose geometry on reopen. A missing file is REPORTED, not
    // swallowed: geometry vanishing without explanation is the worse failure.
    //
    // Grouped by file and read ONCE per file, then handed out in order — a
    // STEP holding four solids became four features, and re-reading it four
    // times would be both slow and a leak, since each read returns all four.
    if (partKernel.available) {
      final byFile = <String, List<ExtrudeFeature>>{};
      for (final f in p.features) {
        // M131 — features are polymorphic; only an extrude can be an
        // imported body, so the type test is the guard AND the promotion.
        if (f is! ExtrudeFeature) continue;
        if (!f.imported || f.solid != null) continue;
        final rel = f.importPath;
        if (rel == null) {
          f.computeError = 'imported body has no source file';
          continue;
        }
        (byFile[rel] ??= []).add(f);
      }
      for (final entry in byFile.entries) {
        final abs = _resolveImport(name, entry.key);
        if (abs == null) {
          for (final f in entry.value) {
            f.computeError = 'imported file missing';
          }
          Log.w('import', 'missing STEP: ${entry.key}');
          continue;
        }
        final solids = partKernel.importStepSolids(abs);
        for (var i = 0; i < entry.value.length; i++) {
          if (i < solids.length) {
            entry.value[i].solid = solids[i];
          } else {
            entry.value[i].computeError = 'solid no longer in the file';
          }
        }
        // The file grew since the import: nothing claims those, so free them.
        for (var i = entry.value.length; i < solids.length; i++) {
          solids[i].dispose();
        }
      }
      // M182 — only sync projections when the recompute SUCCEEDED: a failed
      // pass leaves last-good geometry in place, and re-deriving projections
      // from a half-broken body is how closed profiles opened.
      if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    }
    Log.i(
        'part',
        'opened "$name": sketches=${p.childSketches.length} '
            'features=${p.features.length} kernel=${partKernel.available}');
    return p;
  }

  Future<bool> savePart(String name) async {
    // M255 — the LIVE half of Make Part.
    //
    // Every path that changes a part rebuilds it and then saves it, so this is
    // the one funnel where "a part's geometry just moved" is true of every
    // edit in the app, with nothing to remember at twenty call sites. Run
    // BEFORE the await so the derived body is current in the same frame the
    // edit lands in — the origin's own fold has already run by the time
    // anything asks to be saved.
    //
    // It does NOT notify: this is called from inside methods that are about to
    // notify anyway, and a second notify from in here would fire during their
    // own listeners. The rebuilt bodies are new mesh objects, so the frame
    // that follows draws them (assemblySceneSignature hashes mesh identity).
    refreshDerived();
    final sw = Stopwatch()..start();
    try {
      return await _savePartInner(name);
    } finally {
      // A Stopwatch rather than Perf.span: this is async, and span measures a
      // synchronous body — wrapping a Future would time how long it took to
      // CREATE the future, which is nearly zero and would read as "saving is
      // free". Same reason as saveSketch below.
      Perf.record('io.savePart', sw.elapsedMicroseconds / 1000.0);
    }
  }

  Future<bool> _savePartInner(String name) async {
    final p = parts[name];
    if (p == null || _docsDir == null) return false;
    _ensureStaged(name);
    try {
      _partJson(name).writeAsStringSync(jsonEncode(p.toJson()));
      // copy: the loop awaits, and a plane pick during that window would
      // append a child sketch (concurrent modification)
      for (final c in List<ChildSketch>.of(p.childSketches)) {
        await _saveSketchIn(_partSketchDir(name), c.model);
      }
      // M177 — a deleted child sketch used to leave its files behind in the
      // part folder, which was invisible clutter. Inside a single-file
      // document it would be dead weight carried in every copy and every
      // AirDrop, so the staging folder is pruned to what the part still has.
      _pruneChildSketches(name, p);
      p.dirty = false;
    } catch (e, st) {
      Log.e('part', 'save "$name" failed', e, st);
      return false;
    }
    await _writePartPreview(name, p);
    if (!_commitStage(name, 'part')) return false;
    await refreshSaved();
    notifyListeners();
    return true;
  }

  /// Deletes staged sketch files belonging to child sketches [p] no longer has.
  void _pruneChildSketches(String name, PartModel p) {
    try {
      final keep = {for (final c in p.childSketches) c.model.name};
      for (final f in _partSketchDir(name).listSync().whereType<File>()) {
        final file = f.uri.pathSegments.last;
        final dot = file.indexOf('.');
        if (dot <= 0) continue;
        if (!keep.contains(file.substring(0, dot))) f.deleteSync();
      }
    } catch (e) {
      Log.w('part', 'pruning "$name" failed: $e');
    }
  }

  /// The preview format currently on disk. Bump when a change makes older
  /// cached stills wrong rather than merely out of date.
  ///
  /// 1 — opaque, the viewport colour baked in (up to M236).
  /// 2 — transparent; the card supplies the ground (M237).
  static const int kPreviewFormat = 2;

  /// Documents whose still has already been redrawn in the current format.
  ///
  /// A preview lives INSIDE the document (`readDocEntry(kPreviewEntry)`), not
  /// only in the cache, so dropping the cache repairs nothing — the old
  /// opaque still is simply extracted again. Redrawing it means writing the
  /// document, and that is not something to do to every file on the launch
  /// path. So it happens when a document is OPENED, once, and this set is how
  /// "once" is remembered across launches.
  final Set<String> _previewsRepaired = <String>{};

  /// Drops the extracted thumbnail cache when the format on disk is older than
  /// [kPreviewFormat]. Cheap: a handful of file deletes, no geometry.
  void _migratePreviews() {
    try {
      final f = File('${_cacheRoot.path}/settings.json');
      Map<String, Object?> data = <String, Object?>{};
      if (f.existsSync()) {
        final raw = jsonDecode(f.readAsStringSync());
        if (raw is Map) {
          data = <String, Object?>{
            for (final e in raw.entries) '${e.key}': e.value
          };
        }
      }
      _previewsRepaired
        ..clear()
        ..addAll(
            (data['previewsRepaired'] as List? ?? const []).whereType<String>());
      if (data['previewFormat'] == kPreviewFormat) return;
      // A format bump invalidates every earlier repair.
      _previewsRepaired.clear();
      final thumbs = Directory('${_cacheRoot.path}/thumbs');
      if (thumbs.existsSync()) thumbs.deleteSync(recursive: true);
      data['previewFormat'] = kPreviewFormat;
      data['previewsRepaired'] = <String>[];
      f.writeAsStringSync(jsonEncode(data));
      Log.i('preview', 'format -> $kPreviewFormat, thumbnail cache dropped');
    } catch (e) {
      // A migration that cannot run costs stale-looking cards, not a launch.
      Log.w('preview', 'preview migration failed: $e');
    }
  }

  /// Redraws [name]'s still in the current format, once, and remembers it.
  ///
  /// Deliberately NOT on the launch path and deliberately not a sweep over
  /// every document: rewriting files the user did not ask about, at startup,
  /// is how a cosmetic fix turns into a data-loss report.
  Future<void> _repairPreview(String name) async {
    if (_previewsRepaired.contains(name)) return;
    final p = parts[name];
    if (p == null) return;
    // GUARD, and the important line in this method: repairing means SAVING,
    // and saving a model that did not load completely would overwrite a good
    // document with a partial one. A cosmetic fix must never be able to cost
    // geometry, so a part with nothing in it is left alone — its card is a
    // placeholder either way.
    if (p.features.isEmpty) {
      Log.i('preview', 'skipping the redraw for "$name": nothing loaded');
      return;
    }
    _previewsRepaired.add(name);
    try {
      await savePart(name);
      final f = File('${_cacheRoot.path}/settings.json');
      Map<String, Object?> data = <String, Object?>{};
      if (f.existsSync()) {
        final raw = jsonDecode(f.readAsStringSync());
        if (raw is Map) {
          data = <String, Object?>{
            for (final e in raw.entries) '${e.key}': e.value
          };
        }
      }
      data['previewsRepaired'] = _previewsRepaired.toList();
      f.writeAsStringSync(jsonEncode(data));
      Log.i('preview', 'redrew the still for "$name"');
    } catch (e) {
      _previewsRepaired.remove(name); // try again next time
      Log.w('preview', 'could not redraw the still for "$name": $e');
    }
  }

  /// Renders the part's solids to <name>.png (380x240) for the gallery card
  /// and the long-press lift preview.
  ///
  /// M82 — ONE ENGINE. The still is produced by the same RealityKit renderer
  /// that draws the live 3D viewport ([RealityThumbnailer.render] spins up an
  /// off-screen ARView and pushes the very same scene payload), so a body looks
  /// on the card exactly as it looks in the viewport. The Dart CPU painter
  /// (paintPartSolids) remains as the FALLBACK for every place RealityKit is
  /// unavailable — host tests, non-iOS, iOS < 15, app backgrounded with no key
  /// window, or any failed snapshot — and is still the only path exercised by
  /// the widget tests.
  ///
  /// Both engines are handed the IDENTICAL camera from [fitThumbCamera]: the
  /// fixed TOP-FRONT-RIGHT isometric corner, framed to the silhouette and
  /// independent of wherever the user left the live camera. A part therefore
  /// always presents the same corner in the gallery, and switching engines
  /// cannot change the framing.
  ///
  /// A part with no drawable solid — freshly created, or every feature deleted,
  /// or (on a build with no linked kernel) never computed — gets NO png and any
  /// stale one is removed, so its card honestly falls back to the cube glyph.
  Future<void> _writePartPreview(String name, PartModel p) async {
    final png = _pngFile(name);
    try {
      final named = [
        for (final f in p.features)
          // M91: a feature below End of Part is not part of the model yet.
          if (f.visible && f.solid != null && !f.consumedByJoin && !f.rolledBack)
            (f.name, f.solid!)
      ];
      if (named.isEmpty) {
        if (png.existsSync()) png.deleteSync();
        return;
      }
      const w = 380.0, h = 240.0;
      const size = Size(w, h);
      final solids = [for (final (_, s) in named) s];
      final cam = fitThumbCamera(solids, size);

      // Preferred path: the real engine.
      //
      // M237 — rendered on a TRANSPARENT ground (the default). The card paints
      // its own surface behind the PNG, so the file carries the part and never
      // a palette: a thumbnail written in Ember still looks right in Chalk,
      // and a scheme switch does not invalidate a single cached still.
      final shot = await RealityThumbnailer.render(
        // M272 — the appearances too. `named` is keyed by FEATURE name and a
        // material belongs to a body, so this is the same feature -> body ->
        // material walk _bodyRowTint does.
        scene: buildThumbScenePayload(named, tintOf: (id) {
          for (final f in p.features) {
            if (f.name == id) {
              return materialArgb(p.bodyMaterials[f.bodyName]) ?? kNoTint;
            }
          }
          return kNoTint;
        }),
        camera: cameraPayload(cam, size),
        width: w.toInt(),
        height: h.toInt(),
      );
      if (shot != null && shot.isNotEmpty) {
        // M269 — and CHECK that it came back without one, rather than
        // assuming. The off-screen renderer is a real view in the real window
        // and the ground it was told to use is not always the ground it draws.
        await png.writeAsBytes(await demattePng(shot) ?? shot);
        return;
      }

      // Fallback: CPU painter, same camera.
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
      // No background fill, for the reason above: the still is the part, and
      // the card supplies the ground.
      paintPartSolids(canvas, Cam3(cam, size), solids,
          materialOf: (s) => materialColorOfSolid(p, s));
      final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        await png.writeAsBytes(bytes.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('part preview write failed: $e');
    }
  }

  /// Stills already checked this session: path -> the mtime it was checked at.
  /// A still is only ever wrong once, and re-decoding nine PNGs on every
  /// gallery refresh to re-learn that is exactly the kind of cost a gallery
  /// must not carry.
  final Map<String, int> _groundChecked = {};

  /// M269 — the one-time repair for stills written before the check existed.
  ///
  /// Runs off the gallery refresh rather than at save, because the file that
  /// is wrong belongs to a document the user is not opening: waiting for the
  /// next save would leave the odd cream card among the charcoal ones until
  /// they happened to edit that part again. Rewriting the extracted thumbnail
  /// also makes it NEWER than its document, which is what stops [_thumbFor]
  /// from extracting the baked original over it again.
  Future<void> _repairThumbGrounds(List<SavedSketchInfo> list) async {
    var changed = false;
    for (final s in list) {
      final f = s.preview;
      if (f == null) continue;
      try {
        if (!f.existsSync()) continue;
        final stamp = f.lastModifiedSync().millisecondsSinceEpoch;
        if (_groundChecked[f.path] == stamp) continue;
        _groundChecked[f.path] = stamp;
        final fixed = await demattePng(await f.readAsBytes());
        if (fixed == null) continue;
        await f.writeAsBytes(fixed);
        _groundChecked[f.path] = f.lastModifiedSync().millisecondsSinceEpoch;
        // The bytes changed under a path Flutter has already decoded and
        // cached; without this the gallery keeps showing the old picture until
        // the app is relaunched.
        await FileImage(f).evict();
        changed = true;
      } catch (e) {
        Log.w('doc', 'thumbnail ground repair failed: $e');
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> deletePart(String name) async {
    if (_docsDir == null) return;
    openTabs.remove(name);
    if (curTab == name) {
      cancel3DCommands(); // M230
      pickPlane = false;
      activeChild = null;
      curTab = openTabs.isNotEmpty ? openTabs.last : null;
      if (curTab == null) editingLayer = null;
      _reanalyze();
    }
    parts.remove(name)?.dispose();
    // M245 — every component of it loses its geometry and keeps its row, so
    // the assembly says the part is gone rather than quietly drawing a copy
    // that no longer exists anywhere.
    _componentModels.remove(name)?.dispose();
    linkOccurrences();
    // M255 — and every part DERIVED from it goes sick NOW, naming the body it
    // can no longer read, rather than going on drawing the copy it happens to
    // be holding until something else asks it to rebuild.
    refreshDerived();
    _deleteDocFile(name);
    await refreshSaved();
    notifyListeners();
  }

  Future<bool> renamePart(String from, String to) async {
    if (_docsDir == null) return false;
    final target = to.trim();
    if (target == from) return true;
    if (validateSketchName(target) != null) return false;
    if (docNameExists(target)) return false;
    final wasOpen = openTabs.contains(from);
    final tabIndex = openTabs.indexOf(from);
    final wasCurrent = curTab == from;
    if (parts.containsKey(from)) {
      await savePart(from);
      openTabs.remove(from);
      parts.remove(from)?.dispose();
      if (wasCurrent) {
        activeChild = null;
        curTab = null;
      }
    }
    if (!_renameDocFile(from, target)) return false;
    // M245 — every assembly that places this part follows it. Done AFTER the
    // file has moved, so a failed rename leaves every reference pointing at
    // the document that is still there.
    final moved = _componentModels.remove(from);
    if (moved != null) _componentModels[target] = moved;
    await _renameSourceInAssemblies(from, target);
    // M255 — and every part DERIVED from it, in memory and on disk. Same
    // reason, one level down: a derived body names its origin by document
    // name too.
    await _renameSourceInDerivedParts(from, target);
    linkOccurrences();
    if (wasOpen) {
      await openPart(target);
      openTabs.remove(target);
      openTabs.insert(math.min(tabIndex, openTabs.length), target);
      if (!wasCurrent) curTab = openTabs.isNotEmpty ? openTabs.last : null;
    }
    // M255 — LAST, after the links have been re-pointed and the renamed
    // document is back. A derived body read a model that was disposed halfway
    // through this, so it is sick at this point and correct one line later; a
    // refresh anywhere earlier would be refreshing into the middle of the
    // rename.
    refreshDerived();
    await refreshSaved();
    notifyListeners();
    return true;
  }

  Future<String?> duplicatePart(String name) async {
    if (_docsDir == null) return null;
    if (parts.containsKey(name)) await savePart(name);
    if (_findDoc(name) == null) return null;
    var copy = '$name copy';
    var n = 2;
    while (docNameExists(copy)) {
      copy = '$name copy $n';
      n++;
    }
    if (!_duplicateDocFile(name, copy)) return null;
    await refreshSaved();
    notifyListeners();
    return copy;
  }

  // =========================================================================
  // M240 — ASSEMBLIES
  //
  // The third document kind. Everything below mirrors the part side one method
  // at a time (create / open / save / load / delete / rename / duplicate) and
  // deliberately does NOT try to share an implementation with it: a part is a
  // feature timeline with a kernel behind it and an assembly is a list of
  // placements, and the only thing they have in common is the document
  // plumbing — which they DO share, through _stage / _commitStage / _findDoc.
  // =========================================================================

  /// Open assemblies, by document name.
  final Map<String, AssemblyModel> assemblies = {};

  /// The open assembly, or null when the current tab is a part or a sketch.
  AssemblyModel? get currentAssembly =>
      curTab == null ? null : assemblies[curTab];

  bool isAssemblyName(String name) =>
      assemblies.containsKey(name) || _findDoc(name)?.isAssembly == true;

  String suggestedAssemblyName() {
    var n = 1;
    while (docNameExists('Assembly$n')) {
      n++;
    }
    return 'Assembly$n';
  }

  /// What can be PLACED into the open assembly: every part in the gallery
  /// and, M246, every OTHER assembly that would not make this one contain
  /// itself. Most recently modified first, so the one you were just working
  /// on is at the top of the list.
  ///
  /// The name is historical — it offered only parts until subassemblies
  /// existed — and is kept because the ribbon, the tests and the toast keys
  /// all say it.
  List<String> placeableParts() {
    final into = currentAssembly;
    final out = [
      for (final e in library.entries)
        if (e.value.isPart ||
            (e.value.isAssembly &&
                into != null &&
                !_wouldNestCycle(into, e.key)))
          e.key
    ];
    final when = <String, DateTime>{
      for (final s in saved) s.name: s.modified,
    };
    out.sort((a, b) {
      final ma = when[a], mb = when[b];
      if (ma == null || mb == null) {
        return a.toLowerCase().compareTo(b.toLowerCase());
      }
      return mb.compareTo(ma);
    });
    return out;
  }

  Future<bool> createNamedAssembly(String name) async {
    final clean = name.trim();
    if (validateSketchName(clean) != null) return false;
    if (docNameExists(clean)) return false;
    final a = AssemblyModel(clean);
    assemblies[clean] = a;
    if (!openTabs.contains(clean)) openTabs.add(clean);
    curTab = clean;
    activeChild = null;
    editingLayer = null;
    tool = Tool.none;
    _reanalyze();
    await saveAssembly(clean);
    return true;
  }

  Future<void> openAssembly(String name) async {
    if (!assemblies.containsKey(name)) {
      assemblies[name] = await _loadAssemblyModel(name);
    }
    // M245 — the geometry comes from the ONE model per part document, loaded
    // now if nothing holds it yet. Awaited: a component with no geometry
    // draws as a missing part, and one frame of that is a flicker.
    await _loadPlacedSources();
    // M255 — and a DERIVED component may have been placed here while its
    // origin was edited in a part tab since. Same reason it is awaited above:
    // the assembly must not draw one frame of yesterday's body.
    refreshDerived();
    if (!openTabs.contains(name)) openTabs.add(name);
    if (curTab != name) {
      selectedBody = null; // a selection belongs to ONE part
      browserHoverBody = null;
    }
    curTab = name;
    activeChild = null;
    editingLayer = null;
    tool = Tool.none;
    _reanalyze();
    notifyListeners();
  }

  File _assemblyJson(String name) => File('${_stage(name).path}/$kMetaEntry');

  Future<AssemblyModel> _loadAssemblyModel(String name) async {
    final a = AssemblyModel(name);
    _ensureStaged(name);
    try {
      final f = _assemblyJson(name);
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        a.loadJson(j);
      }
    } catch (e, st) {
      Log.e('asm', 'load "$name" failed', e, st);
    }
    // The occurrences came back as references. Give each one its geometry.
    //
    // A source part that has since been DELETED leaves its occurrence in the
    // list with no part behind it: the browser still shows the row (so the
    // user can see what is missing and remove it) and nothing is drawn for it.
    // Dropping the row instead would silently rewrite the user's assembly the
    // first time a file went walkabout.
    for (final o in List<AssemblyOccurrence>.of(a.occurrences)) {
      // The MODEL is not loaded here — see linkOccurrences. The assembly is
      // not in `assemblies` yet at this point, so there is nothing for the
      // link to walk; openAssembly does it once the model is in place.
      if (_findDoc(o.source)?.isPart != true) {
        Log.w('asm', 'occurrence "${o.id}": part "${o.source}" is gone');
      }
    }
    return a;
  }

  // ---- M245: a component IS its part ---------------------------------------
  //
  // "A part in an assembly should be linked to the part at all times. So when
  // the part updates, it updates in assembly."
  //
  // M240 loaded a PRIVATE COPY of the part for every occurrence, once, when
  // the assembly was opened. That is a snapshot, not a link: edit the part
  // and the assembly went on drawing what it had looked like at open time.
  //
  // The rule now is that there is exactly ONE PartModel per part document in
  // the whole app, and every occurrence of that part points at it:
  //
  //   * open in its own tab  -> `parts[name]`, the model being edited. An
  //     extrusion added there is in the assembly the moment you switch to it,
  //     with no reload, no second kernel build and no copy of the mesh.
  //   * not open             -> `_componentModels[name]`, a shared load kept
  //     for the assemblies that reference it.
  //
  // The two are the SAME OBJECT across a tab open or close: opening a part
  // promotes the shared load into `parts`, closing it hands it back. So a
  // component never notices a tab opening, and nothing is ever loaded twice.
  //
  // The RealityKit side needs nothing: assemblySceneSignature already hashes
  // each piece's mesh identity, so a rebuilt part moves the signature and the
  // heavy push fires by itself.

  /// Models for parts that are PLACED but not open in a tab. One per
  /// document, shared by every occurrence of it, owned here.
  final Map<String, PartModel> _componentModels = {};

  /// M246 — the same, for SUBASSEMBLIES. An assembly placed inside another is
  /// a document like any other: one model, shared, and the very one open in
  /// its own tab when it is open, so editing a subassembly shows in its
  /// parent for the same reason editing a part does.
  final Map<String, AssemblyModel> _componentAssemblies = {};

  /// The one model for part [name], or null when there is none to be had.
  PartModel? _sourceModel(String name) =>
      parts[name] ?? _componentModels[name];

  /// The one model for assembly [name], or null.
  AssemblyModel? _sourceAssembly(String name) =>
      assemblies[name] ?? _componentAssemblies[name];

  /// Every document any OPEN assembly places, transitively.
  ///
  /// Transitive because a subassembly's own components have to stay loaded
  /// too: the parent draws them, and nothing else references them.
  Set<String> _placedSources() {
    final out = <String>{};
    void walk(AssemblyModel a, Set<String> seen) {
      for (final o in a.occurrences) {
        out.add(o.source);
        if (!o.isSubAssembly) continue;
        if (!seen.add(o.source)) continue; // a cycle cannot be created, but
        final child = _sourceAssembly(o.source); // a hand-edited file could
        if (child != null) walk(child, seen);
      }
    }

    for (final a in assemblies.values) {
      walk(a, {a.name});
    }
    // M255 — and every part a LOADED part is DERIVED from.
    //
    // This set is what decides which shared models are loaded and which are
    // freed, and until Make Part existed an assembly was the only thing that
    // could reach across documents. A derived body reaches exactly as far: it
    // reads the origin's geometry on every rebuild, so freeing the origin
    // because "nothing places it" would blank the derived part instead.
    //
    // Re-read on every call rather than cached, exactly like the walk above,
    // because [_loadPlacedSources] loops on it: a derived part loaded in one
    // pass contributes ITS origin to the next, so a chain of derivations
    // resolves without anything having to know how long it is.
    for (final f in _loadedDeriveFeatures()) {
      if (f.sourceDoc.isNotEmpty) out.add(f.sourceDoc);
    }
    return out;
  }

  /// Every part model this session holds — open in a tab, or shared by an
  /// assembly / a derived part. One place, so the three walks below cannot
  /// disagree about what "loaded" means.
  Iterable<PartModel> get _loadedParts sync* {
    yield* parts.values;
    for (final e in _componentModels.entries) {
      // A document open in a tab lives in `parts`; the shared map may still
      // hold the same object mid-transfer, and yielding it twice would
      // rebuild it twice.
      if (!parts.containsKey(e.key)) yield e.value;
    }
  }

  Iterable<DeriveFeature> _loadedDeriveFeatures() sync* {
    for (final p in _loadedParts) {
      for (final f in p.features) {
        if (f is DeriveFeature) yield f;
      }
    }
  }

  /// Points every occurrence of every open assembly at the current model for
  /// its source.
  ///
  /// Cheap and idempotent — it assigns references — so it is called after
  /// anything that can change where a model lives rather than being reasoned
  /// about case by case. That is the whole point: there is no path by which a
  /// component can be left holding a stale model, because nothing has to
  /// remember to update one.
  void linkOccurrences() {
    void link(AssemblyModel a, Set<String> seen) {
      for (final o in a.occurrences) {
        if (o.isSubAssembly) {
          // The GUARD is against a document edited by hand into a cycle, not
          // against anything the app can produce — placeComponent refuses to
          // create one. Without it a cycle would recurse until the stack ran
          // out, which is a crash on open rather than a bad drawing.
          o.part = null;
          o.sub = seen.contains(o.source) ? null : _sourceAssembly(o.source);
          final child = o.sub;
          if (child != null && seen.add(o.source)) {
            link(child, seen);
            seen.remove(o.source);
          }
        } else {
          o.sub = null;
          o.part = _sourceModel(o.source);
        }
      }
    }

    // M255 — a DERIVED body is pointed at its origin here for the same
    // reason, and by the same argument: assigning a reference is cheap, so it
    // happens at every point where a model can have moved rather than being
    // reasoned about case by case. Null when the origin is not loaded (or is
    // gone), which the feature reports honestly instead of drawing what it
    // last saw.
    for (final f in _loadedDeriveFeatures()) {
      f.source = _sourceModel(f.sourceDoc);
    }
    for (final a in assemblies.values) {
      link(a, {a.name});
      // M247 — the geometry a work feature was built from has just been
      // (re)attached, and with M245's live link it may be a part that was
      // edited in its own tab since. Re-deriving here is what makes a work
      // plane on a face follow that face across a part edit, and it is the
      // same reason the solve calls it: a work feature is a function of its
      // inputs, so every point where the inputs can have changed re-runs it.
      _resolveAsmWorkFeatures(a);
    }
  }

  /// M255 — re-reads every derived body in the session, and says how many
  /// parts actually changed.
  ///
  /// The counterpart to [linkOccurrences]: that one says WHERE the origin is,
  /// this one goes and reads it. Separate on purpose — linking is a reference
  /// assignment and is called everywhere; this runs the kernel and is called
  /// at the three moments a stale derived body could be SEEN (a part tab
  /// opening, an assembly tab opening, and an edit to any part).
  ///
  /// Cheap when nothing moved. The fold's build signature carries the origin
  /// body's identity ([DeriveFeature.sourceKey]), so an unchanged origin makes
  /// every feature here a cache hit and no B-Rep is copied.
  int refreshDerived() {
    final changed = <String>{};
    // To a FIXED POINT, because a derived part can itself be derived from —
    // Make Part run on a derived body is a chain, and Inventor allows it. The
    // walk below is in map order, not dependency order, so a single pass can
    // read a link that the same pass is about to change; the next pass sees
    // it. Bounded so that a document hand-edited into a cycle stops rather
    // than spins, and cheap because a pass that changes nothing is entirely
    // cache hits.
    for (var pass = 0; pass < 8; pass++) {
      var moved = 0;
      for (final p in _loadedParts.toList()) {
        final derived = [for (final f in p.features) if (f is DeriveFeature) f];
        if (derived.isEmpty) continue;
        final before = [for (final f in derived) identityHashCode(f.solid)];
        // M182 — projections only after a SUCCESSFUL recompute, exactly as
        // every other rebuild in this file does it.
        if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
        for (var i = 0; i < derived.length; i++) {
          if (identityHashCode(derived[i].solid) == before[i]) continue;
          moved++;
          changed.add(p.name);
          break;
        }
      }
      if (moved == 0) break;
    }
    if (changed.isNotEmpty) {
      Log.i('part', 'derived bodies re-read: ${changed.join(", ")}');
    }
    return changed.length;
  }

  /// Loads whatever the open assemblies place and is not loaded yet, then
  /// links. Awaited, because a component with no geometry draws as a missing
  /// part and one frame of that is a flicker.
  /// Loops rather than recurses: loading a subassembly can reveal documents
  /// IT places, so the pass repeats until nothing new appears. Bounded by the
  /// number of documents, and the tried-set makes a hand-edited cycle
  /// terminate rather than spin.
  Future<void> _loadPlacedSources() async {
    final tried = <String>{};
    for (var pass = 0; pass < 32; pass++) {
      final want = _placedSources().difference(tried);
      if (want.isEmpty) break;
      for (final name in want) {
        tried.add(name);
        final doc = _findDoc(name);
        if (doc?.isAssembly == true) {
          if (_sourceAssembly(name) != null) continue;
          try {
            _componentAssemblies[name] = await _loadAssemblyModel(name);
          } catch (e, st) {
            Log.e('asm', 'could not load subassembly "$name"', e, st);
          }
        } else if (doc?.isPart == true) {
          if (_sourceModel(name) != null) continue;
          try {
            _componentModels[name] = await _loadPartModel(name);
          } catch (e, st) {
            Log.e('asm', 'could not load part "$name"', e, st);
          }
        }
      }
      linkOccurrences(); // so the next pass can see into what just loaded
    }
    linkOccurrences();
  }

  /// M245 — follows a part RENAME through every assembly that places it.
  ///
  /// An occurrence names its source by document name, so without this a
  /// rename would orphan every component of that part — the assembly keeps
  /// its rows and draws nothing, which is the same failure as the part having
  /// been deleted and is not what a rename means.
  ///
  /// Open assemblies are re-pointed in memory. The ones on disk are rewritten
  /// in place, because a link that only survives while the document happens
  /// to be open is not a link. They are small JSON files and there are as
  /// many of them as the gallery shows, so this is a handful of reads.
  Future<void> _renameSourceInAssemblies(String from, String to) async {
    for (final a in assemblies.values) {
      var touched = false;
      for (var i = 0; i < a.occurrences.length; i++) {
        final o = a.occurrences[i];
        if (o.source != from) continue;
        // The id carries the source name ("Bracket:1"), so it moves too —
        // otherwise the browser would go on calling it by the old name and
        // the next occurrence placed would collide with it.
        a.rename(o, '$to:${o.id.substring(from.length + 1)}', to);
        touched = true;
      }
      if (touched) {
        a.bump();
        unawaited(saveAssembly(a.name));
      }
    }
    for (final name in library.keys.toList()) {
      if (library[name]?.isAssembly != true) continue;
      if (assemblies.containsKey(name)) continue; // handled above, in memory
      try {
        _ensureStaged(name);
        final f = _assemblyJson(name);
        if (!f.existsSync()) continue;
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        var touched = false;
        for (final raw in (j['occurrences'] as List? ?? const [])) {
          if (raw is! Map) continue;
          if (raw['src'] != from) continue;
          raw['src'] = to;
          final id = raw['id'];
          if (id is String && id.startsWith('$from:')) {
            raw['id'] = '$to:${id.substring(from.length + 1)}';
          }
          touched = true;
        }
        if (!touched) continue;
        // The constraints name occurrences too, and a relationship pointing
        // at an id that no longer exists is a constraint the solver reports
        // sick for ever.
        for (final raw in (j['constraints'] as List? ?? const [])) {
          if (raw is! Map) continue;
          for (final key in const ['a', 'b', 'c']) {
            final ref = raw[key];
            if (ref is! Map) continue;
            final occ = ref['occ'];
            if (occ is String && occ.startsWith('$from:')) {
              ref['occ'] = '$to:${occ.substring(from.length + 1)}';
            }
          }
        }
        f.writeAsStringSync(jsonEncode(j));
        _commitStage(name, kAssemblyDocKind);
      } catch (e, st) {
        Log.e('asm', 'could not re-point "$name" after a rename', e, st);
      }
    }
  }

  /// Frees the shared models nothing places any more.
  ///
  /// Called when an assembly closes. A model that is ALSO open in a tab is
  /// not ours to free — it lives in `parts` / `assemblies` and these maps do
  /// not hold it.
  void _evictUnplacedSources() {
    // M255 — to a FIXED POINT, because the wanted set shrinks as it goes: a
    // derived part keeps its origin loaded (see _placedSources), so freeing
    // the derived part is what makes the origin free-able. One pass would
    // leave the origin behind until the next assembly happened to close,
    // which for a session that never closes another one is for ever.
    //
    // Bounded by the number of loaded documents — each pass frees at least
    // one or stops.
    for (var pass = 0; pass < 32; pass++) {
      final want = _placedSources();
      var freed = 0;
      for (final name in _componentModels.keys.toList()) {
        if (want.contains(name)) continue;
        _componentModels.remove(name)?.dispose();
        freed++;
      }
      for (final name in _componentAssemblies.keys.toList()) {
        if (want.contains(name)) continue;
        _componentAssemblies.remove(name)?.dispose();
        freed++;
      }
      if (freed == 0) return;
    }
  }

  /// The assemblies [name] places DIRECTLY, read from the document.
  ///
  /// From the loaded model when there is one, and from the file otherwise.
  /// The file matters: the containment question is about documents, not about
  /// what happens to be open, and an assembly two steps away in the chain is
  /// very often closed.
  Set<String> _directlyNests(String name) {
    final loaded = _sourceAssembly(name);
    if (loaded != null) {
      return {
        for (final o in loaded.occurrences)
          if (o.isSubAssembly) o.source
      };
    }
    try {
      if (_findDoc(name)?.isAssembly != true) return const {};
      _ensureStaged(name);
      final f = _assemblyJson(name);
      if (!f.existsSync()) return const {};
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final raw in (j['occurrences'] as List? ?? const []))
          if (raw is Map && raw['kind'] == kAssemblyDocKind)
            if (raw['src'] is String) raw['src'] as String
      };
    } catch (e, st) {
      Log.e('asm', 'could not read the nesting of "$name"', e, st);
      return const {};
    }
  }

  /// True when placing [source] into [into] would make an assembly contain
  /// itself, directly or through any chain of subassemblies.
  ///
  /// Inventor refuses this and so does everything else that can: a cyclic
  /// containment has no geometry — the recursion that draws it never ends —
  /// so there is nothing to show and no error the user could act on later.
  /// It is refused at the one moment it can be explained, which is now.
  ///
  /// Walks the DOCUMENTS rather than the loaded models. A chain is usually
  /// only half open: placing B into A is fine, placing A into B is a cycle,
  /// and at that moment A is very often just a file.
  bool _wouldNestCycle(AssemblyModel into, String source) {
    if (source == into.name) return true;
    final seen = <String>{source};
    final queue = <String>[source];
    while (queue.isNotEmpty) {
      for (final next in _directlyNests(queue.removeLast())) {
        if (next == into.name) return true;
        if (seen.add(next)) queue.add(next);
      }
    }
    return false;
  }

  Future<bool> saveAssembly(String name) async {
    final a = assemblies[name];
    if (a == null || _docsDir == null) return false;
    _ensureStaged(name);
    try {
      _assemblyJson(name).writeAsStringSync(jsonEncode(a.toJson()));
    } catch (e, st) {
      Log.e('asm', 'save "$name" failed', e, st);
      return false;
    }
    await _writeAssemblyPreview(name, a);
    if (!_commitStage(name, kAssemblyDocKind)) return false;
    await refreshSaved();
    notifyListeners();
    return true;
  }

  /// The gallery still for an assembly.
  ///
  /// M241 — the SAME engine the part's still uses, and for the same reason:
  /// one renderer means the card and the live viewport cannot disagree. The
  /// off-screen ARView is handed each component's placement beside its mesh,
  /// exactly as the viewport is; the CPU painter stays as the fallback for a
  /// host run or an older iOS.
  Future<void> _writeAssemblyPreview(String name, AssemblyModel a) async {
    final png = _pngFile(name);
    try {
      final pieces = [
        for (final (id, _, at, s) in assemblyPieces(a)) (id, s, at)
      ];
      // M272 — built from the SAME walk, so a piece and its appearance cannot
      // drift apart. Matching an id back to an occurrence by prefix would work
      // today and break the first time a piece path changes shape.
      final pieceTint = {
        for (final (id, o, _, _) in assemblyPieces(a))
          id: materialArgb(o.material) ?? kNoTint
      };
      if (pieces.isEmpty) {
        if (png.existsSync()) png.deleteSync();
        return;
      }
      const w = 380.0, h = 240.0;
      const size = Size(w, h);
      final placed = placedComponents(a);
      final cam = fitAssemblyThumbCamera(placed, size);

      // M237 — a TRANSPARENT ground: the card paints its own surface behind
      // the PNG, so a still written in one scheme still looks right in the
      // other and a palette switch invalidates no cached file.
      final shot = await RealityThumbnailer.render(
        // M272 — and each component's own appearance.
        scene: buildPlacedThumbScenePayload(pieces,
            tintOf: (id) => pieceTint[id] ?? kNoTint),
        camera: cameraPayload(cam, size),
        width: w.toInt(),
        height: h.toInt(),
      );
      if (shot != null && shot.isNotEmpty) {
        // M272 — the same check the part's still gets (M269). It was fitted to
        // one of the two writers and not the other, which is exactly how a
        // cream card comes back on an assembly six weeks from now.
        await png.writeAsBytes(await demattePng(shot) ?? shot);
        return;
      }

      // Fallback: CPU painter, same camera.
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
      final mats = placedMaterials(a);
      paintAssemblySolids(canvas, Cam3(cam, size), placed, materialOf: (i) {
        final argb = materialArgb(mats[i]);
        return argb == null ? null : Color(argb);
      });
      final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        await png.writeAsBytes(bytes.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint('assembly preview write failed: $e');
    }
  }

  // ---- placing components -------------------------------------------------

  /// M240 — Place Component. The ONE assembly command that is wired.
  ///
  /// Loads [source]'s geometry, sets it down clear of what is already there
  /// and selects it. The first component of an assembly is GROUNDED, exactly
  /// as Inventor grounds the first one it places: an assembly needs something
  /// to be built against, and a free-floating first component would drift
  /// under the very drag this milestone adds.
  ///
  /// M250 — [at] places it SOMEWHERE PARTICULAR instead, which is what Create
  /// Component needs: the new part goes on the plane you picked, not clear of
  /// everything else. The reframe goes with it — a placement the user aimed
  /// is already where they are looking, and Zoom All would throw that away.
  Future<AssemblyOccurrence?> placeComponent(String source,
      {Placement? at}) async {
    final a = currentAssembly;
    if (a == null) return null;
    // M246 — a subassembly is placed by the same command, which is Inventor's
    // Place Component exactly: one button, and what you pick decides.
    final asSub = isAssemblyName(source);
    if (!asSub && !isPartName(source)) {
      toast(L.current.msgAsmNoSuchPart(source));
      return null;
    }
    if (asSub && _wouldNestCycle(a, source)) {
      toast(L.current.msgAsmWouldNest(source));
      return null;
    }
    // M245 — the SHARED model, loaded once per document. Placing something
    // that is already open in a tab, or already placed elsewhere, costs
    // nothing and links to the very object being edited.
    if (asSub) {
      if (_sourceAssembly(source) == null) {
        try {
          _componentAssemblies[source] = await _loadAssemblyModel(source);
        } catch (e, st) {
          Log.e('asm', 'could not load subassembly "$source"', e, st);
        }
      }
    } else if (_sourceModel(source) == null) {
      try {
        _componentModels[source] = await _loadPartModel(source);
      } catch (e, st) {
        Log.e('asm', 'could not load part "$source"', e, st);
      }
    }
    final part = asSub ? null : _sourceModel(source);
    final sub = asSub ? _sourceAssembly(source) : null;
    if (part == null && sub == null) {
      toast(L.current.msgAsmCouldNotPlace(source));
      return null;
    }
    final occ = AssemblyOccurrence(
      id: a.nextOccurrenceId(source),
      source: source,
      sourceKind: asSub ? kAssemblyDocKind : 'part',
      part: part,
      sub: sub,
      grounded: a.occurrences.isEmpty,
    );
    if (at != null) {
      occ.offset = at.at;
      occ.rot = at.rot;
      occ.reflect = at.reflect;
    } else {
      occ.offset = nextPlacement(a, occurrenceBounds(occ));
    }
    a.occurrences.add(occ);
    a.selected = occ;
    // A subassembly's own components have to be resolved too — it may place
    // parts nothing else in this session has loaded.
    if (asSub) await _loadPlacedSources();
    a.bump();
    // Inventor runs Zoom All when a component is placed, and it has to here:
    // a placement lands CLEAR of what is already there (see nextPlacement), so
    // without reframing, the second component of a large assembly arrives off
    // the edge of the screen and the command looks like it did nothing.
    //
    // NOT for a placement the caller aimed: that one landed where the user
    // pointed, so it is already on screen, and reframing would move the view
    // out from under the plane they had just chosen.
    if (at == null) a.needsFit = true;
    notifyListeners();
    unawaited(saveAssembly(a.name));
    return occ;
  }

  void selectOccurrence(AssemblyOccurrence? occ) {
    final a = currentAssembly;
    if (a == null || identical(a.selected, occ)) return;
    a.selected = occ;
    notifyListeners();
  }

  /// Called when a component drag finishes, so the new placement is persisted
  /// once rather than on every frame of the drag.
  void endOccurrenceDrag() {
    final a = currentAssembly;
    if (a == null) return;
    // M241 — the drag itself never bumped the generation (a placement rides
    // the light RealityKit push). Now that it has settled, tick it once so the
    // origin planes and axes, which are sized to the assembly's contents,
    // catch up with where the component ended.
    //
    // notifyListeners is what makes that tick reach the renderer: the last
    // frame of the drag already rebuilt the viewport, and without this nothing
    // would ask it to again until the user touched something else — the planes
    // would sit at the old extent for as long as the assembly was left alone.
    a.bump();
    // M250 — a Free Move leaves a related component where its relationships
    // say it does not belong. Saying so is the difference between Inventor's
    // documented behaviour and a drag that looks like it did not take.
    final moved = _dragOccId;
    if (moved != null) _warnFreePositioned(a, moved);
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  void setOccurrenceVisible(AssemblyOccurrence occ, bool on) {
    occ.visible = on;
    currentAssembly?.bump();
    notifyListeners();
  }

  void setOccurrenceGrounded(AssemblyOccurrence occ, bool on) {
    occ.grounded = on;
    currentAssembly?.bump();
    notifyListeners();
    final a = currentAssembly;
    if (a != null) unawaited(saveAssembly(a.name));
  }

  void deleteOccurrence(AssemblyOccurrence occ) {
    final a = currentAssembly;
    if (a == null) return;
    a.remove(occ);
    a.bump();
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  /// Origin plane / axis / centre-point visibility in the assembly browser.
  void setAssemblyOriginVisible(String key, bool on) {
    final a = currentAssembly;
    if (a == null || !a.vis.containsKey(key)) return;
    a.vis[key] = on;
    a.bump();
    notifyListeners();
  }

  // ---- M242: RELATIONSHIPS -------------------------------------------------
  //
  // Place Constraint, the browser's Relationships folder, and the solve that
  // both of them stand on. The division of labour:
  //
  //   asm_pick.dart    a tap -> an AsmRef (geometry in the component's frame)
  //   asm_solver.dart  the constraints -> where every component ends up
  //   here            the COMMANDS: open, collect, preview, apply, edit,
  //                   suppress, delete, and the drag that goes through the
  //                   solver instead of round it
  //
  // The one design decision worth stating up front is the PREVIEW. Inventor
  // shows the result of a constraint before you commit it, and undoes it if
  // you cancel. That means the document's placements are, while the dialog is
  // open, not the committed ones — so a snapshot is taken when the dialog
  // opens and restored on cancel. Nothing else in the app moves geometry it
  // has not committed, which is exactly why it is written down here.

  ConstraintSession? constraintSession;

  /// True while Place Constraint is collecting selections, so the viewport
  /// picks GEOMETRY instead of components and the ribbon button stays lit.
  bool get constraintPicking => constraintSession != null;

  /// Inventor's "Default to Undirected", remembered across dialogs.
  bool defaultUndirectedAngle = false;

  /// The committed placements, taken when the dialog opens. See the note
  /// above: a preview moves the real occurrences, and Cancel has to be able
  /// to put them back exactly.
  Map<String, (Vec3, Quat)>? _asmSnapshot;

  /// Highlighted in the viewport while the dialog collects: every filled
  /// slot, in WORLD coordinates and ready to draw.
  List<AsmMark> get constraintMarkers {
    final s = constraintSession, a = currentAssembly;
    if (s == null || a == null) return const [];
    return [
      for (var i = 0; i < s.needed; i++)
        if (s.slot(i) != null) markFor(a, s.slot(i)!)
    ];
  }

  /// M247 — what the ASSEMBLY command that is currently collecting has taken,
  /// ready to draw.
  ///
  /// One list for both commands because at most one of them is ever armed:
  /// openConstraint and the work-feature commands cancel each other, for the
  /// same reason the three work-feature commands cancel each other. The
  /// viewport therefore draws "the current selection" rather than having to
  /// know which command made it.
  List<AsmMark> get asmMarkers {
    final a = currentAssembly;
    if (a == null) return const [];
    if (asmPickWorkGeometry) {
      return [for (final r in _asmWfPicks) markFor(a, r)];
    }
    return constraintMarkers;
  }

  /// One stored reference, ready to draw.
  ///
  /// The size comes from the COMPONENT the reference is on, not from the
  /// assembly: a marker sized to the whole document swallows a small part and
  /// disappears on a big one. A reference to the assembly's own origin has no
  /// component, so it takes the assembly's extent — which is the right answer
  /// there, since the origin planes are drawn to that extent too.
  AsmMark markFor(AssemblyModel a, AsmRef r) {
    final geom = worldGeomOf(a, r);
    final o = r.isAssemblyOrigin ? null : a.byId(r.occurrence);
    final anchor = worldAnchorOf(a, r);
    // The picked FACE's own size when the pick could measure it, which is
    // what makes the highlight mean "this face" rather than "somewhere on
    // this part". The component's extent is the fallback: the assembly's own
    // origin geometry has no face, and a document written before the pick
    // recorded one carries no extent.
    if (r.extent > 0) return AsmMark(geom, anchor, r.extent);
    final b = o == null ? assemblyContentBounds(a) : occurrenceBounds(o);
    final span = b == null ? 20.0 : (b.$2 - b.$1).length;
    return AsmMark(geom, anchor, math.max(2.0, span * 0.22));
  }

  /// Opens Place Constraint. With [edit] it opens on that constraint, filled
  /// in, which is Inventor's double-click-a-relationship behaviour.
  void openConstraint({AsmConstraint? edit}) {
    final a = currentAssembly;
    if (a == null) return;
    // M249 — a running DRIVE is moving components on a timer, and this dialog
    // is about to snapshot their placements and preview against them. Two
    // authorities over one placement is the failure asm_solver documents for
    // pattern elements; closing the drive first is the same rule applied to
    // two dialogs. openDrive does the reverse.
    if (driveSession != null) closeDrive();
    final s = ConstraintSession(editing: edit);
    if (edit != null) {
      s.kind = edit.kind;
      s.tab = tabOf(edit.kind);
      s.solution = edit.solution;
      s.a = edit.a;
      s.b = edit.b;
      s.c = edit.c;
      s.value = edit.value;
      s.name = edit.name;
      s.armed = 0;
    } else if (defaultUndirectedAngle) {
      s.defaultUndirected = true;
    }
    // M250 — and Free Move / Free Rotate, which are armed commands like any
    // other: a tap meant for a constraint selection must not move the
    // component instead.
    cancelAsmPosition();
    constraintSession = s;
    _takeAsmSnapshot(a);
    _refreshConstraintPreview();
    notifyListeners();
  }

  /// M249 — opens PLACE JOINT. With [edit] it opens on that joint, filled in.
  ///
  /// The same session as Place Constraint, on [AsmTab.joint] — see
  /// [ConstraintSession.jointType]. Which means every command that already
  /// knows how to feed the constraint dialog (the viewport's tap routing, the
  /// marker drawing, Apply, Cancel and the snapshot) feeds this one without
  /// being told it exists.
  void openJoint({AsmConstraint? edit}) {
    final a = currentAssembly;
    if (a == null) return;
    if (driveSession != null) closeDrive(); // see openConstraint
    // M250 — and the two Position commands and Create Component, which are
    // armed states waiting for the same taps this dialog is about to collect.
    cancelAsmPosition();
    cancelCreateComponent();
    final s = ConstraintSession(editing: edit);
    s.tab = AsmTab.joint;
    if (edit != null && edit.isJoint) {
      s.jointType = jointTypeOf(edit.kind);
      s.kind = edit.kind;
      s.solution = edit.solution;
      s.a = edit.a;
      s.b = edit.b;
      s.value = edit.value;
      s.name = edit.name;
    } else {
      // Inventor opens on Automatic, and it is the right default: it is the
      // entry that makes ONE pick pair enough, which is the whole point of the
      // command. Rigid is what Automatic falls back to with nothing picked, so
      // that is what `kind` reads until the second selection lands.
      s.jointType = AsmJointType.automatic;
      s.kind = AsmKind.jointRigid;
      s.solution = solutionsFor(s.kind).first;
    }
    constraintSession = s;
    _takeAsmSnapshot(a);
    _refreshConstraintPreview();
    notifyListeners();
  }

  /// Chooses a joint type in the Place Joint dialog.
  void setJointType(AsmJointType type) {
    final s = constraintSession;
    if (s == null || !s.isJoint || s.jointType == type) return;
    s.jointType = type;
    final fixed = jointKindOf(type);
    // Automatic has no kind of its own: it is re-derived from the picks below.
    if (fixed != null) {
      s.kind = fixed;
      if (!solutionsFor(fixed).contains(s.solution)) {
        s.solution = solutionsFor(fixed).first;
      }
    }
    _resolveAutomaticJointKind(s);
    _checkConstraintPair(s);
    _refreshConstraintPreview();
    notifyListeners();
  }

  /// Re-runs Inventor's Automatic rule over the current pair.
  ///
  /// Called after every pick and after every type change, so the dialog is
  /// never showing a type the picks no longer imply. A no-op unless Automatic
  /// is the chosen type.
  void _resolveAutomaticJointKind(ConstraintSession s) {
    final a = currentAssembly;
    if (a == null || !s.isJoint) return;
    if (s.jointType != AsmJointType.automatic) return;
    if (s.a == null || s.b == null) {
      s.kind = AsmKind.jointRigid;
      return;
    }
    s.kind = resolveAutomaticJoint(worldGeomOf(a, s.a!), worldGeomOf(a, s.b!));
    if (!solutionsFor(s.kind).contains(s.solution)) {
      s.solution = solutionsFor(s.kind).first;
    }
  }

  /// The twist a joint of [kind] would capture from the pair in [s], or null
  /// when the type leaves the rotation about its axis free.
  ///
  /// Read from where the components CURRENTLY are, which is the whole point:
  /// see [AsmConstraint.twist]. Callers must have restored the placement
  /// snapshot first, or a Rigid joint would capture the twist of its own
  /// preview rather than of the assembly.
  double? _capturedTwist(AssemblyModel a, AsmKind kind, AsmRef ra, AsmRef rb) {
    if (!isJointKind(kind) || !jointLocks(kind).twist) return null;
    final fa = worldJointFrameOf(a, ra);
    final fb = worldJointFrameOf(a, rb);
    if (!fa.hasAxis || !fb.hasAxis) return null;
    return jointTwistBetween(fa.ref, fb.ref, fa.axis);
  }

  /// Cancel: the preview is undone and nothing is written.
  void cancelConstraint() {
    if (constraintSession == null) return;
    _restoreAsmSnapshot();
    constraintSession = null;
    final a = currentAssembly;
    if (a != null) {
      a.bump();
      _solveAssembly(a);
    }
    notifyListeners();
  }

  void setConstraintTab(AsmTab tab) {
    final s = constraintSession;
    if (s == null || s.tab == tab) return;
    s.tab = tab;
    // Each tab opens on its own first type, the way Inventor's does. The
    // Constraint Set tab has no types at all yet and keeps whatever was
    // selected, so switching to it and back does not discard the picks.
    final kinds = switch (tab) {
      AsmTab.assembly => kAssemblyKinds,
      AsmTab.motion => kMotionKinds,
      AsmTab.transitional => const [AsmKind.transitional],
      AsmTab.constraintSet => const <AsmKind>[],
      // M249 — not one of Place Constraint's tabs; the Joint dialog owns it,
      // and it is reached through [openJoint] rather than through this switch.
      AsmTab.joint => kJointKinds,
    };
    if (kinds.isNotEmpty && !kinds.contains(s.kind)) {
      _applyKind(s, kinds.first);
    }
    notifyListeners();
  }

  void setConstraintKind(AsmKind kind) {
    final s = constraintSession;
    if (s == null || s.kind == kind) return;
    _applyKind(s, kind);
    _refreshConstraintPreview();
    notifyListeners();
  }

  void _applyKind(ConstraintSession s, AsmKind kind) {
    s.kind = kind;
    s.tab = tabOf(kind);
    final sols = solutionsFor(kind);
    // Inventor's Default to Undirected, and the only place it acts: a NEW
    // Angle opens on Undirected rather than on the directed default.
    s.solution = (kind == AsmKind.angle && defaultUndirectedAngle)
        ? AsmSolution.undirectedAngle
        : sols.first;
    // Changing the type keeps the picks — pointing at the same two faces and
    // trying Flush instead of Mate is the commonest thing a user does — but
    // the third slot belongs to a solution that may no longer exist.
    if (s.needed < 3) s.c = null;
    // The field opens on the kind's own neutral value, which is zero for a
    // distance and ONE for a ratio: a gear pair of 0:1 is not a gear pair, and
    // Inventor opens Rotation on 1 for exactly that reason.
    s.value = valueKindOf(kind) == AsmValueKind.ratio ? 1 : 0;
    s.armed = s.firstEmpty < 0 ? 0 : s.firstEmpty;
    _checkConstraintPair(s);
  }

  void setConstraintSolution(AsmSolution sol) {
    final s = constraintSession;
    if (s == null || s.solution == sol) return;
    if (!solutionsFor(s.kind).contains(sol)) return;
    s.solution = sol;
    if (s.needed < 3) s.c = null;
    _refreshConstraintPreview();
    notifyListeners();
  }

  void setConstraintValue(double v) {
    final s = constraintSession;
    if (s == null || s.value == v) return;
    s.value = v;
    _refreshConstraintPreview();
    notifyListeners();
  }

  void setConstraintName(String name) {
    final s = constraintSession;
    if (s == null) return;
    s.name = name;
    notifyListeners();
  }

  /// Lights selection button [i], so the next viewport tap fills that slot.
  /// Tapping the lit one again CLEARS it, which is how Inventor lets you
  /// re-pick a selection you got wrong.
  void armConstraintSelection(int i) {
    final s = constraintSession;
    if (s == null || i < 0 || i >= s.needed) return;
    if (s.armed == i && s.slot(i) != null) {
      s.setSlot(i, null);
      _resolveAutomaticJointKind(s);
      _checkConstraintPair(s);
      _refreshConstraintPreview();
      notifyListeners();
      return;
    }
    s.armed = i;
    notifyListeners();
  }

  void toggleConstraintPreview() {
    final s = constraintSession;
    if (s == null) return;
    s.showPreview = !s.showPreview;
    _refreshConstraintPreview();
    notifyListeners();
  }

  /// Inventor's "Predict Offset and Orientation": fill the value field with
  /// what the two selections already measure, so applying the constraint
  /// holds the parts where they are instead of closing them up.
  void toggleConstraintPredict() {
    final s = constraintSession;
    final a = currentAssembly;
    if (s == null || a == null) return;
    s.predict = !s.predict;
    if (s.predict && s.a != null && s.b != null) {
      final v = predictedValue(s.kind, s.solution, worldGeomOf(a, s.a!),
          worldGeomOf(a, s.b!));
      if (v != null) s.value = v;
    }
    _refreshConstraintPreview();
    notifyListeners();
  }

  void toggleConstraintPickPartFirst() {
    final s = constraintSession;
    if (s == null) return;
    s.pickPartFirst = !s.pickPartFirst;
    notifyListeners();
  }

  void toggleConstraintExpanded() {
    final s = constraintSession;
    if (s == null) return;
    s.expanded = !s.expanded;
    notifyListeners();
  }

  void toggleDefaultUndirected() {
    final s = constraintSession;
    if (s == null) return;
    s.defaultUndirected = !s.defaultUndirected;
    defaultUndirectedAngle = s.defaultUndirected;
    notifyListeners();
  }

  /// A viewport tap while the dialog is open. Returns true when it was
  /// consumed as a selection, so the viewport knows not to also treat it as a
  /// component pick.
  bool pickConstraintRef(AsmPick pick) {
    final s = constraintSession;
    final a = currentAssembly;
    if (s == null || a == null) return false;
    // Inventor refuses the SECOND selection on the component the first came
    // from: a constraint between two faces of one part constrains nothing and
    // is the commonest misclick there is.
    if (s.armed > 0 &&
        s.a != null &&
        !pick.ref.isAssemblyOrigin &&
        pick.ref.occurrence == s.a!.occurrence &&
        s.armed == 1) {
      toast(L.current.msgAsmSameComponent);
      return true;
    }
    s.setSlot(s.armed, pick.ref);
    final next = s.firstEmpty;
    s.armed = next < 0 ? s.armed : next;
    // M249 — Automatic decides from the ORIGINS, so it can only decide once
    // they have both been pointed at. Before the rejection check, because what
    // the pair is allowed to be depends on the type it just resolved to.
    _resolveAutomaticJointKind(s);
    _checkConstraintPair(s);
    // Predict runs on the pair, so it can only fire once the second selection
    // has landed.
    if (s.predict && s.a != null && s.b != null) {
      final v = predictedValue(s.kind, s.solution, worldGeomOf(a, s.a!),
          worldGeomOf(a, s.b!));
      if (v != null) s.value = v;
    }
    _refreshConstraintPreview();
    notifyListeners();
    return true;
  }

  /// Records why the current pair cannot take this kind, for the dialog to
  /// show where Inventor shows its own refusal.
  void _checkConstraintPair(ConstraintSession s) {
    final a = currentAssembly;
    if (a == null || s.a == null || s.b == null) {
      s.rejection = null;
      return;
    }
    s.rejection =
        rejectionFor(s.kind, worldGeomOf(a, s.a!), worldGeomOf(a, s.b!));
  }

  /// The constraint the session currently describes, or null when it is not
  /// yet a constraint (a slot empty, or a pair this kind cannot act on).
  AsmConstraint? buildSessionConstraint(AssemblyModel a) {
    final s = constraintSession;
    if (s == null || !s.complete) return null;
    if (_checkedRejection(s, a) != null) return null;
    var third = s.c;
    // A DIRECTED angle captures its reference vector when it is created, and
    // keeps it. That is what stops the part flipping to the other side of the
    // pair the first time the angle passes through zero — Autodesk's own
    // reason for offering the undirected solution at all. The reference is
    // stored against the ASSEMBLY, not a component, because it must not turn
    // when either part does.
    if (s.kind == AsmKind.angle &&
        s.solution == AsmSolution.directedAngle &&
        third == null) {
      final z = worldGeomOf(a, s.a!).dir.cross(worldGeomOf(a, s.b!).dir);
      if (z.length > 1e-9) {
        third = AsmRef(kAssemblyOrigin,
            AsmGeom.axis(Vec3.zero, z.normalized()), 'Reference Vector');
      }
    }
    final name = s.name.trim().isNotEmpty
        ? s.name.trim()
        : (s.editing?.name ?? nextConstraintName(a.constraints, s.kind));
    return AsmConstraint(
      name: name,
      kind: s.kind,
      solution: s.solution,
      a: s.a!,
      b: s.b!,
      c: s.needed >= 3 ? s.c : third,
      value: s.value,
      suppressed: s.editing?.suppressed ?? false,
    )
      // M249 — a Rigid or Slider joint holds the rotation about its own axis
      // at whatever the components already stood at. Captured HERE, from the
      // model, because this is the one method both the preview and the commit
      // go through and both must produce the same joint.
      ..twist = _capturedTwist(a, s.kind, s.a!, s.b!);
  }

  String? _checkedRejection(ConstraintSession s, AssemblyModel a) {
    if (s.a == null || s.b == null) return null;
    return rejectionFor(s.kind, worldGeomOf(a, s.a!), worldGeomOf(a, s.b!));
  }

  /// Shows what the constraint WOULD do, without committing it.
  ///
  /// Always from the snapshot, never from wherever the last preview left
  /// things: solving twice from a previewed state would let a preview build
  /// on itself and drift.
  void _refreshConstraintPreview() {
    final a = currentAssembly;
    final s = constraintSession;
    if (a == null || s == null) return;
    _restoreAsmSnapshot();
    if (!s.showPreview) {
      _solveAssembly(a);
      return;
    }
    final trial = buildSessionConstraint(a);
    if (trial == null) {
      _solveAssembly(a);
      return;
    }
    // While editing, the constraint being replaced must not fight its own
    // replacement.
    final edited = s.editing;
    final was = edited?.suppressed;
    if (edited != null) edited.suppressed = true;
    a.constraints.add(trial);
    _solveAssembly(a);
    a.constraints.remove(trial);
    if (edited != null && was != null) edited.suppressed = was;
  }

  /// Apply: commit the constraint and keep the dialog open for the next one,
  /// which is what makes placing six mates in a row bearable.
  bool applyConstraint() {
    final a = currentAssembly;
    final s = constraintSession;
    if (a == null || s == null) return false;
    if (!s.complete) {
      toast(L.current.msgAsmPickTwo);
      return false;
    }
    final reason = _checkedRejection(s, a);
    if (reason != null) {
      toast(_constraintRejection(reason));
      return false;
    }
    _restoreAsmSnapshot();
    final built = buildSessionConstraint(a);
    if (built == null) return false;
    final edited = s.editing;
    if (edited != null) {
      edited
        ..kind = built.kind
        ..solution = built.solution
        ..a = built.a
        ..b = built.b
        ..c = built.c
        ..value = built.value
        // M249 — and the captured twist, or editing a Rigid joint's gap would
        // keep the twist the joint was first made with while its geometry
        // moved on. Null for every kind that does not hold one, which is what
        // switching a Rigid joint to Cylindrical has to leave behind.
        ..twist = built.twist;
    } else {
      a.constraints.add(built);
    }
    final report = _solveAssembly(a);
    if (report.sick.containsKey(built.name)) {
      toast(_constraintRejection(report.sick[built.name]!));
    }
    a.bump();
    _takeAsmSnapshot(a);
    // Ready for the next one: the picks are consumed, the settings are not.
    // Inventor keeps the type, the solution and the offset across an Apply,
    // and clears only what you pointed at.
    if (edited == null) {
      s.a = null;
      s.b = null;
      s.c = null;
      s.armed = 0;
      s.rejection = null;
    }
    notifyListeners();
    unawaited(saveAssembly(a.name));
    return true;
  }

  /// OK: apply, then close.
  void okConstraint() {
    final s = constraintSession;
    if (s == null) return;
    // OK on a dialog that has collected nothing is a Cancel — Inventor greys
    // its OK out in that state, and reaching this from a keyboard should not
    // be able to leave the preview applied.
    if (!s.complete) {
      cancelConstraint();
      return;
    }
    if (!applyConstraint()) return;
    constraintSession = null;
    _asmSnapshot = null;
    notifyListeners();
  }

  // ---- M249: Drive Constraint ---------------------------------------------
  //
  // See [DriveSession] for what a drive IS and for the two kinds of sweep.
  // What lives here is the command surface and the TIMER, which is the half
  // M242 left out: the drive pass has been in asm_solver since then with
  // nothing to step it.

  DriveSession? driveSession;

  /// The stepping timer. Never outlives the session: [closeDrive] cancels it,
  /// and so does [dispose] — a periodic timer left running past a widget test
  /// keeps the whole test binding alive.
  Timer? _driveTimer;

  /// The placements as they were when the dialog opened.
  ///
  /// Separate from [_asmSnapshot], which belongs to Place Constraint: the two
  /// dialogs are modeless and the browser can open Drive while nothing else is
  /// up, but sharing one field would let closing either restore the other's.
  Map<String, (Vec3, Quat)>? _driveSnapshot;

  /// Opens the Drive dialog on [c].
  void openDrive(AsmConstraint c) {
    final a = currentAssembly;
    if (a == null) return;
    if (!canDriveConstraint(c)) {
      toast(L.current.msgAsmCannotDrive);
      return;
    }
    // The two other modeless assembly panels collect from the viewport, and a
    // drive moves components under them; closing them is what Inventor does
    // when a second command starts.
    if (constraintSession != null) cancelConstraint();
    // M250 — and the same for the Position commands and Create Component. A
    // drive moves components on a TIMER, so a Free Move left armed under it
    // would be undone between frames by an animation nothing connected it to.
    cancelAsmPosition();
    cancelCreateComponent();
    final motion = !c.isPositional;
    final s = DriveSession(c, motion: motion, value0: c.value);
    // "In Start, enter the beginning value. The default value is the angle or
    // offset defined for the constraint. In End, enter the ending value. The
    // default is the Start value plus ten." A motion drive has no such value,
    // so it starts where the shaft is — zero degrees turned — and Inventor's
    // +10 becomes one full turn, which is the sweep a gear pair is for.
    s.start = motion ? 0 : c.value;
    s.end = motion ? 360 : c.value + 10;
    s.increment = motion ? 5 : 1;
    driveSession = s;
    _driveSnapshot = {for (final o in a.occurrences) o.id: (o.offset, o.rot)};
    notifyListeners();
  }

  /// Closes the dialog and puts the assembly back where it was.
  ///
  /// A drive is a preview of MOTION, not an edit: Inventor restores the
  /// relationship's value when the dialog closes, and restoring the placements
  /// with it is the same promise kept for the motion sweep, which has no value
  /// to put back.
  void closeDrive() {
    final s = driveSession;
    if (s == null) return;
    _driveTimer?.cancel();
    _driveTimer = null;
    s.constraint.value = s.value0;
    final a = currentAssembly;
    final snap = _driveSnapshot;
    if (a != null && snap != null) {
      for (final o in a.occurrences) {
        final was = snap[o.id];
        if (was == null) continue;
        o.offset = was.$1;
        o.rot = was.$2;
      }
      _solveAssembly(a);
      a.bump();
    }
    driveSession = null;
    _driveSnapshot = null;
    notifyListeners();
  }

  void setDriveField({
    double? start,
    double? end,
    double? increment,
    int? totalSteps,
    double? pauseDelay,
    bool? byTotalSteps,
    bool? roundTrip,
    int? cycles,
  }) {
    final s = driveSession;
    if (s == null) return;
    if (start != null) s.start = start;
    if (end != null) s.end = end;
    if (increment != null) s.increment = increment;
    if (totalSteps != null) s.totalSteps = math.max(1, totalSteps);
    if (pauseDelay != null) s.pauseDelay = pauseDelay.clamp(0.0, 10.0);
    if (byTotalSteps != null) s.byTotalSteps = byTotalSteps;
    if (roundTrip != null) s.roundTrip = roundTrip;
    if (cycles != null) s.cycles = math.max(1, cycles);
    // A changed Pause Delay has to reach a sweep that is already running, or
    // the slider does nothing until the user stops and starts again.
    if (s.playing) _armDriveTimer(s);
    notifyListeners();
  }

  /// Plays the sweep. [reverse] is Inventor's ◀ button: it runs the same
  /// range, from wherever the sweep is, back towards Start.
  void playDrive({bool reverse = false}) {
    final s = driveSession;
    if (s == null) return;
    s.reverse = reverse;
    s.playing = true;
    s.cycle = 0;
    _armDriveTimer(s);
    notifyListeners();
  }

  void pauseDrive() {
    final s = driveSession;
    if (s == null) return;
    s.playing = false;
    _driveTimer?.cancel();
    _driveTimer = null;
    notifyListeners();
  }

  /// Inventor's ⏮ / ⏭ : jump to either end of the range without sweeping.
  void driveToEnd({required bool atEnd}) {
    final s = driveSession;
    if (s == null) return;
    pauseDrive();
    _driveTo(s, atEnd ? 1 : 0);
    notifyListeners();
  }

  void _armDriveTimer(DriveSession s) {
    _driveTimer?.cancel();
    // Floored at one frame: a zero Pause Delay means "as fast as it will go",
    // and a zero-duration periodic timer would starve the frame it is meant to
    // be animating.
    final ms = math.max(16, (s.pauseDelay * 1000).round());
    _driveTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _driveTick());
  }

  void _driveTick() {
    final s = driveSession;
    if (s == null || !s.playing) {
      _driveTimer?.cancel();
      _driveTimer = null;
      return;
    }
    final step = s.phaseStep * (s.reverse ? -1 : 1);
    var next = s.phase + step;
    if (next >= 1 || next <= 0) {
      next = next >= 1 ? 1 : 0;
      _driveTo(s, next);
      if (s.roundTrip) {
        // Start/End/Start: the far end turns the sweep round, and arriving
        // back at the near end is what finishes one repetition.
        if (!s.reverse) {
          s.reverse = true;
        } else {
          s.reverse = false;
          s.cycle++;
        }
      } else {
        s.cycle++;
        if (s.cycle < s.cycles) _driveTo(s, 0);
      }
      if (s.cycle >= s.cycles) {
        pauseDrive();
        return;
      }
      notifyListeners();
      return;
    }
    _driveTo(s, next);
    notifyListeners();
  }

  /// Puts the sweep at [phase] and makes the assembly show it.
  void _driveTo(DriveSession s, double phase) {
    final a = currentAssembly;
    // The relationship has to still BE in the document in front of us. Two
    // ways it might not: it was deleted (deleteConstraint closes the dialog,
    // but a timer already in flight can arrive first), or the user switched to
    // another tab while the sweep was running. Either way the honest answer is
    // to stop rather than to drive a constraint that is not on screen.
    if (a == null || !a.constraints.contains(s.constraint)) {
      pauseDrive();
      return;
    }
    final was = s.current;
    s.phase = phase.clamp(0.0, 1.0);
    if (!s.motion) {
      s.constraint.value = s.current;
      _solveAssembly(a);
      return;
    }
    // A motion drive turns the DRIVER, which is what runs asm_solver's drive
    // pass. By the DELTA since the last step, because turnOccurrence takes an
    // increment: it is the same call the viewport's rotate gesture makes, and
    // going through it rather than round it is what keeps one definition of
    // "turning this shaft drives that gear".
    final degrees = s.current - was;
    if (degrees.abs() < 1e-12) return;
    final driver = a.byId(s.constraint.a.occurrence);
    if (driver == null) return;
    final geom = worldGeomOf(a, s.constraint.a);
    final axis = geom.dir;
    if (axis.length < 1e-9) return;
    turnOccurrence(driver, axis.normalized(), worldAnchorOf(a, s.constraint.a),
        degrees * math.pi / 180);
  }

  /// M249 — the first thing in this class with a resource that outlives a
  /// frame, and therefore the first reason it has a dispose at all.
  ///
  /// A `Timer.periodic` keeps firing after the widget tree that owns this
  /// state is gone; in a widget test that is a pending-timer failure at the
  /// end of the test, and in the app it is a solve running against a document
  /// nobody is looking at.
  @override
  void dispose() {
    _driveTimer?.cancel();
    _driveTimer = null;
    // M260 — same reason, one gesture later: the linger timer outlives the
    // tree that was orbiting, and a pending timer fails a widget test.
    _engageTimer?.cancel();
    _engageTimer = null;
    super.dispose();
  }

  // ---- M249: Show / Show Sick / Hide All -----------------------------------
  //
  // The three rows of the Relationships panel, and what they control is what
  // is DRAWN: a constraint used to be visible only as a browser row and, while
  // the dialog was open, as its M244 selection highlight. Inventor draws a
  // glyph at each constrained pair, and these three commands decide which.
  //
  // Show is MODAL, because Inventor's is: "You click Show, then select the
  // component, or alternately select multiple components before starting the
  // command." Both orders work here — with a component already selected the
  // command acts on it at once, and with nothing selected it arms and the next
  // tap in the viewport names the component. The armed state is what lights
  // the ribbon row, so it is never a mode you are in without being told.

  /// True while Show is waiting for the user to point at a component.
  bool showRelationshipsPicking = false;

  /// Inventor's Show: draw the glyphs of everything that touches a component.
  ///
  /// Tapping the row while it is armed disarms it, the way every other toggle
  /// in this ribbon behaves — an armed command with no way out but Escape is
  /// not something a touch device should have.
  void showRelationships() {
    final a = currentAssembly;
    if (a == null) return;
    if (showRelationshipsPicking) {
      showRelationshipsPicking = false;
      notifyListeners();
      return;
    }
    // M250 — Show waits for a tap, and so do Free Move, Free Rotate and Create
    // Component. Disarmed here for the reason every command in this file
    // disarms its siblings: two commands waiting for one tap is a coin toss.
    cancelAsmPosition();
    cancelCreateComponent();
    final sel = a.selected;
    if (sel != null) {
      showRelationshipsOf(sel.id);
      return;
    }
    showRelationshipsPicking = true;
    toast(L.current.hintAsmShowPickComponent);
    notifyListeners();
  }

  /// Adds every relationship on [occurrenceId] to the drawn set.
  ///
  /// Returns false when the component has none, so the caller can say so
  /// rather than leave a tap looking like it missed.
  bool showRelationshipsOf(String occurrenceId) {
    final a = currentAssembly;
    if (a == null) return false;
    final on = a.constraintsOn(occurrenceId);
    showRelationshipsPicking = false;
    if (on.isEmpty) {
      toast(L.current.msgAsmNoRelationships(occurrenceId));
      notifyListeners();
      return false;
    }
    for (final c in on) {
      a.shownRelationships.add(c.name);
    }
    notifyListeners();
    return true;
  }

  /// Inventor's Show Sick: every relationship the solver could not meet, on
  /// whichever components they touch.
  ///
  /// Unlike Show this takes no selection — a sick constraint is a thing to go
  /// and find, so asking which component to look on first would defeat it.
  void showSickRelationships() {
    final a = currentAssembly;
    if (a == null) return;
    showRelationshipsPicking = false;
    final sick = [
      for (final c in a.constraints)
        if (c.isSick && !c.suppressed) c
    ];
    if (sick.isEmpty) {
      // Inventor greys the command out in this state; the ribbon does too (see
      // _assemblyRibbon), so this is the belt to that pair of braces — a
      // keyboard or a test can still reach the command.
      toast(L.current.msgAsmNoSickRelationships);
      notifyListeners();
      return;
    }
    for (final c in sick) {
      a.shownRelationships.add(c.name);
    }
    notifyListeners();
  }

  void hideAllRelationships() {
    final a = currentAssembly;
    if (a == null) return;
    showRelationshipsPicking = false;
    a.shownRelationships.clear();
    notifyListeners();
  }

  // ---- the Relationships folder -------------------------------------------

  void selectConstraint(AsmConstraint? c) {
    final a = currentAssembly;
    if (a == null || identical(a.selectedConstraint, c)) return;
    a.selectedConstraint = c;
    notifyListeners();
  }

  void deleteConstraint(AsmConstraint c) {
    final a = currentAssembly;
    if (a == null) return;
    // M249 — a Drive dialog open on THIS relationship is now open on nothing.
    // Closed first, so its restore lands while the constraint is still there
    // to have its value put back.
    if (identical(driveSession?.constraint, c)) closeDrive();
    a.constraints.remove(c);
    if (identical(a.selectedConstraint, c)) a.selectedConstraint = null;
    // Deleting a constraint gives freedom back; it never takes any, so the
    // components stay exactly where the last solve left them and only the
    // reported DOF changes.
    _solveAssembly(a);
    a.bump();
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  void toggleConstraintSuppressed(AsmConstraint c) {
    final a = currentAssembly;
    if (a == null) return;
    c.suppressed = !c.suppressed;
    // A suppressed constraint is switched off, not broken: clear the verdict
    // the last solve left on it so the browser does not go on showing it sick.
    if (c.suppressed) c.error = null;
    _solveAssembly(a);
    a.bump();
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  /// Runs the solver and files its verdict on the model. Every command that
  /// can change where a component belongs goes through here, so there is one
  /// place the summary and the per-constraint sickness are written.
  AsmSolveReport _solveAssembly(AssemblyModel a, {AsmDrag? drag}) {
    // M248 — BEFORE, so a constraint that names a pattern element sees it
    // where the seed currently puts it rather than where the last solve left
    // it, and so the body list the solve builds is the one the pattern
    // describes. Cheap: a closed-form expression per element.
    regenerateAsmPatterns(a);
    final report = solveAssembly(a, drag: drag);
    // M248 — and AFTER, because the solve just moved the seeds. A pattern
    // element is DRIVEN rather than solved (see asmBodyIsFree), so this is the
    // only thing that places one, and running it on both sides is what makes a
    // patterned bolt follow the bracket it was patterned from in the same
    // gesture rather than one solve later.
    regenerateAsmPatterns(a);
    // M247 — the components have just moved, so every work feature built on
    // one is now naming the wrong place until it is re-derived. AFTER the
    // solve, because that is what it is a function of.
    //
    // Honest scope note: a constraint that references an assembly work
    // feature therefore sees the frame from the PREVIOUS solve, not a
    // simultaneous one. Inventor calls that adaptivity and solves it properly;
    // here it converges over successive solves instead, which is right for
    // the common case (a plane built on a grounded component, or one whose
    // inputs the constraint does not itself move) and stated rather than
    // hidden for the case where it is not.
    _resolveAsmWorkFeatures(a);
    a.solveSummary = AsmSolveSummary(
      dof: report.dof,
      fullyConstrained: report.fullyConstrained,
      sickCount: report.sick.length,
    );
    return report;
  }

  /// Re-solves the open assembly on demand — the ribbon's Update, and what a
  /// test calls to assert where the solver put things.
  AsmSolveReport? solveCurrentAssembly() {
    final a = currentAssembly;
    if (a == null) return null;
    final r = _solveAssembly(a);
    notifyListeners();
    return r;
  }

  // ---- placement snapshots -------------------------------------------------

  void _takeAsmSnapshot(AssemblyModel a) {
    _asmSnapshot = {for (final o in a.occurrences) o.id: (o.offset, o.rot)};
  }

  void _restoreAsmSnapshot() {
    final a = currentAssembly;
    final snap = _asmSnapshot;
    if (a == null || snap == null) return;
    for (final o in a.occurrences) {
      final was = snap[o.id];
      if (was == null) continue;
      o.offset = was.$1;
      o.rot = was.$2;
    }
  }

  /// The l10n sentence for a solver or dialog refusal key.
  String _constraintRejection(String key) {
    final t = L.current;
    return switch (key) {
      'tangentNeedsRound' => t.msgAsmTangentNeedsRound,
      'insertNeedsAxes' => t.msgAsmInsertNeedsAxes,
      'angleNeedsDirections' => t.msgAsmAngleNeedsDirections,
      'motionNeedsAxes' => t.msgAsmMotionNeedsAxes,
      'jointNeedsDirections' => t.msgAsmJointNeedsDirections,
      'bothGrounded' => t.msgAsmBothGrounded,
      'missingComponent' => t.msgAsmMissingComponent,
      'cannotSatisfy' => t.msgAsmCannotSatisfy,
      _ => t.msgAsmCannotConstrain,
    };
  }

  /// The sentence for a constraint's own error, for the browser's tooltip.
  String constraintErrorText(AsmConstraint c) =>
      _constraintRejection(c.error ?? 'cannotConstrain');

  /// The sentence for a refusal key the DIALOG is holding, so the panel can
  /// show it without knowing the keys.
  String constraintRejectionText(String key) => _constraintRejection(key);

  // ---- dragging a component through what freedom it has left ---------------
  //
  // M240 dragged by adding a delta to a placement, which is right for a loose
  // part and wrong for anything constrained: a component mated to another
  // would simply leave, and a linkage grabbed by one link would come apart.
  //
  // So a drag now has two paths, chosen by whether the component is ATTACHED
  // to anything:
  //
  //   loose      the delta, applied directly. Exact, allocation-free, and
  //              identical to what M240 did — a part with no relationships
  //              must not start feeling like a solve.
  //   attached   a soft pull on the grip point, solved with every constraint
  //              in the assembly (asm_solver's AsmDrag). The mechanism follows
  //              the finger as far as its freedom allows and stops dead where
  //              it does not, which is Inventor's behaviour exactly.
  //
  // The GRIP is where the finger went down, in the component's own frame. It
  // has to be: grabbing a crank at its far end and grabbing it at its pivot
  // are different gestures, and a drag that always pulled on the origin could
  // never turn anything.

  /// The component being dragged, its grip in local coordinates, and whether
  /// this drag needs the solver.
  String? _dragOccId;
  Vec3 _dragGrip = Vec3.zero;
  bool _dragSolved = false;

  /// Called on pointer-down over a component, with the world point touched.
  void beginOccurrenceDrag(AssemblyOccurrence occ, Vec3 worldGrip) {
    final a = currentAssembly;
    if (a == null) return;
    _dragOccId = occ.id;
    _dragGrip = occ.toLocal(worldGrip);
    // M250 — FREE MOVE bypasses the solver even on a component that is fully
    // related to everything else. That is the whole of the command: Inventor's
    // Free Move temporarily overrides the constraints, and the next update
    // puts the component back. Without this branch the button would be a
    // second name for the drag the viewport already had.
    _dragSolved = !asmFreePositioning && _isAttached(a, occ.id);
  }

  /// True when [id] is connected, through active positional constraints, to
  /// anything at all. Transitively: a link two joints away from the one being
  /// dragged still has to move with it.
  bool _isAttached(AssemblyModel a, String id) {
    final seen = <String>{id};
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final at = queue.removeLast();
      for (final c in a.constraints) {
        if (c.suppressed || !c.isPositional) continue;
        if (!c.touches(at)) continue;
        // A constraint to the assembly's own origin attaches too — it is what
        // pins a part to the XY plane — so the constraint counts even when it
        // names only one component.
        if (c.occurrences.length < 2) return true;
        for (final other in c.occurrences) {
          if (seen.add(other)) queue.add(other);
        }
      }
    }
    return seen.length > 1;
  }

  /// Moves the dragged component so its grip lands on [worldTarget].
  void dragOccurrenceTo(Vec3 worldTarget) {
    final a = currentAssembly;
    final id = _dragOccId;
    if (a == null || id == null) return;
    final occ = a.byId(id);
    if (occ == null || occ.grounded) return;
    if (!_dragSolved) {
      occ.offset = occ.offset + (worldTarget - occ.toWorld(_dragGrip));
      notifyListeners();
      return;
    }
    _solveAssembly(a, drag: AsmDrag(id, _dragGrip, worldTarget));
    notifyListeners();
  }

  /// Moves [occ] by [delta] millimetres. Grounded occurrences do not move —
  /// see [placeComponent].
  ///
  /// The delta form, kept because it is what a caller with no grip has: it
  /// pulls on the component's own origin, which for a loose part is the same
  /// translation and for an attached one is the honest "drag it from the
  /// middle".
  void moveOccurrence(AssemblyOccurrence occ, Vec3 delta) {
    if (occ.grounded) return;
    final a = currentAssembly;
    if (a == null || !_isAttached(a, occ.id)) {
      occ.offset = occ.offset + delta;
      notifyListeners();
      return;
    }
    _solveAssembly(a,
        drag: AsmDrag(occ.id, Vec3.zero, occ.toWorld(Vec3.zero) + delta));
    notifyListeners();
  }

  /// Turns [occ] about the world axis [axis] through [pivot], driving any
  /// motion constraints it is the mover of.
  ///
  /// This is the second half of "dynamic": a gear pair is not solved (see
  /// asm_solver's header — motion constraints act only on open degrees of
  /// freedom), it is DRIVEN, so turning one shaft has to propose where the
  /// other goes and let the assembly constraints have the last word.
  ///
  /// M250 — [solve] is what Free Rotate turns off, and the split is worth
  /// stating because the two halves of this method are not the same kind of
  /// thing. Inventor's Free Rotate OVERRIDES assembly constraints: the
  /// component stays where the command put it and snaps back at the next
  /// update. So the solve goes. [driveMotion] stays, because a motion
  /// constraint is not a positional one — there is nothing for it to override
  /// — and turning a gear by hand and having its mate turn with it is the
  /// entire content of a motion constraint.
  void turnOccurrence(
      AssemblyOccurrence occ, Vec3 axis, Vec3 pivot, double radians,
      {bool solve = true}) {
    final a = currentAssembly;
    if (a == null || occ.grounded || radians.abs() < 1e-12) return;
    final q = Quat.axisAngle(axis, radians);
    occ.rot = (q * occ.rot).normalized();
    occ.offset = pivot + q.rotate(occ.offset - pivot);
    driveMotion(a, occ.id, radians);
    if (solve) _solveAssembly(a);
    notifyListeners();
  }

  // ---- M250: FREE MOVE and FREE ROTATE ------------------------------------
  //
  // The two commands in Inventor's Position panel, and the reason they are
  // commands at all when the viewport has dragged a component since M240.
  //
  // WHAT INVENTOR DOES (researched 2026-08 from search summaries of the
  // Autodesk help and the Inventor forums — help.autodesk.com is blocked from
  // this network, so the pages themselves were not read):
  //
  //   * A partially constrained component can be dragged with NO command at
  //     all, in its free degrees of freedom. That is direct manipulation, it
  //     is what M242's dragOccurrenceTo already does, and it goes through the
  //     solver so a mechanism follows the finger.
  //
  //   * Free Move and Free Rotate TEMPORARILY OVERRIDE the constraints. The
  //     component goes where you put it and STAYS there — until the next
  //     update, or until a new relationship is applied, at which point it
  //     snaps back to where its relationships say it belongs.
  //
  // The second is the whole difference, and it falls out of this codebase
  // rather than having to be built: a free gesture writes the placement and
  // does not call [_solveAssembly], and the next thing that does — a plain
  // drag, a new constraint, an edit, a reopen — puts it back. That IS the
  // snap-back, with nothing to implement and nothing to keep in step.
  //
  // Free Rotate is the one with no existing half at all. The viewport has
  // never had a rotation gesture; [turnOccurrence] was written for it in M242
  // and has had no caller until now. Inventor draws a 3D rotate glyph — a
  // sphere with a rim and four edge handles — on the picked component:
  //
  //     top / bottom handle, dragged vertically     about the HORIZONTAL axis
  //     left / right handle, dragged horizontally   about the VERTICAL axis
  //     inside the sphere                           any direction (trackball)
  //     the rim                                     planar to the screen
  //
  // and releasing drops the component in its rotated position. That is
  // established from the Autodesk help summary and is what the viewport
  // implements; how the glyph LOOKS is inferred, since the pages carrying the
  // picture are blocked here.
  //
  // GROUNDED components refuse both, and that part is a decision rather than a
  // finding: whether Inventor's Free Move overrides Ground was not
  // established. It is refused here because Ground is the one state with
  // nothing to snap back FROM — a grounded component nudged by Free Move
  // would stay nudged for ever, and the pin the browser draws on its row
  // would be a lie. Unground it first, which is one tap in the same tree.

  /// Which Position command is armed, or null.
  AsmPositionMode? asmPositionMode;

  /// True while either is armed: the viewport moves the component ITSELF
  /// rather than asking the solver where it may go.
  bool get asmFreePositioning => asmPositionMode != null;

  void startFreeMove() => _armAsmPosition(AsmPositionMode.move);

  void startFreeRotate() => _armAsmPosition(AsmPositionMode.rotate);

  void _armAsmPosition(AsmPositionMode mode) {
    if (currentAssembly == null) return;
    // Every ribbon entry is a TOGGLE (M210): the same button twice cancels,
    // which on a device with no Escape key is the only way out of a command.
    if (asmPositionMode == mode) {
      cancelAsmPosition();
      return;
    }
    cancelConstraint();
    cancelWorkFeature();
    cancelPattern();
    cancelCreateComponent();
    _cancelAsmShowAndDrive();
    asmPositionMode = mode;
    toast(mode == AsmPositionMode.move
        ? L.current.hintAsmFreeMove
        : L.current.hintAsmFreeRotate);
    notifyListeners();
  }

  void cancelAsmPosition() {
    if (asmPositionMode == null) return;
    asmPositionMode = null;
    _turnOccId = null;
    notifyListeners();
  }

  /// M250 — disarms M249's two commands that would otherwise still be live.
  ///
  /// SHOW is armed and waiting for a tap, and two commands waiting for the
  /// same tap is a coin toss the user cannot see. DRIVE is worse: it moves
  /// components on a TIMER, so a Free Move underneath it would be undone
  /// between frames by an animation the user did not connect to it.
  ///
  /// Its own half — M249's commands disarming M250's — is at each of their
  /// entry points, for the reason the ones above are: an armed command is
  /// cancelled by whoever takes over from it, and there is no central
  /// registry of them to forget to update.
  void _cancelAsmShowAndDrive() {
    if (showRelationshipsPicking) {
      showRelationshipsPicking = false;
      notifyListeners();
    }
    if (driveSession != null) closeDrive();
  }

  /// The component the rotate glyph is drawn on: the selection, as long as it
  /// is something that can turn.
  ///
  /// A pattern ELEMENT is excluded for the reason asm_pattern.dart gives about
  /// a driven body: the pattern places it after every solve, so a rotation
  /// applied here would survive exactly until the next regeneration and then
  /// vanish without explanation.
  AssemblyOccurrence? get freeRotateTarget {
    if (asmPositionMode != AsmPositionMode.rotate) return null;
    final o = currentAssembly?.selected;
    if (o == null || o.grounded || o.isPatternElement) return null;
    return o;
  }

  /// Where the rotate glyph sits and how big it is: the centre of the
  /// component's world bounds, and the radius that encloses it.
  ///
  /// The BOUNDS centre rather than the component's origin, which is where
  /// Inventor puts the glyph and is the only choice that behaves: a part
  /// modelled a long way from its own origin would otherwise be rotated about
  /// a point off in space, and the gesture would read as a translation.
  (Vec3, double)? get freeRotateGlyph {
    final o = freeRotateTarget;
    if (o == null) return null;
    final b = occurrenceBounds(o);
    if (b == null) return null;
    final (lo, hi) = b;
    final centre = (lo + hi) * 0.5;
    // Half the diagonal, so the sphere encloses the component whatever its
    // aspect; floored so a tiny part still gets a glyph you can hit.
    return (centre, math.max(2.0, (hi - lo).length * 0.5));
  }

  /// The occurrence being turned, and the pivot the gesture froze.
  String? _turnOccId;
  Vec3 _turnPivot = Vec3.zero;

  /// Called when the rotate gesture starts on [occ].
  ///
  /// The pivot is frozen for the whole gesture, for the same reason M242
  /// freezes the drag plane: reading the component's centre every frame would
  /// let the rotation move the point it is being measured about, and a turn
  /// that pushed its own pivot away would walk the component across the
  /// screen instead of spinning it.
  void beginOccurrenceTurn(AssemblyOccurrence occ) {
    if (currentAssembly == null || occ.grounded) return;
    _turnOccId = occ.id;
    final b = occurrenceBounds(occ);
    _turnPivot = b == null ? occ.offset : (b.$1 + b.$2) * 0.5;
  }

  /// Turns the component this gesture grabbed by [radians] about the WORLD
  /// axis [axis], through the pivot frozen at the start.
  void turnOccurrenceBy(Vec3 axis, double radians) {
    final a = currentAssembly;
    final id = _turnOccId;
    if (a == null || id == null) return;
    final occ = a.byId(id);
    if (occ == null) return;
    // solve: false — this is Inventor's override. See [turnOccurrence].
    turnOccurrence(occ, axis, _turnPivot, radians, solve: false);
  }

  /// Ends the rotate gesture, persisting the new placement once rather than
  /// on every frame of it.
  void endOccurrenceTurn() {
    final a = currentAssembly;
    final id = _turnOccId;
    _turnOccId = null;
    if (a == null || id == null) return;
    // The origin planes and axes are sized to the assembly's contents, so
    // they are stale until the gesture settles — the same tick
    // [endOccurrenceDrag] does, and for the same reason.
    a.bump();
    _warnFreePositioned(a, id);
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  /// Says out loud that a component was put somewhere its relationships do not
  /// agree with, and that the next update will take it back.
  ///
  /// Only when it actually has relationships: a loose component moved by Free
  /// Move stays exactly where it was put for ever, and warning about that
  /// would be warning about nothing. Silence here is what made the same
  /// behaviour read as a bug in Inventor for a generation of users.
  void _warnFreePositioned(AssemblyModel a, String id) {
    if (!asmFreePositioning || !_isAttached(a, id)) return;
    toast(L.current.msgAsmFreePositioned(id));
  }

  // ---- M250: CREATE COMPONENT, and EDIT IN PLACE --------------------------
  //
  // Inventor's Create In-Place Component: a NEW part document, made from
  // inside the assembly, placed where you point and opened for editing with
  // the rest of the assembly still around you.
  //
  // WHAT INVENTOR'S DIALOG HOLDS (researched 2026-08 from search summaries of
  // the Autodesk help pages "Create In-Place Component dialog box" and "Create
  // a part or a virtual part in an assembly"; help.autodesk.com and
  // knowledge.autodesk.com are blocked from this network, so the pages
  // themselves were not read and no screenshot was available):
  //
  //     New Component Name      the file name of the new part
  //     Template                which .ipt template to build it from
  //     New File Location       which folder to write it to
  //     Default BOM Structure   Normal / Phantom / Reference / Purchased
  //     Virtual Component       a component with NO geometry and NO file;
  //                             ticking it disables most of the dialog
  //     Constrain sketch plane to the selected face or plane
  //                             OFF by default; when on, a FLUSH constraint
  //                             is applied between the new component and what
  //                             you picked
  //
  // and then you pick the sketch plane — an origin plane, a work plane or a
  // planar face — and Inventor drops you into the new part with a sketch open
  // on it. The first component of an assembly is grounded.
  //
  // WHAT THIS DIALOG HOLDS, and why the other four rows are absent rather
  // than stubbed. Each of them is a control over something this app does not
  // have, and a disabled row for a concept that does not exist is worse than
  // no row: it invites the user to look for the feature.
  //
  //     Template              there is one kind of part document here and no
  //                           template store. A list with one entry is not a
  //                           choice.
  //     New File Location     there is one gallery (see doc_store.dart); a
  //                           document has a name, not a path.
  //     Default BOM Structure there is no BOM, no parts list and no drawing.
  //     Virtual Component     a component with no file is a BOM row, and it is
  //                           the BOM that gives it meaning. Without one it
  //                           would be an occurrence that draws nothing — which
  //                           is what a component whose part has been DELETED
  //                           already looks like, and that is a fault state,
  //                           not a feature.
  //
  // The name and the Flush checkbox are both real and both do what Inventor's
  // do. See CreateComponentDialog.

  CreateComponentSession? createComponentSession;

  /// True while Create Component is waiting for the sketch plane, so the
  /// viewport picks GEOMETRY rather than grabbing a component.
  bool get asmCreatePicking => createComponentSession?.picking == true;

  /// Opens the dialog. A toggle like every other command button (M210).
  void openCreateComponent() {
    final a = currentAssembly;
    if (a == null) return;
    if (createComponentSession != null) {
      cancelCreateComponent();
      return;
    }
    cancelConstraint();
    cancelWorkFeature();
    cancelPattern();
    cancelAsmPosition();
    _cancelAsmShowAndDrive();
    createComponentSession =
        CreateComponentSession(suggestedPartName());
    notifyListeners();
  }

  void cancelCreateComponent() {
    final s = createComponentSession;
    if (s == null) return;
    createComponentSession = null;
    final a = currentAssembly;
    if (a != null) _asmWfOriginRestore(a);
    notifyListeners();
  }

  /// The dialog's OK: validate the name, then go and collect the plane.
  ///
  /// The name is checked HERE rather than when the part is written, because
  /// the alternative is telling the user their name was no good after they
  /// have already chosen a face — and by then the dialog they would fix it in
  /// is gone.
  bool beginCreateComponentPick() {
    final a = currentAssembly;
    final s = createComponentSession;
    if (a == null || s == null) return false;
    final clean = s.name.trim();
    final bad = validateSketchName(clean);
    if (bad != null) {
      toast(bad);
      return false;
    }
    if (docNameExists(clean)) {
      toast(L.current.msgNameTaken(clean));
      return false;
    }
    s.name = clean;
    s.picking = true;
    // The origin geometry is offered while the pick is open, exactly as
    // _armAsmWorkFeature and startPartSketch do it: the FIRST component of an
    // assembly has nothing else to be placed against, and the assembly's
    // origin planes are off by default.
    _wfOriginAutoShown = a.isEmpty;
    if (_wfOriginAutoShown) {
      for (final k in a.vis.keys) {
        a.vis[k] = true;
      }
      a.bump();
    }
    toast(L.current.hintAsmCreatePickPlane);
    notifyListeners();
    return true;
  }

  /// The viewport reports the picked sketch plane. Creates the part document,
  /// places it there, and opens it for editing in place.
  ///
  /// Only a PLANE will do — an edge or a vertex is not something you can
  /// sketch on — and a rejected pick leaves the command armed, which is the
  /// rule every other assembly pick follows: a mis-tap costs that tap and
  /// nothing else.
  Future<bool> createComponentOn(AsmPick pick) async {
    final a = currentAssembly;
    final s = createComponentSession;
    if (a == null || s == null || !s.picking) return false;
    if (pick.ref.geom.kind != AsmGeomKind.plane) {
      toast(L.current.hintAsmCreatePickPlane);
      return false;
    }
    final name = s.name;
    // The document first. Not OPENED: the assembly has to stay the current
    // tab until the component is placed in it, and openPart mid-way would
    // leave an empty part on screen for the length of one save.
    if (!await createNamedPart(name, open: false)) {
      toast(L.current.msgNameTaken(name));
      return false;
    }
    // The new part's own XY plane, laid onto the plane that was picked: +Z
    // along the picked normal, origin at the point actually touched.
    //
    // Quat.fromTo is the SHORTEST such rotation, so the part's X and Y land
    // wherever that leaves them. Inventor asks a second question here (the
    // sketch's X direction) and this does not; the sketch opens facing the
    // plane either way, and a rotation about the normal is one the user can
    // make by drawing the other way round.
    final n = pick.world.dir.length < 1e-9
        ? const Vec3(0, 0, 1)
        : pick.world.dir.normalized();
    final placed = await placeComponent(name,
        at: Placement(Quat.fromTo(const Vec3(0, 0, 1), n), pick.hit));
    if (placed == null) {
      // placeComponent has already said why. The document exists and is in
      // the gallery — deleting it here would throw away a name the user chose
      // for a failure they can simply retry the placement of.
      cancelCreateComponent();
      return false;
    }
    // Inventor's "Constrain sketch plane to the selected face or plane", and
    // its FLUSH: the new component's sketch plane and the picked one face the
    // same way. Applied AFTER the placement, which already satisfies it, so
    // the solve that follows is a no-op — what this buys is the RELATIONSHIP,
    // which is what makes the new part follow the thing it was built on.
    if (s.constrainSketchPlane) {
      a.constraints.add(AsmConstraint(
        name: nextConstraintName(a.constraints, AsmKind.mate),
        kind: AsmKind.mate,
        solution: AsmSolution.flush,
        // The new component's own XY plane, in its own frame — which is where
        // it will still be after the solver has moved the component, and is
        // the whole reason a constraint stores local geometry.
        a: AsmRef(placed.id, const AsmGeom.plane(Vec3.zero, Vec3(0, 0, 1)),
            planeLabel('xy')),
        b: pick.ref,
      ));
      _solveAssembly(a);
      a.bump();
    }
    _asmWfOriginRestore(a);
    createComponentSession = null;
    unawaited(saveAssembly(a.name));
    // And into the part, with the assembly still around it.
    await enterInPlaceEdit(placed, startSketch: true);
    return true;
  }

  // ---- edit in place ------------------------------------------------------
  //
  // "In the context of the assembly" is the phrase Inventor uses and it is
  // worth being precise about what it buys, because it is the one part of
  // Create Component that could have been skipped: you sketch and model in the
  // NEW part while the REST OF THE ASSEMBLY stays on screen around you, so a
  // bracket is drawn against the thing it bolts to rather than against an
  // empty screen and a remembered dimension.
  //
  // This builds it, and reuses the part editor whole rather than growing a
  // second one. The part tab becomes current, so every part command — sketch,
  // extrude, hole, fillet, work planes, End of Part — is the one that already
  // works, with nothing forked and nothing to keep in step. What edit in place
  // ADDS is three things:
  //
  //   * the CONTEXT: every other component of the parent assembly, drawn
  //     around the part in the part's own frame and dimmed. See
  //     [inPlaceContextPieces], assembly.inPlaceContext for the transform, and
  //     paintPartSolids / buildScenePayload for the two renderers that draw
  //     it. It is drawn in the SAME depth pass as the part, not layered under
  //     it, so a component in front of the part hides it — which is the whole
  //     point of modelling in context.
  //
  //   * the CAMERA, carried across so the view does not jump. See
  //     [_carryCamera].
  //
  //   * a way BACK. Inventor's is a Return button; here it is the row the
  //     browser draws at the top of the part tree while this is on.
  //
  // The honest scope note: this app has one document per tab and a gallery
  // that lists every document, so the new part APPEARS as its own tab and its
  // own gallery card the moment it is created. Inventor hides it inside the
  // assembly until you save. Neither is more correct; this one follows the
  // rule the rest of the app already runs on — a document is a document — and
  // the difference is stated here rather than papered over.

  InPlaceEdit? _inPlace;

  /// The in-place edit that is actually live, or null.
  ///
  /// Validated on every read rather than cleared on every exit: the tab can
  /// change from a dozen places (the tab bar, the gallery, a rename, a delete)
  /// and an edit that outlived its tab would draw one document's assembly
  /// around another document's part. One condition, checked where it is used,
  /// cannot be forgotten in a path nobody thought of.
  InPlaceEdit? get inPlaceEdit {
    final e = _inPlace;
    if (e == null) return null;
    if (curTab != e.part || !parts.containsKey(e.part)) return null;
    final a = assemblies[e.assembly];
    if (a == null || a.byId(e.occurrence) == null) return null;
    return e;
  }

  bool get isEditingInPlace => inPlaceEdit != null;

  /// The rest of the parent assembly, in the edited part's OWN frame, ready
  /// for either renderer. Empty when nothing is being edited in place.
  ///
  /// Recomputed per frame rather than cached: it is a walk over placements
  /// (no mesh is copied — see assembly.inPlaceContext), the components do not
  /// move while a part is being edited, and a cache would be one more thing
  /// to invalidate when the assembly changed underneath.
  List<(String, Placement, KernelSolid)> get inPlaceContextPieces {
    final e = inPlaceEdit;
    if (e == null) return const [];
    final a = assemblies[e.assembly]!;
    return inPlaceContext(a, a.byId(e.occurrence)!);
  }

  /// Opens [occ]'s part for editing with its assembly around it.
  ///
  /// Refused for a SUBASSEMBLY: what would open is an assembly document, and
  /// "the assembly around it" would then have to mean its parent — a second,
  /// nested case with its own camera and its own return path. Inventor does
  /// support it; this says so rather than half-doing it.
  Future<bool> enterInPlaceEdit(AssemblyOccurrence occ,
      {bool startSketch = false}) async {
    final a = currentAssembly;
    if (a == null) return false;
    if (occ.isSubAssembly) {
      toast(L.current.msgAsmEditSubInPlace(occ.id));
      return false;
    }
    if (!isPartName(occ.source)) {
      toast(L.current.msgAsmNoSuchPart(occ.source));
      return false;
    }
    // Whatever was armed in the assembly is not what the user meant any more.
    cancelConstraint();
    cancelWorkFeature();
    cancelPattern();
    cancelAsmPosition();
    cancelCreateComponent();
    _cancelAsmShowAndDrive();
    final asmName = a.name;
    final camera = a.camera;
    final rot = occ.rot;
    final offset = occ.offset;
    await saveAssembly(asmName);
    await openPart(occ.source);
    final p = parts[occ.source];
    if (p == null) return false;
    _inPlace = InPlaceEdit(asmName, occ.id, occ.source);
    _carryCamera(camera, p.camera, rot, offset, into: true);
    if (startSketch) {
      // Inventor opens the new part with a sketch already active on the plane
      // you picked. The component was placed so that its own XY plane IS that
      // plane (see createComponentOn), so this is the ordinary "sketch on XY"
      // path with nothing special about it — which is exactly why the
      // component was placed that way round.
      final framed = p.camera.halfH;
      startPartSketch();
      planePicked('xy');
      // orientToPlane resets the pan to the part origin and the zoom to the
      // app's 27 mm sketch default. The PAN is right — the part's origin is
      // the point that was picked, so 0,0 centres on it — and the ZOOM is
      // not: it frames an empty new part and pushes the assembly you are
      // building against off the screen, which is the one thing edit in place
      // exists to keep on it.
      p.camera.halfH = framed;
    }
    // Say what just happened. The viewport changes completely — a part where
    // an assembly was, with the assembly still drawn around it — and the way
    // back is a ribbon panel and a browser row that were not there a moment
    // ago. A mode you entered without being told is a mode you are stuck in.
    toast(L.current.hintInPlaceEditing(occ.source, asmName));
    notifyListeners();
    return true;
  }

  /// Inventor's Return: back to the assembly, with the view kept.
  Future<void> leaveInPlaceEdit() async {
    final e = inPlaceEdit;
    if (e == null) {
      _inPlace = null;
      return;
    }
    // A sketch open inside the part is closed the ordinary way first, so its
    // features are recomputed and its display state (Slice Graphics) is put
    // back — leaving it open and switching document would strand both.
    if (activeChild != null) finishPartSketch();
    final p = parts[e.part];
    final a = assemblies[e.assembly]!;
    final occ = a.byId(e.occurrence)!;
    _inPlace = null;
    await savePart(e.part);
    await openAssembly(e.assembly);
    if (p != null) {
      _carryCamera(a.camera, p.camera, occ.rot, occ.offset, into: false);
    }
    // The part's geometry has very probably changed, and the assembly's scene
    // signature is what decides whether RealityKit re-uploads a mesh. M245
    // shares ONE model between the tab and the component, so there is nothing
    // to reload — but the renderer still has to be told to look again.
    a.bump();
    notifyListeners();
  }

  /// Carries the view between an assembly and a component's part, in either
  /// direction, so entering and leaving an in-place edit do not jump.
  ///
  /// This is [placedCam] written for a [PartCamera] instead of a [Cam3], and
  /// it is exact for the same reason: the projection is affine, so a component
  /// placed at (rot, offset) is the same picture as the camera turned by rot⁻¹
  /// and panned by the component's origin. `into` runs it one way, `!into` the
  /// other.
  ///
  /// THE MIRROR IS DELIBERATELY DROPPED. A reflected placement would need a
  /// LEFT-handed camera basis, and [PartCamera.setBasis] rebuilds up from
  /// right × −dir, so it cannot hold one. Only [rot] and [offset] travel. The
  /// consequence is worth stating plainly: editing a MIRRORED component in
  /// place shows the un-mirrored part — which is the document you are actually
  /// editing, since M248 mirrors the OCCURRENCE and never the part — seen from
  /// the mirrored camera position. The geometry around it is exact either way,
  /// because [inPlaceContext] goes through the full [Placement].
  void _carryCamera(PartCamera asm, PartCamera part, Quat rot, Vec3 offset,
      {required bool into}) {
    final from = into ? asm : part;
    final to = into ? part : asm;
    final d = into ? rot.unrotate(from.dir) : rot.rotate(from.dir);
    final r = into ? rot.unrotate(from.right) : rot.rotate(from.right);
    final halfH = from.halfH;
    final ox = from.ox, oy = from.oy;
    to.setBasis(d, r);
    to.halfH = PartCamera.clampHalfH(halfH);
    // The pan shift is measured against the ASSEMBLY camera's basis in BOTH
    // directions, because [offset] is a vector in assembly world — that is
    // what placedCam's `ox - at.at.dot(cam.s)` says, and using the part
    // camera's axes for it would drift the model sideways by however far the
    // component sits from the assembly origin. Read after setBasis, since on
    // the way OUT the assembly camera is the one that was just written.
    final sx = asm.right, sy = asm.up;
    to.ox = into ? ox - offset.dot(sx) : ox + offset.dot(sx);
    to.oy = into ? oy - offset.dot(sy) : oy + offset.dot(sy);
  }

  // ---- M250: VIEW REPRESENTATIONS -----------------------------------------
  //
  // The commands behind the browser's Representations folder. What a view
  // representation IS, what Inventor's other two are, and why they are listed
  // rather than built, is all written down in asm_reps.dart; this is only the
  // verbs.
  //
  // Every one of them ends the same way — bump, notify, save — because a
  // representation is document state: it survives the tab, the save and the
  // reopen, exactly like a constraint.

  /// Applies the representation called [name], writing the one being left
  /// back into itself first.
  ///
  /// The write-back is [AssemblyModel.leaveViewRep] and is Inventor's rule for
  /// an UNLOCKED representation. It is what makes going back to Default
  /// restore the view you were working in rather than whatever Default held
  /// the first time it was written.
  void activateViewRep(String name) {
    final a = currentAssembly;
    if (a == null || a.activeViewRep == name) return;
    if (name != kDefaultViewRep && a.viewRepNamed(name) == null) return;
    a.leaveViewRep();
    final rep = a.viewRepNamed(name);
    if (rep != null) a.applyViewRep(rep);
    a.activeViewRep = name;
    // The heavy push: a representation changes which components are DRAWN, and
    // the origin planes are sized to what is left. Both live behind the scene
    // signature, so without this the components would vanish and their planes
    // would not notice.
    a.bump();
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  /// Inventor's right-click New on the View node: saves the display state you
  /// are looking at under a fresh name, and makes it the active one.
  ///
  /// Making it active is not decoration. A New that captured a snapshot and
  /// left you in the old representation would put the next change you made
  /// into the OLD one, and the rep you just created would silently be a
  /// picture of a moment you had already moved on from.
  String? newViewRep() {
    final a = currentAssembly;
    if (a == null) return null;
    // Leave the current one properly first, so the state this one captures is
    // also written where you came from — otherwise creating a rep would lose
    // the working view it was made from.
    a.leaveViewRep();
    final rep = AsmViewRep(name: nextViewRepName(a.viewRepNames));
    a.captureViewRep(rep);
    a.viewReps.add(rep);
    a.activeViewRep = rep.name;
    notifyListeners();
    unawaited(saveAssembly(a.name));
    return rep.name;
  }

  /// Writes the current display state into [name], whatever is active.
  ///
  /// Refused on a LOCKED representation rather than silently ignored: the
  /// padlock is the user's own statement that this one is not to move, and a
  /// command that quietly did nothing would read as broken.
  void updateViewRep(String name) {
    final a = currentAssembly;
    final rep = a?.viewRepNamed(name);
    if (a == null || rep == null) return;
    if (rep.locked) {
      toast(L.current.msgAsmViewRepLocked(name));
      return;
    }
    a.captureViewRep(rep);
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  void toggleViewRepLocked(String name) {
    final a = currentAssembly;
    final rep = a?.viewRepNamed(name);
    if (a == null || rep == null) return;
    // Locking the ACTIVE representation freezes it as it is right now, so what
    // it holds has to be what is on screen — otherwise the padlock would
    // preserve the state it had before the changes you locked it to keep.
    if (!rep.locked && a.activeViewRep == name) a.captureViewRep(rep);
    rep.locked = !rep.locked;
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  /// Renames a representation. Default cannot be renamed, which is Inventor's
  /// rule and this app's too: it is the name a document falls back to when the
  /// active one has gone, so something has to be able to answer to it.
  bool renameViewRep(String from, String to) {
    final a = currentAssembly;
    final rep = a?.viewRepNamed(from);
    if (a == null || rep == null || rep.isDefault) return false;
    final clean = to.trim();
    if (clean.isEmpty || clean == kDefaultViewRep) return false;
    if (clean == from) return true;
    if (a.viewRepNamed(clean) != null) return false;
    rep.name = clean;
    if (a.activeViewRep == from) a.activeViewRep = clean;
    notifyListeners();
    unawaited(saveAssembly(a.name));
    return true;
  }

  /// Deletes a representation. Deleting the ACTIVE one falls back to Default
  /// without applying anything: what is on screen is what you were looking at,
  /// and throwing that away as well would be two commands where the user asked
  /// for one.
  void deleteViewRep(String name) {
    final a = currentAssembly;
    final rep = a?.viewRepNamed(name);
    if (a == null || rep == null || rep.isDefault) return;
    a.viewReps.remove(rep);
    if (a.activeViewRep == name) a.activeViewRep = kDefaultViewRep;
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  // ---- assembly document operations ---------------------------------------

  Future<void> deleteAssembly(String name) async {
    if (_docsDir == null) return;
    openTabs.remove(name);
    if (curTab == name) {
      curTab = openTabs.isNotEmpty ? openTabs.last : null;
      if (curTab == null) editingLayer = null;
      _reanalyze();
    }
    assemblies.remove(name)?.dispose();
    _deleteDocFile(name);
    await refreshSaved();
    notifyListeners();
  }

  Future<bool> renameAssembly(String from, String to) async {
    if (_docsDir == null) return false;
    final target = to.trim();
    if (target == from) return true;
    if (validateSketchName(target) != null) return false;
    if (docNameExists(target)) return false;
    final wasOpen = openTabs.contains(from);
    final tabIndex = openTabs.indexOf(from);
    final wasCurrent = curTab == from;
    if (assemblies.containsKey(from)) {
      await saveAssembly(from);
      openTabs.remove(from);
      assemblies.remove(from)?.dispose();
      if (wasCurrent) curTab = null;
    }
    if (!_renameDocFile(from, target)) return false;
    if (wasOpen) {
      await openAssembly(target);
      openTabs.remove(target);
      openTabs.insert(math.min(tabIndex, openTabs.length), target);
      if (!wasCurrent) curTab = openTabs.isNotEmpty ? openTabs.last : null;
    }
    await refreshSaved();
    notifyListeners();
    return true;
  }

  Future<String?> duplicateAssembly(String name) async {
    if (_docsDir == null) return null;
    if (assemblies.containsKey(name)) await saveAssembly(name);
    if (_findDoc(name) == null) return null;
    var copy = '$name copy';
    var n = 2;
    while (docNameExists(copy)) {
      copy = '$name copy $n';
      n++;
    }
    if (!_duplicateDocFile(name, copy)) return null;
    await refreshSaved();
    notifyListeners();
    return copy;
  }

  /// Writes the part's solids as STEP into the export cache and returns the
  /// path (for the share sheet / Files export). Null without a kernel or
  /// without any computed solid — reported honestly, never faked.
  Future<String?> partExportStep(String name) async {
    if (_docsDir == null) return null;
    // Checked BEFORE the part is loaded: without a kernel there are no solids
    // to export no matter what the document holds, so reading it off disk and
    // folding its features would be pure waste before saying so.
    if (!partKernel.available) {
      toast(L.current.msgNoKernelStep);
      return null;
    }
    final wasLoaded = parts.containsKey(name);
    // M214 — a part that is NOT open loads headlessly and is thrown away
    // again. It used to go through openPart, which is why sharing a part from
    // the gallery opened it: new tab, new current document, tool cleared,
    // viewport rebuilt. Exporting is not navigation.
    final p = wasLoaded ? parts[name]! : await _loadPartModel(name);
    try {
      // Only a part the user actually has open can have unsaved edits worth
      // flushing. Saving the headless copy would rewrite the document (and its
      // thumbnail, and its modified date) purely as a side effect of sharing
      // it — and it is a byte-for-byte copy of what is already on disk.
      if (wasLoaded) await savePart(name);
      // M214 — the LIVE bodies, not every solid the fold produced on its way
      // here. See partExportBodies: each feature stores the running
      // accumulation at its own position, so taking them all handed the
      // kernel the block AND the block-with-the-hole AND the filleted
      // block — which the kernel then unioned back into a plain block. Holes
      // and fillets disappeared from the file while being perfectly visible
      // on screen.
      final bodies = partExportBodies(p);
      if (bodies.isEmpty) {
        toast(L.current.msgNothingToExportYet);
        return null;
      }
      // A feature that failed to build is not in `bodies` at all, so an export
      // could otherwise quietly hand over a part with a body missing. Say so
      // instead: the file is still written (the rest of it is real), but the
      // user is told what is not in it.
      final broken = [
        for (final f in p.features)
          if (f.computeError != null && !f.rolledBack) f.name
      ];
      final exportDir = Directory('${_cacheRoot.path}/export');
      if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
      final path = '${exportDir.path}/$name.step';
      // A stale file from an earlier export must never be what gets shared.
      // Without this, a failed write leaves the PREVIOUS export in place, and
      // the only thing standing between it and the share sheet is that we
      // return null — which is true today and is one refactor from not being.
      final out = File(path);
      if (out.existsSync()) {
        try {
          out.deleteSync();
        } catch (e) {
          Log.w('export', 'could not clear stale $path: $e');
        }
      }
      if (!partKernel.exportStepBodies(bodies, path, product: name)) {
        toast(L.current.msgStepExportFailed(partKernel.lastError));
        return null;
      }
      if (!out.existsSync() || out.lengthSync() == 0) {
        // The kernel said yes and produced nothing. Sharing a zero-byte file
        // is worse than reporting the failure.
        toast(L.current.msgStepExportEmpty);
        Log.w('export', 'kernel reported success but $path is empty/missing');
        return null;
      }
      Log.i(
          'export',
          'STEP "$name": bodies=${bodies.length} '
              '(${bodies.map((b) => b.$1).join(", ")}) '
              'bytes=${out.lengthSync()}'
              '${broken.isEmpty ? "" : " SKIPPED=${broken.join(", ")}"}');
      if (broken.isNotEmpty) {
        toast(L.current
            .msgExportedWithout(broken.length, broken.join(', ')));
      }
      return path;
    } finally {
      // The headless copy owns a B-Rep per body AND a solver engine per child
      // sketch. Dropping the reference without disposing leaks all of them,
      // once per share. `closeTab` disposes an open part for the same reason.
      if (!wasLoaded) p.dispose();
    }
  }

  /// M289 — Binary STL writer that computes per-facet normals from the
  /// triangle geometry (CCW winding) instead of leaving them zero.
  static void writeBinaryStl(IOSink sink, List<OcctMeshData> meshes) {
    final totalTriangles =
        meshes.fold<int>(0, (sum, m) => sum + m.indices.length ~/ 3);
    sink.add(Uint8List(80));
    final countBytes = ByteData(4)
      ..setUint32(0, totalTriangles, Endian.little);
    sink.add(countBytes.buffer.asUint8List());

    for (final mesh in meshes) {
      final pos = mesh.positions;
      final idx = mesh.indices;
      for (var i = 0; i + 2 < idx.length; i += 3) {
        final i0 = idx[i] * 3;
        final i1 = idx[i + 1] * 3;
        final i2 = idx[i + 2] * 3;
        final ax = pos[i1] - pos[i0];
        final ay = pos[i1 + 1] - pos[i0 + 1];
        final az = pos[i1 + 2] - pos[i0 + 2];
        final bx = pos[i2] - pos[i0];
        final by = pos[i2 + 1] - pos[i0 + 1];
        final bz = pos[i2 + 2] - pos[i0 + 2];
        var nx = ay * bz - az * by;
        var ny = az * bx - ax * bz;
        var nz = ax * by - ay * bx;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len > 0) {
          nx /= len;
          ny /= len;
          nz /= len;
        } else {
          nx = 0;
          ny = 0;
          nz = 1;
        }
        final tri = ByteData(50);
        var o = 0;
        void putFloat(double v) {
          tri.setFloat32(o, v, Endian.little);
          o += 4;
        }
        putFloat(nx);
        putFloat(ny);
        putFloat(nz);
        putFloat(pos[i0]);
        putFloat(pos[i0 + 1]);
        putFloat(pos[i0 + 2]);
        putFloat(pos[i1]);
        putFloat(pos[i1 + 1]);
        putFloat(pos[i1 + 2]);
        putFloat(pos[i2]);
        putFloat(pos[i2 + 1]);
        putFloat(pos[i2 + 2]);
        tri.setUint16(o, 0, Endian.little);
        sink.add(tri.buffer.asUint8List());
      }
    }
  }

  /// M289 — STL export for a part: writes the live solids' tessellations as
  /// binary STL, without needing the OCCT kernel. A part is a mesh on this
  /// side already, so the file can be produced from Dart.
  Future<String?> partExportStl(String name) async {
    if (_docsDir == null) return null;
    final wasLoaded = parts.containsKey(name);
    final p = wasLoaded ? parts[name]! : await _loadPartModel(name);
    try {
      if (wasLoaded) await savePart(name);
      final meshes = <OcctMeshData>[
        for (final f in p.features)
          if (f.solid != null) f.solid!.mesh,
      ];
      if (meshes.isEmpty) {
        toast(L.current.msgNothingToExportYet);
        return null;
      }
      final exportDir = Directory('${_cacheRoot.path}/export');
      if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
      final out = File('${exportDir.path}/$name.stl');
      final sink = out.openWrite();
      try {
        writeBinaryStl(sink, meshes);
        await sink.flush();
      } finally {
        await sink.close();
      }
      return out.path;
    } finally {
      if (!wasLoaded) p.dispose();
    }
  }

  /// M218 — ONE sketch of a part, as DXF, for the share sheet / Files
  /// exporter. Null (with a reason on screen) when there is nothing to write.
  ///
  /// A part exports as STEP because a part is solids; a single sketch inside
  /// it is 2D geometry and therefore exports exactly like a sketch document —
  /// same file format, same Defpoints rule for construction geometry
  /// ([_writeExportDxf]), so what a laser cutter reads does not depend on
  /// which of the two places the drawing happens to live in.
  ///
  /// The file holds the sketch's OWN 2D coordinates, not its placement in the
  /// part. That is what a DXF is, and it is what the receiving machine wants:
  /// a profile on the XZ plane 40 mm up would otherwise arrive 40 mm off its
  /// own origin for no gain whatsoever.
  ///
  /// [partName] is the document, [sketchName] the child sketch inside it. An
  /// open part is flushed first so the export is never stale; a part that is
  /// NOT open loads headlessly and is thrown away again (M214 — exporting is
  /// not navigation, and it must not add a tab).
  Future<String?> childSketchExportPath(
      String partName, String sketchName) async {
    if (_docsDir == null) return null;
    final wasLoaded = parts.containsKey(partName);
    final p = wasLoaded ? parts[partName]! : await _loadPartModel(partName);
    try {
      if (wasLoaded) await savePart(partName);
      final cs = p.sketchByName(sketchName);
      if (cs == null) {
        Log.w('export', '"$partName" has no sketch "$sketchName"');
        return null;
      }
      if (cs.model.geometry.isEmpty) {
        toast(L.current.msgNothingToExportEmpty(sketchName));
        return null;
      }
      final exportDir = Directory('${_cacheRoot.path}/export');
      if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
      // Named for BOTH, because a child sketch is identified by both: every
      // part of the gallery is free to call its first sketch "Sketch1", and
      // three of those in the Files app under one name help nobody.
      final out = File('${exportDir.path}/$partName - $sketchName.dxf');
      // A stale file from an earlier export must never be what gets shared
      // (partExportStep's rule, for the same reason: a failed write leaves the
      // previous export in place and only a null return stands between it and
      // the share sheet).
      if (out.existsSync()) {
        try {
          out.deleteSync();
        } catch (e) {
          Log.w('export', 'could not clear stale ${out.path}: $e');
        }
      }
      final storage = File('${_partSketchDir(partName).path}/$sketchName.dxf');
      final path = _writeExportDxf(cs.model, out,
          storage: storage.existsSync() ? storage : null);
      if (path == null || !out.existsSync() || out.lengthSync() == 0) {
        toast(L.current.msgDxfExportFailed);
        Log.w('export', 'DXF "$partName/$sketchName" produced nothing');
        return null;
      }
      Log.i(
          'export',
          'DXF "$partName/$sketchName": entities=${cs.model.geometry.length} '
              'bytes=${out.lengthSync()}');
      return path;
    } catch (e, st) {
      Log.e('export', 'DXF "$partName/$sketchName" failed', e, st);
      toast(L.current.msgDxfExportFailed);
      return null;
    } finally {
      if (!wasLoaded) p.dispose();
    }
  }

  // ---- gallery routing: one card menu, two document kinds ----
  Future<void> deleteDocument(String name) => isAssemblyName(name)
      ? deleteAssembly(name)
      : isPartName(name)
          ? deletePart(name)
          : deleteSketch(name);
  Future<bool> renameDocument(String from, String to) => isAssemblyName(from)
      ? renameAssembly(from, to)
      : isPartName(from)
          ? renamePart(from, to)
          : renameSketch(from, to);
  Future<String?> duplicateDocument(String name) => isAssemblyName(name)
      ? duplicateAssembly(name)
      : isPartName(name)
          ? duplicatePart(name)
          : duplicateSketch(name);

  // ---- child-sketch flow (Start 2D Sketch -> plane pick -> 2D env) ----
  /// True while the origin planes were switched on BY the plane pick, so
  /// cancelling or finishing it only hides the ones we showed and leaves a
  /// plane the user enabled in the browser alone.
  bool _planesAutoShown = false;

  void startPartSketch() {
    final p = currentPart;
    if (p == null) return;
    // Inventor: the origin planes are offered automatically only while the
    // part is still EMPTY (the first sketch). Once a body exists you sketch on
    // its faces — a plane is then offered only if switched on in the browser.
    _planesAutoShown = !p.hasSolid;
    if (_planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = true;
    }
    pickPlane = true;
    toast(L.current.msgSelectPlaneForSketch);
    notifyListeners();
  }

  void cancelPlanePick() {
    final p = currentPart;
    pickPlane = false;
    if (p != null && _planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
    }
    _planesAutoShown = false;
    notifyListeners();
  }

  /// The 3D viewport reports the tapped plane: orient the camera to it and
  /// drop into the EXACT same 2D sketch environment (fresh Layer 1).
  void planePicked(String key) {
    final p = currentPart;
    if (p == null || !pickPlane) return;
    // M167 — the pick may be a USER WORK PLANE. `_hitOrigin` has offered them
    // since M151 and reports them as `wp:<seq>`, but everything downstream
    // here assumed one of the three origin keys: `planeFrame(key)` does not
    // know 'wp:1', so tapping a work plane did nothing at all — neither to
    // start a sketch on it nor to offset from it.
    WorkPlane? wp;
    if (key.startsWith('wp:')) { // WorkPlane.id
      for (final w in p.workPlanes) {
        if (w.id == key) {
          wp = w;
          break;
        }
      }
    }
    if (key.startsWith('wp:') && wp == null) return; // stale row
    // M151 — a work plane is being defined: the pick is an INPUT, not a
    // request to start a sketch.
    if (workPlaneArm != null) {
      _workPlaneInput(wp?.frame ?? planeFrame(key), wp?.name ?? key.toUpperCase());
      return;
    }
    // M228 — likewise for the split panel.
    if (splitSession != null && splitSession!.frame == null) {
      _splitPlaneInput(wp?.frame ?? planeFrame(key),
          wp?.name ?? '${key.toUpperCase()} Plane');
      return;
    }
    // M345 — ...and likewise for a paste that is waiting for its plane. Same
    // shape as the two above: the pick is an INPUT to a command that is
    // already running, not a request to start an empty sketch.
    if (_pasteOnPickedPlane(
        wp == null ? key : kWorkPlaneKey, wp?.frame)) {
      return;
    }
    pickPlane = false;
    if (_planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
    }
    _planesAutoShown = false;
    // Origin planes get their canonical camera. A work plane does NOT get one
    // opens (M80).
    if (wp != null) {
      startSketchOnWorkPlane(wp, alreadyArmed: true);
      return;
    }
    p.camera.orientToPlane(key);
    final sk = SketchModel(p.nextSketchName());
    // M91: stamped with the creation order so it lands at the BOTTOM of the
    // browser timeline, under the extrusions that already exist.
    p.appendChildSketch(ChildSketch(sk, key, null, true, false, p.nextSeq()));
    _admitNewSketchRow(p);
    p.dirty = true;
    activeChild = sk;
    sketchZoomNeedsFit = true;
    _reanalyze();
    Log.i('part', 'child sketch "${sk.name}" on $key of "${p.name}"');
    startNewLayer(); // enters edit + notifies, like createNamedSketch
  }

  /// M181 — the ONE way a sketch is created on a work plane.
  ///
  /// "I still can't make a sketch on a placed work plane" has now been
  /// reported four times, and every fix so far went into the 3D tap: M151
  /// built the path, M167 taught [planePicked] the `wp:N` key, M173 added a
  /// log line saying which surface won. The tap is the fragile part — it has
  /// to beat a solid face and, on an empty part, the three origin planes the
  /// command itself just switched on — and it was also the ONLY way in. The
  /// browser's work-plane menu offered Edit Offset, Hide and Delete, and no
  /// way to sketch on the thing, which is the first entry in Inventor's.
  ///
  /// So this exists as a plain command taking the plane as an argument: no
  /// ray, no depth race, nothing to miss. The tap now routes through it too,
  /// which also ends a smaller mess — the tap stored the sketch as a FACE
  /// sketch and this path stored it as a work-plane sketch, two encodings of
  /// one thing.
  void startSketchOnWorkPlane(WorkPlane w, {bool alreadyArmed = false}) {
    final p = currentPart;
    if (p == null) return;
    // M345 — a paste armed on a plane lands here too when the plane is named
    // from the browser rather than tapped in the viewport.
    if (_pasteOnPickedPlane(kWorkPlaneKey, w.frame)) return;
    if (!alreadyArmed) {
      // Reached from the browser rather than mid-pick: whatever else was
      // armed is not what the user meant any more.
      if (workPlaneArm != null) cancelWorkPlane();
      cancelWorkFeature(); // M215 — same reason as the line above
      cancelPlanePick();
    }
    pickPlane = false;
    if (_planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
    }
    _planesAutoShown = false;
    // Face the plane from the side the camera is already on, exactly as a
    // sketch on a solid face does — the model must not flip around behind you
    // when the editor opens.
    orientToSurface(p, w.frame);
    final sk = SketchModel(p.nextSketchName());
    // M167 — a sketch on a work plane carries that plane's FRAME, the same way
    // a sketch on a solid face carries the face's. `sketchFrameOf` prefers the
    // stored frame over `planeFrame(plane)`, so this needs no new plane kind
    // and it serialises with the frame it already writes. No faceRef, so the
    // M153/M166 face-following pass correctly leaves it alone: a work plane
    // moves because the USER moves it, not because a solid did.
    p.appendChildSketch(
        ChildSketch(sk, kWorkPlaneKey, w.frame, true, false, p.nextSeq()));
    _admitNewSketchRow(p);
    p.dirty = true;
    activeChild = sk;
    sketchZoomNeedsFit = true;
    _reanalyze();
    Log.i('part',
        'child sketch "${sk.name}" on ${w.name} (${w.id}) of "${p.name}"');
    startNewLayer(); // enters edit + notifies, like createNamedSketch
  }

  /// Turns the part camera to look at [fr] from the side it is already on,
  /// with [fr]'s own u axis on screen x.
  ///
  /// A plane can be faced from either side. Taking the nearer one is what
  /// stops the model flipping around behind you when a sketch opens — the old
  /// face-pick code always used -n on the belief that a visible face satisfies
  /// n·dir < 0; the device measurement (mesh3d convention log) showed the
  /// opposite — the camera sits at +dir and a face you can see has n·dir > 0 —
  /// so -n put the camera INSIDE the solid, looking at the face from behind.
  ///
  /// M211 — the FRAME, not just its normal: see [PartCamera.orientToFrame].
  /// Aiming down the normal alone left the roll wherever the orbit had it, and
  /// the sketch camera does not have that freedom, so the model spun as the
  /// sketch opened.
  void orientToSurface(PartModel p, PlaneFrame fr) {
    final dot = fr.n.dot(p.camera.dir);
    p.camera.orientToFrame(fr, flip: dot < 0);
  }

  /// Browser eye on a (consumed) child sketch — Inventor's per-sketch
  /// Visibility toggle. Persisted with the part.
  void toggleSketchVisible(ChildSketch cs) {
    cs.visible = !cs.visible;
    final p = currentPart;
    if (p != null) {
      p.dirty = true;
      if (curTab != null) savePart(curTab!);
    }
    notifyListeners();
  }

  /// M91 — moves the **End of Part** marker so that [after] features are
  /// built. The part-level twin of [setEndOfSketch]: everything below is
  /// suppressed — not built into the body, not drawn, greyed in the browser —
  /// which is Inventor's rollback.
  /// The ONE way the End of Part marker moves.
  ///
  /// Total and idempotent: out-of-range values clamp, a no-op returns early,
  /// and dropping the marker on the last row stores [kEopAtEnd] rather than
  /// that row's number — otherwise the marker silently stops being "at the
  /// end" and every feature created afterwards comes out suppressed.
  void setEndOfPart(int after) {
    final p = currentPart;
    if (p == null) return;
    final n = partTimeline(p).length; // M113 — rows, not features
    final v = after.clamp(0, n);
    if (v == p.eopAfter.clamp(0, n)) return;
    p.eopAfter = v >= n ? kEopAtEnd : v;
    Log.i('part',
        'End of Part -> after $v of $n rows${v >= n ? " (at end)" : ""}');
    applyEndOfPart(p);
    // M122 — RECOMPUTE. Rolling the marker only flipped `rolledBack`; the JOIN
    // chain was never rebuilt, so `consumedByJoin` stayed as it was. Suppress
    // Extrusion2 and Extrusion1 remained flagged as folded into it — one hidden
    // because it is rolled back, the other because it is "consumed" by a
    // feature that no longer exists. Both invisible, and the whole body
    // appeared to vanish when only the last extrusion should have.
    recomputeAllFeatures(p, partKernel);
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// Re-applies the End of Part marker after [PartModel.appendChildSketch]
  /// moved it past a newly created sketch.
  ///
  /// Only does work when something WAS suppressed: with the marker already at
  /// the end nothing is rolled back and nothing has to rebuild. When it was
  /// parked mid-tree, admitting the new row un-suppresses the features it
  /// moved past, so those have to be recomputed to exist again.
  void _admitNewSketchRow(PartModel p) {
    if (applyEndOfPart(p) && partKernel.available) {
      recomputeAllFeatures(p, partKernel);
    }
  }

  /// Inventor's "Delete All Features Below EOP" — drops every suppressed
  /// feature in one step, then parks the marker at the end.
  int deleteBelowEndOfPart() {
    final p = currentPart;
    if (p == null) return 0;
    final victims = [for (final f in p.features) if (f.rolledBack) f];
    if (victims.isEmpty) {
      toast(L.current.msgNothingBelowEop);
      return 0;
    }
    _partCheckpoint(p); // M182 — deleting below EOP must be undoable
    for (final f in victims) {
      f.disposeSolid();
      p.features.remove(f);
    }
    Log.i('part',
        '"${p.name}": deleted ${victims.length} feature(s) below End of Part');
    p.eopAfter = kEopAtEnd; // parks at the end AND keeps it there
    applyEndOfPart(p);
    recomputeAllFeatures(p, partKernel);
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
    return victims.length;
  }

  /// Inventor's **Share Sketch** (M84). A consumed sketch is normally locked
  /// away under the feature that swallowed it; sharing publishes it back to
  /// the top level of the browser so a SECOND feature can use it. Inventor
  /// also expects a shared sketch to be visible — its own workflow says to
  /// turn Visibility on before sharing — so this does that in one step rather
  /// than leaving an invisible top-level row.
  ///
  /// A no-op on a sketch nothing has consumed: there is nothing to free.
  /// M152 — delete a child sketch from the browser's context menu.
  ///
  /// The sketch menu has had Edit / Hide / Share / Unshare since M107 and no
  /// Delete, while layers, features and bodies all had one. Nothing prevented
  /// it; the item was simply never added.
  ///
  /// A CONSUMED sketch is refused rather than cascaded: deleting it would take
  /// the extrusion built on it with it, and silently destroying a feature the
  /// user did not name is worse than making them delete that feature first.
  /// The menu already hides the item in that case; this is the guard behind it.
  bool deleteChildSketch(ChildSketch cs) {
    final p = currentPart;
    if (p == null) return false;
    if (sketchIsConsumed(p, cs)) {
      toast(L.current.msgUsedByFeature(cs.model.name));
      return false;
    }
    _partCheckpoint(p); // M182 — deleting a sketch must be undoable
    // Leaving the sketch open in the 2D editor while its owner disappears is
    // how you get an editor writing back into a part that no longer has it.
    if (activeChild == cs.model) activeChild = null;
    p.childSketches.remove(cs);
    p.dirty = true;
    Log.i('part', 'child sketch "${cs.model.name}" deleted from "${p.name}"');
    _reanalyze();
    if (curTab != null) savePart(curTab!);
    notifyListeners();
    return true;
  }

  void shareSketch(ChildSketch cs) {
    final p = currentPart;
    if (p == null || cs.shared || !sketchIsConsumed(p, cs)) return;
    cs.shared = true;
    cs.visible = true;
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// Inventor's **Unshare** — offered only while a single feature consumes the
  /// sketch (see [canUnshareSketch]). The sketch drops back under its parent
  /// feature; visibility follows Inventor's consumed default and goes off, so
  /// the result is indistinguishable from a sketch that was never shared.
  void unshareSketch(ChildSketch cs) {
    final p = currentPart;
    if (p == null || !canUnshareSketch(p, cs)) return;
    cs.shared = false;
    cs.visible = false;
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  // ---- work planes (M151) -------------------------------------------------
  /// Which work plane is being defined, or null when none is armed. The
  /// viewport shows the origin planes and highlights faces while this is set,
  /// because the pick targets are exactly the ones sketch placement already
  /// knows how to hover.
  WorkPlaneKind? workPlaneArm;

  /// Offset distance in mm for the next offset plane. Signed on purpose —
  /// entering a negative value is how you go the other way, which is one less
  /// thing to build than a Flip button.
  double workPlaneOffset = 10;

  /// M229 — the angle a new [WorkPlaneMethod.angleToPlaneAroundEdge] plane is
  /// built at, and what the value field writes back. 45 is a starting point,
  /// not a destination: the field opens on the plane the moment it exists, the
  /// same order M169 gave the offset (get close, then make it right).
  double workPlaneAngle = 45;

  /// Inputs collected so far. Offset needs one, midplane two.
  final List<PlaneFrame> _wpPicks = [];
  final List<String> _wpNames = [];

  /// Arm work plane creation. Cancels itself if the same kind is armed twice,
  /// so the ribbon button toggles.
  void startWorkPlane(WorkPlaneKind kind) {
    // M247 — the assembly's twin. ONE command per method, routed here rather
    // than duplicated in the ribbon: the button, the flyout entry, the label
    // and the toggle contract are the same in both documents, and only what
    // it is armed ON differs.
    final asm = currentAssembly;
    if (asm != null) return _armAsmWorkFeature(asm, planeKind: kind);
    final p = currentPart;
    if (p == null) return;
    if (workPlaneArm == kind) return cancelWorkPlane();
    workPlaneArm = kind;
    _wpPicks.clear();
    _wpNames.clear();
    pickPlane = true;
    // Offer the origin planes for the duration, exactly as the sketch flow
    // does — without them an empty part has nothing to pick at all.
    _planesAutoShown = !p.hasSolid;
    if (_planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = true;
    }
    toast(kind == WorkPlaneKind.offset
        ? L.current.msgSelectPlaneToOffsetFrom
        : L.current.msgSelectFirstParallel);
    notifyListeners();
  }

  // ---- M168 Slice Graphics ------------------------------------------------

  /// Inventor's Slice Graphics (F7): inside a sketch, cut away everything
  /// between the viewer and the sketch plane. A DISPLAY state — nothing enters
  /// the timeline, and it clears when the sketch closes.
  bool sliceGraphics = false;

  final Map<String, KernelSolid> _sliceCache = {};
  String _sliceKey = '';
  // M222 — the outlines derived from those cuts, memoised on the same inputs.
  String _sliceFacesKey = '';
  List<SectionSlice> _sliceFaces = const [];

  /// Whether the command is offered at all. Inventor greys it out with no
  /// solid to cut; here it is not shown, per M157 — a button that is visible
  /// must do something, because silence reads as broken.
  bool get canSliceGraphics {
    final p = currentPart;
    return p != null && activeChild != null && p.hasSolid;
  }

  void toggleSliceGraphics() {
    if (!canSliceGraphics) return;
    sliceGraphics = !sliceGraphics;
    if (!sliceGraphics) _clearSliceCache();
    Log.i('slice', 'Slice Graphics ${sliceGraphics ? "ON" : "OFF"}');
    notifyListeners();
  }

  /// M168/M222 — the section faces of every sliced body, in the open sketch's
  /// (u,v), as closed OUTLINES and grouped by the body they cut. Empty when
  /// not slicing.
  ///
  /// Grouped, because ISO 128 hatches adjacent parts differently and the same
  /// part identically throughout — so the unit the painter works in is the
  /// body, not the triangle. Outlines, because the triangles are tessellation
  /// and drawing them is what put triangle edges on the screen (M222).
  ///
  /// Memoised on the sketch plane and the identity of every cut mesh, the same
  /// key [slicedSolid] uses: this runs from `paint`, and walking every mesh of
  /// every body per frame is the kind of cost M159/M75 were about.
  List<SectionSlice> sectionSlices() {
    final p = currentPart;
    final cs = activeChild == null ? null : p?.sketchByName(activeChild!.name);
    if (!sliceGraphics || p == null || cs == null) return const [];
    final fr = sketchFrameOf(cs);
    final byBody = <String, List<List<Offset>>>{};
    final sig = StringBuffer()
      ..write(fr.origin.x)
      ..write(',')
      ..write(fr.origin.y)
      ..write(',')
      ..write(fr.origin.z)
      ..write(',')
      ..write(fr.n.x)
      ..write(',')
      ..write(fr.n.y)
      ..write(',')
      ..write(fr.n.z);
    for (final f in p.features) {
      final whole = f.solid;
      if (whole == null || !f.visible || f.consumedByJoin || f.rolledBack) {
        continue;
      }
      final cut = slicedSolid(f.name, whole);
      if (cut == null) continue; // not sliced: nothing was exposed
      sig
        ..write(';')
        ..write(f.bodyName)
        ..write(':')
        ..write(identityHashCode(cut.mesh));
      byBody
          .putIfAbsent(f.bodyName, () => [])
          .addAll(sectionTrianglesAt(cut.mesh, fr));
    }
    final key = sig.toString();
    if (key == _sliceFacesKey) return _sliceFaces;
    final order = p.bodyNames;
    final out = <SectionSlice>[];
    byBody.forEach((body, tris) {
      final loops = sectionOutlines(tris);
      if (loops.isEmpty) return;
      final i = order.indexOf(body);
      out.add(SectionSlice(body, loops, i < 0 ? out.length : i));
    });
    _sliceFacesKey = key;
    _sliceFaces = out;
    return out;
  }

  /// M172 — model units per SCREEN PIXEL in whatever view is in front.
  ///
  /// One number, because every scrubbable field has to agree: a dimension box
  /// in the sketch and an extrude depth in a dialog must move in the same
  /// steps, or the same gesture means two different things depending on which
  /// field you grabbed.
  ///
  /// In a sketch that is the 2D zoom. In a part it is the orthographic
  /// camera's half-height over the viewport half-height — the same conversion
  /// the 3D pan uses — so the step follows what is actually on screen.
  double get viewUnitsPerPixel {
    if (activeChild != null || currentPart == null) {
      return zoom > 0 && zoom.isFinite ? 1.0 / zoom : 0.05;
    }
    final h = currentPart!.camera.halfH;
    final px = viewportHeightPx;
    if (!h.isFinite || h <= 0 || px <= 0) return 0.05;
    return (2 * h) / px;
  }

  /// Viewport height in logical pixels, published by the 3D view so a dialog
  /// can convert without owning a BuildContext. Falls back to a sane default
  /// before the first frame.
  double viewportHeightPx = 800;

  // ---- M169 work-plane selection, drag and exact entry ---------------------

  /// The work plane the user has tapped. Inventor selects on click and shows
  /// its drag arrows; a second tap elsewhere clears it.
  WorkPlane? selectedWorkPlane;

  /// Open value editor for [selectedWorkPlane]'s offset, mirroring Inventor's
  /// dynamic-dimension field: it appears WITH the drag, carries the live
  /// value, and typing an exact number wins over where the finger stopped.
  bool workPlaneOffsetEditing = false;

  /// The offset the current drag started from, so a cancel restores it and
  /// the drag is always measured from a fixed base rather than accumulating.
  double? _wpDragFrom;

  /// True while [w] may be moved by dragging it in the 3D viewport.
  ///
  /// M252 — a committed work plane is SET. Until now any plane was draggable
  /// for as long as it existed: pointer-down on one in the viewport armed a
  /// drag and a tap on one opened its offset field, so pressing OK settled
  /// nothing, and a one-finger orbit that started on a plane moved the plane
  /// instead of the view. Reported as "the plane is set but still when i drag
  /// it goes directly into edit mode ... it should be really set as soon as i
  /// press ok. only editable by longpressing in the Modell browser".
  ///
  /// So arming is explicit now, and there are exactly two ways in: "Edit
  /// Offset" on the plane's long-press menu in the model browser, and the
  /// drag that CREATES a plane (which has not been OK'd yet — see
  /// [commitWorkPlaneCreate]). Both leave the offset field open on this
  /// plane, which is the same state this asks about, and committing or
  /// cancelling the value closes it and sets the plane again.
  bool workPlaneDraggable(WorkPlane w) =>
      workPlaneOffsetEditing &&
      identical(selectedWorkPlane, w) &&
      w.offsetEditable;

  /// Arm [w] for editing: select it AND open its value field.
  ///
  /// M254 — "wenn ich im context menu versatz bearbeiten klicke passiert
  /// nichts". The menu handler did this inline, as [selectWorkPlane] followed
  /// by `workPlaneOffsetEditing = true`, and that cannot work: the flag is a
  /// plain field and does not notify, and [selectWorkPlane] RETURNS EARLY when
  /// the plane is already selected — which it always is, because tapping the
  /// row is how you reach its menu. The log has it twice in a row:
  ///
  ///     browser: tap  wp:6            (selects; editing false)
  ///     browser: menu wp:6 -> wpOffset (flag true; nobody rebuilds)
  ///
  /// M252 is what made it matter — before it, tapping the row opened the field
  /// too, so the menu never had to work on its own.
  void editWorkPlaneValue(WorkPlane w) {
    selectedWorkPlane = w;
    _wpDragFrom = null;
    workPlaneOffsetEditing = w.valueEditable;
    // A midplane has no single number behind it. Saying so beats opening a
    // field on nothing, and beats the silence this method exists to end.
    if (!w.valueEditable) toast(L.current.msgPlaneHasNoOffset(w.name));
    notifyListeners();
  }

  /// Tapping a work plane's row selects it; tapping it AGAIN clears it.
  ///
  /// M254 — "ausserdem ist die work plane im Modell browser immer
  /// gehighlighted". Nothing ever cleared the selection. [selectWorkPlane]
  /// early-returns on the plane already selected, so a second tap could not
  /// undo the first, and no other path ever passed null. A body row has
  /// toggled since M97; this is the same gesture on the same kind of row.
  void toggleWorkPlaneSelected(WorkPlane w) =>
      selectWorkPlane(identical(selectedWorkPlane, w) ? null : w);

  void selectWorkPlane(WorkPlane? w) {
    if (identical(selectedWorkPlane, w)) return;
    selectedWorkPlane = w;
    workPlaneOffsetEditing = false;
    _wpDragFrom = null;
    notifyListeners();
  }

  /// A drag has begun on [w]. Records where it started from.
  void beginWorkPlaneDrag(WorkPlane w) {
    if (!w.offsetEditable) {
      // A plane with no recorded base (a midplane, or one saved before M162)
      // has nothing to measure from — say so instead of moving nothing.
      toast(L.current.msgPlaneHasNoOffset(w.name));
      return;
    }
    selectedWorkPlane = w;
    _wpDragFrom = w.offset ?? 0;
    workPlaneOffsetEditing = true; // the field appears WITH the drag
    notifyListeners();
  }

  /// Live drag: [deltaMm] is the pointer travel projected onto the plane
  /// NORMAL, in model mm. Applied against the value the drag started from.
  void updateWorkPlaneDrag(double deltaMm) {
    final w = selectedWorkPlane, from = _wpDragFrom;
    if (w == null || from == null || !deltaMm.isFinite) return;
    if (!w.setOffset(from + deltaMm)) return;
    currentPart?.dirty = true;
    notifyListeners(); // the scene signature carries the position (M165)
  }

  /// The drag ended. The field stays open so an exact value can be typed —
  /// which is the whole point of Inventor's dynamic input: the drag gets you
  /// close, the number makes it right.
  void endWorkPlaneDrag() {
    final w = selectedWorkPlane;
    _wpDragFrom = null;
    if (w == null) return;
    Log.i('part', 'work plane "${w.name}" dragged -> ${w.def}');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// Commits a typed offset. Returns false when the text is not a number, so
  /// the field can stay open rather than silently discarding what was typed.
  bool commitWorkPlaneOffset(String text) {
    final w = selectedWorkPlane;
    if (w == null) return false;
    final v = parseValueExpr(text); // the same grammar every dialog uses
    if (v == null || !v.isFinite) return false;
    // M229 — the field edits the plane's ONE number, and which number that is
    // depends on the plane. Asking the plane beats a second field and a second
    // flag for what is the same gesture on the same widget.
    final ok = w.kind == WorkPlaneKind.angle
        ? setWorkPlaneAngle(w, v)
        : setWorkPlaneOffset(w, v);
    if (!ok) return false;
    workPlaneOffsetEditing = false;
    notifyListeners();
    return true;
  }

  /// M229 — the angle twin of [setWorkPlaneOffset].
  bool setWorkPlaneAngle(WorkPlane wp, double deg) {
    if (currentAssembly == null && currentPart == null) return false;
    if (!wp.angleEditable) return false;
    if (!wp.setAngle(deg)) return false;
    workPlaneAngle = deg; // the next one starts from what you last used
    Log.i('part', 'work plane "${wp.name}" -> ${wp.def}');
    _workFeatureTouched();
    return true;
  }

  /// M172 — a scrub set the offset directly (the field was dragged rather than
  /// the plane). Absolute, unlike [updateWorkPlaneDrag], which is measured
  /// from where a viewport drag began.
  void updateWorkPlaneDragAbsolute(double mm) {
    final w = selectedWorkPlane;
    if (w == null || !mm.isFinite) return;
    // M229 — a scrub on the field moves whichever number the plane carries;
    // on an angle plane those are degrees, which is also what the scrub steps
    // in (the field passes the plane's own unit).
    final ok = w.kind == WorkPlaneKind.angle ? w.setAngle(mm) : w.setOffset(mm);
    if (!ok) return;
    // M247 — no save and no bump on a live scrub: this fires per frame, and
    // an assembly work plane's frame is in the scene signature already, so
    // the device sees the move without the heavy push being forced. The save
    // comes when the scrub commits.
    currentPart?.dirty = true;
    notifyListeners();
  }

  /// M170 — arrow-key nudge, for the Magic Keyboard. Inventor nudges a
  /// dragged value with the arrows; on a keyboard that is how you get an exact
  /// number without letting go of what you are looking at. Shift takes the
  /// coarse step, exactly as it does everywhere else in this app.
  void nudgeWorkPlaneOffset(int steps, {bool coarse = false}) {
    final w = selectedWorkPlane;
    if (w == null || !w.offsetEditable) return;
    final v = (w.offset ?? 0) + steps * (coarse ? 1.0 : 0.1);
    if (!w.setOffset(v)) return;
    _workFeatureTouched();
  }

  /// Esc: put the plane back where the drag started and close the field.
  void cancelWorkPlaneOffset() {
    final w = selectedWorkPlane;
    final from = _wpDragFrom;
    if (w != null && from != null) w.setOffset(from);
    _wpDragFrom = null;
    workPlaneOffsetEditing = false;
    notifyListeners();
  }

  void _clearSliceCache() {
    for (final s in _sliceCache.values) {
      s.dispose();
    }
    _sliceCache.clear();
    _sliceKey = '';
    _sliceFacesKey = '';
    _sliceFaces = const [];
  }

  /// M291 — THE ONE SECTION IN FRONT, whatever asked for it.
  ///
  /// Two commands produce a cut and they are the same cut: the part's own
  /// section view (half / quarter / three-quarter, from the Appearance panel)
  /// and Slice Graphics inside a sketch, which is a half section at the
  /// sketch's own plane and nothing more. M168 built the second as its own
  /// state with its own cutter; this is where they became one value.
  ///
  /// Slice Graphics wins while a sketch is open, deliberately: it is a
  /// SKETCHING aid — you turned it on to see what you are drawing into — and a
  /// section view left on from before must not decide what you can see of the
  /// plane you are drawing on. Ending the sketch brings the section back
  /// untouched, because neither state was ever overwritten.
  ///
  /// Null means "draw the model whole".
  SectionView? get activeSection {
    final p = currentPart;
    if (p != null && sliceGraphics) {
      final cs = activeChild == null ? null : p.sketchByName(activeChild!.name);
      if (cs != null) return SectionView.slice(sketchFrameOf(cs));
    }
    // An unfinished quarter view (one plane picked, the command still asking
    // for the second) cuts nothing: see SectionView.complete.
    final own = documentSection;
    return own != null && own.complete ? own : null;
  }

  /// M292 — the section on whatever document is open, part or assembly.
  ///
  /// One getter and one setter, because the two are the same value on two
  /// document types and every command below routes through them — the way
  /// [displayMode] already does. An assembly is sectioned by the same planes,
  /// the same flips and the same offsets; only WHICH solids get cut differs,
  /// and that is [sectionedPiece]'s business, not the command's.
  SectionView? get documentSection =>
      currentAssembly?.section ?? currentPart?.section;

  set documentSection(SectionView? v) {
    final a = currentAssembly;
    if (a != null) {
      a.section = v;
      return;
    }
    currentPart?.section = v;
  }

  /// The section stand-in for [solid], or null to draw it whole.
  ///
  /// Cached against the section's signature and the identity of every mesh in
  /// the scene: the cut is a full boolean and must not run per frame. A null
  /// result (no kernel, or the cut failed) deliberately means "show it whole"
  /// — a failed section must never make the part disappear.
  ///
  /// Still called [slicedSolid] because that is what every consumer of it has
  /// been calling since M168 — visibleSolids, the payload, the signature, the
  /// triangle budget, the thumbnails — and renaming it would be the only
  /// change in six files that carried no meaning.
  KernelSolid? slicedSolid(String id, KernelSolid solid) {
    final view = activeSection;
    if (view == null) return null;
    final p = currentPart;
    if (p == null) return null;
    final key = view.signature;
    if (key != _sliceKey) {
      _clearSliceCache();
      _sliceKey = key;
    }
    final hit = _sliceCache['$id:${identityHashCode(solid.mesh)}'];
    if (hit != null) return hit;
    final cut = sectionCutSolid(partKernel, originExtentBounds(p), solid, view);
    if (cut == null) return null;
    _sliceCache['$id:${identityHashCode(solid.mesh)}'] = cut;
    Log.i('slice', 'sectioned $id (${view.mode.id})');
    return cut;
  }

  // ---- M291: the section-view commands ------------------------------------
  //
  // Inventor's flow, and the reason this needed no new picking machinery: pick
  // any plane or planar face, Flip to swap which side goes, drag or type an
  // offset, Continue for the second plane on the two-plane commands, End
  // Section View to get the model back. The pick is the SAME hit test the work
  // planes use (Viewport3D._planeOrFaceAt), which is what makes an origin
  // plane, a work plane and a face all valid targets without three code paths.

  /// The section command waiting for a plane, or null when none is running.
  SectionMode? sectionArm;

  /// What has been picked so far while [sectionArm] is running. Becomes the
  /// part's [PartModel.section] as soon as it is complete.
  SectionView? sectionDraft;

  /// True while the viewport should hand taps to the section command.
  bool get sectionPicking => sectionArm != null;

  /// Whether the commands are offered at all. Inventor greys them out with
  /// nothing to cut; here they are not shown (M157 — a visible button that
  /// does nothing reads as broken).
  bool get canSection =>
      activeChild == null &&
      (currentAssembly != null
          ? currentAssembly!.occurrences.any((o) => o.visible && o.loaded)
          : currentPart?.hasSolid == true);

  /// The section currently applied to the open document, if any.
  SectionView? get partSection => documentSection;

  /// Start one of the three commands. Starting one while another section is up
  /// replaces it, which is what Inventor's own panel does — the three buttons
  /// are one control with three settings, not three independent toggles.
  void beginSection(SectionMode mode) {
    if (!canSection) return;
    sectionArm = mode;
    sectionDraft = null;
    _clearSliceCache();
    _clearAsmSectionCache();
    // The viewport is now waiting for something and must say so: a command
    // that arms silently reads as a button that did nothing (M157's rule,
    // applied to the moment after the tap rather than to the button).
    toast(L.current.msgPickSectionPlane);
    Log.i('slice', 'section: ${mode.id} armed');
    notifyListeners();
  }

  /// A plane or planar face was picked in the viewport.
  ///
  /// The first pick shows the cut immediately for a half section; on the
  /// two-plane commands nothing is cut until the second lands, because a
  /// quarter view that showed a half first and then changed under you is a
  /// worse answer than one that waits.
  void sectionPlanePicked(PlaneFrame frame, String label) {
    final mode = sectionArm;
    if (mode == null || (currentPart == null && currentAssembly == null)) {
      return;
    }
    final draft = sectionDraft;
    if (draft == null) {
      sectionDraft = SectionView(mode, SectionPlane(frame, label));
    } else {
      sectionDraft = draft.withSecond(SectionPlane(frame, label));
    }
    final now = sectionDraft!;
    if (now.complete) {
      documentSection = now;
      sectionArm = null;
      sectionDraft = null;
      Log.i('slice', 'section: ${now.mode.id} on ${now.planes.length} plane(s)');
    }
    _clearSliceCache();
    _clearAsmSectionCache();
    notifyListeners();
  }

  /// Inventor's Flip: swap which side of plane [i] is removed.
  void flipSectionPlane(int i) {
    final v = documentSection;
    if (v == null || i < 0 || i >= v.planes.length) return;
    documentSection = v.withPlane(i, v.planes[i].flip);
    _clearSliceCache();
    _clearAsmSectionCache();
    notifyListeners();
  }

  /// Inventor's Virtual Movement: slide plane [i] along its own normal.
  void setSectionOffset(int i, double mm) {
    final v = documentSection;
    if (v == null || !mm.isFinite) return;
    if (i < 0 || i >= v.planes.length) return;
    documentSection = v.withPlane(i, v.planes[i].copyWith(offset: mm));
    _clearSliceCache();
    _clearAsmSectionCache();
    notifyListeners();
  }

  /// Inventor's End Section View: the whole model back.
  ///
  /// Also cancels a command that is still asking for a plane, which is what
  /// the same button has to mean while one is running — otherwise a
  /// half-started quarter view has no way out but picking a plane you do not
  /// want.
  void endSection() {
    final had = sectionArm != null || documentSection != null;
    sectionArm = null;
    sectionDraft = null;
    documentSection = null;
    if (!had) return;
    _clearSliceCache();
    _clearAsmSectionCache();
    Log.i('slice', 'section: ended');
    notifyListeners();
  }

  // ---- M292: the same section, applied to an assembly ---------------------
  //
  // One plane in the assembly's world space, and a component's solid in its
  // own frame. The cut brings the PLANE to the solid (sectionFrameInto) rather
  // than the solid to the plane: one transform per component instead of one
  // per triangle, and the placement of the cut result is exactly what it was.

  final Map<String, KernelSolid> _asmSectionCache = {};
  String _asmSectionKey = '';

  void _clearAsmSectionCache() {
    for (final s in _asmSectionCache.values) {
      s.dispose();
    }
    _asmSectionCache.clear();
    _asmSectionKey = '';
  }

  /// The section stand-in for one placed piece of an assembly, or null to draw
  /// it whole.
  ///
  /// [id] is the piece's own key ('occurrence/path'), which is what makes two
  /// occurrences of the SAME part cut differently: they sit at different
  /// placements, so the plane arrives in each one's frame in a different
  /// place, and a cache keyed on the mesh alone would give the second one the
  /// first one's cut. Null means "draw it whole" — a failed section must never
  /// make a component vanish.
  KernelSolid? sectionedPiece(String id, Placement at, KernelSolid solid) {
    final view = activeSection;
    final a = currentAssembly;
    if (view == null || a == null) return null;
    final key = view.signature;
    if (key != _asmSectionKey) {
      _clearAsmSectionCache();
      _asmSectionKey = key;
    }
    final hit = _asmSectionCache['$id:${identityHashCode(solid.mesh)}'];
    if (hit != null) return hit;
    // The extent is the WHOLE assembly's, not the component's: the tool has to
    // swallow everything on its side of the plane, and a box sized to one
    // small component would leave the rest of the assembly uncut.
    final extent = paddedOriginExtent(assemblyContentBounds(a));
    final local = SectionView(
        view.mode,
        _pieceLocal(view.a, at),
        view.b == null ? null : _pieceLocal(view.b!, at));
    final cut = sectionCutSolid(partKernel, extent, solid, local);
    if (cut == null) return null;
    _asmSectionCache['$id:${identityHashCode(solid.mesh)}'] = cut;
    return cut;
  }

  /// One section plane, already flipped and offset, brought into the frame of
  /// a piece placed by [at].
  ///
  /// The flip and the offset are applied FIRST (that is what cutFrame is) and
  /// the result is transported, so the transported plane carries them and the
  /// local SectionPlane needs neither.
  SectionPlane _pieceLocal(SectionPlane p, Placement at) =>
      SectionPlane(sectionFrameInto(p.cutFrame, at), p.label);

  // ---- M174 drag-to-create a work plane -----------------------------------

  /// The plane a NEW work plane is being dragged off, while it is being
  /// dragged. Non-null means a live preview is on screen and nothing has been
  /// committed yet.
  PlaneFrame? wpCreateBase;
  String wpCreateLabel = '';
  double wpCreateOffset = 0;

  /// The preview frame, or null when nothing is being created.
  PlaneFrame? get wpCreatePreview => wpCreateBase == null
      ? null
      : offsetPlaneFrame(wpCreateBase!, wpCreateOffset);

  /// Pointer went down on [base] with the Plane command armed. Nothing is
  /// created yet — Inventor shows the plane following your finger and only
  /// commits when you let go, so a mis-grab costs nothing.
  void beginWorkPlaneCreate(PlaneFrame base, String label) {
    // M260 — Offset, or the generic Plane command, which keeps the same drag.
    if (workPlaneArm != WorkPlaneKind.offset && !workPlaneAutoArmed) return;
    wpCreateBase = base;
    wpCreateLabel = label;
    wpCreateOffset = 0;
    notifyListeners();
  }

  /// Live drag, in model mm along the base normal.
  void updateWorkPlaneCreate(double mm) {
    if (wpCreateBase == null || !mm.isFinite) return;
    wpCreateOffset = mm;
    notifyListeners();
  }

  /// Let go: the plane stays where it was dragged to, and the offset field
  /// opens on it immediately — the value is the thing you almost always want
  /// to correct next, so it should not need a second gesture to reach.
  ///
  /// A drag that never moved commits nothing: that is a mis-tap, and creating
  /// a zero-offset plane on top of its own base is never what was meant.
  void commitWorkPlaneCreate() {
    final base = wpCreateBase;
    final d = wpCreateOffset;
    wpCreateBase = null;
    if (base == null) return;
    if (d.abs() < 1e-6) {
      // M260 — under the generic Plane command a press that never moved is a
      // TAP, and a tap is the first (or second) pick of an inferred method.
      // Leave the command armed and let the viewport's tap handler turn the
      // same contact into a WorkRef; cancelling here is what made the plane
      // tool answer a tap with "drag away to set the offset" and nothing
      // else, which is the report this milestone came from.
      //
      // Order-independent on purpose: the Listener's pointer-up and the
      // GestureDetector's tap can arrive either way round, and neither
      // outcome depends on which won.
      if (workPlaneAutoArmed) {
        notifyListeners();
        return;
      }
      cancelWorkPlane();
      toast(L.current.msgDragAwayToSetOffset);
      return;
    }
    final p = currentPart;
    if (p == null) return;
    _commitWorkPlane(p, WorkPlaneKind.offset, offsetPlaneFrame(base, d),
        'Offset ${d.toStringAsFixed(2)} mm from $wpCreateLabel',
        base: base, offset: d);
    final made = p.workPlanes.isEmpty ? null : p.workPlanes.last;
    if (made != null) {
      selectedWorkPlane = made;
      workPlaneOffsetEditing = true; // straight into editing the value
      workPlaneOffset = d; // the next new plane starts from what you just used
    }
    notifyListeners();
  }

  void cancelWorkPlaneCreate() {
    if (wpCreateBase == null) return;
    wpCreateBase = null;
    notifyListeners();
  }

  void cancelWorkPlane() {
    if (workPlaneArm == null) return;
    workPlaneArm = null;
    pickPlane = false;
    _wpPicks.clear();
    _wpNames.clear();
    final p = currentPart;
    if (p != null && _planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
    }
    _planesAutoShown = false;
    notifyListeners();
  }

  /// One pick arrived. Builds the plane as soon as it has enough of them.
  void _workPlaneInput(PlaneFrame f, String label) {
    final p = currentPart;
    final kind = workPlaneArm;
    if (p == null || kind == null) return;
    _wpPicks.add(f);
    _wpNames.add(label);

    if (kind == WorkPlaneKind.offset) {
      // M162 — remember WHAT it was offset from and by how much, so the
      // distance stays editable instead of being baked into the frame.
      _commitWorkPlane(
          p,
          kind,
          offsetPlaneFrame(f, workPlaneOffset),
          'Offset ${workPlaneOffset.toStringAsFixed(2)} mm from $label',
          base: f,
          offset: workPlaneOffset);
      return;
    }

    if (_wpPicks.length < 2) {
      toast(L.current.msgSelectSecondParallel);
      notifyListeners();
      return;
    }
    final mid = midPlaneFrame(_wpPicks[0], _wpPicks[1]);
    if (mid == null) {
      // Keep the flow ALIVE and drop only the bad second pick: making the user
      // restart from the ribbon after one mis-tap is the kind of small cruelty
      // that makes a tool feel hostile.
      _wpPicks.removeLast();
      _wpNames.removeLast();
      toast(L.current.msgNotParallel);
      notifyListeners();
      return;
    }
    _commitWorkPlane(
        p, kind, mid, 'Midplane between ${_wpNames[0]} and ${_wpNames[1]}');
  }

  void _commitWorkPlane(
      PartModel p, WorkPlaneKind kind, PlaneFrame frame, String def,
      {PlaneFrame? base,
      double? offset,
      Vec3? axisAt,
      Vec3? axisDir,
      double? angle}) {
    final wp = WorkPlane(
        // M223 — a free name, not a COUNT. Deleting Work Plane2 of three and
        // making another handed out "Work Plane3" a second time; work axes and
        // points have used _freeWorkName since M215, and bodies since M155.
        _freeWorkName('Work Plane', {for (final w in p.workPlanes) w.name}),
        p.nextSeq(),
        kind,
        def,
        frame,
        base: base,
        offset: offset,
        axisAt: axisAt,
        axisDir: axisDir,
        angle: angle);
    p.workPlanes.add(wp);
    p.dirty = true;
    workPlaneArm = null;
    pickPlane = false;
    _wpPicks.clear();
    _wpNames.clear();
    _planesAutoShown = false;
    // M260 — and the work-feature arming, because the generic Plane command
    // can reach this through the offset DRAG rather than through
    // [_commitConstructedWorkPlane]. Without it the command would stay armed
    // with a stale half-selection after making a plane.
    _finishWorkFeature(p);
    toast(L.current.msgNameColonDef(wp.name, def));
    Log.i('part', 'work plane "${wp.name}" — $def');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// M162 — Inventor's "Edit Work Plane": change the offset distance of an
  /// existing plane and move it, instead of deleting and re-picking.
  ///
  /// Also the only way the distance can be anything but 10 mm at all:
  /// [workPlaneOffset] is what a new plane is built with, and until this
  /// existed nothing ever assigned it, so every offset plane in every saved
  /// document sits exactly 10 mm from its base.
  bool setWorkPlaneOffset(WorkPlane wp, double d) {
    // M247 — the owner is whichever document is open. These four value paths
    // bailed on `currentPart == null`, which in an assembly meant the field
    // accepted a number and wrote nothing at all.
    if (currentAssembly == null && currentPart == null) return false;
    if (!wp.offsetEditable) return false;
    if (!wp.setOffset(d)) return false;
    workPlaneOffset = d; // the next new plane starts from what you last used
    Log.i('part', 'work plane "${wp.name}" -> ${wp.def}');
    _workFeatureTouched();
    return true;
  }

  /// Browser eye on a work plane — Inventor's per-plane Visibility.
  void toggleWorkPlaneVisible(WorkPlane wp) {
    wp.visible = !wp.visible;
    _workFeatureTouched();
  }

  void deleteWorkPlane(WorkPlane wp) {
    final a = currentAssembly;
    if (a != null) {
      // M247 — and whatever was built ON it: see AssemblyModel.removeWorkFeature.
      a.removeWorkFeature(wp.id);
      if (identical(selectedWorkPlane, wp)) selectWorkPlane(null);
      _workFeatureTouched();
      return;
    }
    final p = currentPart;
    if (p == null) return;
    p.workPlanes.remove(wp);
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// M247 — a work feature belongs to whichever document is open, and only
  /// that document has to be marked dirty and saved.
  ///
  /// One helper rather than the `currentPart?.dirty = true; savePart(curTab!)`
  /// pair repeated five times: an assembly reached those lines and quietly
  /// wrote nothing, which is the shape of bug that only shows up after a
  /// restart.
  void _workFeatureTouched() {
    final a = currentAssembly;
    if (a != null) {
      // The plane quads live in the HEAVY RealityKit push, so a visibility
      // change has to move the scene signature or the device keeps drawing
      // what it was given.
      a.bump();
      notifyListeners();
      unawaited(saveAssembly(a.name));
      return;
    }
    currentPart?.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  // ---- M217: Delete Face and Direct Edit ----------------------------------

  /// The open Delete Face / Direct Edit session, or null.
  ///
  /// One session type for both commands, exactly as [EdgeFeatureSession] serves
  /// fillet and chamfer: they collect the same thing (a face set on one body)
  /// and differ only in what they do with it.
  FaceEditSession? faceEdit;

  /// True while the viewport should offer FACES as pick targets.
  bool get pickingFaces => faceEdit != null;

  void openDeleteFace() => _openFaceEdit(FaceEditKind.delete);
  void openDirectMove() => _openFaceEdit(FaceEditKind.move);
  void openDirectSize() => _openFaceEdit(FaceEditKind.size);
  void openDirectScale() => _openFaceEdit(FaceEditKind.scale);

  void _openFaceEdit(FaceEditKind kind) {
    final p = currentPart;
    if (p == null) return;
    // Toggling, like every other part command since M210.
    if (faceEdit?.kind == kind) return cancelFaceEdit();
    cancelWorkPlane();
    cancelWorkFeature();
    if (!p.hasSolid) {
      toast(L.current.msgFaceEditNeedsBody(faceEditName(L.current, kind)));
      return;
    }
    faceEdit = FaceEditSession(kind);
    toast(kind == FaceEditKind.scale
        ? L.current.msgSetScaleThenApply
        : L.current.msgSelectFacesTo(faceEditVerb(L.current, kind)));
    notifyListeners();
  }

  void cancelFaceEdit() {
    if (faceEdit == null) return;
    faceEdit = null;
    notifyListeners();
  }

  /// The viewport reports a tapped face. Toggles it in the set, like the edge
  /// pick — tapping a selected face again removes it, which is the only way to
  /// undo a mis-pick without restarting the command.
  void toggleFacePick(FacePick sel, int meshIndex) {
    final s = faceEdit;
    if (s == null) return;
    final at = s.meshIndices.indexOf(meshIndex);
    if (at >= 0) {
      s.meshIndices.removeAt(at);
      s.faces.removeAt(at);
    } else {
      s.meshIndices.add(meshIndex);
      s.faces.add(sel);
    }
    notifyListeners();
  }

  void setFaceEditValue({double? dx, double? dy, double? dz, double? factor}) {
    final s = faceEdit;
    if (s == null) return;
    if (dx != null) s.dx = dx;
    if (dy != null) s.dy = dy;
    if (dz != null) s.dz = dz;
    if (factor != null) s.factor = factor;
    notifyListeners();
  }

  /// Commits the session as a real timeline feature.
  ///
  /// A feature and not an in-place edit of the solid, deliberately: everything
  /// else in this app rebuilds from the timeline, and a face edit that lived
  /// outside it would be silently discarded by the next recompute — which is
  /// the worst possible failure, because the model would look right until it
  /// did not.
  Future<bool> applyFaceEdit() async {
    final p = currentPart;
    final s = faceEdit;
    if (p == null || s == null) return false;
    final scale = s.kind == FaceEditKind.scale;
    if (s.faces.isEmpty && !scale) {
      toast(L.current.msgSelectAtLeastOneFace);
      return false;
    }
    final host = lastSolidFeature(p);
    if (host == null) {
      toast(L.current.msgNothingToEditBuildBody);
      return false;
    }
    final f = s.kind == FaceEditKind.delete
        ? DeleteFaceFeature(
            name: p.nextFeatureName('Delete Face'),
            bodyName: host.bodyName,
            faces: s.faces)
        : DirectEditFeature(
            name: p.nextFeatureName(scale ? 'Scale' : 'Direct'),
            bodyName: host.bodyName,
            faces: s.faces,
            op: switch (s.kind) {
              FaceEditKind.move => DirectOp.move,
              FaceEditKind.size => DirectOp.size,
              _ => DirectOp.scale,
            },
            dx: s.dx,
            dy: s.dy,
            dz: s.dz,
            factor: s.factor);
    f.seq = p.nextSeq();
    p.features.add(f);
    final ok = recomputeFeature(p, f, partKernel, base: host.solid);
    if (!ok) {
      // A refusal must not leave a sick feature in the timeline: the user
      // asked for an edit and did not get one, so the timeline should look
      // exactly as it did before they asked.
      p.features.remove(f);
      toast(L.current.msgFeatureError(featureTypeName(L.current, f),
          f.computeError ?? partKernel.lastError));
      notifyListeners();
      return false;
    }
    faceEdit = null;
    p.dirty = true;
    if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    if (f.lostFaces > 0) {
      toast(L.current.msgLostFaces(f.name, f.lostFaces));
    }
    if (curTab != null) await savePart(curTab!);
    notifyListeners();
    return true;
  }

  // ---- M215: work axes and work points ------------------------------------
  //
  // One command shape for both, because Inventor's are the same shape: arm a
  // method, collect picks, and the moment the picks determine an answer, build
  // it. The geometry lives in work_features.dart; everything here is the
  // session state around it.

  /// Which Work Axis method is armed, or null.
  WorkAxisMethod? workAxisArm;

  /// Which Work Point method is armed, or null. At most one of these two and
  /// [workPlaneArm] is ever set — arming any of them cancels the others,
  /// because three commands competing for the same tap is not a UI.
  WorkPointMethod? workPointArm;

  /// M223 — which pick-only Work PLANE method is armed, or null.
  ///
  /// Separate from [workPlaneArm], which drives Offset and Midplane: those two
  /// are not pick-only (Offset is a drag with a live distance and an editable
  /// base) and they collect PlaneFrames rather than WorkRefs. Sharing one field
  /// would mean one of the two flows pretending to be the other; sharing the
  /// PICK path, which is what actually matters, costs nothing.
  WorkPlaneMethod? workPlaneMethodArm;

  /// M260 — the generic Plane command is armed, the one that INFERS its
  /// method from the picks ([WorkPlaneMethod.auto]).
  ///
  /// It is the only work-feature command that also owns a GESTURE: a press and
  /// drag on a face is an offset plane and never reaches the inference, while
  /// a tap is a pick that does. Both halves are checked against this.
  bool get workPlaneAutoArmed => workPlaneMethodArm == WorkPlaneMethod.auto;

  /// Picks collected so far for the armed command.
  final List<WorkRef> _wfPicks = [];

  /// True while a work AXIS or POINT command wants geometry. The viewport
  /// reads this to offer faces, edges, vertices and existing work features as
  /// hover targets — a superset of [pickPlane], which only ever wanted planes.
  bool get pickWorkGeometry =>
      workAxisArm != null || workPointArm != null || workPlaneMethodArm != null;

  /// The prompt currently shown for the armed command, or '' when none is.
  String workFeaturePrompt = '';

  /// Selected work axis / point, for the browser highlight and the 3D
  /// highlight. Mirrors [selectedWorkPlane].
  WorkAxis? selectedWorkAxis;
  WorkPoint? selectedWorkPoint;

  void selectWorkAxis(WorkAxis? a) {
    if (identical(selectedWorkAxis, a)) return;
    selectedWorkAxis = a;
    if (a != null) {
      selectedWorkPoint = null;
      selectWorkPlane(null);
    }
    notifyListeners();
  }

  void selectWorkPoint(WorkPoint? pt) {
    if (identical(selectedWorkPoint, pt)) return;
    selectedWorkPoint = pt;
    if (pt != null) {
      selectedWorkAxis = null;
      selectWorkPlane(null);
    }
    notifyListeners();
  }

  /// Arm Work Axis with [method]. Re-arming the same method cancels, so every
  /// ribbon entry is a toggle — the same contract [startWorkPlane] has.
  void startWorkAxis(WorkAxisMethod method) {
    final asm = currentAssembly;
    if (asm != null) return _armAsmWorkFeature(asm, axis: method);
    final p = currentPart;
    if (p == null) return;
    if (workAxisArm == method) return cancelWorkFeature();
    cancelWorkPlane();
    cancelWorkFeature();
    workAxisArm = method;
    _armWorkFeature(p, workAxisPrompt(method, 0));
  }

  void startWorkPoint(WorkPointMethod method) {
    final asm = currentAssembly;
    if (asm != null) return _armAsmWorkFeature(asm, point: method);
    final p = currentPart;
    if (p == null) return;
    if (workPointArm == method) return cancelWorkFeature();
    cancelWorkPlane();
    cancelWorkFeature();
    workPointArm = method;
    _armWorkFeature(p, workPointPrompt(method, 0));
  }

  /// M223 — arm one of the pick-only Work Plane methods. Same toggle contract
  /// as [startWorkAxis]: the same entry twice cancels.
  void startWorkPlaneMethod(WorkPlaneMethod method) {
    final asm = currentAssembly;
    if (asm != null) return _armAsmWorkFeature(asm, planeMethod: method);
    final p = currentPart;
    if (p == null) return;
    if (workPlaneMethodArm == method) return cancelWorkFeature();
    cancelWorkPlane();
    cancelWorkFeature();
    workPlaneMethodArm = method;
    _armWorkFeature(p, workPlanePrompt(method, 0));
  }

  void _armWorkFeature(PartModel p, String prompt) {
    _wfPicks.clear();
    workFeaturePrompt = prompt;
    // The origin planes, axes and centre point are offered for the duration,
    // exactly as the sketch and work-plane flows do. Without them an empty
    // part has nothing to pick at all, and an axis through the origin point
    // is one of the commonest things you want on a part that is still empty.
    _wfOriginAutoShown = !p.hasSolid;
    if (_wfOriginAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = true;
      p.vis['x'] = p.vis['y'] = p.vis['z'] = p.vis['cp'] = true;
    }
    toast(prompt);
    notifyListeners();
  }

  bool _wfOriginAutoShown = false;

  void cancelWorkFeature() {
    // M371 — and Measure with it, BEFORE the early return below.
    //
    // Every command in this app that starts collecting viewport taps calls
    // this on its way in — sixteen call sites, from Extrude to Place
    // Constraint — which makes it the app's de-facto "I am taking the
    // viewport's taps now" signal. Measure joins that signal here rather than
    // at all sixteen, and that is also the only version of this a seventeenth
    // command gets for free.
    //
    // Ahead of the early return because the return is about work features:
    // a command opening with none armed still means it is taking the taps.
    // The reverse direction is [startMeasure], which stands them down.
    cancelMeasure();
    // M247 — in an assembly [workPlaneArm] is part of this command rather
    // than of the part's separate offset/midplane flow, so it disarms here
    // too. In a part it is left alone: cancelWorkPlane owns it there, and
    // clearing it from here would cancel a flow this command never started.
    final asm = currentAssembly;
    if (workAxisArm == null &&
        workPointArm == null &&
        workPlaneMethodArm == null &&
        (asm == null || workPlaneArm == null)) {
      return;
    }
    workAxisArm = null;
    workPointArm = null;
    workPlaneMethodArm = null;
    _wfPicks.clear();
    workFeaturePrompt = '';
    if (asm != null) {
      workPlaneArm = null;
      _asmWfPicks.clear();
      _asmWfOriginRestore(asm);
      notifyListeners();
      return;
    }
    final p = currentPart;
    if (p != null && _wfOriginAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
      p.vis['x'] = p.vis['y'] = p.vis['z'] = p.vis['cp'] = false;
    }
    _wfOriginAutoShown = false;
    notifyListeners();
  }

  /// How many picks the armed command has taken. The viewport shows this so
  /// a two-input method does not look identical to a one-input one.
  int get workFeaturePickCount => _wfPicks.length;

  /// The viewport reports one picked entity. Returns true when it was taken.
  ///
  /// Three outcomes, all of them visible to the user:
  ///   complete  -> the feature is created and the command disarms
  ///   needMore  -> the pick is kept and the prompt advances
  ///   rejected  -> the pick is DROPPED and the command stays armed
  ///
  /// The last one is the one that matters: a mis-tap costs you that tap and
  /// nothing else. Making the user restart from the ribbon after picking a
  /// parallel face is the kind of small cruelty that makes a tool feel
  /// hostile — the same rule the midplane flow already follows.
  bool workFeaturePick(WorkRef ref) {
    final p = currentPart;
    if (p == null) return false;
    final axisM = workAxisArm;
    final pointM = workPointArm;
    final planeM = workPlaneMethodArm;
    if (axisM == null && pointM == null && planeM == null) return false;

    _wfPicks.add(ref);
    if (planeM != null) {
      final r = solveWorkPlane(planeM, _wfPicks, angleDeg: workPlaneAngle);
      if (r.outcome == WorkPickOutcome.complete) {
        _commitConstructedWorkPlane(p, r.solution!, planeM, _wfPicks);
        return true;
      }
      return _wfPending(r.outcome, r.message);
    }
    if (axisM != null) {
      final r = solveWorkAxis(axisM, _wfPicks);
      if (r.outcome == WorkPickOutcome.complete) {
        _commitWorkAxis(p, r.solution!);
        return true;
      }
      return _wfPending(r.outcome, r.message);
    }
    final r = solveWorkPoint(pointM!, _wfPicks);
    if (r.outcome == WorkPickOutcome.complete) {
      _commitWorkPoint(p, r.solution!,
          grounded: pointM == WorkPointMethod.grounded);
      return true;
    }
    return _wfPending(r.outcome, r.message);
  }

  /// The two NON-committing outcomes, which are identical for axes and
  /// points: keep the pick and advance the prompt, or drop it and say why.
  bool _wfPending(WorkPickOutcome outcome, String message) {
    final kept = outcome == WorkPickOutcome.needMore;
    if (kept) {
      workFeaturePrompt = message;
    } else {
      _wfPicks.removeLast();
    }
    toast(message);
    notifyListeners();
    return kept;
  }

  /// M223 — a work plane built from picks. Goes through the same
  /// [_commitWorkPlane] as Offset and Midplane, so naming, the browser row,
  /// the log line and the save are one implementation.
  void _commitConstructedWorkPlane(PartModel p, WorkPlaneSolution s,
      [WorkPlaneMethod? method, List<WorkRef> picks = const []]) {
    // M260 — under the generic Plane command the METHOD the caller armed is
    // `auto`, which says nothing about what to file the result under. The
    // inference reports what it resolved to; read that instead, so an angle
    // plane reached by tapping a face and an edge keeps its editable number
    // exactly as one reached from the named flyout entry does.
    method = s.via ?? method;
    // M229 — an ANGLE plane keeps what it was made from, so the one number it
    // has stays editable. Every other method bakes, and says so: there is
    // nothing to re-type on a plane through three points.
    if (method == WorkPlaneMethod.angleToPlaneAroundEdge && picks.isNotEmpty) {
      final base = picks.firstWhere((r) => r.hasPlane, orElse: () => picks.first);
      final edge = picks.firstWhere(
          (r) => !identical(r, base) && r.hasLine,
          orElse: () => base);
      if (base.hasPlane && edge.hasLine && !identical(base, edge)) {
        _commitWorkPlane(
          p,
          WorkPlaneKind.angle,
          workPlaneFrameAt(s.at, s.n),
          s.def,
          base: workPlaneFrameAt(base.planeAt!, base.planeNormal!),
          axisAt: edge.lineAt!,
          axisDir: edge.lineDir!,
          angle: workPlaneAngle,
        );
        _finishWorkFeature(p);
        // The field opens on it straight away — dynamic input, M169's order.
        selectWorkPlane(p.workPlanes.last);
        workPlaneOffsetEditing = true;
        notifyListeners();
        return;
      }
    }
    _commitWorkPlane(p, WorkPlaneKind.constructed,
        workPlaneFrameAt(s.at, s.n), s.def);
    _finishWorkFeature(p);
  }

  void _commitWorkAxis(PartModel p, WorkAxisSolution s) {
    final a = WorkAxis(
        _freeWorkName('Work Axis', {for (final w in p.workAxes) w.name}),
        p.nextSeq(),
        s.def,
        s.at,
        s.dir);
    p.workAxes.add(a);
    p.dirty = true;
    workAxisArm = null;
    _finishWorkFeature(p);
    selectedWorkAxis = a;
    toast(L.current.msgNameColonDef(a.name, a.def));
    Log.i('part', 'work axis "${a.name}" — ${a.def} '
        'at=(${a.at.x.toStringAsFixed(2)},${a.at.y.toStringAsFixed(2)},'
        '${a.at.z.toStringAsFixed(2)}) '
        'dir=(${a.dir.x.toStringAsFixed(4)},${a.dir.y.toStringAsFixed(4)},'
        '${a.dir.z.toStringAsFixed(4)})');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  void _commitWorkPoint(PartModel p, WorkPointSolution s,
      {bool grounded = false}) {
    final pt = WorkPoint(
        _freeWorkName('Work Point', {for (final w in p.workPoints) w.name}),
        p.nextSeq(),
        s.def,
        s.at,
        grounded: grounded);
    p.workPoints.add(pt);
    p.dirty = true;
    workPointArm = null;
    _finishWorkFeature(p);
    selectedWorkPoint = pt;
    toast(L.current.msgNameColonDef(pt.name, pt.def));
    Log.i('part', 'work point "${pt.name}" — ${pt.def} '
        'at=(${pt.at.x.toStringAsFixed(2)},${pt.at.y.toStringAsFixed(2)},'
        '${pt.at.z.toStringAsFixed(2)})');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  void _finishWorkFeature(PartModel p) {
    workAxisArm = null;
    workPointArm = null;
    workPlaneMethodArm = null;
    _wfPicks.clear();
    workFeaturePrompt = '';
    if (_wfOriginAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
      p.vis['x'] = p.vis['y'] = p.vis['z'] = p.vis['cp'] = false;
    }
    _wfOriginAutoShown = false;
  }

  /// First free "<base>N". Skips names already in use rather than counting the
  /// list, so deleting Work Axis2 and making another does not produce a second
  /// Work Axis3 — the same rule [PartModel.peekSolidName] follows for bodies.
  String _freeWorkName(String base, Set<String> taken) {
    var n = 1;
    while (taken.contains('$base$n')) {
      n++;
    }
    return '$base$n';
  }

  // ---- M247: the assembly's work features ---------------------------------
  //
  // The SAME commands, armed on the .pas document instead of the .ptp. The
  // arm fields above are shared — a command is armed once and three of them
  // competing for one tap is not a UI, whichever document is open — and the
  // only thing this section adds is a second pick list, because what an
  // assembly tap yields is an [AsmRef] and what a part tap yields is a
  // [WorkRef].
  //
  // Why the AsmRef and not the WorkRef is what is kept: the WorkRef is a
  // world-space snapshot, and in an assembly the world moves. See
  // asm_work_features.dart.

  /// Picks collected so far for the armed ASSEMBLY work-feature command, in
  /// the order they were made.
  final List<AsmRef> _asmWfPicks = [];

  /// True while a work-feature command is collecting in an assembly. The
  /// assembly viewport reads this exactly as the part viewport reads
  /// [pickWorkGeometry] — and this is deliberately not the same getter, since
  /// [pickPlane] and [workPlaneArm] mean something in a part that they do not
  /// mean here.
  bool get asmPickWorkGeometry =>
      currentAssembly != null &&
      (workAxisArm != null ||
          workPointArm != null ||
          workPlaneMethodArm != null ||
          workPlaneArm != null);

  /// How many picks the armed assembly command has taken.
  int get asmWorkFeaturePickCount => _asmWfPicks.length;

  /// The references it has taken, for the viewport's highlight.
  List<AsmRef> get asmWorkFeaturePicks => List.unmodifiable(_asmWfPicks);

  void _armAsmWorkFeature(AssemblyModel a,
      {WorkPlaneKind? planeKind,
      WorkPlaneMethod? planeMethod,
      WorkAxisMethod? axis,
      WorkPointMethod? point}) {
    // Every ribbon entry is a TOGGLE: the same entry twice cancels. Same
    // contract the part side has had since M151, and the only way out of a
    // command on a device with no Escape key.
    if ((planeKind != null && workPlaneArm == planeKind) ||
        (planeMethod != null && workPlaneMethodArm == planeMethod) ||
        (axis != null && workAxisArm == axis) ||
        (point != null && workPointArm == point)) {
      return cancelWorkFeature();
    }
    cancelWorkFeature();
    cancelAsmPosition(); // M250 — one armed assembly command at a time
    workPlaneArm = planeKind;
    workPlaneMethodArm = planeMethod;
    workAxisArm = axis;
    workPointArm = point;
    _asmWfPicks.clear();
    workFeaturePrompt = _asmWorkPrompt(0);
    // The origin geometry is offered for the duration, exactly as the part
    // flows do: an assembly with one component and no visible origin plane
    // has very little to point at, and a work plane offset from the assembly
    // XY is one of the first things you want.
    _wfOriginAutoShown = a.isEmpty;
    if (_wfOriginAutoShown) {
      for (final k in a.vis.keys) {
        a.vis[k] = true;
      }
      a.bump();
    }
    toast(workFeaturePrompt);
    notifyListeners();
  }

  /// The prompt for the armed assembly command, given how many picks it has.
  String _asmWorkPrompt(int have) {
    final pm = workPlaneMethodArm;
    if (pm != null) return workPlanePrompt(pm, have);
    final pk = workPlaneArm;
    if (pk != null) return asmPlanePrompt(pk, have);
    final ax = workAxisArm;
    if (ax != null) return workAxisPrompt(ax, have);
    final pt = workPointArm;
    if (pt != null) return workPointPrompt(pt, have);
    return '';
  }

  /// Puts the assembly's origin geometry back the way [_armAsmWorkFeature]
  /// found it.
  void _asmWfOriginRestore(AssemblyModel a) {
    if (!_wfOriginAutoShown) return;
    for (final k in a.vis.keys) {
      a.vis[k] = false;
    }
    a.bump();
    _wfOriginAutoShown = false;
  }

  /// The assembly viewport reports one pick. Returns true when it was taken.
  ///
  /// Three outcomes, and the third is the one that matters: a rejected pick is
  /// DROPPED and the command stays armed, so a mis-tap costs you that tap and
  /// nothing else. Same rule the part side states, for the same reason.
  bool asmWorkFeaturePick(AsmPick pick) {
    final a = currentAssembly;
    if (a == null || !asmPickWorkGeometry) return false;
    _asmWfPicks.add(pick.ref);
    final refs = asmWorkRefs(a, _asmWfPicks);
    if (refs == null) {
      // Only reachable if a component vanished between the tap and here.
      _asmWfPicks.removeLast();
      return false;
    }
    final pm = workPlaneMethodArm, pk = workPlaneArm;
    if (pm != null || pk != null) {
      final r = solveAsmWorkPlane(
          pk ?? _kindOfPlaneMethod(pm!), pm, refs,
          offset: workPlaneOffset, angleDeg: workPlaneAngle);
      if (r.outcome == WorkPickOutcome.complete) {
        _commitAsmWorkPlane(a, r.solution!, pk, pm);
        return true;
      }
      return _asmWfPending(r.outcome, r.message);
    }
    if (workAxisArm != null) {
      final r = solveWorkAxis(workAxisArm!, refs);
      if (r.outcome == WorkPickOutcome.complete) {
        _commitAsmWorkAxis(a, r.solution!, workAxisArm!);
        return true;
      }
      return _asmWfPending(r.outcome, r.message);
    }
    final m = workPointArm!;
    final r = solveWorkPoint(m, refs);
    if (r.outcome == WorkPickOutcome.complete) {
      _commitAsmWorkPoint(a, r.solution!, m);
      return true;
    }
    return _asmWfPending(r.outcome, r.message);
  }

  /// Which [WorkPlaneKind] a pick-only method produces. Only the angle method
  /// carries a re-typable number; everything else is [constructed], which is
  /// what the value field asks about before offering to edit anything.
  WorkPlaneKind _kindOfPlaneMethod(WorkPlaneMethod m) =>
      m == WorkPlaneMethod.angleToPlaneAroundEdge
          ? WorkPlaneKind.angle
          : WorkPlaneKind.constructed;

  bool _asmWfPending(WorkPickOutcome outcome, String message) {
    final kept = outcome == WorkPickOutcome.needMore;
    if (kept) {
      workFeaturePrompt = message;
    } else {
      _asmWfPicks.removeLast();
    }
    toast(message);
    notifyListeners();
    return kept;
  }

  void _commitAsmWorkPlane(AssemblyModel a, WorkPlaneSolution s,
      WorkPlaneKind? kind, WorkPlaneMethod? method) {
    // M260 — the part side's rule, for the same reason: the Work Features
    // flyout is shared with this ribbon (see _assemblyRibbon), so its "Plane"
    // entry arms the inferring command here too and `auto` says nothing about
    // what to file the result under. Read what the inference RESOLVED to.
    //
    // Storing the resolved method also makes the re-solve steadier than the
    // pick list it came from: an assembly work plane is parametric and
    // re-derived on every solve, and a named method cannot change its mind
    // half way through a drag. The midplane is the one that stays `auto`,
    // because it has no named method to resolve to.
    method = s.via ?? method;
    final w = AsmWorkPlane(
      _freeWorkName('Work Plane', {for (final x in a.workPlanes) x.name}),
      a.nextWorkSeq(),
      kind ?? _kindOfPlaneMethod(method!),
      s.def,
      workPlaneFrameAt(s.at, s.n),
      method: method,
      refs: List.of(_asmWfPicks),
      offset: kind == WorkPlaneKind.offset ? workPlaneOffset : null,
      angle: method == WorkPlaneMethod.angleToPlaneAroundEdge
          ? workPlaneAngle
          : null,
    );
    a.workPlanes.add(w);
    _finishAsmWorkFeature(a);
    // Re-derive it once, straight away: the frame above is right, but the
    // base and pivot the value field edits are filled in by the re-solve, so
    // the field has to see one before it can offer to move anything.
    resolveAsmWorkPlane(a, w);
    selectWorkPlane(w);
    if (w.valueEditable) workPlaneOffsetEditing = true;
    _asmWorkFeatureMade(a, w.name, w.def);
  }

  void _commitAsmWorkAxis(
      AssemblyModel a, WorkAxisSolution s, WorkAxisMethod method) {
    final x = AsmWorkAxis(
        _freeWorkName('Work Axis', {for (final v in a.workAxes) v.name}),
        a.nextWorkSeq(),
        s.def,
        s.at,
        s.dir,
        method: method,
        refs: List.of(_asmWfPicks));
    a.workAxes.add(x);
    _finishAsmWorkFeature(a);
    selectedWorkPoint = null;
    selectedWorkAxis = x;
    _asmWorkFeatureMade(a, x.name, x.def);
  }

  void _commitAsmWorkPoint(
      AssemblyModel a, WorkPointSolution s, WorkPointMethod method) {
    final pt = AsmWorkPoint(
        _freeWorkName('Work Point', {for (final v in a.workPoints) v.name}),
        a.nextWorkSeq(),
        s.def,
        s.at,
        method: method,
        refs: List.of(_asmWfPicks),
        grounded: method == WorkPointMethod.grounded);
    a.workPoints.add(pt);
    _finishAsmWorkFeature(a);
    selectedWorkAxis = null;
    selectedWorkPoint = pt;
    _asmWorkFeatureMade(a, pt.name, pt.def);
  }

  void _finishAsmWorkFeature(AssemblyModel a) {
    workPlaneArm = null;
    workPlaneMethodArm = null;
    workAxisArm = null;
    workPointArm = null;
    _asmWfPicks.clear();
    workFeaturePrompt = '';
    _asmWfOriginRestore(a);
  }

  void _asmWorkFeatureMade(AssemblyModel a, String name, String def) {
    a.bump();
    toast(L.current.msgNameColonDef(name, def));
    Log.i('assembly', 'work feature "$name" — $def');
    notifyListeners();
    unawaited(saveAssembly(a.name));
  }

  /// M247 — re-derives every assembly work feature from its stored picks.
  ///
  /// Called from [_solveAssembly], which is the one funnel every command that
  /// can move a component already goes through. Anywhere else and a work
  /// feature would go stale on whichever path forgot it.
  void _resolveAsmWorkFeatures(AssemblyModel a) {
    if (a.workPlanes.isEmpty && a.workAxes.isEmpty && a.workPoints.isEmpty) {
      return;
    }
    resolveAsmWorkFeatures(a);
  }

  void toggleWorkAxisVisible(WorkAxis a) {
    a.visible = !a.visible;
    _workFeatureTouched();
  }

  void toggleWorkPointVisible(WorkPoint pt) {
    pt.visible = !pt.visible;
    _workFeatureTouched();
  }

  void deleteWorkAxis(WorkAxis a) {
    if (identical(selectedWorkAxis, a)) selectedWorkAxis = null;
    final asm = currentAssembly;
    if (asm != null) {
      asm.removeWorkFeature(a.id);
      _workFeatureTouched();
      return;
    }
    final p = currentPart;
    if (p == null) return;
    p.workAxes.remove(a);
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  void deleteWorkPoint(WorkPoint pt) {
    if (identical(selectedWorkPoint, pt)) selectedWorkPoint = null;
    final asm = currentAssembly;
    if (asm != null) {
      asm.removeWorkFeature(pt.id);
      _workFeatureTouched();
      return;
    }
    final p = currentPart;
    if (p == null) return;
    p.workPoints.remove(pt);
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// Reverses a work axis. See [WorkAxis.flip] for why this exists.
  ///
  /// M247 — an ASSEMBLY axis is re-derived from its picks after every solve,
  /// and the solver preserves the sign the method gave it, so a flip that only
  /// negated [WorkAxis.dir] would be undone by the next drag. The re-solve is
  /// the wrong place to hold a user's choice, so the flip is not offered on
  /// one: re-picking two points the other way round is the honest way to
  /// reverse it, and saying so beats a button that works until you move
  /// something. See _workAxisMenu.
  void flipWorkAxis(WorkAxis a) {
    a.flip();
    _workFeatureTouched();
  }

  /// The 3D viewport reports a tapped PLANAR SOLID FACE (M58): same flow as
  /// [planePicked], but the sketch lives on the face's own frame — Inventor's
  /// sketch-on-face.
  void facePicked(PlaneFrame frame, [SketchFaceSel? ref]) {
    final p = currentPart;
    if (p == null || !pickPlane) return;
    // M151 — see planePicked. A face and an origin plane are interchangeable
    // inputs here; both are just a PlaneFrame by the time they arrive.
    if (workPlaneArm != null) {
      _workPlaneInput(frame, 'face');
      return;
    }
    // M228 — the split panel asks the same question, so it reads the same pick.
    if (splitSession != null && splitSession!.frame == null) {
      _splitPlaneInput(frame, 'Face');
      return;
    }
    // M345 — and so does a paste waiting for a plane. A face is a plane.
    if (_pasteOnPickedPlane('face', frame, ref)) return;
    pickPlane = false;
    p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
    final fn = frame.n;
    final camBefore = p.camera.dir;
    final dot = fn.dot(camBefore);
    final chosen = dot >= 0 ? fn : fn * -1;
    // M181 — shared with the work-plane path; see orientToSurface for why the
    // side is chosen this way. M211 — the whole frame goes in, so the roll
    // lands on the frame's u and the swing into the sketch is a pure zoom.
    orientToSurface(p, frame);
    // The earlier diagnostic (clicking the TOP face reported as landing on the
    // BOTTOM view) is answered: the SIDE was never wrong — pol comes out on
    // the side the camera was already on — but the ROLL was, by as much as
    // half a turn, and a view rolled 180° reads as the other side of the face.
    // The line stays, with the roll now in it, because it is the only record
    // of what the camera did at the moment a face was picked.
    String f3(double v) => v.toStringAsFixed(2);
    Log.i(
        'part',
        'face view: n=(${f3(fn.x)},${f3(fn.y)},${f3(fn.z)}) '
        'u=(${f3(frame.u.x)},${f3(frame.u.y)},${f3(frame.u.z)}) '
        'camDir=(${f3(camBefore.x)},${f3(camBefore.y)},${f3(camBefore.z)}) '
        'dot=${f3(dot)} chose=(${f3(chosen.x)},${f3(chosen.y)},${f3(chosen.z)}) '
        '-> pol=${f3(p.camera.pol)} az=${f3(p.camera.az)} '
        'roll=${f3(p.camera.roll)} '
        '(pol~0 = camera above/TOP, pol~3.14 = below/BOTTOM)');
    final sk = SketchModel(p.nextSketchName());
    p.appendChildSketch(ChildSketch(
        sk, 'face', frame, true, false, p.nextSeq(), ref)); // M91, M153
    _admitNewSketchRow(p);
    p.dirty = true;
    activeChild = sk;
    sketchZoomNeedsFit = true;
    _reanalyze();
    Log.i('part', 'child sketch "${sk.name}" on a solid face of "${p.name}"');
    startNewLayer();
  }

  /// Finish Sketch: back to the 3D part; the sketch stays in the part and
  /// every feature is recomputed against its new state.
  void finishPartSketch() {
    // M168 — Slice Graphics is a SKETCH display state (Inventor clears it
    // when the sketch closes). Leaving it on would cut the part view too.
    if (sliceGraphics) {
      sliceGraphics = false;
      _clearSliceCache();
    }
    final p = currentPart;
    finishEdit(save: false);
    activeChild = null;
    _reanalyze();
    if (p != null && partKernel.available) {
      recomputeAllFeatures(p, partKernel);
      for (final f in p.features) {
        if (f.computeError != null) {
          toast(L.current.msgFeatureError(f.name, f.computeError!));
        }
      }
    }
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// Double-click on a part's sketch row: orient to its plane, reopen it.
  void openChildSketch(String name) {
    final p = currentPart;
    final cs = p?.sketchByName(name);
    if (p == null || cs == null) return;
    cancelExtrude();
    cancelHole(); // M225 — the same rule, the other way round
    cancelCombine();
    // M211 — a sketch on a FACE or a work plane has no origin-plane key, and
    // `orientToPlane` answers every key it does not know with the XY target.
    // Reopening one from the browser therefore aimed the part camera at the
    // front view: the sketch itself looked right (the viewport swings to
    // `forSketch` regardless), but the swing started from an unrelated
    // orientation and Finish Sketch dropped you back into it.
    if (cs.face != null) {
      p.camera.orientToFrame(sketchFrameOf(cs));
    } else {
      p.camera.orientToPlane(cs.plane);
    }
    activeChild = cs.model;
    sketchZoomNeedsFit = true;
    editingLayer = null;
    tool = Tool.none;
    _reanalyze();
    notifyListeners();
  }

  void togglePartOriginVis(String key) {
    final p = currentPart;
    if (p == null || !p.vis.containsKey(key)) return;
    p.vis[key] = !(p.vis[key] ?? false);
    p.dirty = true;
    notifyListeners();
  }

  // ---- Extrude (M56): modeless properties panel + region picking ----
  List<ProfileRegion> sessionRegions(ChildSketch cs) => _regionCache
      .putIfAbsent(cs.model.name, () => regionsFrom(profileLoops(cs.model)));

  /// Opens the Extrusion panel — for a NEW feature, or to [edit] an
  /// existing one. Inventor-style: with exactly one profile in the latest
  /// sketch it is pre-selected.
  /// M131 — "edit this feature", whatever kind it is. The browser has one
  /// double-tap and one context-menu entry; which dialog that opens is a
  /// property of the feature, not of the row.
  ///
  /// Kinds whose dialog does not exist yet log and do nothing, rather than
  /// falling back to the extrude panel — opening the wrong editor on a
  /// revolve would let the user change a value that silently belongs to a
  /// different feature.
  void editFeature(PartFeature f) {
    if (f is ExtrudeFeature) {
      openExtrude(f);
    } else if (f is FilletFeature) {
      openFillet(f);
    } else if (f is ChamferFeature) {
      openChamfer(f);
    } else if (f is RevolveFeature) {
      openRevolve(f);
    } else if (f is SweepFeature) {
      openSweep(f);
    } else if (f is LoftFeature) {
      openLoft(f);
    } else if (f is CoilFeature) {
      openCoil(f);
    } else if (f is PatternFeature) {
      _openPattern(f.mode, f);
    } else if (f is CombineFeature) {
      openCombine(f);
    } else if (f is SplitFeature) {
      openSplit(f);
    } else if (f is HoleFeature) {
      // M226 — without this a Hole row in the browser opened nothing at all:
      // the feature was reachable to build and unreachable to change, which is
      // the half-built state this file logs about below.
      openHole(f);
    } else if (f is DeriveFeature) {
      // M255 — Inventor's "Open Base Component". There is nothing in a derived
      // body to edit HERE: it has no numbers of its own, and everything that
      // decides its shape is a feature of the origin. So Edit means what it
      // can only mean — go to where the shape is actually made.
      toast(L.current.msgDerivedEditOrigin(f.sourceDoc));
      unawaited(openDocument(f.sourceDoc));
    } else {
      // Revolve still has no panel; opening the extrude one instead would let
      // the user change a value that belongs to a different feature.
      Log.i('feature', 'no editor wired for ${f.kind} yet (${f.name})');
    }
  }

  // ---- M136 — Fillet / Chamfer -----------------------------------------
  EdgeFeatureSession? edgeSession;

  void openFillet([FilletFeature? edit]) => _openEdgeFeature('fillet', edit);
  void openChamfer([ChamferFeature? edit]) => _openEdgeFeature('chamfer', edit);

  void _openEdgeFeature(String kind, BodyModifyFeature? edit) {
    if (_toggles3DOff(kind, edit)) return; // M210
    if (currentPart == null) return;
    cancelExtrude();
    cancelHole(); // M225 — one 3D panel at a time
    cancelCombine(); // M227 — likewise
    cancelSplit(); // M228 — likewise
    _leaveSketchForCommand(); // M221 — an edge pick needs the 3D viewport
    final s = EdgeFeatureSession(kind, editing: edit);
    if (edit is FilletFeature) {
      // One set per DISTINCT radius, preserving first-seen order, so
      // reopening a multi-set fillet shows the sets it was built with.
      final seen = <double>[];
      for (final r in edit.radii) {
        if (!seen.any((x) => (x - r).abs() < 1e-12)) seen.add(r);
      }
      s.allFillets = edit.allFillets;
      s.allRounds = edit.allRounds;
      s.exprRadii = seen.isEmpty
          ? [edit.exprRadius]
          : [for (final r in seen) '${_mmExpr(r)} mm'];
    } else if (edit is ChamferFeature) {
      s.mode = edit.mode;
      s.exprD1 = edit.exprD1;
      s.exprD2 = edit.exprD2;
      s.exprAngle = edit.exprAngle;
      s.flip = edit.flip;
      s.edgeChain = edit.edgeChain;
    }
    edgeSession = s;
    // Re-open on an existing feature: put its edges back in the picker so the
    // 3D view shows what this feature acts on, not an empty selection.
    pickedEdges.clear();
    pickedEdgeIds.clear();
    pickedEdgeDisplay.clear();
    pickedEdgeSet.clear();
    activeEdgeSet = 0;
    pickedEdgeSolid = null;
    pickedEdgeBodyName = null;
    if (edit != null) {
      pickedEdges.addAll(edit.edges);
      // Put each edge back in the set its radius identifies.
      if (edit is FilletFeature) {
        for (final r in edit.radii) {
          var k = s.exprRadii.indexWhere(
              (e) => (parseValueExpr(e) ?? -1) == r);
          if (k < 0) k = 0;
          pickedEdgeSet.add(k);
        }
      } else {
        pickedEdgeSet.addAll(List<int>.filled(edit.edges.length, 0));
      }
    }
    beginPickEdges();
    _updateEdgeFeaturePreview();
    notifyListeners();
  }

  /// Renders a stored radius back into an editable expression. Whole numbers
  /// lose the decimal point, because "2 mm" is what the user typed and
  /// "2.00 mm" reading back would look like the value had changed.
  static String _mmExpr(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  void setEdgeFeature(
      {String? exprRadius,
      String? exprRadius2,
      int? radiusSet,
      int? mode,
      String? exprD1,
      String? exprD2,
      String? exprAngle,
      bool? flip,
      bool? edgeChain}) {
    final s = edgeSession;
    if (s == null) return;
    if (exprRadius != null) {
      final i = radiusSet ?? 0;
      while (s.exprRadii.length <= i) {
        s.exprRadii.add(s.exprRadii.isEmpty ? '2 mm' : s.exprRadii.last);
      }
      s.exprRadii[i] = exprRadius;
    }
    if (exprRadius2 != null) {
      final i = radiusSet ?? 0;
      while (s.exprRadii2.length <= i) {
        s.exprRadii2.add('');
      }
      s.exprRadii2[i] = exprRadius2;
    }
    if (mode != null) s.mode = mode;
    if (exprD1 != null) s.exprD1 = exprD1;
    if (exprD2 != null) s.exprD2 = exprD2;
    if (exprAngle != null) s.exprAngle = exprAngle;
    if (flip != null) s.flip = flip;
    if (edgeChain != null) s.edgeChain = edgeChain;
    _updateEdgeFeaturePreview();
    notifyListeners();
  }

  /// M230 — every in-flight 3D command, cancelled together.
  ///
  /// They all hold references INTO the model: a sketch name, a body name, a
  /// frame lifted off a face, a list of placements. Every caller of this is a
  /// moment when that model is about to be replaced or left behind — going
  /// home, closing or deleting a part, restoring an undo snapshot — and a
  /// panel that survives one of those comes back pointing at geometry that is
  /// no longer there.
  ///
  /// One list, so the NEXT command is cancelled by construction rather than by
  /// remembering. All four sites used to name `cancelExtrude` alone, which was
  /// right when it was the only 3D session and has been quietly wrong since
  /// M136 added the second.
  void cancel3DCommands() {
    _pastePlaneArmed = false; // M345 — an armed paste is a 3D command too
    cancelMakePart(); // M255
    cancelExtrude();
    cancelEdgeFeature();
    cancelPattern();
    cancelHole();
    cancelCombine();
    cancelSplit();
    cancelWorkFeature();
    cancelWorkPlane();
    cancelPickBody();
    cancelPickExtentFace();
  }

  void cancelEdgeFeature() {
    edgeSession?.disposePreview();
    edgeSession = null;
    cancelPickEdges();
    notifyListeners();
  }

  /// The feature the current session describes, or an error to show.
  (BodyModifyFeature?, String?) _edgeSessionFeature() {
    final s = edgeSession;
    final p = currentPart;
    if (s == null || p == null) return (null, 'no session');
    if (pickedEdges.isEmpty) return (null, L.current.valSelectOneEdge);
    final body = pickedEdgeSolid == null
        ? (s.editing?.bodyName ?? 'Solid1')
        : (_bodyNameOfSolid(pickedEdgeSolid!) ?? 'Solid1');
    if (s.isFillet) {
      // Every set must parse: a bad radius on set 2 has to be reported, not
      // quietly replaced by set 1's value.
      final rs = <double>[];
      for (var i = 0; i < s.exprRadii.length; i++) {
        final v = parseValueExpr(s.exprRadii[i]);
        if (v == null || !(v > 0)) {
          return (null, s.exprRadii.length == 1
              ? L.current.valRadiusPositive
              : L.current.valRadiusOfSetPositive('${i + 1}'));
        }
        rs.add(v);
      }
      if (rs.isEmpty) return (null, L.current.valRadiusPositive);
      // End radii: blank means constant (0). A non-blank value that does not
      // parse is an error, not a silent fallback to constant.
      final rs2 = <double>[];
      for (var i = 0; i < rs.length; i++) {
        final t = i < s.exprRadii2.length ? s.exprRadii2[i].trim() : '';
        if (t.isEmpty) {
          rs2.add(0);
          continue;
        }
        final v = parseValueExpr(t);
        if (v == null || !(v > 0)) {
          return (null, rs.length == 1
              ? L.current.valEndRadiusPositive
              : L.current.valEndRadiusOfSetPositive('${i + 1}'));
        }
        rs2.add(v);
      }
      return (
        FilletFeature(
          name: s.editing?.name ?? p.nextFeatureName('Fillet'),
          bodyName: body,
          edges: [for (final e in pickedEdges) e],
          // radii is parallel to edges, so each edge takes ITS set's radius.
          radii: [
            for (var i = 0; i < pickedEdges.length; i++)
              rs[(i < pickedEdgeSet.length ? pickedEdgeSet[i] : 0)
                  .clamp(0, rs.length - 1)]
          ],
          radii2: rs2.any((r) => r > 0)
              ? [
                  for (var i = 0; i < pickedEdges.length; i++)
                    rs2[(i < pickedEdgeSet.length ? pickedEdgeSet[i] : 0)
                        .clamp(0, rs2.length - 1)]
                ]
              : const [],
          exprRadius: s.exprRadius,
          allFillets: s.allFillets,
          allRounds: s.allRounds,
        ),
        null
      );
    }
    final d1 = parseValueExpr(s.exprD1);
    if (d1 == null || !(d1 > 0)) return (null, L.current.valDistancePositive);
    var d2 = d1, ang = 45.0;
    if (s.mode == 1) {
      final v = parseValueExpr(s.exprD2);
      if (v == null || !(v > 0)) return (null, L.current.valDistance2Positive);
      d2 = v;
    } else if (s.mode == 2) {
      final v = parseValueExpr(s.exprAngle);
      if (v == null || !(v > 0) || v >= 90) {
        return (null, L.current.valAngle0to90);
      }
      ang = v;
    }
    return (
      ChamferFeature(
        name: s.editing?.name ?? p.nextFeatureName('Chamfer'),
        bodyName: body,
        edges: [for (final e in pickedEdges) e],
        mode: s.mode,
        distance1: d1,
        distance2: d2,
        angleDeg: ang,
        exprD1: s.exprD1,
        exprD2: s.exprD2,
        exprAngle: s.exprAngle,
        flip: s.flip,
        edgeChain: s.edgeChain,
      ),
      null
    );
  }

  String? _bodyNameOfSolid(KernelSolid s) {
    final p = currentPart;
    if (p == null) return null;
    for (final f in p.features) {
      if (identical(f.solid, s)) return f.bodyName;
    }
    return null;
  }

  void _updateEdgeFeaturePreview() {
    final s = edgeSession;
    final p = currentPart;
    if (s == null || p == null) return;
    s.disposePreview();
    s.previewError = null;
    final (f, err) = _edgeSessionFeature();
    if (f == null) {
      s.previewError = err;
      return;
    }
    final base = pickedEdgeSolid;
    if (base == null) {
      s.previewError = L.current.valSelectOneEdge;
      return;
    }
    // The throwaway feature owns the solid it builds; hand it straight to the
    // session so the viewport shows the rounded body while the panel is open.
    if (!recomputeFeature(p, f, partKernel, base: base)) {
      s.previewError = f.computeError;
      return;
    }
    s.preview = f.solid;
    s.previewReplacesBody = f.bodyName;
    f.solid = null; // ownership moved to the session
  }

  Future<bool> applyEdgeFeature() async {
    final s = edgeSession;
    final p = currentPart;
    if (s == null || p == null) return false;
    final (f, err) = _edgeSessionFeature();
    if (f == null) {
      toast(err ?? L.current.msgCannotCreateFeature);
      return false;
    }
    final edit = s.editing;
    if (edit != null) {
      final i = p.features.indexOf(edit);
      if (i >= 0) {
        f.seq = edit.seq;
        edit.disposeSolid();
        p.features[i] = f;
      }
    } else {
      f.seq = p.nextSeq();
      p.appendFeature(f); // keeps End of Part past what was just created
    }
    s.disposePreview();
    edgeSession = null;
    cancelPickEdges();
    if (partKernel.available) {
      // M182 — projections only after a SUCCESSFUL recompute (see openPart).
      if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    }
    p.dirty = true;
    Log.i('part',
        '${s.kind} ${edit == null ? "created" : "edited"} ${f.name} '
        '(${f.bodyName}) edges=${f.edges.length}');
    notifyListeners();
    return true;
  }


  // ---- M225 — Hole: Inventor's Modify > Hole, on sketch points ----------

  HoleSession? holeSession;

  /// True while the hole panel wants a sketch point. Read by the viewport for
  /// the same reason [patternPicking3D] is: one predicate next to escape3D
  /// beats a flag test spread through the widget.
  bool get holePicking3D => holeSession != null;

  /// Open the Hole panel — for a new hole, or to [edit] an existing one.
  void openHole([HoleFeature? edit]) {
    final p = currentPart;
    if (p == null) return;
    if (edit == null && holeSession != null && holeSession!.editing == null) {
      cancelHole(); // M210's toggle: the same command twice closes it
      return;
    }
    if (p.childSketches.isEmpty) {
      toast(L.current.msgHoleNeedsSketch);
      return;
    }
    if (edit == null && !p.hasSolid) {
      toast(L.current.msgHoleNeedsBody);
      return;
    }
    cancelExtrude();
    cancelEdgeFeature();
    cancelPattern();
    cancelHole();
    _leaveSketchForCommand(); // M221 — its picks are 3D picks
    final s = HoleSession()..editing = edit;
    if (edit != null) {
      s
        ..sketchName = edit.sketchName
        ..exprDia = edit.exprDia
        ..exprDepth = edit.exprDepth
        ..extent = edit.extent
        ..flip = edit.flip
        ..type = edit.type
        ..exprCbDia = edit.exprCbDia
        ..exprCbDepth = edit.exprCbDepth
        ..exprCsDia = edit.exprCsDia
        ..exprCsAngle = edit.exprCsAngle;
      for (final pl in edit.places) {
        s.places.add(HolePlace(pl.x, pl.y));
      }
    }
    holeSession = s;
    toast(s.places.isEmpty
        ? L.current.msgTapSketchPointsForHoles
        : L.current.msgHoleCount(s.places.length));
    notifyListeners();
  }

  /// A tap landed on the sketch point [at] of [sketchName]: add it, or take it
  /// away if it is already there. Same toggle as a profile pick, and for the
  /// same reason — building up a set must never silently drop one.
  void holePointPicked(String sketchName, Offset at) {
    final s = holeSession;
    if (s == null) return;
    if (s.sketchName != null && s.sketchName != sketchName) {
      if (s.places.isNotEmpty) {
        toast(L.current.msgHolesSameSketch);
        return;
      }
    }
    s.sketchName = sketchName;
    final i = s.places.indexWhere(
        (pl) => (Offset(pl.x, pl.y) - at).distance < 1e-6);
    if (i >= 0) {
      s.places.removeAt(i);
      if (s.places.isEmpty) s.sketchName = null;
    } else {
      s.places.add(HolePlace(at.dx, at.dy));
    }
    notifyListeners();
  }

  void setHole(
      {String? exprDia,
      String? exprDepth,
      FeatureExtent? extent,
      bool? flip,
      HoleType? type,
      String? exprCbDia,
      String? exprCbDepth,
      String? exprCsDia,
      String? exprCsAngle}) {
    final s = holeSession;
    if (s == null) return;
    if (exprDia != null) s.exprDia = exprDia;
    if (exprDepth != null) s.exprDepth = exprDepth;
    if (extent != null) s.extent = extent;
    if (flip != null) s.flip = flip;
    if (type != null) s.type = type;
    if (exprCbDia != null) s.exprCbDia = exprCbDia;
    if (exprCbDepth != null) s.exprCbDepth = exprCbDepth;
    if (exprCsDia != null) s.exprCsDia = exprCsDia;
    if (exprCsAngle != null) s.exprCsAngle = exprCsAngle;
    notifyListeners();
  }

  void cancelHole() {
    if (holeSession == null) return;
    holeSession = null;
    notifyListeners();
  }

  /// Build (or update) the feature and rebuild the part.
  Future<bool> applyHole() async {
    final s = holeSession;
    final p = currentPart;
    if (s == null || p == null) return false;
    if (s.places.isEmpty || s.sketchName == null) {
      toast(L.current.msgTapSketchPointsForHoles);
      return false;
    }
    final dia = parseValueExpr(s.exprDia);
    if (dia == null || !(dia > 0)) {
      toast(L.current.msgDiameterPositive);
      return false;
    }
    final depth = parseValueExpr(s.exprDepth) ?? 0;
    if (s.extent == FeatureExtent.distance && !(depth > 0)) {
      toast(L.current.msgDepthPositive);
      return false;
    }
    final edit = s.editing;
    // M226 — the mouth's numbers, parsed with the same refusal as the rest:
    // a hole that silently drills a 0 mm counterbore is a wrong part.
    final cbDia = parseValueExpr(s.exprCbDia) ?? 0;
    final cbDepth = parseValueExpr(s.exprCbDepth) ?? 0;
    final csDia = parseValueExpr(s.exprCsDia) ?? 0;
    final csAngle = parseValueExpr(s.exprCsAngle) ?? 0;
    if ((s.type == HoleType.counterbore || s.type == HoleType.spotface) &&
        !(cbDia > dia && cbDepth > 0)) {
      toast(L.current
          .msgCboreWiderThanHole(holeTypeDisplay(L.current, s.type)));
      return false;
    }
    if (s.type == HoleType.countersink &&
        !(csDia > dia && csAngle > 0 && csAngle < 180)) {
      toast(L.current.msgCsinkAngle);
      return false;
    }
    final f = HoleFeature(
      name: edit?.name ?? p.nextFeatureName('Hole'),
      bodyName: edit?.bodyName ??
          (p.features.isEmpty ? p.nextSolidName() : p.features.last.bodyName),
      sketchName: s.sketchName!,
      places: [for (final pl in s.places) HolePlace(pl.x, pl.y)],
      dia: dia,
      depth: depth,
      exprDia: s.exprDia,
      exprDepth: s.exprDepth,
      extent: s.extent,
      flip: s.flip,
      type: s.type,
      cbDia: cbDia,
      cbDepth: cbDepth,
      exprCbDia: s.exprCbDia,
      exprCbDepth: s.exprCbDepth,
      csDia: csDia,
      csAngle: csAngle,
      exprCsDia: s.exprCsDia,
      exprCsAngle: s.exprCsAngle,
    );
    if (edit != null) {
      final i = p.features.indexOf(edit);
      if (i >= 0) {
        f.seq = edit.seq;
        edit.disposeSolid();
        p.features[i] = f;
      }
    } else {
      f.seq = p.nextSeq();
      p.appendFeature(f);
    }
    holeSession = null;
    if (partKernel.available) {
      if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    }
    if (f.computeError != null) {
      toast(L.current.msgFeatureError(f.name, f.computeError!));
    }
    p.dirty = true;
    Log.i('part',
        'hole ${edit == null ? "created" : "edited"} ${f.name} '
        '(${f.bodyName}) places=${f.places.length} dia=${f.dia}');
    if (curTab != null) await savePart(curTab!);
    notifyListeners();
    return true;
  }

  // ---- M228 — Split (Trim Solid): trim a body with a plane --------------

  SplitSession? splitSession;

  /// True while the split panel is waiting for its plane. It borrows the plane
  /// PICK the sketch and work-plane flows use ([pickPlane]), because "a plane
  /// or a planar face" is the same question in all three.
  bool get splitPickingPlane => splitSession != null && pickPlane;

  void openSplit([SplitFeature? edit]) {
    final p = currentPart;
    if (p == null) return;
    if (edit == null && splitSession != null && splitSession!.editing == null) {
      cancelSplit();
      return;
    }
    if (edit == null && !p.hasSolid) {
      toast(L.current.msgSplitNeedsBody);
      return;
    }
    cancelExtrude();
    cancelEdgeFeature();
    cancelPattern();
    cancelHole();
    cancelCombine();
    cancelSplit();
    _leaveSketchForCommand();
    final s = SplitSession()..editing = edit;
    if (edit != null) {
      s
        ..frame = edit.frame
        ..label = edit.label
        ..flip = edit.flip
        ..bodyName = edit.bodyName;
    }
    splitSession = s;
    if (s.frame == null) {
      // The origin planes come out for the duration, exactly as they do for a
      // sketch: on a part with one body there may be nothing else to pick.
      pickPlane = true;
      _planesAutoShown = true;
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = true;
      toast(L.current.msgSelectTrimPlane);
    }
    notifyListeners();
  }

  /// The split panel's plane arrived — from an origin plane, a work plane or a
  /// planar face; by the time it is here they are all just a frame.
  void _splitPlaneInput(PlaneFrame f, String label) {
    final s = splitSession;
    if (s == null) return;
    s.frame = f;
    s.label = label;
    pickPlane = false;
    final p = currentPart;
    if (p != null && _planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
    }
    _planesAutoShown = false;
    toast(L.current.msgTrimmingWith(label));
    notifyListeners();
  }

  void repickSplitPlane() {
    final s = splitSession;
    final p = currentPart;
    if (s == null || p == null) return;
    s.frame = null;
    pickPlane = true;
    _planesAutoShown = true;
    p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = true;
    toast(L.current.msgSelectTrimPlane);
    notifyListeners();
  }

  void setSplit({bool? flip, String? bodyName}) {
    final s = splitSession;
    if (s == null) return;
    if (flip != null) s.flip = flip;
    if (bodyName != null) s.bodyName = bodyName;
    notifyListeners();
  }

  void cancelSplit() {
    if (splitSession == null) return;
    final p = currentPart;
    if (pickPlane) {
      pickPlane = false;
      if (p != null && _planesAutoShown) {
        p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
      }
      _planesAutoShown = false;
    }
    splitSession = null;
    notifyListeners();
  }

  Future<bool> applySplit() async {
    final s = splitSession;
    final p = currentPart;
    if (s == null || p == null) return false;
    final fr = s.frame;
    if (fr == null) {
      toast(L.current.msgSelectTrimPlane);
      return false;
    }
    final edit = s.editing;
    final body = edit?.bodyName ??
        s.bodyName ??
        (p.bodyNames.isEmpty ? p.nextSolidName() : p.bodyNames.last);
    final f = SplitFeature(
      name: edit?.name ?? p.nextFeatureName('Split'),
      bodyName: body,
      frame: fr,
      label: s.label.isEmpty ? 'Plane' : s.label,
      flip: s.flip,
    );
    if (edit != null) {
      final i = p.features.indexOf(edit);
      if (i >= 0) {
        f.seq = edit.seq;
        edit.disposeSolid();
        p.features[i] = f;
      }
    } else {
      f.seq = p.nextSeq();
      p.appendFeature(f);
    }
    splitSession = null;
    if (partKernel.available) {
      if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    }
    if (f.computeError != null) {
      toast(L.current.msgFeatureError(f.name, f.computeError!));
    }
    p.dirty = true;
    Log.i('part',
        'split ${edit == null ? "created" : "edited"} ${f.name} '
        'with ${f.label}${f.flip ? " (flipped)" : ""} -> ${f.bodyName}');
    if (curTab != null) await savePart(curTab!);
    notifyListeners();
    return true;
  }

  // ---- M227 — Combine: a boolean between two bodies ---------------------

  CombineSession? combineSession;

  /// True while the combine panel wants a BODY.
  bool get combinePicking3D => combineSession != null;

  void openCombine([CombineFeature? edit]) {
    final p = currentPart;
    if (p == null) return;
    if (edit == null &&
        combineSession != null &&
        combineSession!.editing == null) {
      cancelCombine();
      return;
    }
    if (edit == null && p.bodyNames.length < 2) {
      toast(L.current.msgCombineNeedsTwoBodies);
      return;
    }
    cancelExtrude();
    cancelEdgeFeature();
    cancelPattern();
    cancelHole();
    cancelCombine();
    _leaveSketchForCommand();
    final s = CombineSession()..editing = edit;
    if (edit != null) {
      s
        ..baseBody = edit.bodyName
        ..op = edit.op
        ..keepTool = edit.keepTool;
      s.tools.addAll(edit.tools);
    }
    combineSession = s;
    toast(s.baseBody == null
        ? L.current.msgTapBodyToKeep
        : L.current.msgTapBodiesToCombine(s.baseBody!));
    notifyListeners();
  }

  /// A tap landed on [bodyName]. The FIRST pick is the base — Inventor asks
  /// for it first, and it is the one thing here that is not a toggle: tapping
  /// the base again would leave the panel with nothing to keep.
  void combineBodyPicked(String bodyName) {
    final s = combineSession;
    if (s == null) return;
    if (s.baseBody == null) {
      s.baseBody = bodyName;
      toast(L.current.msgTapBodiesToCombine(bodyName));
      notifyListeners();
      return;
    }
    if (bodyName == s.baseBody) {
      toast(L.current.msgThatIsBaseBody);
      return;
    }
    if (!s.tools.remove(bodyName)) s.tools.add(bodyName);
    notifyListeners();
  }

  void setCombine({String? op, bool? keepTool, String? baseBody}) {
    final s = combineSession;
    if (s == null) return;
    if (op != null) s.op = op;
    if (keepTool != null) s.keepTool = keepTool;
    if (baseBody != null) {
      s.baseBody = baseBody;
      s.tools.remove(baseBody);
    }
    notifyListeners();
  }

  void cancelCombine() {
    if (combineSession == null) return;
    combineSession = null;
    notifyListeners();
  }

  Future<bool> applyCombine() async {
    final s = combineSession;
    final p = currentPart;
    if (s == null || p == null) return false;
    if (s.baseBody == null || s.tools.isEmpty) {
      toast(L.current.msgPickKeepThenCombine);
      return false;
    }
    final edit = s.editing;
    final f = CombineFeature(
      name: edit?.name ?? p.nextFeatureName('Combine'),
      bodyName: s.baseBody!,
      tools: [...s.tools],
      op: s.op,
      keepTool: s.keepTool,
    );
    if (edit != null) {
      final i = p.features.indexOf(edit);
      if (i >= 0) {
        f.seq = edit.seq;
        edit.disposeSolid();
        p.features[i] = f;
      }
    } else {
      f.seq = p.nextSeq();
      p.appendFeature(f);
    }
    combineSession = null;
    if (partKernel.available) {
      if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    }
    if (f.computeError != null) {
      toast(L.current.msgFeatureError(f.name, f.computeError!));
    }
    p.dirty = true;
    Log.i('part',
        'combine ${edit == null ? "created" : "edited"} ${f.name} '
        '${f.op} ${f.tools.join(",")} -> ${f.bodyName}'
        '${f.keepTool ? " (keep)" : ""}');
    if (curTab != null) await savePart(curTab!);
    notifyListeners();
    return true;
  }

  // ---- M212 — the PART patterns: Rectangular / Circular / Sketch Driven /
  //             Mirror. Inventor's Pattern panel, in 3D. ------------------
  //
  // ONE session for all four, mirroring [PatternFeature]: the four panels
  // differ only in which selectors and numbers they show, and four sessions
  // would have been four places to keep the feature selection, the preview
  // and the commit in step — the mistake this file already learned from
  // (ExtrudeSession serves five commands).
  PartPatternSession? patternSession;

  /// Which pattern command is open, or null. Used by the ribbon so a second
  /// tap on the same button closes it (M210's toggle).
  PatternKind? get patternKind => patternSession?.mode;

  void openRectPattern([PatternFeature? edit]) =>
      _openPattern(PatternKind.rectangular, edit);
  void openCircPattern([PatternFeature? edit]) =>
      _openPattern(PatternKind.circular, edit);
  void openSketchPattern([PatternFeature? edit]) =>
      _openPattern(PatternKind.sketchDriven, edit);
  void openMirror([PatternFeature? edit]) =>
      _openPattern(PatternKind.mirror, edit);

  void _openPattern(PatternKind kind, PatternFeature? edit) {
    // M210 — the same command twice closes it. Keyed by the pattern kind, so
    // Rectangular -> Circular switches rather than toggling off.
    if (edit == null &&
        patternSession != null &&
        patternSession!.editing == null &&
        patternSession!.mode == kind) {
      cancelPattern();
      return;
    }
    final p = currentPart;
    if (p == null) return;
    if (p.features.isEmpty) {
      toast(L.current
          .msgPatternNeedsFeature(patternKindDisplay(L.current, kind)));
      return;
    }
    cancelExtrude();
    cancelEdgeFeature();
    cancelPattern();
    cancelHole(); // M225 — one 3D panel at a time
    cancelCombine(); // M227 — likewise
    cancelSplit(); // M228 — likewise
    _leaveSketchForCommand(); // M221 — its picks are 3D picks too
    final s = PartPatternSession(kind, editing: edit);
    if (edit != null) {
      s.readFrom(edit);
    } else {
      // Inventor pre-selects nothing but does put you straight into the
      // Feature selector, which is where every one of these commands starts.
      s.bodyName = lastSolidFeature(p)?.bodyName ?? 'Solid1';
      s.active = PatternField.features;
    }
    patternSession = s;
    _updatePatternPreview();
    notifyListeners();
  }

  /// Inventor's rail beside the panel: switch to another pattern command
  /// WITHOUT losing what has been picked.
  ///
  /// The feature selection, the creation method and the solid/feature mode
  /// are the parts every one of the four commands shares, so they carry over;
  /// the placement inputs do not, because a direction is not an axis and an
  /// axis is not a plane. Re-opening the command from the ribbon instead
  /// would have thrown the selection away — which is the reason Inventor's
  /// rail exists at all.
  void switchPattern(PatternKind kind) {
    final old = patternSession;
    if (old == null || old.mode == kind) return;
    // M248 — the assembly's rail carries the SAME promise (switch command,
    // keep what has been picked) over a different set of inputs, so it is its
    // own path rather than a branch inside this one.
    if (old is AsmPatternSession) {
      _switchAsmPattern(old, kind);
      return;
    }
    final s = PartPatternSession(kind, editing: null);
    s.patternSolid = old.patternSolid;
    s.features
      ..clear()
      ..addAll(old.features);
    s.bodyName = old.bodyName;
    s.compute = old.compute;
    // The placement inputs that DO mean the same thing in both commands are
    // kept: a direction and a rotation axis are both "a line you picked".
    s.dirA = old.dirA ?? old.axis;
    s.axis = old.axis ?? old.dirA;
    s.plane = old.plane;
    s.pointSketch = old.pointSketch;
    s.pathA = old.pathA;
    s.startA = old.startA;
    s.active = old.features.isEmpty && !old.patternSolid
        ? PatternField.features
        : PatternField.none;
    old.disposePreview();
    patternSession = s;
    _updatePatternPreview();
    notifyListeners();
  }

  void cancelPattern() {
    final s = patternSession;
    if (s == null) return;
    // M248 — an assembly session has a LIVE preview to take away and possibly
    // relationships to put back, so it cancels through its own path. Routed
    // here rather than at every caller: the panel's ✕, its Cancel button, Esc
    // and every command that closes a sibling all come through this one.
    if (s is AsmPatternSession) {
      cancelAsmPattern();
      return;
    }
    s.disposePreview();
    patternSession = null;
    notifyListeners();
  }

  /// The panel mutates the session directly (counts, flips, the active
  /// selector) and calls this to re-preview and repaint.
  void patternChanged() {
    if (patternSession is AsmPatternSession) {
      _updateAsmPatternPreview();
      notifyListeners();
      return;
    }
    _updatePatternPreview();
    notifyListeners();
  }

  /// Arms one of the panel's selectors. Tapping the ACTIVE one disarms it,
  /// exactly like the pick fields in the extrude panel.
  void patternPick(PatternField field) {
    final s = patternSession;
    if (s == null) return;
    s.active = s.active == field ? PatternField.none : field;
    final asm = s is AsmPatternSession;
    switch (s.active) {
      case PatternField.features:
        // The same selector, a different noun: an assembly patterns
        // COMPONENTS, and the part's prompt would send the user looking for a
        // feature browser this document does not have.
        toast(asm ? L.current.msgTapComponentToPattern
            : L.current.msgSelectFeatures);
      case PatternField.dirA:
      case PatternField.dirB:
        toast(L.current.msgTapStraightOrCircularEdge);
      case PatternField.axis:
        toast(L.current.msgTapCircularOrStraightEdge);
      case PatternField.plane:
        toast(L.current.msgTapPlanarFace);
      case PatternField.pointSketch:
        toast(L.current.msgTapSketchForOccurrences);
      case PatternField.basePoint:
        toast(L.current.msgTapSketchPointOfOriginal);
      case PatternField.startA:
      case PatternField.startB:
        toast(L.current.msgTapCurveStart);
      case PatternField.orientFace:
        toast(L.current.msgTapFaceToFollow);
      case PatternField.solid:
        toast(L.current.msgTapSolidBodyToPattern);
      case PatternField.none:
        break;
    }
    notifyListeners();
  }

  /// True while a pattern selector wants a tap in the 3D viewport. The
  /// feature list is fed from the BROWSER, not from the viewport, so it is
  /// deliberately not in here.
  bool get patternPicking3D {
    final s = patternSession;
    if (s == null) return false;
    // M213 — features are pickable in the GRAPHICS WINDOW now, not only in
    // the browser: a tap on a face selects the feature that made it.
    return s.active == PatternField.features ||
        s.active == PatternField.startA ||
        s.active == PatternField.startB ||
        s.active == PatternField.orientFace ||
        s.active == PatternField.dirA ||
        s.active == PatternField.dirB ||
        s.active == PatternField.axis ||
        s.active == PatternField.plane ||
        s.active == PatternField.pointSketch ||
        s.active == PatternField.basePoint ||
        s.active == PatternField.solid;
  }

  /// A FEATURE row was tapped in the model browser while the Feature selector
  /// is armed. Inventor's multi-select: tapping a chosen feature removes it.
  ///
  /// Returns true when the tap was consumed, so the browser knows not to open
  /// the feature's editor as well.
  bool patternToggleFeature(PartFeature f) {
    final s = patternSession;
    if (s == null || s.active != PatternField.features || s.patternSolid) {
      return false;
    }
    final p = currentPart;
    if (p == null) return false;
    // A pattern can only copy what is BUILT BEFORE it. Picking a feature that
    // sits below the pattern would be a cycle: the pattern's input would be
    // built out of the pattern's own result.
    final edit = s.editing;
    if (edit != null) {
      var seenPattern = false;
      for (final g in p.features) {
        if (identical(g, edit)) seenPattern = true;
        if (identical(g, f) && seenPattern) {
          toast(L.current.msgBuiltAfterPattern(f.name));
          return true;
        }
      }
    }
    if (!s.features.remove(f.name)) {
      s.features.add(f.name);
      // Inventor patterns into the body the selected features build.
      s.bodyName = f.bodyName;
    }
    _updatePatternPreview();
    notifyListeners();
    return true;
  }

  bool patternHasFeature(String name) =>
      patternSession?.features.contains(name) ?? false;

  /// M213 — face -> feature, cached per MESH.
  ///
  /// Keyed by mesh identity because that is exactly what changes when the
  /// answer changes: a rebuild produces new meshes, and so does a refine at a
  /// finer tessellation. The cache is small and is dropped wholesale rather
  /// than invalidated cleverly — attribution costs one pass over the faces,
  /// and a stale entry here would select the wrong feature.
  final Map<int, Map<int, String>> _faceOwnerCache = {};

  /// Which feature made face [faceId] of [solid], or null when nothing
  /// claims it. Null is a real answer here: a face that no feature's surface
  /// accounts for is unknown, and guessing would pick a feature at random.
  PartFeature? featureOfFace(KernelSolid solid, int faceId) {
    final p = currentPart;
    if (p == null || faceId < 0) return null;
    final body = _bodyNameOfSolid(solid);
    if (body == null) return null;
    final key = identityHashCode(solid.mesh);
    var owners = _faceOwnerCache[key];
    if (owners == null) {
      if (_faceOwnerCache.length > 8) _faceOwnerCache.clear();
      owners = attributeFaces(p, body, solid);
      _faceOwnerCache[key] = owners;
      Log.i(
          'part',
          'face provenance for "$body": ${owners.length} of '
              '${faceSurfaces(solid.mesh).length} faces attributed');
    }
    final name = owners[faceId];
    if (name == null) return null;
    for (final f in p.features) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// A SKETCH row was tapped in the browser while the sketch-driven pattern
  /// is waiting for its points. Returns true when the tap was consumed, so
  /// the browser does not also open the sketch for editing — which would
  /// close the panel that asked for it.
  ///
  /// The browser matters here more than the viewport does: the points of a
  /// consumed sketch are hidden by default, so on a real part the tree is
  /// usually the only place the sketch can be pointed at at all.
  bool patternToggleSketch(ChildSketch cs) {
    final s = patternSession;
    if (s == null ||
        s.mode != PatternKind.sketchDriven ||
        s.active != PatternField.pointSketch) {
      return false;
    }
    patternPointSketchPicked(cs.model.name);
    return true;
  }

  /// A direction or axis was picked in 3D, already reduced to a point and a
  /// direction in world coordinates by the viewport.
  void patternAxisPicked(Vec3 point, Vec3 dir, String label) {
    final s = patternSession;
    if (s == null) return;
    if (dir.length < 1e-9) {
      toast(L.current.msgEdgeNoDirection);
      return;
    }
    // M248 — the panel's three origin-axis shortcuts reach an assembly session
    // through here as well, so the quick row needs no branch of its own. What
    // is stored is a REFERENCE to the assembly's own origin, which is exactly
    // as fixed as a part's and is therefore the one AsmRef that never moves.
    if (s is AsmPatternSession) {
      _asmPatternAxisPicked(s, AsmRef(kAssemblyOrigin,
          AsmGeom.axis(point, dir, source: WorkRefSource.axis), label));
      return;
    }
    final ref = AxisRef(point.x, point.y, point.z, dir.x, dir.y, dir.z, label);
    switch (s.active) {
      case PatternField.dirA:
        s.dirA = ref;
      case PatternField.dirB:
        s.dirB = ref;
      case PatternField.axis:
        s.axis = ref;
      default:
        return;
    }
    Log.i('pattern',
        '${s.active.name} = $label p=(${point.x.toStringAsFixed(2)},'
        '${point.y.toStringAsFixed(2)},${point.z.toStringAsFixed(2)}) '
        'd=(${dir.x.toStringAsFixed(3)},${dir.y.toStringAsFixed(3)},'
        '${dir.z.toStringAsFixed(3)})');
    // One pick, one field: the selector disarms itself so the next tap in the
    // viewport is an ordinary tap again, not a silent re-pick of the value
    // that was just chosen.
    s.active = PatternField.none;
    _updatePatternPreview();
    notifyListeners();
  }

  /// M213 — a CURVE was picked as the direction of a row.
  ///
  /// A path and a straight direction are alternatives for the same row, so
  /// picking one clears the other: a panel showing both would be saying two
  /// different things about where the occurrences go.
  void patternPathPicked(CurveSel sel, {required bool first}) {
    final s = patternSession;
    if (s == null) return;
    if (first) {
      s.pathA = sel;
      s.dirA = null;
      s.startA = 0;
      s.startPickedA = false;
      // Inventor's Orientation Method starts at Identical for a path pattern.
      // The field is shared with the circular command, whose own default is
      // Rotational, so it is set HERE rather than left at whatever the other
      // command wanted.
      s.orientation = PatternOrient.fixed;
    } else {
      s.pathB = sel;
      s.dirB = null;
      s.startB = 0;
      s.startPickedB = false;
    }
    s.active = PatternField.none;
    Log.i('pattern',
        '${first ? "A" : "B"} runs along ${sel.sketchName}#${sel.geoIndex}');
    _updatePatternPreview();
    notifyListeners();
  }

  /// Inventor's Start: where on the path the ORIGINAL sits.
  void patternStartPicked(Vec3 world, {required bool first}) {
    final s = patternSession;
    final p = currentPart;
    if (s == null || p == null) return;
    final sel = first ? s.pathA : s.pathB;
    if (sel == null) {
      toast(L.current.msgPickCurveFirst);
      return;
    }
    final (pts, err) = resolvePath(p, sel);
    if (pts == null) {
      toast(err ?? L.current.msgCurveGone);
      return;
    }
    final poly = <Vec3>[
      for (var i = 0; i + 2 < pts.length; i += 3)
        Vec3(pts[i], pts[i + 1], pts[i + 2])
    ];
    final at = arcLengthNearest(poly, world);
    if (first) {
      s.startA = at;
      s.startPickedA = true;
    } else {
      s.startB = at;
      s.startPickedB = true;
    }
    s.active = PatternField.none;
    _updatePatternPreview();
    notifyListeners();
  }

  /// Inventor's Variable Orientation: the face the occurrences follow.
  void patternOrientFacePicked(PlaneFrame frame) {
    final s = patternSession;
    if (s == null) return;
    s.orientFace = FaceSel(frame.origin.x, frame.origin.y, frame.origin.z,
        frame.n.x, frame.n.y, frame.n.z);
    s.active = PatternField.none;
    _updatePatternPreview();
    notifyListeners();
  }

  /// Inventor 2026's Irregular Distance / Angle. [step] is the occurrence's
  /// step index (1 = the first copy); a null [value] removes the override and
  /// the even spacing takes that occurrence back.
  void patternSetIrregular(String which, int step, double? value) {
    final s = patternSession;
    if (s == null || step < 1) return;
    final m = switch (which) {
      'B' => s.irregularB,
      'C' => s.irregularC,
      _ => s.irregularA,
    };
    if (value == null) {
      m.remove(step);
    } else {
      m[step] = value;
    }
    _updatePatternPreview();
    notifyListeners();
  }

  /// A planar face / work plane / origin plane was picked for the mirror.
  void patternPlanePicked(Vec3 point, Vec3 normal, String label) {
    final s = patternSession;
    if (s == null || s.active != PatternField.plane) return;
    if (normal.length < 1e-9) return;
    if (s is AsmPatternSession) {
      s.refPlane = AsmRef(
          kAssemblyOrigin, AsmGeom.plane(point, normal), label,
          anchor: point);
      s.active = PatternField.none;
      _updateAsmPatternPreview();
      notifyListeners();
      return;
    }
    s.plane =
        PlaneRef(point.x, point.y, point.z, normal.x, normal.y, normal.z, label);
    s.active = PatternField.none;
    Log.i('pattern', 'mirror plane = $label');
    _updatePatternPreview();
    notifyListeners();
  }

  /// The sketch that holds a sketch-driven pattern's points.
  void patternPointSketchPicked(String sketchName) {
    final s = patternSession;
    final p = currentPart;
    if (s == null || p == null) return;
    final cs = p.sketchByName(sketchName);
    if (cs == null) return;
    final pts = sketchPatternPoints(cs.model);
    if (pts.isEmpty) {
      toast(L.current.msgSketchHasNoPoints(sketchName));
      return;
    }
    s.pointSketch = sketchName;
    s.basePicked = false;
    s.active = PatternField.none;
    Log.i('pattern',
        'point sketch = $sketchName (${pts.length} point(s))');
    _updatePatternPreview();
    notifyListeners();
  }

  /// Inventor's Base Point: which of the sketch's points the ORIGINAL sits on.
  void patternBasePointPicked(String sketchName, Offset sketchPoint) {
    final s = patternSession;
    if (s == null) return;
    if (s.pointSketch.isEmpty) s.pointSketch = sketchName;
    if (s.pointSketch != sketchName) {
      toast(L.current.msgBasePointMustBeOf(s.pointSketch));
      return;
    }
    s.basePicked = true;
    s.baseX = sketchPoint.dx;
    s.baseY = sketchPoint.dy;
    s.active = PatternField.none;
    _updatePatternPreview();
    notifyListeners();
  }

  /// Solid mode: which body the whole-solid pattern acts on.
  void patternBodyPicked(String name) {
    final s = patternSession;
    if (s == null) return;
    s.bodyName = name;
    s.active = PatternField.none;
    _updatePatternPreview();
    notifyListeners();
  }

  /// Inventor's Input Geometry switch: pattern FEATURES, or the whole solid.
  void patternSetSolidMode(bool solid) {
    final s = patternSession;
    if (s == null || s.patternSolid == solid) return;
    s.patternSolid = solid;
    s.active = solid ? PatternField.solid : PatternField.features;
    _updatePatternPreview();
    notifyListeners();
  }

  /// Suppress / restore ONE occurrence, the way Inventor does it from the
  /// browser. [index] is Inventor's numbering, with the original as 1 — and
  /// the original is not this feature's to suppress, so it is refused.
  void patternSuppressOccurrence(PatternFeature f, int index, bool suppress) {
    final p = currentPart;
    if (p == null || index <= 1) return;
    if (suppress ? !f.suppressed.add(index) : !f.suppressed.remove(index)) {
      return;
    }
    f.builtSig = null;
    if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    Log.i('part',
        '${f.name}: occurrence $index ${suppress ? "suppressed" : "restored"}');
    notifyListeners();
  }

  /// The feature the panel currently describes, or the reason it cannot be
  /// built yet. One function, used by BOTH the preview and OK, so what you
  /// see is exactly what the button commits.
  (PatternFeature?, String?) _patternSessionFeature() {
    final s = patternSession;
    final p = currentPart;
    if (s == null || p == null) return (null, 'no session');
    if (!s.patternSolid && s.features.isEmpty) {
      return (null, L.current.valSelectOneFeature);
    }
    final f = PatternFeature(
      name: s.editing?.name ?? p.nextFeatureName(patternTypeLabel(s.mode)),
      bodyName: s.bodyName.isEmpty ? 'Solid1' : s.bodyName,
      mode: s.mode,
      patternSolid: s.patternSolid,
      sources: s.patternSolid ? const [] : s.features,
      compute: s.compute,
      suppressed: s.suppressed,
      visible: s.editing?.visible ?? true,
    );
    switch (s.mode) {
      case PatternKind.rectangular:
        if (s.dirA == null && s.pathA == null) {
          return (null, L.current.valSelectDirectionA);
        }
        final ca = _patternCount(s.exprCountA);
        if (ca == null) return (null, L.current.valCountAAtLeastOne);
        final da = parseValueExpr(s.exprDistanceA);
        if (da == null || !(da > 0)) {
          return (null, L.current.valDistanceAPositive);
        }
        f
          ..dirA = s.dirA?.copy()
          ..pathA = s.pathA
          ..startA = s.startA
          ..flipA = s.flipA
          ..midplaneA = s.midplaneA
          ..countA = ca
          ..distanceA = da
          ..exprCountA = s.exprCountA
          ..exprDistanceA = s.exprDistanceA
          ..distributionA = s.distributionA
          ..orientation = s.orientation;
        f.irregularA.addAll(s.irregularA);
        if (s.dirB != null || s.pathB != null) {
          final cb = _patternCount(s.exprCountB);
          if (cb == null) {
            return (null, L.current.valCountBAtLeastOne);
          }
          final db = parseValueExpr(s.exprDistanceB);
          if (db == null || !(db > 0)) {
            return (null, L.current.valDistanceBPositive);
          }
          f
            ..dirB = s.dirB?.copy()
            ..pathB = s.pathB
            ..startB = s.startB
            ..flipB = s.flipB
            ..midplaneB = s.midplaneB
            ..countB = cb
            ..distanceB = db
            ..exprCountB = s.exprCountB
            ..exprDistanceB = s.exprDistanceB
            ..distributionB = s.distributionB;
          f.irregularB.addAll(s.irregularB);
        }
        // Through occurrenceCount, not countA * countB: a second direction
        // that was never picked is not a second row, and multiplying by its
        // leftover count let a one-occurrence pattern through the panel to
        // fail in the kernel instead.
        if (f.occurrenceCount <= 1) {
          return (null, L.current.valPatternNeedsTwo);
        }
      case PatternKind.circular:
        if (s.axis == null) return (null, L.current.valSelectRotationAxis);
        final n = _patternCount(s.exprCountC);
        if (n == null) return (null, L.current.valCountAtLeastOne);
        if (n <= 1) return (null, L.current.valPatternNeedsTwo);
        final ang = parseValueExpr(s.exprAngleC);
        if (ang == null || ang == 0) {
          return (null, L.current.valAngleNotZero);
        }
        f
          ..axis = s.axis!.copy()
          ..flipC = s.flipC
          ..countC = n
          ..angleC = ang
          ..exprCountC = s.exprCountC
          ..exprAngleC = s.exprAngleC
          ..distributionC = s.distributionC
          ..orientation = s.orientation;
        f.irregularC.addAll(s.irregularC);
      case PatternKind.sketchDriven:
        if (s.pointSketch.isEmpty) {
          return (null, L.current.valSelectPointSketch);
        }
        f
          ..pointSketch = s.pointSketch
          ..basePicked = s.basePicked
          ..baseX = s.baseX
          ..baseY = s.baseY
          ..orientFace = s.orientFace;
      case PatternKind.mirror:
        if (s.plane == null) return (null, L.current.valSelectMirrorPlane);
        f
          ..mirrorPlane = s.plane!.copy()
          ..removeOriginal = s.removeOriginal && s.patternSolid;
    }
    return (f, null);
  }

  /// A count field: a positive whole number, through the same expression
  /// parser every other value uses (so "2 * 3" is six occurrences).
  static int? _patternCount(String expr) {
    final v = parseValueExpr(expr);
    if (v == null) return null;
    final n = v.round();
    if (n < 1 || (v - n).abs() > 1e-6) return null;
    return n > kPatternMaxCount ? null : n;
  }

  void _updatePatternPreview() {
    final s = patternSession;
    final p = currentPart;
    if (s == null || p == null) return;
    s.disposePreview();
    s.previewError = null;
    final (f, err) = _patternSessionFeature();
    if (f == null) {
      s.previewError = err;
      return;
    }
    if (!partKernel.available) {
      // Host builds have no kernel. Say so rather than showing an empty
      // viewport that looks like a broken pattern.
      s.previewError = null;
      return;
    }
    // The base is the body as it stands just BEFORE this feature's position:
    // for a new pattern that is the whole body, for an edit it is everything
    // above the feature being edited.
    final edit = s.editing;
    final base = edit == null
        ? currentBodySolid(p, f.bodyName)
        : bodyBaseBefore(p, f.bodyName, edit);
    if (base == null) {
      s.previewError = L.current.valNoSolidToPattern;
      return;
    }
    if (!recomputeFeature(p, f, partKernel, base: base)) {
      s.previewError = f.computeError;
      return;
    }
    s.preview = f.solid;
    s.previewReplacesBody = f.bodyName;
    f.solid = null; // ownership moves to the session
  }

  Future<bool> applyPattern() async {
    final s = patternSession;
    if (s is AsmPatternSession) return applyAsmPattern();
    final p = currentPart;
    if (s == null || p == null) return false;
    final (f, err) = _patternSessionFeature();
    if (f == null) {
      toast(err ?? L.current.msgCannotCreatePattern);
      return false;
    }
    final edit = s.editing;
    if (edit != null) {
      final i = p.features.indexOf(edit);
      if (i >= 0) {
        f.seq = edit.seq;
        edit.disposeSolid();
        p.features[i] = f;
      }
    } else {
      f.seq = p.nextSeq();
      p.appendFeature(f);
    }
    s.disposePreview();
    patternSession = null;
    if (partKernel.available) {
      if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    }
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    Log.i(
        'part',
        '${patternKindLabel(f.mode)} ${edit == null ? "created" : "edited"} '
            '${f.name} (${f.bodyName}) '
            '${f.patternSolid ? "solid" : "${f.sources.length} feature(s)"}');
    notifyListeners();
    return true;
  }

  // ---- M248 — the ASSEMBLY patterns: Pattern Component, Mirror Component,
  //             Copy Component. ---------------------------------------------
  //
  // The same session and the same panel as the part's four, for the reason
  // stated on [AsmPatternSession]. What is different is only what the commands
  // below do with them: the picks come from the assembly viewport rather than
  // the browser, the placement inputs are stored as references that MOVE, and
  // the "preview" is the real thing — the pattern is placed live and Cancel
  // removes it, exactly as the constraint preview places a real constraint and
  // solves with it (see _refreshConstraintPreview).

  /// True while the open pattern command belongs to an assembly.
  bool get asmPatternPicking =>
      patternSession is AsmPatternSession && currentAssembly != null;

  AsmPatternSession? get asmPatternSession =>
      patternSession is AsmPatternSession ? patternSession as AsmPatternSession : null;

  /// Opens Pattern Component (rectangular / circular) or Mirror Component.
  void openAsmPattern(PatternKind kind, [AsmPattern? edit]) {
    final a = currentAssembly;
    if (a == null) return;
    // M210's toggle, keyed by kind — the same rule the part commands follow.
    if (edit == null &&
        patternSession is AsmPatternSession &&
        patternSession!.editing == null &&
        patternSession!.mode == kind) {
      cancelPattern();
      return;
    }
    if (a.occurrences.isEmpty) {
      toast(L.current
          .msgPatternNeedsComponent(patternKindDisplay(L.current, kind)));
      return;
    }
    cancelConstraint();
    cancelWorkFeature();
    cancelPattern();
    cancelAsmPosition(); // M250 — one armed assembly command at a time
    final s = AsmPatternSession(kind, editing: edit);
    if (edit != null) {
      s.readFromAsm(edit);
      // A snapshot to put back on Cancel. The live preview edits the real
      // pattern in place, so without this an opened-and-cancelled edit would
      // leave whatever was typed before the user changed their mind.
      s.restore = AsmPattern(
        name: edit.name,
        mode: edit.mode,
        sources: [...edit.sources],
        refDirA: edit.refDirA,
        refDirB: edit.refDirB,
        refAxis: edit.refAxis,
        refPlane: edit.refPlane,
        driver: edit.driver,
      );
      copyPatternParameters(edit, s.restore!);
    } else {
      s.name = a.nextPatternName(kind);
      // Inventor pre-selects the component you had selected, which is nearly
      // always the one you meant — and puts you in the seed selector either
      // way so a second tap adds another.
      final sel = a.selected;
      if (sel != null && !sel.isPatternElement) s.features.add(sel.id);
      s.active = PatternField.features;
      // A mirror wants its plane next; a grid wants its first direction.
      if (s.features.isNotEmpty) {
        s.active = kind == PatternKind.mirror
            ? PatternField.plane
            : (kind == PatternKind.circular
                ? PatternField.axis
                : PatternField.dirA);
      }
    }
    s.constraintsBefore.addAll(a.constraints);
    patternSession = s;
    _updateAsmPatternPreview();
    notifyListeners();
  }

  /// A tap in the assembly viewport, while a pattern selector is armed.
  ///
  /// Returns true when it was consumed, so the viewport knows not to also
  /// select or drag the component underneath.
  bool asmPatternPick(AsmPick pick) {
    final s = asmPatternSession;
    final a = currentAssembly;
    if (s == null || a == null) return false;
    final r = pick.ref;
    switch (s.active) {
      case PatternField.features:
        // A SEED is a component, so what is taken from the pick is only which
        // occurrence it landed on. Tapping a chosen one removes it, which is
        // Inventor's multi-select and the part panel's own behaviour.
        if (r.isAssemblyOrigin) {
          toast(L.current.msgTapComponentToPattern);
          return true;
        }
        final o = a.byId(r.occurrence);
        if (o == null) return true;
        if (o.isPatternElement) {
          // Patterning a pattern's own output is a cycle: the seed's placement
          // would be a function of the pattern that is being given it.
          toast(L.current.msgCannotPatternAnElement);
          return true;
        }
        if (!s.features.remove(o.id)) s.features.add(o.id);
      case PatternField.dirA:
      case PatternField.dirB:
      case PatternField.axis:
        if (!r.geom.isAxis) {
          toast(L.current.msgTapStraightOrCircularEdge);
          return true;
        }
        if (s.active == PatternField.dirA) {
          s.refDirA = r;
        } else if (s.active == PatternField.dirB) {
          s.refDirB = r;
        } else {
          s.refAxis = r;
        }
        s.active = PatternField.none;
      case PatternField.plane:
        if (!r.geom.isPlane) {
          toast(L.current.msgTapPlanarFace);
          return true;
        }
        s.refPlane = r;
        s.active = PatternField.none;
      default:
        return false;
    }
    _updateAsmPatternPreview();
    notifyListeners();
    return true;
  }

  void _asmPatternAxisPicked(AsmPatternSession s, AsmRef r) {
    switch (s.active) {
      case PatternField.dirA:
        s.refDirA = r;
      case PatternField.dirB:
        s.refDirB = r;
      case PatternField.axis:
        s.refAxis = r;
      default:
        return;
    }
    s.active = PatternField.none;
    _updateAsmPatternPreview();
    notifyListeners();
  }

  /// The assembly rail: switch command WITHOUT losing what has been picked.
  ///
  /// The seeds carry over, because they mean the same thing in all three; and
  /// a direction and a rotation axis are both "a line you picked", so those
  /// carry too. The mirror plane is neither, and keeping it would have the
  /// panel saying two different things about where the copies go — Inventor's
  /// own reason for the rail's rules, and the part [switchPattern]'s.
  void _switchAsmPattern(AsmPatternSession old, PatternKind kind) {
    final a = currentAssembly;
    if (a == null || !kAsmPatternKinds.contains(kind)) return;
    final s = AsmPatternSession(kind);
    s.name = old.name;
    s.restore = old.restore;
    s.constraintsBefore.addAll(old.constraintsBefore);
    s.features
      ..clear()
      ..addAll(old.features);
    s.compute = old.compute;
    s.driver = kind == PatternKind.mirror ? null : old.driver;
    s.refDirA = old.refDirA ?? old.refAxis;
    s.refAxis = old.refAxis ?? old.refDirA;
    s.refDirB = old.refDirB;
    s.refPlane = old.refPlane;
    s.active = old.features.isEmpty
        ? PatternField.features
        : PatternField.none;
    patternSession = s;
    _updateAsmPatternPreview();
    notifyListeners();
  }

  /// Inventor's Associative tab: the pattern follows a FEATURE pattern inside
  /// a component. Null clears it and the pattern goes back to its own numbers.
  void asmPatternSetDriver((String, String)? driver) {
    final s = asmPatternSession;
    if (s == null) return;
    s.driver = driver;
    s.active = PatternField.none;
    _updateAsmPatternPreview();
    notifyListeners();
  }

  /// Every feature pattern reachable from this assembly, as
  /// (occurrence id, feature name) — what the Associative picker lists.
  ///
  /// Read off the LIVE models (M245), so a pattern added to a part appears
  /// here the moment you look.
  List<(String, String)> asmPatternDrivers() {
    final a = currentAssembly;
    if (a == null) return const [];
    return [
      for (final o in a.occurrences)
        if (!o.isPatternElement)
          for (final f in o.part?.features ?? const <PartFeature>[])
            if (f is PatternFeature && f.mode != PatternKind.mirror)
              (o.id, f.name)
    ];
  }

  /// The pattern the panel currently describes, or the reason it cannot be
  /// built. One function for both the preview and OK, so what is on screen is
  /// exactly what the button keeps.
  (AsmPattern?, String?) _asmSessionPattern() {
    final s = asmPatternSession;
    final a = currentAssembly;
    if (s == null || a == null) return (null, 'no session');
    if (s.features.isEmpty) return (null, L.current.valSelectOneComponent);
    final f = AsmPattern(
      name: s.name,
      mode: s.mode,
      sources: s.features,
      refDirA: s.refDirA,
      refDirB: s.refDirB,
      refAxis: s.refAxis,
      refPlane: s.refPlane,
      driver: s.driver,
    );
    f.compute = s.compute;
    f.suppressed.addAll(s.suppressed);
    if (s.driver != null) {
      if (driverFeatureOf(a, s.driver!.$1, s.driver!.$2) == null) {
        return (null, L.current.valDrivingFeatureGone);
      }
      return (f, null);
    }
    switch (s.mode) {
      case PatternKind.rectangular:
        if (s.refDirA == null) return (null, L.current.valSelectDirectionA);
        final ca = _patternCount(s.exprCountA);
        if (ca == null) return (null, L.current.valCountAAtLeastOne);
        final da = parseValueExpr(s.exprDistanceA);
        if (da == null || !(da > 0)) {
          return (null, L.current.valDistanceAPositive);
        }
        f
          ..flipA = s.flipA
          ..midplaneA = s.midplaneA
          ..countA = ca
          ..distanceA = da
          ..exprCountA = s.exprCountA
          ..exprDistanceA = s.exprDistanceA
          ..distributionA = s.distributionA;
        f.irregularA.addAll(s.irregularA);
        if (s.refDirB != null) {
          final cb = _patternCount(s.exprCountB);
          if (cb == null) return (null, L.current.valCountBAtLeastOne);
          final db = parseValueExpr(s.exprDistanceB);
          if (db == null || !(db > 0)) {
            return (null, L.current.valDistanceBPositive);
          }
          f
            ..flipB = s.flipB
            ..midplaneB = s.midplaneB
            ..countB = cb
            ..distanceB = db
            ..exprCountB = s.exprCountB
            ..exprDistanceB = s.exprDistanceB
            ..distributionB = s.distributionB;
          f.irregularB.addAll(s.irregularB);
        }
        if (f.occurrenceCount <= 1) return (null, L.current.valPatternNeedsTwo);
      case PatternKind.circular:
        if (s.refAxis == null) return (null, L.current.valSelectRotationAxis);
        final n = _patternCount(s.exprCountC);
        if (n == null) return (null, L.current.valCountAtLeastOne);
        if (n <= 1) return (null, L.current.valPatternNeedsTwo);
        final ang = parseValueExpr(s.exprAngleC);
        if (ang == null || ang == 0) return (null, L.current.valAngleNotZero);
        f
          ..flipC = s.flipC
          ..countC = n
          ..angleC = ang
          ..exprCountC = s.exprCountC
          ..exprAngleC = s.exprAngleC
          ..distributionC = s.distributionC
          ..orientation = s.orientation;
        f.irregularC.addAll(s.irregularC);
      case PatternKind.mirror:
        if (s.refPlane == null) return (null, L.current.valSelectMirrorPlane);
      case PatternKind.sketchDriven:
        return (null, L.current.valSelectPointSketch);
    }
    return (f, null);
  }

  /// The LIVE preview: the pattern is placed for real and Cancel takes it
  /// away again.
  ///
  /// A ghost drawn by a second painter was the alternative, and it would have
  /// been a second renderer for geometry that the ordinary one already draws
  /// perfectly. Placing it means the preview is depth-sorted against the rest
  /// of the assembly, tinted the same, and picked the same — and it costs one
  /// regeneration per keystroke, which is a closed-form expression per element.
  void _updateAsmPatternPreview() {
    final s = asmPatternSession;
    final a = currentAssembly;
    if (s == null || a == null) return;
    final (f, err) = _asmSessionPattern();
    s.previewError = err;
    final i = a.patterns.indexWhere((p) => p.name == s.name);
    if (f == null) {
      // Not buildable yet: take the elements away rather than leaving the
      // previous keystroke's on screen, which would say the panel accepted
      // something it is refusing.
      if (i >= 0) a.removePattern(s.name);
    } else if (i >= 0) {
      a.patterns[i] = f;
    } else {
      a.patterns.add(f);
    }
    _solveAssembly(a);
    a.bump();
  }

  /// How many relationships the open command has destroyed so far.
  ///
  /// The panel shows it as a warning line. It reports what has ALREADY
  /// happened rather than what would happen, because the preview is the real
  /// thing — you see the rows go and you see the number, and Cancel puts both
  /// back (see [AsmPatternSession.constraintsBefore]). An element's identity
  /// is stable across a count change, so this is only ever the relationships
  /// on elements that genuinely ceased to exist.
  int asmPatternDroppedRelationships() {
    final s = asmPatternSession;
    final a = currentAssembly;
    if (s == null || a == null) return 0;
    final n = s.constraintsBefore.length - a.constraints.length;
    return n > 0 ? n : 0;
  }

  Future<bool> applyAsmPattern() async {
    final s = asmPatternSession;
    final a = currentAssembly;
    if (s == null || a == null) return false;
    final (f, err) = _asmSessionPattern();
    if (f == null) {
      toast(err ?? L.current.msgCannotCreatePattern);
      return false;
    }
    // The preview already placed it; OK is simply "stop being able to cancel".
    patternSession = null;
    a.bump();
    unawaited(saveAssembly(a.name));
    Log.i(
        'assembly',
        '${patternKindLabel(f.mode)} ${s.editing == null ? "created" : "edited"} '
            '${f.name}: ${f.seeds.length} seed(s), '
            '${a.elementsOf(f.name).length} element(s)'
            '${f.isAssociative ? " driven by ${f.driver!.$1}/${f.driver!.$2}" : ""}');
    notifyListeners();
    return true;
  }

  /// Esc / Cancel: the previewed pattern goes away, or an edited one goes
  /// back to what it was.
  void cancelAsmPattern() {
    final s = asmPatternSession;
    final a = currentAssembly;
    if (s == null || a == null) return;
    final was = s.restore;
    if (was == null) {
      a.removePattern(s.name);
    } else {
      final i = a.patterns.indexWhere((p) => p.name == s.name);
      if (i >= 0) {
        a.patterns[i] = was;
      } else {
        a.patterns.add(was);
      }
    }
    patternSession = null;
    // The pattern first, so the regeneration puts every element back under the
    // id it had; THEN the relationships, which name those ids. The other order
    // would restore constraints to components that do not exist yet, and
    // AssemblyModel.remove would take them straight back off.
    _solveAssembly(a);
    for (final c in s.constraintsBefore) {
      if (a.constraints.contains(c)) continue;
      if (c.occurrences.any((id) => a.byId(id) == null)) continue;
      a.constraints.add(c);
    }
    _solveAssembly(a);
    a.bump();
    notifyListeners();
  }

  /// Suppress / restore ONE element, from the browser.
  ///
  /// Inventor's own verb, and the reason a pattern element has no Delete: the
  /// elements belong to the pattern. [index] is Inventor's numbering with the
  /// seed as 1, and the seed is not the pattern's to suppress.
  void asmPatternSuppressElement(AsmPattern p, int index, bool suppress) {
    final a = currentAssembly;
    if (a == null || index <= 1) return;
    if (suppress ? !p.suppressed.add(index) : !p.suppressed.remove(index)) {
      return;
    }
    _solveAssembly(a);
    a.bump();
    unawaited(saveAssembly(a.name));
    Log.i('assembly',
        '${p.name}: element $index ${suppress ? "suppressed" : "restored"}');
    notifyListeners();
  }

  /// Deletes a pattern and every element it placed.
  void deleteAsmPattern(String name) {
    final a = currentAssembly;
    if (a == null) return;
    if (a.patternNamed(name) == null) return;
    if (asmPatternSession?.name == name) patternSession = null;
    a.removePattern(name);
    _solveAssembly(a);
    a.bump();
    unawaited(saveAssembly(a.name));
    Log.i('assembly', 'pattern "$name" deleted');
    notifyListeners();
  }

  /// M248 — COPY COMPONENT.
  ///
  /// Inventor's Copy Components writes NEW PART DOCUMENTS, and rule 1 forbids
  /// that: every instance in this app is an occurrence of the same document,
  /// which is what keeps M245's live link. The honest reading of the command
  /// that remains is "place more occurrences of the same components, keeping
  /// their arrangement", and that is what this does.
  ///
  /// The difference from Place, which is the reason it is a separate command:
  /// Place drops a fresh component at the identity, while this reproduces the
  /// selected one AS IT SITS — its orientation and, for a mirrored component,
  /// its handedness. A subassembly keeps everything inside it, unchanged,
  /// because a copy of a subassembly is a second occurrence of the same
  /// document and its contents were never this occurrence's to begin with.
  ///
  /// Relationships are NOT copied. A constraint mates two named components,
  /// and a copy of one end of it is not constrained to anything — which is
  /// what Inventor's own Copy Components does with constraints that reach
  /// outside the copied set.
  void copySelectedComponent() {
    final a = currentAssembly;
    final o = a?.selected;
    if (a == null || o == null) {
      toast(L.current.msgSelectComponentToCopy);
      return;
    }
    if (o.isPatternElement) {
      // A copy of an element would be an ordinary component that happened to
      // look like one, and the next regeneration would place the element and
      // leave the copy behind. Copy the SEED, or edit the pattern's count.
      toast(L.current.msgCannotCopyAnElement);
      return;
    }
    final bounds = occurrenceBounds(o);
    final size = bounds == null
        ? null
        : (bounds.$1 - o.offset, bounds.$2 - o.offset);
    final copy = AssemblyOccurrence(
      id: a.nextOccurrenceId(o.source),
      source: o.source,
      sourceKind: o.sourceKind,
      offset: o.offset + nextPlacement(a, size),
      rot: o.rot,
      reflect: o.reflect,
      visible: o.visible,
      part: o.part,
      sub: o.sub,
    );
    a.occurrences.add(copy);
    a.selected = copy;
    a.bump();
    _solveAssembly(a);
    unawaited(saveAssembly(a.name));
    Log.i('assembly', 'copied ${o.id} as ${copy.id}');
    notifyListeners();
  }

  /// M137 — Revolve. Shares the extrude session and panel; [kind] switches
  /// Distance for Angle, Taper for the axis, and adds Full.
  void openRevolve([RevolveFeature? edit]) {
    if (_toggles3DOff('revolve', edit)) return; // M210
    _openExtrudeCore();
    final s = extrudeSession;
    if (s == null) return;
    s.kind = 'revolve';
    s.exprA = '360.00 deg';
    s.exprB = '0.00 deg';
    if (edit != null) {
      s.editing = edit;
      s.sketchName = edit.sketchName;
      s.bodyName = edit.bodyName;
      s.direction = edit.direction;
      s.output = edit.output;
      s.exprA = edit.exprA;
      s.exprB = edit.exprB;
      s.full = edit.full;
      s.axPx = edit.axPx;
      s.axPy = edit.axPy;
      s.axDx = edit.axDx;
      s.axDy = edit.axDy;
      s.axisPicked = true;
      s.axisLabel = L.current.lblAxis;
      s.profiles
        ..clear()
        ..addAll(
            [for (final x in edit.profiles) ProfileSel(x.ax, x.ay, x.area)]);
    }
    _updateExtrudePreview();
    notifyListeners();
  }

  void openSweep([SweepFeature? edit]) => _openSketchFeature('sweep', edit);
  void openLoft([LoftFeature? edit]) => _openSketchFeature('loft', edit);
  void openCoil([CoilFeature? edit]) => _openSketchFeature('coil', edit);

  /// Shared opener for the three M131b panels. Each seeds only what its own
  /// kind needs; everything else is the extrude session's defaults.
  void _openSketchFeature(String kind, PartFeature? edit) {
    if (_toggles3DOff(kind, edit)) return; // M210
    _openExtrudeCore();
    final s = extrudeSession;
    if (s == null) return;
    s.kind = kind;
    if (edit is SweepFeature) {
      s.editing = edit;
      s.sketchName = edit.sketchName;
      s.bodyName = edit.bodyName;
      s.output = edit.output;
      s.path = edit.path;
      s.orientation = edit.orientation;
      s.exprTaperSweep = edit.exprTaper;
      s.exprTwist = edit.exprTwist;
      s.profiles
        ..clear()
        ..addAll(
            [for (final x in edit.profiles) ProfileSel(x.ax, x.ay, x.area)]);
    } else if (edit is LoftFeature) {
      s.editing = edit;
      s.bodyName = edit.bodyName;
      s.output = edit.output;
      s.loftSolid = edit.solidOutput;
      s.loftRuled = edit.ruled;
      s.loftClosed = edit.closedLoop;
      s.loftMergeTangent = edit.mergeTangent;
      s.loftSketches
        ..clear()
        ..addAll(edit.sectionSketches);
      s.loftSections
        ..clear()
        ..addAll(
            [for (final x in edit.sections) ProfileSel(x.ax, x.ay, x.area)]);
    } else if (edit is CoilFeature) {
      s.editing = edit;
      s.sketchName = edit.sketchName;
      s.bodyName = edit.bodyName;
      s.output = edit.output;
      s.axPx = edit.axPx;
      s.axPy = edit.axPy;
      s.axDx = edit.axDx;
      s.axDy = edit.axDy;
      s.axisPicked = true;
      s.axisLabel = L.current.lblAxis;
      s.coilMethod = edit.method;
      s.exprRevolutions = edit.exprRevolutions;
      s.exprHeight = edit.exprHeight;
      s.exprPitch = edit.exprPitch;
      s.exprCoilTaper = edit.exprTaper;
      s.coilClockwise = edit.clockwise;
      s.coilCloseStart = edit.closeStart;
      s.coilCloseEnd = edit.closeEnd;
      s.profiles
        ..clear()
        ..addAll(
            [for (final x in edit.profiles) ProfileSel(x.ax, x.ay, x.area)]);
    }
    _updateExtrudePreview();
    notifyListeners();
  }

  /// Armed while the panel waits for a sweep PATH curve.
  bool pickingSweepPath = false;

  void beginPickSweepPath() {
    if (extrudeSession == null) return;
    pickingSweepPath = true;
    toast(L.current.msgTapCurveToSweep);
    notifyListeners();
  }

  void cancelPickSweepPath() {
    if (!pickingSweepPath) return;
    pickingSweepPath = false;
    notifyListeners();
  }

  /// A sketch curve was tapped as the sweep path. Stored as a fingerprint, not
  /// an index, so inserting geometry before it does not re-point the sweep.
  void sweepPathPicked(String sketchName, int geoIndex) {
    final s = extrudeSession;
    final p = currentPart;
    pickingSweepPath = false;
    if (s == null || p == null) {
      notifyListeners();
      return;
    }
    final cs = p.sketchByName(sketchName);
    if (cs == null || geoIndex < 0 || geoIndex >= cs.model.geometry.length) {
      toast(L.current.msgCurveGone);
      notifyListeners();
      return;
    }
    final pts = sketchCurve(cs.model.geometry[geoIndex]);
    if (pts.length < 2) {
      toast(L.current.msgCurveNoLength);
      notifyListeners();
      return;
    }
    var len = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      len += (pts[i + 1] - pts[i]).distance;
    }
    s.path = CurveSel(sketchName, geoIndex, pts.first.dx, pts.first.dy,
        pts.last.dx, pts.last.dy, len);
    _updateExtrudePreview();
    notifyListeners();
  }

  /// Armed while the panel collects LOFT sections.
  bool pickingLoftSections = false;

  void beginPickLoftSections() {
    if (extrudeSession == null) return;
    pickingLoftSections = true;
    toast(L.current.msgTapSectionsInOrder);
    notifyListeners();
  }

  void cancelPickLoftSections() {
    if (!pickingLoftSections) return;
    pickingLoftSections = false;
    notifyListeners();
  }

  /// Adds (or removes) a loft section. Order is pick order, which is the order
  /// the loft runs through them — so this is a list, not a set.
  void toggleLoftSection(String sketchName, ProfileSel sel) {
    final s = extrudeSession;
    if (s == null || !s.isLoft) return;
    for (var i = 0; i < s.loftSections.length; i++) {
      final e = s.loftSections[i];
      if (s.loftSketches[i] == sketchName &&
          (Offset(e.ax, e.ay) - Offset(sel.ax, sel.ay)).distance < 1e-6) {
        s.loftSections.removeAt(i);
        s.loftSketches.removeAt(i);
        _updateExtrudePreview();
        notifyListeners();
        return;
      }
    }
    s.loftSections.add(sel);
    s.loftSketches.add(sketchName);
    _updateExtrudePreview();
    notifyListeners();
  }

  /// Armed while the panel is waiting for an axis line to be tapped in 3D.
  bool pickingRevolveAxis = false;

  void beginPickRevolveAxis() {
    if (extrudeSession == null) return;
    pickingRevolveAxis = true;
    toast(L.current.msgTapAxisLine);
    notifyListeners();
  }

  void cancelPickRevolveAxis() {
    if (!pickingRevolveAxis) return;
    pickingRevolveAxis = false;
    notifyListeners();
  }

  /// An ORIGIN AXIS (x/y/z) was tapped while [pickingRevolveAxis].
  ///
  /// Inventor takes a work axis as a revolve axis, and revolving about Y is
  /// the commonest revolve there is — requiring a drawn construction line for
  /// it was pure friction.
  ///
  /// Inventor's rule still holds: the axis must be COPLANAR with the profile.
  /// An origin axis passes through the world origin, so it lies in the sketch
  /// plane exactly when the world origin is on that plane AND the axis
  /// direction has no component along the plane normal. Both are checked, and
  /// a non-coplanar axis is refused with the reason rather than silently
  /// projected — a projected axis would revolve about a line the user never
  /// chose.
  void revolveAxisPickedOrigin(String axisKey) {
    final s = extrudeSession;
    final p = currentPart;
    pickingRevolveAxis = false;
    if (s == null || p == null) {
      notifyListeners();
      return;
    }
    final dir = switch (axisKey) {
      'x' => const Vec3(1, 0, 0),
      'y' => const Vec3(0, 1, 0),
      'z' => const Vec3(0, 0, 1),
      _ => null,
    };
    final cs = s.sketchName == null ? null : p.sketchByName(s.sketchName!);
    if (dir == null || cs == null) {
      toast(L.current.msgPickAxisLine);
      notifyListeners();
      return;
    }
    final frame = sketchFrameOf(cs);
    // world origin on the plane?
    if ((Vec3.zero - frame.origin).dot(frame.n).abs() > 1e-7) {
      toast(L.current.msgAxisNotInSketchPlane);
      notifyListeners();
      return;
    }
    // direction parallel to the plane?
    if (dir.dot(frame.n).abs() > 1e-7) {
      toast(L.current.msgAxisNotInSketchPlane);
      notifyListeners();
      return;
    }
    final o = frame.toSketch(Vec3.zero);
    s.axPx = o.dx;
    s.axPy = o.dy;
    s.axDx = dir.dot(frame.u);
    s.axDy = dir.dot(frame.v);
    s.axisPicked = true;
    s.axisLabel = '${axisKey.toUpperCase()} Axis';
    _updateExtrudePreview();
    notifyListeners();
  }

  /// A sketch line was tapped while [pickingRevolveAxis]. The axis is stored
  /// as GEOMETRY (point + direction in sketch coordinates), not as a
  /// reference to this entity — the line may later be deleted or redrawn, and
  /// what the feature actually depends on is the axis it defined.
  void revolveAxisPicked(String sketchName, int geoIndex) {
    final s = extrudeSession;
    final p = currentPart;
    pickingRevolveAxis = false;
    if (s == null || p == null) {
      notifyListeners();
      return;
    }
    final cs = p.sketchByName(sketchName);
    if (cs == null || geoIndex < 0 || geoIndex >= cs.model.geometry.length) {
      toast(L.current.msgLineGone);
      notifyListeners();
      return;
    }
    final g = cs.model.geometry[geoIndex];
    if (g.type != Geo.line || g.data.length < 4) {
      toast(L.current.msgAxisMustBeStraight);
      notifyListeners();
      return;
    }
    final dx = g.data[2] - g.data[0], dy = g.data[3] - g.data[1];
    if (dx.abs() < 1e-9 && dy.abs() < 1e-9) {
      toast(L.current.msgLineNoLength);
      notifyListeners();
      return;
    }
    s.axPx = g.data[0];
    s.axPy = g.data[1];
    s.axDx = dx;
    s.axDy = dy;
    s.axisPicked = true;
    s.axisLabel = g.isCenterline
        ? L.current.lblCenterlineGeo
        : (g.isConstruction
            ? L.current.lblConstructionLineGeo
            : L.current.lblLineGeo);
    _updateExtrudePreview();
    notifyListeners();
  }

  /// M210 — pressing the button of the command that is ALREADY open closes it.
  ///
  /// "Same as in 2D: when a tool is selected like extrude, when i click again
  /// on the tool it should be deselected." The sketch tools have always
  /// toggled; the part ribbon's buttons only ever opened, so the highlight
  /// said "armed" and there was no way to disarm from the same place.
  ///
  /// Opening a command to EDIT an existing feature is never a toggle (the
  /// browser sends that, not the button), and switching from one command to
  /// another is not either — only the same kind, twice.
  bool _toggles3DOff(String kind, Object? edit) {
    if (edit != null) return false;
    // M212 — the pattern panel is a 3D command like the others: opening
    // Extrude while it is up closes it, and it never survives underneath.
    if (patternSession != null && patternSession!.editing == null) {
      cancelPattern();
    }
    final ex = extrudeSession;
    if (ex != null && ex.editing == null && ex.kind == kind) {
      cancelExtrude();
      return true;
    }
    final eg = edgeSession;
    if (eg != null && eg.editing == null && eg.kind == kind) {
      cancelEdgeFeature();
      return true;
    }
    return false;
  }

  void openExtrude([ExtrudeFeature? edit]) {
    if (_toggles3DOff('extrude', edit)) return;
    _openExtrudeCore(edit);
  }

  /// A 3D command takes the viewport back from an open sketch, and returns the
  /// name of the sketch it closed (M221).
  ///
  /// With a child sketch open, `Viewport2D` is laid over the whole viewport
  /// (main.dart) and there is no path from a tap on it to a profile, an edge or
  /// a face — it is the sketcher, and it knows nothing about them. So the panel
  /// came up over a surface that swallowed every pick: not one profile could be
  /// selected, which is half of the reported "I cant select the inner circle".
  /// [openChildSketch] has always done the mirror of this (it cancels an open
  /// extrude); only this direction was missing. Inventor finishes the sketch
  /// the same way when a part command starts.
  String? _leaveSketchForCommand() {
    final open = activeChild?.name;
    if (open != null) finishPartSketch();
    return open;
  }

  /// The opener without the toggle, for the panels that BUILD on the extrude
  /// session (revolve, sweep, loft, coil): they run their own toggle first and
  /// must not be closed by this one on the way in.
  void _openExtrudeCore([ExtrudeFeature? edit]) {
    final p = currentPart;
    if (p == null) return;
    if (p.childSketches.isEmpty) {
      toast(L.current.msgCreateSketchFirstExtrude);
      return;
    }
    cancelExtrude();
    cancelHole(); // M225 — one 3D panel at a time
    cancelCombine(); // M227 — likewise
    cancelSplit(); // M228 — likewise
    final wasOpen = _leaveSketchForCommand();
    final s = ExtrudeSession();
    if (edit != null) {
      s
        ..editing = edit
        ..sketchName = edit.sketchName
        ..direction = edit.direction
        ..exprA = edit.exprA
        ..exprB = edit.exprB
        ..exprTaper = edit.exprTaper
        ..bodyName = edit.bodyName
        ..iMate = edit.iMate
        ..matchShape = edit.matchShape
        // M256 — the feature's OWN Output and Extents.
        //
        // Extrude was the one opener that dropped them. Revolve has restored
        // `output` since M137 and sweep/loft/coil since M131b; here the
        // session kept its constructed defaults, so re-opening a Cut Through
        // All came up reading "Join, Distance" and OK turned the cut into a
        // join 5 mm long. The panel has to show what the feature IS — and
        // M256's suggestion, which reads `output` to decide whether to move
        // it, would otherwise have been reasoning about a default nobody
        // chose.
        ..output = edit.output
        ..extent = edit.extent
        ..extentFace = edit.extentFace;
      for (final x in edit.profiles) {
        s.profiles.add(ProfileSel(x.ax, x.ay, x.area));
      }
    } else {
      // The sketch the command was started FROM, if there was one: that is the
      // profile the user is looking at. Only with no sketch open does "the
      // newest one" remain the best guess.
      //
      // M257 — resolved BEFORE the target body, because it is what decides it.
      final cs = (wasOpen == null ? null : p.sketchByName(wasOpen)) ??
          p.childSketches.last;
      s.sketchName = cs.model.name;
      // Inventor: Join merges into an EXISTING body, so default the target to
      // one. Handing out a fresh "SolidN+1" here (as before M101) meant Join
      // never matched anything and silently behaved like New Solid unless the
      // user retyped the existing name by hand.
      final bodies = p.bodyNames;
      if (bodies.isEmpty) {
        s.output = 'new'; // nothing to join to yet: this is the base feature
        s.bodyName = 'Solid${p.solidN + 1}';
      } else {
        s.output = 'join';
        s.bodyName = bodies.last; // the newest, unless the sketch says better
        _retargetBodyForSketch(s);
      }
      final regs = sessionRegions(cs);
      if (regs.length == 1) {
        final ip = regionAnchor(regs.first);
        s.profiles.add(ProfileSel(ip.dx, ip.dy, regs.first.outer.area));
        s.autoPicked = true; // an explicit pick elsewhere replaces this
      }
    }
    extrudeSession = s;
    _updateExtrudePreview();
    notifyListeners();
  }

  /// Click ADDS a face to the extrusion, shift-click REMOVES it — so building
  /// up a multi-face profile never accidentally drops one you already had.
  void toggleSessionProfile(String sketchName, ProfileRegion r,
      {bool remove = false}) {
    final s = extrudeSession;
    if (s == null) return;
    if (s.sketchName != null && s.sketchName != sketchName) {
      if (s.autoPicked) {
        // only the convenience pre-selection was there — the user's own
        // pick decides which sketch this extrusion belongs to
        s.profiles.clear();
      } else if (s.profiles.isNotEmpty) {
        toast(L.current.msgProfilesSameSketch);
        return;
      }
    }
    s.autoPicked = false;
    s.sketchName = sketchName;
    // M257 — the profile decides which sketch this feature belongs to, and the
    // sketch decides which body. Applying the rule at open and not here would
    // be the half-intelligence that is worse than none: right until you pick a
    // profile, then quietly wrong.
    _retargetBodyForSketch(s);
    // M221 — the region's own anchor, not its outer loop's: for a ring the
    // loop's interior point is the middle of the hole, which is also the disc's
    // anchor, so "is this one already selected?" answered yes for the OTHER
    // region and the second of the two could never be picked.
    final ip = regionAnchor(r);
    // A selection made before this rule (or loaded from such a document) still
    // carries the old anchor, so compare through the region each one resolves
    // to rather than through the stored numbers.
    final cs = currentPart?.sketchByName(sketchName);
    final regions = cs == null ? const <ProfileRegion>[] : sessionRegions(cs);
    final i = s.profiles.indexWhere((x) {
      final m = regions.isEmpty ? null : regionForSel(regions, x);
      return m == null
          ? (Offset(x.ax, x.ay) - ip).distance < 1e-6
          : (regionAnchor(m) - ip).distance < 1e-6;
    });
    if (remove) {
      if (i >= 0) s.profiles.removeAt(i);
    } else if (i < 0) {
      s.profiles.add(ProfileSel(ip.dx, ip.dy, r.outer.area));
    }
    _updateExtrudePreview();
    notifyListeners();
  }

  void clearSessionProfiles() {
    final s = extrudeSession;
    if (s == null) return;
    s.profiles.clear();
    s.disposePreview();
    s.previewError = null;
    notifyListeners();
  }

  /// Granular dialog setters — every change re-renders the live preview.
  void setExtrude(
      {ExtrudeDirection? direction,
      String? exprA,
      String? exprB,
      String? exprTaper,
      String? bodyName,
      bool? iMate,
      bool? matchShape,
      String? output,
      FeatureExtent? extent,
      bool? full,
      int? orientation,
      String? exprSweepTaper,
      String? exprTwist,
      bool? loftRuled,
      bool? loftClosed,
      bool? loftMergeTangent,
      int? coilMethod,
      String? exprRevolutions,
      String? exprHeight,
      String? exprPitch,
      String? exprCoilTaper,
      bool? coilClockwise}) {
    final s = extrudeSession;
    if (s == null) return;
    if (direction != null) s.direction = direction;
    if (exprA != null) s.exprA = exprA;
    if (exprB != null) s.exprB = exprB;
    if (exprTaper != null) s.exprTaper = exprTaper;
    if (bodyName != null) s.bodyName = bodyName;
    if (iMate != null) s.iMate = iMate;
    if (matchShape != null) s.matchShape = matchShape;
    if (full != null) s.full = full;
    if (orientation != null) s.orientation = orientation;
    if (exprSweepTaper != null) s.exprTaperSweep = exprSweepTaper;
    if (exprTwist != null) s.exprTwist = exprTwist;
    if (loftRuled != null) s.loftRuled = loftRuled;
    if (loftClosed != null) s.loftClosed = loftClosed;
    if (loftMergeTangent != null) s.loftMergeTangent = loftMergeTangent;
    if (coilMethod != null) s.coilMethod = coilMethod;
    if (exprRevolutions != null) s.exprRevolutions = exprRevolutions;
    if (exprHeight != null) s.exprHeight = exprHeight;
    if (exprPitch != null) s.exprPitch = exprPitch;
    if (exprCoilTaper != null) s.exprCoilTaper = exprCoilTaper;
    if (coilClockwise != null) s.coilClockwise = coilClockwise;
    if (extent != null && extent != s.extent) {
      s.extent = extent;
      // Leaving "To" clears the face: keeping a stale termination face around
      // would silently reapply it if the user came back to To later.
      if (extent != FeatureExtent.toFace) s.extentFace = null;
    }
    if (output != null) {
      // M256 — touching the Output control at all ENDS the automatic one, even
      // when it names the boolean already in force: tapping Join on a feature
      // the suggestion has just moved to Cut is the clearest statement of
      // intent there is, and it must stick.
      s.outputLocked = true;
    }
    if (output != null && output != s.output) {
      s.output = output;
      final p = currentPart;
      if (p != null) {
        final bodies = p.bodyNames;
        if (output == 'join' && bodies.isNotEmpty) {
          // keep an explicit choice, otherwise target the newest body
          if (!bodies.contains(s.bodyName)) s.bodyName = bodies.last;
        } else if (output == 'new') {
          s.bodyName = p.peekSolidName(); // M96 — skips names already taken
        }
      }
    }
    _updateExtrudePreview();
    notifyListeners();
  }

  /// Parses the session values into a throwaway feature (also used for the
  (PartFeature?, String?) _sweepSessionFeature(ExtrudeSession s) {
    if (s.path == null) return (null, L.current.valSelectPathCurve);
    final taper = parseValueExpr(s.exprTaperSweep) ?? 0;
    final twist = parseValueExpr(s.exprTwist) ?? 0;
    if (twist.abs() > 1e-9) {
      // The kernel refuses a non-zero twist rather than producing an
      // untwisted solid; say so here instead of failing at the shim.
      return (null, L.current.valTwistUnsupported);
    }
    return (
      SweepFeature(
        name: s.editing?.name ?? '(preview)',
        bodyName: s.bodyName,
        sketchName: s.sketchName ?? '',
        profiles: [for (final x in s.profiles) ProfileSel(x.ax, x.ay, x.area)],
        path: s.path,
        orientation: s.orientation,
        taperDeg: taper,
        twistDeg: twist,
        exprTaper: s.exprTaperSweep,
        exprTwist: s.exprTwist,
        output: s.output,
      ),
      null
    );
  }

  (PartFeature?, String?) _loftSessionFeature(ExtrudeSession s) {
    if (s.loftSections.length < 2) {
      return (null, L.current.valSelectTwoSections);
    }
    return (
      LoftFeature(
        name: s.editing?.name ?? '(preview)',
        bodyName: s.bodyName,
        sectionSketches: List<String>.from(s.loftSketches),
        sections: [
          for (final x in s.loftSections) ProfileSel(x.ax, x.ay, x.area)
        ],
        solidOutput: s.loftSolid,
        ruled: s.loftRuled,
        closedLoop: s.loftClosed,
        mergeTangent: s.loftMergeTangent,
        output: s.output,
      ),
      null
    );
  }

  (PartFeature?, String?) _coilSessionFeature(ExtrudeSession s) {
    if (!s.axisPicked) return (null, L.current.valSelectAxis);
    final rev = parseValueExpr(s.exprRevolutions) ?? 0;
    final h = parseValueExpr(s.exprHeight) ?? 0;
    final pitch = parseValueExpr(s.exprPitch) ?? 0;
    // Validate the two values the CHOSEN method actually uses, so an unused
    // field left at nonsense does not block a perfectly good coil.
    switch (s.coilMethod) {
      case 1: // pitch and revolution
        if (!(pitch > 0)) return (null, L.current.valPitchPositive);
        if (!(rev > 0)) return (null, L.current.valRevolutionPositive);
        break;
      case 2: // pitch and height
        if (!(pitch > 0)) return (null, L.current.valPitchPositive);
        if (!(h > 0)) return (null, L.current.valHeightPositive);
        break;
      case 3: // spiral
        if (!(rev > 0)) return (null, L.current.valRevolutionPositive);
        break;
      default: // revolution and height
        if (!(rev > 0)) return (null, L.current.valRevolutionPositive);
        if (!(h > 0)) return (null, L.current.valHeightPositive);
    }
    return (
      CoilFeature(
        name: s.editing?.name ?? '(preview)',
        bodyName: s.bodyName,
        sketchName: s.sketchName ?? '',
        profiles: [for (final x in s.profiles) ProfileSel(x.ax, x.ay, x.area)],
        axPx: s.axPx,
        axPy: s.axPy,
        axDx: s.axDx,
        axDy: s.axDy,
        method: s.coilMethod,
        revolutions: rev,
        height: h,
        pitch: pitch,
        taperDeg: parseValueExpr(s.exprCoilTaper) ?? 0,
        exprRevolutions: s.exprRevolutions,
        exprHeight: s.exprHeight,
        exprPitch: s.exprPitch,
        exprTaper: s.exprCoilTaper,
        clockwise: s.coilClockwise,
        closeStart: s.coilCloseStart,
        closeEnd: s.coilCloseEnd,
        output: s.output,
      ),
      null
    );
  }

  /// Revolve twin of [_sessionFeature]. Angle A is the sweep unless Full is
  /// set; Angle B only matters for Asymmetric, exactly as Distance B does.
  (PartFeature?, String?) _revolveSessionFeature(ExtrudeSession s) {
    // M144 — all three extents are resolved by resolveRevolveSweep now;
    // occt_revolve_hits_face answers the picked-face question.
    if (s.extent == FeatureExtent.toFace && s.extentFace == null) {
      return (null, L.current.msgSelectTerminateFace);
    }
    // axisPicked is the ONLY gate. Testing the direction instead let the
    // default (0, 1) through — a non-degenerate vector — so a revolve could
    // be committed about a Y axis the user never chose.
    if (!s.axisPicked) {
      return (null, L.current.valSelectRevolveAxis);
    }
    if (s.axDx == 0 && s.axDy == 0) {
      return (null, L.current.valAxisNoDirection);
    }
    var a = 360.0, b = 0.0;
    if (!s.full) {
      final pa = parseValueExpr(s.exprA);
      if (pa == null || !(pa > 0) || pa > 360) {
        return (null, L.current.valAngleA0to360);
      }
      a = pa;
      if (s.direction == ExtrudeDirection.asymmetric) {
        final pb = parseValueExpr(s.exprB);
        if (pb == null || !(pb > 0)) return (null, L.current.valAngleBPositive);
        b = pb;
      }
      if (a + b > 360.0 + 1e-9) {
        return (null, L.current.valAngleABMax360);
      }
    }
    return (
      RevolveFeature(
        name: s.editing?.name ?? '(preview)',
        bodyName: s.bodyName,
        sketchName: s.sketchName ?? '',
        profiles: [for (final x in s.profiles) ProfileSel(x.ax, x.ay, x.area)],
        axPx: s.axPx,
        axPy: s.axPy,
        axDx: s.axDx,
        axDy: s.axDy,
        direction: s.direction,
        angleA: a,
        angleB: b,
        exprA: s.exprA,
        exprB: s.exprB,
        full: s.full,
        extent: s.extent,
        extentFace: s.extentFace,
        output: s.output,
      ),
      null
    );
  }

  /// preview). Returns null + a toastable reason when a value is invalid.
  (PartFeature?, String?) _sessionFeature(ExtrudeSession s) {
    if (s.isRevolve) return _revolveSessionFeature(s);
    if (s.isSweep) return _sweepSessionFeature(s);
    if (s.isLoft) return _loftSessionFeature(s);
    if (s.isCoil) return _coilSessionFeature(s);
    final usesDistance = s.extent == FeatureExtent.distance;
    final a = parseValueExpr(s.exprA) ?? 0.0;
    // Only a plain Distance is driven by the typed value; To Next / To /
    // Through All resolve against the model, so an empty or nonsense field
    // must not block them.
    if (usesDistance && !(a > 0)) return (null, L.current.valDistanceAPositiveShort);
    var b = 0.0;
    if (usesDistance && s.direction == ExtrudeDirection.asymmetric) {
      final pb = parseValueExpr(s.exprB);
      if (pb == null || !(pb > 0)) return (null, L.current.valDistanceBPositiveShort);
      b = pb;
    }
    final t = parseValueExpr(s.exprTaper);
    if (t == null || t.abs() >= 90) {
      return (null, L.current.valTaperRange);
    }
    final f = ExtrudeFeature(
      name: s.editing?.name ?? '(preview)',
      bodyName: s.bodyName,
      sketchName: s.sketchName ?? '',
      profiles: [for (final x in s.profiles) ProfileSel(x.ax, x.ay, x.area)],
      direction: s.direction,
      distanceA: a,
      distanceB: b,
      taperDeg: t,
      exprA: s.exprA,
      exprB: s.exprB,
      exprTaper: s.exprTaper,
      iMate: s.iMate,
      matchShape: s.matchShape,
      extent: s.extent,
      extentFace: s.extentFace,
      output: s.output,
    );
    return (f, null);
  }

  /// The existing body a boolean would act on, and its accumulated solid, for
  /// the current session — the last committed body for a NEW feature (matching
  /// [applyExtrude]'s "adopt the last body"), or the accumulation strictly
  /// before an EDITED feature. Returns (null, null) when there is nothing to
  /// combine with (no prior solid), so the base feature previews as a plain
  /// prism. Never disposes anything: the returned solid stays owned by its
  /// feature (a boolean makes a NEW solid without consuming its inputs).
  (KernelSolid?, String?) _extrudeBooleanTarget(ExtrudeSession s) {
    final p = currentPart;
    if (p == null) return (null, null);
    if (s.editing != null) {
      final body = s.editing!.bodyName;
      return (bodyBaseBefore(p, body, s.editing!), body);
    }
    // M101 — HONOUR THE CHOSEN TARGET BODY.
    //
    // This used to go straight to lastSolidFeature: whatever body was made
    // most recently. So picking Solid1 set s.bodyName correctly and the COMMIT
    // used it (the log shows "extrude created Extrusion3 (Solid1)"), but the
    // preview kept combining against Solid2 — "it always shows the preview of
    // Solid2 + extrusion even after I selected Solid1". The dropdown never
    // exposed this because it was the last body anyway; picking made it
    // visible.
    final want = s.bodyName;
    if (want != null && want.isNotEmpty) {
      final base = currentBodySolid(p, want);
      if (base != null) return (base, want);
    }
    final lf = lastSolidFeature(p);
    if (lf == null) return (null, null);
    return (currentBodySolid(p, lf.bodyName), lf.bodyName);
  }

  /// True when a Cut/Intersect could act on an existing body — the dialog dims
  /// those options otherwise (the base feature has nothing to cut from).
  bool get extrudeHasBooleanTarget {
    final s = extrudeSession;
    if (s == null) return false;
    final (base, _) = _extrudeBooleanTarget(s);
    return base != null;
  }

  /// M257 — point the session at the body its sketch was drawn ON.
  ///
  /// The target defaulted to the NEWEST body, which is right whenever there is
  /// one body and a coin flip whenever there are several. The M253 bundle has
  /// what that costs, twice in one session:
  ///
  ///     notice: Zielkörper wählen — in 3D oder im Browser antippen.
  ///     (preview) body=Solid1 op=cut
  ///     kernel: cut(a: vol=15557.2693, ...) removed NOTHING
  ///     (preview) body=Solid3 op=cut
  ///     extrude: target body picked: Solid3
  ///
  /// The sketch was on a face of Solid3 the whole time. Nothing was asking it.
  ///
  /// It also makes M256 correct more often, not just faster: a boolean aimed
  /// at the wrong body reads an overlap against the wrong material, so the
  /// Output it suggests is an answer to a question nobody asked.
  void _retargetBodyForSketch(ExtrudeSession s) {
    // 'new' has no target to be wrong about — it is naming a body, not
    // choosing one.
    if (s.bodyIsTheirs || s.output == 'new') return;
    final p = currentPart;
    final name = s.sketchName;
    if (p == null || name == null) return;
    final cs = p.sketchByName(name);
    if (cs == null) return;
    final owner = bodyOfFaceSketch(p, cs);
    if (owner == null || owner == s.bodyName) return;
    Log.i(
        'extrude',
        '${s.kind}: target body ${s.bodyName} -> $owner, '
            'the sketch is drawn on its face');
    s.bodyName = owner;
  }

  /// Guard: the Output suggestion rebuilds the preview once at the boolean it
  /// chose, and that rebuild must not suggest again. One switch per change —
  /// without this, a fake or a kernel whose two booleans disagree could sit
  /// here flipping Join and Cut forever.
  bool _outputSwitching = false;

  /// The fraction of [tool] that lies INSIDE [base], read off the boolean that
  /// has already been run — so the suggestion costs no kernel work at all:
  ///
  ///     join:  |a ∪ b| = |a| + |b| − |a ∩ b|   ⇒  |a ∩ b| = |a| + |b| − |a ∪ b|
  ///     cut:   |a \ b| = |a| − |a ∩ b|         ⇒  |a ∩ b| = |a| − |a \ b|
  ///
  /// Doing it any other way means a third boolean per keystroke on a body the
  /// user is already waiting for; this way the answer is arithmetic on three
  /// numbers the preview computed anyway.
  ///
  /// Null when the numbers cannot answer: a tool with no volume, a boolean
  /// that produced something whose volume is not a number.
  static double? _insideFraction(
      String output, KernelSolid base, KernelSolid tool, KernelSolid combined) {
    final vb = base.volume, vt = tool.volume, vc = combined.volume;
    if (!(vt > 1e-9) || !vb.isFinite || !vc.isFinite) return null;
    final double overlap;
    if (output == 'join') {
      overlap = vb + vt - vc;
    } else if (output == 'cut') {
      overlap = vb - vc;
    } else {
      return null; // intersect and new take no part — see suggestedOutput
    }
    final frac = overlap / vt;
    if (!frac.isFinite) return null;
    // Clamped by hand rather than through num.clamp, whose static type is num
    // and not double. A boolean that came back a hair heavier than its inputs
    // is rounding, not a reading worth acting on the far side of.
    if (frac < 0.0) return 0.0;
    if (frac > 1.0) return 1.0;
    return frac;
  }

  /// [suggestedOutput] against the live session, or null to leave it alone.
  ///
  /// A switch is LOGGED, with the reading behind it. This is a control moving
  /// on its own, and the next report that says "it went to Cut and I did not
  /// want it" has to be answerable from the bundle rather than by guessing at
  /// a fraction nobody can see.
  String? _suggestOutputFor(ExtrudeSession s, KernelSolid base,
      KernelSolid tool, KernelSolid combined) {
    if (s.outputIsTheirs || _outputSwitching) return null;
    final inside = _insideFraction(s.output, base, tool, combined);
    if (inside == null) return null;
    final want = suggestedOutput(s.output, inside);
    if (want != null) {
      Log.i(
          'extrude',
          '${s.kind}: output ${s.output} -> $want, '
              '${(inside * 100).round()}% of the tool lies inside the body');
    }
    return want;
  }

  void _updateExtrudePreview() {
    final s = extrudeSession;
    final p = currentPart;
    if (s == null || p == null) return;
    s.disposePreview();
    s.previewError = null;
    if (s.profiles.isEmpty || s.sketchName == null) return;
    if (!partKernel.available) {
      s.previewError = 'no 3D kernel linked';
      return;
    }
    final (f, err) = _sessionFeature(s);
    if (f == null) {
      s.previewError = err;
      return;
    }
    // The target body is resolved FIRST now: M132's extents resolve against
    // it, so the prism cannot be built without it. It is also what step 2
    // combines against, so this is one lookup, not two.
    final (base, bodyName) = _extrudeBooleanTarget(s);
    // 1. build this feature's own prism (the throwaway feature owns it)
    if (!recomputeFeature(p, f, partKernel, base: base)) {
      s.previewError = f.computeError;
      return;
    }
    // 2. for a boolean output with an existing target body, show the ACTUAL
    //    combined result (join/cut/intersect) and mark the body it stands in
    //    for; otherwise the standalone prism is the preview. This is what
    //    makes the joined/cut/intersected shape visible while the dialog is
    //    open, not only after OK.
    if (s.output != 'new' && base != null && f.solid != null) {
      final combined = combineSolids(partKernel, s.output, base, f.solid!);
      if (combined != null) {
        // M256 — let the geometry choose between Join and Cut, unless the
        // user already has. The switch rebuilds the preview ONCE at the new
        // boolean, because the picture has to be the answer, not the question.
        final want = _suggestOutputFor(s, base, f.solid!, combined);
        if (want != null) {
          s.output = want;
          f.disposeSolid();
          combined.dispose();
          _outputSwitching = true;
          try {
            _updateExtrudePreview();
          } finally {
            _outputSwitching = false;
          }
          return;
        }
        f.disposeSolid(); // drop the throwaway prism
        s.preview = combined;
        s.previewReplacesBody = bodyName;
        return;
      }
      // boolean failed (e.g. a cut that removes everything, or disjoint
      // intersect) — say so and fall back to showing the prism alone.
      s.previewError = partKernel.lastError;
    }
    s.preview = f.solid;
    s.previewReplacesBody = null;
    f.solid = null; // ownership moved to the session
  }

  /// OK / "+" of the Extrusion panel. With [keepOpen] the feature commits
  /// and the panel resets for the next one (Inventor's Apply).
  Future<bool> applyExtrude({bool keepOpen = false}) async {
    final s = extrudeSession;
    final p = currentPart;
    if (s == null || p == null) return false;
    if (s.profiles.isEmpty || s.sketchName == null) {
      toast(L.current.msgPickProfile);
      return false;
    }
    final (parsed, err) = _sessionFeature(s);
    if (parsed == null) {
      toast(err!);
      return false;
    }
    PartFeature f;
    final editing = s.editing;
    if (s.kind != 'extrude') {
      // Only extrude mutates in place. Revolve, sweep, loft and coil REPLACE
      // the feature in the timeline (the same move applyEdgeFeature makes) —
      // mutating each in place would mean four more copies of every field
      // assignment below, for no gain.
      f = parsed;
      if (editing != null) {
        f.name = editing.name;
        f.seq = editing.seq;
        f.bodyName = editing.bodyName;
        final i = p.features.indexOf(editing);
        if (i >= 0) {
          editing.disposeSolid();
          p.features[i] = f;
        }
      } else {
        f.name = p.nextFeatureName(switch (s.kind) {
          'revolve' => 'Revolution',
          'sweep' => 'Sweep',
          'loft' => 'Loft',
          'coil' => 'Coil',
          _ => 'Feature',
        });
        if (f.bodyName.trim().isEmpty) {
          final lastBody =
              p.features.isEmpty ? null : p.features.last.bodyName;
          f.bodyName = (f.output != 'new' && lastBody != null)
              ? lastBody
              : p.nextSolidName();
        } else {
          // M155 — the revolve/sweep/loft/coil dialogs set the body name
          // themselves (from peekSolidName, which does NOT consume). Without
          // this the counter stayed behind its own document: a part with
          // Solid1..Solid3 saved `solidN: 1`, and the next body after a
          // re-open collided with an existing one.
          p.claimBodyName(f.bodyName);
        }
      }
    } else if (editing is ExtrudeFeature && parsed is ExtrudeFeature) {
      f = editing
        ..direction = parsed.direction
        ..distanceA = parsed.distanceA
        ..distanceB = parsed.distanceB
        ..taperDeg = parsed.taperDeg
        ..exprA = parsed.exprA
        ..exprB = parsed.exprB
        ..exprTaper = parsed.exprTaper
        ..bodyName = parsed.bodyName
        ..iMate = parsed.iMate
        ..matchShape = parsed.matchShape
        ..extent = parsed.extent
        ..extentFace = parsed.extentFace
        ..output = parsed.output;
      (f as ExtrudeFeature).profiles
        ..clear()
        ..addAll(parsed.profiles);
    } else {
      f = parsed;
      f.name = p.nextFeatureName();
      if (f.bodyName.trim().isEmpty) {
        // Inventor: a boolean output (Join/Cut/Intersect) acts on the
        // existing body — adopt the last feature's body name; New Solid (or
        // the base feature, with no body yet) gets a fresh Solid name.
        final lastBody = p.features.isEmpty ? null : p.features.last.bodyName;
        f.bodyName = (f.output != 'new' && lastBody != null)
            ? lastBody
            : p.nextSolidName();
      } else {
        p.claimBodyName(f.bodyName); // M155 — one implementation, not two
      }
    }
    // M132 — hand the boolean target in, or a To Next/Through All feature
    // would fail here on commit and only succeed in the fold that follows.
    final (commitBase, _) = _extrudeBooleanTarget(s);
    final ok = recomputeFeature(p, f, partKernel, base: commitBase);
    if (!ok) {
      if (partKernel.available || f.computeError != 'no 3D kernel linked') {
        toast(L.current.msgFeatureError(
            f.name, f.computeError ?? partKernel.lastError));
      }
      if (!partKernel.available) {
        // parameters are stored honestly; the solid waits for the device
        toast(L.current.msgNoKernelFeatureStored);
      } else if (s.editing == null) {
        return false; // a NEW feature that cannot compute is not created
      }
    }
    if (s.editing == null &&
        !(s.kind != 'extrude' && p.features.contains(f))) {
      final firstConsumption = firstConsumerOf(p, f.sketchName) == null;
      f.seq = p.nextSeq(); // M91 — bottom of the timeline
      // A feature added while the marker is parked mid-tree belongs ABOVE it,
      // exactly like Inventor: the marker moves down to admit the new work.
      // `appendFeature` places it; writing the row count here afterwards UNDID
      // that and pinned the marker to today's length, so the next sketch was
      // appended below it and came out rolled back.
      p.appendFeature(f); // keeps End of Part past what was just created
      applyEndOfPart(p);
      if (firstConsumption) {
        // Inventor: creating the feature CONSUMES the sketch — it nests
        // under the feature in the browser and its visibility turns off.
        final cs = p.sketchByName(f.sketchName);
        if (cs != null) cs.visible = false;
      }
    }
    if (partKernel.available) {
      // M182 — projections only after a SUCCESSFUL recompute (see openPart).
      if (recomputeAllFeatures(p, partKernel)) {
        _syncSolidProjections(p); // fold Inventor join chains
      }
    }
    p.dirty = true;
    s.disposePreview();
    Log.i(
        'part',
        '${s.kind} ${s.editing == null ? "created" : "edited"} '
            '${f.name} (${f.bodyName}) '
            '${f is ExtrudeFeature ? "h=${f.distanceA}/${f.distanceB} "
                "taper=${f.taperDeg}" : f is RevolveFeature ? "ang=${f.sweepDeg} "
                "axis=(${f.axPx},${f.axPy})->(${f.axDx},${f.axDy})" : ""} '
            'ok=$ok');
    if (keepOpen) {
      extrudeSession = ExtrudeSession()
        ..kind = s.kind
        ..orientation = s.orientation
        ..coilMethod = s.coilMethod
        ..exprRevolutions = s.exprRevolutions
        ..exprHeight = s.exprHeight
        ..exprPitch = s.exprPitch
        ..coilClockwise = s.coilClockwise
        ..full = s.full
        ..axPx = s.axPx
        ..axPy = s.axPy
        ..axDx = s.axDx
        ..axDy = s.axDy
        ..axisPicked = s.axisPicked
        ..axisLabel = s.axisLabel
        ..sketchName = s.sketchName
        ..bodyName = 'Solid${p.solidN + 1}';
    } else {
      extrudeSession = null;
      _regionCache.clear();
    }
    if (curTab != null) await savePart(curTab!);
    notifyListeners();
    return ok;
  }

  void cancelExtrude() {
    extrudeSession?.disposePreview();
    extrudeSession = null;
    _regionCache.clear();
    // M133 — the dialog owns these arm-flags. Closing it while a pick is
    // armed would leave the viewport swallowing taps with no visible reason
    // and no row left to cancel from.
    pickingExtentFace = false;
    pickingBody = false;
    pickingSweepPath = false;
    pickingLoftSections = false;
    pickingRevolveAxis = false;
    hoverBody = null;
    // M210 — and SAY SO. Every sibling cancel notifies; this one did not, so
    // the only caller that repainted was Esc (escape3D notifies for it). The
    // panel's own ✕ and Cancel changed the state and left the panel on
    // screen, which is exactly "the cross and the cancel button in the dialog
    // dont work".
    notifyListeners();
  }

  /// M218 — true while ANY 3D command owns the next pick in the viewport.
  ///
  /// The long-press context menu asks this before it opens: a press during a
  /// plane pick, a profile pick, an edge / face / work-geometry pick or a
  /// pattern selector belongs to THAT command, and a menu on top of it is a
  /// trap rather than a shortcut.
  ///
  /// One predicate here rather than a dozen flags at the call site, for the
  /// same reason [escape3D] lives here: the list of 3D modes is knowledge
  /// this class already has to keep straight, and a widget that copied it
  /// would go stale the first time a command was added.
  bool get picking3D =>
      pickPlane ||
      extrudeSession != null ||
      edgeSession != null ||
      patternSession != null ||
      workPlaneArm != null ||
      pickingEdges ||
      pickingFaces ||
      pickingExtentFace ||
      pickingBody ||
      pickingSweepPath ||
      pickingLoftSections ||
      pickingRevolveAxis ||
      pickWorkGeometry;

  /// Esc in the 3D viewport: session first, then an armed plane pick.
  void escape3D() {
    // Innermost mode first: Esc during a pick backs OUT of the pick, it does
    // not throw the whole dialog away. Anything else loses the profiles and
    // settings the user just entered.
    if (patternSession != null && patternSession!.active != PatternField.none) {
      // M212 — a pattern selector is a PICK, and Esc during a pick backs out
      // of the pick, not out of the panel that owns it.
      patternSession!.active = PatternField.none;
      notifyListeners();
    } else if (patternSession != null) {
      cancelPattern();
    } else if (holeSession != null) {
      // M225 — the hole panel owns its point picking, so one Esc closes both.
      cancelHole();
    } else if (combineSession != null) {
      cancelCombine(); // M227 — same shape
    } else if (splitSession != null) {
      cancelSplit(); // M228 — same shape, and it puts the origin planes back
    } else if (pickingEdges && edgeSession == null) {
      cancelPickEdges();
    } else if (edgeSession != null) {
      // The edge pick belongs TO the fillet panel, so Esc closes both at
      // once — cancelling only the pick would leave a panel that can no
      // longer be given edges.
      cancelEdgeFeature();
    } else if (pickingExtentFace) {
      cancelPickExtentFace();
    } else if (pickingBody) {
      cancelPickBody();
    } else if (extrudeSession != null) {
      cancelExtrude(); // notifies for itself now (M210)
    } else if (pickWorkGeometry) {
      // M260 — Esc had no branch for the work-feature commands at all, so an
      // armed Axis, Point or (now) Plane could only be put down by tapping
      // its ribbon entry again. Ahead of [pickPlane] because the two are
      // never both set and this one is the newer arming.
      cancelWorkFeature();
    } else if (_pastePlaneArmed) {
      // M345 — an armed paste is put down before the plain plane pick, for the
      // same reason the work-feature branch above sits ahead of it: it is the
      // newer arming, and it owns the pick that is running.
      cancelPastePlanePick();
    } else if (pickPlane) {
      cancelPlanePick();
    } else if (selectedBody != null) {
      // Nothing is running: Esc then means "deselect", the same way it clears
      // a selected component in an assembly.
      selectBody(null);
    }
  }

  /// M84 — rename a feature from the browser context menu. Names are a
  /// DISPLAY label: features are referenced by object identity everywhere
  /// (recompute, consumedByJoin, the extrude session), so nothing has to be
  /// remapped. A duplicate or empty name is refused rather than silently
  /// producing two identical browser rows.
  bool renameFeature(PartFeature f, String name) {
    final p = currentPart;
    final n = name.trim();
    if (p == null || n.isEmpty || n == f.name) return false;
    if (p.features.any((o) => !identical(o, f) && o.name == n)) {
      message = L.current.valFeatureNameTaken(n);
      notifyListeners();
      return false;
    }
    f.name = n;
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
    return true;
  }

  // ---- M182: PART-level undo for destructive operations ----------------
  //
  // The 2D sketches have had an undo journal since M39; the PART had none, so
  // deleting a body/feature/sketch/"everything below EOP" was permanent — and
  // when a broken recompute made the user delete the broken pieces, the data
  // was gone for good. The part journal is deliberately small: it snapshots
  // only the DESTRUCTIVE operations (which can lose data), not every edit.
  final List<PartSnap> _partUndo = [];
  final List<PartSnap> _partRedo = [];

  // M240 — a PART has to be open, not just a stack that is not empty.
  //
  // [undoPart] has always required `currentPart != null` and toasts "nothing
  // to undo" without one; these getters did not, so the quick-tool bar lit
  // Undo from the stack alone. With only two document kinds that never showed:
  // the stack is only ever filled from a part, and leaving one to a SKETCH
  // takes the `app.current != null` branch instead. An ASSEMBLY is neither, so
  // it read the part stack — and opening one after editing a part offered a
  // bright Undo button whose whole behaviour was a toast.
  bool get canUndoPart => currentPart != null && _partUndo.isNotEmpty;
  bool get canRedoPart => currentPart != null && _partRedo.isNotEmpty;

  PartSnap _takePartSnap(PartModel p) => PartSnap(
        p.toJson(),
        [for (final cs in p.childSketches) cs.model.name],
        [for (final cs in p.childSketches) cs.model.captureSnap()],
      );

  /// Records the current part state before a destructive operation. Call
  /// BEFORE mutating. Identical consecutive states are collapsed.
  void _partCheckpoint(PartModel p) {
    final s = _takePartSnap(p);
    if (_partUndo.isNotEmpty && _samePartSnap(_partUndo.last, s)) return;
    _partUndo.add(s);
    _partRedo.clear(); // a new edit forks history
  }

  bool _samePartSnap(PartSnap a, PartSnap b) {
    if (a.sketchNames.length != b.sketchNames.length) return false;
    for (var i = 0; i < a.sketchNames.length; i++) {
      if (a.sketchNames[i] != b.sketchNames[i]) return false;
    }
    // The part JSON is the same map shape the file uses (numbers, strings,
    // bools, lists, maps) — a canonical string comparison is exact and needs
    // no extra dependency. Keys are written in a fixed order by toJson, so
    // jsonEncode is deterministic here.
    return jsonEncode(a.partJson) == jsonEncode(b.partJson);
  }

  /// Ctrl+Z in a part: restores the last pre-destructive state.
  Future<void> undoPart() async {
    final p = currentPart;
    if (p == null || _partUndo.isEmpty) {
      toast(L.current.msgNothingToUndo);
      return;
    }
    _partRedo.add(_partUndo.removeLast());
    await _restorePartSnap(p, _partRedo.last);
    toast(L.current.msgUndone);
  }

  /// Ctrl+Shift+Z in a part: re-applies the last undone destructive op.
  Future<void> redoPart() async {
    final p = currentPart;
    if (p == null || _partRedo.isEmpty) {
      toast(L.current.msgNothingToRedo);
      return;
    }
    final s = _partRedo.removeLast();
    _partUndo.add(s);
    await _restorePartSnap(p, s);
    toast(L.current.msgRedone);
  }

  /// Rebuilds [p] from a snapshot: features, counters, End of Part, work
  /// planes, camera, origin visibility and every child sketch (geometry +
  /// constraints + sidecars, exactly). Then recomputes and saves.
  Future<void> _restorePartSnap(PartModel p, PartSnap snap) async {
    // 0. In-flight 3D sessions hold references into the model that is about
    //    to be replaced wholesale — cancel them first, exactly like the 2D
    //    undo cancels every in-flight pick before restoring.
    // M230 — every 3D session, not the three that happened to be listed. The
    // comment above has been right since M182; the list under it went stale
    // four commands ago.
    cancel3DCommands();
    cancelPlanePick();
    pickingSweepPath = false;
    pickingLoftSections = false;
    pickingRevolveAxis = false;
    hoverBody = null;
    // 1. Rebuild the child sketches to match the snapshot. Keep the ones that
    //    survive, recreate the deleted ones — with their plane/frame/faceRef
    //    metadata, exactly like the open path (partJson['sketches']).
    final meta = <String, Map>{};
    for (final e in (snap.partJson['sketches'] as List? ?? const [])) {
      final m = e as Map;
      meta[m['name'] as String] = m;
    }
    final byName = {for (final cs in p.childSketches) cs.model.name: cs};
    final want = <ChildSketch>[];
    for (var i = 0; i < snap.sketchNames.length; i++) {
      final name = snap.sketchNames[i];
      final snap2 = snap.sketchSnaps[i];
      final m = meta[name] ?? const {};
      final cs = byName[name] ??
          ChildSketch(
              SketchModel(name),
              m['plane'] as String? ?? 'xy',
              PlaneFrame.fromFrameJson(m['frame'] as List?),
              true, // real visibility is applied below from the JSON
              m['shared'] as bool? ?? false,
              (m['seq'] as num?)?.toInt() ?? 0,
              m['faceRef'] is Map
                  ? SketchFaceSel.fromJson(
                      (m['faceRef'] as Map).cast<String, dynamic>())
                  : null);
      cs.model.applySnap(snap2);
      want.add(cs);
      byName[name] = cs;
    }
    p.childSketches
      ..clear()
      ..addAll(want);
    // 2. The part-level state (features, counters, EOP, planes, camera).
    //    loadJson ADDS to the lists, so the current contents must go first.
    for (final f in p.features) {
      f.disposeSolid();
    }
    p.features.clear();
    p.workPlanes.clear();
    p.loadJson(snap.partJson);
    // 2b. Restore per-sketch visibility the way the open path does: stored
    //     value, else the consumed default (a consumed sketch starts hidden).
    for (final cs in p.childSketches) {
      final m = meta[cs.model.name];
      if (m != null && m.containsKey('vis')) {
        cs.visible = m['vis'] as bool? ?? true;
      } else {
        cs.visible = !(firstConsumerOf(p, cs.model.name) != null);
      }
    }
    // 3. Push every restored sketch's geometry into its engine and reset the
    //    sketch's own journal so the restored state is its new baseline.
    for (final cs in p.childSketches) {
      _rebuildEngine(cs.model, cs.model.geometry);
      cs.model.resetHistory();
    }
    if (activeChild != null &&
        !p.childSketches.any((cs) => cs.model == activeChild)) {
      activeChild = null;
    }
    p.dirty = true;
    if (curTab != null) {
      if (partKernel.available) {
        if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
      }
      savePart(curTab!);
    }
    Log.i('part',
        'undo/redo restored "${p.name}": sketches=${p.childSketches.length} '
            'features=${p.features.length}');
    notifyListeners();
  }

  void toggleFeatureVisible(PartFeature f) {
    f.visible = !f.visible;
    currentPart?.dirty = true;
    notifyListeners();
  }

  /// Toggle a whole solid body's visibility (Inventor's Solid Bodies folder
  /// eye): flip every feature that carries that bodyName to a single new
  /// state — visible if any is currently hidden, else hidden.
  void toggleBodyVisible(PartModel part, String bodyName) {
    final feats = part.features.where((f) => f.bodyName == bodyName).toList();
    if (feats.isEmpty) return;
    final show = !feats.any((f) => f.visible);
    for (final f in feats) {
      f.visible = show;
    }
    part.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  Future<void> deleteFeature(PartFeature f) async {
    final p = currentPart;
    if (p == null) return;
    _partCheckpoint(p); // M182 — deleting a feature must be undoable
    // M212 — a pattern that copies this feature loses its input. The pattern
    // survives and reports it honestly at the next rebuild ("the patterned
    // feature X is not available any more"), but the message belongs HERE
    // too: the moment of the deletion is when it can still be undone.
    final orphaned = [
      for (final g in p.features)
        if (g is PatternFeature && g.sources.contains(f.name)) g.name
    ];
    f.disposeSolid();
    p.features.remove(f);
    if (orphaned.isNotEmpty) {
      toast(L.current.msgPatternedByBroken(
          f.name, orphaned.join(', '), orphaned.length));
    }
    Log.i('part', 'feature "${f.name}" deleted from "${p.name}"');
    p.dirty = true;
    if (curTab != null) {
      if (partKernel.available) {
        if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
      }
      await savePart(curTab!);
    }
    notifyListeners();
  }

  // ---- child-sketch persistence: SAME sidecar formats as the top-level
  // sketches, against a per-part directory. The top-level save/load path is
  // deliberately untouched (battle-tested); keep the formats in sync.
  Future<void> _saveSketchIn(Directory dir, SketchModel s) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final base = '${dir.path}/${s.name}';
    s.engine.saveDxf('$base.dxf');
    try {
      File('$base.cons.json')
          .writeAsStringSync(encodeConstraints(s.constraints));
      File('$base.params.json')
          .writeAsStringSync(encodeUserParams(s.userParams));
      File('$base.texts.json').writeAsStringSync(encodeTexts(s.texts));
      File('$base.images.json').writeAsStringSync(encodeImages(s.images));
      final spl = <String, int>{}, sty = <String, int>{};
      final prj = <String, dynamic>{};
      for (var i = 0; i < s.geometry.length; i++) {
        final g = s.geometry[i];
        if (g.spline != Geo.straight) spl['$i'] = g.spline;
        if (g.style != Geo.styleNormal) sty['$i'] = g.style;
        if (g.isProjection) {
          prj['$i'] = g.projSeg >= 0 ? [g.proj, g.projSeg] : g.proj;
        }
      }
      File('$base.splines.json').writeAsStringSync(jsonEncode(spl));
      File('$base.styles.json').writeAsStringSync(jsonEncode(sty));
      File('$base.proj.json').writeAsStringSync(jsonEncode(prj));
      final grs = <String, dynamic>{};
      for (var i = 0; i < s.geometry.length; i++) {
        final gp = gearParams(s.geometry[i]);
        if (gp != null) grs['$i'] = {'d': s.geometry[i].data, 'p': gp.toJson()};
      }
      File('$base.gears.json').writeAsStringSync(jsonEncode(grs));
      File('$base.layers.json').writeAsStringSync(jsonEncode({
        'version': 3,
        'layers': s.layers,
        'hidden': s.hiddenLayers.toList(),
        'locked': s.lockedLayers.toList(),
        'eos': s.eosAfter,
      }));
    } catch (e) {
      Log.w('part', 'child sidecar write failed: $e');
    }
  }

  /// Loads a sketch from [dir]. [name] is what the model is CALLED; [base] is
  /// the file base it is stored under, which differs for a standalone sketch
  /// document (see [kSketchBase]).
  Future<SketchModel> _loadSketchIn(Directory dir, String name,
      {String? base}) async {
    final s = SketchModel(name);
    base = '${dir.path}/${base ?? name}';
    final f = File('$base.dxf');
    if (f.existsSync()) {
      s.engine.loadDxf(f.path);
      s.refresh();
      try {
        final cf = File('$base.cons.json');
        if (cf.existsSync()) {
          s.constraints.addAll(decodeConstraints(cf.readAsStringSync()));
          ensureParamNames(s);
        }
        final pf = File('$base.params.json');
        if (pf.existsSync()) {
          s.userParams.addAll(decodeUserParams(pf.readAsStringSync()));
        }
        final tf = File('$base.texts.json');
        if (tf.existsSync()) s.texts.addAll(decodeTexts(tf.readAsStringSync()));
        final imf = File('$base.images.json');
        if (imf.existsSync()) {
          s.images.addAll(decodeImages(imf.readAsStringSync()));
        }
        void retag(String path, Geo Function(Geo, dynamic) apply) {
          final rf = File(path);
          if (!rf.existsSync()) return;
          (jsonDecode(rf.readAsStringSync()) as Map<String, dynamic>)
              .forEach((k, v) {
            final i = int.tryParse(k);
            if (i != null && i >= 0 && i < s.geometry.length) {
              s.geometry[i] = apply(s.geometry[i], v);
            }
          });
        }

        retag(
            '$base.splines.json',
            (g, v) =>
                g.type == Geo.polyline ? g.asSpline((v as num).toInt()) : g);
        retag('$base.gears.json', (g, v) {
          if (v is Map && v['d'] is List) {
            final d =
                (v['d'] as List).map((e) => (e as num).toDouble()).toList();
            if (d.length >= 6 + 6) {
              return Geo(Geo.polyline, d,
                  layer: g.layer, spline: Geo.gearTag, style: g.style);
            }
          }
          return g;
        });
        retag('$base.styles.json', (g, v) => g.withStyle((v as num).toInt()));
        retag(
            '$base.proj.json',
            (g, v) => v is List
                ? g.withProj((v[0] as num).toInt(), (v[1] as num).toInt())
                : g.withProj((v as num).toInt()));
        syncProjections(s.geometry);
        final lf = File('$base.layers.json');
        var eos = -1;
        if (lf.existsSync()) {
          final j = jsonDecode(lf.readAsStringSync()) as Map<String, dynamic>;
          s.layers.addAll([
            for (final l in (j['layers'] as List? ?? const [])) l as String
          ]);
          s.hiddenLayers
              .addAll((j['hidden'] as List? ?? const []).cast<String>());
          s.lockedLayers
              .addAll((j['locked'] as List? ?? const []).cast<String>());
          eos = (j['eos'] as num?)?.toInt() ?? -1;
        }
        s.eosAfter = eos < 0 ? s.layers.length : eos;
        _syncLayers(s);
        _pruneEmptyBaseLayer(s);
      } catch (e) {
        Log.w('part', 'child sidecar read failed: $e');
      }
    }
    s.resetHistory();
    return s;
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
  /// The geometry to draw THIS frame — which, during a grip drag, is the
  /// result of a live 25-iteration constraint solve.
  ///
  /// Measure it, because of where it runs. This is called from
  /// `CustomPainter.paint` (the comment below says so) and from five other
  /// sites including the snap path and the drag commit, so a single
  /// pointer-move used to pay for the solve more than once —
  /// `PERFORMANCE_PROFILE.md` §5.2 counted 120 solves against 60 painted
  /// frames. It no longer does: the answer is memoised on the drag position,
  /// so every caller within one position shares one solve.
  ///
  /// `2d.displayGeometry.solves` counts the calls that actually solved and
  /// `2d.displayGeometry.cacheHit` the ones answered from the memo; the two
  /// together are the call count, and the first divided by frames is now 1.
  /// The early return is left uncounted on purpose — a non-drag frame does no
  /// work here and should not dilute the average.
  List<Geo> displayGeometry(SketchModel s) {
    if (dragGrip == null || dragPos == null) {
      // No drag in flight, so nothing cached can ever be returned again — the
      // guards below would all miss anyway. Dropping the references here rather
      // than relying on that keeps a finished drag's geometry list from
      // outliving the drag; this is the first paint after every release.
      if (_dgResult != null) {
        _dgSketch = null;
        _dgGrip = null;
        _dgPos = null;
        _dgSource = null;
        _dgResult = null;
      }
      return s.geometry;
    }
    // S4 — ONE SOLVE PER DRAG POSITION, NOT PER CALLER.
    //
    // Measured: 60 painted frames of `ui.drag60` issued 120 calls and 120
    // solves. Two call sites in the painter (the `ent.dofColour` phase and the
    // `constraints` phase) each asked this question about the same cursor
    // position, and a third (the tool preview) and a fourth (endGripDrag's
    // commit) ask it again whenever they are live.
    //
    // They were not duplicates, which is the part worth reading carefully.
    // _displayGeometryInner ENDS a good frame with `_lastGoodDragGeo = gs` and
    // OPENS the next call by warm-starting from that field, so the second call
    // re-pulled the grip to the cursor and ran 25 more solver iterations on the
    // first call's output. Consequences, all measured rather than argued:
    //
    //   - entities were drawn from the first call's list and constraint glyphs
    //     from the second's, so a glyph sat where its entity was about to be
    //     rather than where it was drawn;
    //   - the count varied with UI state (1, 2 or 3 solves per frame depending
    //     on edit mode and whether a tool preview was up), so the geometry a
    //     drag COMMITTED depended on whether glyphs were switched on.
    //
    // Collapsing them is exactly identical for free drags, body drags and
    // drags whose cursor the constraints cannot reach (maxDelta 0.000e+0 on
    // all three). On a genuinely coupled system — two slots joined by a
    // tangent and a point-on-curve — it moves the answer by 3.2e-4 on a 64-unit
    // sketch, 5 ppm, and that difference is a point on the constraint manifold
    // and not a residual off it: both regimes commit at residual norm 2.828e-6,
    // equal to four significant figures, against a satisfaction threshold of
    // 1e-6 and a renderable threshold of 1e-2.
    //
    // The full write-up, with the arithmetic and the pre-registered
    // predictions, is perf/findings/S4-painter.md.
    if (identical(_dgSketch, s) &&
        identical(_dgGrip, dragGrip) &&
        identical(_dgSource, s.geometry) &&
        _dgPos == dragPos &&
        _dgResult != null) {
      Perf.count('2d.displayGeometry.cacheHit');
      return _dgResult!;
    }
    Perf.count('2d.displayGeometry.solves');
    final out =
        Perf.span('2d.displayGeometry', () => _displayGeometryInner(s));
    _dgSketch = s;
    _dgGrip = dragGrip;
    _dgPos = dragPos;
    _dgSource = s.geometry;
    _dgResult = out;
    return out;
  }

  List<Geo> _displayGeometryInner(SketchModel s) {
    // NB: this runs INSIDE CustomPainter.paint. A throw here aborts the whole
    // paint, so every entity after it stays unpainted and the sketch looks like
    // it vanished. Likewise NaN/Inf: Skia drops those paths silently. Neither
    // may ever escape this method.
    try {
      final grip = dragGrip!;
      // M207 — WARM START: continue from the LAST SOLVED FRAME, not from the
      // committed geometry.
      //
      // "The dragging around of those 2 slots is really jumping and buggy."
      //
      // Every frame used to copy `s.geometry`, move the grip to the cursor and
      // solve from there. For one free line that is the same answer either
      // way. For two slots it is not: they carry tangents, an equal and a
      // point-on-curve (the auto-constraints, which are wanted — the user was
      // explicit about that), and a system like that has SEVERAL solutions for
      // any given cursor position. Restarting from the same fixed
      // configuration each frame lets the solver pick a different one as the
      // cursor moves a pixel, and the sketch flips between them. That is the
      // jumping, and it is why it only ever showed up once two shapes were
      // constrained to each other.
      //
      // Continuing from the previous frame makes each step a SMALL one from a
      // point already on the manifold, so the solver stays on the branch it is
      // already on — which is the branch the user is watching. The final
      // settle in endGripDrag still runs 80 iterations from scratch, so
      // nothing accumulates into the commit.
      //
      // Not for a BODY drag. That one translates the entity by
      // (cursor - the point the finger grabbed), an ABSOLUTE anchor fixed when
      // the drag began — apply it to a frame that already carries the previous
      // translation and the entity moves twice as far each frame. A body drag
      // also wishes on every point at once, which is the well-conditioned case
      // this is not about.
      final prev = grip.isBody ? null : _lastGoodDragGeo;
      final gs = List<Geo>.from(
          prev != null && prev.length == s.geometry.length ? prev : s.geometry);
      if (grip.entity < 0 || grip.entity >= gs.length) {
        Log.e(
            'drag',
            'grip points at entity ${grip.entity}, '
                'geometry has ${gs.length} — ignoring drag');
        return s.geometry;
      }
      final before = gs[grip.entity];
      gs[grip.entity] = moveGrip(before, grip, dragPos!);

      if (Log.every('drag-frame', 150)) {
        Log.d(
            'drag',
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

      // A body drag translates the WHOLE entity: every defining point is a
      // drag wish, so the entity moves rigidly (the solver still bends only as
      // far as the constraints allow). A point drag wishes on that one point.
      var dragged = grip.isBody
          ? {for (var p = 0; p < ptCount(before); p++) (grip.entity, p)}
          : {(grip.entity, grip.idx)};

      // M94 — DRAGGING A SHAPE BY ITS CENTRE CARRIES THE SHAPE.
      //
      // A polygon has 4 DOF (centre x/y, radius, rotation). Grabbing the
      // construction circle's centre wishes on 2 of them and leaves radius and
      // rotation free, so the solver was entitled to scale or spin the polygon
      // on the way — it satisfied every constraint, it just was not what the
      // user meant. Inventor carries the shape.
      //
      // Fixed WITHOUT new constraints: extra constraints to hold size and
      // rotation would overdetermine the polygon and put us straight back into
      // the singular-system trap M92 was careful to avoid. Instead the whole
      // rigid group is pre-translated by the same delta and every one of its
      // points becomes a drag wish, so the solver starts from the answer the
      // user wants and its minimum-norm step keeps it. Anything the user HAS
      // constrained still wins — the solve runs normally afterwards and pulls
      // back whatever the constraints require.
      final rigid = _centreRigidGroup(s, gs, grip);
      if (rigid != null) {
        // Measured against where the grip was ON THIS FRAME'S starting
        // geometry, not against where it was when the drag began: with the
        // warm start above those differ, and using the whole-gesture delta
        // would translate the rigid group again on every frame.
        final delta = dragPos! - getPt(before, grip.idx);
        final wishes = <(int, int)>{};
        for (final e in rigid) {
          if (e != grip.entity) gs[e] = translateGeo(gs[e], delta);
          for (var q = 0; q < ptCount(gs[e]); q++) {
            wishes.add((e, q));
          }
        }
        dragged = wishes;
      }
      final ok =
          solveConstraints(gs, s.constraints, dragged: dragged, iterations: 25);

      if (!allFinite(gs)) {
        Log.e(
            'drag',
            'display geometry NON-FINITE after solve — '
                'showing committed geometry instead');
        Log.block(
            'drag', 'bad display geometry', sketchDump(gs, s.constraints));
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
      // M208 — and it must not have destroyed anything since the finger went
      // down. The check inside the solve only sees one step; a slot cap that
      // shrinks a little on each of a hundred frames never trips it, and by
      // the end the slot is a line. Measured against the start of the gesture
      // it is caught on the frame that crosses the floor, and the drag stops
      // there instead of continuing into the collapse.
      final killed = _dragStartGeo == null
          ? const <int>[]
          : collapsedSince(_dragStartGeo!, gs);
      if (killed.isNotEmpty) {
        if (Log.every('drag-collapse', 200)) {
          Log.d(
              'drag',
              'frame would collapse ${killed.join(",")} — '
                  'holding last good geometry');
        }
        return _lastGoodDragGeo ?? s.geometry;
      }
      _lastGoodDragGeo = gs;
      return gs;
    } catch (err, st) {
      Log.e(
          'drag',
          'displayGeometry THREW — this would have blanked the '
              'viewport; showing committed geometry instead',
          err,
          st);
      Log.block(
          'drag', 'sketch at throw', sketchDump(s.geometry, s.constraints));
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
      'drag-frame',
      'solve',
      'lm-ok',
      'lm-fail',
      'slvs-ok',
      'slvs-verify',
      'slvs-bail'
    ]) {
      Log.resetThrottle(k);
    }
    Log.i('drag',
        'BEGIN ${s0 == null ? '(no sketch)' : gripStr(g, s0.geometry)}');
    if (s0 != null) {
      Log.i(
          'drag',
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
    _dragStartGeo = s0 == null ? null : List<Geo>.from(s0.geometry);
    notifyListeners();
  }

  // M47: whole-entity BODY drag ---------------------------------------------
  /// Starts a body drag: the finger grabbed the line/curve itself at [atWorld]
  /// (not a grip point), and the entity translates rigidly as the cursor moves.
  /// Reuses the grip-drag machinery — a body-grip sentinel in [dragGrip], the
  /// same [displayGeometry] preview and the same [endGripDrag] commit — so the
  /// painter, snapping and undo all behave exactly as for a point drag.
  ///
  /// Refuses (like a fully-constrained point grip) when the entity has NO
  /// remaining freedom: it is rigidly placed and a drag would only snap back,
  /// so the caller falls through to selection instead. [dragGrip] stays null in
  /// that case, which makes the subsequent update/end calls no-ops.
  void beginBodyDrag(int entity, Offset atWorld) {
    final s0 = current;
    if (s0 == null || entity < 0 || entity >= s0.geometry.length) return;
    for (final k in const [
      'drag-frame',
      'solve',
      'lm-ok',
      'lm-fail',
      'slvs-ok',
      'slvs-verify',
      'slvs-bail'
    ]) {
      Log.resetThrottle(k);
    }
    final geo = s0.geometry[entity];
    Log.i('drag', 'BEGIN body ${geoStr(entity, geo)}');
    final a = analysis;
    if (a != null) {
      var anyFree = false;
      for (var p = 0; p < ptCount(geo); p++) {
        if (a.freePoints.contains((entity, p))) {
          anyFree = true;
          break;
        }
      }
      if (!anyFree) {
        Log.i('drag', 'REFUSED body drag: entity $entity is fully constrained');
        return;
      }
    }
    dragGrip = Grip.body(entity, atWorld);
    dragPos = atWorld;
    _lastGoodDragGeo = null;
    _dragStartGeo = List<Geo>.from(s0.geometry);
    notifyListeners();
  }


  /// M94 — the entities that must travel rigidly when [grip] drags a shape's
  /// CENTRE, or null when this is an ordinary point drag.
  ///
  /// Recognises the construction-circle centre a polygon is built around
  /// (M92): a circle whose centre is being dragged and which other entities
  /// are pinned ON via point-on-curve `coincident`. Those entities, plus
  /// anything coincident with them, form the shape.
  ///
  /// Returns null unless the group is genuinely a closed shape hanging off
  /// this circle, so a lone circle still drags exactly as before.
  Set<int>? _centreRigidGroup(SketchModel s, List<Geo> gs, Grip grip) {
    if (grip.isBody || grip.idx != 0) return null;
    final ci = grip.entity;
    if (ci >= gs.length || gs[ci].type != Geo.circle) return null;

    // Entities pinned ON this circle by a point-on-curve coincident.
    final onCircle = <int>{};
    for (final c in s.constraints) {
      if (c.type != CType.coincident) continue;
      if (c.pts.length != 1 || c.ents.length != 1 || c.ents.first != ci) {
        continue;
      }
      onCircle.add(c.pts.first.ent);
    }
    if (onCircle.length < 3) return null; // not a polygon

    // Grow across point-to-point coincidents so the whole rim comes along.
    final group = <int>{ci, ...onCircle};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in s.constraints) {
        if (c.type != CType.coincident || c.pts.length < 2) continue;
        final a = c.pts[0].ent, b = c.pts[1].ent;
        if (group.contains(a) && !group.contains(b)) {
          group.add(b);
          grew = true;
        } else if (group.contains(b) && !group.contains(a)) {
          group.add(a);
          grew = true;
        }
      }
    }
    return group;
  }

  void updateGripDrag(Offset w) {
    dragPos = w;
    notifyListeners();
  }

  void endGripDrag() {
    final s = current;
    if (s != null && dragGrip != null && dragPos != null) {
      Log.i(
          'drag',
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
        //
        // M208 — and the settle is CHECKED. It used to be run for its side
        // effect and its answer thrown away, so a settle that collapsed the
        // shape was committed anyway: that is how a slot reached the document
        // as a line with two zero-radius caps, after every drag frame in the
        // log had correctly refused the same configuration. What is shown is
        // what gets committed; if the settle cannot improve on the last shown
        // frame, the last shown frame is what the user was looking at and is
        // sound, so it is committed unrefined.
        final shown = List<Geo>.from(displayGeometry(s));
        final gs = List<Geo>.from(shown);
        final start = _dragStartGeo;
        final settled = solveConstraints(gs, s.constraints) &&
            (start == null || collapsedSince(start, gs).isEmpty);
        if (!settled) {
          Log.w('drag',
              'END: settle rejected — committing the last shown frame');
          gs
            ..clear()
            ..addAll(shown);
        }
        normalizeArcAngles(gs);
        _rebuildEngine(s, gs);
      } catch (err, st) {
        Log.e('drag', 'END: rebuild threw', err, st);
      }
      Log.block(
          'drag', 'sketch after drag', sketchDump(s.geometry, s.constraints));
    }
    dragGrip = null;
    dragPos = null;
    _lastGoodDragGeo = null;
    _dragStartGeo = null;
    Log.flush();
    snap = null;
    notifyListeners();
  }

  /// Is [c] the point-on-CURVE bind that a point-on-POINT between (e,p) and
  /// (j,pj) would make redundant — either participant pinned onto the other
  /// participant's entity?
  static bool _subsumedBy(Constraint c, int e, int p, int j, int pj) {
    if (c.type != CType.coincident ||
        c.pts.length != 1 ||
        c.ents.length != 1) {
      return false;
    }
    final r = c.pts[0];
    final onto = c.ents[0];
    return (r.ent == e && r.pt == p && onto == j) ||
        (r.ent == j && r.pt == pj && onto == e);
  }

  /// Binds the NEW endpoints a trim/split created (every piece endpoint that
  /// was not an endpoint of the original carrier [old]) the way Inventor does:
  /// point-on-point when it meets an existing point (a split's twin piece, a
  /// crossing endpoint), otherwise point-on-curve onto the entity whose
  /// interior it lies on (the cutter). Candidates run through the same
  /// over-constraint gate as manual constraints and are appended to [cons];
  /// the caller's atomic solve then verifies everything together.
  /// [avoid] is the kept trim carrier (M187), which must never be mistaken for
  /// the cutter.
  /// M191 — a construction leftover has to stay ON the geometry it was cut
  /// from, or a drag pulls it off and the dashed ghost stops describing what
  /// was removed (measured before this: after one drag the leftover arcs sat
  /// 2.5 and 3.7 units off their partners' centres, radius out by up to 3.6).
  ///
  /// One equation each, deliberately. The ends are already glued by
  /// [_bindCutPoints], so what is missing is exactly one degree of freedom:
  /// the arc's bulge, or the line's swing. `concentric` (2 equations) or
  /// `collinear` (2) would buy that same single degree of freedom and the
  /// over-constraint gate refuses them — rightly, they carry a redundant row.
  /// An `equal` radius and a point-on-line do it in one.
  void _tieLeftovers(
      List<Geo> gs, int keptStart, int cutStart, List<Constraint> cons) {
    const tol = 1e-6;
    bool round(Geo g) => g.type == Geo.circle || g.type == Geo.arc;

    void tryAdd(Constraint c) {
      if (wouldOverconstrain(gs, cons, c)) {
        Log.i('modify',
            'leftover-tie ${conStr(-1, c)} DROPPED (would over-constrain)');
        return;
      }
      Log.i('modify', 'leftover-tie ${conStr(-1, c)} (M191 cut-away span)');
      cons.add(c);
    }

    for (var e = cutStart; e < gs.length; e++) {
      final ghost = gs[e];
      // the piece it was cut from — same type, among what the trim kept
      var partner = -1;
      for (var k = keptStart; k < cutStart && partner < 0; k++) {
        if (gs[k].type == ghost.type) partner = k;
      }
      if (partner < 0) continue; // nothing was kept: the ghost IS the entity
      if (round(ghost)) {
        tryAdd(Constraint(CType.equal, ents: [partner, e]));
      } else if (ghost.type == Geo.line) {
        // The end NOT sitting on the cut is the one free to swing; pinning it
        // to the kept line's carrier is collinearity in one equation, and
        // leaves the ghost's LENGTH free, which is what its own inherited
        // dimension drives.
        for (final p in const [0, 1]) {
          final q = getPt(ghost, p);
          final atCut = [
            for (var k = keptStart; k < cutStart; k++)
              for (var pk = 0; pk < ptCount(gs[k]); pk++)
                if ((getPt(gs[k], pk) - q).distance < tol) 1
          ].isNotEmpty;
          if (!atCut) {
            tryAdd(Constraint(CType.coincident,
                pts: [PRef(e, p)], ents: [partner]));
          }
        }
      }
    }
  }

  void _bindCutPoints(List<Geo> gs, Geo old, int piecesStart,
      List<Constraint> cons, {int ignoreFrom = -1}) {
    const tol = 1e-6;
    // Entities from [ignoreFrom] on do not exist for this pass — neither as
    // pieces to bind nor as partners to bind to (M191: the construction
    // leftovers, which a kept piece's cut point would otherwise grab instead
    // of the cutter, since they meet exactly there).
    final end = ignoreFrom < 0 ? gs.length : ignoreFrom;
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

    for (var e = piecesStart; e < end; e++) {
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
        for (var j = 0; j < end && cand == null; j++) {
          if (j == e) continue;
          for (var pj = 0; pj < ptCount(gs[j]); pj++) {
            if ((getPt(gs[j], pj) - q).distance < tol) {
              final pp =
                  Constraint(CType.coincident, pts: [PRef(j, pj), PRef(e, p)]);
              // The point-on-point SUBSUMES any point-on-curve bind of either
              // participant onto the other participant's entity (one equation
              // of it, making the pair redundant → the gate would reject the
              // stronger bind). Replace, don't stack: the trial list is `cons`
              // WITHOUT those binds, and it is only adopted if the pair then
              // fits — otherwise the removal never happened.
              final subsumed =
                  cons.where((c) => _subsumedBy(c, e, p, j, pj)).toList();
              final trial =
                  cons.where((c) => !_subsumedBy(c, e, p, j, pj)).toList();
              if (wouldOverconstrain(gs, trial, pp)) {
                // M187 — with the carrier kept, a cut point is already pinned
                // by carrier ∩ cutter, so the stacking pair is genuinely
                // redundant. Keep the curve binds and move on; the two points
                // stay glued THROUGH the geometry they are both pinned to.
                Log.i(
                    'modify',
                    'cut-bind ${conStr(-1, pp)} not needed — the cut point is '
                        'already pinned by its carrier and cutter');
                break;
              }
              for (final c in subsumed) {
                Log.i(
                    'modify',
                    'cut-bind upgrades ${conStr(-1, c)} -> point-on-point '
                        '(stacked endpoints)');
              }
              cons
                ..clear()
                ..addAll(trial);
              cand = pp;
              break;
            }
          }
        }
        // 2) lies on the interior of another entity: the cutter
        if (cand == null) {
          for (var j = 0; j < end; j++) {
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
                cand =
                    Constraint(CType.coincident, pts: [PRef(e, p)], ents: [j]);
                break;
              }
            } else if (t.type == Geo.circle || t.type == Geo.arc) {
              final c0 = Offset(t.data[0], t.data[1]);
              if (((q - c0).distance - t.data[2]).abs() < tol) {
                cand =
                    Constraint(CType.coincident, pts: [PRef(e, p)], ents: [j]);
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
  ///
  /// M345 — [active] false rebuilds a sketch that is NOT the one on screen (a
  /// paste into a sketch the user is not standing in). Everything below is a
  /// property of the sketch it is given and is right either way; the DOF
  /// analysis is not — [analysis] belongs to [current], and overwriting it
  /// with another sketch's answer would mis-colour the one being looked at.
  void _rebuildEngine(SketchModel s, List<Geo> gsIn, {bool active = true}) {
    // Ellipses stay CANONICAL: after a grip drag or a solve, the minor vertex
    // may have drifted off the perpendicular — the renderer orthogonalizes,
    // but the stored point would float off the curve. Snap it back onto the
    // minor axis here, the one place every edit funnels through.
    final gs = [
      for (final g in gsIn)
        g.spline == Geo.ellipseTag
            ? normalizedEllipse(g)
            : g.spline == Geo.gearTag
                ? normalizedGear(g)
                : g
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
        Log.w(
            'layer',
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
          if (g.spline == Geo.gearTag) {
            // The backend (and DXF / 3D) gets the REAL baked tooth outline —
            // "constructed from the lines the backend offers" — while the
            // in-memory Geo keeps its compact two-point form (refresh restores
            // it from tagSource below, so allGeometry never overwrites it).
            final curve = gearCurve(g);
            final xy = <double>[for (final p in curve) ...[p.dx, p.dy]];
            if (xy.length >= 4) {
              s.engine.addPolyline(xy, closed: true);
            } else {
              // degenerate params: fall back to the two defining points
              s.engine.addPolyline(
                  [g.data[2], g.data[3], g.data[4], g.data[5]],
                  closed: false);
            }
            break;
          }
          final n = g.data[1].toInt();
          s.engine.addPolyline([
            for (var i = 0; i < n; i++) ...[
              g.data[2 + 2 * i],
              g.data[3 + 2 * i]
            ]
          ], closed: g.data[0] != 0);
          break;
      }
    }
    _committed(s, tags: gs);
    _refreshDriven(s);
    // M41: expressions referencing driven (reference) parameters follow the
    // fresh measurements; guarded so the chase's own solves do not recurse.
    if (!_inExprChase) _chaseExpressions(s);
    if (active) analysis = _analysisCache.of(s.geometry, s.constraints);
    // UNDO JOURNAL (M39): every committed mutation funnels through this
    // rebuild (the C-API is add-only), so this one call records the whole
    // app's edits — draw, drag, trim, fillet, patterns, dimensions,
    // constraints, layer rename/delete/move. Suppressed while RESTORING a
    // snapshot, or undo would journal itself — and (M179) while a scrub is
    // still under the finger, so the whole drag lands as ONE step when it is
    // released rather than one per detent.
    if (!_restoringHistory && !liveEditing) s.checkpoint();
    Log.i('engine',
        'rebuild done, geometry=${s.geometry.length}, dof=${analysis?.dof}');
  }

  // ---- tools ----
  /// M53 — the last DRAWING tool the user armed; the Pencil double-tap
  /// re-arms it (draw, tap out, inspect, tap back in — Inventor's Esc +
  /// re-pick loop without the keyboard).
  Tool lastDrawTool = Tool.none;

  void selectTool(Tool t) {
    if (t != Tool.none && (toolMeta[t] != null || t == Tool.dimension)) {
      lastDrawTool = t;
    }
    // A sketch entity has to live on a layer, and the only way to know WHICH
    // layer is to be editing one. So no tool outside edit mode — that is what
    // keeps "every line belongs to exactly one layer" true by construction
    // instead of by hope.
    if (t != Tool.none && !inEditMode) {
      Log.i('tool', 'BLOCKED $t — not editing a layer');
      toast(L.current.msgEnterLayerToSketch);
      return;
    }
    // M371 — arming a drawing tool puts Measure away: the symmetric half of
    // [startMeasure] standing the tool down. Both collect taps from the
    // viewport and the measure branch is checked first, so leaving the panel
    // open would mean the tool you just picked never received one. Below the
    // edit-mode guard, so a BLOCKED tool does not close a panel the user is
    // reading.
    if (t != Tool.none) cancelMeasure();
    tool = t;
    // M85: remember the variant for its flyout group. Tool.none (Esc, tool
    // finished) must NOT clear it — that is the whole point: the last used
    // variant stays on the button after the tool ends.
    final grp = toolFlyoutGroup[t];
    if (grp != null) ribbonPick[grp] = t;
    toolPoints.clear();
    _hudResetAll();
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
    // Gear tool opens its modeless dialog (M61), seeded with the last-used
    // parameters. If exactly one existing gear is selected it is opened for
    // EDITING (Insert replaces it in place).
    if (t == Tool.gear) {
      final s = current;
      GearParams seed = lastGearParams.copy();
      GearKind kind = seed.internal ? GearKind.internal : GearKind.external;
      if (s != null) {
        // If a single gear is selected, copy its STYLE into the dialog as a
        // convenient starting point (a fresh gear is still placed by a tap).
        final sel = selection
            .where(
                (i) => i >= 0 && i < s.geometry.length && s.geometry[i].isGear)
            .toList();
        if (sel.length == 1) {
          final p = gearParams(s.geometry[sel.first]);
          if (p != null) {
            seed = p;
            kind = p.internal ? GearKind.internal : GearKind.external;
          }
        }
      }
      gear = GearSession(
        kind: kind,
        params: seed,
        sunTeeth: lastGearSun,
        planetTeeth: lastGearPlanet,
        planetCount: lastGearPlanetCount,
      );
      selection.clear();
    } else {
      gear = null;
    }
    notifyListeners();
  }

  // ---- M97: pick a target body by CLICKING it ----

  /// True while the extrude dialog is waiting for you to pick a target body,
  /// in the 3D viewport or in the model browser. Inventor lets you click the
  /// body instead of hunting through a dropdown.
  bool pickingBody = false;

  /// Body under the cursor while [pickingBody] — highlighted in BOTH the
  /// browser and the 3D view, so the two agree about what a click would take.
  String? hoverBody;

  /// The solid body SELECTED in the model browser, or null.
  ///
  /// Inventor's part-mode selection: clicking a Solid Bodies row highlights
  /// the row and the body itself in 3D, and clicking it again clears both.
  /// Kept here, next to [hoverBody], for the same reason that one is — the
  /// browser (Flutter and native) and both renderers must read ONE answer, or
  /// the row and the geometry can disagree about what is selected.
  String? selectedBody;

  /// The body under the pointer in the MODEL BROWSER, or null.
  ///
  /// Deliberately not [hoverBody]: that one belongs to the extrude dialog's
  /// target pick and re-previews the boolean as it moves, which is far too
  /// much to happen because a pointer crossed a tree row. This one only lights
  /// things up — the row, and the body itself in 3D, in the same colour a
  /// hovered assembly component gets.
  String? browserHoverBody;

  void setBrowserHoverBody(String? name) {
    if (browserHoverBody == name) return;
    browserHoverBody = name;
    notifyListeners();
  }

  /// Selects [name], or clears the selection when it is already selected.
  void toggleBodySelected(String name) =>
      selectBody(selectedBody == name ? null : name);

  void selectBody(String? name) {
    if (selectedBody == name) return;
    selectedBody = name;
    notifyListeners();
  }

  // ---- M272: appearances ----

  /// The appearance of whatever is selected right now, or null for steel.
  ///
  /// One getter over both modes, because the ribbon control is one control:
  /// in a part the selection is a BODY, in an assembly it is a COMPONENT, and
  /// the difference stops at this line.
  String? get selectedMaterial {
    final a = currentAssembly;
    if (a != null) return a.selected?.material;
    final b = selectedBody;
    return b == null ? null : currentPart?.bodyMaterials[b];
  }

  /// Is there anything to paint? The ribbon control dims when there is not.
  bool get canSetMaterial => currentAssembly != null
      ? currentAssembly!.selected != null
      : (currentPart != null && activeChild == null && selectedBody != null);

  /// Paints the current selection. [id] null (or [kMaterialSteel]) strips it.
  ///
  /// Undo is deliberately NOT taken here. An appearance changes nothing the
  /// model is built from — no face moves, no feature rebuilds — so putting it
  /// on the timeline would mean an undo after painting a body silently threw
  /// away the extrusion before it. Re-picking steel is the undo, and it is one
  /// tap away in the same menu.
  void setSelectedMaterial(String? id) {
    final m = sanitiseMaterial(id);
    final a = currentAssembly;
    if (a != null) {
      final o = a.selected;
      if (o == null || o.material == m) return;
      o.material = m;
      Log.i('asm', 'component "${o.id}" appearance = ${m ?? kMaterialSteel}');
      if (curTab != null) saveAssembly(curTab!);
      notifyListeners();
      return;
    }
    final p = currentPart;
    final body = selectedBody;
    if (p == null || body == null) return;
    if (p.bodyMaterials[body] == m) return;
    // Removed rather than stored as 'steel', so an unpainted part's document
    // is byte-identical to what it was before appearances existed.
    m == null ? p.bodyMaterials.remove(body) : p.bodyMaterials[body] = m;
    p.dirty = true;
    Log.i('part', 'body "$body" appearance = ${m ?? kMaterialSteel}');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  // ---- M275: the ViewCube's front ----

  /// The open document's cube orientation, or the identity.
  Quat get cubeOrient =>
      currentAssembly?.cubeOrient ?? currentPart?.cubeOrient ?? Quat.identity;

  /// Redefines which way the cube's FRONT (or TOP) faces, from the current
  /// view — Inventor's "Set Current View as Front".
  ///
  /// Pass [Quat.identity] for "Reset Front". Nothing about the geometry moves;
  /// see PartModel.cubeOrient.
  void setCubeOrient(Quat q) {
    final a = currentAssembly;
    if (a != null) {
      a.cubeOrient = q;
      Log.i('asm', 'cube front redefined');
      if (curTab != null) saveAssembly(curTab!);
      notifyListeners();
      return;
    }
    final p = currentPart;
    if (p == null) return;
    p.cubeOrient = q;
    p.dirty = true;
    Log.i('part', 'cube front redefined');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  // ---- M273: how the model is drawn ----

  CyclesSession? _cycles;
  Object? _cyclesDoc;

  /// M304 — the Cycles renderer for the document that is open.
  ///
  /// One per document, rebuilt when the document changes, because everything
  /// it holds — the queued key, the image on screen — is about THAT model. A
  /// session carried across a tab switch would show the last part's render
  /// over the next part for as long as it took the new key to be offered.
  ///
  /// On a build with no Cycles libraries linked, and in every host test, the
  /// session reports [CyclesSession.available] false and does nothing at all;
  /// rendered mode is then exactly the RealityKit view it has always been.
  CyclesSession get cycles {
    final Object? doc = currentAssembly ?? currentPart;
    if (_cycles == null || !identical(_cyclesDoc, doc)) {
      _cycles?.reset();
      _cyclesDoc = doc;
      _cycles = CyclesSession();
    }
    return _cycles!;
  }

  /// The display mode of whatever document is open, or the working view.
  DisplayMode get displayMode =>
      currentAssembly?.displayMode ??
      currentPart?.displayMode ??
      DisplayMode.fallback;

  /// Is there a 3D document to switch? A sketch has no display mode: it is
  /// lines on a plane, and there is nothing to light.
  bool get canSetDisplayMode =>
      currentAssembly != null || (currentPart != null && activeChild == null);

  /// Switches, and remembers it in the document.
  ///
  /// Saved rather than kept in memory, and undo does not take it, for the same
  /// two reasons M272's appearance is not on the timeline: it changes nothing
  /// the model is built from, and a view you have to re-choose on every open
  /// is a view nobody uses twice.
  void setDisplayMode(DisplayMode m) {
    final a = currentAssembly;
    if (a != null) {
      if (a.displayMode == m) return;
      a.displayMode = m;
      Log.i('asm', 'display mode = ${m.id}');
      if (curTab != null) saveAssembly(curTab!);
      notifyListeners();
      return;
    }
    final p = currentPart;
    if (p == null || p.displayMode == m) return;
    p.displayMode = m;
    p.dirty = true;
    Log.i('part', 'display mode = ${m.id}');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// M286 — whether the rendered floor is drawn. Only meaningful while
  /// [displayMode] is rendered (the working views never draw a floor), but
  /// the ribbon shows the checkbox only in rendered mode so this is never
  /// reachable anywhere else.
  bool get showFloor =>
      currentAssembly?.showFloor ?? currentPart?.showFloor ?? true;

  /// Toggles the floor, remembered in the document like [setDisplayMode].
  void setShowFloor(bool on) {
    final a = currentAssembly;
    if (a != null) {
      if (a.showFloor == on) return;
      a.showFloor = on;
      Log.i('asm', 'show floor = $on');
      if (curTab != null) saveAssembly(curTab!);
      notifyListeners();
      return;
    }
    final p = currentPart;
    if (p == null || p.showFloor == on) return;
    p.showFloor = on;
    p.dirty = true;
    Log.i('part', 'show floor = $on');
    if (curTab != null) savePart(curTab!);
    notifyListeners();
  }

  /// M97 — renames a body everywhere it is built.
  bool renameBody(String from, String to) {
    final p = currentPart;
    final n = to.trim();
    if (p == null || n.isEmpty || n == from) return false;
    if (p.features.any((f) => f.bodyName == n)) {
      message = L.current.valBodyNameTaken(n);
      notifyListeners();
      return false;
    }
    for (final f in p.features) {
      if (f.bodyName == from) f.bodyName = n;
    }
    if (selectedBody == from) selectedBody = n; // the selection follows it
    if (browserHoverBody == from) browserHoverBody = n;
    // M272 — and so does the appearance. Keyed by body NAME, so a rename that
    // did not carry it would silently repaint the body steel.
    final mat = p.bodyMaterials.remove(from);
    if (mat != null) p.bodyMaterials[n] = mat;
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
    return true;
  }

  /// M97 — deletes every feature that builds [bodyName].
  int deleteBody(String bodyName) {
    final p = currentPart;
    if (p == null) return 0;
    final victims = [for (final f in p.features) if (f.bodyName == bodyName) f];
    if (victims.isEmpty) return 0;
    _partCheckpoint(p); // M182 — deleting a body must be undoable
    if (selectedBody == bodyName) selectedBody = null; // nothing left to light
    if (browserHoverBody == bodyName) browserHoverBody = null;
    p.bodyMaterials.remove(bodyName); // M272 — and nothing left to paint

    for (final f in victims) {
      f.disposeSolid();
      p.features.remove(f);
    }
    Log.i('part',
        'body "$bodyName" deleted from "${p.name}" (${victims.length} features)');
    p.eopAfter = kEopAtEnd; // parks at the end AND keeps it there
    applyEndOfPart(p);
    recomputeAllFeatures(p, partKernel);
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    notifyListeners();
    return victims.length;
  }

  // ---- M255: MAKE PART ----------------------------------------------------
  //
  // Inventor's Make Part, off a solid body's browser menu in a multi-body
  // part: the body becomes a part DOCUMENT of its own, that document is placed
  // in an assembly, and the whole thing stays LINKED to the body it came out
  // of — edit the origin and the part follows, for ever, with nothing to press.
  //
  // The link is [DeriveFeature], and what it stores is a REFERENCE (which
  // document, which body) rather than geometry. That is the whole design, and
  // it is M245's rule one level down: "a component IS its part" was the
  // milestone that stopped an assembly drawing a photograph of a part, and a
  // part made from a body has exactly the same way to go wrong. A copy is
  // silent, it looks right on the day it is made, and the document on screen
  // becomes a lie the first time anyone touches the original.
  //
  // WHERE THE NEW PART LANDS. At the IDENTITY, which is worth stating because
  // it does not look like a decision: the derived body is expressed in the
  // origin's own coordinates, so an untransformed placement puts it exactly
  // where it sat in the part it came from. Run the command once per body into
  // the same assembly and the assembly reproduces the multi-body part, piece
  // for piece, in place — which is what Inventor's Make Components does to a
  // whole part in one go, and the reason the target assembly may name one that
  // already exists.
  //
  // WHAT IT DOES NOT DO. It does not remove the body from the origin. Inventor
  // does not either, and the reason is worth keeping: the origin is the master
  // model — the thing every derived part is a view of — and a command that
  // emptied it would be destroying the only copy of the design intent to
  // produce a document that is defined in terms of it.

  MakePartSession? makePartSession;

  /// The assembly the last Make Part went into, so the second body of a part
  /// defaults to the assembly the first one made.
  ///
  /// Decomposing a multi-body part is this command run once per body, and
  /// having to retype the assembly name every time — getting it wrong once and
  /// ending up with Assembly1 and Assembly2 — is the whole difference between
  /// a workflow and a chore.
  String? _lastMakePartTarget;

  /// Opens the dialog on [bodyName]. A toggle, like every other command
  /// button (M210).
  void openMakePart(String bodyName) {
    final p = currentPart;
    if (p == null) return;
    if (makePartSession != null) {
      final same = makePartSession!.body == bodyName;
      cancelMakePart();
      // Long-pressing a DIFFERENT body re-opens on that one rather than
      // leaving the user with a closed dialog and no idea why.
      if (same) return;
    }
    if (!p.features.any((f) => f.bodyName == bodyName)) return;
    cancel3DCommands(); // M230 — one armed command at a time
    makePartSession = MakePartSession(
        bodyName, suggestedDerivedPartName(bodyName), suggestedMakePartTarget());
    notifyListeners();
  }

  void cancelMakePart() {
    if (makePartSession == null) return;
    makePartSession = null;
    notifyListeners();
  }

  /// Inventor's default New Part Name: the BODY's own name.
  ///
  /// Which is why renaming a body to what the part should be called is the
  /// step before Make Part in every Inventor workflow — the dialog then opens
  /// with the right answer already in it. A collision with something already
  /// in the gallery is numbered rather than refused, so the dialog never opens
  /// on a name that cannot be accepted.
  String suggestedDerivedPartName(String bodyName) {
    final base = bodyName.trim();
    if (base.isEmpty) return suggestedPartName();
    if (!docNameExists(base)) return base;
    var n = 2;
    while (docNameExists('$base$n')) {
      n++;
    }
    return '$base$n';
  }

  /// The assembly the dialog opens on: the one the last Make Part went into
  /// while it still exists, and a fresh name otherwise.
  String suggestedMakePartTarget() {
    final last = _lastMakePartTarget;
    if (last != null && isAssemblyName(last)) return last;
    return suggestedAssemblyName();
  }

  /// The dialog's OK. Makes the part, places it, and opens the assembly.
  ///
  /// Both names are validated BEFORE anything is created, for the reason
  /// [beginCreateComponentPick] gives about its own: a name rejected halfway
  /// through leaves the user with a half-finished command and the field they
  /// would fix it in already gone.
  Future<bool> makePart() async {
    final s = makePartSession;
    final origin = currentPart;
    if (s == null || origin == null) return false;
    final partName = s.partName.trim();
    final asmName = s.assemblyName.trim();
    final originName = origin.name;

    final badPart = validateSketchName(partName);
    if (badPart != null) {
      toast(badPart);
      return false;
    }
    if (docNameExists(partName)) {
      toast(L.current.msgNameTaken(partName));
      return false;
    }
    final badAsm = validateSketchName(asmName);
    if (badAsm != null) {
      toast(badAsm);
      return false;
    }
    // An EXISTING assembly is the target, not a collision — that is how a
    // second body joins the first one. A name taken by a part or a sketch is
    // still a collision.
    final reuse = isAssemblyName(asmName);
    if (!reuse && docNameExists(asmName)) {
      toast(L.current.msgNameTaken(asmName));
      return false;
    }
    if (!origin.features.any((f) => f.bodyName == s.body)) {
      toast(L.current.msgMakePartNoBody(s.body));
      return false;
    }

    // 1. The document, holding ONE feature: the link. Not opened — the user is
    //    going to the assembly, and a part tab appearing on the way there is a
    //    document they did not ask to edit.
    if (!await createNamedPart(partName, open: false)) {
      toast(L.current.msgNameTaken(partName));
      return false;
    }
    final made = parts[partName];
    if (made == null) return false;
    final link = DeriveFeature(
      // Inventor names the derived node after the document it came out of,
      // and so does this: the browser row in the new part reads "Bracket", not
      // "Feature1", so what it is derived FROM is the first thing you see.
      // [_renameSourceInDerivedParts] keeps it true across a rename.
      name: originName,
      bodyName: 'Solid1',
      sourceDoc: originName,
      sourceBody: s.body,
    )..seq = made.nextSeq();
    // The link, attached here rather than waited for from linkOccurrences:
    // the recompute below is what gives the new document its geometry, and it
    // is what the preview written by savePart draws.
    link.source = origin;
    made.appendFeature(link);
    made.claimBodyName(link.bodyName);
    if (recomputeAllFeatures(made, partKernel)) _syncSolidProjections(made);
    if (link.computeError != null) {
      Log.w('part',
          'derived "$partName" did not build: ${link.computeError}');
    }
    await savePart(partName);
    // M245's invariant: a document NOT open in a tab lives in the shared map.
    // createNamedPart had to put it in `parts` so it could be built before
    // anything pointed at it; the assembly points at it from here on.
    final model = parts.remove(partName);
    if (model != null) _componentModels[partName] = model;

    // 2. The assembly — the one that was named, made if it is not there yet.
    if (reuse) {
      await openAssembly(asmName);
    } else if (!await createNamedAssembly(asmName)) {
      // The part is made and is in the gallery, so nothing is lost: the user
      // can place it by hand. Deleting it here would throw away a name they
      // chose because a second document could not be created.
      toast(L.current.msgNameTaken(asmName));
      makePartSession = null;
      notifyListeners();
      return false;
    }
    final a = currentAssembly;
    if (a == null) return false;
    final wasEmpty = a.isEmpty;

    // 3. The component, at the identity — see the note at the head of this
    //    section for why that is the placement and not "clear of everything".
    final occ = await placeComponent(partName, at: Placement.identity);
    if (occ == null) {
      // placeComponent has already said why.
      makePartSession = null;
      notifyListeners();
      return false;
    }
    // An aimed placement does not reframe (see placeComponent), which is right
    // when it lands beside components already on screen and wrong for the
    // FIRST one in a new assembly — that would open on an empty view with the
    // part somewhere off the edge of it.
    if (wasEmpty) a.needsFit = true;
    _lastMakePartTarget = asmName;
    makePartSession = null;
    toast(L.current.msgMadePart(partName, originName));
    notifyListeners();
    unawaited(saveAssembly(asmName));
    return true;
  }

  /// M255 — follows a part RENAME into every part DERIVED from it.
  ///
  /// The part-side twin of [_renameSourceInAssemblies], and it exists for the
  /// same reason: a derived body names its origin by DOCUMENT name, so without
  /// this a rename would break every part made from it — each one falling back
  /// to "the origin is not loaded", which is the honest report of a link that
  /// should never have been broken in the first place.
  ///
  /// Loaded models are re-pointed in memory; the ones on disk are rewritten,
  /// because a link that only survives while both documents happen to be open
  /// is not a link.
  Future<void> _renameSourceInDerivedParts(String from, String to) async {
    for (final p in _loadedParts.toList()) {
      var touched = false;
      for (final f in p.features) {
        if (f is! DeriveFeature || f.sourceDoc != from) continue;
        f.sourceDoc = to;
        // The row was named after the origin when it was made. Keep it true —
        // a node reading "Bracket" in a session where nothing is called
        // Bracket any more is worse than no name at all.
        if (f.name == from) f.name = to;
        touched = true;
      }
      if (touched) {
        p.dirty = true;
        unawaited(savePart(p.name));
      }
    }
    for (final name in library.keys.toList()) {
      if (library[name]?.isPart != true) continue;
      if (_sourceModel(name) != null) continue; // handled above, in memory
      try {
        _ensureStaged(name);
        final f = _partJson(name);
        if (!f.existsSync()) continue;
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        var touched = false;
        for (final e in (j['features'] as List? ?? const [])) {
          if (e is! Map) continue;
          if (e['kind'] != 'derive' || e['srcDoc'] != from) continue;
          e['srcDoc'] = to;
          if (e['name'] == from) e['name'] = to;
          touched = true;
        }
        if (!touched) continue;
        f.writeAsStringSync(jsonEncode(j));
        _commitStage(name, 'part');
      } catch (e, st) {
        Log.e('part', 'could not re-point derived "$name" after a rename', e, st);
      }
    }
  }

  // ---- M133: picking a termination FACE for the "To" extent -------------
  //
  // Separate arm-flag from pickingBody on purpose. Both are "tap something in
  // 3D", but they consume different things and can never be active at once —
  // one flag with a mode would just be two flags with extra steps, and the
  // tap path reads better as two explicit branches.
  bool pickingExtentFace = false;

  void beginPickExtentFace() {
    if (extrudeSession == null) return;
    pickingExtentFace = true;
    toast(L.current.msgSelectTerminateFace);
    notifyListeners();
  }

  void cancelPickExtentFace() {
    if (!pickingExtentFace) return;
    pickingExtentFace = false;
    notifyListeners();
  }

  /// A planar face was tapped while [pickingExtentFace]. The frame carries a
  /// point ON the face and its outward normal, which is exactly a [FaceSel] —
  /// and exactly what resolveExtrudeSpan solves analytically.
  void extentFacePicked(PlaneFrame frame) {
    final s = extrudeSession;
    pickingExtentFace = false;
    if (s == null) {
      notifyListeners();
      return;
    }
    s.extentFace = FaceSel(frame.origin.x, frame.origin.y, frame.origin.z,
        frame.n.x, frame.n.y, frame.n.z);
    s.extent = FeatureExtent.toFace;
    _updateExtrudePreview();
    notifyListeners();
  }

  // ---- M133: picking EDGES (fillet/chamfer, wired up in M136) ------------
  //
  // The selection lives on AppState rather than inside a fillet session for
  // the same reason hoverBody does: the viewport and the dialog must read one
  // list, or they will disagree about what is selected.
  bool pickingEdges = false;

  /// Edges picked so far, as re-attachable fingerprints. Order is the order
  /// they were tapped, which is the order their radii are entered in.
  final List<EdgeSel> pickedEdges = [];

  /// Topological ids of [pickedEdges] against the solid they were taken from.
  /// Only valid for as long as that solid lives; the fingerprints are what
  /// survive a rebuild.
  final List<int> pickedEdgeIds = [];

  /// DISPLAY indices of the same edges, parallel to [pickedEdgeIds].
  ///
  /// Kept alongside because the two index spaces are different and each side
  /// needs its own: the kernel addresses topological edges, the renderer
  /// indexes the mesh's display edge list. Converting on demand would mean
  /// re-deriving the mapping on every payload push.
  final List<int> pickedEdgeDisplay = [];

  /// Which edge SET each picked edge belongs to, parallel to [pickedEdges].
  /// Inventor lets one fillet feature carry several sets, each with its own
  /// radius; new picks land in [activeEdgeSet].
  final List<int> pickedEdgeSet = [];

  /// The set new picks go into. Bumped by [newEdgeSet].
  int activeEdgeSet = 0;

  /// How many sets the current selection spans (at least one).
  int get edgeSetCount {
    var n = activeEdgeSet + 1;
    for (final i in pickedEdgeSet) {
      if (i + 1 > n) n = i + 1;
    }
    return n;
  }

  /// Start a new edge set, so the next taps get their own radius.
  void newEdgeSet() {
    final s = edgeSession;
    if (s == null || !s.isFillet) return;
    activeEdgeSet = edgeSetCount;
    while (s.exprRadii.length <= activeEdgeSet) {
      s.exprRadii.add(s.exprRadii.isEmpty ? '2 mm' : s.exprRadii.last);
    }
    while (s.exprRadii2.length <= activeEdgeSet) {
      s.exprRadii2.add('');
    }
    notifyListeners();
  }

  void selectEdgeSet(int i) {
    if (i < 0 || i >= edgeSetCount) return;
    activeEdgeSet = i;
    notifyListeners();
  }

  /// M142 — Inventor's Select Mode: fill the ACTIVE set with every concave
  /// edge ("All Fillets") or every convex one ("All Rounds") of the body.
  ///
  /// Needs the convexity the shim reports (v13); before that the two would
  /// have selected the same set, since nothing distinguished an interior
  /// corner from an exterior one.
  void selectAllEdges({required bool concave}) {
    final s = edgeSession;
    final base = pickedEdgeSolid;
    if (s == null || !s.isFillet) return;
    if (base == null) {
      toast(L.current.msgPickOneEdgeFirst);
      return;
    }
    final live = partKernel.edgesOf(base);
    if (live.isEmpty) {
      toast(L.current.msgBodyHasNoEdges);
      return;
    }
    var added = 0;
    for (final e in live) {
      if (!e.filletable) continue;
      if (concave ? !e.isConcave : !e.isConvex) continue;
      if (pickedEdgeIds.contains(e.index)) continue;
      pickedEdgeIds.add(e.index);
      pickedEdges.add(EdgeSel(e.mx, e.my, e.mz, e.length, e.kind, e.radius));
      // No display index: these were not picked in the viewport, so they
      // cannot be highlighted. -1 is honest; _edgeAccentPayload skips it.
      pickedEdgeDisplay.add(-1);
      pickedEdgeSet.add(activeEdgeSet);
      added++;
    }
    if (concave) {
      s.allFillets = true;
    } else {
      s.allRounds = true;
    }
    toast(added == 0
        ? (concave
            ? L.current.msgNoInteriorEdgesLeft
            : L.current.msgNoExteriorEdgesLeft)
        : (concave
            ? L.current.msgAddedInteriorEdges(added)
            : L.current.msgAddedExteriorEdges(added)));
    _updateEdgeFeaturePreview();
    notifyListeners();
  }

  /// How many edges are in set [i].
  int edgesInSet(int i) => pickedEdgeSet.where((x) => x == i).length;

  /// Body NAME the current edge set belongs to, captured at pick time.
  ///
  /// Recorded separately because [pickedEdgeSolid] is held by identity and a
  /// recompute replaces the instance — and `_bodyNameOfSolid` cannot name the
  /// old one afterwards either, since it matches by identity too. Keeping the
  /// name is the only thing that survives, and it is what decides whether a
  /// later pick is the SAME body or a different one.
  String? pickedEdgeBodyName;

  /// The solid the current edge set was picked from. Held by identity, like
  /// hoverFace, because a rebuild replaces the object.
  KernelSolid? pickedEdgeSolid;

  /// B-Rep edge under the pointer while [pickingEdges]: (solid, display
  /// index).
  ///
  /// NOT `hoverEdge` — that name was already taken by the 2D sketcher's
  /// polyline-segment hover, an `(int, int)?` of (entity, point). The
  /// collision compiled as a duplicate definition and silently retyped every
  /// existing assignment, which is exactly the kind of thing a grep for
  /// "does this already exist" catches and a balance check does not.
  (KernelSolid, int)? hoverEdge3d;

  void setHoverEdge3d(KernelSolid? solid, int display) {
    if (solid == null) {
      if (hoverEdge3d == null) return;
      hoverEdge3d = null;
    } else {
      if (hoverEdge3d != null &&
          identical(hoverEdge3d!.$1, solid) &&
          hoverEdge3d!.$2 == display) {
        return; // unchanged — do not repaint once per frame
      }
      hoverEdge3d = (solid, display);
    }
    notifyListeners();
  }

  void beginPickEdges() {
    pickingEdges = true;
    toast(L.current.msgSelectEdges);
    notifyListeners();
  }

  void cancelPickEdges() {
    if (!pickingEdges && pickedEdges.isEmpty) return;
    pickingEdges = false;
    pickedEdges.clear();
    pickedEdgeIds.clear();
    pickedEdgeDisplay.clear();
    pickedEdgeSet.clear();
    activeEdgeSet = 0;
    pickedEdgeSolid = null;
    pickedEdgeBodyName = null;
    hoverEdge3d = null;
    notifyListeners();
  }

  /// Inventor's edge selection is a toggle: tapping a selected edge removes
  /// it. Matching is by topological id, which is stable for as long as the
  /// solid this selection was made against is alive.
  void toggleEdgePick(int topoId, EdgeSel sel,
      {KernelSolid? solid, int display = -1}) {
    if (!pickingEdges) return;
    // M164 — WHICH edge was tapped. Without this the log jumped straight from
    // "Select edges" to "chamfer created ... edges=2" with nothing in between,
    // so a chamfer on the wrong edge could not be told from a wrong PICK.
    Log.i(
        'edge',
        'pick edge $topoId  r=${sel.radius.toStringAsFixed(4)} '
            'l=${sel.length.toStringAsFixed(3)} k=${sel.kind} '
            'm=(${sel.mx.toStringAsFixed(3)},${sel.my.toStringAsFixed(3)},'
            '${sel.mz.toStringAsFixed(3)}) '
            'body=${solid == null ? "?" : _bodyNameOfSolid(solid)}');
    // One body per feature: Inventor's fillet operates on a single solid, and
    // a set spanning two would have no meaningful base to modify. Switching
    // body starts a new set rather than silently mixing them.
    //
    // Compared by BODY NAME, not by object identity: a recompute replaces the
    // KernelSolid instance, and an identity test would then read "different
    // body" and silently throw away everything the user had selected.
    final newName = solid == null ? null : _bodyNameOfSolid(solid);
    final sameBody = newName != null && newName == pickedEdgeBodyName;
    final switching = solid != null &&
        pickedEdgeSolid != null &&
        !identical(pickedEdgeSolid, solid) &&
        !sameBody;
    if (switching) {
      pickedEdges.clear();
      pickedEdgeIds.clear();
      pickedEdgeDisplay.clear();
      pickedEdgeSet.clear();
      pickedEdgeBodyName = null;
      activeEdgeSet = 0; // the old sets are gone; do not keep pointing past them
    }
    if (solid != null) {
      pickedEdgeSolid = solid;
      if (newName != null) pickedEdgeBodyName = newName;
    }
    final i = pickedEdgeIds.indexOf(topoId);
    if (i >= 0) {
      pickedEdgeIds.removeAt(i);
      pickedEdges.removeAt(i);
      if (i < pickedEdgeDisplay.length) pickedEdgeDisplay.removeAt(i);
      if (i < pickedEdgeSet.length) pickedEdgeSet.removeAt(i);
    } else {
      pickedEdgeIds.add(topoId);
      pickedEdges.add(sel);
      pickedEdgeDisplay.add(display);
      pickedEdgeSet.add(activeEdgeSet);
    }
    // M126 — WITHOUT this the panel froze: _openEdgeFeature computes the
    // preview once with zero edges, so previewError stayed at "Select at
    // least one edge" no matter how many you then tapped. That kept OK greyed
    // out and the warning on screen, and no preview was ever built.
    _updateEdgeFeaturePreview();
    notifyListeners();
  }

  bool edgeIsPicked(int topoId) => pickedEdgeIds.contains(topoId);

  void beginPickBody() {
    if (extrudeSession == null) return;
    pickingBody = true;
    hoverBody = null;
    // The browser's own prehighlight steps aside: while a pick is armed the
    // hover belongs to the dialog, and two lit bodies would be one too many.
    browserHoverBody = null;
    toast(L.current.msgSelectTargetBody);
    notifyListeners();
  }

  void cancelPickBody() {
    if (!pickingBody && hoverBody == null) return;
    pickingBody = false;
    hoverBody = null;
    final s = extrudeSession;
    final back = _hoverBodyRestore;
    _hoverBodyRestore = null;
    if (s != null && back != null && s.bodyName != back) {
      s.bodyName = back; // hovering must not change the target by itself
      _updateExtrudePreview();
    }
    notifyListeners();
  }

  /// M100 — hovering a candidate body re-previews the extrusion AGAINST it.
  ///
  /// The first attempt tinted the hovered body with the preview material, on
  /// top of the extrusion preview that was already drawn — two overlapping
  /// highlights that read as a mess. What the user actually wants to see is
  /// the ANSWER: hover Solid1 and you see the result of joining into Solid1,
  /// hover Solid2 and you see that instead. So the session's target is moved
  /// to the hovered body and the preview recomputed; leaving the hover puts
  /// the committed target back.
  void setHoverBody(String? name) {
    if (!pickingBody || hoverBody == name) return;
    hoverBody = name;
    final s = extrudeSession;
    if (s != null) {
      _hoverBodyRestore ??= s.bodyName;
      s.bodyName = name ?? _hoverBodyRestore!;
      _updateExtrudePreview();
    }
    notifyListeners();
  }

  /// The target the session had before hovering started, so leaving the hover
  /// without picking does not silently retarget the feature.
  String? _hoverBodyRestore;

  /// Commits the pick. Joining onto a body implies the Join output, so
  /// choosing one switches the mode rather than leaving a target set on a
  /// New Solid — which would silently do nothing.
  void pickBody(String name) {
    final s = extrudeSession;
    if (s == null) return;
    pickingBody = false;
    hoverBody = null;
    _hoverBodyRestore = null; // this pick IS the new target
    // M257 — and it ENDS the automatic one. Same rule as M256's Output lock:
    // the suggestion is where you start, never an argument with the user.
    s.bodyLocked = true;
    if (s.output == 'new') s.output = 'join';
    s.bodyName = name;
    Log.i('extrude', 'target body picked: $name');
    _updateExtrudePreview();
    notifyListeners();
  }

  // ---- freehand spline session (M87) ----
  FreehandSession? freehand;

  /// Snap tolerance for the freehand ends, in world mm — a few pixels at the
  /// current zoom, so it feels the same however far you are zoomed in.
  double get freehandSnapTol => (12.0 / (zoom <= 0 ? 1 : zoom)).clamp(0.05, 50.0);

  /// Existing sketch points the freehand ends may snap to (endpoints and
  /// centres of the visible geometry on the editable layer).
  List<Offset> freehandSnapTargets() {
    final s = current;
    if (s == null) return const [];
    final out = <Offset>[];
    for (final g in displayGeometry(s)) {
      for (final q in sketchCurve(g)) {
        out.add(q);
      }
    }
    return out;
  }

  /// The pointer went down with the freehand tool armed.
  void freehandBegin(Offset w) {
    if (tool != Tool.splineFree || !inEditMode) return;
    freehand = FreehandSession()..raw.add(w);
    toolPoints.clear();
    notifyListeners();
  }

  /// The pointer moved while drawing. Samples closer than a hair are dropped
  /// here already, so a resting hand cannot grow the stroke without bound.
  void freehandExtend(Offset w) {
    final f = freehand;
    if (f == null || !f.drawing) return;
    if (f.raw.isNotEmpty && (f.raw.last - w).distance < 1e-6) return;
    f.raw.add(w);
    notifyListeners();
  }

  /// The pointer lifted: stop recording and open the dialog on the fit.
  /// A stroke too short to be a curve (a stray tap) is discarded silently
  /// rather than opening a dialog over nothing.
  void freehandEnd() {
    final f = freehand;
    if (f == null || !f.drawing) return;
    f.drawing = false;
    if (dedupeStroke(f.raw).length < 2) {
      freehand = null;
      toolPoints.clear();
      notifyListeners();
      return;
    }
    freehandRefit();
  }

  /// Re-fits the raw stroke with the session's current parameters and puts the
  /// result into [toolPoints].
  ///
  /// That is the whole trick: the preview painter and `_commitTool` both read
  /// toolPoints, so the freehand curve travels the ORDINARY tool pipeline —
  /// layer stamping, constraint inference, undo — with no special case, and
  /// the preview is by construction exactly what will be committed.
  void freehandRefit() {
    final f = freehand;
    if (f == null) return;
    final fit = fitFreehandStroke(
      f.raw,
      points: f.points,
      smoothing: f.smoothing,
      snapClosed: FreehandSession.snapClosed,
      snapToPoints: FreehandSession.snapToPoints,
      snapTargets:
          FreehandSession.snapToPoints ? freehandSnapTargets() : const [],
      snapTol: freehandSnapTol,
    );
    toolPoints
      ..clear()
      ..addAll(fit.points);
    notifyListeners();
  }

  /// Dialog edit → re-fit → repaint. One entry point, so a slider can never
  /// leave the preview and the pending geometry out of step.
  void freehandNotify() => freehandRefit();

  /// Finish (the ✓ or Enter): commit through the normal tool path.
  void freehandCommit() {
    final s = current;
    final f = freehand;
    if (s == null || f == null) return;
    if (toolPoints.length < kFreehandMinPoints) {
      freehandCancel();
      return;
    }
    _commitTool(s);
    freehand = null;
    toolPoints.clear();
    notifyListeners();
  }

  /// Esc / the dialog's close: throw the ink away, keep the tool armed so the
  /// next stroke starts immediately (Inventor keeps sketch tools running).
  void freehandCancel() {
    freehand = null;
    toolPoints.clear();
    notifyListeners();
  }

  // ---- gear session (M61) ----
  GearSession? gear;
  GearParams lastGearParams = GearParams();
  int lastGearSun = 20, lastGearPlanet = 16, lastGearPlanetCount = 4;

  /// The ribbon's Gear button. Toggles the modeless Gear dialog / tool.
  void toggleGear() {
    if (gear != null || tool == Tool.gear) {
      cancelTool();
    } else {
      selectTool(Tool.gear);
    }
  }

  /// The dialog mutates [gear] and calls this to repaint the live preview
  /// (dialog swatch + viewport ghost) and remember the last-used values.
  void gearNotify() {
    final g = gear;
    if (g != null) {
      lastGearParams = g.params.copy();
      lastGearSun = g.sunTeeth;
      lastGearPlanet = g.planetTeeth;
      lastGearPlanetCount = g.planetCount;
    }
    notifyListeners();
  }

  /// Places the gear the dialog describes at [GearSession.center]. Called by a
  /// viewport tap (which sets the centre) and by the dialog's Insert button.
  /// Atomic, exactly like [commitPattern]: geometry + constraints are appended
  /// then solved on a copy; a failure rolls the constraints back so the sketch
  /// is never left in a diverged state.
  bool commitGear() {
    final s = current;
    final g = gear;
    final lay = editingLayer;
    if (s == null || g == null || lay == null) return false;
    if (!g.placedOnce) {
      toast(L.current.msgTapToPlaceGear);
      return false;
    }
    final ok = g.kind == GearKind.planetary
        ? _commitPlanetaryGear(s, g, lay)
        : _commitSingleGear(s, g, lay);
    if (ok) {
      gearNotify(); // remember the values
      gear = null;
      tool = Tool.none;
      notifyListeners();
    }
    return ok;
  }

  /// One dimension helper for the gear skeleton: makes a driving dimension with
  /// a fresh parameter name and adds it to [s].
  Constraint _gearDim(SketchModel s, String kind, List<PRef> pts, double value,
      Offset textPos,
      {List<int> ents = const []}) {
    final c = Constraint(CType.dimension,
        dimKind: kind, pts: pts, ents: ents, value: value, textPos: textPos);
    c.paramName = _newParamName(s);
    s.constraints.add(c);
    return c;
  }

  /// A single external / internal gear: the rim + a centred horizontal &
  /// vertical construction cross + a rotation reference line (+ optional bore),
  /// wired so the sketch gains exactly THREE degrees of freedom — centre x,
  /// centre y and orientation. The user then dimensions the middle point and
  /// one angle to fully constrain it.
  bool _commitSingleGear(SketchModel s, GearSession g, String lay) {
    final p = g.params.copy()..internal = g.kind == GearKind.internal;
    if (!p.valid) {
      toast(p.internal
          ? L.current.msgInternalGearTeeth
          : L.current.msgGearTeeth);
      return false;
    }
    final center = g.center;
    final ang = g.angleRad;
    final rp = p.pitchRadius;
    final crossHalf = 1.15 * p.outerRadius; // cross overhangs the tips a little
    final crossLen = 2 * crossHalf;
    final dir = Offset(math.cos(ang), math.sin(ang));
    final handle = center + dir * rp;

    final gs = List<Geo>.from(s.geometry);
    final consBefore = s.constraints.length;

    final rim = buildGearGeo(center, ang, p, layer: lay);
    final rimIdx = gs.length;
    gs.add(rim);

    Geo constr(List<double> d) =>
        Geo(Geo.line, d, layer: lay, style: Geo.styleConstruction);
    final hlIdx = gs.length;
    gs.add(constr(
        [center.dx - crossHalf, center.dy, center.dx + crossHalf, center.dy]));
    final vlIdx = gs.length;
    gs.add(constr(
        [center.dx, center.dy - crossHalf, center.dx, center.dy + crossHalf]));
    final rlIdx = gs.length;
    gs.add(constr([center.dx, center.dy, handle.dx, handle.dy]));

    int? boreIdx;
    if (p.bore > 1e-6) {
      boreIdx = gs.length;
      gs.add(Geo(Geo.circle, [center.dx, center.dy, p.bore / 2], layer: lay));
    }

    // rigid skeleton (see class docs) — 13 equations over 16 params -> 3 DOF
    s.constraints
      ..add(Constraint(CType.midpoint,
          pts: [PRef(rimIdx, 0)], ents: [hlIdx]))
      ..add(Constraint(CType.horizontal, ents: [hlIdx]))
      ..add(Constraint(CType.midpoint,
          pts: [PRef(rimIdx, 0)], ents: [vlIdx]))
      ..add(Constraint(CType.vertical, ents: [vlIdx]))
      ..add(Constraint(CType.coincident,
          pts: [PRef(rlIdx, 0), PRef(rimIdx, 0)]))
      ..add(Constraint(CType.coincident,
          pts: [PRef(rlIdx, 1), PRef(rimIdx, 1)]))
      ..add(Constraint(CType.equal, ents: [hlIdx, vlIdx]));
    // the gear's two own driving dimensions: pitch radius (pins the handle /
    // rotation line length) and the cross size.
    _gearDim(s, 'dist', [PRef(rimIdx, 0), PRef(rimIdx, 1)], rp,
        center + dir * (rp * 0.5));
    _gearDim(s, 'dist', [PRef(hlIdx, 0), PRef(hlIdx, 1)], crossLen,
        Offset(center.dx, center.dy - crossHalf - 3));
    if (boreIdx != null) {
      s.constraints.add(Constraint(CType.coincident,
          pts: [PRef(boreIdx, 0), PRef(rimIdx, 0)]));
      _gearDim(s, 'rad', const [], p.bore / 2,
          center + const Offset(0, 0), ents: [boreIdx]);
    }

    if (!_solveAndRebuild(s, gs)) {
      s.constraints.removeRange(consBefore, s.constraints.length);
      toast(L.current.msgCouldNotPlaceGear);
      notifyListeners();
      return false;
    }
    Log.i('gear',
        '${p.internal ? "internal" : "external"} gear z${p.teeth} m${p.module} on "$lay"');
    toast(p.internal
        ? L.current.msgInternalGearPlaced
        : L.current.msgExternalGearPlaced);
    return true;
  }

  /// A planetary set: sun (with the full cross + rotation skeleton), N planets
  /// on a carrier circle (each on a spoke from the centre), and a ring, phased
  /// so the teeth mesh. The whole assembly is one rigid body with three DOF
  /// (system centre + orientation). Degrades gracefully: if the constrained
  /// system cannot be solved, the gears are still placed (unconstrained) so the
  /// user gets geometry rather than nothing.
  bool _commitPlanetaryGear(SketchModel s, GearSession g, String lay) {
    if (g.planetTeeth < 4 || g.sunTeeth < 4 || g.planetCount < 2) {
      toast(L.current.msgPlanetaryNeeds);
      return false;
    }
    final layout = buildPlanetaryLayout(
      base: g.params,
      sunTeeth: g.sunTeeth,
      planetTeeth: g.planetTeeth,
      planetCount: g.planetCount,
      systemAngle: g.angleRad,
    );
    if (!layout.sun.params.valid || !layout.ring.params.valid) {
      toast(L.current.msgPlanetaryUndrawable);
      return false;
    }
    final center = g.center;
    final ang = g.angleRad;
    final gs = List<Geo>.from(s.geometry);
    final consBefore = s.constraints.length;

    Geo constr(List<double> d) =>
        Geo(Geo.line, d, layer: lay, style: Geo.styleConstruction);

    // --- sun with its full single-gear skeleton (provides the 3 system DOF) ---
    final sunP = layout.sun.params;
    final rpSun = sunP.pitchRadius;
    final crossHalf = 1.05 * layout.ring.params.outerRadius;
    final crossLen = 2 * crossHalf;
    final dir = Offset(math.cos(ang), math.sin(ang));
    final sunHandle = center + dir * rpSun;
    final sunIdx = gs.length;
    gs.add(buildGearGeo(center, ang, sunP, layer: lay));
    final hlIdx = gs.length;
    gs.add(constr(
        [center.dx - crossHalf, center.dy, center.dx + crossHalf, center.dy]));
    final vlIdx = gs.length;
    gs.add(constr(
        [center.dx, center.dy - crossHalf, center.dx, center.dy + crossHalf]));
    final rlIdx = gs.length;
    gs.add(constr([center.dx, center.dy, sunHandle.dx, sunHandle.dy]));

    // --- ring: concentric to the sun, orientation locked to the sun ---
    final ringP = layout.ring.params;
    final ringIdx = gs.length;
    gs.add(buildGearGeo(center, ang, ringP, layer: lay));

    // --- carrier circle (construction) through the planet centres ---
    final carrierIdx = gs.length;
    gs.add(Geo(Geo.circle, [center.dx, center.dy, layout.carrierRadius],
        layer: lay, style: Geo.styleConstruction));

    // --- planets, each on a spoke from the centre ---
    final planetIdx = <int>[];
    final spokeIdx = <int>[];
    final planets = layout.planets.toList();
    for (var i = 0; i < planets.length; i++) {
      final pl = planets[i];
      final pc = center + pl.center; // pl.center is relative to the system
      final pIdx = gs.length;
      gs.add(buildGearGeo(pc, pl.angle, pl.params, layer: lay));
      planetIdx.add(pIdx);
      final sIdx = gs.length;
      gs.add(constr([center.dx, center.dy, pc.dx, pc.dy]));
      spokeIdx.add(sIdx);
    }

    // ---- constraints ----
    s.constraints
      ..add(Constraint(CType.midpoint, pts: [PRef(sunIdx, 0)], ents: [hlIdx]))
      ..add(Constraint(CType.horizontal, ents: [hlIdx]))
      ..add(Constraint(CType.midpoint, pts: [PRef(sunIdx, 0)], ents: [vlIdx]))
      ..add(Constraint(CType.vertical, ents: [vlIdx]))
      ..add(Constraint(CType.coincident, pts: [PRef(rlIdx, 0), PRef(sunIdx, 0)]))
      ..add(Constraint(CType.coincident, pts: [PRef(rlIdx, 1), PRef(sunIdx, 1)]))
      ..add(Constraint(CType.equal, ents: [hlIdx, vlIdx]));
    _gearDim(s, 'dist', [PRef(sunIdx, 0), PRef(sunIdx, 1)], rpSun,
        center + dir * (rpSun * 0.5));
    _gearDim(s, 'dist', [PRef(hlIdx, 0), PRef(hlIdx, 1)], crossLen,
        Offset(center.dx, center.dy - crossHalf - 3));
    // ring: centre on the sun centre, handle on the sun's rotation line
    s.constraints
      ..add(Constraint(CType.coincident,
          pts: [PRef(ringIdx, 0), PRef(sunIdx, 0)]))
      ..add(Constraint(CType.coincident,
          pts: [PRef(ringIdx, 1)], ents: [rlIdx]));
    _gearDim(s, 'dist', [PRef(ringIdx, 0), PRef(ringIdx, 1)],
        ringP.pitchRadius, center + dir * (ringP.pitchRadius * 0.5));
    // carrier circle: concentric to the sun, radius = centre distance
    s.constraints.add(Constraint(CType.coincident,
        pts: [PRef(carrierIdx, 0), PRef(sunIdx, 0)]));
    _gearDim(s, 'rad', const [], layout.carrierRadius,
        center + Offset(layout.carrierRadius, 0),
        ents: [carrierIdx]);
    // each planet: spoke from centre to planet centre, planet centre on the
    // Each planet is tied to the system as a RIGID TRIANGLE (sun centre,
    // planet centre, planet handle) whose three pairwise distances are pinned:
    // the triangle rotates with the assembly, so the planet both orbits AND
    // keeps its meshing phase — its tooth 0 stays put relative to the sun.
    for (var i = 0; i < planetIdx.length; i++) {
      final pIdx = planetIdx[i], sIdx = spokeIdx[i];
      final phi = layout.planetCarrierAngles[i];
      final phaseDeg = ((phi - ang) * 180 / math.pi);
      final pl = planets[i];
      final pc = center + pl.center;
      final planetHandle =
          pc + Offset(math.cos(pl.angle), math.sin(pl.angle)) * pl.params.pitchRadius;
      final sunToHandle = (planetHandle - center).distance;
      s.constraints
        ..add(Constraint(CType.coincident,
            pts: [PRef(sIdx, 0), PRef(sunIdx, 0)])) // spoke starts at centre
        ..add(Constraint(CType.coincident,
            pts: [PRef(pIdx, 0), PRef(sIdx, 1)])); // planet centre = spoke end
      _gearDim(s, 'dist', [PRef(sIdx, 0), PRef(sIdx, 1)], layout.carrierRadius,
          pc); // spoke length = centre distance
      // triangle side 2: planet handle radius (planet centre → handle)
      _gearDim(s, 'dist', [PRef(pIdx, 0), PRef(pIdx, 1)], pl.params.pitchRadius,
          (pc + planetHandle) / 2);
      // triangle side 3: sun centre → planet handle — locks the planet's
      // orientation (and thus the mesh phase) without forcing it radial
      _gearDim(s, 'dist', [PRef(sunIdx, 0), PRef(pIdx, 1)], sunToHandle,
          (center + planetHandle) / 2);
      // spoke angle from the rotation line ties the triangle's rotation to the
      // system orientation. The first planet's spoke is collinear with the
      // rotation line (phase 0) — an angle dimension there would be degenerate,
      // so it gets a parallel constraint instead (same one equation).
      final phaseMod = phaseDeg.abs() % 360;
      if (phaseMod < 0.5 || phaseMod > 359.5) {
        s.constraints.add(Constraint(CType.parallel, ents: [rlIdx, sIdx]));
      } else {
        s.constraints.add(Constraint(CType.dimension,
            dimKind: 'ang',
            ents: [rlIdx, sIdx],
            value: phaseDeg,
            textPos: center + dir * (layout.carrierRadius * 0.7))
          ..paramName = _newParamName(s));
      }
    }

    if (!_solveAndRebuild(s, gs)) {
      // graceful degrade: drop the inter-gear constraints, keep the geometry
      s.constraints.removeRange(consBefore, s.constraints.length);
      _rebuildEngine(s, gs);
      Log.w('gear', 'planetary constraints unsatisfied — placed unconstrained');
      toast(layout.assemblyOk
          ? L.current.msgPlanetaryPlacedFree
          : L.current.msgPlanetaryUneven(g.planetCount));
      return true;
    }
    Log.i('gear',
        'planetary sun${g.sunTeeth} planet${g.planetTeeth}x${g.planetCount} ring${layout.ringTeeth}');
    toast(layout.assemblyOk
        ? L.current.msgPlanetaryPlacedDimension
        : L.current.msgPlanetaryUnevenSpacing(g.planetCount));
    return true;
  }

  // ---- fillet / chamfer session (M36) ----
  FilletSession? filletSess;
  double lastFilletRadius = 5;
  int lastChamferMode = 0;
  double lastChamferD1 = 5, lastChamferD2 = 5, lastChamferAngle = 45;

  /// The dialog mutates the session and calls this: remembers the values,
  /// mirrors them into [toolParams] (the preview reads those), restarts the
  /// equal-chain when a value changed, repaints.
  /// M207 — the modeless Polygon window changed the side count. Same shape as
  /// [filletNotify]: fold it into toolParams (which the preview and the commit
  /// both read) and repaint, so the rubber band shows the new polygon before
  /// the next pick rather than after it.
  void polygonSidesNotify(double sides) {
    toolParams = {...toolParams, 'sides': sides};
    notifyListeners();
  }

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
    // M371 — Esc puts Measure away, and it goes FIRST because it is the one
    // command that can be running in a document with no Tool armed at all: a
    // fall-through would have reached `selection.clear()` at the bottom and
    // cleared the user's selection instead of the panel they were looking at.
    //
    // Guarded on the session rather than unconditional, so Esc keeps meaning
    // exactly what it meant everywhere else.
    if (measureSession != null) {
      measureSession = null;
      notifyListeners();
      return;
    }
    // A pattern dialog cancels as a WHOLE (Inventor: Esc = Cancel) — no
    // pick-chain step-back like the drawing tools.
    if (pattern != null) {
      pattern = null;
      tool = Tool.none;
      notifyListeners();
      return;
    }
    // The gear dialog cancels as a whole too (Esc = Cancel).
    if (gear != null) {
      gear = null;
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
    final hadPicks = toolPoints.isNotEmpty ||
        conPts.isNotEmpty ||
        conEnts.isNotEmpty ||
        modEntity != null;
    toolPoints.clear();
    conPts.clear();
    conEnts.clear();
    conEntClicks.clear();
    conEdges.clear();
    modEntity = null;
    _hudResetAll();
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
    Log.i(
        'click',
        'toolClick tool=$tool sketch=${s?.name} '
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
    if (tool == Tool.gear) {
      // A tap places the gear centre here and commits (the dialog stays open
      // only for editing an existing gear). Snapping already resolved [w].
      final g = gear;
      if (g != null) {
        g.center = w;
        g.placedOnce = true;
        commitGear();
      }
      notifyListeners();
      return;
    }
    // HUD / Dynamic Input: fold any typed value into a lock, record this
    // phase's locked quantities for the commit-time dimensions, snap the point
    // to honour the locks, then clear the per-phase input for the next point.
    if (hudActive) {
      final typed = Fmt.num(hudInput);
      if (typed != null) hudLocked[hudFocus] = typed;
      hudInput = '';
      _hudAccumulate();
      w = hudApply(w);
      _hudResetPhase();
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
  /// Entities an offset chain may run through (Inventor's Loop Select): LINE
  /// and ARC on the editing layer, never projected reference geometry — the
  /// same scope as picking/selection. Circles, splines, ellipses and single
  /// polylines are whole shapes and offset on their own.
  Set<int> _chainEligible(SketchModel s) => {
        for (var i = 0; i < s.geometry.length; i++)
          if ((s.geometry[i].type == Geo.line ||
                  s.geometry[i].type == Geo.arc) &&
              geoEditable(s.geometry[i]) &&
              !s.geometry[i].isProjection)
            i
      };

  /// Nearest pickable entity to [w], or null.
  ///
  /// Linear over the whole sketch, called from ~12 sites on the tap and drag
  /// paths (several of them more than once per event). The span answers
  /// whether that linearity is affordable at the sketch sizes we actually
  /// have, before anyone reaches for a spatial index.
  int? _pickEntity(SketchModel s, Offset w) =>
      Perf.span('2d.pickEntity', () => _pickEntityInner(s, w));

  int? _pickEntityInner(SketchModel s, Offset w) {
    var best = -1;
    var bd = 10 / zoom;
    // A TIE goes to normal geometry. After a kept-carrier trim (M187) every
    // piece lies exactly on top of its construction carrier, and the carrier
    // has the lower index — without this, every tap on the visible line would
    // land on the dashed ghost underneath it.
    const tie = 1e-6;
    for (var i = 0; i < s.geometry.length; i++) {
      if (!geoEditable(s.geometry[i])) continue; // other layers are read-only
      final d = distToEntity(s.geometry[i], w);
      final wins = d < bd - tie ||
          (d < bd + tie &&
              best >= 0 &&
              s.geometry[best].isConstruction &&
              !s.geometry[i].isConstruction);
      if (wins) {
        bd = math.min(bd, d);
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

  /// Model edges projectable into the sketch being edited, already flattened
  /// onto its plane. Empty outside a part sketch. Rebuilt on demand and cached
  /// per (part rev, plane) by [projectableEdges].
  List<PartEdge> _projEdges = const [];
  String _projEdgesKey = '';

  /// The 3D edges the Project tool can pick right now. Cached because both the
  /// hover highlight (every pointer move) and the tap go through it, and
  /// flattening a gear's ~440 edges per frame is exactly the kind of
  /// per-frame O(geometry) work that made sketching stutter (see M75).
  List<PartEdge> projectableEdges() {
    Perf.count('project.edgesQuery');
    final part = currentPart;
    final cs = _activeChildSketch();
    if (part == null || cs == null) return const [];
    final fr = sketchFrameOf(cs);
    // M211 — the AXES belong in the key, not just the origin. Every sketch on
    // a face carries key 'face', and a face's origin is the plane's closest
    // point to the world origin, so the two faces of a plate at z=0 — one
    // n=+Z, one n=-Z — agreed on both. Switching between them reused the first
    // one's flattened edges, which are the second one's mirrored.
    final k = StringBuffer()
      ..write(fr.key)
      ..write(fr.origin.x)
      ..write(',')
      ..write(fr.origin.y)
      ..write(',')
      ..write(fr.origin.z)
      ..write('/')
      ..write(fr.u.x)
      ..write(',')
      ..write(fr.u.y)
      ..write(',')
      ..write(fr.u.z)
      ..write('/')
      ..write(fr.n.x)
      ..write(',')
      ..write(fr.n.y)
      ..write(',')
      ..write(fr.n.z);
    for (final f in part.features) {
      k
        ..write(';')
        ..write(f.name)
        ..write(f.visible ? '1' : '0')
        ..write(f.consumedByJoin ? 'c' : '-')
        ..write(f.solid == null ? 'n' : identityHashCode(f.solid!.mesh));
    }
    final key = k.toString();
    if (key != _projEdgesKey) {
      _projEdgesKey = key;
      _projEdges = partEdges(part, fr);
    }
    return _projEdges;
  }

  /// Model edge under the cursor while the Project tool is active, for the
  /// hover highlight. Null when nothing is close enough.
  int? projectHoverEdge(Offset w) {
    if (tool != Tool.project) return null;
    final edges = projectableEdges();
    if (edges.isEmpty) return null;
    return pickPartEdge(edges, w, 8 / zoom);
  }

  /// M279 — the part-wide edge indices of the model FACE under [w], or empty.
  ///
  /// Inventor's Project Geometry takes a face and projects every edge of its
  /// boundary — the outer loop and every inner one, so a plate with four holes
  /// comes across as the outline plus four circles in a single pick. This is
  /// the query behind that; see face_project.dart for how "the edges of this
  /// face" is derived without a new kernel entry point.
  List<int> projectHoverFace(Offset w) {
    if (tool != Tool.project) return const [];
    final part = currentPart;
    final cs = _activeChildSketch();
    if (part == null || cs == null) return const [];
    final ref = faceUnderPoint(part, sketchFrameOf(cs), w);
    if (ref == null) return const [];
    return partEdgeIndicesForFace(part, ref);
  }

  /// The ChildSketch currently being edited, or null.
  ChildSketch? _activeChildSketch() {
    final part = currentPart;
    final child = activeChild;
    if (part == null || child == null) return null;
    for (final c in part.childSketches) {
      if (identical(c.model, child) || c.model.name == child.name) return c;
    }
    return null;
  }

  void _projectClick(SketchModel s, Offset w) {
    final lay = editingLayer;
    if (lay == null) return;
    // A 3D model edge wins over sketch geometry only when nothing in the
    // sketch is closer, so projecting inside the sketch keeps working exactly
    // as before.
    final picked = pickVisibleAny(s, w);
    if (picked == null) {
      final hit = pickPartEdge(projectableEdges(), w, 8 / zoom);
      if (hit != null) {
        _projectSolidEdge(s, hit, lay);
        return;
      }
      // M279 — no edge under the cursor, but a FACE is: project all of it.
      //
      // AFTER the edge test, which is Inventor's order and the only one that
      // works: an edge lies ON the faces it bounds, so a face pick would
      // swallow every edge pick if it went first, and there would be no way to
      // project a single edge of a face at all.
      final faceEdges = projectHoverFace(w);
      if (faceEdges.isNotEmpty) {
        _projectSolidEdges(s, faceEdges, lay);
        return;
      }
    }
    int? src;
    var seg = -1;
    Geo? proto;
    if (picked != null) {
      final g = s.geometry[picked];
      if (g.layer == lay) {
        toast(g.isProjection
            ? L.current.msgAlreadyProjected
            : L.current.msgProjectPicksOtherLayers);
        return;
      }
      src = picked;
      if (g.type == Geo.polyline && !g.isSpline) {
        // a rectangle/polygon side projects as ONE LINE (Inventor projects
        // the clicked edge, not the loop) — resolved at the click (M34)
        final e = polySegmentAt(s, picked, w);
        if (e == null) {
          toast(L.current.msgTapPolygonEdge);
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
        toast(L.current.msgTapGeometryOtherLayer);
        return;
      }
    }
    for (final g in s.geometry) {
      if (g.isProjection &&
          g.proj == src &&
          g.projSeg == seg &&
          g.layer == lay) {
        toast(L.current.msgAlreadyProjected);
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
        s.engine.addPolyline([
          for (var i = 0; i < n; i++) ...[d[2 + 2 * i], d[3 + 2 * i]]
        ], closed: d[0] != 0);
        break;
    }
    _committed(s, tags: tags);
    _solveAndRebuild(s);
    Log.i(
        'project',
        'projected ${src >= 0 ? "entity $src (${proto.type})" : src == Geo.projAxisX ? "X axis" : "Y axis"} onto "$lay"');
  }

  /// Creates the reference curve for model edge [edgeIndex] on [lay].
  bool _isSolidEdgeProjected(SketchModel s, int edgeIndex, String lay) {
    for (final g in s.geometry) {
      if (g.proj == Geo.projSolid &&
          g.projSeg == edgeIndex &&
          g.layer == lay) {
        return true;
      }
    }
    return false;
  }

  /// Builds the sketch entity for model edge [edgeIndex] and adds it to [s]'s
  /// engine. Returns the tag to append, or null when there is nothing to add.
  ///
  /// M279 — split out of [_projectSolidEdge] so a FACE can add all of its
  /// edges before anything commits. Projecting a face by calling the
  /// single-edge command in a loop would put one undo step and one full solve
  /// on EVERY edge: a plate with four holes would be five solves and five
  /// steps to undo, and half a face would be a reachable state.
  Geo? _buildSolidEdge(
      SketchModel s, int edgeIndex, String lay, List<PartEdge> edges) {
    PartEdge? src;
    for (final e in edges) {
      if (e.index == edgeIndex) {
        src = e;
        break;
      }
    }
    if (src == null) return null;
    if (src.kind == ProjKind.polyline && src.pts.length < 2) return null;
    // EXACT form: a projected circle becomes a circle, an arc an arc, a
    // tilted circle a true ellipse. Only a kernel edge with no analytic
    // record falls back to a polyline.
    final copy = geoForPartEdge(src, lay);
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
      default: // plain polyline OR the 3-vertex ellipse tag
        final n = d[1].toInt();
        s.engine.addPolyline([
          for (var i = 0; i < n; i++) ...[d[2 + 2 * i], d[3 + 2 * i]]
        ], closed: d[0] != 0);
    }
    return copy;
  }

  void _projectSolidEdge(SketchModel s, int edgeIndex, String lay) {
    if (_isSolidEdgeProjected(s, edgeIndex, lay)) {
      toast(L.current.msgAlreadyProjected);
      return;
    }
    final copy = _buildSolidEdge(s, edgeIndex, lay, projectableEdges());
    if (copy == null) return;
    _committed(s, tags: List<Geo>.of(s.geometry)..add(copy));
    _solveAndRebuild(s);
    Log.i('project', 'projected model edge $edgeIndex onto "$lay"');
  }

  /// M279 — every edge of a picked FACE, in ONE step.
  ///
  /// Edges already on this layer are skipped silently rather than refused: a
  /// face whose outline you projected by hand should still bring its holes
  /// across, and "already projected" is an answer about one edge, not about a
  /// face that is merely partly there.
  void _projectSolidEdges(SketchModel s, List<int> edgeIndices, String lay) {
    final edges = projectableEdges();
    final tags = List<Geo>.of(s.geometry);
    var added = 0;
    for (final i in edgeIndices) {
      if (_isSolidEdgeProjected(s, i, lay)) continue;
      final copy = _buildSolidEdge(s, i, lay, edges);
      if (copy == null) continue;
      tags.add(copy);
      added++;
    }
    if (added == 0) {
      toast(L.current.msgAlreadyProjected);
      return;
    }
    _committed(s, tags: tags);
    _solveAndRebuild(s);
    toast(L.current.msgProjectedFace(added));
    Log.i('project', 'projected $added edges of a face onto "$lay"');
  }


  /// Re-projects every model-edge reference in [p]'s sketches after the
  /// feature tree changed. Inventor's projected geometry is a LINK, not a
  /// copy: change the parent and the projection follows; delete it and the
  /// projection freezes as fixed curves keeping its constraints. Both are
  /// handled by syncSolidProjections.
  void _syncSolidProjections(PartModel p) =>
      Perf.span('project.syncSolid', () => _syncSolidProjectionsInner(p));

  void _syncSolidProjectionsInner(PartModel p) {
    for (final cs in p.childSketches) {
      var gs = List<Geo>.of(cs.model.geometry);
      if (!gs.any((g) => g.proj == Geo.projSolid)) continue;
      // M182 — a sketch a feature builds on must keep its closed loops. The
      // device session ended in "no closed profile in Sketch5/6" because
      // projection updates followed a body whose fold had broken. The guard
      // (a pure function in part_model.dart, so it is host-testable) refuses
      // an update that would drop a loop and freezes the moved segments.
      final consumed = firstConsumerOf(p, cs.model.name) != null;
      final orig = List<Geo>.of(gs);
      if (!syncSolidProjections(gs, p, sketchFrameOf(cs))) continue;
      if (consumed) {
        gs = freezeProjectionUpdatesThatBreakLoops(
            orig,
            gs,
            cs.model.layers,
            cs.model.hiddenLayers,
            cs.model.eosAfter);
      }
      // M88 — the engine holds the REAL geometry; the tag list alone is not
      // enough. syncProjections() gets away with mutating in place only
      // because it runs INSIDE solveConstraints, whose result is then pushed
      // by _rebuildEngine. This runs after a feature rebuild instead, so it
      // has to push itself — without this, editing an extrusion left every
      // curve projected from it frozen at its old shape.
      _rebuildEngine(cs.model, gs);
      cs.model.dirty = true;
    }
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
          toast(L.current.msgProjectedNoPattern);
          return;
        }
        if (!ps.geo.remove(i)) ps.geo.add(i); // tap toggles
        return;
      case PatField.dir1:
      case PatField.dir2:
        final i = _pickEntity(s, w);
        if (i == null || s.geometry[i].type != Geo.line) {
          toast(L.current.msgPickDirectionLine);
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
          toast(L.current.msgPickAxisPoint);
          return;
        }
        ps.axisPt = p;
        return;
      case PatField.mirrorLine:
        final i = _pickEntity(s, w);
        if (i == null || s.geometry[i].type != Geo.line) {
          toast(L.current.msgPickMirrorLine);
          return;
        }
        if (ps.geo.contains(i)) {
          toast(L.current.msgMirrorLineInSelection);
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
  double _patStep(double value, int count, bool fitted,
      {bool wrap360 = false}) {
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
            final d =
                u1 * (s1 * k1) + (u2 == null ? Offset.zero : u2 * (s2 * k2));
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
        final stepDeg = _patStep(ps.angleC, n, ps.fitted, wrap360: full);
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
      toast(L.current.msgSelectGeometryToPattern);
      return false;
    }
    if (ps.kind == Tool.patRect && _patDir(s, ps.dir1Ent, false) == null) {
      toast(L.current.msgPickLineDirection1);
      return false;
    }
    if (ps.kind == Tool.patCirc && ps.axisPt == null) {
      toast(L.current.msgPickPatternAxis);
      return false;
    }
    if (ps.kind == Tool.mirror && _mirrorFn(s, ps.mirrorEnt) == null) {
      toast(L.current.msgPickTheMirrorLine);
      return false;
    }
    if (ps.kind == Tool.mirror && ps.selfSym) {
      return _commitSelfSymmetric(s, ps, keepOpen);
    }
    final fs = _patTransforms(s);
    if (fs.isEmpty) {
      toast(L.current.msgPatternNothingToCreate);
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
    Log.i(
        'pattern',
        '${ps.kind.name}: $made copies of ${srcs.length} entities onto '
            '"$lay" (associative=${ps.associative}, fitted=${ps.fitted})');
    final ok = _solveAndRebuild(s, gs);
    if (!ok) {
      // roll back the constraints this commit appended; the geometry copies
      // were never adopted (gs is local), so the sketch is untouched
      s.constraints.removeRange(consBefore, s.constraints.length);
      toast(L.current.msgPatternUnsatisfiable);
      notifyListeners();
      return false;
    }
    toast(L.current.msgPatternCreated(made));
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
      toast(L.current.msgSelfSymNeedsOneSpline);
      return false;
    }
    final e = ps.geo.first;
    final g = s.geometry[e];
    final isOpenSpline = g.type == Geo.polyline &&
        (g.spline == Geo.splineCv || g.spline == Geo.splineFit) &&
        g.data[0] == 0;
    if (!isOpenSpline) {
      toast(L.current.msgSelfSymNeedsOpenSpline);
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
      toast(L.current.msgSelfSymEndOnMirror);
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
    s.constraints
        .add(Constraint(CType.coincident, pts: [PRef(e, n - 1)], ents: [axis]));
    Log.i('pattern',
        'self-symmetric spline e$e: $n -> ${ext.length} defining points');
    if (!_solveAndRebuild(s, gs)) {
      s.constraints.removeRange(consBefore, s.constraints.length);
      toast(L.current.msgSelfSymUnsatisfiable);
      notifyListeners();
      return false;
    }
    toast(L.current.msgSelfSymDone);
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
      toast(L.current.msgProjectedNoModify);
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
        // M191 — what the cut takes away stays, as CONSTRUCTION geometry, so a
        // trim does not destroy the dimensions and constraints that were on it
        // (the M187 request). Only the cut-away SPAN, not a copy of the whole
        // entity: M187 kept the entity itself and the device session found
        // exactly what that means — "there are construction lines under the
        // real shape but there should only be construction line for the part
        // that was actually cut away", plus a sketch pinned to dof=0 by the
        // binds that held the visible pieces onto that copy. Kept span and
        // cut-away span are complements, so nothing is doubled and the pieces
        // keep the freedom they had.
        final cutStart = gs.length;
        if (old.style != Geo.styleConstruction) {
          gs.addAll(trimCutAway(s.geometry, i, w)
              .where(_notDegenerate)
              .map((g) => g.withStyle(Geo.styleConstruction)));
        }
        // M36: keep every constraint/dimension the trim leaves standing —
        // point refs follow their surviving piece, entity refs land on the
        // nearest piece of the (unchanged) carrier. With the cut-away span in
        // the list as well, a dimension on the removed part now finds geometry
        // to land on instead of being dropped.
        final remapped =
            remapAfterReplace(s.constraints, i, old, gs, piecesStart);
        // Inventor: the NEW endpoints a cut creates are constrained where they
        // landed — onto the cutting entity (point-on-curve) or onto the point
        // they meet. Without this the trimmed pieces are loose and drag apart,
        // which is exactly what the device session showed (trims only ever
        // REMOVED constraints, 55 -> 49).
        //
        // Two passes: the kept pieces bind to the geometry that was already
        // there (the construction leftovers are invisible to that pass, or a
        // cut point would bind to its own leftover instead of to the cutter),
        // then the leftovers bind to what they now touch — which is the kept
        // piece they were cut from, so the ghost follows the shape.
        _bindCutPoints(gs, old, piecesStart, remapped, ignoreFrom: cutStart);
        if (cutStart < gs.length) {
          _bindCutPoints(gs, old, cutStart, remapped);
          _tieLeftovers(gs, piecesStart, cutStart, remapped);
        }
        // Atomic: verify on the remapped copies BEFORE adopting them. A trim
        // whose surviving constraints cannot be satisfied (a remap edge case)
        // must not scramble the sketch — it is refused instead.
        if (!solveConstraints(gs, remapped)) {
          Log.w('modify', 'trim e$i REJECTED — result cannot be satisfied');
          toast(L.current.msgTrimBreaksConstraints);
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
        // constraints survive. M49: on top of that, Inventor's documented
        // Split rules — Horizontal/Vertical/Parallel/Perpendicular/Collinear
        // are inherited by BOTH segments, Equal/Symmetric are broken.
        final remapped =
            remapAfterSplit(s.constraints, i, old, gs, piecesStart);
        // Inventor glues the two halves back together at the split point:
        // both pieces get a coincident there (and onto whatever the split
        // landed on), so a later drag moves them as connected geometry.
        _bindCutPoints(gs, old, piecesStart, remapped);
        if (!solveConstraints(gs, remapped)) {
          Log.w('modify', 'split e$i REJECTED — result cannot be satisfied');
          toast(L.current.msgSplitBreaksConstraints);
          return;
        }
        Log.i('modify',
            'split e$i: constraints ${s.constraints.length} -> ${remapped.length}');
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
        _commitOffset(s, modEntity!, w);
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
        final a1 = math.atan2(toolPoints[1].dy - c.dy, toolPoints[1].dx - c.dx);
        final a2 = math.atan2(toolPoints[2].dy - c.dy, toolPoints[2].dx - c.dx);
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
      final chain =
          offsetChainAt(s.geometry, modEntity!, hover, _chainEligible(s));
      return chain == null ? const [] : chain.offsets;
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

  /// Inventor's Offset (Loop Select + Constrain Offset, both on by default):
  /// offset the WHOLE connected chain the seed belongs to as one operation and
  /// wire it like Inventor — coincident at every offset corner, each offset
  /// line parallel to its source / each offset arc concentric with its source,
  /// and one editable offset distance (d0) that the rest of the run follows, so
  /// the copy holds together and drives uniformly. Atomic: built and verified
  /// on local copies; if the constrained result cannot be solved it degrades to
  /// the bare geometry rather than corrupting the sketch.
  void _commitOffset(SketchModel s, int seed, Offset w) {
    final chain = offsetChainAt(s.geometry, seed, w, _chainEligible(s));
    if (chain == null) {
      toast(L.current.msgNothingToOffset);
      return;
    }
    final n = chain.offsets.length;
    final firstNew = s.geometry.length;
    final gs = List<Geo>.from(s.geometry)..addAll(chain.offsets);
    final cons = List<Constraint>.from(s.constraints);

    // coincident at every corner of the offset run (wrap when closed)
    final links = <(int, int)>[];
    for (var i = 0; i + 1 < n; i++) {
      links.add((i, i + 1));
    }
    if (chain.closed && n >= 2) links.add((n - 1, 0));
    for (final l in links) {
      cons.add(Constraint(CType.coincident, pts: [
        PRef(firstNew + l.$1, chain.exitPt[l.$1]),
        PRef(firstNew + l.$2, chain.enterPt[l.$2]),
      ]));
    }

    // each offset segment tied to its source: parallel (line)/concentric (arc)
    for (var i = 0; i < n; i++) {
      final src = chain.sources[i];
      if (chain.offsets[i].type == Geo.line &&
          s.geometry[src].type == Geo.line) {
        cons.add(Constraint(CType.parallel, ents: [firstNew + i, src]));
      } else if (chain.offsets[i].type == Geo.arc &&
          s.geometry[src].type == Geo.arc) {
        cons.add(Constraint(CType.concentric, ents: [firstNew + i, src]));
      } else if (chain.offsets[i].type == Geo.circle &&
          s.geometry[src].type == Geo.circle) {
        // M124 — a CIRCLE offset used to get nothing: no constraint tying it
        // to its source and no distance dimension, so the copy was loose
        // geometry that drifted on the first drag and could not be driven to
        // a value. It now behaves like the rest of the run: concentric with
        // its source, and the offset distance carried by a gap dimension.
        cons.add(Constraint(CType.concentric, ents: [firstNew + i, src]));
      }
    }

    // the offset DISTANCE: a perpendicular point-to-source-line dimension on
    // every offset LINE. The first is the editable driver (d0); the rest follow
    // it by expression, so editing one drives the whole run uniformly — exactly
    // Inventor's equidistant "Constrain Offset". On a CLOSED all-line loop the
    // final gap is implied by closure, so it becomes a driven (reference)
    // measure instead of over-constraining.
    final lineSegs = [
      for (var i = 0; i < n; i++)
        if (chain.offsets[i].type == Geo.line) i
    ];
    // M124 — circles carry the same distance as a gap dimension. A circle
    // offset has no "offset line" to hang a pline dimension on, which is why
    // it used to end up undimensioned; the gap between source and copy is the
    // offset distance, so it is the driver for a circle-only offset.
    final circleSegs = [
      for (var i = 0; i < n; i++)
        if (chain.offsets[i].type == Geo.circle &&
            s.geometry[chain.sources[i]].type == Geo.circle)
          i
    ];
    String? driver;
    for (var k = 0; k < lineSegs.length; k++) {
      final i = lineSegs[k];
      final src = chain.sources[i];
      final dim = Constraint(CType.dimension,
          dimKind: 'pline',
          pts: [
            PRef(firstNew + i, chain.enterPt[i]),
            PRef(src, 0),
            PRef(src, 1)
          ],
          value: chain.offsetDist,
          textPos: getPt(chain.offsets[i], chain.enterPt[i]));
      if (k == 0) {
        dim.paramName = driver = _newParamName(s);
      } else {
        dim.expr = driver; // follow the driver's value
        if (chain.closed && k == lineSegs.length - 1) dim.driven = true;
      }
      cons.add(dim);
    }
    for (final i in circleSegs) {
      final src = chain.sources[i];
      final dim = Constraint(CType.dimension,
          dimKind: 'gap',
          ents: [src, firstNew + i],
          // NOT chain.offsetDist: that is the perpendicular run distance the
          // LINE segments use and is 0 for a circle-only chain, which would
          // drive the copy straight back onto its source. The gap a circle
          // offset actually made is the radius difference.
          value: (chain.offsets[i].data[2] - s.geometry[src].data[2]).abs(),
          textPos: getPt(chain.offsets[i], 0) +
              Offset(chain.offsets[i].data[2], 0));
      if (driver == null) {
        dim.paramName = driver = _newParamName(s);
      } else {
        dim.expr = driver; // follow the run's distance, like the lines do
      }
      cons.add(dim);
    }

    // Atomic verify. Full constraints first; if the solver cannot hold them,
    // fall back to the bare offset geometry (always solvable) so the offset
    // still appears rather than scrambling or vanishing.
    if (solveConstraints(gs, cons)) {
      s.constraints
        ..clear()
        ..addAll(cons);
      _rebuildEngine(s, gs);
      Log.i(
          'modify',
          'offset chain from e$seed: +$n segs '
              '(${chain.closed ? "closed" : "open"}), '
              'constraints ${s.constraints.length}');
    } else {
      Log.w(
          'modify',
          'offset chain from e$seed: constrained result unsatisfiable — '
              'placing bare geometry');
      _rebuildEngine(s, gs); // geometry only, no new constraints
    }
  }

  // ---- constraints + dimensions (M7) ----
  PRef? _nearestPointRef(SketchModel s, Offset w,
      {Iterable<PRef> exclude = const []}) {
    bool excluded(PRef r) => exclude.any((x) => x.ent == r.ent && x.pt == r.pt);
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
        toast(L.current.msgAlreadyLocked);
        return false;
      }
    } else if (wouldOverconstrain(s.geometry, s.constraints, c)) {
      Log.i('constraint', 'REJECTED ${conStr(-1, c)} — would over-constrain');
      toast(L.current.msgWouldOverConstrainC);
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
      toast(L.current.msgConstraintUnsatisfiable);
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
  bool _solveAndRebuild(SketchModel s, [List<Geo>? base]) =>
      Perf.span('sketch.solveRebuild', () => _solveAndRebuildInner(s, base));

  bool _solveAndRebuildInner(SketchModel s, [List<Geo>? base]) {
    final gs = List<Geo>.from(base ?? s.geometry);
    final ok = solveConstraints(gs, s.constraints);
    if (!ok) {
      Log.w('solve', 'solveAndRebuild: unsatisfied — sketch left unchanged');
      // The one line above is what this used to be, and on its own it is
      // unactionable: it says a sketch is broken without saying where. Name
      // the constraints that are not held, the entities they point at, and
      // dump the sketch so the failing solve can be replayed off-device.
      Log.block(
          'solve',
          'why "${s.name}" is unsatisfiable',
          solveFailureDump(
              gs, s.constraints, constraintResidualsPer(gs, s.constraints)));
      Log.block('solve', 'sketch "${s.name}" as attempted',
          sketchDump(gs, s.constraints));
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
        // another point -> point-on-point, an entity -> point-on-curve.
        // M123: every carrier type is accepted (line, circle, arc, spline,
        // ellipse, gear, polygon), matching what the solver can actually
        // enforce — restricting this to lines made the tool disagree with both
        // the automatic inference and the trim/split cut-bind.
        if (conPts.isEmpty) {
          if (pt == null) return;
          conPts.add(pt);
          return;
        }
        if (pt != null) {
          _addConstraint(s, Constraint(CType.coincident, pts: [conPts[0], pt]));
          conPts.clear();
        } else if (ent != null && ent != conPts[0].ent) {
          _addConstraint(
              s, Constraint(CType.coincident, pts: [conPts[0]], ents: [ent]));
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
          _addConstraint(
              s, Constraint(CType.fix, pts: [pt], anchors: [q.dx, q.dy]));
        } else if (ent != null) {
          _addConstraint(
              s,
              Constraint(CType.fix,
                  ents: [ent],
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
        _addConstraint(
            s, Constraint(CType.symmetric, pts: List.of(conPts), ents: [ent]));
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
            bool spl(Geo g) => g.isFreeSpline;
            bool plainPoly(Geo g) =>
                g.type == Geo.polyline && g.spline == Geo.straight;
            if (!round(g1.type) && !round(g2.type) && !spl(g1) && !spl(g2)) {
              toast(L.current.msgTangentNeedsCurve);
              conEnts.clear();
              conEntClicks.clear();
              return;
            }
            if ((spl(g1) && g1.data[0] != 0) || (spl(g2) && g2.data[0] != 0)) {
              toast(L.current.msgTangentClosedSpline);
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
                  toast(L.current.msgTangentNeedsCurve);
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
              toast(L.current.msgSmoothNeedsTwoCurves);
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
    // M202 — ...with one exception: a click on a circle's RIM picks the
    // CIRCLE, not its centre point. The centre marker and the edge are two
    // different targets in Inventor, and preferring the point here would make
    // the tangent dimension unreachable — the point tolerance is 10/zoom, so
    // on a small circle at a low zoom the centre swallows the whole rim.
    final preferPoint = pt != null &&
        !(pt.pt == 0 &&
            pt.ent >= 0 &&
            pt.ent < s.geometry.length &&
            _isRimClick(s.geometry[pt.ent], w));

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
                    seg.$2.pt == conPts[1].pt)) {
              //   same edge again: place
              conEdges.add(seg);
              return;
            }
          }
        }
      } else if (nP == 0 && nE == 0 && conEdges.isEmpty) {
        conEnts.add(ent);
        conEntClicks.add(w); //                   first pick: line/circle/arc
        return;
      } else if (nP == 0 && nE == 1 && conEdges.isEmpty) {
        // second entity: any line/circle/arc pairing is dimensionable
        conEnts.add(ent);
        conEntClicks.add(w);
        return;
      } else if (nP == 1 &&
          nE == 0 &&
          conEdges.isEmpty &&
          (isLine(ent) || isCurve(ent))) {
        conEnts.add(ent);
        conEntClicks.add(w); //                   point + line/curve
        return;
      } else if (nE == 0 &&
          conEdges.length == 1 &&
          (nP == 0 || (nP == 2 && pickedEdge != null)) &&
          (isLine(ent) || isCurve(ent))) {
        // ...the mirrored order: edge first (as conPts pair), then a
        // line/curve entity — same combinations as above
        conEnts.add(ent);
        conEntClicks.add(w);
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

  /// M202 — was the curve picked on its RIM rather than near its centre?
  ///
  /// Inventor's rule since 2020: select the line, then hover the CIRCLE'S EDGE
  /// near the tangent point and the glyph changes to a tangent dimension. The
  /// pick position is the whole signal, so it is recorded per entity pick
  /// ([conEntClicks], index-parallel with [conEnts]) and read back here.
  ///
  /// "Rim" is the nearer half: closer to the circumference than to the centre.
  /// Anything else — including a missing click record, so an older session or
  /// a programmatic pick cannot change meaning — stays the centre distance
  /// this app has always produced.
  bool _pickedTheRim(SketchModel s, int ent, int which) {
    if (which >= conEntClicks.length) return false;
    return _isRimClick(s.geometry[ent], conEntClicks[which]);
  }

  /// True when [w] is nearer this curve's RIM than its centre.
  bool _isRimClick(Geo g, Offset w) {
    if (g.type != Geo.circle && g.type != Geo.arc) return false;
    final r = g.data[2];
    if (!(r > 1e-9)) return false;
    final d = (w - Offset(g.data[0], g.data[1])).distance;
    return (d - r).abs() < d;
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

    // A curve participates in distance dimensions through its CENTER point —
    // Inventor's default. M202 adds the tangent-edge variant next to it; which
    // one you get is decided by [_pickedTheRim]. getPt(circle/arc, 0) is the
    // center.
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
        // circle/arc + circle/arc. Inventor gives centre-to-centre here (and
        // reaches edge-to-edge via Alt), but when the two centres COINCIDE
        // that distance is identically 0 — it measures nothing and cannot
        // drive anything. So a concentric pair falls back to the radial GAP,
        // which is the measure that pair actually has: the annulus width, and
        // the same number an Offset of that circle moved (M124).
        final ca = refPt(s.geometry, center(e1));
        final cb = refPt(s.geometry, center(e2));
        if ((ca - cb).distance < 1e-6) {
          d = Constraint(CType.dimension,
              ents: List.of(conEnts), dimKind: 'gap', textPos: w);
        } else {
          final a = center(e1), b = center(e2);
          d = Constraint(CType.dimension,
              pts: [a, b], dimKind: _distKind(s, a, b, w), textPos: w);
        }
      } else if (c1 || c2) {
        // circle/arc + line. M202 — WHERE you clicked the curve decides,
        // which is Inventor's own rule (2020+): click the centre and you get
        // the centre distance, click the EDGE near the tangent point and you
        // get the distance to the rim. "when i make a dimension from a line to
        // a circle, also a dimension from the line to the nearest point on the
        // curve of the circle should be possible. like in inventor."
        final ce = c1 ? e1 : e2, le = c1 ? e2 : e1;
        d = Constraint(CType.dimension,
            pts: [center(ce), PRef(le, 0), PRef(le, 1)],
            ents: [ce],
            dimKind: _pickedTheRim(s, ce, c1 ? 0 : 1) ? 'plinetan' : 'pline',
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
      if (g.isSketchPoint) {
        // M209 — a sketch point has no diameter. Its carrier circle does, and
        // dimensioning that would drive a number nobody can see.
        d = null;
      } else if (g.type == Geo.circle) {
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

  /// M49 — Split, Trim and Extend are one command family in Inventor: while
  /// any of them runs, a right-click switches to the next one WITHOUT leaving
  /// the session ("Right-click to switch to Trim or Extend"). Returns false
  /// when no member of the family is active, so the caller can fall through.
  bool cycleModifyTool() {
    const ring = [Tool.split, Tool.trim, Tool.extendT];
    final at = ring.indexOf(tool);
    if (at < 0) return false;
    tool = ring[(at + 1) % ring.length];
    toolPoints.clear();
    selection.clear();
    Log.i('modify', 'right-click: switched to $tool');
    notifyListeners();
    return true;
  }

  /// M49 — Split hover preview. Inventor previews the split BEFORE the click:
  /// you pause over a curve and it shows where the cut would land (at the
  /// nearest intersecting curve, not under the cursor) and which span the
  /// cursor is on. Returns null when there is nothing to split against.
  SplitPlan? splitPreview(Offset w) {
    final s = current;
    if (s == null || tool != Tool.split) return null;
    final i = _pickEntity(s, w);
    if (i == null) return null;
    if (s.geometry[i].isProjection) return null; // pinned reference geometry
    return planSplit(s.geometry, i, w);
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
      toast(L.current.msgValueUnsatisfiable);
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

  /// M44: screen rects of painted parametric texts (tap-to-edit hit test).
  final List<(SketchText, Rect)> textRects = [];

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
      toast(L.current.msgDrivenDimension);
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
      toast(L.current.msgValueUnsatisfiableShort);
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

  /// name -> current base value (mm resp. deg) of every named dimension AND
  /// every user parameter (M43: Inventors fx table).
  /// M220 — the table itself moved to text_geometry.dart: deriving a text's
  /// GEOMETRY needs the same rendered template the label used to need, and
  /// that code has no AppState. One implementation, forwarded here.
  Map<String, double> paramTable(SketchModel s) => sketchParamTable(s);

  Constraint? _dimByName(SketchModel s, String name) {
    for (final c in s.constraints) {
      if (c.type == CType.dimension && c.paramName == name) return c;
    }
    return null;
  }

  UserParam? _userByName(SketchModel s, String name) {
    for (final u in s.userParams) {
      if (u.name == name) return u;
    }
    return null;
  }

  bool _nameTaken(SketchModel s, String name) =>
      _dimByName(s, name) != null || _userByName(s, name) != null;

  /// name -> the names its expression references (dims + user params).
  Map<String, Set<String>> _depGraph(SketchModel s) => {
        for (final c in s.constraints)
          if (c.type == CType.dimension &&
              c.paramName != null &&
              c.expr != null)
            c.paramName!: exprRefs(c.expr!),
        for (final u in s.userParams)
          if (u.expr != null) u.name: exprRefs(u.expr!),
      };

  /// True when a parameter called [selfName] whose expression references
  /// [refs] would close a dependency cycle.
  bool _cycleIfRefs(SketchModel s, String selfName, Set<String> refs) {
    final g = _depGraph(s);
    final seen = <String>{};
    bool reachesSelf(String n) {
      if (n == selfName) return true;
      if (!seen.add(n)) return false;
      return (g[n] ?? const <String>{}).any(reachesSelf);
    }

    return refs.any(reachesSelf);
  }

  static bool _isAngleDim(Constraint c) =>
      c.dimKind == 'ang' || c.dimKind == 'ang3' || c.dimKind == 'ang4';

  /// True when making [c]'s expression reference [ref] would close a cycle
  /// (ref depends — transitively, across dims AND user params — on c).
  bool _wouldCycle(SketchModel s, Constraint c, String ref) =>
      c.paramName != null && _cycleIfRefs(s, c.paramName!, {ref});

  (List<(Constraint, double?, String?)>, List<(UserParam, double, String?)>)
      _snapshotDims(SketchModel s) => (
            [
              for (final c in s.constraints)
                if (c.type == CType.dimension) (c, c.value, c.expr)
            ],
            [for (final u in s.userParams) (u, u.value, u.expr)],
          );

  void _restoreDims(
      (
        List<(Constraint, double?, String?)>,
        List<(UserParam, double, String?)>
      ) snap) {
    for (final (c, v, e) in snap.$1) {
      c.value = v;
      c.expr = e;
    }
    for (final (u, v, e) in snap.$2) {
      u.value = v;
      u.expr = e;
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
      for (final u in s.userParams) {
        if (u.expr == null) continue;
        final v = evalExpr(u.expr!, table); // user params are length-domain
        if (v != null && (v - u.value).abs() > 1e-9) {
          u.value = v;
          changed = true;
        }
      }
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
      toast(L.current.msgDrivenDimension);
      return false;
    }
    ensureParamNames(s);
    final (name, body) = splitAssignment(raw);
    if (body.trim().isEmpty) return false;
    if (name != null) {
      if (!isValidParamName(name)) {
        toast(L.current.msgInvalidParamName);
        return false;
      }
      final other = _dimByName(s, name);
      if ((other != null && !identical(other, c)) ||
          _userByName(s, name) != null) {
        toast(L.current.msgParamNameInUse(name));
        return false;
      }
    }
    final angle = _isAngleDim(c);
    final refs = exprRefs(body);
    for (final r in refs) {
      if (!_nameTaken(s, r)) {
        toast(L.current.msgUnknownParam(r));
        return false;
      }
      if (r == c.paramName || _wouldCycle(s, c, r)) {
        toast(L.current.msgCircularRefDimension(r));
        return false;
      }
    }
    final v = evalExpr(body, paramTable(s), angle: angle);
    if (v == null) {
      toast(L.current.msgInvalidExpression);
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
      toast(L.current.msgValueUnsatisfiableShort);
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  /// Renames [from] to [to] inside every stored expression — dimensions AND
  /// user parameters (word-boundary match, so renaming d1 does not maul d10).
  void _renameRefs(SketchModel s, String from, String to) {
    final re = RegExp('\\b${RegExp.escape(from)}\\b');
    for (final c in s.constraints) {
      if (c.expr != null) c.expr = c.expr!.replaceAll(re, to);
    }
    for (final u in s.userParams) {
      if (u.expr != null) u.expr = u.expr!.replaceAll(re, to);
    }
    for (final t in s.texts) {
      t.template = renameInTemplate(t.template, from, to); // M44
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
      if ((other != null && !identical(other, c)) ||
          _userByName(s, name) != null) return false;
    }
    final refs = exprRefs(body);
    for (final r in refs) {
      if (!_nameTaken(s, r)) return false;
      if (r == c.paramName || _wouldCycle(s, c, r)) return false;
    }
    return evalExpr(body, paramTable(s), angle: _isAngleDim(c)) != null;
  }

  // -------------------------------------------------------------- M43 ----
  // Inventors Parameters dialog (fx): a movable table listing every model
  // parameter (the dimensions) and user-defined parameters with name,
  // equation and value. Cells accept the same expressions as the dimension
  // edit box; while a cell is focused, tapping a dimension label in the
  // viewport inserts its parameter name (routed through [paramRefSink]).

  /// The Parameters window is open.
  bool showParams = false;
  void toggleParams() {
    showParams = !showParams;
    if (current != null) ensureParamNames(current!);
    notifyListeners();
  }

  /// While a parameter-dialog cell is focused, this receives the parameter
  /// name of a tapped dimension label (viewport click-to-reference).
  void Function(String name)? paramRefSink;

  // M45 — the parametric-text editor window (Inventor-like, movable). When a
  // text is being created/edited it lives here; the viewport routes taps on
  // dimension labels into [textRefSink] so a reference like "d0" is inserted
  // into the template (the user asked for the name wrapped in quotes).
  SketchText? editingText;
  bool editingTextIsNew = false;
  void Function(String token)? textRefSink;

  void beginTextEdit(SketchText t, {required bool isNew}) {
    editingText = t;
    editingTextIsNew = isNew;
    notifyListeners();
  }

  /// Ends the text editor. [keep] false on a brand-new empty text removes it.
  void endTextEdit({bool keep = true}) {
    final t = editingText;
    editingText = null;
    textRefSink = null;
    if (t != null && !keep && editingTextIsNew) {
      current?.texts.remove(t);
    }
    editingTextIsNew = false;
    notifyListeners();
  }

  /// Smallest unused User_1, User_2, … (Inventor auto-names new rows).
  String _newUserName(SketchModel s) {
    var i = 1;
    while (_nameTaken(s, 'User_$i')) {
      i++;
    }
    return 'User_$i';
  }

  /// Adds a fresh user parameter (value 0) and returns it.
  UserParam addUserParam() {
    final s = current!;
    final u = UserParam(_newUserName(s), 0);
    s.userParams.add(u);
    s.checkpoint();
    notifyListeners();
    return u;
  }

  /// Commits the raw text of a user-parameter EQUATION cell — the same
  /// grammar as the dimension edit box: plain number, expression, or
  /// "Name = …" (renames the parameter and follows every reference).
  bool setUserParamText(UserParam u, String raw) {
    final s = current;
    if (s == null) return false;
    ensureParamNames(s);
    final (name, body) = splitAssignment(raw);
    if (body.trim().isEmpty) return false;
    if (name != null && name != u.name) {
      if (!isValidParamName(name) || _nameTaken(s, name)) {
        toast(L.current.msgInvalidOrDuplicateParamName);
        return false;
      }
    }
    final refs = exprRefs(body);
    for (final r in refs) {
      if (!_nameTaken(s, r)) {
        toast(L.current.msgUnknownParam(r));
        return false;
      }
      if (r == u.name || _cycleIfRefs(s, u.name, {r})) {
        toast(L.current.msgCircularRefParam(r));
        return false;
      }
    }
    final v = evalExpr(body, paramTable(s));
    if (v == null) {
      toast(L.current.msgInvalidExpression);
      return false;
    }
    final snap = _snapshotDims(s);
    final oldName = u.name;
    u.value = v;
    u.expr = isPlainNumber(body) ? null : body.trim();
    if (name != null && name != oldName) {
      u.name = name;
      _renameRefs(s, oldName, name);
    }
    // dependents (dims referencing this parameter) follow; an unsatisfiable
    // resulting geometry rolls everything back atomically (M37 rules)
    if (!_solveOnceThenChase(s)) {
      _restoreDims(snap);
      if (name != null && name != oldName) {
        u.name = oldName;
        _renameRefs(s, name, oldName);
      }
      toast(L.current.msgValueUnsatisfiableShort);
      notifyListeners();
      return false;
    }
    s.checkpoint(); // a pure user-param edit may not rebuild the engine
    notifyListeners();
    return true;
  }

  /// Renames a user parameter from its NAME cell.
  bool renameUserParam(UserParam u, String name) {
    final s = current;
    if (s == null) return false;
    name = name.trim();
    if (name == u.name) return true;
    if (!isValidParamName(name) || _nameTaken(s, name)) {
      toast(L.current.msgInvalidOrDuplicateParamName);
      return false;
    }
    final old = u.name;
    u.name = name;
    _renameRefs(s, old, name);
    s.checkpoint();
    notifyListeners();
    return true;
  }

  /// Deletes a user parameter — refused while anything references it
  /// (Inventor greys the delete for in-use parameters).
  bool deleteUserParam(UserParam u) {
    final s = current;
    if (s == null) return false;
    final g = _depGraph(s);
    for (final e in g.entries) {
      if (e.key != u.name && e.value.contains(u.name)) {
        toast(L.current.msgParamUsedBy(u.name, e.key));
        return false;
      }
    }
    s.userParams.remove(u);
    s.checkpoint();
    notifyListeners();
    return true;
  }

  /// Live validation for a user-parameter equation cell.
  bool userParamTextValid(UserParam u, String raw) {
    final s = current;
    if (s == null) return false;
    final (name, body) = splitAssignment(raw);
    if (body.trim().isEmpty) return false;
    if (name != null && name != u.name) {
      if (!isValidParamName(name) || _nameTaken(s, name)) return false;
    }
    final refs = exprRefs(body);
    for (final r in refs) {
      if (!_nameTaken(s, r)) return false;
      if (r == u.name || _cycleIfRefs(s, u.name, {r})) return false;
    }
    return evalExpr(body, paramTable(s)) != null;
  }

  // -------------------------------------------------------------- M44 ----
  // Insert content: parametric text, images, DXF import.

  /// Adds a parametric text at [pos]. Placeholders <ParamName> render as the
  /// parameter's current value and follow changes and renames. Tagged to the
  /// editing layer so its construction bounding rect shows only there.
  /// [placeholder] true skips the undo checkpoint — used when opening the
  /// editor on a brand-new text that is only kept if the user commits it
  /// (the commit path checkpoints then).
  SketchText addText(Offset pos, String template,
      {double height = 8, String? font, bool placeholder = false}) {
    final s = current!;
    final t = SketchText(template, pos.dx, pos.dy,
        height: height,
        font: vectorFontName(font ?? kDefaultTextFont),
        layer: editingLayer ?? kDefaultLayer);
    s.texts.add(t);
    s.dirty = true;
    // M220 — a text is a profile now, so the regions an open extrude session
    // is offering are out of date the moment one appears, moves or changes.
    _regionCache.clear();
    if (!placeholder) s.checkpoint();
    notifyListeners();
    return t;
  }

  void updateText(SketchText t, String template, double height,
      {String? font}) {
    t.template = template;
    t.height = height;
    if (font != null) t.font = vectorFontName(font);
    current?.dirty = true;
    _regionCache.clear();
    current?.checkpoint();
    notifyListeners();
  }

  void moveText(SketchText t, Offset pos, {bool commit = false}) {
    t.x = pos.dx;
    t.y = pos.dy;
    _regionCache.clear();
    if (commit) {
      current?.dirty = true;
      current?.checkpoint();
    }
    notifyListeners();
  }

  void deleteText(SketchText t) {
    current?.texts.remove(t);
    current?.dirty = true;
    _regionCache.clear();
    current?.checkpoint();
    notifyListeners();
  }

  /// Renders [t]'s template against the current parameter table.
  String textDisplay(SketchModel s, SketchText t) => renderedText(s, t);

  /// M45 — the world-space bounding rectangle of a text, sized automatically
  /// from its rendered content, font and height. The anchor (t.x, t.y) is the
  /// LOWER-LEFT of the text, so the rect spans up and to the right.
  ///
  /// M220 — [measure] is no longer required: the box now comes from the same
  /// outline font the geometry is built from ([measureText2D]), so the dashed
  /// rectangle and its snap points bound exactly the curves that are drawn,
  /// exported and extruded. It used to be a TextPainter in the widget layer,
  /// which is why it had to be injected at all.
  Rect textBoundsWorld(SketchModel s, SketchText t,
      {Size Function(SketchText, String)? measure}) {
    final sz = measure == null
        ? measureText2D(s, t)
        : measure(t, textDisplay(s, t));
    final pad = t.height * 0.25; // small breathing room, scales with size
    return Rect.fromLTWH(
        t.x - pad, t.y - pad, sz.width + 2 * pad, sz.height + 2 * pad);
  }

  /// Corners + edge midpoints of every text's bounding rect — offered to the
  /// snapper so dimensions and new geometry can lock onto a text box. Only
  /// texts on the layer being edited contribute (their rect is only shown
  /// there). [measure] as in [textBoundsWorld].
  List<Offset> textSnapPoints(SketchModel s,
      {Size Function(SketchText, String)? measure}) {
    final pts = <Offset>[];
    for (final t in s.texts) {
      if (inEditMode && t.layer != editingLayer) continue;
      final r = textBoundsWorld(s, t, measure: measure);
      pts.addAll([
        r.topLeft,
        r.topRight,
        r.bottomLeft,
        r.bottomRight,
        r.centerLeft,
        r.centerRight,
        r.topCenter,
        r.bottomCenter,
      ]);
    }
    return pts;
  }

  /// Inserts an image file: copies it next to the sketch sidecars (the
  /// picker's temp file dies with the session). Placed centred at [center]
  /// with width [w] mm, aspect from [pxW]x[pxH], tagged to the editing layer.
  SketchImage addImage(String srcPath, Offset center,
      {required int pxW, required int pxH, double w = 100}) {
    final s = current!;
    final ext = srcPath.contains('.') ? srcPath.split('.').last : 'img';
    final name = 'img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      final dir = Directory('${_stage(curTab!).path}/images');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(srcPath).copySync('${dir.path}/$name');
    } catch (e) {
      Log.w('insert', 'image copy failed: $e');
      toast(L.current.msgCouldNotImportImage);
      rethrow;
    }
    final img = SketchImage(
        name, center.dx, center.dy, w, pxH <= 0 ? w : w * pxH / pxW,
        layer: editingLayer ?? kDefaultLayer);
    s.images.add(img);
    s.dirty = true;
    s.checkpoint();
    notifyListeners();
    return img;
  }

  /// Absolute path of an inserted image's file.
  /// Absolute path of an inserted image's file inside the open document.
  ///
  /// M177 — images used to be shared across every sketch in one folder, which
  /// meant a document was not self-contained: send it to someone and the
  /// pictures stayed behind. They now live inside the document. The bare-name
  /// fallback resolves pre-M177 sketches, whose images migration copied in.
  String imagePath(SketchImage i) {
    final name = curTab;
    if (name == null) return i.file;
    final stage = _stage(name).path;
    final inDoc = '$stage/images/${i.file}';
    if (File(inDoc).existsSync()) return inDoc;
    return '$stage/${i.file}';
  }

  void moveImage(SketchImage i, Offset center, {bool commit = false}) {
    i.x = center.dx;
    i.y = center.dy;
    if (commit) {
      current?.dirty = true;
      current?.checkpoint();
    }
    notifyListeners();
  }

  /// Resizes to width [w] (mm), keeping aspect. Clamped to something usable.
  void resizeImage(SketchImage i, double w, {bool commit = false}) {
    final asp = i.h / i.w;
    i.w = w.clamp(1.0, 100000.0);
    i.h = i.w * asp;
    if (commit) {
      current?.dirty = true;
      current?.checkpoint();
    }
    notifyListeners();
  }

  void deleteImage(SketchImage i) {
    current?.images.remove(i);
    current?.dirty = true;
    current?.checkpoint();
    notifyListeners();
  }

  /// Imports a DXF file INTO the current sketch (Insert > ACAD): entities are
  /// parsed by the same backend loader that opens sketches, re-homed onto the
  /// layer being edited (or the default layer) and committed as ONE journal
  /// step through the normal solve/rebuild pipeline.
  /// M111 — imports a STEP file into the current part: one BODY per solid.
  ///
  /// The file is copied INTO the part document and the features remember it,
  /// because the imported B-Rep is not serialised — re-reading the STEP on
  /// open is simpler and lossless, and it keeps the document a description of
  /// where geometry came from rather than a second copy of it.
  Future<int> importStepIntoPart(String path) async {
    final p = currentPart;
    if (p == null) {
      toast(L.current.msgOpenPartForStep);
      return 0;
    }
    final solids = partKernel.importStepSolids(path);
    if (solids.isEmpty) {
      toast(L.current.msgNoSolidsInStep(partKernel.lastError));
      return 0;
    }
    // Keep the source next to the part so it can be re-read on open.
    String? rel;
    try {
      final dir = _partImportDir(curTab!);
      final base = path.split('/').last;
      final dst = File('${dir.path}/$base');
      File(path).copySync(dst.path);
      rel = 'imports/$base';
    } catch (e) {
      Log.w('import', 'could not stash the STEP file: $e');
    }
    for (var i = 0; i < solids.length; i++) {
      final body = p.nextSolidName();
      p.appendFeature(ExtrudeFeature(
        name: 'Import${p.features.length + 1}',
        bodyName: body,
        sketchName: '',
        profiles: const [],
        output: 'new',
      )
        ..imported = true
        ..importPath = rel
        ..solid = solids[i]
        ..seq = p.nextSeq());
    }
    // `appendFeature` already kept the marker past each import — do not pin it
    // to the row count afterwards.
    applyEndOfPart(p);
    p.dirty = true;
    if (curTab != null) await savePart(curTab!);
    Log.i('import', 'STEP: ${solids.length} solid(s) from $path');
    toast(L.current.msgImportedBodies(solids.length));
    notifyListeners();
    return solids.length;
  }

  /// M232 — opens an STL, OBJ or 3MF as a real, editable body.
  ///
  /// Two stages, in two languages, and the split is deliberate. The FILE is
  /// parsed in Dart (`mesh_io.dart`), because container formats are I/O and
  /// belong where they can be tested without a linked kernel. The GEOMETRY is
  /// reconstructed in the shim, because turning a triangle soup into surfaces
  /// needs a spatial index over millions of vertices and then needs OCCT to
  /// intersect, trim and sew what it found.
  ///
  /// The converted body is written out as STEP beside the part and the feature
  /// points at THAT, not at the mesh. Imported bodies are re-read from their
  /// source on every open (see openPart), and re-running a conversion that
  /// takes a second on a large download — and that could answer differently
  /// after a tolerance change — every time the part is opened would be both
  /// slow and dishonest. The conversion happens once; its result is the
  /// document's geometry from then on.
  ///
  /// Returns the number of bodies added (0 on failure, having said why).
  static double _thinnestDim(MeshSoup s) {
    final b = s.bounds;
    if (b == null) return 0;
    return math.min(b[3] - b[0], math.min(b[4] - b[1], b[5] - b[2]));
  }

  Future<int> importMeshIntoPart(String path) async {
    final p = currentPart;
    if (p == null) {
      toast(L.current.msgOpenPartForMesh);
      return 0;
    }
    if (!partKernel.available) {
      toast(L.current.msgNoKernelMesh);
      return 0;
    }

    // Every step from here to the kernel gets a milestone, because every one
    // of them can end the process without an exception Dart could catch: a
    // large file is read whole into memory, and the conversion is native. An
    // iOS app killed for memory leaves no crash report at all, so a line that
    // simply stops is the only evidence there will be.
    Log.milestone('import',
        'mesh: reading "$path" (rss ${Log.rssMb() ?? -1} MB)');
    final MeshSoup soup;
    try {
      soup = loadMeshFile(path);
    } on MeshLoadException catch (e) {
      Log.w('import', 'mesh parse of "$path" refused: $e');
      toast(_meshReadFailure(e));
      return 0;
    } catch (e, st) {
      Log.e('import', 'mesh parse of "$path" failed', e, st);
      toast(L.current.msgMeshUnreadable);
      return 0;
    }
    Log.milestone(
        'import',
        'mesh ${soup.format}: ${soup.triangleCount} tri, '
            '${soup.vertexCount} vtx, ${soup.objectCount} object(s), '
            'diagonal ${soup.diagonal.toStringAsFixed(2)} mm'
            '${soup.uprightedFromZUp ? ', turned Z-up -> Y-up' : ''}'
            // M280 — the number that decides whether thin features survive.
            // In the log because a filled-in cut-out is otherwise a report
            // with no evidence in it: this line says what the fit was allowed
            // to blur, next to the size of the thing it was fitting.
            ', tol ${(brepTolFractionFor(soup) * soup.diagonal)
                .toStringAsFixed(3)} mm'
            '${soup.bounds == null ? '' : ' (thinnest dim '
                '${_thinnestDim(soup).toStringAsFixed(2)} mm)'}'
            '${soup.droppedTriangles > 0 ? ', '
                '${soup.droppedTriangles} dropped' : ''}');

    // M333 — ASK, rather than decide for them.
    //
    // A downloaded mesh has two honest destinations and they are not versions
    // of each other: reverse-engineered surfaces that can be filleted and
    // dimensioned, or the triangles exactly as they are. Guessing produces the
    // worse half of both — a minute of waiting for someone who wanted a
    // faithful copy, or 80,000 faces for someone who wanted geometry to edit.
    // See ImportChoiceSheet.swift for why the sheet is native.
    //
    // Off iOS there is no sheet to ask with, so the conversion is what
    // happens: it is what this entry point did before the dialog existed, and
    // refusing to import at all on a host that simply cannot present a sheet
    // would break the desktop build and the test suite to no purpose. On iOS
    // a null is a real cancellation and is obeyed.
    // The 1:1 path makes one face per triangle and the kernel refuses above
    // kMaxFacetedTriangles. Do not offer it there: a choice that is accepted
    // and then fails, after a wait, is a worse dialog than one that says up
    // front why there is only one way in.
    final canFacet = canImportAsTriangles(soup.triangleCount);
    final choice = await NativeMenu.importChoice(
      title: L.current.askMeshImportTitle,
      message: L.current.askMeshImportBody(
          soup.triangleCount, soup.diagonal.toStringAsFixed(0)),
      convertLabel: L.current.askMeshImportConvert,
      convertDetail: L.current.askMeshImportConvertWhy,
      facetedLabel: canFacet ? L.current.askMeshImportFaceted : null,
      facetedDetail: canFacet
          ? L.current.askMeshImportFacetedWhy
          : L.current.askMeshImportTooManyFaceted(kMaxFacetedTriangles),
      cancelLabel: L.current.cancel,
    );
    if (choice == null && NativeMenu.isSupported) {
      Log.milestone('import', 'mesh: cancelled at the import dialog');
      return 0;
    }
    final how = choice ?? MeshImportChoice.convert;
    Log.milestone('import', 'mesh: importing as ${how.id}');

    // The kernel is single-threaded by contract, so the conversion happens on
    // the DART isolate and no Flutter frame is produced until it returns —
    // under a second for a typical model, half a minute for a big one. A
    // Flutter progress bar would freeze on its first frame and read as a hang,
    // so the card is drawn by UIKit on the platform thread, which stays idle
    // throughout and keeps animating. See NativeBusy / BusyOverlay.swift.
    //
    // M333 — that card now shows the converter's OWN stage and counters, read
    // from the platform thread while this isolate is stuck inside the call
    // that is advancing them (occt_mesh_progress). Nothing needs passing to it
    // from here; the title and the detail are all this side knows.
    //
    // Awaited on purpose: the reply arrives only once the platform thread has
    // put the card up, which is what makes it exist BEFORE the blocking call
    // rather than after it. On a host without the plugin this is a no-op and
    // the toast is still the notice.
    final busyTitle = how == MeshImportChoice.convert
        ? L.current.msgMeshConvertTitle
        : L.current.msgMeshBuildTitle;
    final busyDetail = how == MeshImportChoice.convert
        ? L.current.msgMeshConverting(soup.triangleCount)
        : L.current.msgMeshBuilding(soup.triangleCount);
    toast(busyDetail);
    final liveProgress = await NativeBusy.show(
      busyTitle,
      busyDetail,
      // The card is UIKit and has no localisations of its own.
      stages: MeshStage.names(
        reading: L.current.meshStageReading,
        finding: L.current.meshStageFinding,
        fitting: L.current.meshStageFitting,
        shaping: L.current.meshStageShaping,
        building: L.current.meshStageBuilding,
        finishing: L.current.meshStageFinishing,
        simplifying: L.current.meshStageSimplifying,
      ),
      cancelTitle: L.current.cancel,
      cancellingTitle: L.current.actionCancelling,
    );
    Log.milestone('import',
        'mesh: busy card ${liveProgress ? 'with live progress' : 'indeterminate'}');

    final MeshImportOutcome res;
    try {
      Log.milestone('import',
          'mesh: >> kernel ${how.id} (rss ${Log.rssMb() ?? -1} MB)');
      res = partKernel.meshToBrep(soup.vertices, soup.triangles,
          mode: how.kernelMode,
          tolFraction: brepTolFractionFor(soup),
          maxFacetedTriangles: kMaxFacetedTriangles);
      Log.milestone('import',
          'mesh: << kernel ${how.id} (rss ${Log.rssMb() ?? -1} MB)');
    } catch (_) {
      // The card must not outlive the work under any exit, including one the
      // kernel throws.
      await NativeBusy.hide();
      rethrow;
    }
    Log.milestone('import', res.report.describe());
    final solid = res.solid;
    if (solid == null) {
      await NativeBusy.hide();
      // A cancellation is not a failure. The user knows what they did and why
      // there is no body; repeating it back as an error message, in the tone
      // reserved for something going wrong, is the app arguing with them.
      if (res.error == kMeshCancelled) {
        Log.milestone('import', 'mesh: cancelled by the user');
        toast(L.current.msgMeshImportCancelled);
      } else {
        toast(_meshConvertFailure(res));
      }
      return 0;
    }

    // Persist the RESULT, and make the feature point at it.
    String? rel;
    try {
      final dir = _partImportDir(curTab!);
      var base = path.split('/').last;
      final dot = base.lastIndexOf('.');
      if (dot > 0) base = base.substring(0, dot);
      final dst = File('${dir.path}/$base.step');
      Log.milestone('import', 'mesh: >> write ${dst.path}');
      if (partKernel.exportStep([solid], dst.path)) {
        rel = 'imports/$base.step';
      } else {
        Log.w('import',
            'could not write the converted STEP: ${partKernel.lastError}');
      }
    } catch (e) {
      Log.w('import', 'could not stash the converted body: $e');
    }
    // Everything that blocks the isolate is done: the conversion and the STEP
    // write, which is another native call and on a big model not a fast one.
    await NativeBusy.hide();
    if (rel == null) {
      // Without a file on disk the body would come back empty on reopen, and
      // geometry that vanishes without explanation is the worse failure.
      solid.dispose();
      toast(L.current.msgMeshNotSaved);
      return 0;
    }

    p.appendFeature(ExtrudeFeature(
      name: 'Import${p.features.length + 1}',
      bodyName: p.nextSolidName(),
      sketchName: '',
      profiles: const [],
      output: 'new',
    )
      ..imported = true
      ..importPath = rel
      ..solid = solid
      ..seq = p.nextSeq());
    applyEndOfPart(p);
    p.dirty = true;
    if (curTab != null) await savePart(curTab!);
    Log.milestone('import', 'mesh: done (rss ${Log.rssMb() ?? -1} MB)');
    toast(_meshSuccessMessage(res.report));
    notifyListeners();
    return 1;
  }

  /// The sentence for a mesh file that could not be READ.
  ///
  /// mesh_io.dart throws a [MeshFailure] rather than prose, because the app is
  /// German and a reader has no business holding UI text (M234). This is where
  /// the code becomes a sentence, in whatever language the user is reading.
  String _meshReadFailure(MeshLoadException e) {
    final l = L.current;
    switch (e.reason) {
      case MeshFailure.empty:
        return l.msgMeshEmpty;
      case MeshFailure.unsupportedKind:
        return l.msgCannotOpenKind;
      case MeshFailure.missing:
        return l.msgMeshMissing;
      case MeshFailure.unreadable:
        return l.msgMeshUnreadable;
      case MeshFailure.noGeometry:
        return l.msgMeshNoGeometry;
      case MeshFailure.truncated:
        return l.msgMeshTruncated;
      case MeshFailure.badIndex:
        return l.msgMeshBadIndex(e.detail ?? '?');
      case MeshFailure.notAnArchive:
        return l.msgMeshNotAnArchive;
      case MeshFailure.noModel:
        return l.msgMeshNoModel;
      case MeshFailure.unknownUnit:
        return l.msgMeshUnknownUnit(e.detail ?? '?');
      case MeshFailure.fileTooLarge:
        return l.msgMeshFileTooLarge(
            e.count ?? 0, kMaxMeshFileBytes ~/ (1024 * 1024));
      case MeshFailure.tooManyTriangles:
        return l.msgMeshTooManyTriangles(e.count ?? 0, kMaxMeshTriangles);
    }
  }

  /// The sentence for a mesh that was read but would not CONVERT.
  ///
  /// The report is more useful than the kernel's own message here. "the faces
  /// would not sew" means nothing to someone who downloaded a model; "this mesh
  /// is not watertight, 412 open edges" names something they can go and fix, in
  /// their slicer or in the model they downloaded.
  String _meshConvertFailure(MeshImportOutcome res) {
    final r = res.report;
    if (r.trianglesUsed == 0) return L.current.msgMeshNoGeometry;
    if (r.boundaryEdges > 0) {
      return L.current.msgMeshNotWatertight(r.boundaryEdges);
    }
    final why = res.error;
    return (why != null && why.isNotEmpty)
        ? L.current.msgMeshConvertFailedWhy(why)
        : L.current.msgMeshConvertFailed;
  }

  /// What to tell the user when it worked.
  ///
  /// Three whole sentences, picked and joined — never fragments glued into one.
  /// A localised fragment cannot be relied on to keep its shape when the
  /// surrounding words change language, and this is the one message here with
  /// something conditional to say.
  ///
  /// The number reported is the count of RECOGNISED surfaces, not of faces.
  /// That is the figure that decides whether the next thing the user tries will
  /// work: a hole that came back a cylinder can be filleted, and a hole that
  /// came back forty flat strips cannot. The breakdown by kind goes to the log
  /// (see [MeshToBrepReport.describe]), where it belongs — a toast is read in
  /// two seconds or not at all.
  String _meshSuccessMessage(MeshToBrepReport r) {
    final l = L.current;
    final surfaces = r.analyticFaces;
    final out = <String>[
      surfaces > 0
          ? l.msgMeshImported(surfaces)
          : l.msgMeshImportedFacetedOnly(r.facesBuilt),
    ];
    // Only worth saying alongside a real result; when nothing was recognised,
    // msgMeshImportedFacetedOnly has already said it.
    if (surfaces > 0 && r.facetedPatches > 0) {
      out.add(l.msgMeshImportedFaceted(r.facetedPatches));
    }
    if (!r.closed) out.add(l.msgMeshImportedOpen);
    return out.join(' ');
  }

  bool importDxf(String path) {
    final s = current;
    if (s == null) return false;
    final tmp = SketchModel('_import');
    List<Geo> incoming;
    try {
      if (!tmp.engine.loadDxf(path)) {
        toast(L.current.msgCouldNotReadDxf);
        return false;
      }
      tmp.refresh();
      incoming = tmp.geometry;
    } finally {
      tmp.dispose();
    }
    if (incoming.isEmpty) {
      toast(L.current.msgDxfNoSupportedEntities);
      return false;
    }
    final layer = editingLayer ?? kDefaultLayer;
    if (!s.layers.contains(layer)) s.layers.add(layer);
    // DXF files carry absolute model coordinates that are often far from the
    // origin (the device log showed an import landing near 10000,-2600 —
    // off-screen and invisible). Inventor drops imported geometry where you
    // place it; here we re-centre the incoming bounding box on the ORIGIN so
    // it always lands in view.
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    void acc(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    for (final g in incoming) {
      // sample the defining points; for arcs/circles include the centre and
      // the radius extent so the box encloses the whole curve
      if (g.type == Geo.circle || g.type == Geo.arc) {
        final r = g.data[2];
        acc(g.data[0] - r, g.data[1] - r);
        acc(g.data[0] + r, g.data[1] + r);
      } else {
        for (var k = 0; k + 1 < g.data.length; k += 2) {
          acc(g.data[k], g.data[k + 1]);
        }
      }
    }
    final dx = minX.isFinite ? -(minX + maxX) / 2 : 0.0;
    final dy = minY.isFinite ? -(minY + maxY) / 2 : 0.0;
    Geo shifted(Geo g) {
      final d = List<double>.of(g.data);
      if (g.type == Geo.circle || g.type == Geo.arc) {
        d[0] += dx;
        d[1] += dy;
      } else {
        for (var k = 0; k + 1 < d.length; k += 2) {
          d[k] += dx;
          d[k + 1] += dy;
        }
      }
      return g.withData(d);
    }

    final next = [
      ...s.geometry,
      for (final g in incoming) shifted(g).onLayer(layer),
    ];
    _rebuildEngine(s, next);
    _reanalyze();
    s.dirty = true;
    toast(L.current.msgImportedEntities(incoming.length));
    Log.i(
        'insert',
        'DXF import: ${incoming.length} entities onto "$layer", '
            'recentred by (${dx.toStringAsFixed(1)},${dy.toStringAsFixed(1)})');
    notifyListeners();
    return true;
  }

  /// Commits a MODEL parameter's equation cell (same as the inline editor,
  /// minus the rename-through-"=" — the name cell handles renames).
  bool renameDimParam(Constraint c, String name) {
    final s = current;
    if (s == null || c.paramName == null) return false;
    name = name.trim();
    if (name == c.paramName) return true;
    if (!isValidParamName(name) || _nameTaken(s, name)) {
      toast(L.current.msgInvalidOrDuplicateParamName);
      return false;
    }
    final old = c.paramName!;
    c.paramName = name;
    _renameRefs(s, old, name);
    s.checkpoint();
    notifyListeners();
    return true;
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
      final picks = List<Offset>.from(toolPoints);
      toolPoints.clear();
      if (res == null) {
        // M198 — a refused fillet says WHAT WOULD FIT. "Pick two lines that
        // can meet" is the wrong sentence for a corner that is perfectly
        // valid and simply too short for the radius asked of it, and the
        // number is the one the user needs anyway.
        if (tool == Tool.fillet && picks.length >= 2) {
          final most = filletMaxRadius(s.geometry, picks[0], picks[1], f.radius);
          if (most != null && most > 1e-6) {
            toast(L.current.msgRadiusPastEdge(
                Fmt.fixed(f.radius, 2), Fmt.fixed(most, 2)));
            notifyListeners();
            return;
          }
        }
        toast(tool == Tool.fillet
            ? L.current.msgPickTwoThatMeet
            : L.current.msgPickTwoNonParallel);
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

      // M197 — the CUT-AWAY CORNER stays, as construction geometry.
      //
      // Device report: "when i make a radius on a midpoint rect the
      // construction lines dont go into the corners anymore and the corners
      // should stay there as construction lines like with trimming". Two
      // things in one sentence, and one cause behind both.
      //
      // A centre rectangle's diagonals are held by coincidences on the corner
      // POINTS of its sides (M92). The fillet moves exactly those points back
      // to the tangent points, so the diagonals walked inward with them and
      // stopped meeting at the centre of anything — in the bundle, diagonal 0
      // started at -29.2119 where the corner is at -34.2119.
      //
      // Keeping the removed spans (M191 does this for trim) fixes both halves
      // at once: the virtual corner becomes a real point again — the far end
      // the two stubs share — so there is something for the diagonals to hang
      // on, and the corner is visibly still there.
      //
      // Four equations per stub for four parameters, so the sketch's degrees
      // of freedom are untouched: the near end is coincident with the line's
      // trimmed endpoint (2), the far end is ON that line (1 — a point-on-
      // curve, which together with the near end IS collinearity but without
      // the dependent row a `collinear` would add), and the two far ends are
      // coincident with each other (2), which puts the corner exactly where
      // the two carriers cross. Every one of them still goes through the
      // over-constrain gate, because being right on paper is not the same as
      // being independent of what the sketch already carries.
      // Only for a REAL corner: both picks are lines that were trimmed, and
      // their moved endpoints sat on top of each other before the fillet. Two
      // lines that merely got extended to meet have no corner to keep, and two
      // PARALLEL lines have no crossing at all — pinning a shared far end onto
      // both carriers would then be unsatisfiable and would take the whole
      // fillet down with it.
      final stubs = <int, int>{}; // seam index -> stub entity
      final sharedCorner = p1s != null &&
          p2s != null &&
          s.geometry[e1].type == Geo.line &&
          s.geometry[e2].type == Geo.line &&
          s.geometry[e1].style != Geo.styleConstruction &&
          s.geometry[e2].style != Geo.styleConstruction &&
          (getPt(s.geometry[e1], p1s) - getPt(s.geometry[e2], p2s)).distance <
              1e-6;
      if (sharedCorner) {
        for (var k = 0; k < 2; k++) {
          final (ent, pt) = res.seams[k];
          final oldG = s.geometry[ent];
          final corner = getPt(oldG, pt!); // where the corner WAS
          final tip = getPt(gs[ent], pt); // where the line ends now
          if ((corner - tip).distance < 1e-9) continue;
          stubs[k] = gs.length;
          gs.add(Geo(Geo.line, [tip.dx, tip.dy, corner.dx, corner.dy],
                  layer: oldG.layer)
              .withStyle(Geo.styleConstruction));
        }
        // Both or neither: one stub alone leaves the corner point held by a
        // single carrier, free to slide along it.
        if (stubs.length != 2) {
          gs.removeRange(newIdx + res.adds.length, gs.length);
          stubs.clear();
        }
      }

      void tryAdd(Constraint c, String why) {
        if (wouldOverconstrain(gs, cons, c)) {
          Log.i('modify', 'corner-stub ${conStr(-1, c)} DROPPED ($why would '
              'over-constrain)');
          return;
        }
        cons.add(c);
      }

      // Everything that still points AT the old corner follows it onto the
      // stub — the diagonals, and any dimension that measured from there.
      // Done before the seam constraints below are added, so it can only ever
      // rewrite what the sketch already had.
      for (var k = 0; k < 2; k++) {
        final stub = stubs[k];
        if (stub == null) continue;
        final (ent, pt) = res.seams[k];
        for (var ci = 0; ci < cons.length; ci++) {
          final c = cons[ci];
          if (!c.pts.any((p) => p.ent == ent && p.pt == pt)) continue;
          cons[ci] = c.withPts([
            for (final p in c.pts)
              if (p.ent == ent && p.pt == pt) PRef(stub, 1) else p
          ]);
          Log.i('modify',
              'corner-stub: ${conStr(ci, c)} re-anchored to the corner (e$stub.p1)');
        }
      }

      for (final entry in stubs.entries) {
        final stub = entry.value;
        final (ent, pt) = res.seams[entry.key];
        tryAdd(
            Constraint(CType.coincident,
                pts: [PRef(stub, 0), PRef(ent, pt!)]),
            'stub start on the trimmed end');
        tryAdd(Constraint(CType.coincident, pts: [PRef(stub, 1)], ents: [ent]),
            'stub far end on its carrier');
      }
      if (stubs.length == 2) {
        tryAdd(
            Constraint(CType.coincident,
                pts: [PRef(stubs[0]!, 1), PRef(stubs[1]!, 1)]),
            'the corner itself');
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
            textPos: Offset(g0.data[0] + (g0.data[2] + 8) * math.cos(midAng),
                g0.data[1] + (g0.data[2] + 8) * math.sin(midAng))));
      } else {
        // chamfer: distx + disty on the two endpoints of the chamfer line
        final ax = g0.data[0],
            ay = g0.data[1],
            bx = g0.data[2],
            by = g0.data[3];
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
        Log.w(
            'modify',
            '${tool.name} at e$e1/e$e2 REJECTED — result cannot be satisfied; '
                'rolling back');
        // M188 — the device reports ("couldn't make a radius on the second
        // corner") could not be diagnosed from the log: a rejection said only
        // THAT the solve failed. The refused set is what tells you why — here
        // it showed both fillet arcs glued to the same endpoint.
        Log.block('modify', '${tool.name} refused this', sketchDump(gs, cons));
        toast(tool == Tool.fillet
            ? L.current.msgFilletBreaksSketch
            : L.current.msgChamferBreaksSketch);
        return; // s.geometry / s.constraints untouched
      }
      Log.i('modify', '${tool.name} at e$e1/e$e2 -> e$newIdx (dimensioned)');
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
      // M185 — inspect what a tool actually produced, at the ONE point every
      // 2D tool passes through.
      //
      // trim, extend, offset, mirror, the pattern builders and every draw
      // tool are pure geometry functions with no logging of their own, and
      // adding it to each would still miss the next one. What matters is not
      // which function ran but whether what it made is drawable: a NaN from a
      // degenerate offset or a zero-length line from a trim at a tangent is
      // dropped silently by Skia, and "my line disappeared" is then a bug
      // with no trace anywhere. Checked here, it always has one.
      for (var i = 0; i < placed.length; i++) {
        final g = placed[i];
        if (!geoFinite(g)) {
          Log.e(
              'layer',
              'tool $tool produced NON-FINITE geometry — Skia will drop it '
                  'and it will look like nothing happened: ${geoStr(i, g)}');
        }
      }
      // M203 — and REFUSE it, rather than logging and committing anyway.
      //
      // The device session shows what "committing as drawn" costs. Two
      // rectangle clicks 20 ms apart at the same y (a tap bounce, not a
      // drawn shape) produced a rectangle with two ZERO-LENGTH sides; the
      // log even says "construction auto-constraints unsatisfied ...
      // committing as drawn WITHOUT them". From that moment the sketch was
      // poisoned: every later drag reported "frame solve unsatisfied" and
      // every new constraint came back "cannot be satisfied", because both
      // gates ask whether the WHOLE sketch is degenerate.
      //
      // Nothing is lost by refusing: the geometry could not be drawn, picked
      // or solved anyway. The tool stays armed, so the next click just works.
      if (hasDegenerateGeometry(placed)) {
        Log.w(
            'layer',
            'tool $tool produced DEGENERATE geometry (zero-length line, '
                'zero-radius/zero-sweep arc) — REFUSED: '
                '${placed.asMap().entries.map((e) => geoStr(e.key, e.value)).join('; ')}');
        toast(L.current.msgShapeHasNoSize);
        toolPoints.clear();
        _hudResetAll();
        notifyListeners();
        return;
      }
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
      if (isRect && (placed.length == 4 || placed.length == 6)) {
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
        // M92 — centre rectangles: the two CONSTRUCTION diagonals, entities
        // 4 and 5, each spanning opposite corners. _rectLines emits corner k
        // as line k's point 0, so diagonal 0 runs corner0 -> corner2 and
        // diagonal 1 corner1 -> corner3. Four coincidents pin all eight
        // diagonal parameters, so the rectangle's DOF is untouched and no row
        // is redundant.
        if (placed.length == 6) {
          final d0 = firstNew + 4, d1 = firstNew + 5;
          s.constraints.addAll([
            Constraint(CType.coincident,
                pts: [PRef(d0, 0), PRef(firstNew + 0, 0)]),
            Constraint(CType.coincident,
                pts: [PRef(d0, 1), PRef(firstNew + 2, 0)]),
            Constraint(CType.coincident,
                pts: [PRef(d1, 0), PRef(firstNew + 1, 0)]),
            Constraint(CType.coincident,
                pts: [PRef(d1, 1), PRef(firstNew + 3, 0)]),
          ]);
        }
      } else if (tool == Tool.polygon && placed.length >= 4) {
        deterministicShape = true;
        // M92 — Inventor's polygon: n edge LINES + a circumscribed
        // CONSTRUCTION circle (the last entity). The set is
        //   * corner coincidents             2n equations
        //   * equal edges, n-1 of them        n-1
        //   * every vertex ON the circle       n
        // = 4n-1 independent equations on 4n+3 parameters, leaving exactly the
        // polygon's 4 DOF: centre x, centre y, radius, rotation. So dimension
        // the centre and make ONE side vertical and the polygon is fully
        // constrained, which is the whole point.
        //
        // Why n-1 equals and not n: with every vertex on one circle, n-1 equal
        // chords force the last one too — the n-th equation would be the
        // redundant row that makes the LM normal equations singular and
        // libslvs call the sketch inconsistent (the same trap documented for
        // the slot's parallel and the arc slot's equal below).
        //
        // Point-on-curve is plain `coincident` with ONE point and ONE entity,
        // exactly as in Inventor — the solver already carries that residual
        // (|q - centre| - r) for circles and arcs.
        final n = placed.length - 1;
        final circ = firstNew + n;
        for (var k = 0; k < n; k++) {
          s.constraints.add(Constraint(CType.coincident, pts: [
            PRef(firstNew + k, 1),
            PRef(firstNew + (k + 1) % n, 0),
          ]));
        }
        for (var k = 0; k < n - 1; k++) {
          s.constraints.add(
              Constraint(CType.equal, ents: [firstNew + k, firstNew + k + 1]));
        }
        for (var k = 0; k < n; k++) {
          s.constraints.add(Constraint(CType.coincident,
              pts: [PRef(firstNew + k, 0)], ents: [circ]));
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
        final l1 = firstNew,
            l2 = firstNew + 1,
            c1 = firstNew + 2,
            c2 = firstNew + 3,
            ax = firstNew + 4;
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
          (placed.length == 4 || placed.length == 6)) {
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
        final o = firstNew,
            inn = firstNew + 1,
            ca = firstNew + 2,
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
        // M114 — the two construction RADII (sweep centre -> cap centre).
        //
        // A construction ARC would need concentric plus both endpoints: six
        // equations on an arc's five parameters, rank five, and that redundant
        // row is precisely what the notes above say makes the solver call the
        // sketch inconsistent. Lines have no such problem — four parameters
        // each, pinned by two coincidents each, so the slot's six DOF are
        // untouched and nothing is redundant.
        //
        // Each radius runs from the rails' shared centre to a cap's centre;
        // point 0 of an arc is its centre, so both ends are ordinary point
        // coincidences.
        if (placed.length == 6) {
          final r1 = firstNew + 4, r2 = firstNew + 5;
          s.constraints.addAll([
            Constraint(CType.coincident, pts: [PRef(r1, 0), PRef(o, 0)]),
            Constraint(CType.coincident, pts: [PRef(r1, 1), PRef(ca, 0)]),
            Constraint(CType.coincident, pts: [PRef(r2, 0), PRef(o, 0)]),
            Constraint(CType.coincident, pts: [PRef(r2, 1), PRef(cb, 0)]),
          ]);
        }
      } else if (tool == Tool.circleTangent && placed.length == 1) {
        deterministicShape = true;
        // Inventor's tangent circle: TANGENT to each of the three picked
        // lines — the picks are the tool points themselves.
        for (final tp in toolPoints.take(3)) {
          final li = nearestLineIdx(gs, tp, exclude: firstNew);
          if (li != null) {
            s.constraints.add(Constraint(CType.tangent, ents: [firstNew, li]));
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
          s.constraints.add(Constraint(CType.coincident, pts: [
            PRef(firstNew, gs[firstNew].type == Geo.arc ? 1 : 0),
            src
          ]));
          if (gs[firstNew].type == Geo.arc &&
              gs[src.ent].type != Geo.polyline) {
            s.constraints
                .add(Constraint(CType.tangent, ents: [firstNew, src.ent]));
          }
        }
      } else if (autoConstrain) {
        for (var i = firstNew; i < gs.length; i++) {
          for (final c in inferConstraints(gs, i)) {
            // A REVERSE bind (an existing point landing on the new curve) is
            // the one inferred relation that can hit an already fully
            // constrained sketch, so it takes the same gate a manual
            // constraint would — Inventor refuses those, it does not stack
            // them. Everything else keeps the historical ungated path.
            if (isReverseBind(c, i) &&
                wouldOverconstrain(gs, s.constraints, c)) {
              Log.i('tool',
                  'auto ${conStr(-1, c)} DROPPED (would over-constrain)');
              continue;
            }
            s.constraints.add(c);
          }
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
          for (final c in inferPointBindings(gs, i, bindOnlyBefore: firstNew)) {
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
      // HUD / Dynamic Input: the values the user TYPED while drawing become
      // persistent driving dimensions (Inventor's "persistent dimensions").
      // Fields left cursor-driven emit nothing. Added before the solve so they
      // size the geometry; a dimension that would overconstrain is demoted to a
      // reference (driven) dimension, and a geometric relation that would is
      // dropped — Inventor's own auto-fallbacks.
      if (hudCommitDims.isNotEmpty) {
        for (final d in _hudBuildDims(gs, firstNew, placed.length)) {
          final over = wouldOverconstrain(gs, s.constraints, d);
          if (d.type == CType.dimension) {
            if (over) d.driven = true;
            ensureParamName(s, d);
            s.constraints.add(d);
          } else if (!over) {
            s.constraints.add(d);
          }
        }
      }
      // Constructions place their geometry ALREADY satisfying their auto-
      // constraints (residual ~1e-14), so this solve is a formality that tidies
      // last-digit noise. If it ever reports failure (a genuine bug upstream),
      // never throw the user's shape away: commit the as-drawn geometry and
      // drop the auto-constraints this commit added, loudly.
      final preSolve = List<Geo>.from(gs);
      final consBefore2 = consAtCommitStart;
      if (!solveConstraints(gs, s.constraints)) {
        Log.e(
            'tool',
            'construction auto-constraints unsatisfied for $tool — '
                'committing as drawn WITHOUT them');
        s.constraints.removeRange(consBefore2, s.constraints.length);
        _rebuildEngine(s, preSolve);
      } else {
        _rebuildEngine(s, gs);
      }
    } else {
      // M203 — a tool that built NOTHING now says so. The rect builders refuse
      // a zero-width or zero-height box here (a 20 ms tap bounce makes one),
      // and a silent return through this branch is indistinguishable in a
      // report from a click that never arrived.
      Log.i(
          'layer',
          'tool $tool built no geometry from ${toolPoints.length} point(s) — '
              'nothing committed, tool stays armed');
    }
    _hudResetAll(); // per-shape HUD state does not carry into the next shape
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

  /// Builds the persistent driving dimensions for the values typed into the
  /// HUD while [tool] was drawn. [firstNew] is the index of the shape's first
  /// entity in [gs]; [placedCount] how many entities it added. Only quantities
  /// with a clean, solver-safe dimension are emitted here — the rest still size
  /// the geometry through the locked cursor, they just carry no label yet.
  List<Constraint> _hudBuildDims(List<Geo> gs, int firstNew, int placedCount) {
    final out = <Constraint>[];
    final d = hudCommitDims;
    double? W = d[HudKind.width],
        H = d[HudKind.height],
        Dia = d[HudKind.diameter],
        R = d[HudKind.radius],
        L = d[HudKind.length],
        A = d[HudKind.angle],
        X = d[HudKind.x],
        Y = d[HudKind.y],
        SW = d[HudKind.slotWidth];

    Offset mid(int e) {
      final g = gs[e];
      return (getPt(g, 0) + getPt(g, 1)) / 2;
    }

    // linear distance between the two endpoints of line [e]
    Constraint distOn(int e, double v, String kind, Offset text) =>
        Constraint(CType.dimension,
            pts: [PRef(e, 0), PRef(e, 1)],
            dimKind: kind,
            value: v.abs(),
            textPos: text);

    // M191 — where a person would put it: just OUTSIDE the shape, beside the
    // side it measures. Offsetting blindly (down for width, right for height)
    // drops the label inside a centred rectangle, and the four sides of the
    // rect tools do not all run the same way round.
    Offset beside(int e, Iterable<int> shape, [double gap = 8]) {
      var cx = 0.0, cy = 0.0, n = 0;
      for (final k in shape) {
        for (final p in [getPt(gs[k], 0), getPt(gs[k], 1)]) {
          cx += p.dx;
          cy += p.dy;
          n++;
        }
      }
      final m = mid(e);
      if (n == 0) return m;
      final away = m - Offset(cx / n, cy / n);
      final len = away.distance;
      return len < 1e-9 ? m : m + away / len * gap;
    }

    switch (tool) {
      case Tool.rectTwoPoint:
      case Tool.rect2PC:
        // The centre-start rectangles add two construction diagonals, so this
        // commits 6 entities, not 4 — and requiring exactly 4 meant a typed
        // width and height sized the geometry and then vanished without a
        // dimension, which is what the device session reported. The four SIDES
        // are the first four either way.
        if (placedCount >= 4) {
          final sides = [for (var k = 0; k < 4; k++) firstNew + k];
          if (W != null) {
            out.add(distOn(firstNew, W, 'distx', beside(firstNew, sides)));
          }
          if (H != null) {
            out.add(
                distOn(firstNew + 1, H, 'disty', beside(firstNew + 1, sides)));
          }
        }
        break;
      case Tool.rect3P:
      case Tool.rect3PC:
        if (placedCount >= 4) {
          final sides = [for (var k = 0; k < 4; k++) firstNew + k];
          if (L != null) {
            out.add(distOn(firstNew, L, 'dist', beside(firstNew, sides)));
          }
          if (W != null) {
            out.add(
                distOn(firstNew + 1, W, 'dist', beside(firstNew + 1, sides)));
          }
        }
        break;
      case Tool.circleCenter:
        if (Dia != null) {
          out.add(Constraint(CType.dimension,
              ents: [firstNew],
              dimKind: 'dia',
              value: Dia.abs(),
              textPos: getPt(gs[firstNew], 0)));
        }
        break;
      case Tool.arcCenter:
        if (R != null) {
          out.add(Constraint(CType.dimension,
              ents: [firstNew],
              dimKind: 'rad',
              value: R.abs(),
              textPos: getPt(gs[firstNew], 0)));
        }
        if (A != null) {
          // 3-point angle: start, vertex(center), end
          out.add(Constraint(CType.dimension,
              pts: [PRef(firstNew, 1), PRef(firstNew, 0), PRef(firstNew, 2)],
              dimKind: 'ang3',
              value: A.abs(),
              textPos: getPt(gs[firstNew], 0)));
        }
        break;
      case Tool.line:
        if (L != null) out.add(distOn(firstNew, L, 'dist', mid(firstNew)));
        if (A != null) {
          // cardinal angles map to an H/V relation (Inventor shows the glyph);
          // other angles size the line but carry no standalone dimension yet.
          final a = ((A % 180) + 180) % 180;
          if (a < 0.5 || a > 179.5) {
            out.add(Constraint(CType.horizontal, ents: [firstNew]));
          } else if ((a - 90).abs() < 0.5) {
            out.add(Constraint(CType.vertical, ents: [firstNew]));
          }
        }
        break;
      case Tool.slotCC:
        if (placedCount == 5) {
          if (L != null) {
            // centre-to-centre = distance between the two cap centres
            out.add(Constraint(CType.dimension,
                pts: [PRef(firstNew + 2, 0), PRef(firstNew + 3, 0)],
                dimKind: 'dist',
                value: L.abs(),
                textPos:
                    (getPt(gs[firstNew + 2], 0) + getPt(gs[firstNew + 3], 0)) /
                        2));
          }
          if (SW != null) out.addAll(_slotWidthDim(gs, firstNew, SW));
        }
        break;
      case Tool.slotOverall:
      case Tool.slotCP:
        if (placedCount == 5 && SW != null) {
          out.addAll(_slotWidthDim(gs, firstNew, SW));
        }
        break;
      case Tool.point:
        // origin-relative horizontal + vertical dimensions (Inventor pins a
        // dynamic-input point to the sketch origin the same way).
        if (X != null) {
          out.add(Constraint(CType.dimension,
              pts: [PRef(firstNew, 0), const PRef(kProjCenter, 0)],
              dimKind: 'distx',
              value: X.abs(),
              textPos: getPt(gs[firstNew], 0) + const Offset(0, -8)));
        }
        if (Y != null) {
          out.add(Constraint(CType.dimension,
              pts: [PRef(firstNew, 0), const PRef(kProjCenter, 0)],
              dimKind: 'disty',
              value: Y.abs(),
              textPos: getPt(gs[firstNew], 0) + const Offset(8, 0)));
        }
        break;
      default:
        // ellipse / polygon: sized through the locked cursor, no dimension yet.
        break;
    }
    return out;
  }

  /// Slot width as the perpendicular gap between the two rails (= 2·r).
  List<Constraint> _slotWidthDim(List<Geo> gs, int firstNew, double w) {
    final l1 = firstNew, l2 = firstNew + 1;
    return [
      Constraint(CType.dimension,
          pts: [PRef(l2, 0), PRef(l1, 0), PRef(l1, 1)],
          dimKind: 'pline',
          value: w.abs(),
          textPos: (getPt(gs[l1], 0) + getPt(gs[l2], 0)) / 2)
    ];
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
      toast(L.current.msgSelectThenToggle(what));
      return;
    }
    final gs = List<Geo>.from(s.geometry);
    // Inventor semantics: if ANY selected entity is not yet of this style,
    // the click converts TO it; only a uniformly-styled selection reverts.
    final convert = selection.any((i) => i < gs.length && gs[i].style != style);
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
    final major =
        Geo(Geo.line, [ma.dx, ma.dy, (c * 2 - ma).dx, (c * 2 - ma).dy])
            .onLayer(layer)
            .withStyle(Geo.styleCenterline);
    final minor =
        Geo(Geo.line, [mi.dx, mi.dy, (c * 2 - mi).dx, (c * 2 - mi).dy])
            .onLayer(layer)
            .withStyle(Geo.styleCenterline);
    final iMaj = gs.length, iMin = gs.length + 1;
    gs
      ..add(major)
      ..add(minor);
    s.constraints.addAll([
      Constraint(CType.coincident, pts: [PRef(iMaj, 0), PRef(ellipseIdx, 1)]),
      Constraint(CType.coincident, pts: [PRef(iMin, 0), PRef(ellipseIdx, 2)]),
      Constraint(CType.midpoint, pts: [PRef(ellipseIdx, 0)], ents: [iMaj]),
      Constraint(CType.midpoint, pts: [PRef(ellipseIdx, 0)], ents: [iMin]),
    ]);
    Log.i('layer', 'ellipse axes committed as centerlines ($iMaj, $iMin)');
  }

  void _committed(SketchModel s, {List<Geo>? tags}) {
    s.refresh(tagSource: tags);
    _syncLayers(s);
    s.dirty = true;
  }

  /// 0 while the sketch-entry camera swing is running, 1 once it has settled
  /// (M88).
  ///
  /// The 2D sketch overlay draws with a FIXED transform while the 3D camera is
  /// still moving, so during the swing the two would disagree and the sketch
  /// would appear to slide across the model. The 3D scene already renders
  /// sketch curves as ribbons, so nothing is lost by keeping the overlay
  /// transparent until the camera arrives.
  double sketchOverlayFade = 1;

  void setSketchOverlayFade(double v) {
    final c = v.clamp(0.0, 1.0);
    if ((c - sketchOverlayFade).abs() < 0.001) return;
    sketchOverlayFade = c;
    notifyListeners();
  }

  /// Model edge highlighted under the cursor while the Project tool is
  /// active (index into [projectableEdges]), or null.
  int? hoverSolidEdge;

  /// M279 — the model FACE under the cursor while the Project tool is active,
  /// as the part-wide edge indices a tap would project.
  ///
  /// Empty when the cursor is over an edge (an edge pick is the narrower
  /// statement and wins) or over nothing. The painter draws exactly this set
  /// hot, so what lights up is what a tap takes — the rule the single-edge
  /// hover has followed since M76.
  List<int> hoverSolidFace = const [];

  void setHover(Offset? w) {
    hoverWorld = w;
    final s = current;
    if (s == null || w == null) {
      hoverEnt = null;
      hoverEdge = null;
      hoverSolidEdge = null;
      hoverSolidFace = const [];
    } else if (tool == Tool.project) {
      hoverSolidEdge = null;
      hoverSolidFace = const [];
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
      // Nothing in the sketch under the cursor? Then offer the 3D model edge,
      // matching the click order in _projectClick so the highlight always
      // shows what a tap would actually project.
      hoverSolidEdge = hoverEnt == null ? projectHoverEdge(w) : null;
      // M279 — and, failing an edge, the whole FACE under the cursor.
      hoverSolidFace = (hoverEnt == null && hoverSolidEdge == null)
          ? projectHoverFace(w)
          : const [];
    } else {
      hoverSolidEdge = null;
      hoverSolidFace = const [];
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

  // Practically-endless 2D zoom. Not literally infinite: outside this band the
  // float math loses precision, so we cap far beyond any real drawing (a
  // ~5-order span each way from 1px/mm).
  static const double minZoom = 1e-4;
  static const double maxZoom = 1e6;

  /// Set when the 2D sketcher is entered, so it opens showing the SAME world
  /// height as the 3D viewport instead of its own unrelated default (zoom 1.0
  /// = 1 mm per logical pixel, which showed roughly a metre of world).
  bool sketchZoomNeedsFit = false;

  /// Called by the 2D viewport once it knows its height.
  void fitSketchZoom(double viewportHeightPx) {
    if (!sketchZoomNeedsFit) return;
    sketchZoomNeedsFit = false;
    final halfH = currentPart?.camera.halfH ?? 27.0;
    if (viewportHeightPx <= 0 || halfH <= 0) return;
    // 3D maps [-halfH, +halfH] onto the viewport height; match it exactly.
    zoom = (viewportHeightPx / (2 * halfH)).clamp(minZoom, maxZoom).toDouble();
    notifyListeners();
  }

  void zoomBy(double factor, {Offset? aroundWorld}) {
    final raw = zoom * factor;
    final z = (raw.isFinite ? raw : zoom).clamp(minZoom, maxZoom).toDouble();
    if (aroundWorld != null && z > 0) {
      pan = aroundWorld + (pan - aroundWorld) * (zoom / z);
    }
    zoom = z;
    notifyListeners();
  }

  // ---- save / load / preview ----
  Future<bool> saveSketch(String name) async {
    final sw = Stopwatch()..start();
    try {
      return await _saveSketchInner(name);
    } finally {
      Perf.record('io.saveSketch', sw.elapsedMicroseconds / 1000.0);
    }
  }

  Future<bool> _saveSketchInner(String name) async {
    final s = sketches[name];
    if (s == null || _docsDir == null) return false;
    _ensureStaged(name);
    final ok = s.engine.saveDxf(_dxfFile(name).path);
    try {
      File('${_stage(name).path}/$kSketchBase.cons.json')
          .writeAsStringSync(encodeConstraints(s.constraints));
      File('${_stage(name).path}/$kSketchBase.params.json')
          .writeAsStringSync(encodeUserParams(s.userParams));
      File('${_stage(name).path}/$kSketchBase.texts.json')
          .writeAsStringSync(encodeTexts(s.texts));
      File('${_stage(name).path}/$kSketchBase.images.json')
          .writeAsStringSync(encodeImages(s.images));
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
      final sf = File('${_stage(name).path}/$kSketchBase.splines.json');
      if (spl.isEmpty) {
        if (sf.existsSync()) sf.deleteSync();
      } else {
        sf.writeAsStringSync(jsonEncode(spl));
      }
      // Gear parameter blocks ride in their own sidecar keyed by entity index.
      // The DXF only carries a gear's baked outline; we store the compact
      // editable form (centre, handle + the parameter block) so the gear
      // reloads as a live, draggable gear rather than a dumb polygon. The
      // human-readable params travel alongside for inspection / future tools.
      final grs = <String, dynamic>{};
      for (var i = 0; i < s.geometry.length; i++) {
        final g = s.geometry[i];
        final gp = gearParams(g);
        if (gp != null) grs['$i'] = {'d': g.data, 'p': gp.toJson()};
      }
      final gf = File('${_stage(name).path}/$kSketchBase.gears.json');
      if (grs.isEmpty) {
        if (gf.existsSync()) gf.deleteSync();
      } else {
        gf.writeAsStringSync(jsonEncode(grs));
      }
      // Line styles (centerlines) ride in their own sidecar, same scheme.
      final sty = <String, int>{};
      for (var i = 0; i < s.geometry.length; i++) {
        if (s.geometry[i].style != Geo.styleNormal) {
          sty['$i'] = s.geometry[i].style;
        }
      }
      final stf = File('${_stage(name).path}/$kSketchBase.styles.json');
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
      final pf = File('${_stage(name).path}/$kSketchBase.proj.json');
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
      // The marker is stored as its position within the PERSISTED list —
      // when an empty "0" is skipped above, the index must shift with it.
      var eosPersist = 0;
      for (var i = 0; i < s.layers.length && i < s.eosAfter; i++) {
        if (persistLayers.contains(s.layers[i])) eosPersist++;
      }
      File('${_stage(name).path}/$kSketchBase.layers.json')
          .writeAsStringSync(jsonEncode({
        'version': 3,
        'layers': persistLayers,
        'hidden': s.hiddenLayers.toList(),
        'locked': s.lockedLayers.toList(),
        'eos': eosPersist, // M51: End-of-Sketch marker
      }));
    } catch (e) {
      Log.w('state', 'layer sidecar write failed: $e');
    }
    await _writePreview(name, s);
    if (!_commitStage(name, 'sketch')) return false;
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
      // M237 — no ground. The card paints its own surface behind the PNG, so
      // a still written in one scheme still reads correctly in the other and a
      // cached file never goes stale. (Same rule as _writePartPreview.)
      // M220 — the card shows the text too, because the text IS geometry now
      // (and a thumbnail that omitted half the drawing was never right).
      final geos = [...s.geometry, ...textGeometry(s)];
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
        final scale =
            0.85 * math.min(w / (dx <= 0 ? 1 : dx), h / (dy <= 0 ? 1 : dy));
        Offset map(double x, double y) => Offset(
            w / 2 + (x - (minx + maxx) / 2) * scale,
            h / 2 - (y - (miny + maxy) / 2) * scale);
        final p = Paint()
          ..color = T.ink
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

  // ==== M345 — COPY & PASTE ==============================================
  //
  // "Copy paste should work over the whole app. Everywhere with everything."
  //
  // ONE CLIPBOARD, FIVE PAYLOADS, ONE PASTE. [clipboard] holds a single typed
  // [ClipContent] (clipboard.dart says why it is typed and why there is only
  // one), every Copy in the app fills it, and [paste] is the ONE command that
  // empties it. What a paste MEANS is decided by the pair (payload, place):
  //
  //                    | in a 2D sketch      | in a part          | in an assembly     | in the gallery
  //   sketch geometry  | into that sketch    | a sketch on a plane| —                  | a new 2D document
  //   a solid body     | (finish the sketch) | a new body         | a part + component | a new part document
  //   a component      | —                   | —                  | another occurrence | —
  //   a part document  | —                   | a derived body     | a component        | a duplicate
  //   a sketch document| into that sketch    | a sketch on a plane| —                  | a duplicate
  //
  // Every cell that is a dash says so, in words, at the moment it is tried —
  // "an assembly holds components, not sketches" tells the user where the
  // thing they copied does go. A disabled Paste that never explains itself is
  // the failure mode this table was written to avoid.
  //
  // WHAT A COPY IS. A copy is a COPY: independent geometry, not a link. That
  // is the difference between this and M255's Make Part, which is a link and
  // says so in its name. Pasting a whole part DOCUMENT is the one deliberate
  // exception — that is Inventor's Derive, it is what the user asked for by
  // naming a document rather than a body, and the toast says it is linked.
  //
  // WHERE A PASTE LANDS. At the coordinates it was copied from. See
  // [SketchClip] for why that is right for a CAD document and why "at the
  // cursor" is the exception ([pasteHere]) rather than the rule.

  ClipContent? _clip;

  /// What is on the clipboard, or null when nothing has been copied.
  ClipContent? get clipboard => _clip;

  /// True while a paste is waiting for the plane its sketch should land on.
  ///
  /// Armed by [paste] in a part with sketch geometry on the clipboard, and
  /// read by [planePicked], [facePicked] and [startSketchOnWorkPlane] — the
  /// three ways a plane is named in this app, so the paste can be aimed at an
  /// origin plane, a solid face or a work plane without any of them growing a
  /// command of their own.
  bool _pastePlaneArmed = false;

  bool get pastingOntoPlane => _pastePlaneArmed;

  /// Puts [c] on the clipboard and says so.
  void _clipTake(ClipContent c, {required bool cut}) {
    _clip = c;
    Log.i('clip', '${cut ? 'cut' : 'copy'} ${c.runtimeType} "${c.label}"');
    notifyListeners();
  }

  /// True when the clipboard holds something this document could take. Reads
  /// like the Paste row: the menus use it to decide whether to OFFER Paste,
  /// which is different from what happens when it is pressed (that says why,
  /// out loud — see the table above).
  bool get canPaste {
    final c = _clip;
    if (c == null) return false;
    if (isHome) return c is DocumentClip || c is SketchClip || c is BodyClip;
    if (currentAssembly != null) {
      return c is ComponentClip || c is BodyClip || c is DocumentClip;
    }
    // A SKETCH being open decides before the part does, and the order is the
    // whole rule: inside a part with the 2D editor open, the thing in front of
    // the user is the sketch, and a body pasted into it would land in the part
    // behind their back.
    if (current != null) return c is SketchClip || _isSketchDoc(c);
    if (currentPart != null) return c is! ComponentClip;
    return false;
  }

  bool _isSketchDoc(ClipContent c) =>
      c is DocumentClip && !isPartName(c.name) && !isAssemblyName(c.name);

  // ---- copy: out of a 2D sketch ------------------------------------------

  /// Copies the selected sketch entities. [cut] deletes them afterwards.
  ///
  /// A constraint comes along only when BOTH of its ends were selected — see
  /// [sketchClip]. That is why copying "half a rectangle" gives you two lines
  /// and no dimensions between them and its other half: the alternative is a
  /// dimension pointing at whatever entity happens to occupy that index in the
  /// sketch it lands in.
  bool copySelection({bool cut = false}) {
    final s = current;
    if (s == null) return false;
    final sel = <int>{
      for (final i in selection)
        if (i >= 0 && i < s.geometry.length) i
    };
    if (sel.isEmpty) {
      toast(L.current.msgSelectThenCopy);
      return false;
    }
    _clipTake(
        sketchClip(
          geometry: s.geometry,
          constraints: s.constraints,
          layers: s.layers,
          sourceDoc: curTab ?? s.name,
          sourceSketch: s.name,
          entities: sel,
        ),
        cut: cut);
    if (cut) {
      final n = deleteSelection();
      if (n > 0) toast(L.current.msgCutEntities(n));
      return n > 0;
    }
    toast(L.current.msgCopiedEntities(sel.length));
    return true;
  }

  /// Copies the WHOLE sketch that is open — the browser's Copy on a sketch
  /// row, and Ctrl+C with nothing selected.
  bool copyWholeSketch(SketchModel s, {String? plane}) {
    _clipTake(
        sketchClip(
          geometry: s.geometry,
          constraints: s.constraints,
          layers: s.layers,
          sourceDoc: curTab ?? s.name,
          sourceSketch: s.name,
          userParams: s.userParams,
          texts: s.texts,
          images: _clipImages(curTab ?? s.name, s),
          hidden: s.hiddenLayers,
          locked: s.lockedLayers,
          plane: plane,
        ),
        cut: false);
    toast(L.current.msgCopiedSketch(s.name));
    return true;
  }

  /// Copies one of the open part's child sketches. [cut] deletes it, which is
  /// refused (with a reason) while a feature consumes it — the same rule its
  /// Delete follows, for the same reason.
  bool copyChildSketch(String name, {bool cut = false}) {
    final p = currentPart;
    final cs = p?.sketchByName(name);
    if (p == null || cs == null) return false;
    _clipTake(
        sketchClip(
          geometry: cs.model.geometry,
          constraints: cs.model.constraints,
          layers: cs.model.layers,
          sourceDoc: p.name,
          sourceSketch: cs.model.name,
          userParams: cs.model.userParams,
          texts: cs.model.texts,
          images: _clipImages(p.name, cs.model),
          hidden: cs.model.hiddenLayers,
          locked: cs.model.lockedLayers,
          plane: cs.plane,
        ),
        cut: cut);
    if (cut) {
      if (!deleteChildSketch(cs)) return false; // it said why
      toast(L.current.msgCutSketch(name));
      return true;
    }
    toast(L.current.msgCopiedSketch(name));
    return true;
  }

  /// The images of [s], with the absolute path of each one's file resolved
  /// against the document [doc] it lives in.
  ///
  /// Not [imagePath], which resolves against the CURRENT tab: a sketch can be
  /// copied out of a document that is not the one on screen (a gallery card),
  /// and a picture is not a thing to guess the location of.
  List<ClipImage> _clipImages(String doc, SketchModel s) {
    if (s.images.isEmpty || _docsDir == null) return const [];
    final stage = _stage(doc).path;
    return [
      for (final i in s.images)
        ClipImage(
            i,
            File('$stage/images/${i.file}').existsSync()
                ? '$stage/images/${i.file}'
                : File('$stage/${i.file}').existsSync()
                    ? '$stage/${i.file}'
                    : null)
    ];
  }

  // ---- copy: a solid body ------------------------------------------------

  /// Copies a solid body of the open part.
  ///
  /// The B-Rep is written to a STEP file NOW, in the app's cache, and the clip
  /// points at that file. Three things follow from it, and all three are the
  /// point: the copy survives its origin being closed, edited or deleted; the
  /// same clip can be pasted any number of times; and what a paste produces is
  /// an ordinary imported body (M111), which the part format already knows how
  /// to save and re-read.
  bool copyBody(String bodyName, {bool cut = false}) {
    final p = currentPart;
    if (p == null || _docsDir == null) return false;
    final solid = bodySolid(p, bodyName);
    if (solid == null) {
      toast(L.current.msgNoSuchBody(bodyName));
      return false;
    }
    final dir = Directory('${_cacheRoot.path}/clipboard');
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
    } catch (e) {
      Log.w('clip', 'could not clear the clipboard folder: $e');
    }
    final step = '${dir.path}/body.step';
    if (!partKernel.exportStep([solid], step) || !File(step).existsSync()) {
      // Without a file there is nothing to paste that would survive a
      // restart, and a clipboard that quietly holds a body which cannot be
      // pasted is worse than a copy that failed loudly.
      toast(L.current.msgCopyBodyFailed(partKernel.lastError));
      Log.w('clip', 'STEP export of "$bodyName" failed: ${partKernel.lastError}');
      return false;
    }
    _clipTake(
        BodyClip(
            sourceDoc: p.name,
            bodyName: bodyName,
            stepPath: step,
            volume: solid.volume),
        cut: cut);
    if (cut) {
      if (deleteBody(bodyName) == 0) return false;
      toast(L.current.msgCutBody(bodyName));
      return true;
    }
    toast(L.current.msgCopiedBody(bodyName));
    return true;
  }

  // ---- copy: an assembly component ---------------------------------------

  /// Copies a placed component. The clip is the OCCURRENCE — the document it
  /// is an instance of, and where it sat — so a paste is a second instance of
  /// the same part rather than a second part.
  bool copyComponent(AssemblyOccurrence o, {bool cut = false}) {
    final a = currentAssembly;
    if (a == null) return false;
    if (o.isPatternElement) {
      // Same rule as [copySelectedComponent]: a copy of an element would be an
      // ordinary component that happened to look like one, and the next
      // regeneration would leave it behind.
      toast(L.current.msgCannotCopyAnElement);
      return false;
    }
    _clipTake(
        ComponentClip(
            source: o.source,
            sourceKind: o.sourceKind,
            placement: o.placement,
            sourceAssembly: a.name),
        cut: cut);
    if (cut) {
      deleteOccurrence(o);
      toast(L.current.msgCutComponent(o.id));
      return true;
    }
    toast(L.current.msgCopiedComponent(o.id));
    return true;
  }

  // ---- copy: a whole document (the gallery) ------------------------------

  /// Copies a document off the gallery. The clip is its NAME and kind — a
  /// document is a file, and a copy of one is a thing the paste makes, not a
  /// thing the clipboard carries.
  bool copyDocument(String name) {
    if (!docNameExists(name)) return false;
    final kind = isAssemblyName(name)
        ? kAssemblyDocKind
        : isPartName(name)
            ? 'part'
            : 'sketch';
    _clipTake(DocumentClip(name, kind), cut: false);
    toast(L.current.msgCopiedDocument(name));
    return true;
  }

  /// Copy for whatever is in front of the user right now — what Ctrl+C means.
  ///
  /// The order is the order of the thing they are most likely looking at: a
  /// selection inside the sketch they are editing, then the sketch, then the
  /// body or component that is selected in 3D.
  bool copyCurrent({bool cut = false}) {
    final a = currentAssembly;
    if (a != null) {
      final o = a.selected;
      if (o == null) {
        toast(L.current.msgSelectComponentToCopy);
        return false;
      }
      return copyComponent(o, cut: cut);
    }
    final s = current;
    if (s != null) {
      if (selection.isNotEmpty) return copySelection(cut: cut);
      // Nothing selected: the thing in front of the user is the SKETCH. A cut
      // of a whole child sketch is its deletion, which has a command that
      // knows the rules (a consumed sketch cannot go); a 2D DOCUMENT has no
      // "cut itself" — there is nothing left to be standing in afterwards —
      // so that one copies and says so.
      final cs = _activeChildSketch();
      if (cs != null) return copyChildSketch(cs.model.name, cut: cut);
      return copyWholeSketch(s);
    }
    final p = currentPart;
    if (p != null) {
      final b = selectedBody;
      if (b == null) {
        toast(L.current.msgSelectBodyToCopy);
        return false;
      }
      return copyBody(b, cut: cut);
    }
    return false;
  }

  // ---- paste -------------------------------------------------------------

  /// The one Paste. See the table at the head of this section.
  ///
  /// Returns how many things it made (0 when it did nothing, having said why).
  Future<int> paste() => _paste();

  /// Paste AT THE CURSOR — the deliberate exception to "a paste keeps its
  /// coordinates" ([SketchClip]). Only sketch geometry has a cursor to land
  /// at; everything else falls through to the ordinary paste.
  Future<int> pasteHere([Offset? at]) => _paste(at: at ?? lastPointerWorld);

  Future<int> _paste({Offset? at}) async {
    final c = _clip;
    if (c == null) {
      toast(L.current.msgClipboardEmpty);
      return 0;
    }
    switch (c) {
      case SketchClip():
        return _pasteSketchClip(c, at: at);
      case BodyClip():
        return _pasteBodyClip(c);
      case ComponentClip():
        return _pasteComponentClip(c);
      case DocumentClip():
        return _pasteDocumentClip(c, at: at);
    }
  }

  /// Sketch geometry: into the open sketch, onto a plane of the open part, or
  /// as a new 2D document in the gallery.
  Future<int> _pasteSketchClip(SketchClip clip, {Offset? at}) async {
    if (current != null) {
      final n = pasteIntoSketch(clip,
          delta: at == null ? Offset.zero : at - _clipAnchor(clip));
      if (n > 0) toast(L.current.msgPastedEntities(n));
      return n;
    }
    if (currentPart != null) {
      // Nothing has been named to paste onto, so ask for it — with the three
      // ways of naming a plane already live (an origin plane, a face, a work
      // plane), rather than a fourth picker of its own.
      startPastePlanePick();
      return 0;
    }
    if (currentAssembly != null) {
      toast(L.current.msgAssemblyTakesNoSketch);
      return 0;
    }
    final name = await newSketchDocumentFrom(clip);
    return name == null ? 0 : 1;
  }

  /// Where a "paste here" measures from: the middle of the copied geometry, so
  /// the cursor ends up in the middle of what arrives.
  Offset _clipAnchor(SketchClip clip) => clip.bounds?.center ?? Offset.zero;

  /// A solid body: a new body in the open part, a part plus a component in an
  /// assembly, a new part document in the gallery.
  Future<int> _pasteBodyClip(BodyClip clip) async {
    if (currentPart != null && current != null) {
      toast(L.current.msgFinishSketchToPaste);
      return 0;
    }
    final p = currentPart;
    if (p != null) {
      final n = _readClipBodies(clip, into: p, doc: curTab!);
      if (n > 0) {
        applyEndOfPart(p);
        p.dirty = true;
        await savePart(curTab!);
        toast(L.current.msgPastedBody(clip.bodyName));
        notifyListeners();
      }
      return n;
    }
    final made = await newPartDocumentFrom(clip);
    if (made == null) return 0;
    final a = currentAssembly;
    if (a == null) return 1;
    final wasEmpty = a.isEmpty;
    final occ = await placeComponent(made, at: Placement.identity);
    if (occ == null) return 0;
    if (wasEmpty) a.needsFit = true;
    toast(L.current.msgPastedBodyAsComponent(made));
    unawaited(saveAssembly(a.name));
    return 1;
  }

  /// A component: another occurrence of the same document, in whichever
  /// assembly is open — the one it came from or a different one.
  Future<int> _pasteComponentClip(ComponentClip clip) async {
    final a = currentAssembly;
    if (a == null) {
      toast(L.current.msgPasteComponentNeedsAssembly);
      return 0;
    }
    if (!docNameExists(clip.source)) {
      toast(L.current.msgAsmNoSuchPart(clip.source));
      return 0;
    }
    // Clear of what is already there, from where the original sat: pasting a
    // component exactly on top of the one it was copied from is a placement
    // nobody can see and nobody wants. Same arithmetic as Copy Components.
    final occ = await placeComponent(clip.source,
        at: Placement(clip.placement.rot,
            clip.placement.at + nextPlacement(a, null), clip.placement.reflect));
    if (occ == null) return 0;
    toast(L.current.msgPastedComponent(occ.id));
    return 1;
  }

  /// A whole document. In the gallery that is a duplicate; in an assembly a
  /// placed component; in a part a DERIVED body (Inventor's Derive — a link,
  /// and the toast says so); in a sketch, the sketch's own geometry.
  Future<int> _pasteDocumentClip(DocumentClip clip, {Offset? at}) async {
    if (!docNameExists(clip.name)) {
      toast(L.current.msgNoSuchDocument(clip.name));
      return 0;
    }
    final isSketchDoc = !isPartName(clip.name) && !isAssemblyName(clip.name);
    if (isSketchDoc && (current != null || currentPart != null)) {
      final sk = await _sketchClipOfDocument(clip.name);
      if (sk == null) return 0;
      return _pasteSketchClip(sk, at: at);
    }
    if (currentAssembly != null) {
      if (isSketchDoc) {
        toast(L.current.msgAssemblyTakesNoSketch);
        return 0;
      }
      final occ = await placeComponent(clip.name);
      if (occ == null) return 0;
      toast(L.current.msgPastedComponent(occ.id));
      return 1;
    }
    final p = currentPart;
    if (p != null && isPartName(clip.name)) {
      if (current != null) {
        toast(L.current.msgFinishSketchToPaste);
        return 0;
      }
      return _deriveInto(p, clip.name);
    }
    if (isHome) {
      final copy = await duplicateDocument(clip.name);
      if (copy == null) return 0;
      toast(L.current.msgPastedDocument(copy));
      return 1;
    }
    toast(L.current.msgCannotPasteHere);
    return 0;
  }

  /// Inventor's Derive: [source]'s first solid body, LINKED, as a body of [p].
  ///
  /// Reached by pasting a part document into a part. Deliberately a link and
  /// not a copy — the user named a document rather than a body, and a document
  /// is the thing that goes on being edited. M255 built all of this; here it
  /// is reached from the clipboard instead of from Make Part's dialog.
  Future<int> _deriveInto(PartModel p, String source) async {
    if (source == p.name) {
      toast(L.current.msgCannotDeriveFromItself);
      return 0;
    }
    if (_sourceModel(source) == null) {
      try {
        _componentModels[source] = await _loadPartModel(source);
      } catch (e, st) {
        Log.e('clip', 'could not load "$source" to derive from', e, st);
      }
    }
    final origin = _sourceModel(source);
    final body = origin == null ? null : _firstBodyOf(origin);
    if (origin == null || body == null) {
      toast(L.current.msgNoBodyIn(source));
      return 0;
    }
    _partCheckpoint(p);
    final link = DeriveFeature(
      name: source,
      bodyName: p.nextSolidName(),
      sourceDoc: source,
      sourceBody: body,
    )..seq = p.nextSeq();
    link.source = origin;
    p.appendFeature(link);
    applyEndOfPart(p);
    if (recomputeAllFeatures(p, partKernel)) _syncSolidProjections(p);
    p.dirty = true;
    if (curTab != null) await savePart(curTab!);
    toast(L.current.msgPastedDerived(source));
    notifyListeners();
    return 1;
  }

  String? _firstBodyOf(PartModel p) {
    for (final f in p.features) {
      if (f.solid != null && !f.consumedByJoin) return f.bodyName;
    }
    return null;
  }

  // ---- paste: the sketch side --------------------------------------------

  /// Merges [clip] into the sketch that is open. Returns how many entities
  /// arrived, and SELECTS them — the next gesture then moves what was just
  /// pasted and nothing else.
  int pasteIntoSketch(SketchClip clip,
      {Offset delta = Offset.zero, String? onLayer}) {
    final s = current;
    if (s == null) return 0;
    final layer = onLayer ?? (inEditMode ? editingLayer : null);
    if (layer != null && layerLocked(layer)) {
      toast(L.current.msgLayerLocked(layer));
      return 0;
    }
    if (layer != null && layerRolledBack(layer)) {
      toast(L.current.msgTargetBelowEos(layer));
      return 0;
    }
    final n = _applySketchClip(s, clip,
        doc: curTab ?? s.name,
        delta: delta,
        // In edit mode everything lands on the layer the user has open: this
        // is where they are working, and geometry arriving on a layer they
        // cannot see is geometry they will report as lost.
        forceLayer: layer);
    if (n > 0 && curTab != null) {
      if (currentPart != null) {
        savePart(curTab!);
      } else {
        saveSketch(curTab!);
      }
    }
    return n;
  }

  /// Copies everything on one layer — the layer row's Copy.
  ///
  /// A layer is the closest thing a sketch has to a group, so this is how a
  /// whole sub-drawing travels without having to be rubber-banded first.
  bool copyLayer(String layer, {bool cut = false}) {
    final s = current;
    if (s == null) return false;
    final ents = <int>{
      for (var i = 0; i < s.geometry.length; i++)
        if (s.geometry[i].layer == layer) i
    };
    if (ents.isEmpty) {
      toast(L.current.msgSelectThenCopy);
      return false;
    }
    _clipTake(
        sketchClip(
          geometry: s.geometry,
          constraints: s.constraints,
          layers: s.layers,
          sourceDoc: curTab ?? s.name,
          sourceSketch: s.name,
          entities: ents,
        ),
        cut: cut);
    toast(L.current.msgCopiedEntities(ents.length));
    return true;
  }

  /// Pastes onto ONE named layer — the layer row's Paste, which is how a paste
  /// is aimed at a layer that is not the one being edited.
  int pasteIntoLayer(String layer) {
    final c = _clip;
    if (c is! SketchClip) {
      toast(c == null
          ? L.current.msgClipboardEmpty
          : L.current.msgCannotPasteHere);
      return 0;
    }
    final n = pasteIntoSketch(c, onLayer: layer);
    if (n > 0) toast(L.current.msgPastedEntities(n));
    return n;
  }

  /// Pastes the clipboard's sketch onto a named plane — an origin plane by
  /// key, or a work plane (or face) by frame. The browser's "Paste Sketch
  /// Here"; the viewport's version of the same thing goes through
  /// [startPastePlanePick].
  int pasteSketchOnto(String plane, [PlaneFrame? frame, SketchFaceSel? ref]) {
    final c = _clip;
    if (c is! SketchClip) {
      toast(c == null
          ? L.current.msgClipboardEmpty
          : L.current.msgCannotPasteHere);
      return 0;
    }
    final n = pasteSketchOnPlane(c, plane, frame, ref);
    if (n > 0) notifyListeners();
    return n;
  }

  /// The one implementation of "put this clip into this sketch".
  ///
  /// [fresh] is a sketch that was created FOR the clip (a paste onto a plane,
  /// a new document): it adopts the source's layer order, eye/lock state and
  /// user parameters, because there is nothing there to disagree with. A paste
  /// into an existing sketch adopts none of that — it merges.
  int _applySketchClip(
    SketchModel s,
    SketchClip clip, {
    required String doc,
    Offset delta = Offset.zero,
    String? forceLayer,
    bool fresh = false,
    bool active = true,
  }) {
    if (clip.geometry.isEmpty && clip.texts.isEmpty) {
      toast(L.current.msgClipboardEmpty);
      return 0;
    }
    if (fresh) {
      for (final l in clip.layers) {
        if (!s.layers.contains(l)) s.layers.add(l);
      }
      s.hiddenLayers.addAll(clip.hidden);
      s.lockedLayers.addAll(clip.locked);
      for (final u in clip.userParams) {
        if (!s.userParams.any((e) => e.name == u.name)) {
          s.userParams.add(UserParam(u.name, u.value, u.expr));
        }
      }
    } else if (forceLayer == null) {
      // Keep each entity on the layer it was drawn on; create the ones this
      // sketch does not have yet, live (above the End-of-Sketch marker) —
      // pasted geometry that arrives rolled back is invisible for a reason
      // nobody would guess.
      for (final l in clip.layers) {
        if (!s.layers.contains(l)) s.insertLayerAboveMarker(l);
      }
    }
    final taken = <String>{
      for (final c in s.constraints)
        if (c.paramName != null) c.paramName!,
      for (final u in s.userParams) u.name,
    };
    final res = mergeSketchClip(
      geometry: s.geometry,
      constraints: s.constraints,
      clip: clip,
      delta: delta,
      layer: forceLayer,
      takenNames: taken,
    );
    s.constraints
      ..clear()
      ..addAll(res.constraints);
    s.texts.addAll(res.texts);
    _adoptImages(s, clip, doc, delta);
    _rebuildEngine(s, res.geometry, active: active);
    // The expression chase inside that rebuild can rebuild again through the
    // ordinary (active) path, so put the CURRENT sketch's analysis back rather
    // than leaving another sketch's answer in it.
    if (!active) _reanalyze();
    if (active) {
      selection
        ..clear()
        ..addAll(res.pasted);
      snap = null;
    }
    if (res.renamedParams.isNotEmpty) {
      Log.i('clip',
          'renamed on paste: ${res.renamedParams.entries.map((e) => "${e.key}->${e.value}").join(", ")}');
    }
    if (res.droppedExpressions > 0) {
      Log.i('clip',
          '${res.droppedExpressions} expression(s) dropped: their parameters did not come along');
      toast(L.current.msgPasteDroppedExpressions(res.droppedExpressions));
    }
    Log.i('clip',
        'pasted ${res.pasted.length} entities into "${s.name}" of "$doc"');
    return res.pasted.length;
  }

  /// Copies the clip's pictures into the target document and adds the records.
  ///
  /// A [SketchImage] names a file relative to the document it lives in, so
  /// pasting the record alone would draw nothing. The bytes are copied under a
  /// fresh name (two documents can both hold an "img_1730.png" that is not the
  /// same picture), and an image whose file has gone is dropped rather than
  /// pasted as an empty rectangle.
  void _adoptImages(
      SketchModel s, SketchClip clip, String doc, Offset delta) {
    if (clip.images.isEmpty || _docsDir == null) return;
    final dir = Directory('${_stage(doc).path}/images');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    for (final ci in clip.images) {
      final src = ci.path;
      if (src == null || !File(src).existsSync()) {
        Log.w('clip', 'image "${ci.image.file}" is gone — not pasted');
        continue;
      }
      final ext = ci.image.file.contains('.')
          ? ci.image.file.split('.').last
          : 'img';
      var name = 'img_${DateTime.now().microsecondsSinceEpoch}.$ext';
      var n = 2;
      while (File('${dir.path}/$name').existsSync()) {
        name = 'img_${DateTime.now().microsecondsSinceEpoch}_$n.$ext';
        n++;
      }
      try {
        File(src).copySync('${dir.path}/$name');
      } catch (e) {
        Log.w('clip', 'could not copy image "${ci.image.file}": $e');
        continue;
      }
      s.images.add(SketchImage(name, ci.image.x + delta.dx,
          ci.image.y + delta.dy, ci.image.w, ci.image.h,
          layer: ci.image.layer));
    }
  }

  // ---- paste onto a plane -------------------------------------------------

  /// Arms the plane pick for a paste: the next origin plane, solid face or
  /// work plane named becomes a NEW sketch holding the clip.
  void startPastePlanePick() {
    final p = currentPart;
    if (p == null) return;
    cancel3DCommands(); // M230 — one armed command at a time
    _pastePlaneArmed = true;
    _planesAutoShown = true;
    p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = true;
    pickPlane = true;
    toast(L.current.msgSelectPlaneForPaste);
    notifyListeners();
  }

  void cancelPastePlanePick() {
    if (!_pastePlaneArmed) return;
    _pastePlaneArmed = false;
    cancelPlanePick();
  }

  /// The armed paste, now that a plane has been named. Called by the three
  /// pick paths; returns true when it consumed the pick.
  bool _pasteOnPickedPlane(String plane, PlaneFrame? frame,
      [SketchFaceSel? ref]) {
    if (!_pastePlaneArmed) return false;
    _pastePlaneArmed = false;
    final p = currentPart;
    final clip = _clip;
    if (p == null || clip is! SketchClip) {
      cancelPlanePick();
      return true;
    }
    pickPlane = false;
    if (_planesAutoShown) {
      p.vis['yz'] = p.vis['xz'] = p.vis['xy'] = false;
    }
    _planesAutoShown = false;
    final n = pasteSketchOnPlane(clip, plane, frame, ref);
    if (n > 0) notifyListeners();
    return true;
  }

  /// Creates a child sketch on [plane] holding [clip], and returns how many
  /// entities it holds.
  ///
  /// It does NOT open the 2D editor. Every other way of making a sketch does,
  /// because an empty sketch is only useful once you are drawing in it; this
  /// one arrives finished, and the next thing the user wants is to extrude it.
  int pasteSketchOnPlane(SketchClip clip, String plane,
      [PlaneFrame? frame, SketchFaceSel? ref]) {
    final p = currentPart;
    if (p == null) return 0;
    _partCheckpoint(p); // one paste = one step of the part journal
    final sk = SketchModel(p.nextSketchName());
    p.appendChildSketch(
        ChildSketch(sk, plane, frame, true, false, p.nextSeq(), ref));
    _admitNewSketchRow(p);
    final n = _applySketchClip(sk, clip,
        doc: p.name, fresh: true, active: false);
    sk.resetHistory(); // the pasted state is this sketch's baseline
    p.dirty = true;
    if (curTab != null) savePart(curTab!);
    Log.i('clip',
        'pasted sketch "${sk.name}" on $plane of "${p.name}" ($n entities)');
    toast(L.current.msgPastedSketchOnPlane(sk.name));
    return n;
  }

  // ---- new documents out of a clip ---------------------------------------

  /// A new 2D sketch document holding [clip], opened.
  Future<String?> newSketchDocumentFrom(SketchClip clip, {String? name}) async {
    final want = (name ?? clip.sourceSketch).trim();
    final clean = _freeDocumentName(want.isEmpty ? 'Sketch' : want);
    final bad = validateSketchName(clean);
    if (bad != null) {
      toast(bad);
      return null;
    }
    await openSketch(clean); // creates it: there is no file yet
    final s = sketches[clean];
    if (s == null) return null;
    _applySketchClip(s, clip, doc: clean, fresh: true);
    s.resetHistory();
    await saveSketch(clean);
    Log.i('clip', 'new sketch document "$clean" from "${clip.sourceSketch}"');
    toast(L.current.msgPastedSketchDocument(clean));
    notifyListeners();
    return clean;
  }

  /// A new part document holding [clip]'s body, NOT opened.
  ///
  /// Not opened for the same reason Make Part does not open the part it makes:
  /// the paste that asked for this is on its way somewhere else (an assembly,
  /// or back to the gallery), and a part tab appearing on the way there is a
  /// document nobody asked to edit.
  Future<String?> newPartDocumentFrom(BodyClip clip, {String? name}) async {
    final clean = _freeDocumentName(name ?? clip.bodyName);
    if (!await createNamedPart(clean, open: false)) {
      toast(L.current.msgNameTaken(clean));
      return null;
    }
    final made = parts[clean];
    if (made == null) return null;
    final n = _readClipBodies(clip, into: made, doc: clean);
    if (n == 0) {
      await deletePart(clean); // nothing in it: do not leave an empty document
      return null;
    }
    applyEndOfPart(made);
    made.dirty = true;
    await savePart(clean);
    // M245's invariant: a document not open in a tab lives in the shared map.
    final model = parts.remove(clean);
    if (model != null) _componentModels[clean] = model;
    Log.i('clip', 'new part document "$clean" from body "${clip.bodyName}"');
    return clean;
  }

  /// Reads the clip's STEP into [into] as imported bodies, copying the file
  /// into that document so it can be read again after a restart.
  ///
  /// Returns how many bodies arrived. The STEP holds exactly the one body that
  /// was copied, but the loop is over what the file actually contains: a
  /// kernel is free to hand back a compound, and inventing a count here is how
  /// a paste silently loses geometry.
  int _readClipBodies(BodyClip clip,
      {required PartModel into, required String doc}) {
    if (!File(clip.stepPath).existsSync()) {
      toast(L.current.msgClipboardBodyGone);
      return 0;
    }
    final solids = partKernel.importStepSolids(clip.stepPath);
    if (solids.isEmpty) {
      toast(L.current.msgPasteBodyFailed(partKernel.lastError));
      return 0;
    }
    String? rel;
    try {
      final dir = _partImportDir(doc);
      var base = 'pasted_${DateTime.now().millisecondsSinceEpoch}';
      while (File('${dir.path}/$base.step').existsSync()) {
        base = '${base}_2';
      }
      File(clip.stepPath).copySync('${dir.path}/$base.step');
      rel = 'imports/$base.step';
    } catch (e) {
      Log.w('clip', 'could not stash the pasted STEP: $e');
    }
    if (rel == null) {
      for (final s in solids) {
        s.dispose();
      }
      toast(L.current.msgPasteBodyNotSaved);
      return 0;
    }
    _partCheckpoint(into);
    for (final solid in solids) {
      into.appendFeature(ExtrudeFeature(
        name: into.nextFeatureName('Paste'),
        bodyName: into.nextSolidName(),
        sketchName: '',
        profiles: const [],
        output: 'new',
      )
        ..imported = true
        ..importPath = rel
        ..solid = solid
        ..seq = into.nextSeq());
    }
    recomputeAllFeatures(into, partKernel);
    Log.i('clip',
        'pasted ${solids.length} body/bodies from "${clip.sourceDoc}" into "$doc"');
    return solids.length;
  }

  /// [want], or the first free "want 2", "want 3", … in the gallery.
  String _freeDocumentName(String want) {
    final base = want.trim().isEmpty ? 'Sketch' : want.trim();
    if (!docNameExists(base)) return base;
    var n = 2;
    while (docNameExists('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  /// The geometry of sketch DOCUMENT [name] as a clip, loading it if it is not
  /// open. The model is disposed again unless the document was already open —
  /// reading a document must not leave it in the session.
  Future<SketchClip?> _sketchClipOfDocument(String name) async {
    final open = sketches[name];
    if (open != null) {
      return sketchClip(
        geometry: open.geometry,
        constraints: open.constraints,
        layers: open.layers,
        sourceDoc: name,
        sourceSketch: name,
        userParams: open.userParams,
        texts: open.texts,
        images: _clipImages(name, open),
        hidden: open.hiddenLayers,
        locked: open.lockedLayers,
      );
    }
    if (_docsDir == null) return null;
    _ensureStaged(name);
    final model = await _loadSketchIn(_stage(name), name, base: kSketchBase);
    try {
      return sketchClip(
        geometry: model.geometry,
        constraints: model.constraints,
        layers: model.layers,
        sourceDoc: name,
        sourceSketch: name,
        userParams: model.userParams,
        texts: model.texts,
        images: _clipImages(name, model),
        hidden: model.hiddenLayers,
        locked: model.lockedLayers,
      );
    } finally {
      model.dispose();
    }
  }

  // ---- the two conversions ------------------------------------------------

  /// "Turn this 2D sketch into a part": a new part document whose first sketch
  /// IS this document's, on the XY plane, ready to extrude.
  ///
  /// The sketch document is left alone. A convert that deleted it would be
  /// destroying the only copy of a drawing to produce a document defined in
  /// terms of it — the same argument M255 makes for not emptying the origin of
  /// a Make Part, and the reason this is called "part from sketch" rather than
  /// "convert".
  Future<String?> partFromSketch(String sketchDoc, {String? partName}) async {
    if (isPartName(sketchDoc) || isAssemblyName(sketchDoc)) {
      toast(L.current.msgNotASketch(sketchDoc));
      return null;
    }
    final clip = await _sketchClipOfDocument(sketchDoc);
    if (clip == null) {
      toast(L.current.msgNoSuchDocument(sketchDoc));
      return null;
    }
    final clean = _freeDocumentName(partName ?? sketchDoc);
    final bad = validateSketchName(clean);
    if (bad != null) {
      toast(bad);
      return null;
    }
    if (!await createNamedPart(clean)) {
      toast(L.current.msgNameTaken(clean));
      return null;
    }
    final p = parts[clean];
    if (p == null) return null;
    final sk = SketchModel(p.nextSketchName());
    p.appendChildSketch(ChildSketch(sk, 'xy', null, true, false, p.nextSeq()));
    _applySketchClip(sk, clip, doc: clean, fresh: true, active: false);
    sk.resetHistory();
    p.camera.orientToPlane('xy');
    p.dirty = true;
    await savePart(clean);
    Log.i('clip', 'part "$clean" from sketch document "$sketchDoc"');
    toast(L.current.msgPartFromSketch(clean, sketchDoc));
    notifyListeners();
    return clean;
  }

  /// "Turn this sketch in a part into a 2D sketch": a new sketch DOCUMENT
  /// holding a copy of the part's child sketch, opened.
  ///
  /// A copy, and the part keeps its own — the sketch inside a part is what its
  /// features are built on, and a convert that moved it out would delete every
  /// feature that consumes it.
  Future<String?> sketchDocumentFromChild(String childName,
      {String? docName}) async {
    final p = currentPart;
    final cs = p?.sketchByName(childName);
    if (p == null || cs == null) return null;
    final clip = sketchClip(
      geometry: cs.model.geometry,
      constraints: cs.model.constraints,
      layers: cs.model.layers,
      sourceDoc: p.name,
      sourceSketch: cs.model.name,
      userParams: cs.model.userParams,
      texts: cs.model.texts,
      images: _clipImages(p.name, cs.model),
      hidden: cs.model.hiddenLayers,
      locked: cs.model.lockedLayers,
      plane: cs.plane,
    );
    // "<Part> <Sketch1>" rather than "Sketch1": the gallery is one shelf for
    // every document in the app, and a card called "Sketch1" says nothing
    // about which part it came out of.
    final want = docName ?? '${p.name} ${cs.model.name}';
    return newSketchDocumentFrom(clip, name: want);
  }

  // =========================================================================
  // M371 — MEASURE
  //
  // Inventor's Tools > Measure, which since 2018 is ONE command driven by an
  // information-rich modeless panel rather than the four (Distance, Angle,
  // Loop, Area) it replaced. Everything about how it behaves lives in three
  // places and this is the smallest of them:
  //
  //   measure.dart       what a pair of picks MEANS, and the session's rules
  //   measure_pick.dart  what one tap IS, per document kind
  //   here               arming it, routing picks, and the clipboard
  //
  // WHY IT IS NOT A [Tool]. The Tool enum is the 2D sketcher's create/modify
  // set: `toolClick` places points into `toolPoints`, `cancelTool` steps a
  // pick chain back, and every one of them commits GEOMETRY into the sketch.
  // Measure writes nothing, runs in all three document kinds — the sketcher,
  // the part and the assembly, none of which share a Tool — and its picks are
  // entities rather than points. Making it a Tool would have meant a special
  // case in every one of those paths; a session of its own means none.
  // =========================================================================

  /// The live Measure command, or null when it is not running.
  MeasureSession? measureSession;

  bool get measuring => measureSession != null;

  /// The display choices, kept OUTSIDE the session so they survive it.
  ///
  /// A session is created fresh every time Measure is armed — that is what
  /// makes Esc a real cancel — and if the precision and the second unit lived
  /// in it, a user who works in inches would set them again on every single
  /// measurement. Inventor remembers them for the same reason. Not persisted
  /// to disk: they are a working preference, not a document, and the app has
  /// no measurement section in its settings file to put them in.
  int _measureDecimals = 2;
  MeasureUnitSystem? _measureDualUnit;
  MeasurePriority _measurePriority = MeasurePriority.entity;

  /// M, and the ribbon button. Toggles, like every other modeless command
  /// here: pressing it again puts it away.
  void toggleMeasure() {
    if (measureSession != null) {
      cancelMeasure();
    } else {
      startMeasure();
    }
  }

  /// Arms Measure over whichever document is open.
  ///
  /// Refuses on the gallery rather than opening a panel with nothing to point
  /// at — the one place in the app where there is genuinely nothing to
  /// measure.
  void startMeasure() {
    if (isHome) {
      toast(L.current.measureNeedsDocument);
      return;
    }
    // Measure collects picks from the viewport, so anything else that does
    // must stand down first — otherwise the same tap would be claimed twice
    // and the user would have no way to tell which command took it.
    //
    // GUARDED, because [cancelTool] does two things: it stands the armed
    // command down AND, when there is none, it clears the SELECTION. Calling
    // it unconditionally made arming Measure throw away whatever the user had
    // selected — a side effect nobody asked for and one they would have had to
    // re-do by hand. The guard names exactly the states cancelTool acts on
    // before it reaches that last line.
    if (tool != Tool.none ||
        pattern != null ||
        gear != null ||
        filletSess != null) {
      cancelTool();
    }
    cancelWorkFeature();
    // The three NARROW 3D pick modes. Their branches sit above Measure's in
    // viewport3d's pointer handler — they were there first and reordering
    // them would risk commands this milestone is not about — so an armed one
    // would silently swallow every tap meant for the measurement while its
    // panel sat there looking active. Standing them down is the fix that does
    // not touch their order: after this, nothing above Measure can be armed.
    cancelFaceEdit();
    cancelPickSweepPath();
    cancelPickLoftSections();
    // The ASSEMBLY's collecting commands, for the same reason: every one of
    // them takes taps from the viewport, and two commands claiming one tap is
    // a state the user can neither see nor get out of.
    if (sectionPicking) {
      // The PICK, not the CUT. A section already applied to the document is a
      // VIEW the user set up, and arming a measurement has no business
      // throwing it away — which is what [endSection] would do.
      sectionArm = null;
      sectionDraft = null;
    }
    cancelConstraint();
    cancelAsmPattern();
    cancelCreateComponent();
    showRelationshipsPicking = false;
    measureSession = MeasureSession()
      ..decimals = _measureDecimals
      ..dualUnit = _measureDualUnit
      ..priority = _measurePriority;
    toast(L.current.measureHintPick);
    notifyListeners();
  }

  void cancelMeasure() {
    if (measureSession == null) return;
    measureSession = null;
    notifyListeners();
  }

  /// The viewport reports one picked entity.
  ///
  /// A miss never cancels: a measurement can need two picks and throwing the
  /// first away because the second tap landed on empty space would be the
  /// most expensive possible response to the cheapest possible mistake. Esc
  /// and the ribbon toggle cancel; nothing else does. (The same rule the work
  /// feature commands follow — see [workFeaturePick].)
  void measurePick(MeasureRef ref) {
    final s = measureSession;
    if (s == null) return;
    s.add(ref);
    if (s.picks.length == 1 && s.reading == null) {
      // One pick that measures nothing on its own — a work plane, an origin
      // axis. Say what it is waiting for rather than showing an empty panel.
      toast(L.current.measureHintPickSecond);
    }
    notifyListeners();
  }

  /// The viewport reports what is under the pointer, or null (M374).
  ///
  /// Called from every hover event, so the cheap path matters: [setHover]
  /// answers false when nothing changed and this rebuilds nothing. That guard
  /// is why hovering a face costs one repaint on entering it and none for as
  /// long as the pointer stays on it, rather than one per pointer move.
  void measureHover(MeasureRef? ref) {
    final s = measureSession;
    if (s == null) return;
    if (!s.setHover(ref)) return;
    notifyListeners();
  }

  /// The viewport reports a tap that hit nothing.
  void measureMissed() {
    if (measureSession == null) return;
    toast(L.current.measureNothingHere);
  }

  /// Drops pick [i] — the x on a selection row.
  void measureRemovePick(int i) {
    measureSession?.removeAt(i);
    notifyListeners();
  }

  /// Restart: the picks go, the running totals stay. Inventor's Restart does
  /// exactly that, and it is the distinction that makes summing usable — a
  /// total you have to rebuild after every measurement is not a total.
  void measureRestart() {
    measureSession?.clearPicks();
    notifyListeners();
  }

  void setMeasureMode(MeasureDistanceMode m) {
    final s = measureSession;
    if (s == null || s.mode == m) return;
    s.mode = m;
    s.recompute();
    notifyListeners();
  }

  /// Changing the priority re-picks nothing: it decides what the NEXT tap
  /// answers with. Inventor behaves the same way, and re-interpreting picks
  /// already made would silently change a reading the user is reading.
  void setMeasurePriority(MeasurePriority p) {
    final s = measureSession;
    if (s == null || s.priority == p) return;
    s.priority = p;
    _measurePriority = p;
    notifyListeners();
  }

  void setMeasureDecimals(int d) {
    final s = measureSession;
    if (s == null) return;
    s.decimals = _measureDecimals = d.clamp(0, 6);
    notifyListeners();
  }

  void setMeasureDualUnit(MeasureUnitSystem? u) {
    final s = measureSession;
    if (s == null) return;
    s.dualUnit = _measureDualUnit = u;
    notifyListeners();
  }

  void measureAddToTotals() {
    final s = measureSession;
    if (s == null || !s.addToTotals()) return;
    notifyListeners();
  }

  void measureClearTotals() {
    measureSession?.clearTotals();
    notifyListeners();
  }

  /// Copies the reading to the clipboard — one value, or all of them.
  ///
  /// Inventor's own pair of actions ("copy one or all values in the Measure
  /// tool panel"), and the reason a measurement is worth taking at all: the
  /// number is going somewhere else.
  Future<void> measureCopy({MeasureValue? value}) async {
    final s = measureSession;
    final r = s?.reading;
    if (s == null || r == null) return;
    final text = value == null
        ? measureReadingText(r,
            decimals: s.decimals, unit: MeasureUnitSystem.millimetre)
        : measureFormat(value,
            decimals: s.decimals, unit: MeasureUnitSystem.millimetre);
    await Clipboard.setData(ClipboardData(text: text));
    toast(L.current.measureCopied);
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
        _dashedSeg(
            canvas, map(g.data[0], g.data[1]), map(g.data[2], g.data[3]), p,
            dash: 5, gap: 4);
      } else if (g.isCenterline) {
        // centerline STYLE: same entity, dashed rendering (Inventor's toggle)
        _dashedSeg(
            canvas, map(g.data[0], g.data[1]), map(g.data[2], g.data[3]), p,
            dash: 10, gap: 5);
      } else {
        canvas.drawLine(
            map(g.data[0], g.data[1]), map(g.data[2], g.data[3]), p);
      }
      break;
    case Geo.circle:
      // M209 — a sketch POINT draws as a marker, not as its carrier circle:
      // a small X in SCREEN space, so it stays the same size at every zoom.
      // Inventor's sketch point is exactly this, and it is the whole of "the
      // point tool is placing a circle not a point" — the carrier's radius
      // was never meant to be visible.
      if (g.isSketchPoint) {
        final c = map(g.data[0], g.data[1]);
        const a = 3.5;
        final mp = Paint()
          ..color = p.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, p.strokeWidth)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(c + const Offset(-a, -a), c + const Offset(a, a), mp);
        canvas.drawLine(c + const Offset(-a, a), c + const Offset(a, -a), mp);
        break;
      }
      if (cDash) {
        final c = map(g.data[0], g.data[1]);
        final r = g.data[2] * scale;
        _dashedChain(
            canvas,
            [
              for (var i = 0; i <= 96; i++)
                c +
                    Offset(r * math.cos(i * math.pi / 48),
                        r * math.sin(i * math.pi / 48))
            ],
            p);
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
        _dashedChain(
            canvas,
            [
              for (var i = 0; i <= n; i++)
                c +
                    Offset(r * math.cos(-a1 - sweep * i / n),
                        r * math.sin(-a1 - sweep * i / n))
            ],
            p);
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
        //
        // M219 — sampled for THIS zoom. A curve is flattened until it is
        // within a fifth of a pixel of straight ON SCREEN, so it stays smooth
        // however far in the user zooms and costs nothing when zoomed out.
        // A model-space sample count cannot do both: whatever it is, some
        // magnification turns it into a visible polygon.
        final curve = splineCurveFor(g, tolMm: splineDisplayTol(scale));
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
  final d =
      2 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
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
