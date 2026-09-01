// M249 — Inventor's PLACE JOINT dialog.
//
// A sibling of constraint_dialog.dart in every respect that matters, and it
// borrows that file's rows rather than redrawing them. What is different is
// what the dialog SAYS:
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
//   * THE TYPES ARE PICTURES, with their names in the tooltips. Inventor's are
//     pictures and this is the same question asked twice.
//   * IT SAYS WHAT AUTOMATIC DECIDED. Inventor's Automatic resolves silently
//     and you find out by looking at the browser afterwards. The resolution is
//     free here (see AppState._resolveAutomaticJointKind), so the panel names
//     it as soon as the second origin lands.
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
//
// M338 — drawn as an iOS panel; see constraint_dialog.dart for what each of
// Inventor's parts became and why. The verdict lines — what Automatic chose
// and how many degrees of freedom are left — are the Type section's FOOTER,
// which is where iOS puts a sentence that explains the rows above it.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../asm_joint.dart';
import '../ios_design.dart';
import '../svg_icons.dart';
import 'constraint_dialog.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';

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

  static const _size = Size(IosMetrics.widePanelWidth, 520);

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
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: t.dlgPlaceJoint,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelConstraint),
          trailing: IosBarButton(
              label: t.ok,
              prominent: true,
              onTap: s.complete ? app.okConstraint : null),
        ),
        footer: iosFooter(children: [
          Expanded(
            child: IosButton(
              label: t.apply,
              style: IosButtonStyle.tinted,
              height: 38,
              expand: true,
              onTap: s.complete ? () => app.applyConstraint() : null,
            ),
          ),
        ]),
        children: [
          _typeSection(app, s, t),
          _connectSection(app, s, t),
          _solutionSection(app, s, t),
          if (s.rejection != null)
            iosStatusLine(app.constraintRejectionText(s.rejection!)),
        ],
      ),
    );
  }

  // ---- Type ----------------------------------------------------------------

  Widget _typeSection(AppState app, ConstraintSession s, AppL10n t) =>
      iosSection(
        header: t.grpAsmType,
        // Two sentences, always both: the panel must not change height when
        // the type does, or OK moves out from under the finger halfway
        // through choosing one.
        footer: '${s.jointType == AsmJointType.automatic ? t.hintAsmJointAuto(jointTypeLabel(t, jointTypeOf(s.kind))) : ''}'
            '${s.jointType == AsmJointType.automatic ? '\n' : ''}'
            '${t.hintAsmJointDof(jointDof(s.kind))}',
        children: [
          iosStackedRow(
            child: IosToggleGroup<AsmJointType>(
              value: s.jointType,
              onChanged: app.setJointType,
              segments: [
                for (final j in AsmJointType.values)
                  IosSegment(
                    value: j,
                    icon: iosSvg(AC[_typeIcon(j)]!, 24),
                    tooltip: jointTypeLabel(t, j),
                  ),
              ],
            ),
          ),
        ],
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

  Widget _connectSection(AppState app, ConstraintSession s, AppL10n t) =>
      iosSection(
        header: t.grpAsmConnect,
        children: [
          // Deliberately the Place Constraint dialog's selection rows: it is
          // the same gesture (arm, then point), the same three states and the
          // same wording, so a user who has placed one constraint already
          // knows how to place a joint.
          for (var i = 0; i < s.needed; i++) selectionRow(app, s, t, i),
          asmValueRow(
            app: app,
            label: t.lblAsmGap,
            controller: _gap,
            unit: 'mm',
            onChanged: (v) => _commitGap(app, v),
          ),
        ],
      );

  void _commitGap(AppState app, String text) {
    _gapShown = text;
    final n = double.tryParse(
        text.replaceAll(RegExp(r'[^0-9eE+\-.,]'), '').replaceAll(',', '.'));
    if (n != null) app.setConstraintValue(n);
  }

  // ---- Solution: Inventor's Flip -------------------------------------------

  Widget _solutionSection(AppState app, ConstraintSession s, AppL10n t) {
    final solutions = solutionsFor(s.kind);
    if (solutions.isEmpty) return const SizedBox.shrink();
    return iosSection(
      header: t.grpAsmSolution,
      children: [
        iosStackedRow(
          child: IosToggleGroup<AsmSolution>(
            value: s.solution,
            onChanged: app.setConstraintSolution,
            segments: [
              for (final sol in solutions)
                IosSegment(
                  value: sol,
                  icon: iosSvg(
                      AC[sol == AsmSolution.opposed
                          ? 'solOpposed'
                          : 'solAligned']!,
                      24),
                  tooltip: solutionLabel(t, sol),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
