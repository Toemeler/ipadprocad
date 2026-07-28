// Prototype — the freehand spline's modeless fit window (M87).
//
// Opens where the stroke ended, in the same movable-window idiom as the Gear
// and Parameters dialogs: every edit mutates the session and calls
// app.freehandNotify(), which re-fits from the RAW ink and repaints. The
// preview in the viewport is therefore always exactly the geometry that ✓ will
// commit — there is no second code path to drift.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../freehand.dart';
import '../theme.dart';

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
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 268,
        decoration: BoxDecoration(
          color: T.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: T.panelSep),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6))
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // title bar — drag to move, like every other floating window here
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => widget.onDrag(d.delta),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: T.flyHov,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(children: [
                Text('Freehand Spline',
                    style: ts(12, T.text, w: FontWeight.w600)),
                const Spacer(),
                _IconBtn(
                  tooltip: 'Discard (Esc)',
                  icon: Icons.close,
                  color: T.dim,
                  onTap: widget.app.freehandCancel,
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _slider(
                label: 'Points',
                value: f.points.toDouble(),
                min: kFreehandMinPoints.toDouble(),
                max: kFreehandMaxPoints.toDouble(),
                divisions: kFreehandMaxPoints - kFreehandMinPoints,
                readout: '${f.points}',
                onChanged: (v) => _edit(() => f.points = v.round()),
              ),
              _slider(
                label: 'Smoothing',
                value: f.smoothing,
                min: 0,
                max: 1,
                readout: '${(f.smoothing * 100).round()}%',
                onChanged: (v) => _edit(() => f.smoothing = v),
              ),
              const SizedBox(height: 4),
              _check(
                label: 'Close if ends meet',
                value: f.snapClosed,
                onChanged: (v) => _edit(() => f.snapClosed = v),
              ),
              _check(
                label: 'Snap ends to points',
                value: f.snapToPoints,
                onChanged: (v) => _edit(() => f.snapToPoints = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Text('${widget.app.toolPoints.length} fit points',
                    style: ts(10.5, T.dim)),
                const Spacer(),
                _FinishButton(onTap: widget.app.freehandCommit),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String readout,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(label, style: ts(11.5, T.text)),
            const Spacer(),
            Text(readout, style: ts(11.5, T.dim)),
          ]),
          SizedBox(
            height: 26,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: T.blue,
                inactiveTrackColor: T.panelSep,
                thumbColor: T.blue,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
        ]),
      );

  Widget _check({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: value ? T.blue : Colors.transparent,
                border: Border.all(color: value ? T.blue : T.dim, width: 1.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: value
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(label, style: ts(11.5, T.text)),
          ]),
        ),
      );
}

class _IconBtn extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      );
}

/// The green ✓, same affordance as the ribbon's Finish.
class _FinishButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FinishButton({required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Finish (Enter)',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text('Finish', style: ts(11.5, Colors.white, w: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
