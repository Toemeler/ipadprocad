// M450 — the assistant's stage: one card, one orb, and the morph between them.
//
// WHAT THIS REPLACES. The panel was a chat window that happened to be doing
// work: a fixed 440x660 box that sat over the model at full size whether it
// was waiting for you, waiting for a provider, or doing nothing at all. While
// it worked — which is the longest part, and the part where there is nothing
// for you to do — it covered the thing you had just asked it to change.
//
// THE RULE THIS FILE EXISTS TO ENFORCE. The panel's size is a function of who
// is expected to act:
//
//   * IT needs to act  -> it retracts to a circle in the corner, with one line
//                         of text saying what it is doing right now.
//   * YOU need to act  -> it is a full card, because you cannot type into a
//                         circle.
//
// Nothing else decides the size. Not the length of the answer, not whether a
// block is running, not an error — those all reduce to the question above.
//
// THE LOOK is Apple's Shortcuts assistant: a very round, very soft card with a
// warm off-white gradient, a coloured bloom under it rather than a grey drop
// shadow, a bold centred line, and a quiet example beneath in the accent's own
// grey. The shimmer that crosses it while it thinks is the same idea as the
// one on "Wird geprüft …" — motion that says alive without saying progress,
// because there is no progress to report while a provider is deciding.
//
// REDUCED MOTION IS NOT DECORATION. Every animated thing here asks
// [MediaQuery.disableAnimationsOf] first and holds still if the answer is yes.
// A person who switched motion off did so because motion makes them ill.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ios_design.dart';
import '../theme.dart';

/// The radii the stage morphs between: a card corner and a full circle.
const double kAiCardRadius = 30;

/// The collapsed orb's diameter. Sized against the 44pt hit target with room
/// for the ring, and small enough that it reads as "parked" rather than as a
/// panel that failed to open.
const double kAiOrbSize = 62;

/// How long the retract and the expansion take. Long enough to read as one
/// object moving rather than two objects swapping, short enough that a fast
/// turn does not feel like it is waiting for an animation.
const Duration kAiMorphDuration = Duration(milliseconds: 420);

/// How long the title stays up before the stage retracts.
///
/// The announcement is the whole point of showing a title first — a title that
/// appears and vanishes inside one frame has told nobody anything. This is the
/// floor, not the length: the stage retracts at whichever is later, this or
/// the moment the first request is actually in flight.
const Duration kAiAnnounceDwell = Duration(milliseconds: 950);

bool _still(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// The warm gradient both the card and the orb are filled with.
///
/// Light mode is Apple's: not white but a barely-pink off-white, which is what
/// makes the bloom underneath look like light rather than like a shadow. Dark
/// mode cannot copy that — a light bloom on a dark panel reads as a glow
/// around a hole — so it inverts the idea: the panel colour lifted slightly,
/// with the accent mixed in at the top left where the light would be.
LinearGradient aiStageGradient({double t = 0}) {
  final warm = T.aiStageWarm;
  final cool = T.aiStageCool;
  // The stops drift with `t` so a still image and a thinking one are never
  // quite the same surface. Tiny on purpose: this is a breathing surface, not
  // a moving one.
  final drift = math.sin(t * math.pi * 2) * .06;
  return LinearGradient(
    begin: Alignment(-1 + drift, -1),
    end: Alignment(1, 1 - drift),
    colors: [warm, cool],
  );
}

/// The coloured bloom under the stage. Not a drop shadow: it is the accent,
/// wide and faint, which is what separates this surface from every ordinary
/// panel in the app.
List<BoxShadow> aiStageBloom({double strength = 1}) => [
      BoxShadow(
        color: T.accent.withValues(alpha: (T.isDark ? .20 : .16) * strength),
        blurRadius: 34 * strength,
        spreadRadius: 1,
        offset: const Offset(0, 12),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: (T.isDark ? .34 : .10) * strength),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
    ];

/// A light sweep that crosses its child while [active].
///
/// Says ALIVE, deliberately not PROGRESS. A provider deciding on an answer
/// publishes nothing to be a percentage of, and a bar that fills at a rate the
/// app invented is a lie that gets believed. The step counter beside it is the
/// real number, and it comes from work the app itself did.
class AiShimmer extends StatefulWidget {
  const AiShimmer({
    super.key,
    required this.child,
    required this.active,
    this.radius = kAiCardRadius,
  });
  final Widget child;
  final bool active;
  final double radius;

  @override
  State<AiShimmer> createState() => _AiShimmerState();
}

class _AiShimmerState extends State<AiShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  /// Starts and stops the loop, including when REDUCED MOTION is switched on.
  ///
  /// Gated here rather than only at paint time for two reasons, and the second
  /// one is why this is not cosmetic: a controller left repeating under
  /// `disableAnimations` burns a frame callback forever for a sweep nobody is
  /// drawing, and it makes `pumpAndSettle` in any test that reaches this
  /// widget hang until it times out. Reduced motion has to mean no motion, not
  /// invisible motion.
  void _syncMotion() {
    final run = widget.active && !_still(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(AiShimmer old) {
    super.didUpdateWidget(old);
    _syncMotion();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _still(context)) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _SweepPainter(_c.value, T.accent),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t, this.tint);
  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    // Two highlights at different speeds, so the surface never repeats on an
    // obvious beat. Both are wide and weak; a hard band would read as a
    // loading bar, which is the one thing this must not be mistaken for.
    for (final (speed, phase, alpha) in [(1.0, 0.0, .17), (0.62, .45, .11)]) {
      final x = ((t * speed + phase) % 1) * (size.width * 1.6) - size.width * .3;
      final rect = Rect.fromCircle(
        center: Offset(x, size.height * (phase == 0 ? .34 : .68)),
        radius: size.width * .42,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              tint.withValues(alpha: alpha),
              tint.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t || old.tint != tint;
}

/// The contents of the collapsed state: a turning arc and a mark, with no
/// surface of its own.
///
/// NO BACKGROUND ON PURPOSE. The stage is ONE box that changes size — a card
/// that becomes a circle — so the gradient, the corner radius and the bloom
/// all belong to that box and animate with it. An orb that painted its own
/// circle would be a second object cross-fading over the first, and the whole
/// point of the retract is that it reads as the panel moving, not as the panel
/// disappearing and a button arriving.
class AiOrbCore extends StatefulWidget {
  const AiOrbCore({super.key, required this.working, this.size = kAiOrbSize});
  final bool working;
  final double size;

  @override
  State<AiOrbCore> createState() => _AiOrbCoreState();
}

class _AiOrbCoreState extends State<AiOrbCore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  /// See [_AiShimmerState._syncMotion] — same rule, same two reasons.
  void _syncMotion() {
    final run = widget.working && !_still(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(AiOrbCore old) {
    super.didUpdateWidget(old);
    _syncMotion();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = _still(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = still ? 0.0 : _c.value;
        // The mark breathes rather than the whole orb: the orb's size is the
        // morph's to animate, and two things scaling it at once would fight.
        final breath =
            widget.working && !still ? 1 + math.sin(t * math.pi * 2) * .06 : 1.0;
        return CustomPaint(
          painter:
              widget.working && !still ? _RingPainter(t, T.accent) : null,
          child: Center(
            child: Transform.scale(
              scale: breath,
              child: Icon(
                Icons.auto_awesome,
                size: widget.size * .38,
                color: T.accent,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The turning arc on the orb's rim. An arc rather than a full ring, so the
/// rotation is legible at 62 points without a spinner's busy look.
class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.tint);
  final double t;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = (Offset.zero & size).deflate(2.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          tint.withValues(alpha: 0),
          tint.withValues(alpha: .85),
          tint.withValues(alpha: 0),
        ],
        stops: const [0, .5, 1],
        transform: GradientRotation(t * math.pi * 2),
      ).createShader(inset);
    canvas.drawArc(inset, t * math.pi * 2, math.pi * 1.1, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.tint != tint;
}

/// The line of text beside the parked orb: what it is doing, how far in, and
/// how long it has been at it.
///
/// It sits OUTSIDE the orb rather than under it because the orb lives in the
/// bottom-right corner, where there is no room below and plenty to the left.
class AiOrbLabel extends StatelessWidget {
  const AiOrbLabel({
    super.key,
    required this.headline,
    this.detail,
    this.onTap,
  });
  final String headline;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 10, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          constraints: const BoxConstraints(maxWidth: 230),
          decoration: BoxDecoration(
            gradient: aiStageGradient(),
            borderRadius: BorderRadius.circular(18),
            boxShadow: aiStageBloom(strength: .55),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: IosText.footnote
                    .on(T.text, weight: FontWeight.w600)
                    .copyWith(height: 1.25),
              ),
              if (detail != null && detail!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IosText.caption2.on(T.dim),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero face of the card: a bold centred line with a quiet example under
/// it. This is the "Was soll dein Kurzbefehl tun?" layout, and it is used for
/// three different moments — the empty prompt, the announcement of a task, and
/// a question the assistant is waiting on an answer to — because they are the
/// same moment from the card's point of view: one sentence that matters, and
/// one that helps.
class AiStageHero extends StatelessWidget {
  const AiStageHero({
    super.key,
    required this.title,
    this.subtitle,
    this.footer,
  });
  final String title;
  final String? subtitle;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: IosText.title3
                  .on(T.text, weight: FontWeight.w700)
                  .copyWith(height: 1.22),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: IosText.subheadline
                    .on(IosColors.tertiaryLabel)
                    .copyWith(height: 1.3),
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: 18),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
