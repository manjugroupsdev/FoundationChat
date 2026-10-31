import Foundation

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
