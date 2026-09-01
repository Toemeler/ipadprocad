// M304 — the piece that actually makes rendered mode call Cycles.
//
// Everything before this was a half: M297 worked out the camera arithmetic,
// M299 worked out when an image is valid and when it is a lie, M303 worked out
// the mesh format. None of them ever ran the renderer. This does.
//
// ---------------------------------------------------------------------------
// WHY THE RENDER RUNS IN ANOTHER ISOLATE
// ---------------------------------------------------------------------------
//
// `cy_render` blocks for as long as the sample count takes — seconds. On the
// UI isolate that is seconds of frozen viewport, and the user cannot even
// leave rendered mode to escape it. So the FFI call happens in an isolate
// spawned per render.
//
// This is why [CyclesJob] exists as a plain data class instead of the renderer
// reaching into AppState: everything the render needs has to be COPYABLE, and
// AppState is not. The job is built on the UI isolate, at the moment the key
// changes, and then it is the only thing that crosses.
//
// The shim's symbols are looked up per isolate, but they resolve to the same
// statically linked code in the same process, and `cy_set_resource_path`
// writes a C++ global that every isolate then sees. So the background isolate
// needs no setup of its own.
//
// ---------------------------------------------------------------------------
// AND WHY THE JOB IS BUILT LAZILY
// ---------------------------------------------------------------------------
//
// [offer] is called from `build`, which runs on every frame of every drag.
// Building a job copies every vertex of the model into fresh 32-bit buffers —
// megabytes. So [offer] takes a THUNK, and calls it only on the frame where
// the key actually changed, which is the frame where a render is going to
// start anyway.
import 'dart:isolate';
import 'dart:typed_data';

import 'cycles_boot.dart';
import 'cycles_render.dart';
import 'cycles_view.dart';
import 'ffi/cycles_engine.dart';
import 'log.dart';

/// Everything one render needs, in a form another isolate can be handed.
class CyclesJob {
  const CyclesJob({
    required this.meshes,
    required this.matrix,
    required this.halfWidth,
    required this.halfHeight,
    required this.width,
    required this.height,
    required this.samples,
    this.world = const [0.8, 0.8, 0.8],
  });

  final List<CyclesMesh> meshes;
  final List<double> matrix;
  final double halfWidth;
  final double halfHeight;
  final int width;
  final int height;
  final int samples;
  final List<double> world;

  /// Total triangles, for the log and for a budget test.
  int get triangles {
    var n = 0;
    for (final (_, _, t) in meshes) {
      n += t.length ~/ 3;
    }
    return n;
  }
}

/// The result of one render: the pixels, and what the renderer had to say.
///
/// The note travels BACK ACROSS THE ISOLATE rather than being logged where it
/// is produced, and that is the whole point of the type. Log.init() runs on
/// the UI isolate; in a fresh one the log file handle does not exist, so
/// Log.w there goes to the device console and into a buffer nobody reads —
/// which is to say `cy_last_error()`, the one string that explains a failed
/// render, would be missing from the log file in exactly the situation where
/// somebody is reading the log file to find out why the render failed.
typedef CyclesOutcome = (Uint8List? rgba, String note);

/// Runs [job] through the shim. Top-level so it can be the body of an isolate.
///
/// Never throws: a failed render must not be able to take the app down with
/// it, so the reason comes back as text.
CyclesOutcome renderCyclesJob(CyclesJob job) {
  final ffi = CyclesFfi.instance;
  if (ffi == null) return (null, 'no renderer linked into this binary');
  try {
    final out = ffi.render(
      meshes: job.meshes,
      matrix: job.matrix,
      halfWidth: job.halfWidth,
      halfHeight: job.halfHeight,
      width: job.width,
      height: job.height,
      samples: job.samples,
      world: job.world,
    );
    if (out == null) {
      final why = ffi.lastError;
      return (null, why.isEmpty ? 'the renderer produced no image' : why);
    }
    return (out, ffi.deviceName);
  } catch (e) {
    return (null, '$e');
  }
}

/// Drives [CyclesRender] with real jobs on a real isolate.
///
/// One per document viewport. The app owns it; the widget offers it scenes and
/// draws whatever image it is holding.
class CyclesSession {
  CyclesSession({
    int samples = kCyclesSamples,
    Future<CyclesOutcome> Function(CyclesJob)? runner,
    bool? available,
  })  : _runner = runner ?? _runOnIsolate,
        _samples = samples {
    render = CyclesRender(
      renderer: _render,
      samples: samples,
      available: available ?? cyclesReady,
    );
  }

  final Future<CyclesOutcome> Function(CyclesJob) _runner;
  final int _samples;

  /// The state machine. Read [CyclesRender.image] to draw, [busy] for the
  /// progress affordance.
  late final CyclesRender render;

  CyclesJob? _job;

  /// How many samples the images this session produces were rendered at.
  int get samples => _samples;

  bool get available => render.available;

  /// The job the last started render is running, for the log and for tests.
  CyclesJob? get job => _job;

  /// The scene, as of this frame.
  ///
  /// [wanted] is false whenever a Cycles image would be wrong to show at all —
  /// not rendered mode, no renderer linked, nothing to draw, a sketch open.
  /// [buildJob] is called only when the key changed, so it may be expensive.
  ///
  /// Returns true when the caller should repaint.
  bool offer({
    required bool wanted,
    required String scene,
    required String camera,
    required int width,
    required int height,
    required CyclesJob Function() buildJob,
  }) {
    if (!render.available) return false;
    if (!wanted || width < 1 || height < 1) {
      _job = null;
      return render.request(null);
    }
    final key = CyclesKey(scene, camera, width, height);
    if (render.wants(key)) return false;
    final changed = render.request(key);
    // Built here rather than in `pump`, so the cost lands on the frame that
    // already decided the picture is stale — and so a settle timer that never
    // fires (the user kept moving) never paid it.
    _job = buildJob();
    return changed;
  }

  /// Starts the queued render if one is queued and none is running.
  Future<void>? pump() {
    final f = render.pump();
    if (f != null) {
      final j = _job;
      Log.i(
          'cycles',
          'render start ${render.running} '
              '${j == null ? '' : '${j.meshes.length} meshes, ${j.triangles} tris, '}'
              '$_samples spp');
    }
    return f;
  }

  /// What the renderer said about the last attempt, successful or not.
  ///
  /// The device name when it worked, `cy_last_error()` when it did not.
  String get note => _note;
  String _note = '';

  Future<Uint8List?> _render(CyclesKey key) async {
    final j = _job;
    if (j == null) return null;
    final (rgba, note) = await _runner(j);
    _note = note;
    // Logged HERE, on the isolate that has the log file open.
    if (rgba == null) {
      Log.w('cycles', 'render failed: $note');
    } else {
      Log.i('cycles', 'render done on $note (${rgba.length ~/ 1024} KiB)');
    }
    return rgba;
  }

  void reset() {
    _job = null;
    render.reset();
  }
}

Future<CyclesOutcome> _runOnIsolate(CyclesJob job) =>
    Isolate.run(() => renderCyclesJob(job));
