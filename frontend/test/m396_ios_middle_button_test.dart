// M396 — #24: "when i have a external keyboard and mouse connected, middle
// mouse button doesnt work for pan or orbit with shift. it seems like middle
// mouse button isnt recognized on iOS, idk".
//
// It is recognised — as a press with no name. UIKit describes a pointer press
// with UIEventButtonMask, whose only members are primary and secondary, so a
// middle click reaches Flutter as a pointer whose `buttons` is 0. The device
// trace in the report shows sixteen such down/drag/up sequences among 158
// ordinary left drags that all report 1: the presses arrived, and the mask
// that would have identified them does not exist on that platform.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/mouse_nav.dart';

void main() {
  const mouse = PointerDeviceKind.mouse;

  group('everywhere', () {
    test('the middle button pans, and with shift orbits', () {
      expect(mouseDrag(mouse, kMiddleMouseButton, shift: false), MouseDrag.pan);
      expect(
          mouseDrag(mouse, kMiddleMouseButton, shift: true), MouseDrag.orbit);
    });

    test('left and right drags are left alone', () {
      for (final b in [kPrimaryMouseButton, kSecondaryMouseButton]) {
        expect(mouseDrag(mouse, b, shift: false), MouseDrag.none);
        expect(mouseDrag(mouse, b, shift: true), MouseDrag.none);
        expect(mouseDrag(mouse, b, shift: false, emptyMaskIsMiddle: true),
            MouseDrag.none,
            reason: 'a named button is never the nameless one');
      }
    });

    test('touch, stylus and trackpad have their own gestures', () {
      for (final k in [
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      ]) {
        expect(mouseDrag(k, kMiddleMouseButton, shift: false), MouseDrag.none);
        expect(mouseDrag(k, 0, shift: false, emptyMaskIsMiddle: true),
            MouseDrag.none);
      }
    });
  });

  group('iOS, where the mask is empty', () {
    test('a nameless mouse press is the middle button', () {
      expect(mouseDrag(mouse, 0, shift: false, emptyMaskIsMiddle: true),
          MouseDrag.pan);
      expect(mouseDrag(mouse, 0, shift: true, emptyMaskIsMiddle: true),
          MouseDrag.orbit);
    });

    test('and only there — elsewhere an empty mask is still nothing', () {
      expect(mouseDrag(mouse, 0, shift: false), MouseDrag.none);
      expect(isMiddleDrag(0, emptyMaskIsMiddle: false), isFalse);
      expect(isMiddleDrag(0, emptyMaskIsMiddle: true), isTrue);
    });

    test('a mask carrying the middle bit still works on either platform', () {
      expect(isMiddleDrag(kMiddleMouseButton, emptyMaskIsMiddle: false), isTrue);
      expect(isMiddleDrag(kMiddleMouseButton, emptyMaskIsMiddle: true), isTrue);
      // A chorded press (left held while the wheel is clicked) counts too.
      expect(
          isMiddleDrag(kPrimaryMouseButton | kMiddleMouseButton,
              emptyMaskIsMiddle: false),
          isTrue);
    });
  });
}
