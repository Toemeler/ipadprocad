// M246 — an assembly placed inside an assembly.
//
// "I also want to be able to place assembly's into assembly's."
//
// The design decision that makes this tractable is Inventor's own: a
// SUBASSEMBLY IS ONE RIGID BODY IN ITS PARENT. The parent's solver still sees
// one body per occurrence, the parent's constraints still act on it as a
// whole, and the parts inside it keep the arrangement their own document gave
// them. Everything else follows from one change to the geometry:
//
//   a component used to be "these solids, at this placement"
//   a component is now   "these solids, EACH at its own placement"
//
// which is true of a part too (every feature at the identity) and is the only
// shape that can also describe a subassembly. This suite is mostly about that
// composition being right in every consumer — the painter, the picker, the
// bounds walk, the RealityKit payload — because a transform composed the
// wrong way round still draws SOMETHING, just in the wrong place.
import 'dart:io';
import 'dart:ui' show Size;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_pick.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/widgets/native_browser.dart';
import 'package:prototype/widgets/viewport_assembly.dart';

/// A box with the v4 face metadata, so it can be picked as well as drawn.
KernelSolid facedBox({double h = 10}) {
  final c = [
    [-h, -h, -h], [h, -h, -h], [h, h, -h], [-h, h, -h],
    [-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h],
  ];
  const quads = [
    [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
    [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5],
  ];
  const normals = [
    [0.0, 0.0, -1.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0],
    [0.0, 1.0, 0.0], [-1.0, 0.0, 0.0], [1.0, 0.0, 0.0],
  ];
  final pos = <double>[], nor = <double>[], infos = <double>[];
  final idx = <int>[], triFaces = <int>[];
  for (var f = 0; f < quads.length; f++) {
    final base = pos.length ~/ 3;
    for (final vi in quads[f]) {
      pos.addAll(c[vi]);
      nor.addAll(normals[f]);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    triFaces.addAll([f, f]);
    final n = normals[f];
    final away = [n[1], n[2], n[0]];
    infos.addAll([0,
      n[0] * h + away[0] * 250, n[1] * h + away[1] * 250,
      n[2] * h + away[2] * 250,
      n[0], n[1], n[2], 0, 0, 0, 0, 0, 0, 0, 0]);
  }
  return KernelSolid(
    OcctMeshData(Float64List.fromList(pos), Float64List.fromList(nor),
        Int32List.fromList(idx), Int32List.fromList([0]), Float64List(0),
        triFaces: Int32List.fromList(triFaces),
        faceInfos: Float64List.fromList(infos)),
    8 * h * h * h, null);
}

PartModel boxPart(String name, {double h = 10}) {
  final p = PartModel(name);
  p.features.add(ExtrudeFeature(
    name: 'Extrusion1', bodyName: 'Solid1', sketchName: 'Sketch1',
    profiles: [ProfileSel(0, 0, 10)], direction: ExtrudeDirection.defaultDir,
    distanceA: 2 * h, distanceB: 0, extent: FeatureExtent.distance,
  )..solid = facedBox(h: h));
  return p;
}

AssemblyOccurrence part(String id, Vec3 at,
        {Quat rot = Quat.identity, double h = 10}) =>
    AssemblyOccurrence(
        id: id, source: id.split(':').first,
        part: boxPart(id.split(':').first, h: h), offset: at)
      ..rot = rot;

AssemblyOccurrence nest(String id, AssemblyModel sub, Vec3 at,
        {Quat rot = Quat.identity}) =>
    AssemblyOccurrence(
        id: id,
        source: sub.name,
        sourceKind: 'assembly',
        sub: sub,
        offset: at)
      ..rot = rot;

AppState freshApp(String tag) =>
    AppState()..docsDirForTest = Directory.systemTemp.createTempSync(tag);

Future<void> makePart(AppState app, String name) async {
  expect(await app.createNamedPart(name), isTrue);
  app.parts[name]!.features.add(ExtrudeFeature(
    name: 'Extrusion1', bodyName: 'Solid1', sketchName: 'Sketch1',
    profiles: [ProfileSel(0, 0, 10)], direction: ExtrudeDirection.defaultDir,
    distanceA: 10, distanceB: 0, extent: FeatureExtent.distance,
  ));
  await app.savePart(name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  group('the geometry composes', () {
    test('a part\'s pieces are all at the identity', () {
      final o = part('Bracket:1', const Vec3(5, 0, 0));
      final pieces = o.localSolids.toList();
      expect(pieces, hasLength(1));
      expect(pieces.single.$1, 'Extrusion1');
      expect(pieces.single.$2.rot.isIdentity, isTrue);
      expect(pieces.single.$2.at.length, lessThan(1e-12),
          reason: 'a feature is in the part\'s own space, by definition');
    });

    test('a subassembly hands its parts up with their own placements', () {
      final sub = AssemblyModel('Gear')
        ..occurrences.add(part('A:1', Vec3.zero))
        ..occurrences.add(part('B:1', const Vec3(30, 0, 0)));
      final o = nest('Gear:1', sub, const Vec3(100, 0, 0));

      final pieces = o.localSolids.toList();
      expect(pieces, hasLength(2));
      // The PATH keeps them apart, and names where they came from.
      expect(pieces.map((p) => p.$1),
          ['A:1/Extrusion1', 'B:1/Extrusion1']);
      // The inner placement survives: B is still 30 mm along, INSIDE the
      // subassembly, before the subassembly's own placement applies.
      expect(pieces[0].$2.at.x, closeTo(0, 1e-9));
      expect(pieces[1].$2.at.x, closeTo(30, 1e-9));

      // And in the world it is 100 + 30.
      final world = o.worldSolids.toList();
      expect(world[0].$2.at.x, closeTo(100, 1e-9));
      expect(world[1].$2.at.x, closeTo(130, 1e-9));
    });

    test('a TURNED subassembly turns what is inside it', () {
      // A quarter turn about Z takes +X to +Y. The inner part is 30 mm along
      // +X inside the subassembly, so it has to end up 30 mm along +Y of
      // wherever the subassembly sits — and turned itself, not merely moved.
      final quarter = Quat.axisAngle(const Vec3(0, 0, 1), 1.5707963267948966);
      final sub = AssemblyModel('Gear')
        ..occurrences.add(part('B:1', const Vec3(30, 0, 0)));
      final o = nest('Gear:1', sub, const Vec3(0, 0, 5), rot: quarter);

      final (_, at, _) = o.worldSolids.single;
      expect(at.at.x, closeTo(0, 1e-9));
      expect(at.at.y, closeTo(30, 1e-9), reason: '+X inside became +Y outside');
      expect(at.at.z, closeTo(5, 1e-9));
      // The composed rotation takes the inner part's +X to +Y too.
      final tip = at.applyDir(const Vec3(1, 0, 0));
      expect(tip.y, closeTo(1, 1e-9));
      expect(tip.x.abs(), lessThan(1e-9));
    });

    test('a subassembly inside a subassembly composes twice', () {
      final inner = AssemblyModel('Inner')
        ..occurrences.add(part('A:1', const Vec3(1, 0, 0)));
      final middle = AssemblyModel('Middle')
        ..occurrences.add(nest('Inner:1', inner, const Vec3(10, 0, 0)));
      final o = nest('Middle:1', middle, const Vec3(100, 0, 0));

      final piece = o.worldSolids.single;
      expect(piece.$1, 'Inner:1/A:1/Extrusion1',
          reason: 'the path names the whole chain');
      expect(piece.$2.at.x, closeTo(111, 1e-9));
    });

    test('a hidden component inside a subassembly draws nothing', () {
      final sub = AssemblyModel('Gear')
        ..occurrences.add(part('A:1', Vec3.zero))
        ..occurrences.add(part('B:1', const Vec3(30, 0, 0)));
      sub.occurrences.last.visible = false;
      expect(nest('Gear:1', sub, Vec3.zero).worldSolids, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('every consumer sees the composed transform', () {
    AssemblyModel nested() {
      final sub = AssemblyModel('Gear')
        ..occurrences.add(part('A:1', Vec3.zero))
        ..occurrences.add(part('B:1', const Vec3(40, 0, 0)));
      return AssemblyModel('Machine')
        ..occurrences.add(nest('Gear:1', sub, const Vec3(200, 0, 0)));
    }

    test('the BOUNDS reach the far part, not just the subassembly origin', () {
      final a = nested();
      final b = assemblyContentBounds(a);
      expect(b, isNotNull);
      // A at 200 (half-size 10) and B at 240 (half-size 10).
      expect(b!.$1.x, closeTo(190, 1e-6));
      expect(b.$2.x, closeTo(250, 1e-6),
          reason: 'bounds that stop at 210 mean the composition was dropped');
    });

    test('the PAINTER gets one piece per inner part, each placed', () {
      final placed = placedComponents(nested());
      expect(placed, hasLength(1), reason: 'one component...');
      expect(placed.single.pieces, hasLength(2), reason: '...of two pieces');
      final xs = placed.single.pieces.map((p) => p.$1.at.x).toList()..sort();
      expect(xs[0], closeTo(200, 1e-9));
      expect(xs[1], closeTo(240, 1e-9));
    });

    test('the REALITYKIT payload keys each inner part apart and places it',
        () {
      final a = nested();
      final pieces = assemblyPieces(a);
      expect(pieces.map((p) => p.$1),
          ['Gear:1/A:1/Extrusion1', 'Gear:1/B:1/Extrusion1']);
      expect(pieces[1].$3.at.x, closeTo(240, 1e-9));
      // Two occurrences of ONE subassembly must not collide on the id.
      a.occurrences.add(nest('Gear:2', a.occurrences.first.sub!,
          const Vec3(-200, 0, 0)));
      final ids = assemblyPieces(a).map((p) => p.$1).toSet();
      expect(ids, hasLength(4));
    });

    test('the PICKER finds the inner part where it is drawn, and answers '
        'with the COMPONENT', () {
      final a = nested();
      final cam = Cam3(PartCamera(az: 0, pol: 1.5707963267948966, halfH: 200),
          const Size(800, 600));
      // Point at the far inner part, at 240 mm.
      final hit = pickOccurrence(a, cam, cam.project(const Vec3(240, 0, 0)));
      expect(hit?.id, 'Gear:1',
          reason: 'a subassembly is ONE body: you grab the whole thing');
      // And nothing is at the subassembly origin + inner origin confusion
      // point, which is where a dropped composition would have drawn it.
      final pick = pickAsmRef(a, cam, cam.project(const Vec3(240, 0, 0)));
      expect(pick, isNotNull);
      expect(pick!.ref.occurrence, 'Gear:1');
      // The stored geometry is in the COMPONENT's frame: the subassembly sits
      // at 200, the face is on the part at 240, so locally it is near 40.
      expect(pick.ref.anchor.x, closeTo(40, 12),
          reason: 'a reference is stored in the component it belongs to');
    });
  });

  // -------------------------------------------------------------------------
  group('placing one', () {
    Future<AppState> withDocs(String tag) async {
      final app = freshApp(tag);
      await makePart(app, 'Bracket');
      app.goHome();
      expect(await app.createNamedAssembly('Gear'), isTrue);
      await app.placeComponent('Bracket');
      await app.saveAssembly('Gear');
      await app.closeTab('Gear');
      expect(await app.createNamedAssembly('Machine'), isTrue);
      return app;
    }

    test('an assembly can be placed into another one', () async {
      final app = await withDocs('ipc_m246_place');
      final occ = await app.placeComponent('Gear');
      expect(occ, isNotNull);
      expect(occ!.isSubAssembly, isTrue);
      expect(occ.sub, isNotNull);
      expect(occ.part, isNull, reason: 'exactly one of the two is ever set');
      expect(occ.loaded, isTrue);
      // Its inner part was resolved too, or the subassembly draws nothing.
      expect(occ.sub!.occurrences.single.part, isNotNull);
    });

    test('the Place list offers assemblies as well as parts', () async {
      final app = await withDocs('ipc_m246_list');
      expect(app.placeableParts(), contains('Bracket'));
      expect(app.placeableParts(), contains('Gear'));
      expect(app.placeableParts(), isNot(contains('Machine')),
          reason: 'an assembly cannot contain itself');
    });

    test('an assembly refuses to contain itself, directly', () async {
      final app = await withDocs('ipc_m246_self');
      expect(await app.placeComponent('Machine'), isNull);
      expect(app.currentAssembly!.occurrences, isEmpty);
      expect(app.message, isNotNull, reason: 'and it says why');
    });

    test('an assembly refuses a cycle through a chain', () async {
      final app = await withDocs('ipc_m246_cycle');
      // Machine holds Gear.
      await app.placeComponent('Gear');
      await app.saveAssembly('Machine');
      await app.closeTab('Machine');
      // Now try to put Machine inside Gear, which would close the loop.
      await app.openAssembly('Gear');
      expect(await app.placeComponent('Machine'), isNull);
      expect(app.currentAssembly!.occurrences, hasLength(1),
          reason: 'only the Bracket it already had');
      expect(app.placeableParts(), isNot(contains('Machine')));
    });

    test('it survives the document round trip as an assembly', () async {
      final app = await withDocs('ipc_m246_rt');
      await app.placeComponent('Gear');
      await app.saveAssembly('Machine');
      await app.closeTab('Machine');

      await app.openAssembly('Machine');
      final occ = app.currentAssembly!.occurrences.single;
      expect(occ.isSubAssembly, isTrue,
          reason: 'the KIND is recorded, not guessed from a file that may '
              'not be there');
      expect(occ.sub, isNotNull);
      expect(occ.sub!.occurrences.single.part, isNotNull,
          reason: 'and the load reached the parts inside it');
    });
  });

  // -------------------------------------------------------------------------
  group('a subassembly is LIVE too', () {
    test('editing the subassembly document changes the parent', () async {
      final app = freshApp('ipc_m246_live');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gear');
      await app.placeComponent('Bracket');
      await app.saveAssembly('Gear');
      await app.createNamedAssembly('Machine');
      final occ = (await app.placeComponent('Gear'))!;
      expect(occ.sub!.occurrences, hasLength(1));

      // Gear is still open in its own tab, so the parent must be holding
      // THAT model — the same identity rule a part follows.
      expect(occ.sub, same(app.assemblies['Gear']));
      await app.openAssembly('Gear');
      await app.placeComponent('Bracket');
      expect(occ.sub!.occurrences, hasLength(2),
          reason: 'the parent sees it because it IS the subassembly');
    });
  });

  // -------------------------------------------------------------------------
  group('the browser', () {
    test('a subassembly row nests its own components under it', () async {
      final app = freshApp('ipc_m246_tree');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gear');
      await app.placeComponent('Bracket');
      await app.saveAssembly('Gear');
      await app.closeTab('Gear');
      await app.createNamedAssembly('Machine');
      await app.placeComponent('Gear');

      var rows = buildBrowserRows(app, expanded: {});
      final row = rows.firstWhere((r) => r.id == '${kIdComponent}Gear:1');
      expect(row.expandable, isTrue,
          reason: 'a subassembly always has something under it');
      expect(rows.where((r) => r.id.contains('Bracket:1')), isEmpty);

      rows = buildBrowserRows(app, expanded: {'${kIdComponent}Gear:1'});
      final inner =
          rows.where((r) => r.id == '${kIdComponent}Gear:1/Bracket:1');
      expect(inner, hasLength(1),
          reason: 'the path is slash-separated: the occurrence id has a '
              'colon of its own');
      expect(inner.single.depth, 2);
    });
  });
}
