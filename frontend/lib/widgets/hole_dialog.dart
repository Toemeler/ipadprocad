// M225 — Inventor's Hole panel.
//
// The panel shows exactly what the FEATURE can do: placements, a diameter, the
// four mouth shapes (M226) and how deep. Threads and the drill-point angle are
// each a second set of numbers and are still not offered — an empty section
// that promised them would be the dead control M216 spent a commit removing.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). Two changes beyond the
// chrome are worth naming:
//
//   * THE SHAPE IS A MENU ROW, not a four-way switch. "Plansenkung" and
//     "Kegelsenkung" are eleven and twelve characters; four of them share
//     308 pt in a segmented control and every one comes out an ellipsis. A
//     pop-up row shows the whole name of the chosen shape and, when tapped,
//     the whole name of every alternative — in a real UIMenu on the device.
//   * THE SHAPE NAMES ARE LOCALISED. This panel called `holeTypeShort` and
//     `holeTypeLabel`, which are part_model's ENGLISH domain vocabulary and
//     are English by design (S12-i18n §4.7). `holeTypeShortDisplay` and
//     `holeTypeDisplay` in l10n/cad_terms.dart exist for exactly this and
//     were never wired up here; a German UI has been reading "C'bore depth"
//     since M226.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import '../part_model.dart' show FeatureExtent, HoleType;
import 'dialog_dock.dart';
import 'ios_kit.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';

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

  static const _size = Size(IosMetrics.panelWidth, 520);

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
    final t = L.of(context);
    final n = s.places.length;
    final through = s.extent == FeatureExtent.throughAll;
    final sunk = s.type == HoleType.counterbore || s.type == HoleType.spotface;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: s.editing?.name ?? t.btnHole,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelHole),
          trailing: IosBarButton(
              label: t.ok, prominent: true, onTap: n > 0 ? app.applyHole : null),
        ),
        children: [
          iosSection(
            header: t.secPlacement,
            open: _placeOpen,
            onToggle: () => setState(() => _placeOpen = !_placeOpen),
            children: [
              // The panel is ALWAYS picking while it is open: a hole has
              // nothing else to tap in 3D, so a separate "select" mode would
              // be a button whose only job is to be on.
              iosPickRow(
                label: t.lblPoints,
                value: n == 0
                    ? null
                    : t.lblPointsCount(n) +
                        (s.sketchName == null ? '' : ' · ${s.sketchName}'),
                hint: t.hintTapSketchPointsIn3d,
                armed: n == 0,
                filled: n > 0,
              ),
            ],
          ),
          iosSection(
            header: t.btnHole,
            open: _shapeOpen,
            onToggle: () => setState(() => _shapeOpen = !_shapeOpen),
            children: [
              IosMenuRow<HoleType>(
                label: t.lblType,
                value: s.type,
                cancelLabel: t.cancel,
                choices: [
                  for (final h in HoleType.values)
                    IosMenuChoice(h, holeTypeDisplay(t, h)),
                ],
                onChanged: (v) => app.setHole(type: v),
              ),
              iosValueRow(
                app: app,
                label: t.lblDiameter,
                controller: _dia,
                unit: 'mm',
                onChanged: (v) => app.setHole(exprDia: v),
              ),
              if (sunk) ...[
                iosValueRow(
                  app: app,
                  label: '${holeTypeShortDisplay(t, s.type)} ⌀',
                  controller: _cbDia,
                  unit: 'mm',
                  onChanged: (v) => app.setHole(exprCbDia: v),
                ),
                iosValueRow(
                  app: app,
                  label: '${holeTypeShortDisplay(t, s.type)} ${t.lblDepth}',
                  controller: _cbDepth,
                  unit: 'mm',
                  onChanged: (v) => app.setHole(exprCbDepth: v),
                ),
              ],
              if (s.type == HoleType.countersink) ...[
                iosValueRow(
                  app: app,
                  label: t.lblCountersinkDia,
                  controller: _csDia,
                  unit: 'mm',
                  onChanged: (v) => app.setHole(exprCsDia: v),
                ),
                iosValueRow(
                  app: app,
                  label: t.lblAngle,
                  controller: _csAngle,
                  unit: 'deg',
                  onChanged: (v) => app.setHole(exprCsAngle: v),
                ),
              ],
              iosStackedRow(
                label: t.lblTermination,
                child: IosSegmented<bool>(
                  value: through,
                  onChanged: (v) => app.setHole(
                      extent: v
                          ? FeatureExtent.throughAll
                          : FeatureExtent.distance),
                  segments: [
                    IosSegment(value: false, label: t.lblDistance),
                    IosSegment(value: true, label: t.extThroughAll),
                  ],
                ),
              ),
              if (!through)
                iosValueRow(
                  app: app,
                  label: t.lblDepth,
                  controller: _depth,
                  unit: 'mm',
                  onChanged: (v) => app.setHole(exprDepth: v),
                ),
              iosStackedRow(
                label: t.lblDirection,
                child: IosSegmented<bool>(
                  value: s.flip,
                  onChanged: (v) => app.setHole(flip: v),
                  segments: [
                    IosSegment(value: false, label: t.lblIntoPart),
                    IosSegment(value: true, label: t.lblFlipped),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
