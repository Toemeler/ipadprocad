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
// THE SURFACE IS THE REAL SYSTEM MATERIAL. `UIGlassEffect` through
// [GlassPanel], the same platform view the ribbon, the tab bar and the model
// browser already use — not a gradient painted to look like one. The first
// build of this file WAS a painted gradient, and it was a regression: the
// panel it replaced had mounted genuine glass since M146, so the redesign made
// the most prominent surface in the app the only fake one in it.
//
// WHAT APPLE DOES NOT VEND is the Intelligence glow — the iridescent rim that
// travels round the Shortcuts card while it thinks. `UIGlassEffect` is public
// API; that effect is not, on any layer, which is why a small industry of
// recreations exists. [AiGlowBorder] is a port of the best of them, credited
// below, drawn OVER the real material rather than instead of it.
//
// PORTED FROM: github.com/jacobamobin/AppleIntelligenceGlowEffect
//              MIT licence, Copyright (c) 2025 Jacob Mobin.
// Its technique, faithfully: an angular (sweep) gradient of six fixed hues
// whose stop POSITIONS are re-randomised a few times a second and eased
// between, stroked several times over with increasing width and increasing
// blur. The randomised stops are what stop it looking like a rotating barber
// pole — the colours slide past each other at different rates instead of
// turning as one rigid wheel. Taken as a technique rather than as a dependency
// because the original is SwiftUI: consuming it would mean a second platform
// view, iOS only, and a separate Dart implementation for Windows, Linux,
// macOS and the test host anyway. The hues themselves are in theme.dart.
//
// MOTION SAYS ALIVE, DELIBERATELY NOT PROGRESS. A provider deciding on an
// answer publishes nothing to be a percentage of, and a bar filling at a rate
// the app invented is a lie that gets believed. The step counter beside the
// orb is the real number, and it comes from work the app itself did.
//
// REDUCED MOTION IS NOT DECORATION. Every animated thing here asks
// [MediaQuery.disableAnimationsOf] first and holds still if the answer is yes.
// A person who switched motion off did so because motion makes them ill.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../ios_design.dart';
import '../theme.dart';

/// The collapsed orb's diameter.
///
/// LOCKED TO [kAiCardRadius], AND THE LOCK IS LOAD-BEARING. `GlassPanelView`
/// reads its corner radius once, out of the platform view's creation
/// arguments, and offers no way to change it afterwards — so a stage whose
/// radius animated would need the platform view torn down and rebuilt in the
/// middle of the morph. Keeping `radius == size / 2` means the circle and the
/// card corner are the SAME radius, one glass view is correct in both states,
/// and the whole retract is a pure resize — which `autoresizingMask` on the
/// UIVisualEffectView already handles natively. Change one of these two
/// numbers and you must change the other; m450 asserts it, so the next person
/// finds out at test time rather than by watching the glass go square.
const double kAiOrbSize = 72;

/// The stage's corner radius, in both states. See [kAiOrbSize].
const double kAiCardRadius = kAiOrbSize / 2;

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

/// How often the glow re-rolls its stop positions, and how long it eases
/// between them. The original's 0.4 s roll with a 0.5–1 s ease per layer; one
/// period here with a different phase per layer gets the same drift for one
/// controller instead of four timers.
const Duration kAiGlowPeriod = Duration(milliseconds: 2400);

bool _still(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// The tint laid over the material.
///
/// Over real glass this is a WASH — it has to stay faint enough that the
/// refraction, the specular edge and the backdrop still read through it, or
/// the app has paid for a platform view and then painted over it. Where there
/// is no material it is the surface itself and carries full weight, which is
/// what [overGlass] switches between.
LinearGradient aiStageGradient({bool overGlass = false}) {
  final a = overGlass ? .5 : 1.0;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      T.aiStageWarm.withValues(alpha: T.aiStageWarm.a * a),
      T.aiStageCool.withValues(alpha: T.aiStageCool.a * a),
    ],
  );
}

/// The resting bloom under the stage. Not a drop shadow: it is the accent,
/// wide and faint, which is what separates this surface from every ordinary
/// panel in the app. While the assistant thinks, [AiGlowBorder] takes over.
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

/// The whole surface of the stage: the system material, the tint over it, the
/// content, and the Intelligence glow round its rim while it thinks.
///
/// One widget because those are one object and their order matters — glass at
/// the bottom or it is not a backdrop, the tint above it or it is not a tint,
/// the content above that, and the glow last because it is a RIM: it belongs
/// outside the content, and drawing it under would put the card's own fill
/// over the top of it.
class AiStageSurface extends StatelessWidget {
  const AiStageSurface({
    super.key,
    required this.child,
    required this.working,
    this.radius = kAiCardRadius,
    this.bloom = 1,
    this.glow = true,
  });

  final Widget child;

  /// Drives the glow, and nothing else about the surface.
  final bool working;
  final double radius;
  final double bloom;

  /// False on the small surfaces — the status pill — where a travelling rim
  /// would be noise rather than signal.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final hasGlass = GlassPanel.isSupported;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      // Outside the clip, which is why it is a decoration and not a layer: a
      // bloom clipped to the shape it is blooming out of is not visible at all.
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: aiStageBloom(strength: bloom),
      ),
      // THE CONTENT IS THE ONLY UNPOSITIONED CHILD IN EITHER STACK, and that
      // is what gives them a size. A Stack whose children are all
      // `Positioned.fill` has nothing to measure and throws on an unbounded
      // parent — which the card never hits, because the composer wraps it in
      // a SizedBox, and the status pill hits every time, because its width is
      // its text's. Content first, everything else filled around it.
      child: Stack(
        children: [
          ClipRSuperellipse(
            borderRadius: shape,
            child: Stack(
              children: [
                // 1. THE REAL MATERIAL. It takes no touches — GlassPanel
                // wraps itself in IgnorePointer — so the content above owns
                // every gesture, which is the arrangement M48 and M102 were
                // paid for.
                if (hasGlass)
                  Positioned.fill(child: GlassPanel(cornerRadius: radius)),
                // 2. The tint: a wash over the material, the whole surface
                // where there is none.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: aiStageGradient(overGlass: hasGlass),
                      ),
                    ),
                  ),
                ),
                // 3. What the user came for, and what sizes all of this.
                child,
              ],
            ),
          ),
          // 4. The rim, over everything — its blurred outer half is supposed
          // to spill past the edge, so it is outside the clip.
          if (glow)
            Positioned.fill(
              child: IgnorePointer(
                child: AiGlowBorder(active: working, radius: radius),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Apple Intelligence rim glow, ported from the MIT SwiftUI original
/// credited at the top of this file.
class AiGlowBorder extends StatefulWidget {
  const AiGlowBorder({
    super.key,
    required this.active,
    this.radius = kAiCardRadius,
  });
  final bool active;
  final double radius;

  @override
  State<AiGlowBorder> createState() => _AiGlowBorderState();
}

class _AiGlowBorderState extends State<AiGlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: kAiGlowPeriod);

  /// The stop positions being eased between. The original re-rolls these on a
  /// timer; one controller and two sets that swap at the wrap does the same
  /// thing without four timers outliving the widget that started them.
  late List<double> _from = _roll();
  late List<double> _to = _roll();
  final _random = math.Random();

  List<double> _roll() =>
      List<double>.generate(
          kAiIntelligenceHues.length, (_) => _random.nextDouble())
        ..sort();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _from = _to;
        _to = _roll();
        _c.forward(from: 0);
      }
    });
  }

  /// Starts and stops the loop, including when REDUCED MOTION is switched on.
  ///
  /// Gated here rather than only at paint time for two reasons, and the second
  /// is why it is not cosmetic: a controller left running under
  /// `disableAnimations` burns a frame callback forever for something nobody
  /// is drawing, and it makes `pumpAndSettle` hang in every test that reaches
  /// this widget. Reduced motion has to mean no motion, not invisible motion.
  void _syncMotion() {
    final run = widget.active && !_still(context);
    if (run && !_c.isAnimating) {
      _c.forward(from: 0);
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
  void didUpdateWidget(AiGlowBorder old) {
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
    if (!widget.active || _still(context)) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return CustomPaint(
          painter: _GlowPainter(
            stops: [
              for (var i = 0; i < _from.length; i++)
                _lerpStop(_from[i], _to[i], t)
            ],
            spin: _c.value,
            radius: widget.radius,
          ),
        );
      },
    );
  }

  /// Stops must stay sorted and inside 0..1 or the shader throws; lerping two
  /// sorted lists elementwise keeps both without a re-sort each frame.
  static double _lerpStop(double a, double b, double t) =>
      (a + (b - a) * t).clamp(0.0, 1.0);
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.stops,
    required this.spin,
    required this.radius,
  });
  final List<double> stops;
  final double spin;
  final double radius;

  /// The original's four passes: one crisp, three increasingly blurred and
  /// wider. The crisp one is what makes it a rim rather than a haze; the
  /// blurred ones are what make it glow.
  static const _passes = [
    (width: 2.0, blur: 0.0, alpha: .95),
    (width: 3.0, blur: 5.0, alpha: .75),
    (width: 5.0, blur: 14.0, alpha: .55),
    (width: 7.0, blur: 22.0, alpha: .38),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RSuperellipse.fromRectAndRadius(
      rect.deflate(1),
      Radius.circular(radius),
    );
    final shader = SweepGradient(
      colors: [
        ...kAiIntelligenceHues,
        // The wheel has to close on the colour it opened with, or there is a
        // hard seam at twelve o'clock where the last hue meets the first.
        kAiIntelligenceHues.first,
      ],
      stops: [...stops, 1.0],
      transform: GradientRotation(spin * math.pi * 2),
    ).createShader(rect);

    for (final pass in _passes) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pass.width
        ..shader = shader
        ..blendMode = BlendMode.plus;
      if (pass.blur > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, pass.blur);
      }
      // The per-pass opacity has to be the LAYER's: `Paint.color` is ignored
      // wherever a shader is set, so dimming the stroke that way would have
      // done nothing at all and every pass would have painted at full weight.
      canvas.saveLayer(
        rect.inflate(pass.blur * 2 + pass.width),
        Paint()..color = Color.fromRGBO(0, 0, 0, pass.alpha),
      );
      canvas.drawRSuperellipse(rrect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.spin != spin || old.radius != radius;
}

/// The contents of the collapsed state: a mark that breathes, over the same
/// surface the card uses, with no background of its own.
///
/// NO BACKGROUND ON PURPOSE. The stage is ONE box that changes size — a card
/// that becomes a circle — so the material, the tint, the bloom and the glow
/// all belong to [AiStageSurface] and stay put across the morph. An orb that
/// painted its own circle would be a second object cross-fading over the
/// first, and the whole point of the retract is that it reads as the panel
/// moving, not as the panel disappearing and a button arriving.
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

  /// See [_AiGlowBorderState._syncMotion] — same rule, same two reasons.
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
        return Center(
          child: Transform.scale(
            scale: breath,
            child: Icon(
              Icons.auto_awesome,
              size: widget.size * .34,
              color: T.accent,
            ),
          ),
        );
      },
    );
  }
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
          margin: const EdgeInsets.only(right: 12, bottom: 12),
          constraints: const BoxConstraints(maxWidth: 230),
          child: AiStageSurface(
            working: false,
            glow: false,
            radius: 18,
            bloom: .55,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
