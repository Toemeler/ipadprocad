// M45 — Parametric TEXT editor window (Inventor-like, movable).
//
// A modeless window over the viewport, styled like the Parameters window: a
// multiline template field, a font dropdown and a size field. While the
// template field is focused, tapping a dimension label in the viewport
// inserts that dimension's parameter name wrapped in quotes (e.g. "d0") at
// the cursor (AppState.textRefSink) — the user's requested syntax. Live
// preview shows the rendered result. Dragging the title bar moves the window.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../inserts.dart';
import '../theme.dart';
import '../vector_font.dart';
import 'scrub_field.dart';
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
    final t = app.editingText;
    final preview = (t != null && app.current != null)
        ? renderTemplate(_tpl.text, app.paramTable(app.current!))
        : '';
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: T.fly,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: T.sep),
        boxShadow: [BoxShadow(color: T.shadow, blurRadius: 10)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ---- draggable title bar ----
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => widget.onDrag(d.delta),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: T.sep))),
            child: Row(children: [
              Icon(Icons.text_fields, size: 15, color: T.accent),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(L.of(context).dlgText,
                      style: TextStyle(color: T.text, fontSize: 12))),
              InkWell(
                onTap: () => app.endTextEdit(keep: false),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: T.dim),
                ),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    _tplF.hasFocus
                        ? L.of(context).hintTapDimensionToInsert
                        : L.of(context).hintTextEmbedParams,
                    style: TextStyle(color: T.dim, fontSize: 10)),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                      color: T.tabOnBg,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: T.sep, width: 0.5)),
                  child: TextField(
                    controller: _tpl,
                    focusNode: _tplF,
                    minLines: 2,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 13, color: T.text),
                    decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(8)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Text(L.of(context).lblFont,
                      style: TextStyle(color: T.dim, fontSize: 11)),
                  const SizedBox(width: 6),
                  DropdownButton<String>(
                    value: _font,
                    dropdownColor: T.fly,
                    isDense: true,
                    style: TextStyle(fontSize: 12, color: T.text),
                    underline: const SizedBox(),
                    items: [
                      for (final f in kTextFonts)
                        DropdownMenuItem(
                            value: f,
                            child: Text(f,
                                style: TextStyle(
                                    fontSize: 12, color: T.text)))
                    ],
                    onChanged: (v) => setState(() => _font = v ?? _font),
                  ),
                  const Spacer(),
                  Text(L.of(context).lblSize,
                      style: TextStyle(color: T.dim, fontSize: 11)),
                  const SizedBox(width: 6),
                  // M180 — the text height drags like every other length.
                  ScrubField(
                    app: app,
                    controller: _hCtrl,
                    min: 1,
                    max: 500,
                    onCommit: (v) {
                      final h = double.tryParse(v.replaceAll(',', '.'));
                      if (h != null) setState(() => _height = h.clamp(1.0, 500.0));
                    },
                    child: SizedBox(
                      width: 54,
                      child: TextField(
                        controller: _hCtrl,
                        keyboardType: kValueKeyboard, // M206
                        stylusHandwritingEnabled: kValueHandwriting, // M179
                        style: TextStyle(fontSize: 12, color: T.text),
                        decoration: const InputDecoration(
                            isDense: true, suffixText: 'mm'),
                        onChanged: (v) {
                          final h = double.tryParse(v.replaceAll(',', '.'));
                          if (h != null) _height = h.clamp(1.0, 500.0);
                        },
                      ),
                    ),
                  ),
                ]),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(L.of(context).lblPreview,
                      style: TextStyle(color: T.dim, fontSize: 10)),
                  const SizedBox(height: 2),
                  // M220 — the preview is drawn from the OUTLINE, so what the
                  // window shows is the curve that will be sketched, exported
                  // and extruded, in the family that is actually selected.
                  SizedBox(
                    height: 34,
                    width: double.infinity,
                    child: CustomPaint(
                        painter: _OutlinePreview(preview, _font)),
                  ),
                ],
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (!app.editingTextIsNew)
                    TextButton(
                        onPressed: () {
                          app.deleteText(t!);
                          app.endTextEdit(keep: true);
                        },
                        child: Text(L.of(context).delete,
                            style: TextStyle(color: T.err))),
                  TextButton(
                      onPressed: () => app.endTextEdit(keep: false),
                      child: Text(L.of(context).cancel)),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: T.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6)),
                    child: Text(L.of(context).ok,
                        style: TextStyle(color: T.text)),
                  ),
                ]),
              ]),
        ),
      ]),
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
