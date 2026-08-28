// Prototype — M146: the ribbon's SURFACE, separated from its content.
//
// The ribbon was an opaque `T.panel` strip with two flat blue borders, sitting
// in the main Column so the viewport began below it. It became a FLOATING
// Liquid Glass card (M146), built to the model browser's recipe: same
// `GlassPanel` platform view, same 18 pt continuous corners, same 28 pt side
// inset, and — the part that actually mattered on the device — the same DARK
// trait environment.
//
// M284 (surface A) de-floats it again. The card is now a FLUSH BAND: no side
// inset, no corner radius, no shadow, one hairline seam on the edge that faces
// the viewport. That wins back the ~28 pt of panel width the two side insets
// were giving away, and it is what makes the band read as the OUTERMOST chrome
// rather than a card lying on the canvas. The glass stays — it is still the
// only reason to pay for a platform view — but it now runs to the screen edge.
//
// The band can be docked on any of the four edges (see [RibbonPosition]); the
// position is remembered in settings.json and every floating panel asks
// [RibbonMetrics] where the band ends before placing itself, so the band is
// always BEHIND the chrome that floats over the viewport.
//
// No tint is laid over the glass any more. The tint was there to keep the bar
// reading as chrome, and it is exactly the wrong tool: it dulls the refraction
// that is the only reason to pay for a platform view. The browser does not
// tint, so neither does this.
//
// Only the SURFACE is native. Icons, labels, buttons, flyouts and the
// horizontal scroll stay the Flutter tree they were.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../log.dart';
import '../theme.dart';

/// Which edge the ribbon band is docked on.
enum RibbonPosition {
  top,
  bottom,
  left,
  right;

  /// The name as it is stored in settings.json. NOT shown to anyone — the
  /// visible names come from the ARB.
  String get id => name;

  static RibbonPosition? byId(Object? s) {
    for (final p in RibbonPosition.values) {
      if (p.id == s) return p;
    }
    return null;
  }
}

/// Where the ribbon sits, and where everything else may therefore start.
///
/// The ribbon band is the outermost chrome: the model browser, the ViewCube,
/// the triad, the quick-tool rail and the modeless dialogs all share a
/// coordinate space with it and must start on the inner side of it. They read
/// the per-edge insets below instead of assuming they own an edge of the
/// screen.
class RibbonMetrics {
  /// Surface A: the band is FLUSH, so it keeps no inset from the edge and no
  /// corner radius. The old floating card used 14 pt of side inset and an
  /// 18 pt radius (and the tab bar still uses its own floating geometry).
  static const double side = 0;
  static const double radius = 0;

  /// Flush band: no padding between the band's outer edge and the screen. The
  /// floating card used [EdgeInsets.fromLTRB(14, 8, 14, 0)].
  static EdgeInsets get pad => EdgeInsets.zero;

  /// Width of the band when docked left or right (surface C's rail width).
  static const double railWidth = 104;

  /// Gap between the band and whatever floats beside it.
  static const double gap = 10;

  /// The active dock position. Defaults to [RibbonPosition.top], the flush
  /// band.
  static final ValueNotifier<RibbonPosition> position =
      ValueNotifier<RibbonPosition>(RibbonPosition.top);

  static RibbonPosition get dock => position.value;
  static bool get isTop => dock == RibbonPosition.top;
  static bool get isBottom => dock == RibbonPosition.bottom;
  static bool get isLeft => dock == RibbonPosition.left;
  static bool get isRight => dock == RibbonPosition.right;
  static bool get isVertical => isLeft || isRight;
  static bool get isHorizontal => isTop || isBottom;

  /// The band's thickness in its cross axis — height for top/bottom, width for
  /// left/right — in the content Stack's coordinates. Zero until the band has
  /// been laid out once, and zero forever on the platforms where the ribbon
  /// keeps its own row in the Column; in both cases "no inset" is the right
  /// answer.
  static final ValueNotifier<double> extent = ValueNotifier<double>(0);

  static double get _thickness =>
      extent.value <= 0 ? 0 : extent.value + gap;

  /// The first coordinate a floating overlay may occupy on each edge. An edge
  /// without the band reads zero, which is the correct "no inset".
  static EdgeInsets get contentInsets => EdgeInsets.fromLTRB(
        isLeft ? _thickness : 0,
        isTop ? _thickness : 0,
        isRight ? _thickness : 0,
        isBottom ? _thickness : 0,
      );

  static double get contentTop => contentInsets.top;
  static double get contentRight => contentInsets.right;
  static double get contentBottom => contentInsets.bottom;
  static double get contentLeft => contentInsets.left;

  /// Both [position] and [extent] change where the floating chrome may sit, so
  /// a rebuild has to listen to the two together.
  static final Listenable _changes = Listenable.merge([position, extent]);

  /// Rebuilds [child] whenever the band moves or its thickness changes.
  ///
  /// [b] receives the top inset; callers anchored to a different edge read the
  /// matching [contentLeft]/[contentRight]/[contentBottom] getter directly —
  /// the rebuild still happens because this listens to [_changes].
  static Widget build(Widget Function(BuildContext, double top) b) =>
      AnimatedBuilder(
        animation: _changes,
        builder: (ctx, _) => b(ctx, contentTop),
      );

  // ---- the switch ----------------------------------------------------------

  static RibbonStore? _store;

  /// Point the switch at a settings file and adopt whatever it remembers.
  ///
  /// Called from [AppState.init], off the launch path, for the same reason
  /// [T.attachStore] is: a settings read in front of the first frame is a
  /// launch-time regression this repository measures.
  static void attachStore(RibbonStore store) {
    _store = store;
    final saved = store.load();
    if (saved != null) position.value = saved;
  }

  /// Switch edge, and remember it.
  static void set(RibbonPosition p) {
    if (p == position.value) return;
    position.value = p;
    _store?.save(p);
  }

  @visibleForTesting
  static void resetForTest() {
    position.value = RibbonPosition.top;
    _store = null;
  }
}

/// Measures the ribbon band and publishes its cross-axis thickness.
///
/// Post-frame and only on change: writing a ValueNotifier during layout would
/// schedule a rebuild from inside one, and this project has already lost a day
/// to a widget that rebuilt itself (M50).
class RibbonMeasure extends StatefulWidget {
  final Widget child;
  const RibbonMeasure({super.key, required this.child});

  @override
  State<RibbonMeasure> createState() => _RibbonMeasureState();
}

class _RibbonMeasureState extends State<RibbonMeasure> {
  final _key = GlobalKey();

  void _report(Duration _) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = RibbonMetrics.isVertical ? box.size.width : box.size.height;
    if ((RibbonMetrics.extent.value - h).abs() > 0.5) {
      RibbonMetrics.extent.value = h;
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_report);
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// The ribbon's background surface: the same glass as the model browser, but
/// flush (square corners, no shadow).
class RibbonSurface extends StatelessWidget {
  const RibbonSurface({super.key});

  /// True when the native glass is available. Callers use this to decide
  /// whether the ribbon FLOATS over the viewport: over an opaque bar there is
  /// nothing to see through, so those platforms keep the old Column layout.
  static bool get isGlass => GlassPanel.isSupported;

  @override
  Widget build(BuildContext context) {
    if (!isGlass) return ColoredBox(color: T.panel);
    return const GlassPanel(cornerRadius: RibbonMetrics.radius);
  }
}

/// Where the ribbon position survives a restart.
///
/// The same file, the same shape and the same swallow-the-error rule as
/// [ThemeStore]: it merges into `settings.json` rather than owning it, so the
/// language and appearance preferences sitting beside it are never dropped.
class RibbonStore {
  final Directory dir;
  const RibbonStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'ribbon';

  File get file => File('${dir.path}/$fileName');

  RibbonPosition? load() {
    try {
      final f = file;
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return null;
      return RibbonPosition.byId(raw[key]);
    } catch (e) {
      // A corrupt settings file costs a ribbon position and nothing else. It
      // must not cost the launch.
      Log.w('ribbon', 'could not read the ribbon position: $e');
      return null;
    }
  }

  void save(RibbonPosition p) {
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
      data[key] = p.id;
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('ribbon', 'could not remember the ribbon position: $e');
    }
  }
}
