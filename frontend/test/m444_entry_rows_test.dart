// M444 — "It just says not set up but how do i set it up".
//
// The four Backblaze rows drew perfectly on the iPad and ignored every tap.
// They were `SettingsRowKind.value`, and `value` means read-only ALL THE WAY
// DOWN: `SettingsSheet.swift` returns nil from `willSelectRowAt` for one,
// gives it `.selectionStyle = .none`, and marks it `.staticText` for
// VoiceOver — on the perfectly good reasoning that "a row that flashes but
// does nothing reads as broken".
//
// So a row with both a value to show and something to do had nowhere to live.
// The Flutter fallback had hidden that by keeping a SET OF ROW IDS that were
// secretly tappable; the native sheet had no such set, so Linux and Windows
// worked and the iPad did not. Two renderers, one of them guessing.
//
// That is the M382 report a second time, and it had already claimed two rows
// nobody noticed: `kRowSyncPeer` (M423's way onto another network) and
// `kRowReplacedVersions` (M421's drawer) have been dead on iOS since they
// shipped.
//
// `entry` is the kind that says "shows a value, still a control". What is
// pinned here is the RULE rather than today's list: anything the sync handler
// acts on must not be `value`, so the next such row cannot be born dead.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/settings.dart';
import 'package:prototype/theme.dart';

void main() {
  final t = L.stringsFor(const Locale('en'));
  const info = SettingsInfo(
      build: 'test', kernel3d: '-', kernel2d: '-', system: '-');

  List<SettingsRow> rowsOf(String sectionId, {
    String? bucket,
    String? endpoint,
    String? keyId,
    bool appKey = false,
    int backups = 0,
    int localChanges = 0,
  }) =>
      buildSettings(
        t,
        mode: AppThemeMode.dark,
        locale: const Locale('en'),
        info: info,
        syncBackups: backups,
        syncLocalChanges: localChanges,
        cloudBucket: bucket,
        cloudEndpoint: endpoint,
        cloudKeyId: keyId,
        cloudAppKeySet: appKey,
      ).firstWhere((s) => s.id == sectionId).rows;

  List<SettingsRow> syncRows({bool complete = false}) => rowsOf(
        kSecSync,
        bucket: complete ? 'b' : null,
        endpoint: complete ? 'eu-central-003' : null,
        keyId: complete ? 'k' : null,
        appKey: complete,
        // Both rows below only exist when there is something behind them:
        // the drawer when it holds a version, and Discard when this device
        // has actually diverged. With zero, Discard is deliberately inert —
        // it stays on screen saying "nothing to discard" rather than
        // vanishing, which is M420's point.
        backups: complete ? 1 : 0,
        localChanges: complete ? 1 : 0,
      );

  SettingsRow row(String id, {bool complete = false}) =>
      syncRows(complete: complete).firstWhere((r) => r.id == id);

  group('a row you can set must not claim to be read-only', () {
    // THE REPORT. Four rows saying "Not set up" and no way to set them up.
    test('the four account rows take a tap', () {
      for (final id in const [
        kRowCloudBucket,
        kRowCloudEndpoint,
        kRowCloudKeyId,
        kRowCloudAppKey,
      ]) {
        expect(row(id).kind, SettingsRowKind.entry, reason: id);
        expect(row(id).kind, isNot(SettingsRowKind.value),
            reason: '$id was dead on iOS as a value row');
      }
    });

    // Dead on iOS since they shipped, for the same reason, found while
    // fixing the four above.
    test('so do the two that were quietly dead before these', () {
      expect(row(kRowSyncPeer, complete: true).kind, SettingsRowKind.entry);
      expect(row(kRowReplacedVersions, complete: true).kind,
          SettingsRowKind.entry);
    });

    // THE RULE, not the list. `applySyncRow` switches on these ids; a `value`
    // among them is a row whose handler can never run on iOS.
    //
    // Measured with something behind every row. `kRowDiscardChanges` is
    // legitimately `value` when there is nothing to discard — inert because
    // there is genuinely nothing to do, which is not the bug this is about.
    test('nothing the sync handler acts on is a value row', () {
      const handled = <String>{
        kRowCloudBucket,
        kRowCloudEndpoint,
        kRowCloudKeyId,
        kRowCloudAppKey,
        kRowSyncPeer,
        kRowRemoveAccount,
        kRowDiscardChanges,
        kRowReplacedVersions,
      };
      for (final r in syncRows(complete: true)) {
        if (!handled.contains(r.id)) continue;
        expect(r.kind, isNot(SettingsRowKind.value),
            reason: '${r.id} is acted on but cannot be selected on iOS');
      }
    });

    // And the converse, so `entry` does not become the kind everything gets:
    // the status line really is a fact with nothing behind it.
    test('a row with nothing behind it stays read-only', () {
      expect(row(kRowSyncStatus, complete: true).kind, SettingsRowKind.value);
    });

    test('the About rows stay read-only too', () {
      final about = rowsOf(kSecAbout);
      expect(about, isNotEmpty);
      for (final r in about) {
        expect(r.kind, SettingsRowKind.value, reason: r.id);
      }
    });
  });

  group('what the native sheet is told', () {
    // `kind` crosses the platform channel as its enum name, and
    // `SettingsSheet.swift` switches on that string. A rename here is a
    // silently dead row there.
    test('entry crosses the wire as "entry"', () {
      expect(row(kRowCloudBucket).toMap()['kind'], 'entry');
      expect(row(kRowSyncStatus, complete: true).toMap()['kind'], 'value');
    });

    // The value1 cell style is what draws the right-aligned detail, and the
    // Swift picks it for value AND entry. A row with no detail would render
    // as an empty right-hand side.
    test('an entry row carries the detail it will display', () {
      expect(row(kRowCloudBucket).detail, isNotNull);
      expect(row(kRowCloudBucket).detail, t.settingsCloudNone);
      expect(row(kRowCloudBucket, complete: true).detail, 'b');
    });

    // The key is never the detail — a row's value is rendered on screen, and
    // a screenshot of Settings goes into every bug report.
    test('the application key row shows only that it is saved', () {
      expect(row(kRowCloudAppKey, complete: true).detail,
          t.settingsCloudAppKeySaved);
    });
  });
}
