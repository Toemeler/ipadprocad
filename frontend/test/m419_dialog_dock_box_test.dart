// M419 — "the extrude dialog spawns behind stuff and in front of other stuff
// and part of it is out of the screen. it should spawn a bit more on the left
// and up so that it is directly fully cleared" (#42).
//
// THREE COMPLAINTS, ONE PIECE OF ARITHMETIC. Every floating dialog measured
// `MediaQuery.sizeOf(context)` — the WINDOW — and was then laid out by
// RibbonDockLayout in the STAGE, which is the window minus the ribbon band
// and, on Windows, minus the caption row too. Parking computed in one
// coordinate space and used in a smaller one is too far down (so it hangs off
// the bottom), too far right (so it slides under the quick-tool bar), and
// therefore partly underneath things. "A bit more on the left and up" is the
// correction exactly.
//
// What is pinned here:
//   * the dock reads the STAGE's box when one is published, and falls back to
//     the window when it is not;
//   * a dialog that fits is fully inside the box, on all four edges;
//   * a dialog too tall to centre is pushed UP until it fits rather than
//     hanging off the bottom;
//   * a dialog too tall for the box at all keeps its top edge, because a title
//     bar off the top cannot be dragged back;
//   * parking never runs under the quick-tool bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/dialog_dock.dart';
import 'package:prototype/widgets/quick_tools.dart';

/// The stage on the machine the report came from: a 1536x824 window, less the
/// ribbon band and the Windows caption row.
const _window = Size(1536, 824);
const _stage = Size(1536, 682);

void main() {
  group('the dock asks about the box it is in', () {
    testWidgets('the stage where one is published', (t) async {
      late Size seen;
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: _window),
        child: DialogDockScope(
          size: _stage,
          child: Builder(builder: (c) {
            seen = DialogDock.viewport(c);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(seen, _stage);
    });

    testWidgets('the window where none is', (t) async {
      late Size seen;
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: _window),
        child: Builder(builder: (c) {
          seen = DialogDock.viewport(c);
          return const SizedBox.shrink();
        }),
      ));
      expect(seen, _window,
          reason: 'a dialog pumped on its own still gets a sane answer');
    });
  });

  group('a parked dialog is fully inside its box', () {
    // The extrude panel's own size.
    const panel = Size(380, 620);

    test('the reported case: it used to hang off the bottom', () {
      // What the old code did — centre 620 in the WINDOW — put the panel here.
      final wrong = DialogDock.middle(_window, panel.height);
      expect(wrong + panel.height, greaterThan(_stage.height),
          reason: 'this is the bug: past the bottom of the box it lives in');

      // What it does now.
      final spot = DialogDock.spot(_stage, panel);
      expect(spot.dy, greaterThanOrEqualTo(0));
      expect(spot.dy + panel.height,
          lessThanOrEqualTo(_stage.height - DialogDock.gap));
      expect(spot.dy, lessThan(wrong),
          reason: '"a bit more up", which is what was asked for');
    });

    test('and it clears the quick-tool bar on the right', () {
      final spot = DialogDock.spot(_stage, panel);
      expect(spot.dx + panel.width,
          lessThanOrEqualTo(_stage.width - DialogDock.rightChrome));
      expect(spot.dx, greaterThanOrEqualTo(0));
    });

    test('a short dialog is still centred, not shoved to the top', () {
      const small = Size(300, 200);
      final spot = DialogDock.spot(_stage, small);
      expect(spot.dy, DialogDock.middle(_stage, small.height));
      expect(spot.dy, greaterThan(DialogDock.top()));
    });

    test('every dialog size the app uses fits, or starts at the top', () {
      for (final h in [200.0, 460.0, 560.0, 620.0, 660.0, 900.0]) {
        final spot = DialogDock.spot(_stage, Size(380, h));
        expect(spot.dy, greaterThanOrEqualTo(DialogDock.top() - 0.001),
            reason: 'never off the top: a title bar up there cannot be grabbed');
        if (h + 2 * DialogDock.gap <= _stage.height) {
          expect(spot.dy + h, lessThanOrEqualTo(_stage.height - DialogDock.gap),
              reason: 'a dialog that fits is fully inside');
        } else {
          expect(spot.dy, DialogDock.top(),
              reason: 'one that cannot fit keeps its top edge');
        }
      }
    });
  });

  group('the right-hand edge', () {
    test('is the content area, never the screen', () {
      expect(DialogDock.rightChrome, greaterThan(0),
          reason: 'the bar owns that strip; a dialog under it hides its own '
              'buttons behind a platform view the screenshot cannot show');
      expect(DialogDock.left(_stage, 380),
          _stage.width - 380 - DialogDock.gap - QuickToolsBar.occupiedWidth);
    });

    test('a dialog wider than the box still starts on screen', () {
      expect(DialogDock.left(const Size(320, 600), 900),
          greaterThanOrEqualTo(0));
    });
  });
}
