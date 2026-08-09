import ARKit
import Compression
import CoreLocation
import Foundation

/// Upload/download of serialized ARWorldMaps — the poster's visual scan of a
/// spot. A returning device relocalizes against the scan and recovers the
/// exact pose, so pieces land on the wall they were painted on; GPS only
/// decides which scan is worth trying.
///
/// Self-contained on purpose: the AR session code decides WHEN to save and
/// load; this file only knows HOW.
enum WorldMapStore {
    struct Record: Decodable, Identifiable {
        let id: Int
        let pieceId: Int?
        let lat: Double
        let lng: Double
        let mapPath: String
        let sizeBytes: Int
        let featurePoints: Int?
        let extentM: Double?
        let createdAt: String
    }

    enum StoreError: Error {
        case badStatus(Int)
        case corrupt
    }

    // MARK: - Serialization

    /// NSKeyedArchiver output compresses ~4:1 with LZFSE; maps go from tens of
    /// MB to a few, which matters on conference wifi.
    static func serialize(_ map: ARWorldMap) throws -> Data {
        let raw = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
        return compress(raw) ?? raw
    }

    static func deserialize(_ data: Data) throws -> ARWorldMap {
        let raw = decompress(data) ?? data
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: raw) else {
            throw StoreError.corrupt
        }
        return map
    }

    // MARK: - Network

    static func upload(
        _ map: ARWorldMap,
        pieceId: Int?,
        location: CLLocation,
        featurePoints: Int = 0,
        extentM: Float = 0
    ) async throws -> Record {
        let blob = try serialize(map)

        var request = URLRequest(url: APIClient.baseURL.appendingPathComponent("api/worldmaps"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Feature count and extent are how we tell a substantive scan from a
        // glance at one wall, without downloading the map to find out.
        var meta: [String: Any] = [
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "featurePoints": featurePoints,
            "extentM": Double(extentM),
        ]
        if let pieceId { meta["pieceId"] = pieceId }

        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"map\"; filename=\"scan.armap\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(blob)
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

    /// Nearby scans, nearest first.
    static func nearby(location: CLLocation, radiusM: Double = 100) async throws -> [Record] {
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

    static func download(_ record: Record) async throws -> ARWorldMap {
        let url = APIClient.baseURL.appendingPathComponent("uploads").appendingPathComponent(record.mapPath)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StoreError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try deserialize(data)
    }

    // MARK: - Compression (LZFSE with a 4-byte magic + length header)

    private static let magic = Data("GOTM".utf8)

    private static func compress(_ data: Data) -> Data? {
        let compressed = transform(data, encode: true)
        guard let compressed, compressed.count + 12 < data.count else { return nil }
        var out = magic
        var length = UInt64(data.count).littleEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(compressed)
        return out
    }

    private static func decompress(_ data: Data) -> Data? {
        guard data.count > 12, data.prefix(4) == magic else { return nil }
        let length = data.subdata(in: 4..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        guard length > 0, length < 512 * 1024 * 1024 else { return nil }
        return transform(data.dropFirst(12), encode: false, capacity: Int(length))
    }

    private static func transform(_ data: Data, encode: Bool, capacity: Int? = nil) -> Data? {
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
