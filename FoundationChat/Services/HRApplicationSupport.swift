import Foundation

struct PermissionShiftTiming {
    let startTime: String
    let endTime: String
    var isWorkDay = true

    func error(from: String?, to: String?) -> String? {
        guard isWorkDay else { return "Permissions cannot be requested on a week-off." }
        guard let start = Self.minutes(startTime), let end = Self.minutes(endTime), end > start else {
            return "Permission timing for this shift needs HR review."
        }
        guard let from, let to else { return nil }
        guard let fromMinutes = Self.minutes(from), let toMinutes = Self.minutes(to), toMinutes > fromMinutes else {
            return "To time must be after from time."
        }
        guard fromMinutes >= start, toMinutes <= end, fromMinutes == start || toMinutes == end else {
            return "Permission must start at \(startTime) or end at \(endTime), within your shift."
        }
        return nil
    }

    var defaultEndTime: String? {
        guard let start = Self.minutes(startTime), let end = Self.minutes(endTime), end > start else { return nil }
        let to = min(start + 60, end)
        return String(format: "%02d:%02d", to / 60, to % 60)
    }

    private static func minutes(_ value: String) -> Int? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

enum HRApplicationSupport {
    static func apiDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("yyyy-MM-dd", timeZone: timeZone).string(from: date)
    }

    static func apiTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("HH:mm", timeZone: timeZone).string(from: date)
    }

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    static func responseMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return text(object["error"]) ?? text(object["message"])
    }

    private static func text(_ value: Any?) -> String? {
        if let object = value as? [String: Any] { return text(object["message"]) }
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func submissionMessage(_ error: Error) -> String {
        if let error = error as? URLError, error.code == .timedOut {
            return "Request timed out. Check your request history before submitting again."
        }
        return error.localizedDescription
    }
}
