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
    static let leavePastDateMessage = "Leave can't be applied for a past date."
    static let permissionPastDateMessage = "Permission can't be applied for a past date."

    /// Leave and permission are for today or later; a day before today is
    /// not selectable and is refused on submit (the server refuses it too).
    static func isPastDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }
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
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A plain-text reason (an HTML gateway page is dropped by clean).
            return clean(String(data: data, encoding: .utf8))
        }
        return clean(text(object["error"]) ?? text(object["message"]))
    }

    /// A server reason as a person should read it. Convex wraps a thrown
    /// Error as "Uncaught Error: <reason>\n    at handler (…)", sometimes
    /// behind "[CONVEX M(…)] [Request ID: …] Server Error". Nil when nothing
    /// readable is left (blank, markup, or a bare "Server Error").
    static func clean(_ raw: String?) -> String? {
        var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || text.hasPrefix("<") { return nil }
        for marker in ["Uncaught ConvexError:", "Uncaught Error:", "ConvexError:", "Uncaught:"] {
            if let range = text.range(of: marker, options: .backwards) {
                text = String(text[range.upperBound...])
            }
        }
        text = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        text = text.replacingOccurrences(of: #"\[(CONVEX [^\]]*|Request ID: [^\]]*)\]"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("Called by client") { text = String(text.dropLast("Called by client".count)) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("Error:") { text = String(text.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces) }
        if text.isEmpty || text.caseInsensitiveCompare("Server Error") == .orderedSame { return nil }
        return text
    }

    /// The reply never said what happened (timeout, or a 5xx with no reason):
    /// the request may have been saved, so check the history first.
    static func isAmbiguous(_ error: Error) -> Bool {
        if let error = error as? URLError { return error.code == .timedOut }
        return error.localizedDescription.hasPrefix("Request failed (5")
    }

    private static func text(_ value: Any?) -> String? {
        if let object = value as? [String: Any] { return text(object["message"]) }
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func submissionMessage(_ error: Error, application: String = "Request") -> String {
        if let error = error as? URLError, error.code == .timedOut {
            return "Request timed out. Check your request history before submitting again."
        }
        if isAmbiguous(error) {
            return "\(application) service is temporarily unavailable. Please try again shortly."
        }
        return clean(error.localizedDescription) ?? "Could not submit the request. Please try again."
    }
}
