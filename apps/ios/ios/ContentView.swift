import PencilKit
import SwiftUI

struct ContentView: View {
    @State private var selectedColor: UIColor = UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
    @State private var piecesPlaced = 0
    @State private var lastSurface = "none yet"
    @State private var clearToken = 0
    @State private var status = "starting camera…"
    @State private var hint: String?
    @State private var showDebug = true

    @State private var showDrawer = false
    @State private var draftDrawing = PKDrawing()
    @State private var drawerClearToken = 0
    @State private var currentDrawing: PKDrawing?
    @State private var drawingImage: UIImage?
    @State private var drawingPNG: Data?

    private let palette: [UIColor] = [
        UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1), // yellow
        UIColor(red: 1.00, green: 0.00, blue: 0.50, alpha: 1), // pink
        UIColor(red: 0.00, green: 0.87, blue: 1.00, alpha: 1), // cyan
        UIColor(red: 0.00, green: 0.90, blue: 0.35, alpha: 1), // green
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1), // white
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ARPaintView(
                color: selectedColor,
                clearToken: clearToken,
                showDebug: showDebug,
                drawingImage: drawingImage,
                onPlace: { classification in
                    piecesPlaced += 1
                    lastSurface = classification
                },
                onStatus: { status = $0 },
                onHint: { hint = $0 }
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(status)
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Text("\(piecesPlaced) piece\(piecesPlaced == 1 ? "" : "s") · last: \(lastSurface)")
                    .font(.footnote.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                HStack(spacing: 10) {
                    ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(Color(color))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: selectedColor == color ? 3 : 1))
                        }
                    }

                    Button {
                        showDrawer = true
                        draftDrawing = PKDrawing()
                        drawerClearToken += 1
                    } label: {
                        Image(systemName: drawingImage != nil ? "paintbrush.pointed.fill" : "paintbrush.pointed")
                            .frame(width: 44, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    if drawingImage != nil, let png = drawingPNG, let preview = UIImage(data: png) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if drawingImage != nil {
                        Button {
                            currentDrawing = nil
                            drawingImage = nil
                            drawingPNG = nil
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 34)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }

                    Button {
                        clearToken += 1
                        piecesPlaced = 0
                        lastSurface = "none yet"
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    Button {
                        showDebug.toggle()
                    } label: {
                        Image(systemName: showDebug ? "viewfinder" : "viewfinder.slash")
                            .frame(width: 44, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showDrawer) {
            NavigationStack {
                DrawingCanvasView(drawing: $draftDrawing, clearToken: drawerClearToken)
                    .background(Color.white)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showDrawer = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button("Clear") { drawerClearToken += 1 }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button("Done") { commitDrawing() }
                                .fontWeight(.semibold)
                        }
                    }
                    .navigationTitle("Draw your graffiti")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onChange(of: hint) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if hint == newValue { hint = nil }
            }
        }
    }

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

#Preview {
    ContentView()
}
