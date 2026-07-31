// M172 — a number field you can DRAG.
//
// Tap it and the numeric pad appears; drag left or right across it and the
// value steps in detents whose size follows the zoom (see scrub.dart). The two
// gestures share one field because they are the same intent at different
// precisions: get close by feel, then type the exact number.
//
// Wrapping rather than replacing every TextField is deliberate — the dialogs
// already style their own fields, and a wrapper cannot get that styling wrong.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../scrub.dart';

/// Makes [child] (a TextField driven by [controller]) draggable.
///
/// [onCommit] is called with the formatted text after each detent AND at the
/// end of the drag, so a live preview updates while scrubbing rather than
/// only on release.
class ScrubField extends StatefulWidget {
  final AppState app;
  final TextEditingController controller;
  final Widget child;
  final ValueChanged<String>? onCommit;

  /// Unit suffix to preserve, e.g. 'mm'. A scrub rewrites the number and must
  /// not silently strip the unit the user (or the dialog) put there.
  final String? suffix;

  const ScrubField({
    super.key,
    required this.app,
    required this.controller,
    required this.child,
    this.onCommit,
    this.suffix,
  });

  @override
  State<ScrubField> createState() => _ScrubFieldState();
}

class _ScrubFieldState extends State<ScrubField> {
  double? _start; // value the drag began from
  double _step = 1;
  double _upp = 0.05;
  double _dx = 0;
  bool _live = false;

  /// True while this field holds AppState's live-edit bracket open.
  bool _bracketed = false;

  /// The number currently in the field, or null when it is an expression we
  /// must not clobber. Scrubbing "d0 + 5" would destroy it, so we decline.
  double? _current() {
    final t = widget.controller.text.trim();
    if (t.isEmpty) return 0;
    final stripped =
        t.replaceAll(RegExp(r'(mm|deg|°|ul)\s*$', caseSensitive: false), '')
            .trim()
            .replaceAll(',', '.');
    return double.tryParse(stripped);
  }

  void _begin() {
    _start = _current();
    if (_start == null) return; // an expression: leave it alone
    _upp = widget.app.viewUnitsPerPixel;
    _step = scrubStep(_upp);
    _dx = 0;
    _live = false;
    // M179 — everything this drag applies is real and takes effect at once;
    // it simply is not HISTORY yet, and must not talk. See AppState's live
    // edits: the release below turns both back on for the final value.
    _bracketed = true;
    widget.app.beginLiveEdit();
  }

  void _update(double dx) {
    final start = _start;
    if (start == null) return;
    _dx = dx;
    final v = scrubbedValue(start, _dx, _step, _upp);
    final text = v.toStringAsFixed(scrubDecimals(_step)) +
        (widget.suffix == null ? '' : ' ${widget.suffix}');
    if (text == widget.controller.text) return;
    // A detent was crossed. The tick is what makes it feel mechanical rather
    // than sloppy — on a Pencil it is the only feedback there is.
    HapticFeedback.selectionClick();
    widget.controller.text = text;
    widget.controller.selection =
        TextSelection.collapsed(offset: text.length);
    if (!_live) _live = true;
    widget.onCommit?.call(text);
    setState(() {});
  }

  void _end() {
    final live = _live;
    _start = null;
    _live = false;
    // Journalling and messages come back FIRST, so the final commit below is
    // the one that lands in history and the one allowed to complain. It
    // re-applies the value already showing, so the sketch does not move — it
    // only becomes an undoable step.
    _unbracket();
    if (live) widget.onCommit?.call(widget.controller.text);
  }

  /// Idempotent, and called from dispose as well: a field torn down mid-drag
  /// (the dialog closes, the dimension is deleted) would otherwise leave the
  /// journal switched off for the rest of the session.
  void _unbracket() {
    if (!_bracketed) return;
    _bracketed = false;
    widget.app.endLiveEdit();
  }

  @override
  void dispose() {
    _unbracket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // deferToChild: a tap still reaches the TextField and opens the keyboard.
      // Only a HORIZONTAL drag is claimed, which on touch and Pencil does not
      // compete with anything the field itself wants — text selection there
      // begins with a long-press, not a drag.
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragStart: (_) => _begin(),
      onHorizontalDragUpdate: (d) => _update(_dx + d.delta.dx),
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: _end,
      child: MouseRegion(
        // The affordance. On a trackpad there is no other way to know the
        // number is draggable.
        cursor: SystemMouseCursors.resizeLeftRight,
        child: widget.child,
      ),
    );
  }
}
