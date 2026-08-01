// M182 — "a system that cannot break": the recompute safety net.
//
// Everything here is host-testable with the FakeKernel pattern from m56:
// visibility must never change the fold, a failed feature must poison its
// body instead of spawning a phantom, a broken chain must fail loudly, and
// the projection closure guard must refuse an update that would open a loop a
// feature builds on. The device session that motivated all of it is the
// regression fixture: Chamfer1 lost its base (nothing to modify), Extrusion4
// recomputed as a standalone "cut", projections in Sketch5/6 opened the
// revolve profiles, and the whole second solid died.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/native_browser.dart';

/// The m56 FakeKernel: volumes add on fuse, subtract on cut, and `fail` makes
/// the solid-producing calls return null — exactly what the "cannot break"
/// tests need (a broken kernel call is the analogue of a sick feature).
class FakeKernel implements PartKernel {
  bool fail = false;
  int extrudes = 0;
  int fusions = 0;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  KernelSolid _stub(double v) => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return fail ? null : _stub(height);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    fusions++;
    return _stub(a.volume + b.volume);
  }

  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    return _stub(a.volume - b.volume);
  }

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    return _stub(math.min(a.volume, b.volume));
  }

  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) =>
      [OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 5, 0, 2, 90, 1)];

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// A kernel that RECORDS what the body-modify path handed it, so the tests can
/// assert that a chamfer really got the folded base — even when the feature
/// above it was hidden.
class RecordingKernel extends FakeKernel {
  KernelSolid? lastModifyBase;
  int chamfers = 0;

  @override
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
      double d1, double d2, double angleDeg) {
    chamfers++;
    lastModifyBase = base;
    return _stubFor(base);
  }

  KernelSolid _stubFor(KernelSolid base) => KernelSolid(base.mesh,
      base.volume, null);
}

void _addRect(SketchModel s, String layer) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(0, 0, 20, 0);
  s.engine.addLine(20, 0, 20, 10);
  s.engine.addLine(20, 10, 0, 10);
  s.engine.addLine(0, 10, 0, 0);
  s.refresh();
}

/// An AppState with a real part: [n] extrusions of the SAME 20x10 rectangle,
/// each on its OWN sketch, all built. Per-feature sketches matter here: the
/// "cannot break" tests break ONE feature's profile and assert that only its
/// own body chain reacts, so a shared sketch would fail everything at once.
Future<AppState> appWith(int n, {PartKernel? kernel}) async {
  final app = AppState()..partKernel = kernel ?? FakeKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m182_');
  await app.createNamedPart('P');
  for (var i = 1; i <= n; i++) {
    app.startPartSketch();
    app.planePicked('xy');
    _addRect(app.activeChild!, app.editingLayer!);
    app.finishPartSketch();
    final p = app.currentPart!;
    final f = ExtrudeFeature(
        name: 'Extrusion$i',
        bodyName: 'Solid1',
        sketchName: p.childSketches.last.model.name,
        profiles: [ProfileSel(10, 5, 200)]);
    f.output = i == 1 ? 'new' : 'join';
    f.seq = p.nextSeq();
    p.appendFeature(f);
  }
  recomputeAllFeatures(app.currentPart!, app.partKernel);
  return app;
}

/// Replaces [sketch]'s content with a single open line, so its profile can no
/// longer resolve — the test's stand-in for a feature going sick.
void _breakProfile(SketchModel s) {
  s.engine.dispose();
  s.engine = Engine.create();
  s.engine.setCurrentLayer(s.layers.first);
  s.engine.addLine(0, 0, 20, 0);
  s.refresh();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M182 — visibility is a display property, never geometry', () {
    test('hiding a mid-chain extrusion does not change the folded body',
        () async {
      final app = await appWith(3);
      final p = app.currentPart!;
      final top = p.features[2];
      final before = top.solid!.volume; // E1+E2+E3 folded

      // Hide the MIDDLE extrusion and rebuild — exactly what a subsequent
      // operation does. force: true defeats the feature cache so the fold is
      // REALLY re-derived with E2 invisible: it must still contain E2's
      // volume. (With the old code this rebuilt E3 against E1 only and the
      // body shrank — the reported "hiding an extrusion broke the solid".)
      app.toggleFeatureVisible(p.features[1]);
      recomputeAllFeatures(p, app.partKernel, force: true);
      expect(top.solid!.volume, before,
          reason: 'hiding may change the picture, never the part');
    });

    test('hiding the last feature leaves the next modify feature its base',
        () async {
      final kernel = RecordingKernel();
      final app = await appWith(2, kernel: kernel);
      final p = app.currentPart!;
      final fil = ChamferFeature(
          name: 'Chamfer1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)]);
      fil.seq = p.nextSeq();
      p.appendFeature(fil);
      recomputeAllFeatures(p, app.partKernel);
      expect(kernel.chamfers, 1);
      final baseWithAllVisible = kernel.lastModifyBase;

      // Hide the LAST extrusion (the fold carrier), then force a rebuild:
      // the chamfer must STILL receive the folded body as its base.
      p.features[1].visible = false;
      recomputeAllFeatures(p, app.partKernel, force: true);
      expect(kernel.chamfers, 2);
      expect(kernel.lastModifyBase, isNotNull,
          reason: 'a hidden predecessor must not null the base');
      expect(kernel.lastModifyBase!.volume, baseWithAllVisible!.volume);
    });
  });

  group('M182 — a failed feature poisons its body, never spawns a phantom', () {
    test('downstream features fail loudly and never spawn a phantom', () async {
      final app = await appWith(3);
      final p = app.currentPart!;
      expect(p.features.every((f) => f.solid != null), isTrue,
          reason: 'baseline built');

      // Break the MIDDLE feature: its sketch loses one side of the rectangle,
      // so its profile can no longer resolve. (The device analogue: Chamfer1
      // failing and Extrusion4 materialising as a standalone cut.)
      final mid = p.features[1];
      _breakProfile(p.sketchByName(mid.sketchName)!.model);

      final ok = recomputeAllFeatures(p, app.partKernel, force: true);
      expect(ok, isFalse, reason: 'the pass must report the failure');
      expect(mid.computeError, isNotNull,
          reason: 'the broken feature itself is sick');
      expect(mid.solid, isNull, reason: 'a sick feature holds no solid');
      final top = p.features[2];
      expect(top.computeError, isNotNull,
          reason: 'downstream must NOT be silently recomputed as a phantom');
      expect(top.computeError, contains(mid.name),
          reason: 'the error must name the culprit');
      expect(top.solid, isNull,
          reason: 'the poisoned chain holds no stale or invented solid');
      // The FIRST feature (upstream of the failure) is untouched and still
      // carries its body — a failure only poisons what comes after it.
      expect(p.features[0].solid, isNotNull);
      expect(p.features[0].computeError, isNull);
    });

    test('a body-modify feature on a broken chain never materialises', () async {
      final app = await appWith(1);
      final p = app.currentPart!;
      // The base extrusion goes sick FIRST (the device analogue: Chamfer1
      // losing its base when the fold above it broke).
      _breakProfile(p.sketchByName(p.features[0].sketchName)!.model);
      final fil = ChamferFeature(
          name: 'Chamfer1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)]);
      fil.seq = p.nextSeq();
      p.appendFeature(fil);

      final ok = recomputeAllFeatures(p, app.partKernel, force: true);
      expect(ok, isFalse);
      expect(fil.solid, isNull,
          reason: 'nothing may materialise without a base (no phantoms)');
      expect(fil.computeError, isNotNull,
          reason: 'no solid before this feature is an ERROR, not a phantom');
      expect(fil.computeError, contains(p.features[0].name),
          reason: 'the error must name the broken predecessor');
    });

    test('a missing imported body leaves a non-new feature without a base',
        () async {
      final app = await appWith(1);
      final p = app.currentPart!;
      // The imported body's STEP file is gone: the feature holds no solid and
      // there is nothing to build on. The 'no solid before' path must fire.
      final base = p.features[0];
      (base as ExtrudeFeature).imported = true;
      base.disposeSolid();
      final fil = ChamferFeature(
          name: 'Chamfer1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)]);
      fil.seq = p.nextSeq();
      p.appendFeature(fil);

      recomputeAllFeatures(p, app.partKernel, force: true);
      expect(fil.computeError, contains('no solid before'),
          reason: 'an absent predecessor must be reported, not papered over');
      expect(fil.solid, isNull);
    });
  });

  group('M182 — the projection closure guard', () {
    final layers = ['Layer 1'];
    final hidden = <String>{};
    const eos = 1;

    Geo _line(double x0, double y0, double x1, double y1,
            {int proj = Geo.projNone, int projSeg = -1}) =>
        Geo(Geo.line, [x0, y0, x1, y1],
            layer: 'Layer 1', proj: proj, projSeg: projSeg);

    test('an update that opens a loop is refused and frozen in place', () {
      // A closed rectangle; the fourth side is a projection of a 3D edge.
      final orig = [
        _line(0, 0, 20, 0),
        _line(20, 0, 20, 10),
        _line(20, 10, 0, 10),
        _line(0, 10, 0, 0, proj: Geo.projSolid, projSeg: 7),
      ];
      expect(profileLoopCount(ProfileInput(orig, layers, hidden, eos)), 1);

      // The candidate sync moved the projected side far away: the loop opens.
      final gs = [
        _line(0, 0, 20, 0),
        _line(20, 0, 20, 10),
        _line(20, 10, 0, 10),
        _line(0, 10, 40, 10, proj: Geo.projSolid, projSeg: 7),
      ];
      expect(profileLoopCount(ProfileInput(gs, layers, hidden, eos)), 0,
          reason: 'the candidate really is broken');

      final out =
          freezeProjectionUpdatesThatBreakLoops(orig, gs, layers, hidden, eos);
      expect(profileLoopCount(ProfileInput(out, layers, hidden, eos)), 1,
          reason: 'the guard must restore the loop');
      final frozen = out[3];
      expect(frozen.proj, Geo.projBroken,
          reason: 'the moved segment is frozen, no longer source-following');
      expect(frozen.data[0], 0.0);
      expect(frozen.data[1], 10.0,
          reason: 'it keeps its OLD curve, not the broken new one');
    });

    test('a harmless update (loop still closed) passes through untouched', () {
      final orig = [
        _line(0, 0, 20, 0),
        _line(20, 0, 20, 10),
        _line(20, 10, 0, 10),
        _line(0, 10, 0, 0, proj: Geo.projSolid, projSeg: 7),
      ];
      // The projected edge moved and the whole profile followed it by 1 mm —
      // the loop stays closed (this is a legitimate projection follow).
      final gs = [
        _line(1, 0, 21, 0),
        _line(21, 0, 21, 10),
        _line(21, 10, 1, 10),
        _line(1, 10, 1, 0, proj: Geo.projSolid, projSeg: 7),
      ];
      expect(profileLoopCount(ProfileInput(gs, layers, hidden, eos)), 1);

      final out =
          freezeProjectionUpdatesThatBreakLoops(orig, gs, layers, hidden, eos);
      expect(identical(out, gs), isTrue,
          reason: 'no loop lost -> no freezing, the sync result is pushed');
      expect(out[3].proj, Geo.projSolid);
    });
  });

  group('M182 — the native browser expansion key', () {
    test('a consumed sketch appears when the host stores the row id', () async {
      final app = await appWith(1);
      final p = app.currentPart!;
      final sk = p.childSketches.single.model.name;
      // The host's expansion set holds the ROW ID ('ft:Extrusion1').
      final rows = buildBrowserRows(app, expanded: {'$kIdFeature${p.features[0].name}'});
      final ids = [for (final r in rows) r.id];
      expect(ids, contains('$kIdNested$sk'),
          reason: 'the consumed sketch must nest under its expanded feature');

      // With the BARE name (the old bug) it must NOT appear.
      final rows2 = buildBrowserRows(app, expanded: {p.features[0].name});
      final ids2 = [for (final r in rows2) r.id];
      expect(ids2, isNot(contains('$kIdNested$sk')));
    });
  });
}
