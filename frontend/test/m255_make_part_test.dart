// M255 — Make Part: a solid body becomes a part document, in an assembly, and
// STAYS LINKED to the body it came out of.
//
// "When i longpress a solid there should be a make part option which makes a
// part from this solid and opens it in an assembly. Working just like in
// inventor. Also with a dialog so i can chose a name for the part. But still
// at all times linked to its origin part."
//
// The interesting half is the last clause, and it is the same clause M245 was
// written for one level up ("a part in an assembly should be linked to the
// part at all times"). A command that COPIED the body would pass every test
// you would think to write on the day it shipped: the new part has the right
// shape, it is in the assembly, it is called what you asked for. It becomes
// wrong later, silently, the first time anyone edits the original — and by
// then the document on screen is a lie with nothing on it to click.
//
// So most of this suite is about the link rather than the creation: what
// happens to the derived part when the origin is edited, renamed and deleted.
// The creation tests are here to pin the shape of what is made; the link tests
// are here because they are the ones that can regress without anyone noticing.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';

import 'm56_part_test.dart' show FakeKernel;

/// [FakeKernel] with the one operation Make Part needs: a copy.
///
/// The base fake refuses [placeSolid] — it models no placement, and says so
/// rather than inventing a solid (M212). A derived body IS a placement (the
/// identity), so this suite needs a kernel that can perform one, and counts
/// them: "how many B-Reps did this cost" is the difference between a link that
/// re-reads when the origin moves and one that re-reads on every frame.
class CopyingKernel extends FakeKernel {
  int copies = 0;
  bool canCopy = true;

  @override
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) {
    if (!canCopy) return null;
    copies++;
    lastPlacement = List.of(mat34);
    // A NEW mesh object, as the real kernel returns: the whole staleness
    // machinery downstream is keyed on mesh identity.
    return KernelSolid(
        OcctMeshData(
          Float64List.fromList(s.mesh.positions),
          Float64List.fromList(s.mesh.normals),
          Int32List.fromList(s.mesh.indices),
          Int32List.fromList(s.mesh.edgeStarts),
          Float64List.fromList(s.mesh.edgePoints),
        ),
        s.volume,
        null);
  }

  List<double>? lastPlacement;
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
  app.partKernel = CopyingKernel();
  return app;
}

CopyingKernel kernelOf(AppState app) => app.partKernel as CopyingKernel;

/// A closed rectangle, so an extrusion has a profile to consume.
SketchModel rectSketch(String name) {
  final s = SketchModel(name)..layers.add('Layer 1');
  s.engine.setCurrentLayer('Layer 1');
  s.engine.addLine(0, 0, 20, 0);
  s.engine.addLine(20, 0, 20, 10);
  s.engine.addLine(20, 10, 0, 10);
  s.engine.addLine(0, 10, 0, 0);
  s.refresh();
  return s;
}

/// An origin part with [bodies] solid bodies, each one extrusion off one
/// sketch, built through the kernel.
///
/// Really built, rather than stub solids dropped onto the features by hand.
/// The difference matters here more than it usually would: half this suite is
/// about what the derived part does when the ORIGIN is closed, reopened or
/// renamed, and a part whose geometry only exists because a test put it there
/// comes back from disk with nothing on it — which would make the origin look
/// broken and hide whatever the link actually did.
///
/// [FakeKernel.extrude] returns a solid whose VOLUME is the height it was
/// given, so body i has volume `depth * i` and an edit to a distance is
/// visible as a number.
Future<PartModel> makeOrigin(AppState app, String name,
    {int bodies = 1, double depth = 10}) async {
  expect(await app.createNamedPart(name), isTrue);
  final p = app.parts[name]!;
  p.childSketches.add(ChildSketch(rectSketch('Sketch1'), 'xy'));
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

/// Runs the command as the dialog does: open it on a body, type the two names,
/// press OK.
Future<bool> makePart(AppState app, String body,
    {String? part, String? assembly}) async {
  app.openMakePart(body);
  final s = app.makePartSession;
  expect(s, isNotNull, reason: 'the dialog did not open on "$body"');
  if (part != null) s!.partName = part;
  if (assembly != null) s!.assemblyName = assembly;
  return app.makePart();
}

DeriveFeature? derivedIn(PartModel p) {
  for (final f in p.features) {
    if (f is DeriveFeature) return f;
  }
  return null;
}

/// The model for [name] whether it is open in a tab or shared. Reaches through
/// the same two maps [AppState] does, so a test does not have to know which
/// one is holding it at that moment.
PartModel? modelOf(AppState app, String name) {
  final open = app.parts[name];
  if (open != null) return open;
  for (final a in app.assemblies.values) {
    for (final o in a.occurrences) {
      if (o.source == name && o.part != null) return o.part;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => L.set(kDe));

  // -------------------------------------------------------------------------
  group('what the command makes', () {
    test('a part document holding ONE feature: the link', () async {
      final app = freshApp('ipc_m254_make');
      await makeOrigin(app, 'Bracket');

      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);

      expect(app.isPartName('Web'), isTrue, reason: 'the part is in the gallery');
      final made = modelOf(app, 'Web');
      expect(made, isNotNull);
      expect(made!.features, hasLength(1),
          reason: 'a derived part is its link and nothing else');
      final link = derivedIn(made);
      expect(link, isNotNull, reason: 'the one feature is a DeriveFeature');
      expect(link!.sourceDoc, 'Bracket');
      expect(link.sourceBody, 'Solid1');
      expect(link.name, 'Bracket',
          reason: 'Inventor names the derived node after what it came from');
    });

    test('the derived body is built, and is a COPY rather than the original',
        () async {
      final app = freshApp('ipc_m254_copy');
      final origin = await makeOrigin(app, 'Bracket', depth: 25);
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);

      final link = derivedIn(modelOf(app, 'Web')!)!;
      expect(link.computeError, isNull, reason: link.computeError ?? '');
      expect(link.solid, isNotNull);
      expect(link.solid!.volume, 25, reason: 'the same body');
      expect(link.solid, isNot(same(origin.features.first.solid)),
          reason: 'sharing one B-Rep across two documents would free it under '
              'whichever of them is still drawing');
      expect(kernelOf(app).copies, greaterThan(0));
    });

    test('it is placed in the assembly, at the identity', () async {
      final app = freshApp('ipc_m254_place');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);

      expect(app.curTab, 'Frame', reason: 'the command ends in the assembly');
      final a = app.currentAssembly;
      expect(a, isNotNull);
      expect(a!.occurrences, hasLength(1));
      final o = a.occurrences.single;
      expect(o.source, 'Web');
      expect(o.offset.length, lessThan(1e-9),
          reason: 'the derived body is in the ORIGIN\'s coordinates, so an '
              'untransformed placement puts it exactly where it sat');
      expect(o.rot.w, closeTo(1, 1e-9));
      expect(o.part, isNotNull, reason: 'the component has its geometry');
      expect(derivedIn(o.part!), isNotNull);
    });

    test('the origin keeps its body — nothing is moved out of it', () async {
      final app = freshApp('ipc_m254_keeps');
      final origin = await makeOrigin(app, 'Bracket', bodies: 2);
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);

      expect(origin.features, hasLength(2));
      expect(origin.solidBodies().map((b) => b.$1), ['Solid1', 'Solid2'],
          reason: 'the origin is the master model, not a source of offcuts');
    });

    test('a second body joins the SAME assembly, and it is the default',
        () async {
      final app = freshApp('ipc_m254_second');
      await makeOrigin(app, 'Bracket', bodies: 2);
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      await app.openPart('Bracket');

      // No assembly typed this time: the dialog offers the one the first body
      // went into, which is what makes decomposing a part a workflow rather
      // than an exercise in retyping.
      app.openMakePart('Solid2');
      expect(app.makePartSession!.assemblyName, 'Frame');
      app.makePartSession!.partName = 'Flange';
      expect(await app.makePart(), isTrue);

      final a = app.assemblies['Frame']!;
      expect(a.occurrences.map((o) => o.source), ['Web', 'Flange']);
    });

    test('the suggested part name is the BODY name, as Inventor does it',
        () async {
      final app = freshApp('ipc_m254_suggest');
      await makeOrigin(app, 'Bracket');
      app.renameBody('Solid1', 'Web');

      app.openMakePart('Web');
      expect(app.makePartSession!.partName, 'Web');
    });
  });

  // -------------------------------------------------------------------------
  group('the link', () {
    test('an edit to the origin reaches the derived part, with nothing '
        'propagated', () async {
      final app = freshApp('ipc_m254_live');
      final origin = await makeOrigin(app, 'Bracket', depth: 25);
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      final link = derivedIn(modelOf(app, 'Web')!)!;
      expect(link.solid!.volume, 25);

      // Edit the origin the way the editor does: change the number, rebuild,
      // save. Nothing here touches the derived part, which is the point.
      (origin.features.first as ExtrudeFeature).distanceA = 99;
      expect(recomputeAllFeatures(origin, app.partKernel), isTrue);
      await app.savePart('Bracket');

      expect(link.solid, isNotNull);
      expect(link.solid!.volume, 99,
          reason: 'the derived body IS the origin body, re-read');
    });

    test('an origin that has not moved is not re-copied', () async {
      final app = freshApp('ipc_m254_cheap');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);

      final k = kernelOf(app);
      final was = k.copies;
      for (var i = 0; i < 5; i++) {
        app.refreshDerived();
      }
      expect(k.copies, was,
          reason: 'the build signature carries the origin body\'s identity, so '
              'an unchanged origin must be a cache hit — a link that re-copied '
              'a B-Rep per pass would cost more than a copy ever did');
    });

    test('a re-tessellation of the origin is not a change', () async {
      final app = freshApp('ipc_m254_refine');
      final origin = await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      final k = kernelOf(app);
      final was = k.copies;

      // What the viewport does on every zoom: the SAME KernelSolid, a new mesh
      // inside it. Hashing the mesh would have rebuilt every derived part in
      // the session each time the camera moved.
      origin.features.first.solid!.mesh = stubSolid(1).mesh;
      app.refreshDerived();

      expect(k.copies, was);
    });

    test('deleting the origin makes the derived body sick, by name', () async {
      final app = freshApp('ipc_m254_gone');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      final derived = modelOf(app, 'Web')!;
      expect(derivedIn(derived)!.solid, isNotNull);

      await app.deletePart('Bracket');

      final link = derivedIn(derived)!;
      expect(link.solid, isNull,
          reason: 'a body whose origin is gone must not go on drawing the copy '
              'it happens to be holding');
      expect(link.computeError, isNotNull);
      expect(link.computeError, contains('Bracket'),
          reason: 'the error names what it can no longer read');
    });

    test('renaming the origin follows into the derived part', () async {
      final app = freshApp('ipc_m254_rename');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);

      expect(await app.renamePart('Bracket', 'Support'), isTrue);

      final link = derivedIn(modelOf(app, 'Web')!)!;
      expect(link.sourceDoc, 'Support');
      expect(link.name, 'Support',
          reason: 'a node reading "Bracket" in a session where nothing is '
              'called Bracket any more is worse than no name at all');
      expect(link.computeError, isNull, reason: link.computeError ?? '');
      expect(link.solid, isNotNull, reason: 'and it still builds');
    });

    test('the link survives a close and re-open', () async {
      final app = freshApp('ipc_m254_reopen');
      await makeOrigin(app, 'Bracket', depth: 25);
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      await app.closeTab('Frame');
      await app.closeTab('Bracket');

      await app.openPart('Web');
      final link = derivedIn(app.parts['Web']!)!;
      expect(link.sourceDoc, 'Bracket');
      expect(link.sourceBody, 'Solid1');
      expect(link.computeError, isNull, reason: link.computeError ?? '');
      expect(link.solid, isNotNull,
          reason: 'opening a derived part loads the origin it reads');
      expect(link.solid!.volume, 25);
    });

    test('the origin stays loaded while a derived part needs it', () async {
      final app = freshApp('ipc_m254_retain');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      await app.closeTab('Bracket');

      // The origin is placed by nothing — only READ by the derived part. The
      // model has to survive that or the assembly draws an empty component.
      final o = app.assemblies['Frame']!.occurrences.single;
      expect(derivedIn(o.part!)!.solid, isNotNull);
      expect(derivedIn(o.part!)!.computeError, isNull);
    });

    test('a derived part written to disk carries the reference, not geometry',
        () async {
      final app = freshApp('ipc_m254_json');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);

      final made = modelOf(app, 'Web')!;
      final j = jsonDecode(jsonEncode(made.toJson())) as Map<String, dynamic>;
      final feats = j['features'] as List;
      expect(feats, hasLength(1));
      expect((feats.first as Map)['kind'], 'derive');
      expect((feats.first as Map)['srcDoc'], 'Bracket');
      expect((feats.first as Map)['srcBody'], 'Solid1');

      // And back again, through the dispatching loader every document open
      // goes through.
      final back = PartFeature.fromJson(
          (feats.first as Map).cast<String, dynamic>());
      expect(back, isA<DeriveFeature>());
      expect((back as DeriveFeature).sourceDoc, 'Bracket');
      expect(back.source, isNull,
          reason: 'the MODEL is a runtime object; a document stores the name');
    });

    test('a part made from a DERIVED body follows the whole chain', () async {
      final app = freshApp('ipc_m254_chain');
      await makeOrigin(app, 'Bracket', depth: 25);
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      // Make Part again, this time on the DERIVED part's own body. Inventor
      // allows that, and a chain is where a refresh has to be a fixed point
      // rather than one pass: the walk is over a map, so it can reach the far
      // end of a chain before the middle of it.
      await app.openPart('Web');
      expect(await makePart(app, 'Solid1', part: 'Rib', assembly: 'Frame'),
          isTrue);

      // Reload so the models are walked in the WRONG order — Rib (open, and
      // opened first) before Web (loaded behind it to serve Rib's link). One
      // pass in this order reads Web's old body into Rib and stops.
      for (final t in List<String>.of(app.openTabs)) {
        await app.closeTab(t);
      }
      await app.openPart('Rib');
      await app.openPart('Bracket');
      final origin = app.parts['Bracket']!;
      final end = derivedIn(app.parts['Rib']!)!;
      expect(end.sourceDoc, 'Web');
      expect(end.solid!.volume, 25, reason: end.computeError ?? '');

      (origin.features.first as ExtrudeFeature).distanceA = 77;
      expect(recomputeAllFeatures(origin, app.partKernel), isTrue);
      await app.savePart('Bracket');

      expect(end.solid!.volume, 77,
          reason: 'the far end of the chain is current in the same edit, not '
              'one behind it');
    });

    test('a link with no origin loaded fails honestly rather than empty',
        () async {
      final p = PartModel('Web');
      final f = DeriveFeature(
        name: 'Bracket',
        bodyName: 'Solid1',
        sourceDoc: 'Bracket',
        sourceBody: 'Solid1',
      );
      f.seq = p.nextSeq();
      p.appendFeature(f);

      expect(recomputeAllFeatures(p, CopyingKernel()), isFalse);
      expect(f.solid, isNull);
      expect(f.computeError, contains('Bracket'));
    });

    test('a body that leaves the origin fails by name', () async {
      final app = freshApp('ipc_m254_nobody');
      final origin = await makeOrigin(app, 'Bracket', bodies: 2);
      expect(await makePart(app, 'Solid2', part: 'Web', assembly: 'Frame'),
          isTrue);
      final link = derivedIn(modelOf(app, 'Web')!)!;
      expect(link.solid, isNotNull);

      await app.openPart('Bracket');
      app.deleteBody('Solid2');

      expect(origin.features, hasLength(1));
      expect(link.solid, isNull);
      expect(link.computeError, contains('Solid2'));
    });
  });

  // -------------------------------------------------------------------------
  group('the dialog', () {
    test('opens on the body that was long-pressed and toggles shut', () async {
      final app = freshApp('ipc_m254_toggle');
      await makeOrigin(app, 'Bracket');

      app.openMakePart('Solid1');
      expect(app.makePartSession!.body, 'Solid1');
      app.openMakePart('Solid1');
      expect(app.makePartSession, isNull, reason: 'a toggle, like M210\'s');
    });

    test('long-pressing another body re-opens on THAT one', () async {
      final app = freshApp('ipc_m254_switch');
      await makeOrigin(app, 'Bracket', bodies: 2);

      app.openMakePart('Solid1');
      app.openMakePart('Solid2');
      expect(app.makePartSession?.body, 'Solid2',
          reason: 'a closed dialog with no explanation is not an answer');
    });

    test('a taken part name is refused and NOTHING is created', () async {
      final app = freshApp('ipc_m254_taken');
      await makeOrigin(app, 'Bracket');
      expect(await app.createNamedPart('Web', open: false), isTrue);
      await app.openPart('Bracket');

      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isFalse);
      expect(app.isAssemblyName('Frame'), isFalse,
          reason: 'a name rejected must not leave half a command behind');
      expect(app.makePartSession, isNotNull,
          reason: 'the dialog stays up, on the field that has to be fixed');
    });

    test('an empty name is refused', () async {
      final app = freshApp('ipc_m254_empty');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: '  ', assembly: 'Frame'),
          isFalse);
      expect(app.currentPart?.name, 'Bracket');
    });

    test('a target assembly that is a PART is a collision, not a target',
        () async {
      final app = freshApp('ipc_m254_asmclash');
      await makeOrigin(app, 'Bracket');
      expect(await app.createNamedPart('Frame', open: false), isTrue);
      await app.openPart('Bracket');

      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isFalse);
      expect(app.isPartName('Web'), isFalse);
    });

    test('the command is disarmed by every other 3D command', () async {
      final app = freshApp('ipc_m254_disarm');
      await makeOrigin(app, 'Bracket');
      app.openMakePart('Solid1');
      app.cancel3DCommands();
      expect(app.makePartSession, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the browser row', () {
    test('a derived body is drawn with the link badge, not the plain cube',
        () async {
      final app = freshApp('ipc_m254_icon');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      // The badge is the same one a SHARED sketch carries — the icon language
      // already spells "read from / published to somewhere else" that way.
      expect(derivedIn(modelOf(app, 'Web')!)!.typeLabel, 'Derived');
    });

    test('Edit on a derived body opens the origin instead of nothing',
        () async {
      final app = freshApp('ipc_m254_edit');
      await makeOrigin(app, 'Bracket');
      expect(await makePart(app, 'Solid1', part: 'Web', assembly: 'Frame'),
          isTrue);
      await app.openPart('Web');

      app.editFeature(derivedIn(app.parts['Web']!)!);
      await pumpEventQueue();
      expect(app.curTab, 'Bracket',
          reason: 'there is nothing in a derived body to edit HERE — every '
              'number that decides its shape is a feature of the origin');
    });
  });
}
