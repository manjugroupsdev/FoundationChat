import Foundation

/// Only fixed code dimensions cross this boundary, never arbitrary URLs or messages.
nonisolated enum MobileTelemetryPolicy {
    static let maxQueue = 60
    static let batchSize = 20
    static let flushInterval: TimeInterval = 60
    static let repeatInterval: TimeInterval = 600
    static let maxAge: TimeInterval = 3 * 86_400
    private static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    private static let segments = Set(("api hr auth attendance punch-in punch-out today my sessions session shifts " +
        "leaves leave permissions permission balance usage apply cancel list detail staff profile departments " +
        "designations roles policies policy settings mobile alerts notifications read unread mark-read " +
        "marketing clientPlaceVisits siteVisits cpVisits visits visit start end complete outcome approval " +
        "approve reject requests create update delete search projects project clients client lead leads " +
        "tracking geotrack location batch heartbeat tamper-events current day-status timeline trips " +
        "live route session-route snapped-route nearby-staff geocode-address places consent status stop " +
        "fleet travel-desk bookings dispatch driver drivers vehicles vehicle allocation cab cab-requests " +
        "chat channels messages poll typing presence members dms unread-count read-receipts send " +
        "storage upload download upload-url url lens enroll enrollment photos photo face captures " +
        "login logout verify-otp send-otp validate-session refresh password employee token device " +
        "daily-logs daily-log tasks dashboard summary stats stats-monthly monthly reports calendar " +
        "iam access work-from-home on-duty fines loans payroll payslips collections accounts land " +
        "front-desk visitors post-sales telecaller calls dialer notifications-list mobile-alerts").split(separator: " ").map(String.init))

    static func route(_ path: String) -> String {
        let bare = path.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
        return "/" + bare.split(separator: "/").prefix(12).map { segments.contains(String($0)) ? String($0) : ":id" }.joined(separator: "/")
    }
    static func method(_ value: String?) -> String {
        let value = value ?? "GET"
        return methods.contains(value) ? value : "OTHER"
    }
    static func service(_ host: String?, authority: String?) -> String? {
        guard let host = host?.lowercased() else { return nil }
        switch host {
        case authority?.lowercased(): return "mms"
        case "api-geo.theairix.com": return "geotrack"
        case "mg.theairix.com": return "storage"
        case "api-dialer.theairix.com", "dialer.theairix.com": return "dialer"
        case "api-telecaller.theairix.com": return "telecaller"
        default: return nil
        }
    }
    static func symbol(_ value: String) -> String {
        let value = String(value.prefix(160))
        return value.range(of: #"^[A-Za-z_$][A-Za-z0-9_.$<>:-]{0,159}$"#, options: .regularExpression) != nil ? value : "Unknown"
    }
    static func retryDelay(status: Int?, failures: Int, retryAfter: Double?) -> TimeInterval {
        let exponential = min(21_600, 600 * pow(2, Double(min(5, max(0, failures - 1)))))
        let minimum = [400, 401, 403, 404, 413].contains(status ?? 0) ? 21_600 : exponential
        return max(minimum, min(21_600, max(0, retryAfter ?? 0)))
    }
}

nonisolated struct MobileTelemetryBudget {
    var day: Int = -1
    var errors = 0
    var timings = 0
    var exceptions = 0
    private var seen: [String: TimeInterval] = [:]
    private var successes = 0

    init(day: Int = -1, errors: Int = 0, timings: Int = 0, exceptions: Int = 0) {
        self.day = day; self.errors = errors; self.timings = timings; self.exceptions = exceptions
    }
    mutating func accept(_ signature: String, timing: Bool, healthy: Bool, now: TimeInterval, exception: Bool = false) -> Bool {
        let currentDay = Int(now / 86_400)
        if day != currentDay { day = currentDay; errors = 0; timings = 0; exceptions = 0; seen.removeAll() }
        if healthy { successes += 1; if successes % 20 != 0 { return false } }
        if timing && timings >= 20 || !timing && errors >= 40 { return false }
        if exception && exceptions >= 8 { return false }
        if let previous = seen[signature], now - previous < MobileTelemetryPolicy.repeatInterval { return false }
        if seen.count >= 64, let oldest = seen.min(by: { $0.value < $1.value })?.key { seen.removeValue(forKey: oldest) }
        seen[signature] = now
        if timing { timings += 1 } else { errors += 1 }
        if exception { exceptions += 1 }
        return true
    }
}
