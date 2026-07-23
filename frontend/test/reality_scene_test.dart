// M60 — the PartModel → RealityKit payload mapping (lib/reality_scene.dart).
//
// This is the host-testable half of the RealityKit move: the pure functions
// that build the maps the native side receives. The RealityKit RENDER itself
// is device-only (no Metal/Xcode here, exactly like every prior 3D milestone),
// but the wire payload — camera doubles, which solids are sent, that the heavy
// mesh buffers are referenced not copied, plane/axis/sketch geometry, the
// scene signature that gates re-uploads, and hover-face resolution — is all
// verified here.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart' show Geo;
import 'package:ipadprocad/part_model.dart';
import 'package:ipadprocad/reality_scene.dart';

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
      expect(identical(m['positions'], s.mesh.positions), isTrue);
      expect(identical(m['normals'], s.mesh.normals), isTrue);
      expect(identical(m['indices'], s.mesh.indices), isTrue);
      expect(identical(m['edgePts'], s.mesh.edgePoints), isTrue);
      expect(identical(m['edgeStarts'], s.mesh.edgeStarts), isTrue);
      expect(identical(m['triFaces'], s.mesh.triFaces), isTrue);
      expect(m['positions'], isA<Float64List>());
      expect(m['indices'], isA<Int32List>());
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
        expect(pl['ext'], 10.0);
      }
      // yz/xz/xy in order.
      expect(planes.map((e) => (e as Map)['key']).toList(), ['yz', 'xz', 'xy']);

      final axes = scene['axes'] as List;
      expect(axes.map((e) => (e as Map)['key']).toList(), ['x', 'y', 'z']);

      expect((scene['cp'] as Map)['visible'], isFalse);
      expect(scene.containsKey('preview'), isFalse);
      expect(scene.containsKey('highlight'), isFalse);
    });

    test('pickPlane makes every origin plane visible', () {
      final p = _partWith([_feat('Extrusion1', _cyl())]);
      final app = AppState()..pickPlane = true;
      final planes =
          (buildScenePayload(app, p)['planes'] as List).cast<Map>();
      expect(planes.every((pl) => pl['visible'] == true), isTrue);
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
      final buf = polys.first as Float64List;
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
}
