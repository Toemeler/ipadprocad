// M60 — the PartModel → RealityKit payload mapping (lib/reality_scene.dart).
//
// This is the host-testable half of the RealityKit move: the pure functions
// that build the maps the native side receives. The RealityKit RENDER itself
// is device-only (no Metal/Xcode here, exactly like every prior 3D milestone),
// but the wire payload — camera doubles, which solids are sent, that the heavy
// mesh buffers are referenced not copied, plane/axis/sketch geometry, the
// scene signature that gates re-uploads, and hover-face resolution — is all
// verified here.
import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/solver.dart' show solveConstraints;

import 'synth_mesh.dart';

KernelSolid _cyl({double r = 10, double h = 5}) =>
    KernelSolid(synthCylinderMesh(r, h, 0.5), 3.14 * r * r * h, null);

ExtrudeFeature _feat(String name, KernelSolid? solid,
    {bool visible = true, bool consumed = false, String body = 'Solid1'}) {
  final f = ExtrudeFeature(
      name: name,
      bodyName: body,
      sketchName: 'S1',
      profiles: const [],
      visible: visible);
  f.solid = solid;
  f.consumedByJoin = consumed;
  return f;
}

PartModel _partWith(List<ExtrudeFeature> features) {
  final p = PartModel('P');
  p.features.addAll(features);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cameraPayload', () {
    test('carries the five ortho doubles + viewport size', () {
      final c = PartCamera(az: 0.5, pol: 1.1, halfH: 42, ox: 3, oy: -4);
      final m = cameraPayload(c, const Size(800, 600));
      expect(m['az'], 0.5);
      expect(m['pol'], 1.1);
      expect(m['halfH'], 42);
      expect(m['ox'], 3);
      expect(m['oy'], -4);
      expect(m['w'], 800);
      expect(m['h'], 600);
    });
  });

  group('visibleSolids', () {
    test('drops invisible, consumed and the edited feature', () {
      final vis = _cyl();
      final invis = _cyl();
      final consumed = _cyl();
      final editing = _cyl();
      final p = _partWith([
        _feat('Extrusion1', vis),
        _feat('Extrusion2', invis, visible: false),
        _feat('Extrusion3', consumed, consumed: true),
        _feat('Extrusion4', editing),
        _feat('Extrusion5', null), // failed compute (no solid)
      ]);
      final app = AppState();
      app.extrudeSession = ExtrudeSession()..editing = p.features[3];

      final got = visibleSolids(app, p);
      expect(got.map((e) => e.$1).toList(), ['Extrusion1']);
      expect(identical(got.single.$2, vis), isTrue);
    });
  });

  group('solidPayload', () {
    test('references the mesh buffers without copying', () {
      final s = _cyl();
      final m = solidPayload('Extrusion1', s);
      expect(m['id'], 'Extrusion1');
      expect(m['material'], kMatSteel);
      // Same object identity — no defensive copy of megabytes of geometry.
      // M74: the vertex buffers travel as Float32 (half the bytes, and no
      // per-vertex conversion in Swift). They are still not re-copied per
      // push — the Float32 view is built once per mesh and reused.
      expect(identical(m['positions'], s.mesh.positions32), isTrue);
      expect(identical(m['normals'], s.mesh.normals32), isTrue);
      expect(identical(m['indices'], s.mesh.indices), isTrue);
      expect(identical(m['edgePts'], s.mesh.edgePoints32), isTrue);
      expect(identical(m['edgeStarts'], s.mesh.edgeStarts), isTrue);
      expect(identical(m['triFaces'], s.mesh.triFaces), isTrue);
      expect(m['positions'], isA<Float32List>());
      expect(m['indices'], isA<Int32List>());
    });

    test('an unchanged solid travels as a stub, a changed one in full', () {
      final s = _cyl();
      final p = _partWith([_feat('Extrusion1', s)]);
      final app = AppState();
      final revs = sceneRevs(app, p);
      expect(revs['Extrusion1'], identityHashCode(s.mesh));

      // nothing changed -> geometry omitted, identity still carried
      final stub =
          (buildScenePayload(app, p, knownRevs: revs)['solids'] as List).single
              as Map;
      expect(stub['id'], 'Extrusion1');
      expect(stub['rev'], identityHashCode(s.mesh));
      expect(stub.containsKey('positions'), isFalse,
          reason: 'unchanged meshes must not be re-serialised');

      // re-tessellation flips the mesh identity -> full payload again
      s.mesh = synthCylinderMesh(10, 5, 0.1);
      final full =
          (buildScenePayload(app, p, knownRevs: revs)['solids'] as List).single
              as Map;
      expect(identical(full['positions'], s.mesh.positions32), isTrue);
      expect(full['rev'], identityHashCode(s.mesh));
    });

    test('without knownRevs every solid carries its geometry', () {
      final s = _cyl();
      final p = _partWith([_feat('Extrusion1', s)]);
      final m = (buildScenePayload(AppState(), p)['solids'] as List).single
          as Map;
      expect(identical(m['positions'], s.mesh.positions32), isTrue);
    });

    test('preview tag distinguishes the translucent live solid', () {
      final m = solidPayload('__preview__', _cyl(), material: kMatPreview);
      expect(m['material'], kMatPreview);
    });
  });

  group('buildScenePayload', () {
    test('emits solids, three planes (9-double frames), three axes, cp', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      final scene = buildScenePayload(AppState(), p);

      final solids = scene['solids'] as List;
      expect(solids.length, 1);

      final planes = scene['planes'] as List;
      expect(planes.length, 3);
      for (final pl in planes.cast<Map>()) {
        expect((pl['frame'] as Float64List).length, 9);
        // M83: a plane FRAMES the part, so its size is content-driven — it is
        // no longer the fixed 10 this used to assert. What travels is the
        // rectangle; `ext` remains only as the legacy fallback for a pre-M83
        // native build, and must be the largest of its four half-extents.
        final r = originPlaneRect(p, pl['key'] as String);
        expect(pl['uMin'], r.$1);
        expect(pl['uMax'], r.$2);
        expect(pl['vMin'], r.$3);
        expect(pl['vMax'], r.$4);
        final widest =
            [r.$1.abs(), r.$2.abs(), r.$3.abs(), r.$4.abs()].reduce(max);
        expect(pl['ext'], widest);
        expect(pl['ext'], isNot(kOriginExtentDefault),
            reason: 'a part with geometry must not keep the empty-part size');
      }
      // yz/xz/xy in order.
      expect(planes.map((e) => (e as Map)['key']).toList(), ['yz', 'xz', 'xy']);

      final axes = scene['axes'] as List;
      expect(axes.map((e) => (e as Map)['key']).toList(), ['x', 'y', 'z']);

      expect((scene['cp'] as Map)['visible'], isFalse);
      expect(scene.containsKey('preview'), isFalse);
      expect(scene.containsKey('highlight'), isFalse);
    });

    test('pickPlane shows the origin planes only while the part is empty', () {
      final app = AppState()..pickPlane = true;
      // empty part (first sketch): all three planes offered automatically
      final empty = _partWith([]);
      expect(
          (buildScenePayload(app, empty)['planes'] as List)
              .cast<Map>()
              .every((pl) => pl['visible'] == true),
          isTrue);
      // once geometry exists you sketch on faces — planes stay hidden unless
      // explicitly switched on in the browser
      final withSolid = _partWith([_feat('Extrusion1', _cyl())]);
      final planes =
          (buildScenePayload(app, withSolid)['planes'] as List).cast<Map>();
      expect(planes.every((pl) => pl['visible'] == false), isTrue);
      withSolid.vis['xy'] = true;
      final again =
          (buildScenePayload(app, withSolid)['planes'] as List).cast<Map>();
      expect(again.firstWhere((pl) => pl['key'] == 'xy')['visible'], isTrue);
      expect(again.firstWhere((pl) => pl['key'] == 'yz')['visible'], isFalse);
    });

    test('a child sketch becomes a world-space polyline on its plane', () {
      final sk = SketchModel('S1');
      sk.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      p.childSketches.add(ChildSketch(sk, 'xy'));

      final sketches = buildScenePayload(AppState(), p)['sketches'] as List;
      expect(sketches.length, 1);
      final polys = (sketches.first as Map)['polylines'] as List;
      expect(polys.length, 1);
      // the plane normal rides along so the renderer can lift a face sketch
      // clear of the coplanar face
      expect((sketches.first as Map)['n'], [0.0, 0.0, 1.0]);
      final buf = polys.first as Float32List;
      // Two endpoints, xyz each, lying on the XY plane (z == 0).
      expect(buf.length, 6);
      expect(buf[0], 0);
      expect(buf[1], 0);
      expect(buf[2], 0);
      expect(buf[3], 10);
      expect(buf[4], 0);
      expect(buf[5], 0);
    });

    test('a live preview rides along tagged translucent', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      final app = AppState();
      app.extrudeSession = ExtrudeSession()..preview = _cyl(r: 4, h: 8);
      final scene = buildScenePayload(app, p);
      expect((scene['preview'] as Map)['material'], kMatPreview);
    });

    test('a hovered planar face resolves to (solid id, face id)', () {
      final s = _cyl();
      final p = _partWith([_feat('Extrusion1', s)]);
      final scene = buildScenePayload(AppState(), p,
          hoverFace: (s, synthTopFace));
      final hl = scene['highlight'] as Map;
      expect(hl['solid'], 'Extrusion1');
      expect(hl['face'], synthTopFace);
    });
  });

  // M127 — accented edges travel as RAW WORLD POLYLINES, not as
  // "display edge N of solid X". The old shape broke under a fillet preview:
  // the previewed body is hidden, so the renderer had no geometry to hang the
  // ribbon on and the hover prehighlight vanished.
  group('edgeAccent', () {
    /// A solid whose mesh has three separate 2-point edges, so a display index
    /// maps to a known polyline.
    KernelSolid triEdged() => KernelSolid(
        OcctMeshData(
            Float64List(0),
            Float64List(0),
            Int32List(0),
            Int32List.fromList(const [0, 2, 4, 6]),
            Float64List.fromList(const [
              0, 0, 0, 1, 0, 0, // edge 0
              0, 1, 0, 1, 1, 0, // edge 1
              0, 2, 0, 1, 2, 0, // edge 2
            ])),
        1.0,
        null);

    test('absent entirely when nothing is picked or hovered', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      expect(buildScenePayload(AppState(), p).containsKey('edgeAccent'),
          isFalse);
    });

    test('a picked edge sends its own points, not an index', () {
      final s = triEdged();
      final p = _partWith([_feat('Extrusion1', s)]);
      final app = AppState()..beginPickEdges();
      app.toggleEdgePick(11, EdgeSel(0, 0, 0, 1, 1, 0), solid: s, display: 1);
      final ea = buildScenePayload(app, p)['edgeAccent'] as Map;
      final lines = (ea['lines'] as List).cast<List>();
      expect(lines.length, 1);
      expect(lines.first, [0, 1, 0, 1, 1, 0], reason: 'edge 1 verbatim');
      expect(lines.first, isA<Float32List>(),
          reason: 'the renderer reads these as 32-bit floats; sending float64 '
              'reinterprets the bytes and draws enormous lines nowhere near '
              'the part');
    });

    test('works even when the body is HIDDEN by a preview', () {
      // The exact device bug: a fillet preview replaces the body, so the old
      // per-solid accent had nothing to attach to.
      final s = triEdged();
      final p = _partWith([_feat('Extrusion1', s)]);
      final app = AppState()..beginPickEdges();
      app.toggleEdgePick(11, EdgeSel(0, 0, 0, 1, 1, 0), solid: s, display: 0);
      app.edgeSession = EdgeFeatureSession('fillet')
        ..previewReplacesBody = 'Solid1';
      final ea = buildScenePayload(app, p)['edgeAccent'] as Map;
      expect((ea['lines'] as List).length, 1,
          reason: 'the accent must survive its body being replaced');
    });

    test('hover and selection merge, without duplicating a shared edge', () {
      final s = triEdged();
      final p = _partWith([_feat('Extrusion1', s)]);
      final app = AppState()..beginPickEdges();
      app.toggleEdgePick(11, EdgeSel(0, 0, 0, 1, 1, 0), solid: s, display: 0);
      app.setHoverEdge3d(s, 2);
      var lines = ((buildScenePayload(app, p)['edgeAccent'] as Map)['lines']
              as List)
          .cast<List>();
      expect(lines.length, 2);
      // hovering the already-selected edge must not stack two ribbons
      app.setHoverEdge3d(s, 0);
      lines = ((buildScenePayload(app, p)['edgeAccent'] as Map)['lines']
              as List)
          .cast<List>();
      expect(lines.length, 1);
    });

    test('EVERY emitted line is Float32List, matching the wire format', () {
      // The bug this guards cost a device round trip: Float32List is what
      // Payload.floats binds to on the other side. A Float64List slice
      // compiles, serialises, and then renders as garbage.
      final s = triEdged();
      final p = _partWith([_feat('Extrusion1', s)]);
      final app = AppState()..beginPickEdges();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 1, 1, 0), solid: s, display: 0);
      app.toggleEdgePick(2, EdgeSel(0, 1, 0, 1, 1, 0), solid: s, display: 1);
      app.setHoverEdge3d(s, 2);
      final lines = ((buildScenePayload(app, p)['edgeAccent'] as Map)['lines']
              as List)
          .cast<Object>();
      expect(lines.length, 3);
      for (final l in lines) {
        expect(l, isA<Float32List>());
      }
    });

    test('an out-of-range display index is skipped, not crashed on', () {
      final s = triEdged();
      final p = _partWith([_feat('Extrusion1', s)]);
      final app = AppState()..beginPickEdges();
      app.toggleEdgePick(11, EdgeSel(0, 0, 0, 1, 1, 0), solid: s, display: 99);
      expect(buildScenePayload(app, p).containsKey('edgeAccent'), isFalse);
    });

    test('the LIGHT overlay path always carries the key, even when empty', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      final out = buildOverlaysPayload(AppState(), p);
      expect(out.containsKey('edgeAccent'), isTrue);
      expect(out['edgeAccent'], isEmpty);
    });
  });


  group('sceneSignature', () {
    test('changes when a solid re-tessellates (mesh identity flips)', () {
      final s = _cyl();
      final p = _partWith([_feat('Extrusion1', s)]);
      final app = AppState();
      final before = sceneSignature(app, p);
      // Simulate a refine: the same solid now holds a different mesh object.
      s.mesh = synthCylinderMesh(10, 5, 0.1);
      expect(sceneSignature(app, p), isNot(before));
    });

    test('changes when pickPlane toggles and when a plane becomes visible', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      final app = AppState();
      final base = sceneSignature(app, p);
      app.pickPlane = true;
      expect(sceneSignature(app, p), isNot(base));
      app.pickPlane = false;
      expect(sceneSignature(app, p), base);
      p.vis['xy'] = true;
      expect(sceneSignature(app, p), isNot(base));
    });

    test('is stable across calls when nothing changed', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      final app = AppState();
      expect(sceneSignature(app, p), sceneSignature(app, p));
    });
  });

  group('buildOverlaysPayload', () {
    test('sets hot for the hovered plane / axis and carries no meshes', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      final o = buildOverlaysPayload(AppState(), p, hover: 'xz');
      final planes = (o['planes'] as List).cast<Map>();
      expect(planes.firstWhere((m) => m['key'] == 'xz')['hot'], isTrue);
      expect(planes.firstWhere((m) => m['key'] == 'xy')['hot'], isFalse);
      // Overlays are light: no solid geometry in them.
      expect(o.containsKey('solids'), isFalse);

      final oa = buildOverlaysPayload(AppState(), p, hover: 'y');
      final axes = (oa['axes'] as List).cast<Map>();
      expect(axes.firstWhere((m) => m['key'] == 'y')['hot'], isTrue);
    });

    test('carries the centre-point hover state', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      p.vis['cp'] = true;
      final o = buildOverlaysPayload(AppState(), p, hover: 'cp');
      expect((o['cp'] as Map)['visible'], isTrue);
      expect((o['cp'] as Map)['hot'], isTrue);
      final off = buildOverlaysPayload(AppState(), p, hover: 'xy');
      expect((off['cp'] as Map)['hot'], isFalse);
    });
  });

  group('solver write-back', () {
    test('keeps a tagged polyline\'s gear parameter block', () {
      // A gear rides in a polyline as [closed, count, centre, handle] followed
      // by its parameter block. The slvs write-back rebuilt that list from
      // scratch and dropped the tail, so the tooth contour disappeared the
      // moment the sketch was solved — the preview looked right, the placed
      // gear did not.
      final s = SketchModel('t');
      final tail = [2.0, 20.0, 7.5, 0.0];
      s.geometry.add(Geo(
        Geo.polyline,
        [1.0, 2.0, 0.0, 0.0, 20.0, 0.0, ...tail],
        spline: Geo.gearTag,
      ));
      final gs = List<Geo>.from(s.geometry);
      solveConstraints(gs, s.constraints);
      expect(gs[0].data.length, 6 + tail.length,
          reason: 'the block after the points must survive a solve');
      expect(gs[0].data.sublist(6), tail);
      expect(gs[0].spline, Geo.gearTag);
    });
  });
}
