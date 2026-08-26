// M249 — Inventor's DRIVE dialog, and the timer that steps it.
//
// The command M242 owed the motion constraints. That milestone built Rotation
// and Rotation-Translation and the drive pass they need (asm_solver.driveMotion,
// tested as "motion is DRIVEN, not solved") and gave them nothing to run from:
// a gear pair could only turn if you dragged the shaft with a finger.
//
//   ┌ Drive Constraint ─────────────────────── ✕ ┐
//   │  Start [0.000 deg >]   End [360.000 deg >] │
//   │  Pause Delay [0.05 s >]                    │
//   │  ├──────────●──────────────────────────┤   │
//   │  [⏮] [◀] [⏸] [▶] [⏭]      Angle1 · 128° │
//   │ ┌ Increment ────────┐┌ Repetitions ──────┐ │
//   │ │ ● Amount of value ││ ● Start/End       │ │
//   │ │ ○ Total steps     ││ ○ Start/End/Start │ │
//   │ │ [5.000 deg     >] ││ Cycles [1      >] │ │
//   │ └───────────────────┘└───────────────────┘ │
//   │  ☐ Drive Adaptivity   ☐ Collision Detection│
//   │                                  [ Close ] │
//   └────────────────────────────────────────────┘
//
// The two checkboxes on the last row are DRAWN AND INERT, and that is a
// deliberate exception to M157's rule rather than an oversight of it. M157 is
// about a command that looks ready and does nothing; these are two options of
// a dialog that works, and their absence would make the panel read as a
// different dialog from the one it is a transcription of — the same argument
// the Place Constraint dialog makes for keeping its inert recent-values ▸.
// They are greyed, untappable, and their tooltip says so in words. What is
// behind them is real work: Drive Adaptivity needs adaptive parts, which this
// app has none of, and Collision Detection needs interference checking, which
// is a milestone rather than a checkbox.
//
// Where it opens from is Inventor's own place: "the Drive dialog box opens
// when you right-click a relationship in the browser and select Drive". Both
// browsers carry the entry — see model_browser._constraintMenu and
// native_browser._constraintMenu.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';
import '../scrub.dart';
import '../theme.dart';
import 'constraint_dialog.dart';
import 'dialog_dock.dart';
import 'scrub_field.dart';

/// Which playback mark to draw. See [_DriveDialogState._transport].
enum _TransportMark { toStart, reverse, pause, play, toEnd }

class _TransportPainter extends CustomPainter {
  const _TransportPainter(this.mark, this.color);
  final _TransportMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final h = size.height, w = size.width;
    final mid = h / 2;

    /// A solid triangle pointing right from [x], or left when [dx] is negative.
    void triangle(double x, double dx) {
      final p = Path()
        ..moveTo(x, 0)
        ..lineTo(x + dx, mid)
        ..lineTo(x, h)
        ..close();
      canvas.drawPath(p, paint);
    }

    void bar(double x) => canvas.drawRect(Rect.fromLTWH(x, 0, 2.2, h), paint);

    switch (mark) {
      case _TransportMark.play:
        triangle(w * 0.3, w * 0.4);
      case _TransportMark.reverse:
        triangle(w * 0.7, -w * 0.4);
      case _TransportMark.pause:
        bar(w * 0.35);
        bar(w * 0.53);
      case _TransportMark.toStart:
        bar(w * 0.28);
        triangle(w * 0.72, -w * 0.36);
      case _TransportMark.toEnd:
        triangle(w * 0.28, w * 0.36);
        bar(w * 0.68);
    }
  }

  @override
  bool shouldRepaint(covariant _TransportPainter old) =>
      old.mark != mark || old.color != color;
}

class DriveDialog extends StatefulWidget {
  final AppState app;
  const DriveDialog({super.key, required this.app});

  @override
  State<DriveDialog> createState() => _DriveDialogState();
}

class _DriveDialogState extends State<DriveDialog> {
  Offset? _pos;

  /// One controller per number field, and one "what it last showed" beside
  /// each. The panel rebuilds on every tick of the sweep, so without the
  /// second the running animation would fight anything being typed — the trap
  /// constraint_dialog.dart's `_valueShown` exists for, four times over.
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _pause = TextEditingController();
  final _increment = TextEditingController();
  final _steps = TextEditingController();
  final _cycles = TextEditingController();
  final _shown = <TextEditingController, String>{};

  static const _size = Size(430, 340);

  @override
  void dispose() {
    for (final c in [_start, _end, _pause, _increment, _steps, _cycles]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync(TextEditingController c, String text) {
    if (_shown[c] == text) return;
    _shown[c] = text;
    c.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.driveSession;
    if (s == null) return const SizedBox.shrink();
    final t = L.of(context);
    final unit = _unit(s);

    _sync(_start, '${s.start.toStringAsFixed(3)} $unit');
    _sync(_end, '${s.end.toStringAsFixed(3)} $unit');
    _sync(_pause, s.pauseDelay.toStringAsFixed(2));
    _sync(_increment, '${s.increment.toStringAsFixed(3)} $unit');
    _sync(_steps, '${s.totalSteps}');
    _sync(_cycles, '${s.cycles}');

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: asmPanelCard(width: _size.width, children: [
        asmTitleBar(t.dlgDrive,
            onClose: app.closeDrive,
            onDrag: (d) => setState(() {
                  _pos = (_pos ?? DialogDock.spot(vp, _size)) + d;
                })),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
                child: _numberField(app, t.lblDriveStart, _start, unit,
                    (v) => app.setDriveField(start: v))),
            const SizedBox(width: 8),
            Expanded(
                child: _numberField(app, t.lblDriveEnd, _end, unit,
                    (v) => app.setDriveField(end: v))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
                child: _numberField(app, t.lblDrivePause, _pause, 's',
                    (v) => app.setDriveField(pauseDelay: v))),
            const SizedBox(width: 8),
            // WHERE THE SWEEP IS, in words. The bar below says it as a
            // picture; a number is what a person reads back to somebody else,
            // and it is the constraint's own value rather than the phase.
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(constraintLabel(t, s.constraint.kind),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(11, T.dim)),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 26,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${s.current.toStringAsFixed(2)} $unit',
                            style: ts(12.5, T.text, w: FontWeight.w600)),
                      ),
                    ),
                  ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: _track(s),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _transport(app, s, t),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _incrementGroup(app, s, t, unit)),
            const SizedBox(width: 8),
            Expanded(child: _repetitionGroup(app, s, t)),
          ]),
        ),
        _unbuiltOptions(t),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            asmFlatButton(t.close, app.closeDrive, primary: true),
          ]),
        ),
      ]),
    );
  }

  /// The units the sweep is in.
  ///
  /// A motion drive turns the DRIVER shaft, so it is always degrees whatever
  /// the constraint's own value means — see [DriveSession] for why a ratio is
  /// not a thing to animate. Everything else is the constraint's own unit.
  static String _unit(DriveSession s) {
    if (s.motion) return 'deg';
    return valueKindOf(s.constraint.kind) == AsmValueKind.angle ? 'deg' : 'mm';
  }

  // ---- the position bar ----------------------------------------------------

  /// Where the sweep is, as a picture. Not draggable: the transport below
  /// drives it, and a bar you could grab would be a second authority over the
  /// same phase — one that would fight the timer while it is running.
  Widget _track(DriveSession s) => LayoutBuilder(builder: (_, bc) {
        final w = bc.maxWidth;
        return SizedBox(
          height: 12,
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              top: 5,
              child: Container(height: 2, color: T.panelSep),
            ),
            Positioned(
              left: (w - 8) * s.phase.clamp(0.0, 1.0),
              top: 1,
              child: Container(
                width: 8,
                height: 10,
                decoration: BoxDecoration(
                  color: s.playing ? T.accent : T.dim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ]),
        );
      });

  // ---- the transport -------------------------------------------------------

  /// The five playback buttons.
  ///
  /// PAINTED, not typed. The obvious spelling is ⏮ ◀ ❙❙ ▶ ⏭, and it renders as
  /// five empty boxes: U+23EE and U+23ED are not in the app's text face at
  /// all, and U+25C0 / U+25B6 carry emoji presentation on iOS, so what would
  /// reach the iPad is either tofu or a row of coloured cartoons. A triangle
  /// and a bar are two paths.
  Widget _transport(AppState app, DriveSession s, AppL10n t) =>
      Row(children: [
        _transportButton(_TransportMark.toStart, t.tipDriveToStart,
            () => app.driveToEnd(atEnd: false)),
        const SizedBox(width: 5),
        _transportButton(_TransportMark.reverse, t.tipDriveReverse,
            () => app.playDrive(reverse: true), on: s.playing && s.reverse),
        const SizedBox(width: 5),
        _transportButton(_TransportMark.pause, t.tipDrivePause, app.pauseDrive),
        const SizedBox(width: 5),
        _transportButton(_TransportMark.play, t.tipDrivePlay,
            () => app.playDrive(), on: s.playing && !s.reverse),
        const SizedBox(width: 5),
        _transportButton(_TransportMark.toEnd, t.tipDriveToEnd,
            () => app.driveToEnd(atEnd: true)),
      ]);

  Widget _transportButton(_TransportMark mark, String tip, VoidCallback onTap,
          {bool on = false}) =>
      Tooltip(
        message: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 40,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? T.accent.withValues(alpha: 0.28) : T.fly,
              border: Border.all(color: on ? T.accent : T.panelSep),
              borderRadius: BorderRadius.circular(3),
            ),
            child: CustomPaint(
              size: const Size(16, 12),
              painter: _TransportPainter(mark, on ? T.accent : T.text),
            ),
          ),
        ),
      );

  // ---- Increment / Repetitions --------------------------------------------

  Widget _incrementGroup(
          AppState app, DriveSession s, AppL10n t, String unit) =>
      asmGroup(
        t.grpDriveIncrement,
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              asmRadio(
                  on: !s.byTotalSteps,
                  label: t.optDriveAmount,
                  onTap: () => app.setDriveField(byTotalSteps: false)),
              const SizedBox(height: 3),
              asmRadio(
                  on: s.byTotalSteps,
                  label: t.optDriveSteps,
                  onTap: () => app.setDriveField(byTotalSteps: true)),
              const SizedBox(height: 5),
              // ONE field, showing whichever of the two is chosen. Inventor
              // draws a field per radio and greys the other; at this width two
              // fields would each be too narrow to read a value in.
              s.byTotalSteps
                  ? _field(app, _steps, 'ul',
                      (v) => app.setDriveField(totalSteps: v.round()))
                  : _field(app, _increment, unit,
                      (v) => app.setDriveField(increment: v)),
            ]),
      );

  Widget _repetitionGroup(AppState app, DriveSession s, AppL10n t) => asmGroup(
        t.grpDriveRepetitions,
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              asmRadio(
                  on: !s.roundTrip,
                  label: t.optDriveOnce,
                  onTap: () => app.setDriveField(roundTrip: false)),
              const SizedBox(height: 3),
              asmRadio(
                  on: s.roundTrip,
                  label: t.optDriveBoth,
                  onTap: () => app.setDriveField(roundTrip: true)),
              const SizedBox(height: 5),
              Row(children: [
                Text(t.lblDriveCycles, style: ts(11, T.dim)),
                const SizedBox(width: 6),
                Expanded(
                  child: _field(app, _cycles, 'ul',
                      (v) => app.setDriveField(cycles: v.round())),
                ),
              ]),
            ]),
      );

  /// The two options Inventor has and this app does not. See the file header
  /// for why they are drawn rather than removed.
  Widget _unbuiltOptions(AppL10n t) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Tooltip(
          message: t.hintDriveUnavailable,
          child: Opacity(
            opacity: 0.4,
            child: IgnorePointer(
              child: Row(children: [
                asmTextCheckbox(
                    on: false, label: t.cbDriveAdaptivity, onTap: () {}),
                const SizedBox(width: 14),
                Flexible(
                  child: asmTextCheckbox(
                      on: false, label: t.cbDriveCollision, onTap: () {}),
                ),
              ]),
            ),
          ),
        ),
      );

  // ---- fields --------------------------------------------------------------

  Widget _numberField(AppState app, String label, TextEditingController c,
          String unit, void Function(double) onValue) =>
      Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(11, T.dim)),
            const SizedBox(height: 3),
            _field(app, c, unit, onValue),
          ]);

  Widget _field(AppState app, TextEditingController c, String unit,
      void Function(double) onValue) {
    void commit(String text) {
      _shown[c] = text;
      final n = double.tryParse(
          text.replaceAll(RegExp(r'[^0-9eE+\-.,]'), '').replaceAll(',', '.'));
      if (n != null) onValue(n);
    }

    return ScrubField(
      app: app,
      controller: c,
      suffix: unit,
      kind: scrubKindForUnit(unit),
      onCommit: commit,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: T.fly,
          border: Border.all(color: T.panelSep),
          borderRadius: BorderRadius.circular(3),
        ),
        child: TextField(
          controller: c,
          keyboardType: kValueKeyboard,
          stylusHandwritingEnabled: kValueHandwriting,
          autocorrect: false,
          enableSuggestions: false,
          style: ts(12.5, T.text),
          decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(bottom: 10)),
          onChanged: commit,
        ),
      ),
    );
  }
}
