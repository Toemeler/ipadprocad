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
//
//  * [LivePointers] — the set of contacts that are down RIGHT NOW, with
//    eviction for the ones iOS forgot to lift. See its own doc comment; it is
//    what stands between a lost pointer-up and a viewport that has stopped
//    answering.

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

/// M205 — the contacts that are down RIGHT NOW, and the eviction rule for the
/// ones that never came back up.
///
/// WHY THIS EXISTS
/// ---------------
/// The viewport used to keep a bare `int _pointers`, incremented on down and
/// decremented on up. That is correct exactly as long as every down is
/// followed by an up or a cancel — and on the 2026-08-05 device session it was
/// not. From `bug20260805T141441/gestures.txt`:
///
///     51623ms  DOWN   p38 mouse at(181.2,171.3)
///     52476ms  DOWN   p39 mouse at(609.4,296.8)
///     ...  45 seconds of use, neither pointer ever seen again  ...
///     97390ms  CANCEL p39 touch at(0.0,0.0)
///     97390ms  CANCEL p38 touch at(0.0,0.0)
///
/// Two pointers went down and stayed down for three quarters of a minute. The
/// tally therefore never fell below two, every fresh contact looked like "a
/// second finger", and the viewport did what it is told to do with a second
/// finger: pan and zoom instead of drawing, picking or dragging. That is the
/// whole of "I couldn't place anything and the viewport is jumping around
/// anytime i click anywhere", and of "i cant drag around any point" the hour
/// before. The pair was finally released by the CANCEL storm that the platform
/// view emits when it takes a gesture — which is why the NEXT report in the
/// same session says the movement "was again working idk what happend": filing
/// the bug is what unstuck it.
///
/// THE TWO RULES
/// -------------
/// 1. ONE DEVICE, ONE CONTACT. A pointer id is per press; the DEVICE id behind
///    it is the physical thing — a trackpad cursor, a Pencil tip, one UITouch.
///    A device cannot be pressed twice at once, so a fresh down on a device
///    that is already held proves the held one is gone. This rule cannot
///    misfire; it is not a heuristic.
/// 2. SILENCE IS DEATH. A live contact reports a move every frame even when it
///    does not move — p36, p77 and p84 in the same trace are motionless
///    presses with a move on every vsync. A contact that has said nothing for
///    [staleMs] is therefore not a resting finger, it is a lost one.
///
/// Rule 2 is a judgement call, so it is made SAFE rather than made certain: a
/// move (or an up) for a pointer that was evicted RE-ADOPTS it. The worst a
/// wrong eviction can do is mis-read the first event of a gesture that is
/// already under way, and the contact is back in the set the moment it speaks.
/// The alternative — trusting the tally — costs the whole app until the user
/// happens to file a bug report.
class LivePointers {
  LivePointers({int Function()? clock})
      : _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// How long a contact may stay silent before it is presumed lost. Generous
  /// on purpose: iOS reports motionless presses at frame rate, so a real
  /// contact refreshes itself ~60 times inside this window.
  static const int staleMs = 2000;

  final int Function() _now;
  final Map<int, PointerDeviceKind> _kind = {};
  final Map<int, int> _device = {};
  final Map<int, int> _seenMs = {};

  /// How many contacts are down.
  int get count => _kind.length;

  bool get isEmpty => _kind.isEmpty;

  /// The kind of the ONLY contact, or null when there is not exactly one.
  PointerDeviceKind? get soleKind =>
      _kind.length == 1 ? _kind.values.first : null;

  /// True while a Pencil is on the glass — the condition for palm rejection.
  bool get stylusDown => _kind.values.any((k) =>
      k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus);

  PointerDeviceKind? kindOf(int pointer) => _kind[pointer];

  /// Registers a new contact and returns the pointers dropped as lost — the
  /// caller has its own bookkeeping (palm rejection, tap classifier) to clear
  /// for each of them.
  List<int> down(int pointer, int device, PointerDeviceKind kind) {
    final lost = <int>[];
    final now = _now();
    for (final p in _kind.keys.toList()) {
      if (p == pointer) continue;
      final silent = now - (_seenMs[p] ?? now) > staleMs;
      if (_device[p] == device || silent) lost.add(p);
    }
    for (final p in lost) {
      _forget(p);
    }
    _kind[pointer] = kind;
    _device[pointer] = device;
    _seenMs[pointer] = now;
    return lost;
  }

  /// A contact spoke. Re-adopts a pointer that was evicted by mistake — that
  /// is what makes rule 2 above safe to be wrong about.
  void touch(int pointer, int device, PointerDeviceKind kind) {
    _kind[pointer] = kind;
    _device[pointer] = device;
    _seenMs[pointer] = _now();
  }

  /// Lifted or cancelled. Unknown pointers are fine: an evicted contact that
  /// comes back only to report its up must not resurrect the tally.
  void remove(int pointer) => _forget(pointer);

  /// Drops every contact that has been silent for longer than [staleMs] and
  /// returns them. Meant for a watchdog: without it a lost pointer is only
  /// noticed when the NEXT one goes down, and the user's next gesture is
  /// exactly what it would eat.
  List<int> pruneStale() {
    final now = _now();
    final lost = <int>[
      for (final p in _kind.keys)
        if (now - (_seenMs[p] ?? now) > staleMs) p
    ];
    for (final p in lost) {
      _forget(p);
    }
    return lost;
  }

  void clear() {
    _kind.clear();
    _device.clear();
    _seenMs.clear();
  }

  void _forget(int pointer) {
    _kind.remove(pointer);
    _device.remove(pointer);
    _seenMs.remove(pointer);
  }
}
