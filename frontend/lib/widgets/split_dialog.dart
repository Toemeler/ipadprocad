// M228 — Inventor's Split panel, in the half this architecture carries: Trim
// Solid. One plane, one side, OK.
//
// Chrome from properties_panel.dart, like every other property panel.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'dialog_dock.dart';
import 'properties_panel.dart';
import '../l10n/l.dart';

class SplitDialog extends StatefulWidget {
  final AppState app;
  const SplitDialog({super.key, required this.app});

  @override
  State<SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<SplitDialog> {
  Offset? _pos;
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.splitSession;
    if (s == null) return const SizedBox.shrink();

    const w = 300.0, h = 260.0;
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
            boxShadow: const [
              BoxShadow(
                  color: Color(0x73000000),
                  blurRadius: 24,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: const BoxDecoration(
                  color: T.fly,
                  border: Border(bottom: BorderSide(color: T.panelSep)),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                ),
                child: Row(children: [
                  Text(L.of(context).dlgProperties,
                      style: ts(13, Colors.white, w: FontWeight.w600)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: app.cancelSplit,
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
                Text(s.editing?.name ?? L.of(context).btnSplit, style: ts(12.5, T.blue)),
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 14, color: T.dim),
              ]),
            ),
            panelSection(L.of(context).lblTrim, _open, () => setState(() => _open = !_open), [
              panelRow(
                  L.of(context).lblPlaneField,
                  GestureDetector(
                    onTap: app.repickSplitPlane,
                    child: panelPickField(
                      icon: Icons.crop_din,
                      active: s.frame == null,
                      label: s.frame == null
                          ? L.of(context).hintTapPlaneOrFace
                          : s.label,
                    ),
                  )),
              panelRow(
                  L.of(context).lblKeep,
                  Row(children: [
                    _seg(L.of(context).lblThisSide, !s.flip,
                        () => app.setSplit(flip: false)),
                    const SizedBox(width: 6),
                    _seg(L.of(context).lblOtherSide, s.flip,
                        () => app.setSplit(flip: true)),
                  ])),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(L.of(context).msgSplitRemovesOtherSide,
                  style: ts(11, T.dim)),
            ),
            _footer(app, s),
          ]),
        ),
      ),
    );
  }

  Widget _seg(String label, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? T.blue : const Color(0xFF212429),
              border:
                  Border.all(color: on ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label, style: ts(11.5, on ? Colors.white : T.text)),
          ),
        ),
      );

  Widget _footer(AppState app, SplitSession s) {
    final ready = s.frame != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(children: [
        Expanded(
          child: Opacity(
            opacity: ready ? 1 : 0.45,
            child: GestureDetector(
              onTap: ready ? () => app.applySplit() : null,
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: T.blue, borderRadius: BorderRadius.circular(3)),
                child: Text(L.of(context).ok,
                    style: ts(12.5, Colors.white, w: FontWeight.w600)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: app.cancelSplit,
            child: Container(
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2E33),
                border: Border.all(color: const Color(0xFF3A3F45)),
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
