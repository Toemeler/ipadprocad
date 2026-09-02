// M355 — when the compositor needs the GPU more than the path tracer does.
//
// ---------------------------------------------------------------------------
// THE PROBLEM THIS IS THE LAST PIECE OF
// ---------------------------------------------------------------------------
//
// A path tracer that is running is a path tracer Flutter's compositor queues
// behind for the slice of GPU it needs every eight milliseconds. M354 settled
// that for the ORBIT by not running the tracer at all during a camera move.
//
// It did nothing for the rest of the app. A settled render is megapixels
// against a 4096-sample ceiling — seconds to minutes of solid GPU — and for
// all of it the user can be scrolling the browser, opening a panel or dragging
// a ribbon. Every one of those is an animation that needs the compositor, and
// the compositor is behind the tracer.
//
// M354's remedy cannot be reused here. It parks the session by pushing it a
// view it can finish at once, and pushing a view calls Session::reset, which
// throws away every sample taken so far. Doing that on each touch would reset
// a converging image to noise every time the user brushed the screen. The
// tracer has to stand down and come BACK to the same picture, which is
// cy_live_pause / Session::set_pause and is what Blender's viewport uses.
//
// ---------------------------------------------------------------------------
// WHAT COUNTS AS BUSY, AND WHY IT IS MOVEMENT RATHER THAN TOUCH
// ---------------------------------------------------------------------------
//
// The obvious rule — pause while a finger is down — is wrong in a way that
// matters. Orbit to an angle, then keep the finger on the glass while you look
// at it: the camera has stopped, the settle fires, and the render is the whole
// point of stopping. Under a touch rule it would not start until you let go.
//
// So it is MOVEMENT, not contact. A pointer that is moving is a gesture that
// is animating something, and that is exactly when the compositor is under
// pressure. A finger resting still needs nothing. A tap needs one frame and is
// over before a pause could have helped.
//
// WHAT IT DOES NOT COVER, stated rather than discovered later: a fling. The
// pointer is gone but the scroll physics animate on for up to a second, and
// nothing here sees that. [kCyclesActivityTail] covers the beginning of it and
// no more. Closing that would mean a signal from the scrolling widgets
// themselves, which is a much larger change than this is worth until a device
// says it is needed.
//
// ---------------------------------------------------------------------------
// AND IT TOUCHES NOTHING
// ---------------------------------------------------------------------------
//
// A global pointer route rather than a Listener in the tree. It sees every
// pointer event in the application without any widget knowing it exists, so
// this feature adds no wrapper to the app root, no parameter to a viewport,
// and nothing another milestone editing the ribbon or the panels can collide
// with.
import 'dart:async';

import 'package:flutter/gestures.dart';

/// How long after the last pointer movement the app is still treated as busy.
///
/// Long enough to bridge the gaps inside a drag — a finger moving across glass
/// does not deliver an event every frame — and short enough that letting go is
/// followed by a render rather than by a wait. It is also all the cover a
/// fling gets; see the note above.
const Duration kCyclesActivityTail = Duration(milliseconds: 220);

/// Whether the user is actively moving something on screen right now.
///
/// A process-wide fact with one listener list, in the same shape as
/// CyclesWarmup: several viewports may care and none of them owns it.
class CyclesActivity {
  CyclesActivity._();

  static final CyclesActivity instance = CyclesActivity._();

  bool _busy = false;
  Timer? _tail;
  bool _wired = false;
  final List<void Function()> _listeners = [];

  /// True while a pointer has moved within the last [kCyclesActivityTail].
  bool get busy => _busy;

  void addListener(void Function() fn) {
    _wire();
    _listeners.add(fn);
  }

  void removeListener(void Function() fn) => _listeners.remove(fn);

  /// Registered on the first listener rather than at startup, so a build with
  /// no renderer never installs a global route at all.
  ///
  /// Guarded: [GestureBinding.instance] throws if no binding has been
  /// initialised, which is true of a plain unit test that happens to reach
  /// this. Failing to observe pointers is a renderer that never pauses, which
  /// is exactly the behaviour before this milestone — not a crash.
  void _wire() {
    if (_wired) return;
    _wired = true;
    try {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
    } catch (_) {
      _wired = false;
    }
  }

  void _route(PointerEvent event) {
    // MOVE ONLY. See the header: contact is not the signal, motion is. Scroll
    // and pan events from a trackpad or a mouse wheel count for the same
    // reason a finger does — something on screen is animating.
    if (event is PointerMoveEvent ||
        event is PointerScrollEvent ||
        event is PointerPanZoomUpdateEvent) {
      _mark();
    }
  }

  void _mark() {
    _tail?.cancel();
    _tail = Timer(kCyclesActivityTail, () {
      _tail = null;
      _set(false);
    });
    _set(true);
  }

  void _set(bool now) {
    if (_busy == now) return;
    _busy = now;
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }

  /// Drive it by hand. Tests only — there is no pointer to move in one.
  void markMovedForTest() => _mark();

  /// Forget everything, including the tail timer. Tests only.
  void resetForTest() {
    _tail?.cancel();
    _tail = null;
    _busy = false;
    _listeners.clear();
  }
}
