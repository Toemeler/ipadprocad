// iPadProCAD — RealityKit viewport surface for Flutter (M60).
//
// This package is deliberately DOMAIN-FREE: it knows nothing about parts,
// sketches or OCCT. It exposes one platform view and a small controller with
// three verbs — setScene / setOverlays / setCamera — that take already-built
// payload maps. The app (lib/reality_scene.dart) is what maps PartModel onto
// these payloads, so the RealityKit surface can be reused and unit-tested in
// isolation from the CAD model.
//
// WHY A PLATFORM VIEW (and how gestures still stay in Dart)
// ---------------------------------------------------------
// RealityKit draws into an ARView, which is a UIView. Flutter can only embed a
// UIView through a platform view. We host the ARView with user interaction
// DISABLED, so it never competes for touches: a transparent Flutter gesture
// layer stacked ON TOP receives every pointer exactly as before. The platform
// view is a pure output surface — all camera/pick logic remains in Dart.
//
// The channel name mirrors native_menu's convention: `ipadprocad/<plugin>`.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const String _viewType = 'ipadprocad/reality_view';
const String _channelName = 'ipadprocad/reality_view';

/// Drives one RealityKit viewport. Obtained from [RealityView] via
/// [RealityView.onCreated]. Every method is a fire-and-forget push to native;
/// they are cheap no-ops when the platform view is not available (host tests,
/// non-iOS) so callers never need a platform check of their own.
class RealityViewController {
  RealityViewController._(int id)
      : _channel = MethodChannel('$_channelName/$id');
  final MethodChannel _channel;
  bool _disposed = false;

  /// Full scene push: solids (meshes), origin planes/axes/centre point and
  /// sketch polylines. Send only when the geometry actually changed — the app
  /// gates this behind a mesh signature so a mere hover does not re-upload
  /// megabytes. Payload shape is documented in lib/reality_scene.dart.
  Future<void> setScene(Map<String, dynamic> scene) =>
      _invoke('setScene', scene);

  /// Light push: hover/highlight/visibility booleans only (no mesh data). Safe
  /// to call on every pointer move.
  Future<void> setOverlays(Map<String, dynamic> overlays) =>
      _invoke('setOverlays', overlays);

  /// Per-frame camera push (a handful of doubles). Called on every orbit / pan
  /// / zoom step; the native side reconstructs the orthographic camera so the
  /// RealityKit picture stays locked to the Flutter ViewCube and triad.
  Future<void> setCamera(Map<String, dynamic> camera) =>
      _invoke('setCamera', camera);

  Future<void> _invoke(String method, Map<String, dynamic> args) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native side (host test / non-iOS): silently ignore.
    } catch (e) {
      // Never let a rendering push crash the app; the CPU fallback still runs.
      if (kDebugMode) debugPrint('RealityView.$method failed: $e');
    }
  }

  void _dispose() => _disposed = true;
}

/// A RealityKit 3D viewport. On iOS this embeds an ARView; everywhere else it
/// renders [placeholder] (host tests, web, desktop) so the widget tree is
/// identical and callers can keep a CPU fallback behind the same slot.
class RealityView extends StatefulWidget {
  const RealityView({
    super.key,
    required this.onCreated,
    this.placeholder = const SizedBox.shrink(),
  });

  /// Fires once the platform view exists, handing back its controller.
  final void Function(RealityViewController controller) onCreated;

  /// Shown when no RealityKit surface is available (non-iOS).
  final Widget placeholder;

  /// True only where the native RealityKit platform view can be created.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<RealityView> createState() => _RealityViewState();
}

class _RealityViewState extends State<RealityView> {
  RealityViewController? _controller;

  @override
  void dispose() {
    _controller?._dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!RealityView.isSupported) return widget.placeholder;
    return UiKitView(
      viewType: _viewType,
      creationParams: const <String, dynamic>{},
      creationParamsCodec: const StandardMessageCodec(),
      // gestureRecognizers defaults to empty: the platform view claims no
      // gestures, so every pointer flows to the Flutter Listener/GestureDetector
      // stacked above it (the ARView also has interaction disabled natively).
      onPlatformViewCreated: (id) {
        final c = RealityViewController._(id);
        _controller = c;
        widget.onCreated(c);
      },
    );
  }
}
