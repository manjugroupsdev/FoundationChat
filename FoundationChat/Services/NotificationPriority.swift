import Foundation

/// Which notifications are ACTIONABLE — something the staff has to do or
/// decide — as opposed to something that merely happened.
///
/// Approvals and tasks block other people's work while they sit unread, so
/// they are tinted in the list. Chat mentions, status updates and
/// informational pings keep the default styling and do not compete for
/// attention.
///
/// Kept in step with the Android `NotificationPriority` object — the two
/// lists must agree, or the same notification looks urgent on one phone and
/// ordinary on another.
enum NotificationPriority {

    /// Type markers the backend uses for work that needs an action.
    private static let highPriorityTypeMarkers = [
        "task-",          // task-manager-task, task-overdue, task-extension-*
        "approval",
        "approve",
        "leave-",
        "permission-",
        "attendance-",
        "cp-approval",
        "wfh-",
    ]

    /// Types that match a marker above but are NOT actionable — a decision
    /// someone else already made about you, with nothing left to do.
    private static let neverHighPriorityTypes: Set<String> = [
        "task-status-update",
        "task-extension-reviewed",
    ]

    /// Fallback for legacy rows whose type is missing or unrecognised.
    private static let titleMarkers = ["approval", "approve", "overdue", "pending"]

    static func isHighPriority(type: String?, title: String?) -> Bool {
        let normalizedType = (type ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if !normalizedType.isEmpty {
            if neverHighPriorityTypes.contains(normalizedType) { return false }
            if highPriorityTypeMarkers.contains(where: { normalizedType.contains($0) }) {
                return true
            }
            // A recognised type that matched nothing is a deliberate "no" —
            // don't let the loose title fallback promote it back.
            return false
        }

        let normalizedTitle = (title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return titleMarkers.contains(where: { normalizedTitle.contains($0) })
    }
}
