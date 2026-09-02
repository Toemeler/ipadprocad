// M357 — the triad comes back out from under the ribbon.
//
//   "the triad is behind the ribbon now"
//
// M290 made the band a ROW of the layout, so everything that floats — the
// model browser, the tab bar, the quick tools, the dialogues — gets the box
// that excludes it and clears it without being told. M350 then split the
// DOCUMENT out of that box and ran it edge to edge under the glass, because a
// UIGlassEffect blurs what is behind it and what was behind it was the app's
// ground colour.
//
// Three things were on the wrong side of that split. The coordinate triad, the
// ViewCube and the message toast are drawn inside the viewport, in the
// document's coordinate space — but they are not the model. They float over it
// exactly like the browser does, and they went under the band with the
// geometry.
//
// So the band publishes the edge it covers ([RibbonBleed]) and the viewport
// pads its floating chrome by it. The tests below are about the two halves of
// that: the value is right, and the triad is actually clear of the band.
//
// The value is ZERO whenever the band does not float, which is every host test
// that does not say otherwise and every device that is not an iPad — there the
// document is inside the stage already and M290's arrangement is untouched.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';
import 'package:prototype/widgets/viewport3d.dart';

const Size _screen = Size(1200, 900);

AppState _part() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m353');
  app.parts['P'] = PartModel('P');
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

AppState _home() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m353h');
  return app;
}

/// The whole app layout, document layer and all — this cannot be tested with a
/// bare Ribbon, because the claim is about where the DOCUMENT's chrome lands.
Future<void> _pump(WidgetTester t, AppState app,
    {required RibbonPosition dock, required bool glass}) async {
  RibbonDock.set(dock);
  RibbonSurface.glassOverride = glass;
  await t.binding.setSurfaceSize(_screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(
        app: app,
        bleed: Viewport3D(app: app),
        stage: const SizedBox.expand(),
      ),
    ),
  ));
  // Two frames: the inset is measured in the band's layout and published on
  // the frame after it, deliberately (a notifier fired mid-layout would dirty
  // a subtree already laid out). One frame of lag on a triad after a dock
  // change is the whole cost of this design.
  await t.pump();
  await t.pump();
}

Rect _rect(WidgetTester t, Finder f) =>
    t.getTopLeft(f) & t.getSize(f);

Finder get _triad => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is TriadPainter);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    L.set(kDe);
    RibbonDock.resetForTest();
    RibbonLabels.resetForTest();
    RibbonBleed.resetForTest();
  });
  tearDown(() {
    RibbonSurface.glassOverride = null;
    RibbonDock.resetForTest();
    RibbonLabels.resetForTest();
    RibbonBleed.resetForTest();
  });

  // -------------------------------------------------------------------------
  group('the value', () {
    testWidgets('is zero on every dock while the band is DOCKED', (t) async {
      // No glass, no float: the document is laid out inside the stage and the
      // band covers nothing. This is the branch every non-iPad runs.
      for (final dock in RibbonPosition.values) {
        await _pump(t, _part(), dock: dock, glass: false);
        expect(RibbonBleed.inset.value, EdgeInsets.zero, reason: '$dock');
      }
    });

    testWidgets('is the band thickness, on the band edge, when it floats',
        (t) async {
      for (final dock in RibbonPosition.values) {
        await _pump(t, _part(), dock: dock, glass: true);
        final band = t.getSize(find.byType(Ribbon));
        final v = RibbonBleed.inset.value;
        expect(
            v,
            switch (dock) {
              RibbonPosition.top => EdgeInsets.only(top: band.height),
              RibbonPosition.bottom => EdgeInsets.only(bottom: band.height),
              RibbonPosition.left => EdgeInsets.only(left: band.width),
              RibbonPosition.right => EdgeInsets.only(right: band.width),
            },
            reason: '$dock');
        // One edge, never two: the band is on an edge, not in a corner.
        expect(
            [v.top, v.bottom, v.left, v.right].where((d) => d > 0).length, 1);
      }
    });

    testWidgets('goes back to zero on the gallery, where no band is drawn',
        (t) async {
      // M290 lists this exact failure against M284: chrome clearing a band
      // that is not on screen. Leaving the last document's value behind would
      // reproduce it.
      await _pump(t, _part(), dock: RibbonPosition.top, glass: true);
      expect(RibbonBleed.inset.value.top, greaterThan(0));
      await _pump(t, _home(), dock: RibbonPosition.top, glass: true);
      expect(RibbonBleed.inset.value, EdgeInsets.zero);
    });

    testWidgets('follows the band when it gets thinner', (t) async {
      // Turning the names off changes the band's size, and the inset is a
      // measurement rather than a constant precisely so it follows.
      RibbonLabels.set(true);
      await _pump(t, _part(), dock: RibbonPosition.top, glass: true);
      final named = RibbonBleed.inset.value.top;
      RibbonLabels.set(false);
      await _pump(t, _part(), dock: RibbonPosition.top, glass: true);
      expect(RibbonBleed.inset.value.top, lessThan(named));
    });
  });

  // -------------------------------------------------------------------------
  group('and the triad is out from under the band', () {
    for (final dock in RibbonPosition.values) {
      testWidgets('$dock: the triad does not overlap the band', (t) async {
        await _pump(t, _part(), dock: dock, glass: true);
        expect(_triad, findsOneWidget);
        final triad = _rect(t, _triad);
        final band = _rect(t, find.byType(Ribbon));
        expect(triad.overlaps(band), isFalse,
            reason: 'triad $triad runs under the band $band');
      });

      testWidgets('$dock: and the cube does not either', (t) async {
        // The cube is the top-right half of the same report: a top dock puts
        // the band exactly where it sits.
        await _pump(t, _part(), dock: dock, glass: true);
        final cube = _rect(t, find.byType(ViewCube));
        final band = _rect(t, find.byType(Ribbon));
        expect(cube.overlaps(band), isFalse,
            reason: 'cube $cube runs under the band $band');
      });
    }

    testWidgets('the model itself still runs edge to edge under it',
        (t) async {
      // The point of M350, and the thing this milestone must not undo: the
      // glass has the MODEL behind it, not a strip of ground colour.
      await _pump(t, _part(), dock: RibbonPosition.top, glass: true);
      expect(_rect(t, find.byType(Viewport3D)), Offset.zero & _screen);
    });

    testWidgets('docked, the triad sits where M290 put it', (t) async {
      // Without the glass nothing moves: the document is inside the stage, the
      // inset is zero, and this is the layout that shipped.
      await _pump(t, _part(), dock: RibbonPosition.bottom, glass: false);
      final triad = _rect(t, _triad);
      final band = _rect(t, find.byType(Ribbon));
      expect(triad.overlaps(band), isFalse);
      expect(_rect(t, find.byType(Viewport3D)).bottom, band.top,
          reason: 'the document stops at the band when the band is a row');
    });
  });
}
