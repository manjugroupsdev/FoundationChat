import Foundation

enum AttendanceTrackingGate {
    static func isClockedInForToday(
        firstPunchIn: String?,
        hasOpenSession: Bool
    ) -> Bool {
        hasOpenSession || firstPunchIn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func hasOpenSessionForToday(
        firstPunchIn: String?,
        lastPunchOut: String?,
        hasOpenSession: Bool
    ) -> Bool {
        if hasOpenSession { return true }
        return firstPunchIn.nilIfBlank != nil && lastPunchOut.nilIfBlank == nil
    }

    /// Matches Android's attendance UI rule: only the latest explicit mobile
    /// punch-out completes the day. Biometric/gate activity keeps Clock Out available.
    static func isClockedOutOnMobile(
        daySessions: [ConvexDaySession]?,
        attendanceSessions: [ConvexAttendanceSession]?
    ) -> Bool {
        if let daySessions {
            return computeClockedOutOnMobile(
                daySessions.map {
                    ($0.punchInTime, $0.punchOutTime, $0.punchOutSource)
                }
            )
        }

        return computeClockedOutOnMobile(
            (attendanceSessions ?? []).map {
                ($0.punchInTime, $0.punchOutTime, $0.punchOutSource)
            }
        )
    }

    static func isClockedInForToday(token: String, date: Date = Date()) async -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: date)

        async let attendance = try? HRConvexAPIService.getTodayAttendance(token: token)
        async let sessions = try? HRConvexAPIService.getDaySessions(token: token, date: today)
        let todayAttendance = await attendance
        let daySessions = await sessions

        let firstPunchIn = daySessions?.firstPunchIn.nilIfBlank
            ?? todayAttendance?.firstPunchIn.nilIfBlank
            ?? todayAttendance?.punchInTime.nilIfBlank
            ?? daySessions?.sessions?.compactMap { $0.punchInTime.nilIfBlank }.first
        let hasOpenSession = todayAttendance?.hasOpenSession == true
            || daySessions?.hasOpenSession == true
            || todayAttendance?.isOpen == true

        return isClockedInForToday(
            firstPunchIn: firstPunchIn,
            hasOpenSession: hasOpenSession
        )
    }

    static func hasOpenSessionForToday(token: String, date: Date = Date()) async -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: date)

        async let attendance = try? HRConvexAPIService.getTodayAttendance(token: token)
        async let sessions = try? HRConvexAPIService.getDaySessions(token: token, date: today)
        let todayAttendance = await attendance
        let daySessions = await sessions

        let firstPunchIn = daySessions?.firstPunchIn.nilIfBlank
            ?? todayAttendance?.firstPunchIn.nilIfBlank
            ?? todayAttendance?.punchInTime.nilIfBlank
            ?? daySessions?.sessions?.compactMap { $0.punchInTime.nilIfBlank }.first
        let lastPunchOut = daySessions?.lastPunchOut.nilIfBlank
            ?? todayAttendance?.lastPunchOut.nilIfBlank
            ?? todayAttendance?.punchOutTime.nilIfBlank
            ?? daySessions?.sessions?.compactMap { $0.punchOutTime.nilIfBlank }.last
        let hasOpenSession = todayAttendance?.hasOpenSession == true
            || daySessions?.hasOpenSession == true
            || todayAttendance?.isOpen == true

        return hasOpenSessionForToday(
            firstPunchIn: firstPunchIn,
            lastPunchOut: lastPunchOut,
            hasOpenSession: hasOpenSession
        )
    }

    private static func computeClockedOutOnMobile(
        _ sessions: [(punchInTime: String?, punchOutTime: String?, punchOutSource: String?)]
    ) -> Bool {
        var latestMobilePunchOut: Date?
        var latestOtherActivity: Date?

        for session in sessions {
            if let punchIn = attendanceTimestamp(session.punchInTime),
               latestOtherActivity == nil || punchIn > latestOtherActivity! {
                latestOtherActivity = punchIn
            }

            guard let punchOut = attendanceTimestamp(session.punchOutTime) else { continue }
            if session.punchOutSource?.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("mobile") == .orderedSame {
                if latestMobilePunchOut == nil || punchOut > latestMobilePunchOut! {
                    latestMobilePunchOut = punchOut
                }
            } else if latestOtherActivity == nil || punchOut > latestOtherActivity! {
                latestOtherActivity = punchOut
            }
        }

        guard let latestMobilePunchOut else { return false }
        guard let latestOtherActivity else { return true }
        return latestMobilePunchOut >= latestOtherActivity
    }

    private static func attendanceTimestamp(_ raw: String?) -> Date? {
        guard let raw = raw.nilIfBlank else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
