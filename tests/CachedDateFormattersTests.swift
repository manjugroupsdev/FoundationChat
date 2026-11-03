import Foundation

@main
struct CachedDateFormattersTests {
    static func main() {
        // Same configuration -> same instance (built once).
        precondition(CachedDateFormatters.formatter("h:mm a") === CachedDateFormatters.formatter("h:mm a"))
        precondition(CachedDateFormatters.formatter("h:mm a") !== CachedDateFormatters.formatter("h:mm a", posix: true))
        // Every API shape the old per-call parser accepted.
        let expected = Date(timeIntervalSince1970: 1_793_593_800) // 2026-11-02T04:30:00Z
        for raw in ["2026-11-02T04:30:00.000Z", "2026-11-02T04:30:00Z", "2026-11-02T10:00:00+05:30", "2026-11-02T10:00:00.000+05:30"] {
            guard let date = CachedDateFormatters.parseISO(raw) else { preconditionFailure("unparsed \(raw)") }
            precondition(abs(date.timeIntervalSince(expected)) < 0.001, raw)
        }
        precondition(CachedDateFormatters.parseISO(nil) == nil)
        precondition(CachedDateFormatters.parseISO("") == nil)
        precondition(CachedDateFormatters.parseISO("not a date") == nil)
        // Date-only keys parse with the POSIX formatter.
        precondition(CachedDateFormatters.formatter("yyyy-MM-dd", posix: true).date(from: "2026-11-02") != nil)
        // Safe under concurrent use.
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            let f = CachedDateFormatters.formatter(i % 2 == 0 ? "dd MMM" : "HH:mm", posix: true)
            _ = f.string(from: expected)
            _ = CachedDateFormatters.parseISO("2026-11-02T04:30:00Z")
        }
        print("CachedDateFormatters: 11 assertions passed")
    }
}
