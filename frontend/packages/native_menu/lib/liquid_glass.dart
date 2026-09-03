// Prototype — Apple's Liquid Glass, drawn by Flutter, for the platforms that
// do not have it.
//
// THE PROBLEM THIS SOLVES
// -----------------------
// Four of this app's surfaces are a real `UIGlassEffect` on the iPad: the
// ribbon band, the model browser, the floating panels and the tool bars. They
// are not decorated with glass, they ARE glass — the layout runs the document
// edge to edge underneath them precisely so the material has something to
// refract (see RibbonDockLayout, and RibbonSurface's own note that "glass with
// nothing to refract is a lie about the surface"). Off iOS those surfaces fell
// back to a flat painted panel, and a flat panel is a different app.
//
// So this is the material, rebuilt: blur, refraction at the rim, chromatic
// dispersion, a specular edge and the tint, from the same rectangle and the
// same corner radius UIKit is given.
//
// WHAT MAKES IT THE REAL THING RATHER THAN A BLUR
// -----------------------------------------------
// The rim. A `BackdropFilter` with a gaussian is a frosted pane and has been
// available for years; what it cannot do is bend. This runs a fragment shader
// as the backdrop filter, which means the shader is handed the whole backdrop
// as a texture and can sample it OUTSIDE the panel — so the edge shows a
// compressed, dispersed image of what is beside the panel, exactly as a thick
// pane does. That is the tell, and it is why this is a shader and not a
// `BackdropFilter(blur)` with a border painted on top.
//
// WHEN IT IS NOT AVAILABLE
// ------------------------
// `ImageFilter.shader` needs Impeller. Where it is missing — the Skia
// backend, and the flutter_test host, which is why the suite still exercises
// the painted fallback — [LiquidGlass.isAvailable] is false and the callers
// keep the panel they always had. Where Impeller is there but the program
// fails to load, this degrades one step rather than all the way: blur and
// tint, no refraction. A missing shader must cost fidelity, never a frame.
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// How the material is tuned. One place, so the ribbon, the browser and a
/// dialog cannot drift apart.
///
/// The numbers are read off the iPad build rather than invented: an 18 pt
/// corner (RibbonMetrics.radius), a bevel about a third of that, and a
/// displacement small enough that a straight edge behind the panel still
/// reads as straight where it crosses the rim.
@immutable
class LiquidGlassStyle {
  /// Gaussian applied to the backdrop BEFORE the refraction. Blurring first is
  /// what the reference does: look at the material over a busy viewport and
  /// the bent content at the rim is itself soft.
  final double blurSigma;

  /// How far in from the rim the pane stops bending, in logical pixels.
  final double bevel;

  /// How far a ray is displaced at the steepest part of the bevel, in logical
  /// pixels. Above about 20 the profile stops being a lens and starts being a
  /// funhouse mirror.
  final double refraction;

  /// 2 is a plain rounded rectangle; Apple's corner is near 4. The app clips
  /// with `ClipRSuperellipse`, so the rim has to trace the same curve or it
  /// leaves the edge in the corners.
  final double cornerPower;

  /// The material's own light: the colour it ADDS to the backdrop, with the
  /// alpha as the strength.
  ///
  /// Not a colour it blends toward. See the shader — the material opens the
  /// shadows and leaves the highlights, which is measured behaviour and the
  /// opposite of what an alpha blend toward a dark tint does.
  final Color tint;

  /// Strength of the specular hairline along the rim.
  final double specular;

  /// Width of that hairline, in logical pixels.
  final double rimWidth;

  /// Where the light is, in radians. Screen coordinates, so -3π/4 is the
  /// top-left — which is where UIKit puts it and where every other highlight
  /// in this app comes from.
  final double lightAngle;

  /// Dispersion at the rim, as a fraction of the displacement.
  final double chromatic;

  /// Saturation of the backdrop before tinting. Slightly above 1: the system
  /// material lifts colour rather than washing it out.
  final double saturation;

  /// How fast the lift tapers off as the backdrop gets brighter. 1 is a plain
  /// screen; around 1.5 is what matches the device on both a near-black ground
  /// and a bright render at once.
  final double liftTaper;

  /// How much the boundary darkens on the side facing away from the light.
  final double rimShade;

  /// How far the specular tail reaches past the hairline, in logical pixels.
  final double rimFalloff;

  const LiquidGlassStyle({
    required this.blurSigma,
    required this.bevel,
    required this.refraction,
    required this.cornerPower,
    required this.tint,
    required this.specular,
    required this.rimWidth,
    required this.lightAngle,
    required this.chromatic,
    required this.saturation,
    required this.liftTaper,
    required this.rimShade,
    required this.rimFalloff,
  });

  /// The dark scheme's material. A cool, low-alpha charcoal: on the device the
  /// panel over a bright render is clearly dark and clearly transparent, and
  /// both halves of that matter.
  /// The dark scheme's material, fitted to the device.
  ///
  /// Every number here was read off an iPad screenshot rather than chosen:
  /// the tint from the ground the material lands on, the specular from the
  /// measured 50/30/9 fall-off across the top edge, the rim shade from the
  /// dark hairline on the right edge. The refraction is the one exception —
  /// it is barely detectable in a still of a heavily blurred panel, so it is
  /// set to the smallest amount that bends a straight edge visibly rather
  /// than to a measurement.
  static const LiquidGlassStyle dark = LiquidGlassStyle(
    blurSigma: 26,
    bevel: 16,
    refraction: 8,
    cornerPower: 4,
    // rgb: the light it adds. a: how much. 0.5 * 0.27 ~= the +0.11 lift
    // measured on the app's own ground.
    tint: Color(0x457F7D75),
    specular: 0.245,
    rimWidth: 1.1,
    lightAngle: -2.356194, // -3π/4, the top-left
    chromatic: 0.10,
    saturation: 1.06,
    liftTaper: 1.5,
    rimShade: 0.90,
    rimFalloff: 5,
  );

  /// The light scheme's. Not the dark one inverted: a light material stays
  /// bright by ADDING white rather than by removing black, and its rim is
  /// nearer the surface tone, or the edge reads as a drawn border.
  static const LiquidGlassStyle light = LiquidGlassStyle(
    blurSigma: 26,
    bevel: 16,
    refraction: 8,
    cornerPower: 4,
    // The same mechanism, turned up: a light material lifts hard, which is
    // what takes a dark render to a pale panel and leaves paper as paper.
    tint: Color(0xB0FFFFFF),
    specular: 0.26,
    rimWidth: 1.1,
    lightAngle: -2.356194,
    chromatic: 0.08,
    saturation: 1.02,
    liftTaper: 1.35,
    rimShade: 0.10,
    rimFalloff: 5,
  );

  LiquidGlassStyle copyWith({
    Color? tint,
    double? blurSigma,
    double? refraction,
    double? specular,
  }) =>
      LiquidGlassStyle(
        blurSigma: blurSigma ?? this.blurSigma,
        bevel: bevel,
        refraction: refraction ?? this.refraction,
        cornerPower: cornerPower,
        tint: tint ?? this.tint,
        specular: specular ?? this.specular,
        rimWidth: rimWidth,
        lightAngle: lightAngle,
        chromatic: chromatic,
        saturation: saturation,
        liftTaper: liftTaper,
        rimShade: rimShade,
        rimFalloff: rimFalloff,
      );
}

/// Loads and holds the one compiled program.
///
/// One per process, not one per panel: a `FragmentProgram` is a compiled
/// pipeline and there are up to a dozen glass surfaces on screen at once.
/// Each of them still gets its OWN `FragmentShader` (the uniform block is per
/// instance and they have different rectangles), which is cheap.
class LiquidGlassProgram {
  LiquidGlassProgram._();

  static const String _asset = 'packages/native_menu/shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static bool _tried = false;
  static Future<void>? _loading;

  /// True where a shader CAN run as an image filter. Synchronous, stable from
  /// the first frame, and deliberately not a function of whether the program
  /// has finished loading — the callers use it to decide LAYOUT (whether the
  /// document runs under the band), and a layout that changes when an asset
  /// resolves is a layout that jumps at launch.
  static bool get isAvailable =>
      !kIsWeb && ui.ImageFilter.isShaderFilterSupported && !_disabledByEnv;

  /// `PROTOTYPE_GLASS=0` turns the material off.
  ///
  /// A real escape hatch, not a debug flag. The material costs two backdrop
  /// passes per surface, and a machine with no GPU worth the name — a VM, a
  /// remote desktop, an old integrated chip — is better served by the painted
  /// panels than by a correct material at ten frames a second. There is no
  /// setting for it because the choice is about the MACHINE rather than about
  /// the document, and because a user who needs it needs it before the first
  /// frame, which is earlier than any settings file is read.
  ///
  /// It is also how the cost was measured: the same scene, the same
  /// interaction, with and without.
  static final bool _disabledByEnv = _setting() == '0';

  /// The compile-time define first, then the environment. Both, because the
  /// two answer different questions: `--dart-define` pins a build (a kiosk, a
  /// CI screenshot run), the variable lets one user on one machine turn it off
  /// without one.
  static String _setting() {
    const compiled = String.fromEnvironment('PROTOTYPE_GLASS');
    if (compiled.isNotEmpty) return compiled;
    try {
      return io.Platform.environment['PROTOTYPE_GLASS'] ?? '';
    } catch (_) {
      return ''; // web, where there is no environment to read
    }
  }

  /// The compiled program, or null until it has loaded (or if it failed).
  static ui.FragmentProgram? get program => _program;

  /// Starts the load. Safe to call repeatedly; the work happens once.
  ///
  /// Returns a future so `main()` can await it before the first frame and the
  /// panels never paint one frame of blur-without-refraction. Not required to
  /// be awaited: the render object listens for the load and repaints.
  static Future<void> load() {
    if (_tried) return _loading ?? Future<void>.value();
    _tried = true;
    if (!isAvailable) return _loading = Future<void>.value();
    return _loading = ui.FragmentProgram.fromAsset(_asset).then(
      (p) {
        _program = p;
        _ready.value++;
      },
      onError: (Object e, StackTrace st) {
        // One step down, not off a cliff: the panels keep their blur and tint.
        // Reported through the same trace sink the rest of this package uses,
        // so a bug bundle says which surface the app was actually drawing.
        onLoadFailed?.call('liquid glass shader failed to load: $e');
      },
    );
  }

  /// Bumped once the program is there, so live render objects repaint.
  static final ValueNotifier<int> _ready = ValueNotifier<int>(0);
  static Listenable get ready => _ready;

  /// Where a load failure is reported. The app installs a logger.
  static void Function(String message)? onLoadFailed;

  @visibleForTesting
  static void resetForTest() {
    _program = null;
    _tried = false;
    _loading = null;
  }
}

/// The material itself: a surface that refracts what is behind it.
///
/// Takes no touches and paints no children — it is a BACKGROUND, stacked under
/// the panel's own content exactly the way the UIKit platform view is. Clip it
/// yourself; [cornerRadius] tells the shader where the rim is, it does not cut
/// the corners. (The caller already clips, with the superellipse the rest of
/// the app uses, and a second clip here would be a second answer to the same
/// question.)
class LiquidGlass extends StatefulWidget {
  final double cornerRadius;
  final LiquidGlassStyle style;

  const LiquidGlass({
    super.key,
    this.cornerRadius = 0,
    required this.style,
  });

  /// True where this can draw. See [LiquidGlassProgram.isAvailable].
  static bool get isAvailable => LiquidGlassProgram.isAvailable;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    LiquidGlassProgram.load();
    LiquidGlassProgram.ready.addListener(_adopt);
    _adopt();
  }

  void _adopt() {
    final program = LiquidGlassProgram.program;
    if (program == null || _seen == identityHashCode(program)) return;
    _seen = identityHashCode(program);
    final old = _shader;
    final next = program.fragmentShader();
    if (mounted) {
      setState(() => _shader = next);
    } else {
      _shader = next;
    }
    old?.dispose();
  }

  @override
  void dispose() {
    LiquidGlassProgram.ready.removeListener(_adopt);
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TWO backdrop layers, one under the other, and this is not an
    // optimisation to undo.
    //
    // The obvious build is one filter: `ImageFilter.compose(shader, blur)`.
    // It does not work, and the way it fails is worth writing down because it
    // looks like a shader bug. The composed filter changes the INPUT BOUNDS
    // the engine hands the shader — the blur expands them — and the shader's
    // sampler is no longer the identity over `FlutterFragCoord()`. Every
    // sample near the rim then lands outside the texture, gets clamped, and
    // the panel comes out ringed in a hard dark band. (Measured: the same
    // shader with the blur removed refracts correctly.)
    //
    // So the blur is its own layer, painted first, and the shader is a second
    // one above it. Which is also the better picture: the shader's backdrop is
    // then blurred INSIDE the panel and sharp OUTSIDE it, so the rim shows a
    // crisp compressed strip of the surroundings over a frosted face — which
    // is what a real bevel does, and what one composed filter cannot give at
    // any ordering.
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.style.blurSigma > 0.01)
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: widget.style.blurSigma,
                sigmaY: widget.style.blurSigma,
                tileMode: TileMode.clamp,
              ),
              child: const SizedBox.expand(),
            ),
          _LiquidGlassSurface(
            shader: _shader,
            style: widget.style,
            cornerRadius: widget.cornerRadius,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            // A child, and not because anything is drawn into it: a
            // BackdropFilterLayer with no children is not pushed at all (see
            // RenderBackdropFilter, which returns early when child is null),
            // so the surface needs something to be the layer's content even
            // though that something paints nothing.
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }
}

class _LiquidGlassSurface extends SingleChildRenderObjectWidget {
  final ui.FragmentShader? shader;
  final LiquidGlassStyle style;
  final double cornerRadius;
  final double devicePixelRatio;

  const _LiquidGlassSurface({
    required this.shader,
    required this.style,
    required this.cornerRadius,
    required this.devicePixelRatio,
    required Widget super.child,
  });

  @override
  _RenderLiquidGlass createRenderObject(BuildContext context) =>
      _RenderLiquidGlass(
        shader: shader,
        style: style,
        cornerRadius: cornerRadius,
        devicePixelRatio: devicePixelRatio,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderLiquidGlass ro) {
    ro
      ..shader = shader
      ..style = style
      ..cornerRadius = cornerRadius
      ..devicePixelRatio = devicePixelRatio;
  }
}

/// Pushes the backdrop layer, and — the only interesting part — works out
/// WHERE the panel is in the backdrop's own pixel space.
///
/// The shader's `FlutterFragCoord()` is in the backdrop's pixels, which is the
/// window scaled by the device pixel ratio, not the panel's local box. So the
/// rectangle handed to the shader is the panel's GLOBAL position, times the
/// ratio. Using the paint offset instead would be right only while no ancestor
/// is a repaint boundary or a transform, which is a condition no widget should
/// have to rely on.
class _RenderLiquidGlass extends RenderProxyBox {
  _RenderLiquidGlass({
    required ui.FragmentShader? shader,
    required LiquidGlassStyle style,
    required double cornerRadius,
    required double devicePixelRatio,
  })  : _shader = shader,
        _style = style,
        _cornerRadius = cornerRadius,
        _devicePixelRatio = devicePixelRatio;

  ui.FragmentShader? _shader;
  set shader(ui.FragmentShader? v) {
    if (identical(v, _shader)) return;
    _shader = v;
    markNeedsPaint();
  }

  LiquidGlassStyle _style;
  set style(LiquidGlassStyle v) {
    if (v == _style) return;
    _style = v;
    markNeedsPaint();
  }

  double _cornerRadius;
  set cornerRadius(double v) {
    if (v == _cornerRadius) return;
    _cornerRadius = v;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double v) {
    if (v == _devicePixelRatio) return;
    _devicePixelRatio = v;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;

    // The blur is a separate layer below this one (see LiquidGlass.build), so
    // this filter is the shader and nothing else — which is exactly what keeps
    // its sampler the identity over FlutterFragCoord().
    final shader = _shader;
    if (shader == null) {
      // No program: the blur layer underneath is still a translucent surface,
      // and there is nothing for this layer to add. Paint nothing rather than
      // an untinted pass.
      _paintTintOnly(context, offset);
      return;
    }

    ui.ImageFilter filter;
    try {
      _writeUniforms(shader);
      filter = ui.ImageFilter.shader(shader);
    } catch (e) {
      // Uniforms that do not line up must not take the frame with them.
      assert(() {
        debugPrint('LiquidGlass: no refraction — $e');
        return true;
      }());
      _paintTintOnly(context, offset);
      return;
    }

    final BackdropFilterLayer backdrop = layer ??= BackdropFilterLayer();
    backdrop.filter = filter;
    backdrop.blendMode = BlendMode.srcOver;
    context.pushLayer(backdrop, super.paint, offset);
  }

  /// Narrowing the getter only. The framework's setter takes a
  /// [ContainerLayer], and overriding it with a narrower type is not a legal
  /// override — `covariant` would make it legal and would also let a plain
  /// ContainerLayer through at run time, which is the bug it looks like it is
  /// preventing.
  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  /// Where the shader could not run: the tint alone, over whatever the blur
  /// layer below already produced. One step down — a frosted, tinted surface —
  /// rather than a missing panel.
  void _paintTintOnly(PaintingContext context, Offset offset) {
    layer = null;
    context.canvas.drawRect(
      offset & size,
      Paint()..color = _style.tint,
    );
  }

  void _writeUniforms(ui.FragmentShader s) {
    final dpr = _devicePixelRatio;
    final topLeft = localToGlobal(Offset.zero) * dpr;
    final w = size.width * dpr;
    final h = size.height * dpr;
    final style = _style;
    final tint = style.tint;

    // Index 0 and 1 are the backdrop size, which the engine writes itself.
    var i = 2;
    void f(double v) => s.setFloat(i++, v);

    f(topLeft.dx);
    f(topLeft.dy);
    f(topLeft.dx + w);
    f(topLeft.dy + h);

    f(_cornerRadius * dpr);
    f(style.bevel * dpr);
    f(style.refraction * dpr);
    f(style.cornerPower);

    // Straight, not premultiplied: the shader mixes toward the colour by the
    // alpha, so a premultiplied value would tint toward black.
    f(tint.r);
    f(tint.g);
    f(tint.b);
    f(tint.a);

    f(style.specular);
    f(style.rimWidth * dpr);
    f(style.lightAngle);
    f(style.chromatic);

    f(style.saturation);
    f(style.liftTaper);
    f(style.rimShade);
    f(style.rimFalloff * dpr);
  }
}
