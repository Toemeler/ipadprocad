// M225 — Inventor's Hole panel.
//
// Chrome and field widgets from properties_panel.dart, exactly as the extrude
// and fillet panels use them: three panels that looked alike by copy were the
// reason that file exists, and a fourth copy would undo it.
//
// The panel shows exactly what the FEATURE can do: placements, a diameter, the
// four mouth shapes (M226) and how deep. Threads and the drill-point angle are
// each a second set of numbers and are still not offered — an empty section
// that promised them would be the dead control M216 spent a commit removing.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../part_model.dart'
    show FeatureExtent, HoleType, holeTypeLabel, holeTypeShort;
import '../theme.dart';
import 'dialog_dock.dart';
import 'properties_panel.dart';

class HoleDialog extends StatefulWidget {
  final AppState app;
  const HoleDialog({super.key, required this.app});

  @override
  State<HoleDialog> createState() => _HoleDialogState();
}

class _HoleDialogState extends State<HoleDialog> {
  final _dia = TextEditingController();
  final _depth = TextEditingController();
  final _cbDia = TextEditingController();
  final _cbDepth = TextEditingController();
  final _csDia = TextEditingController();
  final _csAngle = TextEditingController();
  bool _placeOpen = true, _shapeOpen = true;
  Offset? _pos;
  String? _syncedFor;

  @override
  void dispose() {
    _dia.dispose();
    _depth.dispose();
    _cbDia.dispose();
    _cbDepth.dispose();
    _csDia.dispose();
    _csAngle.dispose();
    super.dispose();
  }

  /// Seed the controllers ONCE per session — doing it every build would fight
  /// the cursor while typing, the same reason the other panels sync on open.
  void _syncOnce(HoleSession s) {
    final id = '${identityHashCode(s)}';
    if (_syncedFor == id) return;
    _syncedFor = id;
    _dia.text = s.exprDia;
    _depth.text = s.exprDepth;
    _cbDia.text = s.exprCbDia;
    _cbDepth.text = s.exprCbDepth;
    _csDia.text = s.exprCsDia;
    _csAngle.text = s.exprCsAngle;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.holeSession;
    if (s == null) return const SizedBox.shrink();
    _syncOnce(s);
    final n = s.places.length;
    final through = s.extent == FeatureExtent.throughAll;

    const w = 300.0, h = 420.0;
    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, const Size(w, h));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w,
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
            GestureDetector(
              onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
              child: Container(
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
                    onTap: app.cancelHole,
                    child: Text('✕', style: ts(11.5, T.dim)),
                  ),
                  const Spacer(),
                  Icon(Icons.menu, size: 14, color: T.dim),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                Text(s.editing?.name ?? 'Hole',
                    style: ts(12.5, T.blue)),
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 14, color: T.dim),
              ]),
            ),
            panelSection('Placement', _placeOpen,
                () => setState(() => _placeOpen = !_placeOpen), [
              panelRow(
                  'Points',
                  panelPickField(
                    icon: Icons.control_point,
                    // The panel is ALWAYS picking while it is open: a hole has
                    // nothing else to tap in 3D, so a separate "select" mode
                    // would be a button whose only job is to be on.
                    active: true,
                    label: n == 0
                        ? 'Tap sketch points in 3D…'
                        : '$n point${n == 1 ? '' : 's'}'
                            '${s.sketchName == null ? '' : ' on ${s.sketchName}'}',
                  )),
            ]),
            panelSection('Hole', _shapeOpen,
                () => setState(() => _shapeOpen = !_shapeOpen), [
              // M226 — Inventor's four shapes. Spotface is drawn like a
              // counterbore and kept apart because it MEANS something else.
              panelRow(
                  'Type',
                  Row(children: [
                    for (final t in HoleType.values) ...[
                      if (t != HoleType.values.first) const SizedBox(width: 4),
                      _seg(holeTypeShort(t), s.type == t,
                          () => app.setHole(type: t)),
                    ],
                  ])),
              panelRow(
                  'Diameter',
                  panelValueField(_dia, 'mm',
                      (v) => app.setHole(exprDia: v), app: app)),
              if (s.type == HoleType.counterbore ||
                  s.type == HoleType.spotface) ...[
                panelRow(
                    '${holeTypeLabel(s.type)} ⌀',
                    panelValueField(_cbDia, 'mm',
                        (v) => app.setHole(exprCbDia: v), app: app)),
                panelRow(
                    '${holeTypeLabel(s.type)} depth',
                    panelValueField(_cbDepth, 'mm',
                        (v) => app.setHole(exprCbDepth: v), app: app)),
              ],
              if (s.type == HoleType.countersink) ...[
                panelRow(
                    'Countersink ⌀',
                    panelValueField(_csDia, 'mm',
                        (v) => app.setHole(exprCsDia: v), app: app)),
                panelRow(
                    'Angle',
                    panelValueField(_csAngle, 'deg',
                        (v) => app.setHole(exprCsAngle: v), app: app)),
              ],
              panelRow(
                  'Termination',
                  Row(children: [
                    _seg('Distance', !through,
                        () => app.setHole(extent: FeatureExtent.distance)),
                    const SizedBox(width: 6),
                    _seg('Through All', through,
                        () => app.setHole(extent: FeatureExtent.throughAll)),
                  ])),
              if (!through)
                panelRow(
                    'Depth',
                    panelValueField(_depth, 'mm',
                        (v) => app.setHole(exprDepth: v), app: app)),
              panelRow(
                  'Direction',
                  Row(children: [
                    _seg('Into part', !s.flip, () => app.setHole(flip: false)),
                    const SizedBox(width: 6),
                    _seg('Flipped', s.flip, () => app.setHole(flip: true)),
                  ])),
            ]),
            _footer(app, n),
          ]),
        ),
      ),
    );
  }

  Widget _seg(String label, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? T.blue : const Color(0xFF212429),
              border: Border.all(
                  color: on ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label,
                style: ts(11.5, on ? Colors.white : T.text)),
          ),
        ),
      );

  Widget _footer(AppState app, int n) {
    final ready = n > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(children: [
        Expanded(
          child: Opacity(
            opacity: ready ? 1 : 0.45,
            child: GestureDetector(
              onTap: ready ? () => app.applyHole() : null,
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: T.blue, borderRadius: BorderRadius.circular(3)),
                child: Text('OK',
                    style: ts(12.5, Colors.white, w: FontWeight.w600)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: app.cancelHole,
            child: Container(
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2E33),
                border: Border.all(color: const Color(0xFF3A3F45)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('Cancel', style: ts(12.5, T.text)),
            ),
          ),
        ),
      ]),
    );
  }
}
