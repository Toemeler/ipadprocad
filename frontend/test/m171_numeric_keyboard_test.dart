// M171 — value fields ask for the compact numeric pad on touch and Pencil.
//
// With a Magic Keyboard attached iOS shows no software keyboard at all, so
// this only ever matters for touch and Pencil — and there, a full QWERTY for
// typing "12" costs a third of the screen and buries the geometry being
// dimensioned.
//
// The split is deliberate and is what these tests pin: NUMBERS get the pad,
// FORMULAS keep the keyboard. The Parameters window is expression-first —
// names, functions, references to other parameters — and a numeric pad has no
// letters, so forcing one there would break the feature M41/M43 exist for.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/theme.dart';

void main() {
  group('M171 — the value keyboard', () {
    test('is numeric', () {
      expect(kValueKeyboard.index, TextInputType.number.index,
          reason: 'the compact pad, not a QWERTY');
    });

    test('is SIGNED — an offset can go the other way', () {
      // A work plane offset, a taper and an asymmetric extrude all take
      // negative numbers; a pad without a minus makes them untypeable.
      expect(kValueKeyboard.signed, isTrue);
    });

    test('has a DECIMAL separator — millimetres are not integers', () {
      expect(kValueKeyboard.decimal, isTrue);
    });

    test('it is one constant, so the fields cannot drift apart', () {
      // Five dialogs had grown four slightly different spellings of this.
      // Naming it is what stops a sixth.
      expect(identical(kValueKeyboard, kValueKeyboard), isTrue);
    });
  });
}
