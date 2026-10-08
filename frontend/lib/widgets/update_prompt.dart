// Prototype — the desktop update banner.
//
// Everything IN update_check.dart is plain Dart: it decides whether a newer
// build exists, downloads it and checks it, without ever touching a
// BuildContext. This is the one widget that puts any of that on screen, and
// it shows what the updater is doing from the moment a newer build is found —
// see the header of update_check.dart for why.
//
// THREE SHAPES, all drawn from UpdateCheck.status:
//
//   * a BANNER, at the top of the window, that blocks nothing: "Update
//     available" with the download's progress bar, then "Update ready"
//     (Install now / Later), "A newer version is available" for a copy that
//     cannot update itself, and — on the launch after an update — how it
//     went;
//   * a SCRIM over the whole window between "Install now" and the window
//     closing, saying what is happening at each step. That gap used to be a
//     window that simply vanished;
//   * nothing at all, the rest of the time.
//
// It sits in the Stack in main.dart, over everything, on every screen — the
// old toast was painted by the viewports, so on the home gallery the one
// message the updater ever showed was not on screen at all.
import 'dart:io' show exit;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../desktop_radius.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../theme.dart';
import '../update_check.dart';
import 'window_titlebar.dart';

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
    // Not in the launch path: the check is a network call, and the first
    // frame must not wait on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // One attempt per process — a hot reload re-running this must not fire
      // a second GitHub request or a second download.
      if (_started) return;
      _started = true;
      UpdateCheck.runInBackground();
    });
  }

  Future<void> _restartNow() async {
    final go = await UpdateCheck.restartNow(
      // EVERY open document, not just the visible one: the process is about
      // to be replaced, so a tab nobody is looking at loses just as much.
      beforeInstall: widget.app.flushAllDocuments,
    );
    if (!go) return; // status is `failed`; the card says so
    // Setup is waiting on this PID with its progress card ready to show.
    // Go promptly — the scrim has already said what is happening.
    Log.i('update', 'exiting for the installer');
    Log.flush();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateStatus>(
      valueListenable: UpdateCheck.status,
      builder: (context, s, _) {
        if (s.phase == UpdatePhase.restarting) {
          return Positioned.fill(child: _RestartingScrim(status: s));
        }
        final card = _cardFor(context, s);
        // Below the custom caption strip, where there is one, so the banner
        // never sits on the window's own close and maximise buttons.
        final top = (windowChromeIsCustom
                ? WindowTitleBar.height
                : MediaQuery.paddingOf(context).top) +
            10;
        // Full width so it can centre; Align takes no hits of its own, so the
        // ribbon beside the banner stays clickable.
        return Positioned(
          left: 16,
          right: 16,
          top: top,
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position:
                      Tween(begin: const Offset(0, -0.15), end: Offset.zero)
                          .animate(a),
                  child: child,
                ),
              ),
              child: card ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Widget? _cardFor(BuildContext context, UpdateStatus s) {
    final t = L.of(context);
    final info = s.info;
    switch (s.phase) {
      case UpdatePhase.idle:
      case UpdatePhase.restarting:
        return null;

      case UpdatePhase.downloading:
        return _UpdateCard(
          key: const ValueKey('downloading'),
          icon: Icons.downloading_rounded,
          title: t.updateAvailableTitle,
          message: t.updateDownloadingMessage(info!.label),
          showProgress: true,
          progress: s.progress,
          link: info.releaseUrl.isEmpty ? null : t.updateWhatsNew,
          onLink: () => UpdateCheck.openInBrowser(info.releaseUrl),
          primary: t.updateHide,
          onPrimary: UpdateCheck.hideProgress,
          primaryFilled: false,
        );

      case UpdatePhase.downloadFailed:
        return _UpdateCard(
          key: const ValueKey('downloadFailed'),
          icon: Icons.error_outline_rounded,
          title: t.updateAvailableTitle,
          message: t.updateDownloadFailed,
          secondary: t.updateLater,
          onSecondary: UpdateCheck.dismiss,
          primary: t.updateRetry,
          onPrimary: UpdateCheck.retryDownload,
        );

      case UpdatePhase.ready:
        return _UpdateCard(
          key: const ValueKey('ready'),
          icon: Icons.system_update_alt_rounded,
          title: t.updateReadyTitle,
          message: t.updateReadyMessage(info!.label),
          link: info.releaseUrl.isEmpty ? null : t.updateWhatsNew,
          onLink: () => UpdateCheck.openInBrowser(info.releaseUrl),
          secondary: t.updateLater,
          onSecondary: UpdateCheck.later,
          primary: t.updateInstallNow,
          onPrimary: _restartNow,
        );

      case UpdatePhase.manual:
        return _UpdateCard(
          key: const ValueKey('manual'),
          icon: Icons.system_update_alt_rounded,
          title: t.updateAvailableTitle,
          message: t.updateManualMessage,
          secondary: t.updateNotNow,
          onSecondary: () => UpdateCheck.skip(info!.tag),
          primary: t.updateOpenDownloadPage,
          onPrimary: () {
            UpdateCheck.openInBrowser(info!.releaseUrl);
            UpdateCheck.dismiss();
          },
        );

      case UpdatePhase.failed:
        return _UpdateCard(
          key: const ValueKey('failed'),
          icon: Icons.error_outline_rounded,
          title: t.updateNotInstalledTitle,
          message: t.updateFailed,
          primary: t.updateOk,
          onPrimary: UpdateCheck.dismiss,
        );

      case UpdatePhase.updated:
        return _UpdateCard(
          key: const ValueKey('updated'),
          icon: Icons.check_circle_outline_rounded,
          title: t.updateDoneTitle,
          message: t.updateDoneMessage(s.label ?? ''),
          primary: t.updateOk,
          onPrimary: UpdateCheck.showPendingOffer,
          // Good news needs no answer: it goes by itself.
          autoDismiss: const Duration(seconds: 8),
        );

      case UpdatePhase.notInstalled:
        return _UpdateCard(
          key: const ValueKey('notInstalled'),
          icon: Icons.error_outline_rounded,
          title: t.updateNotInstalledTitle,
          message: t.updateNotInstalledMessage(s.label ?? ''),
          primary: t.updateOk,
          onPrimary: UpdateCheck.showPendingOffer,
        );
    }
  }
}

/// The banner at the top. Non-modal: it covers a strip, never blocks the work.
class _UpdateCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? link;
  final VoidCallback? onLink;
  final String? secondary;
  final VoidCallback? onSecondary;
  final String primary;
  final VoidCallback onPrimary;
  final Duration? autoDismiss;

  /// Draws a progress bar under the message — determinate at [progress],
  /// indeterminate while that is null.
  final bool showProgress;
  final double? progress;
  final bool primaryFilled;

  const _UpdateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.link,
    this.onLink,
    this.secondary,
    this.onSecondary,
    required this.primary,
    required this.onPrimary,
    this.autoDismiss,
    this.showProgress = false,
    this.progress,
    this.primaryFilled = true,
  });

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  @override
  void initState() {
    super.initState();
    final d = widget.autoDismiss;
    if (d != null) {
      Future.delayed(d, () {
        if (mounted) widget.onPrimary();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = desktopDialogRadius(12);
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 420.0);
    final p = widget.progress;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: T.panel,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: T.sep),
          boxShadow: const [
            BoxShadow(
                color: Palette.desktopDialogShadow,
                blurRadius: 24,
                offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(widget.icon, size: 20, color: T.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: ts(13.5, T.text, w: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(widget.message, style: ts(12.5, T.dim, height: 1.35)),
                  ],
                ),
              ),
            ]),
            if (widget.showProgress) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 6,
                      color: T.accent,
                      backgroundColor: T.sep,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 38,
                  child: Text(p == null ? '' : '${(p * 100).floor()} %',
                      textAlign: TextAlign.right, style: ts(12, T.dim)),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              // The link gives way first when the buttons need the room.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: widget.link == null
                      ? null
                      : _LinkButton(label: widget.link!, onTap: widget.onLink!),
                ),
              ),
              if (widget.secondary != null) ...[
                _CardButton(
                    label: widget.secondary!, onTap: widget.onSecondary!),
                const SizedBox(width: 8),
              ],
              _CardButton(
                  label: widget.primary,
                  onTap: widget.onPrimary,
                  primary: widget.primaryFilled),
            ]),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _CardButton(
      {required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(desktopDialogRadius(6)));
    const pad = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
    if (primary) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: T.accent,
          foregroundColor: T.onAccent,
          shape: shape,
          padding: pad,
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: ts(12.5, T.onAccent, w: FontWeight.w600)),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: T.text,
        side: BorderSide(color: T.sep),
        shape: shape,
        padding: pad,
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: ts(12.5, T.text)),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LinkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: T.accent,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(12.5, T.accent)),
      );
}

/// Between "Restart now" and the window going away: the window says what it
/// is doing, so that closing reads as the next step of an update and not as
/// a crash. It also takes the pointer — nothing should be edited after the
/// save it is waiting on.
class _RestartingScrim extends StatelessWidget {
  final UpdateStatus status;
  const _RestartingScrim({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final step = status.step == RestartStep.saving
        ? t.updateStepSaving
        : t.updateStepInstaller;
    return AbsorbPointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            decoration: BoxDecoration(
              color: T.panel,
              borderRadius: BorderRadius.circular(desktopDialogRadius(12)),
              border: Border.all(color: T.sep),
              boxShadow: const [
                BoxShadow(
                    color: Palette.desktopDialogShadow,
                    blurRadius: 32,
                    offset: Offset(0, 12)),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: T.accent),
              ),
              const SizedBox(height: 16),
              Text(t.updateRestartingTitle,
                  textAlign: TextAlign.center,
                  style: ts(14, T.text, w: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(step,
                  textAlign: TextAlign.center,
                  style: ts(12.5, T.dim, height: 1.35)),
            ]),
          ),
        ),
      ),
    );
  }
}
