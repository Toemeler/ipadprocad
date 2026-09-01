// Prototype — the freehand spline's modeless fit window (M87).
//
// Opens where the stroke ended, in the same movable-window idiom as the Gear
// and Parameters dialogs: every edit mutates the session and calls
// app.freehandNotify(), which re-fits from the RAW ink and repaints. The
// preview in the viewport is therefore always exactly the geometry that ✓ will
// commit — there is no second code path to drift.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). The two sliders were
// already the right control and are now the system one; Finish is the
// navigation bar's confirming action with Discard opposite it, and the count
// of fit points is the section's footer rather than a caption crowded against
// the button.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../freehand.dart';
import 'ios_kit.dart';
import '../l10n/l.dart';

class FreehandDialog extends StatefulWidget {
  final AppState app;
  final void Function(Offset) onDrag;
  const FreehandDialog({super.key, required this.app, required this.onDrag});

  @override
  State<FreehandDialog> createState() => _FreehandDialogState();
}

class _FreehandDialogState extends State<FreehandDialog> {
  FreehandSession? get fs => widget.app.freehand;

  void _edit(VoidCallback change) {
    setState(change);
    widget.app.freehandNotify();
  }

  @override
  Widget build(BuildContext context) {
    final f = fs;
    if (f == null) return const SizedBox.shrink();
    final app = widget.app;
    final t = L.of(context);
    return IosPanel(
      width: 320,
      nav: IosNavBar(
        title: t.dlgFreehandSpline,
        onDrag: widget.onDrag,
        leading: IosBarButton(
            label: t.discard,
            tooltip: t.tipDiscardEsc,
            onTap: app.freehandCancel),
        trailing: IosBarButton(
            label: t.finish,
            prominent: true,
            tooltip: t.tipFinishEnter,
            onTap: app.freehandCommit),
      ),
      children: [
        iosSection(
          // M207 — "close if ends meet should be standard and snap ends to
          // points also, and not be a toggle in the dialog." Both were already
          // ON by default; what they cost was two rows of dialog and a decision
          // nobody was going to make differently. They are constants on the
          // session now (see FreehandSession) — off is reachable by deleting
          // the constraint afterwards, like any other.
          footer: t.lblFitPoints(app.toolPoints.length),
          children: [
            iosSliderRow(
              label: t.lblPoints,
              readout: '${f.points}',
              value: f.points.toDouble(),
              min: kFreehandMinPoints.toDouble(),
              max: kFreehandMaxPoints.toDouble(),
              divisions: kFreehandMaxPoints - kFreehandMinPoints,
              onChanged: (v) => _edit(() => f.points = v.round()),
            ),
            iosSliderRow(
              label: t.lblSmoothing,
              readout: '${(f.smoothing * 100).round()}%',
              value: f.smoothing,
              min: 0,
              max: 1,
              onChanged: (v) => _edit(() => f.smoothing = v),
            ),
          ],
        ),
      ],
    );
  }
}
