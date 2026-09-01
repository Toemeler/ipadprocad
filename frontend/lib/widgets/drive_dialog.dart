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
// Two of Inventor's options are drawn and inert rather than absent: Drive
// Adaptivity needs adaptive parts, which this app has none of, and Collision
// Detection needs interference checking, which is a milestone rather than a
// checkbox.
//
// Where it opens from is Inventor's own place: "the Drive dialog box opens
// when you right-click a relationship in the browser and select Drive". Both
// browsers carry the entry — see model_browser._constraintMenu and
// native_browser._constraintMenu.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). Three parts changed
// shape rather than only style:
//
//   * THE TRANSPORT IS FIVE ROUND KEYS, drawn from ios_kit's glyph set rather
//     than from this file's own painter. The reason the old ones were painted
//     stands and is now the kit's: ⏮ ◀ ❙❙ ▶ ⏭ is five empty boxes in the app's
//     text face, and U+25C0 / U+25B6 arrive as coloured emoji on iOS.
//   * THE TWO RADIO PAIRS ARE SEGMENTED CONTROLS. iOS has no radio button;
//     two mutually exclusive modes with one field under them is exactly what
//     a segmented control says.
//   * THE POSITION BAR IS A DISABLED SLIDER — the system control, showing
//     where the sweep is. Still not draggable, for the reason it never was:
//     the transport drives the phase, and a bar you could grab would be a
//     second authority over it that fights the timer while it runs.
import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../ios_design.dart';
import 'constraint_dialog.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';

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

  static const _size = Size(IosMetrics.widePanelWidth, 620);

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
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: t.dlgDrive,
          onDrag: (d) => setState(() => _pos = pos + d),
          trailing: IosBarButton(
              label: t.close, prominent: true, onTap: app.closeDrive),
        ),
        children: [
          _rangeSection(app, s, t, unit),
          _transportSection(app, s, t, unit),
          _incrementSection(app, s, t, unit),
          _repetitionSection(app, s, t),
          _unbuiltSection(t),
        ],
      ),
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

  // ---- Start / End / Pause -------------------------------------------------

  Widget _rangeSection(
          AppState app, DriveSession s, AppL10n t, String unit) =>
      iosSection(
        children: [
          asmValueRow(
              app: app,
              label: t.lblDriveStart,
              controller: _start,
              unit: unit,
              onChanged: (v) => _commit(_start, v,
                  (n) => app.setDriveField(start: n))),
          asmValueRow(
              app: app,
              label: t.lblDriveEnd,
              controller: _end,
              unit: unit,
              onChanged: (v) =>
                  _commit(_end, v, (n) => app.setDriveField(end: n))),
          asmValueRow(
              app: app,
              label: t.lblDrivePause,
              controller: _pause,
              unit: 's',
              onChanged: (v) => _commit(
                  _pause, v, (n) => app.setDriveField(pauseDelay: n))),
        ],
      );

  // ---- where the sweep is, and the keys that move it -----------------------

  Widget _transportSection(
          AppState app, DriveSession s, AppL10n t, String unit) =>
      iosSection(
        children: [
          // WHERE THE SWEEP IS, in words. The bar below says it as a picture;
          // a number is what a person reads back to somebody else, and it is
          // the constraint's own value rather than the phase.
          iosRow(
            label: constraintLabel(t, s.constraint.kind),
            value: '${s.current.toStringAsFixed(2)} $unit',
            valueColour: IosColors.label,
          ),
          iosStackedRow(
            child: IgnorePointer(
              child: CupertinoSlider(
                value: s.phase.clamp(0.0, 1.0),
                onChanged: (_) {},
                activeColor:
                    s.playing ? IosColors.tint : IosColors.secondaryLabel,
              ),
            ),
          ),
          iosStackedRow(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IosCircleButton(
                    glyph: IosGlyph.toStart,
                    tooltip: t.tipDriveToStart,
                    onTap: () => app.driveToEnd(atEnd: false)),
                IosCircleButton(
                    glyph: IosGlyph.backward,
                    tooltip: t.tipDriveReverse,
                    on: s.playing && s.reverse,
                    onTap: () => app.playDrive(reverse: true)),
                IosCircleButton(
                    glyph: IosGlyph.pause,
                    tooltip: t.tipDrivePause,
                    onTap: app.pauseDrive),
                IosCircleButton(
                    glyph: IosGlyph.play,
                    tooltip: t.tipDrivePlay,
                    on: s.playing && !s.reverse,
                    onTap: () => app.playDrive()),
                IosCircleButton(
                    glyph: IosGlyph.toEnd,
                    tooltip: t.tipDriveToEnd,
                    onTap: () => app.driveToEnd(atEnd: true)),
              ],
            ),
          ),
        ],
      );

  // ---- Increment / Repetitions --------------------------------------------

  Widget _incrementSection(
          AppState app, DriveSession s, AppL10n t, String unit) =>
      iosSection(
        header: t.grpDriveIncrement,
        children: [
          iosStackedRow(
            child: IosSegmented<bool>(
              value: s.byTotalSteps,
              onChanged: (v) => app.setDriveField(byTotalSteps: v),
              segments: [
                IosSegment(value: false, label: t.optDriveAmount),
                IosSegment(value: true, label: t.optDriveSteps),
              ],
            ),
          ),
          // ONE field, showing whichever of the two is chosen. Inventor draws
          // a field per radio and greys the other; two fields would each be
          // too narrow to read a value in.
          if (s.byTotalSteps)
            asmValueRow(
                app: app,
                label: t.optDriveSteps,
                controller: _steps,
                unit: 'ul',
                onChanged: (v) => _commit(_steps, v,
                    (n) => app.setDriveField(totalSteps: n.round())))
          else
            asmValueRow(
                app: app,
                label: t.optDriveAmount,
                controller: _increment,
                unit: unit,
                onChanged: (v) => _commit(_increment, v,
                    (n) => app.setDriveField(increment: n))),
        ],
      );

  Widget _repetitionSection(AppState app, DriveSession s, AppL10n t) =>
      iosSection(
        header: t.grpDriveRepetitions,
        children: [
          iosStackedRow(
            child: IosSegmented<bool>(
              value: s.roundTrip,
              onChanged: (v) => app.setDriveField(roundTrip: v),
              segments: [
                IosSegment(value: false, label: t.optDriveOnce),
                IosSegment(value: true, label: t.optDriveBoth),
              ],
            ),
          ),
          asmValueRow(
              app: app,
              label: t.lblDriveCycles,
              controller: _cycles,
              unit: 'ul',
              onChanged: (v) => _commit(
                  _cycles, v, (n) => app.setDriveField(cycles: n.round()))),
        ],
      );

  /// The two options Inventor has and this app does not. See the file header
  /// for why they are drawn rather than removed.
  Widget _unbuiltSection(AppL10n t) => iosSection(
        footer: t.hintDriveUnavailable,
        children: [
          iosSwitchRow(label: t.cbDriveAdaptivity, value: false),
          iosSwitchRow(label: t.cbDriveCollision, value: false),
        ],
      );

  void _commit(
      TextEditingController c, String text, void Function(double) onValue) {
    _shown[c] = text;
    final n = double.tryParse(
        text.replaceAll(RegExp(r'[^0-9eE+\-.,]'), '').replaceAll(',', '.'));
    if (n != null) onValue(n);
  }
}
