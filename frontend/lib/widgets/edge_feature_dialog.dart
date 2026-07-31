// M136 — the Fillet / Chamfer property panel.
//
// ONE widget for both. Inventor presents them as two commands, but the panels
// differ only in the numbers under the edge list — the edge picker, the
// preview, the OK/Cancel behaviour and the whole chrome are identical, and
// two copies would be two places to keep the edge handling in step.
//
// Chrome and field widgets come from properties_panel.dart, shared with the
// extrude dialog.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'properties_panel.dart';

class EdgeFeatureDialog extends StatefulWidget {
  final AppState app;
  const EdgeFeatureDialog({super.key, required this.app});

  @override
  State<EdgeFeatureDialog> createState() => _EdgeFeatureDialogState();
}

class _EdgeFeatureDialogState extends State<EdgeFeatureDialog> {
  /// One controller per edge SET. Grown on demand; never shrunk while the
  /// panel is open, so a controller keeps its cursor if a set is re-selected.
  final List<TextEditingController> _radii = [];

  /// Optional END radius per set. Blank means that set stays constant.
  final List<TextEditingController> _radii2 = [];
  final _d1 = TextEditingController();
  final _d2 = TextEditingController();
  final _angle = TextEditingController();
  bool _inputOpen = true, _shapeOpen = true;

  /// Null until first laid out, then wherever the user dragged it to.
  Offset? _pos;
  String? _syncedFor;

  EdgeFeatureSession get sess => widget.app.edgeSession!;

  @override
  void dispose() {
    for (final c in [..._radii, ..._radii2]) {
      c.dispose();
    }
    _d1.dispose();
    _d2.dispose();
    _angle.dispose();
    super.dispose();
  }

  /// Load the session's expressions into the controllers ONCE per session.
  /// Doing it on every build would fight the user's cursor while typing —
  /// the same reason the extrude dialog seeds its fields on open only.
  void _syncOnce() {
    final s = widget.app.edgeSession;
    if (s == null) return;
    final id = '${s.kind}/${identityHashCode(s)}';
    if (_syncedFor == id) return;
    _syncedFor = id;
    _syncRadii(s);
    _d1.text = s.exprD1;
    _d2.text = s.exprD2;
    _angle.text = s.exprAngle;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.edgeSession;
    if (s == null) return const SizedBox.shrink();
    _syncOnce();
    final n = app.pickedEdges.length;
    final title = s.isFillet ? 'Fillet' : 'Chamfer';

    // M123 — the same fix M122 made for the extrude dialog: (12, 12) is the
    // top-left corner, i.e. directly underneath the floating model browser
    // card, so the panel opened half hidden behind it. Park it against the
    // right edge, vertically centred, once the viewport size is known.
    const w = 300.0, h = 520.0;
    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ??
        Offset(vp.width - w - 18, ((vp.height - h) / 2).clamp(12.0, 400.0));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
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
                  onTap: app.cancelEdgeFeature,
                  child: Text('✕', style: ts(11.5, T.dim)),
                ),
                const Spacer(),
                Icon(Icons.menu, size: 14, color: T.dim),
              ]),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                Text(s.editing?.name ?? title,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: T.blue,
                        decoration: TextDecoration.underline,
                        decorationColor: T.blue)),
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 14, color: T.dim),
              ]),
            ),
            panelSection('Input Geometry', _inputOpen,
                () => setState(() => _inputOpen = !_inputOpen), [
              panelRow(
                  'Edges',
                  GestureDetector(
                    onTap: app.pickingEdges
                        ? app.cancelPickEdges
                        : app.beginPickEdges,
                    child: Container(
                      height: 26,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF212429),
                        border: Border.all(
                            color: app.pickingEdges
                                ? T.blue
                                : const Color(0xFF3A3F45)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                          n == 0
                              ? (app.pickingEdges
                                  ? 'Tap edges in 3D…'
                                  : 'Select edges')
                              : '$n Edge${n == 1 ? '' : 's'}'
                                  '${app.pickingEdges ? ' — tap to finish' : ''}',
                          style: ts(12, n == 0 ? T.dim : T.text)),
                    ),
                  )),
            ]),
            panelSection(
                s.isFillet ? 'Radius' : 'Chamfer',
                _shapeOpen,
                () => setState(() => _shapeOpen = !_shapeOpen),
                s.isFillet ? _filletFields() : _chamferFields()),
            if (s.previewError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Text(s.previewError!,
                    style: ts(11.5, const Color(0xFFE0A030))),
              ),
            _footer(),
          ]),
        ),
      ),
    );
  }

  void _syncRadii(EdgeFeatureSession s) {
    while (_radii.length < s.exprRadii.length) {
      _radii.add(TextEditingController());
    }
    while (_radii2.length < s.exprRadii.length) {
      _radii2.add(TextEditingController());
    }
    for (var i = 0; i < s.exprRadii.length; i++) {
      if (_radii[i].text != s.exprRadii[i]) _radii[i].text = s.exprRadii[i];
      final e2 = i < s.exprRadii2.length ? s.exprRadii2[i] : '';
      if (_radii2[i].text != e2) _radii2[i].text = e2;
    }
  }

  /// One row per edge set — Inventor's "several edge sets in a single fillet
  /// feature", each with its own radius. Tapping a row makes that set the one
  /// new picks land in, so you build set 1, press +, then keep tapping edges.
  List<Widget> _filletFields() {
    final app = widget.app;
    final s = sess;
    _syncRadii(s);
    final sets = app.edgeSetCount;
    return [
      for (var i = 0; i < sets; i++) ...[
        panelRow(
            sets == 1 ? 'Radius' : 'Radius ${i + 1}',
            Row(children: [
              GestureDetector(
                onTap: () => app.selectEdgeSet(i),
                child: Container(
                  width: 62,
                  height: 26,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: i == app.activeEdgeSet
                        ? const Color(0xFF2E4A6B)
                        : const Color(0xFF2A2E33),
                    border: Border.all(
                        color: i == app.activeEdgeSet
                            ? T.blue
                            : const Color(0xFF3A3F45)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('${app.edgesInSet(i)} edge'
                      '${app.edgesInSet(i) == 1 ? '' : 's'}',
                      style: ts(11.5, T.text)),
                ),
              ),
              Expanded(
                child: panelValueField(
                    _radii[i.clamp(0, _radii.length - 1)],
                    'mm',
                    (v) => app.setEdgeFeature(exprRadius: v, radiusSet: i), app: app),
              ),
            ])),
        // Inventor's variable radius: leave blank for a constant fillet, or
        // give an end radius and it varies linearly along each edge of the set.
        panelRow(
            sets == 1 ? 'to (optional)' : 'to ${i + 1}',
            panelValueField(
                _radii2[i.clamp(0, _radii2.length - 1)],
                'mm',
                (v) => app.setEdgeFeature(exprRadius2: v, radiusSet: i), app: app)),
      ],
      // Inventor's Select Mode. Enabled once a body is known, because
      // "all edges" is meaningless without one.
      panelRow(
          'Select',
          Row(children: [
            _pill('All Fillets', () => app.selectAllEdges(concave: true),
                app.pickedEdgeSolid != null),
            const SizedBox(width: 3),
            _pill('All Rounds', () => app.selectAllEdges(concave: false),
                app.pickedEdgeSolid != null),
          ])),
      panelRow(
          '',
          GestureDetector(
            onTap: app.newEdgeSet,
            child: Container(
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2E33),
                border: Border.all(color: const Color(0xFF3A3F45)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('+ Add edge set', style: ts(11.5, T.dim)),
            ),
          )),
    ];
  }

  List<Widget> _chamferFields() {
    final s = sess;
    return [
      panelRow(
          'Method',
          Row(children: [
            _modeButton(0, 'Distance', 'd'),
            const SizedBox(width: 3),
            _modeButton(1, 'Two Distances', 'd1/d2'),
            const SizedBox(width: 3),
            _modeButton(2, 'Distance and Angle', 'd∠'),
          ])),
      panelRow(
          s.mode == 0 ? 'Distance' : 'Distance 1',
          panelValueField(
              _d1, 'mm', (v) => widget.app.setEdgeFeature(exprD1: v), app: widget.app)),
      if (s.mode == 1)
        panelRow(
            'Distance 2',
            panelValueField(
                _d2, 'mm', (v) => widget.app.setEdgeFeature(exprD2: v), app: widget.app)),
      if (s.mode == 2)
        panelRow(
            'Angle',
            panelValueField(
                _angle, 'deg', (v) => widget.app.setEdgeFeature(exprAngle: v), app: widget.app)),
      // Flip only means anything when the two sides differ.
      if (s.mode != 0)
        panelRow(
            'Flip',
            GestureDetector(
              onTap: () => widget.app.setEdgeFeature(flip: !s.flip),
              child: Container(
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.flip
                      ? const Color(0xFF2E4A6B)
                      : const Color(0xFF2A2E33),
                  border: Border.all(
                      color: s.flip ? T.blue : const Color(0xFF3A3F45)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('Swap the two faces', style: ts(12, T.text)),
              ),
            )),
    ];
  }

  Widget _pill(String label, VoidCallback onTap, bool enabled) => Expanded(
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2E33),
                border: Border.all(color: const Color(0xFF3A3F45)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(label, style: ts(11.5, T.text)),
            ),
          ),
        ),
      );

  Widget _modeButton(int mode, String tip, String label) {
    final active = sess.mode == mode;
    return Expanded(
      child: Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => widget.app.setEdgeFeature(mode: mode),
          child: Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  active ? const Color(0xFF2E4A6B) : const Color(0xFF2A2E33),
              border: Border.all(
                  color: active ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label, style: ts(11.5, T.text)),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final app = widget.app;
    final ready = app.pickedEdges.isNotEmpty && sess.previewError == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(children: [
        Expanded(
          child: Opacity(
            opacity: ready ? 1 : 0.45,
            child: GestureDetector(
              onTap: ready ? () => app.applyEdgeFeature() : null,
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: T.blue,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('OK',
                    style: ts(12.5, Colors.white, w: FontWeight.w600)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: app.cancelEdgeFeature,
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
