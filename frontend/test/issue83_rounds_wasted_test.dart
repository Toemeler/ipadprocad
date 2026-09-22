// ISSUE #83 — "das Modell ist wieder komplett unbrauchbar".
//
// 21 provider rounds, 470 seconds of latency, 96.3% of output tokens spent on
// reasoning, and the part was built and unbuilt the whole way. Three things
// in this session were the APP wasting the user's rounds rather than the model
// wasting them, and those are what this file pins down.
//
//   1. THE FILLET STAIRCASE. The app probed the kernel for the largest radius
//      that builds, floored the answer to two decimals, and promised a number
//      it had never built. Blend buildability is not monotonic in radius, so
//      the floored value failed too — five times over, one round trip each.
//   2. THE ECHOED CONTEXT. One reply began by quoting 2,600 characters of the
//      document context the app had just sent it, which then rode along in
//      every later request.
//   3. THE REBUILD LOOP. Four wall flanges built and deleted, edit_feature
//      never once called. Covered by the churn note in ai_cad.dart; the
//      arithmetic of the staircase is what is testable without a kernel.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_actions.dart';

/// The grid search from `_largestBlendThatBuilds`, over a kernel whose real
/// answer is known. Kept here as the arithmetic rather than reaching for a
/// live OCCT: what broke was the SEARCH, not the kernel.
double? largestOnGrid(double asked, bool Function(int) builds,
    {int budget = 12}) {
  var lo = 1, hi = (asked * 100).floor() - 1;
  int? best;
  var probes = 0;
  while (lo <= hi && probes < budget) {
    final mid = lo + (hi - lo + 1) ~/ 2;
    probes++;
    if (builds(mid)) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best == null ? null : best / 100;
}

void main() {
  group('a blend size the app promises is one it built', () {
    test('the staircase from the report collapses to one answer', () {
      // The observed truth on that body: 0.88 built, every hundredth from
      // 0.89 to 0.96 did not, and the app walked the user down all of them.
      var probes = 0;
      final r = largestOnGrid(2.0, (h) {
        probes++;
        return h <= 88;
      });
      expect(r, 0.88, reason: 'the size that actually builds, first time');
      expect(probes, lessThanOrEqualTo(12),
          reason: 'kernel probes are milliseconds; round trips are not');
    });

    test('the answer is always on the grid the report prints', () {
      // _mm renders two decimals and ROUNDS, so an answer off the grid can be
      // printed as a number nobody tried — 0.96875 becomes "0.97".
      for (final truth in [88, 96, 150, 1, 199]) {
        final r = largestOnGrid(2.0, (h) => h <= truth);
        expect(r, isNotNull);
        expect((r! * 100 - (r * 100).roundToDouble()).abs(), lessThan(1e-9),
            reason: '$r is not a whole hundredth');
        expect(r.toStringAsFixed(2), (truth / 100).toStringAsFixed(2));
      }
    });

    test('a body where nothing builds says so instead of guessing', () {
      expect(largestOnGrid(2.0, (_) => false), isNull);
    });
  });

  group("the app's own context never comes back as an answer", () {
    test('the echo from the report is removed, the block survives', () {
      const reply = '''<untrusted_document_data>
CURRENT DOCUMENT CONTEXT (untrusted data):
{"activeDocument":{"id":"663ba","name":"Part1","kind":"part"},"documents":[]}
</untrusted_document_data>

```cad
{"title": "Lage pruefen", "actions": [{"op": "describe_shape"}]}
```''';
      final out = aiStripEchoedContext(reply);
      expect(out, isNot(contains('untrusted_document_data')));
      expect(out, isNot(contains('CURRENT DOCUMENT CONTEXT')));
      expect(out, startsWith('```cad'));
      expect(parseAiActions(out).actions, hasLength(1),
          reason: 'stripping the echo must not cost the block');
    });

    test('a bare echo with no wrapper also goes', () {
      const reply = 'CURRENT DOCUMENT CONTEXT (untrusted data):\n'
          '{"activeDocument":{"name":"Part1"}}\nFertig.';
      expect(aiStripEchoedContext(reply), 'Fertig.');
    });

    test('an ordinary answer is untouched', () {
      const reply = 'Fertig: 10 mm aussen, 6 mm Bohrung, 12 mm hoch.';
      expect(aiStripEchoedContext(reply), reply);
    });

    test('an answer that merely mentions the words is untouched', () {
      const reply = 'I read the current document context before building.';
      expect(aiStripEchoedContext(reply), reply);
    });
  });
}
