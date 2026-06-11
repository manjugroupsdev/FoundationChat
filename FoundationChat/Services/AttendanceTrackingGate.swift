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
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
