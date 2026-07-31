// M174 — a work plane is DRAGGED off a plane or a face, not typed into being.
//
// Requested: set the Pencil down on a plane, drag up or down, see the plane
// preview and a dimension; let go and it stays; land straight in offset-edit
// mode with a number field that behaves like all the others; tap elsewhere to
// finish.
//
// The important consequence is that the offset comes from the GESTURE. Until
// now `workPlaneOffset` was never assigned from anywhere, so every plane ever
// created was exactly 10 mm (M162 found it, the user's own Part4.part.json
// shows it).
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

AppState _armed() {
  final app = AppState();
  app.parts['P'] = PartModel('P');
  app.curTab = 'P';
  app.startWorkPlane(WorkPlaneKind.offset);
  return app;
}

void main() {
  group('M174 — nothing exists until you let go', () {
    test('putting the pointer down creates NO plane', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      expect(app.currentPart!.workPlanes, isEmpty,
          reason: 'a mis-grab must cost nothing');
      expect(app.wpCreatePreview, isNotNull, reason: 'but it IS previewed');
    });

    test('the preview follows the drag', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.updateWorkPlaneCreate(12);
      expect(app.wpCreatePreview!.origin.z, closeTo(12, 1e-9));
      app.updateWorkPlaneCreate(-3);
      expect(app.wpCreatePreview!.origin.z, closeTo(-3, 1e-9),
          reason: 'absolute in drag distance, so it never compounds');
    });

    test('letting go commits it where the drag left it', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.updateWorkPlaneCreate(12);
      app.commitWorkPlaneCreate();
      final w = app.currentPart!.workPlanes.single;
      expect(w.offset, closeTo(12, 1e-9),
          reason: 'the GESTURE sets the offset — not a hardcoded 10 mm');
      expect(w.frame.origin.z, closeTo(12, 1e-9));
      expect(app.wpCreatePreview, isNull, reason: 'the preview is gone');
    });

    test('it lands straight in offset-edit mode', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.updateWorkPlaneCreate(8);
      app.commitWorkPlaneCreate();
      expect(app.selectedWorkPlane, same(app.currentPart!.workPlanes.single));
      expect(app.workPlaneOffsetEditing, isTrue,
          reason: 'the value is what you correct next; do not make them go '
              'find it');
    });

    test('the committed plane is re-offsettable, because it kept its base', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xz'), 'XZ');
      app.updateWorkPlaneCreate(5);
      app.commitWorkPlaneCreate();
      final w = app.currentPart!.workPlanes.single;
      expect(w.offsetEditable, isTrue);
      expect(app.commitWorkPlaneOffset('20'), isTrue);
      expect(w.frame.origin.y, closeTo(20, 1e-9));
    });

    test('a drag that never moved commits nothing', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.commitWorkPlaneCreate();
      expect(app.currentPart!.workPlanes, isEmpty,
          reason: 'a zero-offset plane on top of its own base is never meant');
      expect(app.workPlaneArm, isNull, reason: 'and the command stands down');
    });

    test('cancelling drops the preview and creates nothing', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.updateWorkPlaneCreate(30);
      app.cancelWorkPlaneCreate();
      expect(app.wpCreatePreview, isNull);
      expect(app.currentPart!.workPlanes, isEmpty);
    });

    test('it only arms for the OFFSET command, not the midplane one', () {
      final app = AppState();
      app.parts['P'] = PartModel('P');
      app.curTab = 'P';
      app.startWorkPlane(WorkPlaneKind.midplane);
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      expect(app.wpCreatePreview, isNull,
          reason: 'a midplane is defined by two picks, not by a drag');
    });

    test('the next plane starts from the offset you just used', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.updateWorkPlaneCreate(17);
      app.commitWorkPlaneCreate();
      expect(app.workPlaneOffset, closeTo(17, 1e-9));
    });

    test('a non-finite drag sample cannot corrupt the preview', () {
      final app = _armed();
      app.beginWorkPlaneCreate(planeFrame('xy'), 'XY');
      app.updateWorkPlaneCreate(9);
      app.updateWorkPlaneCreate(double.nan);
      expect(app.wpCreatePreview!.origin.z, closeTo(9, 1e-9));
    });
  });
}
