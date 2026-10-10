import 'dart:io';
import 'package:flutter/services.dart';

/// GrabCAD sign-in stays on its own website. Only a downloaded local file
/// crosses this bridge; passwords and session cookies never reach Flutter.
class NativeGrabCad {
  static const _channel = MethodChannel('prototype/native_menu');
  static bool get supported =>
      Platform.isIOS || Platform.isWindows || Platform.isLinux;

  static Future<bool> signIn(
          {required String title,
          required String done,
          required String cancel,
          required String help,
          String? unavailable}) async =>
      await _channel.invokeMethod<bool>('grabcadSignIn', {
        'title': title,
        'done': done,
        'cancel': cancel,
        'help': help,
        if (unavailable != null) 'unavailable': unavailable,
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

  static Future<void> installRuntime() =>
      _channel.invokeMethod<void>('grabcadInstallRuntime');

  static Future<void> cancelDownload() =>
      _channel.invokeMethod<void>('grabcadCancelDownload');

  static Future<Map<dynamic, dynamic>> request(
      {required String id, required String path, String? body}) async {
    final response = await _channel.invokeMapMethod<dynamic, dynamic>(
        'grabcadRequest', {'id': id, 'path': path, 'body': body});
    if (response == null) throw PlatformException(code: 'unavailable');
    return response;
  }

  static Future<Map<dynamic, dynamic>> diagnostics() async =>
      await _channel.invokeMapMethod<dynamic, dynamic>('grabcadDiagnostics') ??
      {};

  static Future<void> cancelRequests(List<String> ids) =>
      _channel.invokeMethod<void>('grabcadCancelRequests', {'ids': ids});
}
