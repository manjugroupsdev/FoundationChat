import CoreLocation
import Foundation

// MARK: - GeoTrackDirectionsClient

@MainActor
struct GeoTrackDirectionsClient {
    struct GeocodeResult: Sendable {
        let coordinate: CLLocationCoordinate2D
        let formattedAddress: String?
        let name: String?
    }

    struct DirectionsResult: Sendable {
        let polyline: [CLLocationCoordinate2D]
        let distanceMeters: Int
        let durationSeconds: Int
        let distanceText: String
        let durationText: String
    }

    let geoAPI: GeoTrackAPIService

    init(geoAPI: GeoTrackAPIService = .shared) {
        self.geoAPI = geoAPI
    }

    func geocodeAddress(_ address: String) async -> GeocodeResult? {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            let response = try await geoAPI.geocodeAddress(address)
            guard let lat = response.lat, let lng = response.lng else { return nil }
            return GeocodeResult(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                formattedAddress: response.formattedAddress,
                name: response.name
            )
        } catch {
            return nil
        }
    }

    func fetchDriving(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async -> DirectionsResult? {
        do {
            let response = try await geoAPI.route(
                originLat: origin.latitude,
                originLng: origin.longitude,
                destLat: destination.latitude,
                destLng: destination.longitude
            )
            guard let encoded = response.encodedPolyline, !encoded.isEmpty else { return nil }
            let distanceMeters = Int(response.distanceMeters ?? 0)
            let durationSeconds = Int(response.durationSeconds ?? 0)
            return DirectionsResult(
                polyline: Self.decodePolyline(encoded),
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                distanceText: Self.formatDistance(distanceMeters),
                durationText: Self.formatDuration(durationSeconds)
            )
        } catch {
            return nil
        }
    }

    private static func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        }
        return "\(meters) m"
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    private static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(encoded.count / 2)

        var index = encoded.startIndex
        var latitude = 0
        var longitude = 0

        while index < encoded.endIndex {
            guard let deltaLatitude = decodeNextValue(encoded, index: &index) else { break }
            guard let deltaLongitude = decodeNextValue(encoded, index: &index) else { break }

            latitude += deltaLatitude
            longitude += deltaLongitude

            coordinates.append(
                CLLocationCoordinate2D(
                    latitude: Double(latitude) / 100_000.0,
                    longitude: Double(longitude) / 100_000.0
                )
            )
        }

        return coordinates
    }

    private static func decodeNextValue(_ encoded: String, index: inout String.Index) -> Int? {
        var shift = 0
        var result = 0

        while index < encoded.endIndex {
            let scalar = encoded[index].unicodeScalars.first?.value ?? 63
            index = encoded.index(after: index)

            let byte = Int(scalar) - 63
            result |= (byte & 0x1f) << shift
            shift += 5

            if byte < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
        }

        return nil
    }
}
