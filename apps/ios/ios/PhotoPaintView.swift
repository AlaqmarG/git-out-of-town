import PencilKit
import SwiftUI

/// Paint on the still you just shot. Drag to move, pinch to size, twist to
/// rotate. What you see here is exactly what gets projected back onto the wall.
struct PhotoPaintView: View {
    let scene: CapturedScene
    var stickers: [Sticker]
    /// Takes the overlay (transparent, viewport-sized) and the sticker ids used.
    /// Returns why it could not be sprayed, or nil on success.
    var onPlace: (UIImage, [String]) -> String?
    var onCancel: () -> Void

    @State private var placed: [PlacedSticker] = []
    @State private var selectedID: UUID?
    @State private var trayID: String?
    @State private var drawing = PKDrawing()
    @State private var clearToken = 0
    @State private var isDrawing = false
    @State private var failure: String?

    struct PlacedSticker: Identifiable {
        let id = UUID()
        let sticker: Sticker
        var center: CGPoint
        var scale: CGFloat = 1
        var rotation: Angle = .zero
    }

    var body: some View {
        // Both layers are exactly the AR viewport, pinned to the screen's real
        // top-left: a tap here has to be the same point the projector maps back
        // onto the world, so this cannot be inset. The chrome is therefore
        // padded by the device insets by hand rather than by the safe area.
        ZStack(alignment: .topLeading) {
            Color.black

            paintSurface
                .frame(width: scene.viewport.width, height: scene.viewport.height)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let failure {
                    Toast(message: failure, symbol: "exclamationmark.triangle.fill", tint: .red)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if isEmpty && !isDrawing {
                    hintCard.transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if !isDrawing {
                    controls.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, Self.deviceInsets.top + 6)
            .padding(.bottom, Self.deviceInsets.bottom + 10)
            .frame(width: scene.viewport.width, height: scene.viewport.height)
        }
        .frame(width: scene.viewport.width, height: scene.viewport.height)
        .ignoresSafeArea()
        .animation(.snappy, value: isDrawing)
        .animation(.snappy, value: failure)
        .onAppear { trayID = stickers.first?.id }
        .preferredColorScheme(.dark)
    }

    private var isEmpty: Bool { placed.isEmpty && drawing.strokes.isEmpty }

    private static var deviceInsets: EdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        let insets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }

    // MARK: - Layers

    private var paintSurface: some View {
        Image(uiImage: scene.photo)
            .resizable()
            .scaledToFill()
            .clipped()
            .overlay(stickerLayer)
            .overlay {
                // Mounted only while drawing: PencilKit's floating tool picker
                // would otherwise sit on top of the sticker tray.
                if isDrawing {
                    DrawingCanvasView(drawing: $drawing, clearToken: clearToken)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                guard !isDrawing else { return }
                if let trayID, let sticker = stickers.first(where: { $0.id == trayID }) {
                    add(sticker, at: point)
                } else {
                    withAnimation(.snappy) { selectedID = nil }
                }
            }
    }

    /// The one sticker size. The editor is only WYSIWYG if the preview on screen
    /// and the overlay we render out come from the same number.
    static func stickerWidth(scale: CGFloat, viewport: CGSize) -> CGFloat {
        min(viewport.width, viewport.height) * 0.28 * scale
    }

    private var stickerLayer: some View {
        ForEach($placed) { $item in
            StickerLayer(
                item: $item,
                width: Self.stickerWidth(scale: item.scale, viewport: scene.viewport),
                isSelected: selectedID == item.id,
                canEdit: !isDrawing,
                onSelect: { selectedID = item.id },
                onDelete: { remove(item.id) }
            )
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                haptic()
                onCancel()
            } label: {
                Label("Retake", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
            }
            .buttonStyle(.glass)

            Spacer()

            if !isEmpty {
                Button(role: .destructive) {
                    haptic()
                    withAnimation(.snappy) {
                        placed.removeAll()
                        drawing = PKDrawing()
                        // PencilKit owns its own copy of the strokes; only a
                        // token change makes the live canvas let go of them.
                        clearToken += 1
                        selectedID = nil
                        failure = nil
                    }
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Start over")
            }

            // While drawing, the bottom belongs to PencilKit — so finishing lives up here.
            if isDrawing {
                Button {
                    haptic()
                    withAnimation(.snappy) { isDrawing = false }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.spray)
                .foregroundStyle(.black)
            }
        }
    }

    private var hintCard: some View {
        Label("Tap the photo to stamp your sticker", systemImage: "hand.tap.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 12)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            stickerTray

            HStack(spacing: 10) {
                Button {
                    haptic()
                    withAnimation(.snappy) {
                        isDrawing = true
                        selectedID = nil
                    }
                } label: {
                    Image(systemName: "scribble.variable")
                        .font(.body.weight(.semibold))
                        .frame(width: 56, height: 54)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Draw freehand")

                Button {
                    haptic(.medium)
                    place()
                } label: {
                    Label("Spray it on the wall", systemImage: "paintbrush.pointed.fill")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.spray)
                .foregroundStyle(.black)
                .disabled(isEmpty)
                .accessibilityHint(isEmpty ? "Stamp a sticker or draw on the photo first" : "")
            }
        }
    }

    private var stickerTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stickers) { sticker in
                    Button {
                        haptic()
                        trayID = sticker.id
                    } label: {
                        // The pack's lettering pieces are wider than they are tall,
                        // so the art gets a fixed box inside the tile — the tile
                        // never resizes and nothing spills past the tray's clip.
                        Image(uiImage: sticker.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .frame(width: Self.tileSide, height: Self.tileSide)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(trayID == sticker.id ? Color.white.opacity(0.18) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(trayID == sticker.id ? Color.spray : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sticker \(sticker.name)")
                    .accessibilityAddTraits(trayID == sticker.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.trayHeight)
            .animation(.snappy(duration: 0.2), value: trayID)
        }
        .frame(height: Self.trayHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private static let tileSide: CGFloat = 56
    private static let trayHeight: CGFloat = 72

    // MARK: - Editing

    private func add(_ sticker: Sticker, at point: CGPoint) {
        haptic()
        withAnimation(.bouncy(duration: 0.35)) {
            let item = PlacedSticker(sticker: sticker, center: point)
            placed.append(item)
            selectedID = item.id
            failure = nil
        }
    }

    private func remove(_ id: UUID) {
        haptic(.rigid)
        withAnimation(.snappy) {
            placed.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Renders just the paint — no photo — at the AR viewport's size, so the
    /// projector can map it straight back onto the world.
    private func place() {
        let size = scene.viewport
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 2
        let overlay = UIGraphicsImageRenderer(size: size, format: format).image { context in
            for item in placed {
                let image = item.sticker.image
                let aspect = image.size.height / max(image.size.width, 1)
                let width = Self.stickerWidth(scale: item.scale, viewport: size)
                let height = width * aspect

                context.cgContext.saveGState()
                context.cgContext.translateBy(x: item.center.x, y: item.center.y)
                context.cgContext.rotate(by: item.rotation.radians)
                image.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                context.cgContext.restoreGState()
            }
            if !drawing.strokes.isEmpty {
                drawing.image(from: CGRect(origin: .zero, size: size), scale: 2)
                    .draw(in: CGRect(origin: .zero, size: size))
            }
        }
        // Failing here keeps the editor open — the art is the expensive part, so
        // it is never thrown away just because the wall or the fix wasn't ready.
        if let why = onPlace(overlay, placed.map(\.sticker.id)) {
            failure = why
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// One stamped sticker: drag to move, pinch to size, twist to rotate.
private struct StickerLayer: View {
    @Binding var item: PhotoPaintView.PlacedSticker
    let width: CGFloat
    let isSelected: Bool
    let canEdit: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void

    @State private var dragStart: CGPoint?
    @State private var scaleStart: CGFloat?
    @State private var rotationStart: Angle?

    var body: some View {
        Image(uiImage: item.sticker.image)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * aspect)
            .rotationEffect(item.rotation)
            .overlay(alignment: .topTrailing) {
                if isSelected && canEdit {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 26, height: 26)
                            .background(.white, in: Circle())
                            // Stays visually small, but stops being a 26pt target.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 19, y: -19)
                    .accessibilityLabel("Remove sticker")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .background {
                if isSelected && canEdit {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .padding(-8)
                        .rotationEffect(item.rotation)
                }
            }
            .position(item.center)
            .allowsHitTesting(canEdit)
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
            .onTapGesture { onSelect() }
    }

    private var aspect: CGFloat {
        item.sticker.image.size.height / max(item.sticker.image.size.width, 1)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = item.center
                    onSelect()
                }
                guard let start = dragStart else { return }
                item.center = CGPoint(
                    x: start.x + value.translation.width,
                    y: start.y + value.translation.height
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if scaleStart == nil {
                    scaleStart = item.scale
                    onSelect()
                }
                guard let start = scaleStart else { return }
                item.scale = min(max(start * value.magnification, 0.25), 4)
            }
            .onEnded { _ in scaleStart = nil }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                if rotationStart == nil {
                    rotationStart = item.rotation
                    onSelect()
                }
                guard let start = rotationStart else { return }
                item.rotation = start + value.rotation
            }
            .onEnded { _ in rotationStart = nil }
    }
}
