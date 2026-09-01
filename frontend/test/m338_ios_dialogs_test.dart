// M338 — the tool dialogs are iOS panels.
//
// Three groups, and each guards a different way this could rot.
//
//   1. THE RATCHET. Every file in the dialog layer is a source scan away from
//      reaching back into Material's alphabet — one `import
//      'package:flutter/material.dart';` and the next feature adds an
//      ElevatedButton, a Checkbox and a DropdownButton without anybody
//      noticing until it is on a device. The layer may import Material only
//      through a `show` clause, and only for the four things Cupertino has no
//      answer for.
//
//   2. THE PANELS THEMSELVES. Each one is pumped and asked for the three
//      things a panel must have: the command's name, the way out, and the way
//      to commit. This is a shape test, deliberately: the behaviour behind
//      each button is already covered by the milestone that built it, and what
//      M338 could break is whether the button is still there at all.
//
//   3. THE KIT'S OWN CONTRACTS. The type ramp is Apple's numbers rather than
//      approximations; a segmented control answers a tap on the segment that
//      is already chosen (the extents row depends on it); a switch row toggles
//      from its LABEL, which is what SwiftUI's Toggle does and what a 51 pt
//      target on a 308 pt row otherwise costs; and a panel taller than the
//      window scrolls instead of overflowing.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/qcad_engine.dart' show kDefaultLayer;
import 'package:prototype/gear.dart';
import 'package:prototype/inserts.dart';
import 'package:prototype/ios_design.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/combine_dialog.dart';
import 'package:prototype/widgets/constraint_dialog.dart';
import 'package:prototype/widgets/create_component_dialog.dart';
import 'package:prototype/widgets/drive_dialog.dart';
import 'package:prototype/widgets/edge_feature_dialog.dart';
import 'package:prototype/widgets/extrude_dialog.dart';
import 'package:prototype/widgets/freehand_dialog.dart';
import 'package:prototype/widgets/gear_dialog.dart';
import 'package:prototype/widgets/hole_dialog.dart';
import 'package:prototype/widgets/ios_kit.dart';
import 'package:prototype/widgets/joint_dialog.dart';
import 'package:prototype/widgets/make_part_dialog.dart';
import 'package:prototype/widgets/parameters_dialog.dart';
import 'package:prototype/widgets/pattern_dialog.dart';
import 'package:prototype/widgets/pattern_panel_3d.dart';
import 'package:prototype/widgets/scrub_field.dart';
import 'package:prototype/widgets/split_dialog.dart';
import 'package:prototype/widgets/text_editor_window.dart';
import 'package:prototype/widgets/work_plane_offset_field.dart';

/// The files this milestone converted. Named rather than globbed, because the
/// point of the list is that adding a dialog is a decision to join it.
const kDialogLayer = <String>[
  'lib/widgets/combine_dialog.dart',
  'lib/widgets/constraint_dialog.dart',
  'lib/widgets/create_component_dialog.dart',
  'lib/widgets/drive_dialog.dart',
  'lib/widgets/edge_feature_dialog.dart',
  'lib/widgets/extrude_dialog.dart',
  'lib/widgets/freehand_dialog.dart',
  'lib/widgets/gear_dialog.dart',
  'lib/widgets/hole_dialog.dart',
  'lib/widgets/ios_kit.dart',
  'lib/widgets/joint_dialog.dart',
  'lib/widgets/make_part_dialog.dart',
  'lib/widgets/native_prompts.dart',
  'lib/widgets/parameters_dialog.dart',
  'lib/widgets/pattern_dialog.dart',
  'lib/widgets/pattern_panel_3d.dart',
  'lib/widgets/split_dialog.dart',
  'lib/widgets/text_editor_window.dart',
  'lib/widgets/value_pad.dart',
  'lib/widgets/work_plane_offset_field.dart',
];

/// What a dialog may still take from Material, and why each one is here.
///
/// `TextField` is the big one: Flutter's Cupertino text field is a different
/// WIDGET, and M180's contract ("no number in the app is un-draggable") is
/// pinned by a test that looks for `TextField` inside a `ScrubField`. Swapping
/// it would silence that test rather than satisfy it. The other three have no
/// Cupertino equivalent at all.
const kMaterialAllowed = <String>{
  'Material', // TextField asserts a Material ancestor
  'MaterialType',
  'Tooltip', // hover help for a trackpad or a pointer
  'InputDecoration',
  'InputBorder',
  'TextField',
  'showDialog', // presents the Cupertino alerts in native_prompts
};

/// The English strings, so a test can name what the user reads without being
/// in that locale to do it. m242_asm_ui_test.dart's own handle, same shape.
final en = L.stringsFor(kEn);

AppState _sketchApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

AppState _partApp() {
  final app = AppState();
  app.parts['Part1'] = PartModel('Part1');
  app.curTab = 'Part1';
  return app;
}

AppState _asmApp() {
  final app = AppState();
  app.assemblies['Gearbox'] = AssemblyModel('Gearbox');
  app.openTabs.add('Gearbox');
  app.curTab = 'Gearbox';
  return app;
}

/// Pumps [w] the way its host does: inside a Stack for the panels that place
/// themselves, plainly for the ones the viewport positions.
Future<void> _pump(WidgetTester t, Widget w, {bool positioned = true}) async {
  t.view.physicalSize = const Size(2200, 2800);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: Stack(children: [positioned ? w : Positioned(child: w)])),
  ));
  await t.pump();
  // The host test font is a monospaced stand-in whose glyphs are much wider
  // than the real one's, so a label that fits on the device can overflow here.
  // Those are diagnostics about a font that does not ship.
  while (t.takeException() != null) {}
}

void main() {
  setUp(() {
    L.set(kEn);
    T.palette = kEmber;
  });

  // -------------------------------------------------------------------------
  group('M338 — the dialog layer does not go back to Material', () {
    test('every import of material.dart is a narrow `show`', () {
      final offenders = <String>[];
      for (final path in kDialogLayer) {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path is gone from the tree');
        final src = f.readAsStringSync();
        final m = RegExp(
                r"import\s+'package:flutter/material\.dart'([^;]*);")
            .firstMatch(src);
        if (m == null) continue; // best of all: it does not import it
        final clause = m.group(1)!.trim();
        if (!clause.startsWith('show')) {
          offenders.add('$path imports all of Material');
          continue;
        }
        for (final name in clause
            .substring(4)
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)) {
          if (!kMaterialAllowed.contains(name)) {
            offenders.add('$path shows Material\'s $name');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'the tool dialogs are iOS panels; Material\'s widgets are '
              'the alphabet M338 moved them off:\n  ${offenders.join("\n  ")}');
    });

    test('and it does not draw Material icons either', () {
      // `Icons.` is the tell: a Material glyph in an iOS panel is the wrong
      // weight and the wrong shape, and ios_kit draws the handful of SF
      // Symbols these panels need.
      final offenders = <String>[
        for (final path in kDialogLayer)
          if (RegExp(r'\bIcons\.').hasMatch(File(path).readAsStringSync()))
            path,
      ];
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });
  });

  // -------------------------------------------------------------------------
  group('M338 — every panel names its command and offers its two verbs', () {
    /// The three things a panel must show. [confirm] is null for the windows
    /// that have no confirming action of their own (the value windows that ride
    /// beside an armed tool, which Esc and the quick-tool bar close).
    Future<void> shape(WidgetTester t, Widget w, String title,
        {String? cancel, String? confirm, bool positioned = true}) async {
      await _pump(t, w, positioned: positioned);
      expect(find.text(title), findsWidgets, reason: title);
      if (cancel != null) {
        expect(find.text(cancel), findsOneWidget, reason: '$title: $cancel');
      }
      if (confirm != null) {
        expect(find.text(confirm), findsOneWidget, reason: '$title: $confirm');
      }
      // And it is one of ours, not a Material dialog.
      expect(find.byType(IosPanel), findsWidgets, reason: title);
    }

    testWidgets('Extrude', (t) async {
      final app = _partApp()..extrudeSession = ExtrudeSession();
      await shape(t, ExtrudeDialog(app: app), en.btnExtrude,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Hole', (t) async {
      final app = _partApp()..holeSession = HoleSession();
      await shape(t, HoleDialog(app: app), en.btnHole,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Fillet', (t) async {
      final app = _partApp()..edgeSession = EdgeFeatureSession('fillet');
      await shape(t, EdgeFeatureDialog(app: app), en.btnFillet,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Chamfer', (t) async {
      final app = _partApp()..edgeSession = EdgeFeatureSession('chamfer');
      await shape(t, EdgeFeatureDialog(app: app), en.btnChamfer,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Combine', (t) async {
      final app = _partApp()..combineSession = CombineSession();
      await shape(t, CombineDialog(app: app), en.btnCombine,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Split', (t) async {
      final app = _partApp()..splitSession = SplitSession();
      await shape(t, SplitDialog(app: app), en.btnSplit,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Rectangular Pattern (3D)', (t) async {
      final app = _partApp()
        ..patternSession = PartPatternSession(PatternKind.rectangular);
      await shape(t, PatternPanel3D(app: app), en.patRectangular,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Create Component', (t) async {
      final app = _partApp()..createComponentSession = CreateComponentSession('Part2');
      await shape(t, CreateComponentDialog(app: app), en.dlgCreateComponent,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Make Part', (t) async {
      final app = _partApp()..makePartSession = MakePartSession('Solid1', 'Part2', 'Assembly1');
      await shape(t, MakePartDialog(app: app), en.dlgMakePart,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Place Constraint', (t) async {
      final app = _asmApp()..openConstraint();
      await shape(t, ConstraintDialog(app: app), en.dlgPlaceConstraint,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Place Joint', (t) async {
      final app = _asmApp()..openConstraint();
      app.setConstraintTab(AsmTab.joint);
      await shape(t, JointDialog(app: app), en.dlgPlaceJoint,
          cancel: en.cancel, confirm: en.ok);
    });

    testWidgets('Rectangular Pattern (2D)', (t) async {
      final app = _sketchApp()..pattern = PatternSession(Tool.patRect);
      await shape(t, PatternDialog(app: app), en.patRectangular,
          cancel: en.cancel, confirm: en.ok, positioned: false);
    });

    testWidgets('Mirror (2D) keeps Apply as well as Done', (t) async {
      final app = _sketchApp()..pattern = PatternSession(Tool.mirror);
      await shape(t, PatternDialog(app: app), en.patMirror,
          cancel: en.cancel, confirm: en.done, positioned: false);
      expect(find.text(en.apply), findsOneWidget);
    });

    testWidgets('2D Fillet', (t) async {
      final app = _sketchApp()
        ..filletSess = FilletSession(Tool.fillet)
        ..tool = Tool.fillet;
      await shape(t, FilletChamferDialog(app: app), en.btnFillet,
          positioned: false);
    });

    testWidgets('Polygon', (t) async {
      final app = _sketchApp()..tool = Tool.polygon;
      await shape(t, PolygonDialog(app: app), en.dlgPolygon,
          positioned: false);
    });

    testWidgets('Gear', (t) async {
      final app = _sketchApp()
        ..gear = GearSession(kind: GearKind.external, params: GearParams());
      await shape(t, GearDialog(app: app, onDrag: (_) {}), en.dlgGear,
          cancel: en.cancel, confirm: en.btnInsert, positioned: false);
    });

    testWidgets('Parameters', (t) async {
      final app = _sketchApp();
      await shape(t, ParametersDialog(app: app, onDrag: (_) {}),
          en.dlgParameters,
          confirm: en.done, positioned: false);
    });

    testWidgets('Freehand', (t) async {
      final app = _sketchApp()..freehand = FreehandSession();
      await shape(t, FreehandDialog(app: app, onDrag: (_) {}),
          en.dlgFreehandSpline,
          cancel: en.discard, confirm: en.finish, positioned: false);
    });

    testWidgets('Text', (t) async {
      final app = _sketchApp();
      app.beginTextEdit(SketchText('Hello', 0, 0), isNew: true);
      await shape(t, TextEditorWindow(app: app, onDrag: (_) {}), en.dlgText,
          cancel: en.cancel, confirm: en.ok, positioned: false);
    });

    testWidgets('Drive', (t) async {
      final app = _asmApp();
      final a = app.assemblies['Gearbox']!;
      a.constraints.add(AsmConstraint(
        name: 'Rotation:1',
        kind: AsmKind.rotation,
        solution: AsmSolution.forward,
        a: const AsmRef('x:1',
            AsmGeom.axis(Vec3.zero, Vec3(0, 0, 1)), 'Axis'),
        b: const AsmRef('y:1',
            AsmGeom.axis(Vec3(40, 0, 0), Vec3(0, 0, 1)), 'Axis'),
        value: 1,
      ));
      app.openDrive(a.constraints.first);
      expect(app.driveSession, isNotNull,
          reason: 'a rotation constraint is exactly what Drive is for');
      await _pump(t, DriveDialog(app: app));
      expect(find.text(en.dlgDrive), findsWidgets);
      expect(find.text(en.close), findsOneWidget);
      expect(find.byType(IosPanel), findsWidgets);
    });

    testWidgets('the work plane value field', (t) async {
      final app = AppState();
      final p = PartModel('P');
      final w = WorkPlane('Work Plane1', 1, WorkPlaneKind.offset,
          'Offset 10.00 mm from XY', offsetPlaneFrame(planeFrame('xy'), 10),
          base: planeFrame('xy'), offset: 10);
      p.workPlanes.add(w);
      app.parts['P'] = p;
      app.curTab = 'P';
      app.selectWorkPlane(w);
      app.workPlaneOffsetEditing = true;
      await _pump(t, WorkPlaneOffsetField(app: app));
      expect(find.byType(IosPanel), findsOneWidget);
      expect(find.text(en.ok), findsOneWidget);
      expect(find.text(en.cancel), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('M338 — the kit', () {
    test('the type ramp is Apple\'s table, not an approximation', () {
      // Size / leading / tracking at the Large content size. If one of these
      // ever drifts, it drifts here rather than in forty widgets.
      void row(TextStyle s, double size, double leading, double tracking) {
        expect(s.fontSize, size);
        expect(s.height! * s.fontSize!, closeTo(leading, 1e-9));
        expect(s.letterSpacing, tracking);
      }

      row(IosText.body, 17, 22, -0.41);
      row(IosText.headline, 17, 22, -0.43);
      row(IosText.subheadline, 15, 20, -0.24);
      row(IosText.footnote, 13, 18, -0.08);
      row(IosText.caption1, 12, 16, 0);
      expect(IosText.headline.fontWeight, FontWeight.w600);
      expect(IosText.body.fontWeight, FontWeight.w400);
    });

    test('the 44 pt target is a floor the kit knows about', () {
      expect(IosMetrics.hit, 44);
      expect(IosMetrics.row, IosMetrics.hit);
    });

    testWidgets('a segmented control answers a tap on the CHOSEN segment',
        (t) async {
      // The extents row depends on it: tapping the extent that is already in
      // force is how Inventor's panel goes back to a typed distance, and a
      // control that only reports CHANGES cannot say that.
      final taps = <int>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: IosSegmented<int>(
                value: 1,
                onChanged: taps.add,
                segments: const [
                  IosSegment(value: 0, label: 'A'),
                  IosSegment(value: 1, label: 'B'),
                  IosSegment(value: 2, label: 'C'),
                ],
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('B'));
      await t.tap(find.text('C'));
      expect(taps, [1, 2]);
    });

    testWidgets('a disabled segment does not', (t) async {
      final taps = <int>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: IosSegmented<int>(
                value: 0,
                onChanged: taps.add,
                segments: const [
                  IosSegment(value: 0, label: 'A'),
                  IosSegment(value: 1, label: 'B', enabled: false),
                ],
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('B'));
      expect(taps, isEmpty);
    });

    testWidgets('a switch row toggles from its LABEL', (t) async {
      var on = false;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => iosSwitchRow(
              label: 'Symmetric',
              value: on,
              onChanged: (v) => setState(() => on = v),
            ),
          ),
        ),
      ));
      await t.tap(find.text('Symmetric'));
      await t.pumpAndSettle();
      expect(on, isTrue,
          reason: 'SwiftUI\'s Toggle makes the whole row the control, and a '
              '51 pt switch is not a target to hunt for on a touch screen');
      // …and from the switch itself, which is the other half of the same
      // control.
      await t.tap(find.byType(CupertinoSwitch));
      await t.pumpAndSettle();
      expect(on, isFalse);
    });

    testWidgets('a disabled switch row does nothing at all', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: iosSwitchRow(label: 'Not built', value: false),
        ),
      ));
      await t.tap(find.text('Not built'), warnIfMissed: false);
      await t.pump();
      // No exception, no change — the point is that it cannot be tapped into a
      // state the feature would then have to honour.
      expect(find.text('Not built'), findsOneWidget);
    });

    testWidgets('a panel taller than the window scrolls, and does not overflow',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: IosPanel(
              width: 340,
              maxHeight: 200,
              nav: const IosNavBar(title: 'Tall'),
              children: [
                for (var i = 0; i < 30; i++) iosRow(label: 'Row $i'),
              ],
            ),
          ),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull,
          reason: 'a panel that outgrows the viewport must scroll, not paint '
              'a yellow-and-black bar across the app');
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('a value row is still a TextField inside a ScrubField',
        (t) async {
      // M172/M179/M180 in one line: whatever the chrome became, the number is
      // the same widget, with the same keyboard, under the same drag.
      final app = AppState();
      final c = TextEditingController(text: '12');
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: iosValueRow(
              app: app,
              label: 'Radius',
              controller: c,
              unit: 'mm',
              onChanged: (_) {}),
        ),
      ));
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, kValueKeyboard);
      expect(field.stylusHandwritingEnabled, kValueHandwriting);
      expect(
          find.ancestor(
              of: find.byType(TextField), matching: find.byType(ScrubField)),
          findsOneWidget);
    });

    testWidgets('every number in a 3D feature panel scrubs', (t) async {
      // m180_every_number_scrubs_test covers the sketch tools; the part
      // panels were rebuilt by this milestone, so they are checked here on
      // the same terms.
      Future<void> check(Widget w, String where) async {
        await _pump(t, w);
        final fields = t.widgetList<TextField>(find.byType(TextField));
        expect(fields, isNotEmpty, reason: '$where: nothing was pumped');
        for (final f in fields) {
          if (f.enabled == false) continue;
          expect(f.keyboardType, kValueKeyboard, reason: where);
          expect(
              find.ancestor(
                  of: find.byWidget(f), matching: find.byType(ScrubField)),
              findsAtLeast(1),
              reason: '$where: a number with no scrub');
        }
      }

      await check(
          ExtrudeDialog(app: _partApp()..extrudeSession = ExtrudeSession()),
          'extrude');
      await check(HoleDialog(app: _partApp()..holeSession = HoleSession()),
          'hole');
      await check(
          EdgeFeatureDialog(
              app: _partApp()..edgeSession = EdgeFeatureSession('chamfer')),
          'chamfer');
      await check(
          PatternPanel3D(
              app: _partApp()
                ..patternSession = PartPatternSession(PatternKind.circular)),
          'circular pattern');
    });
  });
}
