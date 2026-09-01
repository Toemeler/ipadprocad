// Prototype — the extrusion property panel (M56), which grew into the panel
// for all five swept features: Extrude, Revolve, Sweep, Loft and Coil (M131b).
// The viewport does the profile picking; this panel shows and edits the
// session state, and every keystroke re-previews.
//
// M338 — drawn as an iOS panel (widgets/ios_kit.dart). It is the panel this
// milestone was measured against, so the four decisions it forced are worth
// writing down here rather than in the kit:
//
//   * THE TITLE IS THE COMMAND. The old bar said "Properties" and put the
//     command in a breadcrumb underneath ("Extrusion › Sketch1"). A navigation
//     bar names the thing you are looking at, so the title is the feature and
//     the sketch is the subtitle — which is the same information in the shape
//     iOS reads it in.
//
//   * OK AND CANCEL ARE IN THE BAR, "+" IS IN THE FOOTER. Cancel leads, OK
//     trails, per the HIG. The third verb — Inventor's "+", apply and start
//     another — became a labelled Apply button in the footer, because a bare
//     `+` next to OK is a coin toss under a thumb and its meaning lived only
//     in a tooltip.
//
//   * THE EXTENTS ARE A MENU, NOT THREE ICONS BESIDE THE FIELD. Distance was
//     never a button: the FIELD was the Distance option, and the three icons
//     toggled around it, so "which extent am I in" had to be read off a border
//     colour. All four are now one pop-up row that names the one in force —
//     and the German names ("Bis zum Nächsten") do not fit four segments of a
//     308 pt control, which is the other half of the reason.
//
//   * A DEAD CONTROL IS NOT A CONTROL. The old title bar carried a magnifier
//     and a hamburger, and the breadcrumb an eye and a cube; none of the four
//     had an `onTap`. They were traced from Inventor's chrome. See the kit's
//     header — in a navigation bar every glyph reads as a button, so an inert
//     one is a lie.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import '../part_model.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';

class ExtrudeDialog extends StatefulWidget {
  final AppState app;
  const ExtrudeDialog({super.key, required this.app});
  @override
  State<ExtrudeDialog> createState() => _ExtrudeDialogState();
}

class _ExtrudeDialogState extends State<ExtrudeDialog> {
  /// M122 — null until first laid out, then parked on the RIGHT, vertically
  /// centred. It stays draggable — this only decides where it opens.
  Offset? _pos;
  bool _inputOpen = true, _behaviorOpen = true, _outputOpen = true,
      _advancedOpen = true;
  late final TextEditingController _a, _b, _taper, _body;
  // M131b — sweep / coil fields
  late final TextEditingController _twist, _revs, _height, _pitch, _coilTaper;

  static const _size = Size(IosMetrics.panelWidth, 620);

  ExtrudeSession get sess => widget.app.extrudeSession!;

  @override
  void initState() {
    super.initState();
    _a = TextEditingController(text: sess.exprA);
    _b = TextEditingController(text: sess.exprB);
    _taper = TextEditingController(text: sess.exprTaper);
    _twist = TextEditingController(text: sess.exprTwist);
    _revs = TextEditingController(text: sess.exprRevolutions);
    _height = TextEditingController(text: sess.exprHeight);
    _pitch = TextEditingController(text: sess.exprPitch);
    _coilTaper = TextEditingController(text: sess.exprCoilTaper);
    _body = TextEditingController(text: sess.bodyName);
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _taper.dispose();
    _twist.dispose();
    _revs.dispose();
    _height.dispose();
    _pitch.dispose();
    _coilTaper.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = sess;
    final t = L.of(context);
    final sketchLabel = s.sketchName ?? 'Sketch1';
    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: s.editing?.name ??
              switch (s.kind) {
                'revolve' => t.featRevolution,
                'sweep' => t.btnSweep,
                'loft' => t.btnLoft,
                'coil' => t.btnCoil,
                _ => t.btnExtrude,
              },
          subtitle: Text(sketchLabel),
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelExtrude),
          trailing: IosBarButton(
              label: t.ok,
              prominent: true,
              onTap: () => app.applyExtrude(keepOpen: false)),
        ),
        footer: iosFooter(children: [
          Expanded(
            child: IosButton(
              label: t.apply,
              glyph: IosGlyph.plus,
              style: IosButtonStyle.tinted,
              height: 38,
              expand: true,
              tooltip: t.tipApplyAndStartAnother,
              onTap: () => app.applyExtrude(keepOpen: true),
            ),
          ),
        ]),
        children: [
          _inputSection(app, s, t),
          _behaviorSection(app, s, t),
          _outputSection(app, s, t),
          _advancedSection(app, s, t),
          if (s.previewError != null) iosStatusLine(s.previewError!),
        ],
      ),
    );
  }

  // ---- Input Geometry ------------------------------------------------------

  Widget _inputSection(AppState app, ExtrudeSession s, AppL10n t) => iosSection(
        header: t.secInputGeometry,
        open: _inputOpen,
        onToggle: () => setState(() => _inputOpen = !_inputOpen),
        children: [
          iosPickRow(
            label: t.lblProfiles,
            value: s.profiles.isEmpty
                ? null
                : t.lblProfileCount(s.profiles.length),
            hint: t.hintSelectProfile,
            armed: s.profiles.isEmpty,
            filled: s.profiles.isNotEmpty,
            onClear: s.profiles.isEmpty ? null : app.clearSessionProfiles,
          ),
          // Read-only: which plane the profile came off. Inventor lets this be
          // re-picked; this app has one sketch per feature, so it reads back
          // rather than pretending to be a control.
          iosRow(label: t.lblFrom, value: t.lblSketchPlaneN('1')),
        ],
      );

  // ---- Behavior ------------------------------------------------------------

  Widget _behaviorSection(AppState app, ExtrudeSession s, AppL10n t) {
    final rows = <Widget>[
      iosStackedRow(
        label: t.lblDirection,
        child: IosSegmented<ExtrudeDirection>(
          value: s.direction,
          onChanged: (d) => setState(() => app.setExtrude(direction: d)),
          segments: [
            for (final d in ExtrudeDirection.values)
              IosSegment(
                value: d,
                icon: iosSvg(_dirIcons[d]!, 22),
                tooltip: switch (d) {
                  ExtrudeDirection.defaultDir => t.lblDefault,
                  ExtrudeDirection.flipped => t.lblFlipped,
                  ExtrudeDirection.symmetric => t.lblSymmetric,
                  ExtrudeDirection.asymmetric => t.lblAsymmetric,
                },
              ),
          ],
        ),
      ),
    ];

    // M131b — Sweep drives the profile along a picked path.
    if (s.isSweep) {
      rows.addAll([
        iosPickRow(
          label: t.lblPath,
          value: s.path == null ? null : t.lblPathSelected,
          hint: app.pickingSweepPath
              ? t.hintTapCurveIn3d
              : t.lblSelectCurveOrEdge,
          armed: app.pickingSweepPath,
          filled: s.path != null,
          required_: s.path == null,
          onTap: app.pickingSweepPath
              ? app.cancelPickSweepPath
              : app.beginPickSweepPath,
        ),
        iosStackedRow(
          label: t.lblOrientation,
          child: IosSegmented<int>(
            value: s.orientation,
            onChanged: (v) => app.setExtrude(orientation: v),
            segments: [
              IosSegment(value: 0, label: t.lblFollowPath),
              IosSegment(value: 1, label: t.lblFixed),
              IosSegment(value: 2, label: t.lblGuide),
            ],
          ),
        ),
        iosValueRow(
            app: app,
            label: t.lblTaper,
            controller: _taper,
            unit: 'deg',
            onChanged: (v) => app.setExtrude(exprTaper: v)),
        iosValueRow(
            app: app,
            label: t.lblTwist,
            controller: _twist,
            unit: 'deg',
            onChanged: (v) => app.setExtrude(exprTwist: v)),
      ]);
    }

    // M131b — Loft collects sections instead of one profile.
    if (s.isLoft) {
      rows.addAll([
        iosPickRow(
          label: t.lblSections,
          value: s.loftSections.isEmpty
              ? null
              : t.lblSectionCount(s.loftSections.length),
          hint: app.pickingLoftSections
              ? (s.loftSections.isEmpty
                  ? t.hintTapProfilesIn3d
                  : t.hintTapToFinish)
              : t.hintClickToAdd,
          armed: app.pickingLoftSections,
          filled: s.loftSections.isNotEmpty,
          onTap: app.pickingLoftSections
              ? app.cancelPickLoftSections
              : app.beginPickLoftSections,
        ),
        iosStackedRow(
          label: t.lblTransition,
          child: IosSegmented<bool>(
            value: s.loftRuled,
            onChanged: (v) => app.setExtrude(loftRuled: v),
            segments: [
              IosSegment(value: false, label: t.lblSmooth),
              IosSegment(value: true, label: t.lblRuled),
            ],
          ),
        ),
        iosSwitchRow(
            label: t.lblClosedLoop,
            value: s.loftClosed,
            onChanged: (v) => app.setExtrude(loftClosed: v)),
        iosSwitchRow(
            label: t.lblMergeTangentFaces,
            value: s.loftMergeTangent,
            onChanged: (v) => app.setExtrude(loftMergeTangent: v)),
      ]);
    }

    // M131b — Coil: axis plus one of four equivalent methods.
    if (s.isCoil) {
      rows.add(IosMenuRow<int>(
        label: t.lblMethod,
        value: s.coilMethod.clamp(0, 3),
        cancelLabel: t.cancel,
        choices: [
          IosMenuChoice(0, t.coilRevAndHeight),
          IosMenuChoice(1, t.coilPitchAndRev),
          IosMenuChoice(2, t.coilPitchAndHeight),
          IosMenuChoice(3, t.coilSpiral),
        ],
        onChanged: (v) => app.setExtrude(coilMethod: v),
      ));
      if (s.coilMethod != 2) {
        rows.add(iosValueRow(
            app: app,
            label: t.lblRevolutionCount,
            controller: _revs,
            unit: 'ul',
            onChanged: (v) => app.setExtrude(exprRevolutions: v)));
      }
      if (s.coilMethod == 0 || s.coilMethod == 2) {
        rows.add(iosValueRow(
            app: app,
            label: t.lblHeight,
            controller: _height,
            unit: 'mm',
            onChanged: (v) => app.setExtrude(exprHeight: v)));
      }
      if (s.coilMethod == 1 || s.coilMethod == 2) {
        rows.add(iosValueRow(
            app: app,
            label: t.lblPitch,
            controller: _pitch,
            unit: 'mm',
            onChanged: (v) => app.setExtrude(exprPitch: v)));
      }
      rows.addAll([
        iosValueRow(
            app: app,
            label: t.lblTaper,
            controller: _coilTaper,
            unit: 'deg',
            onChanged: (v) => app.setExtrude(exprCoilTaper: v)),
        iosStackedRow(
          label: t.lblRotationAngle,
          child: IosSegmented<bool>(
            value: s.coilClockwise,
            onChanged: (v) => app.setExtrude(coilClockwise: v),
            segments: const [
              IosSegment(value: false, label: 'CCW'),
              IosSegment(value: true, label: 'CW'),
            ],
          ),
        ),
      ]);
    }

    // M137 — Revolve needs an axis before anything else can be computed, so it
    // sits above the angle.
    if (s.isRevolve || s.isCoil) {
      rows.add(iosPickRow(
        label: t.lblAxis,
        value: s.axisPicked ? s.axisLabel : null,
        hint: app.pickingRevolveAxis ? t.hintTapLineOrAxis : t.lblSelectAxis,
        armed: app.pickingRevolveAxis,
        filled: s.axisPicked,
        required_: !s.axisPicked,
        onTap: app.pickingRevolveAxis
            ? app.cancelPickRevolveAxis
            : app.beginPickRevolveAxis,
      ));
    }

    // Inventor's Full: a complete turn, which overrides the angle.
    if (s.isRevolve) {
      rows.add(iosSwitchRow(
          label: t.lblFull,
          value: s.full,
          onChanged: (v) => app.setExtrude(full: v)));
    }

    // M132/M143/M144 — the four extents. Distance is one of them now rather
    // than the absence of the other three; see the file header.
    final canTerminate = app.extrudeHasBooleanTarget;
    const extents = [
      FeatureExtent.distance,
      FeatureExtent.toNext,
      FeatureExtent.toFace,
      FeatureExtent.throughAll,
    ];
    rows.add(canTerminate
        ? IosMenuRow<FeatureExtent>(
            label: t.lblTermination,
            value: s.extent,
            cancelLabel: t.cancel,
            choices: [
              for (final e in extents) IosMenuChoice(e, extentName(t, e)),
            ],
            onChanged: (e) {
              app.setExtrude(extent: e);
              // Inventor asks for the face the moment you choose "To"; leaving
              // it disarms, so switching away cannot strand the viewport in a
              // pick mode with no dialog row to cancel it.
              if (e == FeatureExtent.toFace) {
                app.beginPickExtentFace();
              } else {
                app.cancelPickExtentFace();
              }
            },
          )
        // With nothing built yet there is no face to terminate against, so the
        // other three are not offered rather than offered and refused. The
        // footer under this section says why.
        : iosRow(
            label: t.lblTermination,
            value: extentName(t, FeatureExtent.distance)));

    final distanceLive = s.extent == FeatureExtent.distance &&
        !(s.isRevolve && s.full);
    rows.add(iosValueRow(
      app: app,
      label: s.isRevolve ? t.lblAngleA : t.lblDistanceA,
      controller: _a,
      unit: s.isRevolve ? 'deg' : 'mm',
      enabled: distanceLive,
      onChanged: (v) => app.setExtrude(exprA: v),
    ));
    if (s.direction == ExtrudeDirection.asymmetric && distanceLive) {
      rows.add(iosValueRow(
        app: app,
        label: s.isRevolve ? t.lblAngleB : t.lblDistanceB,
        controller: _b,
        unit: s.isRevolve ? 'deg' : 'mm',
        onChanged: (v) => app.setExtrude(exprB: v),
      ));
    }
    if (s.extent == FeatureExtent.toFace) {
      rows.add(iosPickRow(
        label: t.lblTerminateOn,
        value: s.extentFace == null ? null : t.lblFaceSelected,
        hint: app.pickingExtentFace ? t.hintTapFaceIn3d : t.lblSelectFace,
        armed: app.pickingExtentFace,
        filled: s.extentFace != null,
        required_: s.extentFace == null,
        onTap: app.pickingExtentFace
            ? app.cancelPickExtentFace
            : app.beginPickExtentFace,
      ));
    }

    return iosSection(
      header: t.secBehavior,
      open: _behaviorOpen,
      onToggle: () => setState(() => _behaviorOpen = !_behaviorOpen),
      footer: canTerminate ? null : t.hintTerminationNeedsBody,
      children: rows,
    );
  }

  // ---- Output --------------------------------------------------------------

  Widget _outputSection(AppState app, ExtrudeSession s, AppL10n t) {
    final bodies = app.currentPart?.bodyNames ?? const <String>[];
    final target = app.extrudeHasBooleanTarget;
    return iosSection(
      header: t.secOutput,
      open: _outputOpen,
      onToggle: () => setState(() => _outputOpen = !_outputOpen),
      children: [
        // Inventor's Output boolean, applied against the existing body: Join
        // (union), Cut (subtract), Intersect (overlap), New Solid (separate
        // body). Cut/Intersect need something to act on, so they are dimmed
        // for the base feature.
        iosStackedRow(
          label: t.lblBoolean,
          child: IosSegmented<String>(
            value: s.output,
            onChanged: (key) {
              app.setExtrude(output: key);
              // M96 — the name field is built ONCE in initState, so when
              // setExtrude picks a fresh body name for New Solid ("Solid2")
              // the controller kept showing the old text and the user had to
              // retype it. Pull the controller back onto the session whenever
              // the output mode changes it.
              if (_body.text != sess.bodyName) {
                _body.text = sess.bodyName;
                _body.selection =
                    TextSelection.collapsed(offset: _body.text.length);
              }
              setState(() {});
            },
            segments: [
              IosSegment(
                  value: 'join',
                  icon: iosSvg(_boolIcons['join']!, 20),
                  tooltip: t.opJoin),
              IosSegment(
                  value: 'cut',
                  icon: iosSvg(_boolIcons['cut']!, 20),
                  enabled: target,
                  tooltip: target
                      ? t.opCut
                      : t.lblNeedsExistingBody(t.opCut)),
              IosSegment(
                  value: 'intersect',
                  icon: iosSvg(_boolIcons['intersect']!, 20),
                  enabled: target,
                  tooltip: target
                      ? t.opIntersect
                      : t.lblNeedsExistingBody(t.opIntersect)),
              IosSegment(
                  value: 'new',
                  icon: iosSvg(_boolIcons['new']!, 20),
                  tooltip: t.opNewSolid),
            ],
          ),
        ),
        // M99 — no dropdown. The target body is PICKED, not chosen from a
        // list: tap it in 3D or in the model browser. A dropdown of body names
        // is exactly the hunting-through-a-list step the pick replaces, and it
        // showed names for bodies you cannot see.
        if (s.output != 'new' && bodies.isNotEmpty)
          iosRow(
              label: t.lblTargetBody,
              value: bodies.contains(s.bodyName) ? s.bodyName : '—',
              valueColour: IosColors.label),
        if (s.output != 'new' && bodies.length > 1)
          iosStackedRow(
            child: IosButton(
              label: app.pickingBody
                  ? t.hintPickBodyTapCancel
                  : t.lblSelectBodyIn3d,
              style: app.pickingBody
                  ? IosButtonStyle.tinted
                  : IosButtonStyle.grey,
              height: 34,
              expand: true,
              onTap: () =>
                  app.pickingBody ? app.cancelPickBody() : app.beginPickBody(),
            ),
          ),
      ],
    );
  }

  // ---- Advanced Properties -------------------------------------------------

  Widget _advancedSection(AppState app, ExtrudeSession s, AppL10n t) =>
      iosSection(
        header: t.secAdvancedProperties,
        open: _advancedOpen,
        onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
        children: [
          // Taper is an extrude-only concept — a revolve has no draft.
          if (!s.isRevolve)
            iosValueRow(
                app: app,
                label: t.lblTaperA,
                controller: _taper,
                unit: 'deg',
                onChanged: (v) => app.setExtrude(exprTaper: v)),
          iosSwitchRow(
              label: 'iMate',
              value: s.iMate,
              onChanged: (v) => app.setExtrude(iMate: v)),
          // Not built: drawn off and inert, which is what it always was.
          iosSwitchRow(label: t.lblMatchShape, value: s.matchShape),
        ],
      );
}

/// The four direction glyphs, unchanged from M56. Recoloured for the active
/// scheme by [iosSvg] like every other inline icon in the app.
const _dirIcons = {
  ExtrudeDirection.defaultDir:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 14 V5 M9 5 l-2.6 2.8 M9 5 l2.6 2.8" stroke="#E8C63F" stroke-width="1.7" fill="none"/><path d="M4 14 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
  ExtrudeDirection.flipped:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 4 V13 M9 13 l-2.6-2.8 M9 13 l2.6-2.8" stroke="#E8C63F" stroke-width="1.7" fill="none"/><path d="M4 4 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
  ExtrudeDirection.symmetric:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 9 V3.5 M9 3.5 l-2.2 2.4 M9 3.5 l2.2 2.4 M9 9 V14.5 M9 14.5 l-2.2-2.4 M9 14.5 l2.2-2.4" stroke="#E8C63F" stroke-width="1.5" fill="none"/><path d="M4 9 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
  ExtrudeDirection.asymmetric:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M7 11 V3 M7 3 l-2.2 2.4 M7 3 l2.2 2.4" stroke="#E8C63F" stroke-width="1.5" fill="none"/><path d="M11 11 V15 M11 15 l-1.8-2 M11 15 l1.8-2" stroke="#E8C63F" stroke-width="1.3" fill="none"/><path d="M3 11 h12" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
};

/// Two overlapping squares merged (union), a dashed tool removed from a corner
/// (difference), the overlap lens filled (intersection), one square with a
/// plus (a brand-new body).
const _boolIcons = {
  'join':
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3" y="6.5" width="8" height="8" rx="1" fill="#E8C63F" fill-opacity=".22" stroke="#E8C63F" stroke-width="1.3"/><rect x="7" y="3.5" width="8" height="8" rx="1" fill="#E8C63F" fill-opacity=".22" stroke="#E8C63F" stroke-width="1.3"/></svg>',
  'cut':
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M3 6.5 h5 V3.5 h7 v11 H3 Z" fill="#9aa0a6" fill-opacity=".28" stroke="#9aa0a6" stroke-width="1.2"/><rect x="8" y="3.5" width="7" height="7" fill="none" stroke="#E8C63F" stroke-width="1.2" stroke-dasharray="2 1.4"/></svg>',
  'intersect':
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3" y="6.5" width="8" height="8" fill="none" stroke="#9aa0a6" stroke-width="1.1"/><rect x="7" y="3.5" width="8" height="8" fill="none" stroke="#9aa0a6" stroke-width="1.1"/><rect x="7" y="6.5" width="4" height="5" fill="#E8C63F" fill-opacity=".6" stroke="#E8C63F" stroke-width="1"/></svg>',
  'new':
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3.5" y="5.5" width="9" height="9" rx="1" fill="#E8C63F" fill-opacity=".2" stroke="#E8C63F" stroke-width="1.3"/><path d="M13 3 v3.4 M11.3 4.7 h3.4" stroke="#E8C63F" stroke-width="1.3"/></svg>',
};
