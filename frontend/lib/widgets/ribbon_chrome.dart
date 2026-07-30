// Prototype — M146: the ribbon's SURFACE, separated from its content.
//
// The ribbon was an opaque `T.panel` strip with two flat blue borders, sitting
// in the main Column so the viewport began below it. It is now a FLOATING
// Liquid Glass card, built to exactly the model browser's recipe: same
// `GlassPanel` platform view, same 18 pt continuous corners, same 28 pt side
// inset, and — the part that actually mattered on the device — the same DARK
// trait environment.
//
// The first device build came out milky white. `UIGlassEffect` adapts to its
// trait collection, a Flutter platform view inherits the host's, and the host
// is light; `GlassBrowserView` had always set `overrideUserInterfaceStyle =
// .dark` and `GlassPanelView` never had. Two panels, one effect, one line of
// difference. Fixed in the plugin, so the browser's own fallback gets it too.
//
// No tint is laid over the glass any more. The tint was there to keep the bar
// reading as chrome, and it is exactly the wrong tool: it dulls the refraction
// that is the only reason to pay for a platform view. The browser does not
// tint, so neither does this.
//
// Only the SURFACE is native. Icons, labels, buttons, flyouts and the
// horizontal scroll stay the Flutter tree they were.
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../theme.dart';

/// Where the ribbon sits, and where everything else may therefore start.
///
/// The ribbon floats over the content area, so the model browser, the ViewCube,
/// the triad and the modeless dialogs all share a coordinate space with it and
/// would otherwise be drawn UNDERNEATH it — which is precisely what the first
/// device build did. They read [bottom] instead of assuming they own the top of
/// the screen.
class RibbonMetrics {
  /// Padding around the floating card. Horizontal value is the model browser's
  /// 28 pt, so the two panels share a left edge.
  static const EdgeInsets pad = EdgeInsets.fromLTRB(28, 8, 28, 0);

  /// The browser's radius, deliberately.
  static const double radius = 18;

  /// Bottom edge of the card in the content Stack's coordinates, including
  /// [pad]. Zero until the ribbon has been laid out once, and zero forever on
  /// the platforms where the ribbon keeps its own row in the Column — in both
  /// cases "no inset" is the right answer.
  static final ValueNotifier<double> bottom = ValueNotifier<double>(0);

  /// Gap between the card and whatever floats below it.
  static const double gap = 10;

  /// Convenience: the first y a floating overlay may occupy.
  static double get contentTop =>
      bottom.value <= 0 ? 0 : bottom.value + gap;

  /// Rebuilds [child] whenever the ribbon's height changes.
  static Widget build(Widget Function(BuildContext, double top) b) =>
      ValueListenableBuilder<double>(
        valueListenable: bottom,
        builder: (ctx, _, __) => b(ctx, contentTop),
      );
}

/// Measures the ribbon card and publishes its bottom edge.
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
    final h = box.size.height;
    if ((RibbonMetrics.bottom.value - h).abs() > 0.5) {
      RibbonMetrics.bottom.value = h;
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_report);
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// The ribbon's background surface: the same glass as the model browser.
class RibbonSurface extends StatelessWidget {
  const RibbonSurface({super.key});

  /// True when the native glass is available. Callers use this to decide
  /// whether the ribbon FLOATS over the viewport: over an opaque bar there is
  /// nothing to see through, so those platforms keep the old Column layout.
  static bool get isGlass => GlassPanel.isSupported;

  @override
  Widget build(BuildContext context) {
    if (!isGlass) return const ColoredBox(color: T.panel);
    return const GlassPanel(cornerRadius: RibbonMetrics.radius);
  }
}
