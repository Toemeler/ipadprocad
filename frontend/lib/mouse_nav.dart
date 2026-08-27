// M283 — MOUSE NAVIGATION.
//
// Until now every navigation gesture in this app was written for a finger, a
// Pencil or a trackpad. A real mouse got what was left over, and it showed:
//
//   "scroll to zoom is not smooth its in steps when using the mouse wheel ...
//    shift and middle mouse click is orbit and only middle mouse click is
//    pan ... the mouse also seems to always make a step back when i let go.
//    and it should be smoothed"
//
// Both halves live here so the three viewports (part, assembly, sketch) answer
// a mouse the same way, and so the behaviour can be tested without a widget.
//
// The wheel's DIRECTION is deliberately not touched: it reads the system's own
// scroll direction setting, and inverting it here would fight the setting
// rather than honour it.
//
// This file holds no camera maths. It answers two questions — "how much zoom
// does this wheel event ask for, and how fast should it arrive" and "what does
// this drag do to the view" — and the viewports keep their own cameras.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';

/// Wheel travel, in logical pixels, that means one doubling (or halving) of
/// the view.
///
/// This is the whole of "not in steps". The old code zoomed a fixed 1.1x per
/// scroll EVENT and threw the delta away, so a wheel that reports one big
/// event per notch moved the view in visible jumps while a wheel that reports
/// many small ones flew. Zoom is now proportional to how far the wheel
/// actually turned, whichever kind of wheel it is.
///
/// The scale: a classic 120-px notch is a bit over a third of a doubling
/// (0.77x), and the small momentum deltas a pointer device sends instead
/// accumulate to the same place. Larger here means a slower wheel.
const double kWheelPixelsPerDoubling = 320.0;

/// The most any single wheel event may add to the pending zoom.
///
/// A flick of a free-spinning wheel can deliver several thousand pixels in one
/// event. Without a ceiling that is a jump from the model to a dot.
const double kWheelMaxDoublings = 3.0;

/// Time for the pending zoom to halve while it glides in.
///
/// This is what turns "in steps" into a movement: a notch is not applied at
/// once, it is paid out over the next few frames. 45 ms is short enough that
/// the wheel still feels connected to the hand and long enough that the
/// individual notches of a fast scroll melt into one continuous zoom.
const double kWheelGlideHalfLife = 0.045;

/// Below this much pending zoom the glide lands exactly instead of chasing an
/// asymptote forever.
const double kWheelSettle = 1e-3;

/// The zoom, in doublings, that one wheel event asks for. Positive zooms IN.
///
/// Scrolling DOWN zooms out, which is the meaning the app has always had and
/// the one the system's scroll-direction setting is expressed against. Only
/// the AMOUNT is new: it is proportional to the travel instead of a fixed step
/// per event.
double wheelDoublings(double scrollDy) {
  if (!scrollDy.isFinite) return 0;
  return -scrollDy / kWheelPixelsPerDoubling;
}

/// A wheel zoom that arrives over several frames instead of in one jump.
///
/// The viewport adds what the wheel asked for with [add] and then, once per
/// frame, asks [takeHalfHeightFactor] for the slice of it that belongs to this
/// frame. Events that land mid-glide simply add to what is still owed, so
/// spinning the wheel accelerates the zoom rather than restarting it.
class WheelZoom {
  double _owed = 0; // doublings still to be paid out; + zooms in
  Offset _focus = Offset.zero;

  /// Where the zoom is anchored — whatever the viewport put in. The 3D
  /// viewports keep a point in view pixels; the sketch keeps a world point,
  /// which stays put on its own as the camera moves.
  Offset get focus => _focus;

  /// True while there is zoom left to pay out.
  bool get active => _owed != 0;

  /// The zoom still owed, in doublings. Positive zooms in.
  double get owed => _owed;

  void add(double doublings, Offset focus) {
    if (!doublings.isFinite || doublings == 0) return;
    _owed = (_owed + doublings)
        .clamp(-kWheelMaxDoublings, kWheelMaxDoublings)
        .toDouble();
    _focus = focus;
  }

  /// Drop whatever is still owed — a drag or a view command has taken over and
  /// the leftover of an old scroll must not keep pulling the camera.
  void cancel() => _owed = 0;

  /// The factor to multiply a camera's half-height by for a frame of [dt]
  /// seconds. Less than 1 zooms in; exactly 1 means there is nothing to do.
  double takeHalfHeightFactor(double dt) {
    if (_owed == 0 || !dt.isFinite || dt <= 0) return 1;
    // Clamped: a frame that arrives after a stall (a kernel call, a file read)
    // would otherwise pay out the whole glide at once, which is the jump this
    // exists to remove.
    final step = math.min(dt, 0.05);
    final decay = math.pow(0.5, step / kWheelGlideHalfLife).toDouble();
    var take = _owed * (1 - decay);
    if ((_owed - take).abs() < kWheelSettle) take = _owed;
    _owed -= take;
    return math.pow(0.5, take).toDouble();
  }

  /// The same slice as [takeHalfHeightFactor], for a camera that stores a
  /// zoom SCALE rather than a half-height: greater than 1 zooms in.
  double takeZoomFactor(double dt) => 1 / takeHalfHeightFactor(dt);
}

/// What a mouse drag does to the view.
enum MouseDrag {
  /// Nothing — the drag belongs to whatever the viewport does with it (a pick,
  /// a box select, a grip, a component).
  none,

  /// Slide the view.
  pan,

  /// Turn the model. The sketch canvas has nothing to turn and pans instead.
  orbit,
}

/// What this pointer state means to the view, for a mouse.
///
/// Inventor's binding, and the one asked for: the middle button pans, and
/// shift with it orbits. That is the exact inverse of what this app did, where
/// the middle button orbited and shift+middle panned.
///
/// [buttons] is the event's button mask and [shift] the keyboard's shift state
/// at the moment of the press. Touch, Pencil and trackpad always get
/// [MouseDrag.none] — they have their own two-finger gestures and no middle
/// button — and so does a plain left or right drag, which stays a pick, a box
/// select or a grip exactly as before.
MouseDrag mouseDrag(PointerDeviceKind kind, int buttons, {required bool shift}) {
  if (kind != PointerDeviceKind.mouse) return MouseDrag.none;
  if (buttons & kMiddleMouseButton == 0) return MouseDrag.none;
  return shift ? MouseDrag.orbit : MouseDrag.pan;
}
