// M345 — copy and paste, everywhere, with everything.
//
// "I want to be able to convert a sketch into a part and a sketch in a part
//  into a single 2d sketch. I want to be able to copy and paste sketches in a
//  part into another sketch or just onto a plane. […] I want to be able to
//  copy and paste part of a sketch. I want to copy and paste a solid into
//  another part or in a assembly. […] Copy paste should work over the whole
//  app. Everywhere with everything."
//
// WHAT THIS SUITE IS ABOUT
// ------------------------
// Two thirds of it is not about "did the geometry arrive". Geometry arriving
// is the easy half and it is pinned in one group; the rest is about what
// happens to everything that HANGS OFF geometry when it crosses a document
// boundary — constraints whose other end was not selected, projections that
// point at an entity index, dimensions named d0 in a sketch that already has a
// d0, expressions referencing a parameter that did not come along, layers the
// target has never heard of, pictures whose files live in another document.
// Every one of those is a way for a paste to look right on the day and be
// wrong later, which is exactly the failure M255 was written about one level
// up.
//
// The kernel is faked (there is no OCCT on a Linux runner), and the fake for
// the body tests writes and reads a REAL FILE — because "the copy survives its
// origin being closed" is a claim about a file, and a fake that kept the body
// in memory would prove nothing.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/clipboard.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/inserts.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/home_view.dart' show sketchMenuGroups, newDocMenuItems;
import 'package:prototype/widgets/native_browser.dart' as nb;
import 'package:prototype/widgets/quick_tools.dart';

import 'm56_part_test.dart' show FakeKernel;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A kernel that can write and re-read a "STEP" file.
///
/// The format is JSON holding one volume per solid, which is enough: every
/// assertion here is about WHICH body arrived and whether it came off a file,
/// and a fake B-Rep would be a lie in a project whose rule (M55) is that the
/// app never fakes one.
class FileKernel extends FakeKernel {
  int exports = 0, imports = 0;
  bool refuseExport = false;

  @override
  bool exportStep(List<KernelSolid> solids, String path) {
    if (refuseExport) return false;
    exports++;
    File(path).writeAsStringSync(
        jsonEncode([for (final s in solids) s.volume]));
    return true;
  }

  @override
  List<KernelSolid> importStepSolids(String path) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    imports++;
    final vols = (jsonDecode(f.readAsStringSync()) as List).cast<num>();
    return [for (final v in vols) stubSolid(v.toDouble())];
  }
}

KernelSolid stubSolid(double volume) => KernelSolid(
      OcctMeshData(
        Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
        Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
        Int32List.fromList(const [0, 1, 2]),
        Int32List.fromList(const [0, 3]),
        Float64List.fromList(const [0, 0, 1]),
      ),
      volume,
      null,
    );

AppState freshApp(String tag) {
  final app = AppState()
    ..docsDirForTest = Directory.systemTemp.createTempSync(tag);
  app.partKernel = FileKernel();
  return app;
}

/// A closed rectangle drawn on one layer, committed through the engine.
Future<SketchModel> rectSketchDoc(AppState app, String name,
    {double w = 20, double h = 10}) async {
  await app.openSketch(name);
  app.startNewLayer(); // -> "Layer 1", in edit mode
  final s = app.current!;
  s.engine.setCurrentLayer('Layer 1');
  s.engine.addLine(0, 0, w, 0);
  s.engine.addLine(w, 0, w, h);
  s.engine.addLine(w, h, 0, h);
  s.engine.addLine(0, h, 0, 0);
  s.refresh();
  return s;
}

/// Four lines and their four corner coincidences, as plain lists — the pure
/// half of this suite works on these rather than on a document.
(List<Geo>, List<Constraint>) rectangle({String layer = 'Layer 1'}) {
  final gs = [
    Geo(Geo.line, [0, 0, 20, 0], layer: layer),
    Geo(Geo.line, [20, 0, 20, 10], layer: layer),
    Geo(Geo.line, [20, 10, 0, 10], layer: layer),
    Geo(Geo.line, [0, 10, 0, 0], layer: layer),
  ];
  final cs = [
    for (var i = 0; i < 4; i++)
      Constraint(CType.coincident,
          pts: [PRef(i, 1), PRef((i + 1) % 4, 0)]),
  ];
  return (gs, cs);
}

/// A part with one child sketch (the rectangle) and one extrusion off it.
Future<PartModel> partWithBody(AppState app, String name,
    {double depth = 10, int bodies = 1}) async {
  expect(await app.createNamedPart(name), isTrue);
  final p = app.parts[name]!;
  final sk = SketchModel('Sketch1')..layers.add('Layer 1');
  sk.engine.setCurrentLayer('Layer 1');
  sk.engine.addLine(0, 0, 20, 0);
  sk.engine.addLine(20, 0, 20, 10);
  sk.engine.addLine(20, 10, 0, 10);
  sk.engine.addLine(0, 10, 0, 0);
  sk.refresh();
  p.appendChildSketch(ChildSketch(sk, 'xy', null, true, false, p.nextSeq()));
  for (var i = 1; i <= bodies; i++) {
    final f = ExtrudeFeature(
      name: 'Extrusion$i',
      bodyName: 'Solid$i',
      sketchName: 'Sketch1',
      profiles: [ProfileSel(10, 5, 200)],
      distanceA: depth * i,
      extent: FeatureExtent.distance,
    )..output = 'new';
    f.seq = p.nextSeq();
    p.appendFeature(f);
    p.claimBodyName(f.bodyName);
  }
  expect(recomputeAllFeatures(p, app.partKernel), isTrue,
      reason: 'the fixture itself must build');
  await app.savePart(name);
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => L.set(kDe));

  // -------------------------------------------------------------------------
  group('taking a copy out of a sketch', () {
    test('a selection takes its geometry and nothing else', () {
      final (gs, cs) = rectangle();
      final clip = sketchClip(
        geometry: gs,
        constraints: cs,
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {0, 1},
      );
      expect(clip.geometry, hasLength(2));
      expect(clip.count, 2);
      expect(clip.whole, isFalse);
      expect(clip.geometry[0].data, [0, 0, 20, 0]);
    });

    test('the copy is DEEP — editing the source cannot change it', () {
      final (gs, cs) = rectangle();
      final clip = sketchClip(
        geometry: gs,
        constraints: cs,
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
      );
      gs[0].data[2] = 999;
      expect(clip.geometry[0].data[2], 20,
          reason: 'the clipboard must not alias a document being edited');
    });

    test('a constraint comes along only when BOTH ends were selected', () {
      final (gs, cs) = rectangle();
      final clip = sketchClip(
        geometry: gs,
        constraints: cs,
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {0, 1},
      );
      // Of the four corners only 0->1 is wholly inside the selection.
      expect(clip.constraints, hasLength(1));
      expect(clip.constraints[0].pts[0].ent, 0);
      expect(clip.constraints[0].pts[1].ent, 1);
    });

    test('indices are remapped to the clip, not left pointing at the source',
        () {
      final (gs, cs) = rectangle();
      final clip = sketchClip(
        geometry: gs,
        constraints: cs,
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {2, 3},
      );
      expect(clip.constraints, hasLength(1));
      expect(clip.constraints[0].pts.map((p) => p.ent), [0, 1],
          reason: 'entity 2 became 0 and entity 3 became 1');
    });

    test('a coincidence against the projected centre point survives', () {
      final (gs, _) = rectangle();
      final clip = sketchClip(
        geometry: gs,
        constraints: [
          Constraint(CType.coincident, pts: [const PRef(0, 0), PRef(kProjCenter, 0)])
        ],
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {0},
      );
      expect(clip.constraints, hasLength(1),
          reason: 'every sketch has an origin, so the reference still means '
              'what it said');
      expect(clip.constraints[0].pts[1].ent, kProjCenter);
    });

    test('a projection whose source did not come along stops being one', () {
      final (gs, _) = rectangle();
      gs[1] = gs[1].withProj(0); // projection OF entity 0
      final clip = sketchClip(
        geometry: gs,
        constraints: const [],
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {1}, // ...and 0 is left behind
      );
      expect(clip.geometry[0].isProjection, isFalse,
          reason: 'a kept tag would point at whatever occupies index 0 in the '
              'sketch it lands in');
    });

    test('a projection whose source DID come along is remapped', () {
      final (gs, _) = rectangle();
      gs[3] = gs[3].withProj(1);
      final clip = sketchClip(
        geometry: gs,
        constraints: const [],
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {1, 3},
      );
      expect(clip.geometry[1].proj, 0);
    });

    test('an AXIS projection is kept — every sketch has axes', () {
      final (gs, _) = rectangle();
      gs[0] = gs[0].withProj(Geo.projAxisX);
      final clip = sketchClip(
        geometry: gs,
        constraints: const [],
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {0},
      );
      expect(clip.geometry[0].proj, Geo.projAxisX);
    });

    test('only the layers the copied geometry actually sits on travel', () {
      final (gs, cs) = rectangle();
      gs[0] = gs[0].onLayer('Layer 2');
      final clip = sketchClip(
        geometry: gs,
        constraints: cs,
        layers: const ['Layer 1', 'Layer 2', 'Layer 3'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {0},
      );
      expect(clip.layers, ['Layer 2']);
    });

    test('a partial copy leaves texts, pictures and parameters behind', () {
      final (gs, cs) = rectangle();
      final clip = sketchClip(
        geometry: gs,
        constraints: cs,
        layers: const ['Layer 1'],
        sourceDoc: 'Doc',
        sourceSketch: 'Doc',
        entities: {0},
        texts: [SketchText('Hello', 1, 2)],
      );
      expect(clip.texts, isEmpty,
          reason: 'a selection of entities says nothing about which text the '
              'user also meant');
    });
  });

  // -------------------------------------------------------------------------
  group('merging a copy back in', () {
    test('the pasted entities are the TAIL, and are reported as such', () {
      final (gs, cs) = rectangle();
      final clip = sketchClip(
          geometry: gs,
          constraints: cs,
          layers: const ['Layer 1'],
          sourceDoc: 'A',
          sourceSketch: 'A');
      final target = [Geo(Geo.circle, [0, 0, 5], layer: 'Layer 1')];
      final res = mergeSketchClip(
          geometry: target, constraints: const [], clip: clip);
      expect(res.geometry, hasLength(5));
      expect(res.pasted, [1, 2, 3, 4]);
      expect(res.constraints, hasLength(4));
      expect(res.constraints[0].pts[0].ent, 1,
          reason: 'entity 0 of the clip is entity 1 of the target');
    });

    test('a delta moves the geometry and the dimension text with it', () {
      final (gs, _) = rectangle();
      final dim = Constraint(CType.dimension,
          pts: [const PRef(0, 0), const PRef(0, 1)],
          value: 20,
          dimKind: 'dist',
          textPos: const Offset(10, -5));
      final clip = sketchClip(
          geometry: gs,
          constraints: [dim],
          layers: const ['Layer 1'],
          sourceDoc: 'A',
          sourceSketch: 'A');
      final res = mergeSketchClip(
          geometry: const [],
          constraints: const [],
          clip: clip,
          delta: const Offset(100, 50));
      expect(res.geometry[0].data, [100, 50, 120, 50]);
      expect(res.constraints[0].textPos, const Offset(110, 45));
    });

    test('a Fix anchor is re-read off the geometry it now pins', () {
      final gs = [
        Geo(Geo.circle, [0, 0, 5], layer: 'Layer 1'),
      ];
      final clip = sketchClip(
          geometry: gs,
          constraints: [
            Constraint(CType.fix, ents: const [0], anchors: const [0, 0, 5])
          ],
          layers: const ['Layer 1'],
          sourceDoc: 'A',
          sourceSketch: 'A');
      final res = mergeSketchClip(
          geometry: const [],
          constraints: const [],
          clip: clip,
          delta: const Offset(3, 4));
      expect(res.constraints[0].anchors, [3, 4, 5],
          reason: 'the anchor follows the circle, and the RADIUS is not a '
              'coordinate');
    });

    test('a colliding parameter name renames the INCOMING dimension', () {
      final (gs, _) = rectangle();
      final clip = sketchClip(
          geometry: gs,
          constraints: [
            Constraint(CType.dimension,
                pts: [const PRef(0, 0), const PRef(0, 1)],
                value: 20,
                dimKind: 'dist',
                paramName: 'd0')
          ],
          layers: const ['Layer 1'],
          sourceDoc: 'A',
          sourceSketch: 'A');
      final res = mergeSketchClip(
          geometry: const [],
          constraints: const [],
          clip: clip,
          takenNames: {'d0'});
      expect(res.renamedParams, {'d0': 'd1'});
      expect(res.constraints[0].paramName, 'd1');
    });

    test('an expression follows the rename', () {
      final (gs, _) = rectangle();
      final clip = sketchClip(
          geometry: gs,
          constraints: [
            Constraint(CType.dimension,
                pts: [const PRef(0, 0), const PRef(0, 1)],
                value: 20,
                dimKind: 'dist',
                paramName: 'd0'),
            Constraint(CType.dimension,
                pts: [const PRef(1, 0), const PRef(1, 1)],
                value: 40,
                dimKind: 'dist',
                paramName: 'd9',
                expr: 'd0 * 2'),
          ],
          layers: const ['Layer 1'],
          sourceDoc: 'A',
          sourceSketch: 'A');
      final res = mergeSketchClip(
          geometry: const [],
          constraints: const [],
          clip: clip,
          takenNames: {'d0'});
      expect(res.constraints[1].expr, 'd1 * 2');
      expect(res.droppedExpressions, 0);
    });

    test('an expression whose parameter stayed behind is dropped, not guessed',
        () {
      final (gs, _) = rectangle();
      final clip = sketchClip(
          geometry: gs,
          constraints: [
            Constraint(CType.dimension,
                pts: [const PRef(0, 0), const PRef(0, 1)],
                value: 20,
                dimKind: 'dist',
                paramName: 'd5',
                expr: 'width / 2')
          ],
          layers: const ['Layer 1'],
          sourceDoc: 'A',
          sourceSketch: 'A');
      final res = mergeSketchClip(
          geometry: const [], constraints: const [], clip: clip);
      expect(res.constraints[0].expr, isNull);
      expect(res.constraints[0].value, 20, reason: 'the VALUE is kept');
      expect(res.droppedExpressions, 1);
    });

    test('a forced layer takes every pasted entity, whatever it was drawn on',
        () {
      final (gs, cs) = rectangle(layer: 'Layer 1');
      final clip = sketchClip(
          geometry: gs,
          constraints: cs,
          layers: const ['Layer 1'],
          sourceDoc: 'A',
          sourceSketch: 'A');
      final res = mergeSketchClip(
          geometry: const [],
          constraints: const [],
          clip: clip,
          layer: 'Layer 7');
      expect(res.geometry.every((g) => g.layer == 'Layer 7'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('part of a sketch, between two sketches', () {
    test('copy, switch document, paste — at the same coordinates', () async {
      final app = freshApp('ipc_m345_two');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0, 1]);
      expect(app.copySelection(), isTrue);
      expect(app.clipboard, isA<SketchClip>());

      await rectSketchDoc(app, 'B', w: 4, h: 4);
      final before = app.current!.geometry.length;
      expect(await app.paste(), 2);
      final s = app.current!;
      expect(s.geometry, hasLength(before + 2));
      expect(s.geometry[before].data, [0, 0, 20, 0],
          reason: 'a paste keeps the coordinates it was copied from');
    });

    test('what arrived is SELECTED, so the next gesture moves it', () async {
      final app = freshApp('ipc_m345_sel');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0, 1]);
      app.copySelection();
      await rectSketchDoc(app, 'B');
      await app.paste();
      expect(app.selection, {4, 5});
    });

    test('paste lands on the layer being edited', () async {
      final app = freshApp('ipc_m345_layer');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]);
      app.copySelection();
      await rectSketchDoc(app, 'B');
      app.startNewLayer(); // Layer 2, now the editing layer
      expect(app.editingLayer, 'Layer 2');
      await app.paste();
      expect(app.current!.geometry.last.layer, 'Layer 2');
    });

    test('cut copies and then removes the original', () async {
      final app = freshApp('ipc_m345_cut');
      final s = await rectSketchDoc(app, 'A');
      app.selection.addAll([0, 1]);
      expect(app.copySelection(cut: true), isTrue);
      expect(s.geometry, hasLength(2));
      expect(app.clipboard, isA<SketchClip>());
      expect((app.clipboard! as SketchClip).count, 2);
    });

    test('paste here puts the middle of the copy under the cursor', () async {
      final app = freshApp('ipc_m345_here');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]); // the line (0,0)-(20,0), centre (10,0)
      app.copySelection();
      await rectSketchDoc(app, 'B');
      await app.pasteHere(const Offset(100, 100));
      final g = app.current!.geometry.last;
      expect(g.data[0], closeTo(90, 1e-9));
      expect(g.data[1], closeTo(100, 1e-9));
      expect(g.data[2], closeTo(110, 1e-9));
    });

    test('the same clip pastes twice', () async {
      final app = freshApp('ipc_m345_twice');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]);
      app.copySelection();
      await rectSketchDoc(app, 'B');
      expect(await app.paste(), 1);
      expect(await app.paste(), 1);
      expect(app.current!.geometry, hasLength(6));
    });

    test('paste with an empty clipboard says so and changes nothing',
        () async {
      final app = freshApp('ipc_m345_empty');
      await rectSketchDoc(app, 'A');
      expect(await app.paste(), 0);
      expect(app.current!.geometry, hasLength(4));
    });
  });

  // -------------------------------------------------------------------------
  group('a sketch onto a plane of a part', () {
    test('paste in a part with no plane named ARMS the plane pick', () async {
      final app = freshApp('ipc_m345_arm');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0, 1, 2, 3]);
      app.copySelection();
      await partWithBody(app, 'Bracket');
      expect(await app.paste(), 0);
      expect(app.pastingOntoPlane, isTrue);
      expect(app.pickPlane, isTrue, reason: 'the viewport is waiting for a tap');
    });

    test('the tapped plane becomes a NEW sketch holding the copy', () async {
      final app = freshApp('ipc_m345_onplane');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0, 1, 2, 3]);
      app.copySelection();
      final p = await partWithBody(app, 'Bracket');
      final before = p.childSketches.length;
      await app.paste();
      app.planePicked('yz');
      expect(p.childSketches, hasLength(before + 1));
      final made = p.childSketches.last;
      expect(made.plane, 'yz');
      expect(made.model.geometry, hasLength(4));
      expect(app.pastingOntoPlane, isFalse);
      expect(app.pickPlane, isFalse);
    });

    test('it does NOT open the 2D editor — the sketch arrives finished',
        () async {
      final app = freshApp('ipc_m345_noedit');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0, 1, 2, 3]);
      app.copySelection();
      await partWithBody(app, 'Bracket');
      await app.paste();
      app.planePicked('xy');
      expect(app.activeChild, isNull);
      expect(app.inEditMode, isFalse);
    });

    test('the browser route needs no pick at all', () async {
      final app = freshApp('ipc_m345_browserplane');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0, 1]);
      app.copySelection();
      final p = await partWithBody(app, 'Bracket');
      expect(app.pasteSketchOnto('xz'), 2);
      expect(p.childSketches.last.plane, 'xz');
    });

    test('Esc puts an armed paste down', () async {
      final app = freshApp('ipc_m345_escape');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]);
      app.copySelection();
      await partWithBody(app, 'Bracket');
      await app.paste();
      expect(app.pastingOntoPlane, isTrue);
      app.escape3D();
      expect(app.pastingOntoPlane, isFalse);
      expect(app.pickPlane, isFalse);
    });

    test('a whole child sketch copies and pastes onto another plane',
        () async {
      final app = freshApp('ipc_m345_child');
      final p = await partWithBody(app, 'Bracket');
      expect(app.copyChildSketch('Sketch1'), isTrue);
      final clip = app.clipboard! as SketchClip;
      expect(clip.whole, isTrue);
      expect(clip.plane, 'xy');
      expect(app.pasteSketchOnto('yz'), 4);
      expect(p.childSketches, hasLength(2));
      expect(p.childSketches.last.model.name, 'Sketch2',
          reason: 'the pasted sketch takes the part\'s next name');
    });

    test('a sketch pasted into an ASSEMBLY says where it does go', () async {
      final app = freshApp('ipc_m345_asmsketch');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]);
      app.copySelection();
      expect(await app.createNamedAssembly('Frame'), isTrue);
      expect(await app.paste(), 0);
      expect(app.message, isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the two conversions', () {
    test('a 2D document becomes a part whose first sketch is it', () async {
      final app = freshApp('ipc_m345_topart');
      await rectSketchDoc(app, 'Plate');
      await app.saveSketch('Plate');

      final made = await app.partFromSketch('Plate');
      expect(made, isNotNull);
      expect(app.isPartName(made!), isTrue);
      final p = app.parts[made]!;
      expect(p.childSketches, hasLength(1));
      expect(p.childSketches[0].plane, 'xy');
      expect(p.childSketches[0].model.geometry, hasLength(4));
      expect(app.curTab, made, reason: 'the part you asked for is opened');
    });

    test('...and the sketch document is left exactly where it was', () async {
      final app = freshApp('ipc_m345_topart_keep');
      await rectSketchDoc(app, 'Plate');
      await app.saveSketch('Plate');
      await app.partFromSketch('Plate');
      expect(app.sketchNameExists('Plate'), isTrue);
      expect(app.sketches['Plate']!.geometry, hasLength(4));
    });

    test('the part is named after the sketch, and does not collide', () async {
      final app = freshApp('ipc_m345_topart_name');
      await rectSketchDoc(app, 'Plate');
      await app.saveSketch('Plate');
      final a = await app.partFromSketch('Plate');
      final b = await app.partFromSketch('Plate');
      expect(a, 'Plate 2', reason: '"Plate" is taken by the sketch itself');
      expect(b, 'Plate 3');
    });

    test('a sketch inside a part becomes a 2D document of its own', () async {
      final app = freshApp('ipc_m345_todoc');
      final p = await partWithBody(app, 'Bracket');
      final made = await app.sketchDocumentFromChild('Sketch1');
      expect(made, 'Bracket Sketch1',
          reason: 'the gallery is one shelf — the card has to say where it '
              'came from');
      expect(app.sketches[made]!.geometry, hasLength(4));
      expect(app.curTab, made);
      expect(p.childSketches, hasLength(1),
          reason: 'the part keeps its own — features are built on it');
    });
  });

  // -------------------------------------------------------------------------
  group('a solid body', () {
    test('copying writes a STEP the paste can read later', () async {
      final app = freshApp('ipc_m345_bodycopy');
      await partWithBody(app, 'Bracket');
      expect(app.copyBody('Solid1'), isTrue);
      final clip = app.clipboard! as BodyClip;
      expect(File(clip.stepPath).existsSync(), isTrue);
      expect(clip.sourceDoc, 'Bracket');
      expect(clip.bodyName, 'Solid1');
    });

    test('a kernel that cannot write one refuses the copy out loud', () async {
      final app = freshApp('ipc_m345_bodyfail');
      await partWithBody(app, 'Bracket');
      (app.partKernel as FileKernel).refuseExport = true;
      expect(app.copyBody('Solid1'), isFalse);
      expect(app.clipboard, isNull,
          reason: 'a clipboard holding a body that cannot be pasted is worse '
              'than a copy that failed');
    });

    test('pasting into another part adds an imported body', () async {
      final app = freshApp('ipc_m345_bodypaste');
      await partWithBody(app, 'Bracket', depth: 7);
      app.copyBody('Solid1');
      final target = await partWithBody(app, 'Housing', depth: 3);
      await app.openPart('Housing');
      final before = target.features.length;

      expect(await app.paste(), 1);
      expect(target.features, hasLength(before + 1));
      final f = target.features.last as ExtrudeFeature;
      expect(f.imported, isTrue);
      expect(f.importPath, startsWith('imports/'),
          reason: 'it has to be re-readable after a restart');
      expect(f.solid, isNotNull);
      expect(f.solid!.volume, 7, reason: 'the body that was copied');
      expect(f.bodyName, isNot('Solid1'),
          reason: 'the target already had a Solid1');
    });

    test('the copy outlives the document it came from', () async {
      final app = freshApp('ipc_m345_bodyoutlives');
      await partWithBody(app, 'Bracket', depth: 5);
      app.copyBody('Solid1');
      await app.closeTab('Bracket');
      await app.deletePart('Bracket');

      final target = await partWithBody(app, 'Housing');
      await app.openPart('Housing');
      expect(await app.paste(), 1);
      expect((target.features.last as ExtrudeFeature).solid!.volume, 5);
    });

    test('cut removes the body from the part it was cut from', () async {
      final app = freshApp('ipc_m345_bodycut');
      final p = await partWithBody(app, 'Bracket', bodies: 2);
      expect(p.features, hasLength(2));
      expect(app.copyBody('Solid1', cut: true), isTrue);
      expect(p.features.any((f) => f.bodyName == 'Solid1'), isFalse);
      expect(app.clipboard, isA<BodyClip>());
    });

    test('pasted into an assembly it becomes a part AND a component',
        () async {
      final app = freshApp('ipc_m345_bodyasm');
      await partWithBody(app, 'Bracket');
      app.copyBody('Solid1');
      expect(await app.createNamedAssembly('Frame'), isTrue);

      expect(await app.paste(), 1);
      final a = app.currentAssembly!;
      expect(a.occurrences, hasLength(1));
      expect(app.isPartName(a.occurrences.first.source), isTrue,
          reason: 'an assembly holds components, so a body has to become a '
              'part document on the way in');
    });

    test('pasted in the gallery it becomes a part document', () async {
      final app = freshApp('ipc_m345_bodygallery');
      await partWithBody(app, 'Bracket');
      app.copyBody('Solid1');
      await app.closeTab('Bracket');
      expect(app.isHome, isTrue);
      expect(await app.paste(), 1);
      expect(app.isPartName('Solid1'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('components and documents', () {
    test('a component pastes as a second occurrence of the same part',
        () async {
      final app = freshApp('ipc_m345_comp');
      await partWithBody(app, 'Bracket');
      expect(await app.createNamedAssembly('Frame'), isTrue);
      final first = await app.placeComponent('Bracket');
      expect(first, isNotNull);
      expect(app.copyComponent(first!), isTrue);

      expect(await app.paste(), 1);
      final a = app.currentAssembly!;
      expect(a.occurrences, hasLength(2));
      expect(a.occurrences[1].source, 'Bracket');
      expect(a.occurrences[1].id, isNot(a.occurrences[0].id));
    });

    test('...and into a DIFFERENT assembly', () async {
      final app = freshApp('ipc_m345_comp2');
      await partWithBody(app, 'Bracket');
      await app.createNamedAssembly('Frame');
      final o = await app.placeComponent('Bracket');
      app.copyComponent(o!);
      await app.createNamedAssembly('Rig');
      expect(await app.paste(), 1);
      expect(app.currentAssembly!.name, 'Rig');
      expect(app.currentAssembly!.occurrences.single.source, 'Bracket');
    });

    test('a component pasted outside an assembly says where it belongs',
        () async {
      final app = freshApp('ipc_m345_comp3');
      await partWithBody(app, 'Bracket');
      await app.createNamedAssembly('Frame');
      final o = await app.placeComponent('Bracket');
      app.copyComponent(o!);
      await app.openPart('Bracket');
      expect(await app.paste(), 0);
    });

    test('a document copied in the gallery pastes as a duplicate', () async {
      final app = freshApp('ipc_m345_doc');
      await rectSketchDoc(app, 'Plate');
      await app.saveSketch('Plate');
      await app.closeTab('Plate');
      expect(app.copyDocument('Plate'), isTrue);
      expect(await app.paste(), 1);
      expect(app.docNameExists('Plate copy'), isTrue);
    });

    test('a sketch DOCUMENT pastes into an open sketch as geometry', () async {
      final app = freshApp('ipc_m345_docintosketch');
      await rectSketchDoc(app, 'Plate');
      await app.saveSketch('Plate');
      app.copyDocument('Plate');
      await rectSketchDoc(app, 'Other', w: 2, h: 2);
      expect(await app.paste(), 4);
      expect(app.current!.geometry, hasLength(8));
    });

    test('a PART pasted into a part is derived — a link, and it says so',
        () async {
      final app = freshApp('ipc_m345_derive');
      await partWithBody(app, 'Bracket', depth: 9);
      await app.closeTab('Bracket');
      expect(app.copyDocument('Bracket'), isTrue);
      final target = await partWithBody(app, 'Housing');
      await app.openPart('Housing');

      expect(await app.paste(), 1);
      final link = target.features.last;
      expect(link, isA<DeriveFeature>());
      expect((link as DeriveFeature).sourceDoc, 'Bracket');
    });

    test('a part cannot be derived from itself', () async {
      final app = freshApp('ipc_m345_selfderive');
      await partWithBody(app, 'Bracket');
      app.copyDocument('Bracket');
      expect(await app.paste(), 0);
    });
  });

  // -------------------------------------------------------------------------
  group('where the commands are', () {
    test('the quick bar grows Copy/Cut with a selection', () async {
      final app = freshApp('ipc_m345_bar');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]);
      final ids = [for (final i in buildQuickTools(app)) i.id];
      expect(ids, contains(QuickToolId.copy));
      expect(ids, contains(QuickToolId.cut));
      expect(ids, isNot(contains(QuickToolId.paste)),
          reason: 'nothing has been copied yet');
    });

    test('...and Paste the moment there is something to paste', () async {
      final app = freshApp('ipc_m345_bar2');
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]);
      app.copySelection();
      final ids = [for (final i in buildQuickTools(app)) i.id];
      expect(ids, contains(QuickToolId.paste));
    });

    test('the bar carries the clipboard in a PART too', () async {
      final app = freshApp('ipc_m345_bar3');
      await partWithBody(app, 'Bracket');
      app.selectBody('Solid1');
      final ids = [for (final i in buildQuickTools(app)) i.id];
      expect(ids, contains(QuickToolId.copy));
      expect(ids, contains(QuickToolId.cut));
    });

    test('a body row offers Copy and Cut', () {
      final ids = [
        for (final section in nb.clipSection('bdCopy', 'bdCut'))
          section.id
      ];
      expect(ids, ['bdCopy', 'bdCut']);
    });

    test('a plane row offers Paste Sketch Here only with a sketch on the '
        'clipboard', () async {
      final app = freshApp('ipc_m345_planerow');
      expect(nb.pasteSketchSection(app), isEmpty);
      await rectSketchDoc(app, 'A');
      app.selection.addAll([0]);
      app.copySelection();
      expect([for (final i in nb.pasteSketchSection(app)) i.id],
          ['pasteSketch']);
    });

    test('a sketch card offers "Create Part from Sketch"; a part card does not',
        () {
      final t = L.current;
      final sketchIds = [
        for (final g in sketchMenuGroups(t, isSketch: true))
          for (final i in g) i.id
      ];
      final partIds = [
        for (final g in sketchMenuGroups(t))
          for (final i in g) i.id
      ];
      expect(sketchIds, contains('toPart'));
      expect(sketchIds, contains('copy'));
      expect(partIds, contains('copy'));
      expect(partIds, isNot(contains('toPart')));
    });

    test('the gallery + grows a Paste entry only when something is on the '
        'clipboard', () {
      final t = L.current;
      expect([for (final i in newDocMenuItems(t)) i.id],
          isNot(contains('paste')));
      expect([for (final i in newDocMenuItems(t, canPaste: true)) i.id],
          contains('paste'));
    });

    test('canPaste follows the document, not the payload alone', () async {
      final app = freshApp('ipc_m345_canpaste');
      await partWithBody(app, 'Bracket');
      await app.createNamedAssembly('Frame');
      final o = await app.placeComponent('Bracket');
      app.copyComponent(o!);
      expect(app.canPaste, isTrue, reason: 'a component, in an assembly');
      await app.openPart('Bracket');
      expect(app.canPaste, isFalse, reason: 'a component, in a part');
    });
  });

  // -------------------------------------------------------------------------
  group('a layer is a thing to copy and a place to paste into', () {
    test('copying a layer takes everything on it', () async {
      final app = freshApp('ipc_m345_lycopy');
      await rectSketchDoc(app, 'A');
      expect(app.copyLayer('Layer 1'), isTrue);
      expect((app.clipboard! as SketchClip).count, 4);
    });

    test('pasting into a named layer ignores which one is being edited',
        () async {
      final app = freshApp('ipc_m345_lypaste');
      await rectSketchDoc(app, 'A');
      app.copyLayer('Layer 1');
      app.startNewLayer(); // Layer 2 is now the editing layer
      expect(app.pasteIntoLayer('Layer 1'), 4);
      expect(app.current!.geometry.last.layer, 'Layer 1');
    });
  });
}
