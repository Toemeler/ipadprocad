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
      // #82 moved this case from `high` to `low`: a round of the action loop
      // does not deliberate, because it can build the thing and read the
      // result instead. The protection #81 needed is unchanged — what killed
      // that turn was a 120-second ceiling on work that needed longer, and
      // `low` still carries three minutes. The rounds in #81 that DID come
      // back took at most 33 seconds.
      final effort = deepSeekReasoningEffort(thorough: true, attempt: 0);
      expect(effort, 'low');
      expect(aiResponseDeadline(effort),
          greaterThan(const Duration(seconds: 120)),
          reason: 'this is the exact case issue #81 failed on');
    });

    test('an answer with no loop behind it still buys the long deadline', () {
      // Edits off, or the closing reply after a blocked block: nothing to
      // test against, so the model has only deliberation — and needs the room.
      final effort =
          deepSeekReasoningEffort(thorough: true, iterating: false);
      expect(effort, 'high');
      expect(aiResponseDeadline(effort), const Duration(minutes: 6));
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
