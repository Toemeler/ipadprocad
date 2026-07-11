// iPadProCAD — app shell. Layout 1:1 with the mock's #stage:
//   ribbon (full width) / main (model browser | viewport  OR  home) / tabbar.
// Starts on the Home view (goHome() in the mock).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'theme.dart';
import 'widgets/bottom_tabbar.dart';
import 'widgets/home_view.dart';
import 'widgets/model_browser.dart';
import 'widgets/ribbon.dart';
import 'widgets/viewport.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final app = AppState();
  app.init();
  runApp(IpadProCadApp(app: app));
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
        body: AnimatedBuilder(
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
    );
  }
}
