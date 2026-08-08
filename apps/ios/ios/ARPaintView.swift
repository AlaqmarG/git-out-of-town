import ARKit
import SceneKit
import SwiftUI

struct ARPaintView: UIViewRepresentable {
    var color: UIColor
    var clearToken: Int
    var showDebug: Bool
    var drawingImage: UIImage?
    var onPlace: (String) -> Void
    var onStatus: (String) -> Void
    var onHint: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            color: color,
            drawingImage: drawingImage,
            onPlace: onPlace,
            onStatus: onStatus,
            onHint: onHint
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        scnView.session.run(configuration)

        scnView.delegate = context.coordinator
        scnView.debugOptions = context.coordinator.debugOptions(showDebug)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        context.coordinator.scnView = scnView
        return scnView
    }

    func updateUIView(_ scnView: ARSCNView, context: Context) {
        context.coordinator.color = color
        context.coordinator.drawingImage = drawingImage
        context.coordinator.clear(clearToken)
        scnView.debugOptions = context.coordinator.debugOptions(showDebug)
    }
}

extension ARPaintView {
    final class Coordinator: NSObject, ARSCNViewDelegate {
        var scnView: ARSCNView?
        var color: UIColor
        var drawingImage: UIImage?
        var onPlace: (String) -> Void
        var onStatus: (String) -> Void
        var onHint: (String) -> Void
        private var lastClearToken = 0
        private var lastStatus = ""

        init(
            color: UIColor,
            drawingImage: UIImage?,
            onPlace: @escaping (String) -> Void,
            onStatus: @escaping (String) -> Void,
            onHint: @escaping (String) -> Void
        ) {
            self.color = color
            self.drawingImage = drawingImage
            self.onPlace = onPlace
            self.onStatus = onStatus
            self.onHint = onHint
        }

        func debugOptions(_ show: Bool) -> SCNDebugOptions {
            show ? [.showFeaturePoints] : []
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            Task { @MainActor [weak self] in
                self?.publishStatus()
            }
        }

        private func publishStatus() {
            let status = sessionStatus()
            guard status != lastStatus else { return }
            lastStatus = status
            Task { @MainActor [weak self] in
                self?.onStatus(status)
            }
        }

        private func sessionStatus() -> String {
            guard let frame = scnView?.session.currentFrame else {
                return "starting camera…"
            }
            switch frame.camera.trackingState {
            case .notAvailable:
                return "AR not available on this device"
            case .normal:
                let planeCount = frame.anchors.reduce(into: 0) { count, anchor in
                    if anchor is ARPlaneAnchor { count += 1 }
                }
                if planeCount == 0 {
                    return "tracking ✓ · scanning — slowly pan the camera around"
                }
                return "tracking ✓ · \(planeCount) surface\(planeCount == 1 ? "" : "s") detected — tap a green area"
            case .limited(let reason):
                return "tracking limited: \(limitedReason(reason))"
            }
        }

        private func limitedReason(_ reason: ARCamera.TrackingState.Reason) -> String {
            switch reason {
            case .initializing: return "initializing — move the phone around"
            case .excessiveMotion: return "slow down"
            case .insufficientFeatures: return "point at a more textured surface"
            case .relocalizing: return "relocalizing"
            @unknown default: return "waiting"
            }
        }

        func clear(_ token: Int) {
            guard token != lastClearToken else { return }
            lastClearToken = token
            guard let scnView else { return }
            for node in scnView.scene.rootNode.childNodes {
                node.removeFromParentNode()
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scnView else { return }
            let location = recognizer.location(in: scnView)

            var results = raycast(in: scnView, at: location, target: .existingPlaneGeometry)
            if results.isEmpty {
                results = raycast(in: scnView, at: location, target: .estimatedPlane)
            }
            guard let result = results.first else {
                onHint("No surface there — aim at a wall or floor and pan around to build tracking")
                return
            }

            let hit = result.worldTransform
            let position = simd_float3(hit.columns.3.x, hit.columns.3.y, hit.columns.3.z)

            var normal = simd_float3(hit.columns.1.x, hit.columns.1.y, hit.columns.1.z)
            if let plane = result.anchor as? ARPlaneAnchor {
                normal = simd_float3(plane.transform.columns.1.x, plane.transform.columns.1.y, plane.transform.columns.1.z)
            }
            normal = simd_normalize(normal)

            if let camera = scnView.session.currentFrame?.camera {
                let cameraPosition = simd_float3(camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
                let toCamera = simd_normalize(cameraPosition - position)
                if simd_dot(normal, toCamera) < 0 {
                    normal = -normal
                }
            }

            let camera = scnView.session.currentFrame?.camera
            let cameraUp = camera.map { c in
                simd_float3(c.transform.columns.1.x, c.transform.columns.1.y, c.transform.columns.1.z)
            } ?? SIMD3<Float>(0, 1, 0)
            let cameraForward = camera.map { c in
                -simd_float3(c.transform.columns.2.x, c.transform.columns.2.y, c.transform.columns.2.z)
            } ?? SIMD3<Float>(0, 0, -1)

            var upOnSurface = cameraUp - normal * simd_dot(cameraUp, normal)
            if simd_length(upOnSurface) < 0.01 {
                upOnSurface = cameraForward - normal * simd_dot(cameraForward, normal)
            }
            if simd_length(upOnSurface) < 0.01 {
                upOnSurface = simd_cross(normal, SIMD3<Float>(0, 1, 0))
            }
            upOnSurface = simd_normalize(upOnSurface)

            let right = simd_cross(upOnSurface, normal)
            let offset = normal * 0.003
            var placement = simd_float4x4(columns: (
                simd_float4(right.x, right.y, right.z, 0),
                simd_float4(upOnSurface.x, upOnSurface.y, upOnSurface.z, 0),
                simd_float4(normal.x, normal.y, normal.z, 0),
                simd_float4(position.x + offset.x, position.y + offset.y, position.z + offset.z, 1)
            ))

            // SCNPlane maps the image rotated 90° clockwise; cancel that in the plane's local frame.
            let upright = simd_float4x4(columns: (
                simd_float4(0, 1, 0, 0),
                simd_float4(-1, 0, 0, 0),
                simd_float4(0, 0, 1, 0),
                simd_float4(0, 0, 0, 1)
            ))
            placement = placement * upright

            let size: Float = 0.3
            let node = SCNNode()
            node.geometry = SCNPlane(width: CGFloat(size), height: CGFloat(size))
            let material = SCNMaterial()
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.diffuse.contents = drawingImage ?? color
            node.geometry?.materials = [material]
            node.simdTransform = placement
            scnView.scene.rootNode.addChildNode(node)

            let classification = (result.anchor as? ARPlaneAnchor)?.classification.label ?? "unknown"
            onPlace(classification)
        }

        private func raycast(in scnView: ARSCNView, at location: CGPoint, target: ARRaycastQuery.Target) -> [ARRaycastResult] {
            guard let query = scnView.raycastQuery(from: location, allowing: target, alignment: .any) else {
                return []
            }
            return scnView.session.raycast(query)
        }
    }
}

extension ARPlaneAnchor.Classification {
    var label: String {
        switch self {
        case .wall: return "wall"
        case .floor: return "floor"
        case .ceiling: return "ceiling"
        case .table: return "table"
        case .seat: return "seat"
        case .door: return "door"
        case .window: return "window"
        default: return "other"
        }
    }
}
