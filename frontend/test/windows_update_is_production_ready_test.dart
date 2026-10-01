// "the automatic updating of the windows app is very buggy and unprofessional.
//  it feels stuck then it just closes the app and idk whats happening."
//
// Every step of the old update worked; together they read as a hang and a
// crash. The 23 Sep log shows it: "Downloading the update…" is the last line,
// the next launch is twelve minutes later, and nothing in between — the lines
// the updater did write were still in log.dart's buffer when exit(0) dropped
// it, and Setup ran /VERYSILENT with no log of its own.
//
// So, in update_check.dart and prototype.iss:
//
//   * the download happens in the background, resumes, and is offered only
//     once verified — nothing on screen can look stuck;
//   * Setup is started directly, waits for this PID itself, SHOWS its
//     progress (/SILENT, skinned in update mode), writes a log, and relaunches
//     the app whether or not the install worked;
//   * the next launch reports the outcome.
//
// This file pins the parts of that the host test can reach: the command line
// Setup is given (the quoting and the switches are what go wrong in the
// field), the download's name on disk, the outcome bookkeeping, and that
// every open document is saved, not only the visible one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/update_check.dart';

/// A realistic Windows install, with the space that breaks naive quoting.
const String kDir = r'C:\Users\t\AppData\Local\Programs\Prototype';
const String kExe = '$kDir\\prototype.exe';
const String kLog = r'C:\Users\t\AppData\Roaming\prototype\logs\update-install.log';

List<String> args({String? relaunch = kExe}) => UpdateCheck.windowsSetupArgs(
      waitForPid: 4321,
      logPath: kLog,
      installDir: kDir,
      relaunchExe: relaunch,
    );

void main() {
  group('SETUP\'S COMMAND LINE', () {
    test('Restart now: progress is shown, and the app comes back', () {
      final a = args();
      expect(a, contains('/SILENT'),
          reason: 'THE REPORT: /VERYSILENT put nothing on screen for minutes');
      expect(a, isNot(contains('/VERYSILENT')));
      expect(a, contains('/RELAUNCH=$kExe'));
    });

    test('install on quit: nothing on screen, nothing relaunched', () {
      final a = args(relaunch: null);
      expect(a, contains('/VERYSILENT'));
      expect(a, isNot(contains('/SILENT')));
      expect(a.any((x) => x.startsWith('/RELAUNCH')), isFalse,
          reason: 'the person closed the app; bringing it back is a bug');
    });

    test('Setup waits for THIS process, so nothing is replaced mid-save', () {
      expect(args(), contains('/WAITPID=4321'));
    });

    test('Setup updates THIS copy, not a second one elsewhere', () {
      expect(args(), contains('/DIR=$kDir'));
    });

    test('Setup writes a log, so a failure can be explained', () {
      expect(args(), contains('/LOG=$kLog'));
    });

    test('update mode, no message boxes, no reboot', () {
      final a = args();
      expect(a, contains('/UPDATE=1'));
      expect(a, contains('/SUPPRESSMSGBOXES'));
      expect(a, contains('/NORESTART'));
    });

    test('paths are whole arguments, never pre-quoted', () {
      // Process.start quotes an argument that contains a space. A path that
      // arrived already quoted would be quoted twice and reach Setup with
      // literal quote characters in it.
      for (final a in args()) {
        expect(a.contains('"'), isFalse, reason: a);
      }
    });
  });

  group('THE INSTALLER SCRIPT agrees with the app', () {
    // CI compiles prototype.iss; these pin that the switches the app sends
    // are the ones the script reads.
    final iss = File('windows/installer/prototype.iss').readAsStringSync();

    test('it reads every parameter the app passes', () {
      expect(iss, contains('{param:UPDATE|0}'));
      expect(iss, contains('{param:WAITPID|0}'));
      expect(iss, contains('{param:RELAUNCH|none}'));
    });

    test('it waits on the PID before installing', () {
      expect(iss, contains('function InitializeSetup'));
      expect(iss, contains('WaitForSingleObject'));
    });

    test('exactly one thing relaunches the app', () {
      // The Restart Manager reopening what it closed AND DeinitializeSetup
      // relaunching would be two windows on the same documents.
      expect(iss, contains('RestartApplications=no'));
      expect(iss, contains('procedure DeinitializeSetup'));
    });

    test('the progress card is shown in update mode', () {
      expect(iss, contains('if WizardSilent and not IsUpdateMode() then Exit;'));
    });
  });

  group('THE DOWNLOAD on disk', () {
    test('named for its release, so it resumes and is reused', () {
      final n = UpdateCheck.downloadName(
          'build-1a2b3c4', 'prototype-build-1a2b3c4-windows-setup.exe');
      expect(n, 'prototype-update-build-1a2b3c4.exe');
    });

    test('ends in the asset\'s own extension', () {
      // An extensionless binary in %TEMP% is what endpoint security is tuned
      // to block.
      expect(UpdateCheck.downloadName('build-x', 'P-x86_64.AppImage'),
          endsWith('.AppImage'));
      expect(UpdateCheck.downloadName('build-x', 'prototype-linux'),
          'prototype-update-build-x');
    });

    test('a tag cannot put a path separator into the name', () {
      final n = UpdateCheck.downloadName(r'v1/..\x', 'setup.exe');
      expect(n.contains('/'), isFalse);
      expect(n.contains(r'\'), isFalse);
    });
  });

  group('THE OUTCOME, reported on the next launch', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('upd_outcome'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a different build is an update that worked', () {
      expect(UpdateCheck.outcomeFor(fromBuild: 'aaa1111', currentBuild: 'bbb2222'),
          UpdateOutcome.updated);
    });

    test('the same build is an update that did not install', () {
      expect(UpdateCheck.outcomeFor(fromBuild: 'aaa1111', currentBuild: 'aaa1111'),
          UpdateOutcome.notInstalled);
    });

    test('the marker is read exactly once', () {
      final store = UpdateStore(dir);
      store.recordPending(tag: 'build-bbb2222', fromBuild: 'aaa1111');
      final p = store.takePending();
      expect(p, isNotNull);
      expect(p!.tag, 'build-bbb2222');
      expect(p.from, 'aaa1111');
      expect(store.takePending(), isNull,
          reason: '"Updated" on every launch afterwards would be noise');
    });

    test('and leaves the rest of the update section alone', () {
      final store = UpdateStore(dir);
      store.recordSkip('build-ccc3333');
      store.recordPending(tag: 'build-bbb2222', fromBuild: 'aaa1111');
      store.takePending();
      expect(store.skipTag, 'build-ccc3333');
    });

    test('labels read as a build, not a tag', () {
      expect(UpdateCheck.labelFor('build-e136f74'), 'Build e136f74');
      expect(UpdateCheck.labelFor('v1.2.0'), 'v1.2.0');
    });
  });

  group('SAVING: every open document, not just the one in front of you', () {
    test('flushAllDocuments writes each open tab', () async {
      final dir = Directory.systemTemp.createTempSync('upd');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final app = AppState()
        ..docsDirForTest = dir
        ..volatileDirsForTest = const [];

      await app.createNamedPart('Alpha');
      await app.createNamedPart('Beta');
      await app.createNamedPart('Gamma');
      expect(app.openTabs.length, greaterThanOrEqualTo(3));

      // The process is about to be replaced by the installer, so a tab nobody
      // is looking at loses exactly as much as the visible one.
      await app.flushAllDocuments();
      for (final n in const ['Alpha', 'Beta', 'Gamma']) {
        expect(File('${dir.path}/$n.ptp').existsSync(), isTrue,
            reason: '"$n" was open and must have been written');
      }
    });

    test('one document that will not save does not strand the others',
        () async {
      final dir = Directory.systemTemp.createTempSync('upd2');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final app = AppState()
        ..docsDirForTest = dir
        ..volatileDirsForTest = const [];
      await app.createNamedPart('Alpha');
      // A tab naming a document that no longer exists anywhere: _flushDocument
      // finds it in none of the three maps and does nothing, which must not be
      // an error either.
      app.openTabs.add('GhostTab');
      await app.createNamedPart('Beta');

      await expectLater(app.flushAllDocuments(), completes);
      expect(File('${dir.path}/Alpha.ptp').existsSync(), isTrue);
      expect(File('${dir.path}/Beta.ptp').existsSync(), isTrue);
    });
  });
}
