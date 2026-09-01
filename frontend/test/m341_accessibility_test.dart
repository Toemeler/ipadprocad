// M341 — the dialog layer answers to VoiceOver, to a haptic, and to Dynamic
// Type.
//
// M338 drew the panels to Apple's measurements. What it did not do is make
// them USABLE the way Apple means it: every control in the kit was a bare
// `GestureDetector`, which is silent to VoiceOver rather than wrong, and so
// the omission was invisible in a screenshot. These tests pin the three
// things a screenshot cannot show.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ios_design.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/edge_feature_dialog.dart';
import 'package:prototype/widgets/extrude_dialog.dart';
import 'package:prototype/widgets/ios_kit.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/qcad_engine.dart' show kDefaultLayer;
import 'package:prototype/widgets/combine_dialog.dart';
import 'package:prototype/widgets/constraint_dialog.dart';
import 'package:prototype/widgets/create_component_dialog.dart';
import 'package:prototype/widgets/freehand_dialog.dart';
import 'package:prototype/widgets/hole_dialog.dart';
import 'package:prototype/widgets/joint_dialog.dart';
import 'package:prototype/widgets/make_part_dialog.dart';
import 'package:prototype/widgets/parameters_dialog.dart';
import 'package:prototype/widgets/pattern_dialog.dart';
import 'package:prototype/widgets/split_dialog.dart';
import 'package:prototype/widgets/text_editor_window.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
  ));
  await t.pump();
  while (t.takeException() != null) {}
}

/// Records the haptic calls the platform would have made.
List<String> _recordHaptics(WidgetTester t) {
  final fired = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') fired.add('${call.arguments}');
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return fired;
}

void main() {
  setUp(() {
    L.set(kEn);
    T.palette = kEmber;
  });

  group('M341 — VoiceOver', () {
    testWidgets('a segment says its name, that it is a button, and whether '
        'it is the chosen one', (t) async {
      final h = t.ensureSemantics();
      await _pump(
        t,
        IosSegmented<int>(
          value: 1,
          onChanged: (_) {},
          segments: const [
            IosSegment(value: 0, label: 'Distance'),
            IosSegment(value: 1, label: 'Angle'),
          ],
        ),
      );
      expect(
          t.getSemantics(find.text('Angle')),
          isSemantics(
              label: 'Angle', isButton: true, isSelected: true, hasTapAction: true));
      expect(t.getSemantics(find.text('Distance')),
          isSemantics(label: 'Distance', isSelected: false));
      h.dispose();
    });

    testWidgets('a glyph button borrows its tooltip, because it has no words '
        'of its own', (t) async {
      final h = t.ensureSemantics();
      await _pump(
          t,
          IosCircleButton(
              glyph: IosGlyph.play, tooltip: 'Play', onTap: () {}));
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      h.dispose();
    });

    testWidgets('a switch row is ONE toggle, not a button wrapped round a '
        'switch', (t) async {
      final h = t.ensureSemantics();
      await _pump(
          t,
          iosSwitchRow(
              label: 'Swap Faces', value: true, onChanged: (_) {}));
      final n = t.getSemantics(find.bySemanticsLabel('Swap Faces'));
      expect(n, isSemantics(label: 'Swap Faces', isToggled: true));
      // The switch's own node must not survive alongside the row's, or there
      // are two things to swipe through for one control.
      expect(find.bySemanticsLabel('Swap Faces'), findsOneWidget);
      h.dispose();
    });

    testWidgets('a disabled control is not offered as a button', (t) async {
      final h = t.ensureSemantics();
      await _pump(
          t, const IosButton(label: 'Apply', onTap: null));
      expect(t.getSemantics(find.text('Apply')),
          isSemantics(isButton: false, hasEnabledState: true, isEnabled: false));
      h.dispose();
    });

    testWidgets('a disclosure header says whether it is open', (t) async {
      final h = t.ensureSemantics();
      await _pump(
          t,
          iosSection(
            header: 'Shape',
            open: false,
            onToggle: () {},
            children: const [SizedBox(height: 10)],
          ));
      expect(t.getSemantics(find.text('Shape')),
          isSemantics(isExpanded: false, isButton: true));
      h.dispose();
    });
  });

  group('M341 — the feel', () {
    testWidgets('a segmented control ticks, the way the scrub and the pad do',
        (t) async {
      final fired = _recordHaptics(t);
      await _pump(
        t,
        IosSegmented<int>(
          value: 0,
          onChanged: (_) {},
          segments: const [
            IosSegment(value: 0, label: 'A'),
            IosSegment(value: 1, label: 'B'),
          ],
        ),
      );
      await t.tap(find.text('B'));
      expect(fired, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('a switch row ticks once, whichever half you hit', (t) async {
      var v = false;
      final fired = _recordHaptics(t);
      await _pump(t, iosSwitchRow(label: 'Flip', value: v, onChanged: (x) => v = x));
      await t.tap(find.text('Flip'));
      expect(v, true, reason: 'the label is part of the control');
      expect(fired.length, 1, reason: 'one tap is one tick, not two');
    });

    testWidgets('a plain button stays SILENT, because iOS leaves Cancel and '
        'OK silent', (t) async {
      final fired = _recordHaptics(t);
      await _pump(t, IosButton(label: 'OK', onTap: () {}));
      await t.tap(find.text('OK'));
      expect(fired, isEmpty);
    });
  });

  group('M341 — Dynamic Type', () {
    Future<Size> sizeAt(WidgetTester t, double scale, Widget w) async {
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: Center(child: SizedBox(width: 320, child: w))),
        ),
      ));
      await t.pump();
      while (t.takeException() != null) {}
      return t.getSize(find.byType(IosSegmented<int>).evaluate().isNotEmpty
          ? find.byType(IosSegmented<int>)
          : find.byType(IosButton));
    }

    final seg = IosSegmented<int>(
      value: 0,
      onChanged: (_) {},
      segments: const [
        IosSegment(value: 0, label: 'Distance'),
        IosSegment(value: 1, label: 'Through All'),
      ],
    );

    testWidgets('a segmented control gets TALLER for a larger text size, '
        'because a 32 pt track cannot hold 40 pt words', (t) async {
      final small = await sizeAt(t, 1.0, seg);
      final large = await sizeAt(t, 2.0, seg);
      expect(small.height, IosMetrics.segment);
      expect(large.height, greaterThan(small.height));
    });

    testWidgets('and stops growing at the cap, the way a tab bar does',
        (t) async {
      // 1.4 is this control's cap. Past it the words stop fitting side by
      // side however tall the track gets, so the kit holds the line rather
      // than shipping a control that ellipsises to nothing.
      final atCap = await sizeAt(t, 1.4, seg);
      final past = await sizeAt(t, 3.1, seg);
      expect(past.height, atCap.height);
      expect(atCap.height, closeTo(IosMetrics.segment * 1.4, 0.01));
    });

    testWidgets('the label inside is clamped too, so the track and its words '
        'can never disagree', (t) async {
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3.1)),
          child: Scaffold(body: Center(child: SizedBox(width: 320, child: seg))),
        ),
      ));
      await t.pump();
      while (t.takeException() != null) {}
      final text = t.widget<Text>(find.text('Distance'));
      final scaler = MediaQuery.of(t.element(find.text('Distance'))).textScaler;
      expect(scaler.scale(13), lessThanOrEqualTo(13 * 1.4 + 0.01));
      expect(text.maxLines, 1);
    });

    testWidgets('a button grows too, and a row was already growing on its own',
        (t) async {
      final small = await sizeAt(t, 1.0, IosButton(label: 'OK', onTap: () {}));
      final large = await sizeAt(t, 2.0, IosButton(label: 'OK', onTap: () {}));
      expect(large.height, greaterThan(small.height));
    });
  });

  // A kit that behaves on its own and a PANEL that behaves are different
  // claims. These pump the real thing.
  group('M341 — and it holds in a real panel', () {
    AppState partApp() {
      final app = AppState();
      app.parts['Part1'] = PartModel('Part1');
      app.curTab = 'Part1';
      return app;
    }

    Future<void> pumpPanel(WidgetTester t, Widget w, double scale) async {
      t.view.physicalSize = const Size(2200, 2800);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Stack(children: [w])),
        ),
      ));
      await t.pump();
      // The test font is a wide monospaced stand-in, so overflow here is a
      // fact about a font that does not ship. m338 makes the same allowance.
      while (t.takeException() != null) {}
    }

    testWidgets('the extrude panel reaches VoiceOver as named buttons, not as '
        'a silent picture', (t) async {
      final h = t.ensureSemantics();
      await pumpPanel(
          t, ExtrudeDialog(app: partApp()..extrudeSession = ExtrudeSession()),
          1.0);
      final en = L.stringsFor(kEn);
      // The two verbs a panel must offer, both actually announced.
      expect(find.bySemanticsLabel(en.cancel), findsOneWidget);
      expect(find.bySemanticsLabel(en.ok), findsOneWidget);
      h.dispose();
    });

    testWidgets('every tappable thing in the panel has SOMETHING to be called '
        'by', (t) async {
      final h = t.ensureSemantics();
      await pumpPanel(
          t,
          EdgeFeatureDialog(
              app: partApp()..edgeSession = EdgeFeatureSession('fillet')),
          1.0);
      // Walk the panel the way VoiceOver would and fail on a button with no
      // name — which is exactly the state the whole kit was in before this
      // milestone, on every control at once.
      final unnamed = <String>[];
      for (final node in t.semantics.simulatedAccessibilityTraversal()) {
        final d = node.getSemanticsData();
        if (d.flagsCollection.isButton && d.label.trim().isEmpty) {
          unnamed.add(d.toString());
        }
      }
      expect(unnamed, isEmpty, reason: 'a button VoiceOver cannot name');
      h.dispose();
    });

    testWidgets('and the panel still lays out at an accessibility text size',
        (t) async {
      await pumpPanel(
          t, ExtrudeDialog(app: partApp()..extrudeSession = ExtrudeSession()),
          3.1);
      expect(find.byType(IosPanel), findsOneWidget);
      // It scrolls rather than overflowing: the panel caps its height and the
      // rows below the fold are reachable.
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  // Every panel, at the largest size iOS offers. A control that behaves in
  // isolation and a PANEL that behaves are different claims, and the nav bar
  // is the proof: it passed every widget test in this file while overflowing
  // by 126 pt on a real dialog.
  group('M341 — no panel overflows at the accessibility sizes', () {
    AppState sketchApp() {
      final app = AppState();
      app.sketches['t'] = SketchModel('t');
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      return app;
    }

    AppState partApp() {
      final app = AppState();
      app.parts['Part1'] = PartModel('Part1');
      app.curTab = 'Part1';
      return app;
    }

    AppState asmApp() {
      final app = AppState();
      app.assemblies['Gearbox'] = AssemblyModel('Gearbox');
      app.openTabs.add('Gearbox');
      app.curTab = 'Gearbox';
      return app;
    }

    final panels = <String, Widget Function()>{
      'Extrude': () =>
          ExtrudeDialog(app: partApp()..extrudeSession = ExtrudeSession()),
      'Hole': () => HoleDialog(app: partApp()..holeSession = HoleSession()),
      'Fillet': () => EdgeFeatureDialog(
          app: partApp()..edgeSession = EdgeFeatureSession('fillet')),
      'Chamfer': () => EdgeFeatureDialog(
          app: partApp()..edgeSession = EdgeFeatureSession('chamfer')),
      'Combine': () =>
          CombineDialog(app: partApp()..combineSession = CombineSession()),
      'Split': () => SplitDialog(app: partApp()..splitSession = SplitSession()),
      'Create Component': () => CreateComponentDialog(
          app: partApp()..createComponentSession = CreateComponentSession('Part2')),
      'Make Part': () => MakePartDialog(
          app: partApp()
            ..makePartSession = MakePartSession('Solid1', 'Part2', 'Assembly1')),
      'Place Constraint': () => ConstraintDialog(app: asmApp()..openConstraint()),
      'Place Joint': () => JointDialog(app: asmApp()..openConstraint()),
      'Pattern 2D': () =>
          PatternDialog(app: sketchApp()..pattern = PatternSession(Tool.patRect)),
      'Mirror 2D': () =>
          PatternDialog(app: sketchApp()..pattern = PatternSession(Tool.mirror)),
      'Polygon': () => PolygonDialog(app: sketchApp()..tool = Tool.polygon),
      'Parameters': () => ParametersDialog(app: sketchApp(), onDrag: (_) {}),
      'Freehand': () =>
          FreehandDialog(app: sketchApp()..freehand = FreehandSession(), onDrag: (_) {}),
      'Text': () => TextEditorWindow(app: sketchApp(), onDrag: (_) {}),
    };

    panels.forEach((name, build) {
      testWidgets('$name lays out at 3.1x', (t) async {
        t.view.physicalSize = const Size(2200, 2800);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
            // copyWith, NOT a bare MediaQueryData: a fresh one has size zero,
            // and then the panel's own maximum height is nonsense and the
            // test invents overflows that the app does not have.
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(3.1)),
              child: Scaffold(body: Stack(children: [build()])),
            );
          }),
        ));
        await t.pump();
        final overflows = <String>[];
        for (var e = t.takeException(); e != null; e = t.takeException()) {
          final m = RegExp(r'overflowed by ([\d.]+) pixels on the (\w+)')
              .firstMatch(e.toString());
          if (m != null) overflows.add('${m[1]}px ${m[2]}');
        }
        expect(overflows, isEmpty, reason: '$name at 3.1x');
      });
    });
  });
}
