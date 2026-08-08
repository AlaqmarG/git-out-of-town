import ARKit
import Combine
import RealityKit
import SwiftUI

struct ARPaintView: UIViewRepresentable {
    var color: UIColor
    var clearToken: Int
    var showDebug: Bool
    var onPlace: (String) -> Void
    var onStatus: (String) -> Void
    var onHint: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(color: color, onPlace: onPlace, onStatus: onStatus, onHint: onHint)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration)

        arView.debugOptions = context.coordinator.debugOptions(showDebug)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        context.coordinator.arView = arView
        context.coordinator.startMonitoring(arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.color = color
        context.coordinator.clear(clearToken)
        arView.debugOptions = context.coordinator.debugOptions(showDebug)
    }
}

extension ARPaintView {
    final class Coordinator: NSObject {
        var arView: ARView?
        var color: UIColor
        var onPlace: (String) -> Void
        var onStatus: (String) -> Void
        var onHint: (String) -> Void
        private var lastClearToken = 0
        private var lastStatus = ""
        private var updateSubscription: (any Cancellable)?

        init(
            color: UIColor,
            onPlace: @escaping (String) -> Void,
            onStatus: @escaping (String) -> Void,
            onHint: @escaping (String) -> Void
        ) {
            self.color = color
            self.onPlace = onPlace
            self.onStatus = onStatus
            self.onHint = onHint
        }

        func startMonitoring(_ arView: ARView) {
            publishStatus()
            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.publishStatus()
            }
        }

        func debugOptions(_ show: Bool) -> ARView.DebugOptions {
            show ? [.showFeaturePoints, .showAnchorGeometry] : []
        }

        private func publishStatus() {
            let status = sessionStatus()
            guard status != lastStatus else { return }
            lastStatus = status
            onStatus(status)
        }

        private func sessionStatus() -> String {
            guard let frame = arView?.session.currentFrame else {
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
            guard let arView else { return }
            for anchor in arView.scene.anchors {
                arView.scene.removeAnchor(anchor)
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = recognizer.location(in: arView)

            var results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .any)
            if results.isEmpty {
                results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
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

            if let camera = arView.session.currentFrame?.camera {
                let cameraPosition = simd_float3(camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
                let toCamera = simd_normalize(cameraPosition - position)
                if simd_dot(normal, toCamera) < 0 {
                    normal = -normal
                }
            }

            let camera = arView.session.currentFrame?.camera
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
            let placement = simd_float4x4(columns: (
                simd_float4(right.x, right.y, right.z, 0),
                simd_float4(upOnSurface.x, upOnSurface.y, upOnSurface.z, 0),
                simd_float4(normal.x, normal.y, normal.z, 0),
                simd_float4(position.x, position.y, position.z, 1)
            ))

            let anchor = AnchorEntity()
            anchor.transform = Transform(matrix: placement)

            let size: Float = 0.3
            let entity = ModelEntity(
                mesh: .generatePlane(width: size, height: size),
                materials: [UnlitMaterial(color: color)]
            )
            entity.position.z = 0.003
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            let classification = (result.anchor as? ARPlaneAnchor)?.classification.label ?? "unknown"
            onPlace(classification)
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
