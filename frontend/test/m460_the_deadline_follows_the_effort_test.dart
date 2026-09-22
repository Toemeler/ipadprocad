// M460 (#81) — A DEADLINE SHORTER THAN THE WORK IS NOT A NETWORK PROBLEM.
//
// Issue #81 is three failed turns in one session. One was a genuinely dropped
// connection, which M455 taught the controller to retry. The other two were
// the app's own doing, and the trace in the bug bundle says so exactly:
//
//   turn.failed network 120270  TimeoutException after 0:02:00.000000
//   turn.failed network 120165  TimeoutException after 0:02:00.000000
//
// Both died at the deadline with the request still in flight, while every
// round in the same session that came back at all took at most 33 seconds.
// The deadline was a flat 120 seconds — for a request the app had just asked
// to think as hard as it can, with no output cap, which on this model means
// up to 64K tokens of reasoning before a single character of the answer.
//
// The app was asking for the most expensive answer it can buy and allowing
// the least time to produce it. That contradiction is what this file fixes:
// one value decides both, so they cannot drift apart again.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_backend.dart';

void main() {
  group('the deadline is decided by the effort, not by a constant', () {
    test('thinking hard buys time; thinking little does not', () {
      expect(aiResponseDeadline('high'),
          greaterThan(aiResponseDeadline('low')));
      expect(aiResponseDeadline('low'),
          greaterThan(aiResponseDeadline('none')));
    });

    test('the round that died at 0:02:00 would now have had room', () {
      // The failing rounds were thorough first attempts, so `high`.
      final effort = deepSeekReasoningEffort(thorough: true, attempt: 0);
      expect(effort, 'high');
      expect(aiResponseDeadline(effort),
          greaterThan(const Duration(seconds: 120)),
          reason: 'this is the exact case issue #81 failed on');
    });

    test('a narrow change still notices a dead connection quickly', () {
      // "Add a 5 mm hole" creates no `must`, so it is not thorough. It must
      // NOT wait six minutes on a socket that is never going to answer.
      final effort = deepSeekReasoningEffort(thorough: false, attempt: 0);
      expect(effort, 'low');
      expect(aiResponseDeadline(effort),
          lessThanOrEqualTo(const Duration(minutes: 3)));
    });

    test('an unknown effort falls back to the ordinary deadline', () {
      expect(aiResponseDeadline('something-new'), aiResponseDeadline('low'));
    });

    test('every deadline is bounded — none of them is "wait forever"', () {
      for (final e in const ['high', 'low', 'none', 'anything']) {
        expect(aiResponseDeadline(e), lessThanOrEqualTo(const Duration(minutes: 10)),
            reason: '$e must still give up eventually');
        expect(aiResponseDeadline(e), greaterThanOrEqualTo(const Duration(minutes: 2)),
            reason: '$e must not be shorter than the old flat deadline');
      }
    });

    test('the retries walk the deadline DOWN, so a turn stays bounded', () {
      // Each attempt thinks less (that is what deepSeekReasoningEffort does),
      // so three attempts cost less than three times the worst one.
      final d = [
        for (var a = 0; a < 3; a++)
          aiResponseDeadline(deepSeekReasoningEffort(thorough: true, attempt: a))
      ];
      expect(d[0], greaterThanOrEqualTo(d[1]));
      expect(d[1], greaterThanOrEqualTo(d[2]));
      final total = d.reduce((x, y) => x + y);
      expect(total, lessThan(d[0] * 3),
          reason: 'a turn that keeps timing out must not cost 3x the worst case');
    });
  });
}
