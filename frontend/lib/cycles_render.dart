// M299 — rendered mode's Cycles path, as a state machine that can be tested
// without a renderer.
//
// ---------------------------------------------------------------------------
// THE SHAPE OF THE PROBLEM
// ---------------------------------------------------------------------------
//
// RealityKit's rendered mode draws every frame. A path tracer cannot: one
// image at viewport size and a useful sample count is seconds of work, not
// milliseconds. So "rendered mode uses Cycles" cannot mean "Cycles draws the
// viewport". It means:
//
//   * the viewport keeps showing what it always showed while you move;
//   * when you STOP moving, a render starts;
//   * when it lands, it is shown over the viewport;
//   * the moment anything changes — camera, geometry, section — the image is
//     stale and goes away.
//
// That last rule is the one worth stating: a path-traced image of a model you
// have since edited is not a nicer picture of your model, it is a picture of a
// different model, and leaving it up is worse than not rendering at all.
//
// ---------------------------------------------------------------------------
// AND IT MUST BE INERT WITHOUT A RENDERER
// ---------------------------------------------------------------------------
//
// The Cycles libraries are not in the app yet. Every build until they are —
// and every host test, forever — has no shim to call, and this has to be
// nothing at all in that case: [available] false, no request ever started,
// rendered mode exactly the RealityKit view it is today. That is what lets
// this ship ahead of the renderer instead of waiting for it.
import 'dart:typed_data';

/// What the viewport is showing over the model, if anything.
enum CyclesPhase {
  /// No render wanted, or none possible.
  idle,

  /// The camera settled and a render is queued but not started.
  pending,

  /// A render is running.
  rendering,

  /// A finished image is on screen and still valid.
  shown,

  /// The last attempt failed. The reason is in [CyclesRender.error].
  failed,
}

/// Everything about the scene that changes the picture.
///
/// The image is thrown away when this changes, so it has to name every input:
/// the camera (where you are looking), the scene signature (the geometry, the
/// section, the visibility) and the size (the image is that many pixels).
/// Anything missing here is a stale image nobody can explain.
class CyclesKey {
  const CyclesKey(this.scene, this.camera, this.width, this.height);

  final String scene;
  final String camera;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CyclesKey &&
      other.scene == scene &&
      other.camera == camera &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(scene, camera, width, height);

  @override
  String toString() => '$scene|$camera|${width}x$height';
}

/// The rendered image, and which scene it is of.
class CyclesImage {
  const CyclesImage(this.key, this.rgba, this.samples);
  final CyclesKey key;
  final Uint8List rgba;
  final int samples;
}

/// Drives one render at a time and decides when the picture on screen is a lie.
///
/// Deliberately free of Flutter, AppState and FFI: what it needs is a function
/// that turns a key into pixels, which the app supplies and a test fakes.
class CyclesRender {
  CyclesRender({
    required this.renderer,
    required this.samples,
    this.available = true,
  });

  /// Produces the image for [key], or null on failure. Runs off the UI thread;
  /// this class never touches it except through the future.
  final Future<Uint8List?> Function(CyclesKey key) renderer;

  /// How hard to work. One number, because a preview that is sometimes 16
  /// samples and sometimes 512 is two different pictures of one model.
  final int samples;

  /// False when this build has no renderer linked. Everything below then does
  /// nothing at all.
  final bool available;

  CyclesPhase _phase = CyclesPhase.idle;
  CyclesKey? _wanted;
  CyclesKey? _running;
  CyclesImage? _image;
  String _error = '';

  CyclesPhase get phase => _phase;
  String get error => _error;

  /// The image to draw over the viewport, or null.
  ///
  /// Null the instant the scene moves away from it: [request] clears it rather
  /// than leaving a picture of a model that no longer exists.
  CyclesImage? get image => _image;

  /// True while something is queued or running, for the progress affordance.
  bool get busy =>
      _phase == CyclesPhase.pending || _phase == CyclesPhase.rendering;

  /// True when [key] is already the scene being waited for or shown.
  ///
  /// [request] answers this too, but only by acting on it. A caller that has
  /// expensive work to do ONLY when the scene changed — building a job out of
  /// every vertex in the model — needs to ask before committing to it.
  bool wants(CyclesKey key) => _wanted == key;

  /// The scene is now [key]. Called on every rebuild; cheap and idempotent.
  ///
  /// Returns true when the caller should repaint.
  bool request(CyclesKey? key) {
    if (!available) return false;
    if (key == null) {
      // Rendered mode is off, or there is nothing to render.
      final had = _image != null || _phase != CyclesPhase.idle;
      _wanted = null;
      _image = null;
      _phase = CyclesPhase.idle;
      return had;
    }
    if (_wanted == key) return false;
    _wanted = key;
    // Whatever is on screen is of a different scene. It goes now, not when the
    // replacement arrives: a wrong picture that lingers for four seconds is
    // read as the answer.
    final had = _image != null;
    _image = null;
    _error = '';
    _phase = CyclesPhase.pending;
    return had || true;
  }

  /// Starts the queued render if nothing is running. Returns the future for
  /// the caller to await, or null when there was nothing to start.
  Future<void>? pump() {
    if (!available) return null;
    if (_phase != CyclesPhase.pending) return null;
    final key = _wanted;
    if (key == null) return null;
    _running = key;
    _phase = CyclesPhase.rendering;
    return _finish(key);
  }

  Future<void> _finish(CyclesKey key) async {
    Uint8List? rgba;
    try {
      rgba = await renderer(key);
    } catch (e) {
      rgba = null;
      _error = '$e';
    }
    // The scene moved while we rendered. The result is of a model that is no
    // longer on screen, so it is discarded rather than shown — and the render
    // that IS wanted is left queued.
    if (_wanted != key) {
      _running = null;
      _phase = _wanted == null ? CyclesPhase.idle : CyclesPhase.pending;
      return;
    }
    _running = null;
    if (rgba == null) {
      _phase = CyclesPhase.failed;
      if (_error.isEmpty) _error = 'the renderer produced no image';
      return;
    }
    _image = CyclesImage(key, rgba, samples);
    _everRendered = true;
    _phase = CyclesPhase.shown;
  }

  /// The render in flight, for the log and for tests.
  CyclesKey? get running => _running;

  /// True once this session has produced at least one image.
  ///
  /// The FIRST render of a run is not like the others: Cycles' Metal backend
  /// has no precompiled kernels, so it compiles them from source on the device
  /// before it can trace a single ray — tens of seconds, once, cached
  /// afterwards. A progress affordance that says the same thing for a
  /// forty-second first render and a three-second second one is telling the
  /// user the app has hung.
  bool get everRendered => _everRendered;
  bool _everRendered = false;

  /// Forget everything. Leaving a document, or losing the renderer.
  ///
  /// [everRendered] deliberately survives: it is a fact about the PROCESS —
  /// whether Metal has compiled its kernels yet — not about this document, and
  /// a new session per document would otherwise promise a long wait that is
  /// not going to happen.
  void reset() {
    _wanted = null;
    _running = null;
    _image = null;
    _error = '';
    _phase = CyclesPhase.idle;
  }
}
