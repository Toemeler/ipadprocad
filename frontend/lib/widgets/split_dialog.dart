// M228 — Inventor's Split panel, in the half this architecture carries: Trim
// Solid. One plane, one side, OK.
//
// M338 — drawn as an iOS panel. The command is unchanged; what moved is the
// chrome: a navigation bar with Cancel leading and OK trailing instead of a
// footer of Win32 buttons, one inset grouped section, and the sentence about
// what Split throws away as that section's footer — which is where iOS puts an
// explanation of the rows above it. See widgets/ios_kit.dart.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';
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

  static const _size = Size(IosMetrics.panelWidth, 300);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.splitSession;
    if (s == null) return const SizedBox.shrink();
    final t = L.of(context);
    final ready = s.frame != null;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: s.editing?.name ?? t.btnSplit,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelSplit),
          trailing: IosBarButton(
              label: t.ok,
              prominent: true,
              onTap: ready ? app.applySplit : null),
        ),
        children: [
          iosSection(
            header: t.lblTrim,
            open: _open,
            onToggle: () => setState(() => _open = !_open),
            footer: t.msgSplitRemovesOtherSide,
            children: [
              iosPickRow(
                label: t.lblPlaneField,
                value: s.frame == null ? null : s.label,
                hint: t.hintTapPlaneOrFace,
                armed: s.frame == null,
                filled: s.frame != null,
                onTap: app.repickSplitPlane,
              ),
              iosStackedRow(
                label: t.lblKeep,
                child: IosSegmented<bool>(
                  value: s.flip,
                  onChanged: (v) => app.setSplit(flip: v),
                  segments: [
                    IosSegment(value: false, label: t.lblThisSide),
                    IosSegment(value: true, label: t.lblOtherSide),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
