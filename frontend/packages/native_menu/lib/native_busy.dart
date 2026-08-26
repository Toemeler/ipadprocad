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

  static Future<void> show(String title, String detail) async {
    try {
      await _ch.invokeMethod<void>('busyShow', {
        'title': title,
        'detail': detail,
      });
      _up = true;
    } on PlatformException {
      // A missing card must never be the reason an import fails.
    } on MissingPluginException {
      // Host without the plugin (tests, desktop) — nothing to show.
    }
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
