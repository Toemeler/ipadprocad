// A fault INSIDE OpenCascade is an error, not a dead app.
//
// Two segfaults were found in the AI lab (docs/AI_LAB_LOG.md, "NATIVE
// CRASH"): a handle fused onto a cup whose shell came back invalid, and a
// fillet on an L bracket carrying blind holes whose floors lie on the far
// face of the wall. The assistant now steers around both (an invalid shell is
// refused, such a hole is drilled through), but the same geometry made by hand
// reaches the kernel directly — so these drive the raw FFI calls, below every
// Dart-side guard, and pin that the shim turns the fault into a failed call
// with a message (see "faults inside OCCT" in backend/occt/shim/occt_capi.cpp).
//
// Before that change each test here killed the test process with SIGSEGV.
//
// Needs the kernel library: set PROTOTYPE_NATIVE_DIR (see LINUX.md). Without
// it every test SKIPS with that reason.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';

List<double> _at(double x, double y, double z) =>
    [1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z];

void main() {
  final f = OcctFfi.instance();
  final skip = f != null
      ? false
      : 'no kernel library — set PROTOTYPE_NATIVE_DIR (see LINUX.md)';

  /// The kernel still answers after a fault was caught.
  void expectKernelAlive(OcctFfi f) {
    final a = f.makeBox(10, 10, 10)!;
    final b = f.makeBox(10, 10, 10)!.transformed(_at(5, 0, 0))!;
    final u = f.fuse(a, b);
    expect(u, isNotNull, reason: f.lastError());
    expect(u!.volume, closeTo(1500, 1e-6));
  }

  test('fusing a handle onto a shell whose walls cross is an error',
      () {
    final ffi = f!;
    // The AI-lab cup: a revolved profile whose rim folds back on itself.
    final profile = <List<double>>[
      [0, 0], [28, 0], [30, 3], [33, 18], [36, 32], [39, 46], [38, 70],
      [37, 67.2426955952197], [34, 70.2426955952197],
      [30, 71.2426955952197], [0, 71.2426955952197],
    ];
    const top = 71.2426955952197;
    final cup = ffi.revolveProfile(
        [<double>[for (final p in profile) ...[p[0], p[1], 0.0]]], 360,
        axPx: 0, axPy: 0, axDx: 0, axDy: 1)!;
    final m = cup.mesh()!;
    final topFaces = <int>{};
    for (var t = 0; t < m.indices.length ~/ 3; t++) {
      var onTop = true;
      for (var k = 0; k < 3; k++) {
        final y = m.positions[m.indices[t * 3 + k] * 3 + 1];
        if ((y - top).abs() > 1e-6) onTop = false;
      }
      if (onTop) topFaces.add(m.topoFaceId(m.triFaces[t]));
    }
    expect(topFaces, hasLength(1));

    // 2.4 mm walls: the shell "succeeds" with an INVALID solid.
    final shell = ffi.shell(cup, topFaces.toList(), 2.4)!;
    expect(shell.valid, isFalse);

    // A round handle leaving the wall on -x and coming back.
    final path = <double>[
      for (final p in const [
        [-30.0, 12.0], [-50.0, 12.0], [-68.0, 20.0], [-71.0, 35.0],
        [-68.0, 50.0], [-50.0, 59.24], [-33.0, 59.24],
      ]) ...[p[0], p[1], 0],
    ];
    final handle = ffi.sweepProfile(
        [<double>[5.5, 0, 1, -5.5, 0, 1]],
        <double>[0, 0, 1, -30, 0, 1, 0, 12, -1, 0, 0, 0],
        path)!;

    final fused = ffi.fuse(shell, handle);
    expect(fused, isNull);
    expect(ffi.lastError(), startsWith('occt_fuse: SIGSEGV'));
    expectKernelAlive(ffi);
  }, skip: skip);

  test('filleting an L bracket beside zero-thickness hole floors is an error',
      () {
    final ffi = f!;
    // Two 4 mm legs, as the AI program built them.
    var body = ffi.fuse(ffi.makeBox(4, 30, 40)!.transformed(_at(-4, 0, -40))!,
        ffi.makeBox(40, 30, 4)!.transformed(_at(0, 0, -4))!)!;

    // A Ø5.5 blind hole 4 deep: a two-arc circle extruded 4 and placed.
    OcctShape hole(List<double> r, double cx, double cy, List<double> t) =>
        ffi.extrudeProfileArcs([<double>[cx + 2.75, cy, 1, cx - 2.75, cy, 1]],
                4)!
            .transformed([
          r[0], r[1], r[2], t[0], //
          r[3], r[4], r[5], t[1], //
          r[6], r[7], r[8], t[2],
        ])!;
    const intoMinusX = <double>[0, 0, -1, 0, 1, 0, 1, 0, 0];
    const intoPlusY = <double>[1, 0, 0, 0, 0, 1, 0, -1, 0];
    for (final tool in [
      hole(intoMinusX, -10, 11, [0, 0, 0]), // floor on the far face
      hole(intoMinusX, -25, 11, [0, 0, 0]), // floor on the far face
      hole(intoPlusY, -1, 2, [0, 11, 0]),
      hole(intoPlusY, -2, 2, [0, 20, 0]),
    ]) {
      body = ffi.cut(body, tool)!;
    }
    expect(body.valid, isTrue);

    final concave = [
      for (final e in body.allEdges())
        if (e.convexity == -1) e.index
    ];
    expect(concave, isNotEmpty);
    final out = body.filletEdges(concave, [for (final _ in concave) 2.5]);
    expect(out, isNull);
    expect(ffi.lastError(), startsWith('occt_fillet_edges: SIGSEGV'));
    expectKernelAlive(ffi);
  }, skip: skip);
}
