// M136 — the Fillet / Chamfer property panel.
//
// ONE widget for both. Inventor presents them as two commands, but the panels
// differ only in the numbers under the edge list — the edge picker, the
// preview, the OK/Cancel behaviour and the whole chrome are identical, and
// two copies would be two places to keep the edge handling in step.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). The fillet's edge SETS
// are the part that changed shape rather than only style: each set used to be
// a 62 pt button with a count in it beside its radius field, which is a
// two-control row that says nothing about which set is armed until you read
// the border colour. A set is now a row of its own — the count on the left,
// the radius on the right, and the ARMED one tinted the way a selected row is
// tinted anywhere else in this app since this milestone. Its optional end
// radius is the row underneath, and it appears only for the set being edited,
// which is what Inventor's variable-radius list does.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';
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

  static const _size = Size(IosMetrics.panelWidth, 520);

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
    final t = L.of(context);
    final n = app.pickedEdges.length;
    final title = s.isFillet ? t.btnFillet : t.btnChamfer;
    final ready = n > 0 && s.previewError == null;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: s.editing?.name ?? title,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelEdgeFeature),
          trailing: IosBarButton(
              label: t.ok,
              prominent: true,
              onTap: ready ? app.applyEdgeFeature : null),
        ),
        children: [
          iosSection(
            header: t.secInputGeometry,
            open: _inputOpen,
            onToggle: () => setState(() => _inputOpen = !_inputOpen),
            children: [
              iosPickRow(
                label: t.lblEdges,
                value: n == 0 ? null : t.lblEdgeCount(n),
                hint: app.pickingEdges ? t.hintTapEdgesIn3d : t.lblSelectEdges,
                armed: app.pickingEdges,
                filled: n > 0,
                onTap:
                    app.pickingEdges ? app.cancelPickEdges : app.beginPickEdges,
              ),
              if (s.isFillet)
                iosStackedRow(
                  label: t.select,
                  enabled: app.pickedEdgeSolid != null,
                  child: Row(children: [
                    Expanded(
                      child: IosButton(
                          label: t.lblAllFillets,
                          style: IosButtonStyle.grey,
                          height: 34,
                          expand: true,
                          onTap: () => app.selectAllEdges(concave: true)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IosButton(
                          label: t.lblAllRounds,
                          style: IosButtonStyle.grey,
                          height: 34,
                          expand: true,
                          onTap: () => app.selectAllEdges(concave: false)),
                    ),
                  ]),
                ),
            ],
          ),
          iosSection(
            header: s.isFillet ? t.lblRadius : t.btnChamfer,
            open: _shapeOpen,
            onToggle: () => setState(() => _shapeOpen = !_shapeOpen),
            footer: s.isFillet ? t.hintEndRadiusOptional : null,
            children: s.isFillet ? _filletRows() : _chamferRows(),
          ),
          if (s.previewError != null) iosStatusLine(s.previewError!),
        ],
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
  List<Widget> _filletRows() {
    final app = widget.app;
    final t = L.of(context);
    final s = sess;
    _syncRadii(s);
    final sets = app.edgeSetCount;
    return [
      for (var i = 0; i < sets; i++) ...[
        Container(
          color: i == app.activeEdgeSet && sets > 1
              ? IosColors.tintedFill
              : null,
          child: iosValueRow(
            app: app,
            label: sets == 1 ? t.lblRadius : t.lblRadiusN('${i + 1}'),
            controller: _radii[i.clamp(0, _radii.length - 1)],
            unit: 'mm',
            onChanged: (v) => app.setEdgeFeature(exprRadius: v, radiusSet: i),
            leading: sets == 1
                ? null
                : IosPressable(
                    onTap: () => setState(() => app.selectEdgeSet(i)),
                    child: Text(t.lblEdgeCount(app.edgesInSet(i)),
                        style: IosText.footnote.on(
                            i == app.activeEdgeSet
                                ? IosColors.tint
                                : IosColors.secondaryLabel)),
                  ),
          ),
        ),
        // Inventor's variable radius: leave blank for a constant fillet, or
        // give an end radius and it varies linearly along each edge of the
        // set. Shown for the ARMED set only — a second field per set is a
        // second field to read past on every one you are not editing.
        if (sets == 1 || i == app.activeEdgeSet)
          iosValueRow(
            app: app,
            label: t.lblEndRadius,
            controller: _radii2[i.clamp(0, _radii2.length - 1)],
            unit: 'mm',
            onChanged: (v) => app.setEdgeFeature(exprRadius2: v, radiusSet: i),
          ),
      ],
      iosStackedRow(
        child: IosButton(
            label: t.btnAddEdgeSet,
            glyph: IosGlyph.plus,
            style: IosButtonStyle.tinted,
            height: 34,
            expand: true,
            onTap: () => setState(app.newEdgeSet)),
      ),
    ];
  }

  List<Widget> _chamferRows() {
    final app = widget.app;
    final t = L.of(context);
    final s = sess;
    return [
      iosStackedRow(
        label: t.lblMethod,
        child: IosSegmented<int>(
          value: s.mode,
          onChanged: (v) => app.setEdgeFeature(mode: v),
          segments: [
            IosSegment(value: 0, label: t.lblDistance),
            IosSegment(value: 1, label: t.lblTwoDistances),
            IosSegment(value: 2, label: t.lblDistanceAndAngle),
          ],
        ),
      ),
      iosValueRow(
        app: app,
        label: s.mode == 0 ? t.lblDistance : t.lblDistance1,
        controller: _d1,
        unit: 'mm',
        onChanged: (v) => app.setEdgeFeature(exprD1: v),
      ),
      if (s.mode == 1)
        iosValueRow(
          app: app,
          label: t.lblDistance2,
          controller: _d2,
          unit: 'mm',
          onChanged: (v) => app.setEdgeFeature(exprD2: v),
        ),
      if (s.mode == 2)
        iosValueRow(
          app: app,
          label: t.lblAngle,
          controller: _angle,
          unit: 'deg',
          onChanged: (v) => app.setEdgeFeature(exprAngle: v),
        ),
      // Flip only means anything when the two sides differ.
      if (s.mode != 0)
        iosSwitchRow(
          label: t.lblSwapFaces,
          value: s.flip,
          onChanged: (v) => app.setEdgeFeature(flip: v),
        ),
    ];
  }
}
