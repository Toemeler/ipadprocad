// M206 — THE NUMBER PAD, AND WHERE IT POINTS.
//
// "When I change the number in this circular pattern window a really small
// number input field is used instead of the whole keyboard. But in every
// dimension input field the whole keyboard comes. Can you change this so this
// small number input field is used everywhere for dimensions and all other
// numbers too instead of the keyboard."
//
// "Also the number input field on circular pattern spawns a little bit too
// high — the arrow of it should be right under the number field."
//
// The two halves of one answer: the app draws its own pad now, and it draws it
// under the field it edits. What is testable on a host is the arithmetic —
// what a keystroke does to the text, and where the pad lands — so that is what
// is pinned here. See value_pad.dart for why we did not simply flip the
// keyboard-type flag.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/scrub_field.dart';
import 'package:prototype/widgets/value_pad.dart';

TextEditingValue v(String text, {int? base, int? extent}) => TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: base ?? text.length,
        extentOffset: extent ?? base ?? text.length,
      ),
    );

void main() {
  group('the field asks the system for no keyboard at all', () {
    test('kValueKeyboard is TextInputType.none', () {
      // The whole first report in one line. A SIGNED number type is what iOS
      // maps to the full QWERTY-with-punctuation keyboard; asking for nothing
      // is what stops any of that from being Apple's decision.
      expect(kValueKeyboard, TextInputType.none);
    });
  });

  group('applyValueKey: typing', () {
    test('a digit lands at the caret, not at the end', () {
      expect(applyValueKey(v('120', base: 1), PadKey.k5).text, '1520');
    });

    test('a digit replaces the selection', () {
      final r = applyValueKey(v('120', base: 0, extent: 3), PadKey.k7);
      expect(r.text, '7');
      expect(r.selection.baseOffset, 1);
    });

    test('the caret follows the digit', () {
      final r = applyValueKey(v('12', base: 2), PadKey.k3);
      expect(r.text, '123');
      expect(r.selection.baseOffset, 3);
    });

    test('a second decimal point is refused', () {
      expect(applyValueKey(v('1.5'), PadKey.dot).text, '1.5');
      expect(applyValueKey(v('15'), PadKey.dot).text, '15.');
    });

    test('a decimal point is allowed when the selection eats the old one', () {
      // "1.5" fully selected, then ".": the existing dot goes with the
      // selection, so the new one is the only one.
      expect(applyValueKey(v('1.5', base: 0, extent: 3), PadKey.dot).text, '.');
    });

    test('an unfocused field with no valid selection types at the end', () {
      const raw = TextEditingValue(text: '42'); // selection is invalid here
      expect(applyValueKey(raw, PadKey.k7).text, '427');
    });
  });

  group('applyValueKey: backspace', () {
    test('deletes the character before the caret', () {
      final r = applyValueKey(v('123', base: 3), PadKey.backspace);
      expect(r.text, '12');
      expect(r.selection.baseOffset, 2);
    });

    test('deletes the selection when there is one', () {
      final r = applyValueKey(v('1234', base: 1, extent: 3), PadKey.backspace);
      expect(r.text, '14');
      expect(r.selection.baseOffset, 1);
    });

    test('at the start of the text it does nothing', () {
      expect(applyValueKey(v('12', base: 0), PadKey.backspace).text, '12');
    });
  });

  group('applyValueKey: the minus is a SIGN, not a character', () {
    test('it toggles on', () {
      expect(applyValueKey(v('5'), PadKey.minus).text, '-5');
    });

    test('and off again', () {
      expect(applyValueKey(v('-5'), PadKey.minus).text, '5');
    });

    test('never lands in the middle of the number', () {
      // The whole reason it is a toggle: pressing it with the caret after the
      // "1" must not produce "1-2".
      expect(applyValueKey(v('12', base: 1), PadKey.minus).text, '-12');
    });

    test('the caret keeps its place relative to the digits', () {
      final r = applyValueKey(v('12', base: 1), PadKey.minus);
      expect(r.selection.baseOffset, 2, reason: 'still after the "1"');
      expect(applyValueKey(r, PadKey.minus).selection.baseOffset, 1);
    });
  });

  group('where the pad lands', () {
    const screen = Size(1600, 900);

    test('below the field, with the tail pointing at its centre', () {
      const field = Rect.fromLTWH(700, 300, 120, 28);
      final (origin, below) = ValuePadOverlay.place(field, screen);
      expect(below, isTrue);
      expect(origin.dy, greaterThan(field.bottom),
          reason: 'under the number, which is the whole of the second report');
      expect(origin.dx + ValuePad.width / 2, closeTo(field.center.dx, 0.5));
    });

    test('above it when there is no room below', () {
      const field = Rect.fromLTWH(700, 860, 120, 28);
      final (origin, below) = ValuePadOverlay.place(field, screen);
      expect(below, isFalse);
      expect(origin.dy + ValuePad.height + ValuePad.tail,
          lessThanOrEqualTo(field.top));
    });

    test('below anyway when there is room in neither direction', () {
      // A field at the very top of a short screen: flipping up would put the
      // pad off the screen, so it stays down and is simply clipped at worst.
      const field = Rect.fromLTWH(700, 4, 120, 28);
      final (_, below) = ValuePadOverlay.place(field, const Size(400, 200));
      expect(below, isTrue);
    });

    test('a field near the right edge does not push the pad off-screen', () {
      const field = Rect.fromLTWH(1560, 300, 36, 28);
      final (origin, _) = ValuePadOverlay.place(field, screen);
      expect(origin.dx + ValuePad.width, lessThanOrEqualTo(screen.width));
      expect(origin.dx, greaterThanOrEqualTo(0));
    });

    test('a field near the left edge does not push it off either', () {
      const field = Rect.fromLTWH(2, 300, 36, 28);
      final (origin, _) = ValuePadOverlay.place(field, screen);
      expect(origin.dx, greaterThanOrEqualTo(0));
    });
  });

  group('through a ScrubField: focus raises it, and its keys edit the field',
      () {
    testWidgets('it appears on focus, under the field, and types into it',
        (t) async {
      final app = AppState();
      final ctrl = TextEditingController(text: '8');
      final node = FocusNode();
      final commits = <String>[];
      await t.binding.setSurfaceSize(const Size(900, 700));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: ScrubField(
                app: app,
                controller: ctrl,
                onCommit: commits.add,
                child: TextField(
                  controller: ctrl,
                  focusNode: node,
                  keyboardType: kValueKeyboard,
                ),
              ),
            ),
          ),
        ),
      ));
      expect(find.byType(ValuePad), findsNothing, reason: 'not focused yet');

      node.requestFocus();
      await t.pumpAndSettle();
      expect(find.byType(ValuePad), findsOneWidget);

      // Under the field it edits — the second half of the report.
      final field = t.getRect(find.byType(TextField));
      final pad = t.getRect(find.byType(ValuePad));
      expect(pad.top, greaterThanOrEqualTo(field.bottom));
      expect(pad.center.dx, closeTo(field.center.dx, 1.0));

      // Typing goes through the same controller the dialog reads.
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      await t.tap(find.text('4'));
      await t.pumpAndSettle();
      expect(ctrl.text, '84');
      expect(commits.last, '84');

      // Losing focus takes it down again.
      node.unfocus();
      await t.pumpAndSettle();
      expect(find.byType(ValuePad), findsNothing);
      node.dispose();
      ctrl.dispose();
    });

    testWidgets('a field that opts out never raises one', (t) async {
      // The Parameters window's Equation cell: expression-first, so it keeps
      // the real keyboard and gets no pad.
      final app = AppState();
      final ctrl = TextEditingController(text: 'd0 + 5');
      final node = FocusNode();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: ScrubField(
                app: app,
                controller: ctrl,
                pad: false,
                child: TextField(controller: ctrl, focusNode: node),
              ),
            ),
          ),
        ),
      ));
      node.requestFocus();
      await t.pumpAndSettle();
      expect(find.byType(ValuePad), findsNothing);
      node.dispose();
      ctrl.dispose();
    });

    testWidgets('OK runs onDone — the Return key touch does not have',
        (t) async {
      final app = AppState();
      final ctrl = TextEditingController(text: '5');
      final node = FocusNode();
      var submitted = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: ScrubField(
                app: app,
                controller: ctrl,
                onDone: () => submitted++,
                child: TextField(controller: ctrl, focusNode: node),
              ),
            ),
          ),
        ),
      ));
      node.requestFocus();
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(submitted, 1);
      expect(find.byType(ValuePad), findsNothing, reason: 'OK closes it');
      node.dispose();
      ctrl.dispose();
    });
  });

  group('the pad itself', () {
    testWidgets('every digit, the point, the sign, delete and OK are there',
        (t) async {
      final pressed = <PadKey>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: ValuePad(onKey: pressed.add))),
      ));
      for (final d in '0123456789'.split('')) {
        expect(find.text(d), findsOneWidget, reason: d);
      }
      expect(find.text('.'), findsOneWidget);
      expect(find.text('±'), findsOneWidget);
      expect(find.text('⌫'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      await t.tap(find.text('7'));
      await t.tap(find.text('OK'));
      expect(pressed, [PadKey.k7, PadKey.done]);
    });

    testWidgets('an unsigned field gets a dead ± rather than a missing one',
        (t) async {
      // Removing the key would reflow the grid under a finger already on its
      // way to a digit.
      final pressed = <PadKey>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(child: ValuePad(onKey: pressed.add, signed: false))),
      ));
      expect(find.text('±'), findsOneWidget);
      await t.tap(find.text('±'));
      expect(pressed, isEmpty);
    });
  });
}
