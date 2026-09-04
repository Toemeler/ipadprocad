// M371 — the Measure panel.
//
// Inventor's Measure is one command driven by one modeless, information-rich
// panel, and the panel is most of what makes it good: a tap on a hole answers
// diameter AND radius AND depth AND area at once, and the panel's job is to
// put the one you came for at the top in a size you can read across a desk
// while leaving the other three a glance away.
//
// THE LAYOUT, top to bottom, and why in this order:
//
//   1. THE HEADLINE. The primary value, set at 34 pt in the tint. It is the
//      answer, and everything else on the panel is a qualification of it. Its
//      role sits above it in 13 pt so "82,50 mm" is never a number with no
//      noun.
//   2. WHAT WAS MEASURED. One chip per pick, each removable. This is the row
//      that makes a two-pick measurement legible: "Fläche → Zylindrische
//      Fläche" says why the number is a distance rather than a length, and
//      the x on a chip undoes a mis-tap without restarting.
//   3. THE DISTANCE MODE. Inventor's Minimum / Center to Center / Maximum,
//      as a segmented control and only when the pair can answer more than
//      one of them.
//   4. EVERY OTHER VALUE, as an ordinary grouped list. Tapping a row copies
//      it — Inventor's "copy one or all values", where the "one" is the row
//      you are pointing at rather than a menu.
//   5. THE TOTALS, when there are any.
//   6. DISPLAY: decimals and the second unit. Inventor's own two controls,
//      and like Inventor's they RE-RENDER the reading rather than re-measure
//      it.
//
// WHY THE NUMBERS ARE NOT [ScrubField]s, when M180 says every number in this
// app is draggable: a measurement is not an input. There is nothing to drive.
// Dragging one would have to either do nothing or change the model, and both
// are worse than a number that is plainly a readout.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import '../l10n/l.dart';
import '../measure.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';

class MeasurePanel extends StatefulWidget {
  const MeasurePanel({super.key, required this.app});

  final AppState app;

  @override
  State<MeasurePanel> createState() => _MeasurePanelState();
}

class _MeasurePanelState extends State<MeasurePanel> {
  Offset? _pos;
  bool _openValues = true;
  bool _openDisplay = false;

  static const _size = Size(IosMetrics.panelWidth, 460);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.measureSession;
    if (s == null) return const SizedBox.shrink();
    final t = L.of(context);
    final r = s.reading;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: t.measureTitle,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(
              label: t.measureRestart,
              onTap: s.isEmpty ? null : app.measureRestart),
          trailing: IosBarButton(
              label: t.close, prominent: true, onTap: app.cancelMeasure),
        ),
        children: [
          _headline(context, s, r),
          _selection(context, app, s),
          if (r != null && r.modes.length > 1) _modes(context, app, s, r),
          if (r != null && r.values.length > 1) _values(context, app, s, r),
          if (!s.totals.isEmpty) _totals(context, app, s),
          _display(context, app, s),
        ],
        footer: r == null
            ? null
            : iosFooter(children: [
                Expanded(
                  child: IosButton(
                    label: t.measureAddToTotal,
                    glyph: IosGlyph.plus,
                    style: IosButtonStyle.grey,
                    height: 36,
                    expand: true,
                    onTap: app.measureAddToTotals,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: IosButton(
                    label: t.measureCopyAll,
                    style: IosButtonStyle.tinted,
                    height: 36,
                    expand: true,
                    onTap: () => app.measureCopy(),
                  ),
                ),
              ]),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 1. the headline
  // -------------------------------------------------------------------------

  /// The primary value, big. With nothing picked it is the prompt instead —
  /// the panel always says what it is waiting for rather than sitting blank.
  Widget _headline(BuildContext context, MeasureSession s, MeasureReading? r) {
    final t = L.of(context);
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            IosMetrics.cardInset + 4, 18, IosMetrics.cardInset + 4, 6),
        child: Row(children: [
          iosGlyph(IosGlyph.pick, size: 17, color: IosColors.tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                s.isEmpty ? t.measureHintPick : t.measureHintPickSecond,
                style: IosText.subheadline.on(IosColors.tint)),
          ),
        ]),
      );
    }
    final v = r.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          IosMetrics.cardInset + 4, 16, IosMetrics.cardInset + 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(measureRoleLabel(v.role),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IosText.footnote.on(IosColors.secondaryLabel)),
          const SizedBox(height: 2),
          // FittedBox, because a volume in cubic millimetres runs to nine
          // digits and a headline that overflows is worse than one that
          // shrinks. scaleDown only: a short value stays at 34 pt.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (v.approximate)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text('≈',
                      style: IosText.title2.on(IosColors.tertiaryLabel)),
                ),
              Text(
                  measureFormat(v,
                      decimals: s.decimals,
                      unit: MeasureUnitSystem.millimetre),
                  maxLines: 1,
                  style: IosText.largeTitle
                      .on(IosColors.tint, weight: FontWeight.w600)),
            ]),
          ),
          if (s.dualUnit != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                  measureFormat(v, decimals: s.decimals, unit: s.dualUnit!),
                  style: IosText.subheadline.on(IosColors.secondaryLabel)),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 2. what was measured
  // -------------------------------------------------------------------------

  Widget _selection(BuildContext context, AppState app, MeasureSession s) {
    final t = L.of(context);
    return iosSection(
      header: t.measureSelection,
      children: [
        for (var i = 0; i < s.picks.length; i++)
          iosPickRow(
            // "1." / "2." rather than a name, because the ORDER is what
            // decides which way round a delta reads.
            label: '${i + 1}.  ${measureRefLabel(s.picks[i].kind)}',
            value: s.picks[i].owner,
            armed: false,
            filled: true,
            onClear: () => app.measureRemovePick(i),
          ),
        // The waiting row, and there is exactly one of it: what to do next
        // when nothing is picked, and what a second pick would buy when one
        // is. With two picks in hand the section is complete and says nothing.
        if (s.picks.length < 2)
          iosPickRow(
            label: s.isEmpty ? t.measureHintPick : t.measureHintPickSecond,
            armed: true,
            filled: false,
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 3. the distance mode
  // -------------------------------------------------------------------------

  Widget _modes(BuildContext context, AppState app, MeasureSession s,
      MeasureReading r) {
    return iosSection(
      children: [
        iosStackedRow(
          child: IosSegmented<MeasureDistanceMode>(
            value: r.mode,
            onChanged: app.setMeasureMode,
            segments: [
              for (final m in r.modes)
                IosSegment(value: m, label: measureModeLabel(m)),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 4. every other value
  // -------------------------------------------------------------------------

  Widget _values(BuildContext context, AppState app, MeasureSession s,
      MeasureReading r) {
    final t = L.of(context);
    // The primary is already the headline; repeating it in the list would be
    // the same number twice on one screen.
    final rest = r.values.skip(1).toList();
    // The footer carries the row's own affordance, and the ≈ note when there
    // is one. Tapping a row to copy it is invisible otherwise, and an
    // invisible affordance is one nobody uses.
    final notes = [
      t.measureCopy,
      if (rest.any((v) => v.approximate)) t.measureApproxNote,
    ];
    return iosSection(
      header: t.measureResult,
      footer: notes.join(' '),
      open: _openValues,
      onToggle: () => setState(() => _openValues = !_openValues),
      children: [
        for (final v in rest)
          iosRow(
            label: measureRoleLabel(v.role),
            value: _valueText(s, v),
            valueMaxLines: 2,
            valueColour: IosColors.label,
            // Tapping a row copies THAT value: Inventor's "copy one value",
            // reached by pointing at the one you want instead of by opening a
            // menu to name it.
            onTap: () => app.measureCopy(value: v),
          ),
      ],
    );
  }

  /// One row's value — with the second unit on its own line under it when the
  /// panel is showing dual units.
  String _valueText(MeasureSession s, MeasureValue v) {
    final primary =
        measureFormat(v, decimals: s.decimals, unit: MeasureUnitSystem.millimetre);
    final head = v.approximate ? '≈ $primary' : primary;
    final dual = s.dualUnit;
    // An angle is the same number in every length unit, so a second line for
    // it would be the same string twice.
    if (dual == null || v.unit == MeasureUnitKind.angle) return head;
    return '$head\n${measureFormat(v, decimals: s.decimals, unit: dual)}';
  }

  // -------------------------------------------------------------------------
  // 5. the totals
  // -------------------------------------------------------------------------

  Widget _totals(BuildContext context, AppState app, MeasureSession s) {
    final t = L.of(context);
    String label(MeasureUnitKind k) => switch (k) {
          MeasureUnitKind.length => t.measureTotalLength,
          MeasureUnitKind.area => t.measureTotalArea,
          MeasureUnitKind.volume => t.measureTotalVolume,
          MeasureUnitKind.angle => t.measureTotalAngle,
        };
    return iosSection(
      header: t.measureTotalsSection,
      children: [
        for (final k in MeasureUnitKind.values)
          if (s.totals.total(k) != null)
            iosRow(
              label: label(k),
              value: measureFormat(
                  MeasureValue(_roleForTotal(k), s.totals.total(k)!),
                  decimals: s.decimals,
                  unit: MeasureUnitSystem.millimetre),
              valueColour: IosColors.label,
              trailing: Text(t.measureTotalCount(s.totals.count(k)),
                  style: IosText.caption1.on(IosColors.tertiaryLabel)),
            ),
        iosRow(
          label: t.measureClearTotals,
          valueColour: IosColors.destructive,
          onTap: app.measureClearTotals,
        ),
      ],
    );
  }

  /// A role with the right UNIT for a total. The role is only read for its
  /// unit here — the label beside it is the total's own.
  MeasureRole _roleForTotal(MeasureUnitKind k) => switch (k) {
        MeasureUnitKind.length => MeasureRole.length,
        MeasureUnitKind.area => MeasureRole.area,
        MeasureUnitKind.volume => MeasureRole.volume,
        MeasureUnitKind.angle => MeasureRole.angle,
      };

  // -------------------------------------------------------------------------
  // 6. display
  // -------------------------------------------------------------------------

  Widget _display(BuildContext context, AppState app, MeasureSession s) {
    final t = L.of(context);
    return iosSection(
      header: t.measureSettings,
      open: _openDisplay,
      onToggle: () => setState(() => _openDisplay = !_openDisplay),
      children: [
        iosRow(
          label: t.measurePrecision,
          value: '${s.decimals}',
          valueColour: IosColors.label,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IosCircleButton(
              glyph: IosGlyph.minus,
              diameter: 30,
              onTap: s.decimals <= 0
                  ? null
                  : () => app.setMeasureDecimals(s.decimals - 1),
            ),
            const SizedBox(width: 6),
            IosCircleButton(
              glyph: IosGlyph.plus,
              diameter: 30,
              onTap: s.decimals >= 6
                  ? null
                  : () => app.setMeasureDecimals(s.decimals + 1),
            ),
          ]),
        ),
        iosStackedRow(
          label: t.measureDualUnit,
          child: IosSegmented<String>(
            value: s.dualUnit?.name ?? '',
            onChanged: (v) => app.setMeasureDualUnit(v.isEmpty
                ? null
                : MeasureUnitSystem.values.firstWhere((u) => u.name == v)),
            segments: [
              IosSegment(value: '', label: t.measureDualUnitOff),
              // The three a millimetre model is actually read in: centimetres
              // and metres for anything architectural, inches for anything
              // that has to talk to an American drawing.
              const IosSegment(value: 'centimetre', label: 'cm'),
              const IosSegment(value: 'metre', label: 'm'),
              const IosSegment(value: 'inch', label: 'in'),
            ],
          ),
        ),
        // Inventor's Component / Part / Faces and Edges combo box, as the
        // control iOS uses for a one-of-three choice. Only where there is
        // something to disambiguate: a 2D sketch has no bodies and no
        // components, so the row would offer two dead options.
        if (app.currentPart != null || app.currentAssembly != null)
          iosStackedRow(
            label: t.measurePriority,
            child: IosSegmented<MeasurePriority>(
              value: s.priority,
              onChanged: app.setMeasurePriority,
              segments: [
                IosSegment(
                    value: MeasurePriority.entity,
                    label: t.measurePriorityEntity),
                IosSegment(
                    value: MeasurePriority.body,
                    label: measureRefLabel(MeasureRefKind.body)),
                if (app.currentAssembly != null)
                  IosSegment(
                      value: MeasurePriority.component,
                      label: measureRefLabel(MeasureRefKind.component)),
              ],
            ),
          ),
      ],
    );
  }
}
