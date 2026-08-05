// M206 — the number pad, ours, everywhere.
//
// THE REPORT
// ----------
// "When I change the number in this circular pattern window a really small
// number input field is used instead of the whole keyboard. But in every
// dimension input field the whole keyboard comes. Can you change this so this
// small number input field is used everywhere for dimensions and all other
// numbers too instead of the keyboard."
//
// "Also the number input field on circular pattern spawns a little bit too
// high — the arrow of it should be right under the number field."
//
// WHY THE TWO FIELDS BEHAVED DIFFERENTLY
// --------------------------------------
// Nothing to do with the dialogs. It is one flag, on the keyboard type:
//
//     TextInputType.numberWithOptions(signed: true,  decimal: true)  // dimensions
//     TextInputType.numberWithOptions(signed: false, decimal: true)  // pattern
//
// iOS maps `signed: true` to `UIKeyboardTypeNumbersAndPunctuation`, which is
// the FULL keyboard, and an unsigned one to the keypad. `kValueKeyboard` — the
// constant every dimension field uses — asked for signed, because an offset
// can be negative. So the app got a third of the screen of QWERTY to type
// "12", exactly as reported.
//
// WHY WE DRAW IT OURSELVES INSTEAD OF FLIPPING THAT FLAG
// -----------------------------------------------------
// Flipping it fixes the first sentence and leaves the second one impossible.
// The system keypad's position is Apple's to choose; it takes it from the
// caret rectangle, and Flutter only reports caret rectangles when Scribble is
// on — which M179 turned OFF for number fields on purpose, because Scribble
// steals the Pencil stroke that the SCRUB (M172) needs. So with the app's own
// rules in place the system pad cannot be told where the number is, and "the
// arrow should be right under the number field" cannot be answered.
//
// It also loses the minus sign: the unsigned keypad has no "-", and offsets,
// tapers and profile shifts are all legitimately negative.
//
// So the pad is ours: it opens under the field it edits with its tail pointing
// at it, it carries its own minus, it never covers a third of the screen, and
// it does not care what iPadOS does next. `kValueKeyboard` becomes
// `TextInputType.none` — the field keeps its caret, its selection and a
// hardware keyboard, and the system simply never raises anything.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One key. [insert] is the text it types; the two specials do their own thing.
enum PadKey {
  k0('0'),
  k1('1'),
  k2('2'),
  k3('3'),
  k4('4'),
  k5('5'),
  k6('6'),
  k7('7'),
  k8('8'),
  k9('9'),
  dot('.'),
  minus('-'),
  backspace(''),
  done('');

  const PadKey(this.insert);
  final String insert;
}

/// Applies [key] to [v] and returns the new value.
///
/// Pure, because this is the part that can be wrong in ways a screenshot never
/// shows: a pad that appends to the end of the text while the caret sits in
/// the middle types the right digits into the wrong number.
///
/// The rules are the ones a CAD number field needs, and no more:
///  * a digit or "." replaces the selection, or inserts at the caret;
///  * a second "." is refused — "1..5" is not a number anyone meant to type;
///  * "-" is a SIGN TOGGLE on the whole value, not a character. It is the only
///    honest reading: a minus in the middle of a number is never wanted, and
///    hunting for position 0 with a fingertip is not a thing to ask of anyone.
TextEditingValue applyValueKey(TextEditingValue v, PadKey key) {
  final text = v.text;
  var sel = v.selection;
  // A field that was never focused reports an invalid selection; treat the
  // caret as being at the end, which is where typing should go.
  if (!sel.isValid) {
    sel = TextSelection.collapsed(offset: text.length);
  }
  final start = sel.start.clamp(0, text.length);
  final end = sel.end.clamp(0, text.length);

  switch (key) {
    case PadKey.done:
      return v;

    case PadKey.minus:
      final negative = text.startsWith('-');
      final body = negative ? text.substring(1) : text;
      final next = negative ? body : '-$body';
      final shift = negative ? -1 : 1;
      return TextEditingValue(
        text: next,
        selection: TextSelection(
          baseOffset: (sel.baseOffset + shift).clamp(0, next.length),
          extentOffset: (sel.extentOffset + shift).clamp(0, next.length),
        ),
      );

    case PadKey.backspace:
      if (start != end) {
        final next = text.replaceRange(start, end, '');
        return TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: start),
        );
      }
      if (start == 0) return v;
      final next = text.replaceRange(start - 1, start, '');
      return TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start - 1),
      );

    default:
      final ch = key.insert;
      final rest = text.replaceRange(start, end, '');
      if (ch == '.' && rest.contains('.')) return v;
      final next = text.replaceRange(start, end, ch);
      return TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + ch.length),
      );
  }
}

/// The pad itself: four columns, four rows, and a tail.
class ValuePad extends StatelessWidget {
  final ValueChanged<PadKey> onKey;

  /// True when the field this pad edits may hold a negative number. The minus
  /// key is drawn dead rather than removed, so the grid never reflows under a
  /// finger that is already on its way to a digit.
  final bool signed;

  const ValuePad({super.key, required this.onKey, this.signed = true});

  /// Geometry, shared with the overlay that positions it.
  ///
  /// [border] is in here because a BoxDecoration's border eats into the
  /// Container's WIDTH rather than adding to it — leave it out and the key row
  /// overflows by exactly two pixels, which is how this was found.
  static const double keyW = 44, keyH = 38, gap = 4, pad = 6, border = 1;
  static const double tail = 7;
  static const double width = 4 * keyW + 3 * gap + 2 * pad + 2 * border;
  static const double height = 4 * keyH + 3 * gap + 2 * pad + 2 * border;

  @override
  Widget build(BuildContext context) {
    Widget k(PadKey key, {String? label, int span = 1, Color? tint}) {
      final dead = key == PadKey.minus && !signed;
      return _PadKeyCap(
        label: label ?? key.insert,
        width: keyW * span + gap * (span - 1),
        enabled: !dead,
        tint: tint,
        onTap: () => onKey(key),
      );
    }

    Widget row(List<Widget> kids) => Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < kids.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              kids[i],
            ]
          ]),
        );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: T.fly,
          border: Border.all(color: T.sep, width: border),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
                color: Color(0x8C000000), blurRadius: 20, offset: Offset(0, 6)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          row([k(PadKey.k7), k(PadKey.k8), k(PadKey.k9),
              k(PadKey.backspace, label: '⌫')]),
          row([k(PadKey.k4), k(PadKey.k5), k(PadKey.k6),
              k(PadKey.minus, label: '±')]),
          row([k(PadKey.k1), k(PadKey.k2), k(PadKey.k3),
              k(PadKey.dot)]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            k(PadKey.k0, span: 2),
            const SizedBox(width: gap),
            k(PadKey.done, label: 'OK', span: 2, tint: T.blue),
          ]),
        ]),
      ),
    );
  }
}

class _PadKeyCap extends StatefulWidget {
  final String label;
  final double width;
  final bool enabled;
  final Color? tint;
  final VoidCallback onTap;
  const _PadKeyCap(
      {required this.label,
      required this.width,
      required this.enabled,
      required this.onTap,
      this.tint});

  @override
  State<_PadKeyCap> createState() => _PadKeyCapState();
}

class _PadKeyCapState extends State<_PadKeyCap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: widget.enabled ? () => setState(() => _down = false) : null,
      onTap: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap();
            }
          : null,
      child: Container(
        width: widget.width,
        height: ValuePad.keyH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint != null
              ? (_down ? tint.withValues(alpha: 0.75) : tint)
              : (_down ? T.hover8 : T.flyHov),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: T.border10),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 17,
            color: widget.enabled
                ? (tint != null ? Colors.white : T.text)
                : T.dim.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// Positions a [ValuePad] under (or, with no room, over) the field it edits,
/// with its tail pointing at the field's centre — which is the whole of the
/// second report: "the arrow of it should be right under the number field".
class ValuePadOverlay extends StatelessWidget {
  /// The field's rectangle in GLOBAL coordinates.
  final Rect anchor;
  final ValueChanged<PadKey> onKey;
  final bool signed;

  const ValuePadOverlay(
      {super.key,
      required this.anchor,
      required this.onKey,
      this.signed = true});

  /// Gap between the field and the tail's tip.
  static const double margin = 4;

  /// Where the pad's top-left corner goes, and whether it hangs below the
  /// anchor. Pure so the arithmetic is tested rather than eyeballed.
  static (Offset, bool) place(Rect anchor, Size screen) {
    const w = ValuePad.width;
    final h = ValuePad.height + ValuePad.tail;
    final below = anchor.bottom + margin + h <= screen.height ||
        anchor.top - margin - h < 0;
    final top = below ? anchor.bottom + margin : anchor.top - margin - h;
    final left = (anchor.center.dx - w / 2)
        .clamp(margin, (screen.width - w - margin).clamp(margin, double.infinity));
    return (Offset(left, top), below);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final (origin, below) = place(anchor, screen);
    // Tail x, relative to the pad's own left edge.
    final tailX = (anchor.center.dx - origin.dx)
        .clamp(14.0, ValuePad.width - 14.0);
    final pad = ValuePad(onKey: onKey, signed: signed);
    final arrow = CustomPaint(
      size: const Size(ValuePad.width, ValuePad.tail),
      painter: _TailPainter(x: tailX, up: below),
    );
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (below) arrow,
        pad,
        if (!below) arrow,
      ]),
    );
  }
}

class _TailPainter extends CustomPainter {
  final double x;
  final bool up;
  const _TailPainter({required this.x, required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    const half = 8.0;
    final path = Path();
    if (up) {
      path.moveTo(x, 0);
      path.lineTo(x - half, size.height);
      path.lineTo(x + half, size.height);
    } else {
      path.moveTo(x, size.height);
      path.lineTo(x - half, 0);
      path.lineTo(x + half, 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = T.fly);
    canvas.drawPath(
        path,
        Paint()
          ..color = T.sep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.x != x || old.up != up;
}
