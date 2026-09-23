// Corners on the Linux and Windows builds.
//
// The iPad's radii are fitted to UIKit's material — a Liquid Glass surface
// wants a generous, continuous corner. The Linux and Windows builds do not
// draw that material (see LiquidGlassProgram.isAvailable) and sit among
// desktop windows whose corners are tighter, so there every radius is drawn a
// little smaller. One factor, applied where a corner is drawn, so the whole
// app shrinks together and nothing drifts.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// How much of the iPad's radius a Linux or Windows corner keeps.
const double kDesktopRadiusScale = 0.8;

/// Forces the desktop corners on or off. Tests only.
@visibleForTesting
bool? debugDesktopCornersOverride;

/// True on a Linux or Windows build.
///
/// Not under `flutter test`: the suite runs on a Linux host and pins the iPad
/// geometry, which is what the other platforms still draw.
bool get desktopCorners => debugDesktopCornersOverride ?? _desktopCorners;

final bool _desktopCorners = _detect();

bool _detect() {
  if (kIsWeb) return false;
  try {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isLinux || Platform.isWindows;
  } catch (_) {
    return false;
  }
}

/// [radius] as this platform draws it.
double desktopRadius(double radius) =>
    desktopCorners ? radius * kDesktopRadiusScale : radius;

/// The dialog layer's corner on Linux and Windows: Windows 11's two radii,
/// 8 for a panel or dialog and 4 for a card, button or field.
double desktopDialogRadius(double radius) {
  if (!desktopCorners || radius <= 0) return radius;
  if (radius >= 14) return 8;
  return radius < 4 ? radius : 4;
}
