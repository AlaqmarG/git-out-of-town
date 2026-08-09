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
    var isActive: Bool
    var locked: Bool
    var drawingImage: UIImage?
    var remotePieces: [RemotePiece]
    var previewSize: Float
    var placeToken: Int
    var cancelToken: Int
    var discardToken: Int
    var onPlace: (String) -> Void
    var onPiecePlaced: (PlacementSnapshot) -> Void
    var onStatus: (String) -> Void
    var onHint: (String) -> Void
    var onPreviewState: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            color: color,
            drawingImage: drawingImage,
            previewSize: previewSize,
            onPlace: onPlace,
            onPiecePlaced: onPiecePlaced,
            onStatus: onStatus,
            onHint: onHint,
            onPreviewState: onPreviewState
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView(frame: .zero)
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
        context.coordinator.locked = locked
        context.coordinator.setActive(isActive)
        context.coordinator.clear(clearToken)
        context.coordinator.renderRemotePieces(remotePieces)
        context.coordinator.previewSize = previewSize
        context.coordinator.setPreviewSize(previewSize)
        context.coordinator.handleCommands(placeToken: placeToken, cancelToken: cancelToken, discardToken: discardToken)
        scnView.debugOptions = context.coordinator.debugOptions(showDebug)
    }
}

extension ARPaintView {
    final class Coordinator: NSObject, ARSCNViewDelegate {
        var scnView: ARSCNView?
        var color: UIColor
        var drawingImage: UIImage?
        var locked = false
        var onPlace: (String) -> Void
        var onPiecePlaced: (PlacementSnapshot) -> Void
        var onStatus: (String) -> Void
        var onHint: (String) -> Void
        var onPreviewState: (Bool) -> Void
        private var lastClearToken = 0
        private var lastStatus = ""
        private var renderedRemoteIDs: Set<Int> = []
        private var remoteNodes: [Int: SCNNode] = [:]
        private var fallbackNodes: [Int: SCNNode] = [:]
        private var fallbackPieces: [Int: RemotePiece] = [:]
        private var lastReanchor = Date.distantPast
        private var usingGeoAnchor = false
        private var checkedGeoTracking = false
        private var sessionActive = true
        var previewSize: Float = 0.3
        private var lastPlaceToken = 0
        private var lastCancelToken = 0
        private var lastDiscardToken = 0
        private var isPreviewing = false
        private var previewNode: SCNNode?
        private var lastPlacedNode: SCNNode?
        private var placedNodes: [SCNNode] = []
        private var snappedIDs: Set<Int> = []
        private var lastCancelAt = Date.distantPast
        private var previewInfo: (placement: simd_float4x4, position: SIMD3<Float>, surfaceType: String)?
        private var lastAppliedPreviewSize: Float = 0

        let hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)

        private struct PendingGeoPiece {
            let image: UIImage
            let transform: simd_float4x4
            let id: Int
        }
        private var pendingGeoPieces: [String: PendingGeoPiece] = [:]

        init(
            color: UIColor,
            drawingImage: UIImage?,
            previewSize: Float,
            onPlace: @escaping (String) -> Void,
            onPiecePlaced: @escaping (PlacementSnapshot) -> Void,
            onStatus: @escaping (String) -> Void,
            onHint: @escaping (String) -> Void,
            onPreviewState: @escaping (Bool) -> Void
        ) {
            self.color = color
            self.drawingImage = drawingImage
            self.previewSize = previewSize
            self.onPlace = onPlace
            self.onPiecePlaced = onPiecePlaced
            self.onStatus = onStatus
            self.onHint = onHint
            self.onPreviewState = onPreviewState
        }

        func debugOptions(_ show: Bool) -> SCNDebugOptions {
            show ? [.showFeaturePoints] : []
        }

        // MARK: - Session

        /// Starts on the GPS-bearing fallback, then upgrades to geo tracking when
        /// ARKit reports coverage at the current spot. Both clients running geo
        /// tracking reconstruct pieces at the exact same real-world spot.
        func setupSession(in scnView: ARSCNView) {
            scnView.session.run(makeWorldConfiguration())
        }

        /// World tracking with every depth capability the device offers: LiDAR
        /// scene reconstruction for occlusion + surface classification, and
        /// person segmentation so people walk in front of pieces.
        private func makeWorldConfiguration() -> ARWorldTrackingConfiguration {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            // North-up world frame: x = east, y = up, z = south. Both placer and
            // viewer use this, so a stored transform reconstructs identically.
            config.worldAlignment = .gravityAndHeading
            if hasLidar {
                config.sceneReconstruction = .meshWithClassification
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                config.frameSemantics.insert(.personSegmentationWithDepth)
            }
            return config
        }

        /// Pause AR while another tab is showing; resume (keeping anchors) on return.
        func setActive(_ active: Bool) {
            guard active != sessionActive, let scnView else { return }
            sessionActive = active
            if active {
                if usingGeoAnchor {
                    scnView.session.run(makeGeoConfiguration())
                } else {
                    scnView.session.run(makeWorldConfiguration())
                }
            } else {
                scnView.session.pause()
            }
        }

        private func makeGeoConfiguration() -> ARGeoTrackingConfiguration {
            let geo = ARGeoTrackingConfiguration()
            geo.planeDetection = [.horizontal, .vertical]
            if ARGeoTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                geo.frameSemantics.insert(.personSegmentationWithDepth)
            }
            return geo
        }

        private func maybeEnableGeoTracking() {
            guard !checkedGeoTracking, !usingGeoAnchor, sessionActive, let scnView else { return }
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
                    scnView.session.run(self.makeGeoConfiguration(), options: [.resetTracking, .removeExistingAnchors])
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

        // MARK: - Occlusion mesh

        nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            if let mesh = anchor as? ARMeshAnchor {
                node.geometry = MeshOcclusion.geometry(from: mesh.geometry)
                node.renderingOrder = -1
                node.name = "occlusion"
                return
            }
            Task { @MainActor [weak self] in
                self?.attachPendingPiece(node: node, anchor: anchor)
            }
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let mesh = anchor as? ARMeshAnchor else { return }
            node.geometry = MeshOcclusion.geometry(from: mesh.geometry)
        }

        // MARK: - Status

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
                let depth = hasLidar ? "LiDAR ✓ · " : ""
                if planeCount == 0 {
                    return "\(depth)tracking ✓ · scanning — slowly pan the camera around"
                }
                return "\(depth)tracking ✓ · \(planeCount) surface\(planeCount == 1 ? "" : "s") detected"
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

        /// Removes only our piece nodes. ARKit-managed nodes — the LiDAR
        /// occlusion meshes above all — must survive, or occlusion silently
        /// dies for the rest of the session.
        func clear(_ token: Int) {
            guard token != lastClearToken else { return }
            lastClearToken = token
            previewNode?.removeFromParentNode()
            previewNode = nil
            previewInfo = nil
            lastPlacedNode = nil
            isPreviewing = false
            onPreviewState(false)
            for node in placedNodes {
                node.removeFromParentNode()
            }
            placedNodes.removeAll()
            for (_, node) in remoteNodes {
                node.removeFromParentNode()
            }
            remoteNodes.removeAll()
            renderedRemoteIDs.removeAll()
            pendingGeoPieces.removeAll()
            fallbackNodes.removeAll()
            fallbackPieces.removeAll()
            snappedIDs.removeAll()
        }

        // MARK: - Placing a piece

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scnView, !isPreviewing, !locked,
                  Date().timeIntervalSince(lastCancelAt) > 0.25 else { return }
            let location = recognizer.location(in: scnView)

            var results = raycast(in: scnView, at: location, target: .existingPlaneGeometry)
            if results.isEmpty {
                results = raycast(in: scnView, at: location, target: .estimatedPlane)
            }
            guard let result = results.first else {
                onHint("No surface there — aim at a wall or floor and pan around to build tracking")
                return
            }
            guard let preview = makePlacement(from: result) else { return }
            enterPreview(preview, scnView: scnView)
        }

        /// Computes the surface-aligned placement for a raycast hit.
        private func makePlacement(from result: ARRaycastResult) -> (placement: simd_float4x4, position: SIMD3<Float>, surfaceType: String)? {
            guard let scnView else { return nil }
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

            var classification = (result.anchor as? ARPlaneAnchor)?.classification.label ?? "unknown"
            if classification == "unknown", hasLidar,
               let anchors = scnView.session.currentFrame?.anchors,
               let meshLabel = MeshOcclusion.classification(at: position, anchors: anchors)?.label {
                classification = meshLabel
            }
            return (placement, position, classification)
        }

        // MARK: - Preview / confirm flow

        private func enterPreview(_ preview: (placement: simd_float4x4, position: SIMD3<Float>, surfaceType: String), scnView: ARSCNView) {
            let node = makePieceNode(size: previewSize, transparent: true)
            node.simdTransform = preview.placement
            scnView.scene.rootNode.addChildNode(node)
            previewNode = node
            previewInfo = preview
            isPreviewing = true
            lastAppliedPreviewSize = previewSize
            onPreviewState(true)
        }

        func setPreviewSize(_ size: Float) {
            guard isPreviewing, let previewNode, abs(size - lastAppliedPreviewSize) > 0.001 else { return }
            lastAppliedPreviewSize = size
            let clamped = max(0.1, min(size, 2.0))
            previewNode.geometry = SCNPlane(width: CGFloat(clamped), height: CGFloat(clamped))
            previewNode.geometry?.materials = [makePieceMaterial(transparent: true)]
        }

        private func confirmPlacement() {
            guard let scnView, let preview = previewInfo else { return }
            previewNode?.removeFromParentNode()
            previewNode = nil
            previewInfo = nil
            isPreviewing = false

            let frame = scnView.session.currentFrame
            let basis = basis(fromPlacement: preview.placement)
            let surfaceTexture = frame.flatMap {
                SurfaceTexture.luminanceMap(frame: $0, basis: basis, size: previewSize)
            }

            // LiDAR: drape the art over the scanned mesh so it wraps the real
            // geometry. Otherwise (or when the mesh is too sparse) a flat quad.
            let node: SCNNode
            if hasLidar, let anchors = frame?.anchors,
               let decal = DecalMesh.geometry(basis: basis, size: previewSize, anchors: anchors) {
                decal.materials = [makePieceMaterial(transparent: false, surfaceTexture: surfaceTexture)]
                node = SCNNode(geometry: decal)
                node.simdTransform = basis
            } else {
                node = makePieceNode(size: previewSize, transparent: false, surfaceTexture: surfaceTexture)
                node.simdTransform = preview.placement
            }
            node.opacity = 0
            scnView.scene.rootNode.addChildNode(node)
            node.runAction(.fadeIn(duration: 0.25))
            lastPlacedNode = node
            placedNodes.append(node)

            let camera = frame?.camera
            onPlace(preview.surfaceType)
            // Give the stamp-in animation a beat so the snapshot shows the final piece.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, let scnView = self.scnView else { return }
                let sceneData = scnView.snapshot().jpegData(compressionQuality: 0.8)
                self.emitPlacementSnapshot(
                    placement: preview.placement,
                    position: preview.position,
                    surfaceType: preview.surfaceType,
                    camera: camera,
                    sceneData: sceneData
                )
            }
            onPreviewState(false)
        }

        private func cancelPlacement() {
            lastCancelAt = Date()
            previewNode?.removeFromParentNode()
            previewNode = nil
            previewInfo = nil
            isPreviewing = false
            onPreviewState(false)
        }

        /// Removes the just-placed piece when the user declines to post it.
        private func discardLast() {
            guard let node = lastPlacedNode else { return }
            lastPlacedNode = nil
            placedNodes.removeAll { $0 === node }
            node.runAction(.sequence([
                .fadeOut(duration: 0.2),
                .removeFromParentNode(),
            ]))
        }

        func handleCommands(placeToken: Int, cancelToken: Int, discardToken: Int) {
            if placeToken != lastPlaceToken {
                lastPlaceToken = placeToken
                confirmPlacement()
            }
            if cancelToken != lastCancelToken {
                lastCancelToken = cancelToken
                cancelPlacement()
            }
            if discardToken != lastDiscardToken {
                lastDiscardToken = discardToken
                discardLast()
            }
        }

        private func makePieceMaterial(transparent: Bool, surfaceTexture: UIImage? = nil) -> SCNMaterial {
            let material = SCNMaterial()
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.diffuse.contents = drawingImage ?? color
            // Decal UVs can overshoot [0,1] at triangle edges; clamping extends
            // the artwork's transparent border instead of tiling it.
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            if let surfaceTexture {
                material.multiply.contents = surfaceTexture
                material.multiply.wrapS = .clamp
                material.multiply.wrapT = .clamp
            }
            if transparent {
                material.transparency = 0.55
            }
            return material
        }

        private func makePieceNode(size: Float, transparent: Bool, surfaceTexture: UIImage? = nil) -> SCNNode {
            let node = SCNNode()
            node.geometry = SCNPlane(width: CGFloat(size), height: CGFloat(size))
            node.geometry?.materials = [makePieceMaterial(transparent: transparent, surfaceTexture: surfaceTexture)]
            return node
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

            // Scale is baked into the rotation columns: viewers apply this to a
            // 0.3 m quad, so length(col0)/0.3 reconstructs the placed size.
            let sizeScale = previewSize / 0.3
            let rotationOnly = simd_float4x4(columns: (
                placement.columns.0 * sizeScale,
                placement.columns.1 * sizeScale,
                placement.columns.2 * sizeScale,
                simd_float4(0, 0, 0, 1)
            ))

            let pitch = camera.map { Double($0.eulerAngles.x) * 180 / .pi } ?? 0
            let distance = simd_length(position - cameraPos)

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

                var world = simd_float4x4(columns: (
                    rotation.columns.0,
                    rotation.columns.1,
                    rotation.columns.2,
                    simd_float4(position.x, position.y, position.z, 1)
                ))
                if let snapped = self.snappedTransform(for: piece, near: position) {
                    world = snapped
                    self.snappedIDs.insert(piece.id)
                }
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

        /// As the GPS fix settles, slide fallback pieces to their corrected
        /// spots — and glue them to a real detected surface as soon as one
        /// matching their stored orientation appears. A physical surface beats
        /// GPS noise, so a snapped piece stays put.
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
                if snappedIDs.contains(id) {
                    if simd_distance(node.simdPosition, desired) > 4 {
                        snappedIDs.remove(id)
                    }
                    continue
                }
                if let snapped = snappedTransform(for: piece, near: desired) {
                    snappedIDs.insert(id)
                    SCNTransaction.begin()
                    SCNTransaction.animationDuration = 0.35
                    node.simdTransform = snapped
                    SCNTransaction.commit()
                    continue
                }
                if simd_distance(node.simdPosition, desired) > 0.5 {
                    var t = node.simdTransform
                    t.columns.3 = simd_float4(desired.x, desired.y, desired.z, 1)
                    node.simdTransform = t
                }
            }
        }

        // MARK: - Surface snapping

        /// Casts along the piece's stored surface normal (LiDAR mesh first,
        /// detected planes otherwise) and, when a surface of the right class is
        /// within reach, returns the piece's transform glued onto it.
        private func snappedTransform(for piece: RemotePiece, near desired: SIMD3<Float>) -> simd_float4x4? {
            guard let scnView else { return nil }
            let stored = piece.placementTransform.flatMap(unflatten)
            let scale = stored.map { simd_length(simd_make_float3($0.columns.0)) } ?? 1
            let normal = stored.map { simd_normalize(simd_make_float3($0.columns.2)) } ?? SIMD3<Float>(0, 0, 1)
            let upHint = stored.map { simd_normalize(simd_make_float3($0.columns.0)) } ?? SIMD3<Float>(0, 1, 0)

            var surfacePoint: SIMD3<Float>?
            var surfaceNormal: SIMD3<Float>?

            let from = desired + normal * 2
            let hits = scnView.scene.rootNode.hitTestWithSegment(
                from: SCNVector3(from),
                to: SCNVector3(desired - normal * 2),
                options: [SCNHitTestOption.backFaceCulling.rawValue: false]
            )
            if let hit = hits.first(where: { $0.node.name == "occlusion" }) {
                surfacePoint = simd_float3(hit.worldCoordinates.x, hit.worldCoordinates.y, hit.worldCoordinates.z)
                let n = hit.worldNormal
                surfaceNormal = simd_normalize(simd_float3(n.x, n.y, n.z))
            } else {
                let query = ARRaycastQuery(origin: from, direction: -normal, allowing: .existingPlaneGeometry, alignment: .any)
                if let result = scnView.session.raycast(query).first {
                    surfacePoint = simd_make_float3(result.worldTransform.columns.3)
                    surfaceNormal = (result.anchor as? ARPlaneAnchor).map {
                        simd_normalize(simd_make_float3($0.transform.columns.1))
                    } ?? normal
                }
            }

            guard let point = surfacePoint, var n = surfaceNormal,
                  simd_distance(point, desired) < 2.5 else { return nil }
            if simd_dot(n, normal) < 0 { n = -n }
            guard orientationMatches(piece.surfaceType, normal: n) else { return nil }

            var t = pieceTransform(position: point + n * 0.004, normal: n, upHint: upHint)
            t.columns.0 *= scale
            t.columns.1 *= scale
            t.columns.2 *= scale
            return t
        }

        /// A wall piece must not land on a floor and vice versa.
        private func orientationMatches(_ surfaceType: String?, normal: SIMD3<Float>) -> Bool {
            switch surfaceType {
            case "wall", "door", "window": return abs(normal.y) < 0.5
            case "floor": return normal.y > 0.7
            case "ceiling": return normal.y < -0.7
            case "table", "seat": return normal.y > 0.5
            default: return true
            }
        }

        /// Surface-aligned piece transform (upright correction included).
        private func pieceTransform(position: SIMD3<Float>, normal: SIMD3<Float>, upHint: SIMD3<Float>) -> simd_float4x4 {
            var up = upHint - normal * simd_dot(upHint, normal)
            if simd_length(up) < 0.01 { up = simd_cross(normal, SIMD3<Float>(1, 0, 0)) }
            if simd_length(up) < 0.01 { up = simd_cross(normal, SIMD3<Float>(0, 0, 1)) }
            up = simd_normalize(up)
            let right = simd_cross(up, normal)
            // Same upright fold as makePlacement: col0 = up, col1 = -right.
            return simd_float4x4(columns: (
                simd_float4(up.x, up.y, up.z, 0),
                simd_float4(-right.x, -right.y, -right.z, 0),
                simd_float4(normal.x, normal.y, normal.z, 0),
                simd_float4(position.x, position.y, position.z, 1)
            ))
        }

        /// Recovers the pre-upright frame (right/up/normal) from a placement.
        private func basis(fromPlacement placement: simd_float4x4) -> simd_float4x4 {
            simd_float4x4(columns: (
                -placement.columns.1,
                placement.columns.0,
                placement.columns.2,
                placement.columns.3
            ))
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
            // Track the child, not ARKit's anchor node — clear() must never
            // remove nodes ARKit manages.
            remoteNodes[pending.id] = child
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
