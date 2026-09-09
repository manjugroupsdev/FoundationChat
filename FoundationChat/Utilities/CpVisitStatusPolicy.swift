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

    static func isOutcomePending(cpStatus: String?, fieldVisitStatus: String?, outcome: String?) -> Bool {
        let cp = cpStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if terminalStatuses.contains(cp) { return false }
        if outcome?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return false }
        let trip = fieldVisitStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["completed", "complete", "done", "closed"].contains(trip)
    }
}
