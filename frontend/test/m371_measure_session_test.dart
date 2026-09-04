// M371 — the COMMAND: what a tap does to the pick list, and what the app does
// when the command is armed and put away.
//
// The third of the three measure test files. m371_measure_test pins the
// arithmetic and m371_measure_pick_test pins what a pixel means; this one pins
// the rules that decide whether the tool FEELS like Inventor's — the ones that
// have nothing to do with geometry and everything to do with not punishing a
// mis-tap.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/section_view.dart';
import 'package:prototype/ffi/qcad_engine.dart' show kDefaultLayer;
import 'package:prototype/assembly.dart';
import 'package:prototype/measure.dart';
import 'package:prototype/part_model.dart'
    show FaceEditKind, FaceEditSession, PartModel, Vec3, planeFrame;

AppState makeApp({String name = 't'}) {
  final app = AppState();
  final s = SketchModel(name);
  app.sketches[name] = s;
  app.curTab = name;
  app.editingLayer = kDefaultLayer;
  return app;
}

MeasureRef pt(double x, [double y = 0, double z = 0]) =>
    MeasureRef.point(Vec3(x, y, z));

MeasureRef face(double z) =>
    MeasureRef.plane(Vec3(0, 0, z), const Vec3(0, 0, 1),
        oriented: true, area: 100, perimeter: 40);

void main() {
  // =========================================================================
  group('the pick list', () {
    test('one pick, then a second, measures the pair', () {
      final s = MeasureSession();
      s.add(pt(0));
      expect(s.picks.length, 1);
      s.add(pt(5));
      expect(s.picks.length, 2);
      expect(s.reading!.primary.value, closeTo(5, 1e-9));
    });

    test('tapping the same thing again TAKES IT BACK OUT', () {
      // One mis-tap costs one tap. Without this the only way to undo a wrong
      // pick is to restart the whole measurement.
      final s = MeasureSession();
      s.add(face(0));
      s.add(face(10));
      expect(s.picks.length, 2);
      final taken = s.add(face(10));
      expect(taken, isFalse);
      expect(s.picks.length, 1);
      expect(s.reading, isNotNull, reason: 'one face still has an area');
    });

    test('a THIRD pick starts a new measurement from that pick', () {
      final s = MeasureSession();
      s.add(face(0));
      s.add(face(10));
      s.add(pt(1, 2, 3));
      expect(s.picks.length, 1);
      expect(s.picks.single.kind, MeasureRefKind.point);
    });

    test('three POINTS are the exception: they are the angle', () {
      final s = MeasureSession();
      s.add(pt(10));
      s.add(pt(0));
      s.add(pt(0, 10));
      expect(s.picks.length, 3);
      expect(s.reading!.primary.role, MeasureRole.angle);
      expect(s.reading!.primary.value * 180 / 3.141592653589793,
          closeTo(90, 1e-6));
    });

    test('a FOURTH point still restarts — the angle is the ceiling', () {
      final s = MeasureSession();
      s.add(pt(10));
      s.add(pt(0));
      s.add(pt(0, 10));
      s.add(pt(4, 4));
      expect(s.picks.length, 1);
    });

    test('a pick can be dropped by index, and the reading follows', () {
      final s = MeasureSession();
      s.add(pt(0));
      s.add(pt(5));
      s.removeAt(0);
      expect(s.picks.length, 1);
      // One point on its own reports where it is.
      expect(s.reading!.valueOf(MeasureRole.positionX)!.value,
          closeTo(5, 1e-9));
    });

    test('changing the distance mode re-solves without re-picking', () {
      final s = MeasureSession();
      s.add(MeasureRef.segment(Vec3.zero, const Vec3(10, 0, 0)));
      s.add(MeasureRef.segment(const Vec3(25, 0, 0), const Vec3(35, 0, 0)));
      expect(s.reading!.primary.value, closeTo(15, 1e-9));
      s.mode = MeasureDistanceMode.maximum;
      s.recompute();
      expect(s.reading!.primary.value, closeTo(35, 1e-9));
      expect(s.picks.length, 2, reason: 'a mode change is not a re-pick');
    });
  });

  // =========================================================================
  group('totals', () {
    test('add accumulates the primary, per unit kind', () {
      final s = MeasureSession();
      s.add(MeasureRef.segment(Vec3.zero, const Vec3(3, 4, 0)));
      expect(s.addToTotals(), isTrue);
      s.add(MeasureRef.segment(Vec3.zero, const Vec3(0, 0, 10)));
      expect(s.addToTotals(), isTrue);
      expect(s.totals.total(MeasureUnitKind.length), closeTo(15, 1e-9));
      expect(s.totals.count(MeasureUnitKind.length), 2);
    });

    test('adding CLEARS the picks, so the next measurement is a measurement',
        () {
      // Without this the second tap of a run lands beside the first pick and
      // is read as the DISTANCE between them — so "sum these five edges"
      // silently becomes "sum four gaps".
      final s = MeasureSession();
      s.add(MeasureRef.segment(Vec3.zero, const Vec3(3, 4, 0)));
      s.addToTotals();
      expect(s.picks, isEmpty);
      expect(s.reading, isNull);
    });

    test('areas and lengths do not pool into one total', () {
      final s = MeasureSession();
      s.add(MeasureRef.segment(Vec3.zero, const Vec3(3, 4, 0)));
      s.addToTotals();
      s.add(face(0));
      s.addToTotals();
      expect(s.totals.total(MeasureUnitKind.length), closeTo(5, 1e-9));
      expect(s.totals.total(MeasureUnitKind.area), closeTo(100, 1e-9));
    });

    test('RESTART keeps the totals — that is what makes summing usable', () {
      final s = MeasureSession();
      s.add(MeasureRef.segment(Vec3.zero, const Vec3(3, 4, 0)));
      s.addToTotals();
      s.clearPicks();
      expect(s.picks, isEmpty);
      expect(s.reading, isNull);
      expect(s.totals.total(MeasureUnitKind.length), closeTo(5, 1e-9));
    });

    test('nothing measured, nothing added', () {
      final s = MeasureSession();
      expect(s.addToTotals(), isFalse);
      expect(s.totals.isEmpty, isTrue);
    });
  });

  // =========================================================================
  group('arming it', () {
    test('M in a sketch opens the panel; M again puts it away', () {
      final app = makeApp();
      expect(app.measuring, isFalse);
      app.toggleMeasure();
      expect(app.measuring, isTrue);
      app.toggleMeasure();
      expect(app.measuring, isFalse);
    });

    test('M on the gallery refuses rather than opening an empty panel', () {
      final app = AppState();
      expect(app.isHome, isTrue);
      app.toggleMeasure();
      expect(app.measuring, isFalse);
      expect(app.message, isNotNull);
    });

    test('arming Measure stands the active TOOL down', () {
      // Both collect taps from the viewport; two commands claiming one tap is
      // a state the user has no way to see or get out of.
      final app = makeApp();
      app.tool = Tool.line;
      app.startMeasure();
      expect(app.tool, Tool.none);
      expect(app.measuring, isTrue);
    });

    test('arming Measure stands the narrow 3D pick modes down', () {
      // Their branches run ABOVE Measure's in the part viewport's pointer
      // handler, so an armed one would swallow every tap meant for the
      // measurement while its own panel sat there looking active.
      final app = AppState();
      app.parts['Part1'] = PartModel('Part1');
      app.curTab = 'Part1';
      // Set directly rather than through openDeleteFace / openSweep, which
      // need a real body and a real sketch: what is under test is the
      // stand-down, not how the three get armed.
      app.faceEdit = FaceEditSession(FaceEditKind.delete);
      app.pickingSweepPath = true;
      app.pickingLoftSections = true;
      expect(app.pickingFaces, isTrue);
      app.startMeasure();
      expect(app.pickingFaces, isFalse);
      expect(app.pickingSweepPath, isFalse);
      expect(app.pickingLoftSections, isFalse);
      expect(app.measuring, isTrue);
    });

    test("arming Measure stands the ASSEMBLY's collectors down too", () {
      final app = AppState();
      app.assemblies['Gearbox'] = AssemblyModel('Gearbox');
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      app.showRelationshipsPicking = true;
      app.startMeasure();
      expect(app.showRelationshipsPicking, isFalse);
      expect(app.constraintPicking, isFalse);
      expect(app.sectionPicking, isFalse);
      expect(app.measuring, isTrue);
    });

    test('but it does NOT throw away a section already applied', () {
      // Cancelling the PICK is standing a command down; cancelling the CUT is
      // undoing a view the user set up.
      final app = AppState();
      app.assemblies['Gearbox'] = AssemblyModel('Gearbox');
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      app.documentSection = SectionView(SectionMode.half,
          SectionPlane(planeFrame('xy'), 'XY'));
      app.startMeasure();
      expect(app.documentSection, isNotNull);
    });

    test('arming a DRAWING TOOL puts Measure away', () {
      // The symmetric half of "arming Measure stands the tool down". Without
      // it the measure branch, which is checked first, would swallow every
      // tap meant for the tool the user just picked.
      final app = makeApp();
      app.startMeasure();
      app.selectTool(Tool.line);
      expect(app.measuring, isFalse);
      expect(app.tool, Tool.line);
    });

    test('a BLOCKED tool does not close the panel', () {
      // Outside a layer, selectTool refuses and toasts. Closing a panel the
      // user is reading as a side effect of a refusal would be gratuitous.
      final app = makeApp()..editingLayer = null;
      app.startMeasure();
      app.selectTool(Tool.line);
      expect(app.tool, Tool.none);
      expect(app.measuring, isTrue);
    });

    test('a command that takes the viewport puts Measure away', () {
      // cancelWorkFeature is the app's "I am collecting taps now" signal, and
      // sixteen commands call it. Measure rides that signal rather than being
      // wired into all sixteen.
      final app = makeApp();
      app.startMeasure();
      app.cancelWorkFeature();
      expect(app.measuring, isFalse);
    });

    test('arming Measure leaves the SELECTION alone', () {
      // cancelTool stands the armed command down and, when there is none,
      // clears the selection. Measure needs the first half and must not
      // trigger the second.
      final app = makeApp();
      app.selection.add(0);
      app.startMeasure();
      expect(app.selection, contains(0));
    });

    test('Esc puts Measure away and leaves the selection alone', () {
      final app = makeApp();
      app.selection.add(0);
      app.startMeasure();
      app.cancelTool(); // what Esc calls
      expect(app.measuring, isFalse);
      expect(app.selection, contains(0),
          reason: 'Esc dismissed the panel, not the selection');
    });

    test('Esc with no Measure running still clears the selection', () {
      final app = makeApp();
      app.selection.add(0);
      app.cancelTool();
      expect(app.selection, isEmpty);
    });

    test('a pick reaches the session, and a miss does not cancel', () {
      final app = makeApp();
      app.startMeasure();
      app.measurePick(pt(0));
      expect(app.measureSession!.picks.length, 1);
      app.measureMissed();
      expect(app.measuring, isTrue);
      expect(app.measureSession!.picks.length, 1);
    });

    test('restart drops the picks but keeps the panel open', () {
      final app = makeApp();
      app.startMeasure();
      app.measurePick(pt(0));
      app.measurePick(pt(5));
      app.measureRestart();
      expect(app.measuring, isTrue);
      expect(app.measureSession!.picks, isEmpty);
    });

    test('the display settings are clamped where they are set', () {
      final app = makeApp();
      app.startMeasure();
      app.setMeasureDecimals(99);
      expect(app.measureSession!.decimals, 6);
      app.setMeasureDecimals(-4);
      expect(app.measureSession!.decimals, 0);
    });

    test('a mode the pair cannot answer is not stored as if it could', () {
      final app = makeApp();
      app.startMeasure();
      app.measurePick(
          MeasureRef.cylinder(Vec3.zero, const Vec3(0, 0, 1), 4));
      app.measurePick(pt(20));
      app.setMeasureMode(MeasureDistanceMode.centre);
      // The session remembers what was ASKED — the reading reports what it
      // could actually answer, which is how the panel's segmented control
      // stays honest without the session second-guessing the solver.
      expect(app.measureSession!.reading!.mode, MeasureDistanceMode.minimum);
    });

    test('the display choices survive a close and reopen', () {
      // A session is thrown away on Esc, which is what makes Esc a real
      // cancel — so the precision and the second unit have to live outside
      // it or a user working in inches sets them again every time.
      final app = makeApp();
      app.startMeasure();
      app.setMeasureDecimals(4);
      app.setMeasureDualUnit(MeasureUnitSystem.inch);
      app.cancelMeasure();
      app.startMeasure();
      expect(app.measureSession!.decimals, 4);
      expect(app.measureSession!.dualUnit, MeasureUnitSystem.inch);
    });

    test('closing Measure forgets the session entirely', () {
      final app = makeApp();
      app.startMeasure();
      app.measurePick(pt(0));
      app.cancelMeasure();
      expect(app.measureSession, isNull);
      app.startMeasure();
      expect(app.measureSession!.picks, isEmpty);
      expect(app.measureSession!.totals.isEmpty, isTrue);
    });
  });

  // =========================================================================
  group('writing it down', () {
    test('a length is written with the unit and the language decimal mark',
        () {
      const v = MeasureValue(MeasureRole.length, 12.5);
      // The app is German by default, so the mark is a comma.
      expect(measureFormat(v, decimals: 2), '12,50 mm');
      expect(measureFormat(v, decimals: 0), '13 mm');
    });

    test('an angle takes no space before the degree sign', () {
      const v = MeasureValue(MeasureRole.angle, 3.141592653589793 / 2);
      expect(measureFormat(v, decimals: 1), '90,0°');
    });

    test('a second unit converts the same number', () {
      const v = MeasureValue(MeasureRole.length, 25.4);
      expect(measureFormat(v, decimals: 3, unit: MeasureUnitSystem.inch),
          '1,000 in');
    });

    test('an area carries the squared symbol', () {
      const v = MeasureValue(MeasureRole.area, 100);
      expect(measureFormat(v, decimals: 1), '100,0 mm²');
    });

    test('Copy all writes one labelled line per value', () {
      final r = measureSingle(
          MeasureRef.segment(Vec3.zero, const Vec3(3, 4, 0)))!;
      final text = measureReadingText(r, decimals: 1);
      final lines = text.split('\n');
      expect(lines.length, r.values.length);
      expect(lines.first, contains('5,0 mm'));
      expect(lines.first, contains(measureRoleLabel(MeasureRole.length)));
    });

    test('an approximate value says so in the copied text', () {
      final r = measureSingle(MeasureRef.curve(
          [Vec3.zero, const Vec3(10, 0, 0)]))!;
      expect(measureReadingText(r, decimals: 1), contains('≈'));
    });
  });
}
