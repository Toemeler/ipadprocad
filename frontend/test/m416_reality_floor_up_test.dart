// M416 — #35: "when i set a new view as front, the placing of the bottom
// plane in rendered mode should change too."
//
// M403 fixed this for the Cycles/Windows floor. This is the same fix for the
// RealityKit floor on iOS/iPadOS, which is the app's primary platform and was
// left untouched by M403 (that commit says so explicitly): the ViewCube's
// orientation is the document's answer to "which way is up", and the rendered
// floor has to be built from it rather than from world +Y.
//
// The RealityKit render itself is device-only and cannot be asserted from
// here — same boundary M286's tests describe. What CAN be pinned, and what
// this file pins, is the Dart side of it: the `'up'` key reaches the scene
// payload, for both a part and an assembly, carrying exactly what the
// ViewCube's orientation says "up" is.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/part_model.dart' show Vec3;
import 'package:prototype/quat.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/reality_scene.dart';

AppState _app() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m414_');
  return a;
}

void main() {
  group('realityUpAxis / assemblyUpAxis', () {
    test('identity is world +Y — every document that never redefined front',
        () {
      expect(realityUpAxis(Quat.identity).y, closeTo(1, 1e-9));
      expect(assemblyUpAxis(Quat.identity).y, closeTo(1, 1e-9));
    });

    test('a quarter turn about X takes +Y onto -Z, the same as cyclesUpAxis',
        () {
      // "the top is now the front": Quat.axisAngle(X, -pi/2) is what M399's
      // ViewCube math already uses for exactly that reorientation.
      final q = Quat.axisAngle(const Vec3(1, 0, 0), -1.5707963267948966);
      final up = realityUpAxis(q);
      expect(up.z, closeTo(-1, 1e-6));
      expect(up.x.abs(), lessThan(1e-6));
      expect(up.y.abs(), lessThan(1e-6));
      expect(assemblyUpAxis(q).z, closeTo(-1, 1e-6));
    });

    test('always unit length, whatever the input quaternion', () {
      final q = Quat.axisAngle(const Vec3(1, 1, 1).normalized(), 0.7);
      expect(realityUpAxis(q).length, closeTo(1, 1e-9));
    });
  });

  group('buildScenePayload', () {
    test('the up key is [0, 1, 0] for a document that never redefined front',
        () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      final up = buildScenePayload(app, p)['up'] as List;
      expect(up, [0.0, 1.0, 0.0]);
    });

    test('and follows the ViewCube once front is redefined', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      p.cubeOrient = Quat.axisAngle(const Vec3(1, 0, 0), -1.5707963267948966);
      final up = (buildScenePayload(app, p)['up'] as List).cast<double>();
      expect(up[0], closeTo(0, 1e-6));
      expect(up[1], closeTo(0, 1e-6));
      expect(up[2], closeTo(-1, 1e-6));
    });
  });

  group('buildAssemblyScenePayload', () {
    test('the up key is [0, 1, 0] by default', () {
      final a = AssemblyModel('A');
      expect(buildAssemblyScenePayload(a)['up'], [0.0, 1.0, 0.0]);
    });

    test('and follows the ViewCube once front is redefined', () {
      final a = AssemblyModel('A')
        ..cubeOrient = Quat.axisAngle(const Vec3(0, 0, 1), 1.5707963267948966);
      final up = (buildAssemblyScenePayload(a)['up'] as List).cast<double>();
      // A quarter turn about Z takes +Y onto -X.
      expect(up[0], closeTo(-1, 1e-6));
      expect(up[1], closeTo(0, 1e-6));
      expect(up[2], closeTo(0, 1e-6));
    });
  });
}
