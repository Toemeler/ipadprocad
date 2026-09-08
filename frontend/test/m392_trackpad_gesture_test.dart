// M392 — #21, "pinch zooming on windows laptop with trackpad is fucked up and
// rotates the modell somehow".
//
// A trackpad pinch is reported as ONE PointerPanZoomUpdate stream carrying a
// cumulative scale AND a cumulative pan, and the fingers' centroid always
// drifts a little as they close — no human pinches perfectly symmetrically.
// Both viewports used to act on both halves of every event, so every pinch
// orbited the model while it zoomed it. The fix is to let a gesture mean one
// thing: whichever threshold it crosses first decides, and the decision holds
// until the fingers come up.
//
// The decision is a pure function so that it can be pinned here; the wiring in
// viewport3d.dart / viewport_assembly.dart is three lines around it.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/mouse_nav.dart';

void main() {
  const undecided = TrackpadGesture.undecided;

  test('a gesture that has barely moved is still undecided', () {
    // The first event or two of any gesture: some scale noise, a point or two
    // of travel. Answering either way here is what picks the wrong one.
    expect(trackpadGesture(undecided, scale: 1, pan: Offset.zero), undecided);
    expect(trackpadGesture(undecided, scale: 1.01, pan: const Offset(2, 1)),
        undecided);
  });

  test('five percent of scale is a pinch', () {
    expect(trackpadGesture(undecided, scale: 1.05, pan: Offset.zero),
        TrackpadGesture.zoom);
    expect(trackpadGesture(undecided, scale: 0.95, pan: Offset.zero),
        TrackpadGesture.zoom);
  });

  test('eight points of travel is a slide', () {
    expect(trackpadGesture(undecided, scale: 1, pan: const Offset(8, 0)),
        TrackpadGesture.drag);
    expect(trackpadGesture(undecided, scale: 1, pan: const Offset(0, -20)),
        TrackpadGesture.drag);
  });

  test('a pinch that has also drifted sideways is a pinch', () {
    // THE BUG, in one line: this event says "zoomed 12%, and wandered 30
    // points doing it", and the old code obeyed both.
    expect(
        trackpadGesture(undecided, scale: 1.12, pan: const Offset(24, 18)),
        TrackpadGesture.zoom);
  });

  test('a decision holds for the rest of the gesture', () {
    // A slide whose fingers splay a little later must not turn into a zoom
    // halfway through, and a pinch must not start orbiting once its centroid
    // has drifted past the drag slop — which is the frame the model jumped on.
    expect(
        trackpadGesture(TrackpadGesture.drag,
            scale: 1.4, pan: const Offset(60, 60)),
        TrackpadGesture.drag);
    expect(
        trackpadGesture(TrackpadGesture.zoom,
            scale: 1.4, pan: const Offset(60, 60)),
        TrackpadGesture.zoom);
  });

  test('scale of zero is ignored, not read as a 100% pinch', () {
    // Some platforms report scale 0 on the first update. Reading it literally
    // makes `(scale - 1).abs()` a full 1.0 and starts every gesture as a zoom.
    expect(trackpadGesture(undecided, scale: 0, pan: Offset.zero), undecided);
    expect(trackpadGesture(undecided, scale: 0, pan: const Offset(9, 0)),
        TrackpadGesture.drag);
  });

  test('a slow asymmetric pinch is a pinch, not a drag', () {
    // M398 — the corner the thresholds decide, and the one the report lives
    // in. A pinch whose fingers close unevenly drags its centroid while it
    // grows; whichever threshold it crosses FIRST IN TIME wins, so the two
    // numbers are what say whether it is called a zoom or an orbit. Walked
    // here as a real gesture rather than asserted at one point.
    var g = TrackpadGesture.undecided;
    for (var step = 1; step <= 12; step++) {
      // 0.5% of scale and 1.2 points of drift per event: a deliberate but
      // slow pinch on a trackpad that reports generously.
      g = trackpadGesture(g,
          scale: 1 + 0.005 * step, pan: Offset(1.2 * step, 0));
      if (g != TrackpadGesture.undecided) break;
    }
    expect(g, TrackpadGesture.zoom,
        reason: 'at five percent the drift reached eight points first and '
            'this came back a drag — the model spinning under a pinch, which '
            'is the bug #21 reported');
  });

  test('a two-finger slide is still a drag, and still starts promptly', () {
    // The mirror case, and the reason the drag slop was left alone: eight
    // points is what a finger gets everywhere else in the app, and an orbit
    // that starts late is felt on every single use.
    var g = TrackpadGesture.undecided;
    var events = 0;
    for (var step = 1; step <= 12; step++) {
      events = step;
      // A slide carries a little scale noise; it must not read as a pinch.
      g = trackpadGesture(g, scale: 1 + 0.001 * step, pan: Offset(0, 3.0 * step));
      if (g != TrackpadGesture.undecided) break;
    }
    expect(g, TrackpadGesture.drag);
    expect(events, lessThanOrEqualTo(3), reason: 'an orbit must not feel sticky');
  });
}
