import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../log.dart';
import 'ai_trace.dart';

/// A bounded local journal, so restarting after an AI fault does not erase
/// the provider's response. Uses the same scrubbed data as the bug bundle.
/// I/O failures never prevent modelling or overwrite conversation state.
class AiTraceStore {
  AiTraceStore(Directory directory)
      : file = File('${directory.path}/ai_trace.json');

  final File file;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  bool _closed = false;
  static const maxFileBytes = 16 * 1024 * 1024;

  Future<void> open() async {
    try {
      if (await file.exists()) {
        if (await file.length() > maxFileBytes) {
          throw const FormatException('Oversized AI trace journal');
        }
        AiTrace.restore(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {
      Log.w('ai', 'previous trace journal could not be read');
    }
    AiTrace.listeners.add(_changed);
  }

  void _changed() {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    if (_closed) return _queue;
    // Capture before queued I/O; a later clear must follow this write.
    final bytes = utf8.encode(jsonEncode(AiTrace.json()));
    _queue = _queue.then((_) async {
      try {
        if (bytes.length > maxFileBytes) {
          throw const FormatException('Oversized AI trace journal');
        }
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } catch (_) {
        Log.w('ai', 'trace journal could not be saved');
      }
    });
    return _queue;
  }

  Future<void> close() {
    AiTrace.listeners.remove(_changed);
    final pending = flush();
    _closed = true;
    return pending;
  }
}
