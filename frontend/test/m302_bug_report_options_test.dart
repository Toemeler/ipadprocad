// The two things the report dialog now decides, and where each one lands.
//
// WHY THESE ARE WORTH PINNING
// ---------------------------
// Both are invisible from inside the app. The screenshot's quality is only
// apparent to whoever opens the bundle days later, and the checkbox's effect
// is a LABEL on a GitHub issue — so nothing about either fails loudly if it
// silently stops working. The assertions here are the only place that notices.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_capture.dart';
import 'package:prototype/widgets/bug_button.dart';

void main() {
  testWidgets('off the device the capture falls back and SAYS it fell back',
      (tester) async {
    // `NativeMenu.isSupported` is false on the host, so `screenshot()` returns
    // null at once and the Flutter boundary runs — the old path exactly.
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: screenshotKey,
        child: const SizedBox(width: 120, height: 80),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => captureScreenshot(timeout: const Duration(milliseconds: 300)));

    expect(nativeScreenshot, isFalse,
        reason: 'the bundle must not claim a window grab it did not get — '
            'that flag is what decides whether the reader is warned the 3D '
            'body and the glass chrome are missing');
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('the request carries the choice, and the default is ON', () {
    // Opt-OUT on purpose: most reports are the automation's to take, and a
    // default that has to be switched on is a default nobody uses.
    expect(const BugReportRequest('x', autofix: true).autofix, isTrue);
    expect(const BugReportRequest('x', autofix: false).autofix, isFalse);
    expect(const BugReportRequest('the floor is dark', autofix: true).text,
        'the floor is dark');
  });
}
