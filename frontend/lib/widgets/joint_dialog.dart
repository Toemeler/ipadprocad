// M249 — Inventor's PLACE JOINT dialog.
//
// A sibling of constraint_dialog.dart in every respect that matters, and it
// borrows that file's controls rather than redrawing them (asmGroup,
// asmIconButton, asmFlatButton, asmPanelCard). What is different is what the
// dialog SAYS:
//
//   ┌ Place Joint ───────────────────────────── ✕ ┐
//   │ ┌ Type ───────────────┐ ┌ Connect ────────┐ │
//   │ │ ▣ ◈ ⊙ ⇄ ⌾ ▱ ●     │ │ [↖1][↖2]        │ │
//   │ └─────────────────────┘ │ Gap [0.000 mm >]│ │
//   │  Automatic: Rotational  └─────────────────┘ │
//   │  1 degree of freedom left                   │
//   │ ┌ Solution ─┐                               │
//   │ │ [ ][ ]    │                               │
//   │ └───────────┘                               │
//   │  [?]   [ OK ] [Cancel] [Apply]              │
//   └─────────────────────────────────────────────┘
//
// Three things about it are decisions rather than transcription:
//
//   * THE TYPE ROW IS SEVEN ICONS, not Inventor's dropdown. A dropdown on a
//     touch device costs a tap to open, a tap to choose and a look to read;
//     the Place Constraint dialog next door already puts its types in a row of
//     pictures and this is the same question asked twice. The names are in the
//     tooltips, where that dialog puts its own.
//
//   * IT SAYS WHAT AUTOMATIC DECIDED. Inventor's Automatic resolves silently
//     and you find out by looking at the browser afterwards. The resolution is
//     free here (see AppState._resolveAutomaticJointKind), so the line under
//     the Type group names it as soon as the second origin lands.
//
//   * IT SAYS HOW MUCH FREEDOM IS LEFT, which is the one number that tells a
//     Slider from a Cylindrical without reading the manual — and it is not a
//     decoration: asm_joint.jointDof is the same table the solver's residuals
//     are built from, and m249_joint_test asserts it against the rank of the
//     real Jacobian.
//
// Like Place Constraint it is MODELESS and holds no selection: the session is
// AppState.constraintSession on AsmTab.joint (see ConstraintSession.jointType
// for why the two commands share one), the viewport writes into it, and this
// panel is a view of it.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../asm_joint.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';
import '../scrub.dart';
import '../svg_icons.dart';
import '../theme.dart';
import 'constraint_dialog.dart';
import 'dialog_dock.dart';
import 'ribbon.dart' show svg;
import 'scrub_field.dart';

class JointDialog extends StatefulWidget {
  final AppState app;
  const JointDialog({super.key, required this.app});

  @override
  State<JointDialog> createState() => _JointDialogState();
}

class _JointDialogState extends State<JointDialog> {
  Offset? _pos;
  final _gap = TextEditingController();

  /// What the gap field last showed, so a rebuild driven by a viewport pick
  /// does not fight the digits being typed into it. constraint_dialog's rule,
  /// and it is here for the same reason: every pick rebuilds this panel.
  String _gapShown = '';

  static const _size = Size(430, 268);

  @override
  void dispose() {
    _gap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.constraintSession;
    if (s == null || !s.isJoint) return const SizedBox.shrink();
    final t = L.of(context);

    final want = '${s.value.toStringAsFixed(3)} mm';
    if (want != _gapShown) {
      _gapShown = want;
      _gap.text = want;
    }

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: asmPanelCard(width: _size.width, children: [
        asmTitleBar(t.dlgPlaceJoint,
            onClose: app.cancelConstraint,
            onDrag: (d) => setState(() {
                  _pos = (_pos ?? DialogDock.spot(vp, _size)) + d;
                })),
        // The Type row gets the WHOLE width. Seven 32 pt buttons and their
        // gaps are 242 pt, which does not fit beside anything at this dialog's
        // width — sharing the row wrapped Ball onto a second line by itself,
        // which read as a separate control rather than as the last of a set.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: _typeGroup(app, s, t),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _connectGroup(app, s, t)),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _solutionGroup(app, s, t),
                    const SizedBox(height: 8),
                    _verdict(s, t),
                  ]),
            ),
          ]),
        ),
        if (s.rejection != null) _rejection(app, s),
        _footer(app, s, t),
      ]),
    );
  }

  // ---- Type ----------------------------------------------------------------

  Widget _typeGroup(AppState app, ConstraintSession s, AppL10n t) => asmGroup(
        t.grpAsmType,
        Wrap(spacing: 3, runSpacing: 3, children: [
          for (final j in AsmJointType.values)
            asmIconButton(
              icon: AC[_typeIcon(j)]!,
              on: s.jointType == j,
              tip: jointTypeLabel(t, j),
              onTap: () => app.setJointType(j),
            ),
        ]),
      );

  static String _typeIcon(AsmJointType j) => switch (j) {
        AsmJointType.automatic => 'jtAutomatic',
        AsmJointType.rigid => 'jtRigid',
        AsmJointType.rotational => 'jtRotational',
        AsmJointType.slider => 'jtSlider',
        AsmJointType.cylindrical => 'jtCylindrical',
        AsmJointType.planar => 'jtPlanar',
        AsmJointType.ball => 'jtBall',
      };

  // ---- Connect: the two origins, and the gap -------------------------------

  Widget _connectGroup(AppState app, ConstraintSession s, AppL10n t) => asmGroup(
        t.grpAsmConnect,
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(spacing: 3, runSpacing: 3, children: [
                for (var i = 0; i < s.needed; i++) _originButton(app, s, t, i),
              ]),
              const SizedBox(height: 6),
              Text(t.lblAsmGap,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(11, T.dim)),
              const SizedBox(height: 3),
              _gapField(app),
            ]),
      );

  /// The origin pickers. Deliberately the Place Constraint dialog's numbered
  /// selection buttons: it is the same gesture (arm, then point), the same
  /// three states, and the same icon, so a user who has placed one constraint
  /// already knows how to place a joint.
  Widget _originButton(AppState app, ConstraintSession s, AppL10n t, int i) {
    final filled = s.slot(i) != null;
    final armed = s.armed == i;
    return Tooltip(
      message: t.tipAsmSelection(i + 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => app.armConstraintSelection(i),
        child: Container(
          width: 36,
          height: 30,
          decoration: BoxDecoration(
            color: armed
                ? T.accent.withValues(alpha: 0.28)
                : (filled ? T.fly : Colors.transparent),
            border: Border.all(color: armed ? T.accent : T.panelSep),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            svg(asmSelectionIcon, 14),
            const SizedBox(width: 1),
            Text('${i + 1}',
                style: ts(11, filled ? T.accent : T.dim,
                    w: filled ? FontWeight.w600 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }

  Widget _gapField(AppState app) {
    final row = Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: T.fly,
        border: Border.all(color: T.panelSep),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _gap,
            keyboardType: kValueKeyboard,
            stylusHandwritingEnabled: kValueHandwriting,
            autocorrect: false,
            enableSuggestions: false,
            style: ts(12.5, T.text),
            decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.only(bottom: 10)),
            onChanged: (v) => _commitGap(app, v),
          ),
        ),
      ]),
    );
    return ScrubField(
      app: app,
      controller: _gap,
      suffix: 'mm',
      kind: scrubKindForUnit('mm'),
      onCommit: (v) => _commitGap(app, v),
      child: row,
    );
  }

  void _commitGap(AppState app, String text) {
    _gapShown = text;
    final n = double.tryParse(
        text.replaceAll(RegExp(r'[^0-9eE+\-.,]'), '').replaceAll(',', '.'));
    if (n != null) app.setConstraintValue(n);
  }

  // ---- what the dialog is about to make ------------------------------------

  /// The resolved type and the freedom it leaves.
  ///
  /// Always two lines tall, whether or not Automatic is chosen: the panel must
  /// not change height when the type does, or the OK button moves out from
  /// under the finger halfway through choosing one. Same rule the Place
  /// Constraint dialog states about its value row.
  Widget _verdict(ConstraintSession s, AppL10n t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 16,
            child: s.jointType == AsmJointType.automatic
                ? Text(
                    t.hintAsmJointAuto(
                        jointTypeLabel(t, jointTypeOf(s.kind))),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(11, T.accent))
                : null,
          ),
          Text(t.hintAsmJointDof(jointDof(s.kind)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ts(11, T.dim)),
        ],
      );

  // ---- Solution: Inventor's Flip -------------------------------------------

  Widget _solutionGroup(AppState app, ConstraintSession s, AppL10n t) => asmGroup(
        t.grpAsmSolution,
        Wrap(spacing: 3, runSpacing: 3, children: [
          for (final sol in solutionsFor(s.kind))
            asmIconButton(
              icon: AC[sol == AsmSolution.opposed ? 'solOpposed' : 'solAligned']!,
              on: s.solution == sol,
              tip: solutionLabel(t, sol),
              onTap: () => app.setConstraintSolution(sol),
            ),
        ]),
      );

  Widget _rejection(AppState app, ConstraintSession s) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(children: [
          svg(asmSickIcon, 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(app.constraintRejectionText(s.rejection!),
                style: ts(11, T.err)),
          ),
        ]),
      );

  Widget _footer(AppState app, ConstraintSession s, AppL10n t) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          asmFlatButton('?', null, width: 26),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                asmFlatButton(t.ok, s.complete ? app.okConstraint : null,
                    primary: true),
                const SizedBox(width: 6),
                asmFlatButton(t.cancel, app.cancelConstraint),
                const SizedBox(width: 6),
                asmFlatButton(
                    t.apply, s.complete ? () => app.applyConstraint() : null),
              ]),
            ),
          ),
          const SizedBox(width: 26),
        ]),
      );
}
