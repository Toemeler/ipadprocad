// Prototype — the Gear dialog (M61). A MOVABLE modeless window over the
// viewport: pick a gear kind (External / Internal / Planetary), set the metric
// parameters, watch a LIVE preview, then place the gear with a viewport tap or
// the Insert button.
//
// Everything the dialog edits lives in AppState.gear (a GearSession); changing
// a field mutates the session and calls app.gearNotify(), which repaints both
// this preview and the ghost following the cursor. Insert calls
// app.commitGear.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). The preview keeps its
// own painter and its own card; what changed is around it — the kind is a
// segmented control, the nine parameters are labelled value rows instead of a
// 120 pt label beside a bordered box, "auto root/tip fillet" is a switch, and
// Insert is the navigation bar's confirming action with Cancel opposite it.
// The sentence about tapping to place, and the pitch/tip/root readout, are the
// two sections' footers — which is where iOS puts a line that explains the
// rows above it, and is where a person can actually read them.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../gear.dart';
import '../ios_design.dart';
import '../scrub.dart';
import '../theme.dart';
import 'ios_kit.dart';
import '../l10n/fmt.dart';
import '../l10n/l.dart';

class GearDialog extends StatefulWidget {
  final AppState app;
  final void Function(Offset delta) onDrag;
  const GearDialog({super.key, required this.app, required this.onDrag});
  @override
  State<GearDialog> createState() => _GearDialogState();
}

class _GearDialogState extends State<GearDialog> {
  late final TextEditingController _module,
      _teeth,
      _corner,
      _angle,
      _shift,
      _bore,
      _sun,
      _planet,
      _count;

  GearSession get gs => widget.app.gear!;

  @override
  void initState() {
    super.initState();
    final g = gs;
    _module = TextEditingController(text: _n(g.params.module));
    _teeth = TextEditingController(text: '${g.params.teeth}');
    _corner = TextEditingController(text: _n(g.params.rootFilletRadius));
    _angle = TextEditingController(text: _n(g.params.pressureAngleDeg));
    _shift = TextEditingController(text: _n(g.params.profileShift));
    _bore = TextEditingController(text: _n(g.params.bore));
    _sun = TextEditingController(text: '${g.sunTeeth}');
    _planet = TextEditingController(text: '${g.planetTeeth}');
    _count = TextEditingController(text: '${g.planetCount}');
  }

  @override
  void dispose() {
    for (final c in [
      _module,
      _teeth,
      _corner,
      _angle,
      _shift,
      _bore,
      _sun,
      _planet,
      _count
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _n(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  double _d(TextEditingController c, double fallback) =>
      Fmt.num(c.text) ?? fallback;
  int _i(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  void _sync() {
    final g = gs;
    g.params.module = _d(_module, g.params.module);
    g.params.teeth = _i(_teeth, g.params.teeth);
    g.params.cornerRadius = _d(_corner, g.params.rootFilletRadius);
    g.params.pressureAngleDeg = _d(_angle, g.params.pressureAngleDeg);
    g.params.profileShift = _d(_shift, g.params.profileShift);
    g.params.bore = _d(_bore, g.params.bore);
    g.sunTeeth = _i(_sun, g.sunTeeth);
    g.planetTeeth = _i(_planet, g.planetTeeth);
    g.planetCount = _i(_count, g.planetCount);
    widget.app.gearNotify();
  }

  void _setKind(GearKind k) {
    gs.kind = k;
    gs.params.internal = k == GearKind.internal;
    widget.app.gearNotify();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = gs;
    final t = L.of(context);
    final planetary = g.kind == GearKind.planetary;
    return IosPanel(
      width: IosMetrics.panelWidth,
      nav: IosNavBar(
        title: t.dlgGear,
        onDrag: widget.onDrag,
        leading: IosBarButton(label: t.cancel, onTap: widget.app.cancelTool),
        trailing: IosBarButton(
          label: t.btnInsert,
          prominent: true,
          onTap: () {
            _sync();
            final gg = widget.app.gear;
            if (gg != null && !gg.placedOnce) {
              // No viewport tap yet: drop it at the CENTRE OF THE VIEW
              // (app.pan is the world point at the viewport centre), so the
              // gear always lands where the user can see it rather than
              // off-screen at the origin.
              gg.center = widget.app.pan;
              gg.placedOnce = true;
            }
            widget.app.commitGear();
          },
        ),
      ),
      children: [
        iosSection(
          footer: _infoLine(g),
          children: [
            iosStackedRow(
              child: IosSegmented<GearKind>(
                value: g.kind,
                onChanged: _setKind,
                segments: [
                  IosSegment(value: GearKind.external, label: t.gearExternal),
                  IosSegment(value: GearKind.internal, label: t.gearInternal),
                  IosSegment(
                      value: GearKind.planetary, label: t.gearPlanetary),
                ],
              ),
            ),
            iosStackedRow(
              child: Container(
                height: 132,
                decoration: ShapeDecoration(
                  color: IosColors.quaternarySystemFill,
                  shape: IosShape.border(IosMetrics.controlRadius),
                ),
                child: IosShape.clip(
                  IosMetrics.controlRadius,
                  child: CustomPaint(
                    painter: _GearPreviewPainter(g),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
        iosSection(
          footer: t.msgGearTapToPlace,
          children: [
            _field(t.lblModuleMm, _module, min: 0.1),
            if (!planetary)
              _field(t.lblTeeth, _teeth,
                  kind: ScrubKind.count, integer: true, min: 3, max: 400),
            _field(t.lblCornerRadiusMm, _corner, min: 0),
            if (planetary) ...[
              _field(t.lblSunTeeth, _sun,
                  kind: ScrubKind.count, integer: true, min: 3, max: 400),
              _field(t.lblPlanetTeeth, _planet,
                  kind: ScrubKind.count, integer: true, min: 3, max: 400),
              _field(t.lblPlanets, _count,
                  kind: ScrubKind.count, integer: true, min: 1, max: 12),
            ],
            _field(t.lblPressureAngle, _angle,
                kind: ScrubKind.angle, min: 5, max: 45),
            _field(t.lblProfileShift, _shift, kind: ScrubKind.ratio),
            if (!planetary) _field(t.lblBoreDia, _bore, min: 0),
            iosSwitchRow(
              label: t.lblAutoRootTip,
              value: g.params.fillet,
              onChanged: (v) {
                g.params.fillet = v;
                widget.app.gearNotify();
                setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  String _infoLine(GearSession g) {
    if (g.kind == GearKind.planetary) {
      final zr = planetaryRingTeeth(g.sunTeeth, g.planetTeeth);
      final ok = planetaryAssembles(g.sunTeeth, g.planetTeeth, g.planetCount);
      final t = L.current;
      return t.gearRingLine(
          '$zr',
          Fmt.fixed(g.params.module * (g.sunTeeth + g.planetTeeth) / 2, 1),
          ok ? '' : t.gearUnevenWarn);
    }
    final p = g.params;
    return L.current.gearPitchLine(
        Fmt.fixed(p.pitchRadius * 2, 1),
        Fmt.fixed(p.tipRadius * 2, 1),
        Fmt.fixed(p.rootRadius * 2, 1));
  }

  /// M180 — every one of these drags. [kind] is what the number measures: a
  /// tooth count steps by one whole tooth, the pressure angle by a degree, the
  /// profile shift by a tenth, and the millimetre fields by whatever the zoom
  /// says a notch is worth, like every other length in the app.
  ///
  /// The controllers hold BARE numbers here (the gear's parameters are set,
  /// not written as expressions), so the unit is DRAWN rather than carried in
  /// the text — see ios_kit.dart on why those are two different arguments.
  /// NO drawn unit: every one of these labels already carries it — "Modul
  /// (mm)", "Eingriffswinkel (°)", "Bohrung Ø (mm)" — and a second one beside
  /// the number would say it twice.
  Widget _field(String label, TextEditingController c,
          {ScrubKind kind = ScrubKind.length,
          bool integer = false,
          double? min,
          double? max}) =>
      iosValueRow(
        app: widget.app,
        label: label,
        controller: c,
        kind: kind,
        integer: integer,
        min: min,
        max: max,
        onChanged: (_) => _sync(),
      );
}

/// Paints the current gear (or planetary set) fitted into the preview box.
class _GearPreviewPainter extends CustomPainter {
  final GearSession g;
  _GearPreviewPainter(this.g);

  @override
  void paint(Canvas canvas, Size size) {
    final loops = <(List<Offset>, Color)>[];
    try {
      if (g.kind == GearKind.planetary) {
        if (g.sunTeeth < 4 || g.planetTeeth < 4 || g.planetCount < 2) return;
        final layout = buildPlanetaryLayout(
          base: g.params,
          sunTeeth: g.sunTeeth,
          planetTeeth: g.planetTeeth,
          planetCount: g.planetCount,
        );
        for (final m in layout.members) {
          final pts = gearProfile(
              center: m.center,
              angle: m.angle,
              params: m.params,
              flankSamples: 10);
          final col = m.role == 'sun'
              ? T.accent
              : m.role == 'ring'
                  ? T.okText
                  : T.warnText;
          loops.add((pts, col));
        }
      } else {
        final p = g.params.copy()..internal = g.kind == GearKind.internal;
        if (!p.valid) return;
        loops.add((
          gearProfile(
              center: Offset.zero, angle: 0, params: p, flankSamples: 12),
          T.accent
        ));
        if (p.bore > 1e-6) {
          loops.add((_circle(Offset.zero, p.bore / 2), T.dim));
        }
      }
    } catch (_) {
      return;
    }
    if (loops.isEmpty) return;

    // fit all loops into the box with a margin
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final (pts, _) in loops) {
      for (final o in pts) {
        if (o.dx < minX) minX = o.dx;
        if (o.dy < minY) minY = o.dy;
        if (o.dx > maxX) maxX = o.dx;
        if (o.dy > maxY) maxY = o.dy;
      }
    }
    final w = (maxX - minX).abs(), h = (maxY - minY).abs();
    if (w < 1e-6 || h < 1e-6) return;
    const margin = 10.0;
    final scale = math.min(
        (size.width - 2 * margin) / w, (size.height - 2 * margin) / h);
    if (scale <= 0) return;
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;

    Offset tx(Offset o) => Offset(
          size.width / 2 + (o.dx - cx) * scale,
          size.height / 2 - (o.dy - cy) * scale, // flip Y (world → screen)
        );

    for (final (pts, col) in loops) {
      if (pts.length < 2) continue;
      final path = Path()..moveTo(tx(pts.first).dx, tx(pts.first).dy);
      for (var i = 1; i < pts.length; i++) {
        final t = tx(pts[i]);
        path.lineTo(t.dx, t.dy);
      }
      path.close();
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..strokeJoin = StrokeJoin.round
            ..color = col);
    }
  }

  List<Offset> _circle(Offset c, double r) => [
        for (var i = 0; i <= 48; i++)
          Offset(c.dx + r * math.cos(i / 48 * 2 * math.pi),
              c.dy + r * math.sin(i / 48 * 2 * math.pi))
      ];

  @override
  bool shouldRepaint(covariant _GearPreviewPainter old) => true;
}
