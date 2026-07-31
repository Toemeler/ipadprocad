// M172 — the feel of drag-to-scrub, as arithmetic.
//
// A number field you can drag is only as good as its step: too fine and a
// 200 mm plate takes a swipe across the room, too coarse and a 0.5 mm fillet
// is untypeable. The step therefore follows the ZOOM — it is derived from
// what a pixel is worth on screen — and lands on the 1-2-5 ladder so it is
// always a number a person would say out loud.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/scrub.dart';

void main() {
  _scaleTests();

  group('M172 — the step follows the zoom', () {
    test('it is always a 1-2-5 value, never a raw fraction of a pixel', () {
      // Sweep two decades of zoom; every answer must be sayable.
      const ok = [
        0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0
      ];
      for (var upp = 0.002; upp < 30; upp *= 1.07) {
        final s = scrubStep(upp);
        expect(ok.any((v) => (v - s).abs() < 1e-9), isTrue,
            reason: 'unitsPerPixel=$upp gave $s');
      }
    });

    test('zoomed IN gives finer steps than zoomed out', () {
      final tight = scrubStep(0.01); // 1 px = 0.01 mm
      final wide = scrubStep(1.0); //  1 px = 1 mm
      expect(tight, lessThan(wide));
    });

    test('a comfortable zoom lands on half-millimetre notches', () {
      // 1 px ~ 0.03 mm: 14 px of travel is ~0.42 mm, which rounds up to 0.5.
      expect(scrubStep(0.03), 0.5);
    });

    test('a millimetre notch at a normal working zoom', () {
      expect(scrubStep(0.06), 1.0);
    });

    test('centimetre notches when zoomed out', () {
      expect(scrubStep(0.6), 10.0);
    });

    test('it never goes below the floor a dialog can display', () {
      expect(scrubStep(1e-9), 0.1);
      expect(scrubStep(0.0001, min: 0.01), 0.01);
    });

    test('nonsense input cannot produce a nonsense step', () {
      expect(scrubStep(0), 0.1);
      expect(scrubStep(-1), 0.1);
      expect(scrubStep(double.nan), 0.1);
      expect(scrubStep(double.infinity), 0.1);
    });
  });

  group('M172 — where a drag lands', () {
    test('holding still inside the first notch does not move the value', () {
      // The single most important case: a TAP must not change the number.
      expect(scrubbedValue(12.37, 0, 0.5, 0.03), 12.37);
      expect(scrubbedValue(12.37, 3, 0.5, 0.03), 12.37);
    });

    test('one notch of travel is one step', () {
      // step 0.5 at 0.03 mm/px = 16.67 px per notch.
      final v = scrubbedValue(12.0, 17, 0.5, 0.03);
      expect(v, closeTo(12.5, 1e-9));
    });

    test('dragging left goes down', () {
      expect(scrubbedValue(12.0, -17, 0.5, 0.03), closeTo(11.5, 1e-9));
    });

    test('it snaps to the GRID, so the values are round', () {
      // From an awkward start, the first notch lands on a clean number
      // rather than carrying the remainder along.
      expect(scrubbedValue(12.37, 17, 0.5, 0.03), closeTo(12.5, 1e-9));
      expect(scrubbedValue(12.37, 34, 0.5, 0.03), closeTo(13.0, 1e-9));
    });

    test('it is absolute in the drag distance, so it never compounds', () {
      // The widget reports total travel, not deltas: the same distance must
      // always give the same answer however many samples arrive.
      final a = scrubbedValue(10, 50, 1.0, 0.06);
      for (final _ in [1, 2, 3]) {
        expect(scrubbedValue(10, 50, 1.0, 0.06), a);
      }
    });

    test('a long drag scales linearly', () {
      // 1 mm step at 0.06 mm/px = 16.67 px per notch; 167 px ~ 10 notches.
      expect(scrubbedValue(0, 167, 1.0, 0.06), closeTo(10, 1e-9));
    });

    test('negative values are reached and stay on the grid', () {
      expect(scrubbedValue(1.0, -50, 1.0, 0.06), closeTo(-2.0, 1e-9));
    });

    test('nonsense cannot corrupt the value', () {
      expect(scrubbedValue(5, double.nan, 1, 0.06), 5);
      expect(scrubbedValue(5, 10, 0, 0.06), 5);
      expect(scrubbedValue(5, 10, 1, 0), 5);
      expect(scrubbedValue(5, 10, double.nan, 0.06), 5);
    });
  });

  group('M172 — the number shown matches the gesture', () {
    test('decimals follow the step, so there is no false precision', () {
      expect(scrubDecimals(1.0), 0);
      expect(scrubDecimals(10.0), 0);
      expect(scrubDecimals(0.5), 1);
      expect(scrubDecimals(0.1), 1);
      expect(scrubDecimals(0.05), 2);
    });

    test('a broken step still formats something sane', () {
      expect(scrubDecimals(0), 2);
      expect(scrubDecimals(double.nan), 2);
    });
  });
}

// --- the step every field agrees on ---------------------------------------
void _scaleTests() {
  group('M172 — one scale for every field', () {
    test('a sketch scrubs by its 2D zoom', () {
      final app = AppState();
      app.zoom = 20; // 20 px per mm
      expect(app.viewUnitsPerPixel, closeTo(0.05, 1e-12));
      expect(scrubStep(app.viewUnitsPerPixel), 1.0);
    });

    test('zooming in makes every field finer, together', () {
      final app = AppState();
      app.zoom = 200;
      final fine = scrubStep(app.viewUnitsPerPixel);
      app.zoom = 2;
      final coarse = scrubStep(app.viewUnitsPerPixel);
      expect(fine, lessThan(coarse),
          reason: 'a dimension box and an extrude depth must not disagree');
    });

    test('a broken zoom cannot produce a broken step', () {
      final app = AppState();
      app.zoom = 0;
      expect(app.viewUnitsPerPixel, 0.05);
      app.zoom = double.nan;
      expect(app.viewUnitsPerPixel, 0.05);
    });

    test('a part scrubs by the 3D camera, not the sketch zoom', () {
      final app = AppState();
      final p = PartModel('P');
      p.camera.halfH = 40; // 80 mm across an 800 px viewport
      app.parts['P'] = p;
      app.curTab = 'P';
      app.viewportHeightPx = 800;
      expect(app.viewUnitsPerPixel, closeTo(0.1, 1e-12));
    });

    test('a part with a nonsense viewport falls back rather than dividing by 0',
        () {
      final app = AppState();
      final p = PartModel('P');
      app.parts['P'] = p;
      app.curTab = 'P';
      app.viewportHeightPx = 0;
      expect(app.viewUnitsPerPixel, 0.05);
    });
  });
}
