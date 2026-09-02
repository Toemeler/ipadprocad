// M361 — the retracted browser says WHICH extrusion each cube is.
//
//   "the icons in the retracted Modell browser should have a letter small on a
//    corner of the icon. E for extrude and a number. E2, E3 and so on or r for
//    revolve. And there should be spacing when a folder ends or starts. Also W
//    for workplane"
//
// Retracted, the panel is a column of pictures and nothing else: M200 strips
// the labels, M204 the disclosure box, and compact() the indentation. That is
// the right trade for a 34 pt column, but it costs the two things a tree uses
// to say what it holds — the NAMES and the STRUCTURE. Three extrusions draw
// the same cube three times, and the Origin folder's seven entries run
// straight on from the timeline as one undifferentiated stack.
//
// The badge gives the name back, compressed to what fits in a corner: a letter
// for the kind, a number for which one of them this is. The gap gives the
// structure back, in the only currency left once indentation has gone.
//
// WHAT THIS FILE DOES NOT COVER. The badge is DRAWN in Swift, into the glyph
// (GlassBrowser.badged) — composed as an image rather than added as a subview,
// because a UIListContentConfiguration owns its image view and a second view
// beside it has to be found, placed and torn down on every cell reuse. That
// drawing cannot be exercised from a host test; what is testable, and what is
// tested here, is every decision that reaches it: which rows carry a badge,
// what it says, and where the gaps fall.
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/native_browser.dart';

/// Features must name a REAL sketch or the fold cannot build them.
const String _sk = 'Sketch1';

ExtrudeFeature _ex(String name) => ExtrudeFeature(
    name: name,
    bodyName: 'Body1',
    sketchName: _sk,
    profiles: [ProfileSel(10, 5, 200)]);

RevolveFeature _rev(String name) => RevolveFeature(
    name: name,
    bodyName: 'Body1',
    sketchName: _sk,
    profiles: [ProfileSel(10, 5, 200)]);

/// A part with a sketch and whatever features are handed in, in order.
AppState _part(List<PartFeature> features, {int planes = 0}) {
  final app = AppState();
  final p = PartModel('Part1');
  final m = SketchModel('Sketch1');
  m.layers.add('Layer 1');
  m.eosAfter = 1;
  p.childSketches.add(ChildSketch(m, 'xy'));
  // A second sketch, consumed by nothing, so it stands in the timeline as its
  // own row rather than nesting under the feature that ate it.
  final spare = SketchModel('Sketch2');
  spare.layers.add('Layer 1');
  spare.eosAfter = 1;
  p.childSketches.add(ChildSketch(spare, 'xy')..seq = 5);
  var seq = 10;
  for (final f in features) {
    f.seq = seq += 10;
    p.features.add(f);
  }
  for (var i = 0; i < planes; i++) {
    p.workPlanes.add(WorkPlane('Arbeitsebene${i + 1}', seq += 10,
        WorkPlaneKind.offset, 'Offset 10.00 mm from XY',
        offsetPlaneFrame(planeFrame('xy'), 10.0 * (i + 1))));
  }
  app.parts['Part1'] = p;
  app.curTab = 'Part1';
  return app;
}

List<GlassRow> _rows(AppState app, {bool collapsed = true}) =>
    buildBrowserRows(app, expanded: const {}, collapsed: collapsed);

GlassRow _byId(List<GlassRow> rows, String id) =>
    rows.firstWhere((r) => r.id == id);

void main() {
  // -------------------------------------------------------------------------
  group('the letter and the number', () {
    test('three extrusions are E1, E2, E3, in tree order', () {
      // The report itself: "E for extrude and a number. E2, E3 and so on".
      final app = _part([_ex('Extrusion1'), _ex('Extrusion2'), _ex('Extrusion3')]);
      final rows = _rows(app);
      expect([
        for (final n in ['Extrusion1', 'Extrusion2', 'Extrusion3'])
          _byId(rows, '$kIdFeature$n').badge
      ], ['E1', 'E2', 'E3']);
    });

    test('a revolve between them is R1, and the extrusions keep counting', () {
      // Per LETTER, not per position: the numbering has to be the ordinal you
      // would count off the panel. Numbering by the feature's own seq would
      // give this part E1 and E3.
      final app = _part([_ex('Extrusion1'), _rev('Drehung1'), _ex('Extrusion2')]);
      final rows = _rows(app);
      expect(_byId(rows, '${kIdFeature}Extrusion1').badge, 'E1');
      expect(_byId(rows, '${kIdFeature}Drehung1').badge, 'R1');
      expect(_byId(rows, '${kIdFeature}Extrusion2').badge, 'E2');
    });

    test('work planes are W, and numbered apart from the features', () {
      // "Also W for workplane". A document's third work plane is W3 however
      // many extrusions sit between them.
      final app = _part([_ex('Extrusion1')], planes: 2);
      final rows = _rows(app);
      final w = [
        for (final r in rows)
          if (r.id.startsWith(kIdWorkPlane)) r.badge
      ];
      expect(w, ['W1', 'W2']);
    });

    test('a sketch in the timeline is S1', () {
      final app = _part([_ex('Extrusion1')]);
      expect(_byId(_rows(app), '${kIdSketch}Sketch2').badge, 'S1');
    });

    test('a folder wears none', () {
      // A folder already says what it is — Inventor's amber, which nothing
      // else in the tree uses. A letter on it would be a second answer to a
      // question that is not being asked.
      final rows = _rows(_part([_ex('Extrusion1')]));
      for (final r in rows.where((r) => r.tint == 'folder')) {
        expect(r.badge, isNull, reason: r.id);
      }
    });

    test('every kind that can repeat has a letter, and they are distinct', () {
      // The table is what the panel reads; two kinds sharing a letter would
      // put E2 on a revolve.
      expect(kFeatureBadge.values.toSet().length, kFeatureBadge.length);
      expect(
          {
            ...kFeatureBadge.values,
            kBadgeWorkPlane,
            kBadgeWorkAxis,
            kBadgeWorkPoint,
            kBadgeSketch,
          }.length,
          kFeatureBadge.length + 4);
    });

    test('and a second document starts again at 1', () {
      // The counter is per BUILD, not a global: opening a second part beside
      // the first must not give its only extrusion E4.
      final a = _part([_ex('E'), _ex('F'), _ex('G')]);
      _rows(a);
      final b = _part([_ex('OnlyOne')]);
      expect(_byId(_rows(b), '${kIdFeature}OnlyOne').badge, 'E1');
    });

    test('and asking twice gives the same answers', () {
      // A rebuild happens on every AppState notification. A counter that kept
      // running across builds would renumber the panel as you worked.
      final app = _part([_ex('Extrusion1'), _ex('Extrusion2')]);
      final first = _rows(app);
      final second = _rows(app);
      for (final r in first) {
        expect(_byId(second, r.id).badge, r.badge, reason: r.id);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the gap', () {
    test('a folder row asks for space above it', () {
      final rows = _rows(_part([_ex('Extrusion1')]));
      final folders = rows.where((r) => r.tint == 'folder').toList();
      expect(folders, isNotEmpty, reason: 'a part should have folders');
      for (final f in folders) {
        expect(f.gapBefore, isTrue, reason: '${f.id} starts a folder');
      }
    });

    test('and so does the first row after one ENDS', () {
      // The half that is easy to forget. Without it the last child of a
      // folder and the folder's next sibling are flush, which reads as if the
      // child belonged to the timeline.
      // The Origin folder OPEN, so there is a folder with contents for the
      // tree to come back out of. Closed, nothing ever gets shallower and the
      // rule has nothing to fire on.
      final rows = buildBrowserRows(_part([_ex('Extrusion1')]),
          expanded: const {'origin'}, collapsed: false);
      var found = false;
      for (var i = 1; i < rows.length; i++) {
        if (rows[i].depth < rows[i - 1].depth) {
          expect(rows[i].gapBefore, isTrue,
              reason: '${rows[i].id} comes back out from '
                  '${rows[i - 1].id} and should be spaced off it');
          found = true;
        }
      }
      expect(found, isTrue, reason: 'no folder closed — the test proves nothing');
    });

    test('never above the very first row', () {
      // A gap at the top of the panel separates nothing from nothing; it is
      // just the column starting in the wrong place.
      expect(_rows(_part([_ex('Extrusion1')])).first.gapBefore, isFalse);
    });

    test('and the gap survives the retract, where it is the only grouping left',
        () {
      // compact() takes the depth away, so this is the ONE thing standing
      // between the timeline and the Origin folder in a 34 pt column.
      final wide = buildBrowserRows(_part([_ex('Extrusion1')]),
          expanded: const {}, collapsed: false);
      final narrow = _rows(_part([_ex('Extrusion1')]));
      expect(narrow.map((r) => r.gapBefore).toList(),
          wide.map((r) => r.gapBefore).toList());
      expect(narrow.every((r) => r.depth == 0), isTrue);
      expect(narrow.any((r) => r.gapBefore), isTrue);
    });

    test('and so does the badge', () {
      final narrow = _rows(_part([_ex('Extrusion1')]));
      expect(_byId(narrow, '${kIdFeature}Extrusion1').badge, 'E1');
      expect(_byId(narrow, '${kIdFeature}Extrusion1').label, '',
          reason: 'retracted rows carry no label — that is why they need one');
    });
  });

  // -------------------------------------------------------------------------
  group('what crosses to the native side', () {
    test('both ride in the row map, and only when they are set', () {
      final rows = _rows(_part([_ex('Extrusion1')]));
      final feature = _byId(rows, '${kIdFeature}Extrusion1').toMap();
      expect(feature['badge'], 'E1');
      // Absent rather than null: the Swift side reads `m["badge"] as? String`,
      // and a key that is present but null is a key it has to think about.
      final root = rows.first.toMap();
      expect(root.containsKey('badge'), isFalse);
      expect(root.containsKey('gapBefore'), isFalse);
    });
  });
}
