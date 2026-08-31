// Prototype — design tokens.
//
// M236 — TWO palettes, not one. Until now every colour in the app was a
// compile-time constant lifted 1:1 from create-panel.html: one dark blue-grey
// scheme, no alternative, and roughly two hundred more colours written
// straight into the painters where no token could reach them. A light mode was
// therefore not a setting, it was a rewrite.
//
// What replaced it:
//
//   [Palette]         — one immutable value holding EVERY colour the app
//                       paints. Two instances exist: [kChalk] (light) and
//                       [kEmber] (dark).
//   [T]               — the same names the 450-odd call sites already use,
//                       now getters that read the ACTIVE palette instead of
//                       constants. Call sites did not change; `const` in front
//                       of the expressions using them did, because a colour
//                       that can change is no longer a compile-time constant.
//   [T.scheme]        — a ValueNotifier the app root listens to, plus the
//                       switch itself: it follows the iPad's own light/dark
//                       setting by default and remembers an explicit choice
//                       in the same settings.json the language uses.
//
// Why a global notifier rather than an InheritedWidget: the geometry is drawn
// by CustomPainters and by off-screen renderers (the gallery thumbnails in
// AppState._writePartPreview) that have no BuildContext and no business
// acquiring one. A painter reads T.ink at paint time; [T.scheme] notifies, the
// tree rebuilds, and the painters repaint with the new palette. The tradeoff
// is that the palette is process-global — which it already was, as constants.
//
// The shape deliberately mirrors M234's [L]: a ValueNotifier the app root
// listens to, a store attached from AppState.init rather than from main() (a
// settings read in front of the first frame is a launch-time regression this
// repository measures), and the same settings.json under .cache. An app with
// one window has one language and one appearance, and the two should not be
// remembered in two different ways.
//
// The palettes themselves: CHALK is a cool grey-cream paper, EMBER a warm
// brown charcoal. Both are held to WCAG by test/m236_theme_test.dart, at the
// bar each role actually answers to: 4.5:1 for anything read as TEXT, 3:1
// (WCAG 1.4.11, non-text contrast) for the graphical states that are meant to
// recede — construction geometry, an unconstrained curve, a disabled control.
// Those are deliberately quiet and forcing them to 4.5 would destroy the very
// distinction they exist to make.
//
// The accent is a petrol teal in both schemes and the ANNOTATION colour is
// copper: everything the app owns is teal, everything the drawing says is
// copper, and the two never trade places.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';
import 'package:reality_view/reality_view.dart';

import 'log.dart';

/// Every colour the app paints, as one value.
///
/// Fields are grouped the way the UI is: chrome first, then the model browser,
/// tab bar and home gallery, then the viewport — the sketch, its annotations
/// and the shaded solid. A new colour belongs HERE, never inline in a painter;
/// that rule is the whole point of the file.
@immutable
class Palette {
  /// Shown in the theme switcher. Not a debug label.
  final String name;

  /// Drives the Material [ThemeData] and, through it, the system text
  /// selection handles and the keyboard's appearance.
  final Brightness brightness;

  // ---- chrome ----
  final Color bg; // app shell behind the ribbon
  final Color panel; // panels, ribbon body
  final Color fly; // flyouts and dialog surfaces: RAISED on light, sunk on dark
  final Color flyHov; // the same surface, hovered

  /// An input well — a text field, a number box, a segmented control's ground.
  ///
  /// Split from [fly] in M237: on dark both are "darker than the panel", so
  /// one token covered both. On light they pull APART — a dialog lifts to
  /// white while the field inside it has to sink below the dialog, or the two
  /// merge into one flat sheet and the field stops looking editable.
  final Color field;
  final Color text; // primary text
  final Color dim; // secondary text and labels
  final Color sep; // hard separator, darkest/lightest hairline
  final Color rawAccent; // selection, active tab, focus ring
  final Color hover; // halo under hovered / pre-selected geometry
  final Color viewport; // the drawing ground
  /// The rendered view's floor, the ground plane the model sits on.
  ///
  /// Distinct from [viewport]: in the rendered view the model is lit and
  /// shadowed, and a shadow needs a surface a step away from the background
  /// to land on. It follows the scheme for the same reason [viewport] does —
  /// a frozen charcoal floor is the dark island under Chalk's cream chrome
  /// that the model browser's icons vanish against.
  final Color floor;
  final Color rawRibbonTop; // ribbon active-tab gradient, top stop
  final Color rawRibbonBottom; // ... and bottom stop
  final Color panelSep; // soft separator inside a panel, control borders

  // ---- model browser ----
  final Color mbBg;
  final Color mbHead;
  final Color mbBorder;
  final Color mbHeadBorder;
  final Color mbText;
  final Color mbDim;
  final Color mbDimmed;
  final Color mbActiveBg;
  final Color mbActiveOutline;
  final Color mbHover;

  // ---- tab bar ----
  final Color tabbarBg;
  final Color tabbarBorder;
  final Color tabBg;
  final Color tabOnBg;
  final Color tabText;
  final Color rawTabUnderline;

  // ---- home ----
  final Color cardBg;
  final Color cardBorder;
  final Color rawCardHoverBorder;
  final Color homeH1;
  final Color cardName;
  final Color cardDate;

  // ---- home gallery (Procreate-style start page) ----
  final Color galleryBg;
  final Color galleryThumb;
  final Color galleryTitle;
  final Color galleryActionBg;
  final Color galleryActionBgHover;
  final Color cardShadow;

  // ---- edit-mode sketch overlay ----
  final Color rawGrey; // unconstrained sketch geometry
  final Color projRef; // projected / reference geometry (copper)
  final Color projRefEdge; // ... its darker edge
  final Color finishGreen; // the "finish sketch" affordance

  // ---- neutral overlays (hover states, hairlines) ----
  //
  // White on dark, BLACK on light. A white 6%-overlay is invisible on cream,
  // which is exactly the bug a light mode ships with when these are constants.
  final Color hover6;
  final Color hover7;
  final Color hover8;
  final Color border10;
  final Color rawConActiveBg;
  final Color rawConActiveBorder;

  // ---- dialogs and controls ----
  final Color scrim; // behind a modal
  final Color shadow; // drop shadow under a floating panel
  final Color chipBg; // an active chip / segment, accent-tinted fill
  final Color rawChipStrong; // a primary button at rest
  final Color onAccent; // text and icons ON chipStrong or accent
  final Color disabled; // disabled text and icons
  final Color disabledFill; // a disabled primary button
  final Color warn; // an incomplete profile, a non-fatal notice
  final Color warnText;
  final Color err; // a conflict, a failed operation: strokes and glyphs
  /// The same meaning as [err] as a FILLED surface. Separate because the two
  /// have opposite requirements: [err] has to stay bright enough to read as a
  /// red line on the viewport, and a fill that bright cannot carry [onAccent]
  /// text on it.
  final Color errFill;
  final Color errText;
  final Color ok; // a closed profile, a solved sketch
  final Color okText;

  // ---- viewport: the sketch ----
  final Color ink; // a sketch curve, and sketch text
  final Color inkDim; // the same, on a layer that is not being edited
  final Color constr; // construction geometry
  final Color snapOk; // snap markers and alignment guides
  final Color grid; // grid dots
  final Color axis; // the world axes through the origin
  final Color rawNode; // a draggable grip / control point

  // Inventor colours a sketch entity by its CONSTRAINT STATE, and the three
  // states have to stay tellable apart on both grounds: fully defined reads as
  // the strongest ink the scheme has, under-constrained keeps its violet (the
  // one hue neither the accent nor the annotation uses), and anything on a
  // layer you are not editing drops back to a whisper.
  final Color dofFull;
  final Color dofUnder;
  final Color refDim;
  final Color dofArrow; // degrees-of-freedom arrows
  final Color ctrl; // spline control polygon and its points

  // ---- viewport: annotation ----
  final Color dimLine; // dimension witness lines and arrows
  final Color dimText; // the value itself
  final Color dimPlate; // the plate the value sits on
  final Color dimPlateHot; // ... when the label is hovered
  final Color hudBg; // the inline value editor's row
  final Color hudBgHot; // ... focused
  final Color toastBg; // the transient message strip
  final Color toastBorder;
  final Color toastText;

  // ---- viewport: the solid ----
  final Color solid; // shaded face base tone
  final Color solidEdge; // a B-Rep edge
  final Color edgeAccent; // a hovered or selected B-Rep edge (copper)
  final Color faceHighlight; // a hovered or selected face
  final Color previewFill; // the live extrude preview
  final Color previewEdge;
  final Color okSolid; // a committed boolean, the "good" solid tint
  final Color okSolidBright;
  final Color axisX;
  final Color axisY;
  final Color axisZ;
  final Color cubeFace; // ViewCube face at rest
  final Color cubeFaceTop; // ... the lit one
  final Color cubeFaceDim; // ... the shaded one
  final Color cubeEdge;
  final Color cubeText;

  const Palette({
    required this.name,
    required this.brightness,
    required this.bg,
    required this.panel,
    required this.fly,
    required this.flyHov,
    required this.field,
    required this.text,
    required this.dim,
    required this.sep,
    required this.rawAccent,
    required this.hover,
    required this.viewport,
    required this.floor,
    required this.rawRibbonTop,
    required this.rawRibbonBottom,
    required this.panelSep,
    required this.mbBg,
    required this.mbHead,
    required this.mbBorder,
    required this.mbHeadBorder,
    required this.mbText,
    required this.mbDim,
    required this.mbDimmed,
    required this.mbActiveBg,
    required this.mbActiveOutline,
    required this.mbHover,
    required this.tabbarBg,
    required this.tabbarBorder,
    required this.tabBg,
    required this.tabOnBg,
    required this.tabText,
    required this.rawTabUnderline,
    required this.cardBg,
    required this.cardBorder,
    required this.rawCardHoverBorder,
    required this.homeH1,
    required this.cardName,
    required this.cardDate,
    required this.galleryBg,
    required this.galleryThumb,
    required this.galleryTitle,
    required this.galleryActionBg,
    required this.galleryActionBgHover,
    required this.cardShadow,
    required this.rawGrey,
    required this.projRef,
    required this.projRefEdge,
    required this.finishGreen,
    required this.hover6,
    required this.hover7,
    required this.hover8,
    required this.border10,
    required this.rawConActiveBg,
    required this.rawConActiveBorder,
    required this.scrim,
    required this.shadow,
    required this.chipBg,
    required this.rawChipStrong,
    required this.onAccent,
    required this.disabled,
    required this.disabledFill,
    required this.warn,
    required this.warnText,
    required this.err,
    required this.errFill,
    required this.errText,
    required this.ok,
    required this.okText,
    required this.ink,
    required this.inkDim,
    required this.constr,
    required this.snapOk,
    required this.grid,
    required this.axis,
    required this.rawNode,
    required this.dofFull,
    required this.dofUnder,
    required this.refDim,
    required this.dofArrow,
    required this.ctrl,
    required this.dimLine,
    required this.dimText,
    required this.dimPlate,
    required this.dimPlateHot,
    required this.hudBg,
    required this.hudBgHot,
    required this.toastBg,
    required this.toastBorder,
    required this.toastText,
    required this.solid,
    required this.solidEdge,
    required this.edgeAccent,
    required this.faceHighlight,
    required this.previewFill,
    required this.previewEdge,
    required this.okSolid,
    required this.okSolidBright,
    required this.axisX,
    required this.axisY,
    required this.axisZ,
    required this.cubeFace,
    required this.cubeFaceTop,
    required this.cubeFaceDim,
    required this.cubeEdge,
    required this.cubeText,
  });

  // ---- the accent, and everything that IS the accent (bug report #11) ----
  //
  // WHY THESE ARE GETTERS OVER `raw*` FIELDS.
  //
  // The accent became the user's choice, and the first two attempts at that
  // both leaked. Overriding `T.accent` alone left EIGHT tokens behind — the
  // card's hover border, the tab underline, the ribbon wash, the constraint
  // fill, the sketch nodes — because each is the accent stored again at
  // another alpha. Overriding the `T` getters too still left the gallery,
  // because `galleryChrome` hands widgets a `Palette` and `home_view` reads
  // `g.cardHoverBorder` off it directly, never touching `T`.
  //
  // A value that can be overridden must be overridden where it LIVES. Here,
  // every reader gets the same answer: `T.cardHoverBorder`, `g.cardHoverBorder`
  // and a palette pulled out of `galleryChrome` cannot disagree, and a widget
  // written tomorrow cannot pick the wrong one.
  //
  // The rule is a COMPARISON, not a list: a token whose RGB matches this
  // palette's own accent follows the choice, one that does not is left alone.
  // A list would go stale the first time a palette changed a token, silently
  // and in exactly the way this comment exists to describe.
  //
  // The alpha stays the TOKEN'S. That is the difference between `ribbonTop` as
  // a wash and `ribbonTop` as a slab.
  Color _tinted(Color c) {
    final chosen = T.accentChoice.value.on(this);
    if (chosen == null) return c;
    if (c.r != rawAccent.r || c.g != rawAccent.g || c.b != rawAccent.b) {
      return c;
    }
    return chosen.withValues(alpha: c.a);
  }

  Color get accent => _tinted(rawAccent);
  Color get ribbonTop => _tinted(rawRibbonTop);
  Color get ribbonBottom => _tinted(rawRibbonBottom);
  Color get tabUnderline => _tinted(rawTabUnderline);
  Color get cardHoverBorder => _tinted(rawCardHoverBorder);
  Color get conActiveBg => _tinted(rawConActiveBg);
  Color get conActiveBorder => _tinted(rawConActiveBorder);
  Color get chipStrong => _tinted(rawChipStrong);
  Color get node => _tinted(rawNode);
}

/// EMBER — warm brown charcoal. The dark scheme.
const Palette kEmber = Palette(
  name: 'Ember',
  brightness: Brightness.dark,
  bg: Color(0xFF24211D),
  panel: Color(0xFF2C2823),
  fly: Color(0xFF1B1815),
  flyHov: Color(0xFF35302A),
  field: Color(0xFF1B1815),
  text: Color(0xFFEDE6D9),
  dim: Color(0xFFA09686),
  sep: Color(0xFF141210),
  rawAccent: Color(0xFF2FA9A2),
  hover: Color(0xFF74D6CE),
  viewport: Color(0xFF201D19),
  floor: Color(0xFF2A2E33),
  rawRibbonTop: Color(0xD92FA9A2),
  rawRibbonBottom: Color(0x732FA9A2),
  panelSep: Color(0xFF3A342D),
  mbBg: Color(0xFF2A2621),
  mbHead: Color(0xFF322D27),
  mbBorder: Color(0xFF141210),
  mbHeadBorder: Color(0xFF1B1815),
  mbText: Color(0xFFE6DFD2),
  mbDim: Color(0xFFA09686),
  mbDimmed: Color(0xFF8E8578),
  mbActiveBg: Color(0xFF3E3831),
  mbActiveOutline: Color(0xFF4E8C88),
  mbHover: Color(0x14E8DCC8),
  tabbarBg: Color(0xFF1B1815),
  tabbarBorder: Color(0xFF100E0C),
  tabBg: Color(0xFF24211D),
  tabOnBg: Color(0xFF2C2823),
  tabText: Color(0xFFA09686),
  rawTabUnderline: Color(0xFF2FA9A2),
  cardBg: Color(0xFF2C2823),
  cardBorder: Color(0xFF1B1815),
  rawCardHoverBorder: Color(0xFF2FA9A2),
  homeH1: Color(0xFFF2ECE0),
  cardName: Color(0xFFEDE6D9),
  cardDate: Color(0xFFA09686),
  galleryBg: Color(0xFF1F1C18),
  galleryThumb: Color(0xFF201D19),
  galleryTitle: Color(0xFFF5F0E6),
  galleryActionBg: Color(0xFF35302A),
  galleryActionBgHover: Color(0xFF3E3831),
  cardShadow: Color(0x66000000),
  rawGrey: Color(0xFF7A7266),
  projRef: Color(0xFFD98A4A),
  projRefEdge: Color(0xFF8A5526),
  finishGreen: Color(0xFF4E9B4A),
  hover6: Color(0x0FFFFFFF),
  hover7: Color(0x12FFFFFF),
  hover8: Color(0x14FFFFFF),
  border10: Color(0x1AFFFFFF),
  rawConActiveBg: Color(0x2E2FA9A2),
  rawConActiveBorder: Color(0x8C2FA9A2),
  scrim: Color(0x73000000),
  shadow: Color(0x8C000000),
  chipBg: Color(0xFF1E4A48),
  rawChipStrong: Color(0xFF237E79),
  onAccent: Color(0xFFF2FBFA),
  disabled: Color(0xFF7A7267),
  disabledFill: Color(0xFF232E2C),
  warn: Color(0xFFC87A3C),
  warnText: Color(0xFFE8A96A),
  err: Color(0xFFF0675F),
  errFill: Color(0xFFB4322C),
  errText: Color(0xFFF0A09A),
  ok: Color(0xFF4E9B4A),
  okText: Color(0xFF7FD06F),
  ink: Color(0xFFEDE6D9),
  inkDim: Color(0x66EDE6D9),
  constr: Color(0xFF8FB6B3),
  snapOk: Color(0xFF6FC96A),
  grid: Color(0xFF3A342D),
  axis: Color(0xFF4A443B),
  rawNode: Color(0xFF2FA9A2),
  dofFull: Color(0xFFFBF7EF),
  dofUnder: Color(0xFFA79BF7),
  refDim: Color(0xFF5C5851),
  dofArrow: Color(0xFFEFD37A),
  ctrl: Color(0xFFE8C060),
  dimLine: Color(0xFFB9AE96),
  dimText: Color(0xFFE9DFC9),
  dimPlate: Color(0xCC201D19),
  dimPlateHot: Color(0xCC2E3A38),
  hudBg: Color(0xE01F1C18),
  hudBgHot: Color(0xF02A3634),
  toastBg: Color(0xE6402F1F),
  toastBorder: Color(0xFF8A6A3A),
  toastText: Color(0xFFF2D6A2),
  solid: Color(0xFF9A9384),
  solidEdge: Color(0xFF17140F),
  edgeAccent: Color(0xFFD98A4A),
  faceHighlight: Color(0xFF45C8C0),
  previewFill: Color(0xFFEA9E5C),
  previewEdge: Color(0xE6F0A868),
  okSolid: Color(0xFF4BC96A),
  okSolidBright: Color(0xFF9AE8A6),
  axisX: Color(0xFFE06A56),
  axisY: Color(0xFF6FC96A),
  axisZ: Color(0xFF5A93D8),
  cubeFace: Color(0xFFE3DCCE),
  cubeFaceTop: Color(0xFFF6F1E7),
  cubeFaceDim: Color(0xFFC9C1B0),
  cubeEdge: Color(0xFFA79E8C),
  cubeText: Color(0xFF4A443B),
);

/// CHALK — cool grey-cream paper. The light scheme.
///
/// Note where it is NOT a mechanical inversion of [kEmber]: [fly] is RAISED
/// here (a dialog field is lighter than its panel, not darker), the neutral
/// overlays are black rather than white, and the shaded solid keeps a cool
/// grey so a steel part still reads as steel on warm paper.
const Palette kChalk = Palette(
  name: 'Chalk',
  brightness: Brightness.light,
  bg: Color(0xFFEDEBE6),
  panel: Color(0xFFF5F4F0),
  fly: Color(0xFFFFFFFF),
  flyHov: Color(0xFFF1EFEA),
  field: Color(0xFFF2F0EB),
  text: Color(0xFF1C1E20),
  dim: Color(0xFF5C6165),
  sep: Color(0xFFD9D6CF),
  rawAccent: Color(0xFF0F6A70),
  hover: Color(0xFF7FC9C4),
  viewport: Color(0xFFFCFBF8),
  floor: Color(0xFFE8E5DF),
  rawRibbonTop: Color(0xD90F6A70),
  rawRibbonBottom: Color(0x730F6A70),
  panelSep: Color(0xFFE3E0D9),
  mbBg: Color(0xFFF5F4F0),
  mbHead: Color(0xFFEDEBE6),
  mbBorder: Color(0xFFD9D6CF),
  mbHeadBorder: Color(0xFFE3E0D9),
  mbText: Color(0xFF1C1E20),
  mbDim: Color(0xFF5C6165),
  mbDimmed: Color(0xFF6E7276),
  mbActiveBg: Color(0xFFD9E9E7),
  mbActiveOutline: Color(0xFF4E9490),
  mbHover: Color(0x0A000000),
  tabbarBg: Color(0xFFE7E4DE),
  tabbarBorder: Color(0xFFD4D0C8),
  tabBg: Color(0xFFEFEDE8),
  tabOnBg: Color(0xFFFCFBF8),
  tabText: Color(0xFF545A5E),
  rawTabUnderline: Color(0xFF0F6A70),
  cardBg: Color(0xFFFFFFFF),
  cardBorder: Color(0xFFE3E0D9),
  rawCardHoverBorder: Color(0xFF0F6A70),
  homeH1: Color(0xFF16181A),
  cardName: Color(0xFF1C1E20),
  cardDate: Color(0xFF63686C),
  galleryBg: Color(0xFFF0EEE9),
  galleryThumb: Color(0xFFFCFBF8),
  galleryTitle: Color(0xFF16181A),
  galleryActionBg: Color(0xFFFFFFFF),
  galleryActionBgHover: Color(0xFFF1EFEA),
  cardShadow: Color(0x14000000),
  rawGrey: Color(0xFF8A9095),
  projRef: Color(0xFFA0561F),
  projRefEdge: Color(0xFF6E3B15),
  finishGreen: Color(0xFF26762F),
  hover6: Color(0x0A000000),
  hover7: Color(0x0D000000),
  hover8: Color(0x12000000),
  border10: Color(0x1A000000),
  rawConActiveBg: Color(0x240F6A70),
  rawConActiveBorder: Color(0x8C0F6A70),
  scrim: Color(0x40000000),
  shadow: Color(0x1F000000),
  chipBg: Color(0xFFD2E3E1),
  rawChipStrong: Color(0xFF0F6A70),
  onAccent: Color(0xFFF4FAF9),
  disabled: Color(0xFF878D91),
  disabledFill: Color(0xFFE0E4E3),
  warn: Color(0xFFA0561F),
  warnText: Color(0xFF7A4116),
  err: Color(0xFFAB2A3C),
  errFill: Color(0xFFAB2A3C),
  errText: Color(0xFF8A2030),
  ok: Color(0xFF26762F),
  okText: Color(0xFF1D5C24),
  ink: Color(0xFF1C1E20),
  inkDim: Color(0x661C1E20),
  constr: Color(0xFF7B8B9C),
  snapOk: Color(0xFF26762F),
  grid: Color(0xFFE6E3DC),
  axis: Color(0xFFD2CEC5),
  rawNode: Color(0xFF0F6A70),
  dofFull: Color(0xFF16181A),
  dofUnder: Color(0xFF5A4CC4),
  refDim: Color(0xFFA8ADB0),
  dofArrow: Color(0xFF8A6A1E),
  ctrl: Color(0xFF8A5F1E),
  dimLine: Color(0xFF6E7A5E),
  dimText: Color(0xFF3C4433),
  dimPlate: Color(0xCCFCFBF8),
  dimPlateHot: Color(0xCCD8E8E6),
  hudBg: Color(0xF0FFFFFF),
  hudBgHot: Color(0xF0DCEBE9),
  toastBg: Color(0xF5F3E4D2),
  toastBorder: Color(0xFFC79A62),
  toastText: Color(0xFF5A3A16),
  solid: Color(0xFFC0C4C7),
  solidEdge: Color(0xFF55595C),
  edgeAccent: Color(0xFFA0561F),
  faceHighlight: Color(0xFF158C8C),
  previewFill: Color(0xFFB4652A),
  previewEdge: Color(0xE68F4E20),
  okSolid: Color(0xFF2E8B3E),
  okSolidBright: Color(0xFF1D6B2A),
  axisX: Color(0xFFB3332A),
  axisY: Color(0xFF26762F),
  axisZ: Color(0xFF1F5C9E),
  cubeFace: Color(0xFFFFFFFF),
  cubeFaceTop: Color(0xFFFFFFFF),
  cubeFaceDim: Color(0xFFE9E6DF),
  cubeEdge: Color(0xFFBDBAB2),
  cubeText: Color(0xFF3C4043),
);


/// What the user picked in the ACCENT switch (bug report #11).
///
/// The accent is the one colour the app uses to mean "this is the thing you
/// are working on" — the selected tab, the tick in a list, an active chip, a
/// focus ring — and the report asked for it to be the user's choice rather
/// than the palette's.
///
/// A CLOSED LIST, NOT A COLOUR WHEEL, and that is the whole design.
/// `m236_theme_test` holds the accent to WCAG AA against BOTH the panel and
/// the viewport, in both palettes, because an accent that cannot be read is
/// not an accent. A free picker hands the user the one control that can break
/// the rule the theme exists to keep, and it would break it silently, on their
/// device, where no test runs. Every entry here is checked by that same test.
///
/// Each entry carries a light value AND a dark value for the reason [Palette]
/// comes in two: a teal that reads on cream is not the teal that reads on
/// charcoal. One value for both would fail one of them — which is exactly what
/// the two built-in accents (`0xFF0F6A70` on Chalk, `0xFF2FA9A2` on Ember)
/// already say.
enum Accent {
  /// Whatever the palette itself says. The default, and what every install
  /// before this had.
  scheme(null, null),
  teal(Color(0xFF107375), Color(0xFF17A8AB)),
  blue(Color(0xFF2569B6), Color(0xFF629CDF)),
  indigo(Color(0xFF734DCB), Color(0xFFA58CDE)),
  magenta(Color(0xFFB23484), Color(0xFFD879B5)),
  amber(Color(0xFF8F5A14), Color(0xFFD6871F)),
  green(Color(0xFF1E7638), Color(0xFF2CAF53)),
  red(Color(0xFFBA3A2C), Color(0xFFDE7D73));

  const Accent(this.light, this.dark);

  /// Null on [scheme] alone: it defers to the palette rather than overriding.
  final Color? light;
  final Color? dark;

  /// The name as it is stored, and the row id the settings sheet sends back.
  /// NOT shown to anyone — visible names come from the ARB.
  String get id => name;

  /// What this accent is on [p], or null to leave the palette's own alone.
  Color? on(Palette p) => p.brightness == Brightness.dark ? dark : light;

  /// The swatch the settings row draws. [scheme] shows what it will actually
  /// give you, which is the palette's own accent rather than a blank.
  Color swatchOn(Palette p) => on(p) ?? p.rawAccent;

  static Accent? byId(Object? s) {
    for (final a in Accent.values) {
      if (a.id == s) return a;
    }
    return null;
  }
}


/// What the user picked in the appearance switch.
enum AppThemeMode {
  /// Follow the iPad's own appearance setting. The default.
  system,
  light,
  dark;

  /// The name as it is stored. NOT shown to anyone — the visible names come
  /// from the ARB, because this app is written in German.
  String get id => name;

  static AppThemeMode? byId(Object? s) {
    for (final m in AppThemeMode.values) {
      if (m.id == s) return m;
    }
    return null;
  }
}

/// Where the appearance choice survives a restart.
///
/// The same file, the same shape and the same swallow-the-error rule as
/// [LocaleStore] — it merges into `settings.json` rather than owning it, so
/// the language preference sitting next to it is never dropped.
class ThemeStore {
  final Directory dir;
  const ThemeStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'theme';
  static const String accentKey = 'accent';

  File get file => File('${dir.path}/$fileName');

  Map<String, Object?> _read() {
    try {
      final f = file;
      if (!f.existsSync()) return const {};
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return const {};
      return <String, Object?>{for (final e in raw.entries) '${e.key}': e.value};
    } catch (e) {
      // A corrupt settings file costs an appearance preference and nothing
      // else. It must not cost the launch.
      Log.w('theme', 'could not read the appearance setting: $e');
      return const {};
    }
  }

  AppThemeMode? load() => AppThemeMode.byId(_read()[key]);

  /// The accent the user chose, or null for "whatever the palette says".
  Accent? loadAccent() => Accent.byId(_read()[accentKey]);

  void save(AppThemeMode m) => _write(key, m.id);

  void saveAccent(Accent a) => _write(accentKey, a.id);

  void _write(String k, Object? value) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final data = <String, Object?>{..._read(), k: value};
      file.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('theme', 'could not remember the appearance setting: $e');
    }
  }
}

/// The design tokens, read at paint time.
///
/// Every name here existed before M221 as a `static const`; they are getters
/// now so the palette can change while the app runs. That is the ONE reason a
/// `const` in front of a widget expression that mentions `T.` had to go.
class T {
  T._();

  /// The active palette, as something the app root can listen to.
  ///
  /// Mirrors [L.locale]: `PrototypeApp` wraps itself in a
  /// ValueListenableBuilder on this, so a switch rebuilds the whole tree and
  /// every CustomPainter with it. Nothing is torn down and the open sketch
  /// stays open — the difference between a theme switch and a restart.
  static final ValueNotifier<Palette> scheme = ValueNotifier<Palette>(kEmber);

  static Palette get palette => scheme.value;

  /// Pins a palette. For tests, and for [_apply].
  @visibleForTesting
  static set palette(Palette p) => scheme.value = p;

  static bool get isDark => palette.brightness == Brightness.dark;

  // ---- the switch ----

  static AppThemeMode _mode = AppThemeMode.system;
  static AppThemeMode get mode => _mode;

  static ThemeStore? _store;

  /// The brightness the OS reports. A field rather than a live read so the
  /// resolution behaves identically in tests, where there is no platform.
  static Brightness _platform = Brightness.dark;

  /// Start following the iPad's own light/dark setting.
  ///
  /// Called from `main()` — unlike the STORE, this is only a synchronous
  /// property read and a callback registration, and it has to happen before
  /// the first frame or the app paints one scheme and snaps to the other.
  static void followPlatform() {
    _platform = PlatformDispatcher.instance.platformBrightness;
    // Push unconditionally on the way in: _apply() below only pushes on a
    // CHANGE, and the common case (the iPad is dark, so is the default) is
    // no change at all — yet UIKit still has to be told, because its own
    // default is whatever the last run left behind.
    _pushToPlatform(_resolved);
    PlatformDispatcher.instance.onPlatformBrightnessChanged = () {
      final b = PlatformDispatcher.instance.platformBrightness;
      if (b == _platform) return;
      _platform = b;
      if (_mode == AppThemeMode.system) _apply();
    };
    _apply();
  }

  /// Point the switch at a settings file and adopt whatever it remembers.
  ///
  /// Called from [AppState.init], i.e. off the launch path, for the same
  /// reason [L.attachStore] is.
  static void attachStore(ThemeStore store) {
    _store = store;
    final saved = store.load();
    if (saved != null) {
      _mode = saved;
      _apply();
    }
    final savedAccent = store.loadAccent();
    if (savedAccent != null) {
      accentChoice.value = savedAccent;
      _pushAccent();
    }
  }

  /// Bug report #11 — the accent the user chose, as something the app root
  /// listens to.
  ///
  /// NOT a field on [Palette], and not carried by [scheme]. A palette is an
  /// immutable value with a hundred and fifty fields and exactly two
  /// instances; copying one to change a single colour would mean a `copyWith`
  /// nobody can read plus a second pair of palettes that `m236_theme_test`
  /// does not know about. And [scheme] cannot publish it, because its value
  /// would be the same `Palette` object before and after — a `ValueNotifier`
  /// compares before it notifies, so nothing would repaint.
  ///
  /// So the accent gets the treatment [L.locale] and `Backdrops.current`
  /// already have: its own notifier, and one more builder at the root. Every
  /// one of the 450 call sites still goes through [accent], so the override
  /// is one line there and cannot be forgotten.
  static final ValueNotifier<Accent> accentChoice =
      ValueNotifier<Accent>(Accent.scheme);

  /// Switch accent, and remember it. Same contract as [set]: a preference that
  /// does not survive the app being killed is not a preference.
  static void setAccent(Accent a) {
    if (a == accentChoice.value) return;
    accentChoice.value = a;
    Log.i('theme', 'accent = ${a.id}');
    // The glass ribbon, tab bar and tool bar are UIKit and cannot see a Dart
    // notifier. Without this the app renders in two accents at once — M237's
    // bug, one colour down.
    _pushAccent();
    _store?.saveAccent(a);
  }

  /// Switch scheme, and remember it. A preference that does not survive the
  /// app being killed is not a preference.
  static void set(AppThemeMode m) {
    if (m == _mode) return;
    _mode = m;
    _apply();
    _store?.save(m);
  }

  static Palette get _resolved => switch (_mode) {
        AppThemeMode.light => kChalk,
        AppThemeMode.dark => kEmber,
        AppThemeMode.system =>
          _platform == Brightness.light ? kChalk : kEmber,
      };

  static void _apply() {
    final p = _resolved;
    if (identical(p, scheme.value)) return;
    scheme.value = p;
    Log.i('theme', 'palette = ${p.name} (mode=${_mode.id})');
    _pushToPlatform(p);
  }

  /// M237 — carry the scheme across to UIKit.
  ///
  /// Flutter is not the whole window. The ribbon, the model browser, the tab
  /// bar and the tool bar are native GLASS, and the 3D viewport is RealityKit;
  /// none of them can see a Dart notifier. Without this push they keep last
  /// session's appearance and the app renders in two schemes at once — which
  /// is exactly what the light-mode screenshots showed.
  ///
  /// Fire-and-forget on purpose: both sides swallow their own failures, and a
  /// theme switch must not be able to throw into the widget tree.
  static void _pushToPlatform(Palette p) {
    final dark = p.brightness == Brightness.dark;
    NativeMenu.setAppearance(dark: dark);
    RealityAppearance.setViewportColor(p.viewport.toARGB32());
    RealityAppearance.setFloorColor(p.floor.toARGB32());
    _pushAccent();
  }

  /// Bug report #11 — the accent, across to UIKit.
  ///
  /// Sent as BOTH values rather than the active one, because UIKit resolves it
  /// against the trait the binder pins. Sent on an appearance change too, not
  /// only on an accent change: a host that has just been told to go light must
  /// already hold the light accent, or the tab bar wears the dark one for a
  /// frame.
  static void _pushAccent() {
    final a = accentChoice.value;
    NativeMenu.setAccent(
      // `rawAccent`, not `accent`: the getter is the OVERRIDDEN value, and
      // asking it for the fallback would be asking the answer to define
      // itself. `Accent.scheme` means "whatever each palette authored".
      light: (a.light ?? kChalk.rawAccent).toARGB32(),
      dark: (a.dark ?? kEmber.rawAccent).toARGB32(),
    );
  }

  /// Resets the switch so one test cannot leak its palette into the next.
  @visibleForTesting
  static void resetForTest() {
    _mode = AppThemeMode.system;
    _platform = Brightness.dark;
    _store = null;
    accentChoice.value = Accent.scheme;
    scheme.value = kEmber;
  }

  static Color get bg => scheme.value.bg;
  static Color get panel => scheme.value.panel;
  static Color get fly => scheme.value.fly;
  static Color get flyHov => scheme.value.flyHov;
  static Color get field => scheme.value.field;
  static Color get text => scheme.value.text;
  static Color get dim => scheme.value.dim;
  static Color get sep => scheme.value.sep;
  /// The accent, after the user's choice (#11). `Accent.scheme` returns null
  /// and the palette's own colour stands, which is what every install had
  /// before the setting existed.
  static Color get accent => scheme.value.accent;

  static Color get hover => scheme.value.hover;
  static Color get viewport => scheme.value.viewport;
  static Color get floor => scheme.value.floor;
  static Color get ribbonTop => scheme.value.ribbonTop;
  static Color get ribbonBottom => scheme.value.ribbonBottom;
  static Color get panelSep => scheme.value.panelSep;

  static Color get mbBg => scheme.value.mbBg;
  static Color get mbHead => scheme.value.mbHead;
  static Color get mbBorder => scheme.value.mbBorder;
  static Color get mbHeadBorder => scheme.value.mbHeadBorder;
  static Color get mbText => scheme.value.mbText;
  static Color get mbDim => scheme.value.mbDim;
  static Color get mbDimmed => scheme.value.mbDimmed;
  static Color get mbActiveBg => scheme.value.mbActiveBg;
  static Color get mbActiveOutline => scheme.value.mbActiveOutline;
  static Color get mbHover => scheme.value.mbHover;

  static Color get tabbarBg => scheme.value.tabbarBg;
  static Color get tabbarBorder => scheme.value.tabbarBorder;
  static Color get tabBg => scheme.value.tabBg;
  static Color get tabOnBg => scheme.value.tabOnBg;
  static Color get tabText => scheme.value.tabText;
  static Color get tabUnderline => scheme.value.tabUnderline;

  static Color get cardBg => scheme.value.cardBg;
  static Color get cardBorder => scheme.value.cardBorder;
  static Color get cardHoverBorder => scheme.value.cardHoverBorder;
  static Color get homeH1 => scheme.value.homeH1;
  static Color get cardName => scheme.value.cardName;
  static Color get cardDate => scheme.value.cardDate;

  static Color get galleryBg => scheme.value.galleryBg;
  static Color get galleryThumb => scheme.value.galleryThumb;
  static Color get galleryTitle => scheme.value.galleryTitle;
  static Color get galleryActionBg => scheme.value.galleryActionBg;
  static Color get galleryActionBgHover => scheme.value.galleryActionBgHover;
  static Color get cardShadow => scheme.value.cardShadow;

  static Color get rawGrey => scheme.value.rawGrey;
  static Color get projRef => scheme.value.projRef;
  static Color get projRefEdge => scheme.value.projRefEdge;
  static Color get finishGreen => scheme.value.finishGreen;

  static Color get hover6 => scheme.value.hover6;
  static Color get hover7 => scheme.value.hover7;
  static Color get hover8 => scheme.value.hover8;
  static Color get border10 => scheme.value.border10;
  static Color get conActiveBg => scheme.value.conActiveBg;
  static Color get conActiveBorder => scheme.value.conActiveBorder;

  static Color get scrim => scheme.value.scrim;
  static Color get shadow => scheme.value.shadow;
  static Color get chipBg => scheme.value.chipBg;
  static Color get chipStrong => scheme.value.chipStrong;
  static Color get onAccent => scheme.value.onAccent;
  static Color get disabled => scheme.value.disabled;
  static Color get disabledFill => scheme.value.disabledFill;
  static Color get warn => scheme.value.warn;
  static Color get warnText => scheme.value.warnText;
  static Color get err => scheme.value.err;
  static Color get errFill => scheme.value.errFill;
  static Color get errText => scheme.value.errText;
  static Color get ok => scheme.value.ok;
  static Color get okText => scheme.value.okText;

  static Color get ink => scheme.value.ink;
  static Color get inkDim => scheme.value.inkDim;
  static Color get constr => scheme.value.constr;
  static Color get snapOk => scheme.value.snapOk;
  static Color get grid => scheme.value.grid;
  static Color get axis => scheme.value.axis;
  static Color get node => scheme.value.node;
  static Color get dofFull => scheme.value.dofFull;
  static Color get dofUnder => scheme.value.dofUnder;
  static Color get refDim => scheme.value.refDim;
  static Color get dofArrow => scheme.value.dofArrow;
  static Color get ctrl => scheme.value.ctrl;

  static Color get dimLine => scheme.value.dimLine;
  static Color get dimText => scheme.value.dimText;
  static Color get dimPlate => scheme.value.dimPlate;
  static Color get dimPlateHot => scheme.value.dimPlateHot;
  static Color get hudBg => scheme.value.hudBg;
  static Color get hudBgHot => scheme.value.hudBgHot;
  static Color get toastBg => scheme.value.toastBg;
  static Color get toastBorder => scheme.value.toastBorder;
  static Color get toastText => scheme.value.toastText;

  static Color get solid => scheme.value.solid;
  static Color get solidEdge => scheme.value.solidEdge;
  static Color get edgeAccent => scheme.value.edgeAccent;
  static Color get faceHighlight => scheme.value.faceHighlight;
  static Color get previewFill => scheme.value.previewFill;
  static Color get previewEdge => scheme.value.previewEdge;
  static Color get okSolid => scheme.value.okSolid;
  static Color get okSolidBright => scheme.value.okSolidBright;
  static Color get axisX => scheme.value.axisX;
  static Color get axisY => scheme.value.axisY;
  static Color get axisZ => scheme.value.axisZ;
  static Color get cubeFace => scheme.value.cubeFace;
  static Color get cubeFaceTop => scheme.value.cubeFaceTop;
  static Color get cubeFaceDim => scheme.value.cubeFaceDim;
  static Color get cubeEdge => scheme.value.cubeEdge;
  static Color get cubeText => scheme.value.cubeText;

  static const fontFamily = '.SF UI Text'; // system-ui on iOS (mock fallback)
}


/// The Material theme, derived from [Palette] so a scheme change carries the
/// framework's own surfaces (text selection, cursors, dialogs) with it.
/// [accent] is passed rather than taken from `p` so the user's choice (#11)
/// reaches the framework's own surfaces too. A cursor and a selection handle
/// in the palette's teal, inside an app the user has set to amber, is the same
/// two-schemes-at-once bug M237 exists to prevent — one layer down.
ThemeData materialTheme(Palette p, {Color? accent}) {
  final a = accent ?? p.accent;
  return ThemeData(
    brightness: p.brightness,
    scaffoldBackgroundColor: p.viewport,
    colorScheme: ColorScheme.fromSeed(
      seedColor: a,
      brightness: p.brightness,
      surface: p.panel,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: a,
      selectionColor: a.withValues(alpha: 0.35),
      selectionHandleColor: a,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: ts(11.5, p.onAccent),
      decoration: BoxDecoration(
        color: p.fly,
        border: Border.all(color: p.sep),
      ),
    ),
  );
}

TextStyle ts(double size, Color color,
        {FontWeight w = FontWeight.normal, double height = 1.1}) =>
    TextStyle(fontSize: size, color: color, fontWeight: w, height: height);

/// M171/M206 — the keyboard a VALUE field asks for: NONE.
///
/// M171 asked for `numberWithOptions(signed: true, decimal: true)`, reasoning
/// that a full QWERTY to type "12" costs a third of the screen and buries the
/// geometry being dimensioned. That reasoning was right and the constant did
/// the opposite of it, because of one flag: iOS maps a SIGNED number type to
/// `UIKeyboardTypeNumbersAndPunctuation`, which is the full keyboard. The
/// pattern dialog, which happened to ask unsigned, got the compact keypad —
/// and the difference was reported as exactly that: "a really small number
/// input field is used ... but in every dimension input field the whole
/// keyboard comes."
///
/// Now the app brings its own (`value_pad.dart`), so the system is asked for
/// nothing at all. The field keeps its caret, its selection and every hardware
/// key; it simply never raises a keyboard. Read that file for why we draw the
/// pad rather than flip the flag — the short version is that the system pad's
/// position is not ours to set, and "the arrow should be right under the
/// number field" was the other half of the same report.
///
/// Deliberately NOT used for the Parameters window's Equation cells: those are
/// expression-first — names, functions, references to other parameters — and a
/// numeric pad has no letters. Numbers get the pad, formulas keep the
/// keyboard. (Those cells pass `pad: false` to their ScrubField for the same
/// reason, and the two must agree.)
const TextInputType kValueKeyboard = TextInputType.none;

/// M179 — Scribble OFF on every number field.
///
/// iPadOS turns a text field into a handwriting target for the Pencil, and it
/// claims the stroke before any gesture in the Flutter tree sees it. On a
/// number field that costs more than it gives: the field it steals from is the
/// SCRUB (M172), where dragging the Pencil left and right across the number is
/// the fastest way to size anything, and what it offers instead is
/// handwriting-recognising "12" — two characters, on the numeric pad that is
/// already open, one tap away.
///
/// So: numbers are scrubbed or tapped, never written. Text fields — sketch and
/// part names, the Parameters window's equations — keep Scribble, because
/// writing a word by hand really is faster than the on-screen keyboard.
///
/// Pass as `stylusHandwritingEnabled:` next to [kValueKeyboard]; the two travel
/// together, and a value field that sets one and not the other is the bug this
/// pairing exists to make obvious.
const bool kValueHandwriting = false;
