// Prototype — the Pattern dialogs (M35): Rectangular / Circular / Mirror,
// 1:1 with Inventor's sketch dialogs (see HANDOFF, mock screenshots):
//
//   Rectangular: Geometry | Direction 1 + Direction 2 (select/flip, count,
//                spacing) | Extents (boundary fill — future work, greyed
//                exactly like Inventor greys it before a boundary is picked)
//                | ? OK Cancel >>  and the expanded Suppress/Associative/
//                Fitted row behind ">>".
//   Circular:    Geometry + Axis (+ flip) | count + angle | Extents | footer.
//   Mirror:      Select + Mirror Line + Self Symmetric | Apply Done Cancel.
//
// The dialog is MODELESS: it floats over the viewport and the user keeps
// tapping geometry while it is open. Which input a tap feeds is the ACTIVE
// selector (blue outline) — AppState._patternClick routes it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../ffi/qcad_engine.dart';
import '../scrub.dart';
import '../svg_icons.dart';
import '../theme.dart';
import 'scrub_field.dart';
import '../l10n/l.dart';

// M236 — getters, not finals: a top-level `final` is initialised lazily on
// first use and would freeze whichever palette was active at that moment.
Color get _fieldBg => T.fly;
Color get _fieldBorder => T.panelSep;
Color get _disabledBg => T.disabledFill;
Color get _disabledBorder => T.disabled;
Color get _disabledText => T.disabled;

class PatternDialog extends StatefulWidget {
  final AppState app;
  const PatternDialog({super.key, required this.app});
  @override
  State<PatternDialog> createState() => _PatternDialogState();
}

class _PatternDialogState extends State<PatternDialog> {
  late final TextEditingController _c1, _s1, _c2, _s2, _cc, _ac;

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
    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: T.panel,
        border: Border.all(color: T.sep),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: T.scrim, blurRadius: 24, offset: Offset(0, 6)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _header(app),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: switch (ps.kind) {
            Tool.patRect => _rectBody(app),
            Tool.patCirc => _circBody(app),
            _ => _mirrorBody(app),
          },
        ),
      ]),
    );
  }

  Widget _header(AppState app) {
    final title = switch (ps.kind) {
      Tool.patRect => L.of(context).patRectangular,
      Tool.patCirc => L.of(context).patCircular,
      _ => L.of(context).patMirror,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: T.fly,
        border: Border(bottom: BorderSide(color: T.panelSep)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: Row(children: [
        Expanded(
            child: Text(title, style: ts(13.5, T.text, w: FontWeight.w600))),
        _IconTap(
          tooltip: L.of(context).cancel,
          onTap: app.cancelTool,
          child: Icon(Icons.close, size: 17, color: T.dim),
        ),
      ]),
    );
  }

  // ---- Rectangular --------------------------------------------------------
  Widget _rectBody(AppState app) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _geometryRow(app),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _directionBox(app, 1)),
        const SizedBox(width: 8),
        Expanded(child: _directionBox(app, 2)),
      ]),
      const SizedBox(height: 10),
      _extentsBox(),
      const SizedBox(height: 10),
      _footer(app),
      if (ps.expanded) _advancedRow(app),
    ]);
  }

  Widget _directionBox(AppState app, int which) {
    final field = which == 1 ? PatField.dir1 : PatField.dir2;
    final ent = which == 1 ? ps.dir1Ent : ps.dir2Ent;
    final flip = which == 1 ? ps.flip1 : ps.flip2;
    // Direction 2 stays greyed until Direction 1 is picked — Inventor's flow.
    final enabled = which == 1 || ps.dir1Ent != null;
    final cCtrl = which == 1 ? _c1 : _c2;
    final sCtrl = which == 1 ? _s1 : _s2;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _fieldBg,
        border: Border.all(color: _fieldBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(L.of(context).lblDirectionN('$which'),
            style: ts(10.5, enabled ? T.dim : _disabledText)),
        const SizedBox(height: 6),
        Row(children: [
          _PickBtn(
            icon: PD['sel']!,
            active: enabled && ps.active == field,
            done: ent != null,
            enabled: enabled,
            tooltip: L.of(context).tipSelectDirectionLine,
            onTap: () {
              ps.active = field;
              app.patNotify();
            },
          ),
          const SizedBox(width: 5),
          _SquareBtn(
            icon: PD['flip']!,
            enabled: enabled && ent != null,
            tooltip: L.of(context).tipFlipDirection,
            onTap: () {
              if (which == 1) {
                ps.flip1 = !flip;
              } else {
                ps.flip2 = !flip;
              }
              app.patNotify();
            },
          ),
          const SizedBox(width: 5),
          _SquareBtn(
            icon: IC['patrect']!,
            enabled: false, // path mode — Inventor's 3rd toggle, future work
            tooltip: L.of(context).tipPatternAlongPath,
            onTap: () {},
          ),
        ]),
        const SizedBox(height: 8),
        _valueField(
          icon: which == 1 ? PD['countH']! : PD['countV']!,
          ctrl: cCtrl,
          enabled: enabled,
          integer: true,
          min: 1,
          max: 64,
          onValue: (v) {
            final n = v.toInt().clamp(1, 64);
            if (which == 1) {
              ps.count1 = n;
            } else {
              ps.count2 = n;
            }
            app.patNotify();
          },
        ),
        const SizedBox(height: 6),
        _valueField(
          icon: PD['spacing']!,
          ctrl: sCtrl,
          enabled: enabled,
          suffix: 'mm',
          onValue: (v) {
            if (which == 1) {
              ps.spacing1 = v;
            } else {
              ps.spacing2 = v;
            }
            app.patNotify();
          },
        ),
      ]),
    );
  }

  // ---- Circular -----------------------------------------------------------
  Widget _circBody(AppState app) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _geometryRow(app)),
        const SizedBox(width: 6),
        _PickBtn(
          icon: PD['selAxis']!,
          active: ps.active == PatField.axis,
          done: ps.axisPt != null,
          tooltip: L.of(context).tipSelectRotationAxisPoint,
          onTap: () {
            ps.active = PatField.axis;
            app.patNotify();
          },
        ),
        const SizedBox(width: 5),
        Text(L.of(context).lblAxis, style: ts(12.5, T.text)),
        const Spacer(),
        _SquareBtn(
          icon: PD['flip']!,
          enabled: ps.axisPt != null,
          tooltip: L.of(context).tipFlipRotation,
          onTap: () {
            ps.flipC = !ps.flipC;
            app.patNotify();
          },
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _valueField(
            icon: PD['countC']!,
            ctrl: _cc,
            integer: true,
            min: 2,
            max: 128,
            onValue: (v) {
              ps.countC = v.toInt().clamp(2, 128);
              app.patNotify();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _valueField(
            icon: PD['angle']!,
            ctrl: _ac,
            suffix: 'deg',
            min: -360,
            max: 360,
            onValue: (v) {
              ps.angleC = v.clamp(-360.0, 360.0);
              app.patNotify();
            },
          ),
        ),
      ]),
      const SizedBox(height: 10),
      _extentsBox(),
      const SizedBox(height: 10),
      _footer(app),
      if (ps.expanded) _advancedRow(app),
    ]);
  }

  // ---- Mirror -------------------------------------------------------------
  Widget _mirrorBody(AppState app) {
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _PickBtn(
          icon: PD['sel']!,
          active: ps.active == PatField.geometry,
          done: ps.geo.isNotEmpty,
          tooltip: L.of(context).tipSelectGeometryToMirror,
          onTap: () {
            ps.active = PatField.geometry;
            app.patNotify();
          },
        ),
        const SizedBox(width: 7),
        Text(L.of(context).select, style: ts(12.5, T.text)),
        const Spacer(),
        Text(
            ps.geo.isEmpty ? 'nothing selected' : '${ps.geo.length} selected',
            style: ts(11.5, T.dim)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _PickBtn(
          icon: PD['mirLine']!,
          active: ps.active == PatField.mirrorLine,
          done: ps.mirrorEnt != null,
          tooltip: L.of(context).tipSelectMirrorLine,
          onTap: () {
            ps.active = PatField.mirrorLine;
            app.patNotify();
          },
        ),
        const SizedBox(width: 7),
        Text(L.of(context).lblMirrorLine, style: ts(12.5, T.text)),
        const Spacer(),
        Text(ps.mirrorEnt == null ? '—' : L.of(context).lblLineN('${ps.mirrorEnt}'),
            style: ts(11.5, T.dim)),
      ]),
      const SizedBox(height: 8),
      _CheckRow(
        label: L.of(context).btnSelfSymmetric,
        hint: selfSymOk ? null : L.of(context).lblSingleOpenSplineOnly,
        value: ps.selfSym,
        enabled: selfSymOk,
        onChanged: (v) {
          ps.selfSym = v;
          app.patNotify();
        },
      ),
      const SizedBox(height: 10),
      Row(children: [
        _HelpBadge(),
        const Spacer(),
        _DlgBtn(
            label: L.of(context).apply,
            outline: true,
            onTap: () => app.commitPattern(keepOpen: true)),
        const SizedBox(width: 8),
        _DlgBtn(label: L.of(context).done, primary: true, onTap: () => app.commitPattern()),
        const SizedBox(width: 8),
        _DlgBtn(label: L.of(context).cancel, onTap: app.cancelTool),
      ]),
    ]);
  }

  // ---- shared pieces ------------------------------------------------------
  Widget _geometryRow(AppState app) {
    return Row(children: [
      _PickBtn(
        icon: PD['sel']!,
        active: ps.active == PatField.geometry,
        done: ps.geo.isNotEmpty,
        tooltip: L.of(context).tipSelectGeometryToPattern,
        onTap: () {
          ps.active = PatField.geometry;
          app.patNotify();
        },
      ),
      const SizedBox(width: 7),
      Text(L.of(context).lblGeometry, style: ts(12.5, T.text)),
      const SizedBox(width: 8),
      Text(ps.geo.isEmpty ? '' : '${ps.geo.length} selected',
          style: ts(11.5, T.dim)),
    ]);
  }

  /// The Extents/Boundary block — rendered exactly like Inventor renders it
  /// before a boundary exists: greyed. Boundary fill is future work (HANDOFF).
  Widget _extentsBox() {
    Widget dis(String icon) => Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            color: _disabledBg,
            border: Border.all(color: _disabledBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Opacity(opacity: .35, child: Center(child: svgi(icon, 14))),
        );
    return Tooltip(
      message: L.of(context).msgBoundaryFillNotYet,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: _disabledBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L.of(context).lblExtents, style: ts(10.5, _disabledText)),
          const SizedBox(height: 6),
          Row(children: [
            dis(PD['sel']!),
            Text(L.of(context).lblBoundary, style: ts(12, _disabledText)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            dis(IC['patrect']!),
            dis(PD['countC']!),
            dis(PD['sel']!),
            Text(L.of(context).lblIncludeGeometry, style: ts(12, _disabledText)),
          ]),
        ]),
      ),
    );
  }

  Widget _footer(AppState app) {
    return Row(children: [
      _HelpBadge(),
      const Spacer(),
      _DlgBtn(label: L.of(context).ok, primary: true, onTap: () => app.commitPattern()),
      const SizedBox(width: 8),
      _DlgBtn(label: L.of(context).cancel, onTap: app.cancelTool),
      const SizedBox(width: 8),
      _DlgBtn(
        label: ps.expanded ? '\u00ab' : '\u00bb',
        onTap: () {
          ps.expanded = !ps.expanded;
          app.patNotify();
        },
      ),
    ]);
  }

  /// The ">>" row: Suppress (future work) + Associative + Fitted.
  Widget _advancedRow(AppState app) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Tooltip(
          message: L.of(context).msgSuppressNotYet,
          child: Opacity(
            opacity: .4,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              svgi(PD['sel']!, 14),
              const SizedBox(width: 4),
              Text(L.of(context).lblSuppress, style: ts(12, T.dim)),
            ]),
          ),
        ),
        const Spacer(),
        _CheckRow(
          label: L.of(context).btnAssociative,
          value: ps.associative,
          onChanged: (v) {
            ps.associative = v;
            app.patNotify();
          },
        ),
        const SizedBox(width: 10),
        _CheckRow(
          label: L.of(context).btnFitted,
          value: ps.fitted,
          onChanged: (v) {
            ps.fitted = v;
            app.patNotify();
          },
        ),
      ]),
    );
  }

  Widget _valueField({
    required String icon,
    required TextEditingController ctrl,
    required void Function(double) onValue,
    bool enabled = true,
    bool integer = false,
    String? suffix,
    double? min,
    double? max,
  }) {
    final row = Row(children: [
      svgi(icon, 15),
      const SizedBox(width: 6),
      Expanded(
        child: SizedBox(
          height: 28,
          child: TextField(
            controller: ctrl,
            enabled: enabled,
            style: ts(12.5, enabled ? T.text : _disabledText),
            keyboardType: kValueKeyboard, // M206: the app's own pad
            stylusHandwritingEnabled: kValueHandwriting, // M179
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(integer ? r'[0-9]' : r'[0-9.,\-]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              suffixText: suffix,
              suffixStyle: ts(11, T.dim),
              filled: true,
              fillColor: enabled ? _fieldBg : _disabledBg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide(color: _fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide(color: T.accent, width: 1.4),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: BorderSide(color: _disabledBorder),
              ),
            ),
            onChanged: (t) {
              final v = double.tryParse(t.replaceAll(',', '.'));
              if (v != null) onValue(v);
            },
          ),
        ),
      ),
    ]);
    // M180 — draggable, like every other number in the app. A disabled field
    // is not: it is greyed because the pattern does not use it, and a value
    // that moves under the finger while the model ignores it is worse than
    // one that does not move.
    if (!enabled) return row;
    return ScrubField(
      app: widget.app,
      controller: ctrl,
      // The unit here is DECORATION (suffixText), so the text is a bare
      // number and must stay one — the onChanged above parses it raw.
      kind: integer
          ? ScrubKind.count
          : scrubKindForUnit(suffix ?? ''),
      min: min,
      max: max,
      onCommit: (t) {
        final v = double.tryParse(t.replaceAll(',', '.'));
        if (v != null) onValue(v);
      },
      child: row,
    );
  }
}

Widget svgi(String s, double size) =>
    SvgPicture.string(s, width: size, height: size);

/// A selector button: blue outline while ARMED (the next viewport tap feeds
/// it), a subtle blue underline once its pick exists — Inventor's language.
class _PickBtn extends StatelessWidget {
  final String icon;
  final bool active, done, enabled;
  final String tooltip;
  final VoidCallback onTap;
  const _PickBtn(
      {required this.icon, required this.active, required this.done,
      this.enabled = true, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled ? _fieldBg : _disabledBg,
            border: Border.all(
                color: active
                    ? T.accent
                    : enabled
                        ? _fieldBorder
                        : _disabledBorder,
                width: active ? 1.5 : 1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Opacity(opacity: enabled ? 1 : .35, child: svgi(icon, 15)),
            if (done)
              Container(
                  margin: const EdgeInsets.only(top: 1),
                  width: 14,
                  height: 2,
                  color: T.accent),
          ]),
        ),
      ),
    );
  }
}

class _SquareBtn extends StatelessWidget {
  final String icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;
  const _SquareBtn(
      {required this.icon, required this.enabled, required this.tooltip,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled ? _fieldBg : _disabledBg,
            border:
                Border.all(color: enabled ? _fieldBorder : _disabledBorder),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
              child:
                  Opacity(opacity: enabled ? 1 : .35, child: svgi(icon, 15))),
        ),
      ),
    );
  }
}

class _DlgBtn extends StatelessWidget {
  final String label;
  final bool primary, outline;
  final VoidCallback onTap;
  const _DlgBtn(
      {required this.label, this.primary = false, this.outline = false,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? T.accent : Colors.transparent,
          border: Border.all(
              color: primary
                  ? T.accent
                  : outline
                      ? T.accent
                      : _fieldBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: ts(12.5, primary ? T.onAccent : outline ? T.accent : T.text,
                w: primary ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value, enabled;
  final void Function(bool) onChanged;
  const _CheckRow(
      {required this.label, this.hint, required this.value,
      this.enabled = true, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: value && enabled ? T.accent : _fieldBg,
            border: Border.all(
                color: enabled ? _fieldBorder : _disabledBorder),
            borderRadius: BorderRadius.circular(2),
          ),
          child: value && enabled
              ? Icon(Icons.check, size: 12, color: T.onAccent)
              : null,
        ),
        const SizedBox(width: 5),
        Text(label, style: ts(12, enabled ? T.text : _disabledText)),
        if (hint != null) ...[
          const SizedBox(width: 4),
          Text(hint!, style: ts(10.5, _disabledText)),
        ],
      ]),
    );
  }
}

class _HelpBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: L.of(context).msgPickWhileSelectorBlue,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          border: Border.all(color: _fieldBorder),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(child: Text('?', style: ts(12, T.dim))),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  const _IconTap(
      {required this.tooltip, required this.onTap, required this.child});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(4), child: child)),
    );
  }
}

/// The modeless 2D Fillet / 2D Chamfer window (M36) — Inventor's tiny value
/// dialogs: it floats while the tool is armed, every two picks make a
/// corner, and the values are editable between corners. Chamfer offers
/// Inventor's three modes (equal distance / two distances / distance +
/// angle) as the icon toggles on the left.
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
    final isFillet = fs.kind == Tool.fillet;
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: T.panel,
        border: Border.all(color: T.sep),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
              color: T.scrim, blurRadius: 24, offset: Offset(0, 6)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: T.fly,
            border: Border(bottom: BorderSide(color: T.panelSep)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
          ),
          // M207 — no ✕ ("on the radius input field the cross at top left
          // isn't needed. remove it"). It was a third way to say Cancel, next
          // to Esc and the quick-tool bar's own Cancel button, on a window
          // whose whole job is to hold one number.
          child: Row(children: [
            Expanded(
                child: Text(isFillet ? '2D Fillet' : '2D Chamfer',
                    style: ts(13.5, T.text, w: FontWeight.w600))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: isFillet ? _filletBody(app) : _chamferBody(app),
        ),
      ]),
    );
  }

  Widget _filletBody(AppState app) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _num(PD['spacing']!, _r, min: 0.1, (v) {
        fs.radius = v;
        app.filletNotify();
      }, suffix: 'mm'),
      const SizedBox(height: 8),
      Text(L.of(context).msgFilletPickTwo, style: ts(10.5, T.dim)),
    ]);
  }

  Widget _chamferBody(AppState app) {
    Widget modeBtn(int m, String icon, String tip) => Padding(
          padding: const EdgeInsets.only(right: 5),
          child: _PickBtn(
            icon: icon,
            active: fs.mode == m,
            done: false,
            tooltip: tip,
            onTap: () {
              fs.mode = m;
              app.filletNotify();
            },
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        modeBtn(0, PD['chamEq']!, L.of(context).lblEqualDistance),
        modeBtn(1, PD['cham2d']!, L.of(context).lblTwoDistances),
        modeBtn(2, PD['chamAng']!, L.of(context).lblDistanceAndAngle),
      ]),
      const SizedBox(height: 8),
      _num(PD['spacing']!, _d1, min: 0.1, (v) {
        fs.d1 = v;
        app.filletNotify();
      }, suffix: 'mm'),
      if (fs.mode == 1) ...[
        const SizedBox(height: 6),
        _num(PD['spacing']!, _d2, min: 0.1, (v) {
          fs.d2 = v;
          app.filletNotify();
        }, suffix: 'mm'),
      ],
      if (fs.mode == 2) ...[
        const SizedBox(height: 6),
        _num(PD['angle']!, _ang, min: 1, max: 89, (v) {
          fs.angle = v;
          app.filletNotify();
        }, suffix: 'deg'),
      ],
      const SizedBox(height: 8),
      Text(L.of(context).msgDistance1FirstLine,
          style: ts(10.5, T.dim)),
    ]);
  }

  Widget _num(String icon, TextEditingController ctrl,
          void Function(double) onValue,
          {String? suffix, double? min, double? max}) =>
      toolNumberRow(
        app: widget.app,
        icon: icon,
        ctrl: ctrl,
        onValue: onValue,
        suffix: suffix,
        min: min,
        max: max,
      );
}

/// M207 — ONE number row for the modeless tool windows.
///
/// The 2D Fillet's radius is the row the device asked every other tool value
/// to look like ("this polygon input field ... should be similar to the radius
/// input field"), so it stopped being a private method of that one dialog.
/// Icon, field, unit, the scrub and the number pad all come from here, and a
/// second spelling of any of them cannot drift in behind the first.
Widget toolNumberRow({
  required AppState app,
  required String icon,
  required TextEditingController ctrl,
  required void Function(double) onValue,
  String? suffix,
  double? min,
  double? max,
  /// Whole numbers only — a polygon has no 5.5 sides.
  bool integer = false,
}) {
  final row = Row(children: [
    svgi(icon, 15),
    const SizedBox(width: 6),
    Expanded(
      child: SizedBox(
        height: 28,
        child: TextField(
          controller: ctrl,
          style: ts(12.5, T.text),
          keyboardType: kValueKeyboard, // M206: the app's own pad
          stylusHandwritingEnabled: kValueHandwriting, // M179
          inputFormatters: [
            FilteringTextInputFormatter.allow(
                RegExp(integer ? r'[0-9]' : r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            suffixText: suffix,
            suffixStyle: ts(11, T.dim),
            filled: true,
            fillColor: _fieldBg,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: BorderSide(color: _fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: BorderSide(color: T.accent, width: 1.4),
            ),
          ),
          onChanged: (t) {
            final v = double.tryParse(t.replaceAll(',', '.'));
            if (v != null && v > 0) onValue(v);
          },
        ),
      ),
    ),
  ]);
  // M180 — the value drags too. The unit is decoration here, so the text stays
  // a bare number for the parse above.
  return ScrubField(
    app: app,
    controller: ctrl,
    kind: integer ? ScrubKind.count : scrubKindForUnit(suffix),
    min: min,
    max: max,
    onCommit: (t) {
      final v = double.tryParse(t.replaceAll(',', '.'));
      if (v != null && v > 0) onValue(v);
    },
    child: row,
  );
}


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
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: T.panel,
        border: Border.all(color: T.sep),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
              color: T.scrim, blurRadius: 24, offset: Offset(0, 6)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: T.fly,
            border: Border(bottom: BorderSide(color: T.panelSep)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(children: [
            Expanded(
                child: Text(L.of(context).dlgPolygon,
                    style: ts(13.5, T.text, w: FontWeight.w600))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            toolNumberRow(
              app: widget.app,
              icon: PD['countC']!,
              ctrl: _sides,
              onValue: _apply,
              min: PolygonDialog.minSides.toDouble(),
              max: PolygonDialog.maxSides.toDouble(),
              integer: true,
            ),
            const SizedBox(height: 8),
            Text(L.of(context).msgPolygonSides,
                style: ts(10.5, T.dim)),
          ]),
        ),
      ]),
    );
  }
}
