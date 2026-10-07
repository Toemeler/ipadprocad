// M490 — desktop UX flows found by driving the real Linux app like a
// first-time Inventor user (mouse + keyboard), one group per finding.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/viewport.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
  // A close-enough sRGB linearisation (gamma 2) for a contrast floor.
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('tooltips are readable', () {
    // The ribbon on a desktop is icons only; its tooltip is the only name a
    // tool has. On the light palette the text was near-white on white.
    for (final (name, p) in [('light', kChalk), ('dark', kEmber)]) {
      test('$name palette: tooltip text contrasts with its surface', () {
        final th = materialTheme(p).tooltipTheme;
        final fg = th.textStyle!.color!;
        final bg = (th.decoration! as BoxDecoration).color!;
        expect(_contrast(fg, bg), greaterThan(4.5),
            reason: 'text $fg on $bg');
      });
    }
  });

  group('the sketch status line speaks the UI language', () {
    testWidgets('German: "N Bemaßungen erforderlich", not English', (t) async {
      final app = AppState();
      final s = SketchModel('t');
      app.sketches['t'] = s;
      app.curTab = 't';
      app.editingLayer = kDefaultLayer;
      app.tool = Tool.rectTwoPoint;
      app.toolClick(const Offset(0, 0));
      app.toolClick(const Offset(40, 30));
      expect(app.analysis, isNotNull);
      final dof = app.analysis!.dof;
      expect(dof, greaterThan(1));
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox.expand(child: Viewport2D(app: app)))));
      await t.pump();
      expect(find.textContaining('dimensions needed'), findsNothing);
      expect(find.text('$dof Bemaßungen erforderlich'), findsOneWidget);
    });
  });
}
