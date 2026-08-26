// M261 — presenting the Settings, and applying what comes back.
//
// settings.dart decides WHICH rows exist; SettingsSheet.swift draws them; this
// is the seam between the two. It owns exactly three things: gathering the
// live state into a spec, routing a tapped (section, row) pair to the thing it
// changes, and re-pushing the spec so the sheet redraws.
//
// THE RE-PUSH IS THE POINT. Nothing in the sheet holds state, so after every
// tap the whole screen is rebuilt from T, L and the environment and sent back
// down. The tick moves because the spec says so, and a language switch
// relabels the sheet itself — including its title and its Done button — under
// the user's finger. A preference screen that needs closing and reopening to
// show what it did is a preference screen people do not trust.
//
// OFF iOS there is a Flutter fallback with the same sections in the same
// order, for the reason every native surface in this app has one: the host
// test suite and a desktop run must behave, and `flutter analyze` must never
// see a MissingPluginException.
import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../ffi/occt_engine.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../settings.dart';
import '../theme.dart';
import 'bug_button.dart';

/// The live facts the About section reports.
///
/// The same numbers [captureEnv] puts at the top of a bug bundle, which is
/// deliberate: when a report and the screen disagree about which build is
/// running, one of them is lying and it should be easy to see which.
SettingsInfo settingsInfo(AppState app) {
  String kernel3d;
  try {
    final ffi = OcctFfi.instance();
    kernel3d = ffi == null ? '—' : '${ffi.version} (shim v${ffi.shimVersion})';
  } catch (_) {
    kernel3d = '—';
  }
  String system;
  try {
    system = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    system = '—';
  }
  return SettingsInfo(
    build: Log.build,
    kernel3d: kernel3d,
    kernel2d: app.backendReal ? app.backendInfo : '—',
    system: system,
  );
}

/// Opens Settings, and stays alive until it closes.
///
/// A class rather than a function because the sheet is long-lived: it sends
/// taps back over the channel for as long as it is up, and something has to
/// hold the handler and know when to take it down again.
class SettingsSheet {
  SettingsSheet._(this._app, this._context);

  final AppState _app;
  final BuildContext _context;
  static SettingsSheet? _open;

  /// True while a sheet is up. The gear button reads it so a second tap
  /// cannot stack two.
  static bool get isOpen => _open != null;

  /// The entry point. Native on iOS, a Flutter dialog everywhere else.
  static Future<void> show(BuildContext context, AppState app) async {
    if (_open != null) return;
    final sheet = SettingsSheet._(app, context);
    if (NativeMenu.isSupported) {
      _open = sheet;
      NativeMenu.setSelectionHandler(NativeMenu.kSettings, sheet._onSelect);
      final ok = await NativeMenu.showSettings(
        title: L.current.settingsTitle,
        doneLabel: L.current.settingsDone,
        sections: settingsToMaps(sheet._spec()),
      );
      // UIKit had nothing to present from. Take the handler back down rather
      // than leaving a live route to a screen that never appeared.
      if (!ok) {
        sheet._close();
        if (context.mounted) await _showFallback(context, app);
      }
      return;
    }
    await _showFallback(context, app);
  }

  List<SettingsSection> _spec() => buildSettings(
        L.current,
        mode: T.mode,
        locale: L.locale.value,
        info: settingsInfo(_app),
        diagnostics: BugReport.enabled,
      );

  void _close() {
    NativeMenu.setSelectionHandler(NativeMenu.kSettings, null);
    if (identical(_open, this)) _open = null;
  }

  Future<void> _push() async {
    await NativeMenu.updateSettings(
      title: L.current.settingsTitle,
      doneLabel: L.current.settingsDone,
      sections: settingsToMaps(_spec()),
    );
  }

  /// One tap. [section] is the section id, [row] the row id — see
  /// [NativeMenu.kSettings].
  void _onSelect(String section, String row) {
    if (row == NativeMenu.kSettingsClosed) {
      _close();
      return;
    }
    switch (section) {
      case kSecAppearance:
        final m = AppThemeMode.byId(row);
        if (m != null) T.set(m);
        break;
      case kSecLanguage:
        L.set(Locale(row)); // ignores anything not shipped; see L.set
        break;
      case kSecDiagnostics:
        _diagnostic(row);
        // The command owns the screen from here: the bug flow opens its own
        // dialogs and the share sheet is a sheet on top of a sheet. Re-pushing
        // under either is pointless and, for the bug report, actively wrong —
        // the screenshot must not catch a settings redraw.
        return;
      default:
        return; // an About row is not selectable; nothing else exists
    }
    // The state changed, so the screen has to say so.
    unawaited(_push());
  }

  void _diagnostic(String row) {
    switch (row) {
      case kRowReportProblem:
        // In front of the sheet, not behind it: the report captures a
        // screenshot, and a settings card floating over the model is not the
        // thing being complained about.
        NativeMenu.dismissSettings();
        _close();
        if (_context.mounted) unawaited(BugReport.open(_context, _app));
        break;
      case kRowShareLog:
        final path = Log.path;
        // Log.path answers a sentence rather than null when there is no file;
        // handing that to the share sheet would open a picker on nothing.
        if (!path.startsWith('/')) return;
        // CLOSE FIRST, then share — and this is not a style choice. The share
        // sheet is a POPOVER on iPad, and NativeMenu anchors every popover to
        // a rect in the FLUTTER view. Presented from on top of the settings
        // card, its source view would not be in the presenting controller's
        // hierarchy, which is the classic iPad popover crash. With the card
        // gone the share sheet comes up over the gallery, which is also where
        // a user expects to end up after asking for a file.
        NativeMenu.dismissSettings();
        _close();
        final size =
            _context.mounted ? MediaQuery.maybeOf(_context)?.size : null;
        final w = size?.width ?? 0, h = size?.height ?? 0;
        unawaited(NativeMenu.shareFile(path,
            anchor: Rect.fromLTWH(w / 2, h / 2, 1, 1)));
        break;
    }
  }

  // ---- the off-iOS stand-in ------------------------------------------------

  /// The same sections, in the same order, as plain Flutter. Not a lookalike
  /// of the UIKit sheet — it does not try to be — but every setting reachable
  /// and every value visible, which is what a desktop run and the test suite
  /// need from it.
  static Future<void> _showFallback(BuildContext context, AppState app) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _FallbackDialog(app: app),
    );
  }
}

class _FallbackDialog extends StatefulWidget {
  final AppState app;
  const _FallbackDialog({required this.app});
  @override
  State<_FallbackDialog> createState() => _FallbackDialogState();
}

class _FallbackDialogState extends State<_FallbackDialog> {
  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final spec = buildSettings(
      t,
      mode: T.mode,
      locale: L.locale.value,
      info: settingsInfo(widget.app),
      diagnostics: BugReport.enabled,
    );
    return AlertDialog(
      backgroundColor: T.panel,
      title: Text(t.settingsTitle, style: ts(15, T.text)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in spec) ...[
                if (s.header != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
                    child: Text(s.header!.toUpperCase(),
                        style: ts(10.5, T.dim)),
                  ),
                for (final r in s.rows)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.title, style: ts(13, T.text)),
                    trailing: r.kind == SettingsRowKind.value
                        ? Text(r.detail ?? '', style: ts(11.5, T.dim))
                        : (r.selected
                            ? Icon(Icons.check, size: 16, color: T.accent)
                            : null),
                    onTap: r.kind == SettingsRowKind.value
                        ? null
                        : () => _tap(s.id, r.id),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.settingsDone, style: ts(13, T.accent)),
        ),
      ],
    );
  }

  void _tap(String section, String row) {
    switch (section) {
      case kSecAppearance:
        final m = AppThemeMode.byId(row);
        if (m != null) T.set(m);
        break;
      case kSecLanguage:
        L.set(Locale(row));
        break;
      case kSecDiagnostics:
        if (row == kRowReportProblem) {
          Navigator.of(context).pop();
          BugReport.open(context, widget.app);
          return;
        }
        return;
    }
    setState(() {});
  }
}
