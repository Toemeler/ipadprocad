// M367 — every sample, a target you can set, and a denoise at the end.
//
// THE REPORT, in three parts:
//
//   "In Blender I see gradually how it renders. Here I see steps. Like sample
//    24, then 50, then 100. I want to see every sample. In the settings I want
//    to be able to set the max sample count. And when this is reached it
//    should denoise, with the same denoiser Blender uses."
//
// plus, separately: "the render info bottom right is currently behind a liquid
// glass button".
//
// ---------------------------------------------------------------------------
// WHAT IS CHECKED HERE AND WHAT CANNOT BE
// ---------------------------------------------------------------------------
//
// The stepping itself is Cycles' RenderScheduler, and the fix is three lines
// of C++ that backend/cycles/patches/progressive.py adds to it. Nothing in
// Dart can observe that, and nothing here pretends to: the sample-by-sample
// arrival is checked where it happens, by render_test.c, which runs a live
// session on a macOS runner and fails if a whole render arrived as one batch.
//
// What IS Dart's, and what these tests hold:
//
//   * the sample target is a SETTING, with a default and a ladder, that
//     survives a restart and refuses a value it does not offer;
//   * the whole path from that setting to what the renderer is asked for —
//     the frame budget, the session's target — carries the number through
//     rather than reading a constant halfway down;
//   * the Settings screen actually offers it, in rows whose ids the handler
//     can turn back into numbers;
//   * the badge clears the floating tab bar's glass.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_live.dart';
import 'package:prototype/cycles_render.dart';
import 'package:prototype/cycles_session.dart';
import 'package:prototype/cycles_view.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/render_samples.dart';
import 'package:prototype/settings.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/bottom_tabbar.dart';
import 'package:prototype/widgets/cycles_layer.dart';

/// Records what the session asked the renderer for. The same shape the M354
/// and M355 tests use, so the three read alike.
class _Rec implements CyclesDriver {
  final List<int> viewSamples = [];

  @override
  set onFrame(void Function(CyclesLiveFrame) fn) {}
  @override
  set onNote(void Function(String, bool) fn) {}
  @override
  void open() {}
  @override
  void setPaused(bool paused) {}
  @override
  void close() {}
  @override
  void setScene(List<CyclesMesh> meshes, CyclesEnv env, int epoch) {}

  @override
  void setView({
    required List<double> matrix,
    required double halfWidth,
    required double halfHeight,
    required int width,
    required int height,
    required int samples,
  }) {
    viewSamples.add(samples);
  }
}

CyclesScene _scene() =>
    const CyclesScene(meshes: [], env: CyclesEnv(), reach: 10);

CyclesViewParams _view(CyclesScene s) => CyclesViewParams(
      matrix: List<double>.filled(12, 0),
      halfWidth: 10,
      halfHeight: 8,
    );

void main() {
  setUp(RenderSamples.resetForTest);
  tearDown(RenderSamples.resetForTest);

  group('the target is a setting', () {
    test('128 out of the box, and the old constant agrees with it', () {
      // The two names exist because one is the SETTING's default and the other
      // is the renderer's fallback, and they must not be allowed to drift: a
      // build where cyclesFrameBudget defaulted to 4096 while Settings showed
      // 128 would render for a minute with a tick in the wrong row.
      expect(kRenderSamplesDefault, 128);
      expect(kCyclesSamples, kRenderSamplesDefault);
      expect(RenderSamples.current, 128);
    });

    test('the ladder is doublings, includes the default, and is sorted', () {
      expect(kRenderSampleChoices, contains(kRenderSamplesDefault));
      expect(kRenderSampleChoices.first, lessThan(kRenderSampleChoices.last));
      for (var i = 1; i < kRenderSampleChoices.length; i++) {
        expect(kRenderSampleChoices[i],
            greaterThan(kRenderSampleChoices[i - 1]),
            reason: 'the ladder has to climb, or the tick moves backwards');
      }
      // 4096 was the constant this setting replaced (M353, Blender's own
      // final-render default). Anyone who wants the old behaviour has to be
      // able to ask for it.
      expect(kRenderSampleChoices, contains(4096));
    });

    test('a value off the ladder is refused rather than clamped', () {
      RenderSamples.set(137);
      expect(RenderSamples.current, kRenderSamplesDefault,
          reason: 'quietly rounding would hide whether the caller or the '
              'stored file was wrong');
      RenderSamples.set(512);
      expect(RenderSamples.current, 512);
    });

    test('it notifies, because the viewport listens for it', () {
      var fired = 0;
      void bump() => fired++;
      RenderSamples.samples.addListener(bump);
      addTearDown(() => RenderSamples.samples.removeListener(bump));
      RenderSamples.set(256);
      expect(fired, 1);
      // Setting the value it already has must not restart a render.
      RenderSamples.set(256);
      expect(fired, 1);
    });
  });

  group('it survives a restart', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('m367');
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('written to settings.json and read back', () {
      RenderSamples.attachStore(RenderSamplesStore(dir));
      RenderSamples.set(512);

      RenderSamples.resetForTest();
      expect(RenderSamples.current, kRenderSamplesDefault);
      RenderSamples.attachStore(RenderSamplesStore(dir));
      expect(RenderSamples.current, 512);
    });

    test('it MERGES into the file rather than owning it', () {
      // The same rule every other preference in this file follows. A store
      // that rewrote settings.json wholesale would drop the appearance, the
      // language and the ribbon dock the first time somebody changed the
      // sample count.
      final f = File('${dir.path}/${RenderSamplesStore.fileName}');
      f.writeAsStringSync(jsonEncode({'renderer': 'cycles', 'ribbon': 'left'}));
      RenderSamples.attachStore(RenderSamplesStore(dir));
      RenderSamples.set(256);
      final back = jsonDecode(f.readAsStringSync()) as Map;
      expect(back['renderer'], 'cycles');
      expect(back['ribbon'], 'left');
      expect(back[RenderSamplesStore.key], 256);
    });

    test('a stored value this build no longer offers falls back', () {
      // A file written by a build with a different ladder. Adopting a value
      // that has no row would put a setting on screen with nothing ticked.
      File('${dir.path}/${RenderSamplesStore.fileName}')
          .writeAsStringSync(jsonEncode({RenderSamplesStore.key: 3}));
      RenderSamples.attachStore(RenderSamplesStore(dir));
      expect(RenderSamples.current, kRenderSamplesDefault);
    });

    test('a corrupt file costs the setting and not the launch', () {
      File('${dir.path}/${RenderSamplesStore.fileName}')
          .writeAsStringSync('{ this is not json');
      expect(() => RenderSamples.attachStore(RenderSamplesStore(dir)),
          returnsNormally);
      expect(RenderSamples.current, kRenderSamplesDefault);
    });
  });

  group('the number reaches the renderer', () {
    test('the frame budget carries the settled target through', () {
      // The one place the two halves of a render request are decided together
      // (M347). A settled frame gets whatever was asked for; a moving one is
      // still capped, because the orbit budget is about contention and has
      // nothing to do with how good the settled picture should be.
      final still = cyclesFrameBudget(800, 600, 2.0,
          moving: false, settled: 512);
      expect(still.samples, 512);

      final moving = cyclesFrameBudget(800, 600, 2.0,
          moving: true, settled: 512);
      expect(moving.samples, kCyclesMovingSamples);
    });

    test('a caller that does not care still gets the default', () {
      expect(cyclesFrameBudget(800, 600, 2.0, moving: false).samples,
          kRenderSamplesDefault);
    });

    test('the session pushes the target it was offered', () {
      final d = _Rec();
      final s = CyclesSession(available: true, driver: d);
      s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: 800,
        height: 600,
        buildScene: _scene,
        buildView: _view,
        samples: 256,
      );
      expect(d.viewSamples.single, 256);
      expect(s.target, 256);
    });

    test('changing the setting is a new request, not the same one', () {
      // The key a session compares includes the target, so a settings change
      // has to restart sampling. If it did not, the number in the badge and
      // the number the tracer is working towards would disagree until the
      // camera happened to move.
      const a = CyclesKey('s', 'c', 800, 600, 128);
      const b = CyclesKey('s', 'c', 800, 600, 512);
      expect(a == b, isFalse);
    });
  });

  group('the Settings screen offers it', () {
    test('one section, one row per rung, exactly one tick', () {
      final spec = buildSettings(L.stringsFor(const Locale('en')),
          mode: AppThemeMode.system,
          locale: const Locale('en'),
          info: const SettingsInfo(
              build: 'b', kernel3d: 'k', kernel2d: 'k', system: 's'),
          samples: 512);
      final sec = spec.firstWhere((s) => s.id == kSecSamples);
      expect(sec.rows.length, kRenderSampleChoices.length);
      expect(sec.rows.where((r) => r.selected).length, 1);
      expect(sec.rows.firstWhere((r) => r.selected).id, '512');
      expect(sec.header, isNotNull);
      expect(sec.footer, isNotNull);
    });

    test('every row id parses back to a rung the setting accepts', () {
      // The handler does `int.tryParse(row)` and hands the result to
      // RenderSamples.set, which refuses anything off the ladder. A row whose
      // id did not round-trip would be a tick that never moves.
      final spec = buildSettings(L.stringsFor(const Locale('en')),
          mode: AppThemeMode.system,
          locale: const Locale('en'),
          info: const SettingsInfo(
              build: 'b', kernel3d: 'k', kernel2d: 'k', system: 's'));
      final sec = spec.firstWhere((s) => s.id == kSecSamples);
      for (final r in sec.rows) {
        final n = int.tryParse(r.id);
        expect(n, isNotNull, reason: 'row ${r.id} is not a number');
        expect(kRenderSampleChoices, contains(n));
        RenderSamples.set(n!);
        expect(RenderSamples.current, n);
      }
    });

    test('every row is a check row and none of them is destructive', () {
      final spec = buildSettings(L.stringsFor(const Locale('en')),
          mode: AppThemeMode.system,
          locale: const Locale('en'),
          info: const SettingsInfo(
              build: 'b', kernel3d: 'k', kernel2d: 'k', system: 's'));
      final sec = spec.firstWhere((s) => s.id == kSecSamples);
      for (final r in sec.rows) {
        expect(r.kind, SettingsRowKind.check);
        expect(r.destructive, isFalse);
        expect(r.title, isNotEmpty);
      }
    });

    test('and it is named in both languages, not spelled in one', () {
      final en = buildSettings(L.stringsFor(const Locale('en')),
              mode: AppThemeMode.system,
              locale: const Locale('en'),
              info: const SettingsInfo(
                  build: 'b', kernel3d: 'k', kernel2d: 'k', system: 's'))
          .firstWhere((s) => s.id == kSecSamples);
      final de = buildSettings(L.stringsFor(const Locale('de')),
              mode: AppThemeMode.system,
              locale: const Locale('de'),
              info: const SettingsInfo(
                  build: 'b', kernel3d: 'k', kernel2d: 'k', system: 's'))
          .firstWhere((s) => s.id == kSecSamples);
      expect(en.header, isNot(de.header));
      expect(en.footer, isNot(de.footer));
    });
  });

  group('the badge is not under the glass', () {
    test('it clears a floating tab bar of any height', () {
      // The bug: `bottom: 12` is the bottom of the VIEWPORT, and the tab bar
      // floats over that — with a glass "island" button pinned to its right
      // end, in the same corner the badge sits in.
      expect(cyclesBadgeBottom(BottomTabBar.kNativeHeight),
          greaterThan(BottomTabBar.kNativeHeight));
      expect(cyclesBadgeBottom(BottomTabBar.kNativeHeight),
          BottomTabBar.kNativeHeight + kCyclesBadgeGap);
    });

    test('and keeps its old corner where there is no floating bar', () {
      // Off iOS the bar has its own row in the Column and the viewport already
      // stops above it, so nothing should move.
      expect(cyclesBadgeBottom(0), kCyclesBadgeGap);
      expect(kCyclesBadgeGap, 12);
    });
  });
}
