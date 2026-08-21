// M227 — Inventor's Combine panel.
//
// The smallest of the property panels, because the command is: which body to
// keep, which to combine into it, and how. Chrome from properties_panel.dart,
// like every other one.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'dialog_dock.dart';
import 'properties_panel.dart';
import '../l10n/l.dart';

class CombineDialog extends StatefulWidget {
  final AppState app;
  const CombineDialog({super.key, required this.app});

  @override
  State<CombineDialog> createState() => _CombineDialogState();
}

class _CombineDialogState extends State<CombineDialog> {
  Offset? _pos;
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.combineSession;
    if (s == null) return const SizedBox.shrink();

    const w = 300.0, h = 300.0;
    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, const Size(w, h));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w,
          decoration: BoxDecoration(
            color: T.panel,
            border: Border.all(color: T.sep),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                  color: T.scrim,
                  blurRadius: 24,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: T.fly,
                  border: Border(bottom: BorderSide(color: T.panelSep)),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                ),
                child: Row(children: [
                  Text(L.of(context).dlgProperties,
                      style: ts(13, T.text, w: FontWeight.w600)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: app.cancelCombine,
                    child: Text('✕', style: ts(11.5, T.dim)),
                  ),
                  const Spacer(),
                  Icon(Icons.menu, size: 14, color: T.dim),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                Text(s.editing?.name ?? L.of(context).btnCombine, style: ts(12.5, T.accent)),
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 14, color: T.dim),
              ]),
            ),
            panelSection(L.of(context).lblBodies, _open, () => setState(() => _open = !_open), [
              panelRow(
                  L.of(context).lblBase,
                  panelPickField(
                    icon: Icons.crop_square,
                    active: s.baseBody == null,
                    label: s.baseBody ?? L.of(context).hintTapBodyToKeep,
                  )),
              panelRow(
                  L.of(context).lblToolbodies,
                  panelPickField(
                    icon: Icons.layers_outlined,
                    active: s.baseBody != null,
                    label: s.tools.isEmpty
                        ? (s.baseBody == null
                            ? L.of(context).hintPickBaseFirst
                            : L.of(context).hintTapBodiesToCombine)
                        : s.tools.join(', '),
                  )),
              panelRow(
                  L.of(context).lblOperation,
                  Row(children: [
                    for (final op in const ['join', 'cut', 'intersect']) ...[
                      if (op != 'join') const SizedBox(width: 6),
                      _seg(_opLabel(L.of(context), op), s.op == op,
                          () => app.setCombine(op: op)),
                    ],
                  ])),
              panelRow(
                  L.of(context).lblKeepTool,
                  Row(children: [
                    _seg('No', !s.keepTool,
                        () => app.setCombine(keepTool: false)),
                    const SizedBox(width: 6),
                    _seg(L.of(context).lblYes, s.keepTool,
                        () => app.setCombine(keepTool: true)),
                  ])),
            ]),
            _footer(app, s),
          ]),
        ),
      ),
    );
  }

  static String _opLabel(AppL10n t, String op) => switch (op) {
        'join' => t.opJoin,
        'intersect' => t.opIntersect,
        _ => t.opCut,
      };

  Widget _seg(String label, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? T.accent : T.fly,
              border:
                  Border.all(color: on ? T.accent : T.panelSep),
              borderRadius: BorderRadius.circular(3),
            ),
            child:
                Text(label, style: ts(11.5, on ? T.onAccent : T.text)),
          ),
        ),
      );

  Widget _footer(AppState app, CombineSession s) {
    final ready = s.baseBody != null && s.tools.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(children: [
        Expanded(
          child: Opacity(
            opacity: ready ? 1 : 0.45,
            child: GestureDetector(
              onTap: ready ? () => app.applyCombine() : null,
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: T.accent, borderRadius: BorderRadius.circular(3)),
                child: Text(L.of(context).ok,
                    style: ts(12.5, T.text, w: FontWeight.w600)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: app.cancelCombine,
            child: Container(
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.bg,
                border: Border.all(color: T.panelSep),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(L.of(context).cancel, style: ts(12.5, T.text)),
            ),
          ),
        ),
      ]),
    );
  }
}
