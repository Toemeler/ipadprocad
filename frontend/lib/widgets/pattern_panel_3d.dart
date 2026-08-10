// M212 — the PART pattern panel: Rectangular, Circular, Sketch Driven and
// Mirror, 1:1 with Inventor's property panel (see the mock screenshots).
//
//   Rectangular:   Input Geometry (Feature) | Direction A (direction, number,
//                  distribution, distance) | Direction B | Output Geometry
//                  (Creation Method) | OK Cancel
//   Circular:      Input Geometry | Orientation (direction, count,
//                  distribution, angle, orientation) | Output Geometry
//   Sketch Driven: Input Geometry | Placement (sketch of points, base point)
//                  | Output Geometry
//   Mirror:        Input Geometry | Mirror Plane (+ the three origin planes)
//                  | Output Geometry (Creation Method, Remove Original)
//
// ONE widget for all four, like [EdgeFeatureDialog] serves fillet and chamfer:
// the chrome, the feature picker, the preview, the creation method and the
// OK/Cancel behaviour are identical, and four copies would be four places to
// keep the selection handling in step.
//
// The panel is MODELESS — it floats over the viewport while the user keeps
// picking geometry. Which input a pick feeds is the ACTIVE selector (blue
// outline), exactly as in Inventor and exactly as the 2D pattern dialog
// already works; AppState routes the taps.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../part_model.dart';
import '../theme.dart';
import 'dialog_dock.dart';
import 'properties_panel.dart';

class PatternPanel3D extends StatefulWidget {
  final AppState app;
  const PatternPanel3D({super.key, required this.app});

  @override
  State<PatternPanel3D> createState() => _PatternPanel3DState();
}

class _PatternPanel3DState extends State<PatternPanel3D> {
  final _countA = TextEditingController();
  final _distA = TextEditingController();
  final _countB = TextEditingController();
  final _distB = TextEditingController();
  final _countC = TextEditingController();
  final _angleC = TextEditingController();

  bool _inputOpen = true, _aOpen = true, _bOpen = true, _outOpen = true;

  /// Null until first laid out, then wherever the user dragged it to.
  Offset? _pos;
  String? _syncedFor;

  PartPatternSession get sess => widget.app.patternSession!;

  @override
  void dispose() {
    for (final c in [_countA, _distA, _countB, _distB, _countC, _angleC]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Load the session's expressions into the controllers ONCE per session.
  /// Doing it on every build would fight the cursor while typing — the same
  /// reason the extrude and fillet panels seed their fields on open only.
  void _syncOnce() {
    final s = widget.app.patternSession;
    if (s == null) return;
    final id = '${s.mode}/${identityHashCode(s)}';
    if (_syncedFor == id) return;
    _syncedFor = id;
    _countA.text = s.exprCountA;
    _distA.text = s.exprDistanceA;
    _countB.text = s.exprCountB;
    _distB.text = s.exprDistanceB;
    _countC.text = s.exprCountC;
    _angleC.text = s.exprAngleC;
  }

  void _changed(VoidCallback edit) {
    edit();
    widget.app.patternChanged();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.patternSession;
    if (s == null) return const SizedBox.shrink();
    _syncOnce();

    const w = 320.0, h = 560.0;
    final vp = MediaQuery.sizeOf(context);
    // M206 — beside the quick-tool bar, not under it. See DialogDock.
    final pos = _pos ?? DialogDock.spot(vp, const Size(w, h));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
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
              _titleBar(pos),
              _commandName(s),
              _inputGeometry(s),
              ..._middleSections(s),
              _outputGeometry(s),
              if (s.previewError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                  child: Text(s.previewError!,
                      style: ts(11.5, const Color(0xFFE0A030))),
                ),
              _footer(s),
            ]),
          ),
          const SizedBox(width: 6),
          // Inventor's vertical rail beside the panel: the pattern commands,
          // then the two Input Geometry modes.
          _rail(s),
        ]),
      ),
    );
  }

  // ---- chrome ------------------------------------------------------------

  Widget _titleBar(Offset pos) => GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: const BoxDecoration(
            color: T.fly,
            border: Border(bottom: BorderSide(color: T.panelSep)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(children: [
            Text('Properties', style: ts(13, Colors.white, w: FontWeight.w600)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: widget.app.cancelPattern,
              child: Text('✕', style: ts(11.5, T.dim)),
            ),
            const Spacer(),
            Icon(Icons.menu, size: 14, color: T.dim),
          ]),
        ),
      );

  Widget _commandName(PartPatternSession s) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Text(s.editing?.name ?? patternKindLabel(s.mode),
              style: TextStyle(
                  fontSize: 12.5,
                  color: T.blue,
                  decoration: TextDecoration.underline,
                  decorationColor: T.blue)),
          const Spacer(),
          Icon(Icons.visibility_outlined, size: 14, color: T.dim),
        ]),
      );

  // ---- sections ----------------------------------------------------------

  Widget _inputGeometry(PartPatternSession s) {
    final app = widget.app;
    final n = s.features.length;
    return panelSection('Input Geometry', _inputOpen,
        () => setState(() => _inputOpen = !_inputOpen), [
      if (s.patternSolid)
        panelRow(
            'Solid',
            _pickButton(
                label: s.bodyName.isEmpty ? 'Select Solid' : s.bodyName,
                active: s.active == PatternField.solid,
                hint: 'Tap the body in 3D…',
                onTap: () => app.patternPick(PatternField.solid)))
      else
        panelRow(
            'Feature',
            _pickButton(
                label: n == 0
                    ? 'Select Features'
                    : '$n Feature${n == 1 ? '' : 's'}',
                active: s.active == PatternField.features,
                // The feature list is fed from the MODEL BROWSER: a feature is
                // a row in the tree, and the graphics window shows a folded
                // body in which one extrusion's faces are no longer its own.
                hint: 'Tap features in the browser…',
                onTap: () => app.patternPick(PatternField.features))),
      if (!s.patternSolid && s.features.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const SizedBox(width: 82),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final f in s.features)
                    _chip(f, () => _changed(() {
                          s.features.remove(f);
                        })),
                ],
              ),
            ),
          ]),
        ),
    ]);
  }

  List<Widget> _middleSections(PartPatternSession s) => switch (s.mode) {
        PatternKind.rectangular => [
            _directionSection('Direction A', s, first: true),
            _directionSection('Direction B', s, first: false),
          ],
        PatternKind.circular => [_orientationSection(s)],
        PatternKind.sketchDriven => [_placementSection(s)],
        PatternKind.mirror => [_mirrorSection(s)],
      };

  /// Direction A / B of a rectangular pattern.
  Widget _directionSection(String title, PartPatternSession s,
      {required bool first}) {
    final app = widget.app;
    final field = first ? PatternField.dirA : PatternField.dirB;
    final ref = first ? s.dirA : s.dirB;
    final open = first ? _aOpen : _bOpen;
    final count = first ? _countA : _countB;
    final dist = first ? _distA : _distB;
    final flip = first ? s.flipA : s.flipB;
    final mid = first ? s.midplaneA : s.midplaneB;
    final distribution = first ? s.distributionA : s.distributionB;
    return panelSection(
        title,
        open,
        () => setState(() => first ? _aOpen = !_aOpen : _bOpen = !_bOpen),
        [
          panelRow('Direction', _axisQuickRow(field)),
          panelRow(
              '',
              Row(children: [
                Expanded(
                  child: _pickButton(
                      label: ref?.label ?? 'Select Dir...',
                      active: s.active == field,
                      hint: 'Tap an edge or axis…',
                      onTap: () => app.patternPick(field),
                      onClear: ref == null
                          ? null
                          : () => _changed(() {
                                if (first) {
                                  s.dirA = null;
                                } else {
                                  s.dirB = null;
                                }
                              })),
                ),
                const SizedBox(width: 4),
                _iconToggle(Icons.swap_horiz, 'Flip', flip,
                    () => _changed(() {
                          if (first) {
                            s.flipA = !s.flipA;
                          } else {
                            s.flipB = !s.flipB;
                          }
                        })),
                const SizedBox(width: 3),
                _iconToggle(Icons.align_horizontal_center, 'Midplane', mid,
                    () => _changed(() {
                          if (first) {
                            s.midplaneA = !s.midplaneA;
                          } else {
                            s.midplaneB = !s.midplaneB;
                          }
                        })),
              ])),
          panelRow(
              'Number',
              panelValueField(count, 'ul', (v) {
                _changed(() {
                  if (first) {
                    s.exprCountA = v;
                  } else {
                    s.exprCountB = v;
                  }
                });
              }, app: app)),
          panelRow(
              'Distribution',
              _segmented([
                ('Spacing', distribution == PatternDistribution.spacing,
                    () => _changed(() {
                          if (first) {
                            s.distributionA = PatternDistribution.spacing;
                          } else {
                            s.distributionB = PatternDistribution.spacing;
                          }
                        })),
                ('Distance', distribution == PatternDistribution.distance,
                    () => _changed(() {
                          if (first) {
                            s.distributionA = PatternDistribution.distance;
                          } else {
                            s.distributionB = PatternDistribution.distance;
                          }
                        })),
              ])),
          panelRow(
              distribution == PatternDistribution.spacing
                  ? 'Spacing'
                  : 'Distance',
              panelValueField(dist, 'mm', (v) {
                _changed(() {
                  if (first) {
                    s.exprDistanceA = v;
                  } else {
                    s.exprDistanceB = v;
                  }
                });
              }, app: app)),
        ]);
  }

  /// Orientation section of a circular pattern.
  Widget _orientationSection(PartPatternSession s) {
    final app = widget.app;
    return panelSection(
        'Orientation', _aOpen, () => setState(() => _aOpen = !_aOpen), [
      panelRow('Direction', _axisQuickRow(PatternField.axis)),
      panelRow(
          '',
          Row(children: [
            Expanded(
              child: _pickButton(
                  label: s.axis?.label ?? 'Select Dir...',
                  active: s.active == PatternField.axis,
                  hint: 'Tap a circular edge or axis…',
                  onTap: () => app.patternPick(PatternField.axis),
                  onClear:
                      s.axis == null ? null : () => _changed(() => s.axis = null)),
            ),
            const SizedBox(width: 4),
            _iconToggle(Icons.swap_horiz, 'Flip', s.flipC,
                () => _changed(() => s.flipC = !s.flipC)),
          ])),
      panelRow(
          'Count',
          panelValueField(_countC, 'ul',
              (v) => _changed(() => s.exprCountC = v),
              app: app)),
      panelRow(
          'Distribution',
          _segmented([
            // Inventor's names for the circular pair. "Incremental" is the
            // angle BETWEEN occurrences, "Fitted" the total they fill.
            ('Incremental', s.distributionC == PatternDistribution.spacing,
                () => _changed(
                    () => s.distributionC = PatternDistribution.spacing)),
            ('Fitted', s.distributionC == PatternDistribution.distance,
                () => _changed(
                    () => s.distributionC = PatternDistribution.distance)),
          ])),
      panelRow(
          'Angle',
          panelValueField(_angleC, 'deg',
              (v) => _changed(() => s.exprAngleC = v),
              app: app)),
      panelRow(
          'Orientation',
          _segmented([
            ('Rotational', s.orientation == PatternOrient.rotational,
                () => _changed(() => s.orientation = PatternOrient.rotational)),
            ('Fixed', s.orientation == PatternOrient.fixed,
                () => _changed(() => s.orientation = PatternOrient.fixed)),
          ])),
    ]);
  }

  /// Placement section of a sketch-driven pattern.
  Widget _placementSection(PartPatternSession s) {
    final app = widget.app;
    final p = app.currentPart;
    final cs = p == null || s.pointSketch.isEmpty
        ? null
        : p.sketchByName(s.pointSketch);
    final n = cs == null ? 0 : sketchPatternPoints(cs.model).length;
    return panelSection(
        'Placement', _aOpen, () => setState(() => _aOpen = !_aOpen), [
      panelRow(
          'Sketch Point',
          _pickButton(
              label: s.pointSketch.isEmpty
                  ? 'Select Point'
                  : '${s.pointSketch} ($n point${n == 1 ? '' : 's'})',
              active: s.active == PatternField.pointSketch,
              hint: 'Tap a sketch point…',
              onTap: () => app.patternPick(PatternField.pointSketch))),
      panelRow(
          'Base Point',
          _pickButton(
              label: s.basePicked
                  ? '(${s.baseX.toStringAsFixed(2)}, '
                      '${s.baseY.toStringAsFixed(2)})'
                  : 'Select Point',
              active: s.active == PatternField.basePoint,
              hint: 'Tap the point the original sits on…',
              onTap: () => app.patternPick(PatternField.basePoint),
              onClear: s.basePicked
                  ? () => _changed(() => s.basePicked = false)
                  : null)),
    ]);
  }

  /// Mirror plane section.
  Widget _mirrorSection(PartPatternSession s) {
    final app = widget.app;
    return panelSection(
        'Mirror Plane', _aOpen, () => setState(() => _aOpen = !_aOpen), [
      panelRow(
          'Plane',
          _pickButton(
              label: s.plane?.label ?? 'Mirror Plane',
              active: s.active == PatternField.plane,
              hint: 'Tap a face or plane…',
              onTap: () => app.patternPick(PatternField.plane),
              onClear:
                  s.plane == null ? null : () => _changed(() => s.plane = null))),
      // Inventor's three origin-plane shortcuts, right in the dialog.
      panelRow(
          '',
          Row(children: [
            for (final key in const ['yz', 'xz', 'xy']) ...[
              Expanded(
                child: _smallButton(
                    '${key.toUpperCase()} Plane',
                    s.plane?.label == '${key.toUpperCase()} Plane',
                    () => _pickOriginPlane(key)),
              ),
              if (key != 'xy') const SizedBox(width: 3),
            ],
          ])),
    ]);
  }

  Widget _outputGeometry(PartPatternSession s) => panelSection(
          'Output Geometry', _outOpen, () => setState(() => _outOpen = !_outOpen), [
        panelRow(
            'Creation Method',
            _segmented([
              ('Identical', s.compute == PatternCompute.identical,
                  () => _changed(() => s.compute = PatternCompute.identical)),
              ('Adjust', s.compute == PatternCompute.adjust,
                  () => _changed(() => s.compute = PatternCompute.adjust)),
            ])),
        // Inventor offers Remove Original only when a SOLID is being
        // mirrored; removing the original of a feature mirror would mean
        // deleting a feature that this one is built on.
        if (s.mode == PatternKind.mirror && s.patternSolid)
          panelRow(
              'Remove Original',
              _smallButton('Keep only the mirrored half', s.removeOriginal,
                  () => _changed(() => s.removeOriginal = !s.removeOriginal))),
      ]);

  // ---- the rail ----------------------------------------------------------

  Widget _rail(PartPatternSession s) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: T.panel,
          border: Border.all(color: T.sep),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _railButton(Icons.grid_on, 'Rectangular Pattern',
              s.mode == PatternKind.rectangular,
              () => widget.app.switchPattern(PatternKind.rectangular)),
          _railButton(Icons.blur_circular, 'Circular Pattern',
              s.mode == PatternKind.circular,
              () => widget.app.switchPattern(PatternKind.circular)),
          _railButton(Icons.scatter_plot, 'Sketch Driven Pattern',
              s.mode == PatternKind.sketchDriven,
              () => widget.app.switchPattern(PatternKind.sketchDriven)),
          _railButton(Icons.flip, 'Mirror', s.mode == PatternKind.mirror,
              () => widget.app.switchPattern(PatternKind.mirror)),
          Container(
              height: 1,
              width: 22,
              margin: const EdgeInsets.symmetric(vertical: 5),
              color: T.panelSep),
          // Inventor's two Input Geometry modes.
          _railButton(Icons.category_outlined, 'Pattern individual features',
              !s.patternSolid, () => widget.app.patternSetSolidMode(false)),
          _railButton(Icons.view_in_ar, 'Pattern a solid', s.patternSolid,
              () => widget.app.patternSetSolidMode(true)),
        ]),
      );

  Widget _railButton(
          IconData icon, String tip, bool active, VoidCallback onTap) =>
      Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2E4A6B) : const Color(0xFF2A2E33),
              border: Border.all(
                  color: active ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 16, color: active ? T.blue : T.text),
          ),
        ),
      );

  // ---- small pieces ------------------------------------------------------

  /// The direction row's quick picks: the three origin axes, which Inventor
  /// puts next to the selector precisely because they are what most patterns
  /// run along.
  Widget _axisQuickRow(PatternField field) {
    final s = sess;
    final current = switch (field) {
      PatternField.dirA => s.dirA,
      PatternField.dirB => s.dirB,
      _ => s.axis,
    };
    return Row(children: [
      Expanded(
        child: _smallButton(
            'Pick', s.active == field, () => widget.app.patternPick(field)),
      ),
      for (final k in const ['x', 'y', 'z']) ...[
        const SizedBox(width: 3),
        SizedBox(
          width: 30,
          child: _smallButton(k.toUpperCase(),
              current?.label == '${k.toUpperCase()} Axis',
              () => _pickOriginAxis(field, k)),
        ),
      ],
    ]);
  }

  void _pickOriginAxis(PatternField field, String key) {
    final app = widget.app;
    final s = app.patternSession;
    if (s == null) return;
    s.active = field;
    app.patternAxisPicked(
        Vec3.zero,
        switch (key) {
          'x' => const Vec3(1, 0, 0),
          'y' => const Vec3(0, 1, 0),
          _ => const Vec3(0, 0, 1),
        },
        '${key.toUpperCase()} Axis');
  }

  void _pickOriginPlane(String key) {
    final app = widget.app;
    final s = app.patternSession;
    if (s == null) return;
    final fr = planeFrame(key);
    s.active = PatternField.plane;
    app.patternPlanePicked(fr.origin, fr.n, '${key.toUpperCase()} Plane');
  }

  Widget _pickButton(
      {required String label,
      required bool active,
      required String hint,
      required VoidCallback onTap,
      VoidCallback? onClear}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF212429),
          border: Border.all(
              color: active ? T.blue : const Color(0xFF3A3F45),
              width: active ? 1.4 : 1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          Icon(Icons.north_west, size: 12, color: active ? T.blue : T.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(active ? hint : label,
                overflow: TextOverflow.ellipsis,
                style: ts(12, active ? T.blue : T.text)),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.cancel_outlined,
                  size: 13, color: Color(0xFF9EA4AA)),
            ),
        ]),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onRemove) => Container(
        padding: const EdgeInsets.fromLTRB(6, 2, 3, 2),
        decoration: BoxDecoration(
          color: const Color(0xFF2E4A6B),
          border: Border.all(color: T.blue),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: ts(11, T.text)),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 11, color: T.dim),
          ),
        ]),
      );

  Widget _segmented(List<(String, bool, VoidCallback)> items) =>
      Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
              child: _smallButton(items[i].$1, items[i].$2, items[i].$3)),
        ]
      ]);

  Widget _smallButton(String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2E4A6B) : const Color(0xFF2A2E33),
            border:
                Border.all(color: active ? T.blue : const Color(0xFF3A3F45)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label,
              overflow: TextOverflow.ellipsis, style: ts(11.5, T.text)),
        ),
      );

  Widget _iconToggle(
          IconData icon, String tip, bool active, VoidCallback onTap) =>
      Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2E4A6B) : const Color(0xFF2A2E33),
              border: Border.all(
                  color: active ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(icon, size: 14, color: active ? T.blue : T.text),
          ),
        ),
      );

  Widget _footer(PartPatternSession s) {
    final app = widget.app;
    final ready = s.previewError == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(children: [
        Expanded(
          child: Opacity(
            opacity: ready ? 1 : 0.45,
            child: GestureDetector(
              onTap: ready ? () => app.applyPattern() : null,
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
            onTap: app.cancelPattern,
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
