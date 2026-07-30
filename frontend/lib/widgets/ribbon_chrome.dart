// Prototype — M146: the ribbon's SURFACE, separated from its content.
//
// Until now the ribbon was an opaque `T.panel` bar with two flat 2 pt borders,
// sitting in the main Column so the viewport began below it. This file makes
// the surface a real Apple Liquid Glass panel (the same `GlassPanel` platform
// view M106 introduced for the model browser) and turns the two blue borders
// into lit edges instead of hairlines.
//
// Only the SURFACE is native. Icons, labels, buttons, flyouts and the
// horizontal scroll stay exactly the Flutter tree they were — that is the
// whole point of doing this step first. The glass is a background with
// `isUserInteractionEnabled = false` on the UIKit side and an `IgnorePointer`
// on ours (M48: a platform view that takes touches swallows the panel's own
// gestures), so scrolling and every button behave as before.
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../theme.dart';

/// One of the two blue edges of the ribbon.
///
/// The mock drew these as flat `BorderSide`s. On glass a flat line reads as a
/// sticker: the surface underneath moves and refracts, the line does not. So
/// each edge now has
///   * a horizontal ALPHA RAMP — full strength across the middle, fading out
///     at both ends, so the line belongs to the panel rather than being cut
///     off by the screen edge;
///   * a bright 1 pt core with a dimmer 1 pt shoulder, which is what gives it
///     depth at 2 pt total (the mock's width, unchanged);
///   * a soft glow spilling AWAY from the ribbon, so the top edge lights the
///     status bar and the bottom edge lights the model behind it.
///
/// Colours are still `T.ribbonTop` / `T.ribbonBottom` from the mock; nothing
/// here invents a new blue.
class RibbonEdgeLine extends StatelessWidget {
  /// Top edge (bright, .85 alpha in the mock) or bottom edge (soft, .45).
  final bool top;

  const RibbonEdgeLine({super.key, required this.top});

  /// Total thickness, unchanged from the mock's `BorderSide(width: 2)`.
  static const double thickness = 2;

  /// How far the glow reaches past the line, in logical pixels.
  static const double glow = 7;

  Color get core => top ? T.ribbonTop : T.ribbonBottom;

  /// The specular highlight riding on the bright half of the line. Apple's
  /// glass edges are lighter than their fill where the light hits; a pure
  /// blue-on-blue line looks painted next to that.
  Color get sheen => Color.lerp(core, Colors.white, top ? 0.45 : 0.30)!;

  @override
  Widget build(BuildContext context) {
    // Alpha ramp along the ribbon. Symmetric, and short enough that the middle
    // 80 % is at full strength — this is an edge, not a vignette.
    List<Color> ramp(Color c) => [
          c.withValues(alpha: 0),
          c.withValues(alpha: c.a * 0.55),
          c,
          c,
          c.withValues(alpha: c.a * 0.55),
          c.withValues(alpha: 0),
        ];
    const stops = [0.0, 0.06, 0.16, 0.84, 0.94, 1.0];

    return IgnorePointer(
      child: SizedBox(
        height: thickness,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // Glow, spilling away from the panel.
            Positioned(
              left: 0,
              right: 0,
              top: top ? -glow : null,
              bottom: top ? null : -glow,
              height: glow + thickness,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: top ? Alignment.bottomCenter : Alignment.topCenter,
                    end: top ? Alignment.topCenter : Alignment.bottomCenter,
                    colors: [
                      core.withValues(alpha: core.a * 0.38),
                      core.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            // The 2 pt line itself: bright core against the panel, dimmer
            // shoulder against the outside.
            Column(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: ramp(top ? sheen : core),
                        stops: stops,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: ramp(top ? core : sheen),
                        stops: stops,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The ribbon's background surface.
///
/// On iOS this is the real `UIGlassEffect` platform view, with a very slight
/// tint so the ribbon still reads as the app's own chrome rather than a
/// window into the model. Everywhere else (host tests, desktop, Android) it
/// falls back to the mock's opaque `T.panel`, so nothing that ever worked
/// stops working and the widget tests keep seeing the colour they expect.
class RibbonSurface extends StatelessWidget {
  const RibbonSurface({super.key});

  /// True when the native glass is available. Callers use this to decide
  /// whether the viewport should run BEHIND the ribbon: over an opaque bar
  /// there is nothing to see, so on those platforms the old layout is kept.
  static bool get isGlass => GlassPanel.isSupported;

  /// Tint laid over the glass. Low alpha on purpose — the whole reason for
  /// the platform view is the system's refraction and specular edge, and a
  /// heavy scrim throws exactly that away.
  static const Color tint = Color(0x40292D33);

  @override
  Widget build(BuildContext context) {
    if (!isGlass) return const ColoredBox(color: T.panel);
    return const IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          GlassPanel(),
          ColoredBox(color: tint),
        ],
      ),
    );
  }
}
