// Prototype — text prompts and confirmations.
//
// NATIVE FIRST, Flutter as the fallback. On the device these are real
// UIAlertControllers (system font, system buttons, destructive action drawn
// red by UIKit). Off iOS — the host test suite, desktop runs — NativeMenu is
// inert, so the same call falls through to a dark AlertDialog that matches the
// rest of the app.
//
// Every caller therefore behaves identically on both sides, and no test has to
// know which half ran.
//
// M338 — the FALLBACKS are Cupertino now. They were Material `AlertDialog`s,
// which is the wrong alphabet for a fallback whose whole job is to stand in
// for a UIAlertController: a Material dialog has left-aligned actions in a
// row, a different corner radius and a different type ramp, so an off-device
// screenshot said nothing about what the device would show. A
// `CupertinoAlertDialog` is the same shape UIKit draws, so the two halves now
// differ only in who renders them.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showDialog;
import 'package:native_menu/native_menu.dart';

import '../ios_design.dart';
import '../l10n/l.dart';

/// One-line text input. Returns null when cancelled.
///
/// [validate] returns null when the value is acceptable, otherwise the reason.
/// The native alert cannot show inline errors, so it re-asks (with the message
/// folded into the alert body) until the value is good or the user cancels —
/// the Flutter path shows the same message under the field.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? message,
  String initialValue = '',
  String placeholder = '',
  String confirmLabel = 'OK',
  String? Function(String value)? validate,
}) async {
  if (NativeMenu.isSupported) {
    var body = message;
    var value = initialValue;
    // Bounded: a user who cannot produce a valid name still leaves by
    // cancelling, and an unbounded loop must never be possible here.
    for (var attempt = 0; attempt < 12; attempt++) {
      final answer = await NativeMenu.promptText(
        title: title,
        message: body,
        initialValue: value,
        placeholder: placeholder,
        confirmLabel: confirmLabel,
      );
      if (answer == null) return null;
      final problem = validate?.call(answer);
      if (problem == null) return answer;
      body = problem;
      value = answer;
    }
    return null;
  }

  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      message: message,
      initialValue: initialValue,
      placeholder: placeholder,
      confirmLabel: confirmLabel,
      validate: validate,
    ),
  );
}

/// The controller MUST be owned by a State: disposing it right after
/// `showDialog` returns kills it while the route is still animating out, and
/// the still-mounted TextField then trips
/// `_dependents.isEmpty` inside _FocusInheritedScope.
class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String initialValue;
  final String placeholder;
  final String confirmLabel;
  final String? Function(String value)? validate;
  const _TextPromptDialog({
    required this.title,
    required this.message,
    required this.initialValue,
    required this.placeholder,
    required this.confirmLabel,
    required this.validate,
  });
  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);
  late String? _error = widget.message;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text;
    final problem = widget.validate?.call(v);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CupertinoTextField(
            controller: _ctrl,
            autofocus: true,
            placeholder: widget.placeholder,
            cursorColor: IosColors.tint,
            style: IosText.subheadline.on(IosColors.label),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: IosText.footnote.on(IosColors.destructive)),
            ),
        ]),
      ),
      actions: [
        CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L.of(context).cancel)),
        CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _submit,
            child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Yes/no confirmation. [destructive] paints the confirm action red.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  if (NativeMenu.isSupported) {
    return NativeMenu.confirm(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L.of(context).cancel)),
        CupertinoDialogAction(
          // UIKit draws a destructive action red itself, and so does this —
          // we never colour one by hand.
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
