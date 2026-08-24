// M242 — Inventor's PLACE CONSTRAINT dialog.
//
// Drawn from the real thing rather than from memory, and its layout is the
// one part of this milestone that is a transcription rather than a design:
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
// Two things about it are worth stating, because they are what make the
// transcription honest rather than decorative:
//
//   * The two checkboxes under the value field, and the one beside the
//     selection buttons, carry a GRAPHIC label and no text — the spectacles
//     for Show Preview, the offset arrows for Predict, the red cursor for
//     Pick Part First. That is exactly what Inventor draws, and a tooltip
//     supplies the name. Widening them into text rows would be a different
//     dialog.
//
//   * The whole thing is MODELESS and collects by pointing. Nothing here
//     holds a selection: [AppState.constraintSession] does, the viewport
//     writes into it, and this panel is a view of it. That is what lets the
//     user orbit, zoom and pick while it is open, which is the only way the
//     command is usable at all.
//
// Chrome from properties_panel.dart / dialog_dock.dart, like every other
// floating panel in this app.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../asm_constraints.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';
import '../scrub.dart';
import '../svg_icons.dart';
import '../theme.dart';
import 'dialog_dock.dart';
import 'ribbon.dart' show svg;
import 'scrub_field.dart';

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

    const w = 372.0;
    final h = s.expanded ? 320.0 : 252.0;
    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, Size(w, h));
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
            boxShadow: [
              BoxShadow(color: T.scrim, blurRadius: 24, offset: Offset(0, 6)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _title(app, t),
            _tabs(app, s, t),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _typeGroup(app, s, t)),
                  const SizedBox(width: 8),
                  Expanded(child: _selectionGroup(app, s, t)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _valueColumn(app, s, t)),
                  const SizedBox(width: 8),
                  Expanded(child: _solutionGroup(app, s, t)),
                ],
              ),
            ),
            if (s.rejection != null) _rejection(app, s),
            _footer(app, s, t),
            if (s.expanded) _drawer(app, s, t),
          ]),
        ),
      ),
    );
  }

  // ---- chrome --------------------------------------------------------------

  Widget _title(AppState app, AppL10n t) => GestureDetector(
        onPanUpdate: (d) => setState(() {
          final vp = MediaQuery.sizeOf(context);
          _pos = (_pos ?? DialogDock.spot(vp, const Size(372, 252))) + d.delta;
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: T.fly,
            border: Border(bottom: BorderSide(color: T.panelSep)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(children: [
            Text(t.dlgPlaceConstraint,
                style: ts(13, T.text, w: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: app.cancelConstraint,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('✕', style: ts(12, T.dim)),
              ),
            ),
          ]),
        ),
      );

  Widget _tabs(AppState app, ConstraintSession s, AppL10n t) => Container(
        height: 26,
        padding: const EdgeInsets.only(left: 8),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: T.panelSep))),
        child: Row(children: [
          for (final (tab, label) in [
            (AsmTab.assembly, t.tabAsmAssembly),
            (AsmTab.motion, t.tabAsmMotion),
            (AsmTab.transitional, t.tabAsmTransitional),
            (AsmTab.constraintSet, t.tabAsmConstraintSet),
          ])
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => app.setConstraintTab(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.tab == tab ? T.panel : Colors.transparent,
                  border: s.tab == tab
                      ? Border(bottom: BorderSide(color: T.accent, width: 2))
                      : null,
                ),
                child: Text(label,
                    style: ts(11.5, s.tab == tab ? T.text : T.dim,
                        w: s.tab == tab
                            ? FontWeight.w600
                            : FontWeight.normal)),
              ),
            ),
        ]),
      );

  /// The bordered, titled box Inventor groups its controls in.
  Widget _group(String title, Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        decoration: BoxDecoration(
          border: Border.all(color: T.panelSep),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: ts(10.5, T.dim)),
              const SizedBox(height: 4),
              child,
            ]),
      );

  // ---- Type ----------------------------------------------------------------

  Widget _typeGroup(AppState app, ConstraintSession s, AppL10n t) {
    final kinds = switch (s.tab) {
      AsmTab.assembly => kAssemblyKinds,
      AsmTab.motion => kMotionKinds,
      AsmTab.transitional => const [AsmKind.transitional],
      // The Constraint Set tab is Inventor's UCS-to-UCS constraint, which this
      // app has no UCS to offer yet. Drawn empty rather than hidden: the tab
      // exists, and a tab that vanishes teaches the user the wrong shape.
      AsmTab.constraintSet => const <AsmKind>[],
    };
    return _group(
      t.grpAsmType,
      kinds.isEmpty
          ? SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t.hintAsmConstraintSet, style: ts(11, T.dim)),
              ),
            )
          : Row(children: [
              for (final k in kinds) ...[
                _iconButton(
                  icon: AC[_typeIcon(k)]!,
                  on: s.kind == k,
                  tip: constraintLabel(t, k),
                  onTap: () => app.setConstraintKind(k),
                ),
                const SizedBox(width: 3),
              ]
            ]),
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
      };

  // ---- Selections ----------------------------------------------------------

  Widget _selectionGroup(AppState app, ConstraintSession s, AppL10n t) =>
      _group(
        t.grpAsmSelections,
        Row(children: [
          for (var i = 0; i < s.needed; i++) ...[
            _selectionButton(app, s, t, i),
            const SizedBox(width: 3),
          ],
          const Spacer(),
          _glyphCheckbox(
            on: s.pickPartFirst,
            icon: asmPickPartIcon,
            tip: t.cbAsmPickPartFirst,
            onTap: app.toggleConstraintPickPartFirst,
          ),
        ]),
      );

  Widget _selectionButton(
      AppState app, ConstraintSession s, AppL10n t, int i) {
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
            // Three states, and they say three different things: ARMED is
            // "tap in the viewport now", FILLED is "this one is done", plain
            // is "not yet". Inventor lights the armed one and ticks the
            // filled one; the tick is the number turning solid here.
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

  // ---- the value field, and the two checkboxes under it --------------------

  Widget _valueColumn(AppState app, ConstraintSession s, AppL10n t) {
    final kind = valueKindOf(s.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_valueLabel(t, kind), style: ts(11, T.dim)),
        const SizedBox(height: 3),
        // A kind with no value still reserves the row: the dialog must not
        // change height when the type changes, or the buttons move out from
        // under the finger halfway through choosing one.
        Opacity(
          opacity: kind == AsmValueKind.none ? 0.4 : 1,
          child: IgnorePointer(
            ignoring: kind == AsmValueKind.none,
            child: _valueField(app, s, kind),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          _glyphCheckbox(
            on: s.showPreview,
            icon: asmPreviewIcon,
            tip: t.cbAsmShowPreview,
            onTap: app.toggleConstraintPreview,
          ),
          const SizedBox(width: 10),
          _glyphCheckbox(
            on: s.predict,
            icon: asmPredictIcon,
            tip: t.cbAsmPredict,
            onTap: app.toggleConstraintPredict,
          ),
        ]),
      ],
    );
  }

  Widget _valueField(AppState app, ConstraintSession s, AsmValueKind kind) {
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
            controller: _value,
            keyboardType: kValueKeyboard,
            stylusHandwritingEnabled: kValueHandwriting,
            autocorrect: false,
            enableSuggestions: false,
            style: ts(12.5, T.text),
            decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.only(bottom: 10)),
            onChanged: (v) => _commitValue(app, v),
          ),
        ),
        // Inventor's ▸, which opens the recent-values list. There is no
        // history to show yet, so it is drawn and inert rather than removed:
        // its absence would make the field look like a different control.
        Text('▸', style: ts(9, T.dim)),
      ]),
    );
    return ScrubField(
      app: app,
      controller: _value,
      suffix: _valueSuffix(kind),
      kind: scrubKindForUnit(_valueSuffix(kind)),
      onCommit: (v) => _commitValue(app, v),
      child: row,
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
    final digits = unit == 'ul' ? 3 : 3;
    return unit == 'ul'
        ? v.toStringAsFixed(digits)
        : '${v.toStringAsFixed(digits)} $unit';
  }

  // ---- Solution ------------------------------------------------------------

  Widget _solutionGroup(AppState app, ConstraintSession s, AppL10n t) =>
      _group(
        t.grpAsmSolution,
        Wrap(spacing: 3, runSpacing: 3, children: [
          for (final sol in solutionsFor(s.kind))
            _iconButton(
              icon: AC[_solutionIcon(sol)]!,
              on: s.solution == sol,
              tip: solutionLabel(t, sol),
              onTap: () => app.setConstraintSolution(sol),
            ),
        ]),
      );

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

  // ---- the refusal line ----------------------------------------------------

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

  // ---- footer --------------------------------------------------------------

  Widget _footer(AppState app, ConstraintSession s, AppL10n t) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(children: [
          _flatButton('?', null, width: 26),
          const Spacer(),
          _flatButton(t.ok, s.complete ? app.okConstraint : null,
              primary: true),
          const SizedBox(width: 6),
          _flatButton(t.cancel, app.cancelConstraint),
          const SizedBox(width: 6),
          _flatButton(t.apply, s.complete ? () => app.applyConstraint() : null),
          const Spacer(),
          _flatButton(s.expanded ? '<<' : '>>', app.toggleConstraintExpanded,
              width: 30),
        ]),
      );

  /// The `>>` drawer: the constraint's NAME, and the one preference Inventor
  /// puts here.
  Widget _drawer(AppState app, ConstraintSession s, AppL10n t) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: T.panelSep))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.lblAsmName, style: ts(11, T.dim)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: T.fly,
                      border: Border.all(color: T.panelSep),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: TextField(
                      controller: _name,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: ts(12.5, T.text),
                      decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: t.hintAsmAutoName,
                          hintStyle: ts(12.5, T.dim),
                          contentPadding: const EdgeInsets.only(bottom: 10)),
                      onChanged: app.setConstraintName,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Only an Angle has a directed default to opt out of, so the
                // box is drawn for every type and only lives on that one —
                // which is what Inventor does, and why it looks disabled
                // beside a Mate.
                Opacity(
                  opacity: s.kind == AsmKind.angle ? 1 : 0.4,
                  child: IgnorePointer(
                    ignoring: s.kind != AsmKind.angle,
                    child: _textCheckbox(
                      on: s.defaultUndirected,
                      label: t.cbAsmDefaultUndirected,
                      onTap: app.toggleDefaultUndirected,
                    ),
                  ),
                ),
              ]),
            ]),
      );

  // ---- small controls ------------------------------------------------------

  Widget _iconButton({
    required String icon,
    required bool on,
    required String tip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 32,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? T.accent.withValues(alpha: 0.28) : Colors.transparent,
              border: Border.all(color: on ? T.accent : T.panelSep),
              borderRadius: BorderRadius.circular(3),
            ),
            child: svg(icon, 22),
          ),
        ),
      );

  /// A checkbox whose LABEL is a picture. Inventor's, and the tooltip is
  /// where the words live.
  Widget _glyphCheckbox({
    required bool on,
    required String icon,
    required String tip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _box(on),
            const SizedBox(width: 4),
            svg(icon, 15),
          ]),
        ),
      );

  Widget _textCheckbox({
    required bool on,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _box(on),
          const SizedBox(width: 5),
          Text(label, style: ts(11, T.text)),
        ]),
      );

  Widget _box(bool on) => Container(
        width: 13,
        height: 13,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? T.accent : T.fly,
          border: Border.all(color: on ? T.accent : T.panelSep),
          borderRadius: BorderRadius.circular(2),
        ),
        child: on
            ? const Icon(Icons.check, size: 10, color: Colors.white)
            : null,
      );

  Widget _flatButton(String label, VoidCallback? onTap,
          {bool primary = false, double width = 62}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: width,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null
                ? T.fly
                : (primary ? T.accent.withValues(alpha: 0.22) : T.fly),
            border: Border.all(
                color: onTap != null && primary ? T.accent : T.panelSep),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label,
              style: ts(12, onTap == null ? T.dim : T.text,
                  w: primary ? FontWeight.w600 : FontWeight.normal)),
        ),
      );
}
