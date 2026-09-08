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
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// M406 — a PNG of the whole WINDOW, or null where no runner can grab one.
  ///
  /// The desktop twin of the native grab iOS does with `drawHierarchy`, and it
  /// exists for the same reason: `RenderRepaintBoundary.toImage` re-rasterises
  /// Flutter's layer tree offscreen, which is a different picture from the one
  /// on the screen. The backdrop-filter surfaces are what it gets wrong — with
  /// no backdrop behind them in that pass the glass panels come out as flat
  /// white slabs — so a bug report about how the app LOOKS arrived with a
  /// picture of something else. #37 was filed against exactly that.
  ///
  /// WINDOWS ONLY, and asked as a platform test rather than by letting the
  /// channel refuse. That is the same guard `NativeMenu.screenshot` uses one
  /// file over, and it is not tidiness: a `MethodChannel` call made where
  /// nothing will answer never completes inside `testWidgets`' fake clock —
  /// neither the reply nor the timeout that was supposed to bound it — so the
  /// bug reporter's own "it returns null instead of throwing" test hangs for
  /// its full twenty seconds and fails. Reaching for a runner that cannot
  /// exist is what costs that, so this does not.
  ///
  /// The Linux runner will implement the same method one day; this is the line
  /// that has to change when it does.
  static Future<Uint8List?> screenshot() async {
    if (!Platform.isWindows) return null;
    return grabWindow();
  }

  /// The call itself, without the platform guard — which is the only part of
  /// this a host test can reach, since the guard's whole job is to stop the
  /// channel being touched there.
  @visibleForTesting
  static Future<Uint8List?> grabWindow() async {
    try {
      final png = await _ch.invokeMethod<Uint8List>('screenshot');
      return (png == null || png.isEmpty) ? null : png;
    } catch (_) {
      // No runner, an older runner, or a window that could not be grabbed.
      // All three mean the same thing here: use the other capture.
      return null;
    }
  }

  /// Tests only.
  static void resetForTest() {
    _onWillClose = null;
  }
}
