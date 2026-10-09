import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_report.dart';
import 'package:prototype/grabcad/grabcad_diagnostics.dart';
import 'package:prototype/log.dart';

void main() {
  test('GrabCAD history is bounded and snapshots are detached', () {
    Log.i('grabcad', 'search page=1 query="gear"');
    final old = GrabCadDiagnostics.snapshot();
    expect((old['events'] as List).last['message'], contains('gear'));
    for (var i = 0; i < GrabCadDiagnostics.capacity + 5; i++) {
      GrabCadDiagnostics.record('INFO', 'request $i');
    }
    final snapshot = GrabCadDiagnostics.snapshot();
    expect(snapshot['events'] as List, hasLength(300));
    expect(snapshot['droppedEvents'] as int, greaterThanOrEqualTo(6));
    expect((old['events'] as List).last['message'], contains('gear'));
  });

  test('bundle indexes diagnostics including failed native capture', () {
    final json = jsonEncode({
      ...GrabCadDiagnostics.snapshot(),
      'nativeCaptureError': 'TimeoutException',
    });
    final files = buildBundle(
      description: 'Login does not appear',
      when: DateTime.utc(2026, 10, 9),
      env: const {},
      part: null,
      grabCadDiagnosticsJson: json,
    );
    expect(files['grabcad/diagnostics.json'], json);
    expect(files['report.md'], contains('grabcad/diagnostics.json'));
    expect(jsonDecode(files['grabcad/diagnostics.json']!)['nativeCaptureError'],
        'TimeoutException');
  });
}
