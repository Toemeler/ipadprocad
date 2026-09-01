// M45 — Parametric TEXT editor window (Inventor-like, movable).
//
// A modeless window over the viewport, styled like the Parameters window: a
// multiline template field, a font dropdown and a size field. While the
// template field is focused, tapping a dimension label in the viewport
// inserts that dimension's parameter name wrapped in quotes (e.g. "d0") at
// the cursor (AppState.textRefSink) — the user's requested syntax. Live
// preview shows the rendered result. Dragging the title bar moves the window.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). The font dropdown was
// the last Material `DropdownButton` in the dialog layer and is a pop-up row
// now, opening a real UIMenu on the device; the size is a value row like every
// other number in the app; and the three buttons became OK trailing, Cancel
// leading, and Delete as a destructive footer action, which is where iOS puts
// the one that destroys something.

import 'dart:math' as math;

import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../inserts.dart';
import '../ios_design.dart';
import '../theme.dart';
import '../vector_font.dart';
import 'ios_kit.dart';
import '../l10n/l.dart';

/// Font families offered in the dropdown.
///
/// M220 — the OUTLINE families, not screen faces. What the dropdown may offer
/// is what the app can turn into curves: a font that only exists as pixels
/// could be drawn but never exported or extruded, which is exactly the gap
/// this milestone closed. See vector_font.dart.
const List<String> kTextFonts = kVectorFontNames;

class TextEditorWindow extends StatefulWidget {
  final AppState app;
  final void Function(Offset delta) onDrag;
  const TextEditorWindow(
      {super.key, required this.app, required this.onDrag});

  @override
  State<TextEditorWindow> createState() => _TextEditorWindowState();
}

class _TextEditorWindowState extends State<TextEditorWindow> {
  late final TextEditingController _tpl;
  late final FocusNode _tplF;
  /// M180 — a real controller, not one built in build(): a scrub writes into
  /// it across many frames, and a fresh controller every rebuild would lose
  /// the value between detents.
  late final TextEditingController _hCtrl;
  late double _height;
  late String _font;

  @override
  void initState() {
    super.initState();
    final t = widget.app.editingText!;
    _tpl = TextEditingController(text: t.template);
    _height = t.height;
    _hCtrl = TextEditingController(text: _heightText());
    // A pre-M220 text names a screen font; open it on the family that took
    // its place instead of silently resetting it to the default.
    _font = vectorFontName(t.font);
    _tplF = FocusNode();
    _tplF.addListener(() {
      final app = widget.app;
      if (_tplF.hasFocus) {
        // dimension-label taps insert "name" at the cursor
        app.textRefSink = (name) {
          final sel = _tpl.selection;
          final s = _tpl.text;
          final st = sel.isValid ? sel.start : s.length;
          final en = sel.isValid ? sel.end : s.length;
          final token = '"$name"';
          _tpl.text = s.replaceRange(st, en, token);
          _tpl.selection =
              TextSelection.collapsed(offset: st + token.length);
          setState(() {});
        };
      } else if (app.textRefSink != null) {
        app.textRefSink = null;
      }
      setState(() {});
    });
    // focus the field on open so click-to-reference is immediately live
    WidgetsBinding.instance.addPostFrameCallback((_) => _tplF.requestFocus());
  }

  @override
  void dispose() {
    if (widget.app.textRefSink != null) widget.app.textRefSink = null;
    _tpl.dispose();
    _hCtrl.dispose();
    _tplF.dispose();
    super.dispose();
  }

  String _heightText() =>
      _height.toStringAsFixed(_height == _height.roundToDouble() ? 0 : 1);

  void _apply() {
    final app = widget.app;
    final t = app.editingText;
    if (t == null) return;
    final tpl = _tpl.text.trim();
    if (tpl.isEmpty) {
      app.deleteText(t);
      app.endTextEdit(keep: false);
      return;
    }
    // live-edit path: the text already exists; push template/height/font
    app.updateText(t, tpl, _height, font: _font);
    app.endTextEdit(keep: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = L.of(context);
    final txt = app.editingText;
    final preview = (txt != null && app.current != null)
        ? renderTemplate(_tpl.text, app.paramTable(app.current!))
        : '';
    return IosPanel(
      width: 380,
      nav: IosNavBar(
        title: t.dlgText,
        onDrag: widget.onDrag,
        leading:
            IosBarButton(label: t.cancel, onTap: () => app.endTextEdit(keep: false)),
        trailing: IosBarButton(label: t.ok, prominent: true, onTap: _apply),
      ),
      footer: app.editingTextIsNew
          ? null
          : iosFooter(children: [
              Expanded(
                child: IosButton(
                  label: t.delete,
                  style: IosButtonStyle.grey,
                  destructive: true,
                  height: 38,
                  expand: true,
                  onTap: () {
                    app.deleteText(txt!);
                    app.endTextEdit(keep: true);
                  },
                ),
              ),
            ]),
      children: [
        iosSection(
          footer: _tplF.hasFocus
              ? t.hintTapDimensionToInsert
              : t.hintTextEmbedParams,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  IosMetrics.rowInset, 8, IosMetrics.rowInset, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: ShapeDecoration(
                  color: IosColors.quaternarySystemFill,
                  shape: IosShape.border(IosMetrics.controlRadius),
                ),
                child: TextField(
                  controller: _tpl,
                  focusNode: _tplF,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: IosColors.tint,
                  onChanged: (_) => setState(() {}),
                  style: IosText.subheadline.on(IosColors.label),
                  decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10)),
                ),
              ),
            ),
          ],
        ),
        iosSection(
          children: [
            // The vector families, as a real pop-up rather than a Material
            // DropdownButton — which was the one Material control left in the
            // dialog layer and did not belong in it.
            IosMenuRow<String>(
              label: t.lblFont,
              value: _font,
              cancelLabel: t.cancel,
              choices: [for (final f in kTextFonts) IosMenuChoice(f, f)],
              onChanged: (f) => setState(() => _font = f),
            ),
            // M180 — the text height drags like every other length.
            iosValueRow(
              app: app,
              label: t.lblSize,
              controller: _hCtrl,
              unitLabel: 'mm',
              min: 1,
              max: 500,
              onChanged: (v) {
                final h = double.tryParse(v.replaceAll(',', '.'));
                if (h != null) setState(() => _height = h.clamp(1.0, 500.0));
              },
            ),
          ],
        ),
        if (preview.isNotEmpty)
          iosSection(
            header: t.lblPreview,
            children: [
              // M220 — the preview is drawn from the OUTLINE, so what the
              // window shows is the curve that will be sketched, exported and
              // extruded, in the family that is actually selected.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    IosMetrics.rowInset, 10, IosMetrics.rowInset, 10),
                child: SizedBox(
                  height: 40,
                  width: double.infinity,
                  child: CustomPaint(painter: _OutlinePreview(preview, _font)),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// M220 — draws a string with the outline font, scaled to fit the strip.
///
/// Only the FIRST line is previewed (the window is 360 px wide and the field
/// takes four): it is a face-and-shape check, not a page proof.
class _OutlinePreview extends CustomPainter {
  final String text;
  final String font;
  const _OutlinePreview(this.text, this.font);

  @override
  void paint(Canvas canvas, Size size) {
    final line = text.split('\n').first;
    if (line.trim().isEmpty || size.height <= 0) return;
    final l = layoutText(line, font, 1); // one em tall, then fitted
    if (l.contours.isEmpty || l.size.width <= 0 || l.size.height <= 0) return;
    final k = math.min(size.height / l.size.height, size.width / l.size.width);
    final path = Path(); // non-zero, like the viewport — see there
    for (final c in l.contours) {
      for (var i = 0; i < c.length; i++) {
        // font space is y-up, the canvas is y-down
        final p = Offset(c[i].dx * k, size.height - c[i].dy * k);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = T.text.withOpacity(0.30));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = T.text);
  }

  @override
  bool shouldRepaint(covariant _OutlinePreview old) =>
      old.text != text || old.font != font;
}
