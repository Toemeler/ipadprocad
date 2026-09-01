// M43 — Inventor's Parameters dialog (Manage > fx Parameters).
//
// A MOVABLE modeless window over the viewport: a table of every model
// parameter (the dimensions: name, equation, value — driven ones read-only)
// and the user parameters, plus an Add row. Name cells rename (references
// follow), equation cells accept the full M41 expression grammar with live
// red validation, and while an equation cell is focused, tapping a dimension
// label in the viewport inserts its parameter name at the cursor
// (AppState.paramRefSink). Dragging the title bar moves the window.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). This one keeps its
// TABLE, and that is a decision rather than an oversight: a parameter is three
// values that are read across (name, equation, result) and compared down a
// column, which is what a table is for and what an inset list of one-value
// rows would destroy. What became iOS is everything around it — the panel, the
// navigation bar, the two grouped sections, the wells the cells sit in, and
// the Add row, which is iOS's own "one more of these" affordance rather than a
// blue plus in a corner.
//
// The `fx` mark that used to sit in the title bar is gone: it was Inventor's
// icon for the command, and a navigation bar names what you are looking at
// rather than which button opened it.
import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../constraints.dart';
import '../ios_design.dart';
import '../params.dart';
import '../scrub.dart';
import 'ios_kit.dart';
import 'scrub_field.dart';
import '../l10n/fmt.dart';
import '../l10n/l.dart';

class ParametersDialog extends StatefulWidget {
  final AppState app;
  final void Function(Offset delta) onDrag;
  const ParametersDialog({super.key, required this.app, required this.onDrag});

  @override
  State<ParametersDialog> createState() => _ParametersDialogState();
}

class _ParametersDialogState extends State<ParametersDialog> {
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = L.of(context);
    final s = app.current;
    final dims = <Constraint>[
      if (s != null)
        for (final c in s.constraints)
          if (c.type == CType.dimension && c.paramName != null) c
    ];
    return IosPanel(
      width: 460,
      maxHeight: 460,
      nav: IosNavBar(
        title: t.dlgParameters,
        onDrag: widget.onDrag,
        trailing:
            IosBarButton(label: t.done, prominent: true, onTap: app.toggleParams),
      ),
      children: [
        iosSection(
          header: t.secModelParameters,
          children: [
            _columns(t),
            if (dims.isEmpty)
              iosRow(label: t.msgNoDimensionsInSketch, enabled: false),
            for (final c in dims) _DimRow(app: app, dim: c),
          ],
        ),
        iosSection(
          header: t.secUserParameters,
          children: [
            _columns(t),
            if (s != null)
              for (final u in s.userParams) _UserRow(app: app, u: u),
            // iOS's "add one more" row: a tinted plus and the verb, at the end
            // of the list it adds to.
            iosRow(
              label: t.btnAddNumericParameter,
              leading: iosGlyph(IosGlyph.plus, size: 17, color: IosColors.tint),
              onTap: () => setState(() => app.addUserParam()),
            ),
          ],
        ),
      ],
    );
  }

  /// The column names. A caption row rather than a section header, because
  /// they belong to the table under them and not to the group.
  Widget _columns(AppL10n t) => Padding(
        padding: const EdgeInsets.fromLTRB(IosMetrics.rowInset, 8,
            IosMetrics.rowInset, 4),
        child: Row(children: [
          SizedBox(
              width: 110,
              child: Text(t.colParameterName,
                  style: IosText.caption1.on(IosColors.secondaryLabel))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(t.colEquation,
                  style: IosText.caption1.on(IosColors.secondaryLabel))),
          const SizedBox(width: 8),
          SizedBox(
              width: 90,
              child: Text(t.colValue,
                  textAlign: TextAlign.right,
                  style: IosText.caption1.on(IosColors.secondaryLabel))),
          const SizedBox(width: 26),
        ]),
      );
}

/// Shared row scaffolding: name cell + equation cell + value + trailing.
class _ParamRow extends StatefulWidget {
  final AppState app;
  final String name;
  final String equation; // raw expr, or the formatted value
  final String value;
  final bool readOnly; // driven dims: measure-only

  /// M180 — what the Equation cell's number measures, when it IS a number. A
  /// cell holding a formula is never scrubbed (ScrubField declines anything it
  /// cannot read as one), which is exactly right: dragging "d0 + 5" would
  /// destroy it.
  final ScrubKind kind;
  final bool Function(String) commitName;
  final bool Function(String) commitEquation;
  final bool Function(String) validEquation;
  final Widget? trailing;
  const _ParamRow(
      {super.key,
      required this.app,
      required this.name,
      required this.equation,
      required this.value,
      required this.commitName,
      required this.commitEquation,
      required this.validEquation,
      this.kind = ScrubKind.length,
      this.readOnly = false,
      this.trailing});

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _eq =
      TextEditingController(text: widget.equation);
  final FocusNode _nameF = FocusNode();
  final FocusNode _eqF = FocusNode();

  @override
  void initState() {
    super.initState();
    // While the EQUATION cell is focused, viewport taps on dimension labels
    // insert the tapped parameter's name at the cursor (Inventor).
    _eqF.addListener(() {
      final app = widget.app;
      if (_eqF.hasFocus) {
        app.paramRefSink = (n) {
          final sel = _eq.selection;
          final t = _eq.text;
          final st = sel.isValid ? sel.start : t.length;
          final en = sel.isValid ? sel.end : t.length;
          _eq.text = t.replaceRange(st, en, n);
          _eq.selection = TextSelection.collapsed(offset: st + n.length);
          setState(() {});
        };
      } else {
        if (app.paramRefSink != null) app.paramRefSink = null;
        _commitEq();
      }
    });
    _nameF.addListener(() {
      if (!_nameF.hasFocus) _commitName();
    });
  }

  @override
  void didUpdateWidget(covariant _ParamRow old) {
    super.didUpdateWidget(old);
    // external changes (rename via "=", chase re-evaluation) refresh idle cells
    if (!_nameF.hasFocus && _name.text != widget.name) {
      _name.text = widget.name;
    }
    if (!_eqF.hasFocus && _eq.text != widget.equation) {
      _eq.text = widget.equation;
    }
  }

  void _commitName() {
    if (_name.text.trim() != widget.name && !widget.commitName(_name.text)) {
      _name.text = widget.name; // rejected: snap back
    }
  }

  void _commitEq() {
    if (_eq.text.trim() != widget.equation &&
        !widget.commitEquation(_eq.text)) {
      _eq.text = widget.equation; // rejected: snap back
    }
  }

  @override
  void dispose() {
    if (widget.app.paramRefSink != null && _eqF.hasFocus) {
      widget.app.paramRefSink = null;
    }
    _nameF.dispose();
    _eqF.dispose();
    _name.dispose();
    _eq.dispose();
    super.dispose();
  }

  /// One editable cell: an input well the size of a control, which is what
  /// tells a table cell apart from a label.
  Widget _cell(Widget child) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: ShapeDecoration(
          color: IosColors.quaternarySystemFill,
          shape: IosShape.border(8),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final eqValid = widget.readOnly || widget.validEquation(_eq.text);
    const deco = InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          IosMetrics.rowInset, 3, IosMetrics.rowInset, 3),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: _cell(TextField(
            controller: _name,
            focusNode: _nameF,
            readOnly: widget.readOnly,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: IosColors.tint,
            style: IosText.footnote.on(IosColors.label),
            decoration: deco,
            onSubmitted: (_) => _commitName(),
          )),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: widget.readOnly
              ? _cell(Text(t.lblReference,
                  style: IosText.footnote.on(IosColors.secondaryLabel)))
              // M180 — the Equation cell drags too, when it holds a plain
              // number. Applied per detent like everywhere else, so the sketch
              // follows the drag instead of waiting for Enter.
              : ScrubField(
                  app: widget.app,
                  controller: _eq,
                  kind: widget.kind,
                  // M206 — no number pad here. This cell is expression-first
                  // (names, functions, references to other parameters) and a
                  // pad has no letters; it keeps the real keyboard, which is
                  // the same call M171 made about the keyboard TYPE.
                  pad: false,
                  onCommit: (t) {
                    widget.commitEquation(t);
                    setState(() {});
                  },
                  child: _cell(TextField(
                    controller: _eq,
                    focusNode: _eqF,
                    autocorrect: false,
                    enableSuggestions: false,
                    cursorColor: IosColors.tint,
                    onChanged: (_) => setState(() {}),
                    style: IosText.footnote.on(
                        eqValid ? IosColors.label : IosColors.destructive),
                    decoration: deco,
                    onSubmitted: (_) => _commitEq(),
                  )),
                ),
        ),
        const SizedBox(width: 8),
        SizedBox(
            width: 90,
            child: Text(widget.value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IosText.footnote.on(IosColors.secondaryLabel))),
        SizedBox(width: 26, child: widget.trailing ?? const SizedBox()),
      ]),
    );
  }
}

class _DimRow extends StatelessWidget {
  final AppState app;
  final Constraint dim;
  const _DimRow({required this.app, required this.dim});

  static bool _angle(Constraint c) =>
      c.dimKind == 'ang' || c.dimKind == 'ang3' || c.dimKind == 'ang4';

  @override
  Widget build(BuildContext context) {
    final v = dim.value ?? 0;
    final unit = _angle(dim) ? '°' : ' mm';
    return _ParamRow(
      key: ObjectKey(dim),
      app: app,
      name: dim.paramName!,
      equation: dim.expr ?? Fmt.fixed(v, _angle(dim) ? 1 : 2),
      value: '${Fmt.fixed(v, _angle(dim) ? 1 : 2)}$unit',
      readOnly: dim.driven,
      kind: _angle(dim) ? ScrubKind.angle : ScrubKind.length,
      commitName: (t) => app.renameDimParam(dim, t),
      commitEquation: (t) => app.setDimensionText(dim, t),
      validEquation: (t) => app.dimTextValid(dim, t),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AppState app;
  final UserParam u;
  const _UserRow({required this.app, required this.u});

  @override
  Widget build(BuildContext context) {
    return _ParamRow(
      key: ObjectKey(u),
      app: app,
      name: u.name,
      equation: u.expr ?? Fmt.fixed(u.value, 2),
      value: Fmt.mm(u.value),
      commitName: (t) => app.renameUserParam(u, t),
      commitEquation: (t) => app.setUserParamText(u, t),
      validEquation: (t) => app.userParamTextValid(u, t),
      trailing: IosPressable(
        onTap: () => app.deleteUserParam(u),
        child: SizedBox(
          width: 26,
          height: 32,
          child: Center(
            child: iosGlyph(IosGlyph.xmarkCircleFill,
                size: 17, color: IosColors.destructive),
          ),
        ),
      ),
    );
  }
}
