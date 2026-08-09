import ARKit
import SwiftUI

/// Apple's recommended relocalization aid: a still of the scene shot from where
/// the painter stood, saved alongside the ARWorldMap. Shown ghosted over a
/// viewer's live camera it turns a blind feature search into "stand here, point
/// that way" — which is the difference between matching in seconds and never.
struct PlacementGuide {
    /// Already encoded, so it can cross to a background task without dragging a
    /// UIImage (and its backing bitmap) along with it.
    let jpeg: Data
    /// Camera pose the still was shot from — 16 floats, COLUMN-major, the same
    /// `flatten()` order as `placementTransform`.
    let transform: [Double]

    /// Longest side, in pixels. The map it rides with is already megabytes and
    /// the server caps this at 512 KB; recognisable is all it has to be.
    nonisolated private static let maxSide: CGFloat = 640

    /// Grabs the live AR view. Main actor only, and worth calling before
    /// `getCurrentWorldMap` hands off to the session queue. Downscaling and
    /// JPEG encoding are left to `encode` — this runs right after a post, on
    /// the render thread, so it does the one thing that has to happen here.
    @MainActor
    static func capture(from view: ARSCNView) -> (image: UIImage, transform: [Double])? {
        guard let camera = view.session.currentFrame?.camera else { return nil }
        return (view.snapshot(), flatten(camera.transform))
    }

    /// Deliberately off the main actor: a full-size redraw plus a JPEG encode is
    /// the last thing the render loop needs right after a post.
    nonisolated static func encode(_ shot: (image: UIImage, transform: [Double])) -> PlacementGuide? {
        let full = shot.image
        let side = max(full.size.width, full.size.height)
        guard side > 0 else { return nil }

        // Redrawn at scale 1: `snapshot()` hands back a Retina bitmap, nine
        // times the pixels for a picture nobody inspects closely.
        let ratio = min(1, maxSide / side)
        let size = CGSize(
            width: (full.size.width * ratio).rounded(),
            height: (full.size.height * ratio).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            full.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = small.jpegData(compressionQuality: 0.6) else { return nil }
        return PlacementGuide(jpeg: jpeg, transform: shot.transform)
    }
}

/// The painter's view, ghosted over the live camera while we try to match it.
struct PlacementGuideView: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Fit, never fill: the app rotates, so a viewer holding the phone
            // the other way round gets a letterboxed ghost — which reads as
            // "turn your phone" — rather than a stretched lie to match against.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.6)
                // The shutter and the whole HUD sit underneath this.
                .allowsHitTesting(false)

            Button(action: onDismiss) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text("Stand here and match this view")
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 15)
                .frame(minHeight: 44)
                .glassEffect(.regular, in: Capsule())
            }
            .buttonStyle(.plain)
            // Clear of the shutter bar on the shortest phone we support.
            .padding(.bottom, 200)
            .accessibilityLabel("Stand here and match this view. Activate to hide the guide.")
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
