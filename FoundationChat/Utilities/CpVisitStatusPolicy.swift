import Foundation

/// Resolves the display/action status shared by Home and the CP Visits list.
///
/// A CP and its spawned field visit are separate records. While travel is live,
/// the field visit owns states such as `arrived`. Once the CP itself reaches a
/// terminal state, however, that CP state must win even if a flaky follow-up
/// request left the field visit open.
enum CpVisitStatusPolicy {
    private static let terminalStatuses: Set<String> = [
        "completed",
        "complete",
        "done",
        "closed",
        "cancelled",
        "canceled",
        "postponed",
        "pending_gm_approval"
    ]

    static func resolve(
        cpStatus: String?,
        fieldVisitStatus: String?,
        serverEffectiveStatus: String? = nil
    ) -> String {
        let server = serverEffectiveStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !server.isEmpty { return server }

        let cp = cpStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if terminalStatuses.contains(cp.lowercased()) {
            return cp
        }

        let fieldVisit = fieldVisitStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fieldVisit.isEmpty {
            return fieldVisit
        }

        return cp.isEmpty ? "scheduled" : cp
    }

    static func actorParticipant(
        in joint: JointCpSummary?,
        currentStaffIds: Set<String>
    ) -> JointCpParticipant? {
        guard !currentStaffIds.isEmpty else { return nil }
        return joint?.participants?.first { participant in
            guard let staffId = participant.staffId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !staffId.isEmpty
            else { return false }
            return currentStaffIds.contains(staffId)
        }
    }

    static func resolveForActor(
        cpStatus: String?,
        fieldVisitStatus: String?,
        serverEffectiveStatus: String?,
        joint: JointCpSummary?,
        currentStaffIds: Set<String>
    ) -> String {
        let parentStatus = resolve(
            cpStatus: cpStatus,
            fieldVisitStatus: fieldVisitStatus,
            serverEffectiveStatus: serverEffectiveStatus
        )
        // A Joint CP is NOT finished when one participant's own leg finishes.
        // The visit closes only when the higher-level reviewer adds their remark
        // and completes it. Submitting completes the owner's field visit, so this
        // is checked BEFORE the terminal return below (which reads the field
        // visit) — only a terminal CP or server status outranks it.
        let cpOrServerTerminal = [cpStatus, serverEffectiveStatus].contains { value in
            terminalStatuses.contains(
                value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            )
        }
        if !cpOrServerTerminal, let joint, jointReviewStillOpen(joint) {
            return jointPendingReview
        }
        if terminalStatuses.contains(parentStatus.lowercased()) {
            return parentStatus
        }

        let participantStatus = actorParticipant(in: joint, currentStaffIds: currentStaffIds)?
            .status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let participantStatus, !participantStatus.isEmpty {
            return participantStatus
        }
        return parentStatus
    }

    /// Card status for a Joint CP whose outcome is submitted but not yet
    /// reviewed. Its own value rather than "arrived" or "completed", both of
    /// which already drive actions that are wrong here. Must match the Android
    /// `JOINT_PENDING_REVIEW` constant.
    static let jointPendingReview = "pending_joint_review"

    /// True while the Joint CP workflow is still running.
    ///
    /// Answers only from the workflow the SERVER resolved. A payload with no
    /// workflow — an older deployment, or a list shape that omits it — returns
    /// false and the previous behaviour stands, so a missing field can never
    /// strand a genuinely finished visit in a pending state.
    private static func jointReviewStillOpen(_ joint: JointCpSummary) -> Bool {
        let state = joint.workflow?.state?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return jointReviewOpenStates.contains(state.replacingOccurrences(of: "-", with: "_"))
    }

    /// Only the states AFTER the owner has sent the outcome. The server's
    /// earlier states (awaiting_both_trips, awaiting_owner_arrival,
    /// awaiting_owner_outcome) are live trips; treating them as pending review
    /// hid the trip actions and sent the staff back to "Start Trip".
    private static let jointReviewOpenStates: Set<String> = [
        "pending_review",
        "reviewing"
    ]

    static func isOutcomePending(cpStatus: String?, fieldVisitStatus: String?, outcome: String?) -> Bool {
        let cp = cpStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if terminalStatuses.contains(cp) { return false }
        if outcome?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return false }
        let trip = fieldVisitStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["completed", "complete", "done", "closed"].contains(trip)
    }
}
