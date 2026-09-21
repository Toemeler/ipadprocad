// #57 / #64 — the gallery still, drawn by the same renderer as the viewport.
//
//   "on windows the preview image isnt done with the Flutter GPU. It is done
//    with the cpu painter. change this."
//   "the preview images in windows are still not made with flutter gpu 3d
//    renderer"
//
// M82 settled the principle — ONE ENGINE: the still is produced by whatever
// draws the live viewport, so a body looks on the card exactly as it looks in
// the viewport. It only ever had two engines to choose between, RealityKit and
// the Dart CPU painter, and off iOS that meant the painter. M372 then gave the
// viewport a third (flutter_scene, on Flutter GPU) and the still did not
// follow: on Windows the viewport went to the GPU and the card stayed on the
// painter, so the same part was drawn twice by two renderers that disagree
// about depth, lighting and silhouette. That is the report, and it is the
// principle M82 wrote down, not a new one.
//
// The whole of it is that `Scene.render` takes a `ui.Canvas`. A recorder is a
// canvas, so the still is the same three verbs the live view is driven with
// (setScene / setCamera / render) aimed at a `PictureRecorder` instead of at
// the screen — no render-to-texture, no platform view, no second description
// of what is in the scene.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

import '../gpu_view.dart' show GpuView;
import 'scene_builder.dart';

/// Renders one off-screen still with the Flutter GPU renderer.
///
/// The contract is [RealityThumbnailer]'s, deliberately: same named
/// parameters, same payload maps, and **null rather than a throw** whenever
/// this build cannot draw — so a caller stays a straight line of preferences
/// ending at the CPU painter, and a GPU that cannot produce a still costs a
/// nicer picture rather than the picture.
abstract final class GpuThumbnailer {
  /// PNG bytes for [scene] seen through [camera], or null.
  ///
  /// Null when Flutter GPU is not available in this build (the same probe the
  /// viewport decides its own layout from), when the payload carries no
  /// camera, or when anything at all goes wrong: a still is decoration, and
  /// it must never be able to take a save down with it.
  static Future<Uint8List?> render({
    required Map<String, dynamic> scene,
    required Map<String, dynamic> camera,
    required int width,
    required int height,
  }) async {
    if (!GpuView.isSupported) return null;
    if (width <= 0 || height <= 0) return null;

    ui.Picture? picture;
    ui.Image? image;
    try {
      // Pipelines and the shader library, once per process. `renderViews`
      // does NOT wait on this — it prints "not ready to render" and returns,
      // leaving a blank canvas — so the await is what separates a still from
      // an empty PNG on the first save after launch.
      await Scene.initializeStaticResources();

      final s = Scene();
      final builder = SceneBuilder(s);
      // Order matters the way it does for the live view: the camera's depth
      // bracket is computed from the extent the scene push measured (M409),
      // so the scene goes in first.
      builder.setScene(scene);
      builder.setCamera(camera);
      final cam = builder.camera;
      if (cam == null) return null;

      final w = width.toDouble(), h = height.toDouble();
      final area = ui.Rect.fromLTWH(0, 0, w, h);
      final recorder = ui.PictureRecorder();
      // `region` explicitly, rather than letting it fall out of the canvas's
      // local clip: a recorder with no clip reports an effectively infinite
      // one, and the scene would size its off-screen target from that.
      s.render(cam, ui.Canvas(recorder, area), viewport: area, pixelRatio: 1);

      picture = recorder.endRecording();
      image = await picture.toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (e) {
      // M372's probe answers "is Flutter GPU switched on", which is not the
      // same question as "can this driver encode an off-screen pass". A
      // machine that answers yes to the first and fails the second gets the
      // painter, and says so once rather than losing its stills silently.
      debugPrint('GpuThumbnailer: no still — $e');
      return null;
    } finally {
      image?.dispose();
      picture?.dispose();
    }
  }
}
