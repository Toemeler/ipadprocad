// S2 (optimisation split) — the Dart half of the bulk edge enumeration.
//
// `allEdges()` stopped being a loop over `occt_shape_edge_info` and became one
// call to `occt_shape_edges_info`, because the per-call whole-shape work made
// the loop Theta(n^2): PERFORMANCE_PROFILE.md §6.5 measures k = 2.012
// [1.910, 2.113], R² = 1.0000, ten seconds for one solid at 1440 edges.
//
// The kernel half of that change is pinned where the kernel is, by smoke
// scenario [35] in backend/occt/tests/smoke_occt.c, which compares the bulk
// records against the per-edge records BITWISE on four solids. It needs a real
// OCCT and so runs in CI, not here — on the host the occt_* symbols are not
// linked at all (see m55_occt_ffi_test.dart).
//
// What CAN be pinned here is the half that lives in Dart, and it is not
// nothing: the buffer decode. Twelve doubles per record, packed end to end,
// read back at an offset. Get the offset arithmetic or the field order wrong
// and every edge comes back describing its neighbour — a fillet then
// reattaches to the wrong edge on load, silently, which is the failure mode
// this whole change is most at risk of. These tests would fail if any of that
// drifted.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';

/// One record in the shim's documented layout, so the tests below read as the
/// layout rather than as twelve anonymous numbers.
List<double> record({
  required double kind,
  double mx = 0,
  double my = 0,
  double mz = 0,
  double tx = 0,
  double ty = 0,
  double tz = 0,
  double length = 0,
  double radius = 0,
  double faceCount = 0,
  double dihedral = 0,
  double convexity = 0,
}) =>
    [kind, mx, my, mz, tx, ty, tz, length, radius, faceCount, dihedral,
        convexity];

void main() {
  // A circular edge with every field distinct, so a transposition of any two
  // cannot hide behind equal values.
  final circle = record(
    kind: 2,
    mx: 1.5, my: -2.5, mz: 3.5,
    tx: 0.6, ty: -0.8, tz: 0.0,
    length: 31.4159,
    radius: 5.0,
    faceCount: 2,
    dihedral: 90.0,
    convexity: -1,
  );

  test('every field lands in the field the shim header names', () {
    final e = OcctEdgeInfo.decodeRecord(7, circle)!;
    expect(e.index, 7);
    expect(e.kind, 2);
    expect(e.mx, 1.5);
    expect(e.my, -2.5);
    expect(e.mz, 3.5);
    expect(e.tx, 0.6);
    expect(e.ty, -0.8);
    expect(e.tz, 0.0);
    expect(e.length, 31.4159);
    expect(e.radius, 5.0);
    expect(e.faceCount, 2);
    expect(e.dihedralDeg, 90.0);
    expect(e.convexity, -1);
    // And the derived predicates the UI actually reads.
    expect(e.filletable, isTrue);
    expect(e.isConcave, isTrue);
    expect(e.isConvex, isFalse);
  });

  test('a record at an offset decodes exactly as it does at offset zero', () {
    // Three records packed end to end, the interesting one third. The two
    // fillers are deliberately DIFFERENT from it: an off-by-twelve would
    // decode a filler and the fields would not match.
    final filler = record(kind: 1, mx: 99, length: 99, faceCount: 1);
    final packed = <double>[...filler, ...filler, ...circle];
    expect(packed.length, 36);

    final atZero = OcctEdgeInfo.decodeRecord(3, circle)!;
    final atOffset = OcctEdgeInfo.decodeRecord(3, packed, 24)!;

    expect(atOffset.kind, atZero.kind);
    expect(atOffset.mx, atZero.mx);
    expect(atOffset.my, atZero.my);
    expect(atOffset.mz, atZero.mz);
    expect(atOffset.tx, atZero.tx);
    expect(atOffset.ty, atZero.ty);
    expect(atOffset.tz, atZero.tz);
    expect(atOffset.length, atZero.length);
    expect(atOffset.radius, atZero.radius);
    expect(atOffset.faceCount, atZero.faceCount);
    expect(atOffset.dihedralDeg, atZero.dihedralDeg);
    expect(atOffset.convexity, atZero.convexity);
    expect(atOffset.toString(), atZero.toString());
  });

  test('a degenerate edge (kind 0) is KEPT, not dropped', () {
    // The shim returns success with an all-zero record for a degenerate edge —
    // "an honest nothing here". The old Dart loop added it to the list, and so
    // must the new decode: dropping it would renumber every edge after it.
    final e = OcctEdgeInfo.decodeRecord(4, record(kind: 0));
    expect(e, isNotNull);
    expect(e!.kind, 0);
    expect(e.index, 4);
    expect(e.filletable, isFalse);
  });

  test('a negative kind is the shim saying it could not read this edge', () {
    // v21 marker. The bulk path cannot return null per edge — the buffer is
    // positional — so it writes a type outside the documented 0..4 range and
    // the caller drops the record, reproducing what the per-edge loop did with
    // a null return.
    expect(OcctEdgeInfo.decodeRecord(1, record(kind: -1)), isNull);
  });

  test('a short or out-of-range read is null, never an exception', () {
    // A truncated buffer means the shim wrote fewer records than the caller
    // expected. Throwing here would take down a whole rebuild; returning null
    // drops one edge, which is the same degradation as a per-edge failure.
    expect(OcctEdgeInfo.decodeRecord(1, const <double>[1, 2, 3]), isNull);
    expect(OcctEdgeInfo.decodeRecord(1, circle, 1), isNull);
    expect(OcctEdgeInfo.decodeRecord(1, circle, -1), isNull);
    expect(OcctEdgeInfo.decodeRecord(1, const <double>[]), isNull);
  });

  test('rounding of the three integer fields matches the old constructor', () {
    // kind, faceCount and convexity cross the ABI as doubles and are rounded.
    // The shim writes them as exact small integers, but the rounding is what
    // the previous code did (`buf[0].round()`), so it is pinned rather than
    // assumed: a truncation instead of a round would turn a convexity of
    // -1.0 into 0 ("unknown") on any platform that represented it a hair high.
    final e = OcctEdgeInfo.decodeRecord(
        1, record(kind: 3.9999999999, faceCount: 2.0000000001,
            convexity: -0.9999999999))!;
    expect(e.kind, 4);
    expect(e.faceCount, 2);
    expect(e.convexity, -1);
  });
}
