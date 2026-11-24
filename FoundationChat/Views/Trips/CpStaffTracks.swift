import CoreLocation
import Foundation

// CP trip map: the staff who are ON a CP (both on a Joint CP), their latest
// heartbeat fix, and the path + distance they travelled for this trip.
// Read-only display data — mirrors Android's ui/home/CpStaffTracks.kt. The
// pure rules live in Services/CpStaffTrackRules.swift (helper-tested).
// Nothing here touches the trip, outcome, punch or tracking service flows.

struct CpStaffTrack: Identifiable, Sendable {
    struct LiveFix: Sendable {
        let lat: Double
        let lng: Double
        let lastSeenMs: Double
        let trackingActive: Bool
        /// Shown only through `CpStaffTrack.motionToShow(now:)`.
        let motion: CpTrackMotion?
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }

    /// One piece of the path, drawn as its own polyline (never joined to the next).
    struct Segment: Sendable {
        let points: [CpTrackPoint]
        var dashed: Bool = false
        var coordinates: [CLLocationCoordinate2D] {
            points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        }
    }

    enum PathState: Sendable {
        case shown
        case notStarted
        /// The trip started (by its status) but no start time was recorded.
        case startUnknown
        case noPoints
        case notAvailable
    }

    var id: String { staffId }
    let staffId: String
    let name: String
    let isPrimary: Bool
    /// Server-assigned Joint CP route colour ("#RRGGBB"), when there is one.
    let routeColor: String?
    var segments: [Segment]
    var distanceMeters: Double?
    let live: LiveFix?
    var pathState: PathState
    /// This staff member's trip on this CP is running (by its status).
    let tripInProgress: Bool
    let windowStartMs: Double?
    let windowEndMs: Double?
    /// False when running with no recorded start (window = today's IST day).
    let startKnown: Bool

    var hasPath: Bool { segments.contains { $0.points.count >= 2 } }

    func isStale(now: Double) -> Bool {
        guard let live else { return true }
        return CpStaffTrackRules.isStale(lastSeenMs: live.lastSeenMs, trackingActive: live.trackingActive, now: now)
    }

    func motionToShow(now: Double) -> CpTrackMotion? {
        CpStaffTrackRules.motionToShow(
            motion: live?.motion,
            tripInProgress: tripInProgress,
            lastSeenMs: live?.lastSeenMs,
            trackingActive: live?.trackingActive == true,
            now: now
        )
    }

    var window: CpStaffTrackRules.Window? {
        guard let windowStartMs, let windowEndMs else { return nil }
        return CpStaffTrackRules.Window(start: windowStartMs, end: windowEndMs, open: tripInProgress, startKnown: startKnown)
    }
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
    /// This staff member's trip status (their Joint CP leg, else the CP's).
    let status: String?
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
    let movementMode: String?
    let activity: String?
    let speed: Double?
}

/// One geo-service live row, decoded for the CP map (RFC 3339 lastSeen,
/// and `trackingActive` read on its own — not folded into `isOnline`).
struct CpLiveStatusRow: Decodable, Sendable {
    let staffId: String?
    let lat: Double?
    let lng: Double?
    let lastSeenMs: Double?
    let trackingActive: Bool?
    let movementMode: String?
    let activity: String?
    let speed: Double?

    private enum CodingKeys: String, CodingKey {
        case staffId, lat, lng, lastSeen, lastSeenAt, trackingActive, movementMode, activity, speed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        staffId = c.geoStringIfPresent(.staffId)
        lat = c.geoDoubleIfPresent(.lat)
        lng = c.geoDoubleIfPresent(.lng)
        lastSeenMs = c.geoMillisIfPresent(.lastSeen, .lastSeenAt)
        trackingActive = c.geoBoolIfPresent(.trackingActive)
        movementMode = c.geoStringIfPresent(.movementMode)
        activity = c.geoStringIfPresent(.activity)
        speed = c.geoDoubleIfPresent(.speed)
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

// MARK: - App glue

enum CpStaffTrackPolicy {
    private static func cpTripStatus(_ cp: CpVisitDetail) -> String? {
        cp.effectiveStatus.flatMap(cpNonBlank) ?? cp.fieldVisit?.status.flatMap(cpNonBlank) ?? cp.status
    }

    /// Staff on the CP: Joint participants (primary first), else the assigned field staff.
    static func involvedStaff(_ cp: CpVisitDetail) -> [CpInvolvedStaff] {
        var seen = Set<String>()
        let participants = (cp.joint?.participants ?? []).filter { participant in
            guard let id = participant.staffId.flatMap(cpNonBlank) else { return false }
            return seen.insert(id).inserted
        }
        if !participants.isEmpty {
            return participants
                .sorted { ($0.isPrimary ?? false) && !($1.isPrimary ?? false) }
                .map {
                    CpInvolvedStaff(
                        staffId: $0.staffId.flatMap(cpNonBlank) ?? "",
                        name: $0.staffName,
                        isPrimary: $0.isPrimary ?? false,
                        routeColor: $0.routeColor,
                        startedAt: $0.startedAt.map(Double.init),
                        completedAt: $0.completedAt.map(Double.init),
                        recordedDistanceMeters: $0.distanceMeters,
                        status: $0.status.flatMap(cpNonBlank) ?? cpTripStatus(cp)
                    )
                }
        }
        guard let staffId = cp.assignedStaffId.flatMap(cpNonBlank) else { return [] }
        return [
            CpInvolvedStaff(
                staffId: staffId,
                name: cp.assignedStaff?.name ?? cp.assignedStaff?.staffName,
                isPrimary: true,
                routeColor: nil,
                startedAt: cp.fieldVisit?.startedAt.map(Double.init),
                completedAt: cp.fieldVisit?.completedAt.map(Double.init),
                recordedDistanceMeters: cp.fieldVisit?.distanceMeters,
                status: cpTripStatus(cp)
            )
        ]
    }

    /// The trip's real start: the viewer's own Joint CP leg, else the field
    /// visit, else the primary participant. Nil when unknown.
    static func tripStartedAt(_ cp: CpVisitDetail, viewerStaffId: String?) -> Double? {
        let participants = cp.joint?.participants ?? []
        let own = participants.first { viewerStaffId != nil && $0.staffId == viewerStaffId }?.startedAt
        return [own, cp.fieldVisit?.startedAt, participants.first { $0.isPrimary == true }?.startedAt]
            .compactMap { $0 }
            .first { $0 > 0 }
            .map(Double.init)
    }

    static func initialPathState(window: CpStaffTrackRules.Window?, status: String?) -> CpStaffTrack.PathState {
        if window != nil { return .notAvailable }
        return CpStaffTrackRules.isFinishedStatus(status) ? .startUnknown : .notStarted
    }

    static func liveFix(
        lat: Double?, lng: Double?, lastSeenMs: Double?, trackingActive: Bool,
        movementMode: String?, activity: String?, speed: Double?, window: CpStaffTrackRules.Window?
    ) -> CpStaffTrack.LiveFix? {
        guard CpStaffTrackRules.liveFixVisible(lat: lat, lng: lng, lastSeenMs: lastSeenMs, trackingActive: trackingActive, window: window),
              let lat, let lng, let lastSeenMs
        else { return nil }
        return CpStaffTrack.LiveFix(
            lat: lat, lng: lng, lastSeenMs: lastSeenMs, trackingActive: trackingActive,
            motion: CpStaffTrackRules.motion(movementMode: movementMode, activity: activity, speedMps: speed)
        )
    }

    /// Fixes inside the window → cleaned (spikes, jumps, stays) → split at gaps.
    static func rawSegments(_ fixes: [GeoTrackTrackCleaner.Fix], window: CpStaffTrackRules.Window) -> [CpStaffTrack.Segment] {
        var seen = Set<String>()
        let inside = fixes
            .filter { fix in
                guard let at = fix.atMs, at >= window.start, at <= window.end else { return false }
                return seen.insert("\(at)|\(fix.lat)|\(fix.lng)").inserted
            }
            .sorted { ($0.atMs ?? 0) < ($1.atMs ?? 0) }
        let cleaned = GeoTrackTrackCleaner.clean(inside).map { CpTrackPoint(lat: $0.lat, lng: $0.lng, atMs: $0.atMs) }
        return CpStaffTrackRules.splitAtGaps(cleaned).map { CpStaffTrack.Segment(points: $0) }
    }

    static func distance(_ segments: [CpStaffTrack.Segment]) -> Double? {
        CpStaffTrackRules.segmentsDistance(segments.map(\.points))
    }

    static func fromServer(_ dto: CpStaffTrackDTO, now: Double, involved: CpInvolvedStaff?) -> CpStaffTrack? {
        guard let staffId = dto.staffId.flatMap(cpNonBlank) else { return nil }
        let window = CpStaffTrackRules.tripWindow(
            startedAt: dto.startedAt ?? involved?.startedAt,
            completedAt: dto.completedAt ?? involved?.completedAt,
            status: involved?.status,
            now: now
        )
        let segments: [CpStaffTrack.Segment] = window.map { w in
            rawSegments((dto.routePoints ?? []).map {
                GeoTrackTrackCleaner.Fix(lat: $0.lat, lng: $0.lng, accuracy: nil, atMs: $0.recordedAt)
            }, window: w)
        } ?? []
        let live = dto.live.flatMap {
            liveFix(lat: $0.lat, lng: $0.lng, lastSeenMs: $0.lastSeen, trackingActive: $0.trackingActive == true,
                    movementMode: $0.movementMode, activity: $0.activity, speed: $0.speed, window: window)
        }
        let drawn = distance(segments)
        return CpStaffTrack(
            staffId: staffId,
            name: dto.staffName.flatMap(cpNonBlank) ?? involved?.name.flatMap(cpNonBlank) ?? "Staff",
            isPrimary: dto.isPrimary == true,
            routeColor: dto.routeColor ?? involved?.routeColor,
            segments: segments,
            distanceMeters: drawn ?? dto.recordedDistanceMeters ?? involved?.recordedDistanceMeters,
            live: live,
            pathState: drawn != nil ? .shown : initialPathState(window: window, status: involved?.status),
            tripInProgress: window?.open == true,
            windowStartMs: window?.start,
            windowEndMs: window?.end,
            startKnown: window?.startKnown ?? true
        )
    }
}

// MARK: - Loader

/// Prefers the server's scoped `staff-tracks` route; while that route is not
/// deployed it falls back to the direct geo reads. Paths, where the viewer may
/// read them directly: road-matched snapped-route first, else session-route
/// one IST day at a time (geo refuses ranges over 48 h), split at gaps.
enum CpStaffTracksLoader {
    enum Result: Sendable {
        case loaded([CpStaffTrack])
        /// The server says this viewer may not see these tracks.
        case forbidden
        case unavailable
    }

    nonisolated(unsafe) private static var serverRouteMissing = false
    nonisolated(unsafe) private static var snappedRouteMissing = false

    static func load(
        token: String,
        cpId: String,
        involved: [CpInvolvedStaff],
        viewerStaffId: String?,
        viewerCanViewAllTracking: Bool,
        geoAPI: GeoTrackAPIService
    ) async -> Result {
        let now = Date().timeIntervalSince1970 * 1000
        var byId: [String: CpInvolvedStaff] = [:]
        for staff in involved { byId[staff.staffId] = staff }
        var tracks: [CpStaffTrack]?
        if !serverRouteMissing {
            switch await MarketingConvexAPIService.getCpStaffTracks(token: token, id: cpId) {
            case .loaded(let rows):
                let parsed = rows.compactMap { CpStaffTrackPolicy.fromServer($0, now: now, involved: byId[$0.staffId ?? ""]) }
                if !parsed.isEmpty || involved.isEmpty { tracks = parsed }
            case .forbidden:
                return .forbidden
            case .notDeployed:
                serverRouteMissing = true
            case .failed:
                break
            }
        }
        if tracks == nil {
            guard !involved.isEmpty else { return .unavailable }
            tracks = await loadLive(involved: involved, now: now, geoAPI: geoAPI)
        }
        // One row (and one marker) per staff member.
        var seen = Set<String>()
        var filled: [CpStaffTrack] = []
        for track in tracks ?? [] where seen.insert(track.staffId).inserted {
            filled.append(await withPath(track, viewerStaffId: viewerStaffId, viewerCanViewAllTracking: viewerCanViewAllTracking, geoAPI: geoAPI))
        }
        return .loaded(filled)
    }

    private static func withPath(
        _ track: CpStaffTrack, viewerStaffId: String?, viewerCanViewAllTracking: Bool, geoAPI: GeoTrackAPIService
    ) async -> CpStaffTrack {
        guard let window = track.window, !track.hasPath else { return track }
        var result = track
        guard CpStaffTrackRules.canReadRouteDirectly(
            staffId: track.staffId, viewerStaffId: viewerStaffId, viewerCanViewAllTracking: viewerCanViewAllTracking
        ) else {
            result.pathState = .notAvailable
            return result
        }
        // Road-matched first.
        let snapped = await snappedSegments(staffId: track.staffId, window: window, geoAPI: geoAPI)
        if let drawn = CpStaffTrackPolicy.distance(snapped) {
            result.segments = snapped
            result.distanceMeters = drawn
            result.pathState = .shown
            return result
        }
        // Raw session-route, one IST day (≤ 24 h) per read.
        var fixes: [GeoTrackTrackCleaner.Fix] = []
        var anyRead = false
        for chunk in CpStaffTrackRules.dayChunks(window) {
            if let data = try? await geoAPI.sessionRoute(
                staffId: track.staffId, dayStart: Int64(chunk.start), dayEnd: Int64(chunk.end)
            ) {
                anyRead = true
                fixes += data.timeline.map {
                    GeoTrackTrackCleaner.Fix(lat: $0.lat, lng: $0.lng, accuracy: $0.accuracy, atMs: $0.recordedAt, isMock: $0.isMock == true)
                }
            }
        }
        let segments = CpStaffTrackPolicy.rawSegments(fixes, window: window)
        let drawn = CpStaffTrackPolicy.distance(segments)
        result.segments = segments
        result.distanceMeters = drawn ?? track.distanceMeters
        result.pathState = drawn != nil ? .shown : (anyRead ? .noPoints : .notAvailable)
        return result
    }

    private static func snappedSegments(
        staffId: String, window: CpStaffTrackRules.Window, geoAPI: GeoTrackAPIService
    ) async -> [CpStaffTrack.Segment] {
        guard !snappedRouteMissing else { return [] }
        var segments: [(start: Double, segment: CpStaffTrack.Segment)] = []
        for date in CpStaffTrackRules.istDates(window) {
            do {
                for piece in try await geoAPI.snappedRoute(staffId: staffId, date: date) {
                    guard piece.kind != "gap" else { continue }
                    let start = piece.startedAt.flatMap { GeoTrackWire.millis(from: $0) }
                    let end = piece.endedAt.flatMap { GeoTrackWire.millis(from: $0) }
                    guard (start ?? -.infinity) <= window.end, (end ?? .infinity) >= window.start else { continue }
                    let points = piece.coordinates.map { CpTrackPoint(lat: $0.latitude, lng: $0.longitude, atMs: nil) }
                    guard points.count >= 2 else { continue }
                    segments.append((start ?? 0, CpStaffTrack.Segment(points: points, dashed: piece.kind == "estimated")))
                }
            } catch GeoTrackAPIError.badStatus(404) {
                snappedRouteMissing = true
                return []
            } catch GeoTrackAPIError.notFound {
                snappedRouteMissing = true
                return []
            } catch {
                continue
            }
        }
        return segments.sorted { $0.start < $1.start }.map(\.segment)
    }

    /// Tracks from the CP detail + each staff member's own live row (no path yet).
    private static func loadLive(involved: [CpInvolvedStaff], now: Double, geoAPI: GeoTrackAPIService) async -> [CpStaffTrack] {
        let rows = (try? await geoAPI.liveStatus(forStaffIds: involved.map(\.staffId))) ?? []
        var latest: [String: CpLiveStatusRow] = [:]
        for row in rows {
            guard let id = row.staffId.flatMap(cpNonBlank) else { continue }
            if (row.lastSeenMs ?? 0) >= (latest[id]?.lastSeenMs ?? -1) { latest[id] = row }
        }
        return involved.map { staff in
            let window = CpStaffTrackRules.tripWindow(
                startedAt: staff.startedAt, completedAt: staff.completedAt, status: staff.status, now: now
            )
            let row = latest[staff.staffId]
            return CpStaffTrack(
                staffId: staff.staffId,
                name: staff.name.flatMap(cpNonBlank) ?? "Staff",
                isPrimary: staff.isPrimary,
                routeColor: staff.routeColor,
                segments: [],
                distanceMeters: staff.recordedDistanceMeters,
                live: row.flatMap {
                    CpStaffTrackPolicy.liveFix(
                        lat: $0.lat, lng: $0.lng, lastSeenMs: $0.lastSeenMs, trackingActive: $0.trackingActive == true,
                        movementMode: $0.movementMode, activity: $0.activity, speed: $0.speed, window: window
                    )
                },
                pathState: CpStaffTrackPolicy.initialPathState(window: window, status: staff.status),
                tripInProgress: window?.open == true,
                windowStartMs: window?.start,
                windowEndMs: window?.end,
                startKnown: window?.startKnown ?? true
            )
        }
    }
}
