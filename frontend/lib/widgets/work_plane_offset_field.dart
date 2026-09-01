// M169 — the work plane's VALUE field: Inventor's dynamic input.
//
// M229 — "offset" in the name is history. It edits the one number a work plane
// carries, which is millimetres for an offset plane and degrees for an angled
// one; the plane says which (WorkPlane.valueUnit), so a third editable kind
// lands in one place rather than three.
//
// It appears WITH the drag, carries the live value, and a typed number wins
// over wherever the finger stopped. That order is the whole point of dynamic
// input: the drag gets you close, the number makes it right — so the field is
// never a separate step you have to go looking for.
//
// Deliberately small and anchored near the top of the viewport rather than
// modal: the plane it edits has to stay visible while the value changes, or
// you are typing blind.
//
// M338 — the same bar, drawn with the iOS kit: the panel's material and its
// superellipse corners, a value well rather than an outlined Material field,
// and OK / Cancel as a filled and a plain iOS button. It keeps its shape — one
// horizontal strip, not a grouped list — because it is dynamic input attached
// to a drag, not a dialog.
import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import '../l10n/fmt.dart';
import '../l10n/l.dart';
import '../part_model.dart' show parseValueExpr;
import 'ios_kit.dart';
import 'scrub_field.dart';
import '../theme.dart';

class WorkPlaneOffsetField extends StatefulWidget {
  final AppState app;
  const WorkPlaneOffsetField({super.key, required this.app});

  @override
  State<WorkPlaneOffsetField> createState() => _WorkPlaneOffsetFieldState();
}

class _WorkPlaneOffsetFieldState extends State<WorkPlaneOffsetField> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  double? _shown;
  bool _bad = false;

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Follows the drag: while the user is dragging, the field shows the live
  /// distance. It stops following the moment they start typing, so a drag
  /// cannot overwrite what is being entered.
  void _syncFromModel() {
    final w = widget.app.selectedWorkPlane;
    // M229 — the plane's ONE number: mm for an offset, degrees for an angle.
    final v = w?.value;
    if (v == null || _focus.hasFocus) return;
    if (_shown != null && (_shown! - v).abs() < 1e-9) return;
    _shown = v;
    _c.text = Fmt.fixed(v, 2);
    _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
  }

  void _commit() {
    if (widget.app.commitWorkPlaneOffset(_c.text)) {
      setState(() => _bad = false);
    } else {
      setState(() => _bad = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final w = app.selectedWorkPlane;
    if (w == null || !app.workPlaneOffsetEditing) return const SizedBox.shrink();
    _syncFromModel();
    // M178 anchored this to the RIBBON, because the ribbon floated over this
    // same coordinate space (M146) and `top: 14` put the field UNDERNEATH the
    // glass — on the device, a smear of blurred shapes inside the ribbon.
    //
    // M290 — `top: 14` is correct again, and cannot come back: the band takes
    // a row of the layout, so the top of this Stack is already the top of what
    // is left after it.
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: Center(
        child: IosPanel(
          width: 460,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(children: [
                Flexible(
                  child: Text(L.of(context).lblWorkPlaneOffset(w.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IosText.subheadline.on(IosColors.secondaryLabel)),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  // M172 — this one is draggable too, so the plane can be
                  // scrubbed from the field as well as in the viewport.
                  child: ScrubField(
                    app: app,
                    controller: _c,
                    onCommit: (t) {
                      final v = parseValueExpr(t);
                      if (v != null) app.updateWorkPlaneDragAbsolute(v);
                    },
                    // M206 — the pad's OK is Enter, because on touch there is
                    // no Enter (see the Shortcuts block below for the hardware
                    // one).
                    onDone: _commit,
                    child: Shortcuts(
                      // M170 — Magic Keyboard. Esc cancels, Enter commits (via
                      // onSubmitted), and the arrows nudge the value the way
                      // Inventor does — shift for the coarse step, the same
                      // convention as everywhere else here. The arrows are
                      // bound ON the field because that is where focus is: the
                      // field autofocuses the moment a drag begins, so the
                      // keyboard is live without a second click.
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.escape):
                            _CancelIntent(),
                        SingleActivator(LogicalKeyboardKey.arrowUp):
                            _NudgeIntent(1, false),
                        SingleActivator(LogicalKeyboardKey.arrowDown):
                            _NudgeIntent(-1, false),
                        SingleActivator(LogicalKeyboardKey.arrowUp,
                            shift: true): _NudgeIntent(1, true),
                        SingleActivator(LogicalKeyboardKey.arrowDown,
                            shift: true): _NudgeIntent(-1, true),
                      },
                      child: Actions(
                        actions: {
                          _CancelIntent: CallbackAction<_CancelIntent>(
                              onInvoke: (_) => app.cancelWorkPlaneOffset()),
                          _NudgeIntent: CallbackAction<_NudgeIntent>(
                              onInvoke: (i) {
                            app.nudgeWorkPlaneOffset(i.steps,
                                coarse: i.coarse);
                            // The field is showing the OLD number until it
                            // re-syncs, and it will not re-sync while it has
                            // focus — so push the new value in directly.
                            final v = app.selectedWorkPlane?.value;
                            if (v != null) {
                              _shown = v;
                              _c.text = Fmt.fixed(v, 2);
                              _c.selection = TextSelection.collapsed(
                                  offset: _c.text.length);
                            }
                            return null;
                          }),
                        },
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: ShapeDecoration(
                            color: IosColors.quaternarySystemFill,
                            shape: IosShape.border(
                              IosMetrics.controlRadius,
                              side: _bad
                                  ? BorderSide(
                                      color: IosColors.destructive, width: 1)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _c,
                                focusNode: _focus,
                                autofocus: true,
                                textAlign: TextAlign.right,
                                keyboardType: kValueKeyboard,
                                // M179 — the Pencil scrubs this field; it does
                                // not write on it.
                                stylusHandwritingEnabled: kValueHandwriting,
                                autocorrect: false,
                                enableSuggestions: false,
                                cursorColor: IosColors.tint,
                                style:
                                    IosText.subheadline.on(IosColors.label),
                                decoration: const InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding:
                                        EdgeInsets.symmetric(vertical: 8)),
                                onSubmitted: (_) => _commit(),
                              ),
                            ),
                            const SizedBox(width: 5),
                            // M229 — the unit the PLANE says, not a constant:
                            // this one field now edits an offset in mm or an
                            // angle in degrees.
                            Text(w.valueUnit,
                                style: IosText.subheadline
                                    .on(IosColors.secondaryLabel)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IosButton(
                    label: L.of(context).ok,
                    style: IosButtonStyle.filled,
                    height: 34,
                    onTap: _commit),
                const SizedBox(width: 6),
                IosButton(
                    label: L.of(context).cancel,
                    height: 34,
                    onTap: app.cancelWorkPlaneOffset),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

class _NudgeIntent extends Intent {
  final int steps;
  final bool coarse;
  const _NudgeIntent(this.steps, this.coarse);
}
