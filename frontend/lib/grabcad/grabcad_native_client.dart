import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:native_menu/grabcad.dart';
import 'grabcad_client.dart';

/// iPad metadata requests use the same WebKit cookies as sign-in/downloads.
/// Session cookies stay native; only public model JSON crosses this bridge.
class GrabCadNativeClient extends http.BaseClient {
  static int _nextId = 0;
  final _pending = <String>{};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed');
    if (request.url.scheme != 'https' ||
        request.url.host != 'grabcad.com' ||
        !request.url.path.startsWith('/community/api/v1/') ||
        !['GET', 'POST'].contains(request.method)) {
      throw http.ClientException('Unsupported GrabCAD request');
    }
    final id = 'metadata-${++_nextId}';
    _pending.add(id);
    try {
      final bytes = await request.finalize().toBytes();
      if (_closed) throw http.ClientException('Client closed');
      final response = await NativeGrabCad.request(
        id: id,
        path: request.url.path.substring('/community/api/v1/'.length) +
            (request.url.hasQuery ? '?${request.url.query}' : ''),
        body: request.method == 'POST' ? utf8.decode(bytes) : null,
      );
      if (_closed) throw http.ClientException('Client closed');
      return http.StreamedResponse(
        Stream.value(utf8.encode(response['body'] as String)),
        response['status'] as int,
        headers: {'content-type': response['contentType'] as String? ?? ''},
      );
    } on PlatformException catch (e) {
      throw GrabCadException(e.code);
    } finally {
      _pending.remove(id);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (_pending.isNotEmpty) {
      unawaited(
          NativeGrabCad.cancelRequests(_pending.toList()).catchError((_) {}));
    }
  }
}
