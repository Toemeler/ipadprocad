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
// STOPS polling the moment the image is finished, which is what keeps a
// converged viewport from costing anything at all.
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
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int samples;
  final int target;
  final bool done;
  final bool denoised;
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
  void setScene(List<CyclesMesh> meshes, CyclesEnv env);

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
  const _SceneMsg(this.meshes, this.env);
  final List<CyclesMesh> meshes;
  final CyclesEnv env;
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
      this.done, this.denoised);

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
      if (_closed) {
        iso.kill(priority: Isolate.immediate);
        return;
      }
      _isolate = iso;
      _starting = false;
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
      ));
      return;
    }
    if (msg is _NoteMsg) {
      _onNote?.call(msg.text, msg.failed);
    }
  }

  @override
  void setScene(List<CyclesMesh> meshes, CyclesEnv env) {
    final m = _SceneMsg(meshes, env);
    final tx = _tx;
    if (tx == null) {
      _pendingScene = m;
      open();
      return;
    }
    tx.send(m);
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
  Timer? poll;

  void stopPolling() {
    poll?.cancel();
    poll = null;
  }

  void tick() {
    if (width <= 0 || height <= 0) return;
    final CyclesFrame? f;
    try {
      f = ffi.liveFrame(width, height);
    } catch (e) {
      stopPolling();
      toMain.send(_NoteMsg('$e', true));
      return;
    }
    if (f == null) return;
    toMain.send(_FrameMsg(
      TransferableTypedData.fromList([f.rgba]),
      f.width,
      f.height,
      f.samples,
      f.target,
      f.done,
      f.denoised,
    ));
    if (f.done) {
      // Finished. Nothing more will change until the camera or the model does,
      // and both of those restart the polling — so an idle rendered viewport
      // costs one timer cancellation and then nothing.
      stopPolling();
    }
  }

  void startPolling() {
    if (poll != null) return;
    poll = Timer.periodic(kCyclesPoll, (_) => tick());
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
