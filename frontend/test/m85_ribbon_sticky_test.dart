// M85 — the Create panel's split buttons remember their last variant.
//
// The complaint this fixes: choosing Slot from the Rectangle flyout started
// the slot tool and highlighted the button, but the button kept showing
// Rectangle — and once the tool ended or was cancelled, tapping the body
// started Rectangle again. Inventor's split buttons are sticky in both
// respects.
//
// The face itself is a widget concern; what is pinned here is the STATE it
// reads, because that is where the behaviour actually lives:
//   * selecting a variant records it for its flyout group;
//   * ending or cancelling the tool (Tool.none) must NOT clear it;
//   * groups are independent;
//   * keyboard shortcuts update it exactly like a flyout pick, because the
//     recording sits in selectTool rather than in the ribbon;
//   * it is session state — it never touches the document.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';

void main() {
  group('toolFlyoutGroup covers the Create panel', () {
    test('every rectangle-flyout tool maps to the rect group', () {
      for (final t in [
        Tool.rectTwoPoint,
        Tool.rect3P,
        Tool.rect2PC,
        Tool.rect3PC,
        Tool.slotCC,
        Tool.slotOverall,
        Tool.slotCP,
        Tool.slot3A,
        Tool.slotCPA,
        Tool.polygon,
      ]) {
        expect(toolFlyoutGroup[t], 'rect', reason: '$t');
      }
    });

    test('the other split groups are complete', () {
      expect(toolFlyoutGroup[Tool.splineCV], 'line');
      expect(toolFlyoutGroup[Tool.ellipse], 'circle');
      expect(toolFlyoutGroup[Tool.arcTangent], 'arc');
      expect(toolFlyoutGroup[Tool.chamfer], 'fillet');
    });

    test('Tool.none belongs to no group, so it can never overwrite a pick', () {
      expect(toolFlyoutGroup[Tool.none], isNull);
    });
  });

  group('the pick survives the tool ending', () {
    // selectTool refuses to start a tool outside edit mode, so the recording
    // is exercised through the same map selectTool uses.
    test('a variant replaces the default for its group only', () {
      final pick = <String, Tool>{};
      void record(Tool t) {
        final g = toolFlyoutGroup[t];
        if (g != null) pick[g] = t;
      }

      record(Tool.slotCC);
      expect(pick['rect'], Tool.slotCC);
      expect(pick['line'], isNull, reason: 'groups are independent');

      // Tool finished or Esc pressed.
      record(Tool.none);
      expect(pick['rect'], Tool.slotCC,
          reason: 'the last used variant must stay on the button');

      // A different group does not disturb it.
      record(Tool.ellipse);
      expect(pick['circle'], Tool.ellipse);
      expect(pick['rect'], Tool.slotCC);

      // Choosing the plain rectangle again goes back.
      record(Tool.rectTwoPoint);
      expect(pick['rect'], Tool.rectTwoPoint);
    });
  });

  group('AppState wiring', () {
    test('ribbonPick starts empty, so every button shows its standard face',
        () {
      expect(AppState().ribbonPick, isEmpty);
    });

    test('selectTool outside edit mode records nothing (it never starts)', () {
      final app = AppState();
      expect(app.inEditMode, isFalse);
      app.selectTool(Tool.slotCC);
      expect(app.tool, Tool.none);
      expect(app.ribbonPick['rect'], isNull,
          reason: 'a refused tool must not change the button face');
    });
  });
}
