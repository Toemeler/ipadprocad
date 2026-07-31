// Shared chrome for Inventor-style property panels.
//
// Extracted from ExtrudeDialog when Fillet and Chamfer arrived: three panels
// with three private copies of the same section header, label row, pick field
// and value field is exactly the duplication that had already happened once
// with point-to-segment distance. The bodies here are the extrude dialog's
// originals, moved rather than reimplemented, so nothing about the existing
// panel changes appearance.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../scrub.dart';
import '../theme.dart';
import 'scrub_field.dart';

Widget panelSection(String title, bool open, VoidCallback onToggle,
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

Widget panelRow(String label, Widget field) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 82, child: Text(label, style: ts(12, T.dim))),
        Expanded(child: field),
      ]),
    );

Widget panelPickField(
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

/// M172 — [app] makes the field DRAGGABLE. Optional so a caller that has no
/// AppState to hand still gets a plain field rather than failing to compile;
/// every real caller passes it, and a field that silently refuses to scrub is
/// the one bug this signature is shaped to prevent — it is one argument, in
/// one place, for every value in every feature dialog.
Widget panelValueField(TextEditingController c, String suffix,
    ValueChanged<String> onChanged,
    {IconData? trailingIcon, AppState? app}) {
  final row = Row(children: [
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
              // M171 — the compact numeric pad on touch and Pencil. This one
              // field backs every value in the extrude, revolve, coil, fillet
              // and chamfer dialogs, so it is the highest-leverage place to
              // put it.
              keyboardType: kValueKeyboard,
              // M179 — and no Scribble on it. The Pencil's job on a number is
              // to SCRUB it (the ScrubField below); handwriting recognition
              // would claim that stroke before the gesture ever saw it.
              stylusHandwritingEnabled: kValueHandwriting,
              autocorrect: false,
              enableSuggestions: false,
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
  if (app == null) return row;
  return ScrubField(
    app: app,
    controller: c,
    suffix: suffix,
    // M180 — the unit the caller already passes is the answer to "what does
    // this number measure", so no dialog has to say it twice: 'deg' steps in
    // degrees, 'ul' (a coil's turns) in tenths, everything else in the
    // zoom's own millimetres.
    kind: scrubKindForUnit(suffix),
    onCommit: onChanged,
    child: row,
  );
}

/// Greys a subtree out without removing it — the value stays readable, it
/// simply is not what drives the feature right now.
Widget panelDimWhen(bool dim, Widget child) => dim
    ? IgnorePointer(child: Opacity(opacity: 0.4, child: child))
    : child;
