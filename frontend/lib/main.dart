// iPadProCAD — app shell. Layout 1:1 with the mock's #stage:
//   ribbon (full width) / main (model browser | viewport  OR  home) / tabbar.
// Starts on the Home view (goHome() in the mock).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'log.dart';

import 'app_state.dart';
import 'theme.dart';
import 'widgets/bottom_tabbar.dart';
import 'widgets/home_view.dart';
import 'widgets/model_browser.dart';
import 'widgets/ribbon.dart';
import 'widgets/viewport.dart';
import 'widgets/viewport3d.dart';
import 'widgets/extrude_dialog.dart';

void main() {
  // Logger FIRST — works synchronously, before any binding exists.
  Log.init();
  runZonedGuarded(() {
    Log.step('main', 'WidgetsFlutterBinding.ensureInitialized', () {
      WidgetsFlutterBinding.ensureInitialized();
    });
    // Route every framework + platform-dispatcher error into the log file.
    FlutterError.onError = (details) {
      Log.e('flutter', 'FlutterError: ${details.exceptionAsString()}',
          details.exception, details.stack);
      FlutterError.presentError(details);
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      Log.e('platform', 'uncaught platform error', error, stack);
      return true;
    };
    // Flutter's default ErrorWidget is a RenderErrorBox, which sizes itself to
    // constraints.biggest — in release it is a plain light-grey block. Inside
    // an intrinsically-sized parent (the ribbon) that means ONE broken widget
    // inflates to full screen height and shoves the rest of the app out of the
    // layout. Replace it with a bounded, obvious marker so a local failure
    // stays local; the real exception is already in the log file.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      Log.e('widget', 'build failed: ${details.exceptionAsString()}',
          details.exception, details.stack);
      return const SizedBox(
        width: 24,
        height: 24,
        child: ColoredBox(color: Color(0x66E05A56)),
      );
    };
    Log.step('main', 'setPreferredOrientations (fire-and-forget)', () {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]).then((_) => Log.i('main', 'orientation set'),
          onError: (e, st) => Log.e('main', 'orientation failed', e, st));
    });
    final app = Log.step('main', 'AppState()', () => AppState());
    // init() is async; log its outcome instead of silently dropping it.
    Log.i('main', '>> AppState.init (async, not awaited)');
    app
        .init()
        .then((_) => Log.i('main', '<< AppState.init OK'))
        .catchError((e, st) => Log.e('main', 'AppState.init FAILED', e, st));
    // The log must survive the app being backgrounded or killed by iOS: flush
    // on every lifecycle change, otherwise the last (most interesting) lines
    // sit in the buffer forever.
    WidgetsBinding.instance.addObserver(_LogFlusher());
    Log.i('main', 'LOG FILE: ${Log.path}');
    Log.i('main', 'build=${Log.build}');
    Log.step('main', 'runApp', () => runApp(IpadProCadApp(app: app)));
    Log.i('main', 'main() completed — first frame pending');
  }, (error, stack) {
    Log.e('zone', 'UNCAUGHT ZONE ERROR', error, stack);
  });
}

class _LogFlusher extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Log.i('lifecycle', state.name);
    Log.flush();
  }
}

class IpadProCadApp extends StatelessWidget {
  final AppState app;
  const IpadProCadApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iPadProCAD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: T.viewport,
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 500),
          textStyle: ts(11.5, Colors.white),
          decoration: BoxDecoration(
            color: const Color(0xFF212429),
            border: Border.all(color: T.sep),
          ),
        ),
      ),
      home: Scaffold(
        // M42-Fix: the CAD canvas must NOT reflow when the software keyboard
        // appears (inline dimension editor). Resizing re-centres the world
        // transform (map() anchors at size/2), which made the whole sketch
        // JUMP on every editor open/close, broke label hit-tests mid-tap,
        // and read as random pan/zoom drift on the device.
        resizeToAvoidBottomInset: false,
        // Apple status bar (time etc.) must not overlap the ribbon.
        body: AnimatedBuilder(
          animation: app,
          builder: (context, _) {
            // The strip SafeArea reserves for the status bar is painted by
            // whatever sits BEHIND the SafeArea, so it has to be coloured
            // here — otherwise it comes out in the scaffold's viewport tone
            // while the ribbon right beneath it is T.panel, which reads as a
            // seam across the top of the screen. It follows the view: the
            // ribbon's tone in a sketch, the gallery's on home.
            return ColoredBox(
              color: app.isHome ? T.galleryBg : T.panel,
              child: SafeArea(
                bottom: false,
                child: Column(children: [
                  // On the home gallery there is no ribbon — the "+" button in the
                  // gallery header is the only new-sketch affordance. The ribbon
                  // only belongs to an open sketch.
                  if (!app.isHome)
                    SizedBox(width: double.infinity, child: Ribbon(app: app)),
                  Expanded(
                    child: app.isHome
                        ? HomeView(app: app)
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                ModelBrowser(app: app),
                                Expanded(
                                  // A 3D part shows the part viewport; an
                                  // open child sketch falls through to the
                                  // unchanged 2D sketcher (M56).
                                  child: app.currentPart != null &&
                                          app.activeChild == null
                                      ? Stack(children: [
                                          Positioned.fill(
                                              child: Viewport3D(app: app)),
                                          if (app.extrudeSession != null)
                                            ExtrudeDialog(app: app),
                                        ])
                                      : Viewport2D(app: app),
                                ),
                              ]),
                  ),
                  BottomTabBar(app: app),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
