import ARKit
import SceneKit

/// Builds the paint surface from ARKit's dense depth map rather than the
/// reconstruction mesh.
///
/// The mesh is ~5 cm and chunky: across a can or a keyboard it produces
/// disconnected patches with holes between them. `sceneDepth` is a 256×192
/// per-pixel distance map — dense enough to follow a curved surface smoothly,
/// and its grid IS screen space, so texture coordinates are exact by
/// construction instead of being re-projected.
enum DepthDecal {
    /// A value copy of one frame's depth. ARKit recycles the pixel buffer, so
    /// nothing here may reference it after the frame.
    struct Depth {
        let values: [Float]
        let confidence: [UInt8]
        let width: Int
        let height: Int

        func sample(x: Int, y: Int) -> Float? {
            guard x >= 0, x < width, y >= 0, y < height else { return nil }
            let index = y * width + x
            let d = values[index]
            // Confidence 0 is ARKit's "low"; those samples are usually metres out.
            guard d > 0.05, d < 8, confidence[index] > 0 else { return nil }
            return d
        }
    }

    static func capture(from frame: ARFrame) -> Depth? {
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let map = sceneDepth.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)

        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map),
              CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.size

        var values = [Float](repeating: 0, count: width * height)
        let floats = base.assumingMemoryBound(to: Float.self)
        for y in 0..<height {
            for x in 0..<width {
                values[y * width + x] = floats[y * stride + x]
            }
        }

        var confidence = [UInt8](repeating: 2, count: width * height)
        if let confidenceMap = sceneDepth.confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
            if let cBase = CVPixelBufferGetBaseAddress(confidenceMap) {
                let cStride = CVPixelBufferGetBytesPerRow(confidenceMap)
                let bytes = cBase.assumingMemoryBound(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        confidence[y * width + x] = bytes[y * cStride + x]
                    }
                }
            }
        }
        return Depth(values: values, confidence: confidence, width: width, height: height)
    }

    /// Geometry in world space covering the painted region, with UVs equal to
    /// the screen position the user painted at.
    static func build(
        depth: Depth,
        camera: ARCamera,
        viewport: CGSize,
        orientation: UIInterfaceOrientation,
        mask: PaintMask
    ) -> ProjectedDecal.Result? {
        guard let bounds = mask.bounds else { return nil }

        // Sample on a screen-space grid over the painted area. 96 cells across
        // the art is far finer than the reconstruction mesh and still cheap.
        let cells = 96
        let toImage = camera.imageResolution
        let display = frame(for: camera, viewport: viewport, orientation: orientation).inverted()

        let intrinsics = camera.intrinsics
        let scaleX = Float(depth.width) / Float(toImage.width)
        let scaleY = Float(depth.height) / Float(toImage.height)
        let fx = intrinsics[0][0] * scaleX, fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX, cy = intrinsics[2][1] * scaleY
        let transform = camera.transform

        /// Screen point → world point, via the depth map.
        func world(atU u: CGFloat, v: CGFloat) -> SIMD3<Float>? {
            let image = CGPoint(x: u, y: v).applying(display)
            let dx = Int((image.x * CGFloat(depth.width)).rounded())
            let dy = Int((image.y * CGFloat(depth.height)).rounded())
            guard let d = depth.sample(x: dx, y: dy) else { return nil }
            // ARKit camera space: +x right, +y up, −z forward. Image y runs down.
            let camPoint = SIMD4<Float>(
                (Float(dx) - cx) * d / fx,
                -(Float(dy) - cy) * d / fy,
                -d,
                1
            )
            return simd_make_float3(transform * camPoint)
        }

        var points = [SIMD3<Float>?](repeating: nil, count: (cells + 1) * (cells + 1))
        for row in 0...cells {
            for col in 0...cells {
                let u = bounds.minX + bounds.width * CGFloat(col) / CGFloat(cells)
                let v = bounds.minY + bounds.height * CGFloat(row) / CGFloat(cells)
                points[row * (cells + 1) + col] = world(atU: u, v: v)
            }
        }

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [UInt32] = []
        var sum = SIMD3<Float>.zero
        var normalSum = SIMD3<Float>.zero
        var kept = 0
        var graze = GrazeMap()

        let camPos = simd_make_float3(transform.columns.3)

        func uv(row: Int, col: Int) -> CGPoint {
            CGPoint(
                x: bounds.minX + bounds.width * CGFloat(col) / CGFloat(cells),
                y: bounds.minY + bounds.height * CGFloat(row) / CGFloat(cells)
            )
        }

        for row in 0..<cells {
            for col in 0..<cells {
                let quad = [
                    points[row * (cells + 1) + col],
                    points[row * (cells + 1) + col + 1],
                    points[(row + 1) * (cells + 1) + col],
                    points[(row + 1) * (cells + 1) + col + 1],
                ]
                guard let a = quad[0], let b = quad[1], let c = quad[2], let d = quad[3] else { continue }

                // A silhouette edge — say the rim of a can against the wall
                // behind it — must not be bridged, or the paint stretches
                // across thin air. Depth spread flags it.
                let depths = [a, b, c, d].map { simd_distance($0, camPos) }
                guard let near = depths.min(), let far = depths.max(),
                      far - near < max(0.06, near * 0.06) else { continue }

                let centre = uv(row: row, col: col)
                guard mask.isPainted(u: centre.x, v: centre.y) else { continue }

                guard let n = unitVector(simd_cross(b - a, c - a)) else { continue }
                let facing = simd_dot(n, camPos - a) > 0 ? n : -n
                if let toCan = unitVector(camPos - a) {
                    graze.add(u: centre.x, v: centre.y, cosine: simd_dot(facing, toCan))
                }

                let base = UInt32(positions.count)
                // Held off the surface so the art wins the depth test against
                // the occlusion mesh. This path is the one that needs it most:
                // the geometry comes from dense depth, the occluder from the
                // 5 cm reconstruction mesh, and the two disagree by centimetres.
                let lift = decalLift(from: camPos, at: (a + b + c + d) / 4)
                for corner in [a, b, c, d] {
                    positions.append(SCNVector3(corner + lift))
                    normals.append(SCNVector3(facing))
                }
                texcoords.append(contentsOf: [
                    uv(row: row, col: col),
                    uv(row: row, col: col + 1),
                    uv(row: row + 1, col: col),
                    uv(row: row + 1, col: col + 1),
                ])
                indices.append(contentsOf: [
                    base, base + 2, base + 1,
                    base + 1, base + 2, base + 3,
                ])
                sum += (a + b + c + d) / 4
                normalSum += facing
                kept += 1
            }
        }

        guard kept >= 4 else { return nil }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: texcoords),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )

        let position = sum / Float(kept)
        let normal = unitVector(normalSum) ?? SIMD3<Float>(0, 0, 1)
        var extent: Float = 0
        for p in positions {
            extent = max(extent, simd_distance(SIMD3<Float>(p.x, p.y, p.z), position))
        }

        return ProjectedDecal.Result(
            geometry: geometry,
            triangleCount: kept * 2,
            placement: ProjectedDecal.surfaceFrame(
                position: position,
                normal: normal,
                upHint: simd_make_float3(transform.columns.1)
            ),
            position: position,
            surfaceNormal: normal,
            extent: max(extent * 2, 0.05),
            graze: graze.image()
        )
    }

    /// Normalized image space → normalized viewport space for this camera.
    private static func frame(
        for camera: ARCamera,
        viewport: CGSize,
        orientation: UIInterfaceOrientation
    ) -> CGAffineTransform {
        // `displayTransform` lives on ARFrame, but it is purely a function of the
        // camera's image resolution, the viewport and the orientation — all of
        // which are captured here, so it can be rebuilt from the camera alone.
        let image = camera.imageResolution
        let rotated = orientation.isPortrait
            ? CGSize(width: image.height, height: image.width)
            : image
        let scale = max(viewport.width / rotated.width, viewport.height / rotated.height)
        let fitted = CGSize(width: rotated.width * scale, height: rotated.height * scale)
        let offset = CGPoint(
            x: (viewport.width - fitted.width) / 2,
            y: (viewport.height - fitted.height) / 2
        )

        var t = CGAffineTransform.identity
        switch orientation {
        case .portrait:
            t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .landscapeLeft:
            t = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
        default:
            t = .identity
        }
        return t
            .concatenating(CGAffineTransform(scaleX: fitted.width, y: fitted.height))
            .concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
            .concatenating(CGAffineTransform(scaleX: 1 / viewport.width, y: 1 / viewport.height))
    }
}
