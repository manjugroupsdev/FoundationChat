import Foundation

/// Reads the geo tracking service's wire format tolerantly.
///
/// The published mobile contract is epoch milliseconds and `_id`, but the Go
/// service sends RFC 3339 strings (`"2026-09-17T13:12:31.428Z"`, sometimes with
/// six fractional digits or a `+05:30` offset), `tripId`, `sessionId`,
/// `trackingActive` and `lastSeen`. Swift's synthesized decoding throws on the
/// first mismatched field and discards the WHOLE response, so on iOS the
/// timeline, trips, tamper events and session route were all unreadable.
/// Android has accepted both shapes since 4dff5204 (EpochMillisAdapter).
enum GeoTrackWire {
    /// Epoch milliseconds from an RFC 3339 / ISO 8601 string or a numeric string.
    nonisolated static func millis(from raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let number = Double(value) { return number }

        // yyyy-MM-ddTHH:mm:ss[.fraction](Z|±HH:MM|±HHMM)
        let parts = value.split(separator: "T", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let dateFields = parts[0].split(separator: "-").compactMap { Int($0) }
        guard dateFields.count == 3 else { return nil }

        var timeAndZone = parts[1]
        var offsetSeconds = 0
        if timeAndZone.hasSuffix("Z") || timeAndZone.hasSuffix("z") {
            timeAndZone.removeLast()
        } else if let signIndex = timeAndZone.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let zone = String(timeAndZone[signIndex...])
            timeAndZone = String(timeAndZone[..<signIndex])
            let sign = zone.hasPrefix("-") ? -1 : 1
            let digits = zone.dropFirst().filter(\.isNumber)
            guard digits.count == 4,
                  let hours = Int(digits.prefix(2)),
                  let minutes = Int(digits.suffix(2)) else { return nil }
            offsetSeconds = sign * (hours * 3600 + minutes * 60)
        }

        let clockAndFraction = timeAndZone.split(separator: ".", maxSplits: 1).map(String.init)
        let clock = clockAndFraction[0].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 3 else { return nil }
        var fraction = 0.0
        if clockAndFraction.count == 2 {
            let digits = clockAndFraction[1].filter(\.isNumber)
            guard !digits.isEmpty, let parsed = Double("0." + digits) else { return nil }
            fraction = parsed
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = dateFields[0]
        components.month = dateFields[1]
        components.day = dateFields[2]
        components.hour = clock[0]
        components.minute = clock[1]
        components.second = clock[2]
        guard let date = components.date else { return nil }
        let seconds = date.timeIntervalSince1970 + fraction - Double(offsetSeconds)
        return (seconds * 1000).rounded()
    }
}

extension KeyedDecodingContainer {
    /// A timestamp sent as epoch milliseconds (number) or an RFC 3339 string.
    nonisolated func geoMillisIfPresent(_ keys: Key...) -> Double? {
        for key in keys {
            if let number = try? decodeIfPresent(Double.self, forKey: key) { return number }
            if let text = try? decodeIfPresent(String.self, forKey: key),
               let millis = GeoTrackWire.millis(from: text) { return millis }
        }
        return nil
    }

    /// The first non-empty string among alternative key spellings.
    nonisolated func geoStringIfPresent(_ keys: Key...) -> String? {
        for key in keys {
            if let text = try? decodeIfPresent(String.self, forKey: key),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }

    nonisolated func geoDoubleIfPresent(_ key: Key) -> Double? {
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return number }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    nonisolated func geoIntIfPresent(_ key: Key) -> Int? {
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return number }
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return Int(number) }
        return nil
    }

    nonisolated func geoBoolIfPresent(_ keys: Key...) -> Bool? {
        for key in keys {
            if let flag = try? decodeIfPresent(Bool.self, forKey: key) { return flag }
        }
        return nil
    }
}
