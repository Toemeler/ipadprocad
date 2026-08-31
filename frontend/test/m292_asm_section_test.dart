// M292 — the same section view, on an assembly.
//
// M291 built half / quarter / three-quarter section views for a part and left
// the assembly out for one reason: the pick had to reach a component's faces,
// which is the assembly viewport's hit test rather than the part's. Everything
// else already carried over — and this milestone is mostly the proof of that,
// because the interesting claim is how LITTLE is different:
//
//   * The commands, the modes, the flips and the offsets are one value on two
//     document types. AppState.documentSection is the whole of the routing,
//     and every command reads and writes it — the way displayMode already
//     does. Nothing about SectionView, SectionMode or SectionPlane is
//     assembly-aware.
//   * The cut is the same function. sectionCutSolid takes the model's padded
//     extent rather than a PartModel, so a part hands it originExtentBounds
//     and an assembly hands it paddedOriginExtent(assemblyContentBounds).
//   * The pick is the assembly's own. pickAsmRef — the hit test Mate and the
//     work features already use — answers with a PLANE for a planar face and
//     for the three origin planes, which is exactly "pick any plane or planar
//     face" on this side.
//
// The ONE thing that is genuinely new is the frame transport. An assembly's
// section plane is one plane in world space, but each component's solid lives
// in its own frame, so the cut brings the plane to the solid instead of the
// solid to the plane: one transform per component rather than one per
// triangle, and the placement of the result is exactly what it was. That, and
// what it means for two occurrences of the same part, is what most of this
// file is about.
//
// The boolean itself needs OCCT and does not run on this host.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/section_view.dart';

KernelSolid _box(double s) {
  final pos = <double>[], nor = <double>[], idx = <int>[];
  void quad(List<List<double>> p, List<double> n) {
    final base = pos.length ~/ 3;
    for (final v in p) {
      pos.addAll(v);
      nor.addAll(n);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  quad([
    [0, 0, 0],
    [s, 0, 0],
    [s, s, 0],
    [0, s, 0]
  ], [
    0,
    0,
    -1
  ]);
  quad([
    [0, 0, s],
    [s, 0, s],
    [s, s, s],
    [0, s, s]
  ], [
    0,
    0,
    1
  ]);
  return KernelSolid(
      OcctMeshData(
        Float64List.fromList(pos),
        Float64List.fromList(nor),
        Int32List.fromList(idx),
        Int32List.fromList([0]),
        Float64List(0),
        triFaces: Int32List.fromList(List<int>.filled(idx.length ~/ 3, 0)),
      ),
      s * s * s,
      null);
}

PartModel _boxPart(String name) => PartModel(name)
  ..features.add(ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: 'Sketch1',
      profiles: const [])
    ..solid = _box(10));

/// An assembly of two copies of one part, 40 mm apart.
AppState _asmApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m292');
  final a = AssemblyModel('Rig');
  a.occurrences.add(AssemblyOccurrence(
      id: 'Block:1', source: 'Block', part: _boxPart('Block'),
      offset: Vec3.zero));
  a.occurrences.add(AssemblyOccurrence(
      id: 'Block:2', source: 'Block', part: _boxPart('Block'),
      offset: const Vec3(40, 0, 0)));
  app.assemblies['Rig'] = a;
  app.curTab = 'Rig';
  return app;
}

void main() {
  group('the commands are the same commands', () {
    test('an assembly with components can be sectioned', () {
      final app = _asmApp();
      expect(app.currentAssembly, isNotNull);
      expect(app.canSection, isTrue);
    });

    test('an empty assembly cannot', () {
      final app = AppState();
      app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m292e');
      app.assemblies['Bare'] = AssemblyModel('Bare');
      app.curTab = 'Bare';
      expect(app.canSection, isFalse);
      app.beginSection(SectionMode.half);
      expect(app.sectionPicking, isFalse);
    });

    test('the whole session runs on the assembly', () {
      final app = _asmApp();
      app.beginSection(SectionMode.quarter);
      expect(app.sectionPicking, isTrue);

      app.sectionPlanePicked(planeFrame('xy'), 'XY');
      expect(app.sectionPicking, isTrue, reason: 'still asking');
      expect(app.activeSection, isNull, reason: 'an unfinished view cuts nothing');

      app.sectionPlanePicked(planeFrame('yz'), 'YZ');
      expect(app.currentAssembly!.section?.mode, SectionMode.quarter);
      expect(app.activeSection?.planes.length, 2);

      app.flipSectionPlane(1);
      expect(app.currentAssembly!.section!.planes[1].flipped, isTrue);
      app.setSectionOffset(0, 6);
      expect(app.currentAssembly!.section!.planes[0].offset, 6);

      app.endSection();
      expect(app.currentAssembly!.section, isNull);
      expect(app.activeSection, isNull);
    });

    test('a part and an assembly hold their own', () {
      // documentSection routes on what is OPEN, so switching tabs must find
      // each document still cut the way it was left.
      final app = _asmApp();
      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(planeFrame('xy'), 'XY');

      app.parts['Block'] = _boxPart('Block');
      app.curTab = 'Block';
      expect(app.documentSection, isNull, reason: 'a different document');
      app.beginSection(SectionMode.threeQuarter);
      app.sectionPlanePicked(planeFrame('yz'), 'YZ');
      app.sectionPlanePicked(planeFrame('xz'), 'XZ');
      expect(app.documentSection?.mode, SectionMode.threeQuarter);

      app.curTab = 'Rig';
      expect(app.documentSection?.mode, SectionMode.half,
          reason: 'the assembly kept its own');
    });

    test('it is never written to disk', () {
      final app = _asmApp();
      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(planeFrame('xy'), 'XY');
      final json = app.currentAssembly!.toJson();
      expect(json.toString().contains('section'), isFalse);
    });
  });

  group('the plane travels to the component, not the other way round', () {
    test('a placement moves the plane by exactly its inverse', () {
      final at = Placement(Quat.identity, const Vec3(40, 0, 0));
      final world = planeFrame('yz'); // normal +X through the origin
      final local = sectionFrameInto(world, at);
      // The plane sits 40 mm along -X in the component's own frame, which is
      // where the component's origin sees it.
      expect(local.origin.x, closeTo(-40, 1e-9));
      expect(local.n.x.abs(), closeTo(1, 1e-9));
    });

    test('a rotation turns the normal with it', () {
      final at = Placement(Quat.axisAngle(const Vec3(0, 0, 1), math_pi_2),
          Vec3.zero);
      final local = sectionFrameInto(planeFrame('yz'), at);
      // +X in world is +Y in a component turned a quarter turn about Z... or
      // -Y, depending which way the quarter turn went. What must hold either
      // way is that the normal is a unit vector in the XY plane and no longer
      // along X.
      expect(local.n.z.abs(), closeTo(0, 1e-9));
      expect(local.n.y.abs(), closeTo(1, 1e-9));
      expect(local.n.x.abs(), closeTo(0, 1e-9));
    });

    test('the transported frame is RIGHT-handed, mirrored or not', () {
      // The in-plane axes are rebuilt rather than carried across precisely
      // because a mirrored component's placement reverses handedness, and a
      // left-handed frame handed to PlaneFrame.mat34 builds the cut box
      // mirrored.
      final mirrored = Placement(
          Quat.identity, const Vec3(5, 0, 0), const Vec3(1, 0, 0));
      for (final at in [Placement.identity, mirrored]) {
        for (final key in ['xy', 'yz', 'xz']) {
          final f = sectionFrameInto(planeFrame(key), at);
          final cross = f.u.cross(f.v);
          expect(cross.x, closeTo(f.n.x, 1e-9), reason: '$key');
          expect(cross.y, closeTo(f.n.y, 1e-9), reason: '$key');
          expect(cross.z, closeTo(f.n.z, 1e-9), reason: '$key');
        }
      }
    });

    test('planeFrameAbout has no degenerate axis', () {
      // The seed is whichever world axis is least parallel to the normal, so
      // a plane facing exactly along one of them is not a special case.
      for (final n in [
        const Vec3(1, 0, 0),
        const Vec3(0, 1, 0),
        const Vec3(0, 0, 1),
        const Vec3(-1, 0, 0),
      ]) {
        final f = planeFrameAbout(const Vec3(1, 2, 3), n);
        expect(f.u.dot(f.n).abs(), lessThan(1e-9), reason: '$n');
        expect(f.v.dot(f.n).abs(), lessThan(1e-9), reason: '$n');
        expect(f.u.dot(f.u), closeTo(1, 1e-9), reason: '$n');
        expect(f.v.dot(f.v), closeTo(1, 1e-9), reason: '$n');
      }
    });
  });

  group('two occurrences of one part are cut differently', () {
    test('the same world plane lands in a different place in each', () {
      // THE reason the cut is cached per PIECE and not per mesh. Both
      // occurrences share one PartModel and one mesh; a cache keyed on the
      // mesh alone would hand the second one the first one's cut, and the
      // second block would be sliced as though it stood at the origin.
      final world = planeFrame('yz');
      final one = sectionFrameInto(world, Placement.identity);
      final two = sectionFrameInto(
          world, Placement(Quat.identity, const Vec3(40, 0, 0)));
      expect(one.origin.x, isNot(closeTo(two.origin.x, 1e-6)));
    });
  });

  group('the scene knows the section changed', () {
    test('the assembly signature carries it', () {
      // M95, M122 and M165, once more: a change that is not in the signature
      // sends no rebuild, and a section replaces every mesh in the scene.
      final app = _asmApp();
      final a = app.currentAssembly!;
      final whole = assemblySceneSignature(a, app: app);

      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(planeFrame('xy'), 'XY');
      final cut = assemblySceneSignature(a, app: app);
      expect(cut, isNot(whole));

      app.flipSectionPlane(0);
      expect(assemblySceneSignature(a, app: app), isNot(cut));

      app.endSection();
      expect(assemblySceneSignature(a, app: app), whole);
    });

    test('and a caller that passes no app gets the whole assembly', () {
      // The thumbnail path. A gallery card shows the assembly, not the view
      // state somebody left it in.
      final app = _asmApp();
      final a = app.currentAssembly!;
      final before = assemblySceneSignature(a);
      app.beginSection(SectionMode.half);
      app.sectionPlanePicked(planeFrame('xy'), 'XY');
      expect(assemblySceneSignature(a), before);
      expect(assemblyPieces(a).length, 2);
    });
  });
}

/// A quarter turn, spelled out rather than imported for one use.
const double math_pi_2 = 1.5707963267948966;
