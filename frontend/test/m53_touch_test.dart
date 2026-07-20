// M53 — touch input logic. Pins the Procreate tap classifier (two fingers =
// undo, three = redo) and the finger slop scaling. Pure logic, no widgets:
// the classifier is fed synthetic pointer streams with an injected clock.

import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/touch.dart';

void main() {
  test('touchSlop widens fingers only', () {
    expect(touchSlop(PointerDeviceKind.touch, 12), closeTo(21.6, 1e-9));
    expect(touchSlop(PointerDeviceKind.stylus, 12), 12);
    expect(touchSlop(PointerDeviceKind.mouse, 10), 10);
  });

  test('clean two-finger tap fires 2, three-finger tap fires 3', () {
    var t = 0;
    final m = MultiFingerTap(clock: () => t);
    m.down(1, const Offset(100, 100));
    t = 30;
    m.down(2, const Offset(160, 100));
    t = 120;
    expect(m.up(1, const Offset(101, 101)), 0, reason: 'one still down');
    expect(m.up(2, const Offset(161, 99)), 2);

    // and a fresh session with three fingers
    t = 1000;
    m.down(1, const Offset(100, 100));
    m.down(2, const Offset(160, 100));
    t = 1040;
    m.down(3, const Offset(220, 100));
    t = 1200;
    m.up(1, const Offset(100, 100));
    m.up(2, const Offset(160, 100));
    expect(m.up(3, const Offset(220, 100)), 3);
  });

  test('movement is a pan/pinch, never a tap', () {
    var t = 0;
    final m = MultiFingerTap(clock: () => t);
    m.down(1, const Offset(0, 0));
    m.down(2, const Offset(80, 0));
    m.move(1, const Offset(40, 0)); // > moveSlopPx
    t = 100;
    m.up(1, const Offset(40, 0));
    expect(m.up(2, const Offset(80, 0)), 0);
  });

  test('too slow is not a tap', () {
    var t = 0;
    final m = MultiFingerTap(clock: () => t);
    m.down(1, const Offset(0, 0));
    m.down(2, const Offset(80, 0));
    t = MultiFingerTap.maxDurationMs + 50;
    m.up(1, const Offset(0, 0));
    expect(m.up(2, const Offset(80, 0)), 0);
  });

  test('stylus activity poisons the session (resting palm never undoes)', () {
    var t = 0;
    final m = MultiFingerTap(clock: () => t);
    m.down(1, const Offset(0, 0));
    m.down(2, const Offset(80, 0));
    m.nonTouchActivity(); // Pencil touched down mid-session
    t = 100;
    m.up(1, const Offset(0, 0));
    expect(m.up(2, const Offset(80, 0)), 0);

    // ...and the NEXT session is clean again
    t = 500;
    m.down(1, const Offset(0, 0));
    m.down(2, const Offset(80, 0));
    t = 600;
    m.up(1, const Offset(0, 0));
    expect(m.up(2, const Offset(80, 0)), 2);
  });

  test('one finger and four fingers fire nothing', () {
    var t = 0;
    final m = MultiFingerTap(clock: () => t);
    m.down(1, const Offset(0, 0));
    t = 80;
    expect(m.up(1, const Offset(0, 0)), 0);

    t = 500;
    for (var i = 1; i <= 4; i++) {
      m.down(i, Offset(i * 60.0, 0));
    }
    t = 620;
    for (var i = 1; i <= 3; i++) {
      expect(m.up(i, Offset(i * 60.0, 0)), 0);
    }
    expect(m.up(4, const Offset(240, 0)), 0, reason: 'maxCount was 4');
  });

  test('a cancelled pointer poisons only its own session', () {
    var t = 0;
    final m = MultiFingerTap(clock: () => t);
    m.down(1, const Offset(0, 0));
    m.down(2, const Offset(80, 0));
    m.cancel(1);
    t = 90;
    expect(m.up(2, const Offset(80, 0)), 0);

    t = 400;
    m.down(1, const Offset(0, 0));
    m.down(2, const Offset(80, 0));
    t = 480;
    m.up(2, const Offset(80, 0));
    expect(m.up(1, const Offset(0, 0)), 2);
  });
}
