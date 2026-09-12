import Foundation

/// What a tracking point or heartbeat belongs to.
///
/// The app runs ONE tracking session per attendance day — deliberately, because
/// tracking is bounded to clock-in → clock-out and a second session would tear
/// the point stream in half. So a CP trip or an on-duty trip is not a session of
/// its own; it is a stretch of the day's session, and the only way the GeoTrack
/// service can attribute distance to it is if each point says so.
///
/// Without this, every point arrives tagged "attendance" and a CP trip's real
/// distance can only be guessed from a time window. That is what forced the
/// backend into straight-line fallbacks for trip distance and travel allowance.
///
/// `contextType` values match the backend segment contract
/// (see `reports/GEOTRACK_CONVEX_CUTOVER.md` §5.2 in the Android repo) and the
/// Android `TrackingContext` — the two platforms MUST agree, or the same trip
/// reports differently depending on the phone it was walked with.
struct TrackingContext: Sendable, Equatable {
    let contextType: String
    let contextId: String?

    static let attendance = "attendance"
    static let cpTrip = "cp_trip"
    static let siteVisit = "site_visit"
    static let onDuty = "on_duty"
    static let fleetTrip = "fleet_trip"

    /// The plain shift: no trip is running, so the point belongs to the
    /// attendance day. `contextId` stays nil on purpose — the session was
    /// opened with the attendance row id as its own contextId, so repeating it
    /// on every point would be redundant, and guessing it here would risk
    /// disagreeing with the session after a day rollover.
    static let shift = TrackingContext(contextType: attendance, contextId: nil)
}

/// The single source of truth for "what is this staff doing right now".
///
/// Android keeps this in `SessionManager.fieldActivity()` because its tracking
/// notification also reads it. iOS has no such notification, so the store is
/// standalone — but the KINDS and the resulting `contextType` strings are
/// identical by design.
///
/// Backed by `UserDefaults` rather than in-memory state because the tracking
/// pipeline keeps recording across app suspension and relaunch; an in-memory
/// flag would silently reset to "plain shift" mid-trip.
enum TrackingContextStore {
    enum Kind: String {
        case cp
        case siteVisit = "sv"
        case onDuty = "onduty"
        case fleet

        var contextType: String {
            switch self {
            case .cp: return TrackingContext.cpTrip
            case .siteVisit: return TrackingContext.siteVisit
            case .onDuty: return TrackingContext.onDuty
            case .fleet: return TrackingContext.fleetTrip
            }
        }
    }

    private static let kindKey = "geotrack.fieldActivity.kind"
    private static let refKey = "geotrack.fieldActivity.refId"
    /// Written by the HR dashboard's on-duty flow long before this store
    /// existed. Read as a fallback so an on-duty trip started on a build that
    /// predates this — or by a path that has not been wired yet — still
    /// attributes its points.
    private static let legacyOnDutyTripIdKey = "attendance.onDuty.tripId"

    private static var defaults: UserDefaults { .standard }

    static func begin(_ kind: Kind, refId: String?) {
        defaults.set(kind.rawValue, forKey: kindKey)
        defaults.set(refId?.trimmedNonEmpty, forKey: refKey)
    }

    /// Attach the trip id to the activity that is already running.
    ///
    /// On-duty starts the activity immediately (so the UI is right the moment
    /// the user taps) but only learns its trip id when the backend call
    /// returns. No-op when the activity has since been cleared or replaced, so
    /// a late response can never re-tag a different trip.
    static func attachRef(_ kind: Kind, refId: String?) {
        guard defaults.string(forKey: kindKey) == kind.rawValue else { return }
        defaults.set(refId?.trimmedNonEmpty, forKey: refKey)
    }

    static func end(_ kind: Kind? = nil) {
        if let kind, defaults.string(forKey: kindKey) != kind.rawValue { return }
        defaults.removeObject(forKey: kindKey)
        defaults.removeObject(forKey: refKey)
    }

    /// Clear a visit/trip context without disturbing an on-duty one.
    ///
    /// A staff member can be on duty for the day AND run a CP trip inside it.
    /// Completing the CP trip must not silently end the on-duty attribution,
    /// so this only clears the trip kinds.
    static func endTripContext() {
        end(.cp)
        end(.siteVisit)
        end(.fleet)
    }

    /// The context to stamp on telemetry captured right now.
    ///
    /// Read at CAPTURE time, never at flush time: a buffered backlog uploaded
    /// hours later must stay attributed to the trip it was recorded during, the
    /// same reason the buffered point carries its own `sessionId`.
    static func current() -> TrackingContext {
        guard
            let raw = defaults.string(forKey: kindKey),
            // An unknown kind means a newer flow set an activity this build does
            // not know. Fall back to the shift rather than inventing a segment
            // type the backend would reject.
            let kind = Kind(rawValue: raw)
        else {
            return fallbackOnDutyContext() ?? .shift
        }
        let ref = defaults.string(forKey: refKey)?.trimmedNonEmpty
            ?? (kind == .onDuty ? defaults.string(forKey: legacyOnDutyTripIdKey)?.trimmedNonEmpty : nil)
        return TrackingContext(contextType: kind.contextType, contextId: ref)
    }

    private static func fallbackOnDutyContext() -> TrackingContext? {
        guard let tripId = defaults.string(forKey: legacyOnDutyTripIdKey)?.trimmedNonEmpty else {
            return nil
        }
        return TrackingContext(contextType: TrackingContext.onDuty, contextId: tripId)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
