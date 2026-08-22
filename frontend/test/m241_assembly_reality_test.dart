// M241 — the assembly on RealityKit: the wire payload, and the rule that
// decides which of the two pushes carries what.
//
// The RENDER is device-only, as it has been for every 3D milestone — there is
// no Metal and no Swift compiler here. What CAN be pinned is everything the
// Swift side depends on being true, and this milestone added three contracts
// that a Dart change could break silently while every existing test stayed
// green:
//
//   1. THE PLACEMENT REACHES THE RENDERER, in the shape Payload.vec3 reads.
//      `at` must be a PLAIN List of three numbers. A Float64List would arrive
//      as FlutterStandardTypedData, `as? [Any]` would fail, and every
//      component would silently render at the origin — one solid where there
//      should be three.
//
//   2. A PART'S PAYLOAD IS UNCHANGED. `at` and `tint` are optional keys, and
//      a part sends neither. If they ever appear there, the part viewport is
//      taking a new code path in Swift for no reason.
//
//   3. THE TWO PUSHES CARRY DIFFERENT THINGS. A placement travels on the
//      LIGHT push and must NOT move the scene signature: if it did, dragging
//      a component would re-upload every mesh and rebuild every plane quad
//      sixty times a second. This is the whole performance claim of doing it
//      this way, and it is one string comparison away from being lost.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/reality_payload.dart';
import 'package:prototype/theme.dart';

import 'synth_mesh.dart';

KernelSolid _cyl({double r = 10, double h = 5}) =>
    KernelSolid(synthCylinderMesh(r, h, 0.5), 3.14 * r * r * h, null);

PartModel _partWith(String name, List<KernelSolid> solids) {
  final p = PartModel(name);
  for (var i = 0; i < solids.length; i++) {
    p.features.add(ExtrudeFeature(
      name: 'Extrusion${i + 1}',
      bodyName: 'Solid${i + 1}',
      sketchName: 'S1',
      profiles: const [],
    )..solid = solids[i]);
  }
  return p;
}

AssemblyOccurrence _occ(String id, Vec3 at, {int bodies = 1}) =>
    AssemblyOccurrence(
      id: id,
      source: id.split(':').first,
      part: _partWith(id.split(':').first,
          [for (var i = 0; i < bodies; i++) _cyl(r: 8.0 + i)]),
      offset: at,
    );

AssemblyModel _asm(List<AssemblyOccurrence> occs) {
  final a = AssemblyModel('Gearbox');
  a.occurrences.addAll(occs);
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the pieces an assembly draws', () {
    test('one id per occurrence per body, and they are unique', () {
      final a = _asm([
        _occ('Bracket:1', Vec3.zero, bodies: 2),
        _occ('Bracket:2', const Vec3(40, 0, 0), bodies: 2),
      ]);
      final ids = [for (final (id, _, _) in assemblyPieces(a)) id];
      expect(ids, [
        'Bracket:1/Extrusion1',
        'Bracket:1/Extrusion2',
        'Bracket:2/Extrusion1',
        'Bracket:2/Extrusion2',
      ]);
      expect(ids.toSet().length, ids.length,
          reason: 'the renderer keys its entity cache on these');
    });

    test('a hidden component, and one whose part is gone, draw nothing', () {
      final gone = AssemblyOccurrence(id: 'Ghost:1', source: 'Ghost');
      final hidden = _occ('Bracket:2', const Vec3(40, 0, 0))..visible = false;
      final a = _asm([_occ('Bracket:1', Vec3.zero), hidden, gone]);
      expect([for (final (id, _, _) in assemblyPieces(a)) id],
          ['Bracket:1/Extrusion1']);
      // ...and the occurrence itself is still there to be listed and removed.
      expect(a.occurrences, hasLength(3));
    });
  });

  group('solidPayload placement and tint', () {
    test('the placement is a PLAIN list of three numbers', () {
      // The contract with Payload.vec3 in PartScene.swift, which reads
      // `as? [Any]` of NSNumber. A typed list would arrive as
      // FlutterStandardTypedData and be dropped — every component at the
      // origin, with no error anywhere.
      final m = solidPayload('x', _cyl(), at: const Vec3(1, -2, 3.5));
      final at = m['at'];
      expect(at, isA<List<dynamic>>());
      expect(at, isNot(isA<TypedData>()));
      expect(at, [1.0, -2.0, 3.5]);
    });

    test('a part sends neither key', () {
      final m = solidPayload('Extrusion1', _cyl());
      expect(m.containsKey('at'), isFalse);
      expect(m.containsKey('tint'), isFalse);
      // ...and the rest of the payload is what it always was.
      expect(m['id'], 'Extrusion1');
      expect(m['material'], kMatSteel);
      expect(m['positions'], isA<Float32List>());
    });

    test('a component AT the origin sends no placement either', () {
      // Not an optimisation — the identity check is component-wise, because
      // Vec3 has no operator== and `at != Vec3.zero` would be an identity
      // comparison that a runtime-built zero fails.
      final m = solidPayload('x', _cyl(), at: Vec3(0, 0, 0));
      expect(m.containsKey('at'), isFalse);
    });

    test('a geometry-less payload still carries placement and tint', () {
      // This IS the drag path: the renderer keeps the mesh it holds and only
      // moves the holder. If the buffers came back the drag would be
      // re-uploading the part every frame.
      final m = solidPayload('x', _cyl(),
          includeGeometry: false, at: const Vec3(5, 0, 0), tint: 0xFF112233);
      expect(m.containsKey('positions'), isFalse);
      expect(m['at'], [5.0, 0.0, 0.0]);
      expect(m['tint'], 0xFF112233);
    });
  });

  group('the tint says which component is which', () {
    test('selected, hovered and plain are three different answers', () {
      final sel = _occ('Bracket:1', Vec3.zero);
      final hov = _occ('Bracket:2', const Vec3(40, 0, 0));
      final plain = _occ('Bracket:3', const Vec3(80, 0, 0));
      final a = _asm([sel, hov, plain])..selected = sel;

      final s = assemblyTint(a, sel, hoverId: hov.id);
      final h = assemblyTint(a, hov, hoverId: hov.id);
      final p = assemblyTint(a, plain, hoverId: hov.id);
      expect(p, kNoTint, reason: 'an untouched component is plain steel');
      expect(s, isNot(kNoTint));
      expect(h, isNot(kNoTint));
      expect(s, isNot(h), reason: 'selected must not look like hovered');
      expect(s, T.faceHighlight.toARGB32());
    });

    test('selection wins over hover on the same component', () {
      final o = _occ('Bracket:1', Vec3.zero);
      final a = _asm([o])..selected = o;
      expect(assemblyTint(a, o, hoverId: o.id), T.faceHighlight.toARGB32());
    });

    test('the tint follows the palette, not a frozen constant', () {
      // The Swift side has no palette — that is why the colour is pushed. If
      // this ever stops depending on T, a scheme switch would leave the
      // selection tone from the other one on screen.
      final o = _occ('Bracket:1', Vec3.zero);
      final a = _asm([o])..selected = o;
      final was = T.mode;
      T.set(AppThemeMode.light);
      final light = assemblyTint(a, o);
      T.set(AppThemeMode.dark);
      final dark = assemblyTint(a, o);
      T.set(was);
      expect(light, isNot(dark));
    });
  });

  group('the scene payload', () {
    test('every component travels with its own placement', () {
      final a = _asm([
        _occ('Bracket:1', Vec3.zero),
        _occ('Bracket:2', const Vec3(40, 1, -2)),
      ]);
      final solids =
          (buildAssemblyScenePayload(a)['solids'] as List).cast<Map>();
      expect(solids, hasLength(2));
      expect(solids[0].containsKey('at'), isFalse, reason: 'sits at 0,0,0');
      expect(solids[1]['at'], [40.0, 1.0, -2.0]);
      // The mesh itself is BY REFERENCE — two occurrences of one part must not
      // mean two copies of its vertex buffer in memory.
      expect(solids[0]['positions'], isA<Float32List>());
    });

    test('a known mesh travels as identity + placement only', () {
      final a = _asm([_occ('Bracket:1', const Vec3(3, 0, 0))]);
      final revs = assemblySceneRevs(a);
      final solids =
          (buildAssemblyScenePayload(a, knownRevs: revs)['solids'] as List)
              .cast<Map>();
      expect(solids, hasLength(1));
      expect(solids.single.containsKey('positions'), isFalse);
      expect(solids.single['at'], [3.0, 0.0, 0.0]);
    });

    test('two occurrences of ONE part are one upload each, keyed apart', () {
      final a = _asm([
        _occ('Bracket:1', Vec3.zero),
        _occ('Bracket:2', const Vec3(40, 0, 0)),
      ]);
      final revs = assemblySceneRevs(a);
      expect(revs.keys.toSet(),
          {'Bracket:1/Extrusion1', 'Bracket:2/Extrusion1'});
    });

    test('the origin planes and axes are sized to the assembly', () {
      final a = _asm([_occ('Bracket:1', const Vec3(50, 0, 0))]);
      a.vis['xy'] = true;
      final scene = buildAssemblyScenePayload(a);
      final planes = (scene['planes'] as List).cast<Map>();
      expect(planes.map((p) => p['key']).toList(), kPlaneKeys);
      final xy = planes.firstWhere((p) => p['key'] == 'xy');
      expect(xy['visible'], isTrue);
      expect(xy['frame'], isA<Float64List>());
      // The plane has to reach past the component it frames AND still contain
      // the origin, or the axes would leave the plane. Measured against the
      // content, not a magic number: the fixture's radius is not the point.
      final (lo, hi) = assemblyContentBounds(a)!;
      expect(xy['uMax'] as double, greaterThan(hi.x));
      expect(xy['uMin'] as double, lessThanOrEqualTo(0));
      expect(lo.x, greaterThan(0), reason: 'the fixture sits clear of origin');

      final axes = (scene['axes'] as List).cast<Map>();
      expect(axes.map((x) => x['key']).toList(), ['x', 'y', 'z']);
      expect((axes.first['hi'] as double), closeTo(xy['uMax'] as double, 1e-9));
      expect(axes.first['dir'], [1.0, 0.0, 0.0]);
    });

    test('sketches travel as an empty list, not as an absent key', () {
      // The renderer clears its sketch root FROM this key. Leaving it out
      // would strand whatever a previously open part left in the same view.
      final scene = buildAssemblyScenePayload(_asm([]));
      expect(scene['sketches'], isEmpty);
      expect(scene.containsKey('sketches'), isTrue);
    });
  });

  group('the overlays payload — the drag path', () {
    test('it carries every placement and tint, and no geometry at all', () {
      final sel = _occ('Bracket:2', const Vec3(40, 0, 0));
      final a = _asm([_occ('Bracket:1', Vec3.zero), sel])..selected = sel;
      final o = buildAssemblyOverlaysPayload(a);
      final places = (o['placements'] as List).cast<Map>();
      expect(places, hasLength(2));
      expect(places[0]['id'], 'Bracket:1/Extrusion1');
      expect(places[0]['at'], [0.0, 0.0, 0.0],
          reason: 'the light push is unconditional — no omitted zeroes');
      expect(places[1]['at'], [40.0, 0.0, 0.0]);
      expect(places[1]['tint'], T.faceHighlight.toARGB32());
      for (final p in places) {
        expect(p.containsKey('positions'), isFalse);
        expect(p.containsKey('indices'), isFalse);
      }
    });

    test('plane and axis visibility ride it too', () {
      final a = _asm([_occ('Bracket:1', Vec3.zero)]);
      a.vis['xz'] = true;
      a.vis['y'] = true;
      final o = buildAssemblyOverlaysPayload(a);
      final planes = (o['planes'] as List).cast<Map>();
      expect(planes.firstWhere((p) => p['key'] == 'xz')['visible'], isTrue);
      expect(planes.firstWhere((p) => p['key'] == 'xy')['visible'], isFalse);
      final axes = (o['axes'] as List).cast<Map>();
      expect(axes.firstWhere((x) => x['key'] == 'y')['visible'], isTrue);
      expect(axes.firstWhere((x) => x['key'] == 'x')['visible'], isFalse);
    });
  });

  group('the scene signature gates the HEAVY push', () {
    test('MOVING a component does not move it', () {
      // The claim this milestone rests on. If a placement ever enters the
      // signature, a drag re-uploads every mesh and rebuilds every plane quad
      // on every frame.
      final o = _occ('Bracket:1', Vec3.zero);
      final a = _asm([o]);
      final before = assemblySceneSignature(a);
      o.offset = const Vec3(37, -4, 12);
      expect(assemblySceneSignature(a), before);
    });

    test('SELECTING a component does not move it either', () {
      // Selection is a tint, and a tint rides the light push.
      final o = _occ('Bracket:1', Vec3.zero);
      final a = _asm([o]);
      final before = assemblySceneSignature(a);
      a.selected = o;
      expect(assemblySceneSignature(a), before);
    });

    test('placing, hiding, deleting and ENDING A DRAG do move it', () {
      final a = _asm([_occ('Bracket:1', Vec3.zero)]);
      var sig = assemblySceneSignature(a);

      a.occurrences.add(_occ('Bracket:2', const Vec3(40, 0, 0)));
      a.bump();
      expect(assemblySceneSignature(a), isNot(sig));
      sig = assemblySceneSignature(a);

      a.occurrences.last.visible = false;
      a.bump();
      expect(assemblySceneSignature(a), isNot(sig));
      sig = assemblySceneSignature(a);

      // A drag that has SETTLED: the origin planes are sized to the contents,
      // so they are stale until the generation ticks and brings them along.
      a.bump();
      expect(assemblySceneSignature(a), isNot(sig));
      sig = assemblySceneSignature(a);

      a.remove(a.occurrences.last);
      a.bump();
      expect(assemblySceneSignature(a), isNot(sig));
    });

    test('turning an origin plane on moves it', () {
      final a = _asm([_occ('Bracket:1', Vec3.zero)]);
      final before = assemblySceneSignature(a);
      a.vis['xy'] = true;
      expect(assemblySceneSignature(a), isNot(before));
    });
  });

  group('the gallery still', () {
    test('the placed thumb payload carries each component where it sits', () {
      final a = _asm([
        _occ('Bracket:1', Vec3.zero),
        _occ('Bracket:2', const Vec3(40, 0, 0)),
      ]);
      final pieces = [
        for (final (id, o, s) in assemblyPieces(a)) (id, s, o.offset)
      ];
      final scene = buildPlacedThumbScenePayload(pieces);
      final solids = (scene['solids'] as List).cast<Map>();
      expect(solids, hasLength(2));
      expect(solids[1]['at'], [40.0, 0.0, 0.0]);
      // Geometry-only: a card shows the MODEL, never the scaffolding.
      expect(scene.containsKey('planes'), isFalse);
      expect(scene.containsKey('axes'), isFalse);
    });
  });
}
