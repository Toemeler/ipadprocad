// M256 — the Output boolean follows the geometry, until the user says
// otherwise.
//
// Requested from the device: "wenn ich eine extrusion oder ein anderes tool
// brauche soll es überlegene agieren. es soll immer zuerst hinzufügen
// ausgewählt sein. aber wenn ich in die extrusion umkehre soll automatisch auf
// wegnehmen geschaltet werden wenn ein Grossteil der extrusion im gleichen
// teil wäre. ich will es immer noch umschalten können aber es soll intelligent
// funktionieren."
//
// The session log shows the work this replaces, three taps for one intention:
//
//     (preview) op=join      <- drew a circle on a face
//     (preview) op=join      <- turned the extrusion around, into the body
//     (preview) op=cut       <- and had to say so by hand
//
// The rule is in two halves and they are tested apart, because they fail
// apart. [suggestedOutput] is the POLICY — a pure function of the boolean in
// force and how much of the tool is buried — and needs no kernel, no part and
// no panel to pin. The session tests are the WIRING: that the fraction is read
// off the boolean the preview already ran, that the switch reaches the panel,
// and that a choice made by hand ends the automation for good.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A kernel that models OVERLAP, which is the whole point here.
///
/// Every other fake in this suite answers `join = a+b` and `cut = a-b`, which
/// are two different worlds at once — the first says the tool misses the body
/// entirely, the second says it is buried in it. M256 reads the overlap back
/// out of exactly those numbers, so it needs a fake that keeps ONE story:
///
///     |a ∩ b| = inside * |b|
///     join    = |a| + |b| - |a ∩ b|
///     cut     = |a| - |a ∩ b|
///
/// [inside] is the knob the tests turn: 0 is a tool in free air, 1 is a tool
/// wholly buried in the body it is aimed at.
class FakeKernel implements PartKernel {
  bool fail = false;
  double inside = 0;
  int fusions = 0, cuts = 0, intersects = 0;
  List<List<List<Offset>>>? lastGroups;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  KernelSolid _solid(OcctMeshData? mesh, double vol) => KernelSolid(
      mesh ??
          OcctMeshData(
              Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
              Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
              Int32List.fromList(const [0, 1, 2]),
              Int32List.fromList(const [0, 3]),
              Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
      vol,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    lastGroups = groups;
    return fail ? null : _solid(null, height);
  }

  double _overlap(KernelSolid tool) => inside * tool.volume;

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    fusions++;
    return _solid(a.mesh, a.volume + b.volume - _overlap(b));
  }

  @override
  KernelSolid? cutSolids(KernelSolid base, KernelSolid tool) {
    if (fail) return null;
    cuts++;
    return _solid(base.mesh, base.volume - _overlap(tool));
  }

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) {
    if (fail) return null;
    intersects++;
    return _solid(a.mesh, _overlap(b));
  }

  @override
  bool exportStep(List<KernelSolid> solids, String path) => false;

  // M217 — this fake implements EVERY member explicitly (no noSuchMethod), so
  // face surgery has to land here too. It models none of it, and says so.
  @override
  KernelSolid? deleteFaces(KernelSolid base, List<int> faceIds) => null;
  @override
  KernelSolid? moveFaces(KernelSolid base, List<int> faceIds, Vec3 delta) =>
      null;
  @override
  KernelSolid? scaleSolid(KernelSolid base, Vec3 centre, double factor) => null;

  // M214 — this fake implements EVERY member explicitly (no noSuchMethod), so
  // a new member on PartKernel has to land here too. It writes nothing, like
  // exportStep above.
  @override
  bool exportStepBodies(List<(String, KernelSolid)> bodies, String path,
          {String product = ''}) =>
      exportStep([for (final b in bodies) b.$2], path);

  // M102 — the fake does not model revolve or body modification; saying so
  // honestly is what the feature will surface as its computeError.
  @override
  KernelSolid? revolve(List<List<List<Offset>>> groups, double angleDeg,
          double axPx, double axPy, double axDx, double axDy,
          List<double> mat34) =>
      null;
  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => const [];
  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> edgeIds,
          List<double> radii, {List<double> radii2 = const [], BlendReport? report}) =>
      null;
  @override
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
          double d1, double d2, double angleDeg, {BlendReport? report}) =>
      null;

  @override
  List<KernelSolid> importStepSolids(String path) => const [];
  // M212 — the two placements a pattern needs. This fake models neither, and
  // says so rather than inventing a solid.
  @override
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) => null;

  @override
  MeshImportOutcome meshToBrep(Float64List xyz, Int32List triangles,
          {double tolFraction = 0}) =>
      const MeshImportOutcome(
          null, MeshToBrepReport.empty(), 'fake kernel: no mesh converter');
  @override
  KernelSolid? mirrorSolid(KernelSolid s, Vec3 planePoint, Vec3 planeNormal) =>
      null;
  @override
  List<double> revolveHits(KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p) =>
      const [];
  @override
  KernelSolid? sweep(List<List<List<Offset>>> groups, List<double> mat34,
          List<double> pathPts,
          {int orientation = 0,
           double taperDeg = 0,
           double twistDeg = 0,
           int pathMode = SweepPathMode.auto}) =>
      null;
  @override
  KernelSolid? loft(List<List<Offset>> sections, List<List<double>> mats,
          {bool solid = true, bool ruled = false, bool closed = false}) =>
      null;
  @override
  KernelSolid? coil(List<List<List<Offset>>> groups, List<double> mat34,
          Vec3 axP, Vec3 axD,
          {required double revolutions,
          required double height,
          double taperDeg = 0,
          bool clockwise = false}) =>
      null;
  @override
  List<double> revolveHitsFace(
          KernelSolid s, Vec3 axP, Vec3 axD, Vec3 p, Vec3 facePoint) =>
      const [];
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m256_');
  app.partKernel = FakeKernel();
  return app;
}

FakeKernel kernelOf(AppState app) => app.partKernel as FakeKernel;

void addRectLines(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// Solid1: a 20x10 rectangle on XY, extruded 8. The panel is closed after.
///
/// The fake's prism weighs its own HEIGHT, so the body weighs 8 and the tool
/// below weighs 5 — deliberately bigger than the tool, so that a cut leaves
/// something behind and the numbers under test are never a body cut to zero.
Future<AppState> buildBase() async {
  final app = makeApp();
  await app.createNamedPart('Part1');
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: '8 mm');
  await app.applyExtrude();
  return app;
}

/// A second, smaller profile on XY with the extrude panel open on it — the
/// state the user is in when they turn an extrusion around.
Future<AppState> armSecondProfile() async {
  final app = await buildBase();
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 4, 2, 12, 8, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  return app;
}

void main() {
  group('M256 — the policy, on its own', () {
    test('a tool in free air leaves Join alone', () {
      expect(suggestedOutput('join', 0), isNull);
      expect(suggestedOutput('join', 0.2), isNull);
    });

    test('a tool mostly buried asks for Cut', () {
      expect(suggestedOutput('join', 0.6), 'cut');
      expect(suggestedOutput('join', 1.0), 'cut');
    });

    test('and mostly-buried means MOSTLY — half is not an answer', () {
      // The dead band. A single 0.5 threshold would flip the control back and
      // forth while a distance is dragged through it.
      expect(suggestedOutput('join', 0.5), isNull);
      expect(suggestedOutput('cut', 0.5), isNull);
      expect(suggestedOutput('join', 0.59), isNull);
      expect(suggestedOutput('cut', 0.41), isNull);
    });

    test('a Cut that has come back out asks for Join again', () {
      expect(suggestedOutput('cut', 0.4), 'join');
      expect(suggestedOutput('cut', 0), 'join');
    });

    test('a Cut still buried stays a Cut', () {
      expect(suggestedOutput('cut', 1.0), isNull);
      expect(suggestedOutput('cut', 0.6), isNull);
    });

    test('Intersect and New Solid are never suggested and never overruled', () {
      for (final f in [0.0, 0.5, 1.0]) {
        expect(suggestedOutput('intersect', f), isNull);
        expect(suggestedOutput('new', f), isNull);
      }
      // ...and nothing ever suggests them either.
      for (final cur in ['join', 'cut']) {
        for (final f in [0.0, 0.3, 0.5, 0.7, 1.0]) {
          expect(suggestedOutput(cur, f), isNot('intersect'));
          expect(suggestedOutput(cur, f), isNot('new'));
        }
      }
    });

    test('a fraction that is not a number decides nothing', () {
      expect(suggestedOutput('join', double.nan), isNull);
      expect(suggestedOutput('cut', double.infinity), isNull);
    });
  });

  group('M256 — the session follows it', () {
    test('a second body still opens on Join', () async {
      // "es soll immer zuerst hinzufügen ausgewählt sein."
      final app = await armSecondProfile();
      expect(app.extrudeSession!.output, 'join');
    });

    test('extruding away from the body stays Join', () async {
      final app = await armSecondProfile();
      kernelOf(app).inside = 0; // free air
      app.setExtrude(exprA: '6 mm');
      expect(app.extrudeSession!.output, 'join');
    });

    test('turning it around into the body switches to Cut', () async {
      final app = await armSecondProfile();
      kernelOf(app).inside = 1; // the reported case: wholly buried
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(app.extrudeSession!.output, 'cut',
          reason: 'the whole point: three taps for one intention became one');
    });

    test('and the PREVIEW is the cut, not the join it was asked for', () async {
      final app = await armSecondProfile();
      final k = kernelOf(app);
      k.inside = 1;
      k.cuts = 0;
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(k.cuts, greaterThan(0),
          reason: 'the picture has to be the answer, not the question');
      expect(app.extrudeSession!.preview, isNotNull);
      expect(app.extrudeSession!.previewError, isNull);
    });

    test('coming back out of the body returns to Join', () async {
      final app = await armSecondProfile();
      final k = kernelOf(app);
      k.inside = 1;
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(app.extrudeSession!.output, 'cut');
      k.inside = 0;
      app.setExtrude(direction: ExtrudeDirection.defaultDir);
      expect(app.extrudeSession!.output, 'join');
    });

    test('one change switches ONCE — it cannot sit there flipping', () async {
      // A kernel whose two booleans disagree about the same pair is exactly
      // what every other fake in this suite is. The guard is what stops the
      // rebuild from suggesting again, so this must terminate and settle.
      final app = await armSecondProfile();
      final k = kernelOf(app);
      k.inside = 1;
      app.setExtrude(direction: ExtrudeDirection.flipped);
      final settled = app.extrudeSession!.output;
      expect(settled, 'cut');
      app.setExtrude(exprA: '3 mm');
      expect(app.extrudeSession!.output, settled);
    });
  });

  group('M256 — but the user always wins', () {
    test('choosing Join by hand stops the suggestion for good', () async {
      // "ich will es immer noch umschalten können."
      final app = await armSecondProfile();
      final k = kernelOf(app);
      k.inside = 1;
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(app.extrudeSession!.output, 'cut');
      app.setExtrude(output: 'join'); // the user taps Join
      expect(app.extrudeSession!.output, 'join');
      app.setExtrude(exprA: '7 mm'); // and it stays Join through more changes
      expect(app.extrudeSession!.output, 'join');
      app.setExtrude(direction: ExtrudeDirection.defaultDir);
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(app.extrudeSession!.output, 'join');
    });

    test('tapping the boolean already in force locks it too', () async {
      // Tapping Join on a feature the suggestion has NOT yet moved is the same
      // statement of intent, made a moment earlier.
      final app = await armSecondProfile();
      final k = kernelOf(app);
      expect(app.extrudeSession!.output, 'join');
      app.setExtrude(output: 'join');
      k.inside = 1;
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(app.extrudeSession!.output, 'join');
    });

    test('Intersect chosen by hand is never argued with', () async {
      final app = await armSecondProfile();
      final k = kernelOf(app);
      app.setExtrude(output: 'intersect');
      k.inside = 1;
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(app.extrudeSession!.output, 'intersect');
    });
  });

  group('M256 — editing an existing feature', () {
    test('opens on the feature\'s own Output, and keeps it', () async {
      final app = await armSecondProfile();
      final k = kernelOf(app);
      k.inside = 1;
      app.setExtrude(direction: ExtrudeDirection.flipped);
      expect(app.extrudeSession!.output, 'cut');
      await app.applyExtrude();

      final made = app.currentPart!.features.last as ExtrudeFeature;
      expect(made.output, 'cut');

      // Re-open it. Before M256 the session kept its constructed default and
      // the panel read "Join" — and OK wrote that back over the cut.
      k.inside = 0; // and now the geometry would argue for Join
      app.openExtrude(made);
      expect(app.extrudeSession!.output, 'cut',
          reason: "an existing feature's Output is a decision already made");
      expect(app.extrudeSession!.outputIsTheirs, isTrue);
    });

    test('and on its own Extents', () async {
      // Built directly rather than through the panel: Through All cannot be
      // BUILT against a fake kernel — it measures the body's own B-Rep box and
      // bodySpanAlong says so honestly when there is none — and what is under
      // test here is the OPENER, not the extent.
      final app = await armSecondProfile();
      final p = app.currentPart!;
      final f = ExtrudeFeature(
        name: 'Extrusion9',
        bodyName: 'Solid1',
        sketchName: p.childSketches.last.model.name,
        profiles: [ProfileSel(6, 4, 48)],
        output: 'cut',
        extent: FeatureExtent.throughAll,
      );
      p.appendFeature(f);
      app.openExtrude(f);
      expect(app.extrudeSession!.extent, FeatureExtent.throughAll,
          reason: 'it reopened as Distance, and OK wrote Distance back over '
              'the Through All the user had chosen');
      expect(app.extrudeSession!.output, 'cut');
    });
  });
}
