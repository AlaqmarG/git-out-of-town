import ARKit
import SceneKit
import UIKit

/// Drapes graffiti onto the LiDAR reconstruction: collects mesh triangles under
/// the placement quad and projects the artwork onto them, so paint follows the
/// actual surface — around corners, over pipes, across uneven brick.
enum DecalMesh {
    /// Geometry in the local frame of `basis` (col0 = right, col1 = up,
    /// col2 = normal, col3 = position). Nil when the mesh has too few
    /// triangles there — caller falls back to a flat quad.
    static func geometry(basis: simd_float4x4, size: Float, anchors: [ARAnchor]) -> SCNGeometry? {
        let right = simd_make_float3(basis.columns.0)
        let up = simd_make_float3(basis.columns.1)
        let normal = simd_make_float3(basis.columns.2)
        let pos = simd_make_float3(basis.columns.3)
        let half = size / 2
        let margin = half * 1.15

        var positions: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [UInt32] = []

        for case let anchor as ARMeshAnchor in anchors {
            guard simd_distance(simd_make_float3(anchor.transform.columns.3), pos) < Float(size) + 3 else { continue }
            let geometry = anchor.geometry
            for face in 0..<geometry.faces.count {
                let (i0, i1, i2) = geometry.vertexIndices(of: face)
                let w0 = simd_make_float3(anchor.transform * SIMD4<Float>(geometry.vertex(at: i0), 1))
                let w1 = simd_make_float3(anchor.transform * SIMD4<Float>(geometry.vertex(at: i1), 1))
                let w2 = simd_make_float3(anchor.transform * SIMD4<Float>(geometry.vertex(at: i2), 1))
                let centroid = (w0 + w1 + w2) / 3

                let d = centroid - pos
                guard abs(simd_dot(d, right)) < margin,
                      abs(simd_dot(d, up)) < margin,
                      abs(simd_dot(d, normal)) < 0.25 else { continue }

                // Front-facing only: skip triangles on the far side of thin
                // geometry (the back of a column, the underside of a table).
                let faceNormal = simd_cross(w1 - w0, w2 - w0)
                guard simd_length(faceNormal) > 0,
                      simd_dot(simd_normalize(faceNormal), normal) > 0.2 else { continue }

                let base = UInt32(positions.count)
                for w in [w0, w1, w2] {
                    let v = w - pos
                    let local = SIMD3<Float>(simd_dot(v, right), simd_dot(v, up), simd_dot(v, normal) + 0.004)
                    positions.append(SCNVector3(local))
                    texcoords.append(CGPoint(
                        x: CGFloat(local.x / size + 0.5),
                        y: CGFloat(0.5 - local.y / size)
                    ))
                }
                indices.append(contentsOf: [base, base + 1, base + 2])
                if indices.count > 12000 { break }
            }
        }

        guard indices.count >= 6 else { return nil }

        let vertexSource = SCNGeometrySource(vertices: positions)
        let texSource = SCNGeometrySource(textureCoordinates: texcoords)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertexSource, texSource], elements: [element])
    }
}
