// "the auto update is crashing the app often and is very unreliable.
//  make it production ready on windows"
//
// THE CRASH WAS A RACE, and it was in the order of two lines.
//
//   apply()            -> Process.start(setup.exe, /VERYSILENT, detached)
//   _UpdatePromptState -> await app.flushCurrentDocument(); exit(0);
//
// Setup is `CloseApplications=yes` (windows/installer/prototype.iss), so the
// Restart Manager reaches for this process within a second or two of Setup
// starting — while the line below it was still writing a part file. The
// window went away mid-save. From the outside that is a crash, it happened
// more often on documents big enough to take a moment, and it could take the
// document with it.
//
// THE "UNRELIABLE" HALF WAS THE OTHER END. `RestartApplications=yes` only
// restarts what the Restart Manager itself closed, and after a clean exit
// there is nothing for it to have closed — so the app did not come back.
// Updating and being left looking at the desktop is the rest of the report.
//
// So saving now happens INSIDE apply, before anything is launched, and a
// script queued behind this process's own PID does the installing and the
// relaunching. This file pins the parts that go wrong in the field: the
// quoting, the name on disk, and that every open document is saved rather
// than only the visible one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/update_check.dart';

/// A realistic Windows install, with the space that breaks naive quoting.
const String kExe = r'C:\Program Files\Prototype\prototype.exe';
const String kSetup = r'C:\Users\t\AppData\Local\Temp\prototype-update-4321.exe';

String script({int pid = 4321}) => UpdateCheck.windowsRelaunchScript(
      waitForPid: pid,
      installerPath: kSetup,
      exePath: kExe,
    );

void main() {
  group('THE RACE: the script waits for this process to be gone', () {
    test('it polls for the PID before it runs anything', () {
      final s = script(pid: 4321);
      final wait = s.indexOf('tasklist /FI "PID eq 4321"');
      final run = s.indexOf(kSetup);
      expect(wait, greaterThanOrEqualTo(0),
          reason: 'THE REPORT: Setup used to start while the app was saving');
      expect(wait, lessThan(run),
          reason: 'the wait has to come BEFORE the installer, or it is the '
              'same race with more steps');
    });

    test('and it loops rather than checking once', () {
      final s = script();
      expect(s, contains(':wait'));
      expect(s, contains('goto wait'));
      // `ping -n 2 127.0.0.1` is the sleep every Windows has; `timeout` is
      // not available to a non-interactive console.
      expect(s, contains('ping -n 2 127.0.0.1'));
      expect(s, isNot(contains('timeout /t')));
    });
  });

  group('THE RELAUNCH: the app comes back', () {
    test('the executable is started after the installer, not before', () {
      final s = script();
      expect(s.indexOf('start "" "$kExe"'), greaterThan(s.indexOf(kSetup)),
          reason: 'relaunching before the files are replaced would start the '
              'OLD build, which is worse than not relaunching at all');
    });

    test('exactly one thing relaunches it', () {
      // Two would be worse than none: the Restart Manager restarting what it
      // closed AND this script starting a second copy is two windows on one
      // document. Waiting for the PID is what stops RM having anything to
      // close, and this is the only `start` of the app in the script.
      final s = script();
      expect('start "" "$kExe"'.allMatches(s).length, 1);
      expect(s.contains('/RESTARTAPPLICATIONS'), isFalse);
    });
  });

  group('QUOTING, because Program Files has a space in it', () {
    test('every path the shell reads is quoted', () {
      final s = script();
      expect(s, contains('"$kSetup" /VERYSILENT'));
      expect(s, contains('start "" "$kExe"'));
      // `start`'s first quoted argument is its WINDOW TITLE. Without the
      // empty one, a quoted path is taken as the title and nothing launches.
      expect(s, isNot(contains('start "$kExe"')));
    });

    test('the installer runs silently and without a reboot prompt', () {
      final s = script();
      expect(s, contains('/VERYSILENT'));
      expect(s, contains('/SUPPRESSMSGBOXES'));
      expect(s, contains('/NORESTART'));
    });

    test('and it is a batch file, so it needs CRLF', () {
      // A .cmd with bare LF line endings runs, mostly, and then fails on the
      // labels — `goto wait` cannot find `:wait` when the label line has a
      // stray character on it. Not worth discovering in the field.
      final s = script();
      expect(s, startsWith('@echo off\r\n'));
      expect('\n'.allMatches(s).length, '\r\n'.allMatches(s).length);
    });
  });

  group('CLEANING UP after itself', () {
    test('the installer and the script both go', () {
      final s = script();
      expect(s, contains('del /f /q "$kSetup"'));
      expect(s, contains(r'del /f /q "%~f0"'),
          reason: 'every applied update used to leave ~100 MB in %TEMP%');
    });

    test('the download is named as what it is', () {
      // Was `.prototype-update-<millis>`: no extension, leading dot. An
      // extensionless binary in %TEMP% is what endpoint security is tuned to
      // block, and the dot buys nothing on a filesystem with no notion of it.
      final n = UpdateCheck.downloadName('prototype-1a2b3c4-windows-setup.exe');
      expect(n, endsWith('.exe'));
      expect(n, startsWith('prototype-update-'));
      expect(n, isNot(startsWith('.')));
      expect(n, contains('$pid'),
          reason: 'one name per process, so two runs cannot collide and the '
              'sweep can tell its own file from an older one');
    });

    test('an asset with no extension still gets a usable name', () {
      expect(UpdateCheck.downloadName('prototype-linux'),
          'prototype-update-$pid');
    });

    test('and a dotted asset keeps only its LAST extension', () {
      expect(UpdateCheck.downloadName('prototype-x86_64.AppImage'),
          endsWith('.AppImage'));
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
      // The updater cannot afford an exception here: it used to run in the
      // caller, AFTER the installer had started, where a throw meant the exit
      // never happened and the Restart Manager did the closing instead —
      // which is the crash again, by a different route.
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
