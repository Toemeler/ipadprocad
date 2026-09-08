// M388 — a transform between the root view and the Navigator's Overlay puts
// every menu in this app in the wrong place, because each one is positioned
// from a point measured in the ROOT's coordinates (a pointer event, or
// localToGlobal).
//
// The Windows UI scale was such a transform for one afternoon and is gone
// again (M391), so nothing in the app is scaled today and both helpers are
// no-ops. They are still worth pinning: the mismatch is invisible by reading
// either side — both are "the position", and they agree exactly until
// something scales one of them — so the scaled case below is what keeps the
// arithmetic honest for whatever introduces a transform next.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/menus.dart';

Future<BuildContext> pumpBelowOverlay(WidgetTester t, {double scale = 1}) async {
  late BuildContext ctx;
  await t.pumpWidget(MaterialApp(
    // The shape an app-wide scale takes: the transform wraps the routed app,
    // so the Overlay inside it is in the scaled space and `home` is below both.
    builder: (context, child) => scale == 1
        ? child!
        : Transform.scale(
            scale: scale, alignment: Alignment.topLeft, child: child),
    home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    }),
  ));
  return ctx;
}

void main() {
  testWidgets('unscaled, a global point is already an overlay point',
      (t) async {
    final ctx = await pumpBelowOverlay(t);
    expect(overlayPosition(ctx, const Offset(100, 140)), const Offset(100, 140));
    expect(overlayRect(ctx, const Rect.fromLTWH(10, 20, 30, 40)),
        const Rect.fromLTWH(10, 20, 30, 40));
  });

  testWidgets('scaled, the point is corrected into the overlay space',
      (t) async {
    // Half scale: what the root calls (100,140) is (200,280) to anything
    // laid out inside the transform, the Overlay included.
    final ctx = await pumpBelowOverlay(t, scale: 0.5);
    expect(overlayPosition(ctx, const Offset(100, 140)), const Offset(200, 280));
    expect(overlayRect(ctx, const Rect.fromLTWH(10, 20, 30, 40)),
        const Rect.fromLTWH(20, 40, 60, 80));
  });
}
