// M304 — the Cycles image, on screen, over the viewport.
//
// One widget for both viewports. Everything it needs it takes from AppState
// and the camera it is handed, so the part viewport and the assembly viewport
// each add one line rather than a copy of this logic — the two have drifted
// apart before (M292's section cache is what that costs).
//
// ---------------------------------------------------------------------------
// WHY IT WAITS BEFORE STARTING
// ---------------------------------------------------------------------------
//
// A render is seconds of GPU work whose result is thrown away the moment the
// camera moves again. Starting one on every frame of an orbit would spend the
// whole drag rendering images nobody ever sees, and heat the device doing it.
// So the key is offered on every build — that part is cheap, and it is what
// takes a stale image DOWN immediately — but the render itself only starts
// once the scene has held still for [kCyclesSettle].
//
// The timer is restarted, not merely armed, on every change: a slow continuous
// orbit must not accumulate enough quiet frames to trip it.
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

/// How long the scene has to hold still before a render starts.
///
/// Long enough that letting go of an orbit does not immediately commit the
/// device to seconds of path tracing you are about to invalidate; short enough
/// that stopping to look at something starts producing the picture without you
/// wondering whether the mode did anything.
const Duration kCyclesSettle = Duration(milliseconds: 450);

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
  CyclesImage? _decodedOf;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    CyclesWarmup.instance.addListener(_warmupChanged);
    // M340 — and the renderer choice, which is a preference living outside
    // AppState and so does not arrive through a document rebuild. Switching to
    // RealityKit has to take the path-traced image DOWN on the same frame, not
    // whenever the model next changes.
    RenderEngines.engine.addListener(_warmupChanged);
  }

  void _warmupChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CyclesWarmup.instance.removeListener(_warmupChanged);
    RenderEngines.engine.removeListener(_warmupChanged);
    _settle?.cancel();
    _decoded?.dispose();
    super.dispose();
  }

  void _arm() {
    _settle?.cancel();
    _settle = Timer(kCyclesSettle, () {
      if (!mounted) return;
      final f = widget.app.cycles.pump();
      if (f == null) return;
      setState(() {}); // rendering now: show the badge
      f.then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  /// RGBA8 to a texture, once per image.
  ///
  /// Decoding is asynchronous and this is called from build, so the first
  /// build after a render lands draws nothing and the decode's own setState
  /// draws the picture a frame later. That frame is invisible next to the
  /// seconds the render took.
  void _decode(CyclesImage img) {
    if (_decoding) return;
    _decoding = true;
    final key = img.key;
    ui.decodeImageFromPixels(
      img.rgba,
      img.key.width,
      img.key.height,
      ui.PixelFormat.rgba8888,
      (image) {
        _decoding = false;
        if (!mounted) {
          image.dispose();
          return;
        }
        // The scene moved while we were decoding. Same rule as the render
        // itself: an image of a model that is no longer on screen is not shown.
        final now = widget.app.cycles.render.image;
        if (now == null || now.key != key) {
          image.dispose();
          return;
        }
        setState(() {
          _decoded?.dispose();
          _decoded = image;
          _decodedOf = now;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final session = app.cycles;
    if (!session.available) return const SizedBox.shrink();

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final (w, h) = cyclesImageSize(widget.size.width, widget.size.height, dpr);
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
      scene: cyclesSceneKey(app),
      camera: cyclesCameraKey(widget.cam),
      width: w,
      height: h,
      buildJob: () =>
          cyclesSceneJob(app, widget.cam, w, h, samples: session.samples),
    );
    if (changed) {
      // The texture belongs to an image that has just been discarded.
      _decoded?.dispose();
      _decoded = null;
      _decodedOf = null;
    }
    if (session.render.phase == CyclesPhase.pending) {
      _arm();
    } else if (!wanted) {
      _settle?.cancel();
    }

    final img = session.render.image;
    if (img != null && !identical(img, _decodedOf)) _decode(img);

    return IgnorePointer(
      child: Stack(children: [
        if (_decoded != null && _decodedOf != null)
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
class _CyclesBadge extends StatelessWidget {
  const _CyclesBadge(this.session);

  final CyclesSession session;

  @override
  Widget build(BuildContext context) {
    final render = session.render;
    final samples = session.samples;
    // The device the last render actually ran on, which is the one thing
    // somebody looking at this wants to know and cannot otherwise find out:
    // the shim prefers Metal and falls back to the CPU, and a CPU render on
    // an iPad is the difference between four seconds and four minutes. Long
    // names are trimmed — "Apple M4 (GPU - 10 cores)" is more than a badge.
    final dev = render.phase == CyclesPhase.shown && session.note.isNotEmpty
        ? ' · ${session.note.length > 20 ? '${session.note.substring(0, 19)}…' : session.note}'
        : '';
    // The first render of a run also compiles Metal's kernels from source —
    // tens of seconds, once. Saying "$samples spp" through that wait is
    // indistinguishable from a hang, so it says what is actually happening.
    final first = !render.everRendered;
    final t = L.of(context);
    final (label, tone) = switch (render.phase) {
      CyclesPhase.pending => (t.cyclesBadge, T.dim),
      CyclesPhase.rendering when first => (t.cyclesPreparing, T.text),
      CyclesPhase.rendering => (t.cyclesSamples(samples), T.text),
      CyclesPhase.shown => ('${t.cyclesSamples(samples)}$dev', T.dim),
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
