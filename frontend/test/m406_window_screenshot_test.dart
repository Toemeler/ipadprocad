// M406 — the bug report's screenshot on the desktop.
//
// "The white slab is only in the screenshot i dont see this." Exactly so, and
// it is worth saying what that means: #37 was filed about the app's
// appearance, from a picture that was not a picture of the app.
//
// iOS grabs the window natively (`drawHierarchy`); everywhere else the bundle
// fell back to `RenderRepaintBoundary.toImage`, which re-rasterises Flutter's
// LAYER TREE offscreen. A backdrop filter in that pass has no backdrop, so
// every glass surface comes out a flat slab — white, on the light style — that
// was on no screen anywhere. The Windows runner answers `screenshot` with a
// real PrintWindow grab now, and the caveat beside the file says which capture
// produced it.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_report.dart';
import 'package:prototype/platform/desktop_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('prototype/desktop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('the window grab', () {
    test('is null where no runner implements it', () async {
      // iOS, Linux, the test host: the channel throws MissingPluginException
      // and the caller falls back exactly as it always has.
      expect(await DesktopShell.screenshot(), isNull);
    });

    test('is null when the runner could not grab the window', () async {
      // An empty answer is the runner saying "use the other capture" — a
      // PrintWindow a driver refused, a window with no size yet.
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'screenshot');
        return null;
      });
      expect(await DesktopShell.screenshot(), isNull);
      messenger.setMockMethodCallHandler(
          channel, (call) async => Uint8List(0));
      expect(await DesktopShell.screenshot(), isNull);
    });

    test('comes back as the PNG bytes when it worked', () async {
      final png = Uint8List.fromList(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
      messenger.setMockMethodCallHandler(channel, (call) async => png);
      expect(await DesktopShell.screenshot(), png);
    });

    test('a throwing runner is not a failed bug report', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'boom'));
      expect(await DesktopShell.screenshot(), isNull);
    });
  });

  group('the caveat beside the picture', () {
    String md({bool omits3D = false, bool layerTree = false}) => buildBundle(
          description: 'x',
          when: DateTime(2026, 9, 8),
          env: const {},
          part: null,
          hasScreenshot: true,
          screenshotOmits3D: omits3D,
          screenshotIsLayerTree: layerTree,
        )['report.md']!;

    test('a real grab carries no caveat at all', () {
      final m = md();
      expect(m, contains('screenshot.png'));
      expect(m, isNot(contains('NOT in this image')));
      expect(m, isNot(contains('re-rasterised')));
    });

    test('the layer-tree fallback says the glass is not the glass', () {
      final m = md(layerTree: true);
      expect(m, contains('re-rasterised'));
      expect(m, contains('BACKDROP-FILTER'));
      expect(m, contains('Judge nothing about the appearance'));
    });

    test("iOS's own caveat is untouched, and the two can both apply", () {
      final m = md(omits3D: true, layerTree: true);
      expect(m, contains('NOT in this image'));
      expect(m, contains('re-rasterised'));
    });
  });
}
