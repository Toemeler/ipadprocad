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
import 'package:flutter/material.dart' show Material, MaterialType, showDialog;
import 'package:flutter/services.dart';
import 'package:native_menu/native_menu.dart';

import '../desktop_radius.dart';
import '../ios_design.dart';
import '../l10n/l.dart';
import 'ios_kit.dart' show IosBarButton;

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
  // The whole name selected: typing replaces it, which is what a rename or a
  // "new part" box on a desktop does.
  late final TextEditingController _ctrl = TextEditingController.fromValue(
      TextEditingValue(
          text: widget.initialValue,
          selection: TextSelection(
              baseOffset: 0, extentOffset: widget.initialValue.length)));
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
    if (desktopCorners) {
      return DesktopDialog(
        title: widget.title,
        onCancel: () => Navigator.of(context).pop(),
        onConfirm: _submit,
        confirmLabel: widget.confirmLabel,
        cancelLabel: L.of(context).cancel,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoTextField(
              controller: _ctrl,
              autofocus: true,
              placeholder: widget.placeholder,
              cursorColor: IosColors.tint,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: IosColors.cardBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: IosColors.border),
              ),
              style: IosText.subheadline.on(IosColors.label),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: IosText.footnote.on(IosColors.destructive)),
              ),
          ],
        ),
      );
    }
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
    builder: (ctx) => desktopCorners
        ? DesktopDialog(
            title: title,
            content: message == null
                ? null
                : Text(message,
                    style: IosText.subheadline.on(IosColors.secondaryLabel)),
            confirmLabel: confirmLabel,
            cancelLabel: L.of(context).cancel,
            destructive: destructive,
            onConfirm: () => Navigator.of(ctx).pop(true),
            onCancel: () => Navigator.of(ctx).pop(false),
          )
        : CupertinoAlertDialog(
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

/// Linux and Windows: a desktop dialog instead of an iOS alert.
///
/// A left-aligned title with a × beside it, the content, and the buttons at
/// the bottom right — the confirming one filled, first, as Windows orders
/// them. Enter confirms and Esc cancels from anywhere in it.
class DesktopDialog extends StatelessWidget {
  const DesktopDialog({
    super.key,
    required this.title,
    required this.onConfirm,
    required this.onCancel,
    required this.confirmLabel,
    required this.cancelLabel,
    this.content,
    this.destructive = false,
  });

  final String title;
  final Widget? content;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): onConfirm,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): onConfirm,
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Focus(
        autofocus: content is! Column,
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: 420,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: IosColors.groupedBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: IosColors.border),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
                    child: Row(children: [
                      Expanded(
                        child: Text(title,
                            style: IosText.body.on(IosColors.label,
                                weight: FontWeight.w600)),
                      ),
                      GestureDetector(
                        onTap: onCancel,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Icon(CupertinoIcons.xmark,
                                size: 13, color: IosColors.secondaryLabel),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  if (content != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: content,
                    ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    decoration: BoxDecoration(
                      color: IosColors.cardBackground,
                      border:
                          Border(top: BorderSide(color: IosColors.separator)),
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IosBarButton(
                            label: confirmLabel,
                            prominent: true,
                            destructive: destructive,
                            onTap: onConfirm),
                        const SizedBox(width: 8),
                        IosBarButton(label: cancelLabel, onTap: onCancel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
