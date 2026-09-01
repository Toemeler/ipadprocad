// M242 — Inventor's PLACE CONSTRAINT dialog.
//
// Inventor's own layout is a Win32 grid: a tab strip, two bordered group
// boxes side by side (Type | Selections), a value field with two picture
// checkboxes under it, a Solution box, and ? OK Cancel Apply >> along the
// bottom.
//
//   ┌ Place Constraint ───────────────────────── ✕ ┐
//   │ [Assembly] Motion  Transitional  Constraint  │
//   │ ┌ Type ──────────┐  ┌ Selections ─────────┐  │
//   │ │ ▣ △ ◑ ⧉ ⧊     │  │ [↖1][↖2]   ☐ ▣     │  │
//   │ └────────────────┘  └─────────────────────┘  │
//   │  Offset:            ┌ Solution ───────────┐  │
//   │  [0.000 mm      >]  │ [ ][ ]              │  │
//   │  ☑ 👓   ☐ ▦        └─────────────────────┘  │
//   │  [?]   [ OK ] [Cancel] [Apply]        [>>]   │
//   ├──────────────────────────────────────────────┤
//   │  Name  [_________]   ☐ Default to Undirected │
//   └──────────────────────────────────────────────┘
//
// M338 — that grid is gone and the CONTENT is unchanged. What each part
// became, and why:
//
//   * THE TAB STRIP is a segmented control. It was already four labels that
//     select one view of the same panel, which is what a segmented control
//     is for (HIG, Segmented controls: "closely related subviews").
//   * THE TWO NUMBERED SELECTION BUTTONS are pick rows that say what is in
//     them. They were 36 pt boxes reading "↖1" and "↖2" whose three states
//     (armed / filled / empty) were three border colours and whose CONTENT
//     was invisible — you could not tell from the dialog which face you had
//     picked. The row names the occurrence and the geometry.
//   * THE THREE PICTURE CHECKBOXES are switch rows. Pick Part First, Show
//     Preview and Predict were a tick beside a 15 pt glyph, with the words
//     only in a tooltip — which on a touch device is nowhere. Every one of
//     them already had a localised name in the ARB; they wear it now.
//   * THE ">>" DRAWER is a collapsible section. Same button, same content,
//     drawn as iOS draws a section you can fold.
//   * THE "?" IS GONE. It had `onTap: null` from the day it was drawn: this
//     app has no help book to open. See ios_kit.dart on dead controls.
//
// Provenance, because this repo records it: the layout above is a
// transcription of Inventor's dialog; the mapping to iOS is this milestone's.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../ios_design.dart';
import '../scrub.dart';
import '../svg_icons.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';

class ConstraintDialog extends StatefulWidget {
  final AppState app;
  const ConstraintDialog({super.key, required this.app});

  @override
  State<ConstraintDialog> createState() => _ConstraintDialogState();
}

class _ConstraintDialogState extends State<ConstraintDialog> {
  Offset? _pos;
  final _value = TextEditingController();
  final _name = TextEditingController();

  /// What the value field last showed, so a rebuild driven by a viewport pick
  /// does not fight the digits being typed into it.
  String _valueShown = '';

  static const _size = Size(IosMetrics.widePanelWidth, 560);

  @override
  void dispose() {
    _value.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.constraintSession;
    if (s == null) return const SizedBox.shrink();
    final t = L.of(context);

    // The value field is driven from the session (Predict writes into it, and
    // so does switching type), except while the user is typing.
    final want = _formatValue(s.value, s.kind);
    if (want != _valueShown) {
      _valueShown = want;
      _value.text = want;
    }
    if (_name.text != s.name) _name.text = s.name;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: t.dlgPlaceConstraint,
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
          _tabs(app, s, t),
          _typeSection(app, s, t),
          _selectionSection(app, s, t),
          _valueSection(app, s, t),
          _solutionSection(app, s, t),
          if (s.rejection != null)
            iosStatusLine(app.constraintRejectionText(s.rejection!)),
          _drawer(app, s, t),
        ],
      ),
    );
  }

  // ---- the four tabs -------------------------------------------------------

  Widget _tabs(AppState app, ConstraintSession s, AppL10n t) => Padding(
        padding: const EdgeInsets.fromLTRB(
            IosMetrics.cardInset, 12, IosMetrics.cardInset, 0),
        child: IosSegmented<AsmTab>(
          value: s.tab,
          onChanged: app.setConstraintTab,
          segments: [
            IosSegment(value: AsmTab.assembly, label: t.tabAsmAssembly),
            IosSegment(value: AsmTab.motion, label: t.tabAsmMotion),
            IosSegment(
                value: AsmTab.transitional, label: t.tabAsmTransitional),
            IosSegment(
                value: AsmTab.constraintSet, label: t.tabAsmConstraintSet),
          ],
        ),
      );

  // ---- Type ----------------------------------------------------------------

  Widget _typeSection(AppState app, ConstraintSession s, AppL10n t) {
    final kinds = switch (s.tab) {
      AsmTab.assembly => kAssemblyKinds,
      AsmTab.motion => kMotionKinds,
      AsmTab.transitional => const [AsmKind.transitional],
      // The Constraint Set tab is Inventor's UCS-to-UCS constraint, which this
      // app has no UCS to offer yet. Drawn empty rather than hidden: the tab
      // exists, and a tab that vanishes teaches the user the wrong shape.
      AsmTab.constraintSet => const <AsmKind>[],
      // M249 — unreachable: this panel is only mounted for the four tabs
      // above, and main.dart shows JointDialog for the fifth. Written out
      // rather than defaulted so that a SEVENTH tab could not silently land
      // here and draw a joint's types on the wrong dialog.
      AsmTab.joint => const <AsmKind>[],
    };
    if (kinds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: IosMetrics.sectionTop),
        child: iosNote(t.hintAsmConstraintSet),
      );
    }
    return iosSection(
      header: t.grpAsmType,
      children: [
        iosStackedRow(
          child: IosToggleGroup<AsmKind>(
            value: s.kind,
            onChanged: app.setConstraintKind,
            segments: [
              for (final k in kinds)
                IosSegment(
                  value: k,
                  icon: iosSvg(AC[_typeIcon(k)]!, 24),
                  tooltip: constraintLabel(t, k),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _typeIcon(AsmKind k) => switch (k) {
        AsmKind.mate => 'mate',
        AsmKind.angle => 'angle',
        AsmKind.tangent => 'tangent',
        AsmKind.insert => 'insert',
        AsmKind.symmetry => 'symmetry',
        AsmKind.rotation => 'rotation',
        AsmKind.rotationTranslation => 'rotationTranslation',
        AsmKind.transitional => 'transitional',
        // M249 — the joint kinds never reach this dialog's Type row; see
        // [_typeSection]. Answering with the transitional glyph rather than
        // throwing, because a `!` on a null lookup here would take the whole
        // ribbon down (M115's failure), and a wrong picture on a row that is
        // never drawn costs nothing.
        _ => 'transitional',
      };

  // ---- Selections ----------------------------------------------------------

  Widget _selectionSection(AppState app, ConstraintSession s, AppL10n t) =>
      iosSection(
        header: t.grpAsmSelections,
        children: [
          for (var i = 0; i < s.needed; i++) selectionRow(app, s, t, i),
          iosSwitchRow(
            label: t.cbAsmPickPartFirst,
            value: s.pickPartFirst,
            onChanged: (_) => app.toggleConstraintPickPartFirst(),
          ),
        ],
      );

  // ---- the value, and the two options under it -----------------------------

  Widget _valueSection(AppState app, ConstraintSession s, AppL10n t) {
    final kind = valueKindOf(s.kind);
    return iosSection(
      children: [
        // A kind with no value still shows the row, dimmed: the panel must not
        // change height when the type changes, or the buttons move out from
        // under the finger halfway through choosing one.
        iosValueRow(
          app: app,
          label: _valueLabel(t, kind),
          controller: _value,
          unit: _valueSuffix(kind),
          enabled: kind != AsmValueKind.none,
          onChanged: (v) => _commitValue(app, v),
        ),
        iosSwitchRow(
          label: t.cbAsmShowPreview,
          value: s.showPreview,
          onChanged: (_) => app.toggleConstraintPreview(),
        ),
        iosSwitchRow(
          label: t.cbAsmPredict,
          value: s.predict,
          onChanged: (_) => app.toggleConstraintPredict(),
        ),
      ],
    );
  }

  void _commitValue(AppState app, String text) {
    _valueShown = text;
    final n = double.tryParse(
        text.replaceAll(RegExp(r'[^0-9eE+\-.,]'), '').replaceAll(',', '.'));
    if (n != null) app.setConstraintValue(n);
  }

  static String _valueLabel(AppL10n t, AsmValueKind k) => switch (k) {
        AsmValueKind.offset => t.lblAsmOffset,
        AsmValueKind.angle => t.lblAsmAngle,
        AsmValueKind.ratio => t.lblAsmRatio,
        AsmValueKind.distancePerTurn => t.lblAsmDistance,
        AsmValueKind.none => t.lblAsmOffset,
      };

  static String _valueSuffix(AsmValueKind k) => switch (k) {
        AsmValueKind.angle => 'deg',
        AsmValueKind.ratio => 'ul',
        _ => 'mm',
      };

  static String _formatValue(double v, AsmKind kind) {
    final unit = _valueSuffix(valueKindOf(kind));
    return unit == 'ul'
        ? v.toStringAsFixed(3)
        : '${v.toStringAsFixed(3)} $unit';
  }

  // ---- Solution ------------------------------------------------------------

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
                  icon: iosSvg(AC[_solutionIcon(sol)]!, 24),
                  tooltip: solutionLabel(t, sol),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _solutionIcon(AsmSolution s) => switch (s) {
        AsmSolution.mate => 'solMate',
        AsmSolution.flush => 'solFlush',
        AsmSolution.directedAngle => 'solDirectedAngle',
        AsmSolution.undirectedAngle => 'solUndirectedAngle',
        AsmSolution.explicitVector => 'solExplicitVector',
        AsmSolution.inside => 'solInside',
        AsmSolution.outside => 'solOutside',
        AsmSolution.opposed => 'solOpposed',
        AsmSolution.aligned => 'solAligned',
        AsmSolution.symmetric => 'solSymmetric',
        AsmSolution.asymmetric => 'solAsymmetric',
        AsmSolution.forward => 'solForward',
        AsmSolution.reverse => 'solReverse',
        AsmSolution.none => 'solNone',
      };

  // ---- Inventor's ">>" drawer ---------------------------------------------

  /// The constraint's NAME, and the one preference Inventor puts behind `>>`.
  ///
  /// Folded by default, which is what `>>` meant; the chevron on the header is
  /// the same button.
  Widget _drawer(AppState app, ConstraintSession s, AppL10n t) => iosSection(
        header: t.lblAsmName,
        open: s.expanded,
        onToggle: app.toggleConstraintExpanded,
        children: [
          // No row label: the section header already says Name, and iOS does
          // not repeat itself.
          iosTextRow(
            controller: _name,
            placeholder: t.hintAsmAutoName,
            onChanged: app.setConstraintName,
          ),
          // Only an Angle has a directed default to opt out of, so the row is
          // drawn for every type and only lives on that one — which is what
          // Inventor does, and why it looks disabled beside a Mate.
          iosSwitchRow(
            label: t.cbAsmDefaultUndirected,
            value: s.defaultUndirected,
            onChanged: s.kind == AsmKind.angle
                ? (_) => app.toggleDefaultUndirected()
                : null,
          ),
        ],
      );
}

// ===========================================================================
// what the three assembly dialogs share
// ===========================================================================
//
// M249 — Place Joint and Drive are transcriptions of dialogs from the same
// family and draw the same controls; a second copy of "what a selection row in
// an assembly dialog looks like" is a second thing to keep in step for
// nothing. They stay HERE, in the file that first needed them, rather than
// moving to a chrome file of their own — ios_kit.dart owns what a control
// looks like, this owns what the assembly dialogs make of it.

/// One numbered selection slot, as a row that says what is in it.
///
/// Three states, and they say three different things — the same three Inventor
/// lights: ARMED is "tap in the viewport now", FILLED reads back the occurrence
/// and the geometry, EMPTY is a placeholder.
Widget selectionRow(
    AppState app, ConstraintSession s, AppL10n t, int i) {
  final ref = s.slot(i);
  return iosPickRow(
    label: t.tipAsmSelection(i + 1),
    value: ref == null ? null : '${ref.occurrence} · ${ref.label}',
    hint: t.hintAsmPickGeometry,
    armed: s.armed == i,
    filled: ref != null,
    onTap: () => app.armConstraintSelection(i),
  );
}

/// The number field the Place Constraint and Place Joint dialogs share.
///
/// Both hold a value WITH its unit in the text ("0.000 mm"), which is what
/// [ScrubField.suffix] is for; see ios_kit.dart on why a drawn unit and a
/// scrub suffix are not the same argument.
Widget asmValueRow({
  required AppState app,
  required String label,
  required TextEditingController controller,
  required String unit,
  required ValueChanged<String> onChanged,
  bool enabled = true,
}) =>
    iosValueRow(
      app: app,
      label: label,
      controller: controller,
      unit: unit,
      kind: scrubKindForUnit(unit),
      enabled: enabled,
      onChanged: onChanged,
    );
