// M43 — Inventors Parameters dialog (Manage > fx Parameters).
//
// A MOVABLE modeless window over the viewport: a table of every model
// parameter (the dimensions: name, equation, value — driven ones read-only)
// and the user parameters, plus an Add row. Name cells rename (references
// follow), equation cells accept the full M41 expression grammar with live
// red validation, and while an equation cell is focused, tapping a
// dimension label in the viewport inserts its parameter name at the cursor
// (AppState.paramRefSink). Dragging the title bar moves the window.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../constraints.dart';
import '../params.dart';
import '../theme.dart';

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
    final s = app.current;
    final dims = <Constraint>[
      if (s != null)
        for (final c in s.constraints)
          if (c.type == CType.dimension && c.paramName != null) c
    ];
    return Container(
      width: 420,
      constraints: const BoxConstraints(maxHeight: 380),
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
              const Text('fx',
                  style: TextStyle(
                      color: T.blue,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              const Expanded(
                  child: Text('Parameters',
                      style: TextStyle(color: T.text, fontSize: 12))),
              InkWell(
                onTap: app.toggleParams,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: T.dim),
                ),
              ),
            ]),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _header(),
              _section('Model Parameters'),
              if (dims.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('No dimensions in this sketch.',
                        style: TextStyle(color: T.dim, fontSize: 11))),
              for (final c in dims) _DimRow(app: app, dim: c),
              const SizedBox(height: 6),
              _section('User Parameters'),
              if (s != null)
                for (final u in s.userParams) _UserRow(app: app, u: u),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  onTap: () => setState(() => app.addUserParam()),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 14, color: T.blue),
                    SizedBox(width: 4),
                    Text('Add numeric parameter',
                        style: TextStyle(color: T.blue, fontSize: 11)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(t,
            style: const TextStyle(
                color: T.dim, fontSize: 10, fontWeight: FontWeight.w600)),
      );

  Widget _header() => const Padding(
        padding: EdgeInsets.only(bottom: 2),
        child: Row(children: [
          SizedBox(
              width: 96,
              child: Text('Parameter Name',
                  style: TextStyle(color: T.dim, fontSize: 10))),
          SizedBox(width: 6),
          Expanded(
              child:
                  Text('Equation', style: TextStyle(color: T.dim, fontSize: 10))),
          SizedBox(width: 6),
          SizedBox(
              width: 86,
              child: Text('Value', style: TextStyle(color: T.dim, fontSize: 10))),
          SizedBox(width: 22),
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

  @override
  Widget build(BuildContext context) {
    final eqValid = widget.readOnly || widget.validEquation(_eq.text);
    InputDecoration deco() => const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6));
    Widget cell(Widget child) => Container(
          height: 26,
          decoration: BoxDecoration(
              color: const Color(0xFF262B31),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: T.sep, width: 0.5)),
          alignment: Alignment.centerLeft,
          child: child,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: cell(TextField(
            controller: _name,
            focusNode: _nameF,
            readOnly: widget.readOnly,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 11, color: T.text),
            decoration: deco(),
            onSubmitted: (_) => _commitName(),
          )),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: cell(widget.readOnly
              ? const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('(reference)',
                      style: TextStyle(fontSize: 11, color: T.dim)))
              : TextField(
                  controller: _eq,
                  focusNode: _eqF,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                      fontSize: 11,
                      color: eqValid ? T.text : const Color(0xFFE05A5A)),
                  decoration: deco(),
                  onSubmitted: (_) => _commitEq(),
                )),
        ),
        const SizedBox(width: 6),
        SizedBox(
            width: 86,
            child: Text(widget.value,
                style: const TextStyle(fontSize: 11, color: T.dim))),
        SizedBox(width: 22, child: widget.trailing ?? const SizedBox()),
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
    final unit = _angle(dim) ? '\u00b0' : ' mm';
    return _ParamRow(
      key: ObjectKey(dim),
      app: app,
      name: dim.paramName!,
      equation: dim.expr ?? v.toStringAsFixed(_angle(dim) ? 1 : 2),
      value: '${v.toStringAsFixed(_angle(dim) ? 1 : 2)}$unit',
      readOnly: dim.driven,
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
      equation: u.expr ?? u.value.toStringAsFixed(2),
      value: '${u.value.toStringAsFixed(2)} mm',
      commitName: (t) => app.renameUserParam(u, t),
      commitEquation: (t) => app.setUserParamText(u, t),
      validEquation: (t) => app.userParamTextValid(u, t),
      trailing: InkWell(
        onTap: () => app.deleteUserParam(u),
        child: const Icon(Icons.delete_outline, size: 14, color: T.dim),
      ),
    );
  }
}
