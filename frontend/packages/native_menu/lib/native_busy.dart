import 'package:flutter/services.dart';

/// A busy card drawn by UIKit, for work the Dart isolate waits inside.
///
/// Flutter cannot show progress for a blocking native call: no frames are
/// produced while the isolate is inside it, so a Flutter spinner freezes on
/// its first frame and reads as a hang. The platform thread is a different
/// thread and stays idle, so a UIKit view over the FlutterView keeps
/// animating. See BusyOverlay.swift.
///
/// [show] is awaited on purpose. The reply comes back only once the platform
/// thread has actually put the card up, so awaiting it is what guarantees the
/// card exists BEFORE the blocking call starts — a fire-and-forget message
/// would still be sitting in the queue.
class NativeBusy {
  static const MethodChannel _ch = MethodChannel('prototype/native_menu');
  static bool _up = false;

  /// Whether a card is currently showing. Test seam, and a guard against a
  /// nested show leaving one behind.
  static bool get isShowing => _up;

  /// Returns whether the card can show the converter's REAL progress — that
  /// is, whether occt_mesh_progress resolved in this binary (see M333 in
  /// BusyOverlay.swift). False also means "no card at all"; the caller wants
  /// this only to log it, and must not change what it does on the strength of
  /// it. Worth logging because "the bar just swept the whole time" is
  /// otherwise a report with nothing in the bundle to check it against.
  /// [stages] are the stage names in the user's language, INDEXED BY STAGE
  /// NUMBER (see MeshStage). Index 0 is idle and is never shown, so it may be
  /// empty. A short list, or an empty entry, falls back to the kernel's own
  /// English rather than showing a blank line.
  ///
  /// [cancelTitle] adds a Cancel button. Omit it and there is none — which is
  /// also what happens on a build whose kernel cannot be asked to stop, since
  /// a button that does nothing is worse than no button.
  static Future<bool> show(
    String title,
    String detail, {
    List<String> stages = const [],
    String cancelTitle = '',
    String cancellingTitle = '',
  }) async {
    try {
      final real = await _ch.invokeMethod<bool>('busyShow', {
        'title': title,
        'detail': detail,
        'stages': stages,
        'cancelTitle': cancelTitle,
        'cancellingTitle': cancellingTitle,
      });
      _up = true;
      return real ?? false;
    } on PlatformException {
      // A missing card must never be the reason an import fails.
    } on MissingPluginException {
      // Host without the plugin (tests, desktop) — nothing to show.
    }
    return false;
  }

  static Future<void> hide() async {
    if (!_up) return;
    _up = false;
    try {
      await _ch.invokeMethod<void>('busyHide');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// Test-only: forget that a card is up.
  static void resetForTest() => _up = false;
}
