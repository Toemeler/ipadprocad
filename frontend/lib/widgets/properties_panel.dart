// Shared chrome for Inventor-style property panels.
//
// Extracted from ExtrudeDialog when Fillet and Chamfer arrived: three panels
// with three private copies of the same section header, label row, pick field
// and value field is exactly the duplication that had already happened once
// with point-to-segment distance. The bodies here are the extrude dialog's
// originals, moved rather than reimplemented, so nothing about the existing
// panel changes appearance.
import 'package:flutter/material.dart';

import '../theme.dart';

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

Widget panelValueField(TextEditingController c, String suffix,
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

/// Greys a subtree out without removing it — the value stays readable, it
/// simply is not what drives the feature right now.
Widget panelDimWhen(bool dim, Widget child) => dim
    ? IgnorePointer(child: Opacity(opacity: 0.4, child: child))
    : child;
