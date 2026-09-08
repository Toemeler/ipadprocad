// M340 — WHICH RENDERER DRAWS THE RENDERED VIEW, as a value rather than a
// widget.
//
// The app has two of them now. One draws every frame, on the GPU — RealityKit
// through a platform view on iOS, flutter_scene on Flutter GPU everywhere else
// — and Cycles path-traces one image when the camera stops and lays it over
// the top.
//
// M404 — WHICH real-time renderer is a fact about the platform, not a choice
// (#36: "on windows there is still the option reality kit or cycles but
// reality kit doesnt exist at all on windows"). The choice is between drawing
// every frame and path-tracing one; the enum below is named for that now, and
// the label says which engine is doing the drawing here. They are not a progression from worse to
// better — they answer different questions. RealityKit is instant and follows
// you through an orbit; Cycles is seconds of work and knows about bounced
// light, contact shadows and a real specular response. Which one you want
// depends on whether you are LOOKING at the model or SHOWING it.
//
// So it is a choice, and the user makes it.
//
// ---------------------------------------------------------------------------
// WHY IT IS NOT A DOCUMENT SETTING
// ---------------------------------------------------------------------------
//
// The floor toggle sits next to this one in the ribbon and IS remembered in
// the document, because whether a part is presented standing on a ground plane
// is a fact about how you want that part shown. Which renderer draws it is
// not. It is a fact about the machine and about what you are doing right now,
// and a document that carried "use Cycles" would force a path tracer onto a
// device whose kernels have not been compiled — or, worse, onto a build that
// has no Cycles in it at all.
//
// It is remembered app-wide instead, in settings.json beside the ribbon
// position and the appearance. That is also what somebody comparing the two
// actually wants: pick one, and it stays picked as you move between documents.
//
// ---------------------------------------------------------------------------
// AND WHY IT IS HERE RATHER THAN IN settings.dart
// ---------------------------------------------------------------------------
//
// settings.dart states its own rule: what belongs in the Settings screen is a
// choice that outlives the document, and what does not belong is anything that
// reaches into the open drawing — "a preference screen that reaches into the
// open drawing is a second, competing ribbon". This is both at once: it
// outlives the document, and it changes what the viewport is doing this
// second. The CONTROL therefore goes in the ribbon, next to the display mode
// it only makes sense underneath; the VALUE is stored app-wide. This file is
// the value, its store and the switch, in the shape ribbon_dock.dart uses for
// exactly the same split.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gpu_view/gpu_view.dart' show GpuView;
import 'package:reality_view/reality_view.dart' show RealityView;

import 'log.dart';

/// Which renderer draws the rendered view.
enum RenderEngine {
  /// Every frame, follows the camera, no path tracing. RealityKit on iOS,
  /// flutter_scene on Flutter GPU elsewhere — see [realtimeEngineName].
  realtime,

  /// Cycles. One path-traced image once the camera settles.
  cycles;

  /// The stored id. The enum's own `name` would do until somebody renames a
  /// value and every saved setting silently reverts, which is the same reason
  /// [RibbonPosition] and [Accent] spell theirs out.
  /// M404 — the real-time engine's stored id KEEPS its old spelling. It is a
  /// storage key, every settings.json in the field already holds it, and
  /// renaming it would silently reset everybody's choice to the default.
  String get id => switch (this) {
        RenderEngine.realtime => 'realitykit',
        RenderEngine.cycles => 'cycles',
      };

  static RenderEngine? byId(Object? s) {
    for (final e in RenderEngine.values) {
      if (e.id == s) return e;
    }
    return null;
  }
}

/// RealityKit, which is what every build before Cycles did and what a device
/// with no compiled kernels falls back to anyway.
///
/// Deliberately NOT Cycles even where Cycles is available. Rendered mode has
/// to stay instant by default: a first switch into it that hangs for thirty
/// seconds compiling Metal kernels is not a better picture, it is a broken
/// mode. Cycles is something you ask for.
const RenderEngine kRenderEngineDefault = RenderEngine.realtime;

/// M404 — the name of the engine that actually draws the real-time view in
/// THIS build, or null where nothing has a name worth showing.
///
/// The viewport picks its surface with exactly this test (see the M372 note in
/// viewport3d.dart): RealityKit where it exists, flutter_scene on Flutter GPU
/// where that probe succeeded, and the CPU painter otherwise. The label has to
/// ask the same question, or it goes on naming a renderer that is not in the
/// build — which is what #36 saw on Windows, where the picker offered
/// "RealityKit" for a view flutter_scene had been drawing all along.
String? realtimeEngineName() {
  if (RealityView.isSupported) return 'RealityKit';
  if (GpuView.isSupported) return 'Flutter GPU';
  return null;
}

/// The live setting, as something the viewport can listen to.
///
/// Mirrors [RibbonDock] and [Backdrops]: a ValueNotifier the layer watches,
/// plus a store attached once the documents directory is known. Before that
/// the choice still WORKS, it simply is not remembered.
class RenderEngines {
  RenderEngines._();

  static final ValueNotifier<RenderEngine> engine =
      ValueNotifier<RenderEngine>(kRenderEngineDefault);

  static RenderEngine get current => engine.value;
  static bool get isCycles => current == RenderEngine.cycles;
  static bool get isRealtime => current == RenderEngine.realtime;

  static RenderEngineStore? _store;

  /// Point the switch at a settings file and adopt whatever it remembers.
  ///
  /// Called from [AppState.init], off the launch path, for the same reason
  /// [T.attachStore] is.
  static void attachStore(RenderEngineStore store) {
    _store = store;
    final saved = store.load();
    if (saved != null) engine.value = saved;
  }

  /// Switch renderer, and remember it.
  static void set(RenderEngine e) {
    if (e == engine.value) return;
    engine.value = e;
    _store?.save(e);
    Log.i('view', 'renderer = ${e.id}');
  }

  @visibleForTesting
  static void resetForTest() {
    engine.value = kRenderEngineDefault;
    _store = null;
  }
}

/// Where the choice survives a restart.
///
/// The same file, the same shape and the same swallow-the-error rule as
/// [RibbonStore]: it merges into `settings.json` rather than owning it, so the
/// preferences sitting beside it are never dropped.
class RenderEngineStore {
  final Directory dir;
  const RenderEngineStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'renderer';

  File get file => File('${dir.path}/$fileName');

  RenderEngine? load() {
    try {
      final f = file;
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return null;
      return RenderEngine.byId(raw[key]);
    } catch (e) {
      // A corrupt settings file costs a renderer preference and nothing else.
      // It must not cost the launch.
      Log.w('view', 'could not read the renderer setting: $e');
      return null;
    }
  }

  void save(RenderEngine e) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      Map<String, Object?> data = <String, Object?>{};
      final f = file;
      if (f.existsSync()) {
        final raw = jsonDecode(f.readAsStringSync());
        if (raw is Map) {
          data = <String, Object?>{
            for (final e in raw.entries) '${e.key}': e.value
          };
        }
      }
      data[key] = e.id;
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('view', 'could not remember the renderer setting: $e');
    }
  }
}
