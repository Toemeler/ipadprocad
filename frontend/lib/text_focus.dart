// Prototype — "is a text field the one taking this keystroke right now."
//
// M371/M... — a couple of viewports each hook HardwareKeyboard directly for
// single-letter tool shortcuts (M arms Measure) and for Ctrl+Z/Y/C/X/V. That
// hook fires on every physical key press for the whole app, independent of
// Flutter's own focus tree — it is how Undo reaches a key event even while
// no particular widget asked for one. The cost of that reach is that it does
// not know the difference between "the user is not typing anywhere" and "the
// user is naming a document, or filing a bug report, and one of its letters
// happens to be M": bug #17 is a report whose own text box lost every M its
// author typed, to Measure toggling on and off underneath it.
//
// The fix is the same one word processors use for their own single-key
// tools (Photoshop's B, Figma's R): ask what is focused before treating a
// letter as a shortcut, and stand down while it is a text field's job.
import 'package:flutter/widgets.dart';

/// True while an [EditableText] — a `TextField`, a `TextFormField`, this
/// app's own `ScrubField` (it wraps one) — holds the keyboard focus.
///
/// A single-letter or Ctrl+letter global shortcut has to check this before
/// acting: the alternative is a text field that silently loses whichever
/// letters its own app has bound to a tool.
bool get isTypingInTextField {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null && ctx.widget is EditableText;
}
