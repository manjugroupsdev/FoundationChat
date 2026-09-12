import Foundation

/// IAM key that grants CP arrival-OTP reveal. Granted to AVP by designation on
/// the backend (it survives a staff IAM template replacing the configurable
/// designation grants), and assignable to anyone else from the IAM screen.
let cpRevealOtpPermission = "marketing.cpVisits.revealOtp"

/// Who may read a team member's live CP arrival OTP back to them.
///
/// A staff member stuck on a client's doorstep — client refuses the OTP, the
/// SMS never lands — used to have no route forward but the tech team. This is
/// the supported route: their own AVP/GM reveals the active code.
///
/// Every rule here mirrors `requireOtpRevealAccess` in the backend's
/// `convex/hr/fieldVisitOtp.ts`, which stays authoritative — reveal is audited
/// server-side on both view and copy, and the scope is re-checked on each call
/// so a previously returned field-visit id cannot widen it. This exists only so
/// the app does not offer an action the server is going to refuse, and so an
/// unprivileged viewer is never shown that the capability exists.
///
/// Deliberately NOT built on `AuthStore.hasPermission`: that folds in the
/// blanket `isAdmin` flag. An OTP is a client's own verification code, so the
/// grant must be explicit.
enum CpOtpRevealAccess {

    /// General Manager, excluding Assistant General Manager — "AGM" contains
    /// "GM", and an AGM is not a GM.
    static func isGmDesignation(_ value: String?) -> Bool {
        let designation = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if designation.isEmpty { return false }
        if matches(designation, #"\b(?:assistant|asst\.?)\s+general\s+manager\b"#) { return false }
        return matches(designation, #"\bgm\b|\b(?:senior\s+)?general\s+manager\b"#)
    }

    /// Assistant/Associate Vice President, in the spellings HR actually uses.
    static func isAvpDesignation(_ value: String?) -> Bool {
        var designation = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        designation = replacing(designation, #"[._/-]+"#, with: " ")
        designation = replacing(designation, #"\s+"#, with: " ")
        if designation.isEmpty { return false }
        return matches(designation, #"\bavp\b"#)
            || matches(designation, #"\bavvp\b"#)
            || matches(designation, #"\b(?:assistant|asst|associate)\s+vice\s+president\b"#)
            || matches(designation, #"\b(?:assistant|asst|associate)\s+vp\b"#)
    }

    static func isGmOrAvpDesignation(_ value: String?) -> Bool {
        isGmDesignation(value) || isAvpDesignation(value)
    }

    /// Does this viewer hold the capability at all, before any target is known?
    ///
    /// Super Admin bypasses both the key and the designation gate, exactly as
    /// the server does (`staff.isAdmin === true || role === "super-admin"`).
    /// Everyone else needs the explicit key AND a GM/AVP designation: the
    /// permission alone is not enough, so granting it to a coordinator by
    /// mistake does not hand out client OTPs.
    static func holdsCapability(
        isSuperAdmin: Bool,
        designation: String?,
        permissions: Set<String>
    ) -> Bool {
        if isSuperAdmin { return true }
        guard permissions.contains(cpRevealOtpPermission) else { return false }
        return isGmOrAvpDesignation(designation)
    }

    /// Reveal is limited to staff strictly BELOW the viewer in the reporting
    /// hierarchy. `reportingTeamStaffIds` is the team the server itself just
    /// returned for this viewer, so the app never infers the hierarchy locally;
    /// the viewer is excluded because nobody reveals their own OTP.
    static func canReveal(
        isSuperAdmin: Bool,
        designation: String?,
        permissions: Set<String>,
        viewerStaffId: String?,
        targetStaffId: String?,
        reportingTeamStaffIds: Set<String>
    ) -> Bool {
        guard holdsCapability(
            isSuperAdmin: isSuperAdmin,
            designation: designation,
            permissions: permissions
        ) else { return false }
        let target = (targetStaffId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty { return false }
        if isSuperAdmin { return true }
        let viewer = (viewerStaffId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !viewer.isEmpty && viewer == target { return false }
        return reportingTeamStaffIds.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == target
        }
    }

    /// CP states where an active arrival OTP can still exist.
    ///
    /// The server refuses a reveal once arrival is verified or the visit is
    /// closed; offering the action there would only produce an error. A blank
    /// status is allowed through so a deployment that stops sending one
    /// degrades to the server's own answer rather than hiding a capability the
    /// viewer legitimately has.
    static func isRevealableStatus(_ status: String?) -> Bool {
        let normalized = (status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty { return true }
        return !terminalRevealStatuses.contains(normalized)
    }

    /// Arrival is done, or the visit is closed. `arrived` is included because
    /// the server treats it as verified; the approval/outcome states are
    /// terminal for the trip even though the CP row stays open.
    private static let terminalRevealStatuses: Set<String> = [
        "arrived",
        "completed",
        "complete",
        "done",
        "closed",
        "cancelled",
        "canceled",
        "postponed",
        "pending_gm_approval",
    ]

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression]) != nil
    }

    private static func replacing(
        _ value: String,
        _ pattern: String,
        with replacement: String
    ) -> String {
        value.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression]
        )
    }
}

/// Whether this deployment serves the reveal route at all.
///
/// Process-lifetime only, and it only ever narrows: a 404 hides the action, and
/// a relaunch re-offers it. That way the app never shows a manager a button
/// that cannot work twice, and picks the capability up automatically once the
/// backend route is deployed — no app release needed to turn it on.
@MainActor
enum CpOtpRevealSupport {
    private(set) static var isSupported = true

    static func markUnsupported() {
        isSupported = false
    }

    /// Test seam — production code only ever calls `markUnsupported()`.
    static func resetForTests() {
        isSupported = true
    }
}
