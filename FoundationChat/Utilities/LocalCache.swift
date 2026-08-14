import Foundation

/// Tiny on-disk cache for API responses, so data-loading screens can paint
/// INSTANTLY from the last-known snapshot and then refresh in the background
/// ("cache-first" loading), and keep showing the last data while OFFLINE.
///
/// Swift mirror of the Android `ui/common/LocalCache` used across Home/Dashboard/
/// Chat/lists. Design:
///  - One JSON file per key under Application Support/`response_cache/` (durable,
///    excluded from iCloud backup — it's a rebuildable cache, network stays the
///    source of truth).
///  - A dumb key -> JSON store: callers namespace their own keys (include the
///    signed-in staffId and any date/scope) so one user never reads another's
///    cached data. `clearAll()` is also called on logout as a safety net.
///  - Each entry stores a timestamp so callers can treat very old data as stale
///    (`entry(...)`); `get(...)` ignores age.
///  - Every op is failure-swallowing: a miss / corrupt file / IO error never
///    throws — the network path stays authoritative.
enum LocalCache {

    private static let dirName = "response_cache"

    struct Entry<T> {
        let value: T
        let savedAt: Date
    }

    // MARK: - Location

    private static var directory: URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent(dirName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                // Cache dir: keep it out of iCloud/iTunes backup.
                var mutable = dir
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? mutable.setResourceValues(values)
            } catch {
                return nil
            }
        }
        return dir
    }

    private static func fileURL(for key: String) -> URL? {
        guard let dir = directory else { return nil }
        // Sanitize so an arbitrary key is always a valid filename.
        let safe = key.replacingOccurrences(
            of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression
        )
        return dir.appendingPathComponent("\(safe).json")
    }

    // MARK: - Wrappers ({v, t}, t = epoch millis, mirroring Android)

    private struct WriteWrapper<T: Encodable>: Encodable {
        let v: T
        let t: Double
    }
    private struct ReadWrapper<T: Decodable>: Decodable {
        let v: T
        let t: Double?
    }

    // MARK: - API

    /// Store `value` under `key` (JSON, with a save timestamp).
    static func put<T: Encodable>(_ key: String, _ value: T, now: Date = Date()) {
        guard let url = fileURL(for: key) else { return }
        let wrapped = WriteWrapper(v: value, t: now.timeIntervalSince1970 * 1000)
        do {
            let data = try JSONEncoder().encode(wrapped)
            try data.write(to: url, options: .atomic)
        } catch {
            // best-effort — never surface a cache write failure
        }
    }

    /// Cached value for `key`, or nil if absent/unparseable. Ignores age.
    static func get<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        entry(key, as: type)?.value
    }

    /// Cached value + when it was saved, so callers can gate on staleness.
    static func entry<T: Decodable>(_ key: String, as type: T.Type = T.self) -> Entry<T>? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let wrapped = try? JSONDecoder().decode(ReadWrapper<T>.self, from: data)
        else { return nil }
        let savedAt = Date(timeIntervalSince1970: (wrapped.t ?? 0) / 1000)
        return Entry(value: wrapped.v, savedAt: savedAt)
    }

    /// Remove a single key.
    static func remove(_ key: String) {
        guard let url = fileURL(for: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Wipe everything — call on logout so a new user starts clean.
    static func clearAll() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
