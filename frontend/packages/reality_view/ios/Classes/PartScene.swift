// Prototype — RealityKit geometry builders.
//
// Turns the app's payload maps into RealityKit entities. Geometry arrives in
// the coordinates of the DOCUMENT IT WAS BUILT IN, so builders never transform
// — they only tessellate into MeshResources and pick a material.
//
// For a PART that is the world: the app has already placed every solid, and
// every solid's payload carries no placement.
//
// M241 — for an ASSEMBLY it is the SOURCE PART's own space, and the payload
// carries `at`, the component's placement. The renderer puts that on the
// solid's holder Entity (see PartRenderer.rebuildSolids), which is the whole
// mechanism: two occurrences of one part are two holders over ONE uploaded
// mesh, and dragging one is a transform write rather than a mesh upload.
//
// Edges/axes/sketch lines are drawn as thin swept tubes rather than a line
// primitive, because RealityKit's high-level MeshResource has no line
// primitive and the tube approach is depth-buffer correct (no z-fighting, no
// frayed outlines — the exact failure mode of the CPU painter).
import Flutter
import Foundation
import UIKit
import simd

#if canImport(RealityKit)
import RealityKit
#endif

// ---------------------------------------------------------------------------
// Typed-data payload decoding. The Dart side sends Float32List / Int32List,
// which arrive as FlutterStandardTypedData; reinterpret their bytes.
//
// M74: the vertex buffers moved from Float64 to Float32. They used to arrive
// as doubles and get converted here one vertex at a time — pointless, since
// the GPU only takes Float32 — so this now reinterprets the bytes straight
// into SIMD3<Float> with no conversion pass and half the bytes on the wire
// (~3.4 MB -> ~1.7 MB for a 54k-vertex gear).
// ---------------------------------------------------------------------------
enum Payload {
    static func doubles(_ any: Any?) -> [Double]? {
        guard let td = any as? FlutterStandardTypedData else { return nil }
        return td.data.withUnsafeBytes { raw -> [Double] in
            let buf = raw.bindMemory(to: Double.self)
            return Array(buf)
        }
    }

    /// Flat Float32 triples -> SIMD3<Float>, no per-element conversion.
    static func floats(_ any: Any?) -> [SIMD3<Float>]? {
        guard let td = any as? FlutterStandardTypedData else { return nil }
        return td.data.withUnsafeBytes { raw -> [SIMD3<Float>]? in
            let buf = raw.bindMemory(to: Float.self)
            guard buf.count % 3 == 0 else { return nil }
            var out = [SIMD3<Float>]()
            out.reserveCapacity(buf.count / 3)
            var i = 0
            while i < buf.count {
                out.append(SIMD3<Float>(buf[i], buf[i + 1], buf[i + 2]))
                i += 3
            }
            return out
        }
    }

    static func ints(_ any: Any?) -> [Int32]? {
        guard let td = any as? FlutterStandardTypedData else { return nil }
        return td.data.withUnsafeBytes { raw -> [Int32] in
            Array(raw.bindMemory(to: Int32.self))
        }
    }

    static func uints(_ any: Any?) -> [UInt32]? {
        guard let i = ints(any) else { return nil }
        return i.map { UInt32(bitPattern: $0) }
    }

    /// A packed ARGB integer from Dart's `Color.value`, as a plain Int.
    ///
    /// ZERO means "no colour given". That is a sentinel and not a colour: a
    /// fully transparent black is never a tint anyone asks for, and it keeps
    /// the value out of `[String: Int?]`, where Swift's `dict[k] = nil`
    /// REMOVES the entry instead of storing a nil — a trap worth designing
    /// around rather than remembering.
    static func argb(_ any: Any?) -> Int {
        return (any as? NSNumber)?.intValue ?? 0
    }

    /// [argb] as a colour, or nil when it is the zero sentinel.
    static func color(_ argb: Int) -> UIColor? {
        guard argb != 0 else { return nil }
        return UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255.0,
            green: CGFloat((argb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(argb & 0xFF) / 255.0,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255.0)
    }

    static func vec3(_ any: Any?) -> SIMD3<Float>? {
        guard let d = any as? [Any], d.count >= 3,
              let x = (d[0] as? NSNumber)?.doubleValue,
              let y = (d[1] as? NSNumber)?.doubleValue,
              let z = (d[2] as? NSNumber)?.doubleValue else { return nil }
        return SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

// ---------------------------------------------------------------------------
// Colours (mirror frontend theme tokens) + materials.
// ---------------------------------------------------------------------------
enum Colors {
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: a)
    }
    // Neutral mid grey: reads clearly as a SURFACE against the near-black
    // edges and the coloured sketch/overlay lines drawn on top of it.
    static let steel = rgb(0x86, 0x89, 0x8D)
    static let edge = rgb(0x23, 0x27, 0x2C)
    static let orange = rgb(0xEA, 0x9E, 0x5C)
    static let orangeEdge = rgb(0xF0, 0xA8, 0x68)
    static let green = rgb(0x39, 0xD6, 0x5B)
    static let greenBright = rgb(0x8D, 0xFF, 0xA0)
    static let sketch = rgb(0xC4, 0xC9, 0xCE)
    static let highlight = rgb(0x4F, 0xA3, 0xFF)
    static let previewEdge = rgb(0xBF, 0xD4, 0xEC)
}

@available(iOS 15.0, *)
enum Materials {
    // SimpleMaterial (non-metallic) reads correctly under plain directional
    // lights — a metallic PBR surface would need image-based lighting, which a
    // .nonAR scene has none of, and could render black. Matches the CPU
    // painter's flat-Lambert steel look.
    static func steel() -> RealityKit.Material {
        // High roughness: a CAD surface should read matte, so shading tells
        // you the form without a specular sheen competing with the edges.
        return SimpleMaterial(color: Colors.steel, roughness: 0.9, isMetallic: false)
    }

    static func preview() -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Colors.steel)
        m.metallic = .init(floatLiteral: 0.0)
        m.roughness = .init(floatLiteral: 0.5)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        return m
    }

    static func unlit(_ color: UIColor) -> RealityKit.Material {
        return UnlitMaterial(color: color)
    }

    /// M241 — [steel] in another colour, for a solid the app wants tinted:
    /// the SELECTED assembly component, and the one under the pointer.
    ///
    /// The colour is pushed from Dart (payload key `tint`, ARGB) rather than
    /// named here. That is M237's lesson applied to one more constant: the
    /// app has two palettes and the selection tone differs between them, so a
    /// frozen UIColor in this file would be right in one scheme and wrong in
    /// the other — exactly how the viewport background came to be charcoal
    /// under a cream chrome.
    static func tinted(_ color: UIColor) -> RealityKit.Material {
        return SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)
    }

    /// Unlit colour whose ALPHA comes from the ribbon ramp, sampled across
    /// the strip via its cross-width UV. That is what feathers the outline
    /// edges. Falls back to a hard unlit colour if the texture is missing, so
    /// a ramp failure costs sharpness, never the line itself.
    static func unlitSoft(_ color: UIColor) -> RealityKit.Material {
        var m = UnlitMaterial(color: color)
        if #available(iOS 18.0, *) {
            // A ribbon has no thickness, so it renders from both sides where
            // the OS allows it (faceCulling is iOS 18+). This is belt and
            // braces: the reversed winding in RibbonBuilder is what actually
            // fixes the vanished outlines, and it works on every version.
            m.faceCulling = .none
        }
        if #available(iOS 15.0, *) {
            // TextureResource.generate needs iOS 15; below that the outline is
            // simply hard-edged rather than feathered.
            // NB: no opacityThreshold here — that switches on alpha MASKING,
            // which fights the smooth ramp we are blending with.
            if let tex = RampTexture.shared {
                m.blending =
                    .transparent(opacity: .init(scale: 1, texture: .init(tex)))
            }
        }
        return m
    }

    static func unlitTransparent(_ color: UIColor, _ opacity: Float) -> RealityKit.Material {
        var m = UnlitMaterial(color: color)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return m
    }
}

// ---------------------------------------------------------------------------
// Solid geometry: shaded triangles + B-Rep edges + hover-face submesh.
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
struct SolidGeom {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
    let edgePts: [SIMD3<Float>]
    let edgeStarts: [Int]
    let triFaces: [Int32]

    init?(payload s: [String: Any]) {
        guard let p = Payload.floats(s["positions"]),
              let n = Payload.floats(s["normals"]),
              let idx = Payload.uints(s["indices"]),
              !p.isEmpty, idx.count % 3 == 0 else { return nil }
        positions = p
        // Normals must match positions 1:1; if the buffers disagree, drop them
        // and let RealityKit compute (a shaded blob still beats a crash).
        normals = (n.count == p.count) ? n : []

        indices = idx
        edgePts = Payload.floats(s["edgePts"]) ?? []
        edgeStarts = (Payload.ints(s["edgeStarts"]) ?? []).map { Int($0) }
        triFaces = Payload.ints(s["triFaces"]) ?? []
    }

    /// Distance of the farthest vertex from the world origin — feeds the
    /// scene-fitted near/far range (see PartRenderer.placeCamera).
    var boundingRadius: Float {
        var r: Float = 0
        for p in positions { r = max(r, simd_length(p)) }
        return r
    }

    /// Every triangle in BOTH windings. RealityKit culls strictly by winding,
    /// and OCCT's orientation is not uniform across a shape — the inner wall of
    /// a HOLE comes back reversed, which culled it and let you see straight
    /// through the part. Guessing a winding invariant proved fragile (it also
    /// silently culled the whole solid when the guess was backwards), so the
    /// geometry is simply made two-sided: exactly one of the two copies
    /// survives the cull, whatever convention the renderer uses, and they are
    /// coplanar so nothing can z-fight. Only the index buffer doubles —
    /// vertices are shared.
    static func doubleSided(_ idx: [UInt32]) -> [UInt32] {
        var out = idx
        out.reserveCapacity(idx.count * 2)
        var t = 0
        while t + 2 < idx.count {
            out.append(idx[t]); out.append(idx[t + 2]); out.append(idx[t + 1])
            t += 3
        }
        return out
    }

    /// Two-sided WITH FLIPPED NORMALS on the back copy. Sharing one normal
    /// between both windings (as before) only works if every face's normals
    /// point outward — and the device diagnostic showed they do not:
    /// normal_outward measured 1.00 on a plain prism but 0.63 on a body built
    /// from several joined features. A face whose normals point inward is lit
    /// from behind by the camera headlight, renders almost black, and reads as
    /// a HOLE in the solid — which is exactly the "open box" seen when
    /// extruding a rectangle with a circular hole, while a circle-in-circle
    /// (all normals outward) came out fine.
    /// Giving the reversed copy negated normals makes whichever side faces the
    /// camera light correctly, so shading no longer depends on the kernel's
    /// per-face orientation at all.
    func shadedEntity(material: RealityKit.Material) -> Entity {
        let n = UInt32(positions.count)
        var pos = positions
        pos.append(contentsOf: positions)
        var nrm = normals
        if !normals.isEmpty { nrm.append(contentsOf: normals.map { -$0 }) }
        var idx = indices
        var t = 0
        while t + 2 < indices.count {
            idx.append(n + indices[t])
            idx.append(n + indices[t + 2])
            idx.append(n + indices[t + 1])
            t += 3
        }
        var d = MeshDescriptor(name: "solid")
        d.positions = MeshBuffers.Positions(pos)
        if nrm.count == pos.count { d.normals = MeshBuffers.Normals(nrm) }
        d.primitives = .triangles(idx)
        guard let mesh = try? MeshResource.generate(from: [d]) else { return Entity() }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// Source polylines of the B-Rep edges, one array per edge.
    func edgePolylines() -> [[SIMD3<Float>]] {
        guard edgeStarts.count >= 2 else {
            return edgePts.isEmpty ? [] : [edgePts]
        }
        var out = [[SIMD3<Float>]]()
        for e in 0..<(edgeStarts.count - 1) {
            let a = edgeStarts[e], b = edgeStarts[e + 1]
            guard a >= 0, b <= edgePts.count, b - a >= 2 else { continue }
            out.append(Array(edgePts[a..<b]))
        }
        return out
    }

    /// Outline entity. With [viewDir] set this is a camera-facing RIBBON —
    /// two triangles per segment and exactly constant on-screen width — which
    /// is only valid while it faces that direction, so the caller must rebuild
    /// it when the view turns. Without it, the orientation-independent TUBE is
    /// used instead: ~12x the triangles and a slight width wobble, but it
    /// survives any camera move, which makes it the safe fallback.
    func edgeEntity(color: UIColor = Colors.edge, radius: Float = 0.10,
                    viewDir: SIMD3<Float>? = nil) -> Entity? {
        if #available(iOS 15.0, *), let v = viewDir {
            let lines = edgePolylines()
            if !lines.isEmpty,
               let m = RibbonBuilder.mesh(lines, halfWidth: radius, viewDir: v) {
                return ModelEntity(mesh: m, materials: [Materials.unlitSoft(color)])
            }
        }
        guard edgeStarts.count >= 2 else {
            // No per-edge offsets: draw the whole edge point cloud as one tube
            // chain if any points exist.
            if edgePts.isEmpty { return nil }
            return TubeBuilder.polyline(edgePts, radius: radius,
                                        material: Materials.unlit(color))
        }
        var segs = [(SIMD3<Float>, SIMD3<Float>)]()
        for e in 0..<(edgeStarts.count - 1) {
            let a = edgeStarts[e], b = edgeStarts[e + 1]
            guard a >= 0, b <= edgePts.count, b - a >= 2 else { continue }
            for i in a..<(b - 1) {
                segs.append((edgePts[i], edgePts[i + 1]))
            }
        }
        return TubeBuilder.segments(segs, radius: radius, material: Materials.unlit(color))
    }

    /// Submesh of the triangles belonging to [face], nudged out along their
    /// (shared, planar) normal so the blue prehighlight sits above the surface.
    /// Takes an Int because that is what NSNumber.intValue yields on the wire;
    /// the per-triangle face buffer is Int32, so the conversion happens once
    /// here instead of at every call site.
    /// [lift] is the direction the sheet is nudged along. Pass the CAMERA
    /// direction: lifting along the surface normal only works if the supplied
    /// normals really are outward, and that assumption has now been wrong
    /// twice on device. Toward the camera is correct no matter what convention
    /// the kernel used for normals or winding.
    func faceHighlightEntity(face faceId: Int, eps: Float = 0.04,
                             lift: SIMD3<Float>) -> ModelEntity? {
        let face = Int32(faceId)
        guard triFaces.count * 3 == indices.count else { return nil }
        var pos = [SIMD3<Float>]()
        var nrm = [SIMD3<Float>]()
        var idx = [UInt32]()
        var next: UInt32 = 0
        var t = 0
        while t < triFaces.count {
            if triFaces[t] == face {
                let i0 = Int(indices[t * 3]), i1 = Int(indices[t * 3 + 1]), i2 = Int(indices[t * 3 + 2])
                guard i0 < positions.count, i1 < positions.count, i2 < positions.count else { t += 1; continue }
                // Geometric normal for the outward nudge.
                // Lift along the OUTWARD normal. Using the winding normal
                // pushed the highlight INTO the solid (see the winding note
                // above) — which is why it never appeared on device however
                // much depth precision it got.
                let gn = simd_normalize(simd_cross(positions[i1] - positions[i0],
                                                   positions[i2] - positions[i0]))
                for i in [i0, i1, i2] {
                    pos.append(positions[i] + lift * eps)
                    nrm.append(normals.isEmpty ? gn : normals[i])
                    idx.append(next); next += 1
                }
            }
            t += 1
        }
        guard !pos.isEmpty else { return nil }
        var d = MeshDescriptor(name: "facehl")
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nrm)
        // A single-sided sheet is invisible when its winding faces away — the
        // origin planes render precisely because they were built two-sided by
        // hand, the highlight was not. That is why it never showed up.
        d.primitives = .triangles(Self.doubleSided(idx))
        guard let mesh = try? MeshResource.generate(from: [d]) else { return nil }
        return ModelEntity(mesh: mesh,
                           materials: [Materials.unlitTransparent(Colors.highlight, 0.55)])
    }
}

// ---------------------------------------------------------------------------
// Origin work plane: a double-sided translucent quad + outline. The depth
// buffer now makes it pass THROUGH the model correctly — no screen-space
// occluder grid needed (the whole point of the RealityKit move).
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
final class PlaneEntity {
    let entity = Entity()
    private var fill: ModelEntity?
    private var outline: Entity?
    private let corners: [SIMD3<Float>]
    /// Plane normal — used to lift the plane toward the camera when a solid
    /// face happens to be EXACTLY coplanar with it (origin plane through a
    /// face). Without this the two surfaces z-fight; the user-visible rule is
    /// "the work plane wins", same as Inventor.
    private let normal: SIMD3<Float>
    // Cached state: setHot/setVisible arrive on EVERY pointer move, and
    // rebuilding the quad + outline meshes each time is pure churn.
    private var hot = false
    private var visible = true

    init?(payload p: [String: Any]) {
        guard let frame = Payload.doubles(p["frame"]), frame.count >= 9 else { return nil }
        let u = SIMD3<Float>(Float(frame[0]), Float(frame[1]), Float(frame[2]))
        let v = SIMD3<Float>(Float(frame[3]), Float(frame[4]), Float(frame[5]))
        normal = SIMD3<Float>(Float(frame[6]), Float(frame[7]), Float(frame[8]))
        let origin = Payload.vec3(p["origin"]) ?? SIMD3<Float>(0, 0, 0)
        // M83: the plane frames the part, so its (u,v) rectangle is ASYMMETRIC
        // — width/height are the part's, not a fixed square. `ext` remains the
        // fallback for a payload from before M83 (symmetric square).
        let ext = Float((p["ext"] as? NSNumber)?.doubleValue ?? 10)
        let uMin = Float((p["uMin"] as? NSNumber)?.doubleValue ?? Double(-ext))
        let uMax = Float((p["uMax"] as? NSNumber)?.doubleValue ?? Double(ext))
        let vMin = Float((p["vMin"] as? NSNumber)?.doubleValue ?? Double(-ext))
        let vMax = Float((p["vMax"] as? NSNumber)?.doubleValue ?? Double(ext))
        corners = [
            origin + u * uMin + v * vMin,
            origin + u * uMax + v * vMin,
            origin + u * uMax + v * vMax,
            origin + u * uMin + v * vMax,
        ]
        hot = (p["hot"] as? NSNumber)?.boolValue ?? false
        visible = (p["visible"] as? NSNumber)?.boolValue ?? true
        build(hot: hot)
        entity.isEnabled = visible
    }

    private func build(hot: Bool) {
        fill?.removeFromParent()
        outline?.removeFromParent()
        let fillColor = hot ? Colors.green : Colors.orange
        let edgeColor = hot ? Colors.greenBright : Colors.orangeEdge
        // Two triangles, both windings, so the plane shows from either side
        // without relying on per-material face-culling toggles.
        let pos = corners
        let idx: [UInt32] = [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]
        var d = MeshDescriptor(name: "plane")
        d.positions = MeshBuffers.Positions(pos)
        d.primitives = .triangles(idx)
        if let mesh = try? MeshResource.generate(from: [d]) {
            let e = ModelEntity(mesh: mesh,
                                materials: [Materials.unlitTransparent(fillColor, hot ? 0.42 : 0.28)])
            fill = e
            entity.addChild(e)
        }
        if let o = TubeBuilder.polyline(corners + [corners[0]], radius: 0.06,
                                        material: Materials.unlit(edgeColor)) {
            outline = o
            entity.addChild(o)
        }
    }

    func setHot(_ h: Bool) {
        guard h != hot else { return }
        hot = h
        build(hot: h)
    }

    func setVisible(_ v: Bool) {
        guard v != visible else { return }
        visible = v
        entity.isEnabled = v
    }

    /// Shift the plane a hair toward the camera along its own normal, so a
    /// coplanar solid face can never win the depth test against it. [eps]
    /// scales with the zoom, so the lift stays sub-pixel at every scale.
    func applyBias(camDir: SIMD3<Float>, eps: Float) {
        let side: Float = simd_dot(normal, camDir) >= 0 ? 1 : -1
        entity.position = normal * (eps * side)
    }
}

// ---------------------------------------------------------------------------
// Origin axis: a thin tube spanning [lo, hi] along its direction (M83 — the
// same padded box the planes use; pre-M83 payloads fall back to [-ext, +ext]).
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
final class AxisEntity {
    let entity = Entity()
    private let dir: SIMD3<Float>
    private let lo: Float
    private let hi: Float
    private var hot = false
    private var visible = true

    init?(payload a: [String: Any]) {
        guard let d = Payload.vec3(a["dir"]) else { return nil }
        dir = d
        let ext = Float((a["ext"] as? NSNumber)?.doubleValue ?? 10)
        lo = Float((a["lo"] as? NSNumber)?.doubleValue ?? Double(-ext))
        hi = Float((a["hi"] as? NSNumber)?.doubleValue ?? Double(ext))
        hot = (a["hot"] as? NSNumber)?.boolValue ?? false
        visible = (a["visible"] as? NSNumber)?.boolValue ?? true
        build(hot: hot)
        entity.isEnabled = visible
    }

    private func build(hot: Bool) {
        for c in entity.children.map({ $0 }) { c.removeFromParent() }
        let color = hot ? Colors.green : Colors.orange
        if let t = TubeBuilder.polyline([dir * lo, dir * hi], radius: 0.06,
                                        material: Materials.unlit(color)) {
            entity.addChild(t)
        }
    }

    func setHot(_ h: Bool) {
        guard h != hot else { return }
        hot = h
        build(hot: h)
    }

    func setVisible(_ v: Bool) {
        guard v != visible else { return }
        visible = v
        entity.isEnabled = v
    }
}


// ---------------------------------------------------------------------------
// Alpha ramp used to feather the ribbon edges. Built once: a 1-pixel-tall
// strip that is transparent at u=0 and u=1 and opaque across the middle, so
// the ribbon's cross-width UV turns into a soft edge on a STOCK material —
// no CustomMaterial, no Metal.
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
enum RampTexture {
    static let shared: TextureResource? = make()

    private static func make() -> TextureResource? {
        let w = 32
        var px = [UInt8](repeating: 0, count: w * 4)
        for i in 0..<w {
            let u = (Float(i) + 0.5) / Float(w)
            // opaque core between 0.25 and 0.75, smooth falloff outside
            let d = abs(u - 0.5) * 2          // 0 centre .. 1 edge
            let a = d <= 0.5 ? 1.0 : max(0, 1 - (d - 0.5) / 0.5)
            px[i * 4 + 0] = 255
            px[i * 4 + 1] = 255
            px[i * 4 + 2] = 255
            px[i * 4 + 3] = UInt8(max(0, min(255, a * 255)))
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: w, height: 1, bitsPerComponent: 8,
                               bitsPerPixel: 32, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(
                                   rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: true,
                               intent: .defaultIntent)
        else { return nil }
        return try? TextureResource.generate(
            from: cg, options: .init(semantic: .color))
    }
}

// ---------------------------------------------------------------------------
// Ribbon builder: a flat, camera-facing strip per polyline segment.
//
// Why this exists next to TubeBuilder. A swept k-gon is 2*k triangles per
// segment (24 at 16 sides) and its apparent width still wobbles with the view
// by 2*(1 - cos(pi/k)). A strip held perpendicular to the view direction is
// TWO triangles per segment and its width is exact, because the camera is
// ORTHOGRAPHIC: world width = pixels * worldPerPixel with no perspective term.
// So it is both ~12x cheaper and strictly better looking - but it only holds
// while the strip faces the camera, so it has to be rebuilt when the view
// direction turns (see RealityPartView.refreshRibbons).
//
// Antialiasing without a shader: the strip is THREE quads across (an opaque
// core plus a feather each side) and carries a U coordinate running 0..1
// ACROSS the width. Feeding that through an alpha-ramp texture on a stock
// UnlitMaterial gives a soft edge with no custom Metal. Vertex colours would
// have been the obvious route, but RealityKit's stock materials do not read
// them, so UV is the one that actually works here.
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
enum RibbonBuilder {
    /// Fraction of the half width spent on the soft edge on each side.
    private static let feather: Float = 0.45

    /// Builds one mesh for all [pts] polylines, flattened toward [viewDir].
    /// [halfWidth] is in world units and is expected to be derived from the
    /// zoom so the on-screen weight stays put.
    static func mesh(_ polylines: [[SIMD3<Float>]], halfWidth w: Float,
                     viewDir: SIMD3<Float>) -> MeshResource? {
        var positions = [SIMD3<Float>]()
        var uvs = [SIMD2<Float>]()
        var indices = [UInt32]()
        let v = simd_length(viewDir) < 1e-6
            ? SIMD3<Float>(0, 0, 1) : simd_normalize(viewDir)
        let core = w * (1 - feather)

        for pts in polylines where pts.count >= 2 {
            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                let axis = b - a
                let len = simd_length(axis)
                if len < 1e-7 { continue }
                let dir = axis / len
                // In-plane normal: perpendicular to BOTH the segment and the
                // view direction, i.e. exactly the on-screen sideways.
                var side = simd_cross(dir, v)
                let sl = simd_length(side)
                if sl < 1e-5 {
                    // Segment points (nearly) at the camera: it projects to a
                    // dot, so any perpendicular will do and none is visible.
                    var up = SIMD3<Float>(0, 1, 0)
                    if abs(simd_dot(dir, up)) > 0.9 { up = SIMD3<Float>(1, 0, 0) }
                    side = simd_normalize(simd_cross(dir, up))
                } else {
                    side /= sl
                }
                let base = UInt32(positions.count)
                // four rails across the strip: -w, -core, +core, +w
                let offs: [Float] = [-w, -core, core, w]
                let us: [Float] = [0, 0.5, 0.5, 1]
                for (o, u) in zip(offs, us) {
                    positions.append(a + side * o)
                    uvs.append(SIMD2<Float>(u, 0))
                    positions.append(b + side * o)
                    uvs.append(SIMD2<Float>(u, 1))
                }
                // Three quads across: (rail0,rail1), (rail1,rail2),
                // (rail2,rail3).
                //
                // WINDING MATTERS AND GOT THIS WRONG ONCE. The obvious order
                // (i0,i1,j1) has normal cross(dir, side), and with
                // side = cross(dir, v) that is cross(dir, cross(dir, v)) = -v.
                // Since v points TOWARD the camera, every triangle then faced
                // AWAY and the whole outline was culled — on device the
                // outlines vanished completely. Reversed here, and the
                // material also disables culling, because a zero-thickness
                // ribbon is genuinely two-sided and should never depend on
                // which way round it was generated.
                for r in 0..<3 {
                    let i0 = base + UInt32(r * 2)
                    let i1 = base + UInt32(r * 2 + 1)
                    let j0 = base + UInt32((r + 1) * 2)
                    let j1 = base + UInt32((r + 1) * 2 + 1)
                    indices.append(contentsOf: [i0, j1, i1, i0, j0, j1])
                }
            }
        }
        guard !positions.isEmpty else { return nil }
        var d = MeshDescriptor(name: "ribbon")
        d.positions = MeshBuffers.Positions(positions)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }
}

// ---------------------------------------------------------------------------
// Tube builder: sweeps a k-gon cross-section along polyline segments. Each
// segment is an independent short prism (tiny joint gaps are invisible at
// these radii), which keeps the math trivial and robust.
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
enum TubeBuilder {
    /// Cross-section resolution of the swept tube.
    ///
    /// This was 6, and a hexagon is the reason outline thickness visibly
    /// changed with the view: seen across the flats it is 2*r*cos(30) = 1.73r
    /// wide, across the corners 2r — a 15% swing purely from rotating the
    /// camera, plus a faceted look where segments meet at an angle. At 16
    /// sides the swing is 2*r*cos(11.25) = 1.96r, i.e. under 2%, which is
    /// below a pixel at any sane stroke weight. Edges are 1D and cheap next to
    /// the face tessellation, so this is an affordable place to spend.
    private static let sides = 16

    static func polyline(_ pts: [SIMD3<Float>], radius: Float,
                         material: RealityKit.Material) -> Entity? {
        guard pts.count >= 2 else { return nil }
        var segs = [(SIMD3<Float>, SIMD3<Float>)]()
        for i in 0..<(pts.count - 1) { segs.append((pts[i], pts[i + 1])) }
        return segments(segs, radius: radius, material: material)
    }

    static func segments(_ segs: [(SIMD3<Float>, SIMD3<Float>)], radius: Float,
                         material: RealityKit.Material) -> Entity? {
        var positions = [SIMD3<Float>]()
        var normals = [SIMD3<Float>]()
        var indices = [UInt32]()
        for (a, b) in segs {
            appendPrism(a, b, radius: radius,
                        positions: &positions, normals: &normals, indices: &indices)
        }
        guard !positions.isEmpty else { return nil }
        var d = MeshDescriptor(name: "tube")
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [d]) else { return nil }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func appendPrism(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius r: Float,
                                    positions: inout [SIMD3<Float>],
                                    normals: inout [SIMD3<Float>],
                                    indices: inout [UInt32]) {
        let axis = b - a
        let len = simd_length(axis)
        if len < 1e-7 { return }
        let dir = axis / len
        // Perpendicular basis.
        var up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(dir, up)) > 0.9 { up = SIMD3<Float>(1, 0, 0) }
        let uu = simd_normalize(simd_cross(dir, up))
        let vv = simd_normalize(simd_cross(dir, uu))
        let base = UInt32(positions.count)
        for i in 0..<sides {
            let t = Float(i) / Float(sides) * 2 * .pi
            let off = uu * (r * cos(t)) + vv * (r * sin(t))
            let nrm = simd_normalize(off)
            positions.append(a + off); normals.append(nrm)
            positions.append(b + off); normals.append(nrm)
        }
        for i in 0..<sides {
            let i0 = base + UInt32(i * 2)
            let i1 = base + UInt32(i * 2 + 1)
            let j = (i + 1) % sides
            let j0 = base + UInt32(j * 2)
            let j1 = base + UInt32(j * 2 + 1)
            indices.append(contentsOf: [i0, i1, j1, i0, j1, j0])
        }
    }
}

// ---------------------------------------------------------------------------
// S8 — RealityKit first-use warm-up.
//
// THE MEASUREMENT THIS EXISTS FOR
// -------------------------------
// PERFORMANCE_PROFILE.md §7.2.2: the most expensive scene push of a 293-second
// session took 419.67 ms, of which 419.47 ms — 99.95 % — was recorded under
// `rv.native.planes`. §7.2.3 measures the SAME phase, doing the SAME work, at
// 2.373 ms in steady state.
//
// Those two numbers together settle what the 419 ms is. `rebuildPlanes`
// destroys and rebuilds every PlaneEntity on every setScene — three quads,
// three outline tubes, three axes — and it does that 1 698 more times for
// 2.373 ms each. Work that costs 2.373 ms when repeated cannot cost 419 ms
// because of what it is; at most 2.4 ms of that first call is plane
// construction. The remaining ~417 ms is RealityKit's own first use of the
// process — shader library, Metal pipeline state, resource subsystem — which
// the origin planes only PAY because they are the first geometry the app ever
// builds. (They are: `rebuildSolids` runs first in setScene and its worst
// observation is 10.02 ms, so the first scene had no solids in it.)
//
// So making plane construction cheaper cannot recover more than ~2.4 ms, and
// §7.2.2's reading — "RealityKit entity and material construction for the
// origin planes is [the cost]" — is right about the trigger and wrong about
// the cause.
//
// WHAT THIS DOES ABOUT IT
// -----------------------
// Pays that first use somewhere the user is not waiting for a part: one
// runloop turn after the platform view is created, which is at least one
// Flutter frame before the first setScene can arrive (viewport3d.dart's
// onCreated schedules a post-frame setState, and the push happens in the
// build after that).
//
// RealityThumbRenderer builds a PartRenderer of its own per gallery thumbnail,
// so in a session that saves before it opens the 3D viewport the warm-up is
// paid there instead. That is harmless — a thumbnail is written on save, not
// while someone waits for a viewport — and by the second property below it
// cannot cost the save anything either.
//
// It builds one throwaway mesh and one of every material the scene uses, and
// adds NOTHING to the scene graph. That is deliberate: an entity that is added
// and removed can be caught by a frame, and this must not be able to change a
// pixel. The cost of it is therefore bounded by what resource construction
// touches; if RealityKit defers some of its first-use work to the first DRAW,
// that part stays on the first setScene and will still show up there.
//
// It also cannot make anything slower. If the warm-up somehow runs after the
// first setScene, the scene has already paid the first-use cost and the
// warm-up is then the cheap case — the same ~1 ms it costs on any later call.
//
// AND IT IS ITS OWN MEASUREMENT
// -----------------------------
// `rv.native.warmup` splits a number that has never been split. Until now
// "first-use initialisation" and "plane construction" were one span and could
// only be told apart by inference. On the next paired capture they are two,
// and the inference above is falsifiable: if `rv.native.warmup` comes back
// small and `rv.native.planes` is still ~419 ms on its first call, this
// reasoning is wrong and the cost really is in the planes.
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
enum RealityWarmup {
    private static var done = false

    /// Constructs — and immediately discards — one of each resource kind the
    /// scene builders use. Main thread only, like everything else that touches
    /// RealityKit here. Idempotent: a second platform view in the same process
    /// would find the work already done, and saying so is cheaper than
    /// measuring it again.
    static func run() {
        guard !done else { return }
        done = true
        RvPerf.time("rv.native.warmup") {
            // Materials first — the shader library is what the first material
            // of each kind is expected to pull in.
            let unlit = Materials.unlit(Colors.orangeEdge)
            let transparent = Materials.unlitTransparent(Colors.orange, 0.28)
            let soft = Materials.unlitSoft(Colors.highlight)   // also builds RampTexture
            let steel = Materials.steel()
            let preview = Materials.preview()

            // A quad with the same descriptor shape the plane fill uses.
            let quad: [SIMD3<Float>] = [
                SIMD3(-1, 0, -1), SIMD3(1, 0, -1), SIMD3(1, 0, 1), SIMD3(-1, 0, 1),
            ]
            var d = MeshDescriptor(name: "warmup")
            d.positions = MeshBuffers.Positions(quad)
            d.normals = MeshBuffers.Normals([SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: 4))
            d.primitives = .triangles([0, 1, 2, 0, 2, 3])
            if let mesh = try? MeshResource.generate(from: [d]) {
                // ModelEntity construction itself, one entity per material —
                // one entity carrying five materials against a single-submesh
                // mesh is a count mismatch RealityKit need not accept. None is
                // ever parented, so all of them are unreachable from the scene
                // and released at the end of this closure.
                for m in [unlit, transparent, soft, steel, preview] {
                    _ = ModelEntity(mesh: mesh, materials: [m])
                }
            }
            // The swept-tube path the plane outlines and every edge use.
            _ = TubeBuilder.polyline([SIMD3(0, 0, 0), SIMD3(1, 0, 0)],
                                     radius: 0.06, material: unlit)
        }
    }
}
