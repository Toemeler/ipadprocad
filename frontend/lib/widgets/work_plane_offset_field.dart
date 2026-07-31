// M169 — the work plane's offset field: Inventor's dynamic input.
//
// It appears WITH the drag, carries the live value, and a typed number wins
// over wherever the finger stopped. That order is the whole point of dynamic
// input: the drag gets you close, the number makes it right — so the field is
// never a separate step you have to go looking for.
//
// Deliberately small and anchored near the top of the viewport rather than
// modal: the plane it edits has to stay visible while the value changes, or
// you are typing blind.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
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
    final v = w?.offset;
    if (v == null || _focus.hasFocus) return;
    if (_shown != null && (_shown! - v).abs() < 1e-9) return;
    _shown = v;
    _c.text = v.toStringAsFixed(2);
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
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: T.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _bad ? const Color(0xFFE05252) : T.panelSep),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 12, spreadRadius: 1)
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${w.name}  Offset',
                  style: TextStyle(color: T.dim, fontSize: 12)),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape):
                        _CancelIntent(),
                  },
                  child: Actions(
                    actions: {
                      _CancelIntent: CallbackAction<_CancelIntent>(
                          onInvoke: (_) => app.cancelWorkPlaneOffset()),
                    },
                    child: TextField(
                      controller: _c,
                      focusNode: _focus,
                      autofocus: true,
                      style: TextStyle(color: T.text, fontSize: 14),
                      textAlign: TextAlign.right,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      onSubmitted: (_) => _commit(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('mm', style: TextStyle(color: T.dim, fontSize: 12)),
              const SizedBox(width: 10),
              _btn('OK', _commit, primary: true),
              const SizedBox(width: 6),
              _btn('Cancel', app.cancelWorkPlaneOffset),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool primary = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: primary ? T.blue : T.flyHov,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: T.panelSep),
          ),
          child: Text(label,
              style: TextStyle(
                  color: primary ? Colors.white : T.text, fontSize: 12)),
        ),
      );
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}
