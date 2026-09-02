// M290 — the band takes a row of the layout; nothing floats over it.
//
// M284 shipped the dockable flush band, and shipped it as an OVERLAY: the band
// was a `Positioned` inside the content Stack, it measured its own thickness
// after layout and published it, and seven floating panels each subtracted the
// edge that concerned them — the model browser, the tab bar, the quick-tool
// rail, the ViewCube, the triad, the offset field and the modeless dialogs.
//
// That protocol has a cost, and its own history is the evidence:
//
//   * the thickness arrived ONE FRAME LATE (a post-frame callback), so every
//     dock change and every tab whose ribbon is a different height put the
//     chrome briefly in the wrong place;
//   * forgetting to subtract was silent — "inset the tab bar for side-docked
//     bands" and bug report #3, "gallery chrome no longer clears an absent
//     ribbon band", are both that failure, each found on a device;
//   * the published values outlived the band, so the insets had to be
//     special-cased against whether it was drawn at all.
//
// Giving the band a real row deletes all three at once: the stage's box IS the
// content area minus the band, so nothing measures, nothing subtracts, nothing
// goes stale, and a panel added tomorrow cannot forget. These tests measure
// the two boxes on all four edges, and pin the placement rule that motivated
// the whole thing —
//
//   "On the right left and bottom you need to make sure its on the left side
//    of the Modell browser, on the right side of the toolbar and under the
//    bottom bar."
//
// — as the single property it actually is: the band is outside the stage, and
// everything else is inside it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

const Size _screen = Size(1600, 900);
const Key _stageKey = Key('stage');
const Key _bleedKey = Key('bleed');

AppState _document() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m290');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: the full ribbon is up
  return app;
}

/// A document whose ribbon is SHORT: a sketch that is not in edit mode, where
/// the band holds two panels instead of eight. The case the full-height bug
/// actually showed in — see the tests below.
AppState _shortRibbon() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m346');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  return app;
}

AppState _gallery() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m290h');
  return app;
}

Future<void> _pump(WidgetTester t, AppState app) async {
  await t.binding.setSurfaceSize(_screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(
        app: app,
        // SizedBox.expand, not a bare ColoredBox: the docked cases put the
        // stage in an Expanded and would fill either way, but on the gallery
        // it is returned unwrapped and a shrink-wrapping child would measure
        // zero — which would make the assertion below pass for the wrong
        // reason on three of the four docks.
        stage: const SizedBox.expand(key: _stageKey),
        bleed: const SizedBox.expand(key: _bleedKey),
      ),
    ),
  ));
  await t.pump();
}

Rect _rect(WidgetTester t, Finder f) {
  final tl = t.getTopLeft(f);
  final size = t.getSize(f);
  return Rect.fromLTWH(tl.dx, tl.dy, size.width, size.height);
}

void main() {
  setUp(RibbonDock.resetForTest);
  tearDown(RibbonDock.resetForTest);

  group('the band and the stage share the screen without overlapping', () {
    for (final dock in RibbonPosition.values) {
      testWidgets('$dock: the two boxes tile the content area', (t) async {
        RibbonDock.set(dock);
        await _pump(t, _document());

        final band = _rect(t, find.byType(Ribbon));
        final stage = _rect(t, find.byKey(_stageKey));

        // THE property. Under M284 these two rectangles overlapped by design
        // and the difference was made up by every panel inside the stage
        // subtracting an inset it had to know about.
        expect(band.overlaps(stage), isFalse,
            reason: 'the stage must not run under the band');
        // Together they are the whole screen: no gap, no lost strip.
        expect(band.expandToInclude(stage),
            Rect.fromLTWH(0, 0, _screen.width, _screen.height));
      });
    }

    // M346 — the band FILLS its edge, and a SHORT ribbon is the case that
    // proves it.
    //
    // The report: "the ribbon when it is on the right it doesn't go over the
    // full height." A Row centres its children on the cross axis and the band
    // sizes itself to its content (its scroll view shrink-wraps), so a rail
    // whose panels do not reach the bottom sat as a slab in the middle of the
    // edge with the scaffold's ground above and below it.
    //
    // Measured on this screen before the fix: a sketch OUTSIDE edit mode came
    // to 104 pt of a 900 pt edge, starting 398 pt down. In edit mode the same
    // rail measured the full 900 — which is why every test here passed and the
    // device did not: the suite only ever pumped the long ribbon. The two
    // cases are both pumped now.
    //
    // The tiling test above could not see it either: "the two boxes tile the
    // content area" is a union, and a band that sits inside the stage's
    // vertical span unions to exactly the same rectangle.
    for (final dock in RibbonPosition.values) {
      for (final (what, app) in [
        ('a long ribbon', _document),
        ('a short one', _shortRibbon),
      ]) {
        testWidgets('$dock: the band fills its edge with $what', (t) async {
          RibbonDock.set(dock);
          await _pump(t, app());
          final band = _rect(t, find.byType(Ribbon));
          if (dock.isVertical) {
            expect(band.top, 0, reason: 'a rail starts at the top');
            expect(band.height, _screen.height,
                reason: 'and runs the whole height — the glass covers the '
                    'edge, not the middle third of it');
          } else {
            expect(band.left, 0);
            expect(band.width, _screen.width);
          }
        });
      }
    }

    testWidgets('top: the stage starts where the band ends', (t) async {
      RibbonDock.set(RibbonPosition.top);
      await _pump(t, _document());
      expect(_rect(t, find.byKey(_stageKey)).top,
          _rect(t, find.byType(Ribbon)).bottom);
    });

    testWidgets('bottom: the tab bar\'s edge is above the band', (t) async {
      // "under the bottom bar" — the band owns the screen's bottom edge and
      // the stage, which carries the document tab bar, stops on top of it.
      RibbonDock.set(RibbonPosition.bottom);
      await _pump(t, _document());
      final band = _rect(t, find.byType(Ribbon));
      expect(_rect(t, find.byKey(_stageKey)).bottom, band.top);
      expect(band.bottom, _screen.height);
    });

    testWidgets('left: the model browser\'s box starts right of the band',
        (t) async {
      // "on the left side of the Modell browser" — the browser is drawn inside
      // the stage, so this is the assertion for it.
      RibbonDock.set(RibbonPosition.left);
      await _pump(t, _document());
      final band = _rect(t, find.byType(Ribbon));
      expect(band.left, 0);
      expect(band.width, RibbonMetrics.railWidth);
      expect(_rect(t, find.byKey(_stageKey)).left, band.right);
    });

    testWidgets('right: the quick-tool rail\'s box ends left of the band',
        (t) async {
      // "on the right side of the toolbar" — same argument, other edge.
      RibbonDock.set(RibbonPosition.right);
      await _pump(t, _document());
      final band = _rect(t, find.byType(Ribbon));
      expect(band.right, _screen.width);
      expect(band.width, RibbonMetrics.railWidth);
      expect(_rect(t, find.byKey(_stageKey)).right, band.left);
    });
  });

  // M350 — the OTHER branch: where the band is glass it floats, and the
  // document runs under it so the material has something to refract.
  //
  // Every test above pins the docked branch, which is what a host without the
  // native material gets. These pin the one the device gets, through
  // `RibbonSurface.glassOverride` — otherwise the milestone's whole claim
  // would be untested on the only platform it happens on.
  group('with the glass, the band floats and the document runs under it', () {
    setUp(() => RibbonSurface.glassOverride = true);
    tearDown(() => RibbonSurface.glassOverride = null);

    for (final dock in RibbonPosition.values) {
      testWidgets('$dock: the DOCUMENT is the whole screen', (t) async {
        RibbonDock.set(dock);
        await _pump(t, _document());
        expect(_rect(t, find.byKey(_bleedKey)),
            Rect.fromLTWH(0, 0, _screen.width, _screen.height),
            reason: 'blurred ground colour is ground colour — the thing '
                'behind the band has to be the model');
      });

      testWidgets('$dock: the band lies OVER the document', (t) async {
        RibbonDock.set(dock);
        await _pump(t, _document());
        expect(
            _rect(t, find.byType(Ribbon))
                .overlaps(_rect(t, find.byKey(_bleedKey))),
            isTrue);
      });

      testWidgets('$dock: and the chrome still clears it', (t) async {
        // M284's protocol is what this is not. The chrome's box is the row the
        // band did not take, so nothing measures and nothing subtracts — and
        // this is the assertion that says so.
        RibbonDock.set(dock);
        await _pump(t, _document());
        final band = _rect(t, find.byType(Ribbon));
        final stage = _rect(t, find.byKey(_stageKey));
        expect(band.overlaps(stage), isFalse);
        expect(band.expandToInclude(stage),
            Rect.fromLTWH(0, 0, _screen.width, _screen.height));
      });
    }

    testWidgets('the band swallows a tap on its own background', (t) async {
      // Floating, its empty space sits over the viewport, and a Stack lets a
      // hit fall through whatever does not claim it: without the swallow a tap
      // on the ribbon's background would orbit the model behind it.
      // A SHORT ribbon, deliberately: the band's scroll view covers whatever
      // its panels reach, so with the long one there is no background left to
      // tap and the test would pass without the swallow.
      RibbonDock.set(RibbonPosition.right);
      var hitBelow = 0;
      await t.binding.setSurfaceSize(_screen);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RibbonDockLayout(
            app: _shortRibbon(),
            stage: const SizedBox.expand(key: _stageKey),
            bleed: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => hitBelow++,
              child: const SizedBox.expand(key: _bleedKey),
            ),
          ),
        ),
      ));
      await t.pump();
      final band = _rect(t, find.byType(Ribbon));
      // The very bottom of the rail: below every panel, so it is the band's
      // own background and nothing else.
      await t.tapAt(Offset(band.center.dx, band.bottom - 4));
      await t.pump();
      expect(hitBelow, 0);
    });
  });

  group('the gallery has no band at all', () {
    testWidgets('so there is nothing for its chrome to clear', (t) async {
      // M284 needed contentInsetsFor(ribbonDrawn) because the published insets
      // outlived the band; here the band is simply not built, and the stage is
      // the whole screen on every dock.
      for (final dock in RibbonPosition.values) {
        RibbonDock.set(dock);
        await _pump(t, _gallery());
        expect(find.byType(Ribbon), findsNothing, reason: '$dock');
        expect(_rect(t, find.byKey(_stageKey)),
            Rect.fromLTWH(0, 0, _screen.width, _screen.height),
            reason: '$dock');
      }
    });
  });

  group('the dock is a value with a store, not a widget', () {
    // M290 moved RibbonPosition and RibbonStore out of widgets/ribbon_chrome
    // and into lib/ribbon_dock.dart. These tests need no binding, no widget
    // tree and no channel — which is the whole argument for the move, and the
    // rule settings.dart and backdrop.dart already state in their headers.
    test('it round-trips through settings.json', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m290s');
      final store = RibbonStore(dir);
      expect(store.load(), isNull, reason: 'no file yet');
      store.save(RibbonPosition.left);
      expect(store.load(), RibbonPosition.left);
      store.save(RibbonPosition.bottom);
      expect(store.load(), RibbonPosition.bottom);
    });

    test('it merges rather than owning the file', () {
      // The appearance and the language live in the same settings.json; a
      // ribbon write that dropped them would be a preference silently lost.
      final dir = Directory.systemTemp.createTempSync('ipc_m290m');
      File('${dir.path}/${RibbonStore.fileName}')
          .writeAsStringSync(jsonEncode({'theme': 'dark', 'locale': 'de'}));
      RibbonStore(dir).save(RibbonPosition.right);
      final raw = jsonDecode(
              File('${dir.path}/${RibbonStore.fileName}').readAsStringSync())
          as Map;
      expect(raw['theme'], 'dark');
      expect(raw['locale'], 'de');
      expect(raw['ribbon'], 'right');
    });

    test('a corrupt file costs the preference and nothing else', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m290c');
      File('${dir.path}/${RibbonStore.fileName}').writeAsStringSync('{oh no');
      expect(RibbonStore(dir).load(), isNull);
    });

    test('attaching a store adopts what it remembers', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m290a');
      RibbonStore(dir).save(RibbonPosition.bottom);
      expect(RibbonDock.current, RibbonPosition.top);
      RibbonDock.attachStore(RibbonStore(dir));
      expect(RibbonDock.current, RibbonPosition.bottom);
    });

    test('and switching writes it back', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m290w');
      RibbonDock.attachStore(RibbonStore(dir));
      RibbonDock.set(RibbonPosition.left);
      expect(RibbonStore(dir).load(), RibbonPosition.left);
    });

    test('before a store is attached the choice still works', () {
      // A preference changed on a device whose disk is not ready must take
      // effect; it simply is not remembered.
      RibbonDock.set(RibbonPosition.right);
      expect(RibbonDock.current, RibbonPosition.right);
      expect(RibbonDock.isVertical, isTrue);
    });
  });
}
