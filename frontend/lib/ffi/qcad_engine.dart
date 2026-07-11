// iPadProCAD — drawing engine facade.
//
// Primary path: real QCAD core via Dart FFI (symbols statically linked into
// the app binary on iOS -> DynamicLibrary.process()). If the native symbols
// are not present (e.g. `flutter run` on a host without the libs), we fall
// back to a pure-Dart in-memory engine so the UI stays usable — and we REPORT
// which one is active (never pretend the backend is there when it isn't).
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

/// Geometry snapshot of one entity, mirroring qcad_entity_geometry().
class Geo {
  static const line = 1, circle = 2, arc = 3, polyline = 4;
  final int type;
  final List<double> data;
  const Geo(this.type, this.data);
}

abstract class Engine {
  bool get isRealBackend;
  String get version;
  bool addLine(double x1, double y1, double x2, double y2);
  bool addCircle(double cx, double cy, double r);
  bool addArc(double cx, double cy, double r, double a1, double a2,
      {bool reversed = false});
  bool addPolyline(List<double> xy, {bool closed = false});
  List<Geo> allGeometry();
  bool saveDxf(String path);
  bool loadDxf(String path);
  void clearForReload(); // fallback only; real backend gets a fresh doc
  void dispose();

  /// Creates a backend-powered engine if the C symbols are linked in,
  /// otherwise the Dart fallback.
  static Engine create() {
    try {
      final b = _Bindings(DynamicLibrary.process());
      final e = _FfiEngine(b);
      // round-trip probe so a broken link surfaces immediately
      e.addLine(0, 0, 1, 1);
      final ok = e.allGeometry().length == 1;
      e.dispose();
      if (!ok) throw StateError('geometry round-trip failed');
      return _FfiEngine(_Bindings(DynamicLibrary.process()));
    } catch (_) {
      return _FallbackEngine();
    }
  }
}

// ---------------------------------------------------------------------------
// Native bindings (superset of backend/qcad-core/bindings/dart/qcad_ffi.dart,
// extended with the M5 geometry query).
// ---------------------------------------------------------------------------
typedef _InitN = Void Function();
typedef _InitD = void Function();
typedef _VerN = Pointer<Utf8> Function();
typedef _VerD = Pointer<Utf8> Function();
typedef _NewN = Pointer<Void> Function();
typedef _NewD = Pointer<Void> Function();
typedef _FreeN = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _LineN = Int32 Function(Pointer<Void>, Double, Double, Double, Double);
typedef _LineD = int Function(Pointer<Void>, double, double, double, double);
typedef _CircN = Int32 Function(Pointer<Void>, Double, Double, Double);
typedef _CircD = int Function(Pointer<Void>, double, double, double);
typedef _ArcN = Int32 Function(
    Pointer<Void>, Double, Double, Double, Double, Double, Int32);
typedef _ArcD = int Function(
    Pointer<Void>, double, double, double, double, double, int);
typedef _PolyN = Int32 Function(Pointer<Void>, Pointer<Double>, Size, Int32);
typedef _PolyD = int Function(Pointer<Void>, Pointer<Double>, int, int);
typedef _CountN = Int32 Function(Pointer<Void>);
typedef _CountD = int Function(Pointer<Void>);
typedef _IdsN = Int32 Function(Pointer<Void>, Pointer<Int64>, Int32);
typedef _IdsD = int Function(Pointer<Void>, Pointer<Int64>, int);
typedef _GeoN = Int32 Function(
    Pointer<Void>, Int64, Pointer<Int32>, Pointer<Double>, Int32);
typedef _GeoD = int Function(
    Pointer<Void>, int, Pointer<Int32>, Pointer<Double>, int);
typedef _IoN = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _IoD = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _SaveN = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SaveD = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

class _Bindings {
  final DynamicLibrary lib;
  late final _InitD init = lib.lookupFunction<_InitN, _InitD>('qcad_init');
  late final _VerD version =
      lib.lookupFunction<_VerN, _VerD>('qcad_version');
  late final _NewD docNew =
      lib.lookupFunction<_NewN, _NewD>('qcad_document_new');
  late final _FreeD docFree =
      lib.lookupFunction<_FreeN, _FreeD>('qcad_document_free');
  late final _LineD addLine =
      lib.lookupFunction<_LineN, _LineD>('qcad_add_line');
  late final _CircD addCircle =
      lib.lookupFunction<_CircN, _CircD>('qcad_add_circle');
  late final _ArcD addArc = lib.lookupFunction<_ArcN, _ArcD>('qcad_add_arc');
  late final _PolyD addPolyline =
      lib.lookupFunction<_PolyN, _PolyD>('qcad_add_polyline');
  late final _CountD entityCount =
      lib.lookupFunction<_CountN, _CountD>('qcad_entity_count');
  late final _IdsD entityIds =
      lib.lookupFunction<_IdsN, _IdsD>('qcad_entity_ids');
  late final _GeoD entityGeometry =
      lib.lookupFunction<_GeoN, _GeoD>('qcad_entity_geometry');
  late final _IoD loadDxf = lib.lookupFunction<_IoN, _IoD>('qcad_load_dxf');
  late final _SaveD saveDxf =
      lib.lookupFunction<_SaveN, _SaveD>('qcad_save_dxf');
  _Bindings(this.lib) {
    init();
  }
}

class _FfiEngine implements Engine {
  final _Bindings b;
  Pointer<Void> _doc;
  _FfiEngine(this.b) : _doc = b.docNew() {
    if (_doc == nullptr) {
      throw StateError('qcad_document_new returned null');
    }
  }

  @override
  bool get isRealBackend => true;
  @override
  String get version => b.version().toDartString();

  @override
  bool addLine(double x1, double y1, double x2, double y2) =>
      b.addLine(_doc, x1, y1, x2, y2) != 0;
  @override
  bool addCircle(double cx, double cy, double r) =>
      b.addCircle(_doc, cx, cy, r) != 0;
  @override
  bool addArc(double cx, double cy, double r, double a1, double a2,
          {bool reversed = false}) =>
      b.addArc(_doc, cx, cy, r, a1, a2, reversed ? 1 : 0) != 0;
  @override
  bool addPolyline(List<double> xy, {bool closed = false}) {
    final n = xy.length ~/ 2;
    final buf = malloc<Double>(xy.isEmpty ? 1 : xy.length);
    try {
      for (var i = 0; i < xy.length; i++) {
        buf[i] = xy[i];
      }
      return b.addPolyline(_doc, buf, n, closed ? 1 : 0) != 0;
    } finally {
      malloc.free(buf);
    }
  }

  @override
  List<Geo> allGeometry() {
    final total = b.entityIds(_doc, nullptr, 0);
    if (total <= 0) return const [];
    final ids = malloc<Int64>(total);
    final typeOut = malloc<Int32>(1);
    try {
      b.entityIds(_doc, ids, total);
      final out = <Geo>[];
      for (var i = 0; i < total; i++) {
        final need = b.entityGeometry(_doc, ids[i], typeOut, nullptr, 0);
        if (need <= 0) continue;
        final data = malloc<Double>(need);
        try {
          b.entityGeometry(_doc, ids[i], typeOut, data, need);
          out.add(Geo(typeOut.value,
              List<double>.generate(need, (j) => data[j])));
        } finally {
          malloc.free(data);
        }
      }
      return out;
    } finally {
      malloc.free(ids);
      malloc.free(typeOut);
    }
  }

  @override
  bool saveDxf(String path) {
    final p = path.toNativeUtf8();
    try {
      return b.saveDxf(_doc, p, nullptr) != 0;
    } finally {
      malloc.free(p);
    }
  }

  @override
  bool loadDxf(String path) {
    final p = path.toNativeUtf8();
    try {
      return b.loadDxf(_doc, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  @override
  void clearForReload() {
    // Real backend: replace the document with a fresh one before re-loading.
    b.docFree(_doc);
    _doc = b.docNew();
  }

  @override
  void dispose() {
    if (_doc != nullptr) {
      b.docFree(_doc);
      _doc = nullptr;
    }
  }
}

// ---------------------------------------------------------------------------
// Pure-Dart fallback (development hosts without the linked core). Persists as
// a trivial JSON-ish text file next to where the DXF would go, so save/load
// still works for UI development. Clearly reported as NOT the real backend.
// ---------------------------------------------------------------------------
class _FallbackEngine implements Engine {
  final List<Geo> _geos = [];
  @override
  bool get isRealBackend => false;
  @override
  String get version => 'Dart fallback engine (QCAD core NOT linked)';

  @override
  bool addLine(double x1, double y1, double x2, double y2) {
    _geos.add(Geo(Geo.line, [x1, y1, x2, y2]));
    return true;
  }

  @override
  bool addCircle(double cx, double cy, double r) {
    _geos.add(Geo(Geo.circle, [cx, cy, r]));
    return true;
  }

  @override
  bool addArc(double cx, double cy, double r, double a1, double a2,
      {bool reversed = false}) {
    _geos.add(Geo(Geo.arc, [cx, cy, r, a1, a2, reversed ? 1.0 : 0.0]));
    return true;
  }

  @override
  bool addPolyline(List<double> xy, {bool closed = false}) {
    _geos.add(Geo(Geo.polyline,
        [closed ? 1.0 : 0.0, xy.length / 2, ...xy]));
    return true;
  }

  @override
  List<Geo> allGeometry() => List.unmodifiable(_geos);

  @override
  bool saveDxf(String path) {
    // Minimal DXF (R12-style ENTITIES only) so files stay interchangeable
    // with the real backend as far as our own loader is concerned.
    final sb = StringBuffer('0\nSECTION\n2\nENTITIES\n');
    for (final g in _geos) {
      switch (g.type) {
        case Geo.line:
          sb.write('0\nLINE\n8\n0\n10\n${g.data[0]}\n20\n${g.data[1]}\n'
              '11\n${g.data[2]}\n21\n${g.data[3]}\n');
          break;
        case Geo.circle:
          sb.write('0\nCIRCLE\n8\n0\n10\n${g.data[0]}\n20\n${g.data[1]}\n'
              '40\n${g.data[2]}\n');
          break;
        case Geo.arc:
          sb.write('0\nARC\n8\n0\n10\n${g.data[0]}\n20\n${g.data[1]}\n'
              '40\n${g.data[2]}\n50\n${g.data[3] * 180 / math.pi}\n'
              '51\n${g.data[4] * 180 / math.pi}\n');
          break;
        case Geo.polyline:
          final n = g.data[1].toInt();
          sb.write('0\nPOLYLINE\n8\n0\n66\n1\n70\n${g.data[0].toInt()}\n');
          for (var i = 0; i < n; i++) {
            sb.write('0\nVERTEX\n8\n0\n10\n${g.data[2 + 2 * i]}\n'
                '20\n${g.data[3 + 2 * i]}\n');
          }
          sb.write('0\nSEQEND\n');
          break;
      }
    }
    sb.write('0\nENDSEC\n0\nEOF\n');
    try {
      // ignore: avoid_dynamic_calls
      _writeFile(path, sb.toString());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool loadDxf(String path) {
    try {
      final lines = _readFile(path);
      if (lines == null) return false;
      var i = 0;
      String? code, value;
      final pairs = <MapEntry<String, String>>[];
      while (i + 1 < lines.length) {
        code = lines[i].trim();
        value = lines[i + 1].trim();
        pairs.add(MapEntry(code, value));
        i += 2;
      }
      var p = 0;
      while (p < pairs.length) {
        if (pairs[p].key == '0') {
          final ent = pairs[p].value;
          final props = <String, String>{};
          var q = p + 1;
          while (q < pairs.length && pairs[q].key != '0') {
            props[pairs[q].key] = pairs[q].value;
            q++;
          }
          double d(String k, [double def = 0]) =>
              double.tryParse(props[k] ?? '') ?? def;
          if (ent == 'LINE') {
            addLine(d('10'), d('20'), d('11'), d('21'));
          } else if (ent == 'CIRCLE') {
            addCircle(d('10'), d('20'), d('40'));
          } else if (ent == 'ARC') {
            addArc(d('10'), d('20'), d('40'), d('50') * math.pi / 180,
                d('51') * math.pi / 180);
          } else if (ent == 'POLYLINE') {
            final closed = (int.tryParse(props['70'] ?? '0') ?? 0) & 1 == 1;
            final xy = <double>[];
            p = q;
            while (p < pairs.length &&
                pairs[p].key == '0' &&
                pairs[p].value == 'VERTEX') {
              final vp = <String, String>{};
              var r = p + 1;
              while (r < pairs.length && pairs[r].key != '0') {
                vp[pairs[r].key] = pairs[r].value;
                r++;
              }
              xy.add(double.tryParse(vp['10'] ?? '0') ?? 0);
              xy.add(double.tryParse(vp['20'] ?? '0') ?? 0);
              p = r;
            }
            addPolyline(xy, closed: closed);
            continue;
          }
          p = q;
          continue;
        }
        p++;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void clearForReload() => _geos.clear();
  @override
  void dispose() {}
}

void _writeFile(String path, String content) =>
    io.File(path).writeAsStringSync(content);

List<String>? _readFile(String path) {
  final f = io.File(path);
  if (!f.existsSync()) return null;
  return f.readAsLinesSync();
}
