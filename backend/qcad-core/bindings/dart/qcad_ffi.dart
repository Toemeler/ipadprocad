// iPadProCAD — Dart FFI bindings for the QCAD C-ABI wrapper (see qcad_capi.h).
//
// M2, step 4. On iOS the combined static library (libipadprocad.a) is linked
// directly into the app binary, so its symbols are resolved via
// DynamicLibrary.process(). For desktop experiments, build a shared library
// from the wrapper and use QcadBindings.open('<path-to-.so/.dylib>').
//
// Requires the `ffi` pub package (for Utf8 / malloc). Add to the Flutter app's
// pubspec.yaml when this is wired into the frontend (M4):
//     dependencies:
//       ffi: ^2.1.0
//
// NOTE: not yet exercised in CI — there is no Dart SDK in the backend build
// environment. The C ABI these bindings target is validated by the native C
// smoke test (backend/qcad-core/src/capi/tests/smoke.c). See HANDOFF.md.

import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Native signatures (C) and their Dart-side counterparts.
// ---------------------------------------------------------------------------
typedef _InitNative = Void Function();
typedef _InitDart = void Function();

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

typedef _DocNewNative = Pointer<Void> Function();
typedef _DocNewDart = Pointer<Void> Function();

typedef _DocFreeNative = Void Function(Pointer<Void>);
typedef _DocFreeDart = void Function(Pointer<Void>);

typedef _AddLineNative = Int32 Function(
    Pointer<Void>, Double, Double, Double, Double);
typedef _AddLineDart = int Function(
    Pointer<Void>, double, double, double, double);

typedef _AddCircleNative = Int32 Function(Pointer<Void>, Double, Double, Double);
typedef _AddCircleDart = int Function(Pointer<Void>, double, double, double);

typedef _AddArcNative = Int32 Function(
    Pointer<Void>, Double, Double, Double, Double, Double, Int32);
typedef _AddArcDart = int Function(
    Pointer<Void>, double, double, double, double, double, int);

typedef _AddPolylineNative = Int32 Function(
    Pointer<Void>, Pointer<Double>, Size, Int32);
typedef _AddPolylineDart = int Function(
    Pointer<Void>, Pointer<Double>, int, int);

typedef _EntityCountNative = Int32 Function(Pointer<Void>);
typedef _EntityCountDart = int Function(Pointer<Void>);

typedef _EntityIdsNative = Int32 Function(Pointer<Void>, Pointer<Int64>, Int32);
typedef _EntityIdsDart = int Function(Pointer<Void>, Pointer<Int64>, int);

typedef _EntityGeometryNative = Int32 Function(
    Pointer<Void>, Int64, Pointer<Int32>, Pointer<Double>, Int32);
typedef _EntityGeometryDart = int Function(
    Pointer<Void>, int, Pointer<Int32>, Pointer<Double>, int);

typedef _BBoxNative = Int32 Function(Pointer<Void>, Pointer<Double>,
    Pointer<Double>, Pointer<Double>, Pointer<Double>);
typedef _BBoxDart = int Function(Pointer<Void>, Pointer<Double>,
    Pointer<Double>, Pointer<Double>, Pointer<Double>);

typedef _LoadDxfNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _LoadDxfDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _SaveDxfNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SaveDxfDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

/// Low-level lookups. Prefer using [QcadDocument] which wraps these ergonomically.
class QcadBindings {
  final DynamicLibrary _lib;

  late final _InitDart _init =
      _lib.lookupFunction<_InitNative, _InitDart>('qcad_init');
  late final _VersionDart _version =
      _lib.lookupFunction<_VersionNative, _VersionDart>('qcad_version');
  late final _DocNewDart docNew =
      _lib.lookupFunction<_DocNewNative, _DocNewDart>('qcad_document_new');
  late final _DocFreeDart docFree =
      _lib.lookupFunction<_DocFreeNative, _DocFreeDart>('qcad_document_free');
  late final _AddLineDart addLine =
      _lib.lookupFunction<_AddLineNative, _AddLineDart>('qcad_add_line');
  late final _AddCircleDart addCircle =
      _lib.lookupFunction<_AddCircleNative, _AddCircleDart>('qcad_add_circle');
  late final _AddArcDart addArc =
      _lib.lookupFunction<_AddArcNative, _AddArcDart>('qcad_add_arc');
  late final _AddPolylineDart addPolyline =
      _lib.lookupFunction<_AddPolylineNative, _AddPolylineDart>(
          'qcad_add_polyline');
  late final _EntityCountDart entityCount =
      _lib.lookupFunction<_EntityCountNative, _EntityCountDart>(
          'qcad_entity_count');
  late final _EntityIdsDart entityIds =
      _lib.lookupFunction<_EntityIdsNative, _EntityIdsDart>('qcad_entity_ids');
  late final _EntityGeometryDart entityGeometry =
      _lib.lookupFunction<_EntityGeometryNative, _EntityGeometryDart>(
          'qcad_entity_geometry');
  late final _BBoxDart boundingBox =
      _lib.lookupFunction<_BBoxNative, _BBoxDart>('qcad_bounding_box');
  late final _LoadDxfDart loadDxf =
      _lib.lookupFunction<_LoadDxfNative, _LoadDxfDart>('qcad_load_dxf');
  late final _SaveDxfDart saveDxf =
      _lib.lookupFunction<_SaveDxfNative, _SaveDxfDart>('qcad_save_dxf');

  QcadBindings(this._lib) {
    _init(); // idempotent one-time init on the native side
  }

  /// iOS / any host where the wrapper is linked into the running binary.
  factory QcadBindings.process() => QcadBindings(DynamicLibrary.process());

  /// Desktop: open a shared build of the wrapper (.so/.dylib/.dll).
  factory QcadBindings.open(String path) =>
      QcadBindings(DynamicLibrary.open(path));

  String version() => _version().toDartString();
}

/// Axis-aligned bounding box in drawing units.
class BBox {
  final double minX, minY, maxX, maxY;
  const BBox(this.minX, this.minY, this.maxX, this.maxY);
  @override
  String toString() => 'BBox([$minX, $minY] .. [$maxX, $maxY])';
}

/// Ergonomic wrapper over a native document handle.
///
/// Call [dispose] when done to release the native document.
class QcadDocument {
  final QcadBindings _b;
  Pointer<Void> _handle;

  QcadDocument._(this._b, this._handle);

  factory QcadDocument(QcadBindings bindings) {
    final h = bindings.docNew();
    if (h == nullptr) {
      throw StateError('qcad_document_new returned null');
    }
    return QcadDocument._(bindings, h);
  }

  bool addLine(double x1, double y1, double x2, double y2) =>
      _b.addLine(_handle, x1, y1, x2, y2) != 0;

  bool addCircle(double cx, double cy, double radius) =>
      _b.addCircle(_handle, cx, cy, radius) != 0;

  bool addArc(double cx, double cy, double radius, double startAngle,
          double endAngle, {bool reversed = false}) =>
      _b.addArc(_handle, cx, cy, radius, startAngle, endAngle,
          reversed ? 1 : 0) != 0;

  /// [points] is a flat list of alternating x,y coordinates.
  bool addPolyline(List<double> points, {bool closed = false}) {
    if (points.length.isOdd) {
      throw ArgumentError('points must contain an even number of values');
    }
    final count = points.length ~/ 2;
    final buf = malloc<Double>(points.isEmpty ? 1 : points.length);
    try {
      for (var i = 0; i < points.length; i++) {
        buf[i] = points[i];
      }
      return _b.addPolyline(_handle, buf, count, closed ? 1 : 0) != 0;
    } finally {
      malloc.free(buf);
    }
  }

  int get entityCount => _b.entityCount(_handle);

  BBox? boundingBox() {
    final out = malloc<Double>(4);
    try {
      final ok = _b.boundingBox(
          _handle, out.elementAt(0), out.elementAt(1),
          out.elementAt(2), out.elementAt(3));
      if (ok == 0) return null;
      return BBox(out[0], out[1], out[2], out[3]);
    } finally {
      malloc.free(out);
    }
  }

  bool loadDxf(String path) {
    final p = path.toNativeUtf8();
    try {
      return _b.loadDxf(_handle, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  /// [version] may be null (defaults to R2000), 'R12', or 'min'.
  bool saveDxf(String path, {String? version}) {
    final p = path.toNativeUtf8();
    final v = version == null ? nullptr : version.toNativeUtf8();
    try {
      return _b.saveDxf(_handle, p, v.cast()) != 0;
    } finally {
      malloc.free(p);
      if (v != nullptr) malloc.free(v as Pointer<Utf8>);
    }
  }

  void dispose() {
    if (_handle != nullptr) {
      _b.docFree(_handle);
      _handle = nullptr;
    }
  }
}
