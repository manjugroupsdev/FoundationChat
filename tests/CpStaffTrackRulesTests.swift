import Foundation

@main
struct CpStaffTrackRulesTests {
    static func main() {
        typealias R = CpStaffTrackRules
        let min = 60_000.0
        let nov22 = 1795350273286.0 // 22 Nov 2026 17:54 IST
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }

        // Running is decided by trip status, not by a recorded start.
        let now = nov22 + 36 * 60 * min
        let unknownStart = R.tripWindow(startedAt: nil, completedAt: nil, status: "enroute", now: now)!
        check(unknownStart.open && !unknownStart.startKnown, "enroute without start is running, start unknown")
        check(unknownStart.start == R.istStartOfDay(now) && unknownStart.end == now, "duty window is today IST")
        check(R.tripWindow(startedAt: nil, completedAt: nil, status: "In-Progress", now: now)!.open, "in-progress runs")
        check(R.tripWindow(startedAt: nil, completedAt: nil, status: "scheduled", now: now) == nil, "scheduled: no window")
        check(R.tripWindow(startedAt: now - 60 * min, completedAt: nil, status: nil, now: now)!.open, "start alone runs")
        check(!R.tripWindow(startedAt: now - 60 * min, completedAt: nil, status: "completed", now: now)!.open, "completed stops")

        // Day chunks never exceed 24 h; latest 4 days kept.
        let chunks = R.dayChunks(R.Window(start: nov22, end: nov22 + 60 * 60 * min, open: true))
        check(chunks.count == 4, "22-25 Nov is 4 chunks")
        check(chunks.first!.start == nov22 && chunks.last!.end == nov22 + 60 * 60 * min, "chunks cover the window")
        check(chunks.allSatisfy { $0.end - $0.start <= 24 * 60 * min }, "each chunk <= 24 h")
        check(R.dayChunks(R.Window(start: nov22, end: nov22 + 7 * 24 * 60 * min, open: true)).count == 4, "cap 4 days")
        check(R.istDates(R.Window(start: nov22, end: nov22 + 36 * 60 * min, open: true)) == ["2026-11-22", "2026-11-23", "2026-11-24"], "IST dates")

        // Paths split at overnight gaps and jumps; distance only along drawn pieces.
        func p(_ lat: Double, _ at: Double?) -> CpTrackPoint { CpTrackPoint(lat: lat, lng: 80.2, atMs: at) }
        let pieces = R.splitAtGaps([
            p(13.00, 0), p(13.01, 4 * min), p(13.02, 8 * min),
            p(12.84, 14 * 60 * min), p(12.85, 14 * 60 * min + 3 * min),
            p(13.35, 14 * 60 * min + 3 * min + 30_000), p(13.36, 14 * 60 * min + 8 * min),
        ])
        check(pieces.map(\.count) == [3, 2, 2], "split at overnight gap and jump")
        check(R.splitAtGaps([p(13.0, 0), p(13.0001, 3 * 60 * min)]).count == 1, "long stop is not a gap")
        let meters = R.segmentsDistance(R.splitAtGaps([p(13.00, 0), p(13.01, 4 * min), p(12.80, 14 * 60 * min), p(12.81, 14 * 60 * min + 4 * min)]))!
        check(meters > 2000 && meters < 2500, "overnight hop not counted")

        // Labels.
        check(R.distanceLabel(82_000, since: nov22, now: nov22 + 37 * 60 * min) == "82.0 km travelled since 22 Nov", "since label")
        check(R.distanceLabel(3_420, since: now - 60 * min, now: now) == "3.4 km travelled", "same-day label")
        check(R.distanceLabel(nil, now: now) == "Distance —", "no distance")
        check(R.clockLabel(nov22, now: nov22 + 60 * min) == "05:54 PM", "clock today")
        check(R.clockLabel(nov22, now: nov22 + 48 * 60 * min) == "22 Nov, 05:54 PM", "clock other day")
        check(R.locationLabel(lastSeenMs: nil, trackingActive: false, now: now) == "No recent location", "no fix")
        check(R.locationLabel(lastSeenMs: now - 2 * min, trackingActive: true, now: now) == "Live · 2 min ago", "live label")

        // Live fix visibility (duty window).
        let window = R.Window(start: 10 * min, end: 20 * min, open: false)
        check(R.liveFixVisible(lat: 13, lng: 80, lastSeenMs: 90 * min, trackingActive: true, window: nil), "tracking shows")
        check(R.liveFixVisible(lat: 13, lng: 80, lastSeenMs: 15 * min, trackingActive: false, window: window), "in-window shows")
        check(!R.liveFixVisible(lat: 13, lng: 80, lastSeenMs: 90 * min, trackingActive: false, window: window), "off-duty hidden")
        check(!R.liveFixVisible(lat: 0, lng: 0, lastSeenMs: 15 * min, trackingActive: true, window: window), "0,0 hidden")

        // Access to another staff member's route.
        check(R.canReadRouteDirectly(staffId: "a", viewerStaffId: "a", viewerCanViewAllTracking: false), "self")
        check(!R.canReadRouteDirectly(staffId: "b", viewerStaffId: "a", viewerCanViewAllTracking: false), "other, no access")
        check(R.canReadRouteDirectly(staffId: "b", viewerStaffId: "a", viewerCanViewAllTracking: true), "other, liveTracking")

        // Motion mapping and the running-trip gate.
        check(R.motion(movementMode: "stationary", activity: "IN_VEHICLE", speedMps: 20) == .idle, "mode first")
        check(R.motion(movementMode: "two_wheeler", activity: nil, speedMps: nil) == .moving, "two wheeler moving")
        check(R.motion(movementMode: "anomaly", activity: "IN_VEHICLE", speedMps: 20) == nil, "anomaly nothing")
        check(R.motion(movementMode: nil, activity: "ON_FOOT", speedMps: nil) == .walking, "activity")
        check(R.motion(movementMode: nil, activity: "UNKNOWN", speedMps: 1.2) == .walking, "speed")
        check(R.motion(movementMode: nil, activity: "UNKNOWN", speedMps: nil) == nil, "no guess")
        check(R.motionToShow(motion: .moving, tripInProgress: true, lastSeenMs: now - 2 * min, trackingActive: true, now: now) == .moving, "shown while running")
        check(R.motionToShow(motion: .moving, tripInProgress: false, lastSeenMs: now - 2 * min, trackingActive: true, now: now) == nil, "not before/after trip")
        check(R.motionToShow(motion: .moving, tripInProgress: true, lastSeenMs: now - 30 * min, trackingActive: true, now: now) == nil, "not on stale fix")
        check(R.motionToShow(motion: .moving, tripInProgress: true, lastSeenMs: now - 2 * min, trackingActive: false, now: now) == nil, "not off duty")

        print("CpStaffTrackRules: \(count) assertions passed")
    }
}
