// Prototype — the sketch tool windows: the 2D Pattern dialogs (M35), the 2D
// Fillet / Chamfer value window (M36) and the Polygon side count (M207).
//
//   Rectangular: Geometry | Direction 1 + Direction 2 (select/flip, count,
//                spacing) | Extents (boundary fill — future work, offered
//                exactly as Inventor offers it before a boundary is picked)
//                | OK Cancel >>  and the Suppress / Associative / Fitted
//                block behind ">>".
//   Circular:    Geometry + Axis (+ flip) | count + angle | Extents | footer.
//   Mirror:      Select + Mirror Line + Self Symmetric | Apply Done Cancel.
//
// The dialogs are MODELESS: they float over the viewport and the user keeps
// tapping geometry while they are open. Which input a tap feeds is the ACTIVE
// selector — AppState._patternClick routes it.
//
// M338 — drawn as iOS panels (widgets/ios_kit.dart). Four notes:
//
//   * THE PICK BUTTONS ARE ROWS. `_PickBtn` was a 28 pt square holding a
//     cursor glyph, with a blue underline once its pick existed and the word
//     for what it picks in a Text beside it. The row says both: the name on
//     the leading edge and what is in it on the trailing one.
//   * THE ICONS BESIDE THE NUMBERS ARE NAMES. A yellow diamond meant
//     "spacing" and a dotted arc meant "angle"; the ARB already had both
//     words, and a labelled row does not need to be learned.
//   * THE "?" BADGE IS A FOOTER. It carried a real sentence — "pick while the
//     selector is blue" — in a tooltip, which on a touch screen is nowhere.
//     It is the Geometry section's footer now.
//   * WHAT IS NOT BUILT STAYS VISIBLE, dimmed, with the reason written under
//     it rather than hidden in a tooltip: Inventor's boundary fill, its
//     along-a-path direction mode and its Suppress. Same decision the Drive
//     panel makes about Adaptivity and Collision Detection.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ffi/qcad_engine.dart';
import '../ios_design.dart';
import '../scrub.dart';
import 'ios_kit.dart';
import '../l10n/l.dart';

// ===========================================================================
// the 2D pattern dialogs
// ===========================================================================

class PatternDialog extends StatefulWidget {
  final AppState app;
  const PatternDialog({super.key, required this.app});
  @override
  State<PatternDialog> createState() => _PatternDialogState();
}

class _PatternDialogState extends State<PatternDialog> {
  late final TextEditingController _c1, _s1, _c2, _s2, _cc, _ac;
  bool _advancedOpen = false;

  PatternSession get ps => widget.app.pattern!;

  @override
  void initState() {
    super.initState();
    _c1 = TextEditingController(text: '${ps.count1}');
    _s1 = TextEditingController(text: _n(ps.spacing1));
    _c2 = TextEditingController(text: '${ps.count2}');
    _s2 = TextEditingController(text: _n(ps.spacing2));
    _cc = TextEditingController(text: '${ps.countC}');
    _ac = TextEditingController(text: _n(ps.angleC));
  }

  @override
  void dispose() {
    for (final c in [_c1, _s1, _c2, _s2, _cc, _ac]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    if (app.pattern == null) return const SizedBox.shrink();
    final t = L.of(context);
    final mirror = ps.kind == Tool.mirror;
    return IosPanel(
      width: IosMetrics.panelWidth,
      nav: IosNavBar(
        title: switch (ps.kind) {
          Tool.patRect => t.patRectangular,
          Tool.patCirc => t.patCircular,
          _ => t.patMirror,
        },
        leading: IosBarButton(label: t.cancel, onTap: app.cancelTool),
        trailing: IosBarButton(
            label: mirror ? t.done : t.ok,
            prominent: true,
            onTap: () => app.commitPattern()),
      ),
      // Only Mirror has a third verb; Inventor gives the other two OK and
      // Cancel alone.
      footer: !mirror
          ? null
          : iosFooter(children: [
              Expanded(
                child: IosButton(
                  label: t.apply,
                  style: IosButtonStyle.tinted,
                  height: 38,
                  expand: true,
                  onTap: () => app.commitPattern(keepOpen: true),
                ),
              ),
            ]),
      children: switch (ps.kind) {
        Tool.patRect => _rect(app, t),
        Tool.patCirc => _circ(app, t),
        _ => _mirror(app, t),
      },
    );
  }

  // ---- Rectangular ---------------------------------------------------------

  List<Widget> _rect(AppState app, AppL10n t) => [
        _geometrySection(app, t),
        _directionSection(app, t, 1),
        _directionSection(app, t, 2),
        _extentsSection(t),
        _advancedSection(app, t),
      ];

  Widget _directionSection(AppState app, AppL10n t, int which) {
    final field = which == 1 ? PatField.dir1 : PatField.dir2;
    final ent = which == 1 ? ps.dir1Ent : ps.dir2Ent;
    final flip = which == 1 ? ps.flip1 : ps.flip2;
    // Direction 2 stays inert until Direction 1 is picked — Inventor's flow.
    final enabled = which == 1 || ps.dir1Ent != null;
    final cCtrl = which == 1 ? _c1 : _c2;
    final sCtrl = which == 1 ? _s1 : _s2;
    return iosSection(
      header: t.lblDirectionN('$which'),
      children: [
        iosPickRow(
          label: t.lblGeometry,
          value: ent == null ? null : t.lblLineN('$ent'),
          hint: t.tipSelectDirectionLine,
          armed: enabled && ps.active == field,
          filled: ent != null,
          onTap: enabled
              ? () {
                  ps.active = field;
                  app.patNotify();
                }
              : null,
        ),
        iosSwitchRow(
          label: t.tipFlipDirection,
          value: flip,
          onChanged: enabled && ent != null
              ? (v) {
                  if (which == 1) {
                    ps.flip1 = v;
                  } else {
                    ps.flip2 = v;
                  }
                  app.patNotify();
                }
              : null,
        ),
        // Inventor's third direction mode: run the row along a picked path.
        iosSwitchRow(label: t.tipPatternAlongPath, value: false),
        iosValueRow(
          app: app,
          label: t.lblNumber,
          controller: cCtrl,
          integer: true,
          min: 1,
          max: 64,
          enabled: enabled,
          onChanged: (text) {
            final v = double.tryParse(text.replaceAll(',', '.'));
            if (v == null) return;
            final n = v.toInt().clamp(1, 64);
            if (which == 1) {
              ps.count1 = n;
            } else {
              ps.count2 = n;
            }
            app.patNotify();
          },
        ),
        iosValueRow(
          app: app,
          label: t.lblSpacing,
          controller: sCtrl,
          unitLabel: 'mm',
          kind: ScrubKind.length,
          enabled: enabled,
          onChanged: (text) {
            final v = double.tryParse(text.replaceAll(',', '.'));
            if (v == null || v <= 0) return;
            if (which == 1) {
              ps.spacing1 = v;
            } else {
              ps.spacing2 = v;
            }
            app.patNotify();
          },
        ),
      ],
    );
  }

  // ---- Circular ------------------------------------------------------------

  List<Widget> _circ(AppState app, AppL10n t) => [
        _geometrySection(app, t),
        iosSection(
          header: t.lblAxis,
          children: [
            iosPickRow(
              label: t.lblAxis,
              value: ps.axisPt == null ? null : t.lblLineN('${ps.axisPt!.ent}'),
              hint: t.tipSelectRotationAxisPoint,
              armed: ps.active == PatField.axis,
              filled: ps.axisPt != null,
              onTap: () {
                ps.active = PatField.axis;
                app.patNotify();
              },
            ),
            iosSwitchRow(
              label: t.tipFlipRotation,
              value: ps.flipC,
              onChanged: ps.axisPt == null
                  ? null
                  : (v) {
                      ps.flipC = v;
                      app.patNotify();
                    },
            ),
            iosValueRow(
              app: app,
              label: t.lblCount,
              controller: _cc,
              integer: true,
              min: 2,
              max: 128,
              onChanged: (text) {
                final v = double.tryParse(text.replaceAll(',', '.'));
                if (v == null) return;
                ps.countC = v.toInt().clamp(2, 128);
                app.patNotify();
              },
            ),
            iosValueRow(
              app: app,
              label: t.lblAngle,
              controller: _ac,
              unitLabel: 'deg',
              kind: ScrubKind.angle,
              min: -360,
              max: 360,
              onChanged: (text) {
                final v = double.tryParse(text.replaceAll(',', '.'));
                if (v == null) return;
                ps.angleC = v.clamp(-360.0, 360.0);
                app.patNotify();
              },
            ),
          ],
        ),
        _extentsSection(t),
        _advancedSection(app, t),
      ];

  // ---- Mirror --------------------------------------------------------------

  List<Widget> _mirror(AppState app, AppL10n t) {
    final s = app.current;
    // Self Symmetric is only offered for a single OPEN spline (Inventor).
    var selfSymOk = false;
    if (s != null && ps.geo.length == 1) {
      final i = ps.geo.first;
      if (i < s.geometry.length) {
        final g = s.geometry[i];
        selfSymOk = g.type == Geo.polyline &&
            (g.spline == Geo.splineCv || g.spline == Geo.splineFit) &&
            g.data[0] == 0;
      }
    }
    if (!selfSymOk) ps.selfSym = false;
    return [
      iosSection(
        header: t.lblGeometry,
        footer: t.msgPickWhileSelectorBlue,
        children: [
          iosPickRow(
            label: t.select,
            value: ps.geo.isEmpty ? null : t.lblSelectedCount(ps.geo.length),
            hint: t.tipSelectGeometryToMirror,
            armed: ps.active == PatField.geometry,
            filled: ps.geo.isNotEmpty,
            onTap: () {
              ps.active = PatField.geometry;
              app.patNotify();
            },
          ),
          iosPickRow(
            label: t.lblMirrorLine,
            value: ps.mirrorEnt == null
                ? null
                : t.lblLineN('${ps.mirrorEnt}'),
            hint: t.tipSelectMirrorLine,
            armed: ps.active == PatField.mirrorLine,
            filled: ps.mirrorEnt != null,
            onTap: () {
              ps.active = PatField.mirrorLine;
              app.patNotify();
            },
          ),
        ],
      ),
      iosSection(
        footer: selfSymOk ? null : t.lblSingleOpenSplineOnly,
        children: [
          iosSwitchRow(
            label: t.btnSelfSymmetric,
            value: ps.selfSym,
            onChanged: selfSymOk
                ? (v) {
                    ps.selfSym = v;
                    app.patNotify();
                  }
                : null,
          ),
        ],
      ),
    ];
  }

  // ---- shared sections -----------------------------------------------------

  Widget _geometrySection(AppState app, AppL10n t) => iosSection(
        header: t.lblGeometry,
        // The "?" badge's sentence, in the open. It is the one thing a user
        // has to know about these dialogs and it was living in a tooltip.
        footer: t.msgPickWhileSelectorBlue,
        children: [
          iosPickRow(
            label: t.select,
            value: ps.geo.isEmpty ? null : t.lblSelectedCount(ps.geo.length),
            hint: t.tipSelectGeometryToPattern,
            armed: ps.active == PatField.geometry,
            filled: ps.geo.isNotEmpty,
            onTap: () {
              ps.active = PatField.geometry;
              app.patNotify();
            },
          ),
        ],
      );

  /// Inventor's Extents / Boundary block, offered exactly as Inventor offers
  /// it before a boundary exists: present and inert. Boundary fill is future
  /// work (HANDOFF), and the footer says so instead of a tooltip.
  Widget _extentsSection(AppL10n t) => iosSection(
        header: t.lblExtents,
        footer: t.msgBoundaryFillNotYet,
        children: [
          iosRow(label: t.lblBoundary, enabled: false, chevron: true),
          iosSwitchRow(label: t.lblIncludeGeometry, value: false),
        ],
      );

  /// Inventor's ">>" block: Suppress (future work) + Associative + Fitted.
  Widget _advancedSection(AppState app, AppL10n t) => iosSection(
        header: t.secAdvancedProperties,
        open: _advancedOpen,
        onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
        footer: _advancedOpen ? t.msgSuppressNotYet : null,
        children: [
          iosSwitchRow(label: t.lblSuppress, value: false),
          iosSwitchRow(
            label: t.btnAssociative,
            value: ps.associative,
            onChanged: (v) {
              ps.associative = v;
              app.patNotify();
            },
          ),
          iosSwitchRow(
            label: t.btnFitted,
            value: ps.fitted,
            onChanged: (v) {
              ps.fitted = v;
              app.patNotify();
            },
          ),
        ],
      );
}

// ===========================================================================
// the 2D fillet / chamfer value window
// ===========================================================================

/// The modeless 2D Fillet / 2D Chamfer window (M36) — Inventor's tiny value
/// dialogs: it floats while the tool is armed, every two picks make a corner,
/// and the values are editable between corners. Chamfer offers Inventor's
/// three modes (equal distance / two distances / distance + angle).
///
/// M207 — no ✕: it was a third way to say Cancel, next to Esc and the
/// quick-tool bar's own Cancel button, on a window whose whole job is to hold
/// one number. M338 keeps that decision, so this panel has no navigation
/// actions at all — only a title.
class FilletChamferDialog extends StatefulWidget {
  final AppState app;
  const FilletChamferDialog({super.key, required this.app});
  @override
  State<FilletChamferDialog> createState() => _FilletChamferDialogState();
}

class _FilletChamferDialogState extends State<FilletChamferDialog> {
  late final TextEditingController _r, _d1, _d2, _ang;

  FilletSession get fs => widget.app.filletSess!;

  @override
  void initState() {
    super.initState();
    _r = TextEditingController(text: _n(fs.radius));
    _d1 = TextEditingController(text: _n(fs.d1));
    _d2 = TextEditingController(text: _n(fs.d2));
    _ang = TextEditingController(text: _n(fs.angle));
  }

  @override
  void dispose() {
    for (final c in [_r, _d1, _d2, _ang]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    if (app.filletSess == null) return const SizedBox.shrink();
    final t = L.of(context);
    final isFillet = fs.kind == Tool.fillet;
    return IosPanel(
      width: 300,
      nav: IosNavBar(title: isFillet ? t.btnFillet : t.btnChamfer),
      children: isFillet ? _fillet(app, t) : _chamfer(app, t),
    );
  }

  List<Widget> _fillet(AppState app, AppL10n t) => [
        iosSection(
          footer: t.msgFilletPickTwo,
          children: [
            toolValueRow(
                app: app,
                label: t.lblRadius,
                ctrl: _r,
                unitLabel: 'mm',
                min: 0.1, onValue: (v) {
              fs.radius = v;
              app.filletNotify();
            }),
          ],
        ),
      ];

  List<Widget> _chamfer(AppState app, AppL10n t) => [
        iosSection(
          footer: t.msgDistance1FirstLine,
          children: [
            iosStackedRow(
              label: t.lblMethod,
              child: IosSegmented<int>(
                value: fs.mode,
                onChanged: (m) {
                  fs.mode = m;
                  app.filletNotify();
                },
                segments: [
                  IosSegment(value: 0, label: t.lblEqualDistance),
                  IosSegment(value: 1, label: t.lblTwoDistances),
                  IosSegment(value: 2, label: t.lblDistanceAndAngle),
                ],
              ),
            ),
            toolValueRow(
                app: app,
                label: fs.mode == 0 ? t.lblDistance : t.lblDistance1,
                ctrl: _d1,
                unitLabel: 'mm',
                min: 0.1, onValue: (v) {
              fs.d1 = v;
              app.filletNotify();
            }),
            if (fs.mode == 1)
              toolValueRow(
                  app: app,
                  label: t.lblDistance2,
                  ctrl: _d2,
                  unitLabel: 'mm',
                  min: 0.1, onValue: (v) {
                fs.d2 = v;
                app.filletNotify();
              }),
            if (fs.mode == 2)
              toolValueRow(
                  app: app,
                  label: t.lblAngle,
                  ctrl: _ang,
                  unitLabel: 'deg',
                  kind: ScrubKind.angle,
                  min: 1,
                  max: 89, onValue: (v) {
                fs.angle = v;
                app.filletNotify();
              }),
          ],
        ),
      ];
}

/// M207 — ONE number row for the modeless tool windows.
///
/// The 2D Fillet's radius is the row the device asked every other tool value
/// to look like ("this polygon input field ... should be similar to the radius
/// input field"), so it stopped being a private method of that one dialog.
/// The field, the unit, the scrub and the number pad all come from here, and a
/// second spelling of any of them cannot drift in behind the first.
///
/// M338 — the shared piece is now [iosValueRow]; what stays here is the
/// contract these windows hold their numbers under: a BARE number in the
/// controller (so the parse below works), the unit drawn beside it, and a
/// value that is only pushed to the model when it is positive.
Widget toolValueRow({
  required AppState app,
  required String label,
  required TextEditingController ctrl,
  required void Function(double) onValue,
  String? unitLabel,
  ScrubKind? kind,
  double? min,
  double? max,
  /// Whole numbers only — a polygon has no 5.5 sides.
  bool integer = false,
}) =>
    iosValueRow(
      app: app,
      label: label,
      controller: ctrl,
      unitLabel: unitLabel,
      kind: kind,
      integer: integer,
      min: min,
      max: max,
      onChanged: (text) {
        final v = double.tryParse(text.replaceAll(',', '.'));
        if (v != null && v > 0) onValue(v);
      },
    );

// ===========================================================================
// the polygon side count
// ===========================================================================

/// M207 — the polygon's side count, as a modeless window.
///
/// "This polygon input field needs to be redone; it should be similar to the
/// radius input field."
///
/// It was an AlertDialog: modal, blocking, with the tool not armed until it
/// was answered. Two things followed from that. The number pad opened over a
/// modal barrier and behaved like it — "the small number input field doesn't
/// work, it just closes directly when i want to input something" — and the
/// count could not be changed once the dialog was gone, so drawing a hexagon
/// and then a pentagon meant re-picking the tool.
///
/// This is the 2D Fillet window's shape instead: the tool is armed
/// immediately, the window rides along beside it, and the value applies to the
/// NEXT polygon placed. Same chrome, same number row, same scrub, same pad.
class PolygonDialog extends StatefulWidget {
  final AppState app;
  const PolygonDialog({super.key, required this.app});

  /// Sides a fresh polygon starts with, and what the field shows when the tool
  /// is armed without a value of its own.
  static const int defaultSides = 6;
  static const int minSides = 3;
  static const int maxSides = 64;

  @override
  State<PolygonDialog> createState() => _PolygonDialogState();
}

class _PolygonDialogState extends State<PolygonDialog> {
  late final TextEditingController _sides;

  @override
  void initState() {
    super.initState();
    _sides = TextEditingController(text: '${_current()}');
  }

  int _current() {
    final v = widget.app.toolParams['sides'];
    return (v ?? PolygonDialog.defaultSides.toDouble())
        .round()
        .clamp(PolygonDialog.minSides, PolygonDialog.maxSides);
  }

  @override
  void dispose() {
    _sides.dispose();
    super.dispose();
  }

  void _apply(double v) {
    final n = v
        .round()
        .clamp(PolygonDialog.minSides, PolygonDialog.maxSides)
        .toDouble();
    // A new map, not a mutation: toolParams is read by the preview and by the
    // commit, and both must see the same value at the same time.
    widget.app.polygonSidesNotify(n);
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    return IosPanel(
      width: 300,
      nav: IosNavBar(title: t.dlgPolygon),
      children: [
        iosSection(
          footer: t.msgPolygonSides,
          children: [
            toolValueRow(
              app: widget.app,
              label: t.lblCount,
              ctrl: _sides,
              onValue: _apply,
              min: PolygonDialog.minSides.toDouble(),
              max: PolygonDialog.maxSides.toDouble(),
              integer: true,
            ),
          ],
        ),
      ],
    );
  }
}
