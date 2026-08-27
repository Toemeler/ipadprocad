// M273 — how the model is DRAWN, as opposed to what it is made of.
//
// Two modes, and the split is Inventor's: you model in one and you look at the
// result in the other.
//
//   * shadedWithEdges — the working view, and what this app has always drawn.
//     Matte faces with every B-Rep edge over them. The edges are the point:
//     they are what you snap to, what tells a fillet from a chamfer, and what
//     makes a face boundary readable at a glance. It is not trying to be
//     pretty; it is trying to be unambiguous.
//
//   * rendered — the presentation view. No edge overlay, physically-based
//     materials, a real key light that CASTS SHADOWS, and a ground for those
//     shadows to land on. What you screenshot for someone who is not going to
//     model anything.
//
// ---------------------------------------------------------------------------
// What "rendered" is, and what it is not
// ---------------------------------------------------------------------------
//
// It is RealityKit's real-time physically-based renderer with shadow-casting
// lights: PBR metallic/roughness surfaces, a three-light rig, cast and contact
// shadows, and the edge overlay off. That is a genuinely different picture
// from the working view and it is what the hardware can give at 120 Hz.
//
// WHERE IT APPLIES. RealityKit only, deliberately. That is the iPad viewport
// and the gallery's stills, i.e. everything the app actually renders on the
// device it is for. The CPU painter (non-iOS runs, the host tests, the
// thumbnail fallback) ignores the mode and keeps drawing the working view: it
// has one Lambert number per vertex and no shadow of any kind, so a "rendered"
// mode there could only ever be a shading curve pretending to be the real
// thing — and a pretend rendered mode is worse than an honest missing one.
//
// It is NOT a ray tracer. RealityKit's shadows are shadow-mapped and its
// lighting is rasterised; Apple silicon does have hardware ray tracing, but
// iOS does not expose a "render this scene with it" switch to RealityKit, and
// a real path tracer would be its own subsystem — a Metal renderer, a BVH over
// the tessellation, sampling, denoising — not a mode flag. Writing "ray
// tracing" on this dropdown would be the kind of promise the rest of this app
// does not make. See the ARB: the row says "Gerendert" / "Rendered".
import 'l10n/l.dart';

/// How the 3D viewport draws the model.
enum DisplayMode {
  /// Matte faces plus every B-Rep edge. The default, and the working view.
  shadedWithEdges,

  /// PBR materials, shadow-casting lights, no edge overlay.
  rendered;

  /// The value stored in a document. Stable across renames of the enum.
  String get id => switch (this) {
        DisplayMode.shadedWithEdges => 'shaded',
        DisplayMode.rendered => 'rendered',
      };

  /// True when the renderer should light and shadow the scene properly.
  bool get isRendered => this == DisplayMode.rendered;

  /// [id] back to a mode, or null when it names nothing this build offers.
  static DisplayMode? byId(String? id) {
    for (final m in DisplayMode.values) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// What a document that does not mention a mode gets. Every part and every
  /// assembly written before M273, and every new one.
  static const DisplayMode fallback = DisplayMode.shadedWithEdges;
}

/// The user-visible name. In the ARB, like every other string.
String displayModeName(AppL10n t, DisplayMode m) => switch (m) {
      DisplayMode.shadedWithEdges => t.viewShadedEdges,
      DisplayMode.rendered => t.viewRendered,
    };
