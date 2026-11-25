import Foundation

/// Short place name shown for a clock-in / clock-out selfie, e.g.
/// "Ekkattuthangal, Chennai". Display only: the punch still sends the raw
/// latitude / longitude and the full address unchanged.
///
/// Built from the area (sub-locality) and the city (locality, or the district
/// when the geocoder gives no city). At most two parts, never the street or
/// house number. When nothing usable comes back the screen shows
/// `compactCoordinates` instead, so the selfie never loses its location.
/// Mirrors Android `PunchPlaceLabel`.
enum PunchPlaceLabel {
    static let maxPartLength = 32

    static func shortName(subLocality: String?, locality: String?, subAdminArea: String?) -> String? {
        let area = clean(subLocality)
        let city = clean(locality) ?? clean(subAdminArea)
        // Area equal to the city ("Coimbatore, Coimbatore") shows the city once.
        let parts: [String]
        if let area, let city, area.caseInsensitiveCompare(city) == .orderedSame {
            parts = [city]
        } else {
            parts = [area, city].compactMap { $0 }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func compactCoordinates(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    /// The line to show: place name when known, else the compact coordinates.
    static func overlayText(placeName: String?, latitude: Double?, longitude: Double?) -> String {
        if let placeName, !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return placeName
        }
        guard let latitude, let longitude else { return "Location unavailable" }
        return compactCoordinates(latitude: latitude, longitude: longitude)
    }

    private static func clean(_ raw: String?) -> String? {
        let value = (raw ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if value.isEmpty { return nil }
        // Postcodes and plus codes ("600032", "2WX4+2M") are not place names.
        if !value.contains(where: { $0.isLetter }) || isPlusCode(value) { return nil }
        if value.count <= maxPartLength { return value }
        let head = String(value.prefix(maxPartLength - 1))
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func isPlusCode(_ value: String) -> Bool {
        value.range(
            of: #"^[23456789CFGHJMPQRVWX]{2,8}\+[23456789CFGHJMPQRVWX]{0,3}\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
