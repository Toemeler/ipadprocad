// iPadProCAD — RealityKit geometry builders.
//
// Turns the app's payload maps into RealityKit entities. All geometry arrives
// in WORLD coordinates (the app has already placed every solid), so builders
// never transform — they only tessellate into MeshResources and pick a
// material. Edges/axes/sketch lines are drawn as thin swept tubes rather than a
// line primitive, because RealityKit's high-level MeshResource has no line
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
// Typed-data payload decoding. The Dart side sends Float64List / Int32List,
// which arrive as FlutterStandardTypedData; reinterpret their bytes.
// ---------------------------------------------------------------------------
enum Payload {
    static func doubles(_ any: Any?) -> [Double]? {
        guard let td = any as? FlutterStandardTypedData else { return nil }
        return td.data.withUnsafeBytes { raw -> [Double] in
            let buf = raw.bindMemory(to: Double.self)
            return Array(buf)
        }
    }

    static func floats(_ any: Any?) -> [SIMD3<Float>]? {
        guard let d = doubles(any), d.count % 3 == 0 else { return nil }
        var out = [SIMD3<Float>]()
        out.reserveCapacity(d.count / 3)
        var i = 0
        while i < d.count {
            out.append(SIMD3<Float>(Float(d[i]), Float(d[i + 1]), Float(d[i + 2])))
            i += 3
        }
        return out
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

    func edgeEntity(color: UIColor = Colors.edge, radius: Float = 0.10) -> Entity? {
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
        let ext = Float((p["ext"] as? NSNumber)?.doubleValue ?? 10)
        corners = [
            origin + u * -ext + v * -ext,
            origin + u * ext + v * -ext,
            origin + u * ext + v * ext,
            origin + u * -ext + v * ext,
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
// Origin axis: a thin tube from -ext to +ext along its direction.
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
final class AxisEntity {
    let entity = Entity()
    private let dir: SIMD3<Float>
    private let ext: Float
    private var hot = false
    private var visible = true

    init?(payload a: [String: Any]) {
        guard let d = Payload.vec3(a["dir"]) else { return nil }
        dir = d
        ext = Float((a["ext"] as? NSNumber)?.doubleValue ?? 10)
        hot = (a["hot"] as? NSNumber)?.boolValue ?? false
        visible = (a["visible"] as? NSNumber)?.boolValue ?? true
        build(hot: hot)
        entity.isEnabled = visible
    }

    private func build(hot: Bool) {
        for c in entity.children.map({ $0 }) { c.removeFromParent() }
        let color = hot ? Colors.green : Colors.orange
        if let t = TubeBuilder.polyline([dir * -ext, dir * ext], radius: 0.06,
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
// Tube builder: sweeps a k-gon cross-section along polyline segments. Each
// segment is an independent short prism (tiny joint gaps are invisible at
// these radii), which keeps the math trivial and robust.
// ---------------------------------------------------------------------------
@available(iOS 15.0, *)
enum TubeBuilder {
    private static let sides = 6

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
