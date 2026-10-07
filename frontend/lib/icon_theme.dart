// Prototype — the icon set, recoloured into the active palette.
//
// v2 (design/icons/SPEC.md §12). The redrawn set ("Modern Crisp") changes
// three things below, and the Python / JS ports in
// tools/icon_redesign/build.py + template.html are the reference
// (test/icon_map_parity_test.dart pins this file to them):
//   (a) hue-less greys: a pure-grey ink no longer picks up a pink cast;
//   (b) chromatic ink on a light theme maps into [.22, cap], cap being the
//       lightest L of that hue / saturation that keeps 3.2:1 on T.bg;
//   (c) in an SVG whose root carries data-lit="2", a gradient `stop-color` is
//       MATERIAL, not ink: never inverted, keeps its own hue / saturation when
//       neutral, light theme L' = .10 + .70 L.
// Plus the constraint red: hues >= 345 deg (the CON ink, SPEC §5.5) go to
// [Palette.conMark], not to the error red.
//
// The text below describes the v1 mapping it grew out of; the neutral
// inversion and the per-meaning buckets still hold for flat ink.
//
// M237. `svg_icons.dart` carries 235 colour literals across 49 distinct
// values: the old scheme's blue (#3D9BE9 and four darker stops of it), its
// green, its amber, its red, and a grey ramp from #E8EAEC down to #3A3F45.
// They are not decoration — a ribbon glyph uses two or three stops of one hue
// to model a face and its shadow, which is what makes the set read as one
// family. That is also why they cannot simply be tinted: flattening a glyph to
// a single colour throws the modelling away.
//
// So they are re-mapped by FAMILY, keeping each colour's place inside its own
// glyph:
//
//   * a neutral (saturation under 12%) is a grey stop. On a dark scheme the
//     ramp runs light-on-dark; on a light one it has to run the other way, so
//     its lightness is INVERTED. That single rule is what turns the whole set
//     from "washed out on cream" into ink on paper.
//   * a chromatic colour keeps its lightness ORDER — the light stop stays the
//     light one — but is moved onto the palette's own hue for that meaning:
//     blue is the app's accent, amber is annotation, green is "good", red is
//     "wrong". On a light ground every stop is additionally darkened, because
//     a colour that reads on charcoal is invisible on paper.
//
// The result is cached per palette AND per accent: the mapping is pure, the
// icon strings are constants, and the ribbon rebuilds on every notification.
//
// Per accent as well since bug report #11, and that was a real bug rather than
// caution. The accent override deliberately does NOT build a new Palette — it
// re-tints at the getter — so `identical(_cachedFor, T.palette)` stayed true
// across a change of accent and every icon kept the colour it was first
// rendered in. The report named it: "it doesnt change most of the things like
// icons".
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

// Group 1 tells a gradient stop from flat paint in the same single pass.
final RegExp _hex = RegExp(r'(stop-color=")?#([0-9a-fA-F]{6})\b');

Palette? _cachedFor;
Accent? _cachedAccent;
final Map<String, String> _cache = <String, String>{};

/// The palette colours the icon mapping reads. A value type so the mapping
/// can be tested against the Python reference port without a live [T].
@immutable
class IconTones {
  final bool dark;
  final Color ink, bg, accent, ok, projRef, err, conMark;
  const IconTones({
    required this.dark,
    required this.ink,
    required this.bg,
    required this.accent,
    required this.ok,
    required this.projRef,
    required this.err,
    required this.conMark,
  });

  /// The active palette and accent.
  factory IconTones.current() => IconTones(
        dark: T.isDark,
        ink: T.ink,
        bg: T.bg,
        accent: T.accent,
        ok: T.ok,
        projRef: T.projRef,
        err: T.err,
        conMark: T.conMark,
      );
}

/// Returns [svg] with every `#rrggbb` moved into the active palette.
///
/// Call at the SvgPicture site, never at a top-level constant: the palette can
/// change while the app runs, and a constant would freeze the first one.
String themedIcon(String svg) {
  // AN ICON MAY DECLARE THAT ITS COLOURS ARE THE SPECIFICATION.
  //
  // The mapping below re-hues every chromatic colour into the palette's own,
  // which is right for the app's icon set — one amber means one thing
  // everywhere — and wrong for the handful of glyphs that exist to MATCH
  // something outside this app. The model browser's folder is the case: on the
  // iPad that view is UIKit, and its folder is `GlassBrowserView.folderAmber`,
  // a fixed (0.88, 0.76, 0.44). Run through the mapper the same amber comes out
  // a dark brown, which is a different picture of the same app.
  //
  // `data-fixed` on the root element. SVG ignores unknown attributes and so
  // does flutter_svg, so it costs nothing at the draw site.
  if (svg.contains('data-fixed')) return svg;
  if (!identical(_cachedFor, T.palette) ||
      _cachedAccent != T.accentChoice.value) {
    _cachedFor = T.palette;
    _cachedAccent = T.accentChoice.value;
    _cache.clear();
    _tones = null;
  }
  return _cache.putIfAbsent(
      svg, () => mapIconSvg(svg, _tones ??= IconTones.current()));
}

IconTones? _tones;

/// [themedIcon] for explicit [tones], uncached. Exposed for tests.
@visibleForTesting
String mapIconSvg(String svg, IconTones tones) {
  // SPEC v2 §12 (c): in a data-lit="2" glyph a gradient stop is material.
  final lit = svg.contains('data-lit="2"');
  return svg.replaceAllMapped(_hex, (m) {
    final stop = m.group(1);
    final hex = m.group(2)!;
    return stop != null && lit
        ? '$stop${mapIconStop(hex, tones)}'
        : '${stop ?? ''}${mapIconInk(hex, tones)}';
  });
}

Color _bucket(double h, IconTones t) => h >= 345
    ? t.conMark // the constraint red (SPEC §5.5), not a failure
    : h >= 175 && h < 265
        ? t.accent // the old blue — everything the app owns
        : h >= 75 && h < 175
            ? t.ok // green — closed, solved, good
            // Amber AND orange. The band starts at 18, not 40: the preview
            // orange (#E59B63, hue 26) and the extrude amber (#C8843F, hue
            // 30) sit below 40 and a narrower band threw them into the red
            // bucket — an orange glyph came out as an error glyph, which is
            // the one mistake a CAD icon set cannot make.
            : h >= 18 && h < 75
                ? t.projRef // annotation and reference
                : t.err; // red — wrong

HSLColor _hsl(String rrggbb) =>
    HSLColor.fromColor(Color(0xFF000000 | int.parse(rrggbb, radix: 16)));

/// (c) A gradient stop in a data-lit="2" SVG: material. Never inverted; a
/// light theme compresses the ramp to L' = .10 + .70 L so the lit top face
/// separates from the paper without an outline.
@visibleForTesting
String mapIconStop(String rrggbb, IconTones tones) {
  final hsl = _hsl(rrggbb);
  final l = tones.dark ? hsl.lightness : 0.10 + 0.70 * hsl.lightness;
  if (hsl.saturation < 0.12) {
    // own hue and saturation: the cool steel stays steel
    return _hexOf(hsl.withLightness(l.clamp(0.12, 0.92)).toColor());
  }
  final t = HSLColor.fromColor(_bucket(hsl.hue, tones));
  return _hexOf(t
      .withSaturation(math.min(hsl.saturation, t.saturation))
      .withLightness(l.clamp(0.22, 0.86))
      .toColor());
}

final Map<(int, int, int), double> _capCache = {};

/// (b) The lightest L of this hue / saturation that still gives 3.2:1 on
/// [bg]. Keyed by the ground too, so the cache never needs clearing.
double _lightCap(double hue, double sat, Color bg) => _capCache.putIfAbsent(
        (bg.toARGB32(), (hue * 1000).round(), (sat * 1000).round()), () {
      final y0 = bg.computeLuminance();
      double lo = 0, hi = 1;
      for (var i = 0; i < 24; i++) {
        final m = (lo + hi) / 2;
        final y =
            HSLColor.fromAHSL(1, hue, sat, m).toColor().computeLuminance();
        final hiY = math.max(y, y0), loY = math.min(y, y0);
        if ((hiY + 0.05) / (loY + 0.05) >= 3.2) {
          lo = m;
        } else {
          hi = m;
        }
      }
      return lo;
    });

/// Flat paint (`fill`, `stroke`, and every colour outside a data-lit="2"
/// glyph's stops): ink.
@visibleForTesting
String mapIconInk(String rrggbb, IconTones tones) {
  final hsl = _hsl(rrggbb);
  final light = !tones.dark;

  // ---- neutral: a grey stop on the icon's own ramp ----
  if (hsl.saturation < 0.12) {
    // Inverted on a light scheme, and pulled off the extremes so a glyph never
    // becomes pure black on paper or pure white on charcoal.
    final l = light ? 1.0 - hsl.lightness : hsl.lightness;
    final ink = HSLColor.fromColor(tones.ink);
    // (a) a pure-grey ink has a meaningless hue of 0: tinting it at .04 gave
    // neutral ink a pink cast on paper.
    final s = ink.saturation < 0.05 ? 0.0 : 0.04;
    return _hexOf(
        ink.withSaturation(s).withLightness(l.clamp(0.12, 0.92)).toColor());
  }

  // ---- chromatic: the palette's hue for what this colour MEANS ----
  final t = HSLColor.fromColor(_bucket(hsl.hue, tones));
  final sat = (t.saturation * 0.85 + hsl.saturation * 0.15).clamp(0.25, 0.95);
  // Keep the stop's own place in its ramp, then re-anchor it for the ground.
  // On paper the band is [.22, cap] (b): as light as the hue may go while it
  // still reads as ink on the paper, so the ORDER of the stops survives and
  // nothing becomes a pastel.
  final l = light
      ? 0.22 + hsl.lightness * (_lightCap(t.hue, sat, tones.bg) - 0.22)
      : hsl.lightness.clamp(0.32, 0.82);
  return _hexOf(t.withLightness(l).withSaturation(sat).toColor());
}

String _hexOf(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}
