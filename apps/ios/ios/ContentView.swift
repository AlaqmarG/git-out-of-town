import CoreLocation
import PencilKit
import SwiftUI

struct ContentView: View {
    var isActive: Bool = true

    @State private var selectedColor: UIColor = UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
    @State private var piecesPlaced = 0
    @State private var lastSurface = "none yet"
    @State private var clearToken = 0
    @State private var status = "starting camera…"
    @State private var hint: String?
    @State private var successToast: String?
    @State private var showDebug = false

    @State private var showDrawer = false
    @State private var draftDrawing = PKDrawing()
    @State private var drawerClearToken = 0
    @State private var currentDrawing: PKDrawing?
    @State private var drawingImage: UIImage?
    @State private var drawingPNG: Data?
    @State private var selectedStickerID: String?
    @State private var stickers: [Sticker] = []

    @State private var sessionId: String
    @State private var remotePieces: [RemotePiece] = []
    @State private var ownPieceIDs: Set<Int> = []

    @State private var isPreviewing = false
    @State private var previewSize: Float = 0.3
    @State private var placeToken = 0
    @State private var cancelToken = 0
    @State private var discardToken = 0

    @State private var awaitingSnapshot = false
    @State private var pendingPost: PendingPost?
    @State private var posting = false

    struct PendingPost {
        let snapshot: PlacementSnapshot
        let imagePNG: Data
        let sceneImage: UIImage?
    }

    private let palette: [UIColor] = [
        UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1), // yellow
        UIColor(red: 1.00, green: 0.00, blue: 0.50, alpha: 1), // pink
        UIColor(red: 0.00, green: 0.87, blue: 1.00, alpha: 1), // cyan
        UIColor(red: 0.00, green: 0.90, blue: 0.35, alpha: 1), // green
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1), // white
    ]

    init(isActive: Bool = true) {
        self.isActive = isActive
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
                color: selectedColor,
                clearToken: clearToken,
                showDebug: showDebug,
                isActive: isActive,
                locked: pendingPost != nil || awaitingSnapshot,
                drawingImage: drawingImage,
                remotePieces: remotePieces,
                previewSize: previewSize,
                placeToken: placeToken,
                cancelToken: cancelToken,
                discardToken: discardToken,
                onPlace: { classification in
                    Task { @MainActor in
                        lastSurface = classification
                    }
                },
                onPiecePlaced: { snapshot in
                    Task { @MainActor in
                        let png = drawingPNG ?? coloredSquarePNG(color: selectedColor)
                        withAnimation(.snappy) {
                            awaitingSnapshot = false
                            pendingPost = PendingPost(
                                snapshot: snapshot,
                                imagePNG: png,
                                sceneImage: snapshot.sceneData.flatMap(UIImage.init(data:))
                            )
                        }
                    }
                },
                onStatus: { status = $0 },
                onHint: { newHint in
                    Task { @MainActor in
                        withAnimation(.snappy) { hint = newHint }
                    }
                },
                onPreviewState: { previewing in
                    Task { @MainActor in
                        withAnimation(.snappy) { isPreviewing = previewing }
                    }
                }
            )
            .ignoresSafeArea()

            cameraVignette
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if !isPreviewing && pendingPost == nil {
                TargetReticle()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            VStack(spacing: 12) {
                topControls
                Spacer(minLength: 80)

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
                } else if awaitingSnapshot {
                    capturingCard
                        .transition(.opacity)
                } else if isPreviewing {
                    previewControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    creationControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .safeAreaPadding(.horizontal, 16)
            .safeAreaPadding(.top, 8)
            .safeAreaPadding(.bottom, 12)
        }
        .animation(.snappy, value: isPreviewing)
        .animation(.snappy, value: pendingPost == nil)
        .sheet(isPresented: $showDrawer) {
            drawingSheet
        }
        .task {
            stickers = StickerCatalog.load()
            LocationService.shared.start()
            await loadLoop()
        }
        .onChange(of: hint) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if hint == newValue {
                    withAnimation(.easeOut) { hint = nil }
                }
            }
        }
        .onChange(of: successToast) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if successToast == newValue {
                    withAnimation(.easeOut) { successToast = nil }
                }
            }
        }
    }

    private var cameraVignette: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.48), .black.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 190)
            Spacer()
            LinearGradient(
                colors: [.clear, .black.opacity(0.08), .black.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)
        }
    }

    private var topControls: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Label {
                        Text("Out of Town")
                            .font(.headline.weight(.semibold))
                    } icon: {
                        Image(systemName: "paintbrush.pointed.fill")
                            .foregroundStyle(Color(selectedColor))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect(.regular, in: Capsule())

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(lastSurface == "none yet" ? "\(piecesPlaced)" : "\(piecesPlaced) · \(lastSurface)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .glassEffect(.regular, in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(piecesPlaced) piece\(piecesPlaced == 1 ? "" : "s") posted. Last surface: \(lastSurface)")

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
            }

            Label(status, systemImage: statusSymbol)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .accessibilityLabel("AR status: \(status)")
        }
    }

    private var guide: (symbol: String, text: String) {
        if status.contains("scanning") || status.contains("initializing") {
            return ("camera.metering.center.weighted", "Slowly pan to find surfaces")
        }
        if drawingImage == nil && piecesPlaced == 0 {
            return ("scribble.variable", "Pick a color, or draw your own piece")
        }
        return ("hand.tap.fill", "Tap a wall to place it")
    }

    private var creationControls: some View {
        VStack(spacing: 10) {
            Label(guide.text, systemImage: guide.symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: Capsule())
                .contentTransition(.opacity)
                .animation(.easeInOut, value: guide.text)

            HStack(spacing: 6) {
                if let customImage = drawingImage {
                    let isSticker = selectedStickerID != nil
                    Button {
                        if !isSticker { openDrawingCanvas() }
                    } label: {
                        Image(uiImage: customImage)
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(isSticker ? "Selected sticker" : "Edit custom graffiti")

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isSticker ? "Sticker" : "Custom piece")
                            .font(.subheadline.weight(.semibold))
                        Text(isSticker ? "Tap a surface to place it" : "Tap the preview to edit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Button {
                        haptic()
                        clearArt()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Remove \(isSticker ? "sticker" : "custom graffiti")")
                } else {
                    HStack(spacing: 5) {
                        ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                            Button {
                                haptic()
                                selectedColor = color
                            } label: {
                                ColorSwatch(color: color, isSelected: selectedColor == color)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(index + 1)")
                            .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                        }
                    }

                    Divider()
                        .frame(height: 24)
                        .padding(.horizontal, 2)

                    Button {
                        openDrawingCanvas()
                    } label: {
                        Image(systemName: "scribble.variable")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Draw custom graffiti")
                }

                Button(role: .destructive) {
                    haptic()
                    clearScene()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Clear all pieces from this scene")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

            stickerStrip
        }
    }

    private var stickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stickers) { sticker in
                    Button {
                        haptic()
                        selectSticker(sticker)
                    } label: {
                        StickerThumb(image: sticker.image, isSelected: selectedStickerID == sticker.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sticker \(sticker.name)")
                    .accessibilityAddTraits(selectedStickerID == sticker.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 56)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var previewControls: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready to place")
                        .font(.headline)
                    Text("Adjust the piece on the surface")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(previewSize * 100)) cm")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
            }

            HStack(spacing: 12) {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                Slider(value: $previewSize, in: 0.15...1.0)
                    .tint(Color(selectedColor))
                    .accessibilityLabel("Piece size")
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
            }

            HStack(spacing: 10) {
                Button {
                    haptic()
                    cancelToken += 1
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glass)

                Button {
                    haptic(.medium)
                    placeToken += 1
                    awaitSnapshot()
                } label: {
                    Label("Place", systemImage: "mappin")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(selectedColor))
                .foregroundStyle(.black)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var capturingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Capturing the moment…")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
    }

    private func postCard(_ pending: PendingPost) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                if let scene = pending.sceneImage {
                    Image(uiImage: scene)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add it to the collage?")
                        .font(.headline)
                    Text(postSubtitle(pending))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    haptic(.rigid)
                    discardToken += 1
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
                            Label("Post it", systemImage: "paperplane.fill")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(selectedColor))
                .foregroundStyle(.black)
                .disabled(posting)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func postSubtitle(_ pending: PendingPost) -> String {
        let place = pending.snapshot.surfaceType.map { "Painted on a \($0)" } ?? "Painted right here"
        return "\(place) — posting pins it to this spot for everyone, forever."
    }

    private var drawingSheet: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                DrawingCanvasView(drawing: $draftDrawing, clearToken: drawerClearToken)
                    .background(Color(uiColor: .systemBackground))
                    .ignoresSafeArea(edges: .bottom)

                if draftDrawing.strokes.isEmpty {
                    Label("Draw anywhere", systemImage: "pencil.tip.crop.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDrawer = false }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Clear", role: .destructive) {
                        haptic()
                        drawerClearToken += 1
                    }
                    Button("Done") { commitDrawing() }
                        .fontWeight(.semibold)
                        .disabled(draftDrawing.strokes.isEmpty)
                }
            }
            .navigationTitle("Create a Piece")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationCornerRadius(32)
    }

    private var statusSymbol: String {
        if status.contains("LiDAR") { return "sensor.fill" }
        if status.contains("tracking ✓") { return "checkmark.circle.fill" }
        if status.contains("limited") { return "exclamationmark.triangle.fill" }
        if status.contains("not available") { return "xmark.circle.fill" }
        return "camera.fill"
    }

    private func openDrawingCanvas() {
        haptic()
        draftDrawing = currentDrawing ?? PKDrawing()
        drawerClearToken += 1
        showDrawer = true
    }

    private func clearScene() {
        clearToken += 1
        piecesPlaced = 0
        lastSurface = "none yet"
        remotePieces = []
        pendingPost = nil
        awaitingSnapshot = false
    }

    private func selectSticker(_ sticker: Sticker) {
        if selectedStickerID == sticker.id {
            clearArt()
        } else {
            currentDrawing = nil
            drawingImage = sticker.image
            drawingPNG = sticker.image.pngData()
            selectedStickerID = sticker.id
        }
    }

    private func clearArt() {
        currentDrawing = nil
        drawingImage = nil
        drawingPNG = nil
        selectedStickerID = nil
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// The snapshot arrives ~300 ms after Place (the stamp-in animation runs
    /// first). If it never comes — e.g. no GPS fix — fall back to creating.
    private func awaitSnapshot() {
        withAnimation(.snappy) { awaitingSnapshot = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if pendingPost == nil {
                withAnimation(.snappy) { awaitingSnapshot = false }
            }
        }
    }

    // MARK: - Post

    private func post(_ pending: PendingPost) {
        posting = true
        let snapshot = pending.snapshot
        let meta = MetaDTO(
            lat: snapshot.lat,
            lng: snapshot.lng,
            heading: snapshot.heading,
            accuracyM: snapshot.accuracyM,
            kind: selectedStickerID == nil ? "spray" : "sticker",
            stickerId: selectedStickerID,
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
                    imagePNG: pending.imagePNG,
                    sceneData: snapshot.sceneData,
                    meta: meta
                )
                await MainActor.run {
                    _ = ownPieceIDs.insert(piece.id)
                    posting = false
                    withAnimation(.snappy) {
                        pendingPost = nil
                        piecesPlaced += 1
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

    private func coloredSquarePNG(color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
        let image = renderer.image { _ in
            color.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        return image.pngData() ?? Data()
    }

    // MARK: - Load

    private func loadLoop() async {
        while !Task.isCancelled {
            if let loc = LocationService.shared.location,
               loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 {
                do {
                    let pieces = try await APIClient.listPieces(
                        lat: loc.coordinate.latitude,
                        lng: loc.coordinate.longitude,
                        radiusMeters: 300
                    )
                    let remote = pieces
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
                    await MainActor.run { remotePieces = remote }
                } catch {
                    // Network hiccup; try again next tick.
                }
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - Drawing export

    private func commitDrawing() {
        let drawing = draftDrawing
        guard !drawing.strokes.isEmpty else {
            showDrawer = false
            return
        }

        let bounds = drawing.bounds
        let target: CGFloat = 1024
        let maxDim = max(bounds.width, bounds.height)
        let scale = maxDim > 0 ? target / maxDim : 1
        let image = drawing.image(from: bounds, scale: scale)
        let square = centeredSquare(image: image, side: target)

        drawingPNG = square.pngData()
        drawingImage = square
        currentDrawing = drawing
        selectedStickerID = nil
        showDrawer = false
    }

    private func centeredSquare(image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            let maxDim = max(image.size.width, image.size.height)
            let scale = maxDim > 0 ? side / maxDim : 1
            let width = image.size.width * scale
            let height = image.size.height * scale
            image.draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        }
    }
}

private struct ColorSwatch: View {
    let color: UIColor
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(color))
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1)

            if isSelected {
                Circle()
                    .stroke(.white, lineWidth: 3)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.black.opacity(0.72))
            } else {
                Circle()
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
        }
        .frame(width: 30, height: 30)
        .padding(3)
        .contentShape(Circle())
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

private struct Toast: View {
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.leading)
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

private struct TargetReticle: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 1)
                .frame(width: 74, height: 74)

            Image(systemName: "scope")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)

            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
}
