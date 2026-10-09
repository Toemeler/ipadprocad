import 'dart:io';
import 'package:flutter/services.dart';

/// GrabCAD sign-in stays on its own website. Only a downloaded local file
/// crosses this bridge; passwords and session cookies never reach Flutter.
class NativeGrabCad {
  static const _channel = MethodChannel('prototype/native_menu');
  static bool get supported => Platform.isIOS;

  static Future<bool> signIn(
          {required String title,
          required String done,
          required String cancel,
          required String help}) async =>
      await _channel.invokeMethod<bool>('grabcadSignIn', {
        'title': title,
        'done': done,
        'cancel': cancel,
        'help': help,
      }) ??
      false;

  static Future<String> download(String url, String name) async {
    final path = await _channel.invokeMethod<String>('grabcadDownload', {
      'url': url,
      'name': name,
    });
    if (path == null) throw PlatformException(code: 'invalid_download');
    return path;
  }

  static Future<void> cancelDownload() =>
      _channel.invokeMethod<void>('grabcadCancelDownload');
}
