// iPadProCAD — Extrusion properties panel (M56), the modeless dialog from
// the reference screenshot: "Properties ✕ | +" header, "Extrusion > Sketch1"
// breadcrumb, collapsible Input Geometry / Behavior / Output / Advanced
// Properties sections, OK / Cancel / +. Draggable over the viewport like
// the Pattern and Fillet dialogs (M35/M36); the viewport does the profile
// picking, this panel shows and edits the session state.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../part_model.dart';
import '../theme.dart';

class ExtrudeDialog extends StatefulWidget {
  final AppState app;
  const ExtrudeDialog({super.key, required this.app});
  @override
  State<ExtrudeDialog> createState() => _ExtrudeDialogState();
}

class _ExtrudeDialogState extends State<ExtrudeDialog> {
  Offset _pos = const Offset(12, 12);
  bool _inputOpen = true, _behaviorOpen = true, _outputOpen = true,
      _advancedOpen = true;
  late final TextEditingController _a, _b, _taper, _body;

  ExtrudeSession get sess => widget.app.extrudeSession!;

  @override
  void initState() {
    super.initState();
    _a = TextEditingController(text: sess.exprA);
    _b = TextEditingController(text: sess.exprB);
    _taper = TextEditingController(text: sess.exprTaper);
    _body = TextEditingController(text: sess.bodyName);
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _taper.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = sess;
    // Live bodies available as a Join target (empty for the base feature).
    final bodies = app.currentPart?.bodyNames ?? const <String>[];
    final sketchLabel = s.sketchName ?? 'Sketch1';
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos += d.delta),
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            color: T.panel,
            border: Border.all(color: T.sep),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x73000000),
                  blurRadius: 24,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ---- header: Properties ✕ | ... + ----
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                color: T.fly,
                border: Border(bottom: BorderSide(color: T.panelSep)),
                borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(children: [
                Text('Properties',
                    style: ts(13, Colors.white, w: FontWeight.w600)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: app.cancelExtrude,
                  child: Text('✕', style: ts(11.5, T.dim)),
                ),
                const SizedBox(width: 10),
                Text('+', style: ts(13, T.dim)),
                const Spacer(),
                Icon(Icons.search, size: 14, color: T.dim),
                const SizedBox(width: 8),
                Icon(Icons.menu, size: 14, color: T.dim),
              ]),
            ),
            // ---- breadcrumb: Extrusion > Sketch1 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                Text(s.editing?.name ?? 'Extrusion',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: T.blue,
                        decoration: TextDecoration.underline,
                        decorationColor: T.blue)),
                Text('  ›  ', style: ts(12, T.dim)),
                Text(sketchLabel, style: ts(12.5, T.text)),
                const Spacer(),
                SvgPicture.string(
                    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 2 L13 5 v5 L8 13 L3 10 V5 Z" fill="#E59B63" stroke="#a86a35" stroke-width=".8"/><path d="M3 5 L8 8 L13 5 M8 8 v5" stroke="#a86a35" stroke-width=".8" fill="none"/></svg>',
                    width: 15,
                    height: 15),
                const SizedBox(width: 8),
                Icon(Icons.visibility_outlined, size: 14, color: T.dim),
              ]),
            ),
            _section('Input Geometry', _inputOpen,
                () => setState(() => _inputOpen = !_inputOpen), [
              _row('Profiles', _pickField(
                  icon: Icons.touch_app_outlined,
                  label: s.profiles.isEmpty
                      ? 'Select a profile in the viewport'
                      : '${s.profiles.length} Profile'
                          '${s.profiles.length == 1 ? '' : 's'}',
                  active: true,
                  onClear:
                      s.profiles.isEmpty ? null : app.clearSessionProfiles)),
              _row('From', _pickField(
                  icon: Icons.layers_outlined,
                  label: '1 Sketch Plane',
                  active: false)),
            ]),
            _section('Behavior', _behaviorOpen,
                () => setState(() => _behaviorOpen = !_behaviorOpen), [
              _row(
                  'Direction',
                  Row(children: [
                    for (final d in ExtrudeDirection.values) ...[
                      _dirButton(d),
                      const SizedBox(width: 4),
                    ],
                    const Spacer(),
                    Text('▾', style: ts(9, T.dim)),
                  ])),
              _row('Distance A',
                  _valueField(_a, 'mm', (v) => app.setExtrude(exprA: v))),
              if (s.direction == ExtrudeDirection.asymmetric)
                _row('Distance B',
                    _valueField(_b, 'mm', (v) => app.setExtrude(exprB: v))),
            ]),
            _section('Output', _outputOpen,
                () => setState(() => _outputOpen = !_outputOpen), [
              // Inventor's Output boolean, applied against the existing body:
              // Join (union), Cut (subtract), Intersect (overlap), New Solid
              // (separate body). Cut/Intersect need something to act on, so
              // they are dimmed for the base feature.
              _row(
                  'Boolean',
                  Row(children: [
                    _boolButton('join', 'Join'),
                    const SizedBox(width: 6),
                    _boolButton('cut', 'Cut',
                        enabled: app.extrudeHasBooleanTarget),
                    const SizedBox(width: 6),
                    _boolButton('intersect', 'Intersect',
                        enabled: app.extrudeHasBooleanTarget),
                    const SizedBox(width: 6),
                    _boolButton('new', 'New Solid'),
                    const Spacer(),
                  ])),
              // Inventor: with Join you PICK a target body (and only need to
              // when there is more than one); a name is yours to type only for
              // New Solid.
              if (s.output == 'join' && bodies.isNotEmpty)
                _row(
                    bodies.length == 1 ? 'Body' : 'Target Body',
                    bodies.length == 1
                        ? Container(
                            height: 26,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(bodies.first, style: ts(12.5, T.text)),
                          )
                        : Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF212429),
                              border:
                                  Border.all(color: const Color(0xFF3A3F45)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: bodies.contains(s.bodyName)
                                    ? s.bodyName
                                    : bodies.last,
                                isDense: true,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF212429),
                                style: ts(12.5, T.text),
                                items: [
                                  for (final b in bodies)
                                    DropdownMenuItem(
                                        value: b,
                                        child: Text(b, style: ts(12.5, T.text)))
                                ],
                                onChanged: (v) {
                                  if (v != null) app.setExtrude(bodyName: v);
                                },
                              ),
                            ),
                          ))
              else
                _row(
                  'Body Name',
                  Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF212429),
                      border: Border.all(color: const Color(0xFF3A3F45)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: TextField(
                      controller: _body,
                      style: ts(12.5, T.text),
                      decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(bottom: 10)),
                      onChanged: (v) => app.setExtrude(bodyName: v),
                    ),
                  ),
                ),
            ]),
            _section('Advanced Properties', _advancedOpen,
                () => setState(() => _advancedOpen = !_advancedOpen), [
              _row(
                  'Taper A',
                  _valueField(
                      _taper, 'deg', (v) => app.setExtrude(exprTaper: v),
                      trailingIcon: Icons.edit_outlined)),
              _checkRow('iMate', s.iMate, true,
                  (v) => app.setExtrude(iMate: v)),
              _checkRow('Match Shape', s.matchShape, false, (_) {}),
            ]),
            if (s.previewError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      size: 13, color: Color(0xFFE05A56)),
                  const SizedBox(width: 5),
                  Expanded(
                      child: Text(s.previewError!,
                          style: ts(10.5, const Color(0xFFE0928F)))),
                ]),
              ),
            // ---- OK / Cancel / + ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(children: [
                _btn('OK', primary: true,
                    onTap: () => app.applyExtrude(keepOpen: false)),
                const SizedBox(width: 8),
                _btn('Cancel', onTap: app.cancelExtrude),
                const Spacer(),
                Tooltip(
                  message: 'Apply and start another',
                  child: GestureDetector(
                    onTap: () => app.applyExtrude(keepOpen: true),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: const Color(0xFF3FA43C)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Center(
                          child: Text('+',
                              style: TextStyle(
                                  fontSize: 16,
                                  height: 1,
                                  color: Color(0xFF5CBF4A)))),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String title, bool open, VoidCallback onToggle,
          List<Widget> children) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Container(
            height: 24,
            margin: const EdgeInsets.fromLTRB(6, 3, 6, 0),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            color: const Color(0xFF2E3237),
            child: Row(children: [
              Text(open ? '▾' : '▸', style: ts(9, T.dim)),
              const SizedBox(width: 6),
              Text(title, style: ts(12, T.text, w: FontWeight.w600)),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Column(children: children),
          ),
      ]);

  Widget _row(String label, Widget field) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 82, child: Text(label, style: ts(12, T.dim))),
          Expanded(child: field),
        ]),
      );

  Widget _pickField(
      {required IconData icon,
      required String label,
      required bool active,
      VoidCallback? onClear}) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF212429),
        border: Border.all(
            color: active ? T.blue : const Color(0xFF3A3F45),
            width: active ? 1.4 : 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(children: [
        Icon(icon, size: 13, color: active ? T.blue : T.dim),
        const SizedBox(width: 6),
        Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: ts(12, T.text))),
        if (onClear != null)
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.cancel_outlined,
                size: 13, color: Color(0xFF9EA4AA)),
          ),
      ]),
    );
  }

  Widget _valueField(TextEditingController c, String suffix,
      ValueChanged<String> onChanged,
      {IconData? trailingIcon}) {
    return Row(children: [
      Expanded(
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF212429),
            border: Border.all(color: const Color(0xFF3A3F45)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: c,
                style: ts(12.5, T.text),
                decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.only(bottom: 10)),
                onChanged: onChanged,
              ),
            ),
            Text('▸', style: ts(9, T.dim)),
          ]),
        ),
      ),
      const SizedBox(width: 6),
      Icon(trailingIcon ?? Icons.swap_vert,
          size: 15, color: T.dim),
    ]);
  }

  /// Inventor Output-boolean toggle: a compact icon button (like [_dirButton])
  /// with a tooltip. [enabled] false dims it and ignores taps — used for
  /// Cut/Intersect when there is no body to act on yet.
  Widget _boolButton(String key, String label, {bool enabled = true}) {
    final active = sess.output == key;
    const icons = {
      // two overlapping squares merged = union
      'join':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3" y="6.5" width="8" height="8" rx="1" fill="#E8C63F" fill-opacity=".22" stroke="#E8C63F" stroke-width="1.3"/><rect x="7" y="3.5" width="8" height="8" rx="1" fill="#E8C63F" fill-opacity=".22" stroke="#E8C63F" stroke-width="1.3"/></svg>',
      // base square, dashed tool being removed from a corner = difference
      'cut':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M3 6.5 h5 V3.5 h7 v11 H3 Z" fill="#9aa0a6" fill-opacity=".28" stroke="#9aa0a6" stroke-width="1.2"/><rect x="8" y="3.5" width="7" height="7" fill="none" stroke="#E8C63F" stroke-width="1.2" stroke-dasharray="2 1.4"/></svg>',
      // two outlined squares, only the overlap lens filled = intersection
      'intersect':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3" y="6.5" width="8" height="8" fill="none" stroke="#9aa0a6" stroke-width="1.1"/><rect x="7" y="3.5" width="8" height="8" fill="none" stroke="#9aa0a6" stroke-width="1.1"/><rect x="7" y="6.5" width="4" height="5" fill="#E8C63F" fill-opacity=".6" stroke="#E8C63F" stroke-width="1"/></svg>',
      // single square with a small plus = a brand-new body
      'new':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3.5" y="5.5" width="9" height="9" rx="1" fill="#E8C63F" fill-opacity=".2" stroke="#E8C63F" stroke-width="1.3"/><path d="M13 3 v3.4 M11.3 4.7 h3.4" stroke="#E8C63F" stroke-width="1.3"/></svg>',
    };
    return Tooltip(
      message: enabled ? label : '$label (needs an existing body)',
      child: GestureDetector(
        onTap: enabled
            ? () {
                widget.app.setExtrude(output: key);
                setState(() {});
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 28,
            height: 26,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2F6FB0) : const Color(0xFF212429),
              border: Border.all(
                  color: active ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
                child: SvgPicture.string(icons[key]!, width: 16, height: 16)),
          ),
        ),
      ),
    );
  }

  Widget _dirButton(ExtrudeDirection d) {
    final active = sess.direction == d;
    final icons = {
      ExtrudeDirection.defaultDir: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 14 V5 M9 5 l-2.6 2.8 M9 5 l2.6 2.8" stroke="#E8C63F" stroke-width="1.7" fill="none"/><path d="M4 14 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
      ExtrudeDirection.flipped: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 4 V13 M9 13 l-2.6-2.8 M9 13 l2.6-2.8" stroke="#E8C63F" stroke-width="1.7" fill="none"/><path d="M4 4 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
      ExtrudeDirection.symmetric: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 9 V3.5 M9 3.5 l-2.2 2.4 M9 3.5 l2.2 2.4 M9 9 V14.5 M9 14.5 l-2.2-2.4 M9 14.5 l2.2-2.4" stroke="#E8C63F" stroke-width="1.5" fill="none"/><path d="M4 9 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
      ExtrudeDirection.asymmetric: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M7 11 V3 M7 3 l-2.2 2.4 M7 3 l2.2 2.4" stroke="#E8C63F" stroke-width="1.5" fill="none"/><path d="M11 11 V15 M11 15 l-1.8-2 M11 15 l1.8-2" stroke="#E8C63F" stroke-width="1.3" fill="none"/><path d="M3 11 h12" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
    };
    return Tooltip(
      message: switch (d) {
        ExtrudeDirection.defaultDir => 'Default',
        ExtrudeDirection.flipped => 'Flipped',
        ExtrudeDirection.symmetric => 'Symmetric',
        ExtrudeDirection.asymmetric => 'Asymmetric',
      },
      child: GestureDetector(
        onTap: () {
          widget.app.setExtrude(direction: d);
          setState(() {});
        },
        child: Container(
          width: 28,
          height: 26,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2F6FB0) : const Color(0xFF212429),
            border: Border.all(
                color: active ? T.blue : const Color(0xFF3A3F45)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
              child:
                  SvgPicture.string(icons[d]!, width: 16, height: 16)),
        ),
      ),
    );
  }

  Widget _checkRow(
      String label, bool value, bool enabled, ValueChanged<bool> onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onTap(!value) : null,
        child: Row(children: [
          Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: value
                  ? (enabled ? T.blue : const Color(0xFF2B3946))
                  : const Color(0xFF212429),
              border: Border.all(color: const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: value
                ? Icon(Icons.check,
                    size: 12,
                    color: enabled ? Colors.white : const Color(0xFF6A6F77))
                : null,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: ts(12, enabled ? T.text : const Color(0xFF6A6F77))),
        ]),
      ),
    );
  }

  Widget _btn(String label, {bool primary = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? T.blue : Colors.transparent,
          border:
              Border.all(color: primary ? T.blue : const Color(0xFF3A3F45)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: ts(12.5, primary ? Colors.white : T.text,
                w: primary ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}
