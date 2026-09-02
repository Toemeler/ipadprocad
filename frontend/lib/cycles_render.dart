// M299 — rendered mode's Cycles path, as a state machine that can be tested
// without a renderer.
//
// ---------------------------------------------------------------------------
// THE SHAPE OF THE PROBLEM, AND HOW M344 CHANGED IT
// ---------------------------------------------------------------------------
//
// M299 stated the problem like this: a path tracer cannot draw the viewport,
// because one image is seconds of work, so rendered mode means "the viewport
// keeps showing what it always showed while you move; when you STOP, a render
// starts; when it lands it is shown; the moment anything changes it is stale
// and goes away."
//
// The first half of that was a fact about a ONE-SHOT renderer, not about path
// tracing. A resident session (M344) has a usable image after one sample and a
// good one after twenty, and it follows the camera. So the rules are now:
//
//   * the path-traced image is on screen the whole time, and refines;
//   * moving the camera restarts sampling and the image keeps up;
//   * changing the MODEL takes the image down at once.
//
// ---------------------------------------------------------------------------
// AND WHY THOSE LAST TWO ARE DIFFERENT
// ---------------------------------------------------------------------------
//
// M299's rule was that any change makes the image a lie. That was right when
// the replacement was four seconds away: "a wrong picture that lingers for
// four seconds is read as the answer."
//
// It is wrong when the replacement is forty milliseconds away, and for the
// same reason. An image of the camera position you were at one frame ago is
// what every renderer on earth shows — it is what a frame IS — and taking it
// down for those forty milliseconds would not be honesty, it would be a
// flicker on every frame of an orbit.
//
// A GEOMETRY change is not like that. A path-traced picture of a model you
// have since edited is not a nicer picture of your model, it is a picture of a
// different model, and there is no frame rate at which showing it is right. So
// the scene half of the key drops the image and the camera half does not.
//
// ---------------------------------------------------------------------------
// AND IT MUST BE INERT WITHOUT A RENDERER
// ---------------------------------------------------------------------------
//
// Every host test, forever, has no shim to call, and this has to be nothing at
// all in that case: [available] false, no request ever started, rendered mode
// exactly the RealityKit view it is today.
import 'dart:typed_data';

import 'cycles_live.dart' show CyclesLiveFrame;

/// What the viewport is showing over the model, if anything.
enum CyclesPhase {
  /// No render wanted, or none possible.
  idle,

  /// Sampling, with or without a picture on screen yet.
  rendering,

  /// Sampling has finished and the image will not improve.
  shown,

  /// The renderer stopped. The reason is in [CyclesRender.error].
  failed,
}

/// What [CyclesRender.request] decided has to be sent to the renderer.
///
/// The whole point of M344's split: a camera move is twelve floats and a
/// model change is every vertex in the document, and the caller must be able
/// to tell them apart before it pays for either.
enum CyclesPush {
  /// Nothing changed.
  nothing,

  /// The camera, the image size or the sample target. Cheap.
  view,

  /// The geometry, the materials or the world, and the camera with them.
  /// Expensive.
  scene,

  /// Rendered mode is off. Shut the renderer down.
  stop,
}

/// Everything about the scene that changes the picture.
///
/// Split in two on purpose. [scene] is the geometry, the section, the
/// visibility and the appearance — everything a model edit touches. [camera],
/// [width] and [height] are the view. Which half changed decides both what is
/// pushed to the renderer and whether the image on screen survives.
class CyclesKey {
  const CyclesKey(this.scene, this.camera, this.width, this.height,
      [this.samples = 0]);

  final String scene;
  final String camera;
  final int width;
  final int height;

  /// How many samples this picture is being sampled TOWARDS.
  ///
  /// M347 — part of the key because it is now part of the request. An orbit
  /// asks for `kCyclesMovingSamples` and a standstill for `kCyclesSamples`,
  /// and the change from one to the other has to reach the renderer. Today it
  /// always travels with a size change, so leaving it out would work by
  /// accident; a key that is missing a field the caller can vary is exactly
  /// how a push comes to be silently skipped.
  final int samples;

  /// True when [other] is a picture of the same MODEL, however the camera has
  /// moved since.
  bool sameScene(CyclesKey other) => other.scene == scene;

  @override
  bool operator ==(Object other) =>
      other is CyclesKey &&
      other.scene == scene &&
      other.camera == camera &&
      other.width == width &&
      other.height == height &&
      other.samples == samples;

  @override
  int get hashCode => Object.hash(scene, camera, width, height, samples);

  @override
  String toString() => '$scene|$camera|${width}x$height@$samples';
}

/// The rendered image, and how far along it is.
class CyclesImage {
  const CyclesImage({
    required this.key,
    required this.rgba,
    required this.width,
    required this.height,
    required this.samples,
    required this.target,
    required this.done,
    required this.denoised,
  });

  final CyclesKey key;
  final Uint8List rgba;
  final int width;
  final int height;

  /// How many samples this frame averages, and the count it is heading for.
  final int samples;
  final int target;

  /// Sampling has finished.
  final bool done;

  /// The a-trous filter was applied.
  ///
  /// M347 — driven by [samples] rather than by [done]: an image sampled past
  /// the shim's `kDenoiseRaw` is the raw path trace, and one that stopped short
  /// of it keeps the filter that earned it. See cycles_denoise.h.
  final bool denoised;
}

/// Decides what the renderer is asked for and what the viewport draws.
///
/// Deliberately free of Flutter, AppState, FFI and isolates: what it needs is
/// a key in and a frame back, which the app supplies and a test fakes.
class CyclesRender {
  CyclesRender({this.available = true});

  /// False when this build has no renderer linked. Everything below then does
  /// nothing at all.
  final bool available;

  CyclesPhase _phase = CyclesPhase.idle;
  CyclesKey? _wanted;
  CyclesImage? _image;
  String _error = '';
  bool _everRendered = false;

  CyclesPhase get phase => _phase;
  String get error => _error;

  /// The scene being rendered, or null when the mode is off.
  CyclesKey? get wanted => _wanted;

  /// The image to draw over the viewport, or null.
  ///
  /// It may be of a slightly older CAMERA than [wanted] — that is what a frame
  /// is — but never of an older MODEL.
  CyclesImage? get image => _image;

  /// True while sampling is still going, for the progress affordance.
  bool get busy => _phase == CyclesPhase.rendering;

  /// True when [key] is already the scene being rendered.
  ///
  /// [request] answers this too, but only by acting on it. A caller with
  /// expensive work to do ONLY when the scene changed needs to ask before
  /// committing to it.
  bool wants(CyclesKey key) => _wanted == key;

  /// The scene is now [key]. Called on every rebuild; cheap and idempotent.
  ///
  /// Returns what to push and whether the viewport needs repainting.
  (CyclesPush, bool) request(CyclesKey? key) {
    if (!available) return (CyclesPush.nothing, false);
    if (key == null) {
      final had = _image != null || _phase != CyclesPhase.idle;
      _wanted = null;
      _image = null;
      _phase = CyclesPhase.idle;
      return (had ? CyclesPush.stop : CyclesPush.nothing, had);
    }
    final was = _wanted;
    if (was == key) return (CyclesPush.nothing, false);
    _wanted = key;
    _error = '';
    _phase = CyclesPhase.rendering;
    if (was != null && was.sameScene(key)) {
      // The camera moved. Whatever is on screen is a picture of this model
      // from where the camera was a frame ago, which is what every frame of
      // every renderer is. It stays until the next one lands.
      return (CyclesPush.view, true);
    }
    // The model changed. A path-traced image of a model that no longer exists
    // is not a stale frame, it is the wrong answer.
    final had = _image != null;
    _image = null;
    return (CyclesPush.scene, had || true);
  }

  /// A frame arrived. Returns true when the viewport should repaint.
  ///
  /// The frame is NOT checked against the key, and that is deliberate: the
  /// renderer only ever renders what it was last told, so a frame in flight
  /// during a camera move is a frame of the previous camera and is exactly
  /// what should be shown until the next one. What protects against showing
  /// the wrong MODEL is [request], which drops the image on the frame the
  /// scene changes — before any frame of the new one can arrive.
  bool accept(CyclesLiveFrame frame) {
    if (!available) return false;
    final key = _wanted;
    if (key == null) return false;
    if (frame.rgba.length < frame.width * frame.height * 4) return false;
    _image = CyclesImage(
      key: key,
      rgba: frame.rgba,
      width: frame.width,
      height: frame.height,
      samples: frame.samples,
      target: frame.target,
      done: frame.done,
      denoised: frame.denoised,
    );
    _everRendered = true;
    _phase = frame.done ? CyclesPhase.shown : CyclesPhase.rendering;
    return true;
  }

  /// The renderer said it could not go on.
  ///
  /// The image is KEPT. A session that dies after producing a picture leaves a
  /// true picture of the model on screen, and taking it down would turn one
  /// failure into two.
  bool fail(String why) {
    if (!available) return false;
    if (_phase == CyclesPhase.failed && _error == why) return false;
    _error = why;
    _phase = CyclesPhase.failed;
    return true;
  }

  /// True once this session has produced at least one image.
  ///
  /// The FIRST render of a run is not like the others: Cycles' Metal backend
  /// has no precompiled kernels, so it compiles them from source on the device
  /// before it can trace a single ray — tens of seconds, once, cached
  /// afterwards. A progress affordance that says the same thing for a
  /// forty-second first render and a live one is telling the user the app has
  /// hung.
  bool get everRendered => _everRendered;

  /// Forget everything. Leaving a document, or losing the renderer.
  ///
  /// [everRendered] deliberately survives: it is a fact about the PROCESS —
  /// whether Metal has compiled its kernels yet — not about this document, and
  /// a new session per document would otherwise promise a long wait that is
  /// not going to happen.
  void reset() {
    _wanted = null;
    _image = null;
    _error = '';
    _phase = CyclesPhase.idle;
  }
}
