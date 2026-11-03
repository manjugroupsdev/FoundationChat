import Foundation

/// A punch the server already has: the staff clocked in (or out) some other
/// way while the clock-in screen was open (another tap, the gate, another
/// device). Not an error, and never something to queue offline or retry.
/// Android: `AttendanceFailure.AlreadyRecorded`.
nonisolated enum AttendanceAlreadyRecorded: Equatable, Sendable {
    case clockedIn
    case clockedOut

    var title: String {
        switch self {
        case .clockedIn: return "Already clocked in"
        case .clockedOut: return "Already clocked out"
        }
    }

    var message: String {
        switch self {
        case .clockedIn: return "You're already clocked in. Your attendance session is active."
        case .clockedOut: return "You're already clocked out. No active punch-in found for today."
        }
    }

    /// Recognises the server's wording, including inside the backend's
    /// "Uncaught Error: ... at ..." wrapper (sent as HTTP 500).
    static func from(_ text: String?) -> AttendanceAlreadyRecorded? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let sample = String(text.prefix(2_000))
        if matches(sample, #"already (punched|clocked) in|punch out first"#) { return .clockedIn }
        if matches(sample, #"no active punch-?in|already (punched|clocked) out"#) { return .clockedOut }
        return nil
    }

    static func from(_ error: Error) -> AttendanceAlreadyRecorded? {
        from((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// What a staff member sees when a punch fails. Backend diagnostics
/// ("Uncaught ReferenceError ...", stack traces, HTML error pages) are
/// replaced with a plain instruction. Android: `AttendanceFailure.serverMessage`.
nonisolated enum AttendanceFailureText {
    static let unconfirmed = "Could not confirm your punch. Check today's attendance before trying again. Contact HR if it is still missing."

    static func userFacing(_ message: String?) -> String {
        if let already = AttendanceAlreadyRecorded.from(message) {
            let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return isDiagnostic(trimmed) ? already.message : trimmed
        }
        guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.count <= 400, !isDiagnostic(trimmed) else { return unconfirmed }
        return trimmed
    }

    private static func isDiagnostic(_ text: String) -> Bool {
        let pattern = #"Uncaught|\b\w*(Error|Exception)\b|is not defined|not a function|Cannot read properties|Traceback|\[CONVEX|<!doctype|<html|(?m)^\s*at\s|\.(kt|java|ts|js|swift):\d+"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
