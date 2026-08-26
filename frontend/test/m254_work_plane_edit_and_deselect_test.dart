// M254 — "Versatz bearbeiten" has to actually open the field, and a selected
// work plane has to be un-selectable.
//
// Two halves of one device report: "wenn ich im context menu versatz
// bearbeiten klicke passiert nichts. ausserdem ist die work plane im Modell
// browser immer gehighlighted". The log shows both, in four lines:
//
//     browser: tap  wp:6                 <- selects it
//     browser: tap  wp:6                 <- and again, which did NOTHING
//     browser: menu wp:6 -> wpOffset     <- and again, which did NOTHING
//     browser: menu wp:6 -> wpOffset
//
// The menu handler was `selectWorkPlane(w)` then `workPlaneOffsetEditing =
// true`. The flag is a plain field and does not notify; selectWorkPlane
// returns early on the plane already selected — and it always IS selected,
// because tapping the row is how you reach its menu. So the flag went true and
// nothing rebuilt. M252 is what made it matter: before it, tapping the row
// opened the field too, so the menu never had to work on its own.
//
// And nothing anywhere passed null to selectWorkPlane, so once a plane was
// selected the row stayed lit for the rest of the session.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

WorkPlane _plane({double offset = 10, int seq = 1}) {
  final base = planeFrame('xy');
  return WorkPlane('Work Plane$seq', seq, WorkPlaneKind.offset,
      'Offset ${offset.toStringAsFixed(2)} mm from XY',
      offsetPlaneFrame(base, offset),
      base: base, offset: offset);
}

AppState _appWith(List<WorkPlane> planes) {
  final app = AppState();
  final p = PartModel('P');
  p.workPlanes.addAll(planes);
  app.parts['P'] = p;
  app.curTab = 'P';
  return app;
}

void main() {
  group('M254 — Edit Offset opens the field', () {
    test('on a plane that is ALREADY selected — the reported case', () {
      final w = _plane();
      final app = _appWith([w]);
      app.selectWorkPlane(w); // the row tap that precedes every menu
      var notified = 0;
      app.addListener(() => notified++);
      app.editWorkPlaneValue(w);
      expect(app.workPlaneOffsetEditing, isTrue);
      expect(notified, greaterThan(0),
          reason: 'a field that opens without a notify never appears — that '
              'is the whole of "passiert nichts"');
    });

    test('on a plane that is not selected yet', () {
      final w = _plane();
      final app = _appWith([w]);
      var notified = 0;
      app.addListener(() => notified++);
      app.editWorkPlaneValue(w);
      expect(app.selectedWorkPlane, same(w));
      expect(app.workPlaneOffsetEditing, isTrue);
      expect(notified, greaterThan(0));
    });

    test('and that is what arms the viewport drag again (M252)', () {
      final w = _plane();
      final app = _appWith([w]);
      app.selectWorkPlane(w);
      expect(app.workPlaneDraggable(w), isFalse);
      app.editWorkPlaneValue(w);
      expect(app.workPlaneDraggable(w), isTrue,
          reason: 'the long-press menu is the one way in M252 left, so it has '
              'to be a way in');
    });

    test('a midplane opens nothing — there is no number behind it', () {
      final w = WorkPlane('Work Plane2', 2, WorkPlaneKind.midplane,
          'Midplane between face and face', planeFrame('xy'));
      final app = _appWith([w]);
      app.editWorkPlaneValue(w);
      expect(app.selectedWorkPlane, same(w), reason: 'it still selects');
      expect(app.workPlaneOffsetEditing, isFalse);
    });
  });

  group('M254 — a selected plane can be un-selected', () {
    test('tapping the row again clears it', () {
      final w = _plane();
      final app = _appWith([w]);
      app.toggleWorkPlaneSelected(w);
      expect(app.selectedWorkPlane, same(w));
      app.toggleWorkPlaneSelected(w);
      expect(app.selectedWorkPlane, isNull,
          reason: 'otherwise the row is lit for the rest of the session');
    });

    test('tapping a different row moves the selection, it does not clear', () {
      final a = _plane(seq: 1);
      final b = _plane(seq: 2);
      final app = _appWith([a, b]);
      app.toggleWorkPlaneSelected(a);
      app.toggleWorkPlaneSelected(b);
      expect(app.selectedWorkPlane, same(b));
    });

    test('clearing closes an open field with it', () {
      final w = _plane();
      final app = _appWith([w]);
      app.editWorkPlaneValue(w);
      app.toggleWorkPlaneSelected(w);
      expect(app.selectedWorkPlane, isNull);
      expect(app.workPlaneOffsetEditing, isFalse,
          reason: 'a field editing nothing would be a trap — M169');
      expect(app.workPlaneDraggable(w), isFalse);
    });
  });
}
