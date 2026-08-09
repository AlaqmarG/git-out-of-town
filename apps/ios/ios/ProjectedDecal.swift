import ARKit
import CoreImage
import SceneKit
import UIKit

/// Projects painted artwork onto the LiDAR reconstruction from the exact camera
/// pose it was painted through. Because every visible triangle keeps the screen
/// position it had in the photo, the art lands wherever the user put it *and*
/// follows the real geometry — around corners, over pipes, down onto the floor.
enum ProjectedDecal {
    struct Triangle {
        let a: SIMD3<Float>
        let b: SIMD3<Float>
        let c: SIMD3<Float>
        var centroid: SIMD3<Float> { (a + b + c) / 3 }
    }

    struct Result {
        let geometry: SCNGeometry
        /// Mesh triangles the art was draped over — 0 means it never wrapped.
        let triangleCount: Int
        /// Surface-aligned frame at the painted centroid, for persistence.
        let placement: simd_float4x4
        let position: SIMD3<Float>
        let surfaceNormal: SIMD3<Float>
        /// Width of the painted area in metres.
        let extent: Float
    }

    /// Snapshots mesh triangles as plain values — the anchors' Metal buffers are
    /// recycled by ARKit, so they can't be read later.
    static func triangles(anchors: [ARAnchor], around point: SIMD3<Float>, maxDistance: Float = 5) -> [Triangle] {
        var out: [Triangle] = []
        for case let anchor as ARMeshAnchor in anchors {
            guard simd_distance(simd_make_float3(anchor.transform.columns.3), point) < maxDistance else { continue }
            let geometry = anchor.geometry
            let transform = anchor.transform
            // ARKit refreshes these Metal buffers concurrently; a torn read can
            // pair a new index buffer with a stale vertex buffer, so indices
            // must be range-checked before they become pointer offsets.
            let vertexCount = UInt32(clamping: geometry.vertices.count)
            for face in 0..<geometry.faces.count {
                let (i0, i1, i2) = geometry.vertexIndices(of: face)
                guard i0 < vertexCount, i1 < vertexCount, i2 < vertexCount else { continue }
                out.append(Triangle(
                    a: simd_make_float3(transform * SIMD4<Float>(geometry.vertex(at: i0), 1)),
                    b: simd_make_float3(transform * SIMD4<Float>(geometry.vertex(at: i1), 1)),
                    c: simd_make_float3(transform * SIMD4<Float>(geometry.vertex(at: i2), 1))
                ))
            }
        }
        return out
    }

    /// Builds world-space geometry whose texture coordinates are the painted
    /// overlay's own pixels. `mask` culls triangles the user left blank.
    static func build(
        triangles: [Triangle],
        camera: ARCamera,
        viewport: CGSize,
        orientation: UIInterfaceOrientation,
        mask: PaintMask
    ) -> Result? {
        let camPos = simd_make_float3(camera.transform.columns.3)
        let forward = -simd_make_float3(camera.transform.columns.2)

        struct Candidate {
            let tri: Triangle
            let uv: (CGPoint, CGPoint, CGPoint)
            let depth: Float
            let cell: Int
        }

        let cells = 96
        var candidates: [Candidate] = []
        candidates.reserveCapacity(4096)
        var nearest = [Float](repeating: .greatestFiniteMagnitude, count: cells * cells)

        for tri in triangles {
            let centroid = tri.centroid
            let toCamera = camPos - centroid
            let depth = simd_dot(centroid - camPos, forward)
            guard depth > 0.15 else { continue }

            let normal = simd_cross(tri.b - tri.a, tri.c - tri.a)
            guard simd_length(normal) > 1e-7, simd_dot(normal, toCamera) > 0 else { continue }

            let p0 = camera.projectPoint(tri.a, orientation: orientation, viewportSize: viewport)
            let p1 = camera.projectPoint(tri.b, orientation: orientation, viewportSize: viewport)
            let p2 = camera.projectPoint(tri.c, orientation: orientation, viewportSize: viewport)
            let cx = (p0.x + p1.x + p2.x) / 3
            let cy = (p0.y + p1.y + p2.y) / 3
            guard cx >= 0, cy >= 0, cx < viewport.width, cy < viewport.height else { continue }

            let u = cx / viewport.width, v = cy / viewport.height
            guard mask.isPainted(u: u, v: v) else { continue }

            let cell = min(cells - 1, Int(v * CGFloat(cells))) * cells + min(cells - 1, Int(u * CGFloat(cells)))
            nearest[cell] = min(nearest[cell], depth)
            candidates.append(Candidate(
                tri: tri,
                uv: (
                    CGPoint(x: p0.x / viewport.width, y: p0.y / viewport.height),
                    CGPoint(x: p1.x / viewport.width, y: p1.y / viewport.height),
                    CGPoint(x: p2.x / viewport.width, y: p2.y / viewport.height)
                ),
                depth: depth,
                cell: cell
            ))
        }

        // Keep only the front-most surface per screen cell, so paint lands on the
        // wall you can see and not on whatever stands behind it.
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [UInt32] = []
        var sum = SIMD3<Float>.zero
        var normalSum = SIMD3<Float>.zero
        var kept = 0

        positions.reserveCapacity(candidates.count * 3)
        texcoords.reserveCapacity(candidates.count * 3)
        indices.reserveCapacity(candidates.count * 3)

        // 10 cm, not 35: a looser window keeps two depth layers per screen cell,
        // and with depth writes off they blend in arbitrary order — ghosting.
        for candidate in candidates where candidate.depth < nearest[candidate.cell] + 0.10 {
            guard let faceNormal = unitVector(simd_cross(
                candidate.tri.b - candidate.tri.a,
                candidate.tri.c - candidate.tri.a
            )) else { continue }
            // The decal sits on the very triangles the occlusion mesh renders, so
            // without a lift it z-fights with them. 3 mm clears a 24-bit depth
            // buffer at wall distance; more visibly slides against the wall at
            // grazing angles — the paint's own "sticker" tell.
            let lift = faceNormal * 0.003
            let base = UInt32(positions.count)
            positions.append(SCNVector3(candidate.tri.a + lift))
            positions.append(SCNVector3(candidate.tri.b + lift))
            positions.append(SCNVector3(candidate.tri.c + lift))
            // Flat per face, deliberately not smoothed: the hard shading break
            // at a corner is what reads as "painted on that wall".
            let faceVector = SCNVector3(faceNormal)
            normals.append(contentsOf: [faceVector, faceVector, faceVector])
            texcoords.append(contentsOf: [candidate.uv.0, candidate.uv.1, candidate.uv.2])
            indices.append(contentsOf: [base, base + 1, base + 2])
            sum += candidate.tri.centroid
            normalSum += faceNormal
            kept += 1
            if kept > 20000 { break }
        }

        guard kept >= 1 else { return nil }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: texcoords),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )

        let position = sum / Float(kept)
        var normal = unitVector(normalSum) ?? SIMD3<Float>(0, 0, 1)
        if simd_dot(normal, camPos - position) < 0 { normal = -normal }

        var extent: Float = 0
        for p in positions {
            extent = max(extent, simd_distance(SIMD3<Float>(p.x, p.y, p.z), position))
        }

        return Result(
            geometry: geometry,
            triangleCount: kept,
            placement: surfaceFrame(
                position: position,
                normal: normal,
                upHint: simd_make_float3(camera.transform.columns.1)
            ),
            position: position,
            surfaceNormal: normal,
            extent: max(extent * 2, 0.05)
        )
    }

    /// Upright, surface-aligned frame — the one convention every placement uses,
    /// so a piece reconstructs identically wherever it is re-read.
    static func surfaceFrame(position: SIMD3<Float>, normal rawNormal: SIMD3<Float>, upHint: SIMD3<Float>) -> simd_float4x4 {
        let normal = unitVector(rawNormal) ?? SIMD3<Float>(0, 0, 1)
        // Looking straight down a surface leaves almost nothing of the hint to
        // project, and normalizing that scrap gives a direction that jitters —
        // so below 1 cm fall back to an arbitrary but stable perpendicular.
        let up = unitVector(upHint - normal * simd_dot(upHint, normal), min: 0.01)
            ?? unitVector(simd_cross(normal, SIMD3<Float>(1, 0, 0)))
            ?? unitVector(simd_cross(normal, SIMD3<Float>(0, 0, 1)))
            ?? SIMD3<Float>(0, 1, 0)
        let right = simd_cross(up, normal)
        // Fold in the SCNPlane 90° correction so viewers can apply this directly.
        return simd_float4x4(columns: (
            simd_float4(up.x, up.y, up.z, 0),
            simd_float4(-right.x, -right.y, -right.z, 0),
            simd_float4(normal.x, normal.y, normal.z, 0),
            simd_float4(position.x, position.y, position.z, 1)
        ))
    }
}

/// `simd_normalize` of a zero-length vector is NaN, and a single NaN anywhere in
/// a node's transform makes SceneKit drop the node without a word. Returns nil
/// rather than poisoning the scene graph.
func unitVector(_ v: SIMD3<Float>, min minLength: Float = 1e-6) -> SIMD3<Float>? {
    let length = simd_length(v)
    guard length.isFinite, length > minLength else { return nil }
    return v / length
}

/// Low-resolution alpha map of the painted overlay: which parts of the screen
/// the user actually painted.
struct PaintMask {
    private let alpha: [UInt8]
    private let side: Int
    let bounds: CGRect?

    init?(overlay: UIImage, side: Int = 96) {
        guard let cg = overlay.cgImage else { return nil }
        // RGBA rather than alpha-only: Swift's CGContext can't take the null
        // colour space that an alpha-only context requires.
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &rgba,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // CoreGraphics draws bottom-left origin; flip so row 0 is the top of the
        // screen, matching the projected UVs this mask is tested against.
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var buffer = [UInt8](repeating: 0, count: side * side)
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side {
                let a = rgba[(y * side + x) * 4 + 3]
                buffer[y * side + x] = a
                guard a > 12 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        self.alpha = buffer
        self.side = side
        bounds = maxX < 0 ? nil : CGRect(
            x: CGFloat(minX) / CGFloat(side),
            y: CGFloat(minY) / CGFloat(side),
            width: CGFloat(maxX - minX + 1) / CGFloat(side),
            height: CGFloat(maxY - minY + 1) / CGFloat(side)
        )
    }

    /// True when this point — or a neighbour — carries paint, so triangles
    /// straddling an edge still get covered.
    func isPainted(u: CGFloat, v: CGFloat) -> Bool {
        let x = min(side - 1, max(0, Int(u * CGFloat(side))))
        let y = min(side - 1, max(0, Int(v * CGFloat(side))))
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < side, ny >= 0, ny < side else { continue }
                if alpha[ny * side + nx] > 12 { return true }
            }
        }
        return false
    }
}
