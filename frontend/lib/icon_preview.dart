// M348 — live icon preview from a PC on the same network.
//
// Icons in this app are compiled-in SVG strings (svg_icons.dart), so trying a
// new drawing meant a commit, a CI build and a SideStore install: minutes per
// look. That is the wrong loop for artwork, where the only question that
// matters — "does it read at 18 px?" — is answered in a second by eye.
//
// So: point the app at an HTTP server on the machine the icons are being drawn
// on, and it prefers what that server offers over what it was built with. The
// server is `tools/icon-sync/serve.py`, which watches a render folder, crops
// each image to a square and publishes a manifest. Save in Blender, look at
// the iPad, it has changed.
//
// OFF BY DEFAULT AND OFF IN EVERY BUILD. The host is empty until someone types
// one into Settings > Diagnostics > Icon Preview, and with it empty
// [imageFor] answers null for everything, so every call site draws exactly the
// SVG it drew before. Nothing about the shipped icon set changes.
//
// Deliberately not a --dart-define: the address of a PC on a home network is
// a DHCP lease, not a build constant, and a rebuild per IP change would defeat
// the point of the whole thing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'icon_theme.dart';
import 'log.dart';
import 'svg_icons.dart';

/// Where the preview host survives a restart.
///
/// The same file, the same shape and the same swallow-the-error rule as
/// `ThemeStore` — it merges into `settings.json` rather than owning it, so the
/// appearance and language preferences sitting next to it are never dropped.
class IconPreviewStore {
  final Directory dir;
  const IconPreviewStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'iconPreviewHost';

  File get file => File('${dir.path}/$fileName');

  Map<String, Object?> _read() {
    try {
      final f = file;
      if (!f.existsSync()) return const {};
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return const {};
      return <String, Object?>{for (final e in raw.entries) '${e.key}': e.value};
    } catch (e) {
      Log.w('iconpreview', 'could not read the preview host: $e');
      return const {};
    }
  }

  String load() {
    final v = _read()[key];
    return v is String ? v : '';
  }

  void save(String host) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final data = <String, Object?>{..._read(), key: host};
      file.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('iconpreview', 'could not remember the preview host: $e');
    }
  }
}

/// The override set, and the poll that keeps it current.
class IconPreview {
  IconPreview._();

  /// The base URL being polled, or empty for "use the built-in icons".
  static final ValueNotifier<String> host = ValueNotifier<String>('');

  /// Bumped whenever the override set changes. Every icon widget listens, so
  /// a new drawing lands without anything else being told to rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static IconPreviewStore? _store;
  static Timer? _timer;
  static final Map<String, Uint8List> _png = <String, Uint8List>{};
  static final Map<String, String> _stamp = <String, String>{};
  static Map<String, String>? _nameOf;
  static Map<String, String>? _short;
  static bool _busy = false;

  /// The last poll failure, for the dialog to show. Null once one succeeds.
  static String? lastError;

  static bool get active => host.value.isNotEmpty;

  /// How many icons the server is currently overriding.
  static int get count => _png.length;

  /// Adopt the remembered host, if there is one. Called from `AppState.init`
  /// alongside the other stores.
  static void attachStore(IconPreviewStore s) {
    _store = s;
    final remembered = s.load();
    if (remembered.isNotEmpty) setHost(remembered);
  }

  /// Point at [raw] (`192.168.1.42:8080`, with or without a scheme), or pass
  /// an empty string to go back to the built-in icons.
  static void setHost(String raw) {
    final h = _normalise(raw);
    if (h == host.value) return;
    _timer?.cancel();
    _timer = null;
    _png.clear();
    _stamp.clear();
    lastError = null;
    host.value = h;
    _store?.save(h);
    revision.value++;
    if (h.isEmpty) {
      Log.i('iconpreview', 'off — using the built-in icons');
      return;
    }
    Log.i('iconpreview', 'polling $h');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_poll()));
    unawaited(_poll());
  }

  static String _normalise(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.length > 8 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static Future<void> _poll() async {
    if (_busy || !active) return;
    _busy = true;
    final base = host.value;
    try {
      final res = await http
          .get(Uri.parse('$base/manifest.json'))
          .timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) {
        throw HttpException('manifest.json returned ${res.statusCode}');
      }
      final raw = jsonDecode(utf8.decode(res.bodyBytes));
      if (raw is! Map) throw const FormatException('manifest is not an object');
      final icons = raw['icons'];
      if (icons is! Map) throw const FormatException('manifest has no "icons"');
      final wanted = <String, String>{
        for (final e in icons.entries) '${e.key}': '${e.value}'
      };

      var changed = false;
      // Deleting a render puts its icon back to the built-in drawing, which is
      // what makes "is mine actually better?" a question you can answer.
      for (final gone in _stamp.keys.toList()) {
        if (!wanted.containsKey(gone)) {
          _stamp.remove(gone);
          _png.remove(gone);
          changed = true;
        }
      }
      for (final e in wanted.entries) {
        if (_stamp[e.key] == e.value) continue;
        // The host can change while a body is in flight; adopting bytes from
        // the old one would show a stale icon with no way to shift it.
        if (base != host.value) return;
        final img = await http
            .get(Uri.parse(
                '$base/i/${Uri.encodeComponent(e.key)}.png?h=${e.value}'))
            .timeout(const Duration(seconds: 5));
        if (img.statusCode != 200) continue;
        if (base != host.value) return;
        _png[e.key] = img.bodyBytes;
        _stamp[e.key] = e.value;
        changed = true;
      }
      if (lastError != null) Log.i('iconpreview', 'server back');
      lastError = null;
      if (changed) {
        Log.i('iconpreview', '${_png.length} icon(s) overridden');
        revision.value++;
      }
    } catch (e) {
      // One line per outage, not one per second: the poll runs forever and a
      // PC that is simply switched off must not fill the log.
      if (lastError == null) Log.w('iconpreview', 'poll failed: $e');
      lastError = '$e';
    } finally {
      _busy = false;
    }
  }

  /// The PNG that replaces [source], or null to draw the SVG as before.
  static Uint8List? imageFor(String source) {
    if (_png.isEmpty) return null;
    final full = _index()[source];
    if (full == null) return null;
    final direct = _png[full];
    if (direct != null) return direct;
    // `extrude.png` is accepted for `CR.extrude` when no other map has a key
    // by that name. Where one does — `split` is in both MD and MO — the
    // qualified name is the only thing that resolves, on purpose.
    final short = _shortOf(full);
    if (_shortIndex()[short] == full) return _png[short];
    return null;
  }

  static String _shortOf(String full) {
    final i = full.indexOf('.');
    return i < 0 ? full : full.substring(i + 1);
  }

  /// SVG source -> the name a render file has to carry to replace it.
  static Map<String, String> _index() {
    final cached = _nameOf;
    if (cached != null) return cached;
    final out = <String, String>{};
    void addMap(String prefix, Map<String, String> src) {
      src.forEach((k, v) => out.putIfAbsent(v, () => '$prefix.$k'));
    }

    addMap('IC', IC);
    addMap('CN', CN);
    addMap('IN', IN);
    addMap('MD', MD);
    addMap('PD', PD);
    addMap('CR', CR);
    addMap('MO', MO);
    addMap('WF', WF);
    addMap('PT', PT);
    addMap('PL', PL);
    addMap('AX', AX);
    addMap('PN', PN);
    addMap('AS', AS);
    addMap('AC', AC);

    void one(String name, String svg) => out.putIfAbsent(svg, () => name);
    one('layerBigIcon', layerBigIcon);
    one('finishIcon', finishIcon);
    one('returnIcon', returnIcon);
    one('newSketchIcon', newSketchIcon);
    one('layerRowIcon', layerRowIcon);
    one('sketchCubeIcon', sketchCubeIcon);
    one('sharedSketchCubeIcon', sharedSketchCubeIcon);
    one('originIcon', originIcon);
    one('xAxisIcon', xAxisIcon);
    one('yAxisIcon', yAxisIcon);
    one('zAxisIcon', zAxisIcon);
    one('planeIcon', planeIcon);
    one('centerPointIcon', centerPointIcon);
    one('endOfSketchIcon', endOfSketchIcon);
    one('homeTabIcon', homeTabIcon);
    one('asmSelectionIcon', asmSelectionIcon);
    one('asmPickPartIcon', asmPickPartIcon);
    one('asmPreviewIcon', asmPreviewIcon);
    one('asmPredictIcon', asmPredictIcon);
    one('asmSickIcon', asmSickIcon);
    one('asmConstraintIcon', asmConstraintIcon);
    one('asmSuppressedIcon', asmSuppressedIcon);
    one('assemblyMenuIcon', assemblyMenuIcon);
    one('assemblyCubeIcon', assemblyCubeIcon);
    one('componentCubeIcon', componentCubeIcon);
    one('groundedPinIcon', groundedPinIcon);
    one('asmPatternIcon', asmPatternIcon);
    one('relationshipsIcon', relationshipsIcon);
    one('representationsIcon', representationsIcon);
    one('viewRepActiveIcon', viewRepActiveIcon);
    one('viewRepIcon', viewRepIcon);
    one('viewRepLockedIcon', viewRepLockedIcon);
    one('inPlaceReturnIcon', inPlaceReturnIcon);
    one('partCubeIcon', partCubeIcon);
    one('derivedCubeIcon', derivedCubeIcon);
    one('sketch2dMenuIcon', sketch2dMenuIcon);
    one('part3dMenuIcon', part3dMenuIcon);

    _nameOf = out;
    return out;
  }

  /// Short key -> qualified name, for the short keys that are unambiguous.
  static Map<String, String> _shortIndex() {
    final cached = _short;
    if (cached != null) return cached;
    final seen = <String, int>{};
    for (final full in _index().values) {
      final k = _shortOf(full);
      seen[k] = (seen[k] ?? 0) + 1;
    }
    final out = <String, String>{};
    for (final full in _index().values) {
      final k = _shortOf(full);
      if (seen[k] == 1) out[k] = full;
    }
    _short = out;
    return out;
  }

  /// Every name a render file may carry, for the dialog's help text.
  static List<String> allNames() => _index().values.toList()..sort();
}

/// Draw [source] — as the live override when there is one, otherwise as the
/// SVG the app was built with.
///
/// Every icon in the app goes through here. With no host set the builder runs
/// once and falls straight through to [SvgPicture.string], which is what every
/// one of these call sites did before.
Widget iconWidget(String source, [double? size]) => ValueListenableBuilder<int>(
      valueListenable: IconPreview.revision,
      builder: (_, __, ___) {
        final png = IconPreview.imageFor(source);
        if (png != null) {
          return Image.memory(
            png,
            width: size,
            height: size,
            fit: BoxFit.contain,
            // Without this the icon blinks white for a frame on every save,
            // which at one save a second is the whole screen flickering.
            gaplessPlayback: true,
          );
        }
        return SvgPicture.string(themedIcon(source), width: size, height: size);
      },
    );
