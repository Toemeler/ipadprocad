// M45 — Parametric TEXT editor window (Inventor-like, movable).
//
// A modeless window over the viewport, styled like the Parameters window: a
// multiline template field, a font dropdown and a size field. While the
// template field is focused, tapping a dimension label in the viewport
// inserts that dimension's parameter name wrapped in quotes (e.g. "d0") at
// the cursor (AppState.textRefSink) — the user's requested syntax. Live
// preview shows the rendered result. Dragging the title bar moves the window.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../inserts.dart';
import '../theme.dart';

/// Font families offered in the dropdown. Roboto is Flutter's default and is
/// always present; the others are common iOS system faces.
const List<String> kTextFonts = [
  'Roboto',
  'Helvetica',
  'Courier',
  'Georgia',
  'Menlo',
];

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
  late double _height;
  late String _font;

  @override
  void initState() {
    super.initState();
    final t = widget.app.editingText!;
    _tpl = TextEditingController(text: t.template);
    _height = t.height;
    _font = kTextFonts.contains(t.font) ? t.font : 'Roboto';
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
    _tplF.dispose();
    super.dispose();
  }

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
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ---- draggable title bar ----
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => widget.onDrag(d.delta),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: T.sep))),
            child: Row(children: [
              const Icon(Icons.text_fields, size: 15, color: T.blue),
              const SizedBox(width: 6),
              const Expanded(
                  child: Text('Text',
                      style: TextStyle(color: T.text, fontSize: 12))),
              InkWell(
                onTap: () => app.endTextEdit(keep: false),
                child: const Padding(
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
                        ? 'Tap a dimension in the sketch to insert it as "name"'
                        : 'Text — embed parameters as <Width> or "d0"',
                    style: const TextStyle(color: T.dim, fontSize: 10)),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                      color: const Color(0xFF262B31),
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
                    style: const TextStyle(fontSize: 13, color: T.text),
                    decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(8)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Font',
                      style: TextStyle(color: T.dim, fontSize: 11)),
                  const SizedBox(width: 6),
                  DropdownButton<String>(
                    value: _font,
                    dropdownColor: T.fly,
                    isDense: true,
                    style: const TextStyle(fontSize: 12, color: T.text),
                    underline: const SizedBox(),
                    items: [
                      for (final f in kTextFonts)
                        DropdownMenuItem(
                            value: f,
                            child: Text(f,
                                style: TextStyle(
                                    fontFamily: f,
                                    fontSize: 12,
                                    color: T.text)))
                    ],
                    onChanged: (v) => setState(() => _font = v ?? _font),
                  ),
                  const Spacer(),
                  const Text('Size',
                      style: TextStyle(color: T.dim, fontSize: 11)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 54,
                    child: TextField(
                      controller: TextEditingController(
                          text: _height.toStringAsFixed(
                              _height == _height.roundToDouble() ? 0 : 1)),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(fontSize: 12, color: T.text),
                      decoration: const InputDecoration(
                          isDense: true, suffixText: 'mm'),
                      onChanged: (v) {
                        final h = double.tryParse(v.replaceAll(',', '.'));
                        if (h != null) _height = h.clamp(1.0, 500.0);
                      },
                    ),
                  ),
                ]),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Preview',
                      style: const TextStyle(color: T.dim, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(preview,
                      style: TextStyle(
                          color: T.text, fontFamily: _font, fontSize: 15)),
                ],
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (!app.editingTextIsNew)
                    TextButton(
                        onPressed: () {
                          app.deleteText(t!);
                          app.endTextEdit(keep: true);
                        },
                        child: const Text('Delete',
                            style: TextStyle(color: Color(0xFFE05A5A)))),
                  TextButton(
                      onPressed: () => app.endTextEdit(keep: false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: T.blue,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6)),
                    child: const Text('OK',
                        style: TextStyle(color: Colors.white)),
                  ),
                ]),
              ]),
        ),
      ]),
    );
  }
}
