// The paths that need a live AppState or a real PartModel.
//
// WHAT IS HERE AND WHY IT COULD NOT GO ANYWHERE ELSE
// --------------------------------------------------
//   * PATTERNS — a pattern is a session on AppState, not a pure function.
//   * PROJECTION — projecting model edges into a sketch needs a part with
//     solids in it.
//   * THE SCENE PAYLOAD — everything Dart hands RealityKit. This is the last
//     thing visible from this side of the platform-view boundary, so if it is
//     expensive nothing downstream can tell you.
//   * UNDO/REDO — journal snapshots deep-copy the whole sketch.
//   * THE DOCUMENT CODEC — what a save and an open actually spend their time
//     on once the disk is taken out of the picture.
//
// THE DISK IS DELIBERATELY OUT OF THE PICTURE
// -------------------------------------------
// savePart/openPart are async and their wall time is dominated by iOS file
// I/O, which varies with storage pressure and tells you nothing you can fix.
// What IS fixable is the serialisation either side of it, and that is
// synchronous and measured here. A number that moves for reasons outside the
// code is worse than no number: it produces "regressions" nobody caused.
//
// FIXTURES ARE MEMOISED, for the same reason as in perf_scenarios_ui: building
// a part with real meshes is itself expensive, and charging that to the
// scenario that uses it would report the fixture instead of the subject.
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Offset;

import 'app_state.dart';
import 'constraints.dart';
import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart';
import 'part_model.dart';
import 'part_pick.dart';
import 'perf.dart';
import 'perf_scenarios.dart'
    show PerfScenario, sketchFixture, constraintFixture, ringProfile;
import 'reality_scene.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

AppState? _buildApp(int n, {List<Constraint>? cons}) {
  try {
    final app = AppState();
    final s = SketchModel('perf');
    app.sketches['perf'] = s;
    app.curTab = 'perf';
    app.editingLayer = kDefaultLayer;
    s.geometry
      ..clear()
      ..addAll(sketchFixture(n));
    s.constraints
      ..clear()
      ..addAll(cons ?? constraintFixture(n));
    s.resetHistory();
    return app;
  } catch (_) {
    return null;
  }
}

final Map<int, AppState?> _apps = {};
AppState? _app(int n) => _apps.putIfAbsent(n, () => _buildApp(n));

/// A part carrying [features] real extruded solids, each with a real mesh.
///
/// Real meshes matter: every scenario below walks triangles or edges, and a
/// stub mesh with one triangle would make all of them look free. The feature
/// objects are built directly and their `solid` assigned rather than driven
/// through `recomputeFeature`, because the subject here is what happens
/// DOWNSTREAM of a rebuild — projection, scene payload, signatures — and going
/// through the recompute would fold the kernel time into every reading.
PartModel? _buildPart(int features, int profilePts) {
  try {
    final occt = OcctFfi.instance();
    if (occt == null) return null;
    final p = PartModel('perfPart');
    for (var i = 0; i < features; i++) {
      final shape =
          occt.extrudeProfileArcs([ringProfile(profilePts, 30 + i * 8.0)], 10.0);
      if (shape == null) continue;
      final mesh = shape.mesh(linDeflection: 0.2);
      if (mesh == null) {
        shape.dispose();
        continue;
      }
      final f = ExtrudeFeature(
        name: 'Extrusion${i + 1}',
        bodyName: 'Solid1',
        sketchName: 'perf',
        profiles: const [],
        distanceA: 10,
      );
      f.solid = KernelSolid(mesh, 1000.0, shape);
      f.seq = i;
      p.features.add(f);
    }
    return p.features.isEmpty ? null : p;
  } catch (_) {
    return null;
  }
}

final Map<String, PartModel?> _parts = {};
PartModel? _part(int features, int profilePts) => _parts.putIfAbsent(
    '$features/$profilePts', () => _buildPart(features, profilePts));

/// Drops the memoised fixtures. Tests that want a cold build call this.
void resetAppFixturesForTest() {
  _apps.clear();
  _parts.clear();
}

/// A part that can genuinely be REBUILT: real child sketches with closed
/// profiles, real extrude features pointing at them, and the real OCCT kernel.
///
/// Distinct from [_buildPart], which assigns solids directly. That one is right
/// for the scenarios measuring what happens downstream of a rebuild — driving
/// the recompute there would fold kernel time into every projection reading.
/// This one is for measuring the recompute ITSELF, so nothing may be
/// short-circuited: the features have to resolve their sketches, arrange their
/// profiles and fold onto the accumulating body exactly as they do in the app.
///
/// Not memoised: a rebuild MUTATES the part (solids, build signatures, face
/// anchors), so handing the same instance to a second scenario would measure a
/// part in whatever state the first one left it.
(PartModel, PartKernel)? _buildRebuildablePart(int features) {
  try {
    if (!OcctFfi.available) return null;
    final p = PartModel('perfRebuild');
    for (var i = 0; i < features; i++) {
      // A closed circular profile per feature, at increasing radius so the
      // solids really intersect and the boolean fold has work to do. A
      // disjoint stack would measure a fold that never touches anything.
      final m = SketchModel('perfSketch$i');
      m.geometry.add(Geo(Geo.circle, [0, 0, 30 + i * 8.0]));
      p.childSketches.add(ChildSketch(m, 'xy'));
      p.features.add(ExtrudeFeature(
        name: 'Extrusion${i + 1}',
        bodyName: 'Solid1',
        sketchName: m.name,
        // The centroid of the profile: how the app records which region of a
        // sketch a feature consumes. An empty list means "no profile chosen"
        // and the feature would decline to build.
        profiles: [ProfileSel(0, 0, 1)],
        distanceA: 10.0 + i * 2,
        output: 'join',
      )..seq = i);
    }
    return (p, OcctPartKernel());
  } catch (_) {
    return null;
  }
}

/// Total triangles across a part's solids — the axis every scene scenario is
/// really swept against.
int _tris(PartModel p) {
  var t = 0;
  for (final f in p.features) {
    final s = f.solid;
    if (s != null) t += s.mesh.triangleCount;
  }
  return t;
}

// ---------------------------------------------------------------------------
// The suite
// ---------------------------------------------------------------------------

List<PerfScenario> buildAppScenarios() {
  final out = <PerfScenario>[];

  // ---- patterns ----------------------------------------------------------
  //
  // patternPreview runs on EVERY frame while the dialog is open — it rebuilds
  // every copy from the source geometry each time — so its cost is a frame
  // cost, not a one-off. Swept against copy count, which is the number in the
  // dialog the user types.
  for (final count in const [4, 16, 64]) {
    out.add(PerfScenario(
      'app.pattern.rect.$count',
      () {
        final app = _app(24);
        if (app == null) return;
        final s = app.current;
        if (s == null) return;
        final ps = PatternSession(Tool.patRect)
          ..geo.addAll([0, 1, 2, 24, 25])
          ..dir1Ent = 24
          ..count1 = count
          ..count2 = 1
          ..spacing1 = 12;
        app.pattern = ps;
        try {
          Perf.gauge('app.patternCount', count);
          var made = 0;
          for (var i = 0; i < 20; i++) {
            made = Perf.span('app.patternPreview', () => app.patternPreview())
                .length;
          }
          Perf.gauge('app.patternCopies', made);
        } finally {
          app.pattern = null;
        }
      },
      note: 'rectangular pattern preview, 20 frames, vs copy count. This runs '
          'per frame while the dialog is open, so divide by 20 for the '
          'per-frame cost — and note patternPreview caps itself at 600 copies',
    ));
  }

  out.add(PerfScenario(
    'app.pattern.circular',
    () {
      final app = _app(24);
      if (app == null) return;
      final ps = PatternSession(Tool.patCirc)
        ..geo.addAll([0, 1, 2])
        ..axisPt = const PRef(kProjCenter, 0)
        ..countC = 24
        ..angleC = 360;
      app.pattern = ps;
      try {
        for (var i = 0; i < 20; i++) {
          Perf.span('app.patternPreview', () => app.patternPreview());
        }
      } finally {
        app.pattern = null;
      }
    },
    note: 'circular pattern, 24 copies — compare against app.pattern.rect.16 '
        'for whether the rotation transform costs more than the translation',
  ));

  out.add(PerfScenario(
    'app.pattern.mirror',
    () {
      final app = _app(24);
      if (app == null) return;
      final ps = PatternSession(Tool.mirror)
        ..geo.addAll([0, 1, 2, 3, 24, 25])
        ..mirrorEnt = 30;
      app.pattern = ps;
      try {
        for (var i = 0; i < 20; i++) {
          Perf.span('app.patternPreview', () => app.patternPreview());
        }
      } finally {
        app.pattern = null;
      }
    },
    note: 'mirror preview — one copy per picked entity, so this is the floor '
        'of the pattern machinery with the copy count taken out',
  ));

  // ---- undo / redo -------------------------------------------------------
  //
  // A checkpoint deep-copies the geometry and serialises constraints, texts,
  // images and parameters. It is taken at the single mutation choke point,
  // i.e. after EVERY edit, so its cost is added to every operation the user
  // performs.
  for (final n in const [8, 24, 64]) {
    out.add(PerfScenario(
      'app.history.$n',
      () {
        final app = _buildApp(n);
        if (app == null) return;
        final s = app.current;
        if (s == null) return;
        Perf.gauge('app.history.entities', s.geometry.length);
        for (var i = 0; i < 20; i++) {
          // Vary the geometry so consecutive snapshots are not collapsed as
          // identical — a checkpoint that dedups measures the comparison, not
          // the snapshot.
          final d = List<double>.from(s.geometry[0].data);
          d[0] += 0.1;
          s.geometry[0] = s.geometry[0].withData(d);
          Perf.span('app.checkpoint', s.checkpoint);
        }
        for (var i = 0; i < 20; i++) {
          Perf.span('app.undoStep', s.undoStep);
        }
        for (var i = 0; i < 20; i++) {
          Perf.span('app.redoStep', s.redoStep);
        }
      },
      note: 'undo journal vs sketch size: 20 checkpoints, 20 undos, 20 redos. '
          'The checkpoint is the one that matters — it is paid after every '
          'single edit, not only when the user presses undo',
    ));
  }

  // ---- the scene payload -------------------------------------------------
  //
  // Everything Dart hands the native renderer. Beyond this boundary nothing is
  // measurable from here, so if the handover is expensive it would otherwise
  // look like "RealityKit is slow".
  for (final (f, pts) in const [(1, 24), (3, 48), (6, 120)]) {
    out.add(PerfScenario(
      'app.scene.${f}x$pts',
      () {
        final app = _app(24);
        final p = _part(f, pts);
        if (app == null || p == null) return;
        Perf.gauge('app.scene.tris', _tris(p));
        Perf.gauge('app.scene.features', p.features.length);
        for (var i = 0; i < 10; i++) {
          Perf.span('app.buildScenePayload', () => buildScenePayload(app, p));
          Perf.span(
              'app.buildOverlaysPayload', () => buildOverlaysPayload(app, p));
        }
        for (var i = 0; i < 60; i++) {
          // The signature is computed on every frame to decide whether a push
          // is needed at all, so it is the one that has to be cheap.
          Perf.span('app.sceneSignature', () => sceneSignature(app, p));
        }
      },
      note: 'the Dart->RealityKit handover vs triangle count. buildScenePayload '
          'is paid per push; sceneSignature is paid per FRAME to decide whether '
          'to push, so it must be far cheaper — if it is not, the push-avoidance '
          'is costing more than the pushes',
    ));
  }

  out.add(PerfScenario(
    'app.sceneRevs',
    () {
      final app = _app(24);
      final p = _part(3, 48);
      if (app == null || p == null) return;
      for (var i = 0; i < 60; i++) {
        Perf.span('app.sceneRevs', () => sceneRevs(app, p));
      }
    },
    note: 'the per-solid revision map, also a per-frame check',
  ));

  // ---- projection --------------------------------------------------------
  //
  // Model edges projected into a sketch. app_state notes that the hover
  // highlight runs this on every pointer move, which makes it a per-frame cost
  // on a path nobody had measured.
  for (final (f, pts) in const [(1, 24), (3, 48), (6, 120)]) {
    out.add(PerfScenario(
      'app.projectEdges.${f}x$pts',
      () {
        final p = _part(f, pts);
        if (p == null) return;
        const fr = PlaneFrame('xy', Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1));
        Perf.gauge('app.project.tris', _tris(p));
        var edges = 0;
        for (var i = 0; i < 10; i++) {
          edges = Perf.span('app.partEdges', () => partEdges(p, fr)).length;
        }
        Perf.gauge('app.project.edges', edges);
      },
      note: 'projecting model edges onto a sketch plane vs part complexity. '
          'The hover highlight re-queries this per pointer move, so divide by '
          '10 and compare against a 8 ms frame budget',
    ));
  }

  // ---- the whole-part rebuild, end to end --------------------------------
  //
  // THE number a user waits for after editing a parameter, and the last named
  // gap from the M213 write-up. Everything else in this file measures a piece
  // of the aftermath (projection, the scene handover, signatures); this drives
  // `recomputeAllFeatures` itself, which is the orchestration ON TOP of the
  // kernel calls: profile arrangement, build-signature hashing, the boolean
  // fold onto the accumulating body, mesh copy-out, and the extra pass a moved
  // face-anchored sketch forces.
  //
  // Kernel time is inside these numbers by construction — that is the point.
  // `kernel.feature.<kind>` and `ffi.occt.*` in the same report separate the
  // two, and `part.rebuild.passes` says whether the loop ran more than once.
  for (final n in const [1, 3, 6]) {
    out.add(PerfScenario(
      'app.rebuildPart.$n',
      () {
        final built = _buildRebuildablePart(n);
        if (built == null) return;
        final (part, kernel) = built;
        Perf.gauge('app.rebuild.features', part.features.length);
        // FORCED. Every feature carries a build signature and an unchanged one
        // is skipped — which is correct behaviour and the exact opposite of
        // what this scenario needs to measure. Without `force` the second and
        // later iterations would report the cost of comparing hashes.
        for (var i = 0; i < 3; i++) {
          recomputeAllFeatures(part, kernel, force: true);
        }
      },
      note: 'the whole-part rebuild vs feature count — what you wait for after '
          'a parameter edit. Compare part.rebuildAll against the sum of '
          'kernel.feature.* to price the Dart-side orchestration, and check '
          'part.rebuild.passes: more than one pass per rebuild means a '
          'face-anchored sketch moved and everything was built twice',
    ));
  }

  // ---- 3D picking --------------------------------------------------------
  //
  // The 2D side has `2d.pickEntity`; this is its 3D twin, and it had no
  // measurement at all. It walks every edge polyline of every mesh and
  // projects it to screen space, per pointer event.
  for (final (f, pts) in const [(1, 24), (3, 48), (6, 120)]) {
    out.add(PerfScenario(
      'app.pickEdge3d.${f}x$pts',
      () {
        final p = _part(f, pts);
        if (p == null) return;
        final meshes = [
          for (final feat in p.features)
            if (feat.solid != null) feat.solid!.mesh
        ];
        if (meshes.isEmpty) return;
        var edges = 0;
        for (final m in meshes) {
          edges += m.edgeCount;
        }
        Perf.gauge('app.pick3d.edges', edges);
        // A trivial isometric-ish projection: the subject is the WALK over
        // every edge of every mesh, not the camera maths, and a real camera
        // would make the number depend on where it happened to be pointing.
        Offset project(Vec3 v) =>
            Offset(v.x - v.z * 0.5, v.y - v.z * 0.35);
        double depth(Vec3 v) => v.z;
        for (var i = 0; i < 30; i++) {
          final t = i / 30.0;
          Perf.span(
              'app.pickEdge3d',
              () => pickEdge(meshes, project, depth,
                  Offset(-40 + t * 80, -20 + t * 40)));
        }
      },
      note: 'the 3D edge pick, 30 events, vs total edge count. Runs per '
          'pointer move while an edge-selection tool is active — which is '
          'exactly the state the app was in when it died during a fillet',
    ));
  }

  // ---- mesh diagnostics --------------------------------------------------
  //
  // Off by default because it costs ~50 ms on a large mesh — a claim that had
  // never been checked against a measurement.
  out.add(PerfScenario(
    'app.meshDiagnostics',
    () {
      final p = _part(3, 48);
      if (p == null) return;
      final was = meshDiagnostics;
      meshDiagnostics = true;
      try {
        for (final f in p.features) {
          final s = f.solid;
          if (s == null) continue;
          Perf.span('app.meshSelfReport', () => meshSelfReport(f.name, s.mesh));
          Perf.span('app.meshAnomalies', () => meshAnomalies(s.mesh));
        }
      } finally {
        meshDiagnostics = was;
      }
    },
    note: 'the watertightness pass the bug button turns on. It is documented '
        'as ~50 ms on a large mesh; this is the first time that number has '
        'been measured rather than asserted',
  ));

  // ---- the document codec ------------------------------------------------
  out.add(PerfScenario(
    'app.partCodec',
    () {
      final p = _part(6, 120);
      if (p == null) return;
      for (var i = 0; i < 20; i++) {
        Perf.span('app.part.toJson', () => p.toJson());
      }
    },
    note: 'serialising the part document (no disk). Save and open pay this on '
        'top of file I/O, and unlike the I/O it is fixable',
  ));

  out.add(PerfScenario(
    'app.sketchCodec',
    () {
      final gs = sketchFixture(64);
      final cs = constraintFixture(64);
      Perf.gauge('app.codec.entities', gs.length);
      var enc = '';
      for (var i = 0; i < 20; i++) {
        enc = Perf.span('app.sketch.encodeCons', () => encodeConstraints(cs));
      }
      for (var i = 0; i < 20; i++) {
        Perf.span('app.sketch.decodeCons', () => decodeConstraints(enc));
      }
    },
    note: 'the constraint sidecar codec at 128 entities — every sketch save '
        'and every sketch open',
  ));

  // ---- the qcad engine ---------------------------------------------------
  //
  // The C-API is add-only, so any grip edit rebuilds the whole document. That
  // makes "add N entities" a per-edit cost, not a per-load one.
  for (final n in const [24, 128]) {
    out.add(PerfScenario(
      'app.engineFill.$n',
      () {
        final app = _buildApp(n ~/ 2);
        if (app == null) return;
        final s = app.current;
        if (s == null) return;
        Perf.gauge('app.engineEntities', s.geometry.length);
        for (var i = 0; i < 5; i++) {
          Perf.span('app.engineFill', () {
            final e = Engine.create();
            for (final g in s.geometry) {
              switch (g.type) {
                case Geo.line:
                  e.addLine(g.data[0], g.data[1], g.data[2], g.data[3]);
                  break;
                case Geo.circle:
                  e.addCircle(g.data[0], g.data[1], g.data[2]);
                  break;
                case Geo.arc:
                  e.addArc(g.data[0], g.data[1], g.data[2], g.data[3],
                      g.data[4]);
                  break;
              }
            }
            e.allGeometry();
          });
        }
      },
      note: 'rebuilding the qcad document from scratch — what every grip edit '
          'costs, because the C-API cannot mutate in place. Compare the two '
          'sizes: if this is superlinear, editing a big sketch degrades',
    ));
  }

  // ---- hit testing -------------------------------------------------------
  out.add(PerfScenario(
    'app.pick.sweep',
    () {
      final app = _app(64);
      if (app == null) return;
      for (var i = 0; i < 120; i++) {
        final a = 2 * math.pi * i / 120;
        app.setHover(Offset(62 * math.cos(a), 62 * math.sin(a)));
      }
    },
    note: '120 hover picks on a 128-entity sketch — the pointer-move cost at '
        'the size where it starts to matter. 2d.pickEntity carries it',
  ));

  return out;
}
