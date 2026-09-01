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
// last frame, which is milliseconds. Waiting for a standstill now buys nothing
// and costs the whole point: a path tracer that follows you round the model.
//
// So the camera is pushed on every frame, and the timer that is left does
// something else entirely.
//
// ---------------------------------------------------------------------------
// THE ONE THING A STANDSTILL STILL DECIDES: HOW BIG THE IMAGE IS
// ---------------------------------------------------------------------------
//
// A path tracer has a frame budget like anything else, and the honest way to
// meet it during an orbit is fewer PIXELS, not fewer samples — the eye is
// tracking a shape in motion and cannot resolve fine detail, but it can see
// noise perfectly well. So the image is rendered at [kCyclesMovingSide] while
// the camera is moving and at [kCyclesMaxSide] once it stops, and the timer
// below is what notices that it stopped.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../cycles_render.dart';
import '../cycles_scene.dart';
import '../cycles_session.dart';
import '../cycles_warmup.dart';
import '../cycles_view.dart';
import '../l10n/l.dart';
import '../part_render.dart' show Cam3;
import '../render_engine.dart';
import '../theme.dart';

/// How long the camera has to hold still before the image is re-rendered at
/// full resolution.
///
/// Long enough that letting go of an orbit does not immediately commit the
/// device to four times the pixels you are about to invalidate; short enough
/// that stopping to look at something sharpens it before you have finished
/// looking.
const Duration kCyclesSettle = Duration(milliseconds: 350);

/// Draws the path-traced image of the current document over the viewport, and
/// nothing at all when there is no renderer or the mode is not rendered.
class CyclesLayer extends StatefulWidget {
  const CyclesLayer({super.key, required this.app, required this.cam,
      required this.size});

  final AppState app;
  final Cam3 cam;
  final Size size;

  @override
  State<CyclesLayer> createState() => _CyclesLayerState();
}

class _CyclesLayerState extends State<CyclesLayer> {
  Timer? _settle;
  ui.Image? _decoded;
  int _decodedSerial = -1;
  int _serial = 0;
  bool _decoding = false;

  /// True while the camera is still being moved, which is what decides the
  /// image size. Set by every camera change, cleared by [kCyclesSettle].
  bool _moving = false;

  /// The camera key the last build saw, so a change can be noticed here
  /// rather than being asked of the session — which cannot answer, because by
  /// the time it has been offered the key it has already adopted it.
  String _lastCamera = '';

  @override
  void initState() {
    super.initState();
    CyclesWarmup.instance.addListener(_repaint);
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
    CyclesWarmup.instance.removeListener(_repaint);
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
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final session = app.cycles;
    if (!session.available) return const SizedBox.shrink();

    final camera = cyclesCameraKey(widget.cam);
    if (camera != _lastCamera) {
      _lastCamera = camera;
      _armSettle();
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final (w, h) =
        cyclesImageSize(widget.size.width, widget.size.height, dpr,
            moving: _moving);
    // Rendered mode being ON is a different question from whether a render can
    // START. On a cold install the Metal kernels are still being compiled from
    // source (M320), and a render begun into that blocks for the whole compile
    // with nothing on screen. So the mode decides what to SHOW and the warm-up
    // decides whether to RENDER.
    final warmup = CyclesWarmup.instance;
    final mode = cyclesWanted(app);
    final wanted = mode && warmup.ready;
    final changed = session.offer(
      wanted: wanted,
      scene: cyclesSceneKey(app, widget.cam),
      camera: camera,
      width: w,
      height: h,
      buildScene: () => cyclesSceneData(app, widget.cam),
      buildView: (scene) => cyclesViewParams(widget.cam, scene.reach),
    );
    if (changed && session.render.image == null) {
      // The model changed, so the texture belongs to a picture of a model that
      // no longer exists.
      _decoded?.dispose();
      _decoded = null;
      _decodedSerial = -1;
    }
    if (!wanted) _settle?.cancel();

    final img = session.render.image;
    if (img != null && _decodedSerial != _serial) _decode(img, _serial);

    return IgnorePointer(
      child: Stack(children: [
        if (_decoded != null)
          Positioned.fill(
            child: RawImage(
              image: _decoded,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
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
