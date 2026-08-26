// Prototype — the RealityKit platform view.
//
// Hosts an ARView (.nonAR) as a passive output surface (user interaction is
// OFF — Flutter owns every gesture). Reconstructs the app's orthographic
// turntable camera from the five PartCamera doubles so the RealityKit picture
// stays locked to the Flutter ViewCube/triad, and renders the scene the app
// pushes over the method channel.
//
// Camera convention (must match frontend/lib/part_render.dart · Cam3):
//   dir      = (sin p·sin a, cos p, sin p·cos a)      // p = pol, a = az
//   forward  = -dir                                    // look direction
//   right(s) = normalize(forward × worldUp)            // worldUp = +Y
//   up(u)    = normalize(s × forward)
//   camera   = (s·ox + u·oy) + dir·D                   // D large; ortho ⇒ D
//              only affects near/far, not projected size
//   vertical world extent on screen = 2·halfH          // ⇒ ortho scale
import Flutter
import Foundation
import UIKit
import simd

#if canImport(RealityKit)
import RealityKit
#endif

final class RealityPartView: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let channel: FlutterMethodChannel

    // The renderer needs RealityKit 2 (MeshDescriptor / MeshResource.generate
    // (from:) / PhysicallyBasedMaterial / Blending) — all iOS 15+. The pod's
    // deployment floor stays 14.0 because Qt-iOS forces it app-wide, so the
    // renderer is RUNTIME-gated: on iOS 14 this view is an empty viewport-
    // coloured surface. Known limitation (the real target is an iPad Pro on
    // iOS 26); raising the app floor to 15 would close the gap entirely.
    private var renderer: AnyObject?

    init(frame: CGRect, channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        container.frame = frame
        RealityPartView.trackBackground(container)
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true

        if #available(iOS 15.0, *) {
            let r = PartRenderer(frame: container.bounds)
            container.addSubview(r.view)
            r.view.frame = container.bounds
            r.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            renderer = r
        }

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
    }

    func view() -> UIView { container }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        // Answerable without a renderer, and deliberately BEFORE the guard: on
        // iOS 14 there is no PartRenderer, and a drain that returned nothing
        // there would look identical to a drain that found no work.
        if call.method == "perfDrain" {
            result(RvPerf.drain())
            return
        }
        guard #available(iOS 15.0, *), let r = renderer as? PartRenderer else {
            result(nil)
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        // Timed HERE rather than in Dart. `3d.push` on the Dart side measures
        // how long the channel call takes to return, which on an asynchronous
        // channel is not how long the scene took to apply — a Dart reading can
        // be a fraction of a millisecond while RealityKit spends thirty on the
        // same payload.
        switch call.method {
        case "setScene":
            RvPerf.time("rv.native.setScene") { r.setScene(args) }
            result(nil)
        case "setOverlays":
            RvPerf.time("rv.native.setOverlays") { r.setOverlays(args) }
            result(nil)
        case "setCamera":
            RvPerf.time("rv.native.setCamera") { r.setCamera(args) }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // M237 — the app's T.viewport, pushed from Dart instead of frozen here.
    //
    // It used to be a `static let` holding 0xFF212830, which is why the 3D
    // viewport stayed charcoal under a cream Flutter chrome. Worse, the 2D
    // sketch painter veils this view at 55% opacity (viewport.dart) — so a
    // near-white veil over a charcoal ground came out as the muddy mid-grey in
    // the sketch screenshot. Both are the same wrong constant.
    private(set) static var viewportColor = UIColor(
        red: 0x21 / 255.0, green: 0x28 / 255.0, blue: 0x30 / 255.0, alpha: 1)

    /// Live views that must repaint when the palette changes. Weak, so a torn
    /// down viewport drops out on its own.
    private static let live = NSHashTable<UIView>.weakObjects()

    static func trackBackground(_ v: UIView) {
        v.backgroundColor = viewportColor
        live.add(v)
    }

    /// Applies a new viewport ground to every live view, now.
    ///
    /// An ARView needs BOTH its `backgroundColor` and its
    /// `environment.background` set: the first is the UIKit layer, the second
    /// is what RealityKit clears the frame to, and a mismatch shows as a flash
    /// of the old colour on the next redraw.
    static func setViewportColor(_ c: UIColor) {
        assert(Thread.isMainThread, "viewport colour must be applied on the main thread")
        viewportColor = c
        for v in live.allObjects {
            v.backgroundColor = c
            #if canImport(RealityKit)
            if #available(iOS 15.0, *), let ar = v as? ARView {
                ar.environment.background = .color(c)
            }
            #endif
        }
    }
}

// ===========================================================================
// The RealityKit renderer proper.
// ===========================================================================
@available(iOS 15.0, *)
final class PartRenderer: NSObject {
    let arView: ARView

    // Scene graph roots.
    private let root = AnchorEntity(world: .zero)
    private let cameraEntity = Entity()
    private let headlight = DirectionalLight()
    private let fillLight = DirectionalLight()

    // Per-solid cached geometry (positions/normals/triangle→face) so a hover
    // (setOverlays) can rebuild just the highlighted-face submesh without the
    // app re-uploading the whole mesh.
    private var solidCache: [String: SolidGeom] = [:]
    private var solidEntities: [String: Entity] = [:]
    /// M241 — the shaded ModelEntity inside each holder, kept so a TINT can be
    /// applied without re-uploading the mesh. Materials used to be chosen only
    /// while a mesh was being built, which is why a material-only payload was
    /// silently ignored (M99) and why body hovering had to re-send geometry.
    private var solidShaded: [String: ModelEntity] = [:]
    /// The tint each solid currently carries (packed ARGB), so re-applying an
    /// unchanged one costs nothing. 0 means the default steel — see
    /// Payload.argb for why a sentinel and not an Optional.
    private var solidTint: [String: Int] = [:]
    /// Where each solid's holder sits. An assembly component's placement (M241);
    /// zero for every solid of a part, which is why a part is unaffected.
    private var solidPlacement: [String: SIMD3<Float>] = [:]
    /// How each solid's holder is turned (M242). Identity for a part and for
    /// an unrotated component; a constraint solve is the only thing that puts
    /// anything else here, and it does so through the LIGHT overlay push.
    private var solidOrientation: [String: simd_quatf] = [:]
    private var planeEntities: [String: PlaneEntity] = [:]
    private var axisEntities: [String: AxisEntity] = [:]
    private var cpEntity: Entity?
    private var sketchRoot = Entity()
    /// Sketch polyline entities with the normal of the plane they lie on, so
    /// a sketch drawn ON a solid face can be lifted clear of it.
    private var sketchEntities: [(Entity, SIMD3<Float>, String)] = []
    /// Edge tubes, kept so they can be nudged toward the camera: a tube is
    /// centred ON the face boundary, so half of it sits INSIDE the solid and
    /// speckles through the surface at grazing angles.
    private var solidEdges: [String: Entity] = [:]
    private var previewEdge: Entity?
    private var edgeEntities: [Entity] {
        Array(solidEdges.values) + (previewEdge.map { [$0] } ?? [])
    }
    /// Mesh revision last uploaded per solid — lets Dart omit the (large)
    /// buffers for solids that did not change, which is what keeps dragging an
    /// extrude distance smooth on a part with several bodies.
    private var solidRev: [String: Int] = [:]
    /// The stroke every outline in the scene was last BUILT at (M251).
    ///
    /// Outlines are geometry, so their world width is baked in at build time;
    /// this is what that width was, and comparing it against what the current
    /// camera wants is the whole rebuild decision. It replaces `edgeBuildHalfH`
    /// — a zoom-only latch that let the on-screen weight swing 1.8x either way
    /// before it did anything, and that the planes and axes never consulted at
    /// all. mmPerPoint 0 means "nothing built yet".
    private var builtStyle = OutlineStyle(mmPerPoint: 0, viewDir: nil)
    /// Last highlight actually built, so hovering the same face does not
    /// regenerate its submesh every frame.
    private var builtHighlight: (String, Int)?
    private var cpState: (Bool, Bool)?
    /// Radius of the rendered geometry around the origin — drives the fitted
    /// near/far range. Starts at the origin-plane extent (±10 mm diagonal).
    private var sceneRadius: Float = 15
    private var previewEntity: Entity?
    /// Geometry of the preview body, kept for the same reason solidCache is:
    /// its outline has to be re-stroked when the camera moves.
    private var previewGeom: SolidGeom?
    private var highlightEntity: ModelEntity?

    /// M127 — one overlay entity for every accented edge, built from raw
    /// polylines so it does not depend on the owning body being drawn.
    private var edgeAccentEntity: ModelEntity?
    /// What it was last built from, so hovering along one edge does not
    /// regenerate the ribbon every frame (same guard as builtHighlight).
    private var builtEdgeAccentKey: String = ""

    // Latest camera (kept so a scene change re-applies the current view).
    private var cam = CameraParams()

    var view: UIView { arView }

    /// Grabs the current RealityKit picture (M82 — gallery stills go through
    /// this so the card and the live viewport come from ONE engine).
    /// `saveToHDR: false` yields a plain sRGB UIImage ready for PNG encoding.
    func snapshot(_ done: @escaping (UIImage?) -> Void) {
        arView.snapshot(saveToHDR: false) { done($0) }
    }

    /// [tracked] is false for the OFF-SCREEN still renderer, and this is the
    /// M269 fix.
    ///
    /// `trackBackground` puts a view in the set that `setViewportColor`
    /// repaints when the palette changes — which is right for a live viewport
    /// and wrong for a renderer that exists for the two-to-eight frames of one
    /// capture. The thumbnailer sets its own transparent ground immediately
    /// after construction; a colour push landing inside that window painted
    /// the ground back to the palette's opaque viewport colour UNDERNEATH the
    /// capture, and the still went to disk carrying the scheme it happened to
    /// be written in. In Chalk that is a cream card among charcoal ones, which
    /// is exactly how this was found.
    ///
    /// Untracked, the still renderer's ground is nobody's business but the
    /// thumbnailer's.
    init(frame: CGRect, tracked: Bool = true) {
        arView = ARView(frame: frame,
                        cameraMode: .nonAR,
                        automaticallyConfigureSession: false)
        super.init()
        commonInit(tracked: tracked)
    }

    private func commonInit(tracked: Bool) {
        arView.isUserInteractionEnabled = false
        if tracked {
            RealityPartView.trackBackground(arView)
        }
        arView.environment.background = .color(RealityPartView.viewportColor)

        // Crisp CAD look: kill the AR post effects that survive into .nonAR.
        // MSAA stays on (RealityKit's default), which is what finally removes
        // the AA cracks/banding the CPU painter fought by hand. Kept to the
        // long-standing option cases only.
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]

        // A camera-locked KEY light (re-oriented every setCamera) so a face
        // pointing at the viewer is brightest — same intent as Cam3.solidLight —
        // plus a dim fixed FILL so faces angled away never go pure black (there
        // is no image-based lighting in a .nonAR scene).
        headlight.light.intensity = 1450
        root.addChild(headlight)
        fillLight.light.intensity = 480
        fillLight.transform = Transform(matrix: Self.lookAt(
            eye: SIMD3<Float>(-3, 6, -4), target: .zero, up: SIMD3<Float>(0, 1, 0)))
        root.addChild(fillLight)

        applyCameraComponent(dist: 400, near: 1, far: 800)
        root.addChild(cameraEntity)
        root.addChild(sketchRoot)
        arView.scene.anchors.append(root)

        // S8 — pay RealityKit's first-use cost here rather than on the first
        // scene. See RealityWarmup in PartScene.swift for why ~417 of the
        // 419.47 ms §7.2.2 attributes to the origin planes is not the planes.
        //
        // `async`, not inline: inline would simply move the stall into
        // platform-view creation, where the user is equally waiting and the
        // viewport has not even painted its background yet. One runloop turn
        // later the surface is up, and the first setScene is still at least a
        // Flutter frame away (viewport3d.dart pushes from the build that
        // follows onCreated's post-frame setState).
        //
        // No capture of self: the warm-up owns nothing and must not keep this
        // renderer alive if the view is torn down before it runs.
        DispatchQueue.main.async { RealityWarmup.run() }
    }

    // MARK: - Camera

    /// [dist] is where the camera sits along +dir; [near]/[far] bracket the
    /// scene TIGHTLY. This matters far more than it looks: an orthographic
    /// depth buffer is LINEAR, so a 0.01…1_000_000 range spread 24 bits over a
    /// million millimetres (~0.06 mm resolution) — coarser than the edge tubes
    /// and the face-highlight lift, which is what made edges speckle, vanish
    /// when zoomed in, and coplanar surfaces fight.
    private func applyCameraComponent(dist: Float, near: Float, far: Float) {
        if #available(iOS 18.0, *) {
            var oc = OrthographicCameraComponent()
            // CALIBRATED ON DEVICE (M60, build 0f04ca2): RealityKit's ortho
            // `scale` is the HALF vertical world extent (Unity's
            // orthographicSize convention), NOT the full height. Cam3 maps
            // [-halfH, +halfH] onto the viewport height, so its half extent is
            // exactly halfH. Passing 2*halfH showed twice the world and made
            // everything render at half size — measured against the Dart
            // overlay's projected plane corners: factor 1.985 ≈ 2.
            oc.scale = Float(max(cam.halfH, 1e-4))
            oc.near = near
            oc.far = far
            cameraEntity.components.set(oc)
            cameraEntity.components.remove(PerspectiveCameraComponent.self)
        } else {
            var pc = PerspectiveCameraComponent()
            pc.near = near
            pc.far = far
            pc.fieldOfViewInDegrees = Float(cam.nearOrthoFovDeg)
            cameraEntity.components.set(pc)
        }
        _ = dist
    }

    func setCamera(_ a: [String: Any]) {
        cam.update(from: a)
        // The outline rebuild used to be decided here, on the zoom alone, and
        // only once it had drifted past 1.8x / 0.55x. placeCamera owns it now
        // (refreshOutlines), because zoom and orbit are the same question and
        // every kind of line has to answer it together.
        placeCamera()
    }

    /// Master switch for the outline ribbons (M70-M72).
    ///
    /// On build 8fb292f these rendered NOTHING on device: the triangle
    /// winding put every ribbon facing away from the camera, so the whole
    /// outline was back-face culled. Fixed in M72 (winding reversed AND the
    /// material made double-sided). The switch stays as an escape hatch — set
    /// it to false to fall back to the 16-sided tube from M69, which is
    /// orientation-independent and swings under 2% in width.
    private static let useRibbons = true

    /// World length of one logical POINT at the current zoom.
    ///
    /// The viewport shows 2*halfH millimetres over `bounds.height` points, so
    /// this is the conversion every line weight in the scene goes through —
    /// and the reason a stroke asked for in points keeps the same on-screen
    /// weight at every zoom and on every screen size. The fallback covers the
    /// window before the view has been laid out (a ~1000 pt viewport), which
    /// is only ever the very first frame.
    private var mmPerPoint: Float {
        let h = Float(arView.bounds.height)
        guard h > 1 else { return Float(cam.halfH) * 2e-3 }
        return Float(cam.halfH) * 2 / h
    }

    /// The stroke the camera wants RIGHT NOW, whatever was last built.
    private var wantedStyle: OutlineStyle {
        OutlineStyle(mmPerPoint: mmPerPoint,
                     viewDir: Self.useRibbons ? cam.dir : nil)
    }

    /// How far the camera may move before every outline is rebuilt.
    ///
    /// WIDTH — 5%. An outline is built at one world width, so its on-screen
    /// weight drifts by exactly the zoom ratio since it was built. The old
    /// latch allowed 1.8x and 0.55x, i.e. a hairline that rendered anywhere
    /// between 0.55 pt and 1.8 pt depending on where the last rebuild happened
    /// to fall — visibly too thick or too thin, and never the same twice.
    ///
    /// 5% of a 1 pt line is 0.1 px on a 2x screen, which nothing can see, and
    /// it costs about 14 rebuilds across a 2x pinch — the same order as the
    /// facing threshold below already costs on an orbit drag, and that has
    /// shipped since M70. Tightening it further buys nothing visible and pays
    /// for it linearly.
    ///
    /// FACING — cos(3 deg), unchanged: a ribbon is only exactly the right
    /// width while it faces the camera, and 3 degrees off costs 0.14%.
    private static let widthTolerance: Float = 1.05
    private static let facingTolerance: Float = 0.99863

    /// Rebuild every outline when the camera has moved far enough for it to
    /// show. One decision for edges, sketch curves, plane borders and axes
    /// together — they are the same kind of line, so they must never be built
    /// at two different answers to the same question.
    private func refreshOutlines() {
        let want = wantedStyle
        guard needsRestroke(want) else { return }
        rebuildOutlines(want)
    }

    private func needsRestroke(_ want: OutlineStyle) -> Bool {
        guard builtStyle.mmPerPoint > 0 else { return true }
        let ratio = want.mmPerPoint / builtStyle.mmPerPoint
        if ratio > Self.widthTolerance || ratio < 1 / Self.widthTolerance {
            return true
        }
        if let a = want.viewDir, let b = builtStyle.viewDir,
           simd_dot(a, b) < Self.facingTolerance {
            return true
        }
        return false
    }

    /// Re-stroke everything at [style]. The solid edges and sketch curves are
    /// what this costs — the plane borders (four segments each) and the axes
    /// (one) are rounding error next to them.
    private func rebuildOutlines(_ style: OutlineStyle) {
        builtStyle = style
        for (id, geom) in solidCache {
            guard let holder = solidEntities[id] else { continue }
            solidEdges[id]?.removeFromParent()
            solidEdges[id] = nil
            if let e = geom.edgeEntity(style: style) {
                holder.addChild(e)
                solidEdges[id] = e
            }
        }
        rebuildSketchRibbons()
        rebuildPreviewEdge()
        for (_, pe) in planeEntities { pe.setStyle(style) }
        for (_, ae) in axisEntities { ae.setStyle(style) }
        applyCenterPointScale()
        // The accent ribbon is camera-facing too, so it must be re-aimed with
        // everything else. Dropping the key forces the next overlay push to
        // rebuild it at the new width and view direction.
        builtEdgeAccentKey = ""
    }

    /// Re-aims the sketch ribbons at the current view. Needed on BOTH orbit
    /// and zoom: a ribbon's orientation follows the view direction and its
    /// width follows halfH, and only the orbit path used to call this — so
    /// zooming left sketch lines at their old width while the model rescaled
    /// around them.
    private func rebuildSketchRibbons() {
        guard Self.useRibbons, !sketchCache.isEmpty else { return }
        let hover = accentHover
        let sel = accentSelected
        rebuildSketches(sketchCache) // clears sketchAccent
        applySketchAccents(hover: hover, selected: sel)
    }

    private func placeCamera() {
        let dir = cam.dir
        let fwd = -dir
        // M89 — the right vector comes from the AZIMUTH, never from dir.
        //
        // It used to be normalize(fwd x (0,1,0)) with a fallback when that got
        // short, and that caused both reported symptoms: the fallback pointed
        // somewhere unrelated to the limit, so the sketch-entry swing SNAPPED
        // at the end; and more basically, at a pole dir = (0,+/-1,0) whatever
        // the azimuth was, so az cannot be recovered from it at all.
        //
        // With dir = (sin p sin a, cos p, sin p cos a):
        //   fwd x (0,1,0) = (sin p cos a, 0, -sin p sin a)
        // whose normalisation is (cos a, 0, -sin a) for EVERY pol, since sin p
        // cancels. No degenerate case, continuous everywhere.
        //
        // Must stay identical to PartCamera.rightFor in part_model.dart: the
        // roll is measured against that basis and applied to this one, so any
        // disagreement renders the sketch rotated or mirrored.
        let azf = Float(cam.az)
        var right = SIMD3<Float>(cos(azf), 0, -sin(azf))
        var up = simd_normalize(simd_cross(right, fwd))

        // M80: roll about the view direction. az/pol pin the basis to world
        // up, which is fine while orbiting but wrong for a sketch on a TILTED
        // face — that face's own u/v must land on screen x/y, and they differ
        // from the derived basis by exactly this angle. Roll is 0 for every
        // camera that existed before, so orbiting is untouched.
        if abs(cam.roll) > 1e-9 {
            let c = Float(cos(cam.roll)), s = Float(sin(cam.roll))
            let r0 = right, u0 = up
            right = simd_normalize(r0 * c + u0 * s)
            up = simd_normalize(u0 * c - r0 * s)
        }

        let center = right * Float(cam.ox) + up * Float(cam.oy)
        // Fit the depth range to the scene instead of using a huge constant:
        // pad covers the geometry radius AND the current view height, so
        // nothing ever clips, while the range stays small enough for a precise
        // depth buffer.
        let pad = max(sceneRadius, Float(cam.halfH)) + 10
        let dist: Float
        if #available(iOS 18.0, *) {
            dist = pad * 4
        } else {
            dist = Float(cam.halfH) / tan(Float(cam.nearOrthoFovRad) * 0.5)
        }
        let near = max(0.001, dist - pad * 2)
        let far = dist + pad * 2
        let pos = center + dir * dist

        // Right-handed look-at: RealityKit cameras look down local -Z, +Y up.
        cameraEntity.transform = Transform(matrix: Self.lookAt(eye: pos, target: center, up: up))

        // Update ortho scale + the fitted depth range for the new zoom.
        applyCameraComponent(dist: dist, near: near, far: far)

        // Coplanar overlays (origin planes, sketches on faces) are lifted a
        // hair toward the camera so they win against an exactly coincident
        // solid face — "the work plane / sketch is in front", like Inventor.
        let bias = max(Float(cam.halfH) * 5e-4, 1e-6)
        for (_, pe) in planeEntities { pe.applyBias(camDir: dir, eps: bias) }
        refreshOutlines()
        for e in edgeEntities { e.position = dir * bias }
        // A sketch drawn ON a solid face is EXACTLY coplanar with it, so it
        // needs a lift comfortably past the depth resolution or it z-fights
        // and reads as "inside" the face. The old bias here was 5e-4 — four
        // times SMALLER than highlightEps, which the code below already
        // documents as the minimum that survives. Match that and add margin.
        for (e, n, _) in sketchEntities {
            let side: Float = simd_dot(n, dir) >= 0 ? 1 : -1
            e.position = n * (sketchEps * side)
        }

        // Headlight follows the camera (points along the view direction).
        headlight.transform = Transform(matrix: Self.lookAt(eye: pos, target: center, up: up))
    }

    /// Column-major world matrix that puts the camera at [eye] looking at
    /// [target] with the given up, matching a right-handed -Z look direction.
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let f = simd_normalize(target - eye)   // forward
        var r = simd_cross(f, up)
        if simd_length(r) < 1e-6 { r = simd_cross(f, SIMD3<Float>(1, 0, 0)) }
        r = simd_normalize(r)
        let u = simd_normalize(simd_cross(r, f))
        // Camera local axes in world: X=r, Y=u, Z=-f (look down -Z).
        let z = -f
        return float4x4(
            SIMD4<Float>(r.x, r.y, r.z, 0),
            SIMD4<Float>(u.x, u.y, u.z, 0),
            SIMD4<Float>(z.x, z.y, z.z, 0),
            SIMD4<Float>(eye.x, eye.y, eye.z, 1))
    }

    // MARK: - Scene

    func setScene(_ a: [String: Any]) {
        sceneRadius = 15 // origin planes span ±10 mm (diagonal ≈ 14.1)
        // Latch the stroke for the whole rebuild BEFORE any of it runs: every
        // builder below reads builtStyle, so a scene comes out at one line
        // weight and one facing rather than at whatever each call site
        // recomputed. placeCamera at the end then finds nothing to restroke.
        builtStyle = wantedStyle
        // Phase by phase, for the same reason the 2D painter is: knowing a
        // scene rebuild cost 40 ms is not actionable, knowing that 36 of them
        // were mesh upload in rebuildSolids is.
        RvPerf.time("rv.native.solids") {
            rebuildSolids(a["solids"] as? [[String: Any]] ?? [])
        }
        RvPerf.time("rv.native.planes") {
            rebuildPlanes(a["planes"] as? [[String: Any]] ?? [])
            rebuildAxes(a["axes"] as? [[String: Any]] ?? [])
            rebuildCenterPoint(a["cp"] as? [String: Any])
        }
        RvPerf.time("rv.native.sketches") {
            rebuildSketches(a["sketches"] as? [[String: Any]] ?? [])
            applySketchAccents(hover: a["hoverSketch"] as? String,
                               selected: Set(a["selSketch"] as? [String] ?? []))
        }
        RvPerf.time("rv.native.accents") {
            rebuildEdgeAccents(from: a["edgeAccent"])
            rebuildPreview(a["preview"] as? [String: Any])
        }
        cpState = nil
        builtHighlight = nil
        RvPerf.time("rv.native.highlight") {
            rebuildHighlight(from: a["highlight"] as? [String: Any])
        }
        RvPerf.time("rv.native.placeCamera") { placeCamera() }
    }

    // Light-touch: hover tints + visibility + face highlight, no mesh upload.
    func setOverlays(_ a: [String: Any]) {
        // M241 — an assembly's component placements ride the LIGHT push, so a
        // drag never enters setScene: no mesh upload, no plane rebuild, no
        // camera re-fit. The heavy path is reserved for the structure of the
        // assembly changing (a component placed, deleted, hidden), which is
        // what the scene signature tracks.
        if let places = a["placements"] as? [[String: Any]] {
            for p in places {
                guard let id = p["id"] as? String else { continue }
                applyPlacement(id,
                               Payload.vec3(p["at"]) ?? SIMD3<Float>(0, 0, 0),
                               Payload.quat(p["rot"]) ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
                applyTint(id, Payload.argb(p["tint"]))
            }
        }
        if let planes = a["planes"] as? [[String: Any]] {
            for p in planes {
                guard let key = p["key"] as? String, let e = planeEntities[key] else { continue }
                e.setVisible((p["visible"] as? NSNumber)?.boolValue ?? true)
                e.setHot((p["hot"] as? NSNumber)?.boolValue ?? false)
            }
        }
        if let axes = a["axes"] as? [[String: Any]] {
            for ax in axes {
                guard let key = ax["key"] as? String, let e = axisEntities[key] else { continue }
                e.setVisible((ax["visible"] as? NSNumber)?.boolValue ?? true)
                e.setHot((ax["hot"] as? NSNumber)?.boolValue ?? false)
            }
        }
        if let c = a["cp"] as? [String: Any] {
            rebuildCenterPoint(c)
        }
        applySketchAccents(hover: a["hoverSketch"] as? String,
                           selected: Set(a["selSketch"] as? [String] ?? []))
        rebuildEdgeAccents(from: a["edgeAccent"])
        rebuildHighlight(from: a["highlight"] as? [String: Any])
    }

    /// Blue prehighlight / selection on individual sketch curves. Cheap: it
    /// only swaps a material, and only on the entities whose state changed.
    private var sketchAccent: [String: Bool] = [:]
    /// Last accent inputs, so re-aiming the sketch ribbons on a camera turn
    /// can restore highlight state that rebuildSketches wipes.
    private var accentHover: String?
    private var accentSelected: Set<String> = []

    /// The colour each sketch curve was BUILT with, parallel to
    /// sketchEntities. Needed because clearing a highlight has to restore that
    /// curve's own tone — falling back to a single flat colour would erase
    /// the constraint-state colouring the moment you hovered anything.
    private var sketchTones: [UIColor] = []

    private func applySketchAccents(hover: String?, selected: Set<String>) {
        accentHover = hover
        accentSelected = selected
        for (idx, item) in sketchEntities.enumerated() {
            let (e, _, key) = item
            guard !key.isEmpty, let me = e as? ModelEntity else { continue }
            let on = (key == hover) || selected.contains(key)
            if sketchAccent[key] == on { continue }
            sketchAccent[key] = on
            let base = idx < sketchTones.count ? sketchTones[idx] : Colors.sketch
            let c = on ? Colors.highlight : base
            me.model?.materials =
                [Self.useRibbons ? Materials.unlitSoft(c) : Materials.unlit(c)]
        }
    }

    private func rebuildSolids(_ solids: [[String: Any]]) {
        // Drop entities no longer present.
        let ids = Set(solids.compactMap { $0["id"] as? String })
        for (id, e) in solidEntities where !ids.contains(id) {
            e.removeFromParent(); solidEntities[id] = nil; solidCache[id] = nil
            solidShaded[id] = nil
            solidTint[id] = nil
            solidPlacement[id] = nil
            solidOrientation[id] = nil
        }
        for (id, e) in solidEdges where !ids.contains(id) {
            e.removeFromParent(); solidEdges[id] = nil; solidRev[id] = nil
        }
        // M127 — the accent no longer references solids at all (raw
        // polylines), so there is nothing to clean up per solid here. It is
        // cleared by the next overlay push carrying an empty set.
        for s in solids {
            guard let id = s["id"] as? String else { continue }
            let rev = (s["rev"] as? NSNumber)?.intValue ?? 0
            let at = Payload.vec3(s["at"]) ?? SIMD3<Float>(0, 0, 0)
            let rot = Payload.quat(s["rot"]) ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            let tint = Payload.argb(s["tint"])
            // Dart omits the buffers when a solid's mesh is unchanged: keep the
            // entity and the cached geometry that are already on screen.
            //
            // M241 — but still take the PLACEMENT and the TINT from it. Those
            // are the two things about an assembly component that change while
            // its mesh does not (dragging it, selecting it), and skipping the
            // whole payload meant a drag could only be expressed by re-sending
            // every vertex of the part being dragged.
            if s["positions"] == nil {
                if let cached = solidCache[id] {
                    applyPlacement(id, at, rot)
                    applyTint(id, tint)
                    sceneRadius = max(sceneRadius,
                                      cached.boundingRadius + simd_length(at))
                    solidRev[id] = rev
                }
                continue
            }
            guard let geom = SolidGeom(payload: s) else { continue }
            solidRev[id] = rev
            solidCache[id] = geom
            // if/else, not a ternary: the two branches are DIFFERENT concrete
            // types (PhysicallyBasedMaterial vs SimpleMaterial) and Swift
            // rejects a ternary whose arms mismatch even with an existential
            // annotation.
            let material: RealityKit.Material
            if (s["material"] as? NSNumber)?.intValue == 1 {
                material = Materials.preview()
            } else if let c = Payload.color(tint) {
                material = Materials.tinted(c)
            } else {
                material = Materials.steel()
            }
            sceneRadius = max(sceneRadius, geom.boundingRadius + simd_length(at))
            let shaded = geom.shadedEntity(material: material)
            let edges = geom.edgeEntity(style: builtStyle)
            let holder = Entity()
            holder.position = at
            holder.orientation = rot
            solidPlacement[id] = at
            solidOrientation[id] = rot
            solidTint[id] = tint
            solidShaded[id] = shaded as? ModelEntity
            holder.addChild(shaded)
            solidEdges[id]?.removeFromParent()
            solidEdges[id] = nil
            if let edges = edges {
                holder.addChild(edges)
                solidEdges[id] = edges
            }
            // Replace the previous holder for this id.
            solidEntities[id]?.removeFromParent()
            root.addChild(holder)
            solidEntities[id] = holder
        }
    }

    /// M241 — move a component without touching its mesh.
    ///
    /// The placement lives on the holder Entity, so RealityKit transforms the
    /// shaded mesh AND its edge tubes together and the depth buffer sorts the
    /// result against every other component for free. This is what makes
    /// dragging a component cost a transform write per frame instead of a
    /// multi-megabyte buffer upload.
    private func applyPlacement(_ id: String, _ at: SIMD3<Float>,
                                _ rot: simd_quatf) {
        guard let holder = solidEntities[id] else { return }
        // Both halves of the rigid transform have to be compared before the
        // early-out: a component being SPUN by the constraint solver holds its
        // position exactly, and testing the translation alone would freeze it.
        let sameAt = solidPlacement[id].map { simd_distance($0, at) < 1e-7 } ?? false
        let sameRot = solidOrientation[id].map {
            abs(simd_dot($0.vector, rot.vector)) > 1 - 1e-9
        } ?? false
        if sameAt && sameRot { return }
        solidPlacement[id] = at
        solidOrientation[id] = rot
        holder.position = at
        holder.orientation = rot
        if let g = solidCache[id] {
            // A rotation about the holder's own origin leaves the radius the
            // mesh sweeps unchanged, so only the translation enters here.
            sceneRadius = max(sceneRadius, g.boundingRadius + simd_length(at))
        }
    }

    /// M241 — recolour a solid without touching its mesh. The zero sentinel
    /// restores steel; see Payload.argb.
    private func applyTint(_ id: String, _ tint: Int) {
        if (solidTint[id] ?? 0) == tint { return }
        solidTint[id] = tint
        guard let me = solidShaded[id] else { return }
        if let c = Payload.color(tint) {
            me.model?.materials = [Materials.tinted(c)]
        } else {
            me.model?.materials = [Materials.steel()]
        }
    }

    private func rebuildPlanes(_ planes: [[String: Any]]) {
        for (_, e) in planeEntities { e.entity.removeFromParent() }
        planeEntities.removeAll()
        for p in planes {
            guard let key = p["key"] as? String,
                  let e = PlaneEntity(payload: p, style: builtStyle) else { continue }
            root.addChild(e.entity)
            planeEntities[key] = e
        }
    }

    private func rebuildAxes(_ axes: [[String: Any]]) {
        for (_, e) in axisEntities { e.entity.removeFromParent() }
        axisEntities.removeAll()
        for ax in axes {
            guard let key = ax["key"] as? String,
                  let e = AxisEntity(payload: ax, style: builtStyle) else { continue }
            root.addChild(e.entity)
            axisEntities[key] = e
        }
    }

    private func rebuildCenterPoint(_ c: [String: Any]?) {
        let vis = ((c?["visible"] as? NSNumber)?.boolValue ?? false)
        let hotNow = ((c?["hot"] as? NSNumber)?.boolValue ?? false)
        if let st = cpState, st == (vis, hotNow) { return }
        cpState = (vis, hotNow)
        cpEntity?.removeFromParent(); cpEntity = nil
        guard vis else { return }
        cpHot = hotNow
        // UNIT sphere, sized by the entity's SCALE rather than by the mesh.
        // The marker had a fixed 0.5 mm radius and so had the same defect the
        // plane borders did — a boulder zoomed in, invisible zoomed out — but
        // unlike a border it is a sphere centred on the origin, so a scale
        // holds it exactly at its point size with no mesh work at all.
        let e = ModelEntity(
            mesh: .generateSphere(radius: 1),
            materials: [Materials.unlit(hotNow ? Colors.green : Colors.orange)])
        cpEntity = e
        root.addChild(e)
        applyCenterPointScale()
    }

    /// Hot state of the centre-point marker, so its size can be re-applied on
    /// a zoom without rebuilding it.
    private var cpHot = false

    private func applyCenterPointScale() {
        guard let e = cpEntity else { return }
        let d = cpHot ? Stroke.centerPointHot : Stroke.centerPoint
        e.scale = .init(repeating: builtStyle.halfWidth(d))
    }

    /// Last sketch payload, kept so the ribbons can be re-aimed when the view
    /// turns — a ribbon is only correct while it faces the camera.
    private var sketchCache: [[String: Any]] = []

    private func rebuildSketches(_ sketches: [[String: Any]]) {
        sketchCache = sketches
        sketchRoot.removeFromParent()
        sketchRoot = Entity()
        sketchEntities.removeAll()
        sketchTones.removeAll() // parallel array, must reset together
        sketchAccent.removeAll()
        for sk in sketches {
            guard let polys = sk["polylines"] as? [Any] else { continue }
            // Normal of the sketch plane (origin plane or the picked face).
            let n = Payload.vec3(sk["n"]) ?? SIMD3<Float>(0, 0, 1)
            let keys = sk["keys"] as? [String] ?? []
            // Per-curve colours (M81): 2D paints white / blue-violet / yellow
            // by constraint state and projection, and 3D used one flat tone,
            // so the same sketch read differently in the two viewports.
            let cols = sk["colors"] as? [Any]
            for (i, raw) in polys.enumerated() {
                guard let pts = Payload.floats(raw) else { continue }
                var tone = Colors.sketch
                if let cols = cols, i < cols.count,
                   let argb = (cols[i] as? NSNumber)?.intValue {
                    tone = UIColor(
                        red: CGFloat((argb >> 16) & 0xFF) / 255.0,
                        green: CGFloat((argb >> 8) & 0xFF) / 255.0,
                        blue: CGFloat(argb & 0xFF) / 255.0,
                        alpha: CGFloat((argb >> 24) & 0xFF) / 255.0)
                }
                sketchTones.append(tone)
                if let e = OutlineBuilder.polyline(pts, color: tone,
                                                   style: builtStyle) {
                    sketchRoot.addChild(e)
                    sketchEntities.append((e, n, i < keys.count ? keys[i] : ""))
                }
            }
        }
        root.addChild(sketchRoot)
    }

    // M95's finding is now the rule for every line rather than for sketch
    // curves alone: a stroke is stated in POINTS and converted through
    // `mmPerPoint`, because "the sketch lines in 3D are too thick; they should
    // be the same thickness as in 2D" is only answerable in the unit the 2D
    // sketcher strokes in. `edgeRadius` and `sketchRadius` stood here and are
    // gone — one was a fixed multiple of the world height, which is a
    // different weight on every screen size. See Stroke and OutlineStyle in
    // PartScene.swift.

    /// Outward lift of a sketch off the face it was drawn on. Must exceed the
    /// depth resolution at the current zoom (see highlightEps).
    private var sketchEps: Float { max(Float(cam.halfH) * 3e-3, 1.5e-5) }

    /// Outward lift of the blue face prehighlight — must comfortably exceed
    /// the depth resolution at the current zoom, or the highlight is swallowed
    /// by the face it is supposed to mark.
    private var highlightEps: Float { max(Float(cam.halfH) * 2e-3, 1e-5) }

    private func rebuildPreview(_ p: [String: Any]?) {
        previewEntity?.removeFromParent(); previewEntity = nil
        previewEdge = nil
        previewGeom = nil
        guard let p = p, let geom = SolidGeom(payload: p) else { return }
        sceneRadius = max(sceneRadius, geom.boundingRadius)
        let holder = Entity()
        holder.addChild(geom.shadedEntity(material: Materials.preview()))
        previewGeom = geom
        previewEntity = holder
        rebuildPreviewEdge()
        root.addChild(holder)
    }

    /// Re-stroke the preview body's outline. It was the one outline nothing
    /// ever rebuilt: a fillet or extrude preview kept the width it was born
    /// with however far you zoomed afterwards, and it was built as a TUBE
    /// while every other outline on screen was a ribbon — so the preview's
    /// edges never quite matched the edges of the part around it.
    private func rebuildPreviewEdge() {
        guard let geom = previewGeom, let holder = previewEntity else { return }
        previewEdge?.removeFromParent()
        previewEdge = nil
        if let edges = geom.edgeEntity(color: Colors.previewEdge,
                                       style: builtStyle) {
            holder.addChild(edges)
            previewEdge = edges
        }
    }

    // Blue prehighlight of the hovered planar face: a submesh of just that
    // face's triangles, nudged a hair toward the camera to beat z-fighting.
    /// M127 — overlay the accented edges, built from RAW WORLD POLYLINES.
    ///
    /// Previously this looked each edge up as "display index N of solid X" via
    /// solidCache. That broke as soon as a fillet preview appeared: the
    /// previewed body is replaced on screen, so it is not in solidCache, so
    /// there was nothing to hang the ribbon on and the hover prehighlight
    /// disappeared exactly when it was needed most. Points travel now, so the
    /// accent no longer cares whether its body is drawn.
    private func rebuildEdgeAccents(from a: Any?) {
        var lines = [[SIMD3<Float>]]()
        if let m = a as? [String: Any], let raw = m["lines"] as? [Any] {
            for l in raw {
                // Payload.floats already groups the flat Float32 triples into
                // points (M74), so take them as they come. Re-grouping here is
                // what broke the build: f[i] is a POINT, not a Float. The old
                // `f.count >= 6` meant "at least two points" and still does.
                guard let pts = Payload.floats(l), pts.count >= 2 else { continue }
                lines.append(pts)
            }
        }
        // Cheap identity for the cache: total point count plus the first and
        // last coordinate. Hovering along one edge holds all three steady, so
        // the ribbon is not rebuilt every frame.
        let sig = lines.reduce(0) { $0 &+ $1.count &* 131 }
        let key = "\(sig)|\(lines.first?.first?.x ?? 0)|\(lines.last?.last?.z ?? 0)"
        if key == builtEdgeAccentKey && edgeAccentEntity != nil { return }
        edgeAccentEntity?.removeFromParent()
        edgeAccentEntity = nil
        builtEdgeAccentKey = key
        guard !lines.isEmpty, let v = builtStyle.viewDir else { return }
        // Clearly wider than the base outline: the two ribbons are coplanar by
        // construction, so a depth nudge alone still leaves them z-fighting.
        let lifted = lines.map { $0.map { $0 + cam.dir * highlightEps } }
        guard let mesh = RibbonBuilder.mesh(
            lifted, halfWidth: builtStyle.halfWidth(Stroke.accent),
            viewDir: v) else { return }
        let e = ModelEntity(mesh: mesh,
                            materials: [Materials.unlitSoft(Colors.highlight)])
        edgeAccentEntity = e
        root.addChild(e)
    }

    private func rebuildHighlight(from h: [String: Any]?) {
        let want: (String, Int)? = {
            guard let h = h, let id = h["solid"] as? String,
                  let f = (h["face"] as? NSNumber)?.intValue, f >= 0 else { return nil }
            return (id, f)
        }()
        // Hovering the same face must not regenerate its submesh every frame.
        if let w = want, let b = builtHighlight, w == b, highlightEntity != nil { return }
        if want == nil, builtHighlight == nil, highlightEntity == nil { return }
        builtHighlight = want
        highlightEntity?.removeFromParent(); highlightEntity = nil
        guard let h = h,
              let id = h["solid"] as? String,
              let face = (h["face"] as? NSNumber)?.intValue,
              face >= 0,
              let geom = solidCache[id] else { return }
        // M242 — the lift is a WORLD direction (toward the camera) but the
        // submesh is built in the solid's own space, so a rotated component
        // needs it brought back into that space first. Identity for a part.
        let spin = solidOrientation[id] ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        guard let e = geom.faceHighlightEntity(
            face: face, eps: highlightEps,
            lift: spin.inverse.act(cam.dir)) else { return }
        // M241 — the submesh is built in the solid's OWN space, so a solid
        // that carries a placement needs it applied here too. Zero for every
        // part, which is every caller today; written down so the first
        // assembly command that highlights a face does not have to find this.
        e.position = solidPlacement[id] ?? SIMD3<Float>(0, 0, 0)
        e.orientation = solidOrientation[id] ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        highlightEntity = e
        root.addChild(e)
    }
}

// ===========================================================================
// Camera parameter bag.
// ===========================================================================
@available(iOS 15.0, *)
struct CameraParams {
    var az: Double = .pi / 4
    var pol: Double = 0.955
    var halfH: Double = 27
    var ox: Double = 0
    var oy: Double = 0
    /// Rotation about the view direction (M80); see placeCamera().
    var roll: Double = 0

    // Near-ortho fallback lens (<iOS 18): a narrow FOV keeps parallax tiny.
    var nearOrthoFovDeg: Double = 3.0
    var nearOrthoFovRad: Double { nearOrthoFovDeg * .pi / 180 }

    mutating func update(from a: [String: Any]) {
        az = (a["az"] as? NSNumber)?.doubleValue ?? az
        pol = (a["pol"] as? NSNumber)?.doubleValue ?? pol
        halfH = (a["halfH"] as? NSNumber)?.doubleValue ?? halfH
        ox = (a["ox"] as? NSNumber)?.doubleValue ?? ox
        oy = (a["oy"] as? NSNumber)?.doubleValue ?? oy
        roll = (a["roll"] as? NSNumber)?.doubleValue ?? roll
    }

    var dir: SIMD3<Float> {
        SIMD3<Float>(
            Float(sin(pol) * sin(az)),
            Float(cos(pol)),
            Float(sin(pol) * cos(az)))
    }
}
