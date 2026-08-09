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
    var controller: ARController
    var showDebug: Bool
    var isActive: Bool
    var remotePieces: [RemotePiece]

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView(frame: .zero)
        scnView.delegate = context.coordinator
        scnView.debugOptions = context.coordinator.debugOptions(showDebug)
        scnView.automaticallyUpdatesLighting = true
        context.coordinator.scnView = scnView
        context.coordinator.setupSession(in: scnView)
        return scnView
    }

    func updateUIView(_ scnView: ARSCNView, context: Context) {
        context.coordinator.setActive(isActive)
        context.coordinator.renderRemotePieces(remotePieces)
        scnView.debugOptions = context.coordinator.debugOptions(showDebug)
    }
}

extension ARPaintView {
    final class Coordinator: NSObject, ARSCNViewDelegate {
        var scnView: ARSCNView?
        private let controller: ARController
        private var lastStatus = ""
        private var renderedRemoteIDs: Set<Int> = []
        private var remoteNodes: [Int: SCNNode] = [:]
        private var remoteScale: [Int: Float] = [:]
        private var loadFailures: [Int: Int] = [:]
        private var snapAttempts: [Int: Int] = [:]
        private var fallbackNodes: [Int: SCNNode] = [:]
        private var fallbackPieces: [Int: RemotePiece] = [:]
        private var lastReanchor = Date.distantPast
        private var sessionActive = true
        private var placedNodes: [SCNNode] = []
        private var meshCount = 0
        private var lastPlacedNode: SCNNode?
        private var snappedIDs: Set<Int> = []
        /// The interface orientation the still was shot in. Everything that maps
        /// between the overlay and the world has to use *that* orientation, not
        /// whichever way the phone happens to be held when Place is tapped.
        private var captureOrientation: UIInterfaceOrientation = .portrait

        let hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)

        init(controller: ARController) {
            self.controller = controller
            super.init()
            controller.coordinator = self
        }

        func debugOptions(_ show: Bool) -> SCNDebugOptions {
            show ? [.showFeaturePoints] : []
        }

        // MARK: - Session

        func setupSession(in scnView: ARSCNView) {
            scnView.session.run(makeWorldConfiguration())
        }

        /// World tracking with every depth capability the device offers: LiDAR
        /// scene reconstruction for occlusion, wrapping and surface
        /// classification, plus person segmentation.
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
                scnView.session.run(makeWorldConfiguration())
            } else {
                scnView.session.pause()
            }
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            Task { @MainActor [weak self] in
                self?.publishStatus()
                self?.maybeReanchor()
            }
        }

        // MARK: - Occlusion mesh

        nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let mesh = anchor as? ARMeshAnchor else { return }
            node.geometry = MeshOcclusion.geometry(from: mesh.geometry)
            node.renderingOrder = -1
            node.name = "occlusion"
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let mesh = anchor as? ARMeshAnchor else { return }
            node.geometry = MeshOcclusion.geometry(from: mesh.geometry)
        }

        // MARK: - Status

        private func publishStatus() {
            let (status, ready) = sessionStatus()
            guard status != lastStatus else { return }
            lastStatus = status
            controller.setStatus(status, ready: ready)
        }

        private func sessionStatus() -> (String, Bool) {
            guard let frame = scnView?.session.currentFrame else {
                return ("Starting camera…", false)
            }
            switch frame.camera.trackingState {
            case .notAvailable:
                return ("AR isn't available on this device", false)
            case .normal:
                if hasLidar {
                    let meshes = frame.anchors.reduce(into: 0) { count, anchor in
                        if anchor is ARMeshAnchor { count += 1 }
                    }
                    meshCount = meshes
                    return meshes < 2
                        ? ("Scanning the surface — pan slowly (\(meshes))", false)
                        : ("Depth ready · \(meshes) chunks — point at a wall", true)
                }
                let planes = frame.anchors.reduce(into: 0) { count, anchor in
                    if anchor is ARPlaneAnchor { count += 1 }
                }
                return planes == 0
                    ? ("Scanning — pan slowly across a wall", false)
                    : ("Ready — point at a wall", true)
            case .limited(let reason):
                return (limitedReason(reason), false)
            }
        }

        private func limitedReason(_ reason: ARCamera.TrackingState.Reason) -> String {
            switch reason {
            case .initializing: return "Getting started — move the phone around"
            case .excessiveMotion: return "Slow down"
            case .insufficientFeatures: return "Point at a more textured surface"
            case .relocalizing: return "Finding your spot again"
            @unknown default: return "Waiting"
            }
        }

        /// Removes only our piece nodes. ARKit-managed nodes — the LiDAR
        /// occlusion meshes above all — must survive, or occlusion silently
        /// dies for the rest of the session.
        func clearPieces() {
            for node in placedNodes { node.removeFromParentNode() }
            placedNodes.removeAll()
            lastPlacedNode = nil
            for (_, node) in remoteNodes { node.removeFromParentNode() }
            remoteNodes.removeAll()
            remoteScale.removeAll()
            renderedRemoteIDs.removeAll()
            fallbackNodes.removeAll()
            fallbackPieces.removeAll()
            snappedIDs.removeAll()
            loadFailures.removeAll()
            snapAttempts.removeAll()
        }

        // MARK: - Capture

        /// Freezes what the user is looking at: the rendered still, the pose it
        /// was seen from, and a value copy of the depth mesh in front of them.
        func capture() -> CapturedScene? {
            guard let scnView, let frame = scnView.session.currentFrame else { return nil }
            let viewport = scnView.bounds.size
            guard viewport.width > 0, viewport.height > 0 else { return nil }
            captureOrientation = scnView.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait

            let photo = scnView.snapshot()
            let camera = frame.camera
            let camPos = simd_make_float3(camera.transform.columns.3)
            let ahead = camPos - simd_make_float3(camera.transform.columns.2) * 2

            let triangles = hasLidar
                ? ProjectedDecal.triangles(anchors: frame.anchors, around: ahead)
                : []

            let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
            let fallback = flatPlacement(at: center, in: scnView)

            return CapturedScene(
                photo: photo,
                camera: camera,
                viewport: viewport,
                triangles: triangles,
                hasLidar: hasLidar,
                fallbackPlacement: fallback,
                surfaceType: surfaceType(at: ahead, frame: frame, fallback: fallback?.surfaceType)
            )
        }

        private func surfaceType(at point: SIMD3<Float>, frame: ARFrame, fallback: String?) -> String? {
            if let fallback, fallback != "unknown" { return fallback }
            guard hasLidar else { return nil }
            return MeshOcclusion.classification(at: point, anchors: frame.anchors)?.label
        }

        /// Raycast-derived flat placement — the no-LiDAR path, and the safety net
        /// when the mesh has nothing to project onto.
        private func flatPlacement(at screenPoint: CGPoint, in scnView: ARSCNView) -> (transform: simd_float4x4, position: SIMD3<Float>, surfaceType: String)? {
            var results = raycast(in: scnView, at: screenPoint, target: .existingPlaneGeometry)
            if results.isEmpty {
                results = raycast(in: scnView, at: screenPoint, target: .estimatedPlane)
            }
            guard let result = results.first, let camera = scnView.session.currentFrame?.camera else { return nil }

            let hit = result.worldTransform
            let position = simd_make_float3(hit.columns.3)
            var normal = (result.anchor as? ARPlaneAnchor).map {
                simd_normalize(simd_make_float3($0.transform.columns.1))
            } ?? simd_normalize(simd_make_float3(hit.columns.1))

            let camPos = simd_make_float3(camera.transform.columns.3)
            if simd_dot(normal, simd_normalize(camPos - position)) < 0 { normal = -normal }

            let transform = ProjectedDecal.surfaceFrame(
                position: position + normal * 0.004,
                normal: normal,
                upHint: simd_make_float3(camera.transform.columns.1)
            )
            let classification = (result.anchor as? ARPlaneAnchor)?.classification.label ?? "unknown"
            return (transform, position, classification)
        }

        // MARK: - Placing painted art

        /// Projects the finished overlay back into the world through the pose it
        /// was painted from, so it lands exactly where the user drew it and wraps
        /// whatever geometry was under the brush.
        func placePainted(overlay: UIImage, scene: CapturedScene) -> PlacementSnapshot? {
            guard let scnView, let mask = PaintMask(overlay: overlay) else { return nil }

            var node: SCNNode
            let placement: simd_float4x4
            let position: SIMD3<Float>
            let sizeMeters: Float

            if let projected = ProjectedDecal.build(
                triangles: scene.triangles,
                camera: scene.camera,
                viewport: scene.viewport,
                orientation: captureOrientation,
                mask: mask
            ) {
                projected.geometry.materials = [material(art: overlay, shade: scene.photo)]
                node = SCNNode(geometry: projected.geometry)
                placement = projected.placement
                position = projected.position
                sizeMeters = projected.extent
                controller.setLastPlacement("wrapped · \(projected.triangleCount) tris")
            } else {
                // No usable mesh: a flat quad on the raycast surface, cropped to
                // what the user actually painted.
                guard let fallback = scene.fallbackPlacement,
                      let bounds = mask.bounds,
                      let art = crop(overlay, to: bounds) else { return nil }
                let camPos = simd_make_float3(scene.camera.transform.columns.3)
                let distance = simd_distance(fallback.position, camPos)
                // Metres per screen-height at that distance, from the vertical FOV.
                let projection = scene.camera.projectionMatrix(
                    for: captureOrientation,
                    viewportSize: scene.viewport,
                    zNear: 0.01,
                    zFar: 100
                )
                let screenHeightM = 2 * distance / projection.columns.1.y
                let screenWidthM = screenHeightM * Float(scene.viewport.width / scene.viewport.height)
                let width = Float(bounds.width) * screenWidthM
                let height = Float(bounds.height) * screenHeightM

                let plane = SCNPlane(width: CGFloat(width), height: CGFloat(height))
                plane.materials = [material(art: art, shade: nil)]
                node = SCNNode(geometry: plane)

                // Slide it to where it sat on screen: +x right, +y down in the mask.
                var t = fallback.transform
                let right = -simd_make_float3(t.columns.1)
                let up = simd_make_float3(t.columns.0)
                let offset = right * Float(bounds.midX - 0.5) * screenWidthM
                    - up * Float(bounds.midY - 0.5) * screenHeightM
                t.columns.3 += simd_float4(offset, 0)
                placement = t
                position = simd_make_float3(t.columns.3)
                sizeMeters = max(width, height)
                node.simdTransform = placement
                controller.setLastPlacement(scene.triangles.isEmpty ? "flat · no mesh" : "flat · mesh missed")
            }

            node.renderingOrder = 10
            node.opacity = 0
            scnView.scene.rootNode.addChildNode(node)
            node.runAction(.fadeIn(duration: 0.3))
            placedNodes.append(node)
            lastPlacedNode = node

            return snapshot(placement: placement, position: position, size: sizeMeters, scene: scene)
        }

        /// Art on top, with the surface's own light and grain multiplied through
        /// it — same UVs, so the grain lines up perfectly with the wall.
        private func material(art: UIImage, shade: UIImage?) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = art
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            if let shade, let luminance = SurfaceTexture.luminance(of: shade) {
                material.multiply.contents = luminance
                material.multiply.wrapS = .clamp
                material.multiply.wrapT = .clamp
            }
            return material
        }

        private func crop(_ image: UIImage, to unit: CGRect) -> UIImage? {
            guard let cg = image.cgImage else { return nil }
            let rect = CGRect(
                x: unit.minX * CGFloat(cg.width),
                y: unit.minY * CGFloat(cg.height),
                width: unit.width * CGFloat(cg.width),
                height: unit.height * CGFloat(cg.height)
            ).integral
            guard let cropped = cg.cropping(to: rect) else { return nil }
            return UIImage(cgImage: cropped)
        }

        private func snapshot(
            placement: simd_float4x4,
            position: SIMD3<Float>,
            size: Float,
            scene: CapturedScene
        ) -> PlacementSnapshot? {
            guard let location = LocationService.shared.location else { return nil }
            let cameraPos = simd_make_float3(scene.camera.transform.columns.3)

            // Session frame is ENU (x=east, y=up, z=south) via gravityAndHeading.
            let enu = position - cameraPos
            let lat = location.coordinate.latitude + Double(-enu.z) / 111320
            let lng = location.coordinate.longitude + Double(enu.x) / (111320 * cos(location.coordinate.latitude * .pi / 180))

            // Viewers apply this to a 0.3 m quad, so bake the real size into the
            // rotation columns' length.
            let scale = max(size, 0.05) / 0.3
            let stored = simd_float4x4(columns: (
                placement.columns.0 * scale,
                placement.columns.1 * scale,
                placement.columns.2 * scale,
                simd_float4(0, 0, 0, 1)
            ))

            return PlacementSnapshot(
                lat: lat,
                lng: lng,
                altitudeM: location.altitude + Double(enu.y),
                heading: LocationService.shared.heading,
                accuracyM: location.horizontalAccuracy,
                distanceM: Double(simd_length(enu)),
                devicePitch: Double(scene.camera.eulerAngles.x) * 180 / .pi,
                surfaceType: scene.surfaceType == "unknown" ? nil : scene.surfaceType,
                usedGeoAnchor: false,
                hasLidar: hasLidar,
                placementTransform: flatten(stored)
            )
        }

        /// Removes the just-placed piece when the user declines to post it.
        func discardLast() {
            guard let node = lastPlacedNode else { return }
            lastPlacedNode = nil
            placedNodes.removeAll { $0 === node }
            node.runAction(.sequence([.fadeOut(duration: 0.2), .removeFromParentNode()]))
        }

        // MARK: - Rendering other people's pieces

        func renderRemotePieces(_ pieces: [RemotePiece]) {
            guard let scnView else { return }
            let wanted = Set(pieces.map(\.id))
            for (id, node) in remoteNodes where !wanted.contains(id) {
                node.removeFromParentNode()
                remoteNodes.removeValue(forKey: id)
                // The reanchor loop walks fallbackNodes, so a piece left behind
                // there keeps being repositioned long after it left the scene.
                remoteScale.removeValue(forKey: id)
                fallbackNodes.removeValue(forKey: id)
                fallbackPieces.removeValue(forKey: id)
                snappedIDs.remove(id)
                loadFailures.removeValue(forKey: id)
                snapAttempts.removeValue(forKey: id)
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
                // Cheap gates first — don't download an image we can't place.
                guard scnView.session.currentFrame != nil,
                      let gateFix = LocationService.shared.location, self.isUsableFix(gateFix) else {
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }
                // A piece whose image keeps failing stays in renderedRemoteIDs,
                // which is what stops the 3-second poll re-downloading it forever.
                guard self.loadFailures[piece.id, default: 0] < 3 else { return }

                let image: UIImage
                do {
                    image = try await APIClient.loadImage(path: piece.imagePath)
                } catch {
                    self.loadFailures[piece.id, default: 0] += 1
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }

                guard let frame = scnView.session.currentFrame,
                      let loc = LocationService.shared.location, self.isUsableFix(loc) else {
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }

                let camPos = simd_make_float3(frame.camera.transform.columns.3)
                let position = self.worldPosition(for: piece, from: loc, cameraPos: camPos)
                let stored = piece.placementTransform.flatMap(unflatten)
                let rotation = stored ?? matrix_identity_float4x4

                let node = SCNNode(geometry: SCNPlane(width: 0.3, height: 0.3))
                node.geometry?.materials = [self.remoteMaterial(image: image)]

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
                if stored == nil {
                    // Web pieces carry no orientation — face the viewer.
                    node.constraints = [SCNBillboardConstraint()]
                }
                node.simdTransform = world
                // The piece's real size lives in its transform's column lengths;
                // remember it before `applyVisibility` overwrites node.scale.
                self.remoteScale[piece.id] = simd_length(simd_make_float3(world.columns.0))
                self.applyVisibility(to: node, id: piece.id, snapped: self.snappedIDs.contains(piece.id), camPos: camPos)
                scnView.scene.rootNode.addChildNode(node)
                self.remoteNodes[piece.id] = node
                self.fallbackNodes[piece.id] = node
                self.fallbackPieces[piece.id] = piece
                self.publishNearby()
            }
        }

        private func remoteMaterial(image: UIImage) -> SCNMaterial {
            let material = SCNMaterial()
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.diffuse.contents = image
            return material
        }

        /// A piece the GPS has parked inside a wall would be swallowed by the
        /// occlusion mesh and simply never seen. Until it snaps onto a real
        /// surface it renders through geometry, like a map marker; once snapped
        /// it sits on the wall and occludes properly. Distant pieces are also
        /// scaled up so they stay legible instead of vanishing to a speck.
        private func applyVisibility(to node: SCNNode, id: Int, snapped: Bool, camPos: SIMD3<Float>) {
            if let material = node.geometry?.firstMaterial {
                material.readsFromDepthBuffer = snapped
                material.writesToDepthBuffer = snapped
            }
            node.renderingOrder = snapped ? 0 : 20

            let distance = simd_distance(node.simdPosition, camPos)
            let boost = snapped ? 1 : max(1, min(distance / 4, 6))
            // Setting node.scale *replaces* the scale SceneKit decomposed out of
            // simdTransform, so the piece's stored size has to be multiplied back
            // in — otherwise every remote piece collapses to the 0.3 m base quad.
            node.simdScale = SIMD3(repeating: (remoteScale[id] ?? 1) * boost)
        }

        /// How many pieces are loaded vs actually placed in the world, and how
        /// far the closest one is — surfaced in the debug readout.
        private func publishNearby() {
            let camPos = scnView?.session.currentFrame
                .map { simd_make_float3($0.camera.transform.columns.3) }
            let distances = remoteNodes.values.map { node -> Float in
                guard let camPos else { return .greatestFiniteMagnitude }
                return simd_distance(node.simdPosition, camPos)
            }
            controller.setNearby(
                rendered: remoteNodes.count,
                snapped: snappedIDs.count,
                nearestM: distances.min().map { $0 < .greatestFiniteMagnitude ? Double($0) : nil } ?? nil
            )
        }

        // MARK: - Reconstruction helpers (GPS fallback)

        /// A fix we can hang world positions off. Indoors a good fix never
        /// arrives, so this is deliberately generous — a piece in roughly the
        /// right direction beats no piece at all, and snapping corrects it.
        private func isUsableFix(_ loc: CLLocation) -> Bool {
            loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 80 &&
                Date().timeIntervalSince(loc.timestamp) < 60
        }

        /// Where a piece should sit in world space, given our current pose + fix.
        /// Vertical comes from the surface type, not GPS altitude (very noisy).
        private func worldPosition(for piece: RemotePiece, from loc: CLLocation, cameraPos: SIMD3<Float>) -> SIMD3<Float> {
            // Wrapped, so a piece across the antimeridian is 100 m away and not
            // half a planet away.
            let lngDelta = (piece.lng - loc.coordinate.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
            let eastDelta = lngDelta * 111320 * cos(loc.coordinate.latitude * .pi / 180)
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
        /// spots — and glue them to a real surface as soon as one matching their
        /// stored orientation appears. A physical surface beats GPS noise, so a
        /// snapped piece stays put.
        private func maybeReanchor() {
            guard Date().timeIntervalSince(lastReanchor) > 2 else { return }
            lastReanchor = Date()
            guard let scnView, !fallbackNodes.isEmpty else { return }
            guard let frame = scnView.session.currentFrame,
                  let loc = LocationService.shared.location, isUsableFix(loc) else { return }
            let camPos = simd_make_float3(frame.camera.transform.columns.3)
            // Each snap attempt is a full-scene hit test; budget them per cycle
            // and back off per piece, or a room full of un-snappable pieces
            // turns into a periodic main-thread stall.
            var snapBudget = 4
            for (id, node) in fallbackNodes {
                guard let piece = fallbackPieces[id] else { continue }
                let desired = worldPosition(for: piece, from: loc, cameraPos: camPos)
                if snappedIDs.contains(id) {
                    if simd_distance(node.simdPosition, desired) > 4 { snappedIDs.remove(id) }
                    continue
                }
                let attempts = snapAttempts[id, default: 0]
                if snapBudget > 0, attempts < 10 || attempts % 8 == 0 {
                    snapBudget -= 1
                    snapAttempts[id] = attempts + 1
                    if let snapped = snappedTransform(for: piece, near: desired) {
                        snappedIDs.insert(id)
                        SCNTransaction.begin()
                        SCNTransaction.animationDuration = 0.35
                        node.simdTransform = snapped
                        applyVisibility(to: node, id: id, snapped: true, camPos: camPos)
                        SCNTransaction.commit()
                        continue
                    }
                } else if attempts >= 10 {
                    snapAttempts[id] = attempts + 1
                }
                if simd_distance(node.simdPosition, desired) > 0.5 {
                    var t = node.simdTransform
                    t.columns.3 = simd_float4(desired.x, desired.y, desired.z, 1)
                    node.simdTransform = t
                }
                applyVisibility(to: node, id: id, snapped: false, camPos: camPos)
            }
            publishNearby()
        }

        /// Casts along the piece's stored surface normal (LiDAR mesh first,
        /// detected planes otherwise) and, when a surface of the right class is
        /// within reach, returns the piece's transform glued onto it.
        private func snappedTransform(for piece: RemotePiece, near desired: SIMD3<Float>) -> simd_float4x4? {
            guard let scnView else { return nil }
            let stored = piece.placementTransform.flatMap(unflatten)
            // A transform written by a future client could carry anything; clamp
            // it to sizes that can actually be seen rather than trusting it.
            let scale = stored.map { min(max(simd_length(simd_make_float3($0.columns.0)), 0.05), 40) } ?? 1
            let normal = stored.flatMap { unitVector(simd_make_float3($0.columns.2)) } ?? SIMD3<Float>(0, 0, 1)
            let upHint = stored.flatMap { unitVector(simd_make_float3($0.columns.0)) } ?? SIMD3<Float>(0, 1, 0)

            var surfacePoint: SIMD3<Float>?
            var surfaceNormal: SIMD3<Float>?

            let from = desired + normal * 2
            let hits = scnView.scene.rootNode.hitTestWithSegment(
                from: SCNVector3(from),
                to: SCNVector3(desired - normal * 2),
                options: [SCNHitTestOption.backFaceCulling.rawValue: false]
            )
            if let hit = hits.first(where: { $0.node.name == "occlusion" }),
               let n = unitVector(simd_float3(hit.worldNormal)) {
                surfacePoint = simd_float3(hit.worldCoordinates)
                surfaceNormal = n
            } else {
                let query = ARRaycastQuery(origin: from, direction: -normal, allowing: .existingPlaneGeometry, alignment: .any)
                if let result = scnView.session.raycast(query).first {
                    surfacePoint = simd_make_float3(result.worldTransform.columns.3)
                    surfaceNormal = (result.anchor as? ARPlaneAnchor)
                        .flatMap { unitVector(simd_make_float3($0.transform.columns.1)) } ?? normal
                }
            }

            guard let point = surfacePoint, var n = surfaceNormal,
                  simd_distance(point, desired) < 2.5 else { return nil }
            if simd_dot(n, normal) < 0 { n = -n }
            guard orientationMatches(piece.surfaceType, normal: n) else { return nil }

            var t = ProjectedDecal.surfaceFrame(position: point + n * 0.004, normal: n, upHint: upHint)
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

        private func raycast(in scnView: ARSCNView, at location: CGPoint, target: ARRaycastQuery.Target) -> [ARRaycastResult] {
            guard let query = scnView.raycastQuery(from: location, allowing: target, alignment: .any) else { return [] }
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

/// Nil for anything that isn't a usable matrix. `placement_transform` is a JSONB
/// column any client can fill, and both a short array (index crash) and a NaN
/// (node silently disappears) are one bad row away.
func unflatten(_ a: [Double]) -> simd_float4x4? {
    guard a.count == 16, a.allSatisfy(\.isFinite) else { return nil }
    let f = a.map(Float.init)
    return simd_float4x4(columns: (
        simd_float4(f[0], f[1], f[2], f[3]),
        simd_float4(f[4], f[5], f[6], f[7]),
        simd_float4(f[8], f[9], f[10], f[11]),
        simd_float4(f[12], f[13], f[14], f[15])
    ))
}
