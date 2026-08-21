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
import '../l10n/fmt.dart';
import '../l10n/l.dart';

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
  bool _extentsOpen = false;

  /// One controller per irregular entry, keyed 'A2', 'B3', 'C4' — direction
  /// and step. Kept for the life of the panel so a field does not lose the
  /// cursor when a sibling is added.
  final Map<String, TextEditingController> _irr = {};

  /// Null until first laid out, then wherever the user dragged it to.
  Offset? _pos;
  String? _syncedFor;

  PartPatternSession get sess => widget.app.patternSession!;

  @override
  void dispose() {
    for (final c in [_countA, _distA, _countB, _distB, _countC, _angleC]) {
      c.dispose();
    }
    for (final c in _irr.values) {
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
    // A different session means different irregular entries; keeping the old
    // controllers would show the previous command's numbers in this one.
    for (final c in _irr.values) {
      c.dispose();
    }
    _irr.clear();
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
            Text(L.of(context).dlgProperties, style: ts(13, Colors.white, w: FontWeight.w600)),
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
    return panelSection(L.of(context).secInputGeometry, _inputOpen,
        () => setState(() => _inputOpen = !_inputOpen), [
      if (s.patternSolid)
        panelRow(
            L.of(context).lblSolid,
            _pickButton(
                label: s.bodyName.isEmpty ? L.of(context).lblSelectSolid : s.bodyName,
                active: s.active == PatternField.solid,
                hint: L.of(context).hintTapBodyIn3d,
                onTap: () => app.patternPick(PatternField.solid)))
      else
        panelRow(
            L.of(context).lblFeature,
            _pickButton(
                label: n == 0
                    ? L.of(context).lblSelectFeatures
                    : '$n Feature${n == 1 ? '' : 's'}',
                active: s.active == PatternField.features,
                // The feature list is fed from the MODEL BROWSER: a feature is
                // a row in the tree, and the graphics window shows a folded
                // body in which one extrusion's faces are no longer its own.
                hint: L.of(context).hintTapFeaturesInBrowser,
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
            _directionSection(L.of(context).lblDirectionA, s, first: true),
            _directionSection(L.of(context).lblDirectionB, s, first: false),
            _extentsSection(s),
          ],
        PatternKind.circular => [_orientationSection(s)],
        PatternKind.sketchDriven => [_placementSection(s)],
        PatternKind.mirror => [_mirrorSection(s)],
      };

  /// Inventor's Extents: WHERE on the path each row starts. Shown only when
  /// a row actually runs along a curve — on a straight direction there is no
  /// path to start anywhere on, and a permanently dead field would be the
  /// ninth of those this ribbon has had.
  Widget _extentsSection(PartPatternSession s) {
    if (s.pathA == null && s.pathB == null) return const SizedBox.shrink();
    final app = widget.app;
    return panelSection(L.of(context).secExtents, _extentsOpen,
        () => setState(() => _extentsOpen = !_extentsOpen), [
      if (s.pathA != null)
        panelRow(
            L.of(context).lblStartA,
            _pickButton(
                label: s.startPickedA
                    ? L.of(context).lblMmAlong(Fmt.fixed(s.startA, 2))
                    : L.of(context).lblCurveStart,
                active: s.active == PatternField.startA,
                hint: L.of(context).hintTapPointOnCurve,
                onTap: () => app.patternPick(PatternField.startA),
                onClear: s.startPickedA
                    ? () => _changed(() {
                          s.startA = 0;
                          s.startPickedA = false;
                        })
                    : null)),
      if (s.pathB != null)
        panelRow(
            L.of(context).lblStartB,
            _pickButton(
                label: s.startPickedB
                    ? L.of(context).lblMmAlong(Fmt.fixed(s.startB, 2))
                    : L.of(context).lblCurveStart,
                active: s.active == PatternField.startB,
                hint: L.of(context).hintTapPointOnCurve,
                onTap: () => app.patternPick(PatternField.startB),
                onClear: s.startPickedB
                    ? () => _changed(() {
                          s.startB = 0;
                          s.startPickedB = false;
                        })
                    : null)),
    ]);
  }

  /// Inventor 2026's Irregular Distance / Irregular Angle: one occurrence
  /// given its own offset instead of the even step. The "+" adds the next
  /// step that has none, which is the order they are normally wanted in.
  List<Widget> _irregularRows(PartPatternSession s, String which, int count,
      String unit) {
    final map = switch (which) {
      'B' => s.irregularB,
      'C' => s.irregularC,
      _ => s.irregularA,
    };
    final steps = map.keys.toList()..sort();
    return [
      for (final k in steps)
        panelRow(
            L.of(context).nodeOccurrence(k + 1),
            Row(children: [
              Expanded(
                child: panelValueField(_irrController('$which$k', map[k]!),
                    unit, (v) {
                  final parsed = parseValueExpr(v);
                  if (parsed != null) {
                    widget.app.patternSetIrregular(which, k, parsed);
                  }
                }, app: widget.app),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => widget.app.patternSetIrregular(which, k, null),
                child: Icon(Icons.cancel_outlined, size: 14, color: T.dim),
              ),
            ])),
      panelRow(
          '',
          _smallButton(
              which == 'C' ? L.of(context).lblAddIrregularAngle : L.of(context).lblAddIrregularDistance,
              false, () {
            for (var k = 1; k < count; k++) {
              if (!map.containsKey(k)) {
                // Seeded with the even offset, so adding one changes nothing
                // until it is edited — an Inventor-shaped "make this one
                // different", not a jump.
                widget.app.patternSetIrregular(which, k, _evenOffset(s, which, k));
                setState(() {});
                return;
              }
            }
          })),
    ];
  }

  /// The offset the even spacing would give step [k] — what a new irregular
  /// entry starts at.
  double _evenOffset(PartPatternSession s, String which, int k) {
    final v = parseValueExpr(switch (which) {
          'B' => s.exprDistanceB,
          'C' => s.exprAngleC,
          _ => s.exprDistanceA,
        }) ??
        0;
    final n = (parseValueExpr(switch (which) {
              'B' => s.exprCountB,
              'C' => s.exprCountC,
              _ => s.exprCountA,
            }) ??
            2)
        .round();
    final d = switch (which) {
      'B' => s.distributionB,
      'C' => s.distributionC,
      _ => s.distributionA,
    };
    final full = which == 'C' && (v.abs() - 360).abs() < 1e-9;
    return patternStep(v, n, d,
            wrapsFullTurn: full && d == PatternDistribution.distance) *
        k;
  }

  TextEditingController _irrController(String key, double value) {
    final c = _irr.putIfAbsent(
        key, () => TextEditingController(text: _fmt(value)));
    return c;
  }

  /// The count a direction currently holds, for bounding the irregular
  /// entries. A field mid-edit can be anything, so an unparsable one means
  /// "no room" rather than an exception.
  static int _countOf(String expr) {
    final v = parseValueExpr(expr);
    if (v == null) return 1;
    final n = v.round();
    return n < 1 ? 1 : n;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? Fmt.fixed(v, 0) : Fmt.fixed(v, 2);

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
    final path = first ? s.pathA : s.pathB;
    return panelSection(
        title,
        open,
        () => setState(() => first ? _aOpen = !_aOpen : _bOpen = !_bOpen),
        [
          panelRow(L.of(context).lblDirection, _axisQuickRow(field)),
          panelRow(
              '',
              Row(children: [
                Expanded(
                  child: _pickButton(
                      label: path != null
                          ? '${path.sketchName} curve'
                          : (ref?.label ?? L.of(context).lblSelectDir),
                      active: s.active == field,
                      hint: L.of(context).hintTapEdgeOrAxis,
                      onTap: () => app.patternPick(field),
                      onClear: (ref == null && path == null)
                          ? null
                          : () => _changed(() {
                                if (first) {
                                  s.dirA = null;
                                  s.pathA = null;
                                  s.startPickedA = false;
                                  s.startA = 0;
                                } else {
                                  s.dirB = null;
                                  s.pathB = null;
                                  s.startPickedB = false;
                                  s.startB = 0;
                                }
                              })),
                ),
                const SizedBox(width: 4),
                _iconToggle(Icons.swap_horiz, L.of(context).lblFlip, flip,
                    () => _changed(() {
                          if (first) {
                            s.flipA = !s.flipA;
                          } else {
                            s.flipB = !s.flipB;
                          }
                        })),
                const SizedBox(width: 3),
                _iconToggle(Icons.align_horizontal_center, L.of(context).lblMidplane, mid,
                    () => _changed(() {
                          if (first) {
                            s.midplaneA = !s.midplaneA;
                          } else {
                            s.midplaneB = !s.midplaneB;
                          }
                        })),
              ])),
          panelRow(
              L.of(context).lblNumber,
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
              L.of(context).lblDistribution,
              _segmented([
                (L.of(context).lblSpacing, distribution == PatternDistribution.spacing,
                    () => _changed(() {
                          if (first) {
                            s.distributionA = PatternDistribution.spacing;
                          } else {
                            s.distributionB = PatternDistribution.spacing;
                          }
                        })),
                (L.of(context).lblDistance, distribution == PatternDistribution.distance,
                    () => _changed(() {
                          if (first) {
                            s.distributionA = PatternDistribution.distance;
                          } else {
                            s.distributionB = PatternDistribution.distance;
                          }
                        })),
                // Inventor's third option exists only for a row that runs
                // along a CURVE — there is nothing to fit to on a straight
                // direction, and an option that cannot act is a lie.
                if (path != null)
                  (L.of(context).lblCurveLength,
                      distribution == PatternDistribution.curveLength,
                      () => _changed(() {
                            if (first) {
                              s.distributionA = PatternDistribution.curveLength;
                            } else {
                              s.distributionB = PatternDistribution.curveLength;
                            }
                          })),
              ])),
          if (distribution != PatternDistribution.curveLength)
            panelRow(
                distribution == PatternDistribution.spacing
                    ? L.of(context).lblSpacing
                    : L.of(context).lblDistance,
                panelValueField(dist, 'mm', (v) {
                  _changed(() {
                    if (first) {
                      s.exprDistanceA = v;
                    } else {
                      s.exprDistanceB = v;
                    }
                  });
                }, app: app)),
          // Inventor's Orientation Method belongs to a row on a PATH: only
          // there can a copy follow the curve instead of keeping its attitude.
          if (path != null && first)
            panelRow(
                L.of(context).lblOrientation,
                _segmented([
                  (L.of(context).lblIdentical, s.orientation == PatternOrient.fixed,
                      () => _changed(
                          () => s.orientation = PatternOrient.fixed)),
                  (L.of(context).lblDirectionA, s.orientation == PatternOrient.rotational,
                      () => _changed(
                          () => s.orientation = PatternOrient.rotational)),
                ])),
          ..._irregularRows(s, first ? 'A' : 'B', _countOf(first ? s.exprCountA : s.exprCountB), 'mm'),
        ]);
  }

  /// Orientation section of a circular pattern.
  Widget _orientationSection(PartPatternSession s) {
    final app = widget.app;
    return panelSection(
        L.of(context).lblOrientation, _aOpen, () => setState(() => _aOpen = !_aOpen), [
      panelRow(L.of(context).lblDirection, _axisQuickRow(PatternField.axis)),
      panelRow(
          '',
          Row(children: [
            Expanded(
              child: _pickButton(
                  label: s.axis?.label ?? L.of(context).lblSelectDir,
                  active: s.active == PatternField.axis,
                  hint: L.of(context).hintTapCircularEdge,
                  onTap: () => app.patternPick(PatternField.axis),
                  onClear:
                      s.axis == null ? null : () => _changed(() => s.axis = null)),
            ),
            const SizedBox(width: 4),
            _iconToggle(Icons.swap_horiz, L.of(context).lblFlip, s.flipC,
                () => _changed(() => s.flipC = !s.flipC)),
          ])),
      panelRow(
          L.of(context).lblCount,
          panelValueField(_countC, 'ul',
              (v) => _changed(() => s.exprCountC = v),
              app: app)),
      panelRow(
          L.of(context).lblDistribution,
          _segmented([
            // Inventor's names for the circular pair. "Incremental" is the
            // angle BETWEEN occurrences, "Fitted" the total they fill.
            (L.of(context).lblIncremental, s.distributionC == PatternDistribution.spacing,
                () => _changed(
                    () => s.distributionC = PatternDistribution.spacing)),
            (L.of(context).btnFitted, s.distributionC == PatternDistribution.distance,
                () => _changed(
                    () => s.distributionC = PatternDistribution.distance)),
          ])),
      panelRow(
          L.of(context).lblAngle,
          panelValueField(_angleC, 'deg',
              (v) => _changed(() => s.exprAngleC = v),
              app: app)),
      panelRow(
          L.of(context).lblOrientation,
          _segmented([
            (L.of(context).lblRotational, s.orientation == PatternOrient.rotational,
                () => _changed(() => s.orientation = PatternOrient.rotational)),
            (L.of(context).lblFixed, s.orientation == PatternOrient.fixed,
                () => _changed(() => s.orientation = PatternOrient.fixed)),
          ])),
      ..._irregularRows(s, 'C', _countOf(s.exprCountC), 'deg'),
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
        L.of(context).secPlacement, _aOpen, () => setState(() => _aOpen = !_aOpen), [
      panelRow(
          L.of(context).lblSketchPoint,
          _pickButton(
              label: s.pointSketch.isEmpty
                  ? L.of(context).lblSelectPoint
                  : L.of(context).lblPointCount(s.pointSketch, n),
              active: s.active == PatternField.pointSketch,
              hint: L.of(context).hintTapSketchPoint,
              onTap: () => app.patternPick(PatternField.pointSketch))),
      panelRow(
          L.of(context).lblBasePoint,
          _pickButton(
              label: s.basePicked
                  ? L.of(context)
                      .lblCoords(Fmt.fixed(s.baseX, 2), Fmt.fixed(s.baseY, 2))
                  : L.of(context).lblSelectPoint,
              active: s.active == PatternField.basePoint,
              hint: L.of(context).hintTapOriginalPoint,
              onTap: () => app.patternPick(PatternField.basePoint),
              onClear: s.basePicked
                  ? () => _changed(() => s.basePicked = false)
                  : null)),
      // Inventor's Variable Orientation: Identical keeps every copy parallel
      // to the parent, Follow Face turns it to the surface it lands on.
      panelRow(
          L.of(context).lblOrientation,
          _segmented([
            (L.of(context).lblIdentical, s.orientFace == null,
                () => _changed(() => s.orientFace = null)),
            (L.of(context).lblFollowFace, s.orientFace != null,
                () => app.patternPick(PatternField.orientFace)),
          ])),
      if (s.orientFace != null || s.active == PatternField.orientFace)
        panelRow(
            L.of(context).lblFaceField,
            _pickButton(
                label: s.orientFace == null
                    ? L.of(context).lblSelectFaceBtn
                    : L.of(context).lblFaceField,
                active: s.active == PatternField.orientFace,
                hint: L.of(context).hintTapFaceToFollow,
                onTap: () => app.patternPick(PatternField.orientFace),
                onClear: s.orientFace == null
                    ? null
                    : () => _changed(() => s.orientFace = null))),
    ]);
  }

  /// Mirror plane section.
  Widget _mirrorSection(PartPatternSession s) {
    final app = widget.app;
    return panelSection(
        L.of(context).lblMirrorPlane, _aOpen, () => setState(() => _aOpen = !_aOpen), [
      panelRow(
          L.of(context).lblPlaneField,
          _pickButton(
              label: s.plane?.label ?? L.of(context).lblMirrorPlane,
              active: s.active == PatternField.plane,
              hint: L.of(context).hintTapFaceOrPlane,
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
          L.of(context).secOutputGeometry, _outOpen, () => setState(() => _outOpen = !_outOpen), [
        panelRow(
            L.of(context).lblCreationMethod,
            _segmented([
              (L.of(context).lblIdentical, s.compute == PatternCompute.identical,
                  () => _changed(() => s.compute = PatternCompute.identical)),
              (L.of(context).lblAdjust, s.compute == PatternCompute.adjust,
                  () => _changed(() => s.compute = PatternCompute.adjust)),
            ])),
        // Inventor offers Remove Original only when a SOLID is being
        // mirrored; removing the original of a feature mirror would mean
        // deleting a feature that this one is built on.
        if (s.mode == PatternKind.mirror && s.patternSolid)
          panelRow(
              L.of(context).lblRemoveOriginal,
              _smallButton(L.of(context).lblKeepMirroredHalf, s.removeOriginal,
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
          _railButton(Icons.grid_on, L.of(context).patRectangular,
              s.mode == PatternKind.rectangular,
              () => widget.app.switchPattern(PatternKind.rectangular)),
          _railButton(Icons.blur_circular, L.of(context).patCircular,
              s.mode == PatternKind.circular,
              () => widget.app.switchPattern(PatternKind.circular)),
          _railButton(Icons.scatter_plot, L.of(context).patSketchDriven,
              s.mode == PatternKind.sketchDriven,
              () => widget.app.switchPattern(PatternKind.sketchDriven)),
          _railButton(Icons.flip, L.of(context).patMirror, s.mode == PatternKind.mirror,
              () => widget.app.switchPattern(PatternKind.mirror)),
          Container(
              height: 1,
              width: 22,
              margin: const EdgeInsets.symmetric(vertical: 5),
              color: T.panelSep),
          // Inventor's two Input Geometry modes.
          _railButton(Icons.category_outlined, L.of(context).lblPatternFeatures,
              !s.patternSolid, () => widget.app.patternSetSolidMode(false)),
          _railButton(Icons.view_in_ar, L.of(context).lblPatternSolid, s.patternSolid,
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
            L.of(context).lblPick, s.active == field, () => widget.app.patternPick(field)),
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
                child: Text(L.of(context).ok,
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
              child: Text(L.of(context).cancel, style: ts(12.5, T.text)),
            ),
          ),
        ),
      ]),
    );
  }
}
