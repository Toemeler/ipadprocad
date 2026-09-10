// Issue #46 — "the auto upload of bug reports doesnt work anymore on my ipad".
//
// The report that came with it had to travel by WeTransfer, because the app
// could not file it. The bundle the app HAD filed successfully, hours earlier
// from the desktop, says why: 10.74 MB of zip, of which 10.22 MB — 95 % — is
// one member, `performance_logs_prev.txt`, 57.6 MB of rolling perf log that
// went in whole because nothing ever capped it.
//
// That is the same fault M415 fixed for #41, arriving from the other side.
// M415 made the upload budget follow the payload; this let the payload grow
// past the point where it still could. At 10.24 MiB the budget is pinned at
// its 90 s cap, which asks for ~950 kbit/s of sustained uplink — precisely
// the figure M415 wrote down as what a tablet does not clear and a desktop
// does. And reading 57.6 MB into a String on the way there is a few hundred
// megabytes of peak allocation that iOS answers by killing the process.
//
// What is pinned here:
//   * a rolling log enters the bundle as its TAIL, bounded, whatever its size;
//   * the tail starts on a line boundary and says the head was dropped;
//   * a log smaller than the cap is untouched, and a missing one is null;
//   * the bundle that results is small enough that the upload budget is still
//     FOLLOWING it rather than sitting on its cap — which is the difference
//     between a report that files itself and one that arrives by WeTransfer;
//   * and when the relay refuses one anyway, the dialog says what it said.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_report.dart';
import 'package:prototype/bug_upload.dart';

/// Log-shaped text of roughly [bytes], varied enough not to deflate away to
/// nothing — a real rolling log is timestamps and changing numbers, and a test
/// built from one repeated line would compress like nothing this ever sees.
String _logLike(int bytes) {
  final b = StringBuffer();
  var seed = 0x2545F491;
  var i = 0;
  while (b.length < bytes) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    b.writeln('2026-09-10T11:32:${(i % 60).toString().padLeft(2, '0')}.'
        '${(seed % 1000000).toString().padLeft(6, '0')} '
        '[perf] frame ${i} build=${seed % 977 / 7.0} raster=${seed % 313 / 3.0} '
        'remesh=${seed % 1511} gpu=0x${seed.toRadixString(16)}');
    i++;
  }
  return b.toString();
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('issue46'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File _write(String name, String text) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(text);
    return f;
  }

  group('a rolling log enters the bundle as its tail', () {
    test('an oversized log is bounded, and it is the END that survives', () {
      final whole = _logLike(6 * 1024 * 1024);
      final f = _write('performance_logs_prev.txt', whole);
      expect(f.lengthSync(), greaterThan(bugLogTailBytes));

      final tail = readLogTail(f.path)!;
      // Bounded: the marker line is the only thing above the cap.
      expect(utf8.encode(tail).length,
          lessThanOrEqualTo(bugLogTailBytes + 200));
      // And it is the tail: the last line of the file is in it, the first is
      // not. The report is written at the END of the session it describes,
      // which is the whole reason this end is the one worth keeping.
      final lines = whole.trimRight().split('\n');
      expect(tail, contains(lines.last));
      expect(tail, isNot(contains(lines.first)));
    });

    test('it starts on a line boundary and says what it dropped', () {
      final f = _write('log.txt', _logLike(5 * 1024 * 1024));
      final tail = readLogTail(f.path)!;

      // The first line is the marker, not half of whatever line the seek
      // landed in the middle of.
      final first = tail.split('\n').first;
      expect(first, startsWith(bugLogTailMarker));
      expect(first, contains('${f.lengthSync()}'));
      // The line under it is a whole log line, not a fragment of one.
      expect(tail.split('\n')[1], startsWith('2026-09-10T11:32:'));
    });

    test('a log under the cap is handed over untouched', () {
      final small = _logLike(64 * 1024);
      final f = _write('log.txt', small);
      expect(f.lengthSync(), lessThan(bugLogTailBytes));
      expect(readLogTail(f.path), small);
      expect(readLogTail(f.path), isNot(contains(bugLogTailMarker)));
    });

    test('a log that is not there is still just null', () {
      expect(readLogTail('${tmp.path}/never-written.txt'), isNull);
    });

    test('a window with no newline in it at all still comes back', () {
      // One enormous line — no boundary to cut on. Bounded anyway.
      final f = _write('log.txt', 'x' * (3 * 1024 * 1024));
      final tail = readLogTail(f.path)!;
      expect(utf8.encode(tail).length,
          lessThanOrEqualTo(bugLogTailBytes + 200));
    });
  });

  group('and that is what puts the bundle back inside the budget', () {
    test('the tail bundle is a fraction of the whole-file one', () {
      // The member from the real report, at a size a test can afford. The
      // arithmetic below is scale-free: what is pinned is the RATIO, and that
      // the budget is still following the tail bundle rather than capped.
      final f = _write('performance_logs_prev.txt', _logLike(6 * 1024 * 1024));

      Map<String, String> bundleWith(String perfPrev) => {
            ...buildBundle(
              description: 'the auto upload doesnt work anymore on my ipad',
              when: DateTime(2026, 9, 10, 11, 32, 23),
              env: const {'os': 'ios', 'build': 'test'},
              part: null,
            ),
            'performance_logs_prev.txt': perfPrev,
          };

      // How it was: the whole file, straight in.
      final wholeZip = writeBundle(
          tmp, 'whole', bundleWith(f.readAsStringSync()))!.lengthSync();
      // How it is: the tail.
      final tailZip =
          writeBundle(tmp, 'tail', bundleWith(readLogTail(f.path)!))!
              .lengthSync();

      expect(tailZip * 2, lessThan(wholeZip),
          reason: 'the tail bundle must be materially smaller, not marginally');
      expect(tailZip, lessThan(bugLogTailBytes));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the budget the real bundle got was pinned at its cap', () {
      // 10 736 399 bytes — the zip filed on 2026-09-10, the last one before
      // the iPad stopped being able to file at all.
      const filed = 10736399;
      expect(bugUploadTimeoutFor(filed), bugUploadTimeoutFor(500 << 20),
          reason: 'the budget had stopped following the payload: this bundle '
              'and one fifty times its size were allowed the same seconds');
      // Which is what it was asking of the uplink, in bits per second.
      final needed = filed * 8 / bugUploadTimeoutFor(filed).inSeconds;
      expect(needed, greaterThan(900000),
          reason: 'M415 wrote 900 kbit/s down as the demand a tablet does not '
              'meet; the bundle had grown back up to it');
    });

    test('a tail-capped bundle is one the budget still follows', () {
      // Everything but the perf log in the filed report came to 515 452 bytes;
      // 2 MiB of perf log deflates to well under half a megabyte beside it.
      const realistic = 1000000;
      expect(bugUploadTimeoutFor(realistic),
          lessThan(bugUploadTimeoutFor(500 << 20)));
      final needed =
          realistic * 8 / bugUploadTimeoutFor(realistic).inSeconds;
      expect(needed, lessThan(300000),
          reason: 'and it is asking for an uplink a tablet actually has');
    });
  });

  group('and a refusal says what the relay said', () {
    test('the JSON error the Worker answers with is what is shown', () {
      // relay/worker.js, the 413 branch: the one refusal a reporter can act
      // on, and the one the dialog used to reduce to "HTTP 413".
      expect(bugRelayRefusalDetail('{"error":"bundle too large: 26214401 '
          'bytes"}'), ' — bundle too large: 26214401 bytes');
    });

    test('something that is not the relay still contributes its first line',
        () {
      expect(
          bugRelayRefusalDetail('<html>\n<head><title>502</title></head>\n'),
          ' — <html>');
    });

    test('an empty body adds nothing rather than a dangling dash', () {
      expect(bugRelayRefusalDetail(''), '');
      expect(bugRelayRefusalDetail('   \n  '), '');
    });

    test('and it cannot run away with the dialog', () {
      final detail = bugRelayRefusalDetail(jsonEncode({'error': 'x' * 5000}));
      expect(detail.length, lessThan(260));
      expect(detail, endsWith('...'));
    });
  });
}
