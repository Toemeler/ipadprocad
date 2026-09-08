// M398 — the rectangle a glass panel hands its shader, under a transform.
//
// The class comment on _RenderLiquidGlass promises this survives "a repaint
// boundary or a transform", and half of it did not: the ORIGIN went through
// `localToGlobal`, which applies every ancestor transform, and the EXTENT came
// from the panel's own local size, which does not. The two agree exactly until
// something scales the subtree.
//
// Something did. The Windows build drew the whole app inside a 0.75 Transform
// (M388) and published a MediaQuery device pixel ratio 0.75x the truth to go
// with it, and a device came back with white slabs where the glass should
// have been — "liquidglass elements look false" (#19). That scale is gone
// (M391 took it out, because it also made a quarter of the window unclickable
// and the look could not be judged from here), so on every platform this is
// now arithmetic that lands where it already did — which the "no transform"
// cases below pin as firmly as the scaled ones.
//
// It is worth having anyway. M391's own note proposes a density pass over the
// constants as the way to make the Windows UI smaller, and whoever writes it
// should not have to rediscover that a backdrop rectangle is measured in a
// space a Transform changes.
import 'dart:ui' show Offset, Size, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/liquid_glass.dart';

void main() {
  group('the rectangle a glass panel occupies in the backdrop', () {
    test('with no transform above it, it is the panel times the ratio', () {
      final g = glassDeviceRect(
        topLeftGlobal: const Offset(100, 50),
        bottomRightGlobal: const Offset(400, 250),
        localSize: const Size(300, 200),
        devicePixelRatio: 2,
      );
      expect(g.rect, const Rect.fromLTRB(200, 100, 800, 500));
      // Radii and rim widths are authored in local points; with nothing
      // scaling the panel their conversion is just the ratio.
      expect(g.unit, 2);
    });

    test('under a 0.75 scale the EXTENT shrinks with the origin', () {
      // A 300x200 panel whose top-left sits at local-global (400, 300) inside
      // a subtree scaled by 0.75: the window sees it at (300, 225) and
      // 225x150 big. Both corners come back through localToGlobal, so both
      // carry the scale.
      final g = glassDeviceRect(
        topLeftGlobal: const Offset(300, 225),
        bottomRightGlobal: const Offset(525, 375),
        localSize: const Size(300, 200),
        devicePixelRatio: 2,
      );
      expect(g.rect, const Rect.fromLTRB(600, 450, 1050, 750));
      expect(g.rect.width, 450); // 300 local * 0.75 * 2
      expect(g.rect.height, 300);
      // And a local point is worth ratio x scale device pixels, which is what
      // keeps a corner radius the right size on screen.
      expect(g.unit, closeTo(1.5, 1e-9));
    });

    test('the old arithmetic is what it replaced, and it was wrong', () {
      // Origin from the global position, extent from the LOCAL size — the
      // combination that shipped. Reproduced here so the difference is on the
      // record rather than in a commit message.
      const localSize = Size(300, 200);
      const dprAsPublished = 1.5; // 2 * 0.75, the falsified MediaQuery value
      const oldTopLeft = Offset(300 * dprAsPublished, 225 * dprAsPublished);
      final oldRect = Rect.fromLTWH(oldTopLeft.dx, oldTopLeft.dy,
          localSize.width * dprAsPublished, localSize.height * dprAsPublished);

      final now = glassDeviceRect(
        topLeftGlobal: const Offset(300, 225),
        bottomRightGlobal: const Offset(525, 375),
        localSize: localSize,
        devicePixelRatio: 2,
      );

      // The old origin was 0.75x of the true device position — the whole panel
      // pulled toward the top-left corner, which is why the surfaces nearest
      // that corner looked least wrong.
      expect(oldRect.left, lessThan(now.rect.left));
      expect(oldRect.top, lessThan(now.rect.top));
      expect(now.rect.left / oldRect.left, closeTo(1 / 0.75, 1e-9));
    });

    test('a mirroring transform still yields a rectangle', () {
      // Sorted rather than assumed: a negative width is not a rectangle and
      // the shader would read it as an empty one.
      final g = glassDeviceRect(
        topLeftGlobal: const Offset(400, 250),
        bottomRightGlobal: const Offset(100, 50),
        localSize: const Size(300, 200),
        devicePixelRatio: 1,
      );
      expect(g.rect, const Rect.fromLTRB(100, 50, 400, 250));
      expect(g.rect.width, isPositive);
    });

    test('a zero-sized panel falls back to the ratio rather than dividing by '
        'zero', () {
      final g = glassDeviceRect(
        topLeftGlobal: Offset.zero,
        bottomRightGlobal: Offset.zero,
        localSize: Size.zero,
        devicePixelRatio: 3,
      );
      expect(g.unit, 3);
      expect(g.rect, Rect.zero);
    });
  });
}
