// M388 — bug #17: a global shortcut must stand down while a text field has
// the keyboard.
//
// The fix in viewport3d.dart / viewport_assembly.dart is one line each, and
// all of it rests on `isTypingInTextField` answering truthfully. That answer
// is a claim about a framework internal — WHICH element owns the focus node
// a TextField is focused through — and a guard that quietly always says "no
// one is typing" is worse than no guard at all: the bug stays, and the fix
// reads like it is in place. So this tests the claim itself rather than the
// two callers, which are `if (guard) return false;` and nothing else.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/text_focus.dart';

void main() {
  testWidgets('a focused TextField is seen as typing', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(focusNode: node)),
    ));

    expect(isTypingInTextField, isFalse,
        reason: 'nothing has asked for the keyboard yet');

    node.requestFocus();
    await t.pump();
    expect(isTypingInTextField, isTrue,
        reason: 'the field has it — every letter belongs to the text');

    node.unfocus();
    await t.pump();
    expect(isTypingInTextField, isFalse,
        reason: 'and the shortcuts come back when it lets go');
  });

  testWidgets('a focused button is not typing', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextButton(focusNode: node, onPressed: () {}, child: const Text('x')),
      ),
    ));

    node.requestFocus();
    await t.pump();
    expect(isTypingInTextField, isFalse,
        reason: 'focus is not the question; whether it is TEXT focus is');
  });
}
