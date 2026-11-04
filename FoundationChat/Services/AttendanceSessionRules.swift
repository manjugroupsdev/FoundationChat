import Foundation

/// A session left open is closed by the midnight job at 23:59:59 IST. That
/// close is not a punch anybody made, so it must not show as "11:59 PM Punch
/// Out" or stretch the day's range. Same rule as the web (isSyntheticClose in
/// convex/lib/attendanceTime.ts) and Android (AttendanceSessions): flagged
/// autoClosedAtDayEnd, or exactly `<date>T18:29:59.000Z` on older rows.
nonisolated enum AttendanceSessionRules {
    static let autoClosedNote = "No punch-out recorded. The session was automatically closed at the end of the day."

    static func isSyntheticClose(punchOutTime: String?, autoClosed: Bool?, date: String?) -> Bool {
        guard let out = punchOutTime, !out.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if autoClosed == true { return true }
        guard let date, !date.isEmpty else { return false }
        return out == "\(date)T18:29:59.000Z"
    }

    /// The punch-out, unless it is the midnight job's close.
    static func realPunchOut(punchOutTime: String?, autoClosed: Bool?, date: String?) -> String? {
        isSyntheticClose(punchOutTime: punchOutTime, autoClosed: autoClosed, date: date) ? nil : punchOutTime
    }
}
