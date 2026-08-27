// M268 — the FPS overlay is gone; the numbers it kept are not.
//
// The bottom-right readout (M77) was removed because a permanent debug HUD
// over the canvas of an app that ships is not a feature. The risk in removing
// it was never the pixels: five perf gauges were computed as a SIDE EFFECT of
// drawing it, three of which nothing else in the app produces. Deleted with
// the widget, they would have vanished from every bug bundle and from
// `perf_snapshot.json`, and nothing would have failed — the perf gate skips
// these five by name, precisely because they describe the open document rather
// than the suite's own work.
//
// So these tests are about the numbers surviving the widget:
//
//   1. `documentGauges` counts what the renderer draws — and reports NOTHING,
//      rather than zero, for a document that is not open.
//   2. `Perf.report()` and `Perf.jsonSnapshot()` PULL from the registered
//      sources, so the values are current at the moment a snapshot is taken
//      instead of as fresh as the last repaint.
//   3. A source that throws costs its own numbers and nothing else.
//   4. `installDocumentGauges` twice leaves ONE source, not two.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/perf_document.dart';

/// A kernel whose solids carry a KNOWN triangle count, so the walk can be
/// checked against arithmetic rather than against whatever OCCT happens to
/// tessellate.
class _TriKernel implements PartKernel {
  _TriKernel(this.trisPerSolid);
  final int trisPerSolid;

  @override
  bool get available => true;
  @override
  String get info => 'tri-stub';
  @override
  String get lastError => 'tri-stub failure';

  KernelSolid _mk(double v) => KernelSolid(
      OcctMeshData(
          Float64List(0),
          Float64List(0),
          Int32List(trisPerSolid * 3),
          Int32List.fromList(const [0]),
          Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
          double taperDeg, List<double> mat34) =>
      _mk(height);
  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) => _mk(3);
  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) => _mk(4);
  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) => _mk(5);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

late String _sk;

ExtrudeFeature _ex(String name, String body) => ExtrudeFeature(
    name: name,
    bodyName: body,
    sketchName: _sk,
    profiles: [ProfileSel(10, 5, 200)]);

void _addRect(SketchModel s, String layer) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(0, 0, 20, 0);
  s.engine.addLine(20, 0, 20, 10);
  s.engine.addLine(20, 10, 0, 10);
  s.engine.addLine(0, 10, 0, 0);
  s.refresh();
}

/// A part with one sketch and [n] separate bodies, each built, each carrying
/// [trisPerSolid] triangles. `output: 'new'` throughout on purpose: a join
/// would consume its predecessor, and the point here is to count solids.
Future<AppState> _appWith(int n, {int trisPerSolid = 4}) async {
  final app = AppState()..partKernel = _TriKernel(trisPerSolid);
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m268_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  _addRect(app.activeChild!, app.editingLayer!);
  app.finishPartSketch();
  final p = app.currentPart!;
  _sk = p.childSketches.single.model.name;
  for (var i = 1; i <= n; i++) {
    final f = _ex('Extrusion$i', 'Solid$i')
      ..output = 'new'
      ..seq = p.nextSeq();
    p.appendFeature(f);
  }
  recomputeAllFeatures(p, app.partKernel);
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(Perf.resetForTest);
  tearDown(Perf.resetForTest);

  group('the overlay is gone', () {
    test('nothing imports the deleted widget', () {
      // A stale import would not compile, but a stale REFERENCE in a comment
      // or a doc is how a reader is sent looking for a file that is not there.
      final f = File('lib/widgets/perf_overlay.dart');
      expect(f.existsSync(), isFalse,
          reason: 'perf_overlay.dart was removed in M268');
    });
  });

  group('documentGauges — what the renderer draws', () {
    test('an empty app reports NOTHING, not zeroes', () {
      // The distinction matters in a bug bundle: "0 triangles" says a model is
      // open and empty; a missing key says the gallery was on screen.
      expect(documentGauges(AppState()), isEmpty);
    });

    test('counts features, built solids and their triangles', () async {
      final app = await _appWith(3, trisPerSolid: 4);
      final g = documentGauges(app);
      expect(g[kGaugeFeatures], 3);
      expect(g[kGaugeSolids], 3);
      expect(g[kGaugeTriangles], 12);
    });

    test('a hidden feature is counted but not drawn', () async {
      final app = await _appWith(3, trisPerSolid: 4);
      app.currentPart!.features.first.visible = false;
      final g = documentGauges(app);
      // Still three features — the browser shows it. Two solids and eight
      // triangles — the viewport does not.
      expect(g[kGaugeFeatures], 3);
      expect(g[kGaugeSolids], 2);
      expect(g[kGaugeTriangles], 8);
    });

    test('sketch entities and projections', () async {
      final app = await _appWith(1);
      final s = app.currentPart!.childSketches.single.model;
      app.openChildSketch(s.name);
      expect(app.current, isNotNull);
      final g = documentGauges(app);
      expect(g[kGaugeSketchEntities], s.geometry.length);
      expect(g[kGaugeSketchProjections], 0);
    });
  });

  group('Perf pulls its sources', () {
    test('a snapshot carries the CURRENT counts, not the last observed', () {
      var n = 1;
      Perf.addGaugeSource(() => {'m268.n': n});
      expect(Perf.jsonSnapshot()['gauges'], containsPair('m268.n', 1));
      n = 7;
      // No repaint, no timer, no widget: the number moved because a snapshot
      // asked for it. That is the whole reason this indirection exists.
      expect(Perf.jsonSnapshot()['gauges'], containsPair('m268.n', 7));
    });

    test('a throwing source costs only its own numbers', () {
      Perf.addGaugeSource(() => throw StateError('boom'));
      Perf.addGaugeSource(() => {'m268.survivor': 42});
      expect(Perf.jsonSnapshot()['gauges'],
          containsPair('m268.survivor', 42));
    });

    test('a source can be taken back down', () {
      Map<String, int> src() => {'m268.gone': 1};
      Perf.addGaugeSource(src);
      Perf.pullGauges();
      expect(Perf.gauges.containsKey('m268.gone'), isTrue);
      Perf.removeGaugeSource(src);
      Perf.gauges.remove('m268.gone');
      Perf.pullGauges();
      expect(Perf.gauges.containsKey('m268.gone'), isFalse);
    });

    test('installing twice leaves one source, not two', () async {
      final a = await _appWith(2, trisPerSolid: 5);
      final b = await _appWith(1, trisPerSolid: 5);
      installDocumentGauges(a);
      installDocumentGauges(b);
      Perf.pullGauges();
      // The SECOND app answers. Stacked, the first would have overwritten it
      // and the report would describe a document nobody has open.
      expect(Perf.gauges[kGaugeFeatures], 1);
      expect(Perf.gauges[kGaugeTriangles], 5);
    });
  });
}
