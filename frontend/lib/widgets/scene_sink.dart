// Prototype — one render surface's verbs, whichever surface this build has
// (M372).
//
// The 3D viewports drive RealityKit on iOS and flutter_scene everywhere else,
// and both take the SAME three payload maps, built by the same
// reality_scene.dart. That is deliberate: two descriptions of what is in the
// viewport would drift, and the drift would show up as "the Linux build draws
// it differently", which is the whole thing this port is not allowed to be.
//
// So the push is written once against this, and the build picks the surface.
import 'package:gpu_view/gpu_view.dart';
import 'package:reality_view/reality_view.dart';

/// One render surface's verbs, so the push does not have to know which.
///
/// Four closures rather than an interface both packages implement: reality_view
/// speaks to a UIKit platform view and gpu_view draws inside the Flutter tree,
/// they have nothing in common but this, and making them share a base class
/// would make each one depend on the other's platform.
class SceneSink {
  final void Function(Map<String, dynamic>) setScene;
  final void Function(Map<String, dynamic>) setOverlays;
  final void Function(Map<String, dynamic>) setCamera;
  final void Function(bool) setPaused;

  const SceneSink({
    required this.setScene,
    required this.setOverlays,
    required this.setCamera,
    required this.setPaused,
  });

  factory SceneSink.reality(RealityViewController c) => SceneSink(
        setScene: c.setScene,
        setOverlays: c.setOverlays,
        setCamera: c.setCamera,
        setPaused: c.setPaused,
      );

  factory SceneSink.gpu(GpuViewController c) => SceneSink(
        setScene: c.setScene,
        setOverlays: c.setOverlays,
        setCamera: c.setCamera,
        setPaused: c.setPaused,
      );
}
