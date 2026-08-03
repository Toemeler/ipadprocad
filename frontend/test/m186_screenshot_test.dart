// M186 — the screenshot path, and the reason it has a deadline.
//
// The first version of this test hung for ten minutes. RenderRepaintBoundary
// .toImage hands the work to the rasterizer and waits for it; in a headless
// test there is nothing to answer, so the future never completes. That is not
// a test artefact — a backgrounded or surface-less app is the same situation,
// and an unbounded await here meant the bug button could HANG THE APP while
// reporting a hang. captureScreenshot is bounded because of this test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_capture.dart';

void main() {
  testWidgets('a capture that cannot complete gives up instead of hanging',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: screenshotKey,
        child: Container(width: 200, height: 120, color: const Color(0xFF36C)),
      ),
    ));
    await tester.pumpAndSettle();

    // Short deadline so the test states the property in a second rather than
    // waiting out the production one.
    final png = await tester.runAsync(() =>
        captureScreenshot(timeout: const Duration(milliseconds: 300)));

    // Headless, this comes back null via the timeout. On a device with a live
    // rasterizer it comes back as PNG bytes. Both are correct; what must NEVER
    // happen is this test not returning, which is what it is really pinning.
    if (png != null) {
      expect(png.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          reason: 'if bytes came back at all they must be a real PNG');
    }
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('with nothing mounted it returns null instead of throwing',
      (tester) async {
    // The bug button must never take the app down while reporting a bug.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await captureScreenshot(), isNull);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
