import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'ai_models.dart' show aiId;

abstract class Build123dTransport {
  Stream<Map<String, dynamic>> generate(Map<String, dynamic> job);
  void cancel();
}

/// Executes in the app's bundled Pyodide/OCP.wasm worker. No modelling server,
/// runtime downloads, provider keys or CAD file paths cross this bridge.
class Build123dClient implements Build123dTransport {
  static const _methods = MethodChannel('prototype/build123d');
  static const _events = EventChannel('prototype/build123d/events');
  String? _active;

  @override
  void cancel() {
    final id = _active;
    if (id != null) {
      unawaited(_methods
          .invokeMethod<void>('cancel', {'id': id}).catchError((Object _) {}));
    }
  }

  @override
  Stream<Map<String, dynamic>> generate(Map<String, dynamic> job) async* {
    if (_active != null)
      throw StateError('A local model build is already running');
    final id = aiId();
    _active = id;
    final messages = StreamController<Map<String, dynamic>>();
    Timer? timer;
    StreamSubscription<dynamic>? subscription;
    try {
      final bytes = utf8.encode(jsonEncode(job));
      if (bytes.length > 16 * 1024 * 1024) {
        throw const FormatException('Local modelling request exceeds 16 MiB');
      }
      var count = 0;
      var total = 0;
      var terminal = false;
      subscription = _events.receiveBroadcastStream().listen((raw) {
        if (raw is! Map || raw['id'] != id || messages.isClosed) return;
        try {
          final event = raw['event'];
          if (event is! Map ||
              terminal ||
              ++count > 33 ||
              !const {'preview', 'complete', 'error'}.contains(event['type'])) {
            throw const FormatException('Invalid local CAD event');
          }
          final size = utf8.encode(jsonEncode(event)).length;
          total += size;
          if (size > 17 * 1024 * 1024 || total > 64 * 1024 * 1024) {
            throw const FormatException('Local model exceeds geometry limits');
          }
          terminal = event['type'] != 'preview';
          messages.add(Map<String, dynamic>.from(event));
          if (terminal) unawaited(messages.close());
        } catch (error, stack) {
          messages.addError(error, stack);
          unawaited(messages.close());
          cancel();
        }
      }, onError: (Object error, StackTrace stack) {
        if (!messages.isClosed) {
          messages.addError(error, stack);
          unawaited(messages.close());
        }
      });
      timer = Timer(const Duration(seconds: 165), () {
        if (!messages.isClosed) {
          messages.addError(TimeoutException('Local CAD runtime timed out'));
          unawaited(messages.close());
          cancel();
        }
      });
      unawaited(_methods
          .invokeMethod<void>('run', {'id': id, 'job': job}).catchError(
              (Object error, StackTrace stack) {
        if (!messages.isClosed) {
          messages.addError(error, stack);
          unawaited(messages.close());
        }
      }));
      yield* messages.stream;
      if (!terminal)
        throw const FormatException('Local CAD stopped before completing');
    } finally {
      timer?.cancel();
      cancel();
      await subscription?.cancel();
      _active = null;
    }
  }
}
