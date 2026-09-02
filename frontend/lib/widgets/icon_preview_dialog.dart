// M348 — the one screen that turns the live icon preview on.
import 'package:flutter/material.dart';

import '../icon_preview.dart';
import '../l10n/l.dart';
import '../theme.dart';

/// Ask for the address of the machine running `tools/icon-sync/serve.py`.
Future<void> showIconPreviewDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _IconPreviewDialog());

class _IconPreviewDialog extends StatefulWidget {
  const _IconPreviewDialog();
  @override
  State<_IconPreviewDialog> createState() => _IconPreviewDialogState();
}

class _IconPreviewDialogState extends State<_IconPreviewDialog> {
  late final TextEditingController _c =
      TextEditingController(text: IconPreview.host.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _apply(String v) {
    IconPreview.setHost(v);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return AlertDialog(
      backgroundColor: T.panel,
      title: Text(t.settingsIconPreview,
          style: TextStyle(color: T.text, fontSize: 17)),
      content: ValueListenableBuilder<int>(
        valueListenable: IconPreview.revision,
        builder: (_, __, ___) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.iconPreviewHelp,
                style: TextStyle(color: T.dim, fontSize: 13, height: 1.35)),
            const SizedBox(height: 14),
            TextField(
              controller: _c,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: _apply,
              style: TextStyle(color: T.text, fontSize: 15),
              decoration: InputDecoration(
                // An address, not a sentence: the same in every language, and
                // localising it would only invite someone to translate it.
                hintText: '192.168.1.42:8080',
                hintStyle: TextStyle(color: T.dim),
                filled: true,
                fillColor: T.field,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(_status(t),
                style: TextStyle(color: _statusColor(), fontSize: 12.5)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _apply(''),
          child: Text(t.iconPreviewTurnOff, style: TextStyle(color: T.dim)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel, style: TextStyle(color: T.dim)),
        ),
        TextButton(
          onPressed: () => _apply(_c.text),
          child: Text(t.iconPreviewConnect, style: TextStyle(color: T.accent)),
        ),
      ],
    );
  }

  String _status(AppL10n t) {
    if (!IconPreview.active) return t.iconPreviewIdle;
    final err = IconPreview.lastError;
    if (err != null) {
      return t.iconPreviewUnreachable(IconPreview.host.value, err);
    }
    return t.iconPreviewLive(IconPreview.count, IconPreview.host.value);
  }

  Color _statusColor() {
    if (!IconPreview.active) return T.dim;
    return IconPreview.lastError != null ? T.err : T.ok;
  }
}
