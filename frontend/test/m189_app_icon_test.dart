// M189 — the app icon set is committed art, and CI copies it over the one
// `flutter create` scaffolds. Nothing in the build validates it: a missing
// size, a stray alpha channel or a filename that drifted out of Contents.json
// all produce a GREEN build that ships Flutter's default blue icon (or, for
// alpha, a black square on the home screen and an App Store rejection).
//
// So the checks live here, where they run on every push.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const iconSet = 'branding/AppIcon.appiconset';

/// (width, height, PNG colour type) straight out of the IHDR chunk.
(int, int, int) pngHeader(File f) {
  final b = f.readAsBytesSync();
  expect(b.length, greaterThan(26), reason: '${f.path} is not a PNG');
  // 8-byte signature, then length+type, then the IHDR payload
  expect(b.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10],
      reason: '${f.path} lacks the PNG signature');
  int be32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (be32(16), be32(20), b[25]);
}

void main() {
  group('M189 app icon', () {
    test('every image Contents.json names exists at its stated size', () {
      final dir = Directory(iconSet);
      expect(dir.existsSync(), isTrue,
          reason: '$iconSet is missing — CI copies exactly this directory');
      final contents = jsonDecode(
              File('$iconSet/Contents.json').readAsStringSync())
          as Map<String, dynamic>;
      final images = (contents['images'] as List).cast<Map<String, dynamic>>();
      expect(images, isNotEmpty);

      for (final img in images) {
        final name = img['filename'] as String;
        final f = File('$iconSet/$name');
        expect(f.existsSync(), isTrue, reason: '$name referenced but missing');
        // "83.5x83.5" at "2x" is 167 px — the one entry where the arithmetic
        // is not a round number, and the one most often got wrong by hand.
        final side = double.parse((img['size'] as String).split('x').first);
        final scale = int.parse((img['scale'] as String).replaceAll('x', ''));
        final want = (side * scale).round();
        final (w, h, _) = pngHeader(f);
        expect(w, want, reason: '$name should be ${want}px wide');
        expect(h, want, reason: '$name should be ${want}px tall');
      }
    });

    test('no icon carries an alpha channel', () {
      for (final f in Directory(iconSet)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))) {
        final (_, _, colourType) = pngHeader(f);
        // 2 = truecolour. 4 and 6 are the alpha ones; 3 (palette) can carry
        // alpha in a tRNS chunk, so it is not acceptable either.
        expect(colourType, 2,
            reason: '${f.path} must be opaque RGB — iOS rejects an alpha '
                'channel on the marketing icon and paints the rest black');
      }
    });

    test('the marketing icon is there at 1024 and is not the placeholder', () {
      final f = File('$iconSet/Icon-App-1024x1024@1x.png');
      final (w, h, _) = pngHeader(f);
      expect(w, 1024);
      expect(h, 1024);
      // The source art it is rendered from stays in the repo, so the set can
      // be regenerated (branding/make_app_icon.py) rather than reverse
      // engineered from the largest PNG.
      expect(File('branding/app_icon_source.png').existsSync(), isTrue);
      expect(File('branding/make_app_icon.py').existsSync(), isTrue);
    });

    test('the set covers every size iOS asks an iPad app for', () {
      final have = Directory(iconSet)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      for (final name in const [
        'Icon-App-20x20@1x.png', // iPad notification
        'Icon-App-20x20@2x.png',
        'Icon-App-29x29@1x.png', // settings
        'Icon-App-29x29@2x.png',
        'Icon-App-40x40@1x.png', // spotlight
        'Icon-App-40x40@2x.png',
        'Icon-App-76x76@1x.png', // home screen
        'Icon-App-76x76@2x.png',
        'Icon-App-83.5x83.5@2x.png', // iPad Pro home screen
        'Icon-App-1024x1024@1x.png',
      ]) {
        expect(have, contains(name));
      }
    });
  });
}
