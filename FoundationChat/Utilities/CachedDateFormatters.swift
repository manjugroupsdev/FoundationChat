import Foundation

/// Shared, reused date formatters. Creating a `DateFormatter` or
/// `ISO8601DateFormatter` is expensive, and screens were creating new ones on
/// every render, per row and per call (the HR dashboard did it many times
/// per frame), which made scrolling and refreshes stutter. Formatters are
/// safe to share across threads once configured, so each configuration is
/// built once.
nonisolated enum CachedDateFormatters {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// A formatter for `format`. `posix` fixes the locale to en_US_POSIX for
    /// parsing/writing API values; otherwise it follows the device locale.
    static func formatter(_ format: String, posix: Bool = false) -> DateFormatter {
        let key = (posix ? "posix|" : "local|") + format
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        if posix { f.locale = Locale(identifier: "en_US_POSIX") }
        f.dateFormat = format
        formatters[key] = f
        return f
    }

    /// An API timestamp: ISO 8601 with or without fractional seconds, or the
    /// same written with an explicit offset.
    static func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = isoFractional.date(from: raw) { return date }
        if let date = isoPlain.date(from: raw) { return date }
        if let date = formatter("yyyy-MM-dd'T'HH:mm:ssXXX", posix: true).date(from: raw) { return date }
        return formatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", posix: true).date(from: raw)
    }
}
