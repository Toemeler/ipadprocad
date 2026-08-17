// M222 — "when i slice graphics there are triangles visible ... different
// parts should have different schraffur, like in iso norm."
//
// Reported against build `1a0bb61` (M210) and left open there as "a render
// fault plus a real feature". The render fault is one line of intent: the
// painter built ONE Path out of every mesh TRIANGLE of the section and then
// stroked it as "the section outline". A triangle soup has no outline — every
// shared edge is in that path twice and gets drawn, so what reached the screen
// was the tessellation. It also changes whenever the model is re-meshed, which
// is why it looked random.
//
// sectionOutlines() keeps only the edges that belong to a single triangle,
// which is the definition of a boundary, and stitches them into closed loops.
// The ISO half then falls out of grouping those loops by BODY: ISO 128-50 asks
// that adjacent parts be told apart by hatch direction or spacing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

double _area(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].dx * p[j].dy - p[j].dx * p[i].dy;
  }
  return a / 2; // SIGNED: the winding is part of the answer
}

/// The eight triangles of a 10x10 square with a 2x2 hole in the middle, wound
/// counter-clockwise, the way a mesher hands a face over.
List<List<Offset>> _ringSoup() {
  const o = [
    Offset(0, 0),
    Offset(10, 0),
    Offset(10, 10),
    Offset(0, 10),
  ];
  const i = [
    Offset(4, 4),
    Offset(6, 4),
    Offset(6, 6),
    Offset(4, 6),
  ];
  final out = <List<Offset>>[];
  for (var k = 0; k < 4; k++) {
    final k1 = (k + 1) % 4;
    out.add([o[k], o[k1], i[k1]]);
    out.add([o[k], i[k1], i[k]]);
  }
  return out;
}

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m222_');
  app.partKernel = FakeKernel();
  return app;
}

void main() {
  group('M222 — a section has an outline, a mesh has edges', () {
    test('the shared edge of two triangles is NOT drawn', () {
      // A square split along its diagonal — the case that put a diagonal line
      // across every flat section face on screen.
      final tris = [
        [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)],
        [const Offset(0, 0), const Offset(10, 10), const Offset(0, 10)],
      ];
      final loops = sectionOutlines(tris);
      expect(loops.length, 1);
      expect(loops.single.length, 4,
          reason: 'the square, not two triangles sharing a diagonal');
      expect(_area(loops.single).abs(), closeTo(100, 1e-9));
      // The diagonal's endpoints are both corners, so the giveaway is that no
      // corner appears twice.
      final seen = <String>{};
      for (final p in loops.single) {
        expect(seen.add('${p.dx},${p.dy}'), isTrue, reason: 'no repeats');
      }
    });

    test('a face with a hole comes back as two loops, wound apart', () {
      final loops = sectionOutlines(_ringSoup());
      expect(loops.length, 2);
      final outer = loops.firstWhere((l) => _area(l).abs() > 50);
      final hole = loops.firstWhere((l) => _area(l).abs() < 50);
      expect(_area(outer), closeTo(100, 1e-9),
          reason: 'the boundary walk keeps the triangles’ own winding');
      expect(_area(hole), closeTo(-4, 1e-9),
          reason: 'a hole must wind the other way, or it would fill in');
      expect(outer.length, 4);
      expect(hole.length, 4);
    });

    test('vertices that differ in the last bit are the same vertex', () {
      // Two triangles of one face meet at coordinates the kernel calls equal;
      // the transform into sketch (u,v) can move them apart in the last bit.
      // Un-welded, every interior edge would look like two boundary edges and
      // the whole soup would come back.
      const eps = 1e-9;
      final tris = [
        [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)],
        [
          const Offset(eps, eps),
          const Offset(10 + eps, 10 - eps),
          const Offset(0, 10),
        ],
      ];
      final loops = sectionOutlines(tris);
      expect(loops.length, 1);
      expect(loops.single.length, 4);
    });

    test('a lone triangle is its own outline', () {
      final loops = sectionOutlines([
        [const Offset(0, 0), const Offset(10, 0), const Offset(0, 10)],
      ]);
      expect(loops.length, 1);
      expect(loops.single.length, 3);
    });

    test('nothing in, nothing out', () {
      expect(sectionOutlines(const []), isEmpty);
    });

    test('two separate faces stay two separate outlines', () {
      final tris = [
        [const Offset(0, 0), const Offset(1, 0), const Offset(0, 1)],
        [const Offset(5, 5), const Offset(6, 5), const Offset(5, 6)],
      ];
      expect(sectionOutlines(tris).length, 2,
          reason: 'a body can be cut in more than one place');
    });
  });

  group('M222 — ISO 128 hatching', () {
    test('neighbouring bodies never draw the same hatch', () {
      for (var i = 0; i + 1 < kSectionHatch.length; i++) {
        expect(kSectionHatch[i], isNot(kSectionHatch[i + 1]));
      }
      expect(kSectionHatch.toSet().length, kSectionHatch.length,
          reason: 'four distinct styles, or the cycle repeats early');
    });

    test('direction alternates, and the repeat differs in spacing', () {
      // ISO 128-50: adjacent parts differ by DIRECTION where possible, and by
      // spacing when the direction has to come round again.
      expect(kSectionHatch[0].$1, isNot(kSectionHatch[1].$1));
      expect(kSectionHatch[2].$1, kSectionHatch[0].$1);
      expect(kSectionHatch[2].$2, isNot(kSectionHatch[0].$2));
    });
  });

  group('M222 — what the painter is handed', () {
    test('nothing at all while slicing is off', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
      expect(app.sliceGraphics, isFalse);
      expect(app.sectionSlices(), isEmpty);
    });

    test('a slice carries its body name and a style index', () {
      // The grouping contract, without a kernel in the way.
      const s = SectionSlice('Solid2', [
        [Offset(0, 0), Offset(1, 0), Offset(0, 1)]
      ], 1);
      expect(s.body, 'Solid2');
      expect(s.loops.single.length, 3);
      expect(kSectionHatch[s.style % kSectionHatch.length],
          kSectionHatch[1]);
    });
  });
}
