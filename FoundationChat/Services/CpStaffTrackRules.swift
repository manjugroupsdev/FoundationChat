import Foundation

// Pure rules for the CP trip map's staff tracks (MMS-271). Foundation only so
// tests/CpStaffTrackRulesTests.swift can run them with swiftc. Mirrors
// Android's CpStaffTrackPolicy (ui/home/CpStaffTracks.kt).

nonisolated struct CpTrackPoint: Equatable, Sendable {
    var lat: Double
    var lng: Double
    /// Epoch milliseconds; nil for road-matched points (no per-point time).
    var atMs: Double?
}

nonisolated enum CpTrackMotion: String, Sendable {
    case moving = "Moving"
    case walking = "Walking"
    case idle = "Idle"
}

nonisolated enum CpStaffTrackRules {
    /// A heartbeat this old is shown as "last seen", not live.
    static let liveFreshMs: Double = 10 * 60_000
    /// A silence this long between fixes that also moved this far is a gap, not a road.
    static let gapMs: Double = 10 * 60_000
    static let gapMinMeters: Double = 300
    /// Faster than this between two fixes is a jump, never a drawn line.
    static let maxSegmentSpeedMps: Double = 55
    /// Paths are read per IST day; long-open trips read only the latest days.
    static let maxDays = 4
    static let dayMs: Double = 24 * 60 * 60_000

    static let ist = TimeZone(identifier: "Asia/Kolkata")!

    private static let runningStatuses: Set<String> = [
        "in_progress", "started", "enroute", "en_route", "ongoing", "active",
        "arrived", "arrival_verified", "on_site", "reached", "reaching",
        "picked_up", "client_started", "pending_review", "reviewing",
    ]

    private static let finishedStatuses: Set<String> = [
        "completed", "complete", "done", "closed", "cancelled", "canceled",
        "postponed", "pending_gm_approval", "rejected", "no_show",
    ]

    struct Window: Equatable, Sendable {
        let start: Double
        let end: Double
        let open: Bool
        var startKnown: Bool = true
    }

    private static func normalized(_ status: String?) -> String? {
        guard let status else { return nil }
        let value = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return value.isEmpty ? nil : value
    }

    static func isRunningStatus(_ status: String?) -> Bool {
        guard let value = normalized(status) else { return false }
        return runningStatuses.contains(value)
    }

    static func isFinishedStatus(_ status: String?) -> Bool {
        guard let value = normalized(status) else { return false }
        return finishedStatuses.contains(value)
    }

    static func istStartOfDay(_ ms: Double) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ist
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: ms / 1000))
        return day.timeIntervalSince1970 * 1000
    }

    /// The trip window, with "running" decided from the trip STATUS:
    /// start recorded → start…completion (or now); running with no start →
    /// today's IST day (duty window); otherwise nil (not started).
    static func tripWindow(startedAt: Double?, completedAt: Double?, status: String?, now: Double) -> Window? {
        let finished = (completedAt ?? 0) > 0 || isFinishedStatus(status)
        let hasStart = (startedAt ?? 0) > 0
        let running = !finished && (isRunningStatus(status) || hasStart)
        if let startedAt, startedAt > 0 {
            if let completedAt, completedAt >= startedAt {
                return Window(start: startedAt, end: completedAt, open: false)
            }
            return Window(start: startedAt, end: max(startedAt, now), open: running)
        }
        guard running else { return nil }
        return Window(start: istStartOfDay(now), end: now, open: true, startKnown: false)
    }

    /// IST-day chunks (each ≤ 24 h), latest `max` only. The geo timeline /
    /// session-route refuse ranges over 48 h.
    static func dayChunks(_ window: Window, max: Int = maxDays) -> [(start: Double, end: Double)] {
        var chunks: [(start: Double, end: Double)] = []
        var start = window.start
        while start < window.end && chunks.count < 400 {
            let end = min(istStartOfDay(start) + dayMs - 1, window.end)
            chunks.append((start, end))
            start = end + 1
        }
        if chunks.isEmpty && window.end >= window.start { chunks.append((window.start, window.end)) }
        return Array(chunks.suffix(max))
    }

    static func istDates(_ window: Window, max: Int = maxDays) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ist
        formatter.dateFormat = "yyyy-MM-dd"
        var dates: [String] = []
        for chunk in dayChunks(window, max: Int.max) {
            let date = formatter.string(from: Date(timeIntervalSince1970: chunk.start / 1000))
            if dates.last != date { dates.append(date) }
        }
        return Array(dates.suffix(max))
    }

    static func liveFixVisible(lat: Double?, lng: Double?, lastSeenMs: Double?, trackingActive: Bool, window: Window?) -> Bool {
        guard let lat, let lng, lat.isFinite, lng.isFinite else { return false }
        if lat == 0, lng == 0 { return false }
        guard (-90...90).contains(lat), (-180...180).contains(lng) else { return false }
        guard let lastSeenMs, lastSeenMs > 0 else { return false }
        if trackingActive { return true }
        guard let window else { return false }
        return lastSeenMs >= window.start && lastSeenMs <= window.end
    }

    static func isStale(lastSeenMs: Double, trackingActive: Bool, now: Double) -> Bool {
        !trackingActive || now - lastSeenMs > liveFreshMs
    }

    static func canReadRouteDirectly(staffId: String, viewerStaffId: String?, viewerCanViewAllTracking: Bool) -> Bool {
        if viewerCanViewAllTracking { return true }
        guard let viewerStaffId, !viewerStaffId.isEmpty else { return false }
        return staffId == viewerStaffId
    }

    static func viewerIsInvolved(viewerStaffId: String?, involved: Set<String>) -> Bool {
        guard let viewerStaffId, !viewerStaffId.isEmpty else { return false }
        return involved.contains(viewerStaffId)
    }

    static func distanceMeters(_ a: CpTrackPoint, _ b: CpTrackPoint) -> Double {
        let radius = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    private static func isBreak(_ a: CpTrackPoint, _ b: CpTrackPoint) -> Bool {
        let meters = distanceMeters(a, b)
        guard let aAt = a.atMs, let bAt = b.atMs else { return meters > 1_000 }
        let dt = bAt - aAt
        if dt <= 0 { return meters > gapMinMeters }
        if dt > gapMs && meters > gapMinMeters { return true }
        return meters / (dt / 1000) > maxSegmentSpeedMps
    }

    /// Splits a cleaned path wherever the line would not be real travel
    /// (a silence that also moved, or an impossible speed). Pieces of fewer
    /// than two points are dropped; pieces are never joined.
    static func splitAtGaps(_ points: [CpTrackPoint]) -> [[CpTrackPoint]] {
        var pieces: [[CpTrackPoint]] = []
        var current: [CpTrackPoint] = []
        for point in points {
            if let previous = current.last, isBreak(previous, point) {
                if current.count >= 2 { pieces.append(current) }
                current = []
            }
            current.append(point)
        }
        if current.count >= 2 { pieces.append(current) }
        return pieces
    }

    /// Distance along the drawn pieces only; never across a gap between them.
    static func segmentsDistance(_ segments: [[CpTrackPoint]]) -> Double? {
        let drawn = segments.filter { $0.count >= 2 }
        guard !drawn.isEmpty else { return nil }
        return drawn.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) { $0 + distanceMeters($1.0, $1.1) }
        }
    }

    /// Only today's travel is drawn for a trip still open since an earlier
    /// IST day (or with no recorded start): days of driving are not "the trip".
    static func isTodayOnly(_ window: Window?, now: Double) -> Bool {
        guard let window, window.open else { return false }
        return !window.startKnown || !sameIstDay(window.start, now)
    }

    static func sameIstDay(_ a: Double, _ b: Double) -> Bool {
        istStartOfDay(a) == istStartOfDay(b)
    }

    /// "850 m travelled" / "3.4 km travelled".
    static func distanceLabel(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "Distance —" }
        return meters < 1000
            ? "\(Int(meters.rounded())) m travelled"
            : String(format: "%.1f km travelled", meters / 1000)
    }

    static func clockLabel(_ ms: Double, now: Double) -> String {
        format(ms, sameIstDay(ms, now) ? "hh:mm a" : "d MMM, hh:mm a")
    }

    private static func format(_ ms: Double, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ist
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    static func locationLabel(lastSeenMs: Double?, trackingActive: Bool, now: Double) -> String {
        guard let lastSeenMs else { return "No recent location" }
        let age = max(0, now - lastSeenMs)
        if trackingActive && age <= liveFreshMs {
            let minutes = Int(age / 60_000)
            return minutes < 1 ? "Live · just now" : "Live · \(minutes) min ago"
        }
        return "Last seen \(clockLabel(lastSeenMs, now: now))"
    }

    /// geo movementMode first, then activity recognition, then speed. Nil
    /// when nothing usable: never a guess.
    static func motion(movementMode: String?, activity: String?, speedMps: Double?) -> CpTrackMotion? {
        switch movementMode?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "stationary", "still", "idle": return .idle
        case "walking", "running", "on_foot": return .walking
        case "vehicle", "two_wheeler", "four_wheeler", "cycling", "in_vehicle", "driving": return .moving
        case "anomaly": return nil
        default: break
        }
        switch activity?.trimmingCharacters(in: .whitespaces).uppercased() {
        case "STILL": return .idle
        case "WALKING", "ON_FOOT", "RUNNING": return .walking
        case "IN_VEHICLE", "ON_BICYCLE", "CYCLING": return .moving
        default: break
        }
        guard let speed = speedMps, speed.isFinite, speed >= 0 else { return nil }
        if speed > maxSegmentSpeedMps { return nil }
        if speed < 0.5 { return .idle }
        if speed < 2.5 { return .walking }
        return .moving
    }

    /// Motion to show: only while the trip runs and the fix is live and fresh.
    static func motionToShow(
        motion: CpTrackMotion?, tripInProgress: Bool, lastSeenMs: Double?, trackingActive: Bool, now: Double
    ) -> CpTrackMotion? {
        guard tripInProgress, let lastSeenMs, !isStale(lastSeenMs: lastSeenMs, trackingActive: trackingActive, now: now) else {
            return nil
        }
        return motion
    }
}
