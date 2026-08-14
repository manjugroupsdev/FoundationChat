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

        // Avoid `async let` with optional-try here. On physical devices this
        // combination can trip Swift's async-let allocator when the parent
        // SwiftUI task is cancelled during startup.
        let todayAttendance = try? await HRConvexAPIService.getTodayAttendance(token: token)
        let daySessions = try? await HRConvexAPIService.getDaySessions(token: token, date: today)

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

        // Keep these requests cancellation-safe. See `isClockedInForToday`.
        let todayAttendance = try? await HRConvexAPIService.getTodayAttendance(token: token)
        let daySessions = try? await HRConvexAPIService.getDaySessions(token: token, date: today)

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

    /// Live "is an attendance session open RIGHT NOW?" check. Mirrors Android
    /// `AttendanceTrackingGate.hasOpenSessionNow(token:)`.
    ///
    /// This is deliberately STRICTER than ``isClockedInForToday(token:date:)``:
    /// that lenient day-gate stays true for the rest of the day after the first
    /// punch (so already-started trips / CP cards keep working through a mid-day
    /// break), whereas this looks at the raw open-session flag alone — a closed
    /// day (clocked out) returns `false` even though they punched in earlier. It
    /// is what gates STARTING a *new* trip so a clocked-out staffer must clock in
    /// first.
    ///
    /// Returns:
    ///  - `true`  → an open session exists right now.
    ///  - `false` → no open session (clocked out, or not punched in yet).
    ///  - `nil`   → couldn't determine (both endpoints errored). Callers must NOT
    ///    treat `nil` as "clocked out" — in particular the tracking pipeline must
    ///    never stop tracking on a `nil`, or a transient outage would drop a
    ///    legitimate in-window journey. Buffered points sync later.
    ///
    /// Source-agnostic like the rest of the gate: the raw `hasOpenSession` flag is
    /// set server-side for a mobile, biometric, manual, or csv-import punch alike,
    /// so a biometric punch at the office gate opens the trip-start gate exactly
    /// as an in-app punch does.
    static func hasOpenSessionNow(token: String, date: Date = Date()) async -> Bool? {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: date)

        var todayAnswered = false
        var dayAnswered = false
        var open = false

        do {
            let attendance = try await HRConvexAPIService.getTodayAttendance(token: token)
            todayAnswered = true
            if attendance?.hasOpenSession == true || attendance?.isOpen == true {
                open = true
            }
        } catch {
            // endpoint didn't answer authoritatively
        }

        do {
            let daySessions = try await HRConvexAPIService.getDaySessions(token: token, date: today)
            dayAnswered = true
            if daySessions.hasOpenSession == true {
                open = true
            }
        } catch {
            // endpoint didn't answer authoritatively
        }

        // Neither endpoint answered → unknown; don't let callers act on a guess.
        if !todayAnswered && !dayAnswered { return nil }
        return open
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
