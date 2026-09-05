import Foundation

struct MapServiceCoordinate: Decodable, Sendable {
    let lat: Double?
    let lng: Double?
}

struct MapServiceAddressResult: Decodable, Identifiable, Sendable {
    let placeId: String?
    let name: String?
    let address: String?
    let location: MapServiceCoordinate?
    let types: [String]?

    var id: String {
        placeId ?? "\(name ?? "")|\(address ?? "")"
    }
}

private struct MapServiceSearchResponse: Decodable, Sendable {
    let results: [MapServiceAddressResult]
    let error: String?
}

private struct MapServiceReverseResult: Decodable, Sendable {
    let address: String?
}

private struct MapServiceReverseResponse: Decodable, Sendable {
    let results: [MapServiceReverseResult]
    let error: String?
}

enum MapServiceAPI {
    private static let baseURL = URL(string: "https://api-map-service.aivida.in/")!

    static func search(query: String, limit: Int = 6) async throws -> [MapServiceAddressResult] {
        var components = URLComponents(
            url: baseURL.appending(path: "api/address/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        let result = try await BackgroundJSONDecoder.decode(MapServiceSearchResponse.self, from: data)
        if let error = result.error, result.results.isEmpty {
            throw MapServiceError.message(error)
        }
        return result.results
    }

    static func reverseGeocode(latitude: Double, longitude: Double) async throws -> String? {
        var components = URLComponents(
            url: baseURL.appending(path: "api/geocode/reverse"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        let result = try await BackgroundJSONDecoder.decode(MapServiceReverseResponse.self, from: data)
        if let error = result.error, result.results.isEmpty {
            throw MapServiceError.message(error)
        }
        return result.results.first?.address
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}

private enum MapServiceError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}
