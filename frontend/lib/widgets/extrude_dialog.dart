// Prototype — Extrusion properties panel (M56), the modeless dialog from
// the reference screenshot: "Properties ✕ | +" header, "Extrusion > Sketch1"
// breadcrumb, collapsible Input Geometry / Behavior / Output / Advanced
// Properties sections, OK / Cancel / +. Draggable over the viewport like
// the Pattern and Fillet dialogs (M35/M36); the viewport does the profile
// picking, this panel shows and edits the session state.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../part_model.dart';
import '../theme.dart';
import 'properties_panel.dart';

class ExtrudeDialog extends StatefulWidget {
  final AppState app;
  const ExtrudeDialog({super.key, required this.app});
  @override
  State<ExtrudeDialog> createState() => _ExtrudeDialogState();
}

class _ExtrudeDialogState extends State<ExtrudeDialog> {
  /// M122 — null until first laid out, then parked on the RIGHT, vertically
  /// centred. The old default was (12, 12): the top-left corner, i.e. directly
  /// underneath the floating model browser card, so the dialog opened half
  /// hidden behind it. It stays draggable — this only changes where it starts.
  Offset? _pos;
  bool _inputOpen = true, _behaviorOpen = true, _outputOpen = true,
      _advancedOpen = true;
  late final TextEditingController _a, _b, _taper, _body;
  // M131b — sweep / coil fields
  late final TextEditingController _twist, _revs, _height, _pitch, _coilTaper;

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
    // Live bodies available as a Join target (empty for the base feature).
    final bodies = app.currentPart?.bodyNames ?? const <String>[];
    final sketchLabel = s.sketchName ?? 'Sketch1';
    // Park it against the right edge, centred, the first time we know how big
    // the viewport is.
    const w = 300.0, h = 560.0;
    final size = MediaQuery.sizeOf(context);
    final pos = _pos ??
        Offset(size.width - w - 18, ((size.height - h) / 2).clamp(12.0, 400.0));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
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
            // ---- header: Properties ✕ | ... + ----
            Container(
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
                  onTap: app.cancelExtrude,
                  child: Text('✕', style: ts(11.5, T.dim)),
                ),
                const SizedBox(width: 10),
                Text('+', style: ts(13, T.dim)),
                const Spacer(),
                Icon(Icons.search, size: 14, color: T.dim),
                const SizedBox(width: 8),
                Icon(Icons.menu, size: 14, color: T.dim),
              ]),
            ),
            // ---- breadcrumb: Extrusion > Sketch1 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                Text(
                    s.editing?.name ??
                        switch (s.kind) {
                          'revolve' => 'Revolution',
                          'sweep' => 'Sweep',
                          'loft' => 'Loft',
                          'coil' => 'Coil',
                          _ => 'Extrusion',
                        },
                    style: TextStyle(
                        fontSize: 12.5,
                        color: T.blue,
                        decoration: TextDecoration.underline,
                        decorationColor: T.blue)),
                Text('  ›  ', style: ts(12, T.dim)),
                Text(sketchLabel, style: ts(12.5, T.text)),
                const Spacer(),
                SvgPicture.string(
                    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 2 L13 5 v5 L8 13 L3 10 V5 Z" fill="#E59B63" stroke="#a86a35" stroke-width=".8"/><path d="M3 5 L8 8 L13 5 M8 8 v5" stroke="#a86a35" stroke-width=".8" fill="none"/></svg>',
                    width: 15,
                    height: 15),
                const SizedBox(width: 8),
                Icon(Icons.visibility_outlined, size: 14, color: T.dim),
              ]),
            ),
            panelSection('Input Geometry', _inputOpen,
                () => setState(() => _inputOpen = !_inputOpen), [
              panelRow('Profiles', panelPickField(
                  icon: Icons.touch_app_outlined,
                  label: s.profiles.isEmpty
                      ? 'Select a profile in the viewport'
                      : '${s.profiles.length} Profile'
                          '${s.profiles.length == 1 ? '' : 's'}',
                  active: true,
                  onClear:
                      s.profiles.isEmpty ? null : app.clearSessionProfiles)),
              panelRow('From', panelPickField(
                  icon: Icons.layers_outlined,
                  label: '1 Sketch Plane',
                  active: false)),
            ]),
            panelSection('Behavior', _behaviorOpen,
                () => setState(() => _behaviorOpen = !_behaviorOpen), [
              panelRow(
                  'Direction',
                  Row(children: [
                    for (final d in ExtrudeDirection.values) ...[
                      _dirButton(d),
                      const SizedBox(width: 4),
                    ],
                    const Spacer(),
                    Text('▾', style: ts(9, T.dim)),
                  ])),
              // M131b — Sweep drives the profile along a picked path.
              if (s.isSweep)
                panelRow(
                    'Path',
                    GestureDetector(
                      onTap: app.pickingSweepPath
                          ? app.cancelPickSweepPath
                          : app.beginPickSweepPath,
                      child: _pickBox(
                          app.pickingSweepPath
                              ? 'Tap a curve in 3D…'
                              : (s.path == null
                                  ? 'Select Curve or Edge'
                                  : 'Path selected'),
                          armed: app.pickingSweepPath,
                          filled: s.path != null)),
                  ),
              if (s.isSweep)
                panelRow(
                    'Orientation',
                    Row(children: [
                      _smallToggle('Follow Path', s.orientation == 0,
                          () => app.setExtrude(orientation: 0)),
                      const SizedBox(width: 3),
                      _smallToggle('Fixed', s.orientation == 1,
                          () => app.setExtrude(orientation: 1)),
                      const SizedBox(width: 3),
                      _smallToggle('Guide', s.orientation == 2,
                          () => app.setExtrude(orientation: 2)),
                    ])),
              if (s.isSweep) ...[
                panelRow(
                    'Taper',
                    panelValueField(_taper, 'deg',
                        (v) => app.setExtrude(exprTaper: v))),
                panelRow(
                    'Twist',
                    panelValueField(_twist, 'deg',
                        (v) => app.setExtrude(exprTwist: v))),
              ],
              // M131b — Loft collects sections instead of one profile.
              if (s.isLoft) ...[
                panelRow(
                    'Sections',
                    GestureDetector(
                      onTap: app.pickingLoftSections
                          ? app.cancelPickLoftSections
                          : app.beginPickLoftSections,
                      child: _pickBox(
                          s.loftSections.isEmpty
                              ? (app.pickingLoftSections
                                  ? 'Tap profiles in 3D…'
                                  : 'Click to add')
                              : '${s.loftSections.length} Sections'
                                  '${app.pickingLoftSections ? " — tap to finish" : ""}',
                          armed: app.pickingLoftSections,
                          filled: s.loftSections.isNotEmpty)),
                  ),
                panelRow(
                    'Transition',
                    Row(children: [
                      _smallToggle('Smooth', !s.loftRuled,
                          () => app.setExtrude(loftRuled: false)),
                      const SizedBox(width: 3),
                      _smallToggle('Ruled', s.loftRuled,
                          () => app.setExtrude(loftRuled: true)),
                    ])),
                _checkRow('Closed Loop', s.loftClosed, true,
                    (v) => app.setExtrude(loftClosed: v)),
                _checkRow('Merge Tangent Faces', s.loftMergeTangent, true,
                    (v) => app.setExtrude(loftMergeTangent: v)),
              ],
              // M131b — Coil: axis plus one of four equivalent methods.
              if (s.isCoil) ...[
                panelRow(
                    'Method',
                    _methodDropdown(app, s)),
                if (s.coilMethod != 2)
                  panelRow(
                      'Revolution',
                      panelValueField(_revs, 'ul',
                          (v) => app.setExtrude(exprRevolutions: v))),
                if (s.coilMethod == 0 || s.coilMethod == 2)
                  panelRow(
                      'Height',
                      panelValueField(_height, 'mm',
                          (v) => app.setExtrude(exprHeight: v))),
                if (s.coilMethod == 1 || s.coilMethod == 2)
                  panelRow(
                      'Pitch',
                      panelValueField(_pitch, 'mm',
                          (v) => app.setExtrude(exprPitch: v))),
                panelRow(
                    'Taper',
                    panelValueField(_coilTaper, 'deg',
                        (v) => app.setExtrude(exprCoilTaper: v))),
                panelRow(
                    'Rotation',
                    Row(children: [
                      _smallToggle('CCW', !s.coilClockwise,
                          () => app.setExtrude(coilClockwise: false)),
                      const SizedBox(width: 3),
                      _smallToggle('CW', s.coilClockwise,
                          () => app.setExtrude(coilClockwise: true)),
                    ])),
              ],
              // M137 — Revolve needs an axis before anything else can be
              // computed, so it sits above the angle.
              if (s.isRevolve || s.isCoil)
                panelRow(
                    'Axis',
                    GestureDetector(
                      onTap: app.pickingRevolveAxis
                          ? app.cancelPickRevolveAxis
                          : app.beginPickRevolveAxis,
                      child: Container(
                        height: 26,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF212429),
                          border: Border.all(
                              color: app.pickingRevolveAxis
                                  ? T.blue
                                  : (s.axisPicked
                                      ? const Color(0xFF3A3F45)
                                      : const Color(0xFFA05A2C))),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                            app.pickingRevolveAxis
                                ? 'Tap a line or origin axis…'
                                : (s.axisPicked
                                    ? s.axisLabel
                                    : 'Select Axis'),
                            style: ts(
                                12, s.axisPicked ? T.text : T.dim)),
                      ),
                    )),
              // Inventor's Full: a complete turn, which overrides the angle.
              if (s.isRevolve)
                panelRow(
                    'Full',
                    GestureDetector(
                      onTap: () => app.setExtrude(full: !s.full),
                      child: Container(
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: s.full
                              ? const Color(0xFF2E4A6B)
                              : const Color(0xFF2A2E33),
                          border: Border.all(
                              color:
                                  s.full ? T.blue : const Color(0xFF3A3F45)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text('360°', style: ts(12, T.text)),
                      ),
                    )),
              // M132 — Inventor's Extents sit right of the value, as in the
              // reference panel. The field itself IS the Distance option, so
              // it dims while one of the three is active, and tapping the
              // active one returns to Distance.
              panelRow(
                  s.isRevolve ? 'Angle A' : 'Distance A',
                  Row(children: [
                    Expanded(
                      child: panelDimWhen(
                        s.extent != FeatureExtent.distance ||
                            (s.isRevolve && s.full),
                        panelValueField(_a, s.isRevolve ? 'deg' : 'mm',
                            (v) => app.setExtrude(exprA: v)),
                      ),
                    ),
                    // M143 — Extents now work for a revolve too, via
                    // occt_revolve_hits. "To <face>" is still extrude-only:
                    // terminating a rotation on a picked face needs the angle
                    // at which the sweep meets THAT face, not the first
                    // material it meets, so it stays hidden rather than
                    // quietly behaving like To Next.
                    // M144 — all three work for a revolve too now:
                    // occt_revolve_hits_face answers the picked-face question
                    // that occt_revolve_hits could not.
                    const SizedBox(width: 6),
                    _extentButton(FeatureExtent.toNext),
                    const SizedBox(width: 3),
                    _extentButton(FeatureExtent.toFace),
                    const SizedBox(width: 3),
                    _extentButton(FeatureExtent.throughAll),
                  ])),
              if (s.direction == ExtrudeDirection.asymmetric &&
                  s.extent == FeatureExtent.distance &&
                  !(s.isRevolve && s.full))
                panelRow(
                    s.isRevolve ? 'Angle B' : 'Distance B',
                    panelValueField(_b, s.isRevolve ? 'deg' : 'mm',
                        (v) => app.setExtrude(exprB: v))),
              if (s.extent == FeatureExtent.toFace)
                panelRow(
                    'Terminate on',
                    GestureDetector(
                      onTap: app.pickingExtentFace
                          ? app.cancelPickExtentFace
                          : app.beginPickExtentFace,
                      child: Container(
                        height: 26,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF212429),
                          border: Border.all(
                              color: app.pickingExtentFace
                                  ? T.blue
                                  : const Color(0xFF3A3F45)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                            app.pickingExtentFace
                                ? 'Tap a face in 3D…'
                                : (s.extentFace == null
                                    ? 'Select face'
                                    : 'Face selected — tap to change'),
                            style: ts(
                                12,
                                s.extentFace == null && !app.pickingExtentFace
                                    ? T.dim
                                    : T.text)),
                      ),
                    )),
            ]),
            panelSection('Output', _outputOpen,
                () => setState(() => _outputOpen = !_outputOpen), [
              // Inventor's Output boolean, applied against the existing body:
              // Join (union), Cut (subtract), Intersect (overlap), New Solid
              // (separate body). Cut/Intersect need something to act on, so
              // they are dimmed for the base feature.
              panelRow(
                  'Boolean',
                  Row(children: [
                    _boolButton('join', 'Join'),
                    const SizedBox(width: 6),
                    _boolButton('cut', 'Cut',
                        enabled: app.extrudeHasBooleanTarget),
                    const SizedBox(width: 6),
                    _boolButton('intersect', 'Intersect',
                        enabled: app.extrudeHasBooleanTarget),
                    const SizedBox(width: 6),
                    _boolButton('new', 'New Solid'),
                    const Spacer(),
                  ])),
              // M99 — no dropdown. The target body is PICKED, not chosen
              // from a list: tap it in 3D or in the model browser (the button
              // below arms that). A dropdown of body names is exactly the
              // hunting-through-a-list step the pick replaces, and it showed
              // names for bodies you cannot see.
              if (s.output != 'new' && bodies.isNotEmpty)
                panelRow(
                    'Target Body',
                    Text(bodies.contains(s.bodyName) ? s.bodyName : '—',
                        style: ts(12.5, T.text))),
              if (s.output != 'new' && bodies.length > 1)
                panelRow(
                    '',
                    GestureDetector(
                      onTap: () => app.pickingBody
                          ? app.cancelPickBody()
                          : app.beginPickBody(),
                      child: Container(
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: app.pickingBody
                              ? const Color(0xFF2F6FB0)
                              : const Color(0xFF212429),
                          border: Border.all(
                              color: app.pickingBody
                                  ? T.blue
                                  : const Color(0xFF3A3F45)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                            app.pickingBody
                                ? 'Pick a body… (tap to cancel)'
                                : 'Select body in 3D / browser',
                            style: ts(11.5, T.text)),
                      ),
                    )),
            ]),
            panelSection('Advanced Properties', _advancedOpen,
                () => setState(() => _advancedOpen = !_advancedOpen), [
              // Taper is an extrude-only concept — a revolve has no draft.
              if (!s.isRevolve)
                panelRow(
                    'Taper A',
                    panelValueField(
                        _taper, 'deg', (v) => app.setExtrude(exprTaper: v),
                        trailingIcon: Icons.edit_outlined)),
              _checkRow('iMate', s.iMate, true,
                  (v) => app.setExtrude(iMate: v)),
              _checkRow('Match Shape', s.matchShape, false, (_) {}),
            ]),
            if (s.previewError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      size: 13, color: Color(0xFFE05A56)),
                  const SizedBox(width: 5),
                  Expanded(
                      child: Text(s.previewError!,
                          style: ts(10.5, const Color(0xFFE0928F)))),
                ]),
              ),
            // ---- OK / Cancel / + ----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(children: [
                _btn('OK', primary: true,
                    onTap: () => app.applyExtrude(keepOpen: false)),
                const SizedBox(width: 8),
                _btn('Cancel', onTap: app.cancelExtrude),
                const Spacer(),
                Tooltip(
                  message: 'Apply and start another',
                  child: GestureDetector(
                    onTap: () => app.applyExtrude(keepOpen: true),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: const Color(0xFF3FA43C)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Center(
                          child: Text('+',
                              style: TextStyle(
                                  fontSize: 16,
                                  height: 1,
                                  color: Color(0xFF5CBF4A)))),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Inventor Output-boolean toggle: a compact icon button (like [_dirButton])
  /// with a tooltip. [enabled] false dims it and ignores taps — used for
  /// Cut/Intersect when there is no body to act on yet.
  /// The bordered "click to pick something in 3D" field the panels use for
  /// every geometry reference (path, sections, axis, termination face).
  Widget _pickBox(String label, {bool armed = false, bool filled = false}) =>
      Container(
        height: 26,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF212429),
          border: Border.all(
              color: armed
                  ? T.blue
                  : (filled
                      ? const Color(0xFF3A3F45)
                      : const Color(0xFFA05A2C))),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: ts(12, filled || armed ? T.text : T.dim)),
      );

  /// A small segmented toggle, for the option groups Inventor draws as a row
  /// of icon buttons (Orientation, Transition, Rotation).
  Widget _smallToggle(String label, bool active, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  active ? const Color(0xFF2E4A6B) : const Color(0xFF2A2E33),
              border: Border.all(
                  color: active ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label,
                style: ts(11, T.text), overflow: TextOverflow.ellipsis),
          ),
        ),
      );

  /// Inventor's four Coil methods. They all describe the same helix, so which
  /// two fields are shown below follows from this.
  Widget _methodDropdown(AppState app, ExtrudeSession s) {
    const names = [
      'Revolution and Height',
      'Pitch and Revolution',
      'Pitch and Height',
      'Spiral',
    ];
    return GestureDetector(
      onTap: () => app.setExtrude(coilMethod: (s.coilMethod + 1) % 4),
      child: Container(
        height: 26,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF212429),
          border: Border.all(color: const Color(0xFF3A3F45)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          Expanded(
              child: Text(names[s.coilMethod.clamp(0, 3)],
                  style: ts(12, T.text), overflow: TextOverflow.ellipsis)),
          Icon(Icons.arrow_drop_down, size: 16, color: T.dim),
        ]),
      ),
    );
  }

  /// One Extents toggle. Inventor greys To Next / To / Through All out for a
  /// base feature, because with nothing built yet there is no face to
  /// terminate against — [AppState.extrudeHasBooleanTarget] is exactly that
  /// condition, and it is already what dims Cut and Intersect below.
  Widget _extentButton(FeatureExtent e) {
    final app = widget.app;
    final active = sess.extent == e;
    final enabled = app.extrudeHasBooleanTarget;
    const icons = {
      // arrow stopping at the FIRST plate it meets
      FeatureExtent.toNext:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M3 3.5 v11" stroke="#9aa0a6" stroke-width="1.2"/><path d="M11.5 2.5 v13" stroke="#9aa0a6" stroke-width="1.4"/><path d="M15.5 2.5 v13" stroke="#9aa0a6" stroke-width="1.4" stroke-opacity=".45"/><path d="M4.5 9 h5.4" stroke="#E8C63F" stroke-width="1.4"/><path d="M9.2 6.9 L11.4 9 L9.2 11.1 Z" fill="#E8C63F"/></svg>',
      // arrow stopping at a HIGHLIGHTED plate (the picked face)
      FeatureExtent.toFace:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M3 3.5 v11" stroke="#9aa0a6" stroke-width="1.2"/><path d="M11.5 2.5 v13" stroke="#9aa0a6" stroke-width="1.4" stroke-opacity=".45"/><path d="M15.5 2.5 v13" stroke="#E8C63F" stroke-width="1.8"/><path d="M4.5 9 h9.4" stroke="#E8C63F" stroke-width="1.4"/><path d="M13.2 6.9 L15.4 9 L13.2 11.1 Z" fill="#E8C63F"/></svg>',
      // arrow passing THROUGH everything
      FeatureExtent.throughAll:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M3 3.5 v11" stroke="#9aa0a6" stroke-width="1.2"/><path d="M8.5 2.5 v13" stroke="#9aa0a6" stroke-width="1.4" stroke-opacity=".45"/><path d="M12.5 2.5 v13" stroke="#9aa0a6" stroke-width="1.4" stroke-opacity=".45"/><path d="M4.5 9 h10.4" stroke="#E8C63F" stroke-width="1.4"/><path d="M14 6.6 L17 9 L14 11.4 Z" fill="#E8C63F"/></svg>',
      FeatureExtent.distance: '',
    };
    return Tooltip(
      message: enabled
          ? extentLabel(e)
          : '${extentLabel(e)} (needs an existing body)',
      child: GestureDetector(
        onTap: enabled
            ? () {
                // tapping the active one goes back to a typed Distance
                final next = active ? FeatureExtent.distance : e;
                widget.app.setExtrude(extent: next);
                // Inventor asks for the face the moment you choose "To";
                // leaving it disarms, so switching away cannot strand the
                // viewport in a pick mode with no dialog row to cancel it.
                if (next == FeatureExtent.toFace) {
                  widget.app.beginPickExtentFace();
                } else {
                  widget.app.cancelPickExtentFace();
                }
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2E4A6B) : const Color(0xFF2A2E33),
              border: Border.all(
                  color: active ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            padding: const EdgeInsets.all(4),
            child: SvgPicture.string(icons[e] ?? ''),
          ),
        ),
      ),
    );
  }

  Widget _boolButton(String key, String label, {bool enabled = true}) {
    final active = sess.output == key;
    const icons = {
      // two overlapping squares merged = union
      'join':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3" y="6.5" width="8" height="8" rx="1" fill="#E8C63F" fill-opacity=".22" stroke="#E8C63F" stroke-width="1.3"/><rect x="7" y="3.5" width="8" height="8" rx="1" fill="#E8C63F" fill-opacity=".22" stroke="#E8C63F" stroke-width="1.3"/></svg>',
      // base square, dashed tool being removed from a corner = difference
      'cut':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M3 6.5 h5 V3.5 h7 v11 H3 Z" fill="#9aa0a6" fill-opacity=".28" stroke="#9aa0a6" stroke-width="1.2"/><rect x="8" y="3.5" width="7" height="7" fill="none" stroke="#E8C63F" stroke-width="1.2" stroke-dasharray="2 1.4"/></svg>',
      // two outlined squares, only the overlap lens filled = intersection
      'intersect':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3" y="6.5" width="8" height="8" fill="none" stroke="#9aa0a6" stroke-width="1.1"/><rect x="7" y="3.5" width="8" height="8" fill="none" stroke="#9aa0a6" stroke-width="1.1"/><rect x="7" y="6.5" width="4" height="5" fill="#E8C63F" fill-opacity=".6" stroke="#E8C63F" stroke-width="1"/></svg>',
      // single square with a small plus = a brand-new body
      'new':
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><rect x="3.5" y="5.5" width="9" height="9" rx="1" fill="#E8C63F" fill-opacity=".2" stroke="#E8C63F" stroke-width="1.3"/><path d="M13 3 v3.4 M11.3 4.7 h3.4" stroke="#E8C63F" stroke-width="1.3"/></svg>',
    };
    return Tooltip(
      message: enabled ? label : '$label (needs an existing body)',
      child: GestureDetector(
        onTap: enabled
            ? () {
                widget.app.setExtrude(output: key);
                // M96 — the name field is built ONCE in initState, so when
                // setExtrude picks a fresh body name for New Solid ("Solid2",
                // "Solid3") the controller kept showing the old text and the
                // user had to retype it. Pull the controller back onto the
                // session whenever the output mode changes it.
                if (_body.text != sess.bodyName) {
                  _body.text = sess.bodyName;
                  _body.selection =
                      TextSelection.collapsed(offset: _body.text.length);
                }
                setState(() {});
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 28,
            height: 26,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2F6FB0) : const Color(0xFF212429),
              border: Border.all(
                  color: active ? T.blue : const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
                child: SvgPicture.string(icons[key]!, width: 16, height: 16)),
          ),
        ),
      ),
    );
  }

  Widget _dirButton(ExtrudeDirection d) {
    final active = sess.direction == d;
    final icons = {
      ExtrudeDirection.defaultDir: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 14 V5 M9 5 l-2.6 2.8 M9 5 l2.6 2.8" stroke="#E8C63F" stroke-width="1.7" fill="none"/><path d="M4 14 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
      ExtrudeDirection.flipped: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 4 V13 M9 13 l-2.6-2.8 M9 13 l2.6-2.8" stroke="#E8C63F" stroke-width="1.7" fill="none"/><path d="M4 4 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
      ExtrudeDirection.symmetric: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M9 9 V3.5 M9 3.5 l-2.2 2.4 M9 3.5 l2.2 2.4 M9 9 V14.5 M9 14.5 l-2.2-2.4 M9 14.5 l2.2-2.4" stroke="#E8C63F" stroke-width="1.5" fill="none"/><path d="M4 9 h10" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
      ExtrudeDirection.asymmetric: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M7 11 V3 M7 3 l-2.2 2.4 M7 3 l2.2 2.4" stroke="#E8C63F" stroke-width="1.5" fill="none"/><path d="M11 11 V15 M11 15 l-1.8-2 M11 15 l1.8-2" stroke="#E8C63F" stroke-width="1.3" fill="none"/><path d="M3 11 h12" stroke="#9aa0a6" stroke-width="1.2"/></svg>',
    };
    return Tooltip(
      message: switch (d) {
        ExtrudeDirection.defaultDir => 'Default',
        ExtrudeDirection.flipped => 'Flipped',
        ExtrudeDirection.symmetric => 'Symmetric',
        ExtrudeDirection.asymmetric => 'Asymmetric',
      },
      child: GestureDetector(
        onTap: () {
          widget.app.setExtrude(direction: d);
          setState(() {});
        },
        child: Container(
          width: 28,
          height: 26,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2F6FB0) : const Color(0xFF212429),
            border: Border.all(
                color: active ? T.blue : const Color(0xFF3A3F45)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
              child:
                  SvgPicture.string(icons[d]!, width: 16, height: 16)),
        ),
      ),
    );
  }

  Widget _checkRow(
      String label, bool value, bool enabled, ValueChanged<bool> onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onTap(!value) : null,
        child: Row(children: [
          Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: value
                  ? (enabled ? T.blue : const Color(0xFF2B3946))
                  : const Color(0xFF212429),
              border: Border.all(color: const Color(0xFF3A3F45)),
              borderRadius: BorderRadius.circular(2),
            ),
            child: value
                ? Icon(Icons.check,
                    size: 12,
                    color: enabled ? Colors.white : const Color(0xFF6A6F77))
                : null,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: ts(12, enabled ? T.text : const Color(0xFF6A6F77))),
        ]),
      ),
    );
  }

  Widget _btn(String label, {bool primary = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? T.blue : Colors.transparent,
          border:
              Border.all(color: primary ? T.blue : const Color(0xFF3A3F45)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: ts(12.5, primary ? Colors.white : T.text,
                w: primary ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}
