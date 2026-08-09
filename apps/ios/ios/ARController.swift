import ARKit
import SwiftUI

/// The frozen moment the user paints on: the still they saw, the pose it was
/// seen from, and the depth-reconstructed geometry in front of them.
struct CapturedScene: Identifiable {
    let id = UUID()
    let photo: UIImage
    let camera: ARCamera
    let viewport: CGSize
    let triangles: [ProjectedDecal.Triangle]
    /// Dense per-pixel depth — the preferred surface source, far finer than the
    /// reconstruction mesh on curved or detailed objects.
    let depth: DepthDecal.Depth?
    let orientation: UIInterfaceOrientation
    let hasLidar: Bool
    /// Screen-space raycast used when there is no mesh to project onto.
    let fallbackPlacement: (transform: simd_float4x4, position: SIMD3<Float>, surfaceType: String)?
    let surfaceType: String?
}

/// Lets SwiftUI drive the AR session directly instead of through change tokens.
@MainActor
@Observable
final class ARController {
    @ObservationIgnored weak var coordinator: ARPaintView.Coordinator?

    private(set) var status = "starting camera…"
    private(set) var hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    private(set) var isReady = false
    /// True when the viewfinder's center is over reconstructed mesh or a
    /// detected plane — i.e. the point under the reticle can hold paint.
    private(set) var isPlaceable = false

    /// Why the session stopped, if it did. A dead session is indistinguishable
    /// from one still warming up — same nil frame, same "starting camera…" —
    /// so without this the screen sits black and the shutter lies forever.
    private(set) var failure: String?
    @ObservationIgnored private var didRetry = false

    /// Diagnostics for the debug readout: pieces fetched, placed in the world,
    /// glued to a real surface, and how far the closest one is.
    var fetched = 0
    private(set) var rendered = 0
    private(set) var snapped = 0
    private(set) var nearestM: Double?

    func setStatus(_ status: String, ready: Bool) {
        self.status = status
        isReady = ready
        if ready {
            failure = nil
            didRetry = false
        }
    }

    func setPlaceable(_ placeable: Bool) {
        guard isPlaceable != placeable else { return }
        isPlaceable = placeable
    }

    /// Call from `ARSessionObserver.session(_:didFailWithError:)`.
    func sessionFailed(_ error: Error) {
        isReady = false
        guard (error as? ARError)?.code != .cameraUnauthorized else {
            failure = "Camera access is off. Turn it on in Settings to paint."
            return
        }
        guard !didRetry else {
            failure = "AR stopped. Restart it, or close and reopen the app."
            return
        }
        // A sensor hiccup usually clears on a fresh run, so try once silently —
        // a banner the user can't act on is worse than a two-second stall.
        didRetry = true
        setStatus("Restarting AR…", ready: false)
        restart()
    }

    /// Call from `ARSessionObserver.sessionInterruptionEnded(_:)`.
    func sessionResumed() {
        failure = nil
        didRetry = false
    }

    /// Pause-then-resume, so the session comes back on the coordinator's own
    /// configuration. Rebuilding it here is how the LiDAR mesh gets lost.
    func restart() {
        failure = nil
        coordinator?.setActive(false)
        coordinator?.setActive(true)
    }

    /// How the last piece landed: draped over N mesh facets, or flat. Shown on
    /// the Post card — if wrapping silently stops working, it says so.
    private(set) var lastPlacement = "—"
    private(set) var lastPlacementWrapped = false

    func setLastPlacement(_ text: String, wrapped: Bool) {
        lastPlacement = text
        lastPlacementWrapped = wrapped
    }

    func setNearby(rendered: Int, snapped: Int, nearestM: Double?) {
        self.rendered = rendered
        self.snapped = snapped
        self.nearestM = nearestM
    }

    /// How well the current spot is scanned: "rough" | "good" | "precise".
    /// Drives the placement-quality chip on the Post card.
    private(set) var scanQuality = "rough"

    func setScanQuality(_ quality: String) {
        guard scanQuality != quality else { return }
        scanQuality = quality
    }

    func capture() -> CapturedScene? { coordinator?.capture() }

    @discardableResult
    func place(overlay: UIImage, scene: CapturedScene) -> PlacementSnapshot? {
        coordinator?.placePainted(overlay: overlay, scene: scene)
    }

    /// Ship the visual scan of this spot so other devices can relocalize
    /// against it. Call after the piece is posted; fire-and-forget.
    func saveScan(pieceId: Int) { coordinator?.saveScan(pieceId: pieceId) }

    func discardLast() { coordinator?.discardLast() }
    func clearPieces() { coordinator?.clearPieces() }
}
