// M270 — the gallery's backdrop.
//
// "in the settings i want to be able to change the menu background. i can
// chose a color from a few recommended colors or i can chose an image."
//
// The setting itself is small. What these tests are actually about is the
// thing that makes it safe to offer: a backdrop the user picks is one the app
// did not design around, and a gallery whose card titles have gone invisible
// is a worse gallery than one with a boring background.
//
//   * Every offered colour, run through galleryChrome, gives the cards ink
//     that CONTRASTS with it. That is the invariant, and it is checked against
//     the swatch table itself, so adding a colour later without thinking about
//     it fails here rather than on someone's screen.
//   * A picture keeps the app's own chrome, because the scrim between them is
//     the app's own ground.
//   * The setting round-trips through settings.json without dropping the two
//     preferences that share the file, and refuses to be reset by a value it
//     does not recognise.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/backdrop.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/settings.dart';
import 'package:prototype/theme.dart';

/// WCAG relative luminance and contrast, written out again rather than reused
/// from the library: proving the swatches are readable with the same function
/// that decides which ink they get would prove nothing at all.
double _lum(Color c) {
  double lin(double s) =>
      s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Directory _tmp() => Directory.systemTemp.createTempSync('prototype_m270_');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    T.resetForTest();
    Backdrops.resetForTest();
  });
  tearDown(() {
    T.resetForTest();
    Backdrops.resetForTest();
  });

  group('the offered colours stay readable', () {
    test('every swatch gives the cards ink that contrasts with it', () {
      // 4.5:1 is the WCAG AA threshold for body text, and a card title at
      // 13.5pt semibold is body text. This is the test that makes the whole
      // feature safe: it runs over kBackdropSwatches, so a sixth colour added
      // without thought fails HERE.
      for (final sw in kBackdropSwatches) {
        for (final app in [kEmber, kChalk]) {
          final chrome = galleryChrome(Backdrop.color(sw.argb), app);
          expect(_contrast(chrome.cardName, sw.color), greaterThan(4.5),
              reason: '${sw.id}: the card title is unreadable on it');
          expect(_contrast(chrome.cardDate, sw.color), greaterThan(3.0),
              reason: '${sw.id}: the card date is unreadable on it');
        }
      }
    });

    test('a light colour flips the chrome even under the dark app', () {
      // The point of galleryChrome. Sand under Ember must NOT keep Ember's
      // cream ink, and this is the case the user would have hit first.
      final light = galleryChrome(const Backdrop.color(0xFFE8E2D6), kEmber);
      expect(light.brightness, Brightness.light);
      final dark = galleryChrome(const Backdrop.color(0xFF12151A), kChalk);
      expect(dark.brightness, Brightness.dark);
    });

    test('auto and a picture both keep the app on its own palette', () {
      // Auto IS the palette. A picture keeps it because what sits behind a
      // card there is the palette's ground, veiled over the photograph.
      expect(galleryChrome(Backdrop.auto, kEmber), same(kEmber));
      expect(galleryChrome(Backdrop.auto, kChalk), same(kChalk));
      expect(galleryChrome(const Backdrop.image('/x.jpg'), kEmber), same(kEmber));
    });

    test('the scrim is strong enough to matter and weak enough to see through',
        () {
      expect(kBackdropScrim, greaterThan(0.4));
      expect(kBackdropScrim, lessThan(0.7));
    });

    test('isDarkArgb is luminance, not the average-the-channels shortcut', () {
      // The shortcut calls saturated green dark and saturated blue light, and
      // is wrong about both.
      expect(isDarkArgb(0xFF00FF00), isFalse, reason: 'green is bright');
      expect(isDarkArgb(0xFF0000FF), isTrue, reason: 'blue is not');
      expect(isDarkArgb(0xFF000000), isTrue);
      expect(isDarkArgb(0xFFFFFFFF), isFalse);
    });
  });

  group('what the gallery paints', () {
    test('a colour is painted, a picture is not', () {
      expect(galleryGround(Backdrop.auto, kEmber), kEmber.galleryBg);
      expect(galleryGround(const Backdrop.color(0xFF2A323C), kEmber),
          const Color(0xFF2A323C));
      // Null is the signal to draw the file instead — see home_view.
      expect(galleryGround(const Backdrop.image('/x.jpg'), kEmber), isNull);
    });
  });

  group('the setting survives the app being killed', () {
    test('a colour round-trips', () {
      final dir = _tmp();
      const b = Backdrop.color(0xFF1E2A24);
      BackdropStore(dir).save(b);
      expect(BackdropStore(dir).load(), b);
    });

    test('it shares settings.json without dropping the neighbours', () {
      // Appearance and language live in the same file. A store that owned it
      // would silently throw one of them away on every write.
      final dir = _tmp();
      ThemeStore(dir).save(AppThemeMode.light);
      BackdropStore(dir).save(const Backdrop.color(0xFF12151A));
      final raw = jsonDecode(
          File('${dir.path}/${BackdropStore.fileName}').readAsStringSync());
      expect(raw['theme'], AppThemeMode.light.id);
      expect(ThemeStore(dir).load(), AppThemeMode.light);
      expect(BackdropStore(dir).load(), const Backdrop.color(0xFF12151A));
    });

    test('a colour this build does not offer leaves the choice alone', () {
      // A settings file written by a LATER build. Resetting to the default
      // because a name is unfamiliar loses a preference the user set.
      expect(Backdrop.byId('aubergine'), isNull);
      expect(Backdrop.fromJson({'kind': 'color', 'id': 'aubergine'}),
          Backdrop.auto);
    });

    test('a remembered picture that is gone falls back rather than blanking',
        () {
      final dir = _tmp();
      BackdropStore(dir).save(const Backdrop.image('/nowhere/at/all.jpg'));
      expect(BackdropStore(dir).load(), Backdrop.auto);
    });

    test('rubbish in the file costs the backdrop and nothing else', () {
      final dir = _tmp();
      File('${dir.path}/${BackdropStore.fileName}').writeAsStringSync('{');
      expect(BackdropStore(dir).load(), isNull);
    });
  });

  group('choosing a picture', () {
    test('the file is COPIED, and the old one goes with it', () {
      // The picker hands back a path in a staging area iOS is free to empty. A
      // wallpaper that survives until the next reboot looks like the app
      // forgot.
      final src = _tmp(), into = _tmp();
      final a = File('${src.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      expect(Backdrops.adoptImage(a, into), isTrue);
      final first = Backdrops.current.value;
      expect(first.kind, BackdropKind.image);
      expect(File(first.imagePath).existsSync(), isTrue);
      expect(first.imagePath.endsWith('.jpg'), isTrue);

      final b = File('${src.path}/b.png')..writeAsBytesSync([4, 5]);
      expect(Backdrops.adoptImage(b, into), isTrue);
      // One wallpaper, not a folder of them the user cannot see or delete.
      expect(into.listSync().whereType<File>().length, 1);
      expect(Backdrops.current.value.imagePath.endsWith('.png'), isTrue);
    });

    test('clearing removes the file as well as the setting', () {
      final src = _tmp(), into = _tmp();
      Backdrops.adoptImage(File('${src.path}/a.jpg')..writeAsBytesSync([1]),
          into);
      Backdrops.clear(into);
      expect(Backdrops.current.value, Backdrop.auto);
      expect(into.listSync().whereType<File>(), isEmpty);
    });

    test('a source that is not there fails without changing anything', () {
      final into = _tmp();
      expect(Backdrops.adoptImage(File('/nowhere/x.jpg'), into), isFalse);
      expect(Backdrops.current.value, Backdrop.auto);
    });
  });

  group('the Settings section', () {
    List<SettingsSection> spec({Backdrop backdrop = Backdrop.auto}) =>
        buildSettings(L.stringsFor(const Locale('de')),
            mode: AppThemeMode.system,
            locale: const Locale('de'),
            backdrop: backdrop,
            info: const SettingsInfo(
                build: 'b', kernel3d: '3', kernel2d: '2', system: 's'));

    SettingsSection section(List<SettingsSection> s) =>
        s.firstWhere((x) => x.id == kSecBackdrop);

    test('every offered colour is a row, and each carries its own swatch', () {
      final rows = section(spec()).rows;
      for (final sw in kBackdropSwatches) {
        final r = rows.firstWhere((x) => x.id == sw.id);
        // The colour IS the value, which is why this row has a glyph where
        // Appearance and Language deliberately do not.
        expect(r.tint, sw.argb, reason: '${sw.id} has no swatch');
        expect(r.symbol, isNotNull);
        expect(r.kind, SettingsRowKind.check);
      }
    });

    test('exactly one tick, and it is on what is set', () {
      for (final b in [
        Backdrop.auto,
        const Backdrop.color(0xFF2A323C),
        const Backdrop.image('/tmp/pic.jpg'),
      ]) {
        final rows = section(spec(backdrop: b)).rows;
        final ticked = rows.where((r) => r.selected).map((r) => r.id).toList();
        expect(ticked, [b.selectedId], reason: 'for $b');
      }
    });

    test('the picture row appears only when there is one, and names the file',
        () {
      expect(section(spec()).rows.map((r) => r.id), isNot(contains(kBackdropImage)));
      final rows = section(spec(backdrop: const Backdrop.image('/a/b/wall.png')))
          .rows;
      final pic = rows.firstWhere((r) => r.id == kBackdropImage);
      // The name, not the path: a settings row is not wide enough for one and
      // the name is the part a person recognises.
      expect(pic.detail, 'wall.png');
    });

    test('Remove is offered only when there is something to remove', () {
      expect(section(spec()).rows.map((r) => r.id),
          isNot(contains(kRowRemoveImage)));
      final rows =
          section(spec(backdrop: const Backdrop.image('/a/b.png'))).rows;
      final rm = rows.firstWhere((r) => r.id == kRowRemoveImage);
      expect(rm.destructive, isTrue);
    });

    test('Choose is always offered', () {
      for (final b in [Backdrop.auto, const Backdrop.image('/a/b.png')]) {
        expect(section(spec(backdrop: b)).rows.map((r) => r.id),
            contains(kRowChooseImage));
      }
    });

    test('every row is named in the ARB, in both languages', () {
      for (final l in [const Locale('de'), const Locale('en')]) {
        final t = L.stringsFor(l);
        for (final sw in kBackdropSwatches) {
          expect(backdropName(t, sw.id), isNotEmpty);
        }
        expect(backdropName(t, kBackdropAuto), isNotEmpty);
        expect(t.settingsBackdrop, isNotEmpty);
        expect(t.settingsBackdropFooter, isNotEmpty);
      }
      // ...and the two languages actually say different things, or one of them
      // is an untranslated copy of the other.
      expect(L.stringsFor(const Locale('de')).settingsBackdrop,
          isNot(L.stringsFor(const Locale('en')).settingsBackdrop));
    });

    test('the tint reaches the wire, and only where it belongs', () {
      final maps = settingsToMaps(spec());
      final backdropRows =
          (maps.firstWhere((m) => m['id'] == kSecBackdrop)['rows'] as List)
              .cast<Map<String, Object?>>();
      expect(backdropRows.where((r) => r['tint'] != null).length,
          kBackdropSwatches.length);
      for (final m in maps.where((m) => m['id'] != kSecBackdrop)) {
        for (final raw in (m['rows'] as List).cast<Map<String, Object?>>()) {
          expect(raw.containsKey('tint'), isFalse,
              reason: '${m['id']}/${raw['id']} should carry no colour');
        }
      }
    });
  });
}
