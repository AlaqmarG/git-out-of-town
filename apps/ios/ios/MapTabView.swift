import CoreLocation
import MapKit
import SwiftUI

enum GallerySort: String, CaseIterable {
    case nearest = "Nearest"
    case newest = "Newest"
}

/// The home screen: everything painted around you, live. The map says where;
/// the gallery underneath says what, for every piece in view at once; opening
/// one hands the whole screen to the artwork.
struct MapTabView: View {
    @Binding var tab: AppTab
    @Binding var arMode: ARMode
    var onHelp: () -> Void

    @State private var pieces: [PieceDTO] = []
    @State private var selected: PieceDTO?
    @State private var expanded = false
    @State private var sort: GallerySort = .nearest
    @State private var loaded = false
    @State private var offline = false
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var didAutoFrame = false

    private var location = LocationService.shared
    private var permissions = Permissions.shared

    init(tab: Binding<AppTab>, arMode: Binding<ARMode>, onHelp: @escaping () -> Void) {
        _tab = tab
        _arMode = arMode
        self.onHelp = onHelp
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(pieces) { piece in
                Annotation("", coordinate: piece.coordinate) {
                    PieceMarker(piece: piece, isSelected: selected?.id == piece.id)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selected = piece
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
            if !pieces.isEmpty {
                NearbyGallery(pieces: pieces, expanded: $expanded, sort: $sort) { selected = $0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: pieces.isEmpty)
        .fullScreenCover(item: $selected) { piece in
            PieceDetailView(
                piece: piece,
                context: pieces,
                onOpen: { selected = $0 },
                onViewInAR: {
                    selected = nil
                    arMode = .view
                    tab = .paint
                },
                dismiss: { selected = nil }
            )
        }
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
                action: { arMode = .paint; tab = .paint }
            )
        } else if loaded && pieces.isEmpty {
            blocker(
                symbol: "paintbrush.pointed.fill",
                title: "Be the first here",
                message: "Nobody has painted this street yet. Open Paint, point at a wall, and put something on it.",
                actionTitle: "Start painting",
                action: { arMode = .paint; tab = .paint }
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
        PieceImage(path: piece.artPath)
            .padding(4)
            .frame(width: isSelected ? 56 : 44, height: isSelected ? 56 : 44)
            .clipped()
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.spray : .white.opacity(0.5), lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .animation(.snappy(duration: 0.2), value: isSelected)
            .accessibilityElement()
            .accessibilityLabel("\(piece.title) \(piece.surfaceLine)")
            .accessibilityAddTraits(.isButton)
    }
}

/// Everything in view, not one pin at a time. Collapsed it is a strip of
/// artwork you can flick through without leaving the map; expanded it is the
/// full list with distance, direction and age on every row.
private struct NearbyGallery: View {
    let pieces: [PieceDTO]
    @Binding var expanded: Bool
    @Binding var sort: GallerySort
    var onOpen: (PieceDTO) -> Void

    private var location = LocationService.shared

    init(pieces: [PieceDTO], expanded: Binding<Bool>, sort: Binding<GallerySort>, onOpen: @escaping (PieceDTO) -> Void) {
        self.pieces = pieces
        _expanded = expanded
        _sort = sort
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if expanded {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sorted) { piece in
                            Button { onOpen(piece) } label: { row(piece) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 300)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sorted) { piece in
                            Button { onOpen(piece) } label: { thumbnail(piece) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 88)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy, value: expanded)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("\(pieces.count) here")
                        .font(.subheadline.weight(.bold))
                        .contentTransition(.numericText())
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse the list of pieces here" : "Show all \(pieces.count) pieces here")

            Spacer(minLength: 0)

            Button {
                sort = sort == .nearest ? .newest : .nearest
            } label: {
                Label(sort.rawValue, systemImage: sort == .nearest ? "location.fill" : "clock")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.spray)
            .accessibilityLabel("Sorted by \(sort.rawValue). Tap to change.")
        }
    }

    /// Nearest needs a fix; without one it would be an arbitrary order dressed
    /// up as a meaningful one, so fall back to newest.
    private var sorted: [PieceDTO] {
        guard sort == .nearest, let loc = location.location else {
            return pieces.sorted { $0.createdAt > $1.createdAt }
        }
        return pieces.sorted {
            loc.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))
                < loc.distance(from: CLLocation(latitude: $1.lat, longitude: $1.lng))
        }
    }

    private func thumbnail(_ piece: PieceDTO) -> some View {
        PieceImage(path: piece.previewPath)
            .frame(width: 116, height: 88)
            .clipped()
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(caption(piece))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(6)
            }
            .accessibilityElement()
            .accessibilityLabel("\(piece.title), \(caption(piece))")
    }

    private func row(_ piece: PieceDTO) -> some View {
        HStack(spacing: 12) {
            PieceImage(path: piece.previewPath)
                .frame(width: 72, height: 60)
                .clipped()
                .background(.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(piece.city.map { "\(piece.title) · \($0)" } ?? piece.title)
                    .font(.subheadline.weight(.semibold))
                if let relation = PieceGeo.relation(to: piece) {
                    HStack(spacing: 5) {
                        Image(systemName: "location.north.fill")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(relation.arrow))
                        Text(relation.text)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.spray)
                }
                Text("\(PieceGeo.ago(piece.createdAt)) · \(piece.surfaceLine)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func caption(_ piece: PieceDTO) -> String {
        PieceGeo.relation(to: piece).map { PieceGeo.distanceText($0.meters) }
            ?? PieceGeo.ago(piece.createdAt)
    }
}
