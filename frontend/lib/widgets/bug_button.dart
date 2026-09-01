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
    final answer = await showDialog<BugReportRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BugDialog(),
    );
    if (answer == null) return; // cancelled
    if (!context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final result =
        await captureBugReport(app, answer.text, autofix: answer.autofix);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ResultDialog(
        path: result.file?.path,
        issueUrl: result.upload?.issueUrl,
        uploadFailed: result.upload != null && !result.upload!.ok,
      ),
    );
  }
}

/// What the report dialog came back with.
///
/// A record rather than a bare String since the checkbox arrived: the fix
/// automation is opt-OUT, and which way the box was left has to travel with
/// the words all the way to the label on the issue.
class BugReportRequest {
  const BugReportRequest(this.text, {required this.autofix});
  final String text;

  /// True — the default — means the issue is filed for the automated fixer.
  /// False means it is filed for a person, and `ci/bugfix` never claims it.
  final bool autofix;
}

class _BugDialog extends StatefulWidget {
  const _BugDialog();

  @override
  State<_BugDialog> createState() => _BugDialogState();
}

class _BugDialogState extends State<_BugDialog> {
  final _c = TextEditingController();

  /// ON by default. Most reports are the automation's to take, and a default
  /// that has to be switched ON is a default nobody uses.
  bool _autofix = true;

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
            const SizedBox(height: 8),
            // A row rather than a CheckboxListTile: this dialog is 460 wide
            // and the tile's own padding would push the label away from the
            // box far enough to read as two separate controls.
            InkWell(
              onTap: () => setState(() => _autofix = !_autofix),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _autofix,
                      onChanged: (v) => setState(() => _autofix = v ?? true),
                      side: BorderSide(color: T.sep),
                      activeColor: T.accent,
                      checkColor: T.onAccent,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(L.of(context).bugAutofix,
                          style: ts(12, T.text)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                _autofix
                    ? L.of(context).bugAutofixOn
                    : L.of(context).bugAutofixOff,
                style: ts(11, T.dim),
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
          onPressed: () => Navigator.of(context)
              .pop(BugReportRequest(_c.text, autofix: _autofix)),
          child: Text(L.of(context).btnSaveReport, style: ts(13, T.onAccent)),
        ),
      ],
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.path, this.issueUrl, this.uploadFailed = false});

  final String? path;
  final String? issueUrl;
  final bool uploadFailed;

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
            if (issueUrl != null) ...[
              const SizedBox(height: 10),
              Text(L.of(context).msgBugUploaded, style: ts(12, T.dim)),
              const SizedBox(height: 4),
              SelectableText(issueUrl!, style: ts(11, T.dim)),
            ] else if (uploadFailed) ...[
              const SizedBox(height: 10),
              Text(L.of(context).msgBugUploadFailed, style: ts(12, T.dim)),
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
        if (issueUrl != null)
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: issueUrl!)),
            child: Text(L.of(context).btnCopyIssueLink, style: ts(13, T.text)),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.of(context).done, style: ts(13, T.onAccent)),
        ),
      ],
    );
  }
}
