// iPadProCAD — the RealityKit platform view.
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
        container.backgroundColor = RealityPartView.viewportColor
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
        guard #available(iOS 15.0, *), let r = renderer as? PartRenderer else {
            result(nil)
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "setScene":    r.setScene(args);    result(nil)
        case "setOverlays": r.setOverlays(args); result(nil)
        case "setCamera":   r.setCamera(args);   result(nil)
        default:            result(FlutterMethodNotImplemented)
        }
    }

    // 0xFF212830 — the app's T.viewport.
    static let viewportColor = UIColor(
        red: 0x21 / 255.0, green: 0x28 / 255.0, blue: 0x30 / 255.0, alpha: 1)
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
    private var planeEntities: [String: PlaneEntity] = [:]
    private var axisEntities: [String: AxisEntity] = [:]
    private var cpEntity: Entity?
    private var sketchRoot = Entity()
    /// Sketch polyline entities with the normal of the plane they lie on, so
    /// a sketch drawn ON a solid face can be lifted clear of it.
    private var sketchEntities: [(Entity, SIMD3<Float>)] = []
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
    /// halfH the edge tubes were built for; rebuilt when the zoom drifts far
    /// enough that their on-screen weight would change noticeably.
    private var edgeBuildHalfH: Double = 0
    /// Last highlight actually built, so hovering the same face does not
    /// regenerate its submesh every frame.
    private var builtHighlight: (String, Int)?
    private var cpState: (Bool, Bool)?
    /// Radius of the rendered geometry around the origin — drives the fitted
    /// near/far range. Starts at the origin-plane extent (±10 mm diagonal).
    private var sceneRadius: Float = 15
    private var previewEntity: Entity?
    private var highlightEntity: ModelEntity?

    // Latest camera (kept so a scene change re-applies the current view).
    private var cam = CameraParams()

    var view: UIView { arView }

    init(frame: CGRect) {
        arView = ARView(frame: frame,
                        cameraMode: .nonAR,
                        automaticallyConfigureSession: false)
        super.init()
        commonInit()
    }

    private func commonInit() {
        arView.isUserInteractionEnabled = false
        arView.backgroundColor = RealityPartView.viewportColor
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
        headlight.light.intensity = 2000
        root.addChild(headlight)
        fillLight.light.intensity = 650
        fillLight.transform = Transform(matrix: Self.lookAt(
            eye: SIMD3<Float>(-3, 6, -4), target: .zero, up: SIMD3<Float>(0, 1, 0)))
        root.addChild(fillLight)

        applyCameraComponent(dist: 400, near: 1, far: 800)
        root.addChild(cameraEntity)
        root.addChild(sketchRoot)
        arView.scene.anchors.append(root)
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
        if edgeBuildHalfH > 0 {
            let ratio = cam.halfH / edgeBuildHalfH
            if ratio > 1.8 || ratio < 0.55 { rebuildEdgesForZoom() }
        }
        placeCamera()
    }

    /// Re-tube the cached solids at the current zoom. Edge tubes have a fixed
    /// WORLD radius, so without this they thin to nothing when zooming in and
    /// turn into bars when zooming out.
    private func rebuildEdgesForZoom() {
        let r = edgeRadius
        for (id, geom) in solidCache {
            guard let holder = solidEntities[id] else { continue }
            solidEdges[id]?.removeFromParent()
            solidEdges[id] = nil
            if let e = geom.edgeEntity(radius: r) {
                holder.addChild(e)
                solidEdges[id] = e
            }
        }
        edgeBuildHalfH = cam.halfH
    }

    private func placeCamera() {
        let dir = cam.dir
        let fwd = -dir
        var right = simd_cross(fwd, SIMD3<Float>(0, 1, 0))
        if simd_length(right) < 1e-6 {
            right = simd_cross(fwd, SIMD3<Float>(0, 0, 1))
        }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, fwd))

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
        for e in edgeEntities { e.position = dir * bias }
        for (e, n) in sketchEntities {
            let side: Float = simd_dot(n, dir) >= 0 ? 1 : -1
            e.position = n * (bias * side)
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
        edgeBuildHalfH = cam.halfH
        rebuildSolids(a["solids"] as? [[String: Any]] ?? [])
        rebuildPlanes(a["planes"] as? [[String: Any]] ?? [])
        rebuildAxes(a["axes"] as? [[String: Any]] ?? [])
        rebuildCenterPoint(a["cp"] as? [String: Any])
        rebuildSketches(a["sketches"] as? [[String: Any]] ?? [])
        rebuildPreview(a["preview"] as? [String: Any])
        cpState = nil
        builtHighlight = nil
        rebuildHighlight(from: a["highlight"] as? [String: Any])
        placeCamera()
    }

    // Light-touch: hover tints + visibility + face highlight, no mesh upload.
    func setOverlays(_ a: [String: Any]) {
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
        rebuildHighlight(from: a["highlight"] as? [String: Any])
    }

    private func rebuildSolids(_ solids: [[String: Any]]) {
        // Drop entities no longer present.
        let ids = Set(solids.compactMap { $0["id"] as? String })
        for (id, e) in solidEntities where !ids.contains(id) {
            e.removeFromParent(); solidEntities[id] = nil; solidCache[id] = nil
        }
        for (id, e) in solidEdges where !ids.contains(id) {
            e.removeFromParent(); solidEdges[id] = nil; solidRev[id] = nil
        }
        for s in solids {
            guard let id = s["id"] as? String else { continue }
            let rev = (s["rev"] as? NSNumber)?.intValue ?? 0
            // Dart omits the buffers when a solid's mesh is unchanged: keep the
            // entity and the cached geometry that are already on screen.
            if s["positions"] == nil {
                if let cached = solidCache[id] {
                    sceneRadius = max(sceneRadius, cached.boundingRadius)
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
            } else {
                material = Materials.steel()
            }
            sceneRadius = max(sceneRadius, geom.boundingRadius)
            let shaded = geom.shadedEntity(material: material)
            let edges = geom.edgeEntity(radius: edgeRadius)
            let holder = Entity()
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

    private func rebuildPlanes(_ planes: [[String: Any]]) {
        for (_, e) in planeEntities { e.entity.removeFromParent() }
        planeEntities.removeAll()
        for p in planes {
            guard let key = p["key"] as? String, let e = PlaneEntity(payload: p) else { continue }
            root.addChild(e.entity)
            planeEntities[key] = e
        }
    }

    private func rebuildAxes(_ axes: [[String: Any]]) {
        for (_, e) in axisEntities { e.entity.removeFromParent() }
        axisEntities.removeAll()
        for ax in axes {
            guard let key = ax["key"] as? String, let e = AxisEntity(payload: ax) else { continue }
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
        let hot = hotNow
        let e = ModelEntity(
            mesh: .generateSphere(radius: hot ? 0.6 : 0.5),
            materials: [Materials.unlit(hot ? Colors.green : Colors.orange)])
        cpEntity = e
        root.addChild(e)
    }

    private func rebuildSketches(_ sketches: [[String: Any]]) {
        sketchRoot.removeFromParent()
        sketchRoot = Entity()
        sketchEntities.removeAll()
        for sk in sketches {
            guard let polys = sk["polylines"] as? [Any] else { continue }
            // Normal of the sketch plane (origin plane or the picked face).
            let n = Payload.vec3(sk["n"]) ?? SIMD3<Float>(0, 0, 1)
            for raw in polys {
                guard let pts = Payload.floats(raw) else { continue }
                if let e = TubeBuilder.polyline(
                    pts, radius: edgeRadius * 1.2,
                    material: Materials.unlit(Colors.sketch)) {
                    sketchRoot.addChild(e)
                    sketchEntities.append((e, n))
                }
            }
        }
        root.addChild(sketchRoot)
    }

    /// Edge/sketch tube radius tied to the zoom, so lines keep a roughly
    /// constant on-screen weight instead of vanishing when zoomed in.
    private var edgeRadius: Float { max(Float(cam.halfH) * 1.2e-3, 1e-6) }

    /// Outward lift of the blue face prehighlight — must comfortably exceed
    /// the depth resolution at the current zoom, or the highlight is swallowed
    /// by the face it is supposed to mark.
    private var highlightEps: Float { max(Float(cam.halfH) * 2e-3, 1e-5) }

    private func rebuildPreview(_ p: [String: Any]?) {
        previewEntity?.removeFromParent(); previewEntity = nil
        previewEdge = nil
        guard let p = p, let geom = SolidGeom(payload: p) else { return }
        sceneRadius = max(sceneRadius, geom.boundingRadius)
        let holder = Entity()
        holder.addChild(geom.shadedEntity(material: Materials.preview()))
        if let edges = geom.edgeEntity(color: Colors.previewEdge, radius: edgeRadius) {
            holder.addChild(edges)
            previewEdge = edges
        }
        previewEntity = holder
        root.addChild(holder)
    }

    // Blue prehighlight of the hovered planar face: a submesh of just that
    // face's triangles, nudged a hair toward the camera to beat z-fighting.
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
        guard let e = geom.faceHighlightEntity(
            face: face, eps: highlightEps, lift: cam.dir) else { return }
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

    // Near-ortho fallback lens (<iOS 18): a narrow FOV keeps parallax tiny.
    var nearOrthoFovDeg: Double = 3.0
    var nearOrthoFovRad: Double { nearOrthoFovDeg * .pi / 180 }

    mutating func update(from a: [String: Any]) {
        az = (a["az"] as? NSNumber)?.doubleValue ?? az
        pol = (a["pol"] as? NSNumber)?.doubleValue ?? pol
        halfH = (a["halfH"] as? NSNumber)?.doubleValue ?? halfH
        ox = (a["ox"] as? NSNumber)?.doubleValue ?? ox
        oy = (a["oy"] as? NSNumber)?.doubleValue ?? oy
    }

    var dir: SIMD3<Float> {
        SIMD3<Float>(
            Float(sin(pol) * sin(az)),
            Float(cos(pol)),
            Float(sin(pol) * cos(az)))
    }
}
