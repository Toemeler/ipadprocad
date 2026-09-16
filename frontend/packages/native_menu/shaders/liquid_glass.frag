#version 460 core
#include <flutter/runtime_effect.glsl>

// Prototype — Liquid Glass, as a backdrop filter.
//
// WHAT THIS IS FOR
// ----------------
// On the iPad the ribbon, the model browser and every floating panel are a
// real `UIGlassEffect`: the system material, with its own refraction, its own
// specular edge and its own response to what is behind it. Off iOS there is no
// such material, and the app's own note about that is the specification this
// shader is written against — "glass with nothing to refract is a lie about
// the surface, not a cheaper version of it" (RibbonSurface). A translucent
// grey panel is not the same app. This is.
//
// WHY A BACKDROP FILTER AND NOT A PAINTER
// ---------------------------------------
// Refraction needs the pixels BEHIND the panel, and a CustomPainter cannot
// read them. `ImageFilter.shader` inside a BackdropFilter can: the engine
// hands the whole backdrop in as a sampler, so the rim can show a bent,
// compressed image of what lies BESIDE the panel — which is the one thing that
// separates thick glass from a blur.
//
// THE COORDINATE SPACE, measured rather than assumed
// --------------------------------------------------
// `FlutterFragCoord()` here is in the BACKDROP's own pixel space — the window,
// not the panel — and the first `vec2` uniform is overwritten by the engine
// with that backdrop's size, which is why nothing sets it and why it must stay
// the first uniform. `texture(uTex, FlutterFragCoord().xy / uSize)` is
// therefore the identity: it reproduces the backdrop exactly where it already
// was. Everything below is a departure from that identity.
//
// (Verified empirically before this was written: a probe that painted bands at
// fixed fragcoord values showed them at window coordinates, not panel ones.)

precision highp float;

/// The backdrop's size in pixels. WRITTEN BY THE ENGINE — see above. It must
/// be the first uniform and must be a vec2, or ImageFilter.shader refuses.
uniform vec2 uSize;

/// The panel, in the same pixel space: (left, top, right, bottom).
uniform vec4 uRect;

/// x  corner radius, px
/// y  bevel depth: how far in from the rim the glass stops bending, px
/// z  refraction: how far a ray is displaced at the steepest part, px
/// w  corner exponent: 2 is a plain rounded rect, ~4 is Apple's squircle
uniform vec4 uShape;

/// The material's own colour, straight (not premultiplied).
uniform vec4 uTint;

/// x  specular strength      z  light angle, radians
/// y  rim width, px — ONE hairline's width, so the dark contour and the
///                    bright line beside it are each about this wide
/// w  chromatic aberration, as a fraction of the displacement
uniform vec4 uLight;

/// x  saturation
/// y  lift taper: how fast the tint's screen gives out as the backdrop
///    brightens. 1 is a plain screen
/// z  contour: how dark the material's own outer line is
/// w  tail: how far the rim's light reaches inward, px
uniform vec4 uGrade;

uniform sampler2D uTex;

out vec4 fragColor;

/// Signed distance to a rounded-superellipse box centred on the origin.
///
/// The corner is a p-norm rather than a circle, because the app clips its
/// panels with `ClipRSuperellipse` — Apple's squircle — and a rim highlight
/// drawn on a circular corner would visibly leave the edge it is meant to be
/// tracing.
float sdGlass(vec2 p, vec2 b, float r, float n) {
  vec2 q = abs(p) - b + vec2(r);
  // Along the straight sides only one component is positive; the p-norm would
  // be the same as the max there, but this branch also covers the interior,
  // where the norm is not defined by a positive quadrant at all.
  if (min(q.x, q.y) < 0.0) return max(q.x, q.y) - r;
  return pow(pow(q.x, n) + pow(q.y, n), 1.0 / n) - r;
}

/// The outward surface normal, by central difference.
///
/// An analytic gradient of the p-norm is not worth the trouble here: this runs
/// once per fragment on a few thousand pixels of chrome, and a one-pixel step
/// is exactly the scale the rim is drawn at anyway.
vec2 glassNormal(vec2 p, vec2 b, float r, float n) {
  const vec2 e = vec2(1.0, 0.0);
  float dx = sdGlass(p + e.xy, b, r, n) - sdGlass(p - e.xy, b, r, n);
  float dy = sdGlass(p + e.yx, b, r, n) - sdGlass(p - e.yx, b, r, n);
  vec2 g = vec2(dx, dy);
  float len = length(g);
  return len > 1e-5 ? g / len : vec2(0.0, -1.0);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;

  // THE RECT AND THE FRAGMENT HAVE TO BE IN THE SAME SPACE, and nothing
  // guarantees they are.
  //
  // `uRect` is measured on the Dart side through `localToGlobal`, so it is in
  // the WINDOW's device pixels. `FlutterFragCoord()` is in the BACKDROP's.
  // Those are one space only while the backdrop IS the window, and the engine
  // never promised that: a backdrop filter under a clip — which this material
  // always is, because GlassPanel clips it to the panel — may be handed a
  // texture covering the clipped region alone. The fragment at the panel's
  // top-left then reads 0 while the rect says 98.
  //
  // THAT IS #56. The card came out as two rectangles — glass where the shader
  // believed the panel to be, untouched backdrop across the rest of it — with
  // the rim drawn 38 px inside the card's own right edge, on two different
  // windows and two different card heights, while every measurement on the
  // Dart side said the rect was the card's to the pixel. Both are true: the
  // rect was right, and it was right about the wrong space.
  //
  // `uSize` settles it, and it is already here: the engine writes the
  // backdrop's size into the first uniform. A backdrop no larger than the
  // panel in BOTH axes cannot be the window, so it is the panel's own region,
  // and the panel's box in that space is the whole of it. When the backdrop IS
  // the window the test is false and nothing changes — which is the band, both
  // tab-bar pills and the quick tools, every surface that renders correctly
  // today and must go on doing so.
  vec2 rectLo = uRect.xy;
  vec2 rectHi = uRect.zw;
  vec2 rectSize = rectHi - rectLo;
  if (uSize.x <= rectSize.x + 1.0 && uSize.y <= rectSize.y + 1.0) {
    rectLo = vec2(0.0);
    rectHi = uSize;
  }

  vec2 centre = 0.5 * (rectLo + rectHi);
  vec2 halfSize = 0.5 * (rectHi - rectLo);
  vec2 p = fc - centre;

  float radius = clamp(uShape.x, 0.0, min(halfSize.x, halfSize.y));
  float power = max(uShape.w, 2.0);
  float d = sdGlass(p, halfSize, radius, power);

  // THE MATERIAL STOPS AT ITS OWN RECTANGLE, and this is a guard rather than
  // a matter of taste.
  //
  // `uRect` is the panel's box in the backdrop's pixel space, measured on the
  // Dart side; the caller clips this filter to the SAME box, so every fragment
  // the shader runs on is inside the rect — until the two disagree. That has
  // now happened twice, and both times it arrived as BLOWN-OUT WHITE: #19
  // ("liquidglass elements look false", a 0.75 transform the rect did not
  // carry) and #56 ("really weird white artifacts on the modell browser", a
  // 38 px disagreement on Windows with the Dart arithmetic measurably right).
  //
  // The white was this shader's doing rather than the measurement's. The rim's
  // inward glow is `exp(-edge / falloff)` with `edge = -d`, so OUTSIDE the
  // rect the exponent turns positive and the term runs away: 38 px out, on a
  // 4 px falloff, is exp(9.5) — some fourteen thousand times the light the rim
  // is meant to add, which saturates to opaque white and reads as a slab. The
  // refraction goes the same way, because `t` is zero out there and zero is
  // the steepest part of the bevel, so the sample is displaced by the full
  // amount as well.
  //
  // Neither term has any meaning off the panel, so neither is evaluated there.
  // INSIDE — every fragment of every surface whose rect and clip agree, which
  // is every surface on every platform today — `onPanel` is 1 and nothing
  // below changes by a bit. Outside it is 0 and this pass is the identity,
  // which leaves the backdrop the blur layer underneath already produced: a
  // panel that stops short of its own clip is a seam, and a seam is a far
  // smaller lie than a white slab over the document.
  float onPanel = 1.0 - smoothstep(0.0, 1.0, d);

  // How deep into the pane this fragment is: 0 at the rim, 1 where the bevel
  // has flattened out and the glass is simply a sheet.
  float bevel = max(uShape.y, 1.0);
  float t = clamp(-d / bevel, 0.0, 1.0);

  // THE BEVEL'S CROSS-SECTION, and this is the part that decides whether it
  // reads as glass or as a gradient.
  //
  // A circular profile — the edge of a lens, not a ramp. The surface angle is
  // zero across the face and turns over hard in the last pixel or two, so the
  // image is untouched over the whole panel and compressed violently right at
  // the rim. A smoothstep would spread the same total bend evenly and give the
  // soft, plastic look that every "glassmorphism" panel has.
  float u = 1.0 - t;                             // 1 at the rim, 0 inside
  float cosA = sqrt(max(1.0 - u * u, 1e-4));
  float slope = u / cosA;                        // tan of the surface angle

  // SATURATED, not clamped, and this is not a detail. The tangent runs to
  // infinity at the rim; a clamp turns the last few pixels into a flat plateau
  // of maximum displacement, which samples a band of the backdrop from tens of
  // pixels away and paints it as a hard dark stripe round the panel. (That is
  // exactly what the first build did, and it looked like a drawn border.)
  // x/(1+x) keeps the shape — nothing across the face, hard turn at the rim —
  // and lands on 1 instead of running away, so uShape.z is the ACTUAL largest
  // displacement in pixels rather than a coefficient of one.
  float bend = slope / (1.0 + slope);

  vec2 nrm = glassNormal(p, halfSize, radius, power);

  // OUTWARD. A convex edge bends a ray toward the thick middle, so the ray
  // that arrives at the rim started further out — the rim shows a squeezed
  // picture of what is beside the panel, not a stretched picture of what is
  // under it. Sampling inward instead is the single most common way to get
  // this wrong, and it looks like a smear.
  vec2 disp = nrm * bend * uShape.z * onPanel;

  // Chromatic aberration, at the rim only because `disp` is zero elsewhere.
  // A real edge disperses; without this the rim is clean in a way glass never
  // is. Kept small — this is a UI surface, not a prism.
  float ca = uLight.w;
  vec2 uvR = clamp((fc + disp * (1.0 + ca)) / uSize, vec2(0.0), vec2(1.0));
  vec2 uvG = clamp((fc + disp) / uSize, vec2(0.0), vec2(1.0));
  vec2 uvB = clamp((fc + disp * (1.0 - ca)) / uSize, vec2(0.0), vec2(1.0));

  vec3 col = vec3(
      texture(uTex, uvR).r,
      texture(uTex, uvG).g,
      texture(uTex, uvB).b);

  // Vibrancy. The material keeps colour rather than washing it out, so a
  // copper render behind the panel is still copper.
  float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(vec3(lum), col, mix(1.0, uGrade.x, onPanel));

  // THE TINT, AND IT IS A LIFT RATHER THAN A WASH.
  //
  // This is the one thing that decides whether the surface reads as Apple's
  // material or as a sheet of tinted perspex over the document, and the first
  // build of it had the sign wrong: `mix(col, darkTint, a)` pulls everything
  // toward the tint, so a bright render behind the panel came out muddy and a
  // dark ground came out darker still.
  //
  // Measured off the device instead. In the dark scheme the material takes the
  // app's own ground from (31,28,24) to (58,55,50) — a lift of about +0.11 —
  // and leaves a bright copper render within a couple of levels of where it
  // was. That is a SCREEN, damped by how bright the backdrop already is: it
  // opens the shadows, which is what makes text legible over anything, and it
  // barely touches the highlights, which is what keeps the render readable
  // through the panel.
  //
  // The exponent is the taper. 1 is a plain screen and lifts the midtones too
  // much; around 1.5 matches the two measured points at once.
  col += uTint.rgb * uTint.a * onPanel *
      pow(max(1.0 - col, vec3(0.0)), vec3(uGrade.y));

  // THE RIM, WHICH IS THREE THINGS AND NOT ONE, and every one of them was
  // read off the device rather than designed.
  //
  // Scan down through the browser's TOP edge on the iPad — light scheme, the
  // panel over the render, green channel at 2x, and the cleanest of the four
  // because the backdrop is the same flat 141 above the boundary and below it:
  //
  //   ... 141 141 141 | 119 | 247 228 208 206 204 203 202 201 200 199 199 198
  //       198 197 197 197 196 196 ...
  //
  // Three features, in this order from the outside in:
  //
  //   1. ONE DARK PIXEL, OUTSIDE the panel. Not a shadow — it is the same
  //      width on all four edges with no offset — and not a fade, because the
  //      pixel beside it is the untouched backdrop. A shader clipped to the
  //      panel cannot reach it, so it is drawn by the widget; see GlassPanel.
  //      What is left here is the sub-pixel case: a boundary that does not
  //      land on a pixel edge puts part of that line INSIDE, and uGrade.z
  //      darkens it there.
  //   2. A BRIGHT HAIRLINE at the first pixel inside, +51 over the interior,
  //      falling to +32 at the next and +12 at the one after. Fitted: that is
  //      a gaussian in the distance from the rim, and the ratios pin its width
  //      to about one logical pixel. It is there on every edge — top +51,
  //      bottom +48, left +23 — so it is a raised lens edge catching the whole
  //      surround, not a light from one corner. The lit side carries a little
  //      more, and only a little.
  //   3. A LONG SOFT TAIL inward: +12, +10, +8, +7, +6, +5, +4, +3, +3, +2, +2,
  //      +1, +1, +1, 0. An exponential with a scale near four logical pixels —
  //      NOT the S-curve a smoothstep gives, which holds its value for the
  //      first few pixels and then falls off a cliff. Reproducing 2 and 3 as
  //      one term is what made the first build's edge read as a soft plastic
  //      bevel: they are a hairline AND a glow, at ten times the width.
  // Clamped at the rim rather than run past it — see `onPanel` above, which
  // is what actually keeps the two terms below off the fragments where a
  // negative edge would matter. This says the same thing a second way, so
  // that `exp(-edge / falloff)` cannot exceed 1 whatever a future caller
  // hands in.
  float edge = max(-d, 0.0);                        // 0 at the rim, grows in

  vec2 lightDir = vec2(cos(uLight.z), sin(uLight.z));
  float lit = max(dot(nrm, lightDir), 0.0);

  float hairScale = max(uLight.y, 0.5);
  float hs = edge / hairScale;
  float hair = exp(-hs * hs);
  float tail = exp(-edge / max(uGrade.w, 1.0));

  col += uLight.x * (0.70 + 0.30 * lit) * hair * onPanel;
  col += uLight.x * (0.20 + 0.15 * lit) * tail * onPanel;

  // The inside half of the outer contour, and nothing more: zero by half a
  // device pixel in, so on a panel whose edge lands on a pixel boundary — the
  // usual case — this costs nothing and GlassPanel's stroke is the whole line.
  col *= 1.0 - uGrade.z * onPanel * (1.0 - smoothstep(0.0, 0.5, edge));

  fragColor = vec4(col, 1.0);
}
