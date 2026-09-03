// Prototype — app shell. Layout 1:1 with the mock's #stage:
//   ribbon (full width) / main (model browser | viewport  OR  home) / tabbar.
// Starts on the Home view (goHome() in the mock).
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'log.dart';
import 'perf.dart';
import 'perf_document.dart';
import 'ffi/perf_hook.dart';
import 'package:gpu_view/gpu_view.dart';
import 'package:reality_view/perf_hook.dart';

import 'cycles_boot.dart';
import 'platform/desktop_launch.dart';
import 'platform/desktop_shell.dart';
import 'app_state.dart';
import 'backdrop.dart';
import 'ribbon_dock.dart';
import 'l10n/l.dart';
import 'theme.dart';
import 'bug_capture.dart';
import 'gesture_trace.dart';
import 'widgets/bottom_tabbar.dart';
import 'widgets/home_view.dart';
import 'widgets/model_browser.dart';
import 'package:native_menu/native_menu.dart';

import 'widgets/native_browser_host.dart';
import 'widgets/quick_tools.dart';
import 'widgets/pattern_panel_3d.dart';
import 'widgets/ribbon_dock_layout.dart';
import 'widgets/viewport.dart';
import 'widgets/viewport3d.dart';
import 'widgets/viewport_assembly.dart';
import 'widgets/edge_feature_dialog.dart';
import 'widgets/extrude_dialog.dart';
import 'widgets/combine_dialog.dart';
import 'widgets/constraint_dialog.dart';
import 'widgets/create_component_dialog.dart';
import 'widgets/drive_dialog.dart';
import 'widgets/joint_dialog.dart';
import 'widgets/split_dialog.dart';
import 'widgets/hole_dialog.dart';
import 'widgets/make_part_dialog.dart';
import 'widgets/work_plane_offset_field.dart';

void main([List<String> args = const <String>[]]) {
  // A desktop launch can carry a document: the file manager runs the .desktop
  // file's `Exec=prototype %f` with the path as an argument. Recorded FIRST,
  // before anything can look at it, and acted on only once AppState.init has
  // finished — see below. Defaulted, so `main()` still has the signature the
  // iOS entry point is called with and nothing about that build changes.
  DesktopLaunch.record(args);
  // Logger FIRST — works synchronously, before any binding exists.
  Log.init();
  Perf.init();
  // The FFI modules time through injected hooks so they keep their "only
  // dart:ffi" invariant (see ffi/perf_hook.dart). Install the real recorder
  // before anything can call the kernel — an unwired hook silently records
  // nothing, which would look exactly like a kernel that costs nothing.
  installFfiPerfHooks(span: Perf.span, count: Perf.count);
  // Same seam for the RealityKit plugin: it is a separate package and the
  // dependency runs app -> plugin, so it cannot import perf.dart either.
  installRealityViewPerfHooks(record: Perf.record, count: Perf.count);
  installNativeMenuPerfHooks(record: Perf.record, count: Perf.count);
  // Time to first frame: the one launch number a user actually feels. Measured
  // from the top of main() to the first frame the engine reports as rasterised,
  // which is the same event MetricKit's MXAppLaunchMetric ends on — so the two
  // can be compared instead of argued about.
  Perf.markLaunchStart();
  runZonedGuarded(() {
    Log.step('main', 'WidgetsFlutterBinding.ensureInitialized', () {
      WidgetsFlutterBinding.ensureInitialized();
    });
    // Only NOW can frame timings be registered — SchedulerBinding.instance
    // does not exist before the line above. Perf.init() ran earlier on purpose
    // (the file must be open before anything can be measured); this is the
    // half that needs the binding. See Perf.attachToBinding.
    Perf.attachToBinding();
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
      return SizedBox(
        width: 24,
        height: 24,
        child: ColoredBox(color: T.err),
      );
    };
    // M147 — FULLSCREEN. The status bar is hidden at runtime as well as in
    // the Info.plist (the workflow patches UIStatusBarHidden, since the Runner
    // is generated by `flutter create` and there is no plist in the repo).
    // Both on purpose: the plist covers the launch image and the first frames,
    // before any Dart has run, and the runtime call covers the case where the
    // system restores the bar after a lifecycle event. Neither alone is
    // enough, and a bar that flashes on for two frames at launch is exactly
    // the sort of thing that only shows up on the device.
    Log.step('main', 'hide system UI (fire-and-forget)', () {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
              overlays: const <SystemUiOverlay>[])
          .then((_) => Log.i('main', 'system UI hidden'),
              onError: (e, st) => Log.e('main', 'hide system UI failed', e, st));
    });
    Log.step('main', 'setPreferredOrientations (fire-and-forget)', () {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]).then((_) => Log.i('main', 'orientation set'),
          onError: (e, st) => Log.e('main', 'orientation failed', e, st));
    });
    // M306 — find out at LAUNCH whether this build can path-trace, rather
    // than at the first render. The Metal backend compiles its kernels from
    // source on the device, so a build carrying the Cycles libraries but not
    // the kernel tree fails inside a shader compiler with an error that names
    // nothing; this checks for the tree, logs the file if it is missing, and
    // leaves rendered mode as the RealityKit view it has always been.
    Log.step('main', 'initCycles', initCycles);
    final app = Log.step('main', 'AppState()', () => AppState());
    // Every native menu pick and every sheet the OS did or did not present,
    // into the same log the bug reporter ships. Installed before the first
    // frame so nothing a user can reach happens off the record.
    NativeMenu.trace = (message) => Log.i('menu', message);
    // M367 — and the Liquid Glass material says whether it came up. Off iOS
    // this is the ribbon's, the browser's and every panel's surface; a program
    // that failed to compile costs the refraction and leaves a plain blur,
    // which looks enough like the real thing that nobody would report it.
    LiquidGlassProgram.onLoadFailed = (m) => Log.w('glass', m);
    Log.step('main', 'LiquidGlassProgram.load', LiquidGlassProgram.load);
    // M372 — and the 3D viewport says which renderer it got.
    //
    // Off iOS the shaded viewport is flutter_scene on Flutter GPU, and Flutter
    // GPU is a per-PROJECT switch rather than a platform capability: the
    // desktop runners turn it on (see linux/runner/my_application.cc), a
    // release build compiles the command-line switch out, and a build that
    // missed it falls back to the CPU painter with no error anywhere. So the
    // question is asked once, before the first frame — the answer decides
    // LAYOUT as well as drawing, and a layout that changes when a capability
    // resolves is a layout that jumps at launch.
    if (!Platform.isIOS) {
      Log.step('main', 'GpuView.probe', GpuView.probe);
      Log.i('3d', GpuView.isSupported
          ? 'renderer: flutter_scene (Flutter GPU)'
          : 'renderer: the CPU painter — Flutter GPU is not available in this '
              'build. On desktop that is the DartProject switch in the runner.');
    }
    // M236 — adopt the iPad's own light/dark setting and start listening for
    // changes BEFORE the first frame, so the app never paints one scheme and
    // then snaps to the other. Only a property read and a callback: the
    // PERSISTED override is read later, from AppState.init, for the same
    // launch-time reason the language is.
    Log.step('main', 'T.followPlatform', T.followPlatform);
    // M268 — the open document's size, reported with every perf snapshot.
    //
    // These five counts used to be a side effect of painting the bottom-right
    // FPS overlay, which is gone: it was a permanent debug readout over a
    // shipping app's canvas. Registering the source here keeps the numbers —
    // and makes them reliable for the first time, since they no longer depend
    // on a readout being visible.
    Log.step('main', 'installDocumentGauges', () => installDocumentGauges(app));
    // init() is async; log its outcome instead of silently dropping it.
    Log.i('main', '>> AppState.init (async, not awaited)');
    app
        .init()
        .then((_) {
          Log.i('main', '<< AppState.init OK');
          _openLaunchDocument(app);
        })
        .catchError((e, st) => Log.e('main', 'AppState.init FAILED', e, st));
    // The log must survive the app being backgrounded or killed by iOS: flush
    // on every lifecycle change, otherwise the last (most interesting) lines
    // sit in the buffer forever. The same observer persists the open document
    // (incl. its gallery preview) when the app is suspended or torn down, so a
    // sketch/part left open — never explicitly closed — still has a fresh card.
    final flusher = _LogFlusher(app);
    WidgetsBinding.instance.addObserver(flusher);
    // The desktop's window close, which arrives too late as a lifecycle event
    // to be useful — see desktop_shell.dart. A no-op on iOS, where no runner
    // asks the question.
    DesktopShell.onWillClose(flusher.flushDocument);
    Log.i('main', 'LOG FILE: ${Log.path}');
    Log.i('main', 'build=${Log.build}');
    Log.step('main', 'runApp', () => runApp(PrototypeApp(app: app)));
    Log.i('main', 'main() completed — first frame pending');
  }, (error, stack) {
    Log.e('zone', 'UNCAUGHT ZONE ERROR', error, stack);
  });
}

/// Opens the document the process was launched with, if there was one.
///
/// AFTER init, never during it: the gallery, the documents directory and the
/// remembered externals all come from init, and a document opened before them
/// is a document that is open and not in the gallery.
///
/// The path is passed as its own bookmark. On the desktop that is the truth —
/// a path IS the durable handle to a file outside the app's folder, which is
/// exactly what a bookmark is for on iOS — and it is what makes Save write
/// back to the file the user double-clicked instead of to a copy. See
/// native_menu/linux, which hands back the same pair from its Open dialog.
void _openLaunchDocument(AppState app) {
  final path = DesktopLaunch.document;
  if (path == null) return;
  Log.i('doc', 'launch argument: opening $path');
  app.openPath(path, bookmark: path).then(
      (name) => Log.i('doc',
          name == null ? 'launch document was refused' : 'opened "$name"'),
      onError: (e, st) => Log.e('doc', 'launch document failed', e, st));
}

class _LogFlusher extends WidgetsBindingObserver {
  final AppState app;
  _LogFlusher(this.app);

  /// Saves of the open document, one after another.
  ///
  /// Two of them can be asked for within a few milliseconds — `hidden` fires
  /// and then the runner asks before closing — and `saveSketch`/`savePart`
  /// write a staging folder and then pack it into the document file. Two of
  /// those interleaved would pack a folder that is being rewritten. Chaining
  /// makes the second wait for the first, which also means the runner's
  /// handshake waits for the save that `hidden` already started, rather than
  /// starting a second one.
  Future<void> _saves = Future<void>.value();

  /// Persist the open document; completes when it is actually on disk.
  Future<void> flushDocument() {
    _saves = _saves.then((_) => app.flushCurrentDocument()).then((_) {
      Log.flush();
    }).catchError((Object e, StackTrace st) {
      // A save that failed must not also break the chain, or every later save
      // in this session is skipped.
      Log.e('lifecycle', 'flush failed', e, st);
    });
    return _saves;
  }

  /// The window's close button, on a desktop.
  ///
  /// iOS never asks: an app is suspended and then killed, and
  /// [didChangeAppLifecycleState] below is where the open document gets
  /// written.
  ///
  /// A desktop embedder that supports `System.requestAppExit` asks first and
  /// WAITS for the answer, which makes this the cleanest place to save.
  /// The GTK embedder in the Flutter version this was written against does
  /// NOT ask — a window close produces `inactive`, `hidden`, and then the
  /// process is gone — so the `hidden` branch below is what actually saves
  /// today. This stays because it costs one method, it is what Windows and a
  /// later GTK will use, and a save that happens twice is a save.
  ///
  /// Answering [ui.AppExitResponse.exit] rather than `cancel`: this saves, it
  /// does not argue. A "you have unsaved changes" dialog would be a new piece
  /// of behaviour that the iPad does not have, and the app has never had
  /// unsaved changes to warn about — every path out of a document persists it.
  /// This is that path, for the one exit route only a desktop has.
  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    Log.i('lifecycle', 'exit requested — flushing the open document');
    await flushDocument();
    return ui.AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Log.i('lifecycle', state.name);
    Log.flush();
    // Leaving the foreground (backgrounded, or being torn down): persist the
    // open document and its preview now. The DXF/part JSON and sidecars are
    // written synchronously inside save*, so they land even on `detached`;
    // the PNG is best-effort. No-op when the gallery is showing.
    //
    // `hidden` is the DESKTOP's version of the same moment, and it is the one
    // that matters here. Measured, not assumed: closing the GTK window
    // produces `inactive` then `hidden` and then the process is gone — no
    // `detached`, and no `System.requestAppExit` for [didRequestAppExit] to
    // answer. Without this line the last edits before a window close were
    // simply lost. It also fires on a minimise, where a save is merely
    // early and costs nothing.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      flushDocument();
    }
  }
}

class PrototypeApp extends StatelessWidget {
  final AppState app;
  const PrototypeApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    // M234 — the language switch applies HERE and nowhere else.
    //
    // `L.locale` is a ValueNotifier, so switching rebuilds exactly this
    // subtree: MaterialApp gets a new locale, Localizations reloads the
    // delegate (synchronously — our delegate returns a SynchronousFuture) and
    // every `L.of(context)` below it reads the other language on the very next
    // frame. Nothing is torn down, no state is lost, the open sketch stays
    // open. That is the difference between a language switch and a restart.
    //
    // M236 — and the appearance switch applies in the SAME place, nested
    // inside it. Every colour on screen is read from the active palette at
    // paint time, so one notification here rebuilds the chrome and marks
    // every CustomPainter dirty. That is what makes a live theme switch
    // possible without threading a BuildContext into the painters.
    return ValueListenableBuilder<Locale>(
      valueListenable: L.locale,
      builder: (context, locale, _) => ValueListenableBuilder<Palette>(
        valueListenable: T.scheme,
        // M270 — and the gallery's backdrop, on the same terms. It changes
        // only one screen, but that screen reads it at PAINT time (see
        // galleryPalette), so the notification has to reach a rebuild the same
        // way the palette's does.
        builder: (context, palette, _) => ValueListenableBuilder<Backdrop>(
          valueListenable: Backdrops.current,
          // M284 — and the ribbon band's dock. It changes the whole content
          // Stack's edges, so it rebuilds the app shell the same way a theme
          // switch does.
          // M349 — and whether the band writes its names, which changes the
          // band's HEIGHT (and a rail's width), so it rebuilds the shell for
          // the same reason the dock does.
          builder: (context, _, __) => ValueListenableBuilder<bool>(
            valueListenable: RibbonLabels.show,
            builder: (context, _____, ______) =>
                ValueListenableBuilder<RibbonPosition>(
            valueListenable: RibbonDock.position,
            // Bug report #11 — and the accent, for the same reason as the
            // backdrop: it is read at PAINT time through `T.accent`, and its
            // own notifier is what says it moved. It cannot ride on T.scheme,
            // whose value is the same Palette object before and after.
            builder: (context, __, ___) => ValueListenableBuilder<Accent>(
              valueListenable: T.accentChoice,
              builder: (context, _______, ________) => _app(locale, palette),
            ),
          ),
          ),
        ),
      ),
    );
  }


  /// M350 — THE DOCUMENT, and nothing that floats over it.
  ///
  /// This layer runs edge to edge under the ribbon band where the native glass
  /// exists (see [RibbonDockLayout]), which is the whole reason it was split
  /// out: a UIGlassEffect blurs what is BEHIND it, and until now what was
  /// behind the band was the app's ground colour. Blurred ground colour is
  /// ground colour, which is why the band read as a painted panel.
  ///
  /// The MODEL BROWSER is here rather than in the chrome when there is no
  /// native panel for it (M108's rule): without glass it is an opaque column
  /// that takes real width beside the viewport, and floating an opaque tree
  /// over the model would just hide it.
  Widget _document(AppState app) {
    if (app.isHome) return HomeView(app: app);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // M367 — `GlassPanel`, not `GlassBrowser`. The question this asks is
        // "is the browser opaque", and the answer stopped being "everywhere
        // but iOS" when the material arrived off iOS too. See the note above.
        if (!GlassPanel.isSupported) NativeModelBrowser(app: app),
        Expanded(
          // A 3D part shows the part viewport; an open child sketch falls
          // through to the unchanged 2D sketcher (M56).
          //
          // M80 — Inventor keeps the LIVE 3D scene while you sketch; it does
          // not draw a flat picture of the model. Autodesk's own Slice
          // Graphics docs give it away: you rotate the model during a sketch,
          // and model geometry can OCCLUDE the sketch plane. Both need real
          // depth. So in a part we ALWAYS render Viewport3D, and an open child
          // sketch simply puts the 2D editor transparently on top with the
          // camera aimed down its plane.
          child: app.currentAssembly != null
              ? ViewportAssembly(app: app)
              : app.currentPart != null
                  ? Stack(children: [
                      Positioned.fill(child: Viewport3D(app: app)),
                      if (app.activeChild != null)
                        Positioned.fill(
                          // Faded in by the camera swing (M88); IgnorePointer
                          // while invisible so a stray tap cannot land on a
                          // sketch that is not on screen yet.
                          child: IgnorePointer(
                            ignoring: app.sketchOverlayFade < 0.99,
                            child: Opacity(
                              opacity: app.sketchOverlayFade,
                              child: Viewport2D(app: app),
                            ),
                          ),
                        ),
                    ])
                  : Viewport2D(app: app),
        ),
      ],
    );
  }

  /// M350 — everything that floats OVER the document.
  ///
  /// Laid out in the box that excludes the band (see [RibbonDockLayout]), so
  /// none of it can slide under the ribbon and none of it has to know the
  /// ribbon exists — M290's promise, kept for the panels it was made for.
  ///
  /// The modeless dialogues moved in here with the rest. They park against the
  /// right-hand edge of the CONTENT area (M206's [DialogDock]), and "the
  /// content area" is precisely this box: they were the one part of the old
  /// stage that would have gone under a floating band.
  Widget _chrome(AppState app) {
    if (app.isHome) {
      return Stack(children: [
        if (GlassPanel.isSupported)
          Positioned(
              bottom: 0, left: 0, right: 0, child: BottomTabBar(app: app)),
        QuickToolsBar(app: app),
      ]);
    }
    return Stack(children: [
      // The document's own modeless panels, per document kind. Each of them
      // collects from the viewport it floats over, which is why they are
      // modeless and why they are ABOVE it and BELOW the standing chrome.
      if (app.currentAssembly != null) ...[
        // M249 — one session, two dialogs: Place Joint and Place Constraint
        // collect identically and share AppState.constraintSession, and the
        // tab is what says which of them is on screen.
        if (app.constraintSession?.isJoint == true)
          JointDialog(app: app)
        else if (app.constraintSession != null)
          ConstraintDialog(app: app),
        // M249 — Drive. Modeless like the other two, and over the viewport
        // because what it animates is the model behind it.
        if (app.driveSession != null) DriveDialog(app: app),
        // M248 — Pattern Component and Mirror Component, in the PART's panel
        // with an assembly session in it.
        if (app.asmPatternSession != null) PatternPanel3D(app: app),
        // M250 — Create In-Place Component. It takes itself away when OK hands
        // over to the plane pick: the card would otherwise sit on top of the
        // face you are choosing.
        if (app.createComponentSession != null)
          CreateComponentDialog(app: app),
        // M247 — an assembly has work planes now, and an offset or an angle
        // plane carries the one number this field edits.
        WorkPlaneOffsetField(app: app),
      ] else if (app.currentPart != null) ...[
        if (app.extrudeSession != null) ExtrudeDialog(app: app),
        if (app.edgeSession != null) EdgeFeatureDialog(app: app),
        // M212 — Rectangular / Circular / Sketch Driven / Mirror, one modeless
        // panel for all four.
        if (app.patternSession != null) PatternPanel3D(app: app),
        if (app.holeSession != null) HoleDialog(app: app), // M225
        if (app.combineSession != null) CombineDialog(app: app), // M227
        if (app.splitSession != null) SplitDialog(app: app), // M228
        // M255 — Make Part. It takes nothing from the viewport (the body was
        // chosen by the long press that opened it), so it stays up until OK
        // or Cancel.
        if (app.makePartSession != null) MakePartDialog(app: app),
        // M169 — the work plane's dynamic offset input. Never modal: the plane
        // it edits must stay visible while the number changes.
        WorkPlaneOffsetField(app: app),
      ],
      // M116 — the browser is a FLOATING card, not a full-height wall: it
      // starts at the top of the content area and stops above the tab bar, so
      // the origin triad in the bottom-left corner stays visible under it.
      // M146/M290 — and it is anchored to this box, which already excludes the
      // band on every dock.
      if (GlassPanel.isSupported)
        Positioned.fill(
          child: Padding(
            padding:
                EdgeInsets.only(bottom: BottomTabBar.floatingHeight + 8),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: double.infinity,
                child: NativeModelBrowser(app: app),
              ),
            ),
          ),
        ),
      // M150 — the tab bar floats too. It was the last thing still taking a
      // row of the Column, which left an opaque strip across the bottom that
      // the model visibly stopped at.
      if (GlassPanel.isSupported)
        Positioned(
            bottom: 0, left: 0, right: 0, child: BottomTabBar(app: app)),
      // M192 — the quick tools on the right edge, always visible. Last in the
      // Stack: it must sit ABOVE everything it floats over, and it is the
      // smallest of the floating panels, so it covers least.
      QuickToolsBar(app: app),
    ]);
  }

  Widget _app(Locale locale, Palette palette) {
    return MaterialApp(
      title: 'Prototype',
      locale: locale,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: materialTheme(palette, accent: T.accent),
      home: Scaffold(
        // M42-Fix: the CAD canvas must NOT reflow when the software keyboard
        // appears (inline dimension editor). Resizing re-centres the world
        // transform (map() anchors at size/2), which made the whole sketch
        // JUMP on every editor open/close, broke label hit-tests mid-tap,
        // and read as random pan/zoom drift on the device.
        resizeToAvoidBottomInset: false,
        // Apple status bar (time etc.) must not overlap the ribbon.
        // M186 — two diagnostic wrappers, outermost first.
        //
        // Listener sees the RAW pointer stream before the gesture arena
        // resolves it, which is the only place a "my tap did the wrong thing"
        // report can be answered from. It never handles anything, so it
        // cannot change behaviour.
        //
        // RepaintBoundary gives the bug button something to photograph. NOTE
        // that on iOS the 3D body is a RealityKit PLATFORM VIEW and is
        // composited by the OS outside Flutter's layer tree, so it will NOT
        // appear in the capture — 2D sketches come out complete, a 3D capture
        // shows the chrome and overlays over empty viewport. The bundle says
        // so next to the image, because a blank 3D area must never be read as
        // "the body was missing".
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: GestureTrace.record,
          onPointerMove: GestureTrace.record,
          onPointerUp: GestureTrace.record,
          onPointerCancel: GestureTrace.record,
          onPointerSignal: GestureTrace.record,
          child: RepaintBoundary(
          key: screenshotKey,
          // M268 — one child, deliberately kept. The bug reporter (M194) and
          // the performance readout (M77) both used to float here; both are
          // gone. Unwrapping the Stack would re-lay-out the entire app to
          // remove nothing, and this is where the next thing that floats over
          // everything will go.
          child: Stack(children: [
          AnimatedBuilder(
          animation: app,
          builder: (context, _) {
            // The strip SafeArea reserves for the status bar is painted by
            // whatever sits BEHIND the SafeArea, so it has to be coloured
            // here — otherwise it comes out in the scaffold's viewport tone
            // while the ribbon right beneath it is T.panel, which reads as a
            // seam across the top of the screen. It follows the view: the
            // ribbon's tone in a sketch, the gallery's on home.
            // M270 — and on home it follows the BACKDROP, or a chosen colour
            // would leave the palette's old ground as a stripe across the top
            // of the very screen it was chosen for. A picture keeps the
            // palette's ground here: the strip is behind the SafeArea and the
            // photograph does not run under it.
            // M346 — over a document the ground is the VIEWPORT's, not the
            // panel's.
            //
            // It is what the strip behind the status bar shows, and (until
            // M350 put the document under the band) it was what the ribbon's
            // glass had to refract. Both want the same answer: the tone the
            // canvas is drawn on, so the boundary is where it already was —
            // between the canvas and the chrome, not across the top of the
            // screen.
            return ColoredBox(
              color: app.isHome
                  ? (galleryGround(Backdrops.current.value, T.palette) ??
                      T.galleryBg)
                  : T.viewport,
              child: SafeArea(
                bottom: false,
                child: Column(children: [
                  // M290 — THE BAND TAKES A ROW OF THE LAYOUT.
                  //
                  // On the home gallery there is no ribbon at all — the "+"
                  // button in the gallery header is the only new-sketch
                  // affordance — so [RibbonDockLayout] hands the stage back
                  // and there is no band for anything to work around.
                  //
                  // Over a document the band gets a real edge of this box and
                  // the whole rest of the app is laid out in what is left.
                  // That IS the placement rule: the model browser is right of
                  // a left band, the quick-tool rail and the ViewCube are left
                  // of a right one and the tab bar rests above a bottom one,
                  // because all three are children of a box that no longer
                  // contains it. Nothing measures the band, nothing subtracts
                  // it, and a panel added tomorrow cannot forget to.
                  Expanded(
                    child: RibbonDockLayout(
                      app: app,
                      // M350 — the DOCUMENT, edge to edge. See
                      // [RibbonDockLayout]: where the native glass exists the
                      // band floats over this layer, so the material has the
                      // model to refract instead of a slab of ground colour.
                      // Only the document is in here; everything that floats
                      // over it is in [stage] and is laid out in the box that
                      // EXCLUDES the band, which is what keeps M290's promise
                      // that no panel has to subtract anything.
                      bleed: _document(app),
                      stage: _chrome(app),
                    ),
                  ),
                  if (!GlassPanel.isSupported) BottomTabBar(app: app),
                ]),
              ),
            );
          },
        ),
          // M194 — the bug reporter used to float here as a draggable red
          // circle. It is the last button of the quick-tool bar now (which
          // renders on the home gallery too, so it is still reachable from
          // every view) and nothing of it floats over the canvas any more.
        ]),
          ),
        ),
      ),
    );
  }
}
