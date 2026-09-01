// M212 — the PART pattern panel: Rectangular, Circular, Sketch Driven and
// Mirror, 1:1 with Inventor's property panel.
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
// picking geometry. Which input a pick feeds is the ACTIVE selector (the
// tinted row), exactly as in Inventor; AppState routes the taps.
//
// M248 — and it serves the ASSEMBLY's Pattern Component and Mirror Component
// as well, on an [AsmPatternSession]. Almost nothing here knows: the counts,
// the distributions, the irregular rows, the flips, the midplanes, the origin
// quick-picks and the OK/Cancel behaviour are the same objects and the same
// AppState methods, which route on the session's type. What DOES differ is
// named in one place each and is exactly three things —
//
//   * INPUT GEOMETRY is components, not features or a solid.
//   * THE PICKED INPUTS ARE REFERENCES that move with their component (see
//     asm_pattern.dart), so the label and the clear button read and write the
//     AsmRef rather than the resolved AxisRef beside it.
//   * A WARNING LINE, because the preview is the real pattern: shrinking a
//     count destroys elements and the relationships on them, and the panel
//     says how many while Cancel can still put them back.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). Two of its controls
// changed shape rather than only style:
//
//   * FLIP AND MIDPLANE ARE SWITCHES. They were two 26 pt icon buttons beside
//     the direction picker whose meaning lived in a tooltip, which on a touch
//     device is nowhere. They are named switch rows now.
//   * THE MODE RAIL IS A CONTROL CLUSTER, not a strip of bordered squares. It
//     keeps its own card beside the panel — Inventor puts it there and it is
//     genuinely a different axis of choice from everything in the panel — but
//     it is drawn as iOS draws a group of toggles.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import '../part_model.dart';
import '../svg_icons.dart' show PT;
import 'dialog_dock.dart';
import 'ios_kit.dart';
import '../l10n/cad_terms.dart';
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

  static const _size = Size(IosMetrics.panelWidth, 620);

  PartPatternSession get sess => widget.app.patternSession!;

  /// The open session when it belongs to an ASSEMBLY, else null. Every
  /// difference in this file is behind one of these.
  AsmPatternSession? get asm => widget.app.asmPatternSession;

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
    final t = L.of(context);
    final ready = s.previewError == null;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IosPanel(
          width: _size.width,
          nav: IosNavBar(
            title: s.editing?.name ?? patternKindDisplay(t, s.mode),
            onDrag: (d) => setState(() => _pos = pos + d),
            leading: IosBarButton(label: t.cancel, onTap: app.cancelPattern),
            trailing: IosBarButton(
                label: t.ok,
                prominent: true,
                onTap: ready ? app.applyPattern : null),
          ),
          children: [
            _inputGeometry(s, t),
            ..._middleSections(s, t),
            _outputGeometry(s, t),
            if (s.previewError != null) iosStatusLine(s.previewError!),
          ],
        ),
        const SizedBox(width: 8),
        // Inventor's vertical rail beside the panel: the pattern commands,
        // then the two Input Geometry modes.
        _rail(s, t),
      ]),
    );
  }

  // ---- sections ----------------------------------------------------------

  Widget _inputGeometry(PartPatternSession s, AppL10n t) {
    final app = widget.app;
    final n = s.features.length;
    final a = asm;
    return iosSection(
      header: t.secInputGeometry,
      open: _inputOpen,
      onToggle: () => setState(() => _inputOpen = !_inputOpen),
      children: [
        // M248 — an assembly patterns COMPONENTS. The same list and the same
        // chips; what changes is the noun, where the taps come from (the
        // graphics window, never a feature browser) and that there is no
        // solid mode to switch to.
        if (a != null)
          iosPickRow(
            label: t.lblComponent,
            value: n == 0 ? null : t.lblNComponents(n),
            hint: s.active == PatternField.features
                ? t.hintTapComponentIn3d
                : t.lblSelectComponents,
            armed: s.active == PatternField.features,
            filled: n > 0,
            onTap: () => app.patternPick(PatternField.features),
          )
        else if (s.patternSolid)
          iosPickRow(
            label: t.lblSolid,
            value: s.bodyName.isEmpty ? null : s.bodyName,
            hint: s.active == PatternField.solid
                ? t.hintTapBodyIn3d
                : t.lblSelectSolid,
            armed: s.active == PatternField.solid,
            filled: s.bodyName.isNotEmpty,
            onTap: () => app.patternPick(PatternField.solid),
          )
        else
          iosPickRow(
            label: t.lblFeature,
            // The feature list is fed from the MODEL BROWSER: a feature is a
            // row in the tree, and the graphics window shows a folded body in
            // which one extrusion's faces are no longer its own.
            value: n == 0 ? null : t.lblFeatureCount(n),
            hint: s.active == PatternField.features
                ? t.hintTapFeaturesInBrowser
                : t.lblSelectFeatures,
            armed: s.active == PatternField.features,
            filled: n > 0,
            onTap: () => app.patternPick(PatternField.features),
          ),
        if (a != null) ..._associativeRows(a, t),
        if ((a != null || !s.patternSolid) && s.features.isNotEmpty)
          iosStackedRow(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in s.features)
                  iosChip(f, () => _changed(() => s.features.remove(f))),
              ],
            ),
          ),
      ],
    );
  }

  /// Inventor's Associative tab, as a row rather than a tab: the pattern
  /// follows a FEATURE pattern inside a component.
  ///
  /// Listed off the LIVE models, so a hole pattern added in the part's own tab
  /// appears here the moment you look — which is the same liveness that makes
  /// the bolts follow it afterwards (M245).
  List<Widget> _associativeRows(AsmPatternSession s, AppL10n t) {
    if (s.mode == PatternKind.mirror) return const [];
    final drivers = widget.app.asmPatternDrivers();
    if (drivers.isEmpty && s.driver == null) return const [];
    final cur = s.driver;
    return [
      // M338 — a real pop-up, where it used to be one button cycling the list.
      // A cycling button is only bearable while the list is short and gives no
      // way back; a menu names every choice and marks the one in force.
      IosMenuRow<int>(
        label: t.lblFeaturePattern,
        value: cur == null
            ? -1
            : drivers.indexWhere((d) => d.$1 == cur.$1 && d.$2 == cur.$2),
        cancelLabel: t.cancel,
        choices: [
          IosMenuChoice(-1, t.lblOwnSpacing),
          for (var i = 0; i < drivers.length; i++)
            IosMenuChoice(i, '${drivers[i].$1} · ${drivers[i].$2}'),
        ],
        onChanged: (i) => widget.app
            .asmPatternSetDriver(i < 0 ? null : drivers[i]),
      ),
    ];
  }

  List<Widget> _middleSections(PartPatternSession s, AppL10n t) =>
      switch (s.mode) {
        PatternKind.rectangular => [
            _directionSection(t.lblDirectionA, s, t, first: true),
            _directionSection(t.lblDirectionB, s, t, first: false),
            _extentsSection(s, t),
          ],
        PatternKind.circular => [_orientationSection(s, t)],
        PatternKind.sketchDriven => [_placementSection(s, t)],
        PatternKind.mirror => [_mirrorSection(s, t)],
      };

  /// Inventor's Extents: WHERE on the path each row starts. Shown only when
  /// a row actually runs along a curve — on a straight direction there is no
  /// path to start anywhere on, and a permanently dead field would be the
  /// ninth of those this ribbon has had.
  Widget _extentsSection(PartPatternSession s, AppL10n t) {
    if (s.pathA == null && s.pathB == null) return const SizedBox.shrink();
    final app = widget.app;
    return iosSection(
      header: t.secExtents,
      open: _extentsOpen,
      onToggle: () => setState(() => _extentsOpen = !_extentsOpen),
      children: [
        if (s.pathA != null)
          iosPickRow(
            label: t.lblStartA,
            value: s.startPickedA ? t.lblMmAlong(Fmt.fixed(s.startA, 2)) : null,
            hint: s.active == PatternField.startA
                ? t.hintTapPointOnCurve
                : t.lblCurveStart,
            armed: s.active == PatternField.startA,
            filled: s.startPickedA,
            onTap: () => app.patternPick(PatternField.startA),
            onClear: s.startPickedA
                ? () => _changed(() {
                      s.startA = 0;
                      s.startPickedA = false;
                    })
                : null,
          ),
        if (s.pathB != null)
          iosPickRow(
            label: t.lblStartB,
            value: s.startPickedB ? t.lblMmAlong(Fmt.fixed(s.startB, 2)) : null,
            hint: s.active == PatternField.startB
                ? t.hintTapPointOnCurve
                : t.lblCurveStart,
            armed: s.active == PatternField.startB,
            filled: s.startPickedB,
            onTap: () => app.patternPick(PatternField.startB),
            onClear: s.startPickedB
                ? () => _changed(() {
                      s.startB = 0;
                      s.startPickedB = false;
                    })
                : null,
          ),
      ],
    );
  }

  /// Inventor 2026's Irregular Distance / Irregular Angle: one occurrence
  /// given its own offset instead of the even step. The "+" adds the next
  /// step that has none, which is the order they are normally wanted in.
  List<Widget> _irregularRows(
      PartPatternSession s, AppL10n t, String which, int count, String unit) {
    final map = switch (which) {
      'B' => s.irregularB,
      'C' => s.irregularC,
      _ => s.irregularA,
    };
    final steps = map.keys.toList()..sort();
    return [
      for (final k in steps)
        iosValueRow(
          app: widget.app,
          label: t.nodeOccurrence(k + 1),
          controller: _irrController('$which$k', map[k]!),
          unit: unit,
          onChanged: (v) {
            final parsed = parseValueExpr(v);
            if (parsed != null) {
              widget.app.patternSetIrregular(which, k, parsed);
            }
          },
          leading: IosPressable(
            onTap: () => widget.app.patternSetIrregular(which, k, null),
            child: iosGlyph(IosGlyph.xmarkCircleFill,
                size: 17, color: IosColors.tertiaryLabel),
          ),
        ),
      iosStackedRow(
        child: IosButton(
          label: which == 'C'
              ? t.lblAddIrregularAngle
              : t.lblAddIrregularDistance,
          glyph: IosGlyph.plus,
          style: IosButtonStyle.tinted,
          height: 34,
          expand: true,
          onTap: () {
            for (var k = 1; k < count; k++) {
              if (!map.containsKey(k)) {
                // Seeded with the even offset, so adding one changes nothing
                // until it is edited — an Inventor-shaped "make this one
                // different", not a jump.
                widget.app
                    .patternSetIrregular(which, k, _evenOffset(s, which, k));
                setState(() {});
                return;
              }
            }
          },
        ),
      ),
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

  TextEditingController _irrController(String key, double value) =>
      _irr.putIfAbsent(key, () => TextEditingController(text: _fmt(value)));

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
  Widget _directionSection(String title, PartPatternSession s, AppL10n t,
      {required bool first}) {
    final app = widget.app;
    final field = first ? PatternField.dirA : PatternField.dirB;
    final a = asm;
    // M248 — for an assembly the picked input is the REFERENCE; dirA/dirB
    // beside it are the resolved cache the arithmetic reads (asm_pattern.dart,
    // section B), and clearing one of those would leave the reference behind
    // to fill it in again on the next regeneration.
    final asmRef = a == null ? null : (first ? a.refDirA : a.refDirB);
    final ref = a != null
        ? (asmRef == null
            ? null
            : AxisRef(0, 0, 0, 1, 0, 0, asmRef.label))
        : (first ? s.dirA : s.dirB);
    final open = first ? _aOpen : _bOpen;
    final count = first ? _countA : _countB;
    final dist = first ? _distA : _distB;
    final flip = first ? s.flipA : s.flipB;
    final mid = first ? s.midplaneA : s.midplaneB;
    final distribution = first ? s.distributionA : s.distributionB;
    final path = first ? s.pathA : s.pathB;
    final label = ref?.label;

    return iosSection(
      header: title,
      open: open,
      onToggle: () => setState(() => first ? _aOpen = !_aOpen : _bOpen = !_bOpen),
      children: [
        iosPickRow(
          label: t.lblDirection,
          value: path != null ? '${path.sketchName} curve' : label,
          hint: t.hintTapEdgeOrAxis,
          armed: s.active == field,
          filled: ref != null || path != null,
          onTap: () => app.patternPick(field),
          onClear: (ref == null && path == null)
              ? null
              : () => _changed(() {
                    if (a != null) {
                      if (first) {
                        a.refDirA = null;
                        s.dirA = null;
                      } else {
                        a.refDirB = null;
                        s.dirB = null;
                      }
                    } else if (first) {
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
                  }),
        ),
        // The three origin axes, which Inventor puts next to the selector
        // precisely because they are what most patterns run along.
        _axisQuickRow(field, label, t),
        iosSwitchRow(
          label: t.lblFlip,
          value: flip,
          onChanged: (v) => _changed(() {
            if (first) {
              s.flipA = v;
            } else {
              s.flipB = v;
            }
          }),
        ),
        iosSwitchRow(
          label: t.lblMidplane,
          value: mid,
          onChanged: (v) => _changed(() {
            if (first) {
              s.midplaneA = v;
            } else {
              s.midplaneB = v;
            }
          }),
        ),
        iosValueRow(
          app: app,
          label: t.lblNumber,
          controller: count,
          unit: 'ul',
          onChanged: (v) => _changed(() {
            if (first) {
              s.exprCountA = v;
            } else {
              s.exprCountB = v;
            }
          }),
        ),
        iosStackedRow(
          label: t.lblDistribution,
          child: IosSegmented<PatternDistribution>(
            value: distribution,
            onChanged: (d) => _changed(() {
              if (first) {
                s.distributionA = d;
              } else {
                s.distributionB = d;
              }
            }),
            segments: [
              IosSegment(
                  value: PatternDistribution.spacing, label: t.lblSpacing),
              IosSegment(
                  value: PatternDistribution.distance,
                  label: t.lblTotalDistance),
              // Inventor's third option exists only for a row that runs along
              // a CURVE — there is nothing to fit to on a straight direction,
              // and an option that cannot act is a lie.
              if (path != null)
                IosSegment(
                    value: PatternDistribution.curveLength,
                    label: t.lblCurveLength),
            ],
          ),
        ),
        if (distribution != PatternDistribution.curveLength)
          iosValueRow(
            app: app,
            label: distribution == PatternDistribution.spacing
                ? t.lblSpacing
                : t.lblTotalDistance,
            controller: dist,
            unit: 'mm',
            onChanged: (v) => _changed(() {
              if (first) {
                s.exprDistanceA = v;
              } else {
                s.exprDistanceB = v;
              }
            }),
          ),
        // Inventor's Orientation Method belongs to a row on a PATH: only there
        // can a copy follow the curve instead of keeping its attitude.
        if (path != null && first)
          iosStackedRow(
            label: t.lblOrientation,
            child: IosSegmented<PatternOrient>(
              value: s.orientation,
              onChanged: (o) => _changed(() => s.orientation = o),
              segments: [
                IosSegment(value: PatternOrient.fixed, label: t.lblIdentical),
                IosSegment(
                    value: PatternOrient.rotational, label: t.lblDirectionA),
              ],
            ),
          ),
        ..._irregularRows(s, t, first ? 'A' : 'B',
            _countOf(first ? s.exprCountA : s.exprCountB), 'mm'),
      ],
    );
  }

  /// The three origin-axis quick picks, as a segmented control: they are
  /// mutually exclusive with each other and with a picked edge, which is
  /// exactly what a segmented control says.
  Widget _axisQuickRow(PatternField field, String? label, AppL10n t) =>
      iosStackedRow(
        child: IosSegmented<String>(
          value: label != null && label.endsWith(' Axis')
              ? label.substring(0, 1).toLowerCase()
              : '',
          onChanged: (k) => _pickOriginAxis(field, k),
          segments: const [
            IosSegment(value: 'x', label: 'X'),
            IosSegment(value: 'y', label: 'Y'),
            IosSegment(value: 'z', label: 'Z'),
          ],
        ),
      );

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

  /// Orientation section of a circular pattern.
  Widget _orientationSection(PartPatternSession s, AppL10n t) {
    final app = widget.app;
    return iosSection(
      header: t.lblOrientation,
      open: _aOpen,
      onToggle: () => setState(() => _aOpen = !_aOpen),
      children: [
        iosPickRow(
          label: t.lblDirection,
          value: s.axis?.label,
          hint: t.hintTapCircularEdge,
          armed: s.active == PatternField.axis,
          filled: s.axis != null,
          onTap: () => app.patternPick(PatternField.axis),
          onClear: s.axis == null ? null : () => _changed(() => s.axis = null),
        ),
        _axisQuickRow(PatternField.axis, s.axis?.label, t),
        iosSwitchRow(
          label: t.lblFlip,
          value: s.flipC,
          onChanged: (v) => _changed(() => s.flipC = v),
        ),
        iosValueRow(
          app: app,
          label: t.lblCount,
          controller: _countC,
          unit: 'ul',
          onChanged: (v) => _changed(() => s.exprCountC = v),
        ),
        iosStackedRow(
          label: t.lblDistribution,
          child: IosSegmented<PatternDistribution>(
            value: s.distributionC,
            onChanged: (d) => _changed(() => s.distributionC = d),
            // Inventor's names for the circular pair. "Incremental" is the
            // angle BETWEEN occurrences, "Fitted" the total they fill.
            segments: [
              IosSegment(
                  value: PatternDistribution.spacing, label: t.lblIncremental),
              IosSegment(
                  value: PatternDistribution.distance, label: t.btnFitted),
            ],
          ),
        ),
        iosValueRow(
          app: app,
          label: t.lblAngle,
          controller: _angleC,
          unit: 'deg',
          onChanged: (v) => _changed(() => s.exprAngleC = v),
        ),
        iosStackedRow(
          label: t.lblOrientation,
          child: IosSegmented<PatternOrient>(
            value: s.orientation,
            onChanged: (o) => _changed(() => s.orientation = o),
            segments: [
              IosSegment(
                  value: PatternOrient.rotational, label: t.lblRotational),
              IosSegment(value: PatternOrient.fixed, label: t.lblFixed),
            ],
          ),
        ),
        ..._irregularRows(s, t, 'C', _countOf(s.exprCountC), 'deg'),
      ],
    );
  }

  /// Placement section of a sketch-driven pattern.
  Widget _placementSection(PartPatternSession s, AppL10n t) {
    final app = widget.app;
    final p = app.currentPart;
    final cs = p == null || s.pointSketch.isEmpty
        ? null
        : p.sketchByName(s.pointSketch);
    final n = cs == null ? 0 : sketchPatternPoints(cs.model).length;
    return iosSection(
      header: t.secPlacement,
      open: _aOpen,
      onToggle: () => setState(() => _aOpen = !_aOpen),
      children: [
        iosPickRow(
          label: t.lblSketchPoint,
          value: s.pointSketch.isEmpty
              ? null
              : t.lblPointCount(s.pointSketch, n),
          hint: s.active == PatternField.pointSketch
              ? t.hintTapSketchPoint
              : t.lblSelectPoint,
          armed: s.active == PatternField.pointSketch,
          filled: s.pointSketch.isNotEmpty,
          onTap: () => app.patternPick(PatternField.pointSketch),
        ),
        iosPickRow(
          label: t.lblBasePoint,
          value: s.basePicked
              ? t.lblCoords(Fmt.fixed(s.baseX, 2), Fmt.fixed(s.baseY, 2))
              : null,
          hint: s.active == PatternField.basePoint
              ? t.hintTapOriginalPoint
              : t.lblSelectPoint,
          armed: s.active == PatternField.basePoint,
          filled: s.basePicked,
          onTap: () => app.patternPick(PatternField.basePoint),
          onClear:
              s.basePicked ? () => _changed(() => s.basePicked = false) : null,
        ),
        // Inventor's Variable Orientation: Identical keeps every copy parallel
        // to the parent, Follow Face turns it to the surface it lands on.
        iosStackedRow(
          label: t.lblOrientation,
          child: IosSegmented<bool>(
            value: s.orientFace != null,
            onChanged: (follow) => follow
                ? app.patternPick(PatternField.orientFace)
                : _changed(() => s.orientFace = null),
            segments: [
              IosSegment(value: false, label: t.lblIdentical),
              IosSegment(value: true, label: t.lblFollowFace),
            ],
          ),
        ),
        if (s.orientFace != null || s.active == PatternField.orientFace)
          iosPickRow(
            label: t.lblFaceField,
            value: s.orientFace == null ? null : t.lblFaceField,
            hint: s.active == PatternField.orientFace
                ? t.hintTapFaceToFollow
                : t.lblSelectFaceBtn,
            armed: s.active == PatternField.orientFace,
            filled: s.orientFace != null,
            onTap: () => app.patternPick(PatternField.orientFace),
            onClear: s.orientFace == null
                ? null
                : () => _changed(() => s.orientFace = null),
          ),
      ],
    );
  }

  /// Mirror plane section.
  Widget _mirrorSection(PartPatternSession s, AppL10n t) {
    final app = widget.app;
    final a = asm;
    final label = a != null ? a.refPlane?.label : s.plane?.label;
    final picked = a != null ? a.refPlane != null : s.plane != null;
    return iosSection(
      header: t.lblMirrorPlane,
      open: _aOpen,
      onToggle: () => setState(() => _aOpen = !_aOpen),
      children: [
        iosPickRow(
          label: t.lblPlaneField,
          value: label,
          hint: s.active == PatternField.plane
              ? t.hintTapFaceOrPlane
              : t.lblMirrorPlane,
          armed: s.active == PatternField.plane,
          filled: picked,
          onTap: () => app.patternPick(PatternField.plane),
          onClear: !picked
              ? null
              : () => _changed(() {
                    if (a != null) {
                      a.refPlane = null;
                      s.plane = null;
                    } else {
                      s.plane = null;
                    }
                  }),
        ),
        // Inventor's three origin-plane shortcuts, right in the dialog.
        iosStackedRow(
          child: IosSegmented<String>(
            value: label != null && label.endsWith(' Plane')
                ? label.substring(0, 2).toLowerCase()
                : '',
            onChanged: _pickOriginPlane,
            segments: const [
              IosSegment(value: 'yz', label: 'YZ'),
              IosSegment(value: 'xz', label: 'XZ'),
              IosSegment(value: 'xy', label: 'XY'),
            ],
          ),
        ),
      ],
    );
  }

  /// Inventor's Output Geometry. A PART's: Creation Method decides whether a
  /// termination is re-resolved where each copy lands, and Remove Original
  /// deletes half a solid. Neither exists for a component — a copy of a
  /// component is the same component — so an assembly shows the warning line
  /// in its place.
  Widget _outputGeometry(PartPatternSession s, AppL10n t) {
    final a = asm;
    if (a != null) {
      final dropped = widget.app.asmPatternDroppedRelationships();
      if (dropped == 0) return const SizedBox.shrink();
      return iosStatusLine(t.msgRelationshipsDropped(dropped), warning: true);
    }
    return iosSection(
      header: t.secOutputGeometry,
      open: _outOpen,
      onToggle: () => setState(() => _outOpen = !_outOpen),
      children: [
        iosStackedRow(
          label: t.lblCreationMethod,
          child: IosSegmented<PatternCompute>(
            value: s.compute,
            onChanged: (c) => _changed(() => s.compute = c),
            segments: [
              IosSegment(value: PatternCompute.identical, label: t.lblIdentical),
              IosSegment(value: PatternCompute.adjust, label: t.lblAdjust),
            ],
          ),
        ),
        // Inventor offers Remove Original only when a SOLID is being mirrored;
        // removing the original of a feature mirror would mean deleting a
        // feature that this one is built on.
        if (s.mode == PatternKind.mirror && s.patternSolid)
          iosSwitchRow(
            label: t.lblRemoveOriginal,
            value: s.removeOriginal,
            onChanged: (v) => _changed(() => s.removeOriginal = v),
          ),
      ],
    );
  }

  // ---- the rail ----------------------------------------------------------

  /// The four pattern commands and the two Input Geometry modes, in their own
  /// card beside the panel — Inventor's rail, drawn as a cluster of iOS
  /// toggles.
  Widget _rail(PartPatternSession s, AppL10n t) {
    final app = widget.app;
    final a = asm;
    return IosPanel(
      width: 60,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (kind, icon) in [
              (PatternKind.rectangular, PT['rect']!),
              (PatternKind.circular, PT['circ']!),
              // M248 — Sketch Driven is a PART command. An assembly has no
              // sketches of its own, and driving one from a sketch inside a
              // component needs that sketch picked THROUGH the occurrence,
              // which is a different feature nothing offers. Left out rather
              // than shown dead, because the rail's other entries all work.
              if (a == null) (PatternKind.sketchDriven, PT['sketch']!),
              (PatternKind.mirror, PT['mirror']!),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IosIconToggle(
                  on: s.mode == kind,
                  tooltip: patternKindDisplay(t, kind),
                  size: const Size(44, 40),
                  onTap: () => app.switchPattern(kind),
                  child: iosSvg(icon, 22),
                ),
              ),
            // Inventor's two Input Geometry modes — a PART's. An assembly has
            // no bodies, so there is no solid to pattern and no switch.
            if (a == null) ...[
              Container(
                height: IosMetrics.hairline,
                width: 28,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: IosColors.separator,
              ),
              for (final (solid, icon, name) in [
                (false, _featuresIcon, t.lblPatternFeatures),
                (true, _solidIcon, t.lblPatternSolid),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: IosIconToggle(
                    on: s.patternSolid == solid,
                    tooltip: name,
                    size: const Size(44, 40),
                    onTap: () => app.patternSetSolidMode(solid),
                    child: iosSvg(icon, 22),
                  ),
                ),
            ],
          ]),
        ),
      ],
    );
  }
}

/// The two Input Geometry modes, drawn here rather than in svg_icons.dart
/// because this rail is the only place either is used — the same rule the
/// extrude panel's direction glyphs follow.
const _featuresIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="2.5" y="2.5" width="6" height="6" rx="1" fill="#3D9BE9" fill-opacity=".55" stroke="#1a5f95" stroke-width=".9"/><rect x="9.5" y="9.5" width="6" height="6" rx="1" fill="#3D9BE9" fill-opacity=".55" stroke="#1a5f95" stroke-width=".9"/><rect x="9.5" y="2.5" width="6" height="6" rx="1" fill="none" stroke="#9aa0a6" stroke-width=".9" stroke-dasharray="2 1.4"/><rect x="2.5" y="9.5" width="6" height="6" rx="1" fill="none" stroke="#9aa0a6" stroke-width=".9" stroke-dasharray="2 1.4"/></svg>';

const _solidIcon =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 2 L15.5 5.5 L15.5 12.5 L9 16 L2.5 12.5 L2.5 5.5 Z" fill="#3D9BE9" fill-opacity=".5" stroke="#1a5f95" stroke-width="1"/><path d="M2.5 5.5 L9 9 L15.5 5.5 M9 9 L9 16" fill="none" stroke="#1a5f95" stroke-width=".9"/></svg>';
