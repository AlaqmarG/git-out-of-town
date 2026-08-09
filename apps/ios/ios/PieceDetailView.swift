import CoreLocation
import SwiftUI

extension PieceDTO {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    /// ⚠️ The scene photo ALREADY CONTAINS the artwork — it is the AR view the
    /// painter saw. Drawing the art on top of it renders the piece twice.
    var hasScene: Bool { sceneImagePath != nil }
    var previewPath: String { sceneImagePath ?? artPath }
    var artPath: String { finalImagePath ?? rawImagePath }
    var title: String { kind == "sticker" ? "Sticker" : "Spray" }

    var surfaceLine: String {
        guard let surfaceType, surfaceType != "none" else { return "on the wall" }
        return "on a \(surfaceType)"
    }
}

/// Where a piece is, relative to whoever is holding the phone.
struct PieceRelation {
    let meters: Double
    let bearing: Double
    /// Rotation for an on-screen arrow: the bearing, minus where the phone points.
    let arrow: Double

    var text: String { "\(PieceGeo.distanceText(meters)) · \(PieceGeo.compassWord(bearing))" }
}

/// Distance, direction and age — the vocabulary both the map and the AR viewer
/// describe a piece with. Wording matches the web so the two read as one product.
enum PieceGeo {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func date(_ raw: String) -> Date? { iso.date(from: raw) ?? isoPlain.date(from: raw) }

    static func ago(_ raw: String) -> String {
        guard let date = date(raw) else { return "" }
        let mins = Int((Date().timeIntervalSince(date) / 60).rounded())
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        let hours = Int((Double(mins) / 60).rounded())
        if hours < 24 { return "\(hours)h ago" }
        return "\(Int((Double(hours) / 24).rounded()))d ago"
    }

    static func distanceText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
    }

    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let dLng = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func compassWord(_ bearing: Double) -> String {
        let words = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return words[Int((bearing + 22.5) / 45) % 8]
    }

    @MainActor
    static func relation(to piece: PieceDTO) -> PieceRelation? {
        guard let loc = LocationService.shared.location else { return nil }
        let bearing = bearing(from: loc.coordinate, to: piece.coordinate)
        return PieceRelation(
            meters: loc.distance(from: CLLocation(latitude: piece.lat, longitude: piece.lng)),
            bearing: bearing,
            arrow: bearing - (LocationService.shared.heading ?? 0)
        )
    }

    /// Vertical placement, which is the half of "where is it" a map cannot show.
    @MainActor
    static func height(of piece: PieceDTO) -> String? {
        guard let altitude = piece.altitudeM, let loc = LocationService.shared.location,
              loc.verticalAccuracy >= 0 else { return nil }
        let delta = altitude - loc.altitude
        if abs(delta) < 1 { return "about eye level" }
        return delta > 0
            ? String(format: "%.1f m above you", delta)
            : String(format: "%.1f m below you", -delta)
    }

    /// How exactly this piece knows where it is — which decides whether it lands
    /// on the real wall in AR or merely faces you from roughly the right spot.
    static func precision(of piece: PieceDTO) -> (symbol: String, text: String) {
        if piece.markerTransform != nil {
            return ("scope", "Measured off the venue marker — lands within centimetres")
        }
        if piece.usedGeoAnchor { return ("globe", "Pinned with a geo anchor") }
        if piece.placementTransform != nil {
            return ("cube.transparent", "Surface-aligned — snaps onto the real wall in AR")
        }
        return ("location.circle", "Pinned by GPS — faces you in AR")
    }

    /// Everything painted within `radius` of a piece, nearest first. The spatial
    /// relationship between pieces, which a single pin cannot express.
    static func neighbours(of piece: PieceDTO, in pieces: [PieceDTO], radius: Double = 40) -> [PieceDTO] {
        let origin = CLLocation(latitude: piece.lat, longitude: piece.lng)
        return pieces
            .filter { $0.id != piece.id }
            .map { ($0, origin.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .prefix(8)
            .map(\.0)
    }
}

/// A remote image that admits when it failed instead of spinning forever.
struct PieceImage: View {
    let path: String
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: APIClient.imageURL(path: path)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
            default:
                ProgressView().controlSize(.small).tint(.white)
            }
        }
    }
}

/// Opening a piece is the moment this project is about, so it takes over the
/// screen rather than sitting in a corner — the same call the web map makes.
/// The artwork is the subject at 4:3; everything else recedes behind a blur.
struct PieceDetailView: View {
    let piece: PieceDTO
    /// The rest of the set the piece was opened from, so it can say what else is
    /// on this wall and let the viewer walk the block without going back.
    var context: [PieceDTO] = []
    var onOpen: (PieceDTO) -> Void = { _ in }
    var onViewInAR: (() -> Void)?
    var dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    artwork
                    caption
                    placement
                    if !neighbours.isEmpty { nearbyStrip }
                    if let onViewInAR { arButton(onViewInAR) }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) { closeButton }
    }

    // MARK: - Art

    private var artwork: some View {
        ZStack {
            Color.black
            if piece.hasScene {
                PieceImage(path: piece.previewPath)
            } else {
                // The web lightbox sizes bare artwork to 76% of the panel.
                PieceImage(path: piece.artPath, contentMode: .fit)
                    .scaleEffect(0.76)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(piece.surfaceLine.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(12)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityLabel("\(piece.title) \(piece.surfaceLine)")
    }

    private var caption: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(piece.city.map { "\(piece.title) · \($0)" } ?? piece.title)
                    .font(.title3.weight(.bold))
                Text(metaLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let colors = piece.colors, !colors.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(colors.prefix(6).enumerated()), id: \.offset) { _, c in
                        Circle()
                            .fill(Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255))
                            .frame(width: 15, height: 15)
                            .overlay(Circle().stroke(.white.opacity(0.15)))
                    }
                }
                .padding(.top, 5)
                .accessibilityLabel("\(colors.count) colours used")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaLine: String {
        var parts = [PieceGeo.ago(piece.createdAt)]
        if let strokes = piece.strokeCount, strokes > 0 { parts.append("\(strokes) strokes") }
        if let ms = piece.durationMs, ms > 0 { parts.append("\(Int((Double(ms) / 1000).rounded()))s to paint") }
        if piece.client == "ios" { parts.append("painted in AR") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Where it is

    private var placement: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let relation = PieceGeo.relation(to: piece) {
                HStack(spacing: 9) {
                    Image(systemName: "location.north.fill")
                        .font(.subheadline.weight(.bold))
                        .rotationEffect(.degrees(relation.arrow))
                        .animation(.snappy(duration: 0.3), value: relation.arrow)
                    Text(relation.text)
                    if let height = PieceGeo.height(of: piece) {
                        Text("· \(height)").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.spray)
                .accessibilityLabel("\(relation.text) of you")
            }

            let precision = PieceGeo.precision(of: piece)
            Label(precision.text, systemImage: precision.symbol)
            Label(coordinateLine, systemImage: "mappin.and.ellipse")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var coordinateLine: String {
        var line = String(format: "%.5f, %.5f", piece.lat, piece.lng)
        if let altitude = piece.altitudeM { line += String(format: " · %.0f m ASL", altitude) }
        return line
    }

    // MARK: - The rest of this wall

    private var neighbours: [PieceDTO] { PieceGeo.neighbours(of: piece, in: context) }

    private var nearbyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(neighbours.count) more within 40 m")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(neighbours) { other in
                        Button { onOpen(other) } label: {
                            PieceImage(path: other.previewPath)
                                .frame(width: 84, height: 84)
                                .background(.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nearby \(other.title), \(PieceGeo.ago(other.createdAt))")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func arButton(_ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Label(arTitle, systemImage: "arkit")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.spray)
        .foregroundStyle(.black)
    }

    private var arTitle: String {
        guard let relation = PieceGeo.relation(to: piece), relation.meters >= 30 else {
            return "View it in AR"
        }
        return "Walk there, then view in AR"
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.bold))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .padding(.trailing, 18)
        .padding(.top, 6)
        .accessibilityLabel("Close")
    }
}
