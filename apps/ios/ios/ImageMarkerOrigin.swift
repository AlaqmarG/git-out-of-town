import ARKit

/// A printed poster used as a shared coordinate origin: two phones that both
/// see it agree on where "zero" is, so a placement one of them paints lands on
/// the same brick for the other. See `docs/marker.md` — the printed size is
/// load-bearing.
///
/// The world origin move is translation only. The session runs
/// `.gravityAndHeading`, and every geo conversion in `ARPaintView` plus every
/// `ARWorldMap` we upload is written against those ENU axes; rotating the world
/// onto the poster's yaw would silently re-frame all of it, including scans
/// already on the server.
///
/// The poster's rotation is still needed, because ENU axes come from the
/// compass and two compasses indoors disagree by degrees — which is tens of
/// centimetres a couple of metres out. So it is kept here and applied only at
/// the wire boundary: `local(of:)` converts a placement into the poster's own
/// frame before it is stored, `world(of:)` converts it back. Both devices
/// measure that frame off the same physical object, so neither compass enters.
@MainActor
enum ImageMarkerOrigin {
    /// Nil when the resource group is missing — which is exactly the value the
    /// session used before this existed, so the detector simply never runs.
    static let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "ARMarkers", bundle: nil)

    /// The poster's pose in the current world frame, once adopted. Nil is the
    /// whole fallback: no poster seen, no marker-relative anything.
    private(set) static var frame: simd_float4x4?

    static var isLocked: Bool { frame != nil }

    /// Moves the world origin onto the poster, once per world frame. Returns
    /// true only on the call that actually moved it — re-setting mid-session
    /// would teleport every node already placed at the old origin.
    static func adopt(_ anchor: ARImageAnchor, in session: ARSession) -> Bool {
        guard !isLocked else { return false }
        var origin = matrix_identity_float4x4
        origin.columns.3 = anchor.transform.columns.3
        // The origin lands on the poster, so in the frame that exists after this
        // call the poster sits at zero and only its rotation is left.
        frame = gravityAligned(anchor.transform)
        session.setWorldOrigin(relativeTransform: origin)
        return true
    }

    /// Call whenever the session is re-run with `.resetTracking`: that throws
    /// the world frame away, so the poster has to be adopted again.
    static func reset() { frame = nil }

    /// A world placement in the poster's frame, for storage. Nil when no poster
    /// has been adopted, which is what keeps `markerTransform` null.
    static func local(of world: simd_float4x4) -> simd_float4x4? {
        frame.map { simd_inverse($0) * world }
    }

    /// The inverse: someone else's marker-relative placement, in our world.
    ///
    /// `marker_transform` is a JSONB column any client can fill, and this one is
    /// trusted absolutely — it bypasses GPS, snapping and every other sanity
    /// check in the render path. So the bounds are enforced here: nothing lives
    /// half a kilometre from a poster you can see, and no piece is 40 m wide.
    static func world(of local: simd_float4x4) -> simd_float4x4? {
        guard let frame else { return nil }
        let offset = simd_make_float3(local.columns.3)
        // The column length is a scale factor against the 0.3 m base quad, not
        // a width — multiply through before comparing it to metres.
        let widthM = simd_length(simd_make_float3(local.columns.0)) * 0.3
        guard simd_length(offset) < 60, widthM > 0.01, widthM < 40 else { return nil }
        return frame * local
    }

    /// Gravity for two of the three axes and the poster only for the yaw.
    /// ARKit's image-anchor rotation is good to a degree or two on every axis,
    /// while the gravity vector is good to a tenth of one — so a poster hanging
    /// roughly plumb is measured far more consistently this way, and the two
    /// devices' frames differ by yaw alone.
    private static func gravityAligned(_ transform: simd_float4x4) -> simd_float4x4 {
        let up = SIMD3<Float>(0, 1, 0)
        // Yaw comes off the image's own width axis (anchor +x), which is
        // horizontal whether the poster is on a wall or flat on a table. Taking
        // it off the outward normal instead would need a "is this poster flat?"
        // branch, and the two branches sit 90° apart — so two phones either side
        // of that threshold would place every shared piece a quarter turn out.
        let width = simd_make_float3(transform.columns.0)
        let right = width - up * simd_dot(width, up)
        // Only a poster rolled onto its side leaves nothing to project.
        guard simd_length(right) > 1e-3 else { return matrix_identity_float4x4 }
        let x = simd_normalize(right)
        return simd_float4x4(columns: (
            simd_float4(x, 0),
            simd_float4(up, 0),
            simd_float4(simd_cross(x, up), 0),
            simd_float4(0, 0, 0, 1)
        ))
    }
}
