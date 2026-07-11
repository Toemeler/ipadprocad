// iPadProCAD — application state (tabs, layers, edit mode, active tool) and
// persistence (DXF per sketch + preview PNG in the app Documents directory).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'ffi/qcad_engine.dart';
import 'log.dart';
import 'theme.dart';

/// Drawing tools with real backend support (M5 step 3). Every other ribbon
/// button exists exactly as in the mock but has no function yet.
enum Tool { none, line, circleCenter, rectTwoPoint, arcThreePoint }

class SketchModel {
  final String name;
  final Engine engine;
  List<Geo> geometry = [];
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

  // ---- tools ----
  void selectTool(Tool t) {
    tool = t;
    toolPoints.clear();
    notifyListeners();
  }

  void cancelTool() {
    toolPoints.clear();
    tool = Tool.none;
    notifyListeners();
  }

  /// Handles a committed click at world coordinates for the active tool.
  void toolClick(Offset w) {
    final s = current;
    if (s == null || tool == Tool.none) return;
    toolPoints.add(w);
    switch (tool) {
      case Tool.line:
        if (toolPoints.length == 2) {
          s.engine.addLine(
              toolPoints[0].dx, toolPoints[0].dy, toolPoints[1].dx, toolPoints[1].dy);
          // CAD-style chaining: next line starts at the last endpoint
          final last = toolPoints[1];
          toolPoints
            ..clear()
            ..add(last);
          _committed(s);
        }
        break;
      case Tool.circleCenter:
        if (toolPoints.length == 2) {
          final r = (toolPoints[1] - toolPoints[0]).distance;
          if (r > 0) s.engine.addCircle(toolPoints[0].dx, toolPoints[0].dy, r);
          toolPoints.clear();
          _committed(s);
        }
        break;
      case Tool.rectTwoPoint:
        if (toolPoints.length == 2) {
          final a = toolPoints[0], b = toolPoints[1];
          s.engine.addPolyline(
              [a.dx, a.dy, b.dx, a.dy, b.dx, b.dy, a.dx, b.dy],
              closed: true);
          toolPoints.clear();
          _committed(s);
        }
        break;
      case Tool.arcThreePoint:
        if (toolPoints.length == 3) {
          final arc = arcFrom3Points(toolPoints[0], toolPoints[1], toolPoints[2]);
          if (arc != null) {
            s.engine.addArc(arc.$1.dx, arc.$1.dy, arc.$2, arc.$3, arc.$4,
                reversed: arc.$5);
          }
          toolPoints.clear();
          _committed(s);
        }
        break;
      case Tool.none:
        break;
    }
    notifyListeners();
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
