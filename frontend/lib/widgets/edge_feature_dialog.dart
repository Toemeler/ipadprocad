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
import 'dialog_dock.dart';
import 'properties_panel.dart';
import '../l10n/l.dart';

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
    final title = s.isFillet ? L.of(context).btnFillet : L.of(context).btnChamfer;

    // M123 — the same fix M122 made for the extrude dialog: (12, 12) is the
    // top-left corner, i.e. directly underneath the floating model browser
    // card, so the panel opened half hidden behind it. Park it against the
    // right edge, vertically centred, once the viewport size is known.
    const w = 300.0, h = 520.0;
    final vp = MediaQuery.sizeOf(context);
    // M206 — beside the quick-tool bar, not under it. See DialogDock.
    final pos = _pos ?? DialogDock.spot(vp, const Size(w, h));
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
            boxShadow: [
              BoxShadow(
                  color: T.scrim,
                  blurRadius: 24,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
              child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: T.fly,
                border: Border(bottom: BorderSide(color: T.panelSep)),
                borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(children: [
                Text(L.of(context).dlgProperties,
                    style: ts(13, T.text, w: FontWeight.w600)),
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
                        color: T.accent,
                        decoration: TextDecoration.underline,
                        decorationColor: T.accent)),
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 14, color: T.dim),
              ]),
            ),
            panelSection(L.of(context).secInputGeometry, _inputOpen,
                () => setState(() => _inputOpen = !_inputOpen), [
              panelRow(
                  L.of(context).lblEdges,
                  GestureDetector(
                    onTap: app.pickingEdges
                        ? app.cancelPickEdges
                        : app.beginPickEdges,
                    child: Container(
                      height: 26,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: T.fly,
                        border: Border.all(
                            color: app.pickingEdges
                                ? T.accent
                                : T.panelSep),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                          n == 0
                              ? (app.pickingEdges
                                  ? L.of(context).hintTapEdgesIn3d
                                  : L.of(context).lblSelectEdges)
                              : '$n Edge${n == 1 ? '' : 's'}'
                                  '${app.pickingEdges ? ' — tap to finish' : ''}',
                          style: ts(12, n == 0 ? T.dim : T.text)),
                    ),
                  )),
            ]),
            panelSection(
                s.isFillet ? L.of(context).lblRadius : L.of(context).btnChamfer,
                _shapeOpen,
                () => setState(() => _shapeOpen = !_shapeOpen),
                s.isFillet ? _filletFields() : _chamferFields()),
            if (s.previewError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Text(s.previewError!,
                    style: ts(11.5, T.warnText)),
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
            sets == 1 ? L.of(context).lblRadius : L.of(context).lblRadiusN('${i + 1}'),
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
                        ? T.chipBg
                        : T.bg,
                    border: Border.all(
                        color: i == app.activeEdgeSet
                            ? T.accent
                            : T.panelSep),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(L.of(context).lblEdgeCount(app.edgesInSet(i)),
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
          L.of(context).select,
          Row(children: [
            _pill(L.of(context).lblAllFillets, () => app.selectAllEdges(concave: true),
                app.pickedEdgeSolid != null),
            const SizedBox(width: 3),
            _pill(L.of(context).lblAllRounds, () => app.selectAllEdges(concave: false),
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
                color: T.bg,
                border: Border.all(color: T.panelSep),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(L.of(context).btnAddEdgeSet, style: ts(11.5, T.dim)),
            ),
          )),
    ];
  }

  List<Widget> _chamferFields() {
    final s = sess;
    return [
      panelRow(
          L.of(context).lblMethod,
          Row(children: [
            _modeButton(0, L.of(context).lblDistance, 'd'),
            const SizedBox(width: 3),
            _modeButton(1, L.of(context).lblTwoDistances, 'd1/d2'),
            const SizedBox(width: 3),
            _modeButton(2, L.of(context).lblDistanceAndAngle, 'd∠'),
          ])),
      panelRow(
          s.mode == 0 ? L.of(context).lblDistance : L.of(context).lblDistance1,
          panelValueField(
              _d1, 'mm', (v) => widget.app.setEdgeFeature(exprD1: v), app: widget.app)),
      if (s.mode == 1)
        panelRow(
            L.of(context).lblDistance2,
            panelValueField(
                _d2, 'mm', (v) => widget.app.setEdgeFeature(exprD2: v), app: widget.app)),
      if (s.mode == 2)
        panelRow(
            L.of(context).lblAngle,
            panelValueField(
                _angle, 'deg', (v) => widget.app.setEdgeFeature(exprAngle: v), app: widget.app)),
      // Flip only means anything when the two sides differ.
      if (s.mode != 0)
        panelRow(
            L.of(context).lblFlip,
            GestureDetector(
              onTap: () => widget.app.setEdgeFeature(flip: !s.flip),
              child: Container(
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.flip
                      ? T.chipBg
                      : T.bg,
                  border: Border.all(
                      color: s.flip ? T.accent : T.panelSep),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(L.of(context).lblSwapFaces, style: ts(12, T.text)),
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
                color: T.bg,
                border: Border.all(color: T.panelSep),
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
                  active ? T.chipBg : T.bg,
              border: Border.all(
                  color: active ? T.accent : T.panelSep),
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
                  color: T.accent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(L.of(context).ok,
                    style: ts(12.5, T.text, w: FontWeight.w600)),
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
                color: T.bg,
                border: Border.all(color: T.panelSep),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(L.of(context).cancel, style: ts(12.5, T.text)),
            ),
          ),
        ),
      ]),
    );
  }
}
