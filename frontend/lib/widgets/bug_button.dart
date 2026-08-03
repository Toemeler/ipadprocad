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
// It DRAGS, because a bug reporter that covers the bug is useless. The default
// corner is chosen to clear the tab bar, and the position is remembered for
// the session.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../bug_capture.dart';
import '../log.dart';
import '../theme.dart';

class BugButton extends StatefulWidget {
  const BugButton({super.key, required this.app});

  final AppState app;

  /// The single switch. Flip to false to remove the affordance entirely.
  static bool enabled = true;

  @override
  State<BugButton> createState() => _BugButtonState();
}

class _BugButtonState extends State<BugButton> {
  // Remembered for the session so it stays where it was dragged.
  static Offset? _pos;
  static const double _size = 44;

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!BugButton.enabled) return const SizedBox.shrink();
    final screen = MediaQuery.of(context).size;
    final p = _pos ??
        Offset(screen.width - _size - 14, screen.height - _size - 96);

    return Positioned(
      left: p.dx.clamp(0.0, (screen.width - _size).clamp(0.0, double.infinity)),
      top: p.dy.clamp(0.0, (screen.height - _size).clamp(0.0, double.infinity)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => setState(() => _pos = (_pos ?? p) + d.delta),
        onTap: _busy ? null : _open,
        child: Semantics(
          label: 'Report a bug',
          button: true,
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: _busy ? T.sep : const Color(0xFFB4232A),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 6, spreadRadius: 1)
              ],
            ),
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.bug_report, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BugDialog(),
    );
    if (text == null) return; // cancelled
    if (!mounted) return;
    setState(() => _busy = true);
    // Capture is synchronous file work; yield one frame first so the spinner
    // actually paints rather than appearing after the freeze it is meant to
    // cover.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final file = captureBugReport(widget.app, text);
    if (!mounted) return;
    setState(() => _busy = false);
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
      title: Text('Report a bug', style: ts(16, Colors.white)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What did you expect, and what happened instead?\n'
              'The model, every feature\'s state and the full log are '
              'attached automatically — describe only what you SAW.',
              style: ts(12, Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              autofocus: true,
              maxLines: 6,
              minLines: 4,
              style: ts(13, Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. filleted the top edge at 2 mm and the wall '
                    'disappeared instead of rounding',
                hintStyle: ts(12, Colors.white38),
                filled: true,
                fillColor: const Color(0xFF191B1F),
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
          child: Text('Cancel', style: ts(13, Colors.white70)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB4232A)),
          // Deliberately NOT disabled on empty text: the state dump is the
          // valuable half and it is complete either way, so a wordless report
          // still beats no report.
          onPressed: () => Navigator.of(context).pop(_c.text),
          child: Text('Save report', style: ts(13, Colors.white)),
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
      title: Text(ok ? 'Report saved' : 'Report FAILED',
          style: ts(16, Colors.white)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ok
                  ? 'Files app > On My iPad > prototype > bugreports\n'
                      'Send the .zip — it contains everything needed; no '
                      'explanation has to travel with it.'
                  : 'The bundle could not be written. The log still has the '
                      'description, so the session is not lost — see the '
                      '"bug" lines in prototype_log.txt.',
              style: ts(12, Colors.white70),
            ),
            if (ok) ...[
              const SizedBox(height: 10),
              SelectableText(path!, style: ts(11, Colors.white54)),
            ],
          ],
        ),
      ),
      actions: [
        if (ok)
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: path!)),
            child: Text('Copy path', style: ts(13, Colors.white70)),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Done', style: ts(13, Colors.white)),
        ),
      ],
    );
  }
}
