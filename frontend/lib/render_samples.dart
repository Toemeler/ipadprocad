// M367 — HOW MANY SAMPLES A PATH-TRACED FRAME GETS, as a setting.
//
// ---------------------------------------------------------------------------
// WHY IT IS A SETTING AT ALL
// ---------------------------------------------------------------------------
//
// It used to be a constant, and the constant was 4096 — Blender's own
// final-render default, chosen (M353) so that "the path tracer is never the
// reason a render stopped looking better". That reasoning is sound about the
// CEILING and says nothing about the WAIT, and the wait is what a person
// standing in front of an iPad experiences: sampling now arrives one sample at
// a time and the image visibly improves the whole way, so the number decides
// how long the picture keeps changing before it settles and the GPU goes
// quiet.
//
// Nobody can pick that for somebody else. A quick look while modelling wants
// tens of samples; a shot to show a client wants hundreds and is worth waiting
// for. So it is the user's, and it sits in Settings beside the other choices
// that outlive the document.
//
// ---------------------------------------------------------------------------
// WHY 128 IS THE DEFAULT
// ---------------------------------------------------------------------------
//
// Because the render is DENOISED at the end now, and that changes the
// arithmetic completely.
//
// Without a denoiser, the only thing standing between a path trace and a clean
// image is samples, and the count has to be high enough to bury the noise —
// which is where 4096 came from. With one, the samples only have to get the
// image close enough for the denoiser to finish it, and for a studio-lit CAD
// scene of opaque solids that happens in the low hundreds. Everything past
// that is time spent on a difference the denoiser was going to remove anyway.
//
// 128 is also roughly where adaptive sampling stops finding work on a scene
// like this: flat lit faces are done in tens of samples and only the contact
// shadows and glossy reflections spend the rest, so a typical render reaches
// its own convergence and stops before the ceiling. The ceiling matters for
// the scenes that do not.
//
// ---------------------------------------------------------------------------
// AND WHY IT IS NOT A DOCUMENT SETTING
// ---------------------------------------------------------------------------
//
// The same argument render_engine.dart makes for the renderer choice: how hard
// this machine should work on a picture is a fact about the machine and about
// what you are doing right now, not about the part. A document carrying "4096
// samples" would impose a minute of somebody else's iPad on every person who
// opened it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log.dart';

/// The settled sample target a fresh install renders with.
///
/// See the note above for why it is 128 and not the 4096 it replaced. It is
/// also the value every existing caller falls back to, which is why it is a
/// plain `const` rather than the first entry of [kRenderSampleChoices].
const int kRenderSamplesDefault = 128;

/// What the Settings screen offers.
///
/// A LADDER, NOT A FIELD. The settings sheet is a list of rows with a tick —
/// there is no numeric entry in it, and inventing one for this would be a
/// keyboard on a screen that has never needed one. A ladder is also the
/// honest shape of the choice: sample counts are useful in doublings, and
/// nobody wants 137.
///
/// It stops at 4096 because that is Blender's own final-render default and
/// the value this setting replaced; there is no argument for offering more on
/// a tablet, and adaptive sampling means a scene that would use it has almost
/// certainly stopped on its own long before.
const List<int> kRenderSampleChoices = <int>[32, 64, 128, 256, 512, 1024, 4096];

/// The live setting, as something the viewport can listen to.
///
/// Mirrors [RenderEngines] exactly — a ValueNotifier the layer watches, plus a
/// store attached once the documents directory is known. Before that the
/// choice still WORKS, it simply is not remembered.
class RenderSamples {
  RenderSamples._();

  static final ValueNotifier<int> samples =
      ValueNotifier<int>(kRenderSamplesDefault);

  static int get current => samples.value;

  static RenderSamplesStore? _store;

  /// Point the setting at a settings file and adopt whatever it remembers.
  ///
  /// Called from [AppState.init], off the launch path, for the same reason
  /// [RenderEngines.attachStore] is.
  static void attachStore(RenderSamplesStore store) {
    _store = store;
    final saved = store.load();
    if (saved != null) samples.value = saved;
  }

  /// Change the target, and remember it.
  ///
  /// Anything not in [kRenderSampleChoices] is REFUSED rather than clamped. A
  /// value that arrives here comes from a settings row id or from a stored
  /// file, and both of those are ladder entries; a number that is neither is a
  /// bug or a hand-edited file, and quietly rounding it would hide which.
  static void set(int n) {
    if (!kRenderSampleChoices.contains(n)) return;
    if (n == samples.value) return;
    samples.value = n;
    _store?.save(n);
    Log.i('view', 'cycles samples = $n');
  }

  @visibleForTesting
  static void resetForTest() {
    samples.value = kRenderSamplesDefault;
    _store = null;
  }
}

/// Where the choice survives a restart.
///
/// The same file, the same shape and the same swallow-the-error rule as
/// [RenderEngineStore]: it merges into `settings.json` rather than owning it,
/// so the preferences sitting beside it are never dropped.
class RenderSamplesStore {
  final Directory dir;
  const RenderSamplesStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'renderSamples';

  File get file => File('${dir.path}/$fileName');

  int? load() {
    try {
      final f = file;
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return null;
      final v = raw[key];
      // Stored as a number, checked against the ladder on the way back in: a
      // file written by an older build with a value this one no longer offers
      // must fall back to the default rather than putting a setting on screen
      // that has no row to carry its tick.
      if (v is! int || !kRenderSampleChoices.contains(v)) return null;
      return v;
    } catch (e) {
      // A corrupt settings file costs a sample count and nothing else. It must
      // not cost the launch.
      Log.w('view', 'could not read the sample setting: $e');
      return null;
    }
  }

  void save(int n) {
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
      data[key] = n;
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('view', 'could not remember the sample setting: $e');
    }
  }
}
