// M344 — the renderer as something that is always running.
//
// ---------------------------------------------------------------------------
// WHAT REPLACED WHAT
// ---------------------------------------------------------------------------
//
// M304 spawned an isolate per render: build a job, hand it over, block until
// the image came back, throw the isolate away. That is the right shape for a
// photograph and the wrong one for a viewport. Three things about it cannot be
// fixed by making it faster:
//
//   * the SCENE is rebuilt every time. Every vertex is copied into fresh
//     buffers, crossed over the FFI boundary and uploaded to the GPU — for a
//     camera move, which changed twelve floats;
//   * there is no picture until the whole thing finishes. A path tracer has a
//     usable image after one sample and a good one after twenty, and none of
//     that was reachable;
//   * an isolate that has exited cannot be asked anything, so "how far along
//     is it" had to be a C global that the UI polled.
//
// So: ONE isolate, alive for as long as rendered mode is on, holding the
// Cycles session. It takes two kinds of message — here is the scene, here is
// the camera — and sends frames back as they converge. The camera message is
// twelve floats and can be sent on every frame of an orbit; the scene message
// is sent when the model changes, which is when it has to be.
//
// ---------------------------------------------------------------------------
// WHY IT POLLS RATHER THAN BEING PUSHED
// ---------------------------------------------------------------------------
//
// Because the frames are produced on Cycles' OWN thread, inside C++, and there
// is no way for that thread to enter a Dart isolate. It could be given a
// NativeCallable — Dart supports one — but that callback would then run on
// Cycles' render thread, in the middle of its path-tracing loop, and anything
// it did would be time the GPU spent idle.
//
// The shim's answer instead is `cy_live_frame`, which is cheap when there is
// nothing new: it compares a serial number under a mutex and returns 0. So the
// worker polls it, on its own event loop, at a rate nobody has to see — and it
// drops to [kCyclesIdlePoll] the moment the image is finished, which is what
// keeps a converged viewport from costing anything worth measuring.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'cycles_view.dart' show CyclesEnv, CyclesMesh;
import 'ffi/cycles_engine.dart';
import 'log.dart';

/// How often the worker asks the shim whether there is a new frame.
///
/// A little under a display refresh. Faster is pointless — the viewport cannot
/// show two images in one frame — and slower would add latency to an orbit
/// that is already waiting on the path tracer. The call is a mutex and an
/// integer compare when there is nothing new, so an idle poll is free; what is
/// not free is the copy and the denoise, and those happen only when a frame
/// has actually landed.
const Duration kCyclesPoll = Duration(milliseconds: 14);

/// How often the worker asks after a frame that said it was FINISHED.
///
/// M347 — BECAUSE "FINISHED" USED TO BE A ONE-WAY DOOR. The worker stopped
/// polling outright when a frame came back done, on the reasoning that nothing
/// more will change until the camera or the model does, and both of those
/// restart it. That reasoning is sound and its failure mode is total: one
/// wrong `done` — and there was a race in the shim that produced them, see
/// restart() in cycles_shim.cpp — and the viewport is finished forever, with a
/// half-sampled picture on screen and a badge that says it is the final one.
/// Nothing short of touching the camera brings it back, and the user's report
/// was exactly that: "it won't get better than this."
///
/// A viewport must not have a state it cannot leave. So a finished render
/// drops to this instead of stopping: five calls a second, each of them a
/// mutex and an integer compare in C++ that returns 0, which is nothing at all
/// next to the path tracing it is watching for — and if a frame ever does
/// arrive after a `done`, it is shown rather than lost.
const Duration kCyclesIdlePoll = Duration(milliseconds: 200);

/// One frame, as it crosses back from the worker.
class CyclesLiveFrame {
  const CyclesLiveFrame({
    required this.rgba,
    required this.width,
    required this.height,
    required this.samples,
    required this.target,
    required this.done,
    required this.denoised,
    this.epoch = 0,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int samples;
  final int target;
  final bool done;
  final bool denoised;

  /// Which scene this is a frame OF.
  ///
  /// THE ONE THING A FRAME CANNOT BE LATE ABOUT. A frame of the previous
  /// CAMERA is what a frame is, and is shown; a frame of the previous MODEL is
  /// the wrong answer at any frame rate. The window is small — one turn of the
  /// worker's event loop, between the UI sending a scene and the worker
  /// applying it — but it is real: a poll that was already queued when the
  /// message arrived answers with the old picture, and the UI has by then
  /// adopted the new key. So the worker stamps every frame with the scene it
  /// was last told about, and the session drops anything older.
  final int epoch;
}

/// What the session drives. One real implementation and one fake, so the state
/// machine above it can be tested with no renderer and no isolate.
abstract class CyclesDriver {
  /// Called on the UI isolate whenever a frame arrives.
  set onFrame(void Function(CyclesLiveFrame) fn);

  /// Called when the renderer has something to say about itself.
  ///
  /// [failed] separates the two things it ever says: the name of the device it
  /// came up on, and the reason it could not. Both are worth showing and only
  /// one of them takes the mode down, and a caller that had to tell them apart
  /// by inspecting the text would be parsing an error message.
  set onNote(void Function(String text, bool failed) fn);

  /// Bring the renderer up. Safe to call again.
  void open();

  /// Replace the geometry and the world. Expensive.
  ///
  /// [epoch] identifies the scene; every frame produced from it comes back
  /// carrying it. See [CyclesLiveFrame.epoch].
  void setScene(List<CyclesMesh> meshes, CyclesEnv env, int epoch);

  /// Suspend or resume sampling, keeping the samples already taken.
  ///
  /// M355 — NOT THE SAME THING AS PUSHING A CHEAP VIEW (M354). That resets the
  /// session, which is right when the view is about to change anyway and
  /// catastrophic otherwise: it throws away every sample accumulated so far,
  /// so using it to free the GPU during a tap would reset a converging image
  /// to noise every time the user touched the screen. This comes back to the
  /// same picture.
  ///
  /// Idempotent, and cheap enough to call from a pointer callback.
  void setPaused(bool paused);

  /// Point the camera. Cheap; may be called every frame.
  void setView({
    required List<double> matrix,
    required double halfWidth,
    required double halfHeight,
    required int width,
    required int height,
    required int samples,
  });

  /// Stop rendering and give the GPU memory back.
  void close();
}

// ---- the messages ----------------------------------------------------------
// Plain classes rather than maps, so a field that is added and not filled in
// is a compile error rather than a null at the far end.

class _SceneMsg {
  const _SceneMsg(this.meshes, this.env, this.epoch);
  final List<CyclesMesh> meshes;
  final CyclesEnv env;
  final int epoch;
}

class _PauseMsg {
  const _PauseMsg(this.paused);
  final bool paused;
}

class _ViewMsg {
  const _ViewMsg(this.matrix, this.halfWidth, this.halfHeight, this.width,
      this.height, this.samples);
  final List<double> matrix;
  final double halfWidth;
  final double halfHeight;
  final int width;
  final int height;
  final int samples;
}

class _CloseMsg {
  const _CloseMsg();
}

class _FrameMsg {
  const _FrameMsg(this.bytes, this.width, this.height, this.samples, this.target,
      this.done, this.denoised, this.epoch);

  /// MOVED, not copied. A viewport-sized frame is a megabyte or two and one
  /// arrives every few tens of milliseconds; sending a plain Uint8List would
  /// copy every one of them across the isolate boundary. TransferableTypedData
  /// hands the buffer over instead and leaves the sender without it, which is
  /// exactly the semantics here — the worker never looks at a frame again.
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int samples;
  final int target;
  final bool done;
  final bool denoised;
  final int epoch;
}

class _NoteMsg {
  const _NoteMsg(this.text, this.failed);
  final String text;
  final bool failed;
}

/// Drives the shim's resident session from one long-lived isolate.
class CyclesLive implements CyclesDriver {
  CyclesLive();

  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  bool _starting = false;
  bool _closed = false;

  /// Messages sent before the worker's port arrived. There are at most two —
  /// a scene and a view — because each replaces the last.
  _SceneMsg? _pendingScene;
  _ViewMsg? _pendingView;

  @override
  set onFrame(void Function(CyclesLiveFrame) fn) => _onFrame = fn;
  void Function(CyclesLiveFrame)? _onFrame;

  @override
  set onNote(void Function(String text, bool failed) fn) => _onNote = fn;
  void Function(String text, bool failed)? _onNote;

  @override
  void open() {
    if (_isolate != null || _starting) return;
    if (CyclesFfi.instance == null) return;
    _starting = true;
    _closed = false;
    final rx = ReceivePort();
    _rx = rx;
    rx.listen(_receive);
    Isolate.spawn(_cyclesWorker, rx.sendPort,
            debugName: 'cycles', errorsAreFatal: false)
        .then((iso) {
      // CLEARED ON BOTH PATHS. A close() that lands while the spawn is still
      // in flight used to leave this true forever, and `open` is guarded on
      // it — so rendered mode would come back on and never render again, with
      // nothing in the log to say why.
      _starting = false;
      if (_closed) {
        iso.kill(priority: Isolate.immediate);
        return;
      }
      _isolate = iso;
    }).catchError((Object e) {
      _starting = false;
      Log.w('cycles', 'could not start the render isolate: $e');
      _onNote?.call('$e', true);
    });
  }

  void _receive(Object? msg) {
    if (msg is SendPort) {
      _tx = msg;
      // Whatever arrived while the isolate was starting, in the order it has
      // to be applied: a view with no scene renders an empty frame, and a
      // scene with no view renders nothing at all.
      final scene = _pendingScene;
      final view = _pendingView;
      _pendingScene = null;
      _pendingView = null;
      if (scene != null) msg.send(scene);
      if (view != null) msg.send(view);
      return;
    }
    if (msg is _FrameMsg) {
      final fn = _onFrame;
      if (fn == null) return;
      final data = msg.bytes.materialize().asUint8List();
      fn(CyclesLiveFrame(
        rgba: data,
        width: msg.width,
        height: msg.height,
        samples: msg.samples,
        target: msg.target,
        done: msg.done,
        denoised: msg.denoised,
        epoch: msg.epoch,
      ));
      return;
    }
    if (msg is _NoteMsg) {
      _onNote?.call(msg.text, msg.failed);
    }
  }

  @override
  void setScene(List<CyclesMesh> meshes, CyclesEnv env, int epoch) {
    final m = _SceneMsg(meshes, env, epoch);
    final tx = _tx;
    if (tx == null) {
      _pendingScene = m;
      open();
      return;
    }
    tx.send(m);
  }

  @override
  void setPaused(bool paused) {
    // DROPPED when the worker is not up yet, rather than queued. A pause is a
    // statement about right now; replaying a stale one at the moment the
    // renderer finally starts would leave it suspended for no reason, and the
    // next pointer event will state it again anyway.
    _tx?.send(_PauseMsg(paused));
  }

  @override
  void setView({
    required List<double> matrix,
    required double halfWidth,
    required double halfHeight,
    required int width,
    required int height,
    required int samples,
  }) {
    final m =
        _ViewMsg(matrix, halfWidth, halfHeight, width, height, samples);
    final tx = _tx;
    if (tx == null) {
      _pendingView = m;
      open();
      return;
    }
    tx.send(m);
  }

  @override
  void close() {
    _closed = true;
    _pendingScene = null;
    _pendingView = null;
    _tx?.send(const _CloseMsg());
    _tx = null;
    // The worker closes the Cycles session and then its own port, which ends
    // its event loop and the isolate with it. Killing it outright would leave
    // the session — and its GPU memory — behind, because nothing in C++ is
    // told that a Dart isolate has gone.
    _isolate = null;
    final rx = _rx;
    _rx = null;
    // Closed a beat later, so the worker's last frames and its shutdown are
    // not dropped on the floor.
    Timer(const Duration(seconds: 1), rx?.close ?? () {});
  }
}

/// The worker. Top-level, because that is what an isolate body has to be.
///
/// Everything it owns is here rather than in a class: it is one isolate with
/// one job, and its whole state is the size of the image it is rendering.
void _cyclesWorker(SendPort toMain) {
  final rx = ReceivePort();
  toMain.send(rx.sendPort);

  final ffi = CyclesFfi.instance;
  if (ffi == null) {
    toMain.send(const _NoteMsg('no renderer linked into this binary', true));
    rx.close();
    return;
  }

  var width = 0;
  var height = 0;
  var opened = false;
  var epoch = 0;
  Timer? poll;
  // Which cadence `poll` is running at, so a restart at the same rate is a
  // no-op and a change of rate actually changes it.
  Duration? rate;

  void stopPolling() {
    poll?.cancel();
    poll = null;
    rate = null;
  }

  // One poll. True when the frame that landed said sampling is over.
  //
  // It REPORTS rather than acts, so the cadence lives in one place — and so
  // `tick` and `startPolling` need not name each other, which two local
  // functions declared in one block cannot do.
  bool tick() {
    if (width <= 0 || height <= 0) return false;
    final CyclesFrame? f;
    try {
      f = ffi.liveFrame(width, height);
    } catch (e) {
      stopPolling();
      toMain.send(_NoteMsg('$e', true));
      return false;
    }
    if (f == null) return false;
    toMain.send(_FrameMsg(
      TransferableTypedData.fromList([f.rgba]),
      f.width,
      f.height,
      f.samples,
      f.target,
      f.done,
      f.denoised,
      epoch,
    ));
    return f.done;
  }

  void startPolling([Duration every = kCyclesPoll]) {
    if (poll != null && rate == every) return;
    poll?.cancel();
    rate = every;
    poll = Timer.periodic(every, (_) {
      // Finished. Nothing more will change until the camera or the model does,
      // and both of those put the fast cadence back — so an idle rendered
      // viewport costs `kCyclesIdlePoll`, which is a handful of integer
      // compares a second and no GPU at all. It is not zero on purpose: see
      // the note on that constant for what stopping outright cost.
      if (tick()) startPolling(kCyclesIdlePoll);
    });
  }

  bool ensureOpen() {
    if (opened) return true;
    // BLOCKING, and on a cold install this is where the Metal kernels are
    // compiled — minutes. It is on the worker, which is the whole reason the
    // worker exists, and the warm-up has usually already paid it by now.
    try {
      opened = ffi.liveOpen();
    } catch (e) {
      toMain.send(_NoteMsg('$e', true));
      return false;
    }
    if (!opened) {
      toMain.send(_NoteMsg(ffi.lastError, true));
      return false;
    }
    toMain.send(_NoteMsg(ffi.deviceName, false));
    return true;
  }

  rx.listen((Object? msg) {
    if (msg is _CloseMsg) {
      stopPolling();
      if (opened) {
        try {
          ffi.liveClose();
        } catch (_) {
          // A renderer that will not shut down cleanly must not keep the
          // isolate alive; the process is about to reclaim it either way.
        }
      }
      opened = false;
      rx.close();
      return;
    }
    if (msg is _SceneMsg) {
      if (!ensureOpen()) return;
      // Stamped BEFORE the upload, so a frame produced during it — there are
      // none, because liveScene blocks this isolate, but the ordering is the
      // point — belongs to the new scene and not the old.
      epoch = msg.epoch;
      try {
        if (!ffi.liveScene(msg.meshes, msg.env)) {
          toMain.send(_NoteMsg(ffi.lastError, true));
          return;
        }
      } catch (e) {
        toMain.send(_NoteMsg('$e', true));
        return;
      }
      startPolling();
      return;
    }
    if (msg is _PauseMsg) {
      // NOT ensureOpen(). Pausing a renderer that has not been brought up is
      // not a reason to bring it up — that would turn a stray touch during
      // startup into a kernel compile.
      if (!opened) return;
      try {
        ffi.livePause(msg.paused);
      } catch (e) {
        toMain.send(_NoteMsg('$e', true));
      }
      return;
    }
    if (msg is _ViewMsg) {
      if (!ensureOpen()) return;
      width = msg.width;
      height = msg.height;
      try {
        if (!ffi.liveView(
          matrix: msg.matrix,
          halfWidth: msg.halfWidth,
          halfHeight: msg.halfHeight,
          width: msg.width,
          height: msg.height,
          samples: msg.samples,
        )) {
          toMain.send(_NoteMsg(ffi.lastError, true));
          return;
        }
      } catch (e) {
        toMain.send(_NoteMsg('$e', true));
        return;
      }
      startPolling();
    }
  });
}
