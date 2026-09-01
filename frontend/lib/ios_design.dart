// M338 — the iOS design system, as tokens.
//
// WHAT THIS FILE IS FOR
// ---------------------
// Every tool dialog in this app was a transcription of an Autodesk Inventor
// window: 11–12 pt labels, 24–26 pt rows, 3 pt corners, hairline boxes around
// groups of controls, and OK / Cancel / Apply in a footer. That is a faithful
// drawing of a Win32 dialog, and on an iPad it is the one part of the app that
// does not belong to the platform it runs on. The ribbon, the model browser,
// the tab bar, the quick-tool rail and the whole Settings screen are already
// real UIKit (M106, M107, M149, M192, M261); the dialogs were the last
// Windows-shaped thing left.
//
// This file holds the MEASUREMENTS. `widgets/ios_kit.dart` holds the controls
// built from them, and every dialog is drawn with those controls.
//
// WHY TOKENS RATHER THAN NUMBERS AT THE CALL SITE
// -----------------------------------------------
// The same reason theme.dart exists for colour. A 17 pt body written into
// forty widgets is forty places to be wrong about what iOS's body size is, and
// a reviewer cannot tell a considered 17 from a coincidental one. Here each
// value is named after the thing Apple names it after, and the name is the
// citation: `IosText.body` is the Dynamic Type body style at the Large content
// size, not "the size that looked right".
//
// THE THREE DECISIONS THAT ARE NOT TRANSCRIPTION
// ----------------------------------------------
//
// 1. THE COLOURS ARE THE APP'S, THE ROLES ARE APPLE'S. iOS gives semantic
//    colours (label, secondaryLabel, separator, systemGroupedBackground,
//    tertiarySystemFill …) and this app already gives two hand-built palettes
//    held to WCAG by test/m236_theme_test.dart, with a user-chosen accent on
//    top (M237). Replacing those with systemBlue and systemGray6 would throw
//    away both the contrast work and the identity, and would leave one window
//    rendered in two schemes — the exact bug M237 exists to prevent. So the
//    ROLES are Apple's and the pigments are [T]'s.
//
// 2. THE FILLS ARE TRANSLUCENT, NOT PALETTE SLOTS. Apple's four system fills
//    are grey at a fixed alpha, so a segmented track composites correctly over
//    whatever is behind it. That property is load-bearing here: on Ember
//    `T.fly` and `T.field` are the SAME colour, so a segmented control drawn
//    with `field` on a card drawn with `fly` would be invisible. The fills
//    below are therefore [T.text] at Apple's alphas — Apple's mechanism, the
//    app's hue.
//
// 3. THE CORNERS ARE SUPERELLIPSES. Apple's rounded rectangle is not a rounded
//    rectangle; it is a squircle, and the difference is visible at every
//    radius above about 8 pt. Flutter ships the real curve as
//    [RoundedSuperellipseBorder] / `ClipRSuperellipse`, so there is no reason
//    to draw the wrong one. [IosShape] is the one place that decides.
//
// SOURCES. Apple Human Interface Guidelines — Materials, Layout, Typography,
// Color, Buttons, Sheets, Popovers, Segmented controls, Toggles, Sliders,
// Lists and tables (developer.apple.com/design/human-interface-guidelines),
// read for this milestone. The Dynamic Type sizes and tracking are the Large
// content size row of Apple's own type table.
import 'package:flutter/widgets.dart';

import 'theme.dart';

/// The Dynamic Type ramp at the Large (default) content size.
///
/// Size / leading / tracking are Apple's published values, not approximations:
/// body is 17 pt on 22 pt leading with −0.41 pt tracking, and a footnote is
/// 13 on 18 with −0.08. Leading is expressed as Flutter's [TextStyle.height]
/// multiple, which is what leading/size comes to.
///
/// The FAMILY is deliberately left null. Flutter's iOS typography already
/// resolves to `.SF UI Text`, so naming a family here would only be a second
/// place to get it wrong — and in the host test suite it would name a font
/// that is not installed.
///
/// These are STYLES, not sizes: a caller asks for the role it means
/// ([headline] for a panel title, [subheadline] for a row label) and gets the
/// weight and the leading that go with it. Colour is applied by the caller,
/// because the same role is read at three different emphases.
class IosText {
  IosText._();

  static const TextStyle largeTitle = TextStyle(
      fontSize: 34, height: 41 / 34, letterSpacing: 0.37, fontWeight: FontWeight.w400);
  static const TextStyle title1 = TextStyle(
      fontSize: 28, height: 34 / 28, letterSpacing: 0.36, fontWeight: FontWeight.w400);
  static const TextStyle title2 = TextStyle(
      fontSize: 22, height: 28 / 22, letterSpacing: 0.35, fontWeight: FontWeight.w400);
  static const TextStyle title3 = TextStyle(
      fontSize: 20, height: 25 / 20, letterSpacing: 0.38, fontWeight: FontWeight.w400);

  /// 17/22 semibold — a panel's title, a row that heads a group.
  static const TextStyle headline = TextStyle(
      fontSize: 17, height: 22 / 17, letterSpacing: -0.43, fontWeight: FontWeight.w600);

  /// 17/22 regular — the size a list row is set in on iOS.
  static const TextStyle body = TextStyle(
      fontSize: 17, height: 22 / 17, letterSpacing: -0.41, fontWeight: FontWeight.w400);
  static const TextStyle callout = TextStyle(
      fontSize: 16, height: 21 / 16, letterSpacing: -0.32, fontWeight: FontWeight.w400);

  /// 15/20 — the row size this app's panels actually use. See [IosMetrics] for
  /// why a CAD inspector sets its rows a step below body.
  static const TextStyle subheadline = TextStyle(
      fontSize: 15, height: 20 / 15, letterSpacing: -0.24, fontWeight: FontWeight.w400);

  /// 13/18 — a grouped-list section header, a footer note, a segment label.
  static const TextStyle footnote = TextStyle(
      fontSize: 13, height: 18 / 13, letterSpacing: -0.08, fontWeight: FontWeight.w400);
  static const TextStyle caption1 = TextStyle(
      fontSize: 12, height: 16 / 12, letterSpacing: 0, fontWeight: FontWeight.w400);
  static const TextStyle caption2 = TextStyle(
      fontSize: 11, height: 13 / 11, letterSpacing: 0.07, fontWeight: FontWeight.w400);
}

/// Applies a colour, and optionally a weight, to one of [IosText]'s roles.
///
/// `IosText.body.on(IosColors.label)` reads as what it is. The alternative —
/// `IosText.body.copyWith(color: …)` at three hundred call sites — is the same
/// thing with more punctuation.
extension IosTextStyleX on TextStyle {
  TextStyle on(Color c, {FontWeight? weight}) =>
      copyWith(color: c, fontWeight: weight ?? fontWeight);
}

/// iOS's semantic colours, filled from the app's own palette.
///
/// The names are UIKit's on purpose: a reader who knows what
/// `secondarySystemGroupedBackground` means knows what this app puts there,
/// and a reader who does not can look it up. Every one is a GETTER, because
/// [T.scheme] can change under a running app and a `final` would freeze
/// whichever palette happened to be active when the library was first touched
/// (the trap theme.dart's own M236 note describes).
class IosColors {
  IosColors._();

  // ---- content ----

  /// Primary text.
  static Color get label => T.text;

  /// A row's value, a section header, anything explanatory.
  static Color get secondaryLabel => T.dim;

  /// A placeholder, an unfilled slot.
  static Color get tertiaryLabel => T.dim.withValues(alpha: 0.55);

  /// A control that is present but cannot be used.
  static Color get quaternaryLabel => T.dim.withValues(alpha: 0.32);

  /// The tint: every interactive word, every selected state.
  static Color get tint => T.accent;

  /// Text and glyphs ON the tint.
  static Color get onTint => T.onAccent;

  /// A destructive action, and an error.
  static Color get destructive => T.err;

  /// A warning that is not yet an error.
  static Color get warning => T.warn;

  // ---- backgrounds ----

  /// The ground a grouped list sits on — the panel's own surface.
  static Color get groupedBackground => T.panel;

  /// A group's card. On Chalk this is RAISED above the ground (white on
  /// paper); on Ember it is sunk below it. That polarity is the palette's own
  /// decision (see theme.dart on `fly`), and following it is what keeps a
  /// dialog looking like the rest of the app in both schemes.
  static Color get cardBackground => T.fly;

  /// The hairline between two rows of one card, and around a control.
  static Color get separator => T.panelSep;

  /// A harder edge: the outline of a floating panel against the viewport.
  static Color get border => T.sep;

  // ---- fills ----
  //
  // Apple's four system fills, at Apple's alphas, in the app's ink. See the
  // file header for why these are translucent rather than palette slots.

  static const _fillAlpha = (0.20, 0.36);
  static const _secondaryFillAlpha = (0.16, 0.32);
  static const _tertiaryFillAlpha = (0.12, 0.24);
  static const _quaternaryFillAlpha = (0.08, 0.18);

  static Color _fill((double, double) a) =>
      T.text.withValues(alpha: T.isDark ? a.$2 : a.$1);

  /// A thumbnail well, a large inert area.
  static Color get systemFill => _fill(_fillAlpha);

  /// A pressed control.
  static Color get secondarySystemFill => _fill(_secondaryFillAlpha);

  /// A segmented control's track, an unselected option's ground.
  static Color get tertiarySystemFill => _fill(_tertiaryFillAlpha);

  /// The faintest wash — an input well inside a card.
  static Color get quaternarySystemFill => _fill(_quaternaryFillAlpha);

  /// The selected segment's thumb.
  ///
  /// It must be LIGHTER than the track it slides on, and the track is already
  /// [tertiarySystemFill] — 24 % of the ink — over the card. On light that is
  /// the card itself (white thumb, grey track, which is iOS's own pairing); on
  /// dark it has to be lifted past the track deliberately, or the two come out
  /// within a few values of each other and the thumb disappears. 0.42 is the
  /// step iOS's own #636366 thumb takes over its #3C3C3E track.
  static Color get segmentThumb => T.isDark
      ? Color.alphaBlend(T.text.withValues(alpha: 0.34), cardBackground)
      : cardBackground;

  /// The tint at the weight a selected-but-not-filled control wears.
  static Color get tintedFill => T.accent.withValues(alpha: T.isDark ? 0.26 : 0.14);

  /// The tint at the weight a pressed tinted control wears.
  static Color get tintedFillPressed =>
      T.accent.withValues(alpha: T.isDark ? 0.38 : 0.22);
}

/// The measurements. Everything here is a point value from the HIG or from the
/// system controls it describes.
class IosMetrics {
  IosMetrics._();

  /// "A button needs a hit region of at least 44x44 pt" — HIG, Buttons. This
  /// is a FLOOR that the kit applies by padding, never by growing the drawing.
  static const double hit = 44;

  /// A grouped-list row. 44 is the UIKit default and the same number as [hit],
  /// which is not a coincidence: a row IS a button.
  static const double row = 44;

  /// A row that carries only a label and a value can be shorter; one that
  /// carries a control never is.
  static const double compactRow = 38;

  /// Leading and trailing inset INSIDE a card, to the text.
  static const double rowInset = 16;

  /// A card's inset from the panel's own edge. 16 is iOS's standard content
  /// margin at these widths.
  static const double cardInset = 16;

  /// Space above a section header, and below a section's card.
  static const double sectionTop = 22;
  static const double sectionBottom = 8;

  /// Between a section header and its card.
  static const double headerGap = 6;

  /// Vertical rhythm inside a card between stacked controls.
  static const double stack = 10;

  /// A separator. iOS draws one physical pixel; 0.5 logical is the closest a
  /// resolution-independent value gets, and it is what Flutter's own
  /// [Divider] uses for a hairline.
  static const double hairline = 0.5;

  // ---- radii, all continuous (see [IosShape]) ----

  /// A floating panel. iPadOS panels and popovers sit near 18–20.
  static const double panelRadius = 20;

  /// A grouped-list card.
  static const double cardRadius = 12;

  /// A button, an input well, an icon toggle.
  static const double controlRadius = 10;

  /// A segmented control's track. Its thumb is [segmentRadius] − [segmentInset].
  static const double segmentRadius = 9;
  static const double segmentInset = 2;

  /// A segmented control's height. UIKit's default.
  static const double segment = 32;

  /// A navigation bar. UIKit's compact height, which is what a panel wears.
  static const double navBar = 44;

  /// The standard widths a feature panel and a wide (two-column) panel take.
  ///
  /// 340, not the 300 the Inventor transcriptions used: an iOS row is set in
  /// 15 pt with a 16 pt inset on each side, and a German label plus its value
  /// does not fit what an 11 pt Win32 label did.
  static const double panelWidth = 340;
  static const double widePanelWidth = 440;
}

/// The corner. Apple's rounded rectangle is a superellipse, and Flutter draws
/// the real one — so this file is the only place that has to know.
///
/// [border] returns a [ShapeBorder] for [ShapeDecoration]; [clip] wraps a
/// child in the matching clip. Using a plain `BorderRadius.circular` anywhere
/// in the dialog layer is a bug, not a shortcut: the two curves differ most
/// exactly at the radii a panel and a card use.
class IosShape {
  IosShape._();

  static ShapeBorder border(double radius, {BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius), side: side);

  static Widget clip(double radius, {required Widget child}) =>
      ClipRSuperellipse(
          borderRadius: BorderRadius.circular(radius), child: child);
}

/// The shadow a floating panel casts.
///
/// Two shadows, not one: iOS layers a wide soft ambient shadow under a tight
/// key shadow, which is what stops a card from looking like a sticker. The
/// colour is the palette's own scrim so it stays honest on light paper.
List<BoxShadow> iosPanelShadow() => [
      BoxShadow(
          color: T.scrim.withValues(alpha: T.isDark ? 0.22 : 0.11),
          blurRadius: 44,
          offset: const Offset(0, 10)),
      BoxShadow(
          color: T.scrim.withValues(alpha: T.isDark ? 0.20 : 0.06),
          blurRadius: 6,
          offset: const Offset(0, 2)),
    ];

/// The shadow under a segmented control's thumb. iOS's own, to the point.
List<BoxShadow> iosThumbShadow() => [
      BoxShadow(
          color: T.scrim.withValues(alpha: T.isDark ? 0.45 : 0.12),
          blurRadius: 8,
          offset: const Offset(0, 3)),
      BoxShadow(
          color: T.scrim.withValues(alpha: T.isDark ? 0.30 : 0.04),
          blurRadius: 1,
          offset: const Offset(0, 3)),
    ];
