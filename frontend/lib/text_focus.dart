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
///
/// TWO CHECKS, BECAUSE THE NODE'S OWNER IS NOT FIXED. `FocusNode.context` is
/// the context of whatever attached the node, and which element that is
/// depends on how the field is built: a widget that attaches its own node
/// (`FocusNode.attach` from its State) leaves `context.widget` as the field
/// itself, while one that hands the node to a `Focus` widget inside its own
/// build leaves the `Focus` there and the [EditableText] one or more levels
/// ABOVE it. Checking only the first — which is what this file did when it
/// was written — silently answers "nobody is typing" on the second shape,
/// and a guard that never fires is worse than no guard, because it reads
/// like the bug is fixed. Ask both ways.
bool get isTypingInTextField {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null || !ctx.mounted) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}
