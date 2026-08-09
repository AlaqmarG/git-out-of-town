import CoreLocation
import MapKit
import SwiftUI

/// The home screen: everything painted around you, live. Tap a piece to see
/// it and get pointed to the spot; walk over and open Paint to view it in AR.
struct MapTabView: View {
    @Binding var tab: AppTab
    var onHelp: () -> Void

    @State private var pieces: [PieceDTO] = []
    @State private var selected: PieceDTO?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    private var location = LocationService.shared

    init(tab: Binding<AppTab>, onHelp: @escaping () -> Void) {
        _tab = tab
        self.onHelp = onHelp
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(pieces) { piece in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: piece.lat, longitude: piece.lng)) {
                    PieceMarker(piece: piece, isSelected: selected?.id == piece.id)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.snappy) {
                                selected = selected?.id == piece.id ? nil : piece
                            }
                        }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .top) { header }
        .safeAreaInset(edge: .bottom) {
            if let selected {
                PieceGuideCard(piece: selected, tab: $tab) {
                    withAnimation(.snappy) { self.selected = nil }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected?.id)
        .task { await refreshLoop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label {
                Text(pieces.isEmpty ? "Nothing painted nearby yet" : "\(pieces.count) piece\(pieces.count == 1 ? "" : "s") around you")
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "paintbrush.pointed.fill")
                    .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.00))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .glassEffect(.regular, in: Capsule())

            Spacer()

            Button {
                onHelp()
            } label: {
                Image(systemName: "questionmark.circle")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("How this works")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            if let loc = location.location {
                if let fetched = try? await APIClient.listPieces(
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude,
                    radiusMeters: 2000
                ) {
                    pieces = fetched
                    if let sel = selected {
                        selected = fetched.first { $0.id == sel.id } ?? sel
                    }
                }
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

private struct PieceMarker: View {
    let piece: PieceDTO
    let isSelected: Bool

    var body: some View {
        AsyncImage(url: APIClient.imageURL(path: piece.finalImagePath ?? piece.rawImagePath)) { image in
            image.resizable().scaledToFit().padding(4)
        } placeholder: {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
        }
        .frame(width: isSelected ? 52 : 38, height: isSelected ? 52 : 38)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? Color(red: 1.00, green: 0.84, blue: 0.00) : .white.opacity(0.5), lineWidth: isSelected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Photo of the piece in place + live distance and a compass arrow that
/// points where to walk.
private struct PieceGuideCard: View {
    let piece: PieceDTO
    @Binding var tab: AppTab
    var dismiss: () -> Void

    private var location = LocationService.shared

    init(piece: PieceDTO, tab: Binding<AppTab>, dismiss: @escaping () -> Void) {
        self.piece = piece
        _tab = tab
        self.dismiss = dismiss
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: previewURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color.black.opacity(0.25)
                        ProgressView()
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                    if let guidance {
                        HStack(spacing: 7) {
                            Image(systemName: "location.north.fill")
                                .font(.caption.weight(.bold))
                                .rotationEffect(.degrees(guidance.arrow))
                                .animation(.snappy(duration: 0.3), value: guidance.arrow)
                            Text(guidance.text)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.00))
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Close")
            }

            if piece.client == "ios" {
                Button {
                    tab = .paint
                } label: {
                    Label(arButtonTitle, systemImage: "arkit")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(red: 1.00, green: 0.84, blue: 0.00))
                .foregroundStyle(.black)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var previewURL: URL {
        APIClient.imageURL(path: piece.sceneImagePath ?? piece.finalImagePath ?? piece.rawImagePath)
    }

    private var title: String {
        piece.surfaceType.map { "Piece on a \($0)" } ?? "Piece #\(piece.id)"
    }

    private var subtitle: String {
        piece.client == "ios"
            ? "Walk to the spot, then open Paint and scan around — it appears where it was sprayed."
            : "Painted from the web — see it on the map."
    }

    private var arButtonTitle: String {
        if let guidance, guidance.meters < 30 { return "You're here — view it in AR" }
        return "Walk there, then view in AR"
    }

    private var guidance: (meters: Double, text: String, arrow: Double)? {
        guard let loc = location.location else { return nil }
        let target = CLLocation(latitude: piece.lat, longitude: piece.lng)
        let meters = loc.distance(from: target)
        let bearing = bearingDegrees(
            from: loc.coordinate,
            to: CLLocationCoordinate2D(latitude: piece.lat, longitude: piece.lng)
        )
        let distanceText = meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
        let arrow = bearing - (location.heading ?? 0)
        return (meters, "\(distanceText) · \(compassWord(bearing))", arrow)
    }

    private func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let dLng = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func compassWord(_ bearing: Double) -> String {
        let words = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return words[Int((bearing + 22.5) / 45) % 8]
    }
}
