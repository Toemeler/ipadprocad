// M206 — WHERE A FLOATING DIALOG OPENS.
//
// "The gear dialog should spawn at the right like the extrude panel and all
// other dialogs. Now it spawns under the Modell browser."
//
// "Also other Dialogs spawn under the fast toolbar on the right but they
// should spawn a bit more to the left right next to the toolbar."
//
// Two halves of one rule that was written down nowhere: dialogs park against
// the right edge of the CONTENT area — beside the quick-tool bar, never under
// it, and never in the top-left corner where the model browser lives. Every
// window asks [DialogDock] now.
//
// The reason this survived so long is worth keeping in mind while reading the
// numbers: the quick-tool bar is a UIKit platform view, so on a Flutter
// screenshot the corner it occupies looks EMPTY. A dialog underneath it looks
// perfectly placed in every screenshot ever attached to a bug report.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/dialog_dock.dart';
import 'package:prototype/widgets/quick_tools.dart';

void main() {
  const screen = Size(1600, 900);
  const dialog = Size(300, 560);

  group('the right edge belongs to the quick-tool bar', () {
    test('a docked dialog stops short of it', () {
      final left = DialogDock.left(screen, dialog.width);
      final right = left + dialog.width;
      expect(right, lessThanOrEqualTo(screen.width - QuickToolsBar.occupiedWidth),
          reason: 'the bar owns that strip; a dialog under it hides its own '
              'buttons behind chrome the screenshot cannot show');
    });

    test('and it really is short of it, not merely inside the screen', () {
      // The old spelling was `width - w - 18`, which IS inside the screen and
      // was still wrong. This is the assertion that would have caught it.
      final left = DialogDock.left(screen, dialog.width);
      expect(left + dialog.width, lessThan(screen.width - 18));
    });

    test('there is a gap, so it does not touch the bar either', () {
      final left = DialogDock.left(screen, dialog.width);
      expect(screen.width - QuickToolsBar.occupiedWidth - (left + dialog.width),
          greaterThanOrEqualTo(DialogDock.gap - 0.001));
    });
  });

  group('it is not in the top-left corner', () {
    test('a docked dialog is on the RIGHT half of the screen', () {
      final spot = DialogDock.spot(screen, dialog);
      expect(spot.dx, greaterThan(screen.width / 2),
          reason: 'the top-left is the model browser — the gear dialog opened '
              'under it, which is the report');
    });

    test('and clear of the ribbon at the top', () {
      expect(DialogDock.top(), greaterThanOrEqualTo(DialogDock.gap));
      expect(DialogDock.spot(screen, dialog).dy,
          greaterThanOrEqualTo(DialogDock.top()));
    });
  });

  group('it survives shapes that do not fit', () {
    test('a dialog taller than the screen still starts at the top', () {
      final spot = DialogDock.spot(screen, const Size(300, 4000));
      expect(spot.dy, DialogDock.top(),
          reason: 'centring something too tall would push its title bar off');
    });

    test('a dialog wider than the screen is not pushed off the left', () {
      final left = DialogDock.left(const Size(400, 900), 900);
      expect(left, greaterThanOrEqualTo(0));
    });

    test('a narrow window is centred vertically in what is left', () {
      final spot = DialogDock.spot(screen, const Size(300, 200));
      final free = screen.height - DialogDock.top() - DialogDock.gap;
      expect(spot.dy, closeTo(DialogDock.top() + (free - 200) / 2, 0.001));
    });
  });
}
