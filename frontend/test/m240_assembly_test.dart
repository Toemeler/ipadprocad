// M240 — the assembly document, its ribbon, and the one interaction that is
// wired: place a component, then drag it.
//
// What is worth pinning here, and why each of these could break silently:
//
//   * THE DOCUMENT KIND. A third `kind` string runs through the extension
//     table, the gallery scan, the routing in openDocument/deleteDocument and
//     the file the save lands in. Getting any one of those wrong produces a
//     document that opens as a PART — no error, just the wrong editor.
//   * THE SHIFTED CAMERA. Every component is drawn and hit-tested through
//     `shiftedCam`, on the identity project(w + t) == shiftedCam(t).project(w).
//     If that drifts, components render in one place and pick in another,
//     which reads as "dragging grabs the wrong part".
//   * PLACE. The first component is grounded (Inventor), the next is set down
//     clear of it, and a grounded one refuses to move.
//   * THE RIBBON. Five panels, Inventor's order, and which commands are
//     ENABLED — the claim of the milestone, so it is asserted rather than
//     described. M240 shipped with one (Place); M242 built Constrain, M247 the
//     three work features, M248 Pattern/Mirror/Copy, M249 Joint / Show / Hide
//     All and M250 Create / Free Move / Free Rotate — so the tab is finished
//     and the drawn-and-disabled list is empty. Show Sick is the one command
//     that can be untappable, and it is greyed for a REASON (nothing is sick)
//     rather than for being unbuilt.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/widgets/native_browser.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/viewport_assembly.dart';

/// An axis-aligned box mesh centred on the origin, as a [KernelSolid] with no
/// B-Rep behind it — the shape every host fake in this suite has.
///
/// Twelve real triangles, because the pick and the bounds walk the index
/// buffer: a mesh with no triangles would make [pickOccurrence] vacuously
/// return null and the test pass for the wrong reason.
KernelSolid boxSolid({double h = 10}) {
  final c = [
    [-h, -h, -h],
    [h, -h, -h],
    [h, h, -h],
    [-h, h, -h],
    [-h, -h, h],
    [h, -h, h],
    [h, h, h],
    [-h, h, h],
  ];
  const faces = [
    [0, 3, 2, 1], // -Z
    [4, 5, 6, 7], // +Z
    [0, 1, 5, 4], // -Y
    [3, 7, 6, 2], // +Y
    [0, 4, 7, 3], // -X
    [1, 2, 6, 5], // +X
  ];
  const normals = [
    [0.0, 0.0, -1.0],
    [0.0, 0.0, 1.0],
    [0.0, -1.0, 0.0],
    [0.0, 1.0, 0.0],
    [-1.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
  ];
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  for (var f = 0; f < faces.length; f++) {
    final base = pos.length ~/ 3;
    for (final vi in faces[f]) {
      pos.addAll(c[vi]);
      nor.addAll(normals[f]);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }
  return KernelSolid(
    OcctMeshData(
      Float64List.fromList(pos),
      Float64List.fromList(nor),
      Int32List.fromList(idx),
      Int32List.fromList([0]),
      Float64List(0),
    ),
    8 * h * h * h,
    null,
  );
}

/// A part model carrying one box, ready to be hung on an occurrence.
PartModel boxPart(String name, {double h = 10}) {
  final p = PartModel(name);
  p.features.add(ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: 'Sketch1',
    profiles: [ProfileSel(0, 0, 10)],
    direction: ExtrudeDirection.defaultDir,
    distanceA: 2 * h,
    distanceB: 0,
    extent: FeatureExtent.distance,
  )..solid = boxSolid(h: h));
  return p;
}

AssemblyOccurrence placed(String id, Vec3 at, {bool grounded = false}) =>
    AssemblyOccurrence(
        id: id, source: id.split(':').first, part: boxPart(id.split(':').first),
        offset: at, grounded: grounded);

AppState freshApp(String tag) =>
    AppState()..docsDirForTest = Directory.systemTemp.createTempSync(tag);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  group('the document kind', () {
    test('an assembly is its own kind, extension and DocRef', () {
      expect(extForKind(kAssemblyDocKind), kAsmExt);
      expect(extForKind('part'), kPartExt);
      expect(extForKind('sketch'), kSketchExt);
      // An unknown kind must not silently become an assembly.
      expect(extForKind('nonsense'), kPartExt);
      expect(kDocExtensions, containsAll([kPartExt, kSketchExt, kAsmExt]));
      expect(docNameOf('/x/Gearbox.$kAsmExt'), 'Gearbox');
      expect(isAssemblyPath('/x/Gearbox.$kAsmExt'), isTrue);
      expect(isAssemblyPath('/x/Gearbox.$kPartExt'), isFalse);
      expect(isPartPath('/x/Gearbox.$kAsmExt'), isFalse);
    });

    test('created, saved, closed and re-opened as an assembly', () async {
      final app = freshApp('ipc_m240_doc');
      expect(await app.createNamedAssembly('Gearbox'), isTrue);
      expect(app.isAssemblyName('Gearbox'), isTrue);
      // The routing questions the rest of the app asks.
      expect(app.isPartName('Gearbox'), isFalse);
      expect(app.currentPart, isNull);
      expect(app.current, isNull, reason: 'an assembly is not a sketch');
      expect(app.docNameExists('Gearbox'), isTrue,
          reason: 'the name is taken across all three kinds');

      // The file it landed in.
      final path = app.pathOfDocument('Gearbox');
      expect(path, isNotNull);
      expect(path!.endsWith('.$kAsmExt'), isTrue, reason: path);

      // A camera the user moved survives the round trip; that is the whole
      // reason the document carries one.
      app.currentAssembly!.camera.halfH = 123.5;
      app.currentAssembly!.vis['xy'] = true;
      await app.saveAssembly('Gearbox');
      await app.closeTab('Gearbox');
      expect(app.assemblies.containsKey('Gearbox'), isFalse);

      await app.openDocument('Gearbox');
      expect(app.currentAssembly, isNotNull,
          reason: 'openDocument must route .pas to openAssembly');
      expect(app.currentAssembly!.camera.halfH, closeTo(123.5, 1e-9));
      expect(app.currentAssembly!.vis['xy'], isTrue);
    });

    test('an occurrence survives the round trip as a reference', () async {
      final app = freshApp('ipc_m240_occ');
      await app.createNamedAssembly('Gearbox');
      final a = app.currentAssembly!;
      a.occurrences.add(placed('Bracket:1', const Vec3(1, 2, 3),
          grounded: true));
      a.occurrences.add(placed('Bracket:2', const Vec3(40, 0, 0)));
      await app.saveAssembly('Gearbox');
      await app.closeTab('Gearbox');
      await app.openAssembly('Gearbox');

      final back = app.currentAssembly!;
      expect(back.occurrences.map((o) => o.id).toList(),
          ['Bracket:1', 'Bracket:2']);
      expect(back.occurrences.first.offset.x, closeTo(1, 1e-9));
      expect(back.occurrences.first.offset.y, closeTo(2, 1e-9));
      expect(back.occurrences.first.offset.z, closeTo(3, 1e-9));
      expect(back.occurrences.first.grounded, isTrue);
      expect(back.occurrences.last.grounded, isFalse);
      // The source part does not exist in this scratch folder, so the geometry
      // could not be loaded — and the OCCURRENCE is still listed. Dropping it
      // would rewrite the user's assembly behind their back.
      expect(back.occurrences.first.loaded, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('occurrence ids and placement', () {
    test('ids count the way Inventor counts them', () {
      final a = AssemblyModel('A');
      expect(a.nextOccurrenceId('Bracket'), 'Bracket:1');
      a.occurrences.add(placed('Bracket:1', Vec3.zero));
      expect(a.nextOccurrenceId('Bracket'), 'Bracket:2');
      a.occurrences.add(placed('Bracket:2', Vec3.zero));
      expect(a.nextOccurrenceId('Bracket'), 'Bracket:3');
      expect(a.nextOccurrenceId('Shaft'), 'Shaft:1');
    });

    test('the first component lands on the origin, the next one clear of it',
        () {
      final a = AssemblyModel('A');
      final first = AssemblyOccurrence(
          id: 'Bracket:1', source: 'Bracket', part: boxPart('Bracket'));
      expect(nextPlacement(a, occurrenceBounds(first)), Vec3.zero,
          reason: 'nothing to clear yet');
      a.occurrences.add(first);

      final second = AssemblyOccurrence(
          id: 'Bracket:2', source: 'Bracket', part: boxPart('Bracket'));
      second.offset = nextPlacement(a, occurrenceBounds(second));
      // Strictly to the +X side of everything already placed, so two
      // occurrences of one part are two visible components.
      final (lo, hi) = assemblyContentBounds(a)!;
      expect(second.offset.x - 10, greaterThan(hi.x), reason: 'lo.x=${lo.x}');
      a.occurrences.add(second);
      // And they do not overlap.
      final b1 = occurrenceBounds(a.occurrences[0])!;
      final b2 = occurrenceBounds(a.occurrences[1])!;
      expect(b2.$1.x, greaterThan(b1.$2.x));
    });

    test('origin planes and axes frame the placed components', () {
      final a = AssemblyModel('A');
      // Empty: the fixed default cube, exactly as an empty part gets.
      final (elo, ehi) = assemblyOriginExtent(a);
      expect(ehi.x, closeTo(kOriginExtentDefault, 1e-9));
      expect(elo.x, closeTo(-kOriginExtentDefault, 1e-9));

      a.occurrences.add(placed('Bracket:1', const Vec3(50, 0, 0)));
      final (lo, hi) = assemblyOriginExtent(a);
      // The component sits at x in [40, 60]; the extent must reach past it
      // AND still contain the origin, or the axes would leave the planes.
      expect(hi.x, greaterThan(60));
      expect(lo.x, lessThanOrEqualTo(0));
      final (axLo, axHi) = assemblyAxisSpan(a, const Vec3(1, 0, 0));
      expect(axHi, closeTo(hi.x, 1e-9));
      expect(axLo, closeTo(lo.x, 1e-9));
    });
  });

  // -------------------------------------------------------------------------
  group('the shifted camera', () {
    const size = Size(800, 600);

    test('projecting through a shifted camera equals shifting the point', () {
      final cam = Cam3(PartCamera(az: 0.7, pol: 1.1, halfH: 40), size);
      const t = Vec3(13, -7, 21);
      final sc = shiftedCam(cam, t);
      for (final w in const [
        Vec3.zero,
        Vec3(5, 5, 5),
        Vec3(-30, 12, 4),
        Vec3(0.001, 0, -100),
      ]) {
        final a = cam.project(w + t);
        final b = sc.project(w);
        expect(b.dx, closeTo(a.dx, 1e-9), reason: 'x for $w');
        expect(b.dy, closeTo(a.dy, 1e-9), reason: 'y for $w');
      }
    });

    test('it holds after an orbit, at any roll', () {
      final c = PartCamera(az: 0.3, pol: 0.9, halfH: 30)
        ..orbitScreen(0.8, -1.3)
        ..orbitScreen(-0.2, 0.4);
      final cam = Cam3(c, size);
      expect(c.roll, isNot(closeTo(0, 1e-6)),
          reason: 'the trackball must have produced a roll to be worth testing');
      const t = Vec3(-4, 9, 2);
      final p = cam.project(const Vec3(3, 1, -2) + t);
      final q = shiftedCam(cam, t).project(const Vec3(3, 1, -2));
      expect(q.dx, closeTo(p.dx, 1e-9));
      expect(q.dy, closeTo(p.dy, 1e-9));
    });
  });

  // -------------------------------------------------------------------------
  group('picking a component', () {
    const size = Size(800, 600);
    // Straight down -Z at the XY plane, so screen x/y map to world x/y and the
    // expected hit is something a reader can check by eye.
    Cam3 frontCam() =>
        Cam3(PartCamera(az: 0, pol: 1.5707963267948966, halfH: 60), size);

    test('the component under the pointer is the one that is picked', () {
      final a = AssemblyModel('A');
      a.occurrences.add(placed('Bracket:1', Vec3.zero));
      a.occurrences.add(placed('Shaft:1', const Vec3(40, 0, 0)));
      final cam = frontCam();

      expect(pickOccurrence(a, cam, cam.project(Vec3.zero))?.id, 'Bracket:1');
      expect(pickOccurrence(a, cam, cam.project(const Vec3(40, 0, 0)))?.id,
          'Shaft:1');
      // Between them there is nothing.
      expect(pickOccurrence(a, cam, cam.project(const Vec3(22, 0, 0))), isNull);
      // And off the model entirely.
      expect(pickOccurrence(a, cam, const Offset(2, 2)), isNull);
    });

    test('a hidden component is not pickable', () {
      final a = AssemblyModel('A');
      final o = placed('Bracket:1', Vec3.zero);
      a.occurrences.add(o);
      final cam = frontCam();
      expect(pickOccurrence(a, cam, cam.project(Vec3.zero)), isNotNull);
      o.visible = false;
      expect(pickOccurrence(a, cam, cam.project(Vec3.zero)), isNull);
    });

    test('the NEARER of two stacked components wins', () {
      final a = AssemblyModel('A');
      // Two boxes on the view axis, one behind the other. WHICH of the two is
      // nearer is asserted through Cam3.depth rather than by naming a sign:
      // the renderer's convention (larger depth = nearer, the rule
      // buildSceneSolid and the painter's sort both run on) is the one the
      // pick has to agree with, and hard-coding +Z here would only pin my
      // reading of it.
      a.occurrences.add(placed('A:1', const Vec3(0, 0, -30)));
      a.occurrences.add(placed('B:1', const Vec3(0, 0, 30)));
      final cam = frontCam();
      final nearer = cam.depth(const Vec3(0, 0, -30)) >
              cam.depth(const Vec3(0, 0, 30))
          ? 'A:1'
          : 'B:1';
      expect(pickOccurrence(a, cam, cam.project(Vec3.zero))?.id, nearer);
    });
  });

  // -------------------------------------------------------------------------
  group('placing and moving', () {
    test('Place grounds the first component and not the second', () async {
      final app = freshApp('ipc_m240_place');
      expect(await app.createNamedPart('Bracket'), isTrue);
      await app.savePart('Bracket');
      app.goHome();
      expect(await app.createNamedAssembly('Gearbox'), isTrue);

      final first = await app.placeComponent('Bracket');
      expect(first, isNotNull);
      expect(first!.id, 'Bracket:1');
      expect(first.grounded, isTrue,
          reason: 'Inventor grounds the first component of an assembly');

      final second = await app.placeComponent('Bracket');
      expect(second!.id, 'Bracket:2');
      expect(second.grounded, isFalse);
      expect(app.currentAssembly!.occurrences, hasLength(2));
      expect(app.currentAssembly!.selected, same(second),
          reason: 'the component you just placed is the one selected');
    });

    test('Place says so when the part is not there', () async {
      final app = freshApp('ipc_m240_noplace');
      await app.createNamedAssembly('Gearbox');
      expect(await app.placeComponent('Nothing'), isNull);
      expect(app.message, isNotNull);
      expect(app.currentAssembly!.occurrences, isEmpty);
    });

    test('an unconstrained component moves; a grounded one does not', () {
      final app = freshApp('ipc_m240_move');
      final a = AssemblyModel('Gearbox');
      app.assemblies['Gearbox'] = a;
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      final fixed = placed('Base:1', Vec3.zero, grounded: true);
      final free = placed('Lid:1', const Vec3(40, 0, 0));
      a.occurrences.addAll([fixed, free]);

      app.moveOccurrence(free, const Vec3(5, -2, 1));
      expect(free.offset.x, closeTo(45, 1e-9));
      expect(free.offset.y, closeTo(-2, 1e-9));
      expect(free.offset.z, closeTo(1, 1e-9));

      app.moveOccurrence(fixed, const Vec3(5, 5, 5));
      expect(fixed.offset, Vec3.zero, reason: 'grounded means grounded');
    });

    test('a screen-space drag moves the component exactly under the finger',
        () {
      const size = Size(800, 600);
      final app = freshApp('ipc_m240_drag');
      final a = AssemblyModel('Gearbox');
      app.assemblies['Gearbox'] = a;
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      final o = placed('Lid:1', Vec3.zero);
      a.occurrences.add(o);

      // An arbitrary orbited camera, so this is not accidentally an
      // axis-aligned special case.
      final c = PartCamera(az: 0.9, pol: 1.2, halfH: 45)..orbitScreen(0.3, 0.2);
      final cam = Cam3(c, size);
      const from = Offset(300, 300);
      const to = Offset(360, 240);
      // The viewport's own rule: the world delta is the difference of the two
      // pixels unprojected onto the camera plane.
      app.moveOccurrence(
          o, cam.unprojectOnCamPlane(to) - cam.unprojectOnCamPlane(from));

      // The component's ORIGIN must now project exactly where the finger went.
      final landed = cam.project(o.offset);
      expect(landed.dx, closeTo(cam.project(Vec3.zero).dx + (to.dx - from.dx),
          1e-6));
      expect(landed.dy, closeTo(cam.project(Vec3.zero).dy + (to.dy - from.dy),
          1e-6));
    });

    test('a settled drag ticks the generation and tells the viewport', () {
      // M241 — the drag itself deliberately does NOT move the scene
      // signature (a placement rides the light RealityKit push), so the
      // origin planes, which are sized to the assembly's contents, are stale
      // the moment the finger lifts. endOccurrenceDrag is what settles that,
      // and it has to NOTIFY or nothing rebuilds to act on it.
      final app = freshApp('ipc_m240_dragend');
      final a = AssemblyModel('Gearbox');
      app.assemblies['Gearbox'] = a;
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      final o = placed('Lid:1', Vec3.zero);
      a.occurrences.add(o);

      var notified = 0;
      app.addListener(() => notified++);

      final genBefore = a.gen;
      app.moveOccurrence(o, const Vec3(10, 0, 0));
      expect(a.gen, genBefore, reason: 'a drag in flight must not tick it');
      expect(notified, greaterThan(0), reason: 'the viewport must repaint');

      final n = notified;
      app.endOccurrenceDrag();
      expect(a.gen, greaterThan(genBefore));
      expect(notified, greaterThan(n));
    });

    test('deleting an occurrence clears the selection with it', () {
      final app = freshApp('ipc_m240_del');
      final a = AssemblyModel('Gearbox');
      app.assemblies['Gearbox'] = a;
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      final o = placed('Lid:1', Vec3.zero);
      a.occurrences.add(o);
      app.selectOccurrence(o);
      expect(a.selected, same(o));
      app.deleteOccurrence(o);
      expect(a.occurrences, isEmpty);
      expect(a.selected, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the browser tree', () {
    test('an assembly shows Representations, Relationships, Origin, then the '
        'components', () {
      final app = freshApp('ipc_m240_tree');
      final a = AssemblyModel('Gearbox');
      app.assemblies['Gearbox'] = a;
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      a.occurrences.add(placed('Bracket:1', Vec3.zero, grounded: true));
      a.occurrences.add(placed('Bracket:2', const Vec3(40, 0, 0)));

      final rows = buildBrowserRows(app, expanded: const {});
      expect(rows.map((r) => r.id).toList(), [
        'root',
        kIdRepresentations,
        kIdRelationships,
        'origin',
        '${kIdComponent}Bracket:1',
        '${kIdComponent}Bracket:2',
      ]);
      expect(rows.first.label, 'Gearbox');
      // The grounded one carries Inventor's pin.
      expect(rows[4].symbol, 'pin.fill');
      expect(rows[5].symbol, 'cube');
      // Every component row has an eye and a menu.
      expect(rows[4].hasEye, isTrue);
      expect(rows[4].menu, isNotEmpty);
    });

    test('expanding Origin lists the same seven entries a part has', () {
      final app = freshApp('ipc_m240_origin');
      final a = AssemblyModel('Gearbox');
      app.assemblies['Gearbox'] = a;
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      a.vis['xy'] = true;

      final rows = buildBrowserRows(app, expanded: const {'origin'});
      final origin = [
        for (final r in rows)
          if (r.id.startsWith(kIdOrigin)) r
      ];
      expect(origin.map((r) => r.id.substring(kIdOrigin.length)).toList(),
          ['yz', 'xz', 'xy', 'x', 'y', 'z', 'cp']);
      expect(origin.firstWhere((r) => r.id.endsWith('xy')).eyeOn, isTrue);
      expect(origin.firstWhere((r) => r.id.endsWith('yz')).eyeOn, isFalse);
    });

    test('a component id with a colon in it survives the row-id round trip',
        () {
      // 'cp:' + 'Bracket:1' — the id after the prefix must be taken WHOLE.
      final a = AssemblyModel('Gearbox');
      final o = placed('Bracket:1', Vec3.zero);
      a.occurrences.add(o);
      const rowId = '${kIdComponent}Bracket:1';
      expect(a.byId(rowId.substring(kIdComponent.length)), same(o));
    });
  });

  // -------------------------------------------------------------------------
  group('the ribbon', () {
    Future<void> pumpAssemblyRibbon(WidgetTester t, AppState app) async {
      await t.binding.setSurfaceSize(const Size(1366, 1024));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
      await t.pump();
    }

    AppState assemblyApp() {
      final app = freshApp('ipc_m240_ribbon');
      app.assemblies['Gearbox'] = AssemblyModel('Gearbox');
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      return app;
    }

    setUp(resetFlyoutCacheForTest);
    tearDown(() => L.set(kDe));

    testWidgets('it is the five Inventor panels, in Inventor order',
        (t) async {
      L.set(kEn);
      resetFlyoutCacheForTest();
      await pumpAssemblyRibbon(t, assemblyApp());
      for (final p in const [
        'Component',
        'Position',
        'Relationships',
        'Work Features',
      ]) {
        expect(find.text(p), findsOneWidget, reason: 'panel "$p"');
      }
      // "Pattern" is on screen TWICE and both are meant to be: Inventor's
      // Pattern panel holds a Pattern command. findsWidgets, not a laxer
      // matcher everywhere — the four above must still be exactly one each.
      expect(find.text('Pattern'), findsNWidgets(2));
      // And it is NOT the part ribbon: no Extrude, no Fillet.
      expect(find.text('Extrude'), findsNothing);
      expect(find.text('Fillet'), findsNothing);
    });

    // M242 (SPEC CHANGE) — Constrain is built now, so the name and the list
    // below both move by exactly one entry.
    //
    // M248 (SPEC CHANGE) — and so do Pattern, Mirror and Copy. All three are
    // built: Pattern and Mirror open the part's pattern panel with an assembly
    // session in it, and Copy places another occurrence of the selected
    // component as it sits. The drawn-and-disabled list loses all three, and
    // "Pattern" — which covers the panel TITLE as well as the command — is now
    // tappable exactly once, since a panel title never was.
    //
    // M250 (SPEC CHANGE) — and so do Create, Free Move and Free Rotate. All
    // three are built: Create Component writes a new part document, places it
    // on the plane you pick and opens it for editing with the assembly still
    // around it; Free Move and Free Rotate are Inventor's Position commands,
    // which move a component WITHOUT the solver — the relationships are
    // overridden until the next update takes it back. Landing beside M249,
    // which built the other three, that empties the drawn-and-disabled list
    // altogether; the loop below therefore asserts the positive.
    //
    // M247 (SPEC CHANGE) — and so do Plane, Axis and Point. Two things move
    // with them:
    //
    //   * UCS leaves the panel. It is unbuilt in BOTH modes, and the part
    //     ribbon has always kept it behind the panel's ▼ where _OverRow draws
    //     it dimmed (M216's rule). Now that the other three are real, the
    //     assembly panel is the part panel, ▼ and all — so 'UCS' is no longer
    //     on screen until that menu is opened, and this test says so rather
    //     than pinning a layout that no longer exists.
    //   * the three that are built are TAPPABLE, and the drawn-and-disabled
    //     list loses them.
    //
    // M249 (SPEC CHANGE) — Joint, Show and Hide All are built. Written before
    // M250 landed, when those three were what the list would have kept; they
    // are built too, so between them nothing is left in it.
    //
    // SHOW SICK stays in it, and it is the one entry there for a NEW reason:
    // it is built and unavailable. Inventor's own rule — "the command is not
    // available if all relationships are healthy" — and this fixture has no
    // relationships at all, so the row must draw exactly as an unbuilt one
    // does. The test below says so on both sides: untappable here, and
    // tappable the moment a constraint goes sick (see "Show Sick lights up
    // only when something is sick").
    testWidgets('every command is drawn; the built ones are enabled',
        (t) async {
      L.set(kEn);
      resetFlyoutCacheForTest();
      await pumpAssemblyRibbon(t, assemblyApp());
      for (final b in const [
        'Place',
        'Create',
        'Free Move',
        'Free Rotate',
        'Joint',
        'Constrain',
        'Show',
        'Show Sick',
        'Hide All',
        'Mirror',
        'Copy',
        'Plane',
        'Axis',
        'Point',
      ]) {
        expect(find.text(b), findsOneWidget, reason: 'button "$b"');
      }
      expect(find.text('Pattern'), findsNWidgets(2),
          reason: 'the Pattern command inside the Pattern panel');
      // M247 — behind the ▼, exactly as in the part ribbon.
      expect(find.text('UCS'), findsNothing,
          reason: 'UCS is unbuilt in both modes and lives in the overflow');

      // "Enabled" is a property of the widget tree, not of the colour: a
      // disabled command's GestureDetector carries no onTap, so nothing can
      // fire from it however it is drawn.
      int tappable(String label) {
        final gds = find
            .ancestor(
                of: find.text(label), matching: find.byType(GestureDetector))
            .evaluate();
        return gds
            .where((e) => (e.widget as GestureDetector).onTap != null)
            .length;
      }

      expect(tappable('Place'), greaterThan(0), reason: 'Place is the one');
      expect(tappable('Constrain'), greaterThan(0),
          reason: 'M242 — Place Constraint opens from here');
      for (final on in const ['Plane', 'Axis', 'Point']) {
        expect(tappable(on), greaterThan(0),
            reason: 'M247 — "$on" builds an assembly work feature');
      }
      for (final on in const ['Mirror', 'Copy']) {
        expect(tappable(on), greaterThan(0),
            reason: 'M248 — "$on" is built');
      }
      for (final on in const ['Joint', 'Show', 'Hide All']) {
        expect(tappable(on), greaterThan(0),
            reason: 'M249 — "$on" is built');
      }
      for (final on in const ['Create', 'Free Move', 'Free Rotate']) {
        expect(tappable(on), greaterThan(0),
            reason: 'M250 — "$on" is built');
      }
      // 'Pattern' is on screen twice — the panel title and the command — and
      // exactly ONE of them is tappable, which is the stronger assertion than
      // either count alone: the command works and the title is still a label.
      expect(tappable('Pattern'), 1,
          reason: 'M248 — the command is wired; the panel title is not a '
              'button and never was');
      // M249 + M250 (SPEC CHANGE) — THE DRAWN-AND-DISABLED LIST IS EMPTY.
      //
      // It has been a list of exceptions since M240 and there is nothing left
      // to except: M249 built Joint, Show and Hide All, M250 built Create,
      // Free Move and Free Rotate. So the claim is asserted the other way
      // round — every command on this tab is tappable — which is the stronger
      // statement and the one that will fail if a future milestone adds a
      // button and forgets to wire it.
      //
      // Show Sick is deliberately not in the list, and it is not an exception
      // either: it is BUILT and UNAVAILABLE, greyed because nothing is sick.
      // See the assertion below, which pins both halves of that.
      for (final b in const [
        'Place',
        'Create',
        'Free Move',
        'Free Rotate',
        'Joint',
        'Constrain',
        'Show',
        'Hide All',
        'Mirror',
        'Copy',
        'Plane',
        'Axis',
        'Point',
      ]) {
        expect(tappable(b), greaterThan(0),
            reason: '"$b" is built and must be tappable');
      }
      // M249 — built, and unavailable because nothing is sick. Drawn exactly
      // as an unbuilt command is, which is what Inventor does with it.
      expect(tappable('Show Sick'), 0,
          reason: 'M249 — Show Sick is greyed while every relationship is '
              'healthy, and this assembly has none at all');
    });

    testWidgets('it renders in German too', (t) async {
      L.set(kDe);
      resetFlyoutCacheForTest();
      await pumpAssemblyRibbon(t, assemblyApp());
      expect(find.text('Komponente'), findsOneWidget);
      expect(find.text('Platzieren'), findsOneWidget);
      expect(find.text('Beziehungen'), findsOneWidget);
      expect(find.text('Frei bewegen'), findsOneWidget);
      expect(find.text('Abhängig machen'), findsOneWidget);
      // Same collision as the English side: panel title and command.
      expect(find.text('Anordnung'), findsNWidgets(2));
    });
  });
}
