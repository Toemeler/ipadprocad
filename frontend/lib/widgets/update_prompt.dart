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
    final applied = await UpdateCheck.apply(info);
    if (!applied) {
      if (mounted) widget.app.toast(t.updateFailed);
      return;
    }

    // The new build is already launching (Windows) or launched (Linux) —
    // see UpdateCheck.apply. This process now has to let go of its files,
    // the open document included, as fast as it safely can.
    Log.i('update', 'applying update — flushing and exiting');
    await widget.app.flushCurrentDocument();
    exit(0);
  }

  // Nothing to paint — this widget exists only to own a BuildContext with a
  // Navigator above it. UpdateCheck.checkIfDue() is the Linux/Windows guard;
  // on iOS it returns null immediately and _run() never gets past it.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
