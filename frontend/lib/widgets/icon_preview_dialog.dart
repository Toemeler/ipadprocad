// M348 — the one screen that turns the live icon preview on.
//
// Deliberately NOT localised. Every other visible string in this app comes
// from the ARB because the app is German; this one is a developer affordance
// that exists to point a tablet at a PC on the same desk, and inventing two
// translations for a field that takes an IP address is ceremony for nobody.
import 'package:flutter/material.dart';

import '../icon_preview.dart';
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
    return AlertDialog(
      backgroundColor: T.panel,
      title: Text('Icon Preview', style: TextStyle(color: T.text, fontSize: 17)),
      content: ValueListenableBuilder<int>(
        valueListenable: IconPreview.revision,
        builder: (_, __, ___) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run tools/icon-sync/serve.py on the PC you draw on, then type '
              'the address it prints. Leave empty to use the built-in icons.',
              style: TextStyle(color: T.dim, fontSize: 13, height: 1.35),
            ),
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
                hintText: '192.168.1.42:8080',
                hintStyle: TextStyle(color: T.dim),
                filled: true,
                fillColor: T.field,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(_status(), style: TextStyle(color: _statusColor(), fontSize: 12.5)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _apply(''),
          child: Text('Turn off', style: TextStyle(color: T.dim)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: T.dim)),
        ),
        TextButton(
          onPressed: () => _apply(_c.text),
          child: Text('Connect', style: TextStyle(color: T.accent)),
        ),
      ],
    );
  }

  String _status() {
    if (!IconPreview.active) return 'Off — showing the built-in icons.';
    final err = IconPreview.lastError;
    if (err != null) return 'Cannot reach ${IconPreview.host.value}\n$err';
    return '${IconPreview.count} icon(s) live from ${IconPreview.host.value}';
  }

  Color _statusColor() {
    if (!IconPreview.active) return T.dim;
    return IconPreview.lastError != null ? T.err : T.ok;
  }
}
