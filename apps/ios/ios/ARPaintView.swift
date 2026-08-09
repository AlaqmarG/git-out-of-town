import ARKit
import CoreLocation
import Metal
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
    /// The same placement in the printed poster's frame, when one was in view.
    /// Nil is the norm, and means viewers fall back to lat/lng.
    let markerTransform: [Double]?
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
    let markerTransform: [Double]?
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
        // The wireframe answers "is ARKit meshing at all?" — the one question
        // that can't be answered from a Mac.
        MeshOcclusion.showWireframe = showDebug
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
        /// Remote pieces already given the wall treatment, and how many times we
        /// have tried — a piece seen only edge-on must not retry forever.
        private var dressedIDs: Set<Int> = []
        private var dressAttempts: [Int: Int] = [:]
        private var lastDress = Date.distantPast
        /// Bumped whenever the scene is emptied. An in-flight image download
        /// carries the generation it started in, so a placement computed against
        /// a world origin that has since moved is dropped instead of landing.
        private var sceneGeneration = 0
        /// Last set the poll loop handed us. Server state, not scene state, so
        /// `clearPieces` leaves it alone and the scene can be rebuilt from it
        /// without waiting for the next poll.
        private var lastRemotePieces: [RemotePiece] = []
        private var lastPlacedFrame: simd_float4x4?
        private var lastPlacedSize: Float = 0.3
        private var anchoredPieceIDs: Set<Int> = []
        private var knownImagePaths: [Int: String] = [:]
        private var relocalizeAttempted = false
        private var relocalizeInFlight = false
        private var relocalizeTask: Task<Void, Never>?
        private var coaching: CoachingOverlay?
        private var relocalizing = false {
            didSet { coaching?.goal = relocalizing ? .tracking : .anyPlane }
        }
        private var sessionStartedAt: TimeInterval = 0
        /// The venue map this session is extending: whatever we relocalized
        /// against, then every version we ship on top of it. Nil means this
        /// session has no lineage yet and the next upload starts one.
        private var chainParent: WorldMapStore.Record?
        /// Frame time the current `chainParent` became ours. The visitor has to
        /// actually walk somewhere before their map is worth re-uploading.
        private var chainBaselineAt: TimeInterval = 0
        /// The walk-around re-upload fires once per session. A post ships a map
        /// of its own; this is for the visitor who only ever looks.
        private var extendedThisSession = false
        /// Apple's gate for saving a world map: has this session ever reached
        /// `.mapped`? Sticky, because the live status oscillates.
        private var everMapped = false
        private var lastPlaceabilityUpdate: TimeInterval = 0
        /// The interface orientation the still was shot in. Everything that maps
        /// between the overlay and the world has to use *that* orientation, not
        /// whichever way the phone happens to be held when Place is tapped.
        private var captureOrientation: UIInterfaceOrientation = .portrait

        let hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)

        init(controller: ARController) {
            self.controller = controller
            super.init()
            controller.coordinator = self
            // Resolve the shader probe now: it compiles Metal from source, and
            // the only other time it would run is the first tap that places art.
            Task.detached(priority: .utility) { _ = Self.aerosolShaderCompiles }
        }

        func debugOptions(_ show: Bool) -> SCNDebugOptions {
            show ? [.showFeaturePoints] : []
        }

        // MARK: - Session

        func setupSession(in scnView: ARSCNView) {
            scnView.session.run(makeWorldConfiguration())
            coaching = CoachingOverlay(
                session: scnView.session,
                in: scnView,
                onActive: { [weak self] in self?.controller.setCoaching($0) },
                onReset: { [weak self] in self?.startOver() }
            )
        }

        /// "Start Over" on the coaching overlay — the escape hatch from a
        /// relocalization that will never match. Resetting only the session
        /// would leave the in-flight attempt free to swap another world map in
        /// underneath, and every node still parked at the old world origin.
        private func startOver() {
            guard let scnView else { return }
            relocalizeTask?.cancel()
            relocalizeTask = nil
            relocalizing = false
            // One attempt per session, and this was it: retrying would drop the
            // user straight back into the stall they just escaped.
            relocalizeAttempted = true
            everMapped = false
            meshCount = 0
            sessionStartedAt = 0
            anchoredPieceIDs.removeAll()
            lastPlacedFrame = nil
            resetWorld(with: makeWorldConfiguration())
        }

        /// The one way to re-run with `.resetTracking`. Every world coordinate in
        /// the app is about to mean somewhere else, so the marker origin and the
        /// whole scene go with it. Marker-placed pieces especially: they sit
        /// outside `fallbackNodes` precisely so nothing repositions them, which
        /// also means nothing would ever fix them.
        private func resetWorld(with config: ARWorldTrackingConfiguration) {
            ImageMarkerOrigin.reset()
            controller.setMarkerLocked(false)
            clearPieces()
            scnView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        /// ARKit relocalizes after a `pause()` and, when that fails, restarts the
        /// session — which deletes every anchor, mesh included. We would rather
        /// keep the reconstruction and let tracking recover on its own.
        nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
            false
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
            // Detection only (`maximumNumberOfTrackedImages` stays 0): the
            // poster fires one anchor, we take the origin off it, done.
            config.detectionImages = ImageMarkerOrigin.referenceImages
            if hasLidar {
                config.sceneReconstruction = .meshWithClassification
                // The dense per-pixel depth map. The reconstruction mesh is ~5cm
                // and tears into patches across a can or a keyboard; this is
                // 256x192 and follows a curved surface smoothly.
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                    config.frameSemantics.insert(.smoothedSceneDepth)
                } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.insert(.sceneDepth)
                }
            }
            // Person segmentation competes with scene reconstruction for the same
            // depth pipeline and slows mesh growth. Wrapping art onto real
            // geometry matters more than people occluding it.
            return config
        }

        /// Pause AR while another tab is showing; resume (keeping anchors) on return.
        func setActive(_ active: Bool) {
            guard active != sessionActive, let scnView else { return }
            sessionActive = active
            if active {
                scnView.session.run(makeWorldConfiguration())
            } else {
                controller.setPlaceable(false)
                scnView.session.pause()
            }
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            Task { @MainActor [weak self] in
                self?.publishStatus()
                self?.publishPlaceability(at: time)
                self?.maybeRelocalize()
                self?.maybeExtendMap(at: time)
                self?.maybeReanchor()
                self?.maybeDressRemotePieces()
            }
        }

        // MARK: - Session failure

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor [weak self] in
                self?.controller.sessionFailed(error)
            }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor [weak self] in
                self?.controller.sessionResumed()
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
            if let marker = anchor as? ARImageAnchor {
                Task { @MainActor [weak self] in
                    self?.adoptMarker(marker)
                }
                return
            }
            // Anchors named piece:<id>:<mm> arrive out of a relocalized world
            // map — each one is a piece at its exact painted spot.
            if let name = anchor.name, name.hasPrefix("piece:") {
                Task { @MainActor [weak self] in
                    self?.attachAnchoredPiece(node: node, name: name)
                }
            }
        }

        nonisolated func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let mesh = anchor as? ARMeshAnchor else { return }
            node.geometry = MeshOcclusion.geometry(from: mesh.geometry)
        }

        // MARK: - Status

        private func publishStatus() {
            publishScanQuality()
            let (status, ready) = sessionStatus()
            guard status != lastStatus else { return }
            lastStatus = status
            controller.setStatus(status, ready: ready)
        }

        /// How well this spot is scanned — drives the placement-quality chip on
        /// the Post card and decides whether a world map is worth uploading.
        private func publishScanQuality() {
            guard let frame = scnView?.session.currentFrame else { return }
            let quality: String
            switch frame.worldMappingStatus {
            case .mapped:
                // Sticky: ARKit drops back to .extending the moment the camera
                // turns to fresh geometry, but the mapped area stays mapped.
                everMapped = true
                quality = "precise"
            case .extending: quality = everMapped ? "precise" : "good"
            default: quality = everMapped ? "precise" : "rough"
            }
            controller.setScanQuality(quality)
        }

        private func sessionStatus() -> (String, Bool) {
            if relocalizing {
                return ("Matching this spot to earlier scans…", false)
            }
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

        /// Updates the viewfinder at a modest rate: green means the exact point
        /// under it intersects LiDAR mesh or a fully detected AR plane.
        private func publishPlaceability(at time: TimeInterval) {
            guard time - lastPlaceabilityUpdate >= 0.1 else { return }
            lastPlaceabilityUpdate = time
            guard sessionActive, let scnView, let frame = scnView.session.currentFrame else {
                controller.setPlaceable(false)
                return
            }
            guard case .normal = frame.camera.trackingState else {
                controller.setPlaceable(false)
                return
            }

            let center = CGPoint(x: scnView.bounds.midX, y: scnView.bounds.midY)
            let hitsMesh = hasLidar && scnView.hitTest(center, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .backFaceCulling: false,
                .ignoreHiddenNodes: false
            ]).contains { $0.node.name == "occlusion" }
            let hitsPlane = !raycast(in: scnView, at: center, target: .existingPlaneGeometry).isEmpty
            controller.setPlaceable(hitsMesh || hitsPlane)
        }

        /// Removes only our piece nodes. ARKit-managed nodes — the LiDAR
        /// occlusion meshes above all — must survive, or occlusion silently
        /// dies for the rest of the session.
        func clearPieces() {
            sceneGeneration += 1
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
            dressedIDs.removeAll()
            dressAttempts.removeAll()
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
            let depth = hasLidar ? DepthDecal.capture(from: frame) : nil

            let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
            let fallback = flatPlacement(at: center, in: scnView)

            return CapturedScene(
                photo: photo,
                camera: camera,
                viewport: viewport,
                triangles: triangles,
                depth: depth,
                orientation: captureOrientation,
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

            // Dense depth first: it follows a can or a keyboard smoothly where
            // the 5 cm reconstruction mesh tears into disconnected patches.
            let fromDepth = scene.depth.flatMap {
                DepthDecal.build(
                    depth: $0,
                    camera: scene.camera,
                    viewport: scene.viewport,
                    orientation: scene.orientation,
                    mask: mask
                )
            }
            if let projected = fromDepth ?? ProjectedDecal.build(
                triangles: scene.triangles,
                camera: scene.camera,
                viewport: scene.viewport,
                orientation: captureOrientation,
                mask: mask
            ) {
                projected.geometry.materials = [
                    material(art: overlay, shade: scene.photo, graze: projected.graze),
                ]
                node = SCNNode(geometry: projected.geometry)
                placement = projected.placement
                position = projected.position
                sizeMeters = projected.extent
                controller.setLastPlacement(
                    fromDepth != nil
                        ? "Wrapped to dense depth · \(projected.triangleCount) facets"
                        : "Wrapped onto \(projected.triangleCount) mesh facets",
                    wrapped: true
                )
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
                // The wall behind the art, cropped to the same screen region, so
                // the flat path picks up surface grain too. Without this, every
                // fallback placement rendered as flat colour on flat colour.
                // A flat quad has one normal, so every point of it faces the can
                // equally — no graze map to build.
                plane.materials = [
                    material(art: art, shade: crop(scene.photo, to: bounds), graze: nil),
                ]
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
                controller.setLastPlacement(
                    scene.triangles.isEmpty
                        ? "Flat — no depth mesh here yet (scan longer)"
                        : "Flat — mesh had \(scene.triangles.count) facets but none under the art",
                    wrapped: false
                )
            }

            node.renderingOrder = 10
            node.opacity = 0
            scnView.scene.rootNode.addChildNode(node)
            node.runAction(.fadeIn(duration: 0.3))
            placedNodes.append(node)
            lastPlacedNode = node
            // Rigid frame for the ARWorldMap anchor: unit axes + the real position.
            lastPlacedFrame = simd_float4x4(columns: (
                simd_float4(simd_normalize(simd_make_float3(placement.columns.0)), 0),
                simd_float4(simd_normalize(simd_make_float3(placement.columns.1)), 0),
                simd_float4(simd_normalize(simd_make_float3(placement.columns.2)), 0),
                simd_float4(position, 1)
            ))
            lastPlacedSize = sizeMeters

            return snapshot(placement: placement, position: position, size: sizeMeters, scene: scene)
        }

        // MARK: - Shared origin (printed marker)

        /// The poster gives every device that sees it the same world origin.
        /// Only worth doing while the scene is still empty: nothing we have
        /// added is anchor-backed, so ARKit will not carry it across the origin
        /// change, and a piece the user already painted would jump.
        private func adoptMarker(_ anchor: ARImageAnchor) {
            guard let scnView, sessionActive, placedNodes.isEmpty, anchoredPieceIDs.isEmpty,
                  ImageMarkerOrigin.adopt(anchor, in: scnView.session) else { return }
            // Remote pieces are sitting at coordinates from the old origin. Drop
            // them and rebuild in the new frame right here — waiting on the poll
            // loop would mean waiting for the piece SET to change, which at a
            // quiet venue is never.
            clearPieces()
            controller.setMarkerLocked(true)
            renderRemotePieces(lastRemotePieces)
        }

        // MARK: - Visual relocalization (ARWorldMap)

        /// After a successful post: pin the piece as a named anchor and ship the
        /// session's visual scan to the server, so a returning device can match
        /// this exact spot instead of trusting GPS. Fire-and-forget.
        func saveScan(pieceId: Int) {
            guard let scnView, let frame = lastPlacedFrame else { return }
            // Apple: save a map only once the session has reached `.mapped`.
            // `.extending` relocalizes only if the viewer retraces the painter's
            // path; `.mapped` just needs a similar viewpoint — and a stranger
            // walking up to a wall will never retrace anything.
            guard everMapped else { return }

            let name = WorldMapStore.pieceName(id: pieceId, sizeM: lastPlacedSize)
            let pieceAnchor = ARAnchor(name: name, transform: frame)
            scnView.session.add(anchor: pieceAnchor)
            anchoredPieceIDs.insert(pieceId)
            // What the painter is looking at right now, shipped with the map so
            // a viewer can stand in the same place instead of hunting for the
            // match. Grabbed here, before the phone drifts off the wall.
            shipMap(pieceId: pieceId, appending: pieceAnchor, shot: PlacementGuide.capture(from: scnView))
        }

        /// The other half of chaining, and the whole pitch: a visitor who never
        /// paints still leaves the venue's map better than they found it. Once a
        /// session, after they have actually walked somewhere.
        ///
        /// Deliberately ships no placement guide. Wherever this visitor happens
        /// to be standing after a wander is a worse "stand here" than the
        /// painter's own view, so the server keeps the parent's.
        private func maybeExtendMap(at time: TimeInterval) {
            // Cheap checks first: `currentFrame` retains an ARFrame and its pixel
            // buffers, and this runs on every rendered frame for the whole window.
            guard !extendedThisSession, sessionActive, everMapped,
                  chainParent != nil, time - chainBaselineAt > 25,
                  let frame = scnView?.session.currentFrame,
                  // A map re-serialized while tracking is shaky is exactly the
                  // corrupt scan that must never take the head position.
                  case .normal = frame.camera.trackingState else { return }
            extendedThisSession = true
            shipMap(pieceId: nil)
        }

        /// Serialize the session's map and ship it as the next version of
        /// whatever this session is extending — or as a new venue when it is
        /// extending nothing.
        ///
        /// The server decides whether the chain is actually allowed; a scan
        /// carrying a fresh piece lands either way. Everything after the frame
        /// grab runs off the main actor: pruning reads the whole point cloud and
        /// archiving compresses megabytes, and both would stall the render loop.
        private func shipMap(
            pieceId: Int?,
            appending extra: ARAnchor? = nil,
            shot: (image: UIImage, transform: [Double])? = nil
        ) {
            guard let scnView else { return }
            let parent = chainParent
            scnView.session.getCurrentWorldMap { map, _ in
                guard let map else { return }
                // `add(anchor:)` only takes effect on the NEXT captured frame, so
                // the map we just asked for may not contain the piece at all —
                // and a map that relocalizes perfectly but carries no anchor is
                // indistinguishable from relocalization failing.
                if let extra, !map.anchors.contains(where: { $0.identifier == extra.identifier }) {
                    map.anchors.append(extra)
                }
                Task { @MainActor [weak self] in
                    guard let self, let location = LocationService.shared.location else { return }
                    let record = await Task.detached(priority: .utility) { () -> WorldMapStore.Record? in
                        let stats = WorldMapStore.prune(map)
                        // A walk-around that added nothing isn't worth a multi-MB
                        // upload the server would only refuse. A post always is.
                        if pieceId == nil, let parent,
                           !WorldMapStore.improves(stats, over: parent) { return nil }
                        return try? await WorldMapStore.upload(
                            map,
                            stats: stats,
                            pieceId: pieceId,
                            parentId: parent?.id,
                            location: location,
                            guide: shot.flatMap(PlacementGuide.encode)
                        )
                    }.value
                    guard let record else { return }
                    // Build the next version on this one. Chaining onto `parent`
                    // again would be refused — it is superseded now — and even our
                    // own first scan of a venue is something the rest of this
                    // session should thicken rather than sit beside.
                    self.chainParent = record
                    self.chainBaselineAt = self.scnView?.session.currentFrame?.timestamp ?? 0
                }
            }
        }

        /// Once per session, and ONLY in the first seconds: if someone scanned
        /// near here, relocalize against the closest scan — anchors inside it put
        /// their pieces on the exact wall.
        ///
        /// The window matters enormously. Relocalizing means `.resetTracking`,
        /// and Apple documents that as removing every anchor in the session —
        /// mesh anchors included. Do it late and it deletes the depth mesh the
        /// user just spent 30 seconds building, killing wrapping and occlusion
        /// for the rest of the session. So: only before there is a mesh to lose.
        private func maybeRelocalize() {
            guard !relocalizeAttempted, !relocalizeInFlight, sessionActive, meshCount == 0,
                  let scnView, let frame = scnView.session.currentFrame else { return }
            // The first frame arrives well after setupSession, so the session
            // start can only be read off a real frame (timestamps are uptime).
            if sessionStartedAt == 0 { sessionStartedAt = frame.timestamp }
            guard frame.timestamp - sessionStartedAt < 6,
                  let location = LocationService.shared.location,
                  location.horizontalAccuracy >= 0, location.horizontalAccuracy < 80 else { return }
            // Set before the await, or every render frame spawns another copy
            // of this task and they run competing session resets.
            relocalizeInFlight = true
            relocalizeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.relocalizeInFlight = false }
                // One exit for every way this ends — matched, exhausted,
                // cancelled — so the ghost can never outlive the search.
                defer { self.controller.setGuide(nil) }
                // Indoors at ±20 m GPS the nearest map is often the wrong room,
                // so walk the candidates rather than betting on one.
                guard let records = try? await WorldMapStore.nearby(location: location, radiusM: 80),
                      !records.isEmpty, !Task.isCancelled else { return }
                // Only now: a network blip shouldn't disable relocalization for
                // the whole session.
                self.relocalizeAttempted = true

                // Whether any candidate reset the session: only then does a
                // failure leave it pinned to an unmatched map, and only then is
                // the clean reset below worth the anchors it costs.
                var reset = false
                for record in records.prefix(3) {
                    // Apple's placement guide: the painter's view, shown ghosted
                    // so the user aims at the right wall while ARKit is still
                    // looking. Fetched alongside the map, never in front of it —
                    // the match window is six seconds wide. Scans saved before
                    // guides existed have none, and then the search runs blind
                    // exactly as it always did.
                    async let guide: UIImage? = {
                        guard let path = record.snapshotPath else { return nil }
                        return try? await APIClient.loadImage(path: path)
                    }()
                    let downloaded = try? await WorldMapStore.download(record)
                    let ghost = await guide
                    guard let map = downloaded else { continue }
                    // Start Over cancels us, and has already reset the session.
                    guard !Task.isCancelled else { return }
                    guard let scnView = self.scnView, self.sessionActive,
                          // The download took time; a mesh that grew meanwhile is
                          // worth more than the relocalization.
                          self.meshCount == 0 else { break }
                    self.controller.setGuide(ghost)

                    let config = self.makeWorldConfiguration()
                    config.initialWorldMap = map
                    reset = true
                    self.relocalizing = true
                    self.resetWorld(with: config)

                    // Apple gives no failure callback: `.normal` is the only
                    // signal a match landed, and a miss stays "relocalizing"
                    // forever. So poll, then move to the next candidate.
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        if case .normal = scnView.session.currentFrame?.camera.trackingState {
                            self.relocalizing = false
                            // Matched. The session now holds this map's anchors,
                            // so everything it serializes from here on is that
                            // map plus wherever this visitor walks — the next
                            // version of it, not a rival scan beside it.
                            self.chainParent = record
                            self.chainBaselineAt = scnView.session.currentFrame?.timestamp ?? 0
                            return
                        }
                    }
                }
                self.relocalizing = false
                // Nothing matched: drop back to a clean session + GPS fallback.
                if reset, self.sessionActive {
                    self.resetWorld(with: self.makeWorldConfiguration())
                }
            }
        }

        /// A piece riding a relocalized anchor: exact placement, managed by ARKit.
        private func attachAnchoredPiece(node: SCNNode, name: String) {
            guard let (id, size) = WorldMapStore.pieceName(name) else { return }
            Task { @MainActor [weak self] in
                // The anchor can resolve before the first pieces fetch lands, so
                // wait for the poll loop to learn this piece's image path. A map
                // outlives its pieces — an anchor for a deleted piece never
                // resolves a path, and must not suppress anything.
                var path: String?
                for _ in 0..<10 {
                    path = self?.knownImagePaths[id]
                    if path != nil { break }
                    try? await Task.sleep(for: .seconds(1))
                }
                // Relocalization runs on fixes up to ±80 m but the poll loop
                // gates at ±50 m, so in that band the anchor resolves and the
                // path never arrives. Fetch it directly rather than render nothing.
                if path == nil, let loc = LocationService.shared.location,
                   let pieces = try? await APIClient.listPieces(
                       lat: loc.coordinate.latitude,
                       lng: loc.coordinate.longitude,
                       radiusMeters: 300
                   ) {
                    for piece in pieces { self?.knownImagePaths[piece.id] = piece.finalImagePath ?? piece.rawImagePath }
                    path = self?.knownImagePaths[id]
                }
                guard let self, let path, let image = try? await APIClient.loadImage(path: path) else { return }
                // Claim the piece only now that it can actually be drawn.
                // Claiming earlier suppressed the GPS copy too, so a piece whose
                // image failed to load vanished from both paths entirely.
                self.anchoredPieceIDs.insert(id)
                if let stale = self.remoteNodes.removeValue(forKey: id) { stale.removeFromParentNode() }
                self.fallbackNodes.removeValue(forKey: id)
                self.fallbackPieces.removeValue(forKey: id)
                let plane = SCNPlane(width: size, height: size)
                let material = SCNMaterial()
                material.isDoubleSided = true
                material.lightingModel = .constant
                material.diffuse.contents = image
                plane.materials = [material]
                node.addChildNode(SCNNode(geometry: plane))
                self.remoteNodes[id] = node.childNodes.last ?? node
                self.publishNearby()
            }
        }

        /// Art on top, with the surface's own light and grain multiplied through
        /// it — same UVs, so the grain lines up perfectly with the wall.
        private func material(art: UIImage, shade: UIImage?, graze: UIImage?) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = art
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            // NOT .constant. Constant shading renders every triangle identically,
            // so a decal draped over a corner looks exactly like a flat one —
            // the wrap is there but invisible. .blinn responds to the ARKit light
            // estimate, which is what makes a corner read as a corner. (.blinn
            // and not .physicallyBased: `multiply` is broken under PBR.)
            material.lightingModel = .blinn
            material.ambient.contents = UIColor.white
            material.specular.contents = UIColor(white: 0.16, alpha: 1)
            material.shininess = 0.3
            material.isDoubleSided = true
            material.writesToDepthBuffer = false

            if let shade, let luminance = SurfaceTexture.luminance(of: shade) {
                // Soft-light through the wall rather than plain multiply, so the
                // surface can lighten the paint as well as darken it — a bare
                // multiply can only ever darken, which caps how integrated the
                // paint can look. The same map also thins the coat slightly
                // where the wall is dark; relief comes from the normal map below.
                if Self.aerosolShaderCompiles {
                    material.shaderModifiers = [.surface: Self.aerosolShader]
                    material.setValue(SCNMaterialProperty(contents: luminance), forKey: "wallTex")
                    // A colour binds as a 1x1 texture: every surface square to the
                    // can, which is what a flat quad gets and what a missing map
                    // falls back to.
                    material.setValue(
                        SCNMaterialProperty(contents: graze ?? UIColor.white),
                        forKey: "grazeTex"
                    )
                    material.setValue(Float(1), forKey: "wallCap")
                } else {
                    material.multiply.contents = luminance
                }
                Self.bakeSurface(shade, into: material)
            }
            return material
        }

        /// Reads the wall once — its grain and how much light reaches it — and
        /// hands both to the material. Both are the expensive kind of CoreImage
        /// work, so they land a beat late rather than stalling the tap that
        /// placed the piece; the 0.3 s fade-in covers the gap. Until then the
        /// paint renders uncapped and flat, which is exactly the old look.
        private static func bakeSurface(_ shade: UIImage, into material: SCNMaterial) {
            Task.detached(priority: .userInitiated) {
                let grain = SurfaceTexture.normalMap(of: shade)
                // Paint cannot out-shine the light falling on the wall. A dark or
                // unreadable wall dulls the art down to the floor, never to black.
                let cap = SurfaceTexture.averageLuminance(of: shade).map {
                    min(1, max(Float($0), Aerosol.wallLumaFloor) * Aerosol.capHeadroom)
                }
                await MainActor.run {
                    if let grain {
                        material.normal.contents = grain
                        material.normal.intensity = Aerosol.bump
                    }
                    if let cap { material.setValue(cap, forKey: "wallCap") }
                }
            }
        }

        /// SceneKit gives no callback when a shader modifier fails to compile —
        /// it just logs and renders the material wrong, mid-demo. Prove the body
        /// compiles on this device once; otherwise use the plain multiply blend.
        private static let aerosolShaderCompiles: Bool = {
            let split = aerosolShader.components(separatedBy: "#pragma body")
            let declared = split.first?.components(separatedBy: "#pragma declaration") ?? []
            guard let device = MTLCreateSystemDefaultDevice(),
                  split.count == 2, declared.count == 2 else { return false }
            // SceneKit emits the declaration block at global scope, so the probe
            // has to as well — otherwise `gotNoise` is undefined here, the probe
            // fails, and every device silently drops to the plain multiply.
            let harness = """
            #include <metal_stdlib>
            using namespace metal;
            \(declared[1].replacingOccurrences(of: "#pragma transparent", with: ""))
            struct GotSurface { float4 diffuse; float2 diffuseTexcoord; float3 normal; };
            static void gotBody(thread GotSurface &_surface,
                                texture2d<float, access::sample> wallTex,
                                texture2d<float, access::sample> grazeTex,
                                float wallCap) {
            \(split[1])
            }
            """
            return (try? device.makeLibrary(source: harness, options: nil)) != nil
        }()

        /// Blends the art into the wall it is projected onto. Runs per fragment
        /// with the decal's own projected UVs, so the wall sample under any
        /// point of the art is exactly the wall behind it.
        /// Relief is deliberately absent: `material.normal` carries a Sobel map of
        /// the same wall, which SceneKit has already folded into `_surface.normal`
        /// on a tangent frame it derives itself. The two-tap luminance gradient
        /// this pass used to run was the same idea done worse, and would stack.
        private static let aerosolShader = """
        #pragma arguments
        texture2d<float, access::sample> wallTex;
        texture2d<float, access::sample> grazeTex;
        float wallCap;

        #pragma declaration
        static float gotNoise(float2 p) {
            const float2 seed = float2(127.1, 311.7);
            float2 i = floor(p);
            float2 f = smoothstep(float2(0.0), float2(1.0), fract(p));
            float4 h = fract(sin(float4(
                dot(i, seed), dot(i + float2(1.0, 0.0), seed),
                dot(i + float2(0.0, 1.0), seed), dot(i + float2(1.0, 1.0), seed)
            )) * 43758.5453);
            return mix(mix(h.x, h.y, f.x), mix(h.z, h.w, f.x), f.y);
        }

        #pragma transparent
        #pragma body

        // Most of a decal's area is unpainted mask; none of the below can make it
        // visible, and depth writes are already off so there is no early-Z to lose.
        if (_surface.diffuse.a < 0.002) { discard_fragment(); }

        constexpr sampler wallSampler(coord::normalized, filter::linear, address::clamp_to_edge);
        float2 uv = _surface.diffuseTexcoord;
        float3 wall = wallTex.sample(wallSampler, uv).rgb;
        float3 art = _surface.diffuse.rgb;
        const float3 luma = float3(0.299, 0.587, 0.114);

        // Pegtop soft light.
        float3 blended = (1.0 - 2.0 * wall) * art * art + 2.0 * wall * art;
        float3 paint = mix(art, blended, \(Aerosol.wallStrength));

        // Desaturating toward grey is luma-preserving, so `grey` is also the peak
        // to cap: paint cannot out-shine the light falling on the wall.
        float grey = dot(paint, luma);
        paint = mix(float3(grey), paint, 1.0 - \(Aerosol.desaturate));
        _surface.diffuse.rgb = saturate(paint * min(1.0, wallCap / max(grey, 1e-3)));

        // Never fully opaque, and it covers a dark rough patch less well than
        // smooth bright plaster.
        float l = dot(wall, luma);
        float alpha = _surface.diffuse.a * \(Aerosol.paintOpacity) * mix(0.93, 1.0, l);

        // Dissolve the softened boundary, so the outline reads as droplets rather
        // than a cut line. Multiplied, never replaced: a solid interior sits above
        // edgeHigh and comes through untouched.
        float bite = (gotNoise(uv * \(Aerosol.edgeNoiseScale)) - 0.5) * \(Aerosol.edgeBite);
        alpha *= smoothstep(\(Aerosol.edgeLow) + bite, \(Aerosol.edgeHigh) + bite, _surface.diffuse.a);

        // Thinner where the wall turned away from the can, and a slow wander so
        // coverage reads hand-sprayed.
        alpha *= mix(1.0 - \(Aerosol.graze), 1.0, grazeTex.sample(wallSampler, uv).r);
        alpha *= mix(1.0 - \(Aerosol.coats), 1.0, gotNoise(uv * \(Aerosol.coatNoiseScale)));
        _surface.diffuse.a = saturate(alpha);
        """

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
            let sized = simd_float4x4(columns: (
                placement.columns.0 * scale,
                placement.columns.1 * scale,
                placement.columns.2 * scale,
                simd_float4(position, 1)
            ))
            // lat/lng carries the position for the geo path, so its copy of the
            // matrix has none. The marker copy keeps it: that is the whole point
            // — a position measured off the poster instead of off the GPS.
            var stored = sized
            stored.columns.3 = simd_float4(0, 0, 0, 1)

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
                placementTransform: flatten(stored),
                markerTransform: ImageMarkerOrigin.local(of: sized).map(flatten)
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
            lastRemotePieces = pieces
            for piece in pieces { knownImagePaths[piece.id] = piece.imagePath }
            let wanted = Set(pieces.map(\.id))
            for (id, node) in remoteNodes where !wanted.contains(id) && !anchoredPieceIDs.contains(id) {
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
                dressedIDs.remove(id)
                dressAttempts.removeValue(forKey: id)
            }
            renderedRemoteIDs.formIntersection(wanted.union(anchoredPieceIDs))
            // Anchored pieces ride their world-map anchors at the exact painted
            // spot; the GPS path must not spawn a second, guessed copy.
            for piece in pieces where !renderedRemoteIDs.contains(piece.id) && !anchoredPieceIDs.contains(piece.id) {
                renderedRemoteIDs.insert(piece.id)
                addRemoteNode(for: piece, scnView: scnView)
            }
        }

        private func addRemoteNode(for piece: RemotePiece, scnView: ARSCNView) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let generation = self.sceneGeneration
                // A piece painted off the poster needs no fix at all — which is
                // the whole point indoors, where a usable one never arrives.
                let byMarker = piece.markerTransform != nil && ImageMarkerOrigin.isLocked
                // Cheap gates first — don't download an image we can't place.
                guard scnView.session.currentFrame != nil,
                      byMarker || LocationService.shared.location.map(self.isUsableFix) == true else {
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

                // The scene was torn down while we downloaded — the world origin
                // moved, or the user started over. Whatever we computed is stale,
                // and the poll loop has already queued a replacement.
                guard generation == self.sceneGeneration else { return }
                // attachAnchoredPiece may have claimed this piece while the
                // image downloaded; a second GPS copy would overwrite its
                // remoteNodes entry and never be removed.
                guard !self.anchoredPieceIDs.contains(piece.id) else { return }
                guard let frame = scnView.session.currentFrame else {
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }
                let camPos = simd_make_float3(frame.camera.transform.columns.3)

                let node = SCNNode(geometry: SCNPlane(width: 0.3, height: 0.3))
                node.geometry?.materials = [self.remoteMaterial(image: image)]

                // Measured off the same physical poster the painter used: exact,
                // and nothing here may second-guess it afterwards.
                if let world = piece.markerTransform.flatMap(unflatten).flatMap(ImageMarkerOrigin.world(of:)) {
                    node.simdTransform = world
                    self.snappedIDs.insert(piece.id)
                    self.remoteScale[piece.id] = simd_length(simd_make_float3(world.columns.0))
                    self.applyVisibility(to: node, id: piece.id, snapped: true, camPos: camPos)
                    // Exact to a few centimetres — which is inside the LiDAR
                    // mesh's own error, so depth-testing it is a coin flip on
                    // whether the wall swallows it. Nothing here is allowed to
                    // reposition the piece, so draw it through instead.
                    node.geometry?.firstMaterial?.readsFromDepthBuffer = false
                    node.renderingOrder = 5
                    scnView.scene.rootNode.addChildNode(node)
                    self.remoteNodes[piece.id] = node
                    self.publishNearby()
                    return
                }

                guard let loc = LocationService.shared.location, self.isUsableFix(loc) else {
                    self.renderedRemoteIDs.remove(piece.id)
                    return
                }
                let position = self.worldPosition(for: piece, from: loc, cameraPos: camPos)
                let stored = piece.placementTransform.flatMap(unflatten)
                let rotation = stored ?? matrix_identity_float4x4

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
            // World position: anchored pieces live on a child node whose local
            // position is zero.
            let distances = remoteNodes.values.map { node -> Float in
                guard let camPos else { return .greatestFiniteMagnitude }
                return simd_distance(node.simdWorldPosition, camPos)
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

        /// A remote piece arrives as bare artwork — the painter's wall sample was
        /// never uploaded — so a visitor used to get a flat quad where the
        /// painter got wall-integrated paint. But the visitor is standing at that
        /// wall. Sample it from here and run the identical treatment.
        ///
        /// Only pieces glued to a real surface qualify: an unsnapped piece is
        /// deliberately a floating map marker, and wall grain on something
        /// hovering in mid-air reads worse than leaving it flat.
        private func maybeDressRemotePieces() {
            guard Date().timeIntervalSince(lastDress) > 2, let scnView,
                  let frame = scnView.session.currentFrame else { return }
            let viewport = scnView.bounds.size
            guard viewport.width > 0, viewport.height > 0 else { return }
            let orientation = scnView.window?.windowScene?.effectiveGeometry
                .interfaceOrientation ?? .portrait

            var jobs: [(id: Int, corners: SurfaceTexture.Corners)] = []
            for (id, node) in remoteNodes
            where !dressedIDs.contains(id) && dressAttempts[id, default: 0] < 6 {
                guard snappedIDs.contains(id) || anchoredPieceIDs.contains(id),
                      let corners = screenQuad(
                          of: node, camera: frame.camera,
                          viewport: viewport, orientation: orientation
                      ) else { continue }
                dressAttempts[id, default: 0] += 1
                jobs.append((id, corners))
                if jobs.count == 3 { break }
            }
            guard !jobs.isEmpty else { return }
            lastDress = Date()

            // One snapshot serves the whole pass. Painted content is hidden for
            // it, or a piece samples its own art as the wall behind itself.
            let painted = placedNodes + Array(remoteNodes.values)
            for node in painted { node.isHidden = true }
            let photo = scnView.snapshot()
            for node in painted { node.isHidden = false }

            for job in jobs { dress(id: job.id, photo: photo, corners: job.corners) }
        }

        /// Warps the wall out of the snapshot and rebuilds the piece's material
        /// with it. Off the main actor, because it is the same CoreImage work the
        /// placement path defers; the piece stays flat until it lands.
        private func dress(id: Int, photo: UIImage, corners: SurfaceTexture.Corners) {
            guard let art = remoteNodes[id]?.geometry?.firstMaterial?.diffuse.contents as? UIImage
            else { return }
            // Claim it up front so the next pass, two seconds from now, does not
            // start a second warp for the same piece while this one is in flight.
            dressedIDs.insert(id)
            Task.detached(priority: .utility) { [weak self] in
                guard let wall = SurfaceTexture.rectified(photo, to: corners) else {
                    await MainActor.run { self?.dressedIDs.remove(id) }
                    return
                }
                await MainActor.run {
                    guard let self, let node = self.remoteNodes[id],
                          let old = node.geometry?.firstMaterial else { return }
                    let dressed = self.material(art: art, shade: wall, graze: nil)
                    // The remote paths own depth behaviour — a marker renders
                    // through geometry, a snapped piece occludes — so carry the
                    // current settings across rather than taking the painter's.
                    dressed.readsFromDepthBuffer = old.readsFromDepthBuffer
                    dressed.writesToDepthBuffer = old.writesToDepthBuffer
                    node.geometry?.materials = [dressed]
                    self.dressedIDs.insert(id)
                }
            }
        }

        /// The piece's quad in unit viewport coordinates, or nil when it is not
        /// squarely enough in view for the wall behind it to be worth sampling.
        private func screenQuad(
            of node: SCNNode,
            camera: ARCamera,
            viewport: CGSize,
            orientation: UIInterfaceOrientation
        ) -> SurfaceTexture.Corners? {
            // Read the half-extents off the geometry: the GPS path uses a 0.3 m
            // quad scaled by the node, the anchored path a pre-sized one.
            guard let plane = node.geometry as? SCNPlane else { return nil }
            let hw = plane.width / 2, hh = plane.height / 2
            // SCNPlane's texture origin is its local top-left, verified.
            let local = [
                SCNVector3(-hw, hh, 0), SCNVector3(hw, hh, 0),
                SCNVector3(-hw, -hh, 0), SCNVector3(hw, -hh, 0),
            ]
            let camPos = simd_make_float3(camera.transform.columns.3)
            let forward = -simd_make_float3(camera.transform.columns.2)

            var unit: [CGPoint] = []
            for corner in local {
                let world = simd_float3(node.convertPosition(corner, to: nil))
                // A point behind the lens projects to a mirrored point, not a miss.
                guard simd_dot(world - camPos, forward) > 0.2 else { return nil }
                let p = camera.projectPoint(world, orientation: orientation, viewportSize: viewport)
                guard p.x.isFinite, p.y.isFinite else { return nil }
                let u = p.x / viewport.width, v = p.y / viewport.height
                // Slightly off-screen is fine; mostly off-screen has no wall in
                // the snapshot to sample.
                guard u > -0.15, u < 1.15, v > -0.15, v < 1.15 else { return nil }
                unit.append(CGPoint(x: u, y: v))
            }
            // Too small on screen and there is no grain left to resolve.
            let width = hypot(unit[1].x - unit[0].x, unit[1].y - unit[0].y)
            let height = hypot(unit[2].x - unit[0].x, unit[2].y - unit[0].y)
            guard min(width, height) > 0.12 else { return nil }

            return SurfaceTexture.Corners(
                topLeft: unit[0], topRight: unit[1],
                bottomLeft: unit[2], bottomRight: unit[3]
            )
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
