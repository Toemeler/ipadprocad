// M389 — "the ribbon should on windows go all the way up not stop on the top
// bar".
//
// Windows has no system caption: `flutter_window.cpp` answers WM_NCCALCSIZE
// with the whole window as client area, and `WindowTitleBar` draws the drag
// strip and the three buttons that stand in for one. main.dart put that strip
// in a Column ABOVE everything — a 32-point row across the full width — so on
// the dock the app actually ships with (left) the ribbon rail began 32 points
// down, with a bare band of ground colour over the top of it that exists on no
// other platform. On the iPad the band starts at the top of the screen.
//
// The strip is [RibbonDockLayout.caption] now and takes a row of the STAGE —
// the box that already excludes the band. That is the whole change, and it is
// two claims:
//
//   * the band reaches the window's top edge;
//   * nothing else moved. Everything inside the stage (the model browser, the
//     quick tools, the gallery) is laid out under the strip exactly as it was
//     under the old row, so no panel gained a strip of window buttons over its
//     head and no hit test changed.
//
// Both are measured here, on every dock, because "the band goes to the top"
// is trivially satisfiable by simply deleting the strip and the second claim
// is what says that is not what happened.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';
import 'package:prototype/widgets/window_titlebar.dart';

const Size _screen = Size(1600, 900);
const Key _stageKey = Key('stage');
const Key _bleedKey = Key('bleed');
const Key _captionKey = Key('caption');

/// Stands in for [WindowTitleBar], at its real height. The bar itself talks to
/// a MethodChannel on construction (`isMaximized`), which is not what any of
/// this is about — what is being measured is the ROW, and a row is a size.
const double _captionHeight = 32;

AppState _document() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m389');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

AppState _gallery() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m389h');
  return app;
}

Future<void> _pump(WidgetTester t, AppState app, {required bool windows}) async {
  await t.binding.setSurfaceSize(_screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(
        app: app,
        stage: const SizedBox.expand(key: _stageKey),
        bleed: const SizedBox.expand(key: _bleedKey),
        caption: windows
            ? const SizedBox(key: _captionKey, height: _captionHeight)
            : null,
      ),
    ),
  ));
  await t.pump();
}

Rect _rect(WidgetTester t, Finder f) {
  final tl = t.getTopLeft(f);
  final s = t.getSize(f);
  return Rect.fromLTWH(tl.dx, tl.dy, s.width, s.height);
}

void main() {
  setUp(RibbonDock.resetForTest);
  tearDown(RibbonDock.resetForTest);

  // ---- the claim in the report -------------------------------------------

  for (final dock in [
    RibbonPosition.left,
    RibbonPosition.right,
    RibbonPosition.bottom,
  ]) {
    testWidgets('$dock: the band reaches the top edge with a caption up',
        (t) async {
      RibbonDock.set(dock);
      await _pump(t, _document(), windows: true);

      final band = _rect(t, find.byType(Ribbon));
      if (dock.isVertical) {
        expect(band.top, 0, reason: 'the rail starts at the window top');
        expect(band.height, _screen.height,
            reason: 'and still runs the whole height — M346 stands');
      } else {
        // A bottom band never started at the top; what it must not lose is
        // its own edge to a strip that is no longer above everything.
        expect(band.bottom, _screen.height);
      }
    });

    testWidgets('$dock: the caption does not overlap the band', (t) async {
      RibbonDock.set(dock);
      await _pump(t, _document(), windows: true);

      final band = _rect(t, find.byType(Ribbon));
      final caption = _rect(t, find.byKey(_captionKey));
      expect(caption.top, 0, reason: 'the window buttons stay at the top');
      expect(caption.overlaps(band), isFalse,
          reason: 'a drag strip over the ribbon would swallow its buttons — '
              'that is the reason it is a row of the stage and not an overlay');
    });

    testWidgets('$dock: the stage keeps its row under the strip', (t) async {
      RibbonDock.set(dock);
      await _pump(t, _document(), windows: true);

      final caption = _rect(t, find.byKey(_captionKey));
      final stage = _rect(t, find.byKey(_stageKey));
      // The second claim. Under the old layout the stage also began at 32;
      // it must still, or the browser and the quick tools have slid up under
      // the window buttons.
      expect(stage.top, _captionHeight);
      expect(stage.overlaps(caption), isFalse);
      // And the two of them together are still exactly the box the band left,
      // so nothing between them was lost to a gap.
      expect(stage.top, caption.bottom);
      expect(stage.bottom,
          dock.isVertical ? _screen.height : _rect(t, find.byType(Ribbon)).top);
    });
  }

  // ---- top dock, the documented exception --------------------------------

  testWidgets('top dock keeps the strip above the band, and says why',
      (t) async {
    RibbonDock.set(RibbonPosition.top);
    await _pump(t, _document(), windows: true);

    final caption = _rect(t, find.byKey(_captionKey));
    final band = _rect(t, find.byType(Ribbon));
    expect(caption.top, 0);
    // A top-docked ribbon spans the full width, so there is no corner left for
    // close and maximise that is not ribbon. Putting the strip in the stage
    // here would strand the window buttons UNDER the ribbon — worse than the
    // 32 points it would save.
    expect(band.top, _captionHeight);
    expect(band.width, _screen.width);
  });

  // ---- the gallery, which has no band at all -----------------------------

  testWidgets('the home gallery still gets the strip, above everything',
      (t) async {
    await _pump(t, _gallery(), windows: true);

    expect(find.byType(Ribbon), findsNothing);
    final caption = _rect(t, find.byKey(_captionKey));
    final stage = _rect(t, find.byKey(_stageKey));
    expect(caption.top, 0);
    expect(stage.top, _captionHeight,
        reason: 'the gallery header must not run under the window buttons');
  });

  // ---- and every other platform is untouched -----------------------------

  for (final dock in RibbonPosition.values) {
    testWidgets('$dock: without a caption the layout is exactly M290\'s',
        (t) async {
      RibbonDock.set(dock);
      await _pump(t, _document(), windows: false);

      expect(find.byKey(_captionKey), findsNothing);
      final band = _rect(t, find.byType(Ribbon));
      final stage = _rect(t, find.byKey(_stageKey));
      expect(band.overlaps(stage), isFalse);
      expect(band.expandToInclude(stage),
          Rect.fromLTWH(0, 0, _screen.width, _screen.height),
          reason: 'the band and the stage still tile the whole content area');
    });
  }

  // ---- and the strip claims its own 32 points ---------------------------
  //
  // A row of the stage sits OVER the document where the band floats, which is
  // new: the strip used to be a row above the whole app with nothing behind
  // it, and translucent hit-test behaviour was therefore invisible. With the
  // viewport underneath, translucent would let one gesture at the top of the
  // window both move the window and orbit the model.
  testWidgets('the real bar swallows a press instead of passing it through',
      (t) async {
    // WindowTitleBar asks native whether the window is maximised on init.
    final ch = const MethodChannel('prototype/desktop');
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async => false);
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null));

    var reachedBehind = 0;
    await t.binding.setSurfaceSize(_screen);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            // Opaque: a bare SizedBox has no child to defer to and would
            // never be hit, which would make the first expectation below pass
            // for the wrong reason.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => reachedBehind++,
              child: const SizedBox.expand(),
            ),
          ),
          const Align(alignment: Alignment.topLeft, child: WindowTitleBar()),
        ]),
      ),
    ));
    await t.pump();

    // Well inside the drag strip, clear of the three buttons on the right.
    await t.tapAt(const Offset(200, _captionHeight / 2));
    // Past the double-tap window: onDoubleTap leaves a timer running, and a
    // pending timer at teardown is an error rather than a warning.
    await t.pump(const Duration(milliseconds: 400));
    expect(reachedBehind, 0,
        reason: 'a press on the caption strip must not also reach the model');

    // And just below it the document is still perfectly reachable.
    await t.tapAt(const Offset(200, _captionHeight + 20));
    await t.pump(const Duration(milliseconds: 400));
    expect(reachedBehind, 1);
  });
}
