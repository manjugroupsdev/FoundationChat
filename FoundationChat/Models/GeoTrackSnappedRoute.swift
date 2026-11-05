import CoreLocation
import Foundation

/// GET {geo}/api/geotrack/snapped-route: the day's route matched to roads.
struct GeoTrackSnappedRouteResponse: Decodable {
    let success: Bool?
    let data: GeoTrackSnappedRouteData?
    let error: String?
}

struct GeoTrackSnappedRouteData: Decodable {
    let segments: [GeoTrackSnappedSegment]?
}

/// One piece of the route: snapped / routed follow roads (draw solid);
/// gap / estimated are inferred or lack road data (draw dashed).
struct GeoTrackSnappedSegment: Decodable, Identifiable, Equatable {
    let kind: String?
    let startedAt: String?
    let endedAt: String?
    let encodedPolyline: String?

    var id: String { "\(startedAt ?? "")-\(endedAt ?? "")-\(kind ?? "")" }
    var isDashed: Bool { kind == "gap" || kind == "estimated" }
    var coordinates: [CLLocationCoordinate2D] { Self.decode(encodedPolyline ?? "") }

    /// Google encoded polyline (precision 5) → coordinates.
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(encoded.utf8)
        var out: [CLLocationCoordinate2D] = []
        var index = 0
        var lat = 0
        var lng = 0
        while index < bytes.count {
            var values = [0, 0]
            for axis in 0..<2 {
                var result = 0
                var shift = 0
                var byte = 0
                repeat {
                    guard index < bytes.count else { return out }
                    byte = Int(bytes[index]) - 63
                    index += 1
                    result |= (byte & 0x1f) << shift
                    shift += 5
                } while byte >= 0x20
                values[axis] = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
            lat += values[0]
            lng += values[1]
            out.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5))
        }
        return out
    }
}
