// Prototype — Windows only: the whole UI at 75% of its iPad-authored size.
//
// Every size in this app — a ribbon icon, a browser row, `ts(12.5, ...)` —
// is a constant tuned against the iPad mock this was built from (see
// theme.dart, RibbonMetrics, NativeModelBrowser's 264/56/46). A mouse and a
// 27" monitor read those exact numbers as oversized touch targets, which is
// what "the UI on Windows seems too big for desktop" is: not a bug in any
// one widget, but the same iPad-shaped constant appearing in hundreds of
// them. Rescaling each one is a hundred small changes with a hundred chances
// to miss one and a hundred more to unstick it from the next iPad tweak;
// scaling the RENDERED RESULT is one change that cannot drift from the
// widgets it covers, because it never looks inside them.
//
// HOW: give the subtree a canvas 1/0.75 BIGGER than the real window
// (OverflowBox — a plain SizedBox would be clamped straight back down by the
// real constraints), let it lay out exactly as it does everywhere else, and
// paint that oversized result scaled down to fit the real window exactly
// (Transform.scale). MediaQuery.size is corrected to match the virtual
// canvas too, or anything that reads screen size directly (Ribbon's flyout
// placement, a dialog's max-width clamp) would place itself against the
// real, smaller window while everything drawn around it sits in the bigger
// one. Transform's hit-testing is written to invert exactly this transform,
// so a tap lands on whatever is drawn under the cursor, scaled or not.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// How much smaller than the iPad-authored sizes the Windows build renders.
/// 0.75 is what was asked for; nothing else in this file assumes that exact
/// number, so a different one is a one-line change.
const double kWindowsUiScale = 0.75;

bool get _shouldScale => !kIsWeb && Platform.isWindows;

/// Wraps [child] — meant for `MaterialApp.builder` — so it renders at
/// [kWindowsUiScale] on Windows and passes through unchanged everywhere
/// else.
class WindowsUiScale extends StatelessWidget {
  final Widget? child;
  const WindowsUiScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    if (child == null) return const SizedBox.shrink();
    if (!_shouldScale) return child;

    final mq = MediaQuery.of(context);
    // The canvas the child gets to lay out in — bigger than the real window
    // by exactly the factor the paint step shrinks it back by.
    final virtual = mq.size / kWindowsUiScale;

    return MediaQuery(
      data: mq.copyWith(
        size: virtual,
        padding: mq.padding / kWindowsUiScale,
        viewPadding: mq.viewPadding / kWindowsUiScale,
        viewInsets: mq.viewInsets / kWindowsUiScale,
        // A canvas 1/0.75 wider at 0.75x the density is the SAME number of
        // physical pixels, which is what anything sizing a raster off this
        // needs (cycles_layer.dart sizes the path-traced image by it). Left
        // at the real ratio it would allocate 1.78x the pixels the window
        // can show and scale them back down.
        devicePixelRatio: mq.devicePixelRatio * kWindowsUiScale,
      ),
      child: Transform.scale(
        scale: kWindowsUiScale,
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: virtual.width,
          maxHeight: virtual.height,
          child: SizedBox(
            width: virtual.width,
            height: virtual.height,
            child: child,
          ),
        ),
      ),
    );
  }
}
