import SwiftUI

/// First-launch walkthrough. Replayable from the ? buttons.
struct TutorialView: View {
    var done: () -> Void

    @State private var page = 0

    private struct Page {
        let symbol: String
        let tint: Color
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(
            symbol: "paintbrush.pointed.fill",
            tint: .spray,
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
            symbol: "camera.fill",
            tint: Color(red: 0.00, green: 0.90, blue: 0.35),
            title: "Shoot, then paint",
            text: "Pan slowly so the phone reads the depth, take a photo of the spot, then stamp stickers or draw straight onto it."
        ),
        Page(
            symbol: "paperplane.fill",
            tint: Color(red: 1.00, green: 0.00, blue: 0.50),
            title: "Post it — or toss it",
            text: "Nothing goes public until you hit Post. After that it's on the world map for anyone to visit."
        ),
        Page(
            symbol: "location.fill",
            tint: Color(red: 0.62, green: 0.55, blue: 1.00),
            title: "Two things we'll ask for",
            text: "The camera, to see the wall. Your location, to pin the paint to it. Say yes to both or nothing can be placed."
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
                    Button {
                        done()
                    } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        // Scrolls rather than clipping: at accessibility text
                        // sizes the copy is taller than the phone.
                        ScrollView {
                            VStack(spacing: 28) {
                                ZStack {
                                    Circle()
                                        .fill(item.tint.opacity(0.16))
                                    Circle()
                                        .stroke(item.tint.opacity(0.35), lineWidth: 1.5)
                                    Image(systemName: item.symbol)
                                        .font(.system(size: 64, weight: .medium))
                                        .foregroundStyle(item.tint)
                                }
                                .frame(width: 168, height: 168)
                                .scaleEffect(page == index ? 1 : 0.8)
                                .animation(.bouncy(duration: 0.5), value: page)

                                VStack(spacing: 12) {
                                    Text(item.title)
                                        .font(.title.weight(.bold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                    Text(item.text)
                                        .font(.body)
                                        .foregroundStyle(.white.opacity(0.75))
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 36)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                        .scrollBounceBehavior(.basedOnSize)
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
                        .frame(minHeight: 54)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.spray)
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
