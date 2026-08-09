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
    @State private var loaded = false
    @State private var offline = false
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var didAutoFrame = false

    private var location = LocationService.shared
    private var permissions = Permissions.shared

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
        .overlay { status }
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
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            Task { await refresh() }
        }
        .task { await refreshLoop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label {
                Text(headline)
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "paintbrush.pointed.fill")
                    .foregroundStyle(Color.spray)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassEffect(.regular, in: Capsule())

            Spacer(minLength: 0)

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

    private var headline: String {
        if permissions.locationDenied { return "Location is off" }
        if offline { return "Can't reach the wall" }
        if !loaded { return "Looking around you…" }
        return pieces.isEmpty
            ? "Nothing painted nearby yet"
            : "\(pieces.count) piece\(pieces.count == 1 ? "" : "s") around you"
    }

    /// A map with no pins looks broken. Say which of the three reasons it is,
    /// and give the way out of each.
    @ViewBuilder
    private var status: some View {
        if permissions.locationDenied {
            blocker(
                symbol: "location.slash.fill",
                title: "Turn on location",
                message: "The map shows what has been painted around you — it needs to know where you are.",
                actionTitle: "Open Settings",
                action: Permissions.openSettings
            )
        } else if offline && pieces.isEmpty {
            blocker(
                symbol: "wifi.slash",
                title: "Can't reach the wall",
                message: "The map lives on the server. It'll fill in on its own as soon as you're back online.",
                actionTitle: "Paint offline anyway",
                action: { tab = .paint }
            )
        } else if loaded && pieces.isEmpty && selected == nil {
            blocker(
                symbol: "paintbrush.pointed.fill",
                title: "Be the first here",
                message: "Nobody has painted this street yet. Open Paint, point at a wall, and put something on it.",
                actionTitle: "Start painting",
                action: { tab = .paint }
            )
        }
    }

    private func blocker(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        BlockerView(symbol: symbol, title: title, message: message, actionTitle: actionTitle, action: action)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(24)
    }

    /// Fetch whatever the camera is looking at — pan to Stackt, see Stackt.
    /// Falls back to a radius around the user until the map reports a region.
    private func refresh() async {
        do {
            let fetched: [PieceDTO]
            if let region = visibleRegion {
                fetched = try await APIClient.listPieces(
                    west: region.center.longitude - region.span.longitudeDelta / 2,
                    south: region.center.latitude - region.span.latitudeDelta / 2,
                    east: region.center.longitude + region.span.longitudeDelta / 2,
                    north: region.center.latitude + region.span.latitudeDelta / 2
                )
            } else if let loc = location.location {
                fetched = try await APIClient.listPieces(
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude,
                    radiusMeters: 2000
                )
            } else {
                return
            }
            // Reassigning identical pieces re-creates every annotation and
            // makes the markers blink on each poll.
            if fetched.map(\.id) != pieces.map(\.id) { pieces = fetched }
            if let sel = selected {
                selected = fetched.first { $0.id == sel.id } ?? sel
            }
            loaded = true
            offline = false

            // An empty view around the user reads as "everything vanished" —
            // frame the world's pieces instead of showing a blank map.
            if pieces.isEmpty, !didAutoFrame {
                didAutoFrame = true
                let all = try await APIClient.listPieces(west: -180, south: -85, east: 180, north: 85)
                if !all.isEmpty {
                    pieces = all
                    withAnimation(.snappy) { position = .automatic }
                }
            }
        } catch {
            offline = true
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

private struct PieceMarker: View {
    let piece: PieceDTO
    let isSelected: Bool

    var body: some View {
        PieceThumbnail(url: APIClient.imageURL(path: piece.finalImagePath ?? piece.rawImagePath), inset: 4)
            .frame(width: isSelected ? 56 : 44, height: isSelected ? 56 : 44)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.spray : .white.opacity(0.5), lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .animation(.snappy(duration: 0.2), value: isSelected)
            .accessibilityElement()
            .accessibilityLabel(piece.surfaceType.map { "Piece on a \($0)" } ?? "Piece \(piece.id)")
            .accessibilityAddTraits(.isButton)
    }
}

/// A remote image that admits when it failed instead of spinning forever.
private struct PieceThumbnail: View {
    let url: URL
    var inset: CGFloat = 0

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill().padding(inset)
            case .failure:
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            default:
                ProgressView().controlSize(.small).tint(.white)
            }
        }
        .clipped()
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
                PieceThumbnail(url: previewURL)
                    .frame(width: 96, height: 96)
                    .background(.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)

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
                        .foregroundStyle(Color.spray)
                        .accessibilityLabel("\(guidance.text) of you")
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Close")
            }

            // Every piece renders in AR — web ones simply face you — so this is
            // never a dead-end card.
            Button {
                tab = .paint
            } label: {
                Label(arButtonTitle, systemImage: "arkit")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.spray)
            .foregroundStyle(.black)
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
        guard let guidance, guidance.meters < 30 else {
            return "Walk to the spot, then open Paint and scan around — it appears where it was sprayed."
        }
        return "You're close. Open Paint and pan slowly across the wall to see it."
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
