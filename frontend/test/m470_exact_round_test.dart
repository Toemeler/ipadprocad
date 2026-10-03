// M470 — exact rounds where OCCT's blend gives up (lib/blend_fallback.dart).
//
// The fallback builds a round as a swept section instead of a rolling ball.
// It is checked here against OCCT's OWN fillet on shapes OCCT can round, so
// both have to agree: an outer edge of a box, an inner corner of an L, and
// the circular edge where a boss stands on a plate (outer and inner). Same
// volume to a hair means the section, its side and its sweep are right.
//
// Needs the kernel library (PROTOTYPE_NATIVE_DIR); skips without it.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/blend_fallback.dart';
import 'package:prototype/ffi/occt_engine.dart';


void main() {
  final f = OcctFfi.instance();
  final skip = f == null ? 'no kernel library — set PROTOTYPE_NATIVE_DIR' : false;

  /// Rounds the edge of [s] nearest [mid] both ways and compares.
  void sameAsOcct(OcctShape s, List<double> mid, double r, {int? kind}) {
    final ffi = f!;
    final edges = s.allEdges();
    final pick = [for (final e in edges) if (kind == null || e.kind == kind) e];
    pick.sort((a, b) {
      double d(OcctEdgeInfo e) =>
          (e.mx - mid[0]) * (e.mx - mid[0]) + (e.my - mid[1]) * (e.my - mid[1]) + (e.mz - mid[2]) * (e.mz - mid[2]);
      return d(a).compareTo(d(b));
    });
    final e = pick.first;
    final occt = s.filletEdges([e.index], [r]);
    expect(occt, isNotNull, reason: 'OCCT rounds this one itself');
    final mesh = s.mesh()!;
    final exact = exactRoundFallback(ffi, s, mesh, edges, [e.index], [r]);
    expect(exact, isNotNull, reason: 'the exact path builds it');
    expect(exact!.$2, [true]);
    expect(exact.$1.valid, isTrue);
    expect(exact.$1.volume, closeTo(occt!.volume, 1e-3 * r * r),
        reason: 'the same round as OCCT builds');
    exact.$1.dispose();
    occt.dispose();
  }

  test('an outer edge of a box', () {
    final box = f!.makeBox(20, 10, 10)!;
    sameAsOcct(box, [10, 0, 10], 3);
    // and the volume it removes is the section times the length
    final e = box.allEdges().firstWhere((e) => (e.mx - 10).abs() < 1e-6 && e.my.abs() < 1e-6 && (e.mz - 10).abs() < 1e-6);
    final out = exactRoundFallback(f, box, box.mesh()!, box.allEdges(), [e.index], [3])!;
    expect(out.$1.volume, closeTo(2000 - 20 * 9 * (1 - 3.141592653589793 / 4), 1e-6));
  }, skip: skip);

  test('an inner corner of an L', () {
    final a = f!.makeBox(30, 10, 5)!;
    final b = f.makeBox(5, 10, 20)!;
    final l = f.fuse(a, b)!;
    sameAsOcct(l, [5, 5, 5], 2);
  }, skip: skip);

  test('a boss on a plate: the outer rim and the inner corner', () {
    final plate = f!.makeBox(40, 40, 5)!;
    final boss = f.makeCylinder(20, 20, 5, 8, 10)!;
    final part = f.fuse(plate, boss)!;
    sameAsOcct(part, [28, 20, 15], 2, kind: 2); // outer rim at the top of the boss
    sameAsOcct(part, [28, 20, 5], 2, kind: 2); // inner corner at its foot
  }, skip: skip);
}
