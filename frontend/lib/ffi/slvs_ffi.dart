// Dart FFI binding for the libslvs shim (backend/slvs/shim/slvs_shim.h).
//
// Symbols are statically linked into the app binary on iOS, so we resolve
// them from DynamicLibrary.process(). If the symbol isn't linked (e.g. the
// native lib isn't in the build yet), [SlvsFfi.available] is false and callers
// fall back to the Dart solver. This module depends only on dart:ffi /
// package:ffi so it can't drag the rest of the app into a compile error.
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Constraint type codes — must match the SH_* defines in slvs_shim.h.
class Sh {
  static const coincident = 1;
  static const pointOnLine = 2;
  static const horizontal = 3;
  static const vertical = 4;
  static const parallel = 5;
  static const perpendicular = 6;
  static const collinear = 7;
  static const concentric = 8;
  static const equal = 9;
  static const tangent = 10;
  static const symmetric = 11;
  static const midpoint = 12;
  static const distance = 13;
  static const distX = 14;
  static const distY = 15;
  static const diameter = 16;
  static const radius = 17;
  static const angle = 18;
  static const dragged = 19;

  static const resultOkay = 0;
  static const resultInconsistent = 1; // also libslvs's REDUNDANT_OKAY

  // Entity-ref encoding (kind 1=line, 2=circle, 3=arc), matches SH_ENT.
  static int ent(int kind, int idx) => kind * 100000000 + idx;
}

typedef _SolveN = Int32 Function(
    Int32, Pointer<Double>, Pointer<Double>, Pointer<Int32>, // nPts px py fixed
    Int32, Pointer<Int32>, Pointer<Int32>, //                   nLines la lb
    Int32, Pointer<Int32>, Pointer<Double>, //                  nCircles cc cr
    Int32, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Double>,
    Int32, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, //   nCons ct ca cb
    Pointer<Int32>, Pointer<Int32>, Pointer<Double>, //         ce1 ce2 cval
    Pointer<Int32>, Pointer<Int32>, Int32); //                  dof failed cap
typedef _SolveD = int Function(
    int, Pointer<Double>, Pointer<Double>, Pointer<Int32>,
    int, Pointer<Int32>, Pointer<Int32>,
    int, Pointer<Int32>, Pointer<Double>,
    int, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>, Pointer<Double>,
    int, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>,
    Pointer<Int32>, Pointer<Int32>, Pointer<Double>,
    Pointer<Int32>, Pointer<Int32>, int);
typedef _VerN = Int32 Function();
typedef _VerD = int Function();

/// Result of a solve: outcome code, remaining degrees of freedom, and (on
/// failure) the indices of the offending constraints.
class SlvsResult {
  final int result;
  final int dof;
  final List<int> failed;
  SlvsResult(this.result, this.dof, this.failed);
  bool get ok => result == Sh.resultOkay;

  /// The solve produced usable coordinates. INCONSISTENT is libslvs's collapsed
  /// code for REDUNDANT_OKAY too — a converged solve whose system merely holds
  /// redundant equations, which is exactly what WHERE_DRAGGED creates on every
  /// drag of constrained geometry. The caller verifies the residuals anyway.
  bool get usable =>
      result == Sh.resultOkay || result == Sh.resultInconsistent;
}

/// A sketch flattened to the shim's model: points plus point-indexed entities.
class SlvsSketch {
  final List<double> px = [];
  final List<double> py = [];
  final List<int> fixed = [];
  final List<int> lineA = [], lineB = [];
  final List<int> circC = [];
  final List<double> circR = [];
  final List<int> arcC = [], arcS = [], arcE = [];
  final List<double> arcR = [];
  // constraint columns
  final List<int> ct = [], ca = [], cb = [], ce1 = [], ce2 = [];
  final List<double> cval = [];

  int addPoint(double x, double y, {bool fix = false}) {
    px.add(x);
    py.add(y);
    fixed.add(fix ? 1 : 0);
    return px.length - 1;
  }

  int addLine(int a, int b) {
    lineA.add(a);
    lineB.add(b);
    return lineA.length - 1;
  }

  int addCircle(int center, double r) {
    circC.add(center);
    circR.add(r);
    return circC.length - 1;
  }

  int addArc(int c, int s, int e, double r) {
    arcC.add(c);
    arcS.add(s);
    arcE.add(e);
    arcR.add(r);
    return arcC.length - 1;
  }

  void addCon(int type,
      {int a = -1, int b = -1, int e1 = 0, int e2 = 0, double val = 0}) {
    ct.add(type);
    ca.add(a);
    cb.add(b);
    ce1.add(e1);
    ce2.add(e2);
    cval.add(val);
  }
}

class SlvsFfi {
  SlvsFfi._(this._solve);
  final _SolveD _solve;

  static SlvsFfi? _cached;
  static bool _probed = false;

  /// Returns the binding if the native symbol is linked, else null (caller
  /// falls back to the Dart solver). Probed once and cached.
  static SlvsFfi? instance() {
    if (_probed) return _cached;
    _probed = true;
    try {
      final lib = DynamicLibrary.process();
      final ver = lib.lookupFunction<_VerN, _VerD>('slvs_shim_version')();
      if (ver <= 0) return null;
      final solve = lib.lookupFunction<_SolveN, _SolveD>('slvs_solve');
      _cached = SlvsFfi._(solve);
    } catch (_) {
      _cached = null;
    }
    return _cached;
  }

  static bool get available => instance() != null;

  /// Solves [s] in place: on OKAY, s.px/py, s.circR and s.arcR are updated.
  SlvsResult solve(SlvsSketch s) {
    final nPts = s.px.length;
    final nLines = s.lineA.length;
    final nCirc = s.circC.length;
    final nArcs = s.arcC.length;
    final nCons = s.ct.length;
    const failCap = 64;

    final px = _d(s.px), py = _d(s.py), fx = _i(s.fixed);
    final la = _i(s.lineA), lb = _i(s.lineB);
    final cc = _i(s.circC), cr = _d(s.circR);
    final ac = _i(s.arcC), as_ = _i(s.arcS), ae = _i(s.arcE), ar = _d(s.arcR);
    final ct = _i(s.ct), ca = _i(s.ca), cb = _i(s.cb);
    final ce1 = _i(s.ce1), ce2 = _i(s.ce2), cval = _d(s.cval);
    final dof = calloc<Int32>();
    final failed = calloc<Int32>(failCap);

    try {
      final r = _solve(
          nPts, px, py, fx,
          nLines, la, lb,
          nCirc, cc, cr,
          nArcs, ac, as_, ae, ar,
          nCons, ct, ca, cb, ce1, ce2, cval,
          dof, failed, failCap);
      // Read back whenever the shim produced coordinates — that includes
      // INCONSISTENT, which is libslvs's collapsed code for REDUNDANT_OKAY (a
      // converged solve). solver.dart verifies the residuals before trusting it.
      if (r == Sh.resultOkay || r == Sh.resultInconsistent) {
        for (var i = 0; i < nPts; i++) {
          s.px[i] = px[i];
          s.py[i] = py[i];
        }
        for (var k = 0; k < nCirc; k++) s.circR[k] = cr[k];
        for (var k = 0; k < nArcs; k++) s.arcR[k] = ar[k];
      }
      final fails = <int>[];
      // number of failures isn't returned separately; scan for the sentinel
      // is unnecessary — the solver only writes valid handles, zero-padded.
      for (var i = 0; i < failCap; i++) {
        if (failed[i] != 0) fails.add(failed[i]);
      }
      return SlvsResult(r, dof.value, fails);
    } finally {
      calloc.free(px); calloc.free(py); calloc.free(fx);
      calloc.free(la); calloc.free(lb);
      calloc.free(cc); calloc.free(cr);
      calloc.free(ac); calloc.free(as_); calloc.free(ae); calloc.free(ar);
      calloc.free(ct); calloc.free(ca); calloc.free(cb);
      calloc.free(ce1); calloc.free(ce2); calloc.free(cval);
      calloc.free(dof); calloc.free(failed);
    }
  }

  static Pointer<Double> _d(List<double> xs) {
    final p = calloc<Double>(xs.isEmpty ? 1 : xs.length);
    for (var i = 0; i < xs.length; i++) p[i] = xs[i];
    return p;
  }

  static Pointer<Int32> _i(List<int> xs) {
    final p = calloc<Int32>(xs.isEmpty ? 1 : xs.length);
    for (var i = 0; i < xs.length; i++) p[i] = xs[i];
    return p;
  }
}
