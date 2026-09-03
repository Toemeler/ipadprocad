// Prototype — the desktop window's side of the conversation.
//
// One question, asked by the runner and answered here: THE WINDOW IS ABOUT TO
// CLOSE, IS THERE ANYTHING TO WRITE?
//
// It exists because the two platforms end differently, and the difference is
// not cosmetic. iOS suspends an app and kills it later: `paused` arrives, the
// app writes the open document, and `detached` is a second chance at the same
// thing. Closing a GTK window produces `inactive`, `hidden`, and then the
// engine is torn down — measured, on Flutter 3.47: the save started on
// `hidden` got as far as the DXF and the process was gone before the document
// file was packed. A lifecycle callback cannot fix that, because it is `void`
// and cannot make anybody wait.
//
// So the runner asks first and WAITS for the answer (see
// linux/runner/my_application.cc: it returns TRUE from `delete-event`, invokes
// `willClose`, and destroys the window in the reply callback). This is the
// Dart end of that handshake. It is also exactly the shape `didRequestAppExit`
// has, which is what a future GTK — and Windows today — will use instead; when
// that happens this file goes away and nothing else changes.
import 'package:flutter/services.dart';

/// The channel the runner opens. Named for the surface rather than the
/// platform: the Windows runner will use the same name and the same method.
const String _kChannel = 'prototype/desktop';

class DesktopShell {
  DesktopShell._();

  static const MethodChannel _ch = MethodChannel(_kChannel);
  static Future<void> Function()? _onWillClose;

  /// Registers what to do before the window closes.
  ///
  /// The runner blocks the close until this future completes — and gives up
  /// after a couple of seconds, because a window that cannot be closed is a
  /// worse bug than a document that was not saved. Keep the work here to
  /// writing what is already in memory.
  ///
  /// A no-op where no runner asks (iOS, the test host): the handler is stored
  /// and never called.
  static void onWillClose(Future<void> Function() handler) {
    _onWillClose = handler;
    _ch.setMethodCallHandler(_handle);
  }

  static Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'willClose') return null;
    final handler = _onWillClose;
    if (handler == null) return true;
    await handler();
    // The value is not read; replying at all is the signal. Returning it
    // rather than null keeps the channel's contract obvious from either side.
    return true;
  }

  /// Tests only.
  static void resetForTest() {
    _onWillClose = null;
  }
}
