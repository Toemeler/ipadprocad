// M210 — THREE THINGS THE PART RIBBON DID NOT DO.
//
// "When i select extrude the solid is invisible suddenly."
// "When a tool is in use the cancel button in the toolbar should be there and
//  the cross and the cancel button in the dialog dont work."
// "Same as in 2d: when a tool is selected like extrude, when i click again on
//  the tool it should be deselected."
//
// Three separate faults with one thing in common: every one of them is the
// part side of a rule the sketch side has had for milestones.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';
import 'package:prototype/widgets/quick_tools.dart';

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m210');
  return app;
}

/// A part with one body, one child sketch and one committed extrusion.
(AppState, PartModel) _partWithSolid() {
  final app = _app();
  final p = PartModel('Part1');
  app.parts['p'] = p;
  app.curTab = 'p';
  return (app, p);
}

void main() {
  group('a preview only hides what it can stand in for', () {
    test('a failed preview leaves the body on screen', () {
      final (app, p) = _partWithSolid();
      final f = _feature();
      p.features.add(f);
      expect(visibleSolids(app, p).length, 1, reason: 'nothing open yet');

      // Editing it with a WORKING preview hides it: the preview stands in.
      final s = ExtrudeSession()
        ..editing = f
        ..previewReplacesBody = 'Solid1'
        ..preview = _FakeSolid();
      app.extrudeSession = s;
      expect(visibleSolids(app, p), isEmpty,
          reason: 'the combined preview is drawn instead');

      // The preview FAILS — the extent face stopped being reachable, which is
      // exactly what the device log shows. Nothing stands in for the body now,
      // so hiding it leaves an empty viewport under an open panel.
      s.preview = null;
      expect(visibleSolids(app, p).length, 1,
          reason: 'a failed preview must never make the part vanish');
    });

    test('the same rule for a fillet preview', () {
      final (app, p) = _partWithSolid();
      final f = _feature();
      p.features.add(f);
      final e = EdgeFeatureSession('fillet')..previewReplacesBody = 'Solid1';
      app.edgeSession = e;
      expect(visibleSolids(app, p).length, 1,
          reason: 'no preview built yet — the body is all there is');
      e.preview = _FakeSolid();
      expect(visibleSolids(app, p), isEmpty);
    });
  });

  group('Cancel is reachable, and it works', () {
    test('the quick bar lights Cancel while a part command runs', () {
      final (app, p) = _partWithSolid();
      expect(quickCanCancel(app), isFalse, reason: 'nothing to cancel');
      app.extrudeSession = ExtrudeSession();
      expect(quickCanCancel(app), isTrue);
      app.extrudeSession = null;
      app.pickPlane = true;
      expect(quickCanCancel(app), isTrue, reason: 'an armed pick counts too');
    });

    test('and the bar SHOWS the pair in a part with no sketch open', () {
      final (app, p) = _partWithSolid();
      var ids = buildQuickTools(app).map((i) => i.id).toList();
      expect(ids, isNot(contains(QuickToolId.cancel)),
          reason: 'an idle part: nothing for them to do, so they are omitted');

      app.extrudeSession = ExtrudeSession();
      ids = buildQuickTools(app).map((i) => i.id).toList();
      expect(ids, contains(QuickToolId.cancel));
      expect(ids, contains(QuickToolId.ok),
          reason: 'the panel has an OK too, and the bar is where Enter lives');
    });

    test('cancelExtrude notifies — the panel button repaints', () {
      final (app, p) = _partWithSolid();
      app.extrudeSession = ExtrudeSession();
      var beats = 0;
      void bump() => beats++;
      app.addListener(bump);
      app.cancelExtrude();
      app.removeListener(bump);
      expect(app.extrudeSession, isNull);
      expect(beats, greaterThan(0),
          reason: 'without this the state changed and the panel stayed up — '
              'which is "the cross and the cancel button dont work"');
    });
  });

  group('a part command toggles off', () {
    test('opening Extrude twice closes it', () {
      final (app, p) = _partWithSolid();
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      app.openExtrude();
      expect(app.extrudeSession, isNotNull);
      app.openExtrude();
      expect(app.extrudeSession, isNull, reason: 'the second press disarms');
    });

    test('but a DIFFERENT command switches rather than closing', () {
      final (app, p) = _partWithSolid();
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      app.openExtrude();
      app.openRevolve();
      expect(app.extrudeSession, isNotNull);
      expect(app.extrudeSession!.kind, 'revolve');
      app.openRevolve();
      expect(app.extrudeSession, isNull, reason: 'and revolve toggles too');
    });

    test('fillet toggles, and chamfer switches', () {
      final (app, p) = _partWithSolid();
      app.openFillet();
      expect(app.edgeSession?.kind, 'fillet');
      app.openChamfer();
      expect(app.edgeSession?.kind, 'chamfer');
      app.openChamfer();
      expect(app.edgeSession, isNull);
    });

    test('opening to EDIT a feature is never a toggle', () {
      // The browser sends this, not the ribbon button: pressing it twice is
      // not what happened, so it must open, not close.
      final (app, p) = _partWithSolid();
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      final f = _feature();
      p.features.add(f);
      app.openExtrude(f);
      expect(app.extrudeSession?.editing, same(f));
      app.openExtrude(f);
      expect(app.extrudeSession?.editing, same(f),
          reason: 'still open — an edit request is not a button press');
    });
  });
}

/// One committed extrusion with a solid on it, which is all the scene reads.
ExtrudeFeature _feature() => ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: 'Sketch1',
      profiles: [ProfileSel(0, 0, 1)],
    )..solid = _FakeSolid();

/// The scene only asks whether a solid is THERE, so a stand-in is enough.
class _FakeSolid implements KernelSolid {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
