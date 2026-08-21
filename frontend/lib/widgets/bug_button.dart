// Prototype — the report-it-now button.
//
// TEMPORARY, by request: this is a debugging affordance for the prototype
// phase, not a shipping feature. [BugButton.enabled] turns the whole thing off
// in one place when it has served its purpose.
//
// Why a button at all, when there is already a log: the log says what the app
// did, never what the user expected. A bug is the gap between those two, and
// only one of them is on disk. Pressing this while the wrong thing is still on
// screen captures BOTH — the sentence, and the exact model state that produced
// it — into one file, with no round trip to ask "which feature?" or "can you
// send the part too?".
//
// M194 — it used to be a red circle FLOATING over the canvas, draggable
// because a bug reporter that covers the bug is useless. It is now the last
// button of the quick-tool bar (M192), which is chrome and therefore covers
// nothing: the reason to drag it went away, and one less thing floats over the
// model. What is left here is the flow — the two dialogs and the capture
// between them — with no widget of its own.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../bug_capture.dart';
import '../log.dart';
import '../theme.dart';
import '../l10n/l.dart';

/// The report-it-now affordance, as a flow rather than a widget.
class BugReport {
  /// The single switch. Flip to false to remove the affordance entirely —
  /// the bar drops its button with it.
  static bool enabled = true;

  /// Describe it, capture it, say where it landed.
  ///
  /// No progress indicator on purpose. The screenshot inside
  /// [captureBugReport] must show the state being COMPLAINED about, and the
  /// surest way to keep the reporting UI out of it is to have none on screen
  /// while it is taken — hence the delay, which lets the dialog finish
  /// dismissing before the frame is grabbed. The two dialogs bracket the wait,
  /// so the user is never left wondering whether the tap registered.
  static Future<void> open(BuildContext context, AppState app) async {
    if (!enabled) return;
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BugDialog(),
    );
    if (text == null) return; // cancelled
    if (!context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final file = await captureBugReport(app, text);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ResultDialog(path: file?.path),
    );
  }
}

class _BugDialog extends StatefulWidget {
  const _BugDialog();

  @override
  State<_BugDialog> createState() => _BugDialogState();
}

class _BugDialogState extends State<_BugDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.panel,
      title: Text(L.of(context).dlgReportBug, style: ts(16, T.text)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L.of(context).msgBugPrompt,
              style: ts(12, T.dim),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              autofocus: true,
              maxLines: 6,
              minLines: 4,
              style: ts(13, T.onAccent),
              decoration: InputDecoration(
                hintText: L.of(context).hintBugExample,
                hintStyle: ts(12, T.dim),
                filled: true,
                fillColor: T.field,
                border: OutlineInputBorder(
                    borderSide: BorderSide(color: T.sep)),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: T.sep)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.of(context).cancel, style: ts(13, T.text)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: T.errFill),
          // Deliberately NOT disabled on empty text: the state dump is the
          // valuable half and it is complete either way, so a wordless report
          // still beats no report.
          onPressed: () => Navigator.of(context).pop(_c.text),
          child: Text(L.of(context).btnSaveReport, style: ts(13, T.onAccent)),
        ),
      ],
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final ok = path != null;
    if (!ok) {
      Log.w('bug', 'result dialog: no bundle was written');
    }
    return AlertDialog(
      backgroundColor: T.panel,
      title: Text(ok ? L.of(context).msgReportSaved : L.of(context).msgReportFailed,
          style: ts(16, T.text)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ok
                  ? L.of(context).msgBugSaved
                  : L.of(context).msgBugBundleFailed,
              style: ts(12, T.dim),
            ),
            if (ok) ...[
              const SizedBox(height: 10),
              SelectableText(path!, style: ts(11, T.dim)),
            ],
          ],
        ),
      ),
      actions: [
        if (ok)
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: path!)),
            child: Text(L.of(context).btnCopyPath, style: ts(13, T.text)),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.of(context).done, style: ts(13, T.onAccent)),
        ),
      ],
    );
  }
}
