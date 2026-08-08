import ARKit
import CoreLocation
import SceneKit
import SwiftUI

/// Everything needed to persist a placement: geo position + the exact
/// orientation (relative to a north-up frame at the piece) for reconstruction.
struct PlacementSnapshot {
    let lat: Double
    let lng: Double
    let altitudeM: Double?
    let heading: Double?
    let accuracyM: Double?
    let distanceM: Double
    let devicePitch: Double
    let surfaceType: String?
    let usedGeoAnchor: Bool
    let hasLidar: Bool
    let placementTransform: [Double]
    /// JPEG of the camera frame at placement (with the piece composited). Shown on the web.
    let sceneData: Data?
}

/// A piece placed by someone else, to be rendered from its stored transform.
struct RemotePiece: Identifiable {
    let id: Int
    let imagePath: String
    let lat: Double
    let lng: Double
    let altitudeM: Double?
    let surfaceType: String?
    let placementTransform: [Double]?
}

struct ARPaintView: UIViewRepresentable {
    var color: UIColor
    var clearToken: Int
    var showDebug: Bool
    var drawingImage: UIImage?
    var remotePieces: [RemotePiece]
    var onPlace: (String) -> Void
    var onPiecePlaced: (PlacementSnapshot) -> Void
    var onStatus: (String) -> Void
    var onHint: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            color: color,
            drawingImage: drawingImage,
            onPlace: onPlace,
            onPiecePlaced: onPiecePlaced,
            onStatus: onStatus,
            onHint: onHint
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        // North-up world frame: x = east, y = up, z = south. Both placer and
        // viewer use this, so a stored transform reconstructs identically.
        configuration.worldAlignment = .gravityAndHeading
        scnView.session.run(configuration)

        scnView.delegate = context.coordinator
        scnView.debugOptions = context.coordinator.debugOptions(showDebug)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        context.coordinator.scnView = scnView
        context.coordinator.setupSession(in: scnView)
        return scnView
    }

    func updateUIView(_ scnView: ARSCNView, context: Context) {
        context.coordinator.color = color
        context.coordinator.drawingImage = drawingImage
        context.coordinator.clear(clearToken)
        context.coordinator.renderRemotePieces(remotePieces)
        scnView.debugOptions = context.coordinator.debugOptions(showDebug)
    }
}

extension ARPaintView {
    final class Coordinator: NSObject, ARSCNViewDelegate {
        var scnView: ARSCNView?
        var color: UIColor
        var drawingImage: UIImage?
        var onPlace: (String) -> Void
        var onPiecePlaced: (PlacementSnapshot) -> Void
        var onStatus: (String) -> Void
        var onHint: (String) -> Void
        private var lastClearToken = 0
        private var lastStatus = ""
        private var renderedRemoteIDs: Set<Int> = []
        private var remoteNodes: [Int: SCNNode] = [:]
        private var fallbackNodes: [Int: SCNNode] = [:]
        private var fallbackPieces: [Int: RemotePiece] = [:]
        private var lastReanchor = Date.distantPast
        private var usingGeoAnchor = false
        private var checkedGeoTracking = false
        private struct PendingGeoPiece {
            let image: UIImage
            let transform: simd_float4x4
            let id: Int
        }
        private var pendingGeoPieces: [String: PendingGeoPiece] = [:]

        init(
            color: UIColor,
            drawingImage: UIImage?,
            onPlace: @escaping (String) -> Void,
            onPiecePlaced: @escaping (PlacementSnapshot) -> Void,
            onStatus: @escaping (String) -> Void,
            onHint: @escaping (String) -> Void
        ) {
            self.color = color
            self.drawingImage = drawingImage
            self.onPlace = onPlace
            self.onPiecePlaced = onPiecePlaced
            self.onStatus = onStatus
            self.onHint = onHint
        }

        func debugOptions(_ show: Bool) -> SCNDebugOptions {
            show ? [.showFeaturePoints] : []
        }

        /// Starts on the GPS-bearing fallback, then upgrades to geo tracking when
        /// ARKit reports coverage at the current spot. Both clients running geo
        /// tracking reconstruct pieces at the exact same real-world spot.
        func setupSession(in scnView: ARSCNView) {
            let world = ARWorldTrackingConfiguration()
            world.planeDetection = [.horizontal, .vertical]
            world.worldAlignment = .gravityAndHeading
            scnView.session.run(world)
        }

        private func maybeEnableGeoTracking() {
            guard !checkedGeoTracking, !usingGeoAnchor, let scnView else { return }
            guard ARGeoTrackingConfiguration.isSupported else {
                checkedGeoTracking = true
                return
            }
            // Wait for a decent fix rather than giving up on the first (bad) one.
            guard let loc = LocationService.shared.location,
                  loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 30 else {
                return
            }
            checkedGeoTracking = true
            ARGeoTrackingConfiguration.checkAvailability(at: loc.coordinate) { [weak self] available, _ in
                Task { @MainActor in
                    guard let self, let scnView = self.scnView else { return }
                    guard available else {
                        self.onStatus("geo-tracking not available here — using GPS placement")
                        return
                    }
                    let geo = ARGeoTrackingConfiguration()
                    geo.planeDetection = [.horizontal, .vertical]
                    scnView.session.run(geo, options: [.resetTracking, .removeExistingAnchors])
                    self.usingGeoAnchor = true
                    // Drop any GPS-fallback nodes; they'll be re-added via geo anchors.
                    for (_, node) in self.remoteNodes {
                        node.removeFromParentNode()
                    }
                    self.remoteNodes.removeAll()
                    self.renderedRemoteIDs.removeAll()
                    self.fallbackNodes.removeAll()
                    self.fallbackPieces.removeAll()
                    self.pendingGeoPieces.removeAll()
                    self.onStatus("geo-tracking active — pieces pin to exact spots")
                }
            }
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            Task { @MainActor [weak self] in
                self?.publishStatus()
                self?.maybeEnableGeoTracking()
                self?.maybeReanchor()
            }
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            Task { @MainActor [weak self] in
                self?.attachPendingPiece(node: node, anchor: anchor)
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
                return "tracking ✓ · \(planeCount) surface\(planeCount == 1 ? "" : "s") detected — tap a surface"
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
            remoteNodes.removeAll()
            renderedRemoteIDs.removeAll()
            pendingGeoPieces.removeAll()
            fallbackNodes.removeAll()
            fallbackPieces.removeAll()
        }

        // MARK: - Placing a piece

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

            let sceneData = scnView.snapshot().jpegData(compressionQuality: 0.8)

            let classification = (result.anchor as? ARPlaneAnchor)?.classification.label ?? "unknown"
            onPlace(classification)

            emitPlacementSnapshot(
                placement: placement,
                position: position,
                surfaceType: classification,
                camera: camera,
                sceneData: sceneData
            )
        }

        private func emitPlacementSnapshot(
            placement: simd_float4x4,
            position: SIMD3<Float>,
            surfaceType: String,
            camera: ARCamera?,
            sceneData: Data?
        ) {
            guard let location = LocationService.shared.location else {
                onHint("No GPS fix — piece stays local (not saved)")
                return
            }
            let cameraPos = camera.map {
                simd_float3($0.transform.columns.3.x, $0.transform.columns.3.y, $0.transform.columns.3.z)
            } ?? position

            // Session frame is ENU (x=east, y=up, z=south) via gravityAndHeading.
            let enu = position - cameraPos
            let pieceLat = location.coordinate.latitude + Double(-enu.z) / 111320
            let pieceLng = location.coordinate.longitude + Double(enu.x) / (111320 * cos(location.coordinate.latitude * .pi / 180))
            let pieceAlt = location.altitude + Double(enu.y)

            let rotationOnly = simd_float4x4(columns: (
                placement.columns.0,
                placement.columns.1,
                placement.columns.2,
                simd_float4(0, 0, 0, 1)
            ))

            let pitch = camera.map { Double($0.eulerAngles.x) * 180 / .pi } ?? 0
            let distance = simd_length(position - cameraPos)
            let hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)

            onPiecePlaced(PlacementSnapshot(
                lat: pieceLat,
                lng: pieceLng,
                altitudeM: pieceAlt,
                heading: LocationService.shared.heading,
                accuracyM: location.horizontalAccuracy,
                distanceM: Double(distance),
                devicePitch: pitch,
                surfaceType: surfaceType == "unknown" ? nil : surfaceType,
                usedGeoAnchor: usingGeoAnchor,
                hasLidar: hasLidar,
                placementTransform: flatten(rotationOnly),
                sceneData: sceneData
            ))
        }

        // MARK: - Rendering other people's pieces

        func renderRemotePieces(_ pieces: [RemotePiece]) {
            guard let scnView else { return }
            let wanted = Set(pieces.map(\.id))
            for (id, node) in remoteNodes where !wanted.contains(id) {
                node.removeFromParentNode()
                remoteNodes.removeValue(forKey: id)
            }
            renderedRemoteIDs.formIntersection(wanted)
            for piece in pieces where !renderedRemoteIDs.contains(piece.id) {
                renderedRemoteIDs.insert(piece.id)
                addRemoteNode(for: piece, scnView: scnView)
            }
        }

        private func addRemoteNode(for piece: RemotePiece, scnView: ARSCNView) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let image: UIImage
                do {
                    image = try await APIClient.loadImage(path: piece.imagePath)
                } catch {
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }

                if self.usingGeoAnchor {
                    let coordinate = CLLocationCoordinate2D(latitude: piece.lat, longitude: piece.lng)
                    let anchor: ARGeoAnchor
                    if let altitude = piece.altitudeM {
                        anchor = ARGeoAnchor(coordinate: coordinate, altitude: altitude)
                    } else {
                        anchor = ARGeoAnchor(coordinate: coordinate)
                    }
                    self.pendingGeoPieces[anchor.identifier.uuidString] = PendingGeoPiece(
                        image: image,
                        transform: piece.placementTransform.flatMap(unflatten) ?? matrix_identity_float4x4,
                        id: piece.id
                    )
                    scnView.session.add(anchor: anchor)
                    return
                }

                guard let frame = scnView.session.currentFrame,
                      let loc = LocationService.shared.location else {
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }
                guard self.isUsableFix(loc) else {
                    // Bad or stale fix — hold off and retry on a later tick.
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }

                let camPos = simd_float3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
                let position = self.worldPosition(for: piece, from: loc, cameraPos: camPos)

                let rotation = piece.placementTransform.flatMap(unflatten) ?? matrix_identity_float4x4
                let node = SCNNode()
                node.geometry = SCNPlane(width: 0.3, height: 0.3)
                let material = SCNMaterial()
                material.isDoubleSided = true
                material.lightingModel = .constant
                material.diffuse.contents = image
                node.geometry?.materials = [material]

                let world = simd_float4x4(columns: (
                    rotation.columns.0,
                    rotation.columns.1,
                    rotation.columns.2,
                    simd_float4(position.x, position.y, position.z, 1)
                ))
                node.simdTransform = world
                scnView.scene.rootNode.addChildNode(node)
                self.remoteNodes[piece.id] = node
                self.fallbackNodes[piece.id] = node
                self.fallbackPieces[piece.id] = piece
            }
        }

        // MARK: - Reconstruction helpers (GPS fallback)

        /// A fix we trust enough to hang world positions off: fresh and reasonably accurate.
        private func isUsableFix(_ loc: CLLocation) -> Bool {
            loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 25 &&
                Date().timeIntervalSince(loc.timestamp) < 5
        }

        /// Where a piece should sit in world space, given our current pose + fix.
        /// Vertical comes from the surface type, not GPS altitude (which is very
        /// noisy) — floor near the ground, ceiling overhead, everything else at eye height.
        private func worldPosition(for piece: RemotePiece, from loc: CLLocation, cameraPos: SIMD3<Float>) -> SIMD3<Float> {
            let eastDelta = (piece.lng - loc.coordinate.longitude) * 111320 * cos(loc.coordinate.latitude * .pi / 180)
            let northDelta = (piece.lat - loc.coordinate.latitude) * 111320
            let upDelta = heightForSurface(piece.surfaceType) - 1.4
            return cameraPos + simd_float3(Float(eastDelta), Float(upDelta), Float(-northDelta))
        }

        private func heightForSurface(_ type: String?) -> Double {
            switch type {
            case "floor": return 0.1
            case "ceiling": return 2.6
            default: return 1.4
            }
        }

        /// As the GPS fix settles, slide fallback pieces to their corrected spots.
        private func maybeReanchor() {
            guard Date().timeIntervalSince(lastReanchor) > 2 else { return }
            lastReanchor = Date()
            guard let scnView, !fallbackNodes.isEmpty else { return }
            guard let frame = scnView.session.currentFrame,
                  let loc = LocationService.shared.location, isUsableFix(loc) else { return }
            let camPos = simd_float3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
            for (id, node) in fallbackNodes {
                guard let piece = fallbackPieces[id] else { continue }
                let desired = worldPosition(for: piece, from: loc, cameraPos: camPos)
                if simd_distance(node.simdPosition, desired) > 0.5 {
                    var t = node.simdTransform
                    t.columns.3 = simd_float4(desired.x, desired.y, desired.z, 1)
                    node.simdTransform = t
                }
            }
        }

        /// Attaches the piece quad to a resolved `ARGeoAnchor` node, relative to the
        /// anchor. ARKit keeps refining the anchor transform; the child follows it.
        private func attachPendingPiece(node: SCNNode, anchor: ARAnchor) {
            guard let pending = pendingGeoPieces.removeValue(forKey: anchor.identifier.uuidString) else { return }
            let plane = SCNPlane(width: 0.3, height: 0.3)
            let material = SCNMaterial()
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.diffuse.contents = pending.image
            plane.materials = [material]
            let child = SCNNode(geometry: plane)
            child.simdTransform = pending.transform
            node.addChildNode(child)
            remoteNodes[pending.id] = node
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
        default: return "unknown"
        }
    }
}

// MARK: - Transform helpers (column-major 4x4 <-> 16 floats)

func flatten(_ m: simd_float4x4) -> [Double] {
    var out: [Double] = []
    out.reserveCapacity(16)
    for c in 0..<4 {
        for r in 0..<4 {
            out.append(Double(m[c][r]))
        }
    }
    return out
}

func unflatten(_ a: [Double]) -> simd_float4x4 {
    simd_float4x4(columns: (
        simd_float4(Float(a[0]), Float(a[1]), Float(a[2]), Float(a[3])),
        simd_float4(Float(a[4]), Float(a[5]), Float(a[6]), Float(a[7])),
        simd_float4(Float(a[8]), Float(a[9]), Float(a[10]), Float(a[11])),
        simd_float4(Float(a[12]), Float(a[13]), Float(a[14]), Float(a[15]))
    ))
}
