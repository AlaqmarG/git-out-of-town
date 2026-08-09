import ARKit
import SceneKit

/// LiDAR scene-reconstruction helpers: depth-only geometry so real objects
/// occlude graffiti behind them, and per-face classification for `surface_type`.
enum MeshOcclusion {
    /// Invisible geometry that writes depth only — anything behind it is hidden.
    ///
    /// Every buffer is copied. ARKit recycles an `ARMeshAnchor`'s Metal buffers
    /// on the next anchor update, so a zero-copy `SCNGeometrySource(buffer:)`
    /// leaves SceneKit rendering whatever ARKit wrote after we let go — garbage
    /// occluders at best, an out-of-bounds GPU read once a chunk shrinks.
    static func geometry(from mesh: ARMeshGeometry) -> SCNGeometry {
        let vertices = mesh.vertices
        let vertexCount = min(vertices.count, (vertices.buffer.length - vertices.offset) / vertices.stride)
        let source = SCNGeometrySource(
            data: Data(
                bytes: vertices.buffer.contents().advanced(by: vertices.offset),
                count: vertexCount * vertices.stride
            ),
            semantic: .vertex,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: vertices.stride
        )

        let faces = mesh.faces
        let indexBytes = 3 * faces.bytesPerIndex
        let faceCount = min(faces.count, faces.buffer.length / indexBytes)
        let element = SCNGeometryElement(
            data: Data(bytes: faces.buffer.contents(), count: faceCount * indexBytes),
            primitiveType: .triangles,
            primitiveCount: faceCount,
            bytesPerIndex: faces.bytesPerIndex
        )

        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.colorBufferWriteMask = []
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    /// Classification of the mesh face nearest to a world-space point,
    /// or nil when no face is within 30 cm.
    static func classification(at point: SIMD3<Float>, anchors: [ARAnchor]) -> ARMeshClassification? {
        var best: (distanceSq: Float, cls: ARMeshClassification)?
        for case let anchor as ARMeshAnchor in anchors {
            let origin = simd_make_float3(anchor.transform.columns.3)
            guard simd_distance(origin, point) < 5 else { continue }
            let local = simd_make_float3(anchor.transform.inverse * SIMD4<Float>(point, 1))
            let geometry = anchor.geometry
            guard let source = geometry.classification else { continue }
            for face in 0..<geometry.faces.count {
                let d = simd_distance_squared(geometry.centerOf(face: face), local)
                if d < (best?.distanceSq ?? .greatestFiniteMagnitude) {
                    best = (d, geometry.classificationOf(face: face, source: source))
                }
            }
        }
        guard let best, best.distanceSq < 0.09 else { return nil }
        return best.cls
    }
}

extension ARMeshGeometry {
    func centerOf(face: Int) -> SIMD3<Float> {
        let indices = vertexIndices(of: face)
        // NaN on a torn index: every distance comparison fails, so callers
        // skip the face instead of reading out of bounds.
        let count = UInt32(clamping: vertices.count)
        guard indices.0 < count, indices.1 < count, indices.2 < count else {
            return SIMD3<Float>(repeating: .nan)
        }
        return (vertex(at: indices.0) + vertex(at: indices.1) + vertex(at: indices.2)) / 3
    }

    func vertexIndices(of face: Int) -> (UInt32, UInt32, UInt32) {
        let bytesPerIndex = faces.bytesPerIndex
        let base = faces.buffer.contents().advanced(by: face * 3 * bytesPerIndex)
        func index(_ i: Int) -> UInt32 {
            if bytesPerIndex == 2 {
                return UInt32(base.advanced(by: i * 2).assumingMemoryBound(to: UInt16.self).pointee)
            }
            return base.advanced(by: i * 4).assumingMemoryBound(to: UInt32.self).pointee
        }
        return (index(0), index(1), index(2))
    }

    func vertex(at index: UInt32) -> SIMD3<Float> {
        let ptr = vertices.buffer.contents().advanced(by: vertices.offset + vertices.stride * Int(index))
        var v = SIMD3<Float>.zero
        memcpy(&v, ptr, 12)
        return v
    }

    func classificationOf(face: Int, source: ARGeometrySource) -> ARMeshClassification {
        let ptr = source.buffer.contents().advanced(by: source.offset + source.stride * face)
        return ARMeshClassification(rawValue: Int(ptr.assumingMemoryBound(to: UInt8.self).pointee)) ?? .none
    }
}

extension ARMeshClassification {
    /// Matches `SurfaceType` in packages/shared.
    var label: String? {
        switch self {
        case .wall: return "wall"
        case .floor: return "floor"
        case .ceiling: return "ceiling"
        case .table: return "table"
        case .seat: return "seat"
        case .door: return "door"
        case .window: return "window"
        default: return nil
        }
    }
}
