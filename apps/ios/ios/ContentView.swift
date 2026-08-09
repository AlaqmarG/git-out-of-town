import CoreLocation
import SwiftUI

/// The camera screen: point, shoot, paint, post. One decision at a time.
struct ContentView: View {
    var isActive: Bool = true
    var onHelp: () -> Void = {}

    @State private var ar = ARController()
    @State private var stickers: [Sticker] = []
    @State private var sessionId: String
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

    struct PendingPost {
        let snapshot: PlacementSnapshot
        let artPNG: Data
        let scenePreview: UIImage
        let sceneJPEG: Data?
        let stickerIDs: [String]
    }

    private static let accent = Color(red: 1.00, green: 0.84, blue: 0.00)

    init(isActive: Bool = true, onHelp: @escaping () -> Void = {}) {
        self.isActive = isActive
        self.onHelp = onHelp
        let key = "got.sessionId"
        if let existing = UserDefaults.standard.string(forKey: key), existing.count >= 8 {
            _sessionId = State(initialValue: existing)
        } else {
            let id = "ios-" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(24).description
            UserDefaults.standard.set(id, forKey: key)
            _sessionId = State(initialValue: id)
        }
    }

    var body: some View {
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

                if let hint {
                    Toast(message: hint, symbol: "exclamationmark.triangle.fill", tint: .red)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let successToast {
                    Toast(message: successToast, symbol: "checkmark.seal.fill", tint: .green)
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
        .task {
            stickers = StickerCatalog.load()
            LocationService.shared.start()
            await loadLoop()
        }
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
                        .frame(height: 44)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityLabel("\(piecesPosted) piece\(piecesPosted == 1 ? "" : "s") posted")
                }

                Button {
                    haptic()
                    showDebug.toggle()
                } label: {
                    Image(systemName: showDebug ? "viewfinder.circle.fill" : "viewfinder.circle")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(showDebug ? "Hide tracking points" : "Show tracking points")
            }

            Label(ar.status, systemImage: ar.isReady ? "checkmark.circle.fill" : "camera.metering.center.weighted")
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .foregroundStyle(ar.isReady ? Self.accent : .primary)
                .animation(.easeInOut, value: ar.isReady)
        }
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
                    Circle().fill(Self.accent).frame(width: 62, height: 62)
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
                        .frame(height: 48)
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
                    .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Self.accent)
                .foregroundStyle(.black)
                .disabled(posting)
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

    private func place(overlay: UIImage, ids: [String], scene: CapturedScene) {
        captured = nil
        guard let snapshot = ar.place(overlay: overlay, scene: scene) else {
            withAnimation(.snappy) {
                hint = LocationService.shared.location == nil
                    ? "No GPS fix yet — can't pin it here"
                    : "Couldn't find a surface — get closer and retake"
            }
            return
        }
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
            sessionId: sessionId,
            client: "ios",
            surfaceType: snapshot.surfaceType,
            distanceM: snapshot.distanceM,
            devicePitch: snapshot.devicePitch,
            usedGeoAnchor: snapshot.usedGeoAnchor,
            hasLidar: snapshot.hasLidar,
            altitudeM: snapshot.altitudeM,
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
                    _ = ownPieceIDs.insert(piece.id)
                    posting = false
                    withAnimation(.snappy) {
                        pendingPost = nil
                        piecesPosted += 1
                        successToast = "On the map — the world can see it"
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    posting = false
                    withAnimation(.snappy) { hint = "Couldn't post — check connection" }
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
                    remotePieces = pieces
                        .filter { !ownPieceIDs.contains($0.id) && $0.client == "ios" }
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
                }
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func autoDismiss(_ value: String?, clear: @escaping () -> Void) {
        guard value != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut) { clear() }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private struct Toast: View {
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(tint.opacity(0.7)),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
    }
}
