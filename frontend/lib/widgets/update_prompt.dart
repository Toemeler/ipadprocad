// Prototype — the desktop update prompt.
//
// Everything IN update_check.dart is plain Dart: it can decide whether a
// newer build exists without ever touching a BuildContext. Asking the user
// cannot be plain Dart — confirmAction (native_prompts.dart) needs a route to
// push — so this is the one widget that exists to hand it one. It renders
// nothing of its own; it is dropped into the Stack in main.dart purely to be
// a place in the tree with a Navigator above it.
import 'dart:io' show exit;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../update_check.dart';
import 'native_prompts.dart';

class UpdatePrompt extends StatefulWidget {
  final AppState app;
  const UpdatePrompt({super.key, required this.app});

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Not in the launch path: the check itself is a network call, and this
    // widget's own first build must not wait on it. addPostFrameCallback
    // means the first frame is already on screen before anything here runs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    // One attempt per process — a second addPostFrameCallback (a hot reload
    // in development; nothing on a real launch re-triggers initState) must
    // not fire a second GitHub request or, worse, a second dialog stacked on
    // the first.
    if (_started) return;
    _started = true;

    final info = await UpdateCheck.checkIfDue();
    if (info == null || !mounted) return;

    final t = L.of(context);
    final wantsUpdate = await confirmAction(
      context,
      title: t.updateAvailableTitle,
      message: info.selfUpdatable
          ? t.updateAvailableMessage
          : t.updateManualMessage,
      confirmLabel:
          info.selfUpdatable ? t.updateNow : t.updateOpenDownloadPage,
      // This is an offer, not a warning — Cancel/"not now" must not be
      // painted the way a destructive action is.
      destructive: false,
    );
    if (!mounted) return;

    if (!wantsUpdate) {
      UpdateCheck.skip(info.tag);
      return;
    }

    if (!info.selfUpdatable) {
      // apply() itself opens the release page and returns false — nothing
      // more to do here, and nothing to exit for.
      await UpdateCheck.apply(info);
      return;
    }

    widget.app.toast(t.updateDownloading);
    // SAVING HAPPENS INSIDE apply(), before anything is launched, and that
    // order is the fix rather than a tidy-up. It used to be here, AFTER the
    // installer had been started — and Setup closes this app through the
    // Restart Manager within a second or two of starting, which meant the
    // window went away while this line was still writing a part file. The
    // user reported it as the app crashing during updates, which is what it
    // looked like and very nearly what it was.
    //
    // EVERY open document, not just the visible one: the process is about to
    // be replaced, so a tab nobody is looking at loses just as much.
    final applied = await UpdateCheck.apply(
      info,
      beforeInstall: widget.app.flushAllDocuments,
    );
    if (!applied) {
      if (mounted) widget.app.toast(t.updateFailed);
      return;
    }

    // Everything is saved and the installer is queued behind this process's
    // own exit (see windowsRelaunchScript). Go, promptly: the script is
    // waiting on this PID and the user is watching a window that has already
    // said it is updating.
    Log.i('update', 'update queued — exiting for the installer');
    exit(0);
  }

  // Nothing to paint — this widget exists only to own a BuildContext with a
  // Navigator above it. UpdateCheck.checkIfDue() is the Linux/Windows guard;
  // on iOS it returns null immediately and _run() never gets past it.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
