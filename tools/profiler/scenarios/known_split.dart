// A plain-Dart fixture whose cost split is measured IN THE SAME RUN.
//
// Why this exists. `OPTIMIZATION_PLAN_2.md` §5-S7 requires the profiler to
// reproduce a known attribution before it may be believed on an unknown one.
// The known attribution that matters is `analyzeSketch`'s (PERFORMANCE_PROFILE.md
// §5.5.2, perf/findings/S3-solver.md §2) — but that routine imports `dart:ui`
// and can therefore only run under `flutter test`, whose engine starts the VM
// with `--profile-vm`, a flag that cannot be changed at runtime and that
// degrades stack attribution (see perf/findings/S7-profiler.md §4).
//
// So the instrument is calibrated here instead, on a plain Dart VM where
// `profile_vm` is false, against a ground truth this file measures itself:
//
//   * `phaseJacobian` — a dense finite-difference Jacobian, `total` residual
//     evaluations of O(m) each, written column-wise into an `m x total`
//     `List<List<double>>`. This is step 1 of §5.5.2, same data structure,
//     same access pattern.
//   * `phaseElimination` — Gauss-Jordan reduction to RREF over that matrix,
//     with the same `if (f == 0) continue;` skip the real one carries
//     (perf/findings/S3-solver.md §0.2). This is step 2.
//
// Both are bracketed by a Stopwatch AND by a UserTag. The Stopwatch split is
// printed and becomes the expectation; the profiler must recover it from
// sampled stacks alone. That makes the check DIFFERENTIAL in the sense
// OPTIMIZATION_PLAN_2.md §1.4 requires — two instruments, same machine, same
// run — rather than a constant recorded on somebody else's hardware.

import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

final _tagJac = developer.UserTag('known.jacobian');
final _tagElim = developer.UserTag('known.elimination');

/// One residual vector of length [m] over the parameters [x]. Cheap per entry
/// and dependent on every parameter, so the finite-difference loop below has
/// to do the full O(m) evaluation `total` times, exactly as `_residuals` does.
List<double> residuals(List<double> x, int m) {
  final out = List<double>.filled(m, 0.0);
  final n = x.length;
  for (var i = 0; i < m; i++) {
    final a = x[i % n];
    final b = x[(i * 7 + 3) % n];
    out[i] = a * a - b + math.sqrt(a.abs() + 1.0);
  }
  return out;
}

/// The same two phases over `Float64List` rows.
///
/// `List<double>` stores BOXED doubles, so every write in either phase
/// allocates — which is faithful to `solver.dart` and useless for calibrating a
/// profiler, because the resulting garbage collection is time the Dart sampler
/// cannot see at all (it has no Dart stack to walk while the collector runs).
/// The typed variant removes that confound: wall time and Dart CPU time become
/// nearly the same quantity, so a disagreement between the Stopwatch and the
/// sampler is the sampler's fault and not the allocator's. Running both
/// variants measures the confound instead of arguing about it.
@pragma('vm:never-inline')
List<Float64List> elimCopyTyped(List<Float64List> src) =>
    [for (final row in src) Float64List.fromList(row)];

@pragma('vm:never-inline')
List<List<double>> elimCopy(List<List<double>> src) =>
    [for (final row in src) List<double>.of(row)];

@pragma('vm:never-inline')
List<Float64List> phaseJacobianTyped(Float64List x, int m) {
  final total = x.length;
  final r0 = residualsTyped(x, m);
  final j = List.generate(m, (_) => Float64List(total));
  final r2 = Float64List(m);
  for (var k = 0; k < total; k++) {
    final h = 1e-6 * (1 + x[k].abs());
    final save = x[k];
    x[k] = save + h;
    residualsInto(x, r2);
    x[k] = save;
    for (var i = 0; i < m; i++) {
      j[i][k] = (r2[i] - r0[i]) / h;
    }
  }
  return j;
}

Float64List residualsTyped(Float64List x, int m) {
  final out = Float64List(m);
  residualsInto(x, out);
  return out;
}

void residualsInto(Float64List x, Float64List out) {
  final n = x.length;
  final m = out.length;
  for (var i = 0; i < m; i++) {
    final a = x[i % n];
    final b = x[(i * 7 + 3) % n];
    out[i] = a * a - b + math.sqrt(a.abs() + 1.0);
  }
}

@pragma('vm:never-inline')
int phaseEliminationTyped(List<Float64List> src, int rows, int cols) {
  final a = src;
  var rank = 0;
  for (var col = 0; col < cols && rank < rows; col++) {
    var piv = -1;
    var best = 1e-9;
    for (var r = rank; r < rows; r++) {
      final v = a[r][col].abs();
      if (v > best) {
        best = v;
        piv = r;
      }
    }
    if (piv < 0) continue;
    final t = a[rank];
    a[rank] = a[piv];
    a[piv] = t;
    final prow = a[rank];
    final inv = 1.0 / prow[col];
    for (var c = col; c < cols; c++) {
      prow[c] *= inv;
    }
    for (var r = 0; r < rows; r++) {
      if (r == rank) continue;
      final f = a[r][col];
      if (f == 0) continue;
      final row = a[r];
      for (var c = col; c < cols; c++) {
        row[c] -= f * prow[c];
      }
    }
    rank++;
  }
  return rank;
}

@pragma('vm:never-inline')
List<List<double>> phaseJacobian(List<double> x, int m) {
  final total = x.length;
  final r0 = residuals(x, m);
  final j = List.generate(m, (_) => List<double>.filled(total, 0.0));
  for (var k = 0; k < total; k++) {
    final h = 1e-6 * (1 + x[k].abs());
    final save = x[k];
    x[k] = save + h;
    final r2 = residuals(x, m);
    x[k] = save;
    for (var i = 0; i < m; i++) {
      j[i][k] = (r2[i] - r0[i]) / h;
    }
  }
  return j;
}

@pragma('vm:never-inline')
int phaseElimination(List<List<double>> src, int rows, int cols) {
  final a = src;
  var rank = 0;
  for (var col = 0; col < cols && rank < rows; col++) {
    var piv = -1;
    var best = 1e-9;
    for (var r = rank; r < rows; r++) {
      final v = a[r][col].abs();
      if (v > best) {
        best = v;
        piv = r;
      }
    }
    if (piv < 0) continue;
    final t = a[rank];
    a[rank] = a[piv];
    a[piv] = t;
    final prow = a[rank];
    final inv = 1.0 / prow[col];
    for (var c = col; c < cols; c++) {
      prow[c] *= inv;
    }
    for (var r = 0; r < rows; r++) {
      if (r == rank) continue;
      final f = a[r][col];
      if (f == 0) continue;
      final row = a[r];
      for (var c = col; c < cols; c++) {
        row[c] -= f * prow[c];
      }
    }
    rank++;
  }
  return rank;
}

/// Arguments: total m jacRepeats elimRepeats warmups
///
/// The two repeat counts are what make this a CALIBRATION rather than a single
/// check. Running one phase more often than the other moves the true split
/// anywhere on the scale, so the profiler can be tested at a low share, a
/// middling one and a high one, and a systematic bias shows up as a slope
/// error instead of hiding inside one lucky point.
Future<void> main(List<String> args) async {
  final total = args.isNotEmpty ? int.parse(args[0]) : 900;
  final m = args.length > 1 ? int.parse(args[1]) : 700;
  final jacRepeats = args.length > 2 ? int.parse(args[2]) : 1;
  final elimRepeats = args.length > 3 ? int.parse(args[3]) : 1;
  final warmups = args.length > 4 ? int.parse(args[4]) : 2;
  final lingerMs = args.length > 5 ? int.parse(args[5]) : 4000;
  final typed = args.length > 6 ? args[6] == 'typed' : false;

  // Warm up the SAME variant that will be timed. An unoptimised first run is
  // not merely slower: the VM discards that code object once the function is
  // reoptimised, and a sample taken inside it comes back from a later fetch as
  // `<unknown Dart function>` — unattributable to anything. Warming the wrong
  // variant leaves the first timed run cold, which cost about 40 % of the
  // first Jacobian's samples before this was fixed.
  for (var w = 0; w < warmups + 3; w++) {
    final wx = List<double>.generate(240, (i) => 1.0 + i * 0.01);
    if (typed) {
      final wxt = Float64List.fromList(wx);
      phaseEliminationTyped(
          elimCopyTyped(phaseJacobianTyped(wxt, 180)), 180, 240);
    } else {
      phaseElimination(elimCopy(phaseJacobian(wx, 180)), 180, 240);
    }
  }

  final swJ = Stopwatch();
  final swE = Stopwatch();
  var rank = 0;
  List<List<double>> j = const [];

  List<Float64List> jt = const [];
  final x = List<double>.generate(total, (i) => 1.0 + i * 0.001);
  final xt = Float64List.fromList(x);

  // Every executed millisecond is inside exactly one timed, tagged phase.
  // An earlier version ran extra untimed Jacobians to feed extra elimination
  // repeats; the sampler saw that work and the Stopwatch did not, which reads
  // as a 34-point profiler error and is nothing of the kind.
  for (var rep = 0; rep < jacRepeats; rep++) {
    final prevJ = _tagJac.makeCurrent();
    swJ.start();
    if (typed) {
      jt = phaseJacobianTyped(xt, m);
    } else {
      j = phaseJacobian(x, m);
    }
    swJ.stop();
    prevJ.makeCurrent();
  }

  // Reduction destroys its input, so every repeat after the first needs a
  // fresh copy. The copy runs INSIDE the timed, tagged elimination region and
  // in a function of its own, so the Stopwatch and the sampler charge it to
  // exactly the same phase — the one property this fixture cannot do without.
  for (var rep = 0; rep < elimRepeats; rep++) {
    final prevE = _tagElim.makeCurrent();
    swE.start();
    if (typed) {
      rank = phaseEliminationTyped(elimCopyTyped(jt), m, total);
    } else {
      rank = phaseElimination(elimCopy(j), m, total);
    }
    swE.stop();
    prevE.makeCurrent();
  }

  final jac = swJ.elapsedMicroseconds / 1000.0;
  final elim = swE.elapsedMicroseconds / 1000.0;
  // The line the validator parses. `elimShare` is the ground truth; the
  // profiler has to recover it from stacks it took no part in producing.
  print('PROFILER_SCENARIO_RESULT scenario=known_split '
      'total=$total m=$m rank=$rank '
      'jacRepeats=$jacRepeats elimRepeats=$elimRepeats '
      'storage=${typed ? 'Float64List' : 'ListOfDouble'} '
      'jacobianMs=$jac eliminationMs=$elim '
      'elimShare=${elim / (jac + elim)}');

  // Stay alive long enough for the profiler's final full-window sweep to find
  // a VM to ask. It stops as soon as it has seen the line above.
  await Future<void>.delayed(Duration(milliseconds: lingerMs));
}
