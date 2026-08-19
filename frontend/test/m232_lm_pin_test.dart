// M232 — the Levenberg–Marquardt fallback, pinned exactly, BEFORE its normal
// equations were rewritten.
//
// This is a harsher pin than the DOF one, and it has to be. `analyzeSketch`
// reports; `_lm` MOVES GEOMETRY. A change that shifts a coordinate in the
// fifteenth decimal is not visible in any assertion about dof or colouring,
// but it is a different sketch, it is what the user's part is built on, and
// after eighty iterations of a damped least-squares loop a difference that
// small is not guaranteed to stay small — the λ schedule branches on
// `e2 < err`, so one flipped comparison takes the whole run down another path.
//
// So the pin records the full solved parameter vector, digit for digit, via
// `toString` (which round-trips a double exactly in Dart). Nothing here is
// rounded, and nothing is compared with a tolerance. If the numbers move at
// all, this fails.
//
// The cases deliberately cover all three LM entry paths in
// `_solveConstraintsInner`:
//   * `lm`         — no drag, libslvs declined
//   * `lm-frozen`  — a drag the constraints CAN honour
//   * `lm-relaxed` — a drag they cannot, so the freeze is dropped and a
//                    second full run happens (the worst case in the 2D
//                    pipeline, per PERFORMANCE_PROFILE §5.4)
// and the unsatisfiable system the profile measures as
// `solve.overConstrained`.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/solver.dart';

/// Every number in the sketch, exactly. `toString` round-trips a double in
/// Dart, so this is the bit pattern in readable form — not an approximation
/// of it.
String geoSig(List<Geo> gs) =>
    gs.map((g) => '${g.type}:${g.data.join(",")}').join(';');

/// A short, human-checkable digest for the golden table, plus the full string
/// behind it so a failure can be read rather than guessed at.
void main() {
  group('the LM fallback moves geometry to exactly where it did (M232 pin)',
      () {
    // The profile's own over-constrained fixture: two conflicting fixes on one
    // point, 168 parameters, 124 residuals. The solver cannot win, so this
    // exercises the LOSING path — which §5.4 measures at 66.4 ms against a
    // 0.271 ms fast-path solve.
    test('solve.overConstrained — unsatisfiable, both LM passes', () {
      final gs = sketchFixture(24);
      final cs = constraintFixture(24)
        ..add(Constraint(CType.fix,
            ents: [1], pts: [const PRef(1, 0)], anchors: [999.0, 999.0]));
      final ok = solveConstraints(gs, cs, iterations: 80);
      // Recorded, not assumed: the two fixes conflict, but the LM lands the
      // point on the SECOND anchor to within `_renderable`, so the solve
      // reports success. Pinning the return value matters as much as pinning
      // the geometry — it is what the caller uses to decide whether to keep
      // the configuration at all.
      expect(ok, isTrue);
      expect(geoSig(gs), _goldOverConstrained);
    });

    test('an unsatisfied but SOLVABLE system converges to the same place', () {
      // Perturbed away from its solution so the LM actually has work to do.
      final gs = sketchFixture(12);
      for (var i = 0; i < gs.length; i++) {
        final d = List<double>.of(gs[i].data);
        d[0] += 3.5;
        d[1] -= 2.25;
        gs[i] = gs[i].withData(d);
      }
      final cs = constraintFixture(12);
      solveConstraints(gs, cs, iterations: 80);
      expect(geoSig(gs), _goldPerturbed);
    });

    test('a drag the constraints CAN honour (lm-frozen)', () {
      final gs = sketchFixture(8);
      final cs = constraintFixture(8);
      solveConstraints(gs, cs,
          dragged: {(0, 0)}, iterations: 80);
      expect(geoSig(gs), _goldDragFrozen);
    });

    test('a drag the constraints CANNOT honour (lm-relaxed, two full runs)',
        () {
      // The dragged point is pinned by a `fix` as well, so freezing it makes
      // the system unsatisfiable and the second, relaxed run must happen.
      final gs = sketchFixture(8);
      final cs = constraintFixture(8);
      final d = List<double>.of(gs[0].data);
      d[0] += 40; // haul the fixed circle's centre far off its anchor
      d[1] += 40;
      gs[0] = gs[0].withData(d);
      solveConstraints(gs, cs, dragged: {(0, 0)}, iterations: 80);
      expect(geoSig(gs), _goldDragRelaxed);
    });

    test('a tiny system with a tangency (branch capture on the LM path)', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 10]),
        Geo(Geo.line, [-30, 12, 30, 11]),
      ];
      final cs = [
        Constraint(CType.tangent, ents: [0, 1]),
        Constraint(CType.fix, pts: [const PRef(0, 0)], anchors: [0.0, 0.0]),
        Constraint(CType.dimension, ents: [0], dimKind: 'rad', value: 10.0),
      ];
      solveConstraints(gs, cs, iterations: 80);
      expect(geoSig(gs), _goldTangent);
    });

    test('rank/redundancy reporting is unchanged (debugRank)', () {
      // debugRank shares the Jacobian builder with the analysis and is the
      // ground truth other tests assert redundancy against.
      final gs = sketchFixture(12);
      final cs = constraintFixture(12);
      final (rank, eqs, params) = debugRank(gs, cs);
      expect('$rank/$eqs/$params', _goldDebugRank);
    });
  });
}

// Recorded from the implementation as it stood at 15dc9ae — after the sparse
// DOF analysis landed, before the normal equations changed.
const _goldOverConstrained = r'2:60.0,0.0,4.0;2:998.9999999999947,998.9999999999944,4.0;2:51.96152422706632,29.999999999999996,4.0;2:42.42640687119285,42.426406871192846,4.0;2:30.000000000000007,51.96152422706631,4.0;2:15.529142706151244,57.9555495773441,4.0;2:3.67394039744206e-15,60.0,4.0;2:-15.529142706151237,57.9555495773441,4.0;2:-29.999999999999986,51.96152422706632,4.0;2:-42.426406871192846,42.42640687119285,4.0;2:-51.96152422706632,29.999999999999996,4.0;2:-57.955549577344094,15.52914270615126,4.0;2:-60.0,7.34788079488412e-15,4.0;2:-57.9555495773441,-15.529142706151248,4.0;2:-51.96152422706633,-29.999999999999982,4.0;2:-42.426406871192874,-42.426406871192825,4.0;2:-30.00000000000003,-51.961524227066306,4.0;2:-15.529142706151237,-57.9555495773441,4.0;2:-1.1021821192326178e-14,-60.0,4.0;2:15.529142706151218,-57.95554957734411,4.0;2:30.000000000000007,-51.96152422706631,4.0;2:42.42640687119284,-42.42640687119286,4.0;2:51.961524227066306,-30.00000000000003,4.0;2:57.95554957734409,-15.529142706151294,4.0;1:60.0,0.0,998.9999999999932,998.999999999993;1:998.9999999999932,998.999999999993,51.96152422706632,29.999999999999996;1:51.96152422706632,29.999999999999996,42.42640687119285,42.426406871192846;1:42.42640687119285,42.426406871192846,30.000000000000007,51.96152422706631;1:30.000000000000007,51.96152422706631,15.529142706151244,57.9555495773441;1:15.529142706151244,57.9555495773441,3.67394039744206e-15,60.0;1:3.67394039744206e-15,60.0,-15.529142706151237,57.9555495773441;1:-15.529142706151237,57.9555495773441,-29.999999999999986,51.96152422706632;1:-29.999999999999986,51.96152422706632,-42.426406871192846,42.42640687119285;1:-42.426406871192846,42.42640687119285,-51.96152422706632,29.999999999999996;1:-51.96152422706632,29.999999999999996,-57.955549577344094,15.52914270615126;1:-57.955549577344094,15.52914270615126,-60.0,7.34788079488412e-15;1:-60.0,7.34788079488412e-15,-57.9555495773441,-15.529142706151248;1:-57.9555495773441,-15.529142706151248,-51.96152422706633,-29.999999999999982;1:-51.96152422706633,-29.999999999999982,-42.426406871192874,-42.426406871192825;1:-42.426406871192874,-42.426406871192825,-30.00000000000003,-51.961524227066306;1:-30.00000000000003,-51.961524227066306,-15.529142706151237,-57.9555495773441;1:-15.529142706151237,-57.9555495773441,-1.1021821192326178e-14,-60.0;1:-1.1021821192326178e-14,-60.0,15.529142706151218,-57.95554957734411;1:15.529142706151218,-57.95554957734411,30.000000000000007,-51.96152422706631;1:30.000000000000007,-51.96152422706631,42.42640687119284,-42.42640687119286;1:42.42640687119284,-42.42640687119286,51.961524227066306,-30.00000000000003;1:51.961524227066306,-30.00000000000003,57.95554957734409,-15.529142706151294;1:57.95554957734409,-15.529142706151294,60.0,0.0';
const _goldPerturbed = r'2:60.0000000000608,-3.908426421262302e-11,4.0;2:54.46152422705853,28.39285714286207,4.0;2:32.499999999992355,50.354381369928475,4.0;2:2.500000000005853,58.39285714285577,4.0;2:-27.49999999999159,50.35438136992852,4.0;2:-49.46152422706524,28.39285714286207,4.0;2:-57.50000000000761,-1.607142857136884,4.0;2:-49.4615242270652,-31.60714285714655,4.0;2:-27.499999999991662,-53.56866708420931,4.0;2:2.500000000005883,-61.607142857137966,4.0;2:32.499999999992355,-53.56866708420931,4.0;2:54.46152422705855,-31.60714285714654,4.0;1:60.000000000077975,-5.012744401508246e-11,54.46152422705841,28.392857142862148;1:54.46152422705864,28.392857142862,32.499999999992234,50.35438136992855;1:32.49999999999247,50.354381369928404,2.500000000005735,58.392857142855846;1:2.5000000000059637,58.392857142855696,-27.499999999991708,50.35438136992859;1:-27.49999999999148,50.35438136992845,-49.46152422706536,28.392857142862148;1:-49.46152422706513,28.392857142862,-57.50000000000773,-1.607142857136808;1:-57.500000000007496,-1.607142857136955,-49.46152422706532,-31.60714285714647;1:-49.461524227065084,-31.60714285714662,-27.499999999991783,-53.56866708420923;1:-27.49999999999155,-53.56866708420938,2.5000000000057647,-61.60714285713789;1:2.5000000000059934,-61.60714285713804,32.499999999992234,-53.56866708420923;1:32.49999999999247,-53.56866708420938,54.46152422705843,-31.60714285714646;1:54.46152422705866,-31.60714285714661,60.00000000007775,-4.998046583009453e-11';
const _goldDragFrozen = r'2:60.0,0.0,4.0;2:42.42640687119285,42.426406871192846,4.0;2:3.67394039744206e-15,60.0,4.0;2:-42.426406871192846,42.42640687119285,4.0;2:-60.0,7.34788079488412e-15,4.0;2:-42.42640687119286,-42.426406871192846,4.0;2:-1.1021821192326178e-14,-60.0,4.0;2:42.42640687119284,-42.42640687119286,4.0;1:60.0,0.0,42.42640687119285,42.426406871192846;1:42.42640687119285,42.426406871192846,3.67394039744206e-15,60.0;1:3.67394039744206e-15,60.0,-42.426406871192846,42.42640687119285;1:-42.426406871192846,42.42640687119285,-60.0,7.34788079488412e-15;1:-60.0,7.34788079488412e-15,-42.42640687119286,-42.426406871192846;1:-42.42640687119286,-42.426406871192846,-1.1021821192326178e-14,-60.0;1:-1.1021821192326178e-14,-60.0,42.42640687119284,-42.42640687119286;1:42.42640687119284,-42.42640687119286,60.0,0.0';
const _goldDragRelaxed = r'2:60.00000000042362,4.2361516734748947e-10,4.0;2:42.42640687119285,42.426406871192846,4.0;2:3.67394039744206e-15,60.0,4.0;2:-42.426406871192846,42.42640687119285,4.0;2:-60.0,7.34788079488412e-15,4.0;2:-42.42640687119286,-42.426406871192846,4.0;2:-1.1021821192326178e-14,-60.0,4.0;2:42.42640687119284,-42.42640687119286,4.0;1:60.000000000542435,5.424324137770882e-10,42.42640687119285,42.426406871192846;1:42.42640687119285,42.426406871192846,3.67394039744206e-15,60.0;1:3.67394039744206e-15,60.0,-42.426406871192846,42.42640687119285;1:-42.426406871192846,42.42640687119285,-60.0,7.34788079488412e-15;1:-60.0,7.34788079488412e-15,-42.42640687119286,-42.426406871192846;1:-42.42640687119286,-42.426406871192846,-1.1021821192326178e-14,-60.0;1:-1.1021821192326178e-14,-60.0,42.42640687119284,-42.42640687119286;1:42.42640687119284,-42.42640687119286,60.000000000542435,5.424324137771941e-10';
const _goldTangent = r'2:2.219533014422542e-13,1.5094336170718e-11,10.000000000015097;1:-30.03100938740162,10.507690747518124,29.968591906089518,9.496203300564591';
const _goldDebugRank = r'62/62/84';
