import CoreLocation
import Foundation

// CP trip map: the staff who are ON a CP (both on a Joint CP), their latest
// heartbeat fix, and the path + distance they travelled for this trip.
// Read-only display data — mirrors Android's ui/home/CpStaffTracks.kt.
// Nothing here touches the trip, outcome, punch or tracking service flows.

struct CpStaffTrack: Identifiable, Sendable {
    struct LiveFix: Sendable {
        let lat: Double
        let lng: Double
        let lastSeenMs: Double
        let trackingActive: Bool
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }

    enum PathState: Sendable {
        /// A path with at least two fixes is drawn.
        case shown
        /// The trip has not started, so there is no trip path yet.
        case notStarted
        /// Started, but no fixes were recorded in the trip window.
        case noPoints
        /// This viewer may not read the path on this server version.
        case notAvailable
    }

    var id: String { staffId }
    let staffId: String
    let name: String
    let isPrimary: Bool
    /// Server-assigned Joint CP route colour ("#RRGGBB"), when there is one.
    let routeColor: String?
    let path: [GeoTrackTrackCleaner.Point]
    let distanceMeters: Double?
    let live: LiveFix?
    let pathState: PathState
    /// The trip has started and is not completed yet.
    let tripInProgress: Bool
}

/// A staff member known to be on the CP, from the CP detail payload.
struct CpInvolvedStaff: Sendable {
    let staffId: String
    let name: String?
    let isPrimary: Bool
    let routeColor: String?
    let startedAt: Double?
    let completedAt: Double?
    let recordedDistanceMeters: Double?
}

// MARK: - Wire models (every field optional: one odd value must not fail the parse)

struct CpStaffTracksResponse: Decodable, Sendable {
    let success: Bool?
    let data: CpStaffTracksData?
    let error: String?
}

struct CpStaffTracksData: Decodable, Sendable {
    let visitId: String?
    let cpType: String?
    let staff: [CpStaffTrackDTO]?
}

struct CpStaffTrackDTO: Decodable, Sendable {
    let staffId: String?
    let staffName: String?
    let isPrimary: Bool?
    let workflowRole: String?
    let routeColor: String?
    let startedAt: Double?
    let completedAt: Double?
    let tripOpen: Bool?
    let routeAvailable: Bool?
    let routePoints: [CpApprovalRoutePoint]?
    let distanceMeters: Double?
    let recordedDistanceMeters: Double?
    let live: CpStaffLiveFixDTO?
}

struct CpStaffLiveFixDTO: Decodable, Sendable {
    let lat: Double?
    let lng: Double?
    let lastSeen: Double?
    let trackingActive: Bool?
}

/// One geo-service live row, decoded for the CP map (RFC 3339 lastSeen,
/// and `trackingActive` read on its own — not folded into `isOnline`).
struct CpLiveStatusRow: Decodable, Sendable {
    let staffId: String?
    let lat: Double?
    let lng: Double?
    let lastSeenMs: Double?
    let trackingActive: Bool?

    private enum CodingKeys: String, CodingKey {
        case staffId, lat, lng, lastSeen, lastSeenAt, trackingActive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        staffId = c.geoStringIfPresent(.staffId)
        lat = c.geoDoubleIfPresent(.lat)
        lng = c.geoDoubleIfPresent(.lng)
        lastSeenMs = c.geoMillisIfPresent(.lastSeen, .lastSeenAt)
        trackingActive = c.geoBoolIfPresent(.trackingActive)
    }
}

struct CpLiveStatusRowsResponse: Decodable, Sendable {
    let success: Bool?
    let error: String?
    let data: [CpLiveStatusRow]?
}

/// Trimmed text, or nil when blank (the app's `nilIfBlank` helpers are file-private).
private func cpNonBlank(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Pure rules

enum CpStaffTrackPolicy {
    /// A heartbeat this old is shown as "last seen", not live.
    static let liveFreshMs: Double = 10 * 60_000

    struct Window: Equatable, Sendable {
        let start: Double
        let end: Double
        let open: Bool
    }

    /// Trip window: trip start to completion, or to `now` while it runs. Nil before the trip starts.
    static func window(startedAt: Double?, completedAt: Double?, now: Double) -> Window? {
        guard let startedAt, startedAt > 0 else { return nil }
        if let completedAt, completedAt >= startedAt {
            return Window(start: startedAt, end: completedAt, open: false)
        }
        return Window(start: startedAt, end: max(startedAt, now), open: true)
    }

    /// A heartbeat fix belongs on the map only while tracking runs (inside the
    /// staff member's clock-in → clock-out window) or when it was recorded
    /// during this trip. An old fix from another duty is never shown.
    static func liveFixVisible(lat: Double?, lng: Double?, lastSeenMs: Double?, trackingActive: Bool, window: Window?) -> Bool {
        guard let lat, let lng, lat.isFinite, lng.isFinite else { return false }
        if lat == 0, lng == 0 { return false }
        guard (-90...90).contains(lat), (-180...180).contains(lng) else { return false }
        guard let lastSeenMs, lastSeenMs > 0 else { return false }
        if trackingActive { return true }
        guard let window else { return false }
        return lastSeenMs >= window.start && lastSeenMs <= window.end
    }

    /// The geo service lets only admins / attendance.liveTracking holders read
    /// another staff member's route; everyone else silently gets their OWN
    /// route back. So the direct read is only used where it is safe.
    static func canReadRouteDirectly(staffId: String, viewerStaffId: String?, viewerCanViewAllTracking: Bool) -> Bool {
        if viewerCanViewAllTracking { return true }
        guard let viewerStaffId, !viewerStaffId.isEmpty else { return false }
        return staffId == viewerStaffId
    }

    static func viewerIsInvolved(viewerStaffId: String?, involved: Set<String>) -> Bool {
        guard let viewerStaffId, !viewerStaffId.isEmpty else { return false }
        return involved.contains(viewerStaffId)
    }

    static func cleanPath(_ fixes: [GeoTrackTrackCleaner.Fix], window: Window) -> [GeoTrackTrackCleaner.Point] {
        let inside = fixes
            .filter { fix in
                guard let at = fix.atMs else { return false }
                return at >= window.start && at <= window.end
            }
            .sorted { ($0.atMs ?? 0) < ($1.atMs ?? 0) }
        return GeoTrackTrackCleaner.clean(inside)
    }

    static func pathDistanceMeters(_ path: [GeoTrackTrackCleaner.Point]) -> Double? {
        guard path.count >= 2 else { return nil }
        var total = 0.0
        for index in 1..<path.count {
            total += GeoTrackTrackCleaner.distanceM(path[index - 1].lat, path[index - 1].lng, path[index].lat, path[index].lng)
        }
        return total
    }

    static func distanceLabel(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "Distance —" }
        if meters < 1000 { return "\(Int(meters.rounded())) m travelled" }
        return String(format: "%.1f km travelled", meters / 1000)
    }

    static func locationLabel(_ live: CpStaffTrack.LiveFix?, now: Double) -> String {
        guard let live else { return "No recent location" }
        let age = max(0, now - live.lastSeenMs)
        if live.trackingActive && age <= liveFreshMs {
            let minutes = Int(age / 60_000)
            return minutes < 1 ? "Live · just now" : "Live · \(minutes) min ago"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return "Last seen \(formatter.string(from: Date(timeIntervalSince1970: live.lastSeenMs / 1000)))"
    }

    /// Staff on the CP: Joint participants (primary first), else the assigned field staff.
    static func involvedStaff(_ cp: CpVisitDetail) -> [CpInvolvedStaff] {
        var seen = Set<String>()
        let participants = (cp.joint?.participants ?? [])
            .filter { participant in
                guard let id = participant.staffId?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return false }
                return seen.insert(id).inserted
            }
        if !participants.isEmpty {
            return participants
                .sorted { ($0.isPrimary ?? false) && !($1.isPrimary ?? false) }
                .map {
                    CpInvolvedStaff(
                        staffId: $0.staffId ?? "",
                        name: $0.staffName,
                        isPrimary: $0.isPrimary ?? false,
                        routeColor: $0.routeColor,
                        startedAt: $0.startedAt.map(Double.init),
                        completedAt: $0.completedAt.map(Double.init),
                        recordedDistanceMeters: $0.distanceMeters
                    )
                }
        }
        guard let staffId = cp.assignedStaffId?.trimmingCharacters(in: .whitespaces), !staffId.isEmpty else { return [] }
        return [
            CpInvolvedStaff(
                staffId: staffId,
                name: cp.assignedStaff?.name ?? cp.assignedStaff?.staffName,
                isPrimary: true,
                routeColor: nil,
                startedAt: cp.fieldVisit?.startedAt.map(Double.init),
                completedAt: cp.fieldVisit?.completedAt.map(Double.init),
                recordedDistanceMeters: cp.fieldVisit?.distanceMeters
            )
        ]
    }

    static func fromServer(_ dto: CpStaffTrackDTO, now: Double) -> CpStaffTrack? {
        guard let staffId = dto.staffId?.trimmingCharacters(in: .whitespaces), !staffId.isEmpty else { return nil }
        let window = window(startedAt: dto.startedAt, completedAt: dto.completedAt, now: now)
        let path: [GeoTrackTrackCleaner.Point] = window.map { w in
            cleanPath((dto.routePoints ?? []).map { GeoTrackTrackCleaner.Fix(lat: $0.lat, lng: $0.lng, accuracy: nil, atMs: $0.recordedAt) }, window: w)
        } ?? []
        var live: CpStaffTrack.LiveFix?
        if let fix = dto.live,
           liveFixVisible(lat: fix.lat, lng: fix.lng, lastSeenMs: fix.lastSeen, trackingActive: fix.trackingActive == true, window: window),
           let lat = fix.lat, let lng = fix.lng, let seen = fix.lastSeen {
            live = CpStaffTrack.LiveFix(lat: lat, lng: lng, lastSeenMs: seen, trackingActive: fix.trackingActive == true)
        }
        let state: CpStaffTrack.PathState
        if path.count >= 2 {
            state = .shown
        } else if window == nil {
            state = .notStarted
        } else if dto.routeAvailable == false {
            state = .notAvailable
        } else {
            state = .noPoints
        }
        return CpStaffTrack(
            staffId: staffId,
            name: dto.staffName.flatMap(cpNonBlank) ?? "Staff",
            isPrimary: dto.isPrimary == true,
            routeColor: dto.routeColor,
            path: path,
            distanceMeters: pathDistanceMeters(path) ?? dto.distanceMeters ?? dto.recordedDistanceMeters,
            live: live,
            pathState: state,
            tripInProgress: window?.open == true
        )
    }
}

// MARK: - Loader

/// Prefers the server's scoped `staff-tracks` route; while that route is not
/// deployed it falls back to the direct geo reads, reading another staff
/// member's path only where the geo service will return THAT staff member's rows.
enum CpStaffTracksLoader {
    enum Result: Sendable {
        case loaded([CpStaffTrack])
        /// The server says this viewer may not see these tracks.
        case forbidden
        case unavailable
    }

    /// Set after a 404 so an older server is not asked again this app session.
    nonisolated(unsafe) private static var serverRouteMissing = false

    static func load(
        token: String,
        cpId: String,
        involved: [CpInvolvedStaff],
        viewerStaffId: String?,
        viewerCanViewAllTracking: Bool,
        geoAPI: GeoTrackAPIService
    ) async -> Result {
        let now = Date().timeIntervalSince1970 * 1000
        if !serverRouteMissing {
            switch await MarketingConvexAPIService.getCpStaffTracks(token: token, id: cpId) {
            case .loaded(let rows):
                let tracks = rows.compactMap { CpStaffTrackPolicy.fromServer($0, now: now) }
                if !tracks.isEmpty || involved.isEmpty { return .loaded(tracks) }
            case .forbidden:
                return .forbidden
            case .notDeployed:
                serverRouteMissing = true
            case .failed:
                break
            }
        }
        guard !involved.isEmpty else { return .unavailable }

        let liveRows = (try? await geoAPI.liveStatus(forStaffIds: involved.map(\.staffId))) ?? []
        var liveByStaff: [String: CpLiveStatusRow] = [:]
        for row in liveRows {
            if let id = row.staffId, !id.isEmpty { liveByStaff[id] = row }
        }

        var tracks: [CpStaffTrack] = []
        for staff in involved {
            let window = CpStaffTrackPolicy.window(startedAt: staff.startedAt, completedAt: staff.completedAt, now: now)
            let canRead = CpStaffTrackPolicy.canReadRouteDirectly(
                staffId: staff.staffId,
                viewerStaffId: viewerStaffId,
                viewerCanViewAllTracking: viewerCanViewAllTracking
            )
            var routeRead = false
            var path: [GeoTrackTrackCleaner.Point] = []
            if let window, canRead,
               let data = try? await geoAPI.sessionRoute(
                   staffId: staff.staffId,
                   dayStart: Int64(window.start),
                   dayEnd: Int64(window.end)
               ) {
                routeRead = true
                path = CpStaffTrackPolicy.cleanPath(
                    data.timeline.map {
                        GeoTrackTrackCleaner.Fix(lat: $0.lat, lng: $0.lng, accuracy: $0.accuracy, atMs: $0.recordedAt, isMock: $0.isMock == true)
                    },
                    window: window
                )
            }
            var live: CpStaffTrack.LiveFix?
            if let row = liveByStaff[staff.staffId],
               CpStaffTrackPolicy.liveFixVisible(
                   lat: row.lat, lng: row.lng, lastSeenMs: row.lastSeenMs,
                   trackingActive: row.trackingActive == true, window: window
               ),
               let lat = row.lat, let lng = row.lng, let seen = row.lastSeenMs {
                live = CpStaffTrack.LiveFix(lat: lat, lng: lng, lastSeenMs: seen, trackingActive: row.trackingActive == true)
            }
            let state: CpStaffTrack.PathState
            if path.count >= 2 {
                state = .shown
            } else if window == nil {
                state = .notStarted
            } else if !canRead || !routeRead {
                state = .notAvailable
            } else {
                state = .noPoints
            }
            tracks.append(CpStaffTrack(
                staffId: staff.staffId,
                name: staff.name.flatMap(cpNonBlank) ?? "Staff",
                isPrimary: staff.isPrimary,
                routeColor: staff.routeColor,
                path: path,
                distanceMeters: CpStaffTrackPolicy.pathDistanceMeters(path) ?? staff.recordedDistanceMeters,
                live: live,
                pathState: state,
                tripInProgress: window?.open == true
            ))
        }
        return .loaded(tracks)
    }
}
