/// M205 — the gesture contract for the native chrome.
///
/// THE REPORT
/// ----------
/// "A few times clicks on native swift liquidglass elements like the debug
/// button didn't work by clicking on the trackpad." — "the buttons seem to get
/// bigger when i click but somehow it doesnt count as a click."
///
/// "Bigger, but not a click" is UIKit describing the failure precisely. A
/// UIButton grows and lights on `touchesBegan`; it fires on `touchesEnded`
/// inside its bounds. A button that highlights and then goes dark without
/// acting has been sent `touchesCancelled` in between — the press was seen,
/// and then taken away from it.
///
/// WHO TAKES IT
/// -----------
/// A `UiKitView` is wrapped by the engine in a touch-intercepting view that
/// holds every touch back while the FLUTTER side decides whether it wants the
/// gesture. Only if Flutter's arena hands the sequence to the platform view do
/// the touches reach UIKit; if anything on the Flutter side claims it first,
/// what UIKit gets instead is a cancel. By default a platform view enters that
/// arena as a polite participant and waits for everyone else, which means the
/// outcome depends on what else happens to be listening over the bar, on
/// timing, and — as this session showed — on the OS build.
///
/// A toolbar is not a thing to negotiate over. A touch that lands on the quick
/// tools, the tab bar or the model browser belongs to UIKit and to nothing
/// else, and [eagerNativeTouches] says so: the platform view claims the
/// sequence the instant it starts, the arena is resolved before any competitor
/// can enter, and the touches are delivered natively without the delay or the
/// cancel. It is also what stops those pointers from sitting half-alive in the
/// Flutter framework — the other half of the same session's report, where a
/// pointer went down on a native view and Flutter never saw it come up.
///
/// The native side keeps its own belt-and-braces on top of this (see
/// `GlassButton` in the Swift sources), because two independent guards is what
/// "a double proof fix" means.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Hands every touch that starts inside a platform view straight to UIKit.
///
/// Pass as `UiKitView.gestureRecognizers` for native chrome the user operates
/// directly. Do NOT pass it for a view that is only a backdrop: a claimed
/// touch never reaches the Flutter widgets around it.
Set<Factory<OneSequenceGestureRecognizer>> eagerNativeTouches() =>
    <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    };
