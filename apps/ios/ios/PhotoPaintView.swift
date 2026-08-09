import PencilKit
import SwiftUI

/// Paint on the still you just shot. Drag to move, pinch to size, twist to
/// rotate. What you see here is exactly what gets projected back onto the wall.
struct PhotoPaintView: View {
    let scene: CapturedScene
    var stickers: [Sticker]
    /// Returns the overlay (transparent, viewport-sized) and the sticker ids used.
    var onPlace: (UIImage, [String]) -> Void
    var onCancel: () -> Void

    @State private var placed: [PlacedSticker] = []
    @State private var selectedID: UUID?
    @State private var trayID: String?
    @State private var drawing = PKDrawing()
    @State private var isDrawing = false
    @State private var showHint = true

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
                if showHint && placed.isEmpty && drawing.strokes.isEmpty && !isDrawing {
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
        .onAppear { trayID = stickers.first?.id }
        .preferredColorScheme(.dark)
    }

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
                    DrawingCanvasView(drawing: $drawing, clearToken: 0)
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

    private var stickerLayer: some View {
        ForEach($placed) { $item in
            StickerLayer(
                item: $item,
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

            if !placed.isEmpty || !drawing.strokes.isEmpty {
                Button(role: .destructive) {
                    haptic()
                    withAnimation(.snappy) {
                        placed.removeAll()
                        drawing = PKDrawing()
                        selectedID = nil
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
                .tint(Color(red: 1.00, green: 0.84, blue: 0.00))
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
                .tint(Color(red: 1.00, green: 0.84, blue: 0.00))
                .foregroundStyle(.black)
                .disabled(placed.isEmpty && drawing.strokes.isEmpty)
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
                        Image(uiImage: sticker.image)
                            .resizable()
                            .scaledToFit()
                            .padding(7)
                            .frame(width: 58, height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(trayID == sticker.id ? Color.white.opacity(0.18) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        trayID == sticker.id ? Color(red: 1.00, green: 0.84, blue: 0.00) : .clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sticker \(sticker.name)")
                    .accessibilityAddTraits(trayID == sticker.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .animation(.snappy(duration: 0.2), value: trayID)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Editing

    private func add(_ sticker: Sticker, at point: CGPoint) {
        haptic()
        withAnimation(.bouncy(duration: 0.35)) {
            let item = PlacedSticker(sticker: sticker, center: point)
            placed.append(item)
            selectedID = item.id
            showHint = false
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
                let base = min(size.width, size.height) * 0.28 * item.scale
                let aspect = image.size.height / max(image.size.width, 1)
                let width = base
                let height = base * aspect

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
        onPlace(overlay, placed.map(\.sticker.id))
    }
}

/// One stamped sticker: drag to move, pinch to size, twist to rotate.
private struct StickerLayer: View {
    @Binding var item: PhotoPaintView.PlacedSticker
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
            .frame(width: size, height: size * aspect)
            .rotationEffect(item.rotation)
            .overlay(alignment: .topTrailing) {
                if isSelected && canEdit {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 26, height: 26)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 10, y: -10)
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

    private var size: CGFloat { 120 * item.scale }
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
