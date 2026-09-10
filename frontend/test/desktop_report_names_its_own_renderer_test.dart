// Found by running the Linux build rather than by reading it: the app told a
// Linux user that rendered mode "stays RealityKit".
//
//     cycles: no renderer in this build; rendered mode stays RealityKit
//     3d: renderer: flutter_scene (Flutter GPU)
//
// Two lines apart, in the same launch, on a platform where RealityKit does not
// exist. That is #36's mistake ("on windows there is still the option reality
// kit ... but reality kit doesnt exist at all on windows") surviving in the
// log after it was fixed in the picker — and the log is what someone reads to
// find out why a render did nothing.
//
// The bug bundle carried the same assumption further, and worse, because that
// one is READ BY WHOEVER FIXES THE BUG. Every report's contents page said
// `reality.txt` is "what Dart last handed the native renderer. The 3D body is
// drawn by RealityKit behind a platform view, so this is the last thing
// visible from this side of that boundary" — on Windows too, where the shaded
// body is drawn by flutter_scene inside Flutter and IS in the screenshot. The
// maintainer protocol's rule that the body is never in the screenshot is built
// on that sentence, so a desktop report sent its reader looking for a body
// that was in the picture all along.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_report.dart';
import 'package:prototype/render_engine.dart';

Map<String, String> _bundle({required bool platformView}) => buildBundle(
      description: 'x',
      when: DateTime(2026, 9, 10),
      env: const {},
      part: null,
      realityText: 'scene: 1 body',
      bodyIsPlatformView: platformView,
    );

void main() {
  group('the contents page describes the renderer this platform HAS', () {
    test('on iOS reality.txt is the far side of a platform-view boundary', () {
      final report = _bundle(platformView: true)['report.md']!;
      expect(report, contains('RealityKit'));
      expect(report, contains('platform view'));
    });

    test('on a desktop it is a scene Flutter drew, and says the body is in '
        'the screenshot', () {
      final report = _bundle(platformView: false)['report.md']!;
      expect(report, isNot(contains('RealityKit')),
          reason: 'a desktop report must not name a renderer this build has '
              'no trace of — that is what sent readers to the wrong file');
      expect(report, contains('flutter_scene'));
      expect(report, contains('screenshot.png'),
          reason: 'the correction is only useful if it says where the body '
              'actually IS');
    });

    test('and reality.txt itself is carried either way', () {
      for (final pv in [true, false]) {
        expect(_bundle(platformView: pv)['reality.txt'], 'scene: 1 body');
      }
    });

    test('the default is the desktop answer, not the iOS one', () {
      // Every caller in the app passes the flag; a future one that forgets
      // should get the answer that is true on two platforms out of three
      // rather than the one that is true on one.
      final report = buildBundle(
        description: 'x',
        when: DateTime(2026, 9, 10),
        env: const {},
        part: null,
        realityText: 's',
      )['report.md']!;
      expect(report, isNot(contains('RealityKit')));
    });
  });

  group('and the fallback line names a renderer that is in the build', () {
    test('realtimeEngineName is what decides it, on every surface', () {
      // The picker (#36), the viewport and now the Cycles fallback line all
      // ask this one question. On the test host neither surface exists, which
      // is the third answer and the one that must not be spelled "RealityKit"
      // either.
      final name = realtimeEngineName();
      expect(name, anyOf(isNull, 'RealityKit', 'Flutter GPU'));
      if (name != null) {
        expect(name, isNot(equals('Cycles')));
      }
    });
  });
}
