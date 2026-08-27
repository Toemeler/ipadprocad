// M273 — the second dropdown: how the model is DRAWN.
//
// "there should be a solid with edges mode like right now and there should be
// a rendered mode with actual raytracing shadows, lights and everything. in a
// dropdown right under the material."
//
// The picture itself is RealityKit's and cannot be asserted from here. What
// CAN be, and what these tests are for, is everything around it:
//
//   * the mode reaches the renderer at all. It is one boolean on the scene
//     payload, and it has to be in the scene SIGNATURE too — the signature is
//     what decides whether a heavy push happens, and a mode switch changes
//     every material and adds or removes the whole edge overlay. Without that
//     line the dropdown would move and the viewport would not.
//   * it is remembered per document, and a document nobody switched writes the
//     bytes it always wrote.
//   * an unknown mode in a stored file reads as the working view rather than
//     leaving the document unopenable.
//
// The M272 companion is in here too: an APPEARANCE change on a part had the
// same gap, and a part's light push carries no solid tints at all.
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/display_mode.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/theme.dart';

AppState _app() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m273_');
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(T.resetForTest);
  tearDown(T.resetForTest);

  group('the two modes', () {
    test('the working view is the default and the fallback', () {
      expect(DisplayMode.fallback, DisplayMode.shadedWithEdges);
      expect(PartModel('P').displayMode, DisplayMode.shadedWithEdges);
      expect(AssemblyModel('A').displayMode, DisplayMode.shadedWithEdges);
      expect(DisplayMode.shadedWithEdges.isRendered, isFalse);
      expect(DisplayMode.rendered.isRendered, isTrue);
    });

    test('ids round-trip and are stable strings, not enum indices', () {
      // Stored in documents, so a reorder of the enum must not repaint every
      // saved part.
      expect(DisplayMode.shadedWithEdges.id, 'shaded');
      expect(DisplayMode.rendered.id, 'rendered');
      for (final m in DisplayMode.values) {
        expect(DisplayMode.byId(m.id), m);
      }
      expect(DisplayMode.byId('pathtraced'), isNull);
      expect(DisplayMode.byId(null), isNull);
    });

    test('both modes are named in the ARB, in both languages', () {
      for (final l in [const Locale('de'), const Locale('en')]) {
        final t = L.stringsFor(l);
        final names = [for (final m in DisplayMode.values) displayModeName(t, m)];
        for (final n in names) {
          expect(n, isNotEmpty);
        }
        expect(names.toSet().length, names.length);
      }
    });

    test('the rendered row does NOT promise ray tracing', () {
      // RealityKit rasterises and shadow-maps. iOS exposes no "render this
      // with the ray tracing units" switch, so a row that said so would be a
      // promise the renderer cannot keep — and this app does not make those.
      for (final l in [const Locale('de'), const Locale('en')]) {
        final n = displayModeName(L.stringsFor(l), DisplayMode.rendered)
            .toLowerCase();
        expect(n, isNot(contains('ray')));
        expect(n, isNot(contains('trac')));
      }
    });
  });

  group('a document remembers it', () {
    test('a part nobody switched writes what it always wrote', () {
      expect(PartModel('P').toJson().containsKey('view'), isFalse);
      expect(AssemblyModel('A').toJson().containsKey('view'), isFalse);
    });

    test('switched, it round-trips — part and assembly', () {
      final p = PartModel('P')..displayMode = DisplayMode.rendered;
      expect(p.toJson()['view'], 'rendered');
      expect((PartModel('P')..loadJson(p.toJson())).displayMode,
          DisplayMode.rendered);

      final a = AssemblyModel('A')..displayMode = DisplayMode.rendered;
      expect(a.toJson()['view'], 'rendered');
      final back = AssemblyModel('A')..loadJson(a.toJson());
      expect(back.displayMode, DisplayMode.rendered);
    });

    test('a mode this build does not offer reads as the working view', () {
      // Not "leave it alone", unlike M270's backdrop swatch: there is nothing
      // to leave it at. A renderer handed an unknown mode draws nothing.
      expect((PartModel('P')..loadJson({'view': 'pathtraced'})).displayMode,
          DisplayMode.shadedWithEdges);
    });
  });

  group('it reaches the renderer', () {
    test('the payload carries one boolean, and only when it is on', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      expect(buildScenePayload(app, p)['render'], isFalse);
      p.displayMode = DisplayMode.rendered;
      expect(buildScenePayload(app, p)['render'], isTrue);
    });

    test('the assembly payload too', () {
      final a = AssemblyModel('A');
      expect(buildAssemblyScenePayload(a)['render'], isFalse);
      a.displayMode = DisplayMode.rendered;
      expect(buildAssemblyScenePayload(a)['render'], isTrue);
    });

    test('the SIGNATURE moves, or the switch would not push', () async {
      // The signature is what decides between the heavy push (meshes,
      // materials, the edge overlay) and the light one. A mode switch is the
      // heaviest rebuild there is and no light push could express it.
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      final before = sceneSignature(app, p);
      p.displayMode = DisplayMode.rendered;
      expect(sceneSignature(app, p), isNot(before));

      final a = AssemblyModel('A');
      final asmBefore = assemblySceneSignature(a);
      a.displayMode = DisplayMode.rendered;
      expect(assemblySceneSignature(a), isNot(asmBefore));
    });

    test('M272 — an APPEARANCE moves the part signature too', () async {
      // Found writing this milestone: a part's light push carries no solid
      // tints at all (only an assembly's does), so a body painted brass kept
      // its old colour until something else happened to move the signature.
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      final before = sceneSignature(app, p);
      p.bodyMaterials['Solid1'] = 'brass';
      expect(sceneSignature(app, p), isNot(before));
    });
  });

  group('the ribbon control has something to act on', () {
    test('a part and an assembly can switch; a sketch cannot', () async {
      final app = _app();
      expect(app.canSetDisplayMode, isFalse); // the gallery
      await app.createNamedPart('P');
      expect(app.canSetDisplayMode, isTrue);
      expect(app.displayMode, DisplayMode.shadedWithEdges);

      app.setDisplayMode(DisplayMode.rendered);
      expect(app.displayMode, DisplayMode.rendered);
      expect(app.currentPart!.displayMode, DisplayMode.rendered);

      // In a sketch there is nothing to light: it is lines on a plane.
      app.startPartSketch();
      app.planePicked('xy');
      expect(app.canSetDisplayMode, isFalse);
    });

    test('setting the mode it already has does nothing', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.currentPart!.dirty = false;
      app.setDisplayMode(DisplayMode.shadedWithEdges);
      expect(app.currentPart!.dirty, isFalse);
    });
  });
}
