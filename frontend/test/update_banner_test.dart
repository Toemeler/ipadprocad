// "the auto update on windows isnt working at all. on every app start it
//  should check if a new version is available. if there is it should show at
//  the top. then it should show a loading bar of it downloading the new
//  version and when its finished it should ask if it should install the new
//  one now"
//
// update_check.dart drives UpdateCheck.status; this pins what the banner
// makes of it: at the TOP of the window, a progress bar with a percentage
// while downloading, and an Install now / Later question once it is done.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/gen/app_l10n.dart';
import 'package:prototype/update_check.dart';
import 'package:prototype/widgets/update_prompt.dart';

const UpdateInfo kInfo = UpdateInfo(
  tag: 'build-abc1234',
  assetUrl: 'https://example.invalid/setup.exe',
  assetName: 'prototype-build-abc1234-windows-setup.exe',
  checksumsUrl: 'https://example.invalid/SHA256SUMS-windows.txt',
  releaseUrl: 'https://example.invalid/release',
  selfUpdatable: true,
);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('update_banner_test');
    // The banner starts the background check on its first frame, and that
    // waits for the store; attached, a 'local' build checks nothing.
    UpdateCheck.attachStore(UpdateStore(dir));
    UpdateCheck.status.value = UpdateStatus.none;
  });

  tearDown(() {
    UpdateCheck.status.value = UpdateStatus.none;
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('en'),
      home: Material(
        child: Stack(children: [
          const Positioned.fill(child: SizedBox()),
          UpdatePrompt(app: AppState()),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('downloading: at the top, with a progress bar and percentage',
      (tester) async {
    await pump(tester);
    UpdateCheck.status.value = const UpdateStatus(UpdatePhase.downloading,
        info: kInfo, progress: 0.42);
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Downloading Build abc1234…'), findsOneWidget);
    expect(find.text('42 %'), findsOneWidget);
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 0.42);

    final top = tester.getTopLeft(find.text('Update available')).dy;
    expect(top, lessThan(120), reason: 'THE REPORT: it should show at the top');
  });

  testWidgets('size not known yet: the bar is indeterminate', (tester) async {
    await pump(tester);
    UpdateCheck.status.value =
        const UpdateStatus(UpdatePhase.downloading, info: kInfo);
    await tester.pump();
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, isNull);
  });

  testWidgets('finished: asks whether to install now', (tester) async {
    await pump(tester);
    UpdateCheck.status.value =
        const UpdateStatus(UpdatePhase.ready, info: kInfo);
    await tester.pumpAndSettle();

    expect(find.text('Update ready'), findsOneWidget);
    expect(find.text('Install Now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(UpdateCheck.status.value.phase, UpdatePhase.idle);
  });

  testWidgets('a failed download offers to try again', (tester) async {
    await pump(tester);
    UpdateCheck.status.value =
        const UpdateStatus(UpdatePhase.downloadFailed, info: kInfo);
    await tester.pumpAndSettle();
    expect(find.text('The download didn’t finish.'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('Hide keeps the download going but takes the banner away',
      (tester) async {
    await pump(tester);
    UpdateCheck.status.value =
        const UpdateStatus(UpdatePhase.downloading, info: kInfo, progress: 0.1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });
}
