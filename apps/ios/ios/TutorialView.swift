import SwiftUI

/// First-launch walkthrough. Replayable from the ? buttons.
struct TutorialView: View {
    var done: () -> Void

    @State private var page = 0

    private static let accent = Color(red: 1.00, green: 0.84, blue: 0.00)

    private struct Page {
        let symbol: String
        let tint: Color
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(
            symbol: "paintbrush.pointed.fill",
            tint: accent,
            title: "Paint the real world",
            text: "Any wall is a canvas. Graffiti you spray pins to that exact spot — for everyone, forever."
        ),
        Page(
            symbol: "map.fill",
            tint: Color(red: 0.00, green: 0.87, blue: 1.00),
            title: "Find pieces around you",
            text: "The map shows everything painted near you. Tap a piece and the arrow points you to its spot."
        ),
        Page(
            symbol: "arkit",
            tint: Color(red: 0.00, green: 0.90, blue: 0.35),
            title: "Spray in AR",
            text: "Open Paint and pan slowly so it learns the walls. Pick a color or draw your own, then tap any surface."
        ),
        Page(
            symbol: "paperplane.fill",
            tint: Color(red: 1.00, green: 0.00, blue: 0.50),
            title: "Post it — or toss it",
            text: "Nothing goes public until you hit Post. After that it's on the world map for anyone to visit."
        ),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.07, blue: 0.10), Color(red: 0.12, green: 0.08, blue: 0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { done() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding()
                }

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 28) {
                            ZStack {
                                Circle()
                                    .fill(item.tint.opacity(0.16))
                                    .frame(width: 168, height: 168)
                                Circle()
                                    .stroke(item.tint.opacity(0.35), lineWidth: 1.5)
                                    .frame(width: 168, height: 168)
                                Image(systemName: item.symbol)
                                    .font(.system(size: 64, weight: .medium))
                                    .foregroundStyle(item.tint)
                            }
                            .scaleEffect(page == index ? 1 : 0.8)
                            .animation(.bouncy(duration: 0.5), value: page)

                            VStack(spacing: 12) {
                                Text(item.title)
                                    .font(.title.weight(.bold))
                                    .foregroundStyle(.white)
                                Text(item.text)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 36)
                            }
                        }
                        .tag(index)
                        .padding(.bottom, 40)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        done()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Start exploring")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.glassProminent)
                .tint(Self.accent)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .animation(.snappy, value: page)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    TutorialView {}
}
