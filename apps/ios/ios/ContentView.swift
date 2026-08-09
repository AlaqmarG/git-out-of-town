import ARKit
import CoreLocation
import SwiftUI

/// The camera screen: point, shoot, paint, post. One decision at a time.
struct ContentView: View {
    var isActive: Bool = true
    @Binding var tab: AppTab
    var onHelp: () -> Void = {}

    @State private var ar = ARController()
    @State private var stickers: [Sticker] = []
    @State private var remotePieces: [RemotePiece] = []
    @State private var ownPieceIDs: Set<Int> = []

    @State private var captured: CapturedScene?
    @State private var pendingPost: PendingPost?
    @State private var posting = false
    @State private var hint: String?
    @State private var successToast: String?
    @State private var piecesPosted = 0
    @State private var showDebug = false
    @State private var shutterFlash = false

    /// Computed, not stored: a stored private property would make the
    /// memberwise initializer private too.
    private var permissions: Permissions { .shared }

    struct PendingPost {
        let snapshot: PlacementSnapshot
        let artPNG: Data
        let scenePreview: UIImage
        let sceneJPEG: Data?
        let stickerIDs: [String]
    }

    /// Stable per-install id. Resolved once, not on every view rebuild — this
    /// used to hit UserDefaults on the main thread for each re-render.
    private static let sessionId: String = {
        let key = "got.sessionId"
        if let existing = UserDefaults.standard.string(forKey: key), existing.count >= 8 { return existing }
        let id = "ios-" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(24)
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    var body: some View {
        Group {
            if !ARWorldTrackingConfiguration.isSupported {
                BlockerView(
                    symbol: "arkit",
                    title: "AR isn't available here",
                    message: "This device can't run AR. Use Around You to see what everyone else has painted."
                )
            } else if permissions.camera == .authorized {
                camera
            } else {
                cameraBlocker
            }
        }
        .task {
            // We ask, rather than letting ARKit ask when it starts the session,
            // so a denial lands somewhere we can explain and recover from.
            if permissions.camera == .notDetermined { await permissions.requestCamera() }
        }
    }

    private var cameraBlocker: some View {
        BlockerView(
            symbol: "camera.fill",
            title: "Camera access is off",
            message: "Painting means looking at a real wall through the camera. Nothing is recorded — only the photo you choose to paint on.",
            actionTitle: permissions.camera == .notDetermined ? nil : "Open Settings",
            action: Permissions.openSettings
        )
    }

    private var camera: some View {
        ZStack {
            ARPaintView(
                controller: ar,
                showDebug: showDebug,
                isActive: isActive && captured == nil,
                remotePieces: remotePieces
            )
            .ignoresSafeArea()

            vignette.ignoresSafeArea().allowsHitTesting(false)

            if shutterFlash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            VStack(spacing: 12) {
                topBar
                Spacer(minLength: 40)

                if let failure = ar.failure {
                    // Recoverable, not a wall: if this ever fires spuriously the
                    // user is one tap from a working camera either way.
                    Toast(message: failure, symbol: "exclamationmark.triangle.fill", tint: .red) {
                        haptic(.rigid)
                        if permissions.camera == .authorized { ar.restart() } else { Permissions.openSettings() }
                    }
                } else if permissions.locationDenied {
                    Toast(message: "Location is off — pieces can't be pinned", symbol: "location.slash.fill", tint: .red) {
                        Permissions.openSettings()
                    }
                }
                if let hint {
                    Toast(message: hint, symbol: "exclamationmark.triangle.fill", tint: .red)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let successToast {
                    Toast(message: successToast, symbol: "checkmark.seal.fill", tint: .green) {
                        tab = .map
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let pendingPost {
                    postCard(pendingPost)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    shutterBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .safeAreaPadding(.horizontal, 16)
            .safeAreaPadding(.top, 8)
            .safeAreaPadding(.bottom, 12)
            // A camera HUD has nowhere to reflow to; past this the controls eat
            // the viewfinder. The tutorial and the map carry no such cap.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .animation(.snappy, value: pendingPost == nil)
        .fullScreenCover(item: $captured) { scene in
            PhotoPaintView(
                scene: scene,
                stickers: stickers,
                onPlace: { overlay, ids in place(overlay: overlay, ids: ids, scene: scene) },
                onCancel: { captured = nil }
            )
        }
        .task { stickers = StickerCatalog.load() }
        .task(id: isActive) { if isActive { await loadLoop() } }
        .onChange(of: hint) { _, value in autoDismiss(value) { hint = nil } }
        .onChange(of: successToast) { _, value in autoDismiss(value) { successToast = nil } }
    }

    // MARK: - Chrome

    private var vignette: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 170)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    haptic()
                    onHelp()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("How this works")

                Spacer(minLength: 0)

                if piecesPosted > 0 {
                    Label("\(piecesPosted)", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityLabel("\(piecesPosted) piece\(piecesPosted == 1 ? "" : "s") posted")
                }
            }

            // Long-press, not a button: the tracking readout is for us, and a
            // stranger tapping it by accident just sees jargon.
            Label(ar.status, systemImage: ar.isReady ? "checkmark.circle.fill" : "camera.metering.center.weighted")
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .foregroundStyle(ar.isReady ? Color.spray : .primary)
                .animation(.easeInOut, value: ar.isReady)
                .onLongPressGesture {
                    haptic(.rigid)
                    showDebug.toggle()
                }
                .accessibilityHint("Long press to show tracking diagnostics")

            if showDebug {
                Text(debugLine)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
            }
        }
    }

    private var debugLine: String {
        let accuracy = LocationService.shared.location?.horizontalAccuracy ?? -1
        let nearest = ar.nearestM.map { String(format: "%.0fm", $0) } ?? "—"
        return """
        fetched \(ar.fetched) · in world \(ar.rendered) · snapped \(ar.snapped) · nearest \(nearest)
        gps ±\(accuracy < 0 ? "?" : String(format: "%.0f", accuracy))m · last: \(ar.lastPlacement)
        """
    }

    private var shutterBar: some View {
        VStack(spacing: 16) {
            Label(
                ar.isReady ? "Take a photo of the spot" : "Pan slowly to scan the surface",
                systemImage: ar.isReady ? "camera.fill" : "arrow.left.and.right"
            )
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .animation(.easeInOut, value: ar.isReady)

            Button {
                shoot()
            } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.9), lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(Color.spray).frame(width: 62, height: 62)
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.black)
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .scaleEffect(ar.isReady ? 1 : 0.92)
            .opacity(ar.isReady ? 1 : 0.55)
            .animation(.bouncy, value: ar.isReady)
            .accessibilityLabel("Take a photo to paint on")
        }
    }

    private func postCard(_ pending: PendingPost) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(uiImage: pending.scenePreview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Preview of what you painted")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add it to the collage?")
                        .font(.headline)
                    Text(subtitle(pending))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    haptic(.rigid)
                    ar.discardLast()
                    withAnimation(.snappy) { pendingPost = nil }
                } label: {
                    Label("Discard", systemImage: "trash")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.glass)
                .disabled(posting)

                Button {
                    haptic(.medium)
                    post(pending)
                } label: {
                    Group {
                        if posting {
                            ProgressView().tint(.black)
                        } else {
                            Label("Post it", systemImage: "paperplane.fill").fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.spray)
                .foregroundStyle(.black)
                .disabled(posting)
                .accessibilityLabel(posting ? "Posting" : "Post it")
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func subtitle(_ pending: PendingPost) -> String {
        let place = pending.snapshot.surfaceType.map { "Sprayed on a \($0)" } ?? "Sprayed right here"
        return "\(place) — posting pins it to this spot for everyone, forever."
    }

    // MARK: - Flow

    private func shoot() {
        // A second tap while the editor is animating in would swap the item out
        // from under an already-presenting cover, which SwiftUI drops silently.
        guard captured == nil, pendingPost == nil else { return }
        guard let scene = ar.capture() else {
            withAnimation(.snappy) { hint = "Hold steady a moment longer" }
            return
        }
        haptic(.medium)
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeIn(duration: 0.18)) { shutterFlash = false }
        }
        captured = scene
    }

    /// Returns a message if the art could not be pinned — the editor stays open
    /// on failure so half a minute of painting is never thrown away.
    private func place(overlay: UIImage, ids: [String], scene: CapturedScene) -> String? {
        // Checked before placing, not after: the placer drops the art into the
        // world first and only then discovers it has no fix to pin it with.
        guard LocationService.shared.location != nil else {
            return permissions.locationDenied
                ? "Location is off — turn it on in Settings to pin this"
                : "Waiting for a GPS fix — hold on a moment and spray again"
        }
        guard let snapshot = ar.place(overlay: overlay, scene: scene) else {
            return "Couldn't find the wall — tap Retake and get a little closer"
        }
        captured = nil
        let preview = composite(photo: scene.photo, overlay: overlay)
        withAnimation(.snappy) {
            pendingPost = PendingPost(
                snapshot: snapshot,
                artPNG: artwork(from: overlay),
                scenePreview: preview,
                sceneJPEG: preview.jpegData(compressionQuality: 0.8),
                stickerIDs: ids
            )
        }
        return nil
    }

    /// What the world sees on the map: the photo with the paint burned in.
    private func composite(photo: UIImage, overlay: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        return UIGraphicsImageRenderer(size: photo.size, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: photo.size))
            overlay.draw(in: CGRect(origin: .zero, size: photo.size))
        }
    }

    /// The bare artwork, trimmed to what was painted.
    private func artwork(from overlay: UIImage) -> Data {
        guard let cg = overlay.cgImage,
              let bounds = PaintMask(overlay: overlay)?.bounds else {
            return overlay.pngData() ?? Data()
        }
        let rect = CGRect(
            x: bounds.minX * CGFloat(cg.width),
            y: bounds.minY * CGFloat(cg.height),
            width: bounds.width * CGFloat(cg.width),
            height: bounds.height * CGFloat(cg.height)
        ).integral
        guard let cropped = cg.cropping(to: rect) else { return overlay.pngData() ?? Data() }
        return UIImage(cgImage: cropped).pngData() ?? Data()
    }

    private func post(_ pending: PendingPost) {
        posting = true
        let snapshot = pending.snapshot
        let meta = MetaDTO(
            lat: snapshot.lat,
            lng: snapshot.lng,
            heading: snapshot.heading,
            accuracyM: snapshot.accuracyM,
            kind: pending.stickerIDs.isEmpty ? "spray" : "sticker",
            stickerId: pending.stickerIDs.first,
            sessionId: Self.sessionId,
            client: "ios",
            surfaceType: snapshot.surfaceType,
            distanceM: snapshot.distanceM,
            devicePitch: snapshot.devicePitch,
            usedGeoAnchor: snapshot.usedGeoAnchor,
            hasLidar: snapshot.hasLidar,
            // Indoors CoreLocation hands back altitudes far outside the server's
            // accepted range, which 400s the whole upload. It's a nice-to-have
            // field, so drop it rather than lose the piece.
            altitudeM: snapshot.altitudeM.flatMap { (-500...9999).contains($0) ? $0 : nil },
            placementTransform: snapshot.placementTransform
        )
        Task {
            do {
                let piece = try await APIClient.uploadPiece(
                    imagePNG: pending.artPNG,
                    sceneData: pending.sceneJPEG,
                    meta: meta
                )
                await MainActor.run {
                    // Ours is already on the wall as a local node; re-rendering
                    // the server's copy from a GPS estimate would double it up.
                    _ = ownPieceIDs.insert(piece.id)
                    remotePieces.removeAll { $0.id == piece.id }
                    posting = false
                    withAnimation(.snappy) {
                        pendingPost = nil
                        piecesPosted += 1
                        successToast = "On the map — tap to see it"
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                // The card stays up, so Post is simply retryable. A 4xx is the
                // one case retrying won't fix — don't send them to check wifi.
                let rejected = if case APIError.badStatus(let code) = error { (400..<500).contains(code) } else { false }
                await MainActor.run {
                    posting = false
                    withAnimation(.snappy) {
                        hint = rejected
                            ? "The wall wouldn't take this one — retake and try again"
                            : "Couldn't post — check your connection and try again"
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    // MARK: - Load

    private func loadLoop() async {
        while !Task.isCancelled {
            if let loc = LocationService.shared.location,
               loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 {
                if let pieces = try? await APIClient.listPieces(
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude,
                    radiusMeters: 300
                ) {
                    ar.fetched = pieces.count
                    let next = pieces
                        .filter { !ownPieceIDs.contains($0.id) }
                        .map {
                            RemotePiece(
                                id: $0.id,
                                imagePath: $0.finalImagePath ?? $0.rawImagePath,
                                lat: $0.lat,
                                lng: $0.lng,
                                altitudeM: $0.altitudeM,
                                surfaceType: $0.surfaceType,
                                placementTransform: $0.placementTransform
                            )
                        }
                    // Every assignment rebuilds the AR view; only do it when the
                    // set actually changed.
                    if next.map(\.id) != remotePieces.map(\.id) { remotePieces = next }
                }
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func autoDismiss(_ value: String?, clear: @escaping () -> Void) {
        guard value != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut) { clear() }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

struct Toast: View {
    let message: String
    let symbol: String
    let tint: Color
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        Label(message, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .glassEffect(
                .regular.tint(tint.opacity(0.7)),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
    }
}
