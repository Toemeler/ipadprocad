// M227 — Inventor's Combine panel.
//
// The smallest of the property panels, because the command is: which body to
// keep, which to combine into it, and how.
//
// M338 — drawn as an iOS panel, from widgets/ios_kit.dart like every other
// one. The two body slots are pick rows (the panel is always collecting, and
// which slot a tap lands in follows from whether a base has been chosen yet),
// the operation is a segmented control, and "keep the tool body" is a switch —
// which is what a yes/no in a list row is on iOS, rather than a pair of
// buttons labelled Yes and No.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';
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

  static const _size = Size(IosMetrics.panelWidth, 360);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.combineSession;
    if (s == null) return const SizedBox.shrink();
    final t = L.of(context);
    final ready = s.baseBody != null && s.tools.isNotEmpty;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: s.editing?.name ?? t.btnCombine,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelCombine),
          trailing: IosBarButton(
              label: t.ok,
              prominent: true,
              onTap: ready ? app.applyCombine : null),
        ),
        children: [
          iosSection(
            header: t.lblBodies,
            open: _open,
            onToggle: () => setState(() => _open = !_open),
            children: [
              iosPickRow(
                label: t.lblBase,
                value: s.baseBody,
                hint: t.hintTapBodyToKeep,
                armed: s.baseBody == null,
                filled: s.baseBody != null,
              ),
              iosPickRow(
                label: t.lblToolbodies,
                value: s.tools.isEmpty ? null : s.tools.join(', '),
                hint: s.baseBody == null
                    ? t.hintPickBaseFirst
                    : t.hintTapBodiesToCombine,
                armed: s.baseBody != null && s.tools.isEmpty,
                filled: s.tools.isNotEmpty,
              ),
              iosStackedRow(
                label: t.lblOperation,
                child: IosSegmented<String>(
                  value: s.op,
                  onChanged: (v) => app.setCombine(op: v),
                  segments: [
                    IosSegment(value: 'join', label: t.opJoin),
                    IosSegment(value: 'cut', label: t.opCut),
                    IosSegment(value: 'intersect', label: t.opIntersect),
                  ],
                ),
              ),
              iosSwitchRow(
                label: t.lblKeepTool,
                value: s.keepTool,
                onChanged: (v) => app.setCombine(keepTool: v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
