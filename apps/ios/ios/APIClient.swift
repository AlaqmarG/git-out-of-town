import Foundation
import UIKit

enum APIError: Error {
    case badStatus(Int)
    case decoding(Error)
}

/// Mirror of `Piece` from `packages/shared` — the server emits camelCase.
struct PieceDTO: Decodable {
    let id: Int
    let lat: Double
    let lng: Double
    let heading: Double?
    let accuracyM: Double?
    let rawImagePath: String
    let finalImagePath: String?
    let sceneImagePath: String?
    let kind: String
    let stickerId: String?
    let client: String
    let surfaceType: String?
    let usedGeoAnchor: Bool
    let altitudeM: Double?
    let placementTransform: [Double]?
    let markerTransform: [Double]?
    let createdAt: String
    let city: String?
    let colors: [RgbDTO]?
    let strokeCount: Int?
    let durationMs: Int?
}

struct RgbDTO: Codable {
    let r: Int
    let g: Int
    let b: Int
}

/// Mirror of `CreatePieceRequest` — sent as the `meta` JSON part.
struct MetaDTO: Encodable {
    let lat: Double
    let lng: Double
    let heading: Double?
    let accuracyM: Double?
    let kind: String
    let stickerId: String?
    let sessionId: String
    let client: String
    let surfaceType: String?
    let distanceM: Double?
    let devicePitch: Double?
    let usedGeoAnchor: Bool
    let hasLidar: Bool?
    let altitudeM: Double?
    let placementTransform: [Double]?
    let markerTransform: [Double]?
    let colors: [RgbDTO]?
    let strokeCount: Int?
    let durationMs: Int?
}

extension PieceDTO: Identifiable {}

enum APIClient {
    // nonisolated: the world-map upload path runs off the main actor so a
    // multi-MB archive+compress can't stall the render loop, and it needs this.
    nonisolated static let baseURL = URL(string: "https://gitoutoftown.129-153-49-190.sslip.io")!

    /// URL for a stored image path (`rawImagePath`, `finalImagePath`, …).
    static func imageURL(path: String) -> URL {
        baseURL.appendingPathComponent("uploads").appendingPathComponent(path)
    }

    /// Pieces inside a radius of a point.
    static func listPieces(lat: Double, lng: Double, radiusMeters: Double) async throws -> [PieceDTO] {
        let latDelta = radiusMeters / 111320
        let lngDelta = radiusMeters / (111320 * cos(lat * .pi / 180))
        return try await listPieces(
            west: lng - lngDelta,
            south: lat - latDelta,
            east: lng + lngDelta,
            north: lat + latDelta
        )
    }

    /// Pieces inside a bounding box — what the map camera is looking at.
    static func listPieces(west: Double, south: Double, east: Double, north: Double) async throws -> [PieceDTO] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/pieces"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(
            name: "bbox",
            value: "\(max(west, -180)),\(max(south, -90)),\(min(east, 180)),\(min(north, 90))"
        )]

        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        struct Response: Decodable { let pieces: [PieceDTO] }
        do {
            return try JSONDecoder().decode(Response.self, from: data).pieces
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// POST /api/pieces — multipart/form-data with `image` (PNG) + optional
    /// `scene` (camera frame) + `meta` (JSON).
    static func uploadPiece(imagePNG: Data, sceneData: Data? = nil, meta: MetaDTO) async throws -> PieceDTO {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pieces"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"art.png\"\r\n")
        body.append("Content-Type: image/png\r\n\r\n")
        body.append(imagePNG)
        body.append("\r\n")
        if let sceneData {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"scene\"; filename=\"scene.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(sceneData)
            body.append("\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"meta\"\r\n\r\n")
        body.append(try JSONEncoder().encode(meta))
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            let piece = try JSONDecoder().decode(PieceDTO.self, from: data)
            requestTransform(id: piece.id)
            return piece
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Kicks off the server-side Replicate restyle. Fire-and-forget: the raw
    /// art is already saved and shown; the polished version swaps in when the
    /// map next refreshes. A failure here must never surface to the user.
    private static func requestTransform(id: Int) {
        Task {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/transform"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["id": id])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    /// Downloads an image for use as a quad texture. Cached — the AR view
    /// re-requests the same paths every few seconds as pieces come and go.
    static func loadImage(path: String) async throws -> UIImage {
        if let cached = imageCache.object(forKey: path as NSString) {
            return cached
        }
        let (data, response) = try await URLSession.shared.data(from: imageURL(path: path))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let image = UIImage(data: data) else {
            throw APIError.decoding(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not an image")))
        }
        imageCache.setObject(image, forKey: path as NSString)
        return image
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
