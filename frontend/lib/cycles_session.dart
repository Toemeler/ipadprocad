// M304 — the piece that actually makes rendered mode call Cycles.
//
// M344 — AND WHAT IT DRIVES NOW.
//
// It used to build a whole job — every vertex, the camera, the world — and
// hand it to a fresh isolate that rendered it once and exited. The job was the
// unit, and there was only one kind of it.
//
// There are two now, and keeping them apart is the entire performance
// argument of the live renderer:
//
//   THE SCENE is every vertex in the document, its materials and its world. It
//   is megabytes, it is an upload to the GPU, and it is rebuilt only when the
//   model changes.
//
//   THE VIEW is twelve floats, two half-extents and an image size. It is sent
//   on every frame of an orbit and costs nothing.
//
// [CyclesRender] decides which of the two a rebuild needs; this class builds
// it and hands it to a [CyclesDriver]. The driver is an interface so the whole
// path above it can be tested with no renderer, no isolate and no GPU.
import 'cycles_boot.dart';
import 'cycles_live.dart';
import 'cycles_render.dart';
import 'cycles_view.dart';
import 'log.dart';

/// Everything the renderer needs that does not change when the camera moves.
///
/// [reach] travels with the meshes because the camera needs it — the eye is
/// pulled back past the scene so nothing is clipped — and it is a property of
/// the GEOMETRY, not of the view. Recomputing it per camera push would mean
/// walking every vertex on every frame of an orbit, which is the one thing the
/// split exists to avoid.
class CyclesScene {
  const CyclesScene({
    required this.meshes,
    required this.env,
    required this.reach,
  });

  final List<CyclesMesh> meshes;
  final CyclesEnv env;
  final double reach;

  /// Total triangles, for the log and for a budget test.
  int get triangles {
    var n = 0;
    for (final (_, _, t, _) in meshes) {
      n += t.length ~/ 3;
    }
    return n;
  }
}

/// Where the camera is, in the form the shim takes.
class CyclesViewParams {
  const CyclesViewParams({
    required this.matrix,
    required this.halfWidth,
    required this.halfHeight,
  });

  final List<double> matrix;
  final double halfWidth;
  final double halfHeight;
}

/// Drives [CyclesRender] with a real renderer on a real isolate.
///
/// One per document viewport. The app owns it; the widget offers it scenes and
/// draws whatever image it is holding.
class CyclesSession {
  CyclesSession({
    int samples = kCyclesSamples,
    CyclesDriver? driver,
    bool? available,
  })  : _samples = samples,
        _driver = driver ?? CyclesLive() {
    render = CyclesRender(available: available ?? cyclesReady);
    _driver.onFrame = _frame;
    _driver.onNote = _takeNote;
  }

  final int _samples;
  final CyclesDriver _driver;

  /// The state machine. Read [CyclesRender.image] to draw, [busy] for the
  /// progress affordance.
  late final CyclesRender render;

  /// The scene last pushed, kept for its reach and for the log.
  CyclesScene? _scene;

  /// Which scene the renderer is holding, counted up on every push.
  ///
  /// A frame stamped with an older one is a picture of a model that has since
  /// been edited, and there is no frame rate at which showing it is right.
  /// See [CyclesLiveFrame.epoch] for the window this closes.
  int _epoch = 0;

  /// Fires when a frame lands, so a viewport can repaint without polling.
  ///
  /// A LIST, not one callback. Both viewports build a CyclesLayer and there is
  /// a frame or two during a document switch where both are mounted; with a
  /// single slot the second overwrites the first, and then the first's dispose
  /// clears it — leaving a live session nobody is listening to and a viewport
  /// that has stopped updating for no visible reason. The same shape
  /// CyclesWarmup already uses, for the same reason.
  final List<void Function()> _listeners = [];

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);

  void _notify() {
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }

  /// The sample count images from this session converge to when the camera is
  /// STILL. An orbit is pushed a smaller target; see [offer].
  int get samples => _samples;

  /// What the most recent push actually asked for, for the log and for tests.
  int get target => _target;

  bool get available => render.available;

  /// The scene the renderer is currently holding, for the log and for tests.
  CyclesScene? get scene => _scene;

  /// What the renderer said about itself: the device it is running on, or why
  /// it stopped.
  String get note => _noteText;
  String _noteText = '';

  /// Suspend or resume sampling, keeping what has been sampled.
  ///
  /// M355 — separate from [offer] on purpose. Everything offer decides is a
  /// property of the SCENE, and a change to any of it restarts sampling. This
  /// is a property of the MACHINE — whether the compositor needs the GPU more
  /// than the tracer does this instant — and it must be able to change
  /// without costing the image. Two different questions, so two entry points.
  void setPaused(bool paused) {
    if (!render.available) return;
    if (paused == _paused) return;
    _paused = paused;
    _driver.setPaused(paused);
  }

  bool _paused = false;

  /// Whether sampling is currently suspended, for the log and for tests.
  bool get paused => _paused;

  /// The scene, as of this frame.
  ///
  /// [wanted] is false whenever a Cycles image would be wrong to show at all —
  /// not rendered mode, no renderer linked, nothing to draw, a sketch open.
  ///
  /// [buildScene] is called only when the SCENE key changed, so it may be
  /// expensive. [buildView] is called whenever anything changed, so it may not
  /// be: it is twelve floats and it runs on every frame of an orbit.
  ///
  /// [samples] is what this frame is sampling TOWARDS, which is not one number
  /// any more: an orbit asks for [kCyclesMovingSamples] so the GPU can go idle
  /// between camera pushes, and a standstill asks for [kCyclesSamples]. Null
  /// means the session's own settled target, which is what every caller that
  /// does not navigate wants.
  ///
  /// Returns true when the caller should repaint.
  bool offer({
    required bool wanted,
    required String scene,
    required String camera,
    required int width,
    required int height,
    required CyclesScene Function() buildScene,
    required CyclesViewParams Function(CyclesScene scene) buildView,
    int? samples,
  }) {
    if (!render.available) return false;
    if (!wanted || width < 1 || height < 1) {
      final (push, repaint) = render.request(null);
      if (push == CyclesPush.stop) {
        _scene = null;
        _driver.close();
        Log.i('cycles', 'renderer stopped');
      }
      return repaint;
    }
    // Held so the scene branch below can push a view too: a scene with no
    // camera renders nothing, so the two always travel together on a rebuild.
    _buildView = buildView;
    final target = samples ?? _samples;
    _target = target;
    final key = CyclesKey(scene, camera, width, height, target);
    final (push, repaint) = render.request(key);
    switch (push) {
      case CyclesPush.nothing:
      case CyclesPush.stop:
        break;
      case CyclesPush.scene:
        final s = buildScene();
        _scene = s;
        _epoch++;
        _driver.open();
        _driver.setScene(s.meshes, s.env, _epoch);
        Log.i(
            'cycles',
            'scene ${s.meshes.length} meshes, ${s.triangles} tris, '
                '${s.env.hasHdri ? 'hdri' : 'no hdri'}, $target spp');
        _pushView(width, height);
      case CyclesPush.view:
        _pushView(width, height);
    }
    return repaint;
  }

  void _pushView(int width, int height) {
    final s = _scene;
    if (s == null) return;
    // Restarted here rather than in `offer`, because this is the call that
    // actually resets the session: everything before it may or may not have
    // decided to push, and a clock started on a decision that did not push
    // would time the wrong thing.
    //
    // NOT FOR A PARKED PUSH. M354 parks the tracer during a gesture by asking
    // for a single sample, and that frame converges in microseconds by design.
    // Timing it would put two lines in the log for every drag and bury the one
    // render anybody wants the numbers for.
    if (_target > 1) {
      _clock = Stopwatch()..start();
      _firstFrameLogged = false;
    } else {
      _clock = null;
    }
    final v = _buildView;
    if (v == null) return;
    final p = v(s);
    _driver.setView(
      matrix: p.matrix,
      halfWidth: p.halfWidth,
      halfHeight: p.halfHeight,
      width: width,
      height: height,
      samples: _target,
    );
  }

  /// The target the LAST push asked for. Set at the top of [offer] alongside
  /// the key, for the same reason [_buildView] is: two branches need it and it
  /// is a parameter, not state that can go stale on its own. Starts at the
  /// settled target, so it reads correctly before anything has been offered.
  late int _target = _samples;

  /// The current frame's view builder. Set at the top of [offer] and read only
  /// inside that same call, so it can never be stale — it is a parameter that
  /// two branches need, not state.
  CyclesViewParams Function(CyclesScene)? _buildView;

  void _frame(CyclesLiveFrame f) {
    // A frame of a model that has since been edited. It was in flight when the
    // scene changed; the state machine has already taken the old picture down
    // and must not be handed it back.
    if (f.epoch != _epoch) return;
    if (!render.accept(f)) return;
    _timeIt(f);
    _notify();
  }

  /// When the view being rendered was pushed, for [_timeIt].
  Stopwatch? _clock;
  bool _firstFrameLogged = false;

  /// M356 — TWO NUMBERS PER RENDER, BECAUSE NOTHING ELSE COMES BACK FROM THE
  /// DEVICE.
  ///
  /// Every judgement about this renderer's speed so far has been made here,
  /// from arithmetic, and every one of them has been checked by a person
  /// saying "it is still slow". That is not a feedback loop. These two lines
  /// turn "it feels laggy" into something with units in it:
  ///
  ///   * TIME TO FIRST PIXEL. How long after letting go of the camera anything
  ///     appears. It is the number the settle delay is traded against and the
  ///     one a person actually feels.
  ///   * TIME TO CONVERGENCE, with the sample count reached and the size. A
  ///     render that stops at 300 samples of 4096 has converged; one that
  ///     stops at 12 has hit something else, and the two are indistinguishable
  ///     from a description.
  ///
  /// Logged rather than shown: the badge is for the person using the app, and
  /// this is for whoever is asked why it is slow.
  void _timeIt(CyclesLiveFrame f) {
    final c = _clock;
    if (c == null) return;
    if (!_firstFrameLogged) {
      _firstFrameLogged = true;
      Log.i('cycles',
          'first pixel in ${c.elapsedMilliseconds} ms (${f.width}x${f.height})');
    }
    if (f.done) {
      Log.i(
          'cycles',
          'converged in ${c.elapsedMilliseconds} ms at ${f.samples}/${f.target} spp '
              '(${f.width}x${f.height})');
      c.stop();
      _clock = null;
    }
  }

  void _takeNote(String text, bool failed) {
    _noteText = text;
    if (failed) {
      Log.w('cycles', 'renderer failed: $text');
      if (render.fail(text)) _notify();
      return;
    }
    Log.i('cycles', 'renderer on $text');
  }

  /// Stop rendering and forget everything. Leaving a document.
  void reset() {
    _scene = null;
    _buildView = null;
    render.reset();
    _driver.close();
  }
}
