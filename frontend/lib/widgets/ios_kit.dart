// M338 — the controls every tool dialog is drawn with, and nothing else.
//
// This file replaces `properties_panel.dart`, which held the same idea for the
// Inventor transcription: one place for the chrome, so five panels do not
// carry five copies of it. What changed is WHICH interface it draws.
//
// WHAT "iOS NATIVE" MEANS HERE, PRECISELY
// ---------------------------------------
// It does not mean a UIViewController per dialog. These panels are modeless,
// they float over a Flutter-drawn viewport, they are driven field-by-field
// from AppState, and every one of them writes a live preview back into the
// scene as you type. Sixteen platform views with a bidirectional channel each
// would be sixteen new places for the Flutter/UIKit boundary to eat a gesture
// — a bill this project has already paid twice (M48, M102).
//
// It means the platform's DESIGN SYSTEM, drawn in Flutter, to Apple's own
// measurements: the Dynamic Type ramp, 44 pt targets, inset grouped lists,
// sliding segmented controls, switches instead of checkboxes, a navigation bar
// with Cancel leading and the confirming action trailing, superellipse
// corners, and — where the platform can actually supply it — the REAL system
// surface rather than a picture of one:
//
//   * the panel's background is `GlassPanel`, the same UIGlassEffect platform
//     view the ribbon and the model browser have used since M106/M146. On
//     device that is Apple's own material, with Apple's refraction and
//     specular edge. Off iOS it falls back to an opaque panel, exactly as
//     `RibbonSurface` does.
//   * a one-of-many choice with long names opens a real UIMenu through
//     `NativeMenu.menu`, the same call the ribbon's Place Component uses.
//   * the switches and sliders are Flutter's own Cupertino widgets, which are
//     maintained against the system controls.
//
// WHAT DID NOT SURVIVE, AND WHY
// -----------------------------
// Three glyphs in the old title bars — a magnifier, a hamburger and an eye —
// had no `onTap` at all. They were traced from Inventor's window chrome and
// were inert from the day they were drawn. A dead control is worse in this
// idiom than in the one it came from, because iOS teaches that everything in a
// navigation bar is a button; M216 already spent a commit removing one for the
// same reason. They are gone rather than drawn disabled.
//
// The number pad, the scrub and the value keyboard are UNTOUCHED. Every
// numeric field here is still a Flutter [TextField] with [kValueKeyboard]
// inside a [ScrubField] — M172's drag, M179's Pencil rule, M180's contract
// that no number in the app is un-draggable, and M206's own pad all keep
// working, and the test that pins them (m180_every_number_scrubs_test) reads
// the same widget it always did.
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Material, MaterialType, Tooltip, InputDecoration, InputBorder, TextField;
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, HapticFeedback;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../icon_theme.dart';
import '../ios_design.dart';
import '../l10n/l.dart';
import '../scrub.dart';
import '../theme.dart';
import 'scrub_field.dart';

// ===========================================================================
// glyphs
// ===========================================================================

/// The handful of SF Symbols the dialogs need, drawn rather than imported.
///
/// Material's icon font is the wrong alphabet in this idiom: its chevron is
/// heavier and squarer than SF's, and its "cancel" disc has a different
/// weight. These are eight paths; getting them right costs less than looking
/// consistently foreign. Each is drawn on a 1×1 box and scaled by the caller,
/// with a stroke weight that tracks the size the way SF's does.
enum IosGlyph {
  chevronRight,
  chevronDown,
  chevronUp,
  /// `chevron.up.chevron.down` — the pop-up button indicator.
  popup,
  xmark,
  /// `xmark.circle.fill` — a filled clear button.
  xmarkCircleFill,
  plus,
  minus,
  checkmark,
  /// `exclamationmark.circle.fill`
  alert,
  /// `arrow.up.left` — "point at something in the viewport".
  pick,
  play,
  pause,
  backward,
  toStart,
  toEnd,
}

Widget iosGlyph(IosGlyph g, {double size = 15, required Color color}) =>
    SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GlyphPainter(g, color)),
    );

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.g, this.color);
  final IosGlyph g;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // SF's line weight at Regular is about 1/12 of the cap height, and it
      // never goes below a pixel of a hairline.
      ..strokeWidth = math.max(1.0, s * 0.115)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final c = Offset(size.width / 2, size.height / 2);

    void chevron(double turns) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(turns * math.pi / 2);
      final a = s * 0.20, b = s * 0.30;
      canvas.drawPath(
          Path()
            ..moveTo(-a, -b)
            ..lineTo(a, 0)
            ..lineTo(-a, b),
          stroke);
      canvas.restore();
    }

    switch (g) {
      case IosGlyph.chevronRight:
        chevron(0);
      case IosGlyph.chevronDown:
        chevron(1);
      case IosGlyph.chevronUp:
        chevron(-1);
      case IosGlyph.popup:
        // Two half-height chevrons, stacked — UIKit's pull-down indicator.
        canvas.save();
        canvas.translate(c.dx, c.dy - s * 0.22);
        final a = s * 0.22, b = s * 0.13;
        canvas.drawPath(
            Path()
              ..moveTo(-a, b)
              ..lineTo(0, -b)
              ..lineTo(a, b),
            stroke);
        canvas.restore();
        canvas.save();
        canvas.translate(c.dx, c.dy + s * 0.22);
        canvas.drawPath(
            Path()
              ..moveTo(-a, -b)
              ..lineTo(0, b)
              ..lineTo(a, -b),
            stroke);
        canvas.restore();
      case IosGlyph.xmark:
        final r = s * 0.30;
        canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), stroke);
        canvas.drawLine(c + Offset(r, -r), c + Offset(-r, r), stroke);
      case IosGlyph.xmarkCircleFill:
        // The cross is CUT OUT of the disc, so the row's own colour shows
        // through it — which is what `.fill` means in SF Symbols. The clear
        // blend only works inside a layer, and the disc must be drawn INSIDE
        // that layer too: one drawn before it would survive the cut and the
        // glyph would come out a solid dot.
        final r = s * 0.17;
        final cut = Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, s * 0.11)
          ..strokeCap = StrokeCap.round;
        canvas.saveLayer(Offset.zero & size, Paint());
        canvas.drawCircle(c, s * 0.5, fill);
        canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), cut);
        canvas.drawLine(c + Offset(r, -r), c + Offset(-r, r), cut);
        canvas.restore();
      case IosGlyph.plus:
        final r = s * 0.32;
        canvas.drawLine(c + Offset(-r, 0), c + Offset(r, 0), stroke);
        canvas.drawLine(c + Offset(0, -r), c + Offset(0, r), stroke);
      case IosGlyph.minus:
        final r = s * 0.32;
        canvas.drawLine(c + Offset(-r, 0), c + Offset(r, 0), stroke);
      case IosGlyph.checkmark:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - s * 0.30, c.dy + s * 0.02)
              ..lineTo(c.dx - s * 0.08, c.dy + s * 0.24)
              ..lineTo(c.dx + s * 0.31, c.dy - s * 0.25),
            stroke);
      case IosGlyph.alert:
        canvas.saveLayer(Offset.zero & size, Paint());
        canvas.drawCircle(c, s * 0.5, fill);
        final cut = Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, s * 0.12)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
            c + Offset(0, -s * 0.24), c + Offset(0, s * 0.05), cut);
        canvas.drawLine(
            c + Offset(0, s * 0.20), c + Offset(0, s * 0.21), cut);
        canvas.restore();
      case IosGlyph.pick:
        // arrow.up.left
        final tip = c + Offset(-s * 0.28, -s * 0.28);
        canvas.drawLine(tip, c + Offset(s * 0.28, s * 0.28), stroke);
        canvas.drawPath(
            Path()
              ..moveTo(tip.dx, tip.dy + s * 0.34)
              ..lineTo(tip.dx, tip.dy)
              ..lineTo(tip.dx + s * 0.34, tip.dy),
            stroke);
      case IosGlyph.play:
        canvas.drawPath(_triangle(c, s, 1), fill);
      case IosGlyph.backward:
        canvas.drawPath(_triangle(c, s, -1), fill);
      case IosGlyph.pause:
        final w = s * 0.11, h = s * 0.30;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: c + Offset(-s * 0.14, 0), width: w * 2, height: h * 2),
                Radius.circular(w * 0.5)),
            fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: c + Offset(s * 0.14, 0), width: w * 2, height: h * 2),
                Radius.circular(w * 0.5)),
            fill);
      case IosGlyph.toStart:
        canvas.drawPath(_triangle(c + Offset(s * 0.08, 0), s * 0.86, -1), fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: c + Offset(-s * 0.30, 0),
                    width: s * 0.11,
                    height: s * 0.56),
                Radius.circular(s * 0.05)),
            fill);
      case IosGlyph.toEnd:
        canvas.drawPath(_triangle(c - Offset(s * 0.08, 0), s * 0.86, 1), fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: c + Offset(s * 0.30, 0),
                    width: s * 0.11,
                    height: s * 0.56),
                Radius.circular(s * 0.05)),
            fill);
    }
  }

  static Path _triangle(Offset c, double s, double dir) {
    final w = s * 0.28, h = s * 0.32;
    return Path()
      ..moveTo(c.dx - w * dir, c.dy - h)
      ..lineTo(c.dx + w * dir, c.dy)
      ..lineTo(c.dx - w * dir, c.dy + h)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.g != g || old.color != color;
}

/// One of the app's inline SVG icons, recoloured for the active scheme.
///
/// The same two lines `ribbon.dart` has had since M50; repeated here so the
/// dialog kit does not have to import a 128 kB ribbon to draw a 16 pt picture.
Widget iosSvg(String source, double size) =>
    SvgPicture.string(themedIcon(source), width: size, height: size);

// ===========================================================================
// press feedback
// ===========================================================================

/// "Always include a press state for a custom button" — HIG, Buttons.
///
/// One wrapper for every tappable thing in this file, so the feel is the same
/// everywhere and no control can be forgotten. The 0.4 is `CupertinoButton`'s
/// own pressed opacity, and the 100 ms fade is its animation.
///
/// M341 — and one place where every tappable thing becomes a BUTTON to
/// VoiceOver. Wrapping each call site by hand is what the rest of this app
/// does (quick_tools, home_view, the view cube), and the sites it missed are
/// the ones nobody notices, because a `GestureDetector` is silent rather than
/// wrong. Doing it here means a control cannot be added to this file without
/// an accessible one arriving with it.
///
/// [semanticLabel] is for the controls with no text of its own to borrow — a
/// glyph button. Giving one EXCLUDES the child's own semantics, so a labelled
/// control reads once, not twice.
class IosPressable extends StatefulWidget {
  const IosPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.opacity = 0.4,
    this.behavior = HitTestBehavior.opaque,
    this.semanticLabel,
    this.selected,
    this.expanded,
    this.isButton = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double opacity;
  final HitTestBehavior behavior;

  /// Spoken instead of the child, for a control that draws a glyph.
  final String? semanticLabel;

  /// Adds "selected" to the announcement. Null for controls that are not
  /// one-of-a-set — a plain button is never "not selected", it just is.
  final bool? selected;

  /// Reads as "expanded" / "collapsed". For the disclosure headers.
  final bool? expanded;

  /// False for a row that is a container rather than a button, so VoiceOver
  /// does not offer to activate something inert.
  final bool isButton;

  @override
  State<IosPressable> createState() => _IosPressableState();
}

class _IosPressableState extends State<IosPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.onTap != null || widget.onLongPress != null;
    return MergeSemantics(
      child: Semantics(
        button: widget.isButton && live,
        enabled: live,
        label: widget.semanticLabel,
        selected: widget.selected,
        expanded: widget.expanded,
        excludeSemantics: widget.semanticLabel != null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: GestureDetector(
          behavior: widget.behavior,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: live ? (_) => _set(true) : null,
          onTapUp: live ? (_) => _set(false) : null,
          onTapCancel: live ? () => _set(false) : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 100),
            opacity: _down && live ? widget.opacity : 1,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The tick a discrete choice makes.
///
/// M341 — the app has clicked on a crossed scrub detent and a pad key since
/// M172 and M206, and iOS itself clicks on a segmented control, a picker and a
/// switch. The kit was the one part with no feel at all, which reads as the
/// controls being pictures rather than parts.
///
/// Deliberately NOT on plain buttons: iOS leaves Cancel and OK silent, and a
/// tick on every tap stops meaning "something changed".
void iosClick() => HapticFeedback.selectionClick();

// ===========================================================================
// the panel
// ===========================================================================

/// The floating card every tool dialog is drawn on.
///
/// On iOS the surface is Apple's own glass (see the file header); everywhere
/// else it is the palette's panel colour with a hairline edge. The corners are
/// superellipses in both cases — cut by UIKit for the platform view, by
/// [IosShape] for the Flutter content.
///
/// [maxHeight] makes the body SCROLL rather than overflow. The Inventor panels
/// had no such limit: the extrude dialog is 560 pt tall with every section
/// open, more at an accessibility text size, and on a landscape iPad in Split
/// View it simply ran off the bottom.
class IosPanel extends StatelessWidget {
  const IosPanel({
    super.key,
    required this.width,
    required this.children,
    this.nav,
    this.footer,
    this.maxHeight,
  });

  final double width;

  /// The navigation bar. Pinned above the scroll, like a real one.
  final Widget? nav;

  /// Scrolls when the content outgrows [maxHeight].
  final List<Widget> children;

  /// Pinned below the scroll — the actions that are not in the nav bar.
  final Widget? footer;

  final double? maxHeight;

  /// How tall a panel may become here: the viewport, less the dock's own gap
  /// at top and bottom. Every dialog passes this rather than guessing.
  static double maxHeightIn(BuildContext context) {
    final size = MediaQuery.maybeSizeOf(context);
    return size == null ? double.infinity : math.max(160.0, size.height - 24);
  }

  @override
  Widget build(BuildContext context) {
    final glass = GlassPanel.isSupported;
    final body = Column(mainAxisSize: MainAxisSize.min, children: children);
    final cap = maxHeight ?? maxHeightIn(context);
    final scrollable = cap.isFinite;

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nav != null) nav!,
        if (scrollable)
          Flexible(child: SingleChildScrollView(child: body))
        else
          body,
        if (footer != null) footer!,
      ],
    );

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: cap),
        child: Container(
          width: width,
          decoration: ShapeDecoration(
            // With the platform view behind it the surface must stay clear, or
            // the glass is a picture of a panel under a panel.
            color: glass ? null : IosColors.groupedBackground,
            shape: IosShape.border(
              IosMetrics.panelRadius,
              // UIKit draws the material's own specular rim; a second hairline
              // on top of it reads as a double edge. The fallback needs one.
              side: glass
                  ? BorderSide.none
                  : BorderSide(
                      color: IosColors.border, width: IosMetrics.hairline),
            ),
            shadows: iosPanelShadow(),
          ),
          child: Stack(children: [
            if (glass)
              const Positioned.fill(
                  child: GlassPanel(cornerRadius: IosMetrics.panelRadius)),
            IosShape.clip(IosMetrics.panelRadius, child: column),
          ]),
        ),
      ),
    );
  }
}

/// A panel's navigation bar: an action on the leading edge, a centred title,
/// an action on the trailing edge — and the whole strip is the drag handle.
///
/// Cancel leads and the confirming action trails, which is where iOS puts them
/// (HIG, Sheets). The Inventor panels put OK / Cancel / Apply in a footer; the
/// third verb, where a dialog has one, goes to [IosPanel.footer] rather than
/// crowding the bar.
class IosNavBar extends StatelessWidget {
  const IosNavBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onDrag,
  });

  final String title;

  /// A second line under the title, 13 pt secondary — where the panel says
  /// which feature and which sketch it is editing.
  final Widget? subtitle;

  final Widget? leading;
  final Widget? trailing;
  final void Function(Offset delta)? onDrag;

  @override
  Widget build(BuildContext context) {
    final labels = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: IosText.headline.on(IosColors.label)),
        if (subtitle != null)
          // MERGE, not replace: a bare DefaultTextStyle drops the inherited
          // family with everything else, and the subtitle then renders in
          // whatever the engine falls back to rather than in the app's face.
          DefaultTextStyle.merge(
            style: IosText.caption1.on(IosColors.secondaryLabel),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: subtitle!,
          ),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta),
      child: Container(
        constraints: BoxConstraints(
            minHeight: subtitle == null ? IosMetrics.navBar : 58),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: IosColors.separator, width: IosMetrics.hairline)),
        ),
        child: _bar(context, labels),
      ),
    );
  }

  /// One line normally; two at the accessibility text sizes.
  ///
  /// A panel is a fixed 340 pt, so at 3.1× "Cancel" and "OK" alone are wider
  /// than the bar — the title had nowhere to go and the row overflowed by 126
  /// pt. UIKit answers this the same way: past a certain size a navigation
  /// bar stops being one line and puts its buttons under the title. Shrinking
  /// the words instead would be the one place in the app where asking for
  /// bigger text gives you smaller text.
  Widget _bar(BuildContext context, Widget labels) {
    // A heading either way, so VoiceOver's rotor can jump straight to "which
    // panel am I in" instead of walking the whole bar.
    final title = Semantics(header: true, child: labels);
    if (IosMetrics.isAccessibilitySize(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: title),
          Row(children: [
            if (leading != null) Flexible(child: leading!),
            const Spacer(),
            if (trailing != null) Flexible(child: trailing!),
          ]),
        ],
      );
    }
    return Row(children: [
      // The two edges take their natural width and the title takes the rest,
      // CENTRED inside it. A Stack would centre on the whole bar and let a
      // long German title slide under the buttons.
      if (leading != null) leading!,
      Expanded(child: Center(child: title)),
      if (trailing != null) trailing!,
    ]);
  }
}

/// A navigation-bar action: one word in the tint, semibold when it confirms.
///
/// 17 pt, the size iOS sets a bar button in, with the 44 pt target the HIG
/// asks for supplied by padding rather than by drawing a box.
class IosBarButton extends StatelessWidget {
  const IosBarButton({
    super.key,
    required this.label,
    this.onTap,
    this.prominent = false,
    this.destructive = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onTap;

  /// The default action — semibold, per iOS.
  final bool prominent;
  final bool destructive;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final colour = !on
        ? IosColors.quaternaryLabel
        : destructive
            ? IosColors.destructive
            : IosColors.tint;
    Widget w = IosPressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
            minWidth: IosMetrics.hit, minHeight: IosMetrics.hit),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IosText.body.on(colour,
                weight: prominent ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

/// A navigation-bar action drawn as a glyph rather than a word.
class IosBarGlyphButton extends StatelessWidget {
  const IosBarGlyphButton({
    super.key,
    required this.glyph,
    this.onTap,
    this.tooltip,
    this.destructive = false,
  });

  final IosGlyph glyph;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colour = onTap == null
        ? IosColors.quaternaryLabel
        : destructive
            ? IosColors.destructive
            : IosColors.tint;
    Widget w = IosPressable(
      onTap: onTap,
      // A glyph has no text to lend VoiceOver, and the tooltip is already
      // this control's name in the user's language.
      semanticLabel: tooltip,
      child: SizedBox(
        width: IosMetrics.hit,
        height: IosMetrics.hit,
        child: Center(child: iosGlyph(glyph, size: 17, color: colour)),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

// ===========================================================================
// the inset grouped list
// ===========================================================================

/// One section of an inset grouped list: an optional header, a card of rows,
/// an optional footer note.
///
/// [open] and [onToggle] keep the collapsing the Inventor panels had — iOS
/// grew the same affordance in its own lists (a section header with a
/// disclosure control) so nothing had to be given up to move idioms.
Widget iosSection({
  String? header,
  String? footer,
  bool? open,
  VoidCallback? onToggle,
  required List<Widget> children,
  EdgeInsets? margin,
}) {
  final expanded = open ?? true;
  Widget? head;
  if (header != null) {
    // SENTENCE CASE, not the upper case UIKit's older grouped table uses.
    // SwiftUI's Form — which is what iOS 26 builds these lists with — sets a
    // section header in plain footnote, and a `toUpperCase()` on a localised
    // string is a decision about German typography that this app has no
    // business making.
    final label = Text(header,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: IosText.footnote.on(IosColors.secondaryLabel));
    head = Padding(
      padding: EdgeInsets.fromLTRB(
          IosMetrics.cardInset + IosMetrics.rowInset - 4,
          IosMetrics.sectionTop,
          IosMetrics.cardInset + 4,
          IosMetrics.headerGap),
      child: onToggle == null
          ? label
          : IosPressable(
              onTap: onToggle,
              expanded: expanded,
              child: Row(children: [
                Expanded(child: label),
                iosGlyph(expanded ? IosGlyph.chevronUp : IosGlyph.chevronDown,
                    size: 12, color: IosColors.tint),
              ]),
            ),
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (head != null) head,
      if (expanded && children.isNotEmpty)
        Padding(
          padding: margin ??
              EdgeInsets.fromLTRB(
                  IosMetrics.cardInset,
                  header == null ? IosMetrics.sectionTop : 0,
                  IosMetrics.cardInset,
                  IosMetrics.sectionBottom),
          child: iosCard(children),
        ),
      if (expanded && footer != null)
        Padding(
          padding: EdgeInsets.fromLTRB(
              IosMetrics.cardInset + IosMetrics.rowInset - 4,
              0,
              IosMetrics.cardInset + IosMetrics.rowInset - 4,
              IosMetrics.sectionBottom),
          child: Text(footer,
              style: IosText.footnote.on(IosColors.secondaryLabel)),
        ),
    ],
  );
}

/// The card itself: rows on one rounded surface, hairlines between them inset
/// to where the text starts. Exposed on its own for the few places that need a
/// card without a section header.
Widget iosCard(List<Widget> rows) {
  final children = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) {
      children.add(Padding(
        padding: const EdgeInsets.only(left: IosMetrics.rowInset),
        child: Container(
            height: IosMetrics.hairline, color: IosColors.separator),
      ));
    }
    children.add(rows[i]);
  }
  return IosShape.clip(
    IosMetrics.cardRadius,
    child: ColoredBox(
      color: IosColors.cardBackground,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children),
    ),
  );
}

/// A row: a label on the leading edge, whatever the row is about on the
/// trailing one, 44 pt tall and tappable as a whole when [onTap] is given.
Widget iosRow({
  String? label,
  Widget? leading,
  Widget? trailing,
  String? value,
  VoidCallback? onTap,
  bool chevron = false,
  bool enabled = true,
  double minHeight = IosMetrics.row,
  Color? valueColour,
  int valueMaxLines = 1,
  double pressOpacity = 0.55,
}) {
  final row = Container(
    constraints: BoxConstraints(minHeight: minHeight),
    padding: const EdgeInsets.symmetric(
        horizontal: IosMetrics.rowInset, vertical: 6),
    // The label's box is TIGHT (an Expanded, not a Flexible), and that is the
    // difference between a list and a heap. A loose label keeps whatever space
    // it does not use, so the value lands a different distance from the right
    // edge on every row and the column of numbers a table exists for never
    // forms. Three parts label to two parts value is the split iOS uses:
    // enough for a compound German noun on two lines, enough for a measured
    // value on one.
    child: Row(children: [
      if (leading != null) ...[leading, const SizedBox(width: 10)],
      if (label != null)
        Expanded(
          flex: value != null ? 3 : 1,
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IosText.subheadline.on(IosColors.label)),
        ),
      if (label == null && value == null) const Spacer(),
      if (value != null) ...[
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Text(value,
              textAlign: TextAlign.right,
              maxLines: valueMaxLines,
              overflow: TextOverflow.ellipsis,
              style: IosText.subheadline
                  .on(valueColour ?? IosColors.secondaryLabel)),
        ),
      ],
      if (trailing != null) ...[const SizedBox(width: 8), trailing],
      if (chevron) ...[
        const SizedBox(width: 6),
        iosGlyph(IosGlyph.chevronRight,
            size: 13, color: IosColors.tertiaryLabel),
      ],
    ]),
  );
  final live = enabled && onTap != null;
  final body =
      live ? IosPressable(onTap: onTap, opacity: pressOpacity, child: row) : row;
  return enabled
      ? body
      : IgnorePointer(child: Opacity(opacity: 0.4, child: body));
}

/// A row whose control needs the WHOLE width: a segmented control, a slider, a
/// wrap of option buttons. The label sits above it in 13 pt, which is what iOS
/// does when a control cannot share a line with its name.
Widget iosStackedRow({
  String? label,
  required Widget child,
  bool enabled = true,
  Widget? labelTrailing,
}) {
  final body = Padding(
    padding: const EdgeInsets.fromLTRB(
        IosMetrics.rowInset, 10, IosMetrics.rowInset, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IosText.footnote.on(IosColors.secondaryLabel)),
            ),
            if (labelTrailing != null) labelTrailing,
          ]),
          const SizedBox(height: 7),
        ],
        child,
      ],
    ),
  );
  return enabled
      ? body
      : IgnorePointer(child: Opacity(opacity: 0.4, child: body));
}

/// A line of explanation between two cards — iOS's section footer, used where
/// a panel has something to say that is not a row.
Widget iosNote(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
          IosMetrics.cardInset + IosMetrics.rowInset - 4,
          0,
          IosMetrics.cardInset + IosMetrics.rowInset - 4,
          IosMetrics.sectionBottom),
      child: Text(text, style: IosText.footnote.on(IosColors.secondaryLabel)),
    );

/// The line a panel shows when the preview refused to build.
///
/// A filled `exclamationmark.circle.fill` and the reason, in the palette's
/// error colour. Not an alert: the panel is still open and the number that
/// caused it is still on screen, which is the whole point of a live preview.
Widget iosStatusLine(String text, {bool warning = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(
          IosMetrics.cardInset + 2, 2, IosMetrics.cardInset + 2, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: iosGlyph(IosGlyph.alert,
              size: 15,
              color: warning ? IosColors.warning : IosColors.destructive),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              style: IosText.footnote.on(
                  warning ? IosColors.warning : IosColors.destructive)),
        ),
      ]),
    );

// ===========================================================================
// the segmented control
// ===========================================================================

/// One choice inside an [IosSegmented].
class IosSegment<T> {
  const IosSegment({
    required this.value,
    this.label,
    this.icon,
    this.tooltip,
    this.enabled = true,
  }) : assert(label != null || icon != null);

  final T value;
  final String? label;

  /// A picture instead of a word. "Prefer using either text or images — not a
  /// mix — in a single segmented control" (HIG), so a control uses one or the
  /// other throughout; the tooltip carries the name for the picture ones.
  final Widget? icon;
  final String? tooltip;
  final bool enabled;
}

/// iOS's sliding segmented control.
///
/// The measurements are UIKit's: a 32 pt track in the tertiary system fill, a
/// thumb inset 2 pt with the system's two-part shadow, 13 pt labels that go
/// semibold when selected, and hairline separators between adjacent unselected
/// segments which disappear beside the thumb.
///
/// [onChanged] fires on EVERY tap, including one on the already-selected
/// segment. A dialog that wants "tap the active one to go back" gets it for
/// free; one that does not simply sets the value it already has.
class IosSegmented<T> extends StatelessWidget {
  const IosSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = IosMetrics.segment,
  });

  final List<IosSegment<T>> segments;
  final T? value;
  final ValueChanged<T> onChanged;
  final double height;

  /// A segmented control is the densest thing in the kit — three or four
  /// labels sharing one 308 pt track — so it takes the smaller cap. Past this
  /// the words stop fitting side by side however tall the track gets.
  static const double _maxGrowth = 1.4;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return SizedBox(height: height);
    final selected = segments.indexWhere((s) => s.value == value);
    const inset = IosMetrics.segmentInset;
    // The track grows with the labels, and the labels stop where the track
    // does, so the two can never disagree and clip.
    final track = height * IosMetrics.growth(context, max: _maxGrowth);

    final control = LayoutBuilder(builder: (context, bc) {
      final total = bc.maxWidth.isFinite ? bc.maxWidth : 300.0;
      final seg = total / segments.length;
      return SizedBox(
        height: track,
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: IosColors.tertiarySystemFill,
                shape: IosShape.border(IosMetrics.segmentRadius),
              ),
            ),
          ),
          // The separators sit UNDER the thumb, and each hides itself when the
          // thumb is on either side of it — which is what UIKit does.
          for (var i = 1; i < segments.length; i++)
            if (selected != i && selected != i - 1)
              Positioned(
                left: seg * i,
                top: track * 0.22,
                bottom: track * 0.22,
                width: IosMetrics.hairline,
                child: ColoredBox(color: IosColors.separator),
              ),
          if (selected >= 0)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: seg * selected + inset,
              top: inset,
              width: seg - inset * 2,
              height: track - inset * 2,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: IosColors.segmentThumb,
                  shape: IosShape.border(IosMetrics.segmentRadius - inset),
                  shadows: iosThumbShadow(),
                ),
              ),
            ),
          Row(children: [
            for (var i = 0; i < segments.length; i++)
              Expanded(child: _label(segments[i], i == selected)),
          ]),
        ]),
      );
    });
    return MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxGrowth, child: control);
  }

  Widget _label(IosSegment<T> s, bool on) {
    final colour = !s.enabled
        ? IosColors.quaternaryLabel
        : IosColors.label;
    Widget content = s.icon != null
        ? Center(
            child: Opacity(
                opacity: s.enabled ? (on ? 1 : 0.72) : 0.35, child: s.icon!))
        : Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(s.label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: IosText.footnote.on(colour,
                      weight: on ? FontWeight.w600 : FontWeight.w400)),
            ),
          );
    content = IosPressable(
      opacity: 0.5,
      onTap: s.enabled
          ? () {
              iosClick();
              onChanged(s.value);
            }
          : null,
      // A picture segment has only its tooltip to be called by; a worded one
      // lends VoiceOver the word already drawn in it.
      semanticLabel: s.label == null ? s.tooltip : null,
      selected: on,
      child: SizedBox.expand(child: content),
    );
    return s.tooltip == null
        ? content
        : Tooltip(message: s.tooltip!, child: content);
  }
}

/// A segmented control that WRAPS, for an option set too wide for one line.
///
/// The assembly dialogs offer eight constraint types and seven joint types as
/// pictures. Seven 32 pt segments fit a 440 pt panel; eight do not, and a
/// segmented control that clips is worse than a group of buttons that wraps.
/// These are drawn as iOS's bordered toggle buttons instead — the same
/// vocabulary a control cluster uses.
class IosToggleGroup<T> extends StatelessWidget {
  const IosToggleGroup({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.size = const Size(44, 36),
  });

  final List<IosSegment<T>> segments;
  final T? value;
  final ValueChanged<T> onChanged;
  final Size size;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in segments)
            IosIconToggle(
              on: s.value == value,
              enabled: s.enabled,
              tooltip: s.tooltip,
              size: size,
              onTap: () => onChanged(s.value),
              child: s.icon ??
                  Text(s.label!,
                      style: IosText.footnote.on(
                          s.value == value ? IosColors.tint : IosColors.label,
                          weight: FontWeight.w600)),
            ),
        ],
      );
}

/// One bordered toggle: tinted when on, the tertiary fill when off.
class IosIconToggle extends StatelessWidget {
  const IosIconToggle({
    super.key,
    required this.child,
    required this.on,
    this.onTap,
    this.tooltip,
    this.enabled = true,
    this.size = const Size(44, 36),
  });

  final Widget child;
  final bool on;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enabled;
  final Size size;

  @override
  Widget build(BuildContext context) {
    Widget w = IosPressable(
      opacity: 0.5,
      onTap: enabled && onTap != null
          ? () {
              iosClick();
              onTap!();
            }
          : null,
      semanticLabel: tooltip,
      selected: on,
      child: Container(
        width: size.width,
        height: size.height,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: on ? IosColors.tintedFill : IosColors.tertiarySystemFill,
          shape: IosShape.border(
            IosMetrics.controlRadius,
            side: on
                ? BorderSide(color: IosColors.tint, width: 1)
                : BorderSide.none,
          ),
        ),
        child: Opacity(opacity: enabled ? 1 : 0.35, child: child),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

// ===========================================================================
// buttons
// ===========================================================================

/// How much weight a button carries. iOS's own ladder.
enum IosButtonStyle {
  /// The accent as a fill. One, at most two, per panel (HIG, Buttons).
  filled,

  /// The accent at low alpha with an accent label — `CupertinoButton.tinted`.
  tinted,

  /// The neutral fill: a secondary action that still wants a shape.
  grey,

  /// A word in the tint and nothing else.
  plain,
}

/// A button, at one of four weights, with the press state the HIG requires.
class IosButton extends StatelessWidget {
  const IosButton({
    super.key,
    required this.label,
    this.onTap,
    this.style = IosButtonStyle.plain,
    this.destructive = false,
    this.glyph,
    this.height = IosMetrics.hit,
    this.tooltip,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IosButtonStyle style;
  final bool destructive;
  final IosGlyph? glyph;
  final double height;
  final String? tooltip;

  /// Fills the width it is given. "Avoid full-width buttons" (HIG) applies to
  /// the SCREEN's edges; inside a 340 pt panel a button that matches the cards
  /// above it is the aligned choice.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final tint = destructive ? IosColors.destructive : IosColors.tint;
    final (Color? bg, Color fg) = switch (style) {
      IosButtonStyle.filled => (
          on ? tint : IosColors.tertiarySystemFill,
          on ? IosColors.onTint : IosColors.quaternaryLabel
        ),
      IosButtonStyle.tinted => (
          on ? IosColors.tintedFill : IosColors.tertiarySystemFill,
          on ? tint : IosColors.quaternaryLabel
        ),
      IosButtonStyle.grey => (
          IosColors.tertiarySystemFill,
          on ? IosColors.label : IosColors.quaternaryLabel
        ),
      IosButtonStyle.plain => (null, on ? tint : IosColors.quaternaryLabel),
    };

    // A button shorter than a standard control is a SECONDARY one, and iOS
    // sets those a step down the ramp — 15 pt rather than 17, with less air
    // around the label. Two of them side by side inside a 308 pt card have
    // about 130 pt each, and "Alle Innenkanten" does not fit that at 17.
    final small = height <= 36;
    Widget w = IosPressable(
      onTap: onTap,
      child: Container(
        // A button may widen, so its label takes the larger cap; only the
        // pill's drawn height has to be told to keep up.
        height: height * IosMetrics.growth(context),
        constraints: const BoxConstraints(minWidth: IosMetrics.hit),
        padding: EdgeInsets.symmetric(horizontal: small ? 10 : 16),
        alignment: Alignment.center,
        decoration: bg == null
            ? null
            : ShapeDecoration(
                color: bg, shape: IosShape.border(IosMetrics.controlRadius)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (glyph != null) ...[
              iosGlyph(glyph!, size: small ? 13 : 15, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (small ? IosText.subheadline : IosText.body).on(fg,
                      weight: style == IosButtonStyle.plain
                          ? FontWeight.w400
                          : FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return expand ? SizedBox(width: double.infinity, child: w) : w;
  }
}

/// A round glyph button — the `+` that applies a feature and starts another,
/// the transport keys in the Drive panel.
class IosCircleButton extends StatelessWidget {
  const IosCircleButton({
    super.key,
    required this.glyph,
    this.onTap,
    this.tooltip,
    this.on = false,
    this.diameter = 36,
  });

  final IosGlyph glyph;
  final VoidCallback? onTap;
  final String? tooltip;

  /// A transport key that is currently running.
  final bool on;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final live = onTap != null;
    Widget w = IosPressable(
      opacity: 0.5,
      onTap: onTap,
      semanticLabel: tooltip,
      selected: on ? true : null,
      child: Container(
        width: diameter,
        height: diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? IosColors.tintedFill : IosColors.tertiarySystemFill,
        ),
        child: iosGlyph(glyph,
            size: diameter * 0.5,
            color: !live
                ? IosColors.quaternaryLabel
                : (on ? IosColors.tint : IosColors.label)),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return SizedBox(
      width: math.max(IosMetrics.hit, diameter),
      height: math.max(IosMetrics.hit, diameter),
      child: Center(child: w),
    );
  }
}

/// The footer strip under a panel's scroll: a hairline, then the actions that
/// are not in the navigation bar.
Widget iosFooter({required List<Widget> children, EdgeInsets? padding}) =>
    Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: IosColors.separator, width: IosMetrics.hairline)),
      ),
      padding: padding ??
          const EdgeInsets.fromLTRB(IosMetrics.cardInset, 8,
              IosMetrics.cardInset, 8),
      child: Row(children: children),
    );

// ===========================================================================
// switches, sliders
// ===========================================================================

/// A switch in a list row — which is the only place iOS allows one (HIG,
/// Toggles). Every checkbox in the old panels became one of these.
///
/// The track takes the app's accent rather than system green: the HIG permits
/// it ("you might want to use your app's accent color"), and a green switch in
/// a panel whose every other selected thing is teal would read as a different
/// app's control.
Widget iosSwitchRow({
  required String label,
  required bool value,
  ValueChanged<bool>? onChanged,
  String? tooltip,
  Widget? leading,
}) {
  // One wrapper for all three ways this row can be flipped — the switch, the
  // row's own tap, and VoiceOver's activation — so the tick happens once and
  // happens whichever way you got here.
  final fire = onChanged == null
      ? null
      : (bool v) {
          iosClick();
          onChanged(v);
        };
  final row = iosRow(
    label: label,
    leading: leading,
    trailing: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: CupertinoSwitch(
        value: value,
        onChanged: fire,
        activeTrackColor: IosColors.tint,
        inactiveTrackColor: IosColors.systemFill,
      ),
    ),
    enabled: onChanged != null,
    // THE WHOLE ROW TOGGLES, which is what SwiftUI's `Toggle` inside a `Form`
    // does — the label is part of the control's hit area, not a caption beside
    // it. UIKit's older table cell did not, and a 51 pt switch as the only
    // target on a 308 pt row is a worse deal on a touch screen than it looks
    // on a Mac. The press feedback is deliberately faint: the switch's own
    // animation is the feedback, and a row that dimmed like a button would
    // read as one.
    onTap: fire == null ? null : () => fire(!value),
    pressOpacity: 0.85,
  );
  final out = tooltip == null ? row : Tooltip(message: tooltip, child: row);
  // ONE node, and a switch rather than a button. Left alone this row would
  // reach VoiceOver as a button that happens to contain a switch — two things
  // to swipe through and the wrong verb on both. `excludeSemantics` drops the
  // parts and states the whole: name, on or off, and a tap that flips it.
  return Semantics(
    container: true,
    toggled: value,
    enabled: onChanged != null,
    label: label,
    onTap: fire == null ? null : () => fire(!value),
    excludeSemantics: true,
    child: out,
  );
}

/// A slider with its value read out above it, the arrangement iOS uses when a
/// slider needs a number beside it.
Widget iosSliderRow({
  required String label,
  required String readout,
  required double value,
  required double min,
  required double max,
  int? divisions,
  required ValueChanged<double> onChanged,
}) =>
    iosStackedRow(
      label: label,
      labelTrailing: Text(readout,
          style: IosText.footnote.on(IosColors.label, weight: FontWeight.w600)),
      child: SizedBox(
        height: 28,
        child: CupertinoSlider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: IosColors.tint,
          onChanged: onChanged,
        ),
      ),
    );

// ===========================================================================
// values
// ===========================================================================

/// The well a number sits in when it cannot have a row of its own — a column
/// of fields, a field beside a chip.
///
/// [unit] and [unitLabel] are NOT the same thing, and conflating them is the
/// bug this signature exists to prevent. [unit] is what [ScrubField] must
/// preserve because the unit is part of the TEXT ("5 mm" in the controller);
/// [unitLabel] is a unit DRAWN beside a field that holds a bare number. A
/// field gets one or the other — never both, or it reads "5 mm mm".
Widget iosValueWell({
  required AppState app,
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  String? unit,
  String? unitLabel,
  ScrubKind? kind,
  double? min,
  double? max,
  bool enabled = true,
  bool integer = false,
  VoidCallback? onDone,
  TextAlign align = TextAlign.right,
}) {
  final field = Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: ShapeDecoration(
      color: IosColors.quaternarySystemFill,
      shape: IosShape.border(IosMetrics.controlRadius),
    ),
    child: Row(children: [
      Expanded(
          child: _valueField(controller, onChanged, enabled, align,
              integer: integer)),
      if (unitLabel != null) ...[
        const SizedBox(width: 4),
        Text(unitLabel, style: IosText.footnote.on(IosColors.secondaryLabel)),
      ],
    ]),
  );
  if (!enabled) {
    return IgnorePointer(child: Opacity(opacity: 0.4, child: field));
  }
  return ScrubField(
    app: app,
    controller: controller,
    suffix: unit,
    kind: kind ?? (integer ? ScrubKind.count : scrubKindForUnit(unit)),
    min: min,
    max: max,
    onCommit: onChanged,
    onDone: onDone,
    child: field,
  );
}

/// A whole row that edits one number: the label on the left, the value and its
/// unit right-aligned, and the ENTIRE row is the scrub target.
///
/// Wrapping the row rather than the field is a deliberate widening: on a
/// 340 pt panel the field itself is about 90 pt of drag, and M172's gesture is
/// meant to be reachable with a Pencil without hunting for it.
Widget iosValueRow({
  required AppState app,
  required String label,
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  String? unit,
  String? unitLabel,
  ScrubKind? kind,
  double? min,
  double? max,
  bool enabled = true,
  bool integer = false,
  VoidCallback? onDone,
  Widget? leading,
}) {
  final row = Container(
    constraints: const BoxConstraints(minHeight: IosMetrics.row),
    padding: const EdgeInsets.symmetric(
        horizontal: IosMetrics.rowInset, vertical: 4),
    child: Row(children: [
      if (leading != null) ...[leading, const SizedBox(width: 10)],
      // Tight, 3:2 — see [iosRow] on why the label may not keep what it does
      // not use.
      Expanded(
        flex: 3,
        child: Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: IosText.subheadline.on(IosColors.label)),
      ),
      const SizedBox(width: 10),
      Expanded(
          flex: 2,
          child: _valueField(controller, onChanged, enabled, TextAlign.right,
              integer: integer)),
      if (unitLabel != null) ...[
        const SizedBox(width: 5),
        Text(unitLabel,
            style: IosText.subheadline.on(IosColors.secondaryLabel)),
      ],
    ]),
  );
  if (!enabled) {
    return IgnorePointer(child: Opacity(opacity: 0.4, child: row));
  }
  return ScrubField(
    app: app,
    controller: controller,
    suffix: unit,
    kind: kind ?? (integer ? ScrubKind.count : scrubKindForUnit(unit)),
    min: min,
    max: max,
    onCommit: onChanged,
    onDone: onDone,
    child: row,
  );
}

/// The [TextField] itself. Deliberately Flutter's Material one, with its
/// decoration stripped: [kValueKeyboard] (M206 — the app draws its own pad),
/// [kValueHandwriting] (M179 — the Pencil scrubs a number, it does not write
/// on it), and the widget type m180_every_number_scrubs_test looks for.
Widget _valueField(TextEditingController c, ValueChanged<String> onChanged,
        bool enabled, TextAlign align, {bool integer = false}) =>
    TextField(
      controller: c,
      enabled: enabled,
      keyboardType: kValueKeyboard,
      stylusHandwritingEnabled: kValueHandwriting,
      autocorrect: false,
      enableSuggestions: false,
      textAlign: align,
      cursorColor: IosColors.tint,
      // A hardware keyboard can still reach these fields (M206 keeps the
      // caret and every physical key), so a count that must be whole says so
      // here as well as in its scrub detent.
      inputFormatters: integer
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))]
          : null,
      style: IosText.subheadline.on(IosColors.label),
      decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8)),
      onChanged: onChanged,
    );

/// A row that edits a NAME rather than a number: no scrub, no pad, an ordinary
/// keyboard. Right-aligned like every other value in an iOS list.
Widget iosTextRow({
  String? label,
  required TextEditingController controller,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  String? placeholder,
  bool autofocus = false,
}) {
  // With no label the field takes the whole row and reads from the leading
  // edge — the shape iOS uses when the SECTION already says what the field is.
  final field = TextField(
    controller: controller,
    autofocus: autofocus,
    autocorrect: false,
    enableSuggestions: false,
    textAlign: label == null ? TextAlign.start : TextAlign.right,
    cursorColor: IosColors.tint,
    style: IosText.subheadline.on(IosColors.label),
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      hintText: placeholder,
      hintStyle: IosText.subheadline.on(IosColors.tertiaryLabel),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
    ),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
  return Container(
    constraints: const BoxConstraints(minHeight: IosMetrics.row),
    padding: const EdgeInsets.symmetric(
        horizontal: IosMetrics.rowInset, vertical: 4),
    child: Row(children: [
      if (label != null) ...[
        Expanded(
          flex: 2,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IosText.subheadline.on(IosColors.label)),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: field),
      ] else
        Expanded(child: field),
    ]),
  );
}

// ===========================================================================
// picking geometry
// ===========================================================================

/// The row a panel uses to say "point at something in the viewport".
///
/// Three states, and they say three different things — the same three the
/// Inventor panels drew with a coloured border, now said the way iOS says
/// them: ARMED tints the row and spells the gesture out on a second line,
/// FILLED reads back what was picked, EMPTY is a placeholder.
///
/// [value] is the STATE and [hint] is the SENTENCE, and keeping them apart is
/// the point of the two arguments. "Tap a plane or a planar face" is nine
/// words; as a row's value it wrapped to two lines and still ellipsised, which
/// is what a value does when it is really a caption. A row's value stays short
/// and the caption goes under it, which is the shape iOS uses for a row that
/// has something to explain.
Widget iosPickRow({
  required String label,
  String? value,
  String? hint,
  required bool armed,
  required bool filled,
  VoidCallback? onTap,
  VoidCallback? onClear,
  bool required_ = false,
}) {
  final colour = armed
      ? IosColors.tint
      : filled
          ? IosColors.label
          : (required_ ? IosColors.warning : IosColors.tertiaryLabel);
  final head = Row(children: [
    if (armed) ...[
      iosGlyph(IosGlyph.pick, size: 15, color: IosColors.tint),
      const SizedBox(width: 10),
    ],
    // 2:3 here, the other way round from an ordinary row: a pick row's LABEL
    // is a noun ("Edges", "Axis") and its VALUE is what was picked, which can
    // be a body name or a list of them.
    Expanded(
      flex: 2,
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IosText.subheadline.on(IosColors.label)),
    ),
    const SizedBox(width: 10),
    Expanded(
      flex: 3,
      child: Text(value ?? '',
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IosText.subheadline.on(colour)),
    ),
    if (onClear != null && filled)
      // Builder, so the label can be looked up in the user's language without
      // 27 call sites having to hand this function a context.
      Builder(builder: (context) {
        return IosPressable(
          onTap: onClear,
          semanticLabel: L.of(context).a11yClearNamed(label),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: iosGlyph(IosGlyph.xmarkCircleFill,
                size: 17, color: IosColors.tertiaryLabel),
          ),
        );
      }),
  ]);

  // The caption shows while the row is ARMED (it is then an instruction) and
  // while it is EMPTY (it is then what to do about that). Once something is
  // picked it goes: the value says everything.
  final showHint = hint != null && (armed || !filled);

  final row = Container(
    color: armed ? IosColors.tintedFill : null,
    constraints: const BoxConstraints(minHeight: IosMetrics.row),
    padding: const EdgeInsets.symmetric(
        horizontal: IosMetrics.rowInset, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        head,
        if (showHint) ...[
          const SizedBox(height: 3),
          Text(hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IosText.footnote.on(
                  armed ? IosColors.tint : IosColors.secondaryLabel)),
        ],
      ],
    ),
  );
  return onTap == null
      ? row
      : IosPressable(onTap: onTap, opacity: 0.55, child: row);
}

/// A removable token — one picked feature, one picked component.
Widget iosChip(String label, VoidCallback onRemove) => Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: ShapeDecoration(
        color: IosColors.tintedFill,
        shape: IosShape.border(9),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IosText.footnote.on(IosColors.tint)),
        ),
        const SizedBox(width: 4),
        Builder(builder: (context) {
          return IosPressable(
            onTap: onRemove,
            semanticLabel: L.of(context).a11yRemoveNamed(label),
            child: iosGlyph(IosGlyph.xmarkCircleFill,
                size: 15, color: IosColors.tint),
          );
        }),
      ]),
    );

// ===========================================================================
// one of many, by menu
// ===========================================================================

/// One entry of a pop-up menu.
class IosMenuChoice<T> {
  const IosMenuChoice(this.value, this.title, {this.symbol});
  final T value;
  final String title;

  /// An SF Symbol name for the native menu. Ignored by the fallback.
  final String? symbol;
}

/// Asks the user to choose one of [choices], and returns it.
///
/// On the device this is a REAL UIKit menu, presented as a popover from
/// [anchor] — the same `NativeMenu.menu` the ribbon has used since M246, so
/// the app has exactly one kind of menu rather than one per surface. Off iOS
/// it falls back to a Cupertino action sheet, which is the same shape drawn in
/// Flutter, so the host test suite and a desktop run behave.
Future<T?> iosChoose<T>(
  BuildContext context, {
  required List<IosMenuChoice<T>> choices,
  required Rect anchor,
  required String cancelLabel,
  T? current,
  String? title,
}) async {
  if (choices.isEmpty) return null;
  if (NativeMenu.isSupported) {
    final id = await NativeMenu.menu(
      items: [
        for (var i = 0; i < choices.length; i++)
          NativeMenuItem(
              id: '$i',
              title: choices[i].title,
              // The chosen row wears a checkmark, which is what a UIMenu does
              // for a single-selection group.
              symbol: choices[i].value == current
                  ? 'checkmark'
                  : choices[i].symbol),
      ],
      anchor: anchor,
      title: title,
      cancelLabel: cancelLabel,
    );
    final i = int.tryParse(id ?? '');
    return i == null || i < 0 || i >= choices.length ? null : choices[i].value;
  }
  if (!context.mounted) return null;
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      actions: [
        for (final c in choices)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(c.value),
            child: Text(c.title,
                style: IosText.body.on(IosColors.tint,
                    weight: c.value == current
                        ? FontWeight.w600
                        : FontWeight.w400)),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(cancelLabel, style: IosText.body.on(IosColors.tint)),
      ),
    ),
  );
}

/// A row that reads back the current choice and opens [iosChoose] when tapped,
/// with UIKit's pull-down indicator on the trailing edge.
///
/// This is what the long-named one-of-many choices became: a coil's four
/// methods, a hole's four shapes where they do not fit a segmented control, a
/// pattern's distribution. A four-segment control of German compound nouns at
/// 340 pt is four ellipses; a menu row shows the whole name of the one that is
/// chosen and the whole name of every alternative.
class IosMenuRow<T> extends StatelessWidget {
  const IosMenuRow({
    super.key,
    required this.label,
    required this.choices,
    required this.value,
    required this.onChanged,
    required this.cancelLabel,
    this.enabled = true,
  });

  final String label;
  final List<IosMenuChoice<T>> choices;
  final T value;
  final ValueChanged<T> onChanged;
  final String cancelLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final now = choices.where((c) => c.value == value);
    return Builder(builder: (rowContext) {
      return iosRow(
        label: label,
        value: now.isEmpty ? '' : now.first.title,
        valueColour: IosColors.tint,
        enabled: enabled,
        trailing: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: iosGlyph(IosGlyph.popup,
              size: 15, color: IosColors.tertiaryLabel),
        ),
        onTap: () async {
          final box = rowContext.findRenderObject();
          final anchor = box is RenderBox && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : Rect.zero;
          final picked = await iosChoose<T>(rowContext,
              choices: choices,
              anchor: anchor,
              current: value,
              cancelLabel: cancelLabel,
              title: label);
          if (picked != null) onChanged(picked);
        },
      );
    });
  }
}
