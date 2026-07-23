// iPadProCAD — the Gear dialog (M61). A MOVABLE modeless window over the
// viewport, matching the Parameters / Pattern dialogs: pick a gear kind
// (External / Internal / Planetary), set the metric parameters, watch a LIVE
// preview, then place the gear with a viewport tap or the Insert button.
//
// Everything the dialog edits lives in AppState.gear (a GearSession); changing
// a field mutates the session and calls app.gearNotify(), which repaints both
// this preview and the ghost following the cursor. Insert calls app.commitGear.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../gear.dart';
import '../theme.dart';

const _fieldBg = Color(0xFF212429);
const _fieldBorder = Color(0xFF3A3F45);

TextStyle _ts(double s, Color c, {FontWeight w = FontWeight.normal}) =>
    TextStyle(fontSize: s, color: c, fontWeight: w, height: 1.1);

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
      double.tryParse(c.text.trim()) ?? fallback;
  int _i(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  void _sync() {
    final g = gs;
    g.params.module = _d(_module, g.params.module);
    g.params.teeth = _i(_teeth, g.params.teeth);
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
    final planetary = g.kind == GearKind.planetary;
    return Container(
      width: 300,
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
              Expanded(
                  child: Text('Gear',
                      style: _ts(12, T.text, w: FontWeight.w600))),
              InkWell(
                onTap: widget.app.cancelTool,
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
                _segmented(g.kind),
                const SizedBox(height: 8),
                // ---- live preview ----
                Container(
                  height: 128,
                  decoration: BoxDecoration(
                    color: const Color(0xFF171A1F),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _fieldBorder),
                  ),
                  child: CustomPaint(
                    painter: _GearPreviewPainter(g),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_infoLine(g),
                    style: _ts(10.5, T.dim), textAlign: TextAlign.left),
                const SizedBox(height: 8),
                // ---- fields ----
                _field('Module (mm)', _module),
                if (!planetary) _field('Teeth', _teeth),
                if (planetary) ...[
                  _field('Sun teeth', _sun),
                  _field('Planet teeth', _planet),
                  _field('Planets', _count),
                ],
                _field('Pressure angle (°)', _angle),
                _field('Profile shift', _shift),
                if (!planetary) _field('Bore Ø (mm)', _bore),
                const SizedBox(height: 6),
                _filletToggle(g),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  _btn('Cancel', () => widget.app.cancelTool()),
                  const SizedBox(width: 8),
                  _btn('Insert', () {
                    _sync();
                    final gg = widget.app.gear;
                    if (gg != null && !gg.placedOnce) {
                      // no tap yet: drop it at the origin so Insert always works
                      gg.center = Offset.zero;
                      gg.placedOnce = true;
                    }
                    widget.app.commitGear();
                  }, primary: true),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Tap in the sketch to place; then dimension the '
                      'centre and one angle.',
                      style: _ts(10, T.dim)),
                ),
              ]),
        ),
      ]),
    );
  }

  String _infoLine(GearSession g) {
    if (g.kind == GearKind.planetary) {
      final zr = planetaryRingTeeth(g.sunTeeth, g.planetTeeth);
      final ok = planetaryAssembles(g.sunTeeth, g.planetTeeth, g.planetCount);
      return 'Ring ${zr}T · centre dist '
          '${(g.params.module * (g.sunTeeth + g.planetTeeth) / 2).toStringAsFixed(1)} mm'
          '${ok ? '' : ' · ⚠ planets not evenly spaced'}';
    }
    final p = g.params;
    return 'Pitch Ø ${(p.pitchRadius * 2).toStringAsFixed(1)} · '
        'tip Ø ${(p.tipRadius * 2).toStringAsFixed(1)} · '
        'root Ø ${(p.rootRadius * 2).toStringAsFixed(1)} mm';
  }

  Widget _segmented(GearKind sel) {
    Widget seg(String label, GearKind k) {
      final on = sel == k;
      return Expanded(
        child: GestureDetector(
          onTap: () => _setKind(k),
          child: Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? T.blue : _fieldBg,
              border: Border.all(color: on ? T.blue : _fieldBorder),
            ),
            child: Text(label,
                style: _ts(11, on ? Colors.white : T.text,
                    w: on ? FontWeight.w600 : FontWeight.normal)),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(children: [
        seg('External', GearKind.external),
        seg('Internal', GearKind.internal),
        seg('Planetary', GearKind.planetary),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
            width: 120,
            child: Text(label, style: _ts(11.5, T.dim))),
        Expanded(
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: c,
              onChanged: (_) => _sync(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))
              ],
              style: _ts(12, T.text),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                filled: true,
                fillColor: _fieldBg,
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3),
                    borderSide: const BorderSide(color: _fieldBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3),
                    borderSide: const BorderSide(color: T.blue)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _filletToggle(GearSession g) {
    final on = g.params.fillet;
    return GestureDetector(
      onTap: () {
        g.params.fillet = !on;
        widget.app.gearNotify();
        setState(() {});
      },
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: on ? T.blue : _fieldBg,
            border: Border.all(color: on ? T.blue : _fieldBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: on
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 8),
        Text('Automatic root & tip radii', style: _ts(11.5, T.text)),
      ]),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? T.blue : Colors.transparent,
          border: Border.all(color: primary ? T.blue : _fieldBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: _ts(12.5, primary ? Colors.white : T.text,
                w: primary ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
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
              ? T.blue
              : m.role == 'ring'
                  ? const Color(0xFF54C96A)
                  : const Color(0xFFE0913A);
          loops.add((pts, col));
        }
      } else {
        final p = g.params.copy()..internal = g.kind == GearKind.internal;
        if (!p.valid) return;
        loops.add((
          gearProfile(
              center: Offset.zero, angle: 0, params: p, flankSamples: 12),
          T.blue
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
