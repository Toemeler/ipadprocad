// M169 — a work plane you can select, drag and type an exact value into, and
// that sits where you made it.
//
// Reported, after M165/M167 made the plane visible and sketchable:
// "it isn't at the bottom of the timeline, it doesn't hover highlight, and I
// can't drag it."
//
// The Inventor flow this implements: tap the plane and it selects and opens
// its offset field; drag it and the plane follows the pointer along its own
// normal while the field shows the live distance; type a number and that wins
// over wherever the finger stopped; Esc puts it back. The drag gets you close,
// the number makes it right — which is why the field opens WITH the drag
// rather than being a separate step.
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

AppState _appWith(WorkPlane w) {
  final app = AppState();
  final p = PartModel('P');
  p.workPlanes.add(w);
  app.parts['P'] = p;
  app.curTab = 'P';
  return app;
}

void main() {
  group('M169 — selection', () {
    test('selecting publishes the plane, and clearing releases it', () {
      final w = _plane();
      final app = _appWith(w);
      app.selectWorkPlane(w);
      expect(app.selectedWorkPlane, same(w));
      app.selectWorkPlane(null);
      expect(app.selectedWorkPlane, isNull);
    });

    test('changing selection closes any open field', () {
      final w = _plane();
      final app = _appWith(w);
      app.selectWorkPlane(w);
      app.workPlaneOffsetEditing = true;
      app.selectWorkPlane(null);
      expect(app.workPlaneOffsetEditing, isFalse,
          reason: 'a field editing nothing would be a trap');
    });
  });

  group('M169 — dragging', () {
    test('the plane follows the drag, measured from where it started', () {
      final w = _plane(offset: 10);
      final app = _appWith(w);
      app.beginWorkPlaneDrag(w);
      app.updateWorkPlaneDrag(5);
      expect(w.offset, closeTo(15, 1e-9));
      // ... and the NEXT sample is absolute, not cumulative: a drag that
      // reports total travel must not compound.
      app.updateWorkPlaneDrag(7);
      expect(w.offset, closeTo(17, 1e-9));
    });

    test('the field opens with the drag, not after it', () {
      final w = _plane();
      final app = _appWith(w);
      app.beginWorkPlaneDrag(w);
      expect(app.workPlaneOffsetEditing, isTrue,
          reason: 'dynamic input: the number is visible WHILE you drag');
    });

    test('dragging negative moves it the other way', () {
      final w = _plane(offset: 10);
      final app = _appWith(w);
      app.beginWorkPlaneDrag(w);
      app.updateWorkPlaneDrag(-14);
      expect(w.offset, closeTo(-4, 1e-9));
    });

    test('a non-finite sample is ignored, not applied', () {
      final w = _plane(offset: 10);
      final app = _appWith(w);
      app.beginWorkPlaneDrag(w);
      app.updateWorkPlaneDrag(double.nan);
      expect(w.offset, 10);
    });

    test('a plane with no base refuses the drag and says why', () {
      final w = WorkPlane('Work Plane2', 2, WorkPlaneKind.midplane,
          'Midplane between face and face', planeFrame('xy'));
      final app = _appWith(w);
      app.beginWorkPlaneDrag(w);
      expect(app.workPlaneOffsetEditing, isFalse,
          reason: 'a midplane has nothing to measure an offset from');
    });
  });

  group('M169 — the exact value wins', () {
    test('typing a number overrides where the drag stopped', () {
      final w = _plane(offset: 10);
      final app = _appWith(w);
      app.beginWorkPlaneDrag(w);
      app.updateWorkPlaneDrag(3.7182);
      expect(app.commitWorkPlaneOffset('12'), isTrue);
      expect(w.offset, closeTo(12, 1e-9));
      expect(app.workPlaneOffsetEditing, isFalse, reason: 'committed, closed');
    });

    test('it takes the same expression grammar as every other field', () {
      final w = _plane();
      final app = _appWith(w);
      app.selectWorkPlane(w);
      expect(app.commitWorkPlaneOffset('5 * 3 mm'), isTrue);
      expect(w.offset, closeTo(15, 1e-9));
    });

    test('nonsense is REFUSED so the field can stay open', () {
      final w = _plane(offset: 10);
      final app = _appWith(w);
      app.selectWorkPlane(w);
      app.workPlaneOffsetEditing = true;
      expect(app.commitWorkPlaneOffset('banana'), isFalse);
      expect(w.offset, 10, reason: 'unchanged');
      expect(app.workPlaneOffsetEditing, isTrue,
          reason: 'silently discarding what was typed would be worse');
    });

    test('Esc puts the plane back where the drag began', () {
      final w = _plane(offset: 10);
      final app = _appWith(w);
      app.beginWorkPlaneDrag(w);
      app.updateWorkPlaneDrag(40);
      expect(w.offset, closeTo(50, 1e-9));
      app.cancelWorkPlaneOffset();
      expect(w.offset, closeTo(10, 1e-9));
      expect(app.workPlaneOffsetEditing, isFalse);
    });

    test('the geometry moves with the value, not just the number', () {
      final w = _plane(offset: 10);
      final app = _appWith(w);
      app.selectWorkPlane(w);
      app.commitWorkPlaneOffset('30');
      expect(w.frame.origin.z, closeTo(30, 1e-9),
          reason: 'the frame is what the renderer and any sketch on it use');
    });
  });

  group('M169 — visibility', () {
    test('the eye toggles and persists on the part', () {
      final w = _plane();
      final app = _appWith(w);
      expect(w.visible, isTrue);
      app.toggleWorkPlaneVisible(w);
      expect(w.visible, isFalse);
      expect(app.currentPart!.dirty, isTrue);
    });
  });
}
