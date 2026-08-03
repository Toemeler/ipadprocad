// Prototype — a ring buffer of the raw touch stream.
//
// The log records RESOLVED intent: "toolClick tool=Tool.line w=(5.4,10.0)".
// That is the right level for almost everything, and useless for the one class
// of bug where the resolution itself is what went wrong — a tap that armed the
// wrong tool, a drag that never started because the gesture arena gave the
// pointer to a parent, a stylus press read as a pan. For those the question is
// what the HARDWARE reported, and nothing was keeping it.
//
// Not written to the log: a pointer stream is 120 Hz per contact on an iPad
// and would bury every other line within seconds. It lives in memory, bounded,
// and is emitted only when a bug is actually reported.
import 'package:flutter/gestures.dart';

class GestureTrace {
  GestureTrace._();

  /// Roughly the last half-minute of interaction at normal speed. Sized to
  /// answer "what did I just do?" — the events leading into the moment the
  /// button was pressed — not to be a session recording.
  static const int capacity = 800;

  static final List<String> _ring = <String>[];
  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<int, int> _lastMoveMs = <int, int>{};

  /// Off switch, for tests and for turning the whole facility off with the
  /// bug button it exists to serve.
  static bool enabled = true;

  static String _kind(PointerDeviceKind k) => switch (k) {
        PointerDeviceKind.touch => 'touch',
        PointerDeviceKind.stylus => 'stylus',
        PointerDeviceKind.invertedStylus => 'stylus-inv',
        PointerDeviceKind.mouse => 'mouse',
        PointerDeviceKind.trackpad => 'trackpad',
        _ => 'other',
      };

  static void _push(String s) {
    _ring.add(s);
    if (_ring.length > capacity) _ring.removeAt(0);
  }

  /// Records [e]. Moves are thinned PER POINTER to ~25 ms, so a slow careful
  /// drag and a fast flick both leave a readable trace instead of the flick
  /// evicting everything before it.
  static void record(PointerEvent e) {
    if (!enabled) return;
    final t = _clock.elapsedMilliseconds;
    final isMove = e is PointerMoveEvent || e is PointerHoverEvent;
    if (isMove) {
      final last = _lastMoveMs[e.pointer];
      if (last != null && t - last < 25) return;
      _lastMoveMs[e.pointer] = t;
    }
    final what = switch (e) {
      PointerDownEvent() => 'DOWN',
      PointerUpEvent() => 'UP',
      PointerCancelEvent() => 'CANCEL',
      PointerMoveEvent() => 'move',
      PointerHoverEvent() => 'hover',
      PointerScrollEvent() => 'scroll',
      _ => e.runtimeType.toString(),
    };
    final b = StringBuffer()
      ..write('${t.toString().padLeft(7)}ms  ')
      ..write(what.padRight(6))
      ..write(' p${e.pointer}')
      ..write(' ${_kind(e.kind)}')
      ..write(' at(${e.position.dx.toStringAsFixed(1)},'
          '${e.position.dy.toStringAsFixed(1)})');
    if (e.pressure > 0 && e.kind == PointerDeviceKind.stylus) {
      b.write(' pressure=${e.pressure.toStringAsFixed(2)}');
    }
    if (e.buttons != 0) b.write(' buttons=${e.buttons}');
    if (e is PointerUpEvent || e is PointerCancelEvent) {
      _lastMoveMs.remove(e.pointer);
    }
    _push(b.toString());
  }

  /// How many contacts are down right now, by pointer id. A report that says
  /// "it panned instead of drawing" is usually two contacts where the user
  /// believed there was one.
  static int get liveContacts => _lastMoveMs.length;

  static List<String> dump() => List<String>.unmodifiable(_ring);

  static void clear() {
    _ring.clear();
    _lastMoveMs.clear();
  }
}
