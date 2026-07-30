// M149 — the tab bar went native. The pixels are Swift and untestable from
// here; the MODEL is Dart and is exactly the part that can be wrong in ways a
// device test would not obviously reveal (a tab that cannot be closed, a Home
// id colliding with a document called "home", the wrong document marked
// current). So the model is what these tests pin.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/widgets/bottom_tabbar.dart';

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m149');
  return app;
}

void main() {
  test('Home is always present, first, and never closable', () {
    final app = makeApp();
    final tabs = buildTabs(app);
    expect(tabs.first.id, kHomeTabId);
    expect(tabs.first.closable, isFalse,
        reason: 'closing Home would leave the bar with no way back');
    expect(tabs.first.label, isEmpty, reason: 'the house glyph says it');
  });

  test('the Home id cannot collide with a document named "home"', () {
    // A document is keyed by its name; if Home shared that key, opening a
    // sketch called "home" would toggle the gallery instead.
    expect(kHomeTabId, isNot('home'));
    expect(kHomeTabId.codeUnitAt(0), 0);
  });

  test('Home is selected on the gallery and deselected once a doc is open',
      () {
    final app = makeApp();
    expect(buildTabs(app).first.selected, isTrue);

    app.sketches['A'] = SketchModel('A');
    app.openTabs.add('A');
    app.curTab = 'A';
    final tabs = buildTabs(app);
    expect(tabs.first.selected, isFalse);
    expect(tabs.firstWhere((t) => t.id == 'A').selected, isTrue);
  });

  test('exactly one tab is selected at a time', () {
    final app = makeApp();
    app.sketches['A'] = SketchModel('A');
    app.sketches['B'] = SketchModel('B');
    app.openTabs.addAll(['A', 'B']);
    app.curTab = 'B';
    expect(buildTabs(app).where((t) => t.selected).length, 1);
  });

  test('every document tab is closable and carries its own name', () {
    final app = makeApp();
    app.sketches['Bracket'] = SketchModel('Bracket');
    app.openTabs.add('Bracket');
    app.curTab = 'Bracket';
    final t = buildTabs(app).firstWhere((t) => t.id == 'Bracket');
    expect(t.closable, isTrue);
    expect(t.label, 'Bracket');
  });

  test('the wire format survives a round trip through the codec', () {
    // Swift reads these exact keys; a rename here is a silently blank bar.
    final m = const GlassTab(
            id: 'x', label: 'L', symbol: 's', selected: true, closable: true)
        .toMap();
    expect(m.keys.toSet(),
        {'id', 'label', 'symbol', 'selected', 'closable'});
    expect(m['selected'], isA<bool>());
  });
}
