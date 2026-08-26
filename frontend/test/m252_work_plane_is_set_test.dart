// M252 — a committed work plane is SET.
//
// Reported: "the plane is set but still when i drag it goes directly into edit
// mode of the plane and i can move it. it should be really set as soon as i
// press ok. only editable by longpressing in the Modell browser".
//
// It was true. M169 armed a viewport drag on pointer-down over ANY work plane
// and opened its offset field on a tap, and M169's browser row did the same,
// so a plane never stopped being editable — pressing OK settled the number and
// nothing else. Worse, the viewport suppresses one-finger orbit and the
// general pick while a plane drag is armed, so a drag that merely STARTED on a
// plane moved the plane instead of the view.
//
// Arming is explicit now, and AppState.workPlaneDraggable is the whole gate
// the viewport asks. There are two ways in — "Edit Offset" on the row's
// long-press menu in the model browser, and the drag that creates a plane,
// which has not been OK'd yet — and committing or cancelling the value is the
// way out. These tests are that rule, from both ends.
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

/// What the model browser's long-press menu does for "Edit Offset"
/// (native_browser_host.dart, item `wpOffset`) — the ONE way in that the user
/// named.
void _editOffsetFromBrowser(AppState app, WorkPlane w) {
  app.selectWorkPlane(w);
  app.workPlaneOffsetEditing = true;
}

void main() {
  group('M252 — a set plane cannot be grabbed', () {
    test('a plane nobody is editing is not draggable', () {
      final w = _plane();
      final app = _appWith([w]);
      expect(app.workPlaneDraggable(w), isFalse);
    });

    test('SELECTING it does not make it draggable', () {
      // A tap in the viewport, and a tap on its browser row, both land here.
      // Selecting is a highlight; it is not permission to move the plane.
      final w = _plane();
      final app = _appWith([w]);
      app.selectWorkPlane(w);
      expect(app.selectedWorkPlane, same(w), reason: 'it did select');
      expect(app.workPlaneDraggable(w), isFalse,
          reason: 'this is the reported bug: a tap must not arm the drag');
    });
  });

  group('M252 — the long-press menu is the way in', () {
    test('"Edit Offset" arms the plane', () {
      final w = _plane();
      final app = _appWith([w]);
      _editOffsetFromBrowser(app, w);
      expect(app.workPlaneDraggable(w), isTrue);
    });

    test('pressing OK sets it again', () {
      final w = _plane(offset: 10);
      final app = _appWith([w]);
      _editOffsetFromBrowser(app, w);
      expect(app.commitWorkPlaneOffset('6.08'), isTrue);
      expect(w.offset, closeTo(6.08, 1e-9));
      expect(app.workPlaneDraggable(w), isFalse,
          reason: '"it should be really set as soon as i press ok"');
    });

    test('cancelling sets it again too', () {
      final w = _plane();
      final app = _appWith([w]);
      _editOffsetFromBrowser(app, w);
      app.cancelWorkPlaneOffset();
      expect(app.workPlaneDraggable(w), isFalse);
    });

    test('a drag leaves it armed, so the value can still be typed', () {
      // M169's flow survives inside the gate: the drag gets you close, the
      // number makes it right, and only the number closes the field.
      final w = _plane(offset: 10);
      final app = _appWith([w]);
      _editOffsetFromBrowser(app, w);
      app.beginWorkPlaneDrag(w);
      app.updateWorkPlaneDrag(-4.49);
      app.endWorkPlaneDrag();
      expect(w.offset, closeTo(5.51, 1e-9));
      expect(app.workPlaneDraggable(w), isTrue,
          reason: 'still editing — the field is open on it');
    });

    test('only the armed plane is draggable, not its neighbour', () {
      final a = _plane(seq: 1);
      final b = _plane(seq: 2);
      final app = _appWith([a, b]);
      _editOffsetFromBrowser(app, a);
      expect(app.workPlaneDraggable(a), isTrue);
      expect(app.workPlaneDraggable(b), isFalse);
    });

    test('selecting another plane disarms the first', () {
      final a = _plane(seq: 1);
      final b = _plane(seq: 2);
      final app = _appWith([a, b]);
      _editOffsetFromBrowser(app, a);
      app.selectWorkPlane(b);
      expect(app.workPlaneDraggable(a), isFalse);
      expect(app.workPlaneDraggable(b), isFalse,
          reason: 'a tap selects; it does not hand the arm over');
    });
  });

  group('M252 — a plane being made is not a plane that is set', () {
    test('drag-to-create lands armed, and OK sets it', () {
      final app = AppState();
      app.parts['P'] = PartModel('P');
      app.curTab = 'P';
      app.startWorkPlane(WorkPlaneKind.offset);
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.updateWorkPlaneCreate(6.08);
      app.commitWorkPlaneCreate();
      final w = app.currentPart!.workPlanes.single;
      expect(app.workPlaneDraggable(w), isTrue,
          reason: 'M174 lands straight in offset-edit; nothing was OK\'d yet');
      expect(app.commitWorkPlaneOffset('6.08'), isTrue);
      expect(app.workPlaneDraggable(w), isFalse);
    });
  });

  group('M252 — a plane with nothing to measure is never draggable', () {
    test('a midplane refuses even while armed', () {
      final w = WorkPlane('Work Plane2', 2, WorkPlaneKind.midplane,
          'Midplane between face and face', planeFrame('xy'));
      final app = _appWith([w]);
      _editOffsetFromBrowser(app, w);
      expect(app.workPlaneDraggable(w), isFalse,
          reason: 'no base to measure an offset from — M169 toasted instead');
    });
  });
}
