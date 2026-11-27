import Foundation

/// Whether "Apply Leave" / "Apply Permission" can be tapped (MMS-290).
///
/// When nothing is left the button turns grey, reads "Unavailable" and shows a
/// one-line reason under it. The server still enforces every limit; this only
/// stops the user filling a form that is bound to be refused. Never blocks
/// while the numbers are loading, failed or unknown. Mirrors Android's
/// `HrApplyAvailability`.
enum HRApplyAvailability {

    struct State: Equatable {
        let available: Bool
        let reason: String?
    }

    static let availableState = State(available: true, reason: nil)

    static let unavailableLabel = "Unavailable"
    static let reasonPermissionHours = "No permission hours left this month"
    static let reasonPermissionRequests = "Monthly permission requests used up"
    static let reasonLeave = "No leave balance left"

    static func permission(loaded: Bool, remainingHours: Double?, remainingRequests: Int?) -> State {
        guard loaded else { return availableState }
        if let remainingRequests, remainingRequests <= 0 {
            return State(available: false, reason: reasonPermissionRequests)
        }
        if let remainingHours, remainingHours <= 0 {
            return State(available: false, reason: reasonPermissionHours)
        }
        return availableState
    }

    /// Leave: grey only when the web-configured unpaid-leave limit is set and
    /// nothing is left of it. A missing/null limit (unlimited, or a server that
    /// doesn't send it yet) never blocks.
    static func leave(loaded: Bool, unpaidLimit: Double?, unpaidRemaining: Double?) -> State {
        guard loaded, unpaidLimit != nil, let unpaidRemaining else { return availableState }
        return unpaidRemaining <= 0 ? State(available: false, reason: reasonLeave) : availableState
    }

    /// Compensatory Off can be picked only when at least one credit exists.
    static func compOffAvailable(creditsFetched: Bool, creditCount: Int) -> Bool {
        !creditsFetched || creditCount > 0
    }
}
