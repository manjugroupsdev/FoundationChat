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

    struct RoadMatchedLeg: Sendable {
        let points: [CLLocationCoordinate2D]
        let isRoadMatched: Bool
    }

    struct RoadMatchedTrail: Sendable {
        let legs: [RoadMatchedLeg]
        let sourcePointCount: Int
        let anchorCount: Int

        var matchedLegCount: Int { legs.filter { $0.isRoadMatched }.count }
        var isFullyMatched: Bool { !legs.isEmpty && matchedLegCount == legs.count }
    }

    let geoAPI: GeoTrackAPIService

    init(geoAPI: GeoTrackAPIService? = nil) {
        self.geoAPI = geoAPI ?? GeoTrackAPIService.shared
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

    /// Builds display-only road geometry through ordered anchors from the recorded trail.
    /// Recorded samples and recorded distance remain the trip evidence.
    func fetchRoadMatchedTrail(
        recordedPoints: [CLLocationCoordinate2D],
        maxAnchors: Int = 8
    ) async -> RoadMatchedTrail? {
        guard recordedPoints.count >= 2 else { return nil }
        let anchors = Self.selectRouteAnchors(recordedPoints, maxAnchors: maxAnchors)
        guard anchors.count >= 2 else { return nil }

        var legs: [RoadMatchedLeg] = []
        for index in 0..<(anchors.count - 1) {
            let origin = anchors[index]
            let destination = anchors[index + 1]
            if let routed = await fetchDriving(origin: origin, destination: destination),
               routed.polyline.count >= 2 {
                legs.append(RoadMatchedLeg(points: routed.polyline, isRoadMatched: true))
            } else {
                legs.append(RoadMatchedLeg(points: [origin, destination], isRoadMatched: false))
            }
        }
        return RoadMatchedTrail(
            legs: legs,
            sourcePointCount: recordedPoints.count,
            anchorCount: anchors.count
        )
    }

    static func selectRouteAnchors(
        _ points: [CLLocationCoordinate2D],
        maxAnchors: Int
    ) -> [CLLocationCoordinate2D] {
        let limit = max(2, maxAnchors)
        let cleaned = points.reduce(into: [CLLocationCoordinate2D]()) { result, point in
            if result.last.map({ distanceMeters($0, point) >= 5 }) ?? true {
                result.append(point)
            }
        }
        guard cleaned.count > 2 else { return cleaned }

        var tolerance = 12.0
        var simplified = simplify(cleaned, toleranceMeters: tolerance)
        while simplified.count > limit && tolerance < 250 {
            tolerance *= 1.5
            simplified = simplify(cleaned, toleranceMeters: tolerance)
        }
        guard simplified.count > limit else { return simplified }

        let lastIndex = simplified.count - 1
        var result: [CLLocationCoordinate2D] = []
        for slot in 0..<limit {
            let index = Int(Double(slot * lastIndex) / Double(limit - 1))
            if result.last.map({ distanceMeters($0, simplified[index]) > 0.1 }) ?? true {
                result.append(simplified[index])
            }
        }
        return result
    }

    private static func simplify(
        _ points: [CLLocationCoordinate2D],
        toleranceMeters: Double
    ) -> [CLLocationCoordinate2D] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var furthestIndex = -1
        var furthestDistance = 0.0
        for index in 1..<(points.count - 1) {
            let distance = distanceToSegmentMeters(points[index], first, last)
            if distance > furthestDistance {
                furthestDistance = distance
                furthestIndex = index
            }
        }
        guard furthestIndex >= 0, furthestDistance > toleranceMeters else { return [first, last] }
        let before = simplify(Array(points[0...furthestIndex]), toleranceMeters: toleranceMeters)
        let after = simplify(Array(points[furthestIndex...]), toleranceMeters: toleranceMeters)
        return Array(before.dropLast()) + after
    }

    private static func distanceToSegmentMeters(
        _ point: CLLocationCoordinate2D,
        _ start: CLLocationCoordinate2D,
        _ end: CLLocationCoordinate2D
    ) -> Double {
        let referenceLatitude = (start.latitude + end.latitude + point.latitude) / 3
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(referenceLatitude * .pi / 180)
        let px = (point.longitude - start.longitude) * metersPerDegreeLongitude
        let py = (point.latitude - start.latitude) * metersPerDegreeLatitude
        let ex = (end.longitude - start.longitude) * metersPerDegreeLongitude
        let ey = (end.latitude - start.latitude) * metersPerDegreeLatitude
        let lengthSquared = ex * ex + ey * ey
        guard lengthSquared > 0 else { return hypot(px, py) }
        let projection = min(1, max(0, (px * ex + py * ey) / lengthSquared))
        return hypot(px - projection * ex, py - projection * ey)
    }

    private static func distanceMeters(
        _ first: CLLocationCoordinate2D,
        _ second: CLLocationCoordinate2D
    ) -> Double {
        let latitudeMeters = (second.latitude - first.latitude) * 111_320
        let meanLatitude = (first.latitude + second.latitude) / 2 * .pi / 180
        let longitudeMeters = (second.longitude - first.longitude) * 111_320 * cos(meanLatitude)
        return hypot(latitudeMeters, longitudeMeters)
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
