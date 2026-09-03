/// Real UIKit context menus, share sheet and Files exporter for Flutter.
///
/// Everything here is a NO-OP unless we are actually running on iOS: the host
/// test suite and `flutter analyze` must never see a MissingPluginException,
/// and every entry point swallows channel failures rather than throwing into
/// the widget tree.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

export 'glass_browser.dart';
export 'liquid_glass.dart';
export 'perf_hook.dart';
export 'glass_tabbar.dart';
export 'glass_toolbar.dart';
export 'native_touches.dart';
import 'package:flutter/services.dart';

import 'liquid_glass.dart';

/// The converter's steps, in the order they run, numbered as the kernel
/// numbers them (OCCT_MS_* in occt_capi.h).
///
/// The busy card is UIKit and has no localisations of its own, so the app
/// hands it a name per stage — [NativeBusy.show]'s `stages`, indexed by these
/// values. The kernel's own English is the fallback.
enum MeshStage {
  idle,
  reading,
  finding,
  fitting,
  shaping,
  building,
  finishing,
  buildingFaceted,
  simplifying;

  /// The list [NativeBusy.show] wants: one name per stage, in order.
  static List<String> names({
    required String reading,
    required String finding,
    required String fitting,
    required String shaping,
    required String building,
    required String finishing,
    required String simplifying,
  }) =>
      [
        '', // idle is never shown
        reading,
        finding,
        fitting,
        shaping,
        building,
        finishing,
        building, // the 1:1 path builds faces too, and says so the same way
        simplifying,
      ];
}

/// What to do with a mesh file at import: reconstruct it, or keep it.
///
/// The ids are the wire values the platform channel carries, and they are also
/// what gets written into a log line, so they are spelled out rather than
/// being an index into this list — inserting a case must not change what an
/// old log meant.
enum MeshImportChoice {
  /// Reverse-engineer surfaces: planes, cylinders, cones, spheres, tori and
  /// fitted B-splines. Slower, and the result is editable CAD.
  convert('convert'),

  /// One B-Rep face per triangle, exactly as the file has them. Faithful to
  /// the last vertex, and not much use for CAD operations afterwards.
  faceted('faceted');

  const MeshImportChoice(this.id);
  final String id;

  /// The kernel's `mode` argument. 1 fits surfaces, 0 keeps triangles; see
  /// occt_brep_from_mesh.
  int get kernelMode => this == MeshImportChoice.convert ? 1 : 0;

  static MeshImportChoice? byId(String? id) {
    for (final c in MeshImportChoice.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// One row in a native menu.
class NativeMenuItem {
  /// Returned verbatim to the selection handler.
  final String id;
  final String title;

  /// SF Symbol name, e.g. `trash`. Unknown names simply render without a glyph.
  final String? symbol;

  /// Destructive rows are drawn red by UIKit — we never colour them ourselves.
  final bool destructive;

  const NativeMenuItem({
    required this.id,
    required this.title,
    this.symbol,
    this.destructive = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        if (symbol != null) 'symbol': symbol,
        'destructive': destructive,
      };
}

/// A rectangle on screen that opens [groups] when long-pressed.
///
/// Each group becomes a visually separated section, which is how a destructive
/// row gets its own block at the bottom (the Files.app convention).
class NativeMenuTarget {
  final String id;

  /// Header shown above the menu. Empty string = no header.
  final String title;

  /// Whole hit region, in logical pixels, relative to the Flutter view.
  final Rect rect;

  /// Sub-region that visually lifts. Defaults to [rect].
  final Rect? previewRect;

  final double cornerRadius;

  /// Image shown in the lifted preview. Cheaper and far more reliable than
  /// snapshotting the Flutter surface.
  final String? previewImagePath;

  /// Whether the target visually LIFTS out of the page under the menu (M90).
  ///
  /// True suits a card that has a [previewImagePath]: iOS lifts the picture.
  /// False suits anything whose pixels we cannot hand to UIKit — a model
  /// browser row lives in the Flutter Metal layer and cannot be snapshotted,
  /// so lifting it produced an EMPTY slab the size of the row: a blank grey
  /// rectangle covering the tree, which is what this flag exists to stop.
  /// With it off the row simply stays where it is and only the menu appears.
  final bool lift;

  final List<List<NativeMenuItem>> groups;

  const NativeMenuTarget({
    required this.id,
    required this.rect,
    required this.groups,
    this.title = '',
    this.previewRect,
    this.cornerRadius = 0,
    this.previewImagePath,
    this.lift = true,
  });

  static Map<String, Object?> _rect(Rect r) => {
        'left': r.left,
        'top': r.top,
        'width': r.width,
        'height': r.height,
      };

  Map<String, Object?> toMap({String idPrefix = ''}) => {
        'id': '$idPrefix$id',
        'title': title,
        'rect': _rect(rect),
        'previewRect': _rect(previewRect ?? rect),
        'cornerRadius': cornerRadius,
        if (previewImagePath != null) 'previewImagePath': previewImagePath,
        'lift': lift,
        'groups': [
          for (final g in groups) [for (final i in g) i.toMap()]
        ],
      };
}

typedef NativeMenuSelection = void Function(String targetId, String itemId);

/// M53 — Apple Pencil hardware gestures (UIPencilInteraction). [event] is
/// `tap` (double-tap on Pencil 2 / Pro) or `squeeze` (Pencil Pro); [x]/[y]
/// carry the squeeze hover pose in window coordinates when iOS provides one.
/// Only fires when the user's system Pencil preference allows app actions.
typedef NativePencilGesture = void Function(String event, double? x, double? y);

class NativeMenu {
  NativeMenu._();

  static const MethodChannel _ch = MethodChannel('prototype/native_menu');

  /// There is ONE interaction on the Flutter view but several widgets want to
  /// own targets (the gallery, the model browser). Each registers under its own
  /// scope and ids travel prefixed, so a selection can be routed back. Without
  /// this a disposing widget would wipe a freshly-mounted widget's targets —
  /// and those two change over in an unspecified order.
  static const String kGallery = 'gallery';

  /// M261 — the scope the Settings sheet reports its taps under. Its "target"
  /// is the SECTION id and its "item" is the row id, so one handler receives
  /// (section, row) and can switch on the pair.
  static const String kSettings = 'settings';

  /// The row id that means "the sheet closed", by Done or by a swipe down.
  /// Must stay identical to `NativeMenuPlugin.settingsClosed`.
  static const String kSettingsClosed = '__closed__';
  static const String kLayers = 'layers';
  static const String _sep = '\u0001';

  /// M237 — push the app's appearance into UIKit.
  ///
  /// Every native surface (the glass ribbon, model browser, tab bar, tool bar
  /// and the menu containers) pins its trait to this rather than resolving it
  /// from the system, so the material and the Flutter text drawn over it never
  /// come from two different schemes. A no-op off iOS, and a swallowed failure
  /// everywhere: an appearance that did not arrive is a cosmetic problem, and
  /// throwing into the widget tree over one is not.
  static Future<void> setAppearance({required bool dark}) async {
    // Recorded FIRST and unconditionally, because off iOS this is not a
    // message to UIKit that gets dropped — it is the only thing that tells the
    // Flutter Liquid Glass which scheme it is standing in. See GlassPanel.
    isDarkAppearance.value = dark;
    if (!isSupported) return;
    try {
      await _ch.invokeMethod<void>('setAppearance', {'dark': dark});
    } catch (_) {
      // Older host build without the method, or no plugin at all.
    }
  }

  /// The scheme the app is currently in, as the app last pushed it.
  ///
  /// A notifier rather than a field: the glass surfaces listen, so a theme
  /// switch changes the material on the next frame without the app having to
  /// know that anything but UIKit was listening. Defaults to dark, which is
  /// what the app starts in before [T.followPlatform] has run.
  static final ValueNotifier<bool> isDarkAppearance = ValueNotifier<bool>(true);

  /// A PNG of the whole window, or null where there is no window to grab.
  ///
  /// Flutter can only screenshot what Flutter drew, and on this app that is a
  /// minority of the screen — the 3D body is a RealityKit platform view and
  /// the ribbon, tab bar and model browser are UIKit glass. A bug report about
  /// any of those used to arrive with a picture that did not contain them.
  ///
  /// Swallows failures like the rest of this class: a report with no picture
  /// is worth much more than no report.
  static Future<Uint8List?> screenshot() async {
    if (!isSupported) return null;
    try {
      return await _ch.invokeMethod<Uint8List>('screenshot');
    } catch (_) {
      // Older host build without the method, or no plugin at all.
      return null;
    }
  }

  /// Bug report #11 — the accent the user chose, for the glass chrome.
  ///
  /// TWO colours, not one, and not the resolved one. UIKit resolves against
  /// the trait `AppearanceBinder` pins, exactly as the Dart side picks a
  /// [Palette]; sending only the active colour would be right until the next
  /// appearance switch and wrong after it, which is the staleness M237 exists
  /// to prevent.
  ///
  /// Swallows failures like [setAppearance]: a tab bar still wearing last
  /// session's teal is cosmetic, not a crash.
  static Future<void> setAccent({required int light, required int dark}) async {
    if (!isSupported) return;
    try {
      await _ch.invokeMethod<void>('setAccent', {'light': light, 'dark': dark});
    } catch (_) {
      // Older host build without the method, or no plugin at all.
    }
  }

  static final Map<String, List<NativeMenuTarget>> _scopes = {};
  static final Map<String, NativeMenuSelection> _handlers = {};
  static NativePencilGesture? _pencil;
  static bool _wired = false;

  /// True only where a real UIKit menu can exist. `Platform.isIOS` is false on
  /// the Linux/macOS host that runs `flutter test`, which is exactly what keeps
  /// the suite free of platform channels.
  ///
  /// This gates the SURFACES — context menus, alerts, action sheets, the
  /// Settings form, the glass chrome. Off iOS the app draws every one of them
  /// itself, in its own design system, and those Flutter paths are what make
  /// the desktop build the same app rather than a GTK lookalike. It is
  /// deliberately NOT the gate for the file errands; see [hasFileSurfaces].
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  /// True where the PLATFORM can run a file errand for us: put a copy where
  /// the user points, hand back a file to open, open one in another program,
  /// ask the mesh-import question, and answer a performance probe.
  ///
  /// A separate gate from [isSupported] because the two halves of this plugin
  /// have opposite answers on the desktop. There is no reason for the app to
  /// draw its own Save dialog — the desktop has one, the user knows it, and
  /// its recent places and its network mounts are things no Flutter widget
  /// can reproduce. There is every reason for the app to draw its own menus.
  ///
  /// macOS is included even though this repo ships no macOS runner yet: the
  /// channel simply answers `not implemented` there and every call below
  /// already degrades to its null, so being wrong about it costs nothing and
  /// being right about it costs one term.
  static bool get hasFileSurfaces =>
      !kIsWeb &&
      (Platform.isIOS ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isMacOS);

  static void setSelectionHandler(String scope, NativeMenuSelection? handler) {
    if (handler == null) {
      _handlers.remove(scope);
    } else {
      _handlers[scope] = handler;
    }
    _wire();
  }

  /// Registers (or clears, with null) the Pencil gesture sink and tells the
  /// native side to attach/detach the UIPencilInteraction. A no-op off iOS —
  /// the host suite never sees the channel.
  static void setPencilHandler(NativePencilGesture? handler) {
    _pencil = handler;
    _wire();
    if (!isSupported) return;
    _invoke<bool>('pencilInterest', {'on': handler != null});
  }

  /// Where this package narrates what the user picked and what the native
  /// side answered. The app installs its logger here at start-up; in tests and
  /// off iOS it stays null and nothing is recorded.
  ///
  /// This exists because of #12. Export from a gallery card did nothing, and
  /// the diagnostic bundle filed against it recorded FIFTY SECONDS of silence
  /// between the app's last log line and the report — the whole interaction
  /// happened in the dark, so neither a person nor the bug-fix pipeline could
  /// tell how far the tap had got. Every native surface answers through here
  /// now, so the next report says which action was picked and what came back.
  static void Function(String message)? trace;

  static void _log(String message) {
    final sink = trace;
    if (sink != null) sink(message);
  }

  static void _wire() {
    if (_wired || !isSupported) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'pencil') {
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        final ev = args?['event'];
        if (ev is String) {
          _pencil?.call(
              ev, (args?['x'] as num?)?.toDouble(), (args?['y'] as num?)?.toDouble());
        }
        return null;
      }
      if (call.method != 'selected') return null;
      final args = (call.arguments as Map?)?.cast<String, Object?>();
      final target = args?['target'];
      final item = args?['item'];
      if (target is! String || item is! String) return null;
      final cut = target.indexOf(_sep);
      final scope = cut < 0 ? '' : target.substring(0, cut);
      final id = cut < 0 ? target : target.substring(cut + 1);
      final handler = _handlers[scope];
      // An unclaimed scope is silent otherwise, and looks exactly like a menu
      // that did nothing — which is the fault this trace was added for.
      _log(handler == null
          ? 'picked "$item" on $scope/$id — NO HANDLER for scope "$scope"'
          : 'picked "$item" on $scope/$id');
      handler?.call(id, item);
      return null;
    });
  }

  /// Replaces the targets owned by [scope]. An empty list drops the scope; when
  /// no scope holds a target the interaction is removed from the Flutter view
  /// entirely, so nothing on screen reacts to a long press.
  static Future<void> setTargets(
      String scope, List<NativeMenuTarget> targets) async {
    if (targets.isEmpty) {
      _scopes.remove(scope);
    } else {
      _scopes[scope] = targets;
    }
    if (!isSupported) return;
    final all = <Map<String, Object?>>[];
    _scopes.forEach((s, list) {
      for (final t in list) {
        all.add(t.toMap(idPrefix: '$s$_sep'));
      }
    });
    await _invoke<bool>('setTargets', {'targets': all});
  }

  /// M261 — present the app's Settings as a real UIKit grouped table.
  ///
  /// [sections] is the whole screen, rebuilt from Dart state on every change:
  /// this sheet holds no state of its own, which is what lets a language
  /// switch relabel it under the user's finger. See SettingsSheet.swift.
  ///
  /// Returns false when there is no iOS sheet — off iOS, or when UIKit had
  /// nothing to present from — so the caller can fall back rather than
  /// believing a screen opened that did not.
  static Future<bool> showSettings({
    required String title,
    required String doneLabel,
    required List<Map<String, Object?>> sections,
  }) async {
    if (!isSupported) return false;
    return await _invoke<bool>('showSettings', {
          'title': title,
          'doneLabel': doneLabel,
          'sections': sections,
        }) ??
        false;
  }

  /// Redraw an open Settings sheet in place. False when none is up.
  static Future<bool> updateSettings({
    required String title,
    required String doneLabel,
    required List<Map<String, Object?>> sections,
  }) async {
    if (!isSupported) return false;
    return await _invoke<bool>('updateSettings', {
          'title': title,
          'doneLabel': doneLabel,
          'sections': sections,
        }) ??
        false;
  }

  /// Close it from Dart (nothing does today; the user closes it).
  static Future<void> dismissSettings() async {
    if (!isSupported) return;
    await _invoke<bool>('dismissSettings', const {});
  }

  /// Native single-field alert. Returns null when cancelled.
  static Future<String?> promptText({
    required String title,
    String? message,
    String initialValue = '',
    String placeholder = '',
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
  }) async {
    if (!isSupported) return null;
    return _invoke<String>('prompt', {
      'title': title,
      'message': message,
      'initialValue': initialValue,
      'placeholder': placeholder,
      'confirmLabel': confirmLabel,
      'cancelLabel': cancelLabel,
    });
  }

  /// Native confirmation alert. [destructive] paints the confirm action red.
  static Future<bool> confirm({
    required String title,
    String? message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    bool destructive = true,
  }) async {
    if (!isSupported) return false;
    return await _invoke<bool>('confirm', {
          'title': title,
          'message': message,
          'confirmLabel': confirmLabel,
          'cancelLabel': cancelLabel,
          'destructive': destructive,
        }) ??
        false;
  }

  /// Native action sheet (the gallery "+"). Returns the chosen item id, or
  /// null when cancelled — or when off iOS, so the caller can fall back to a
  /// Flutter menu. [anchor] is REQUIRED on iPad: an action sheet is a popover
  /// and UIKit raises without a source rectangle, exactly like the share sheet.
  static Future<String?> menu({
    required List<NativeMenuItem> items,
    required Rect anchor,
    String? title,
    String cancelLabel = 'Cancel',
  }) async {
    if (!isSupported) return null;
    final chosen = await _invoke<String>('menu', {
      'items': [for (final i in items) i.toMap()],
      'anchor': NativeMenuTarget._rect(anchor),
      if (title != null) 'title': title,
      'cancelLabel': cancelLabel,
    });
    _log('menu [${[for (final i in items) i.id].join(', ')}]'
        ' → ${chosen ?? 'cancelled or not presented'}');
    return chosen;
  }

  /// How a mesh should be brought in: reconstructed as CAD surfaces, or kept
  /// as the triangles it already is.
  ///
  /// Returns [MeshImportChoice.convert], [MeshImportChoice.faceted], or null
  /// when the user cancelled — and also when there is no native sheet to show
  /// (a test host, desktop), which is why the caller must treat null as "do
  /// not import" rather than as a signal to pick one itself. Silently
  /// choosing on the user's behalf is the exact outcome the sheet exists to
  /// prevent; a caller that wants a default off-iOS should say so at the call
  /// site, where the choice is visible.
  ///
  /// A null [facetedLabel] leaves that choice OUT — for a mesh the 1:1 path
  /// cannot take. [facetedDetail] then carries the reason instead of that
  /// choice's description, and appears in the body on its own. Offering a
  /// button the kernel is going to refuse is worse than not offering it.
  ///
  /// No anchor, unlike [menu]: this is a centred alert, not a popover. It is
  /// asked straight after the Files picker closes, when there is no button it
  /// could point at. See ImportChoiceSheet.swift.
  static Future<MeshImportChoice?> importChoice({
    required String title,
    String? message,
    required String convertLabel,
    required String convertDetail,
    required String? facetedLabel,
    required String facetedDetail,
    String cancelLabel = 'Cancel',
  }) async {
    if (!hasFileSurfaces) return null;
    final id = await _invoke<String>('importChoice', {
      'title': title,
      'message': message,
      'convertLabel': convertLabel,
      'convertDetail': convertDetail,
      if (facetedLabel != null) 'facetedLabel': facetedLabel,
      'facetedDetail': facetedDetail,
      'cancelLabel': cancelLabel,
    });
    return MeshImportChoice.byId(id);
  }

  /// System share sheet. [anchor] is required on iPad: UIKit raises if a
  /// popover has no source rectangle.
  ///
  /// [saveTitle] is the DESKTOP's dialog title. iOS localises its own share
  /// sheet and ignores it; a GTK or Win32 chooser has a title bar we have to
  /// fill, and filling it in English inside a natively German app is exactly
  /// the seam a user sees. Passed in rather than read from a global because
  /// this package has no localisations of its own — the same reason
  /// [NativeBusy.show] takes its stage names and [importChoice] takes its
  /// button labels.
  static Future<bool> shareFile(String path,
          {required Rect anchor, String? saveTitle}) =>
      _sheet('share', path, anchor, saveTitle);

  /// Files exporter ("Save to Files"). Exports a COPY — the sketch stays put.
  static Future<bool> exportFile(String path,
          {required Rect anchor, String? saveTitle}) =>
      _sheet('export', path, anchor, saveTitle);

  static Future<bool> _sheet(
      String method, String path, Rect anchor, String? saveTitle) async {
    if (!hasFileSurfaces) return false;
    final ok = await _invoke<bool>(method, {
          'path': path,
          'anchor': NativeMenuTarget._rect(anchor),
          if (saveTitle != null) 'saveTitle': saveTitle,
        }) ??
        false;
    // `false` here means UIKit had nowhere to present from, or the file was
    // not there — both look identical on screen: nothing opens.
    _log('$method ${path.split('/').last} → ${ok ? 'presented' : 'REFUSED'}');
    return ok;
  }

  /// M214 — thermal state, physical footprint, memory headroom and per-thread
  /// CPU, straight from the OS. Empty map when the host cannot answer.
  ///
  /// These are the facts that decide whether an M4 measurement says anything
  /// about an M2 or an A-series chip, and every one of them is invisible from
  /// Dart. Above all THERMAL STATE: a fanless iPad throttles under a sustained
  /// benchmark, and a report that does not say the device was in `.serious`
  /// invites the conclusion that the code got slower when the silicon got
  /// hotter. See PerfProbe.swift for what each key means and why it is here.
  ///
  /// Returns raw values rather than recording them, so the caller decides
  /// whether this is a scenario sample, a bundle snapshot or a live gauge.
  static Future<Map<String, Object?>> perfProbe() async {
    try {
      final r = await _ch.invokeMapMethod<String, Object?>('perfProbe');
      return r ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {}; // host without the plugin — a probe is never critical
    }
  }

  static Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      // Never let a menu problem take down a frame — but do not let it vanish
      // either. Swallowed here, this was indistinguishable from a tap that
      // never happened.
      _log('$method failed: ${e.code} ${e.message ?? ''}');
      return null;
    } on MissingPluginException {
      return null; // plugin absent (unexpected host) — stay silent
    }
  }

  /// Test-only: forget every registered scope and handler.
  static void resetForTest() {
    _scopes.clear();
    _handlers.clear();
  }

  // ---- M177: opening a document in place ----

  /// Presents the system picker in OPEN mode and returns
  /// `{'path': ..., 'bookmark': ...}` for the file the user chose, or null if
  /// they cancelled (or we are not on iOS).
  ///
  /// Deliberately NOT the ordinary file picker: that one imports a COPY into
  /// tmp, so a document opened from Files could never be saved back to. The
  /// bookmark is the durable handle — hold on to it and pass it to [resolve]
  /// on the next launch.
  /// [openTitle], [knownFilterName] and [allFilesFilterName] are the DESKTOP
  /// chooser's chrome — see [shareFile] for why they are arguments. iOS
  /// ignores them; its picker names itself and has no filter rows.
  static Future<Map<String, String>?> openInPlace({
    required List<String> extensions,
    Rect? anchor,
    String? openTitle,
    String? knownFilterName,
    String? allFilesFilterName,
  }) async {
    if (!hasFileSurfaces) return null;
    final res = await _invoke<Map<Object?, Object?>>('openInPlace', {
      'extensions': extensions,
      if (anchor != null) 'anchor': NativeMenuTarget._rect(anchor),
      if (openTitle != null) 'title': openTitle,
      if (knownFilterName != null) 'knownFilterName': knownFilterName,
      if (allFilesFilterName != null) 'allFilesFilterName': allFilesFilterName,
    });
    return _stringMap(res);
  }

  /// What [openInPlace]'s extensions resolve to, as "ext=identifier" pairs.
  ///
  /// Purely diagnostic, and deliberately a SEPARATE call: presenting the
  /// picker can take the whole process down, so anything we want to know about
  /// why has to be asked — and logged — before that happens. An identifier
  /// beginning `dyn.` means iOS has no declaration for that extension and
  /// invented a placeholder; those are what the picker chokes on.
  static Future<List<String>> probeContentTypes(List<String> extensions) async {
    if (!hasFileSurfaces) return const [];
    final res =
        await _invoke<List<Object?>>('probeContentTypes', {'extensions': extensions});
    return [for (final e in res ?? const []) '$e'];
  }

  /// Re-acquires access to a document remembered from an earlier launch.
  ///
  /// Returns its CURRENT path — which can differ from the stored one, because
  /// the user is free to move or rename the file between launches — and a
  /// refreshed bookmark when the old one had gone stale. Null when the file
  /// can no longer be reached at all.
  static Future<Map<String, String>?> resolveDocument(String bookmark) async {
    if (!hasFileSurfaces) return null;
    return _stringMap(await _invoke<Map<Object?, Object?>>(
        'resolveBookmark', {'bookmark': bookmark}));
  }

  /// Ends access to an externally-opened document.
  static Future<void> releaseDocument(String path) async {
    if (!hasFileSurfaces) return;
    await _invoke<bool>('releaseDocument', {'path': path});
  }

  static Map<String, String>? _stringMap(Map<Object?, Object?>? raw) {
    if (raw == null) return null;
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v is String) out[k] = v;
    });
    return out.containsKey('path') ? out : null;
  }
}

/// M106 — a REAL Apple Liquid Glass surface (`UIGlassEffect`, iOS 26), for use
/// as the background of a panel.
///
/// On the iPad this is the system material, with its own refraction, specular
/// edge and response to what is behind it. Below iOS 26 the native side falls
/// back to `UIBlurEffect(.systemMaterial)` so the panel stays legible.
///
/// M367 — AND OFF iOS IT IS NOW THE SAME MATERIAL, drawn by Flutter.
///
/// The old comment here said the material "cannot be reproduced
/// client-side", and for a `BackdropFilter` that was true: a gaussian is a
/// frosted pane and cannot bend. What changed is that a FRAGMENT SHADER can
/// now be an image filter (`ImageFilter.shader`, Impeller), and the engine
/// hands such a shader the whole backdrop as a texture — including the pixels
/// BESIDE the panel. That is enough to build the real thing: refraction at the
/// rim, chromatic dispersion, a specular edge and the tint. See
/// liquid_glass.dart, which is where all of that lives.
///
/// This matters more than it looks. The app's layout is BUILT around the
/// material — the document runs edge to edge under the ribbon band precisely
/// so the glass has something to refract, and [RibbonSurface.isGlass] switches
/// that layout on the strength of this getter. A desktop build that answered
/// "no glass" got a different layout as well as a different surface, which is
/// two ways of not being the same app.
///
/// It takes no touches — put your own content above it in a [Stack].
class GlassPanel extends StatelessWidget {
  /// Rounds the glass itself, in points. 0 = full-bleed surface, which is what
  /// the model browser has always used. A FLOATING card asks for its own
  /// radius (M146: the ribbon uses 18, the browser's value) — clipping a
  /// platform view from the Flutter side does not work reliably, so on iOS the
  /// corners are cut in UIKit. Off iOS this is what tells the shader where the
  /// rim is; the CALLER still clips, with the superellipse the rest of the app
  /// uses.
  final double cornerRadius;

  const GlassPanel({super.key, this.cornerRadius = 0});

  /// Whether there is a real material here.
  ///
  /// True on iOS, and true wherever a shader can run as an image filter — in
  /// practice a desktop build on Impeller. Deliberately NOT true on the
  /// flutter_test host, where Impeller is off: the painted fallback is what
  /// the suite has always exercised and what a platform without the material
  /// still gets, and both need to stay covered.
  ///
  /// Synchronous and stable from the first frame. It is not a function of
  /// whether the shader program has finished loading, because callers use it
  /// to decide layout and a layout that changes when an asset resolves is a
  /// layout that jumps at launch. A program that fails to load costs
  /// refraction, not the surface.
  static bool get isSupported =>
      !kIsWeb && (Platform.isIOS || LiquidGlass.isAvailable);

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      return IgnorePointer(
        child: UiKitView(
          viewType: 'prototype/glass_panel',
          creationParams: <String, Object?>{'cornerRadius': cornerRadius},
          creationParamsCodec: const StandardMessageCodec(),
        ),
      );
    }
    if (!LiquidGlass.isAvailable) return const SizedBox.shrink();
    // The scheme comes from the app's own push (NativeMenu.setAppearance), so
    // the material follows a theme switch on the next frame — the same signal
    // UIKit's AppearanceBinder is pinned to, and for the same reason: a
    // surface and the text over it must never come from two different schemes.
    final glass = ValueListenableBuilder<bool>(
      valueListenable: NativeMenu.isDarkAppearance,
      builder: (context, dark, _) => LiquidGlass(
        cornerRadius: cornerRadius,
        style: dark ? LiquidGlassStyle.dark : LiquidGlassStyle.light,
      ),
    );
    // THE PANEL CLIPS ITSELF, and it has to.
    //
    // A backdrop filter with nothing above it filtering the WHOLE backdrop is
    // not a subtle bug: the first build of this blurred the entire document,
    // every panel over it, and then the next glass surface blurred that. None
    // of the callers clip, because on the iPad they never had to — UIKit cuts
    // the platform view's corners itself, which is exactly what the
    // `cornerRadius` parameter was for. So the Flutter material takes on the
    // same job, with the superellipse the rest of the app is cut with.
    final Widget clipped = cornerRadius <= 0
        ? ClipRect(child: glass)
        : ClipRSuperellipse(
            borderRadius: BorderRadius.circular(cornerRadius),
            child: glass,
          );

    // AND THE CONTOUR, WHICH IS OUTSIDE THE CLIP, and has to be.
    //
    // The device draws one dark pixel round the panel — the same width on all
    // four edges, no offset, and the pixel beside it is the untouched
    // backdrop, so it is the material's own outer line rather than a shadow.
    // Scanned across the browser's vertical edges, which resolve it: a
    // backdrop of 236 comes out 173 and one of 138 comes out 75.
    //
    // It is what makes the surface read as an OBJECT over a busy render
    // instead of a brightened patch of it, and it was the most visible thing
    // missing from the first build of this material. It cannot come from the
    // shader: the shader is a backdrop filter and the clip above cuts it at
    // the panel's edge, which is the one place the line is not.
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        clipped,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: NativeMenu.isDarkAppearance,
              builder: (context, dark, _) => CustomPaint(
                painter: _GlassContour(
                  radius: cornerRadius,
                  opacity: (dark
                          ? LiquidGlassStyle.dark
                          : LiquidGlassStyle.light)
                      .rimShade,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The material's own outer line: one device pixel, just outside the panel.
///
/// Strokes half a device pixel OUTSIDE the box, so the line lands on the pixel
/// column beside the panel rather than on its bright specular hairline — the
/// order the device draws them in. A parent that clips its children costs the
/// line and nothing else.
class _GlassContour extends CustomPainter {
  final double radius;
  final double opacity;
  final double devicePixelRatio;

  const _GlassContour({
    required this.radius,
    required this.opacity,
    required this.devicePixelRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.isEmpty) return;
    final double w = 1 / devicePixelRatio;
    final Rect outer = (Offset.zero & size).inflate(w / 2);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    if (radius <= 0) {
      canvas.drawRect(outer, paint);
      return;
    }
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(outer, Radius.circular(radius + w / 2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassContour old) =>
      old.radius != radius ||
      old.opacity != opacity ||
      old.devicePixelRatio != devicePixelRatio;
}
