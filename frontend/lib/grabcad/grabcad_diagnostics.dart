import 'dart:collection';

/// Bounded session history, independent of file-log rotation. Callers must
/// supply diagnostic messages only, never headers, cookies or account data.
class GrabCadDiagnostics {
  static const capacity = 300;
  static final _events = Queue<Map<String, Object>>();
  static int _dropped = 0;

  static void record(String level, String message) {
    if (_events.length == capacity) {
      _events.removeFirst();
      _dropped++;
    }
    _events.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'level': level.trim(),
      'message': message.length > 2048 ? message.substring(0, 2048) : message,
    });
  }

  static Map<String, Object> snapshot() => {
        'schemaVersion': 1,
        'scope': 'current app session',
        'droppedEvents': _dropped,
        'events': _events.map((e) => Map<String, Object>.of(e)).toList(),
      };
}
