// M393 — #18: "When installed on iphone it should be Portrait default".
//
// This app has locked itself to landscape since the first commit, because it
// was written for one machine: an iPad, held sideways, with a ribbon across
// the top and a model browser down the side. On an iPhone that lock is simply
// wrong — a phone held upright is turned onto its side by the app before the
// first frame, and there is no way to hold it that stops that happening.
//
// So the lock still exists, it just asks WHICH device first. An iPhone gets
// portrait, everything else keeps the landscape it has always had.
//
// WHY A SIZE AND NOT A DEVICE NAME. Flutter has no "is this a phone" — there
// is no UIUserInterfaceIdiom in the framework, and reading a model string
// ("iPhone17,2") means keeping a list of hardware that is out of date the
// week Apple ships anything. The screen is the honest question anyway, and
// the two families do not overlap or come close to it: the widest iPhone is
// 440 points across (16 Pro Max), the narrowest iPad 744 (mini). Six hundred
// sits in an empty three-hundred-point gap.
//
// The size asked for is the DISPLAY's, not the window's, which the framework
// requires rather than merely suggests — see [_viewSize]. A window is not a
// device: an iPad in Split View is narrower than any phone, and it must not
// be stood on end because somebody dragged a divider.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Below this many logical points across, a screen is a phone's.
const double kPhoneShortestSide = 600;

/// True for a phone-shaped screen. A zero size is NOT a phone — it is an
/// engine that has not measured the view yet, and guessing there would lock
/// the iPad to portrait on a slow launch.
bool isPhoneSize(Size logical) =>
    logical.shortestSide > 0 && logical.shortestSide < kPhoneShortestSide;

/// The orientations to hand [SystemChrome.setPreferredOrientations].
///
/// Deliberately a LOCK on both branches rather than a preference: iOS reads
/// this list as the set it is allowed to rotate into, in no particular order,
/// so "portrait by default, landscape if you turn it" is not something the
/// platform can express. The iPad has been locked for its whole life and the
/// iPhone is locked the other way for the same reason — the layout is built
/// for one shape at a time.
List<DeviceOrientation> preferredOrientations({
  required TargetPlatform platform,
  required Size logical,
}) {
  if (platform == TargetPlatform.iOS && isPhoneSize(logical)) {
    return const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      // Ignored by every iPhone without a home button, and harmless on the
      // ones that have one; listed so the app does not fight a device that
      // does support it.
      DeviceOrientation.portraitDown,
    ];
  }
  return const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
}

/// The DISPLAY this app is on, in logical points, or null before the engine
/// has measured it.
///
/// THE DISPLAY AND NOT THE WINDOW, which is the framework's own instruction
/// rather than a preference. `SystemChrome.setPreferredOrientations` says it
/// in as many words:
///
///   "Applications that make decisions about whether to lock orientation
///    based on the screen size must use the `display` property of the current
///    [FlutterView]."
///
/// — and the worked example beside it divides `display.size` by
/// `display.devicePixelRatio` against a 600-point breakpoint, which is this
/// function. Two ways the window lies about the device:
///
///   * an iPad in Split View or Slide Over hands the app a window narrower
///     than any phone. A third of an 11" iPad is about 320 points, so a
///     window measurement calls a full-size iPad a phone because somebody
///     dragged a divider;
///   * Android letterboxes an app that locks its orientation, and the
///     framework notes that `MediaQueryData.size` then reports the
///     LETTERBOXED size — a measurement this decision itself caused.
///
/// The display moves for neither.
Size? _viewSize() {
  final view = ui.PlatformDispatcher.instance.implicitView;
  if (view == null) return null;
  try {
    final display = view.display;
    final dpr = display.devicePixelRatio;
    if (dpr <= 0) return null;
    final size = display.size / dpr;
    return size.isEmpty ? null : size;
  } catch (_) {
    // `display` throws for a view not attached to one. Unmeasured, which is
    // what null means here — the caller waits a frame and asks again.
    return null;
  }
}

/// M405 — is this an iPhone?
///
/// The same question [preferredOrientations] answers to decide the lock,
/// asked of the same DISPLAY, and given its own name because a second caller
/// now needs it: the ribbon retracts by default here and nowhere else (#38).
///
/// False before the engine has measured the display, which is the
/// conservative answer — it means an iPad's ribbon is never retracted by a
/// measurement that had not arrived yet, and a phone gets its default on the
/// first build after the view exists.
bool isPhoneDevice() {
  if (defaultTargetPlatform != TargetPlatform.iOS) return false;
  final size = _viewSize();
  return size != null && isPhoneSize(size);
}

bool _retried = false;

/// Applies [preferredOrientations] for whatever this device turns out to be.
///
/// Called from `main()`, where the engine has usually — but not always —
/// already sized the view. When it has not, this waits one frame and asks
/// again, once; a second miss falls through to the landscape default rather
/// than spinning a callback per frame forever.
Future<void> applyPreferredOrientations() {
  final size = _viewSize();
  if (size == null && !_retried) {
    _retried = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => applyPreferredOrientations());
    return Future<void>.value();
  }
  return SystemChrome.setPreferredOrientations(preferredOrientations(
    platform: defaultTargetPlatform,
    logical: size ?? Size.zero,
  ));
}
