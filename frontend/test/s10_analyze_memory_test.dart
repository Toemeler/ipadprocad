// S10 — re-deriving PERFORMANCE_PROFILE 5.5.2's 105 MB, on code that ships.
//
// WHY THIS IS ITS OWN FILE
// ------------------------
// Because `flutter test` gives each FILE its own process, and this measurement
// only means anything in a cold one.
//
// The instrument is `ProcessInfo.currentRss`, and it is coarse in a way worth
// stating before any number is read from it. RSS is what the kernel has given
// the process, not what the program is using: a Dart heap that already has
// spare capacity absorbs a 100 MB allocation without asking for a page, and a
// collector that decides to compact hands pages BACK in the middle of a
// measurement. Both were observed while writing this — an earlier version of
// this test lived beside the soak tests, ran in a process whose heap was
// already 288 MB, and measured the dense algorithm at **minus 65 MB**.
//
// So: one process, nothing before it, and the cheap arm first. In that order
// the numbers are what they look like.
//
// WHAT IS BEING RE-DERIVED
// ------------------------
// 5.5.2 costed the DOF analysis's memory from the dimensions of the two DENSE
// structures it built — a 2562 x 3584 Jacobian and a 1022 x 3584 null-space
// basis, 102.8 MB together — and matched a measured 105 MB to 2.2 %. Round
// one's S3 replaced both with sparse structures. The prediction is therefore a
// property of code that no longer exists.
//
// It is re-derived here rather than re-recorded. `solver.dart` still carries
// the dense algorithm as a frozen test-only reference behind
// `denseReferenceForTests`, kept by S3 for exactly this kind of question, so
// both algorithms can run on the same fixture in the same process and the
// COMPARISON is the claim. A recorded megabyte count would be a golden, and
// OPTIMIZATION_PLAN_2 1.4 is the record of what those cost this branch.
import 'dart:io' show ProcessInfo;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/solver.dart';

int _rssBytes() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return 0;
  }
}

/// Churns small short-lived objects to clear new space. Deliberately NOT a
/// large allocation: the obvious version of this asks for tens of megabytes
/// and drops them, which grows the resident set of the measurement it is
/// supposed to be cleaning up.
void _churn() {
  var sink = 0;
  for (var r = 0; r < 8; r++) {
    for (var i = 0; i < 40000; i++) {
      sink ^= <int>[i][0];
    }
  }
  if (sink == 0x7fffffff) fail('unreachable');
}

void main() {
  test('the dense algorithm 5.5.2 costed, against the sparse one that '
      'replaced it', () {
    // 256 circles + 256 lines = 512 entities: the stress ladder's
    // second-highest rung, and the largest that fits a CI budget with the
    // dense arm in it. The dense arm is cubic, so 1024 entities would be
    // half a minute of one test.
    const circles = 256;
    final gs = sketchFixture(circles);
    final cs = constraintFixture(circles);
    final (rank, m, total) = debugRank(gs, cs);
    final dof = total - rank;

    // The fixture's arithmetic, exactly as 5.5.2 closed it at 1024:
    //   sketchFixture(c)     -> c circles (3 params) + c lines (4)  = 7c
    //   constraintFixture(c) -> (c-1) equal (1 residual)
    //                           + 2c coincident (2 each) + fix (2) + dim (1)
    expect(total, 7 * circles);
    expect(m, (circles - 1) + 4 * circles + 3);
    expect(rank, m, reason: 'the fixture is meant to be of full row rank');

    // What the DENSE algorithm must allocate, from its own dimensions. A
    // `List<double>` in the Dart VM is an array of POINTERS, eight bytes each,
    // so the two matrices are m*total*8 and dof*total*8 whatever values end up
    // in them. This is 5.5.2's arithmetic at this size — and it is a LOWER
    // bound, not an estimate, because each distinct value in them is a boxed
    // double costing sixteen bytes more.
    final densePredictedBytes = (m * total * 8) + (dof * total * 8);

    int peakDeltaOf(void Function() body) {
      _churn();
      final before = _rssBytes();
      body();
      return _rssBytes() - before;
    }

    // Sparse first. Running it second would measure it against a heap the
    // dense pass had already grown, and it would read as zero.
    SketchAnalysis? sparseResult, denseResult;
    final sparse = peakDeltaOf(() => sparseResult = analyzeSketch(gs, cs));
    var dense = 0;
    try {
      denseReferenceForTests = true;
      dense = peakDeltaOf(() => denseResult = analyzeSketch(gs, cs));
    } finally {
      denseReferenceForTests = false;
    }

    const mb = 1024 * 1024;
    printOnFailure('total=$total m=$m rank=$rank dof=$dof\n'
        'dense predicted ${densePredictedBytes / mb} MiB (pointer arrays only)\n'
        'dense measured  ${dense / mb} MiB\n'
        'sparse measured ${sparse / mb} MiB');

    // The two paths agree. Not the subject of this test — `m232_analyze_pin_test`
    // owns that claim — but free here, and it is what makes the memory figures
    // a comparison of two implementations of the SAME function rather than of
    // two different functions.
    expect(sparseResult!.dof, denseResult!.dof);
    expect(sparseResult!.freePoints.length, denseResult!.freePoints.length);
    expect(sparseResult!.looseCarriers.length,
        denseResult!.looseCarriers.length);

    // The dense path really does allocate what its dimensions say. One-sided
    // on purpose: RSS can hold more than the live structures — the collector
    // owes nobody a return, and the finite-difference loop churns a residual
    // vector per parameter on top — but it cannot hold less than what is live,
    // and half the predicted figure is a wide allowance for pages the VM
    // already had spare.
    expect(dense, greaterThan(densePredictedBytes ~/ 2),
        reason: 'the dense reference allocated far less than its own '
            'dimensions require — either the byte model in 5.5.2 is wrong, or '
            'RSS moved for a reason that has nothing to do with this call');

    // And the sparse path does not. THIS IS THE FINDING: the structural
    // allocation 5.5.2 measured as 105 MB at the top rung is gone, and what
    // says so is a comparison rather than a constant.
    expect(sparse * 4, lessThan(dense),
        reason: 'the sparse path is not materially cheaper in memory than the '
            'dense one it replaced');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
