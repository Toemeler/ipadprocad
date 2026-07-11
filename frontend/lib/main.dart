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
    app.init().then((_) => Log.i('main', '<< AppState.init OK')).catchError(
        (e, st) => Log.e('main', 'AppState.init FAILED', e, st));
    Log.step('main', 'runApp', () => runApp(IpadProCadApp(app: app)));
    Log.i('main', 'main() completed — first frame pending');
  }, (error, stack) {
    Log.e('zone', 'UNCAUGHT ZONE ERROR', error, stack);
  });
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
        // Apple status bar (time etc.) must not overlap the ribbon.
        body: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
          animation: app,
          builder: (context, _) {
            return Column(children: [
              SizedBox(
                  width: double.infinity,
                  child: Ribbon(app: app)),
              Expanded(
                child: app.isHome
                    ? HomeView(app: app)
                    : Row(crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ModelBrowser(app: app),
                          Expanded(child: Viewport2D(app: app)),
                        ]),
              ),
              BottomTabBar(app: app),
            ]);
            },
          ),
        ),
      ),
    );
  }
}
