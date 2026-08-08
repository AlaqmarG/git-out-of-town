import SwiftUI

struct ContentView: View {
    @State private var selectedColor: UIColor = UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
    @State private var piecesPlaced = 0
    @State private var lastSurface = "none yet"
    @State private var clearToken = 0
    @State private var status = "starting camera…"
    @State private var hint: String?
    @State private var showDebug = true

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
        .onChange(of: hint) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if hint == newValue { hint = nil }
            }
        }
    }
}

#Preview {
    ContentView()
}
