// M172 — drag-to-scrub arithmetic for number fields.
//
// Kept out of the widget on purpose: "which step, and what value does this
// drag land on" is the whole feel of the interaction, and it is the part worth
// testing. The widget is then only plumbing.
import 'dart:math' as math;

/// Screen distance one step should cost. Tuned rather than derived: below
/// ~10 px a finger cannot hold a value still, above ~20 px scrubbing a large
/// range turns into a swipe across the whole screen. 14 px is a comfortable
/// notch on both a finger and a Pencil.
const double kPxPerStep = 14.0;

/// M180 — what a field's number MEASURES, which is what decides its detent.
///
/// The zoom-derived step below is right for a LENGTH and only for a length: it
/// asks "what is a pixel worth in the model", which is a question an angle, a
/// tooth count or a profile shift does not have. Scrubbing the pattern count
/// by whatever 14 px of a zoomed-out view happens to be worth would step it in
/// tens; scrubbing a pressure angle that way would step it in millimetres of
/// nothing. So the fields that are not lengths carry a fixed ladder instead.
enum ScrubKind {
  /// Millimetres in the drawing: dimensions, offsets, radii, depths, spacings.
  length,

  /// Degrees. A degree is a degree at any magnification.
  angle,

  /// A whole number of things: teeth, occurrences, planets.
  count,

  /// A small dimensionless number — a profile shift, a number of turns. Not a
  /// length the zoom can scale, and too fine to step in whole units.
  ratio,
}

/// The fixed detents for the kinds the zoom cannot speak for.
///
/// 1° because that is the unit drawings are dimensioned in; 1 because half a
/// tooth does not exist; 0.1 because a profile shift lives between -0.5 and
/// +0.5 and a whole unit would cross the entire useful range in one notch.
const double kAngleScrubStep = 1.0;
const double kCountScrubStep = 1.0;
const double kRatioScrubStep = 0.1;

/// The detent [kind] steps in, given a view where one pixel spans
/// [unitsPerPixel] model units (which only [ScrubKind.length] consults).
double scrubStepFor(ScrubKind kind, double unitsPerPixel) => switch (kind) {
      ScrubKind.length => scrubStep(unitsPerPixel),
      ScrubKind.angle => kAngleScrubStep,
      ScrubKind.count => kCountScrubStep,
      ScrubKind.ratio => kRatioScrubStep,
    };

/// The [ScrubKind] a field's UNIT implies.
///
/// Every value field in the app already says what its number is in, to print
/// it beside the box — so no dialog has to answer the same question twice.
ScrubKind scrubKindForUnit(String? unit) {
  switch ((unit ?? '').trim().toLowerCase()) {
    case 'deg':
    case '°':
      return ScrubKind.angle;
    case 'ul': // "unitless": a coil's turns
      return ScrubKind.ratio;
    default:
      return ScrubKind.length;
  }
}

/// The units-per-pixel a FIXED step has to be fed to [scrubbedValue] as, so
/// one detent costs the same [kPxPerStep] of travel as a length's does.
///
/// Deriving it rather than special-casing the arithmetic keeps ONE function
/// deciding where a scrub lands — the one with the grid-snapping in it, which
/// is the part that makes a drag feel like detents instead of a smear.
double scrubUnitsPerPixel(ScrubKind kind, double unitsPerPixel) =>
    kind == ScrubKind.length
        ? unitsPerPixel
        : scrubStepFor(kind, unitsPerPixel) / kPxPerStep;

/// The 1-2-5 ladder, the same series every ruler and axis in engineering uses.
/// A step is always something a person would say out loud — 0.5 mm, 2 mm,
/// 1 cm — never 0.37 mm, however the zoom happens to fall.
const List<double> _mantissa = [1.0, 2.0, 5.0];

/// The step a scrub should move in, for a view where one screen pixel spans
/// [unitsPerPixel] model units.
///
/// Zooming in gives finer steps and zooming out coarser ones, which is what
/// makes one gesture serve a 0.5 mm fillet and a 200 mm plate without a mode
/// switch: the step follows what you can actually SEE.
///
/// [min] floors it so an extreme zoom cannot demand steps no one can type;
/// the default 0.1 mm is the finest value the dialogs display.
double scrubStep(double unitsPerPixel, {double min = 0.1}) {
  if (!unitsPerPixel.isFinite || unitsPerPixel <= 0) return min;
  final raw = unitsPerPixel * kPxPerStep;
  if (!raw.isFinite || raw <= 0) return min;
  // Decompose into mantissa x 10^exp, then snap the mantissa UP the ladder.
  final exp = (math.log(raw) / math.ln10).floor();
  final pow10 = math.pow(10.0, exp).toDouble();
  final m = raw / pow10;
  for (final c in _mantissa) {
    if (m <= c * 1.0000001) return math.max(min, c * pow10);
  }
  return math.max(min, 10.0 * pow10);
}

/// Where a scrub of [dxPixels] from [start] lands, in steps of [step].
///
/// Snaps to the step GRID rather than to start + n*step, so the values a
/// scrub produces are the round ones a drawing is dimensioned in — dragging
/// from 12.37 gives 12.5, 13.0, 13.5, not 12.87, 13.37. That snap is what
/// makes it feel like a detent instead of a smear.
double scrubbedValue(double start, double dxPixels, double step,
    double unitsPerPixel) {
  if (step <= 0 || !step.isFinite) return start;
  if (!dxPixels.isFinite || !unitsPerPixel.isFinite) return start;
  final pxPerStep = step / unitsPerPixel;
  if (!pxPerStep.isFinite || pxPerStep <= 0) return start;
  final n = (dxPixels / pxPerStep).roundToDouble();
  if (n == 0) return start; // inside the first notch: hold absolutely still
  final k = start / step;
  // Guard: a huge value over a tiny step overflows the round, and the raw
  // arithmetic is better than a NaN.
  if (!k.isFinite || k.abs() > 1e15) return start + n * step;
  // Step from the grid point BEHIND the direction of travel, so the FIRST
  // notch lands on the next round number rather than skipping it. Snapping
  // start to the NEAREST grid point instead would make one notch from 12.37
  // jump to 13.0, swallowing 12.5 — which reads as a lurch, not a detent.
  final anchor = (n > 0 ? k.floorToDouble() : k.ceilToDouble()) * step;
  return anchor + n * step;
}

/// How many decimals to SHOW for a given step, so the number never displays
/// more precision than the gesture can produce. A 0.5 step showing "12.500"
/// reads as false precision; showing "12" for a 0.1 step hides the change.
int scrubDecimals(double step) {
  if (!step.isFinite || step <= 0) return 2;
  if (step >= 1) return 0;
  if (step >= 0.1) return 1;
  return 2;
}
