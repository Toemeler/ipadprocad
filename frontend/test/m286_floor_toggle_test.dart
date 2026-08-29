// M286 — the "Display floor" checkbox under Appearance ("Aussehen").
//
// The report: a checkbox in the ribbon that hides the floor in RENDERED mode,
// visible only in rendered mode (the working views never draw a floor, so a
// checkbox there would control nothing).
//
// The floor itself is RealityKit's and cannot be asserted from here. What CAN,
// and what these tests pin, is everything on the Dart side of that boundary:
//
//   * the flag reaches the renderer at all — one boolean on the scene payload,
//     for both a part and an assembly, and it must be in the scene SIGNATURE
//     too: toggling the floor is a full re-push of the rendered ground, and
//     without that line the checkbox would move and the viewport would not.
//   * it is remembered per document, and a document nobody touched writes the
//     bytes it always wrote (default "visible" stays implicit, `'floor': false`
//     is only written when it is off).
//   * the AppState toggle switches and persists it, and is a no-op when the
//     flag already has the requested value.
//   * the ribbon only offers the checkbox while `displayMode` is rendered.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/display_mode.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/ribbon.dart';

AppState _app() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m286_');
  return a;
}

AppState _partApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m286');
  app.parts['p'] = PartModel('Part1');
  app.curTab = 'p';
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(T.resetForTest);
  tearDown(T.resetForTest);

  group('the floor is on by default', () {
    test('a part and an assembly start with the floor visible', () {
      expect(PartModel('P').showFloor, isTrue);
      expect(AssemblyModel('A').showFloor, isTrue);
    });
  });

  group('a document remembers it', () {
    test('a part nobody switched writes what it always wrote', () {
      expect(PartModel('P').toJson().containsKey('floor'), isFalse);
      expect(AssemblyModel('A').toJson().containsKey('floor'), isFalse);
    });

    test('hidden, it round-trips — part and assembly', () {
      final p = PartModel('P')..showFloor = false;
      expect(p.toJson()['floor'], isFalse);
      expect((PartModel('P')..loadJson(p.toJson())).showFloor, isFalse);

      final a = AssemblyModel('A')..showFloor = false;
      expect(a.toJson()['floor'], isFalse);
      expect((AssemblyModel('A')..loadJson(a.toJson())).showFloor, isFalse);
    });

    test('the default stays implicit, not written as true', () {
      // Off and back on again writes NO floor key, so a document that only
      // toggled the checkbox is byte-for-byte what a brand new part writes.
      final p = PartModel('P')..showFloor = false;
      p.showFloor = true;
      expect(p.toJson().containsKey('floor'), isFalse);
    });
  });

  group('it reaches the renderer', () {
    test('the payload carries the flag for a part', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      expect(buildScenePayload(app, p)['floor'], isTrue);
      p.showFloor = false;
      expect(buildScenePayload(app, p)['floor'], isFalse);
    });

    test('the assembly payload too', () {
      final a = AssemblyModel('A');
      expect(buildAssemblyScenePayload(a)['floor'], isTrue);
      a.showFloor = false;
      expect(buildAssemblyScenePayload(a)['floor'], isFalse);
    });

    test('the SIGNATURE moves, or the toggle would not push', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      final before = sceneSignature(app, p);
      p.showFloor = false;
      expect(sceneSignature(app, p), isNot(before));

      final a = AssemblyModel('A');
      final asmBefore = assemblySceneSignature(a);
      a.showFloor = false;
      expect(assemblySceneSignature(a), isNot(asmBefore));
    });
  });

  group('the AppState toggle', () {
    test('toggles and remembers it', () async {
      final app = _app();
      expect(app.showFloor, isTrue); // the gallery
      await app.createNamedPart('P');
      expect(app.showFloor, isTrue);

      app.setShowFloor(false);
      expect(app.showFloor, isFalse);
      expect(app.currentPart!.showFloor, isFalse);
    });

    test('setting the value it already has does nothing', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.currentPart!.dirty = false;
      app.setShowFloor(true);
      expect(app.currentPart!.dirty, isFalse);
    });
  });

  group('the ribbon offers it only in rendered mode', () {
    testWidgets('visible when rendered, hidden otherwise', (tester) async {
      L.current = L.stringsFor(const Locale('de'));
      await tester.binding.setSurfaceSize(const Size(1366, 1024));

      final app = _partApp();
      app.currentPart!.displayMode = DisplayMode.rendered;
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Ribbon(app: app))));
      await tester.pump();
      expect(find.text(L.stringsFor(const Locale('de')).viewFloor),
          findsOneWidget);

      app.currentPart!.displayMode = DisplayMode.shadedWithEdges;
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Ribbon(app: app))));
      await tester.pump();
      expect(find.text(L.stringsFor(const Locale('de')).viewFloor),
          findsNothing);
    });
  });
}
