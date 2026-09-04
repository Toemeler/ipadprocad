// Prototype — the icon set, recoloured into the active palette.
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
import 'package:flutter/material.dart';

import 'theme.dart';

final RegExp _hex = RegExp(r'#([0-9a-fA-F]{6})\b');

Palette? _cachedFor;
Accent? _cachedAccent;
final Map<String, String> _cache = <String, String>{};

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
  }
  return _cache.putIfAbsent(
      svg, () => svg.replaceAllMapped(_hex, (m) => _map(m.group(1)!)));
}

String _map(String rrggbb) {
  final v = int.parse(rrggbb, radix: 16);
  final hsl =
      HSLColor.fromColor(Color(0xFF000000 | v));
  final light = !T.isDark;

  // ---- neutral: a grey stop on the icon's own ramp ----
  if (hsl.saturation < 0.12) {
    // Inverted on a light scheme, and pulled off the extremes so a glyph never
    // becomes pure black on paper or pure white on charcoal.
    final l = light ? 1.0 - hsl.lightness : hsl.lightness;
    return _hexOf(HSLColor.fromColor(T.ink)
        .withSaturation(0.04)
        .withLightness(l.clamp(0.12, 0.92))
        .toColor());
  }

  // ---- chromatic: the palette's hue for what this colour MEANS ----
  final h = hsl.hue;
  final Color target;
  if (h >= 175 && h < 265) {
    target = T.accent; // the old blue — everything the app owns
  } else if (h >= 75 && h < 175) {
    target = T.ok; // green — closed, solved, good
  } else if (h >= 18 && h < 75) {
    // Amber AND orange. The band starts at 18, not 40: the preview orange
    // (#E59B63, hue 26) and the extrude amber (#C8843F, hue 30) sit below 40
    // and a narrower band threw them into the red bucket — an orange glyph
    // came out as an error glyph, which is the one mistake a CAD icon set
    // cannot make.
    target = T.projRef; // annotation and reference
  } else {
    target = T.err; // red — wrong
  }
  final t = HSLColor.fromColor(target);

  // Keep the stop's own place in its ramp, then re-anchor it for the ground.
  // On paper the whole ramp moves down; on charcoal it is already right.
  final l = light
      // On paper every stop has to stay ink-like: a saturated colour at L=0.55
      // is a pastel against #FCFBF8 and the glyph dissolves. The band is
      // narrow on purpose — the ORDER of an icon's stops survives, their
      // absolute lightness does not, and order is what models the shape.
      ? (0.16 + hsl.lightness * 0.30).clamp(0.16, 0.46)
      : hsl.lightness.clamp(0.32, 0.82);
  return _hexOf(t
      .withLightness(l)
      .withSaturation((t.saturation * 0.85 + hsl.saturation * 0.15)
          .clamp(0.25, 0.95))
      .toColor());
}

String _hexOf(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}
