// M172 — a number field you can DRAG.
//
// Tap it and the numeric pad appears; drag left or right across it and the
// value steps in detents whose size follows the zoom (see scrub.dart). The two
// gestures share one field because they are the same intent at different
// precisions: get close by feel, then type the exact number.
//
// Wrapping rather than replacing every TextField is deliberate — the dialogs
// already style their own fields, and a wrapper cannot get that styling wrong.
//
// M180 — EVERY number field in the app is wrapped in one of these now. That is
// the point: "can I drag this one?" must never be a question the user has to
// ask, and the answer was previously no for the pattern counts, the gear
// parameters, the 2D fillet radius, the text height, the Parameters window and
// the insert prompts. A field's detent follows what it MEASURES ([kind]), so a
// tooth count steps by one and a pressure angle by a degree, while lengths go
// on following the zoom.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../menus.dart';
import '../scrub.dart';
import 'value_pad.dart';

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
  ///
  /// Only when the unit is part of the TEXT. A field that renders it as
  /// decoration (`suffixText:`) holds a bare number and must keep holding one,
  /// or its own parse stops recognising what the scrub wrote.
  final String? suffix;

  /// M180 — what the number measures, which decides the detent. Defaults to a
  /// length because that is what most of them are.
  final ScrubKind kind;

  /// Range the scrub may not leave. A pattern of zero occurrences and a gear
  /// with minus four teeth are not values the drag should be able to reach —
  /// the dialogs clamp their own input, but a field showing "-4" while the
  /// model holds 4 is a lie about what is going on.
  final double? min, max;

  /// M206 — what the pad's OK key means, when it means more than "done
  /// typing". With no software keyboard there is no Return key on touch, so
  /// any field that used to commit on `onSubmitted` has to be given the same
  /// exit here — the inline dimension editor above all. Null falls back to
  /// committing the text and dropping focus, which is what a dialog field with
  /// its own OK button wants.
  final VoidCallback? onDone;

  /// M206 — show the app's own [ValuePad] while this field has focus.
  ///
  /// True for numbers, which is nearly everything wrapped in a ScrubField.
  /// False for the Parameters window's Equation cell, which is expression-
  /// first: names, functions, references to other parameters. A pad with no
  /// letters is the wrong tool there, and M171 already said so about the
  /// system keyboard for exactly the same reason.
  final bool pad;

  const ScrubField({
    super.key,
    required this.app,
    required this.controller,
    required this.child,
    this.onCommit,
    this.suffix,
    this.kind = ScrubKind.length,
    this.min,
    this.max,
    this.pad = true,
    this.onDone,
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
    final view = widget.app.viewUnitsPerPixel;
    _step = scrubStepFor(widget.kind, view);
    _upp = scrubUnitsPerPixel(widget.kind, view);
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
    var v = scrubbedValue(start, _dx, _step, _upp);
    if (widget.min != null && v < widget.min!) v = widget.min!;
    if (widget.max != null && v > widget.max!) v = widget.max!;
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
    _hidePad();
    super.dispose();
  }

  // ---- M206: the app's own number pad ----

  OverlayEntry? _padEntry;
  bool _padWanted = false;

  /// True when this field's value may be negative. A pattern count and a tooth
  /// count may not; an offset, a taper and a profile shift may. [ScrubField.min]
  /// already carries that fact for the scrub, so the pad reads it from there
  /// rather than growing a second flag that could disagree with the first.
  bool get _signed => (widget.min ?? -1) < 0;

  /// Focus can change DURING a build (a dialog that autofocuses its first
  /// field does exactly that), and inserting an overlay entry mid-build
  /// throws. So the request is recorded and served after the frame — by which
  /// time the field has a laid-out box to anchor to as well.
  void _showPad() {
    if (!widget.pad || !mounted) return;
    _padWanted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_padWanted || _padEntry != null || !mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;
      final anchor = box.localToGlobal(Offset.zero) & box.size;
      _padEntry = OverlayEntry(
        builder: (_) => ValuePadOverlay(
          anchor: anchor,
          signed: _signed,
          onKey: _onPadKey,
        ),
      );
      overlay.insert(_padEntry!);
      // Clicking anywhere else takes it down, including on the native chrome
      // that no Flutter barrier can see (M205).
      OpenMenus.register(_hidePad);
    });
  }

  void _hidePad() {
    _padWanted = false;
    OpenMenus.unregister(_hidePad);
    _padEntry?.remove();
    _padEntry = null;
  }

  void _onPadKey(PadKey key) {
    if (key == PadKey.done) {
      _hidePad();
      final done = widget.onDone;
      if (done != null) {
        done();
      } else {
        widget.onCommit?.call(widget.controller.text);
        FocusManager.instance.primaryFocus?.unfocus();
      }
      return;
    }
    final next = applyValueKey(widget.controller.value, key);
    if (next == widget.controller.value) return;
    if (_outOfRange(next.text)) return;
    widget.controller.value = next;
    widget.onCommit?.call(next.text);
  }

  /// Refuses a keystroke that would take the field outside [ScrubField.min] /
  /// [ScrubField.max] — the same clamp the drag obeys. A half-typed number is
  /// not judged: "" and "-" are on the way to something.
  bool _outOfRange(String text) {
    final t = text.trim();
    if (t.isEmpty || t == '-' || t == '.' || t == '-.') return false;
    final v = double.tryParse(t.replaceAll(',', '.'));
    if (v == null) return false;
    if (widget.min != null && v < widget.min!) return true;
    if (widget.max != null && v > widget.max!) return true;
    return false;
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
        // M206 — the pad follows FOCUS, not taps: a field reached with Tab, or
        // one the dialog focuses itself when it opens, gets it too. The node
        // takes no focus of its own (canRequestFocus: false) so it cannot come
        // between the finger and the TextField underneath.
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (has) => has ? _showPad() : _hidePad(),
          child: widget.child,
        ),
      ),
    );
  }
}
