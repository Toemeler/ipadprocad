// M393 — #18, "When installed on iphone it should be Portrait default".
//
// The app locked itself to landscape unconditionally, so an iPhone held
// upright was turned onto its side before the first frame. The lock now asks
// what it is running on first. The decision is a pure function of the
// platform and the view's size so that both families can be checked here
// without either device.
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/device_class.dart';

const portrait = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];
const landscape = <DeviceOrientation>[
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

void main() {
  test('every iPhone is a phone and every iPad is not', () {
    // Logical points, portrait-up, from Apple's own display specs. The gap
    // between the two families is what the 600-point threshold sits in.
    const phones = <String, Size>{
      'SE (3rd gen)': Size(375, 667),
      '13 mini': Size(375, 812),
      '16': Size(393, 852),
      '16 Pro Max': Size(440, 956),
    };
    const pads = <String, Size>{
      'mini (6th gen)': Size(744, 1133),
      '10th gen': Size(820, 1180),
      'Pro 11"': Size(834, 1210),
      'Pro 13"': Size(1032, 1376),
    };
    for (final e in phones.entries) {
      expect(isPhoneSize(e.value), isTrue, reason: 'iPhone ${e.key}');
      // Held sideways it is still a phone — shortestSide, not width.
      expect(isPhoneSize(e.value.flipped), isTrue, reason: 'iPhone ${e.key}');
    }
    for (final e in pads.entries) {
      expect(isPhoneSize(e.value), isFalse, reason: 'iPad ${e.key}');
      expect(isPhoneSize(e.value.flipped), isFalse, reason: 'iPad ${e.key}');
    }
  });

  test('an iPhone gets portrait, an iPad keeps landscape', () {
    expect(
        preferredOrientations(
            platform: TargetPlatform.iOS, logical: const Size(393, 852)),
        portrait);
    expect(
        preferredOrientations(
            platform: TargetPlatform.iOS, logical: const Size(1210, 834)),
        landscape);
  });

  test('a phone-sized window off iOS is not an iPhone', () {
    // A narrow desktop window is not a reason to rotate a desktop, which
    // cannot rotate; only iOS reads this list at all.
    for (final p in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.android,
    ]) {
      expect(preferredOrientations(platform: p, logical: const Size(400, 800)),
          landscape,
          reason: '$p');
    }
  });

  test('an iPad in Split View is still an iPad', () {
    // M393 follow-up — the measurement is the DISPLAY, not the window, and
    // this is the case that makes the difference. An 11" iPad running two
    // apps side by side hands each of them a window narrower than any iPhone;
    // a third of one is about 320 points. Sizing off that would stand a
    // full-size iPad on end because somebody dragged a divider.
    //
    // `SystemChrome.setPreferredOrientations` requires the display for exactly
    // this reason ("Applications that make decisions about whether to lock
    // orientation based on the screen size must use the `display` property of
    // the current FlutterView"), and Android's letterboxing is the second
    // case: an app that locks its orientation is letterboxed, and the
    // letterboxed size then reports back as narrow — a measurement the lock
    // itself caused.
    const splitViewWindow = Size(320, 1210);
    const theDisplay = Size(834, 1210);

    // What a window measurement says, and why it is the wrong question:
    expect(isPhoneSize(splitViewWindow), isTrue);
    // What _viewSize now asks:
    expect(isPhoneSize(theDisplay), isFalse);
    expect(
        preferredOrientations(
            platform: TargetPlatform.iOS, logical: theDisplay),
        landscape);
  });

  test('an unmeasured view is not mistaken for a phone', () {
    // Size.zero is an engine that has not sized the view yet. Reading it as
    // "narrow, therefore a phone" would stand an iPad on end on a slow
    // launch — the failure this app would actually ship.
    expect(isPhoneSize(Size.zero), isFalse);
    expect(
        preferredOrientations(platform: TargetPlatform.iOS, logical: Size.zero),
        landscape);
  });
}
