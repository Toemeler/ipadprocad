// M304 — the Cycles image, on screen, over the viewport.
//
// One widget for both viewports. Everything it needs it takes from AppState
// and the camera it is handed, so the part viewport and the assembly viewport
// each add one line rather than a copy of this logic — the two have drifted
// apart before (M292's section cache is what that costs).
//
// ---------------------------------------------------------------------------
// M344 — WHAT THE WAIT USED TO BE FOR, AND WHY THERE ISN'T ONE
// ---------------------------------------------------------------------------
//
// This file used to open with a note explaining that a render is seconds of
// GPU work thrown away the moment the camera moves again, so the render only
// started once the scene had held still for 450 ms.
//
// That was true of a one-shot renderer and it is not true of a resident one.
// Sampling restarts on a camera move — it does not start over from a cold
// scene — so the work an orbit throws away is the handful of samples since the
// last frame, which is milliseconds.
//
// M354 — AND THE CONCLUSION DRAWN FROM THAT WAS STILL WRONG. The reasoning
// above is about wasted WORK, and it is correct: following the camera wastes
// almost nothing. What it does not account for is CONTENTION, which is not a
// question of how much work the tracer does but of whether it is doing any.
// The wait is back, for a reason the original note could not have had — see
// below — and the camera is no longer pushed on every frame.
//
// ---------------------------------------------------------------------------
// WHAT A STANDSTILL DECIDES: WHICH RENDERER THE VIEWPORT IS
// ---------------------------------------------------------------------------
//
// M354, and it replaces three milestones of trying to make an orbit cheap
// enough to path-trace. The history is worth keeping because the failure was
// the same each time and none of the fixes were wrong on their own terms:
//
//   * M344 cut the PIXELS of a moving frame ([kCyclesMovingSide]) — fewer
//     pixels, not fewer samples, because the eye tracking a shape in motion
//     cannot resolve detail but can see noise;
//   * M347 cut the SAMPLES too ([kCyclesMovingSamples]), because a tracer
//     aiming at the settled target never finishes a frame of a moving camera
//     and so never stops, pinning the GPU for the whole gesture;
//   * M353 took out the a-trous filter, which cost 51 ms of CPU on every
//     frame handed to the display and could not keep up with its own poll.
//
// Each of those made a moving frame cheaper and the orbit was still not
// smooth. The reason is upstream of all three: the two renderers were being
// asked to share one GPU at all. Flutter's compositor needs a slice of it
// every eight milliseconds, and a path tracer that is RUNNING is a path
// tracer the compositor queues behind — however little it has been asked to
// do. Cheap is not the same as absent.
//
// So while the camera moves, the path tracer does not run and is not shown.
// The viewport IS the RealityKit surface, which is what it is for and which
// was always smooth. The tracer is parked (see [kCyclesParkedSide]) so that
// whatever was in flight is cancelled, and it stays parked until the camera
// holds still for [kCyclesSettle]. Then it renders the standstill at the
// viewport's own device pixels, and only when a frame of THAT camera has
// landed does the image go up and the surface below go to sleep.
//
// The two are exactly complementary: at every moment one of them is drawing
// the viewport and the other is switched off. Nothing shares the GPU.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../cycles_activity.dart';
import '../cycles_render.dart';
import '../cycles_scene.dart';
import '../cycles_session.dart';
import '../cycles_warmup.dart';
import '../cycles_view.dart';
import '../l10n/l.dart';
import '../part_render.dart' show Cam3;
import '../render_engine.dart';
import '../theme.dart';

/// How long the camera has to hold still before the path tracer takes over
/// from the RealityKit surface.
///
/// M354 — SHORTER, BECAUSE IT IS NOW THE LATENCY OF THE WHOLE FEATURE. It used
/// to decide only which SIZE was rendered, with a path-traced image on screen
/// either way. It now decides when the path-traced image appears at all, so
/// every millisecond of it is a millisecond of "I let go and nothing
/// happened".
///
/// The tension is real in both directions and this is a judgement, not a
/// measurement. Too short and the pauses inside a slow drag each start a
/// full-resolution render — which parking then cancels cheaply, but which
/// still makes Cycles resize its buffers to a couple of megapixels and back.
/// Too long and letting go of the model feels like nothing is happening.
/// 250 ms is above the pauses inside a continuous gesture, which are tens of
/// milliseconds, and below the point where a person decides the app has not
/// noticed them.
const Duration kCyclesSettle = Duration(milliseconds: 250);

/// Draws the path-traced image of the current document over the viewport, and
/// nothing at all when there is no renderer or the mode is not rendered.
class CyclesLayer extends StatefulWidget {
  const CyclesLayer({super.key, required this.app, required this.cam,
      required this.size, this.onCover});

  final AppState app;
  final Cam3 cam;
  final Size size;

  /// Called whenever this layer starts or stops COVERING the viewport.
  ///
  /// M347 — so the RealityKit surface underneath can stop drawing frames
  /// nobody will see. It is reported from here rather than worked out by the
  /// viewport because this is the only place that knows whether a texture
  /// actually exists yet: [CyclesSession] has an image a frame before there is
  /// anything decoded to draw with it, and a viewport acting on that would
  /// take the surface down under a hole.
  ///
  /// Called on the frame the fact changes, and with false from dispose — a
  /// surface left paused by a widget that has gone away is a blank viewport.
  final void Function(bool covering)? onCover;

  @override
  State<CyclesLayer> createState() => _CyclesLayerState();
}

class _CyclesLayerState extends State<CyclesLayer> {
  Timer? _settle;
  ui.Image? _decoded;
  int _decodedSerial = -1;
  int _serial = 0;
  bool _decoding = false;

  /// True while the camera is still being moved.
  ///
  /// M354 — AND IT NOW DECIDES WHICH RENDERER IS ON SCREEN, not merely which
  /// image size. While it is true the layer draws nothing, so the RealityKit
  /// surface below is what the user orbits, and the path tracer is parked.
  bool _moving = false;

  /// The camera the path tracer is aimed at, which is NOT [_lastCamera] while
  /// a drag is in progress: it stays on wherever the camera was when the drag
  /// began, so the parked request does not change on every frame of the
  /// gesture and the session is pushed once rather than sixty times a second.
  String _parkCamera = '';

  /// The camera [_decoded] is a picture of.
  ///
  /// A texture outlives the camera it was rendered for — that is what a frame
  /// IS — but after a drag it is a picture of somewhere else entirely, and
  /// putting it back on screen at the moment the camera stops would be a jump
  /// to the wrong angle followed by a correction. RealityKit holds the
  /// viewport until a frame of the CURRENT camera has landed.
  String _decodedCamera = '';

  /// The camera key the last build saw, so a change can be noticed here
  /// rather than being asked of the session — which cannot answer, because by
  /// the time it has been offered the key it has already adopted it.
  String _lastCamera = '';

  /// The viewport size the last build saw.
  ///
  /// M354 — A RESIZE IS A CAMERA MOVE FOR THIS PURPOSE, and leaving it out
  /// would have been worse than the orbit ever was. Rotating the iPad, or
  /// dragging a panel edge, changes this on every frame of the animation, and
  /// a settled render follows the viewport 1:1 — so without this each of those
  /// frames pushes a new full-resolution view and makes Cycles reallocate its
  /// buffers for a couple of megapixels, sixty times a second, while the
  /// compositor is trying to animate. Treated like any other move: park, show
  /// the surface, and render once it has stopped.
  String _lastSize = '';

  /// Reported on EVERY build rather than on changes, and the receiver is
  /// expected to drop a repeat.
  ///
  /// De-duplicating here would be one line and would break the case that
  /// matters: a platform view is recreated on an app resume or a document
  /// switch, and the new one comes up drawing. A layer that only spoke on
  /// changes would have nothing to say to it, and the surface would render
  /// under the path-traced image for the rest of the session.
  void _cover(bool now) => widget.onCover?.call(now);

  @override
  void initState() {
    super.initState();
    CyclesWarmup.instance.addListener(_repaint);
    // M355 — a pointer moving anywhere in the app suspends sampling, so the
    // compositor is never queued behind the tracer during an animation. The
    // listener only has to repaint; the build below turns it into a pause.
    CyclesActivity.instance.addListener(_repaint);
    // M340 — and the renderer choice, which is a preference living outside
    // AppState and so does not arrive through a document rebuild. Switching to
    // RealityKit has to take the path-traced image DOWN on the same frame, not
    // whenever the model next changes.
    RenderEngines.engine.addListener(_repaint);
    _session = widget.app.cycles..addListener(_frameLanded);
  }

  /// The session this widget is subscribed to.
  ///
  /// Held rather than looked up, because AppState builds a NEW session per
  /// document and dispose has to unsubscribe from the one it subscribed to.
  /// Reaching for `app.cycles` in dispose would remove the listener from
  /// whichever session is current by then, leaving the old one holding a
  /// closure over a dead widget.
  CyclesSession? _session;

  @override
  void didUpdateWidget(CyclesLayer old) {
    super.didUpdateWidget(old);
    final now = widget.app.cycles;
    if (identical(now, _session)) return;
    _session?.removeListener(_frameLanded);
    _session = now..addListener(_frameLanded);
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  /// A frame arrived from the render isolate.
  void _frameLanded() {
    if (!mounted) return;
    setState(() => _serial++);
  }

  @override
  void dispose() {
    _cover(false);
    CyclesWarmup.instance.removeListener(_repaint);
    CyclesActivity.instance.removeListener(_repaint);
    RenderEngines.engine.removeListener(_repaint);
    _session?.removeListener(_frameLanded);
    _settle?.cancel();
    _decoded?.dispose();
    super.dispose();
  }

  /// The camera moved. Render small until it stops.
  void _armSettle() {
    if (!_moving) {
      // Deliberately not a setState: this build is already producing the frame
      // that will use the smaller size, and the flag is read below.
      _moving = true;
    }
    _settle?.cancel();
    _settle = Timer(kCyclesSettle, () {
      if (!mounted) return;
      setState(() => _moving = false);
    });
  }

  /// RGBA8 to a texture, once per frame.
  ///
  /// Decoding is asynchronous and this is called from build, so the first
  /// build after a frame lands draws the previous one and the decode's own
  /// setState draws the new one a frame later. At a path tracer's frame rate
  /// that is invisible.
  ///
  /// A frame that arrives while a decode is in flight is DROPPED rather than
  /// queued. It is the right thing for a viewport — the next one is a few
  /// milliseconds behind it and strictly better — and a queue here would turn
  /// a slow decode into unbounded latency.
  void _decode(CyclesImage img, int serial) {
    if (_decoding) return;
    _decoding = true;
    final camera = img.key.camera;
    ui.decodeImageFromPixels(
      img.rgba,
      img.width,
      img.height,
      ui.PixelFormat.rgba8888,
      (image) {
        _decoding = false;
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _decoded?.dispose();
          _decoded = image;
          _decodedSerial = serial;
          _decodedCamera = camera;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final session = app.cycles;
    if (!session.available) {
      // Reported BEFORE the early return. Every host test and every build
      // without a renderer comes through here, and a surface left paused
      // because the layer bailed out first would be a blank viewport.
      _cover(false);
      return const SizedBox.shrink();
    }

    // Rendered mode being ON is a different question from whether a render can
    // START. On a cold install the Metal kernels are still being compiled from
    // source (M320), and a render begun into that blocks for the whole compile
    // with nothing on screen. So the mode decides what to SHOW and the warm-up
    // decides whether to RENDER.
    //
    // COMPUTED BEFORE THE CAMERA BLOCK, and M354 is why. [_moving] is cleared
    // by a timer, and a timer that is cancelled never clears it. Leaving the
    // mode switch below the budget meant that turning rendered mode off in the
    // middle of a drag cancelled the settle with [_moving] still true — and
    // since the tracer is parked for as long as that flag is set, turning the
    // mode back on without touching the camera left it parked forever: the
    // surface on screen, the mode on, and nothing ever rendering. It healed
    // only on the next camera move, which is not a state a viewport is allowed
    // to have. The flag is cleared with the timer, in one place, before
    // anything reads it.
    final warmup = CyclesWarmup.instance;
    final mode = cyclesWanted(app);
    final wanted = mode && warmup.ready;
    if (!wanted) {
      _settle?.cancel();
      _settle = null;
      _moving = false;
    }

    // M355 — SUSPEND SAMPLING WHILE ANYTHING IS BEING DRAGGED, ANYWHERE.
    //
    // Not the same lever as the park below and not the same reason. Parking
    // resets the session, which is right when the view is about to change and
    // ruinous otherwise — it would reset a converging image to noise on every
    // touch. This keeps the samples and gives back the GPU, which is the only
    // thing the compositor actually needs.
    //
    // It is set from build rather than from the listener so there is one place
    // that decides, and `setPaused` drops a repeat, so the cost of saying it
    // again on every build is a bool compare.
    session.setPaused(CyclesActivity.instance.busy);

    final camera = cyclesCameraKey(widget.cam);
    final size = '${widget.size.width.round()}x${widget.size.height.round()}';
    if (_lastCamera.isEmpty) {
      // The first build is not a MOVE. Arming the settle here would hold the
      // renderer off for [kCyclesSettle] every time rendered mode is switched
      // on, for a camera that is not going anywhere.
      _lastCamera = camera;
      _lastSize = size;
      _parkCamera = camera;
    } else if (camera != _lastCamera || size != _lastSize) {
      _lastCamera = camera;
      _lastSize = size;
      _armSettle();
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    // M354 — WHAT THE RENDERER IS ASKED FOR, WHICH IS NOTHING USEFUL WHILE THE
    // CAMERA MOVES.
    //
    // The orbit used to be a small path-traced frame: fewer pixels and fewer
    // samples, on the theory that a cheap enough frame is a fluid one. Three
    // rounds of making it cheaper did not make it fluid, and the reason is
    // that the two renderers were being asked to share one GPU at all. A path
    // tracer that is running is a path tracer the compositor queues behind.
    //
    // So it does not run. While the camera moves the request is parked on a
    // single sample of a [kCyclesParkedSide] frame of wherever the camera was
    // when the drag started: pushing it cancels whatever was in flight, the
    // tracer finishes it in microseconds, and the session idles with the GPU
    // free. RealityKit — which is what the viewport shows for the whole
    // gesture — gets the machine to itself, which is the only version of this
    // that can be as smooth as the RealityKit viewport already is.
    //
    // The parked request is CONSTANT for the length of the drag, so the
    // session is pushed once per gesture rather than once per frame.
    final int wantW, wantH, wantSamples;
    final String wantCamera;
    if (_moving) {
      wantCamera = _parkCamera;
      wantW = kCyclesParkedSide;
      wantH = kCyclesParkedSide;
      wantSamples = 1;
    } else {
      _parkCamera = camera;
      wantCamera = camera;
      final budget = cyclesFrameBudget(
          widget.size.width, widget.size.height, dpr,
          moving: false);
      wantW = budget.width;
      wantH = budget.height;
      wantSamples = budget.samples;
    }
    final changed = session.offer(
      wanted: wanted,
      scene: cyclesSceneKey(app, widget.cam),
      camera: wantCamera,
      width: wantW,
      height: wantH,
      buildScene: () => cyclesSceneData(app, widget.cam),
      buildView: (scene) => cyclesViewParams(widget.cam, scene.reach),
      // M347/M354 — a small target is what lets the session go idle, and
      // parked it is the smallest there is. One sample finishes at once, and
      // an idle session is the whole point: the GPU belongs to RealityKit for
      // as long as the camera is moving.
      samples: wantSamples,
    );
    if (changed && session.render.image == null) {
      // The model changed, so the texture belongs to a picture of a model that
      // no longer exists.
      _decoded?.dispose();
      _decoded = null;
      _decodedSerial = -1;
      _decodedCamera = '';
    }
    final img = session.render.image;
    // NOT WHILE MOVING. A frame that lands during a drag is the parked
    // thumbnail, which is never drawn — decoding it would upload a texture
    // nobody sees and throw away the one from before the drag, which is the
    // only thing that could have been reused if the camera comes back.
    if (img != null && !_moving && _decodedSerial != _serial) {
      _decode(img, _serial);
    }

    // M354 — WHEN THE PATH-TRACED IMAGE IS ON SCREEN AT ALL.
    //
    // Never while the camera is moving: that is the whole change, and it is
    // what makes the orbit RealityKit's. And not for the first moments after
    // it stops either — a texture from before the drag is a picture of a
    // different angle, and showing it the instant the camera settles would be
    // a jump to the wrong view followed by a correction a few hundred
    // milliseconds later. The surface below is already showing the right
    // angle; it keeps the viewport until a frame of THIS camera has landed.
    final showTraced =
        !_moving && _decoded != null && _decodedCamera == camera;

    // The path-traced image is opaque and fills the layer, so while it is up
    // the RealityKit surface below would be rendering into the dark. The two
    // are exactly complementary now: whichever one is not being shown is the
    // one that is switched off.
    _cover(wanted && showTraced);

    return IgnorePointer(
      child: Stack(children: [
        if (showTraced)
          Positioned.fill(
            child: RawImage(
              image: _decoded,
              fit: BoxFit.fill,
              // M347/M353 — LOW, and it is not a downgrade.
              //
              // A MOVING frame is magnified: it renders at
              // [kCyclesMovingSide] and is stretched over a viewport several
              // times wider. Mipmaps — the only thing medium adds over low —
              // are a minification tool, contribute nothing to an upscale, and
              // cost real work on the raster thread for a texture that is
              // replaced a few milliseconds later.
              //
              // A SETTLED frame is now 1:1 (M353 removed the resolution cap),
              // so there is no resampling for any quality to do and the
              // sampler is a no-op on it. That is the sharpness the cap used
              // to cost: before, every settled frame was an upscale from four
              // fifths of the viewport and low was a real, if small,
              // compromise. It is not one any more.
              filterQuality: FilterQuality.low,
            ),
          ),
        if (mode && !warmup.ready)
          Positioned(
            right: 12,
            bottom: 12,
            child: _CyclesWarmupPanel(warmup),
          )
        else if (wanted)
          Positioned(
            right: 12,
            bottom: 12,
            child: _CyclesBadge(session),
          ),
      ]),
    );
  }
}

/// What Cycles is doing, small and in the corner.
///
/// It earns its place: a path tracer that has not finished is
/// indistinguishable from one that is not running, and a failure that shows
/// nothing is indistinguishable from a mode that does nothing. Both have to be
/// legible without being a dialog.
///
/// M344 — AND IT COUNTS UP NOW. The number used to be a constant, because
/// every image was rendered at exactly one sample count and the badge was
/// telling you which. It is a live count against a target, which is the one
/// thing somebody watching a progressive render wants to know and the only
/// honest way to say "this is still getting better".
class _CyclesBadge extends StatelessWidget {
  const _CyclesBadge(this.session);

  final CyclesSession session;

  @override
  Widget build(BuildContext context) {
    final render = session.render;
    final img = render.image;
    // The device the last render actually ran on, which is the one thing
    // somebody looking at this wants to know and cannot otherwise find out.
    // Long names are trimmed — "Apple M4 (GPU - 10 cores)" is more than a badge.
    final dev = render.phase == CyclesPhase.shown && session.note.isNotEmpty
        ? ' · ${session.note.length > 20 ? '${session.note.substring(0, 19)}…' : session.note}'
        : '';
    // The first render of a run also compiles Metal's kernels from source —
    // tens of seconds, once. Saying "0 spp" through that wait is
    // indistinguishable from a hang, so it says what is actually happening.
    final first = !render.everRendered;
    final t = L.of(context);
    final (label, tone) = switch (render.phase) {
      CyclesPhase.rendering when first => (t.cyclesPreparing, T.text),
      CyclesPhase.rendering =>
        (t.cyclesSamples(img?.samples ?? 0), T.text),
      CyclesPhase.shown =>
        ('${t.cyclesSamples(img?.samples ?? session.samples)}$dev', T.dim),
      CyclesPhase.failed => (t.cyclesFailed, T.dim),
      CyclesPhase.idle => ('', T.dim),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: T.panel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: T.sep),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (render.busy)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                    strokeWidth: 1.4, color: T.accent),
              ),
            ),
          Text(label,
              style: TextStyle(
                  color: tone, fontSize: 10.5, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// What the renderer is doing while it cannot yet render.
///
/// Bigger than the badge, deliberately. The badge reports something that takes
/// seconds; this reports something that takes minutes, once per install, and
/// during which rendered mode shows the ordinary shaded view and would
/// otherwise look simply broken. It says three things: that the renderer is
/// being prepared, WHICH STEP Cycles is on in Cycles' own words, and that it
/// will not happen again.
class _CyclesWarmupPanel extends StatelessWidget {
  const _CyclesWarmupPanel(this.warmup);

  final CyclesWarmup warmup;

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final failed = warmup.phase == CyclesWarmupPhase.failed;
    // Cycles' own status sentence — "Loading render kernels (may take a few
    // minutes the first time)", then the sample count. Untranslated on
    // purpose: it comes out of the renderer at runtime, and a paraphrase would
    // be a second thing to keep true.
    final step = warmup.status;
    final p = warmup.progress;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: T.panel.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: T.sep),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (!failed)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: T.accent),
                    ),
                  ),
                Flexible(
                  child: Text(
                    failed ? t.cyclesWarmupFailed : t.cyclesWarmupTitle,
                    style: TextStyle(
                        color: T.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              if (step.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(step,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: T.dim, fontSize: 10.5)),
                ),
              // Only when Cycles is actually counting. A bar that sits at zero
              // for ninety seconds is worse than no bar at all.
              if (!failed && p >= 0 && p <= 1)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 3,
                      backgroundColor: T.sep,
                      color: T.accent,
                    ),
                  ),
                ),
              if (!failed)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(t.cyclesWarmupOnce,
                      style: TextStyle(color: T.dim, fontSize: 10)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
