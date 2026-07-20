// M53 — touch & Apple-Pencil input helpers.
//
// The viewport's pointer plumbing stays where it is; this file holds the two
// pieces that are PURE LOGIC and therefore host-testable without a widget
// tree:
//
//  * [MultiFingerTap] — Procreate's gesture language: a quick two-finger tap
//    is UNDO, a quick three-finger tap is REDO. "Quick" means all fingers up
//    within [maxDurationMs] of the first one down, and no finger travelled
//    more than [moveSlopPx] — that is exactly what separates a tap from the
//    two-finger pan/pinch, which always moves. Any stylus or mouse activity
//    while fingers are down poisons the session (a palm bumping the canvas
//    mid-stroke must never fire an undo).
//
//  * [touchSlop] — hit radii for fingers. A fingertip is ~7 mm of contact
//    where a pencil tip or mouse cursor is a point; Apple's HIG floor for
//    touch targets is 44 pt. Grips, snaps and pick tolerances scale up for
//    PointerDeviceKind.touch and stay at their precise values for stylus and
//    mouse, so the Pencil keeps CAD precision while fingers get CAD mercy.

import 'dart:ui';

import 'package:flutter/gestures.dart';

/// Scale factor applied to pick/snap/grip radii for finger input.
const double kTouchSlopFactor = 1.8;

/// Kind-aware hit radius: [base] px for mouse/stylus, ~1.8x for fingers.
double touchSlop(PointerDeviceKind kind, double base) =>
    kind == PointerDeviceKind.touch ? base * kTouchSlopFactor : base;

/// True for pointer kinds with a precise tip (mouse, trackpad, Apple Pencil).
bool isFinePointer(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.mouse ||
    kind == PointerDeviceKind.stylus ||
    kind == PointerDeviceKind.invertedStylus;

/// Classifies quick multi-finger taps (Procreate: two fingers = undo, three =
/// redo). Feed it every TOUCH pointer's down/move/up/cancel; call
/// [nonTouchActivity] whenever a stylus or mouse button goes down. [up]
/// returns the finger count of a completed clean tap (2 or 3) exactly once,
/// when the last finger lifts — and 0 in every other case.
class MultiFingerTap {
  MultiFingerTap({int Function()? clock})
      : _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// All fingers must be up again within this long of the first one down.
  static const int maxDurationMs = 350;

  /// A finger travelling further than this is a pan/pinch, not a tap.
  static const double moveSlopPx = 18.0;

  final int Function() _now;
  final Map<int, Offset> _downAt = {}; // active touch pointers -> down pos
  int _startMs = 0;
  int _maxCount = 0;
  bool _moved = false;
  bool _poisoned = false;

  /// Number of touch pointers currently down.
  int get activeCount => _downAt.length;

  void down(int pointer, Offset pos) {
    if (_downAt.isEmpty) {
      // first finger of a fresh session
      _startMs = _now();
      _maxCount = 0;
      _moved = false;
      _poisoned = false;
    }
    _downAt[pointer] = pos;
    if (_downAt.length > _maxCount) _maxCount = _downAt.length;
  }

  void move(int pointer, Offset pos) {
    final d = _downAt[pointer];
    if (d == null) return;
    if ((pos - d).distance > moveSlopPx) _moved = true;
  }

  /// Stylus/mouse went down (or a long-press fired) while fingers are down:
  /// whatever this session is, it is not a deliberate undo/redo tap.
  void nonTouchActivity() {
    if (_downAt.isNotEmpty) _poisoned = true;
  }

  void cancel(int pointer) {
    if (_downAt.remove(pointer) != null) _poisoned = true;
  }

  /// Lift a finger. Returns 2 or 3 when this completed a clean two-/three-
  /// finger tap, otherwise 0.
  int up(int pointer, Offset pos) {
    final d = _downAt.remove(pointer);
    if (d == null) return 0;
    if ((pos - d).distance > moveSlopPx) _moved = true;
    if (_downAt.isNotEmpty) return 0; // fingers still down
    final ok = !_moved &&
        !_poisoned &&
        _now() - _startMs <= maxDurationMs &&
        (_maxCount == 2 || _maxCount == 3);
    final n = ok ? _maxCount : 0;
    _maxCount = 0;
    return n;
  }
}
