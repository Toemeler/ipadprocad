// M270 — the gallery's backdrop, as something the user owns.
//
// Everything else in this app's appearance is a SCHEME: two palettes, chosen
// together, each internally consistent. That is right for the working
// surfaces — a ribbon, a browser, a viewport — where a personal colour would
// be noise over the drawing. The gallery is the one screen that is not a
// working surface. It is the app's front page, it is mostly empty, and it is
// the place a personal choice costs nothing and reads as yours.
//
// So one setting, and only for that screen: a colour off a short list, or a
// picture. Nothing here reaches into a document.
//
// ---------------------------------------------------------------------------
// The part that is easy to get wrong
// ---------------------------------------------------------------------------
//
// A backdrop the user picks is a backdrop the app did not design AROUND. The
// cards carry a title and a date in the palette's ink, and cream text on a
// sand-coloured backdrop is not a style problem, it is an unreadable gallery.
// Two rules keep that from happening, and they are the whole reason this file
// is not just a colour in a settings file:
//
//   * A COLOUR decides the gallery's own chrome. Not the app's palette — the
//     backdrop's. Pick a light colour in the dark scheme and the cards, the
//     titles and the dates come out in the light scheme's ink, on that screen
//     only. [galleryChrome] is that rule, and it is a pure function so a test
//     can pin every swatch against it.
//
//   * An IMAGE gets a SCRIM: the palette's own gallery ground, veiled over the
//     picture. A photograph has no luminance to reason about — it has a
//     thousand — and the only honest answer is to put something predictable
//     between it and the text. The picture still reads through it; the labels
//     stop depending on what happens to be behind them.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'log.dart';
import 'theme.dart';

/// What the gallery is painted with.
enum BackdropKind {
  /// The palette's own ground. The default, and what every install starts as.
  auto,

  /// One of [kBackdropSwatches].
  color,

  /// A picture the user chose, copied next to the settings file.
  image,
}

/// One offered colour.
///
/// The id is what goes in settings.json and what the settings row is keyed by;
/// it is never shown. The NAME comes from the ARB, like every other string in
/// this app — see `backdropName`.
class BackdropSwatch {
  final String id;
  final int argb;
  const BackdropSwatch(this.id, this.argb);
  Color get color => Color(argb);
}

/// The offered colours: three deep, two light, in that order.
///
/// Short on purpose. A palette of forty is a colour picker, and a colour
/// picker is how a preference screen turns into a project. These are chosen to
/// be BACKDROPS — desaturated, none of them competing with a card — and to
/// span both ends of the luminance range so the choice is real rather than
/// five shades of the scheme the user already has.
const List<BackdropSwatch> kBackdropSwatches = [
  BackdropSwatch('ink', 0xFF12151A), // near-black, cool
  BackdropSwatch('slate', 0xFF2A323C), // blue grey
  BackdropSwatch('forest', 0xFF1E2A24), // deep green
  BackdropSwatch('sand', 0xFFE8E2D6), // warm paper
  BackdropSwatch('linen', 0xFFF4F2ED), // near white
];

/// The settings-row id for "follow the appearance", i.e. [BackdropKind.auto].
const String kBackdropAuto = 'auto';

/// The settings-row id of the picture row.
const String kBackdropImage = 'image';

/// What the gallery is painted with, right now.
@immutable
class Backdrop {
  final BackdropKind kind;

  /// The chosen colour, when [kind] is [BackdropKind.color].
  final int argb;

  /// Where the chosen picture was copied to, when [kind] is
  /// [BackdropKind.image]. An absolute path: the file lives beside
  /// settings.json, not in the gallery folder, because it is a preference and
  /// a document folder is for documents.
  final String imagePath;

  const Backdrop._(this.kind, this.argb, this.imagePath);

  static const Backdrop auto = Backdrop._(BackdropKind.auto, 0, '');
  const Backdrop.color(int argb) : this._(BackdropKind.color, argb, '');
  const Backdrop.image(String path) : this._(BackdropKind.image, 0, path);

  /// The id of the settings row that carries the tick.
  String get selectedId => switch (kind) {
        BackdropKind.auto => kBackdropAuto,
        BackdropKind.image => kBackdropImage,
        BackdropKind.color => _swatchId(argb) ?? kBackdropAuto,
      };

  static String? _swatchId(int argb) {
    for (final s in kBackdropSwatches) {
      if (s.argb == argb) return s.id;
    }
    return null;
  }

  /// The row id [id] chose, or null when it names nothing this build offers.
  ///
  /// Null rather than a fallback: a settings file from a later build naming a
  /// swatch that no longer exists must leave the current choice alone, not
  /// silently reset it to the default.
  static Backdrop? byId(String id) {
    if (id == kBackdropAuto) return auto;
    for (final s in kBackdropSwatches) {
      if (s.id == id) return Backdrop.color(s.argb);
    }
    return null;
  }

  Map<String, Object?> toJson() => switch (kind) {
        BackdropKind.auto => {'kind': 'auto'},
        BackdropKind.color => {'kind': 'color', 'id': selectedId},
        BackdropKind.image => {'kind': 'image', 'path': imagePath},
      };

  /// Reads [raw] back, and answers [auto] for anything it does not recognise.
  ///
  /// A preference file is the one input that arrives from a previous version
  /// of this app, so every field is optional and nothing here throws.
  static Backdrop fromJson(Object? raw) {
    if (raw is! Map) return auto;
    switch (raw['kind']) {
      case 'color':
        final id = raw['id'];
        return (id is String ? byId(id) : null) ?? auto;
      case 'image':
        final p = raw['path'];
        return p is String && p.isNotEmpty ? Backdrop.image(p) : auto;
      default:
        return auto;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Backdrop &&
      other.kind == kind &&
      other.argb == argb &&
      other.imagePath == imagePath;

  @override
  int get hashCode => Object.hash(kind, argb, imagePath);

  @override
  String toString() => switch (kind) {
        BackdropKind.auto => 'auto',
        BackdropKind.color => 'color(${selectedId})',
        BackdropKind.image => 'image($imagePath)',
      };
}

/// True when [argb] is dark enough to carry light text.
///
/// Relative luminance, sRGB-linearised — the WCAG definition, not the
/// "average the channels" shortcut, because the shortcut calls a saturated
/// green dark and a saturated blue light and both are wrong by a wide margin.
/// The threshold is where black and white text have equal contrast against the
/// same ground.
bool isDarkArgb(int argb) {
  double lin(int c) {
    final s = c / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  final l = 0.2126 * lin((argb >> 16) & 0xFF) +
      0.7152 * lin((argb >> 8) & 0xFF) +
      0.0722 * lin(argb & 0xFF);
  // 0.179 is where black and white text reach equal WCAG contrast against the
  // same ground, so it is the point the ink has to flip.
  return l < 0.179;
}

/// The palette the GALLERY's own chrome must read — its cards, their titles
/// and their dates.
///
/// [app] is the palette the rest of the app is in. A colour backdrop overrides
/// it, because the cards sit on the backdrop and not on the app; auto and an
/// image both keep it, because in both cases what is behind a card is already
/// [Palette.galleryBg] (for an image, veiled over it — see [kBackdropScrim]).
Palette galleryChrome(Backdrop b, Palette app) => switch (b.kind) {
      BackdropKind.auto || BackdropKind.image => app,
      BackdropKind.color => isDarkArgb(b.argb) ? kEmber : kChalk,
    };

/// How much of the palette's gallery ground is veiled over a picture.
///
/// Enough that a card's title is legible over anything, little enough that the
/// picture is plainly still there. Below about 0.4 a white sky eats a white
/// title; above about 0.7 the user has chosen a photograph and been given a
/// tint.
const double kBackdropScrim = 0.55;

/// The colour the gallery paints, or null when it paints a picture instead.
Color? galleryGround(Backdrop b, Palette app) => switch (b.kind) {
      BackdropKind.auto => app.galleryBg,
      BackdropKind.color => Color(b.argb),
      BackdropKind.image => null,
    };

/// Remembers the backdrop in the same `settings.json` the appearance and the
/// language use. Merges rather than owns, for the reason [ThemeStore] does:
/// three preferences, one file, and none of them may drop the others.
class BackdropStore {
  final Directory dir;
  const BackdropStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'backdrop';

  File get file => File('${dir.path}/$fileName');

  Backdrop? load() {
    try {
      final f = file;
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map || !raw.containsKey(key)) return null;
      final b = Backdrop.fromJson(raw[key]);
      // A remembered picture whose file has since gone (deleted from Files, a
      // restore onto a new device) must not leave the gallery blank.
      if (b.kind == BackdropKind.image && !File(b.imagePath).existsSync()) {
        Log.w('backdrop', 'the remembered picture is gone: ${b.imagePath}');
        return Backdrop.auto;
      }
      return b;
    } catch (e) {
      Log.w('backdrop', 'could not read the backdrop setting: $e');
      return null;
    }
  }

  void save(Backdrop b) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      Map<String, Object?> data = <String, Object?>{};
      final f = file;
      if (f.existsSync()) {
        final raw = jsonDecode(f.readAsStringSync());
        if (raw is Map) {
          data = <String, Object?>{
            for (final e in raw.entries) '${e.key}': e.value
          };
        }
      }
      data[key] = b.toJson();
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('backdrop', 'could not remember the backdrop setting: $e');
    }
  }
}

/// The live setting, as something the app root can listen to.
///
/// Mirrors [T.scheme] and [L.locale] exactly, and for the same reason: the
/// gallery reads it at paint time, so one notification rebuilds it without a
/// BuildContext being threaded anywhere.
class Backdrops {
  Backdrops._();

  static final ValueNotifier<Backdrop> current =
      ValueNotifier<Backdrop>(Backdrop.auto);

  static BackdropStore? _store;

  /// The file the picture is copied to. One name, so choosing a second picture
  /// replaces the first instead of filling the folder with wallpapers nobody
  /// can see or delete.
  static const String imageBase = 'backdrop';

  /// Point the setting at a file and adopt what it remembers. Called from
  /// [AppState.init], off the launch path, like the other two.
  static void attachStore(BackdropStore store) {
    _store = store;
    final saved = store.load();
    if (saved != null && saved != current.value) current.value = saved;
  }

  /// Choose, and remember.
  static void set(Backdrop b) {
    if (b == current.value) return;
    current.value = b;
    Log.i('backdrop', 'backdrop = $b');
    _store?.save(b);
  }

  /// Copies [source] next to the settings file and adopts it.
  ///
  /// COPIED, not referenced. The picker hands back a path in a temporary
  /// staging area that iOS is free to empty, and a wallpaper that survives
  /// until the next reboot is worse than none — it looks like the app forgot.
  ///
  /// Returns false when the copy failed, so the caller can say so rather than
  /// leaving a setting that points at nothing.
  static bool adoptImage(File source, Directory into) {
    try {
      if (!into.existsSync()) into.createSync(recursive: true);
      final dot = source.path.lastIndexOf('.');
      final ext = dot > source.path.lastIndexOf('/') && dot >= 0
          ? source.path.substring(dot).toLowerCase()
          : '.img';
      final target = File('${into.path}/$imageBase$ext');
      // Any previous wallpaper goes, whatever it was called: only the
      // extension varies, and two of them would leave a stale file behind
      // that nothing ever reads again.
      _clearImages(into);
      source.copySync(target.path);
      set(Backdrop.image(target.path));
      return true;
    } catch (e) {
      Log.w('backdrop', 'could not adopt the picture: $e');
      return false;
    }
  }

  /// Back to the palette's own ground, and the picture goes with it.
  static void clear(Directory into) {
    _clearImages(into);
    set(Backdrop.auto);
  }

  static void _clearImages(Directory into) {
    try {
      if (!into.existsSync()) return;
      for (final e in into.listSync()) {
        if (e is! File) continue;
        final n = e.uri.pathSegments.last;
        if (n == imageBase || n.startsWith('$imageBase.')) e.deleteSync();
      }
    } catch (e) {
      Log.w('backdrop', 'could not remove the old picture: $e');
    }
  }

  /// Resets the setting so one test cannot leak its backdrop into the next.
  @visibleForTesting
  static void resetForTest() {
    _store = null;
    current.value = Backdrop.auto;
  }
}

/// The palette the gallery's chrome must read, for whatever is set right now.
///
/// A convenience over [galleryChrome] for the widgets that ARE the gallery.
/// They read it at paint time exactly as they read [T], which is what makes a
/// backdrop change a repaint rather than a rebuild of anything.
Palette get galleryPalette => galleryChrome(Backdrops.current.value, T.palette);
