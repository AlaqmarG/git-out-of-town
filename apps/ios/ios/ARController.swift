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

    /// Diagnostics for the debug readout: pieces fetched, placed in the world,
    /// glued to a real surface, and how far the closest one is.
    var fetched = 0
    private(set) var rendered = 0
    private(set) var snapped = 0
    private(set) var nearestM: Double?

    func setStatus(_ status: String, ready: Bool) {
        self.status = status
        isReady = ready
    }

    /// How the last piece landed: draped over N mesh triangles, or flat.
    private(set) var lastPlacement = "—"

    func setLastPlacement(_ text: String) { lastPlacement = text }

    func setNearby(rendered: Int, snapped: Int, nearestM: Double?) {
        self.rendered = rendered
        self.snapped = snapped
        self.nearestM = nearestM
    }

    func capture() -> CapturedScene? { coordinator?.capture() }

    @discardableResult
    func place(overlay: UIImage, scene: CapturedScene) -> PlacementSnapshot? {
        coordinator?.placePainted(overlay: overlay, scene: scene)
    }

    func discardLast() { coordinator?.discardLast() }
    func clearPieces() { coordinator?.clearPieces() }
}
