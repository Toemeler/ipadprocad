// S5 (OPTIMIZATION_PLAN.md §5, Session 5) — why the per-occurrence edge
// enumeration in a patterned blend CANNOT be hoisted out of the loop.
//
// The plan's brief for this session asked for exactly that hoist: profile §8.2
// measures `applyBlendOccurrence` performing one full `kernel.edgesOf(body)`
// per occurrence, 142.9 ms of it on a 180-edge body, and that enumeration is
// 97.6 % of a patterned blend's cost. Removing a factor of N from it looks like
// free money.
//
// It is not, and the plan said where to look: "Establish whether the body
// changes between occurrences before you hoist. This is the single most likely
// way to break a real part in this whole plan." It does change. Each
// occurrence's blend REPLACES the running body, and the ids that
// `resolveEdges` hands to `filletEdges` are positional indices into the
// enumeration of the body they were resolved against. Share one snapshot
// across occurrences and those indices start naming edges of a shape that no
// longer exists — silently, because the kernel will happily blend whatever
// edges the numbers now point at.
//
// This file makes that structural, not editorial. It fails if anyone hoists.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

KernelSolid _stub([double volume = 1000]) => KernelSolid(
    OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
        Int32List.fromList(const [0]), Float64List(0)),
    volume,
    null);

/// One call to the kernel, with the solid it was made against.
class _Call {
  _Call(this.solid, this.ids);
  final KernelSolid solid;
  final List<int> ids;
}

/// A kernel that gives every solid its OWN edge numbering.
///
/// That is the whole design of this fake. A real kernel re-enumerates a shape's
/// topology after a fillet rebuilds it, and the numbers move; this one makes
/// the move loud by handing solid *k* the indices 100k+1 .. 100k+12 for the
/// same twelve edges at the same twelve places. So the ids that come back from
/// a blend say, unambiguously, WHICH enumeration produced them — and a hoisted
/// snapshot would answer with the first solid's numbering for every
/// occurrence.
class EdgeNumberingRecorder implements PartKernel {
  final enumerated = <KernelSolid>[]; // one entry per edgesOf call
  final blended = <_Call>[]; // one entry per filletEdges call
  final _numbering = <KernelSolid, int>{};
  int _next = 0;

  @override
  bool get available => true;
  @override
  String get info => 'edge numbering recorder';
  @override
  String get lastError => '';

  int _generationOf(KernelSolid s) => _numbering.putIfAbsent(s, () => _next++);

  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) {
    enumerated.add(s);
    final g = _generationOf(s);
    // Twelve edges, 10 mm apart along X, so a pattern stepping 10 mm at a time
    // has something to resolve against at every occurrence. Their geometry is
    // identical from one solid to the next; only the NUMBERING moves.
    return [
      for (var i = 0; i < 12; i++)
        OcctEdgeInfo(
            100 * g + i + 1, 1, i * 10.0, 0, 0, 1, 0, 0, 5, 0, 2, 90, -1)
    ];
  }

  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> ids, List<double> radii,
      {List<double> radii2 = const [], BlendReport? report}) {
    blended.add(_Call(base, List.of(ids)));
    // A NEW solid, exactly as the real kernel does: a fillet does not modify
    // its input, it builds a different shape.
    return _stub(base.volume + 1);
  }

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
          double taperDeg, List<double> mat34) =>
      _stub(height * 100);

  @override
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) => _stub(s.volume);

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      _stub(a.volume + b.volume);

  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) =>
      _stub(a.volume - b.volume);

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) => _stub(a.volume);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void _rect(SketchModel s, String layer, double x0, double y0, double x1,
    double y1) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

Future<AppState> _appWithPart(PartKernel k) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m232_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  _rect(app.activeChild!, app.editingLayer!, 0, 0, 20, 10);
  app.finishPartSketch();
  final p = app.currentPart!;
  final sk = p.childSketches.single.model.name;
  p.features.add(ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: sk,
      profiles: [ProfileSel(10, 5, 200)])
    ..output = 'new'
    ..seq = p.nextSeq());
  recomputeAllFeatures(p, k, force: true);
  return app;
}

/// A rectangular pattern of the extrusion AND a fillet on it — the shape of
/// part that §8.2 measured.
PatternFeature _patternedBlend(int count) => PatternFeature(
      name: 'RectangularPattern1',
      bodyName: 'Solid1',
      mode: PatternKind.rectangular,
      sources: ['Extrusion1', 'Fillet1'],
      dirA: AxisRef(0, 0, 0, 1, 0, 0, 'X Axis'),
      countA: count,
      distanceA: 10,
      distributionA: PatternDistribution.spacing,
    );

Future<(EdgeNumberingRecorder, PartModel, PatternFeature)> _setUp(
    int count) async {
  final k = EdgeNumberingRecorder();
  final app = await _appWithPart(k);
  final p = app.currentPart!;
  p.features.add(FilletFeature(
      name: 'Fillet1',
      bodyName: 'Solid1',
      edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
      radii: const [2]));
  final f = _patternedBlend(count);
  k.enumerated.clear();
  k.blended.clear();
  return (k, p, f);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a patterned blend enumerates the body it is about to modify', () {
    test('one enumeration per occurrence, each on a DIFFERENT solid', () async {
      // 9 occurrences = the original + 8 copies, which is §8.2's top rung.
      final (k, p, f) = await _setUp(9);
      expect(recomputeFeature(p, f, k, base: _stub()), isTrue,
          reason: f.computeError ?? '');
      expect(k.blended.length, 8, reason: 'one blend per copy');
      expect(k.enumerated.length, 8,
          reason: 'and one edge enumeration per blend — this is the 97.6 % of '
              '§8.2, and it is per occurrence by necessity, not by accident');
      // The point of the whole file: every enumeration saw a different solid.
      for (var i = 1; i < k.enumerated.length; i++) {
        expect(identical(k.enumerated[i], k.enumerated[i - 1]), isFalse,
            reason: 'occurrence $i was enumerated on the same solid as '
                'occurrence ${i - 1}. If that is ever true, the body stopped '
                'changing between occurrences and this whole finding needs '
                're-deriving — but it is NOT a licence to hoist until it is');
      }
    });

    test('the solid that was enumerated is the solid that gets blended',
        () async {
      final (k, p, f) = await _setUp(5);
      expect(recomputeFeature(p, f, k, base: _stub()), isTrue,
          reason: f.computeError ?? '');
      expect(k.enumerated.length, k.blended.length);
      for (var i = 0; i < k.blended.length; i++) {
        expect(identical(k.blended[i].solid, k.enumerated[i]), isTrue,
            reason: 'occurrence $i resolved its edge ids against one solid and '
                'applied them to another — that is precisely the failure a '
                'hoisted enumeration would introduce');
      }
    });

    test('the ids handed to the kernel come from THAT occurrence\'s '
        'enumeration, not the first one', () async {
      final (k, p, f) = await _setUp(5);
      expect(recomputeFeature(p, f, k, base: _stub()), isTrue,
          reason: f.computeError ?? '');
      // The recorder numbers solid g's edges 100g+1..100g+3. The fingerprint
      // sits at x = 0 and each occurrence moves it 10 mm further along X, so
      // occurrence j must resolve to the SECOND or THIRD edge of ITS OWN
      // generation — never to a 100*0 + n index after the first one.
      final generations = <int>[];
      for (final c in k.blended) {
        expect(c.ids, hasLength(1));
        generations.add(c.ids.single ~/ 100);
      }
      expect(generations, [0, 1, 2, 3],
          reason: 'each occurrence used a fresh enumeration; a hoisted '
              'snapshot would give [0, 0, 0, 0] and quietly blend the wrong '
              'edges of the wrong shape');
      // ...and within each generation it is the moved fingerprint that won.
      expect([for (final c in k.blended) c.ids.single % 100], [2, 3, 4, 5],
          reason: 'the selection at x = 0 was moved to 10, 20, 30, 40, and the '
              'recorder puts its i-th edge at x = 10i — so occurrence j must '
              'land on local edge j + 1 of its own generation');
    });

    test('the first occurrence works on the base solid itself', () async {
      final (k, p, f) = await _setUp(3);
      final base = _stub();
      expect(recomputeFeature(p, f, k, base: base), isTrue,
          reason: f.computeError ?? '');
      // Not an optimisation opportunity — just the fact that anchors the
      // chain: everything after occurrence 1 stands on a solid this loop made.
      expect(identical(k.enumerated.first, base), isFalse,
          reason: 'the extrusion tool is combined onto the base before the '
              'blend runs, so even the first blend sees a folded solid');
    });
  });
}
