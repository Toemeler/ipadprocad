// M344 — the render assets, and the promise that the app works without them.
//
// The HDRI and the PBR texture sets are tens of megabytes and are not in this
// repository. That is deliberate and it is a contract with three sides:
//
//   * this file, which finds whatever is there and answers null for whatever
//     is not;
//   * cycles_shim.cpp, which checks every path again with fopen before it
//     builds a node, because a file can go missing between the scan and the
//     render;
//   * the CI step that copies them into the bundle, which does not fail when
//     the directory is empty.
//
// A build made from a clean clone renders the M332 light rig and the M337 flat
// Principled surfaces — the app that shipped — and that is what most of this
// file is about.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_assets.dart';
import 'package:prototype/cycles_view.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cycles_assets');
    CyclesAssets.instance.resetForTest();
  });

  tearDown(() {
    CyclesAssets.instance.resetForTest();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void put(String relative) {
    final f = File('${root.path}/$relative');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync([0]);
  }

  group('when there is nothing', () {
    test('a build with no asset directory at all is not an error', () {
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.hdri, isNull);
      expect(CyclesAssets.instance.texturesFor('brass').isEmpty, isTrue);
      expect(CyclesAssets.instance.texturesFor(null).isEmpty, isTrue);
    });

    test('a null root — every host test, and any non-iOS platform', () {
      CyclesAssets.instance.scan(null);
      expect(CyclesAssets.instance.hdri, isNull);
    });

    test('an empty directory is the same as no directory', () {
      Directory('${root.path}/$kCyclesAssetDir').createSync(recursive: true);
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.hdri, isNull);
      expect(CyclesAssets.instance.texturesFor('steel').isEmpty, isTrue);
    });
  });

  group('the environment map', () {
    test('is found as .hdr', () {
      put('$kCyclesAssetDir/$kCyclesHdriDir/$kCyclesHdriName.hdr');
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.hdri, endsWith('/studio.hdr'));
    });

    test('.exr is accepted, and .hdr wins when both are there', () {
      // Radiance is about a third the size for a difference nobody can see in
      // a reflection, and the whole file lives in memory while rendered mode
      // is on.
      put('$kCyclesAssetDir/$kCyclesHdriDir/$kCyclesHdriName.exr');
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.hdri, endsWith('.exr'));

      CyclesAssets.instance.resetForTest();
      put('$kCyclesAssetDir/$kCyclesHdriDir/$kCyclesHdriName.hdr');
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.hdri, endsWith('.hdr'));
    });

    test('a file under any other name is not the environment', () {
      // One file, not whatever the directory happens to hold: a studio is a
      // lighting decision, and two of them are two different products.
      put('$kCyclesAssetDir/$kCyclesHdriDir/sunset.hdr');
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.hdri, isNull);
    });
  });

  group('texture sets', () {
    test('every map is optional on its own', () {
      // A directory with only a roughness map in it is a perfectly good set,
      // and is in fact most of the value.
      put('$kCyclesAssetDir/$kCyclesTextureDir/brass/roughness.jpg');
      CyclesAssets.instance.scan(root.path, materialIds: ['brass']);
      final set = CyclesAssets.instance.texturesFor('brass');
      expect(set.isEmpty, isFalse);
      expect(set.roughness, endsWith('/roughness.jpg'));
      expect(set.base, isNull);
      expect(set.height, isNull);
    });

    test('png is accepted too', () {
      put('$kCyclesAssetDir/$kCyclesTextureDir/brass/basecolor.png');
      CyclesAssets.instance.scan(root.path, materialIds: ['brass']);
      expect(CyclesAssets.instance.texturesFor('brass').base,
          endsWith('/basecolor.png'));
    });

    test('an appearance with no directory has no textures', () {
      put('$kCyclesAssetDir/$kCyclesTextureDir/brass/roughness.jpg');
      CyclesAssets.instance.scan(root.path, materialIds: ['brass', 'copper']);
      expect(CyclesAssets.instance.texturesFor('copper').isEmpty, isTrue);
    });

    test('steel is a set like any other, and null asks for it', () {
      // The commonest body in any assembly, and the only one that could not
      // carry a texture set before M344 — because it was the ABSENCE of a
      // material rather than one of them.
      put('$kCyclesAssetDir/$kCyclesTextureDir/steel/height.jpg');
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.texturesFor('steel').height, isNotNull);
      expect(CyclesAssets.instance.texturesFor(null).height, isNotNull);
    });

    test('the file names are the ones every PBR library uses', () {
      // So a set downloaded from Poly Haven or ambientCG drops in with nothing
      // renamed but the directory.
      expect(CyclesMap.base.fileName, 'basecolor');
      expect(CyclesMap.roughness.fileName, 'roughness');
      expect(CyclesMap.metallic.fileName, 'metallic');
      expect(CyclesMap.height.fileName, 'height');
      expect(CyclesMap.occlusion.fileName, 'ao');
    });
  });

  group('scanning', () {
    test('happens once, because it cannot change while the app runs', () {
      // A directory listing per render is thirty syscalls a second during an
      // orbit for an answer that is fixed at launch.
      CyclesAssets.instance.scan(root.path);
      put('$kCyclesAssetDir/$kCyclesHdriDir/$kCyclesHdriName.hdr');
      CyclesAssets.instance.scan(root.path);
      expect(CyclesAssets.instance.hdri, isNull);
    });
  });

  group('what the renderer does with them', () {
    test('no map means the analytic rig at full strength', () {
      final env = cyclesEnvFor(0xFF2A2E33, hdri: null);
      expect(env.hasHdri, isFalse);
      expect(env.rig, 1.0);
      expect(env.ambient, kCyclesAmbient);
      // And the background is still the viewport's own colour, converted.
      expect(env.world[0], closeTo(cyclesLinear(0x2A), 1e-9));
    });

    test('a map turns the rig down but does not turn it off', () {
      // An environment lights beautifully and casts nothing sharp: every
      // shadow it throws is the soft average of a whole room. A part rendered
      // under one alone FLOATS, because the cue that says "resting on the
      // table" is a contact shadow with a direction.
      final env = cyclesEnvFor(0xFF2A2E33, hdri: '/tmp/studio.hdr');
      expect(env.hasHdri, isTrue);
      expect(env.rig, kCyclesRigWithEnvironment);
      expect(env.rig, greaterThan(0.0));
      expect(env.rig, lessThan(1.0));
    });

    test('the environment lights the scene; the viewport colour is behind it',
        () {
      // The separation that lets an HDRI ship at all. What the camera sees is
      // the app's own background, so the image lands on the ground the rest of
      // the app is drawing; what every other ray sees is the studio.
      final env = cyclesEnvFor(0xFF2A2E33, hdri: '/tmp/studio.hdr');
      expect(env.hdriVisible, isFalse);
      expect(env.world[0], closeTo(cyclesLinear(0x2A), 1e-9));
    });
  });

  group('the image size', () {
    test('drops while the camera is moving', () {
      // Fewer PIXELS, not fewer samples: the eye tracking a shape in motion
      // cannot resolve fine detail but can see noise perfectly well.
      final still = cyclesImageSize(1366, 1024, 2.0);
      final moving = cyclesImageSize(1366, 1024, 2.0, moving: true);
      // M353 — a standstill is 1:1; only the orbit is reduced.
      expect(still.$1, 2732);
      expect(moving.$1, kCyclesMovingSide);
      // Same aspect, so the image scales over the viewport identically.
      expect(moving.$1 / moving.$2, closeTo(still.$1 / still.$2, 0.01));
      // And it is a real saving, not a gesture.
      expect(moving.$1 * moving.$2, lessThan(still.$1 * still.$2 / 3));
    });

    test('a viewport already smaller than the moving cap does not grow', () {
      expect(cyclesImageSize(200, 150, 2.0, moving: true), (400, 300));
    });
  });
}
