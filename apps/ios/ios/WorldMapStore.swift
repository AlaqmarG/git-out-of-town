import ARKit
import Compression
import CoreLocation
import Foundation

/// Upload/download of serialized ARWorldMaps — a venue's visual scan. A
/// returning device relocalizes against the scan and recovers the exact pose,
/// so pieces land on the wall they were painted on; GPS only decides which
/// scan is worth trying.
///
/// Scans CHAIN: relocalizing loads the earlier map's anchors into the live
/// session, so once the visitor has walked further `getCurrentWorldMap` returns
/// that map plus everything new. Upload it with `parentId` and it becomes the
/// next version of the same venue — see `WorldMapRecord` in `packages/shared`.
///
/// Self-contained on purpose: the AR session code decides WHEN to save and
/// load; this file only knows HOW.
enum WorldMapStore {
    nonisolated struct Record: Decodable, Identifiable, Sendable {
        let id: Int
        let pieceId: Int?
        let lat: Double
        let lng: Double
        let mapPath: String
        let sizeBytes: Int
        let featurePoints: Int?
        let extentM: Double?
        /// Absent from a server that predates chaining; treat as zero.
        let anchorCount: Int?
        /// The painter's view of this spot, for the ghosted placement guide.
        /// Nil on scans saved before guides existed.
        let snapshotPath: String?
        let snapshotTransform: [Double]?
        let createdAt: String
    }

    enum StoreError: Error {
        case badStatus(Int)
        case corrupt
        case tooLarge
    }

    /// The server refuses a body over 32 MB, and a map nobody can download in
    /// time is no better than no map. Stop chaining well before that ceiling
    /// rather than discovering it as a 413.
    nonisolated static let maxUploadBytes = 24 * 1024 * 1024

    /// What the server gates a chained upload on, measured once. Reading
    /// `rawFeaturePoints` bridges the whole point cloud into Swift, so this is
    /// not something to do per frame or twice per upload.
    struct Stats {
        let anchors: Int
        let featurePoints: Int
        let extentM: Double
    }

    // MARK: - Anchors

    /// An anchor name carries the piece it pins and the size to draw it:
    /// `piece:<id>:<mm>`. The only place that grammar is written down.
    nonisolated static func pieceName(id: Int, sizeM: Float) -> String {
        "piece:\(id):\(Int(max(sizeM, 0.05) * 1000))"
    }

    nonisolated static func pieceName(_ name: String?) -> (id: Int, sizeM: CGFloat)? {
        let parts = name?.split(separator: ":") ?? []
        guard parts.count == 3, parts[0] == "piece", let id = Int(parts[1]), let mm = Int(parts[2])
        else { return nil }
        return (id, CGFloat(max(Float(mm) / 1000, 0.05)))
    }

    /// Prunes `map` to the piece anchors it must carry forward — one per piece,
    /// earlier entries winning — and measures what is left.
    ///
    /// Both halves matter. ARKit hands back the same piece twice when a session
    /// re-adds an anchor it already relocalized (same name, fresh UUID), and
    /// keeping the map's own copy keeps the ORIGINAL painter's transform rather
    /// than this visitor's re-derived one. Everything unnamed — plane anchors,
    /// and the LiDAR mesh anchors above all — is dropped: it is re-detected in
    /// seconds and it is what would otherwise make a chained map grow without
    /// bound.
    @discardableResult
    nonisolated static func prune(_ map: ARWorldMap) -> Stats {
        var seen = Set<Int>()
        map.anchors = map.anchors.filter { anchor in
            guard let id = pieceName(anchor.name)?.id else { return false }
            return seen.insert(id).inserted
        }
        return Stats(
            anchors: map.anchors.count,
            featurePoints: map.rawFeaturePoints.points.count,
            extentM: Double(max(map.extent.x, map.extent.z))
        )
    }

    /// Mirrors `chainRejection` in `apps/web/lib/worldmaps.ts`: carry every
    /// anchor forward, lose no coverage, and add something real. Drift only
    /// costs a skipped or wasted optional upload — the server is the authority
    /// and re-checks every rule atomically.
    nonisolated static func improves(_ stats: Stats, over parent: Record) -> Bool {
        let wasAnchors = parent.anchorCount ?? 0
        let wasPoints = parent.featurePoints ?? 0
        guard stats.anchors >= wasAnchors, stats.featurePoints >= wasPoints else { return false }
        return stats.anchors > wasAnchors
            || (Double(stats.featurePoints) >= Double(wasPoints) * 1.05
                && stats.featurePoints >= wasPoints + 50)
    }

    // MARK: - Serialization

    /// NSKeyedArchiver output compresses ~4:1 with LZFSE; maps go from tens of
    /// MB to a few, which matters on conference wifi.
    nonisolated static func serialize(_ map: ARWorldMap) throws -> Data {
        let raw = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
        return compress(raw) ?? raw
    }

    nonisolated static func deserialize(_ data: Data) throws -> ARWorldMap {
        let raw = decompress(data) ?? data
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: raw) else {
            throw StoreError.corrupt
        }
        return map
    }

    // MARK: - Network

    /// Posts a map — as version N+1 of `parentId` when chaining, otherwise as a
    /// new venue.
    ///
    /// `stats` must be the return of `prune(map)` on this very map: they are what
    /// the server's anchor and quality guards judge, so measuring anything else
    /// would let those guards be quietly wrong.
    nonisolated static func upload(
        _ map: ARWorldMap,
        stats: Stats,
        pieceId: Int?,
        parentId: Int? = nil,
        location: CLLocation,
        guide: PlacementGuide? = nil
    ) async throws -> Record {
        let blob = try serialize(map)
        guard blob.count <= maxUploadBytes else { throw StoreError.tooLarge }

        var request = URLRequest(url: APIClient.baseURL.appendingPathComponent("api/worldmaps"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Feature count and extent are how we tell a substantive scan from a
        // glance at one wall, without downloading the map to find out.
        var meta: [String: Any] = [
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "featurePoints": stats.featurePoints,
            "extentM": stats.extentM,
            "anchorCount": stats.anchors,
        ]
        if let pieceId { meta["pieceId"] = pieceId }
        if let parentId { meta["parentId"] = parentId }
        if let guide { meta["snapshotTransform"] = guide.transform }

        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"map\"; filename=\"scan.armap\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(blob)
        // Optional: the server drops an unusable guide rather than the scan, and
        // a chained version that sends none inherits its parent's.
        if let guide {
            body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"snapshot\"; filename=\"guide.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
            body.append(guide.jpeg)
        }
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"meta\"\r\n\r\n".utf8))
        body.append(try JSONSerialization.data(withJSONObject: meta))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw StoreError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    /// Nearby venues' newest scans, nearest first. Superseded versions are never
    /// listed — chaining onto anything but a head is refused.
    nonisolated static func nearby(location: CLLocation, radiusM: Double = 100) async throws -> [Record] {
        var comps = URLComponents(
            url: APIClient.baseURL.appendingPathComponent("api/worldmaps"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "lat", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "lng", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "radiusM", value: String(radiusM)),
        ]
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StoreError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        struct ListResponse: Decodable { let maps: [Record] }
        return try JSONDecoder().decode(ListResponse.self, from: data).maps
    }

    nonisolated static func download(_ record: Record) async throws -> ARWorldMap {
        let url = APIClient.baseURL.appendingPathComponent("uploads").appendingPathComponent(record.mapPath)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StoreError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try deserialize(data)
    }

    // MARK: - Compression (LZFSE with a 4-byte magic + length header)

    nonisolated private static let magic = Data("GOTM".utf8)

    nonisolated private static func compress(_ data: Data) -> Data? {
        let compressed = transform(data, encode: true)
        guard let compressed, compressed.count + 12 < data.count else { return nil }
        var out = magic
        var length = UInt64(data.count).littleEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(compressed)
        return out
    }

    nonisolated private static func decompress(_ data: Data) -> Data? {
        guard data.count > 12, data.prefix(4) == magic else { return nil }
        let length = data.subdata(in: 4..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        guard length > 0, length < 512 * 1024 * 1024 else { return nil }
        return transform(data.dropFirst(12), encode: false, capacity: Int(length))
    }

    nonisolated private static func transform(_ data: Data, encode: Bool, capacity: Int? = nil) -> Data? {
        let destCapacity = capacity ?? data.count + 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destCapacity)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return encode
                ? compression_encode_buffer(destination, destCapacity, base, src.count, nil, COMPRESSION_LZFSE)
                : compression_decode_buffer(destination, destCapacity, base, src.count, nil, COMPRESSION_LZFSE)
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }
}
