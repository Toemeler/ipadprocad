// M261 — what is IN the Settings screen, and nothing about how it is drawn.
//
// Deliberately free of Flutter widgets, UIKit and AppState, for the reason
// work_features.dart and part_pick.dart are: deciding which rows a preference
// screen has, which one carries the tick and what the About section reports is
// a pure function of the app's state, and a pure function should be testable
// without a device, a channel or a widget tree. The sheet renders this; Dart
// applies what comes back; neither of them decides what a setting means.
//
// ---------------------------------------------------------------------------
// Why there is a Settings screen at all
// ---------------------------------------------------------------------------
//
// Language (M234) and Appearance (M236) were put in the gallery's "+" menu,
// each with the same note: "it lives in the + menu because that is the app's
// only menu that belongs to the APP rather than to a document". That was true
// of the menus that existed, and it was the wrong shelf anyway — "+" is a
// verb, and it means "make me a new document". Two preferences hidden behind
// a create button is where people stop looking for them.
//
// So the gallery header grows a second button. Left is the app, right is the
// new document; the settings that were never about creating anything move out
// of the "+" and into the place the user already looks for settings.
//
// ---------------------------------------------------------------------------
// What belongs here, and what does not
// ---------------------------------------------------------------------------
//
// A setting is a choice that OUTLIVES the document you happen to have open.
// Appearance and Language are exactly that, and both already persist into
// settings.json. Diagnostics are here because they are about the app rather
// than the drawing, and because "Report a Problem" is the row every user
// looks for in Settings first. About is here because a prototype whose build
// cannot be read off the screen makes every bug report start with a question.
//
// What is NOT here, and each for the same reason — it belongs to the document
// and lives where the document is: units, the grid, Slice Graphics, origin
// visibility, the End of Part marker. A preference screen that reaches into
// the open drawing is a second, competing ribbon.
import 'dart:ui' show Locale;

import 'backdrop.dart';
import 'l10n/l.dart';
import 'theme.dart';
import 'render_samples.dart'
    show kRenderSampleChoices, kRenderSamplesDefault;
import 'ribbon_dock.dart' show RibbonPosition, kRibbonLabelsDefault;

/// The user-visible name of an appearance. In the ARB, like every other
/// string — [Palette.name] is 'Chalk'/'Ember', which are internal names.
///
/// M261 — moved here from home_view.dart with the setting itself. It is a
/// pure map from a mode to a word and has no business living in a widget.
String appearanceName(AppL10n t, AppThemeMode m) => switch (m) {
      AppThemeMode.system => t.appearanceSystem,
      AppThemeMode.light => t.appearanceLight,
      AppThemeMode.dark => t.appearanceDark,
    };

/// The user-visible name of an accent (bug report #11). In the ARB, like every
/// other string — the enum's own `name` is 'teal'/'amber'/…
String accentName(AppL10n t, Accent a) => switch (a) {
      Accent.scheme => t.accentScheme,
      Accent.teal => t.accentTeal,
      Accent.blue => t.accentBlue,
      Accent.indigo => t.accentIndigo,
      Accent.magenta => t.accentMagenta,
      Accent.amber => t.accentAmber,
      Accent.green => t.accentGreen,
      Accent.red => t.accentRed,
    };

/// The user-visible name of a ribbon position. In the ARB, like every other
/// string — the enum's own `name` is 'top'/'bottom'/'left'/'right'.
String ribbonName(AppL10n t, RibbonPosition p) => switch (p) {
      RibbonPosition.top => t.ribbonTop,
      RibbonPosition.bottom => t.ribbonBottom,
      RibbonPosition.left => t.ribbonLeft,
      RibbonPosition.right => t.ribbonRight,
    };

/// What a row is, which decides what UIKit builds for it.
enum SettingsRowKind {
  /// Single-select within its section: the chosen one carries the tick.
  check,

  /// A command. Tapping it does something and the sheet stays up.
  action,

  /// Read-only, with a right-aligned detail. The About rows.
  value,
}

class SettingsRow {
  final String id;
  final String title;

  /// Right-aligned detail. Only [SettingsRowKind.value] shows one.
  final String? detail;

  /// SF Symbol. Unknown names simply render without a glyph, exactly as they
  /// do in [NativeMenuItem].
  final String? symbol;

  /// M270 — the colour [symbol] is drawn in, as 0xAARRGGBB. Only the backdrop
  /// swatches use it: everywhere else a row's glyph is chrome and takes the
  /// table's own tint, and a coloured icon in a preference list reads as
  /// decoration. Here the colour is the VALUE.
  final int? tint;
  final SettingsRowKind kind;
  final bool selected;
  final bool destructive;

  const SettingsRow({
    required this.id,
    required this.title,
    this.detail,
    this.symbol,
    this.tint,
    this.kind = SettingsRowKind.action,
    this.selected = false,
    this.destructive = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        if (detail != null) 'detail': detail,
        if (symbol != null) 'symbol': symbol,
        if (tint != null) 'tint': tint,
        'kind': kind.name,
        'selected': selected,
        'destructive': destructive,
      };
}

class SettingsSection {
  final String id;
  final String? header;

  /// The grey explanatory line under a group. Used sparingly: a footer under
  /// every section is a wall of text, and the two that have one are the two
  /// where the row alone genuinely does not say enough.
  final String? footer;
  final List<SettingsRow> rows;

  const SettingsSection({
    required this.id,
    required this.rows,
    this.header,
    this.footer,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        if (header != null) 'header': header,
        if (footer != null) 'footer': footer,
        'rows': [for (final r in rows) r.toMap()],
      };
}

/// Section ids. Constants, because the handler switches on them and a header
/// string changes with the language.
const String kSecAppearance = 'appearance';
const String kSecAccent = 'accent';
const String kSecBackdrop = 'backdrop';
const String kSecLanguage = 'language';
const String kSecRibbon = 'ribbon';

/// M367 — how many samples a path-traced image gets before it is denoised.
///
/// It belongs here by this file's own rule: it OUTLIVES THE DOCUMENT. How hard
/// this iPad should work on a picture is a fact about the machine and about
/// what you are doing, not about the part — a document that carried "4096
/// samples" would impose a minute of somebody else's hardware on everyone who
/// opened it. That is the same argument render_engine.dart makes for the
/// renderer choice, and the reason that one is in the ribbon and this one is
/// not: WHICH renderer draws the viewport changes what is on screen this
/// second, so it sits next to the display mode. HOW LONG it works is a setting
/// you choose once.
const String kSecSamples = 'samples';

/// M349 — the row inside the ribbon section that is a CHECKBOX rather than one
/// of four positions. Its own id, because the handler switches on it and the
/// four dock ids are [RibbonPosition] names.
const String kRowRibbonNames = 'names';
const String kSecDiagnostics = 'diagnostics';
const String kSecAbout = 'about';

/// The two diagnostic commands.
const String kRowReportProblem = 'report';
const String kRowShareLog = 'log';

/// M348 — the live icon preview's address. A developer affordance; see
/// `icon_preview.dart` for why it is a setting and not a build constant.
const String kRowIconPreview = 'iconpreview';

/// M270 — the picture commands. [kBackdropImage] is the row that CARRIES the
/// chosen picture (and re-opens the picker); these two are the verbs beside it.
const String kRowChooseImage = 'choose';
const String kRowRemoveImage = 'remove';

/// The user-visible name of a backdrop. In the ARB, like every other string.
String backdropName(AppL10n t, String id) => switch (id) {
      kBackdropAuto => t.backdropAuto,
      'ink' => t.backdropInk,
      'slate' => t.backdropSlate,
      'forest' => t.backdropForest,
      'sand' => t.backdropSand,
      'linen' => t.backdropLinen,
      _ => t.backdropImage,
    };

/// The read-only facts the About section reports.
///
/// Passed in rather than read here, because every one of them comes from
/// somewhere this file must not import — the kernel FFI, dart:io, AppState.
/// [captureEnv] already gathers the same numbers for a bug bundle; this is the
/// same information with a face on it.
class SettingsInfo {
  final String build;
  final String kernel3d;
  final String kernel2d;
  final String system;

  const SettingsInfo({
    required this.build,
    required this.kernel3d,
    required this.kernel2d,
    required this.system,
  });
}

/// The whole screen, for the state it is given.
///
/// Pure: same inputs, same rows, no reads of [T] or [L] hidden inside. That is
/// what lets a test pin the German screen and the English one in the same run
/// without switching the app's language underneath itself.
List<SettingsSection> buildSettings(
  AppL10n t, {
  required AppThemeMode mode,
  required Locale locale,
  required SettingsInfo info,
  /// Bug report #11 — the accent the user chose. Defaulted so every existing
  /// caller (and every test that pins the other sections) keeps working.
  Accent accent = Accent.scheme,
  /// The palette the swatches are drawn against. The accents come in a light
  /// and a dark value, so a swatch is only truthful once it knows which.
  Palette palette = kEmber,
  /// M270 — the gallery's backdrop. Defaulted so every existing caller (and
  /// every test that pins the other four sections) keeps working unchanged.
  Backdrop backdrop = Backdrop.auto,
  /// M284 — where the ribbon band is docked. Defaulted so existing callers
  /// keep the flush top band.
  RibbonPosition ribbon = RibbonPosition.top,
  /// M349 — whether the ribbon writes the name under each command. Defaulted
  /// to the app's default (off), so a caller that does not care gets the
  /// screen the user actually has.
  bool ribbonNames = kRibbonLabelsDefault,
  /// M367 — the settled sample target a path-traced render aims at. Defaulted
  /// so every existing caller keeps working, and so a test that pins the other
  /// sections does not have to know about this one.
  int samples = kRenderSamplesDefault,
  /// False once the prototype's report-it-now affordance is retired
  /// (BugReport.enabled), and the whole section goes with it rather than
  /// leaving a header over nothing.
  bool diagnostics = true,
}) =>
    [
      SettingsSection(
        id: kSecAppearance,
        header: t.settingsAppearance,
        rows: [
          for (final m in AppThemeMode.values)
            SettingsRow(
              id: m.id,
              title: appearanceName(t, m),
              kind: SettingsRowKind.check,
              selected: m == mode,
            ),
        ],
        footer: t.settingsAppearanceFooter,
      ),
      // Bug report #11 — "make the accent color ... a color which is changable
      // in the settings". Directly under Appearance because it is the same
      // question one step finer: Appearance chooses the palette, this chooses
      // the one colour inside it that means "you are working on this".
      //
      // Swatched like the backdrop rows and for the same reason — a colour
      // named "Indigo" and not shown is a colour you have to pick to find out.
      SettingsSection(
        id: kSecAccent,
        header: t.settingsAccent,
        rows: [
          for (final a in Accent.values)
            SettingsRow(
              id: a.id,
              title: accentName(t, a),
              kind: SettingsRowKind.check,
              selected: a == accent,
              symbol: 'circle.fill',
              tint: a.swatchOn(palette).toARGB32(),
            ),
        ],
        footer: t.settingsAccentFooter,
      ),
      // M270 — BELOW Appearance, because it is a narrower version of the same
      // idea: Appearance is the whole app, this is one screen of it, and a
      // reader who has just chosen light or dark is exactly the reader who
      // wants to know they can also choose what the gallery sits on.
      SettingsSection(
        id: kSecBackdrop,
        header: t.settingsBackdrop,
        rows: [
          SettingsRow(
            id: kBackdropAuto,
            title: backdropName(t, kBackdropAuto),
            kind: SettingsRowKind.check,
            selected: backdrop.kind == BackdropKind.auto,
          ),
          for (final sw in kBackdropSwatches)
            SettingsRow(
              id: sw.id,
              title: backdropName(t, sw.id),
              kind: SettingsRowKind.check,
              selected: backdrop.selectedId == sw.id,
              // The swatch IS the value, which is why this row has a glyph
              // where the Appearance and Language rows deliberately do not:
              // a colour named "Slate" and not shown is a colour you have to
              // pick to find out. iOS does the same in Calendar and Reminders.
              symbol: 'circle.fill',
              tint: sw.argb,
            ),
          // The picture, if there is one, sits with the colours because it is
          // the same choice: what the gallery is painted with. Tapping it when
          // it is already chosen re-opens the picker, which is what a row
          // showing a file name is expected to do.
          if (backdrop.kind == BackdropKind.image)
            SettingsRow(
              id: kBackdropImage,
              title: backdropName(t, kBackdropImage),
              detail: _fileName(backdrop.imagePath),
              kind: SettingsRowKind.check,
              selected: true,
              symbol: 'photo',
            ),
          SettingsRow(
            id: kRowChooseImage,
            title: t.backdropChooseImage,
            symbol: 'photo.on.rectangle',
          ),
          if (backdrop.kind == BackdropKind.image)
            SettingsRow(
              id: kRowRemoveImage,
              title: t.backdropRemoveImage,
              symbol: 'trash',
              destructive: true,
            ),
        ],
        footer: t.settingsBackdropFooter,
      ),
      SettingsSection(
        id: kSecLanguage,
        header: t.settingsLanguage,
        rows: [
          for (final l in kLocales)
            SettingsRow(
              id: l.languageCode,
              // Each language is named IN ITSELF — "Deutsch" stays "Deutsch"
              // in the English screen. That is what iOS does, and it is the
              // only way the row is readable to someone who has the app in a
              // language they cannot read and is trying to get out.
              title: L.stringsFor(l).languageName,
              kind: SettingsRowKind.check,
              selected: l.languageCode == locale.languageCode,
            ),
        ],
      ),
      // M284 — the ribbon band's dock. Four positions; the default is the
      // flush top band (surface A). Placed after Language because it is an
      // interface choice, before the Diagnostics/About that always close the
      // screen.
      SettingsSection(
        id: kSecRibbon,
        header: t.settingsRibbon,
        rows: [
          for (final p in RibbonPosition.values)
            SettingsRow(
              id: p.id,
              title: ribbonName(t, p),
              kind: SettingsRowKind.check,
              selected: p == ribbon,
            ),
          // M349 — the names switch, LAST and in the same section: it is the
          // same object's second property, and a section of its own for one
          // checkbox is a header that says "Ribbon" twice. The four rows above
          // it are a choice of one; this one is a yes/no, which the tick
          // already distinguishes — a checked row among four where exactly one
          // other is checked reads as what it is.
          SettingsRow(
            id: kRowRibbonNames,
            title: t.settingsRibbonNames,
            kind: SettingsRowKind.check,
            selected: ribbonNames,
          ),
        ],
        footer: t.settingsRibbonNamesFooter,
      ),
      // M367 — after the interface choices and before Diagnostics, which is
      // where a reader looking for "how good should the picture be" gets to
      // after they have finished arranging the app and before they start
      // reporting problems with it.
      //
      // A LADDER OF ROWS, not a slider or a field. The sheet is a UIKit table
      // of rows with a tick and has never had a numeric control in it; adding
      // one for this would be a keyboard on a screen that needs none. It is
      // also the honest shape of the choice — sample counts are useful in
      // doublings, and nobody wants 137.
      SettingsSection(
        id: kSecSamples,
        header: t.settingsSamples,
        rows: [
          for (final n in kRenderSampleChoices)
            SettingsRow(
              id: '$n',
              title: t.settingsSamplesRow(n),
              kind: SettingsRowKind.check,
              selected: n == samples,
            ),
        ],
        footer: t.settingsSamplesFooter,
      ),
      if (diagnostics)
        SettingsSection(
          id: kSecDiagnostics,
          header: t.settingsDiagnostics,
          rows: [
            SettingsRow(
              id: kRowReportProblem,
              title: t.settingsReportProblem,
              symbol: 'exclamationmark.bubble',
            ),
            SettingsRow(
              id: kRowShareLog,
              title: t.settingsShareLog,
              symbol: 'square.and.arrow.up',
            ),
            SettingsRow(
              id: kRowIconPreview,
              title: t.settingsIconPreview,
              symbol: 'photo.on.rectangle',
            ),
          ],
          footer: t.settingsDiagnosticsFooter,
        ),
      SettingsSection(
        id: kSecAbout,
        header: t.settingsAbout,
        rows: [
          SettingsRow(
              id: 'build',
              title: t.settingsBuild,
              detail: info.build,
              kind: SettingsRowKind.value),
          SettingsRow(
              id: 'kernel3d',
              title: t.settingsKernel3d,
              detail: info.kernel3d,
              kind: SettingsRowKind.value),
          SettingsRow(
              id: 'kernel2d',
              title: t.settingsKernel2d,
              detail: info.kernel2d,
              kind: SettingsRowKind.value),
          SettingsRow(
              id: 'system',
              title: t.settingsSystem,
              detail: info.system,
              kind: SettingsRowKind.value),
        ],
      ),
    ];

/// The wire form of [buildSettings], which is what the channel carries.
List<Map<String, Object?>> settingsToMaps(List<SettingsSection> s) =>
    [for (final x in s) x.toMap()];

/// The last path segment, for the picture row's detail. Not the whole path: a
/// settings row is not wide enough for one and the name is the part a person
/// recognises.
String _fileName(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}
