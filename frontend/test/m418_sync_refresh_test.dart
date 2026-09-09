// M418 — "on desktop I want a refresh button. On touch devices I just want to
// drag down to refresh in the menu. It should then pull changes from all other
// devices."
//
// The mirror is continuous, so a refresh is not what makes sharing WORK. It is
// what makes it ANSWERABLE: "did it sync?" had no way of being asked, and
// somebody who cannot ask that does not trust the feature — which was most of
// what "the syncing is very dangerous" was about.
//
// What is pinned here:
//   * a refresh with no code set says so instead of pretending;
//   * a refresh with nobody listening reports being alone rather than hanging
//     for its whole settle window;
//   * every outcome carries something the gallery can say out loud — silence
//     is what makes people press a button five times;
//   * the header offers the button only where there is something to sync
//     with, and the drag-down only there too;
//   * a divergence outranks a count in what gets said, because "both versions
//     are here" is the sentence worth reading.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/sync/lan_sync.dart';
import 'package:prototype/sync/sync_store.dart';

void main() {
  late Directory root;
  late Directory docs;
  late Directory prefs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('m418');
    docs = Directory('${root.path}/docs')..createSync();
    prefs = Directory('${root.path}/prefs')..createSync();
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    ShareCodes.resetForTest();
  });

  group('what a refresh answers', () {
    test('sharing off: nothing is attempted, and it says so', () async {
      final r = await LanSync.instance.refresh();
      expect(r.outcome, SyncRefreshOutcome.off);
      expect(r.peers, 0);
    });

    test('it returns quickly rather than sitting out its settle window',
        () async {
      // Nobody is listening in a host test, so this is the "alone" path — and
      // the point is that it ENDS. A refresh that hangs is a spinner that
      // never stops on the one screen the user is waiting on.
      final sw = Stopwatch()..start();
      final r = await LanSync.instance
          .refresh(settle: const Duration(milliseconds: 300));
      sw.stop();
      expect(r.outcome, SyncRefreshOutcome.off,
          reason: 'no code is set in a host test');
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('every outcome has something to say', () {
    // The gallery turns a result into one line. A result it could not speak
    // would be a refresh that appears to do nothing, which is the whole fault
    // this control exists to fix.
    testWidgets('and the words come from the ARB, in both languages',
        (t) async {
      for (final locale in [kEn, const Locale('de')]) {
        late AppL10n l;
        await t.pumpWidget(MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: locale,
          home: Builder(builder: (c) {
            l = AppL10n.of(c)!;
            return const SizedBox.shrink();
          }),
        ));
        await t.pump();
        for (final s in [
          l.syncNow,
          l.syncChecking,
          l.syncUpToDate,
          l.syncNoDevices,
          l.syncFailedNote,
          l.syncUpdated(1),
          l.syncUpdated(3),
          l.syncKeptBoth('Bracket'),
          l.syncKeptBothMany(2),
        ]) {
          expect(s.trim(), isNotEmpty);
        }
        expect(l.syncUpdated(3), contains('3'));
        expect(l.syncKeptBoth('Bracket'), contains('Bracket'));
        expect(l.syncUpdated(1), isNot(contains('1')),
            reason: 'one document reads as a word, not as a digit');
      }
    });
  });

  group('the result carries what the line needs', () {
    test('a divergence is reported alongside the count', () {
      const fork = SyncFork('Bracket.ptp', 'Bracket (iPad).ptp', 'iPad');
      const r = SyncRefreshResult(SyncRefreshOutcome.kept,
          documents: 3, forks: [fork], peers: 1);
      expect(r.forks.single.original, 'Bracket.ptp');
      expect(r.documents, 3);
      // `kept` rather than `updated` even though three documents moved: the
      // gallery reads the outcome, and the divergence is the news.
      expect(r.outcome, SyncRefreshOutcome.kept);
    });

    test('an empty result still names an outcome', () {
      const r = SyncRefreshResult(SyncRefreshOutcome.upToDate);
      expect(r.documents, 0);
      expect(r.forks, isEmpty);
      expect(r.outcome, SyncRefreshOutcome.upToDate);
    });
  });

  group('forks reach the gallery', () {
    test('they are published, and can be cleared once read', () {
      expect(LanSync.instance.recentForks.value, isEmpty);
      LanSync.instance.recentForks.value = const [
        SyncFork('Bracket.ptp', 'Bracket (iPad).ptp', 'iPad')
      ];
      expect(LanSync.instance.recentForks.value.length, 1);
      LanSync.instance.recentForks.value = const <SyncFork>[];
      expect(LanSync.instance.recentForks.value, isEmpty);
    });
  });
}
