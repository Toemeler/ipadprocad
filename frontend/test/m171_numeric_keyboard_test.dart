// M171 — value fields must never raise a full keyboard.
//
// With a Magic Keyboard attached iOS shows no software keyboard at all, so
// this only ever matters for touch and Pencil — and there, a full QWERTY for
// typing "12" costs a third of the screen and buries the geometry being
// dimensioned.
//
// M206 CHANGED THE ANSWER, NOT THE RULE. M171 asked for
// `numberWithOptions(signed: true, decimal: true)` and these tests pinned that
// spelling. The spelling was wrong: iOS maps a SIGNED number type to
// `UIKeyboardTypeNumbersAndPunctuation`, which is the full keyboard — so the
// constant asked for precisely what M171 existed to prevent, and it was
// reported from the device as "in every dimension input field the whole
// keyboard comes". The app draws its own pad now and asks the system for
// nothing at all.
//
// The split M171 cared about is unchanged and is still pinned below: NUMBERS
// get the pad, FORMULAS keep the keyboard. The Parameters window is
// expression-first — names, functions, references to other parameters — and a
// pad has no letters, so forcing one there would break the feature M41/M43
// exist for.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/value_pad.dart';

void main() {
  group('M171/M206 — the value keyboard', () {
    test('raises nothing: the app brings its own pad', () {
      expect(kValueKeyboard, TextInputType.none);
    });

    test('is NOT one of the numeric keyboards any more', () {
      // The whole failure this replaces. Any `TextInputType.number` variant
      // hands the decision back to iOS, and the SIGNED one — which is what a
      // negative offset needs — is the full keyboard on that platform.
      expect(kValueKeyboard.index, isNot(TextInputType.number.index));
      expect(kValueKeyboard.index, isNot(TextInputType.text.index));
    });

    test('the minus M171 wanted is on the pad, not on the keyboard', () {
      // A work plane offset, a taper and an asymmetric extrude all take
      // negative numbers. That requirement did not go away; it moved to a key
      // we draw, where it toggles the sign instead of typing a character.
      expect(PadKey.values, contains(PadKey.minus));
      expect(applyValueKey(const TextEditingValue(text: '5'), PadKey.minus).text,
          '-5');
    });

    test('so is the decimal separator — millimetres are not integers', () {
      expect(PadKey.values, contains(PadKey.dot));
      expect(applyValueKey(const TextEditingValue(text: '15'), PadKey.dot).text,
          '15.');
    });

    test('it is one constant, so the fields cannot drift apart', () {
      // Five dialogs had grown four slightly different spellings of this.
      // Naming it is what stops a sixth — and what made M206 a one-line change
      // instead of a hunt.
      expect(identical(kValueKeyboard, kValueKeyboard), isTrue);
    });
  });
}
