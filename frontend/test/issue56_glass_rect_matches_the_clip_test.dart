// #56 — "i get this really weird white artifacts on the modell browser."
//
// Windows, build 98f27fa, and the bundle's screenshot is a real window grab
// (M406's `DesktopShell.screenshot`, not the re-rasterised layer tree that
// #37 was about — an external GPU overlay is in the image, so it is the
// screen). What is on it, measured off the pixels:
//
//   * the model browser's card is clipped from x=60 to x=310 — exactly
//     `railWidth + cardInsetLeft` to `+ cardWide`, which is where the layout
//     says it is, and the contour sits one pixel outside both;
//   * its top and bottom rims are correct: dark contour, bright hairline, the
//     4 px exponential tail. Textbook;
//   * its LEFT 24 px are saturated white, falling off over the next 13, and
//     the rim structure — contour, hairline, tail — reappears 38 px in;
//   * its RIGHT rim is missing altogether, which is the same 38 px the other
//     way: the rim is past the clip;
//   * every OTHER glass surface in the same frame is correct on every edge —
//     the ribbon band at x=0, both tab-bar pills at x=59 and x=111, the quick
//     tools at x=2501. So it is not a global coordinate space.
//
// That is a panel whose `uRect` and whose clip disagree by 38 px in x. The
// shader's answer to such a disagreement was to blow out to white, because
// its rim glow is `exp(-edge / falloff)` and `edge` goes NEGATIVE outside the
// rect; liquid_glass.frag now bounds the material to its own rectangle, which
// is the fix for the artifact and cannot be reached from here (the host has no
// Impeller, so the shader never runs in this suite).
//
// What IS reachable is the half that produced the same symptom last time. #19
// ("liquidglass elements look false") was white slabs too, and there the rect
// was wrong on the Dart side: the origin went through `localToGlobal` and the
// extent came from the local size, so a scaled subtree tore them apart. M398
// fixed that and m398_glass_rect_test pins the arithmetic.
//
// This pins the other input to the same rect: that `localToGlobal` through the
// model browser's OWN ancestor chain lands where the panel actually paints.
// It does — which is what says the 38 px is not Dart's, and is worth having on
// the record rather than in a commit message, because the chain is deep (an
// Align over an infinite-height box, a zero-duration AnimatedContainer, a
// LayoutBuilder, a Stack of nothing but Positioned children, a Row that exists
// to defeat tight constraints, a margin, an AnimatedOpacity) and every one of
// those is a place a future refactor could put a paint offset that
// `localToGlobal` does not see.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/model_browser.dart';
import 'package:prototype/widgets/native_browser_host.dart';

/// Stands where `GlassPanel` stands — `Positioned.fill` inside the card — and
/// reports both answers to "where is this panel": the one the shader is given
/// (`localToGlobal`, which walks the layout tree) and the one the clip and the
/// contour are drawn at (the paint offset, which is the layer tree).
class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required this.onPaint, super.child});

  final void Function(Offset global, Offset paint, Size size) onPaint;

  @override
  _RenderProbe createRenderObject(BuildContext context) =>
      _RenderProbe(onPaint);

  @override
  void updateRenderObject(BuildContext context, _RenderProbe ro) =>
      ro.onPaint = onPaint;
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.onPaint);

  void Function(Offset global, Offset paint, Size size) onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint(localToGlobal(Offset.zero), offset, size);
    super.paint(context, offset);
  }
}

/// The ribbon band's compact rail, and the Windows caption strip — the two
/// rows the stage is inset by in the reported frame. Their values do not
/// matter to the property; what matters is that the panel is NOT at the
/// window's origin, which is the only case where a lost offset could hide.
const double _rail = 46;
const double _caption = 32;

void main() {
  testWidgets(
      'the model browser hands its shader the box its clip is drawn at',
      (t) async {
    t.view.physicalSize = const Size(2560, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    Offset? global;
    Offset? paint;
    Size? size;

    await t.pumpWidget(MaterialApp(
      home: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(width: _rail),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: _caption),
                Expanded(
                  child: Stack(children: [
                    // main.dart's floating slot for the browser.
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 52),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            height: double.infinity,
                            // NativeModelBrowser: the panel's whole footprint,
                            // card plus retract strip, resized in one step.
                            child: AnimatedContainer(
                              duration: Duration.zero,
                              width: NativeModelBrowser.occupiedWidth,
                              child: LayoutBuilder(
                                builder: (context, bc) => Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      right: NativeModelBrowser.occupiedWidth -
                                          ModelBrowser.cardWide -
                                          ModelBrowser.cardInsetLeft,
                                      // ModelBrowser._fill: a Row, so the
                                      // card's own width survives the tight
                                      // bounds the host hands it.
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 280),
                                            width: ModelBrowser.cardWide,
                                            margin: const EdgeInsets.fromLTRB(
                                                ModelBrowser.cardInsetLeft,
                                                ModelBrowser.cardInsetV,
                                                0,
                                                ModelBrowser.cardInsetV),
                                            decoration: const BoxDecoration(
                                              borderRadius: BorderRadius.all(
                                                  Radius.circular(
                                                      ModelBrowser.cardRadius)),
                                            ),
                                            child: Stack(children: [
                                              Positioned.fill(
                                                child: AnimatedOpacity(
                                                  duration: const Duration(
                                                      milliseconds: 280),
                                                  opacity: 1,
                                                  child: _Probe(
                                                    onPaint: (g, p, s) {
                                                      global = g;
                                                      paint = p;
                                                      size = s;
                                                    },
                                                    child:
                                                        const SizedBox.expand(),
                                                  ),
                                                ),
                                              ),
                                              const Column(
                                                  children: [Text('Sketch1')]),
                                            ]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
        ),
      ]),
    ));
    await t.pumpAndSettle();

    // Where the layout says the card is: the stage's corner plus the card's
    // own margin, and nothing else — no band, no retract strip, no double
    // count of the inset.
    expect(global, const Offset(_rail + ModelBrowser.cardInsetLeft,
        _caption + ModelBrowser.cardInsetV));
    expect(size, isNotNull);
    expect(size!.width, ModelBrowser.cardWide);

    // And the layer tree agrees. A paint offset of zero means every ancestor
    // between here and the last layer boundary reported its translation
    // through `applyPaintTransform`, which is the whole contract: the shader's
    // rectangle is measured one way and the clip around it is drawn the other,
    // and a panel whose two answers differ is the white slab in #19 and #56.
    expect(paint, Offset.zero,
        reason: 'the probe paints at its own layer origin, so localToGlobal '
            'is the only thing placing it');
  });
}
