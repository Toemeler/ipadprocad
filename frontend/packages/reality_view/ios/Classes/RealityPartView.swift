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

        applyCameraComponent()
        root.addChild(cameraEntity)
        root.addChild(sketchRoot)
        arView.scene.anchors.append(root)
    }

    // MARK: - Camera

    private func applyCameraComponent() {
        // True orthographic on iOS 18+, near-orthographic perspective below
        // (long lens far away keeps CAD parallax negligible).
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
            oc.near = 0.01
            oc.far = 1_000_000
            cameraEntity.components.set(oc)
            cameraEntity.components.remove(PerspectiveCameraComponent.self)
        } else {
            var pc = PerspectiveCameraComponent()
            pc.near = 0.01
            pc.far = 1_000_000
            pc.fieldOfViewInDegrees = Float(cam.nearOrthoFovDeg)
            cameraEntity.components.set(pc)
        }
    }

    func setCamera(_ a: [String: Any]) {
        cam.update(from: a)
        placeCamera()
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
        // Perspective fallback needs D tuned to halfH so the FOV frames 2·halfH;
        // orthographic ignores D for size, so a large constant is fine there.
        let dist: Float = {
            if #available(iOS 18.0, *) { return 100_000 }
            return Float(cam.halfH) / tan(Float(cam.nearOrthoFovRad) * 0.5)
        }()
        let pos = center + dir * dist

        // Right-handed look-at: RealityKit cameras look down local -Z, +Y up.
        cameraEntity.transform = Transform(matrix: Self.lookAt(eye: pos, target: center, up: up))

        // Update ortho scale / fallback distance for the new zoom.
        applyCameraComponent()

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
        rebuildSolids(a["solids"] as? [[String: Any]] ?? [])
        rebuildPlanes(a["planes"] as? [[String: Any]] ?? [])
        rebuildAxes(a["axes"] as? [[String: Any]] ?? [])
        rebuildCenterPoint(a["cp"] as? [String: Any])
        rebuildSketches(a["sketches"] as? [[String: Any]] ?? [])
        rebuildPreview(a["preview"] as? [String: Any])
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
        for s in solids {
            guard let id = s["id"] as? String,
                  let geom = SolidGeom(payload: s) else { continue }
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
            let shaded = geom.shadedEntity(material: material)
            let edges = geom.edgeEntity()
            let holder = Entity()
            holder.addChild(shaded)
            if let edges = edges { holder.addChild(edges) }
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
        cpEntity?.removeFromParent(); cpEntity = nil
        guard let c = c, ((c["visible"] as? NSNumber)?.boolValue ?? false) else { return }
        let hot = (c["hot"] as? NSNumber)?.boolValue ?? false
        let e = ModelEntity(
            mesh: .generateSphere(radius: hot ? 0.6 : 0.5),
            materials: [Materials.unlit(hot ? Colors.green : Colors.orange)])
        cpEntity = e
        root.addChild(e)
    }

    private func rebuildSketches(_ sketches: [[String: Any]]) {
        sketchRoot.removeFromParent()
        sketchRoot = Entity()
        for sk in sketches {
            guard let polys = sk["polylines"] as? [Any] else { continue }
            for raw in polys {
                guard let pts = Payload.floats(raw) else { continue }
                if let e = TubeBuilder.polyline(
                    pts, radius: 0.12, material: Materials.unlit(Colors.sketch)) {
                    sketchRoot.addChild(e)
                }
            }
        }
        root.addChild(sketchRoot)
    }

    private func rebuildPreview(_ p: [String: Any]?) {
        previewEntity?.removeFromParent(); previewEntity = nil
        guard let p = p, let geom = SolidGeom(payload: p) else { return }
        let holder = Entity()
        holder.addChild(geom.shadedEntity(material: Materials.preview()))
        if let edges = geom.edgeEntity(color: Colors.previewEdge) { holder.addChild(edges) }
        previewEntity = holder
        root.addChild(holder)
    }

    // Blue prehighlight of the hovered planar face: a submesh of just that
    // face's triangles, nudged a hair toward the camera to beat z-fighting.
    private func rebuildHighlight(from h: [String: Any]?) {
        highlightEntity?.removeFromParent(); highlightEntity = nil
        guard let h = h,
              let id = h["solid"] as? String,
              let face = (h["face"] as? NSNumber)?.intValue,
              face >= 0,
              let geom = solidCache[id] else { return }
        guard let e = geom.faceHighlightEntity(face: face) else { return }
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
