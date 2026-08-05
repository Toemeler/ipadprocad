// M204 — the retracted browser you can actually press.
//
//   "the expand arrow is too much to the right and when its retracted i cant
//    use the icons"   (bug20260805T131020)
//
// Two separate things.
//
// THE ARROW. M199 took the glass away when the panel retracts, so what is left
// at 78 pt is a 16 pt glyph column and 40 pt of nothing, with the chevron strip
// parked out past all of it. The card is 56 pt now: 14 of inset plus the glyph.
// That width is a private constant of the host widget, so what is testable here
// is its consequence — at 34 pt of content a row cannot carry a 16 pt
// disclosure box AND a 16 pt glyph, so the box goes.
//
// THE ICONS. The card is a UiKitView, and resizing one is an awaited round trip
// to the platform view controller, not a Dart layout pass. Animating the width
// fired that round trip on every frame of a 220 ms curve; the resize that lands
// last need not be the one sent last, and Flutter paints the view's texture at
// the widget's size either way — so the icons appeared where the touch
// interceptor no longer was. The animation is gone (one state change, one
// resize). That lives in the widget's build and is not reachable from a headless
// test; the honest note is that it is UNVERIFIED here and only the device can
// confirm it. What the tests below do cover is that the retracted panel offers
// a target for everything the wide one does.
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/native_browser.dart';

AppState part() {
  final app = AppState();
  final p = PartModel('Part4');
  final m = SketchModel('Sketch1');
  m.layers.add('Layer 1');
  m.eosAfter = 1;
  p.childSketches.add(ChildSketch(m, 'xy'));
  app.parts['Part4'] = p;
  app.curTab = 'Part4';
  return app;
}

List<GlassRow> collapsed(AppState app) =>
    buildBrowserRows(app, expanded: const {'bodies'}, collapsed: true);

List<GlassRow> wide(AppState app) =>
    buildBrowserRows(app, expanded: const {'bodies'});

void main() {
  test('THE REPORT: no disclosure box survives the collapse', () {
    final rows = collapsed(part());
    expect(rows.where((r) => r.expandable), isEmpty,
        reason: '16 pt of box + 16 pt of glyph do not fit in 34 pt of row');
  });

  test('and the wide panel still has one — this is a VIEW, not a model change',
      () {
    expect(wide(part()).where((r) => r.expandable), isNotEmpty);
  });

  test('the folder is still listed, it just has no little box', () {
    // Losing the box must not lose the row: tapping a folder row toggles it
    // (the host has done that since M121), so the target is the whole row.
    // (Solid Bodies only appears once the part has one, so Origin is the
    // folder a fresh part always shows.)
    expect(collapsed(part()).map((r) => r.id), contains('origin'));
  });

  test('an expanded folder still shows its children when retracted', () {
    // If the box is the only way to expand, dropping it would strand whatever
    // is inside. The expansion state is the host's, and the rows follow it.
    final app = part();
    final open = buildBrowserRows(app,
        expanded: const {'bodies', 'origin'}, collapsed: true);
    final shut =
        buildBrowserRows(app, expanded: const {'bodies'}, collapsed: true);
    expect(open.length, greaterThan(shut.length),
        reason: 'the Origin folder\'s planes');
  });

  test('compact() keeps everything a target needs', () {
    const r = GlassRow(
      id: 'x',
      label: 'Extrusion1',
      depth: 3,
      symbol: 'cube',
      hasEye: true,
      dim: true,
      expandable: true,
      expanded: true,
      selected: true,
      isEop: true,
      tint: 'blue',
      menu: [
        [GlassMenuItem(id: 'a', title: 'A')]
      ],
    );
    final c = r.compact();
    expect(c.id, 'x', reason: 'the id is what comes back on tap');
    expect(c.symbol, 'cube');
    expect(c.selected, isTrue);
    expect(c.dim, isTrue);
    expect(c.tint, 'blue');
    expect(c.isEop, isTrue);
    expect(c.menu.length, 1);
    // and what the narrow card has no room for
    expect(c.label, isEmpty);
    expect(c.depth, 0);
    expect(c.hasEye, isFalse);
    expect(c.expandable, isFalse);
  });

  test('the two widths still list the same rows, in the same order', () {
    // M199's contract, re-asserted: dropping the box must not drop a row.
    final app = part();
    expect(collapsed(app).map((r) => r.id).toList(),
        wide(app).map((r) => r.id).toList());
  });
}
