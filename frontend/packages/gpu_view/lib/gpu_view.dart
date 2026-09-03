// M372 — the shaded 3D viewport, for platforms with no RealityKit.
//
// WHAT THIS REPLACES, and why it had to be replaced
// -------------------------------------------------
// Off iOS the viewport fell back to `_ScenePainter`, a CPU painter that sorts
// triangles and fills them into a Flutter canvas. It was written so the app
// would RUN anywhere, and it does that; what it does not do is look like the
// app. There is no depth buffer, so coplanar faces fight; no real lighting,
// so a curved surface reads as flat bands; and every frame is a full sort and
// fill on the UI thread, so an orbit on a real part is not sixty frames a
// second. Next to the iPad it is a different program.
//
// This is that surface on the GPU: flutter_scene, on Flutter GPU, on Impeller.
//
// WHY NOT A PLATFORM VIEW, which is what RealityKit needs
// -------------------------------------------------------
// Because it does not need one. flutter_scene renders inside the Flutter tree,
// which buys three things a texture-interop renderer would each cost work to
// get back: the glass chrome composites OVER it correctly with no platform-view
// seam, the transparent gesture layer above it keeps working exactly as it does
// on iOS, and one implementation covers Linux, Windows and macOS because
// Impeller does.
//
// It also means there is no `isSupported` that can be answered from the
// platform alone: Flutter GPU is a per-project switch (see the runner's
// DartProject), and a build that forgot it has no renderer here. So the answer
// is PROBED once at launch, the same shape `LiquidGlassProgram.load` uses for
// the glass shader, and the caller decides layout from a value that is stable
// from the first frame.
//
// THE CONTRACT IS reality_view's, deliberately. Same three verbs, same payload
// maps, built by the same `reality_scene.dart`. Two renderers, one description
// of what is in the viewport.
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

import 'src/scene_builder.dart';

export 'src/ortho_camera.dart' show OrthographicCamera, OrthographicProjection;

/// Drives one GPU viewport. Obtained from [GpuView] via [GpuView.onCreated].
///
/// Every method is a cheap no-op before the first frame or after disposal, so
/// callers never need a lifecycle check of their own — the same promise
/// RealityViewController makes.
class GpuViewController extends ChangeNotifier {
  GpuViewController._(this._builder);

  final SceneBuilder _builder;
  bool _disposed = false;

  /// Full scene push: solids (meshes and their B-Rep edges), origin planes,
  /// axes, centre point and sketch polylines. Send only when the geometry
  /// actually changed — the app gates this behind a mesh signature so a mere
  /// hover does not rebuild megabytes.
  void setScene(Map<String, dynamic> scene) {
    if (_disposed) return;
    _builder.setScene(scene);
    notifyListeners();
  }

  /// Light push: hover/highlight/visibility only. Safe on every pointer move.
  void setOverlays(Map<String, dynamic> overlays) {
    if (_disposed) return;
    _builder.setOverlays(overlays);
    notifyListeners();
  }

  /// Per-frame camera push. Called on every orbit / pan / zoom step.
  void setCamera(Map<String, dynamic> camera) {
    if (_disposed) return;
    _builder.setCamera(camera);
    notifyListeners();
  }

  /// Stop or restart drawing.
  ///
  /// In rendered mode a path-traced image covers this surface completely, and
  /// every frame under it is a full render nobody sees — on the GPU the path
  /// tracer is already saturating. Paused, the view stops ticking; it keeps
  /// applying scenes and cameras, so the frame after a resume is current.
  void setPaused(bool paused) {
    if (_disposed || _paused == paused) return;
    _paused = paused;
    notifyListeners();
  }

  bool get paused => _paused;
  bool _paused = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The viewport surface.
class GpuView extends StatefulWidget {
  const GpuView({
    super.key,
    required this.placeholder,
    required this.onCreated,
  });

  /// Shown until the first scene arrives, and forever on a build where the
  /// probe failed. The app passes its viewport ground colour.
  final Widget placeholder;
  final void Function(GpuViewController) onCreated;

  /// Whether this build can render here.
  ///
  /// False until [probe] has run, and false forever where Flutter GPU is off
  /// or absent. Synchronous and stable from the first frame ONCE probed, which
  /// is the property callers need: they use it to decide layout, and a layout
  /// that changes when a capability resolves is a layout that jumps at launch.
  static bool get isSupported => _supported;
  static bool _supported = false;
  static bool _probed = false;

  /// Asks, once, whether Flutter GPU is actually available in this process.
  ///
  /// Not a platform test. Flutter GPU is switched on per project — on desktop
  /// through the `DartProject` the runner builds — so the honest question is
  /// "can I get a GPU context", and the honest way to ask it is to try. A
  /// build that ships without the switch gets the painted fallback and a log
  /// line, rather than a black viewport.
  ///
  /// SYNCHRONOUS, and that is the point: the caller asks before the first
  /// frame, from a `main()` that is not async, and gets an answer that never
  /// changes afterwards. An asynchronous probe would resolve a frame or two in
  /// and take the viewport's layout with it. Needs the binding to be
  /// initialised; nothing else.
  static bool probe() {
    if (_probed) return _supported;
    _probed = true;
    if (kIsWeb) return _supported = false;
    if (_disabledByEnv) return _supported = false;
    try {
      // Allocating something is what fails when the embedder was not built
      // with Flutter GPU enabled; merely naming the context does not. One
      // 4-byte buffer, freed by the collector immediately after.
      gpu.gpuContext.createDeviceBuffer(gpu.StorageMode.hostVisible, 4);
      _supported = true;
    } catch (_) {
      _supported = false;
    }
    return _supported;
  }

  /// `PROTOTYPE_GPU=0` turns this renderer off and leaves the CPU painter.
  ///
  /// A real escape hatch, the same one the glass material has: a machine whose
  /// driver is a software rasteriser is better served by the painter than by a
  /// correct GPU renderer at four frames a second, and the choice is about the
  /// MACHINE rather than about the document, which is why there is no setting
  /// for it. It is also how the two renderers get compared — one build, one
  /// document, one variable.
  static final bool _disabledByEnv = _setting() == '0';

  static String _setting() {
    const compiled = String.fromEnvironment('PROTOTYPE_GPU');
    if (compiled.isNotEmpty) return compiled;
    try {
      return io.Platform.environment['PROTOTYPE_GPU'] ?? '';
    } catch (_) {
      return ''; // web, where there is no environment to read
    }
  }

  /// Tests only, so a case cannot inherit another's answer.
  @visibleForTesting
  static void setSupportedForTest(bool value) {
    _probed = true;
    _supported = value;
  }

  @override
  State<GpuView> createState() => _GpuViewState();
}

class _GpuViewState extends State<GpuView> {
  late final Scene _scene;
  late final SceneBuilder _builder;
  late final GpuViewController _controller;

  @override
  void initState() {
    super.initState();
    _scene = Scene();
    _builder = SceneBuilder(_scene);
    _controller = GpuViewController._(_builder);
    // After the first frame, for the same reason RealityView defers it: the
    // caller sets state from here, and a setState during build is an error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreated(_controller);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!GpuView.isSupported) return widget.placeholder;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final camera = _builder.camera;
        // No camera yet means no scene yet: the first setCamera arrives in the
        // same frame as the first setScene, and drawing an empty graph through
        // a default camera would flash the clear colour.
        if (camera == null) return widget.placeholder;
        return SceneView(
          _scene,
          camera: camera,
          // The scene changes only when the app pushes, and the app pushes on
          // every camera move — so a per-frame tick would be a full redraw of
          // a still picture between pushes. Paused it stops entirely, which is
          // what rendered mode wants.
          autoTick: !_controller.paused,
        );
      },
    );
  }
}
