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

import 'l10n/l.dart';
import 'theme.dart';

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
  final SettingsRowKind kind;
  final bool selected;
  final bool destructive;

  const SettingsRow({
    required this.id,
    required this.title,
    this.detail,
    this.symbol,
    this.kind = SettingsRowKind.action,
    this.selected = false,
    this.destructive = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        if (detail != null) 'detail': detail,
        if (symbol != null) 'symbol': symbol,
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
const String kSecLanguage = 'language';
const String kSecDiagnostics = 'diagnostics';
const String kSecAbout = 'about';

/// The two diagnostic commands.
const String kRowReportProblem = 'report';
const String kRowShareLog = 'log';

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
