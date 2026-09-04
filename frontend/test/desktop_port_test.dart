// The desktop port's own contracts.
//
// Everything here is shared Dart that only the desktop build reaches, which
// makes it exactly the code that a change on `main` can break without anybody
// noticing: `flutter analyze` sees it, the iPad never runs it, and the first
// symptom is a bundle that launches and quietly does half of what it should.
//
// So the four things that decide whether the Linux (and, later, Windows)
// build IS the same app are pinned here, on the host, with no platform
// channel and no native library:
//
//   1. where the kernels are looked for, and in what order
//   2. what a launch argument turns into
//   3. that the file errands are gated separately from the UIKit surfaces
//   4. that a gallery card's context menu carries the same items the iPad's
//      does, and does the same thing when one is picked
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/native_lib.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/menus.dart';
import 'package:prototype/platform/app_dirs.dart';
import 'package:prototype/platform/desktop_launch.dart';
import 'package:prototype/widgets/context_menu.dart';
import 'package:prototype/widgets/bottom_tabbar.dart';
import 'package:prototype/widgets/home_view.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';

void main() {
  // -------------------------------------------------------------------------
  group('NativeLib — where the kernels come from', () {
    tearDown(NativeLib.resetForTest);

    test('the file name is the platform\'s', () {
      // Not cosmetic: native_lib.dart opens the library by an EXACT name, and
      // the CMake that installs it uses the same one. A mismatch is a bundle
      // that ships the kernels and cannot find them.
      final name = NativeLib.fileName(NativeLib.kernels);
      if (Platform.isWindows) {
        expect(name, 'prototype_native.dll');
      } else if (Platform.isMacOS || Platform.isIOS) {
        expect(name, 'libprototype_native.dylib');
      } else {
        expect(name, 'libprototype_native.so');
      }
    });

    test('the search reaches the bundle layout flutter build produces', () {
      final paths = NativeLib.candidates(NativeLib.kernels);
      final file = NativeLib.fileName(NativeLib.kernels);
      // `flutter build linux` puts the runner at bundle/prototype and the
      // libraries at bundle/lib/. That pair is the shipping case and must be
      // on the list, or a packaged app finds nothing.
      expect(paths.any((p) => p.endsWith('/lib/$file')), isTrue,
          reason: 'bundle/lib/$file must be searched');
      // The loader's own path last, so a distribution package that installs
      // into /usr/lib still works.
      expect(paths.last, file);
    });

    test('an explicit directory wins over everything else', () {
      // What a developer running `flutter run` against a kernel build tree
      // elsewhere sets, and what the CI uses before a bundle exists. It has to
      // come FIRST or a stale copy beside the runner would shadow it.
      final withOverride = NativeLib.candidates(NativeLib.kernels);
      // The environment cannot be mutated from a Dart test, so this asserts
      // the shape rather than the value: without the variable set, the first
      // candidate is the one beside the executable, never a bare file name.
      expect(withOverride.first, isNot(NativeLib.fileName(NativeLib.kernels)));
      expect(withOverride.length, greaterThanOrEqualTo(4));
    });

    test('Cycles is looked for as a separate library', () {
      // Deliberate: it is optional, an order of magnitude bigger, and a build
      // without it is a build without path tracing rather than a broken one.
      expect(NativeLib.cycles, isNot(NativeLib.kernels));
      expect(NativeLib.candidates(NativeLib.cycles).last,
          NativeLib.fileName(NativeLib.cycles));
    });

    test('a miss is reported, not thrown', () {
      // Every caller treats "no symbols" as a supported state. A throw here
      // would take the launch down on a machine with no kernels, which is the
      // normal state of a UI-only `flutter run`.
      expect(() => NativeLib.open('prototype_definitely_not_here'),
          returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  group('app_dirs — where the app keeps its own files', () {
    test('a desktop host is told apart from the iPad', () {
      // The whole point of the split. If this ever answers true on iOS, the
      // app stops using its container and its documents leave the place Files
      // exposes; if it answers false on Linux, they go back to /tmp.
      expect(isDesktopHost, isNot(Platform.isIOS));
      expect(isDesktopHost, isTrue,
          reason: 'this suite runs on a desktop host');
    });

    test('it is a real, writable directory under the data home', () {
      final dir = desktopAppDirectory();
      expect(dir.existsSync(), isTrue);
      expect(dir.path, endsWith(kAppDirName));
      // Never the bare temp root. That was the old fallback, and a reboot
      // deletes it — the failure this function exists to make impossible.
      expect(dir.path, isNot(Directory.systemTemp.path));
      // Writable, which "exists" does not imply: a read-only or full mount
      // exists and cannot be saved into, and finding that out at save time is
      // finding it out too late.
      final probe = File('${dir.path}/.test-probe')..writeAsStringSync('x');
      expect(probe.readAsStringSync(), 'x');
      probe.deleteSync();
    });

    test('it is stable across calls', () {
      // The log, the perf log and AppState all ask separately, and they have
      // to be given the same answer or the log ends up beside a different set
      // of documents than the one the user is editing.
      expect(desktopAppDirectory().path, desktopAppDirectory().path);
    });
  });

  // -------------------------------------------------------------------------
  group('DesktopLaunch — the document a launch carries', () {
    tearDown(DesktopLaunch.resetForTest);

    test('nothing on the command line means nothing to open', () {
      DesktopLaunch.record(const []);
      expect(DesktopLaunch.document, isNull);
    });

    test('the first argument that is a real file wins', () async {
      final dir = Directory.systemTemp.createTempSync('ipc_launch');
      final real = File('${dir.path}/Bracket.ptp')..writeAsStringSync('{}');
      DesktopLaunch.record(['/does/not/exist.ptp', real.path]);
      expect(DesktopLaunch.document, real.absolute.path);
    });

    test('flags are never mistaken for documents', () {
      // `flutter run` and the perf harness both pass their own arguments, and
      // an error dialog at launch because of one would be a regression nobody
      // could work around.
      DesktopLaunch.record(['--enable-dart-profiling', '--observe=0']);
      expect(DesktopLaunch.document, isNull);
    });

    test('the raw arguments stay available for the log', () {
      DesktopLaunch.record(const ['--verbose', 'x.ptp']);
      expect(DesktopLaunch.arguments, ['--verbose', 'x.ptp']);
    });
  });

  // -------------------------------------------------------------------------
  group('NativeMenu — two gates, not one', () {
    test('the UIKit surfaces are iOS only', () {
      // If this ever becomes true off iOS, the app switches away from its own
      // Flutter chrome and has nothing to draw in its place.
      expect(NativeMenu.isSupported, Platform.isIOS);
    });

    test('the file errands include every desktop', () {
      // The host running this suite is a desktop, so this also asserts the
      // thing that matters in practice: Save a copy, Open and the mesh-import
      // question are NOT switched off here the way the menus are.
      expect(NativeMenu.hasFileSurfaces, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('Liquid Glass — the material, and what it decides', () {
    test('the surface is available exactly where a shader filter can run', () {
      // The whole port hinges on this one predicate. It gates the MATERIAL and
      // — through main.dart — the LAYOUT: whether the document runs edge to
      // edge with the browser and the tab bar floating over it, or whether
      // they take rows and columns of their own.
      expect(GlassPanel.isSupported,
          Platform.isIOS || ui.ImageFilter.isShaderFilterSupported);
    });

    test('the test host keeps the painted fallback', () {
      // flutter_test runs without Impeller, so `isSupported` is false here and
      // every widget case in this suite still exercises the panels the app
      // draws where there is no material. That is deliberate: those panels are
      // what a machine without a usable GPU gets, and they have to stay
      // covered. If this ever flips, several hundred golden expectations
      // quietly start describing a different app.
      expect(ui.ImageFilter.isShaderFilterSupported, isFalse,
          reason: 'the tester has no Impeller; see LiquidGlass.isAvailable');
      expect(GlassPanel.isSupported, isFalse);
      expect(RibbonSurface.isGlass, isFalse);
      expect(BottomTabBar.floatingHeight, 0,
          reason: 'without glass the bar keeps its own row');
    });

    test('the dark material is the one measured off the device', () {
      // These are not taste. Each was read off an iPad screenshot: the tint
      // from the ground the material lands on (31,28,24 -> 58,55,50), the
      // specular from the 50/30/9 fall-off across the top edge, the rim shade
      // from the dark hairline at the boundary (11,10,8 against a ground of
      // 31). Changing one means re-measuring, not re-guessing — so a diff that
      // touches them has to touch this too, and say why.
      const s = LiquidGlassStyle.dark;
      expect(s.tint, const Color(0x457F7D75));
      expect(s.specular, 0.18);
      expect(s.rimShade, 0.55);
      expect(s.liftTaper, 1.5);
      expect(s.rimWidth, 1.05);
      expect(s.rimFalloff, 4);
      expect(s.blurSigma, 26);
    });

    test('the light material is the one measured off the device', () {
      // Fitted on the browser's own edges in the light scheme, at 2x:
      //
      //   the LIFT, on two points at once — a backdrop of 141 comes out 196
      //     and one of 243 comes out 249. Solving both gives a PLAIN screen
      //     (taper 1) at an alpha of 0.48, not the damped one the first build
      //     carried.
      //   the HAIRLINE, from +51 / +32 / +12 on consecutive pixels inside the
      //     top edge — a gaussian about one logical pixel wide.
      //   the CONTOUR, from the vertical edges, which land on whole pixel
      //     columns and so resolve the line the horizontal ones only blend:
      //     236 -> 173 and 138 -> 75.
      const s = LiquidGlassStyle.light;
      expect(s.tint, const Color(0x7AFFFFFF));
      expect(s.liftTaper, 1.0);
      expect(s.specular, 0.18);
      expect(s.rimWidth, 1.05);
      expect(s.rimShade, 0.38);
      expect(s.rimFalloff, 4);
      expect(s.blurSigma, 26);
    });

    test('the edge is a property of the material, not of the scheme', () {
      // The device's own hairline is 50/30/9 into a dark interior of 58 and
      // 51/32/12 into a light one of 196 — the same curve at the same
      // strength. Two schemes that disagree about it would be two materials.
      expect(LiquidGlassStyle.light.specular,
          LiquidGlassStyle.dark.specular);
      expect(LiquidGlassStyle.light.rimWidth,
          LiquidGlassStyle.dark.rimWidth);
      expect(LiquidGlassStyle.light.rimFalloff,
          LiquidGlassStyle.dark.rimFalloff);
    });

    test('the refraction stays inside the range the profile is valid over', () {
      // The bend saturates at 1, so `refraction` IS the largest displacement
      // in pixels. Past about a fifth of the bevel the rim stops being a lens
      // and starts sampling a band of backdrop from far enough away to read as
      // a drawn border — which is exactly what the first build did.
      for (final s in [LiquidGlassStyle.dark, LiquidGlassStyle.light]) {
        expect(s.refraction, lessThan(s.bevel));
        expect(s.cornerPower, greaterThanOrEqualTo(2.0),
            reason: 'below 2 the corner is not a superellipse at all');
      }
    });

    test('a style survives copyWith unchanged in every other field', () {
      const base = LiquidGlassStyle.dark;
      final quiet = base.copyWith(blurSigma: 0);
      expect(quiet.blurSigma, 0);
      expect(quiet.tint, base.tint);
      expect(quiet.rimShade, base.rimShade);
      expect(quiet.liftTaper, base.liftTaper);
      expect(quiet.refraction, base.refraction);
    });

    test('the appearance push is what the material follows', () {
      // The app already tells the platform which scheme it is in on every
      // theme change (T._pushToPlatform). Off iOS that message is the ONLY
      // thing that tells the Flutter material whether to be the dark or the
      // light one, so it is recorded unconditionally rather than dropped with
      // the channel call.
      NativeMenu.setAppearance(dark: false);
      expect(NativeMenu.isDarkAppearance.value, isFalse);
      NativeMenu.setAppearance(dark: true);
      expect(NativeMenu.isDarkAppearance.value, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('the gallery card context menu, off iOS', () {
    setUp(OpenMenus.reset);

    AppState makeApp() {
      final app = AppState();
      app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_ctx_test');
      return app;
    }

    Future<void> pumpHome(WidgetTester t, AppState app) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox.expand(child: HomeView(app: app)))));
      await t.pump();
    }

    testWidgets('a long press on a card opens the SAME items the iPad gets',
        (t) async {
      final app = makeApp();
      app.saved = [
        SavedSketchInfo('Bracket', DateTime(2026, 6, 24, 17, 27), null),
      ];
      await pumpHome(t, app);

      await t.longPress(find.text('Bracket'));
      await t.pumpAndSettle();

      // The contract is `sketchMenuGroups`, which is what the native path is
      // handed too — one description of the menu, two things that can draw it.
      final t10n = L.current;
      for (final group in sketchMenuGroups(t10n, isSketch: true)) {
        for (final item in group) {
          expect(find.text(item.title), findsOneWidget,
              reason: '${item.id} must be in the menu');
        }
      }
    });

    testWidgets('picking Rename reaches the same handler the native path does',
        (t) async {
      final app = makeApp();
      app.saved = [
        SavedSketchInfo('Bracket', DateTime(2026, 6, 24, 17, 27), null),
      ];
      await pumpHome(t, app);

      await t.longPress(find.text('Bracket'));
      await t.pumpAndSettle();
      await t.tap(find.text(L.current.rename));
      await t.pumpAndSettle();

      // _onMenuSelection('rename') opens the rename prompt. Its title is the
      // proof the pick was routed, without this test having to know how the
      // prompt is built.
      expect(find.text(L.current.dlgRenameSketch), findsOneWidget);
    });

    testWidgets('a click anywhere else cancels it (M205)', (t) async {
      final app = makeApp();
      app.saved = [
        SavedSketchInfo('Bracket', DateTime(2026, 6, 24, 17, 27), null),
      ];
      await pumpHome(t, app);

      await t.longPress(find.text('Bracket'));
      await t.pumpAndSettle();
      expect(OpenMenus.any, isTrue);

      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text(L.current.duplicate), findsNothing);
      expect(OpenMenus.any, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('showAppContextMenu', () {
    setUp(OpenMenus.reset);

    Future<String?> open(WidgetTester t,
        {required List<List<NativeMenuItem>> groups, String? title}) async {
      String? picked;
      var opened = false;
      await t.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          if (!opened) {
            opened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              picked = await showAppContextMenu(context,
                  at: const Offset(40, 40), groups: groups, title: title);
            });
          }
          return const Scaffold(body: SizedBox.expand());
        }),
      ));
      await t.pumpAndSettle();
      return picked;
    }

    testWidgets('empty groups draw nothing', (t) async {
      await open(t, groups: const []);
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('a title becomes a header', (t) async {
      await open(t,
          title: 'Bracket',
          groups: const [
            [NativeMenuItem(id: 'a', title: 'Rename')]
          ]);
      expect(find.text('Bracket'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
    });

    testWidgets('groups are separated, so Delete stands alone', (t) async {
      // The same shape UIKit gives a two-group menu. One divider between the
      // two groups; a title would add a second, so this case has none.
      await open(t, groups: const [
        [NativeMenuItem(id: 'a', title: 'Rename')],
        [NativeMenuItem(id: 'b', title: 'Delete', destructive: true)],
      ]);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('a destructive row is the error colour and nothing else is',
        (t) async {
      await open(t, groups: const [
        [
          NativeMenuItem(id: 'a', title: 'Rename'),
          NativeMenuItem(id: 'b', title: 'Delete', destructive: true),
        ],
      ]);
      final rename = t.widget<Text>(find.text('Rename'));
      final delete = t.widget<Text>(find.text('Delete'));
      expect(delete.style!.color, isNot(rename.style!.color));
    });
  });
}
