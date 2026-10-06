import CryptoKit
import Foundation

/// The punch THIS phone just made, remembered locally.
///
/// The attendance read endpoints are cached on the server for 2 minutes (and
/// were cached by URLSession for 15 s). A read made right after a clock-in could
/// therefore still say "not punched in": the CP list flipped straight back to
/// "Need to Clock In", a trip refused to start, and GeoTrack's post-punch sync
/// read "closed" and discarded the tracking start. Android never hit this — its
/// screens follow the shared attendance state, which flips the moment the punch
/// succeeds (or is queued offline). This is the iOS equivalent.
enum LocalPunchState {
    struct Punch: Codable, Equatable {
        let isPunchIn: Bool
        let at: Date
        /// India calendar day ("yyyy-MM-dd") the punch belongs to.
        let day: String
        /// One-way fingerprint of the session that punched, so a second
        /// staff member signing in on the same phone never inherits it.
        let owner: String
    }

    /// Longer than the server's attendance read cache (120 s), so a stale
    /// cached answer can never outlive the local override.
    static let freshWindow: TimeInterval = 180

    private static let key = "attendance.lastLocalPunch.v1"

    /// Call only once the server accepted the punch, or it was queued offline.
    static func record(isPunchIn: Bool, token: String, at date: Date = Date()) {
        let punch = Punch(isPunchIn: isPunchIn, at: date, day: indiaDay(date), owner: fingerprint(token))
        if let data = try? JSONEncoder().encode(punch) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func latest(token: String) -> Punch? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let punch = try? JSONDecoder().decode(Punch.self, from: data),
              punch.owner == fingerprint(token)
        else { return nil }
        return punch
    }

    /// Today's latest local punch, when it is recent enough that the server's
    /// cached answer may not include it yet.
    static func freshPunch(token: String, now: Date = Date()) -> Punch? {
        guard let punch = latest(token: token), punch.day == indiaDay(now) else { return nil }
        let age = now.timeIntervalSince(punch.at)
        return (age >= -60 && age <= freshWindow) ? punch : nil
    }

    /// True when this phone punched in at any time today (a lenient day gate,
    /// like the server's firstPunchIn).
    static func punchedInToday(token: String, now: Date = Date()) -> Bool {
        guard let punch = latest(token: token), punch.day == indiaDay(now) else { return false }
        return punch.isPunchIn
    }

    private static func fingerprint(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Attendance days are India days on the server; match them regardless of
    /// the phone's calendar or region settings.
    static func indiaDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

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
        if let daySessions, !daySessions.isEmpty {
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
        // A punch-in this phone made today counts even before the server's
        // cached reads catch up (or while it is still queued offline).
        if LocalPunchState.punchedInToday(token: token, now: date) { return true }
        let today = LocalPunchState.indiaDay(date)

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
        if let fresh = LocalPunchState.freshPunch(token: token, now: date) { return fresh.isPunchIn }
        let today = LocalPunchState.indiaDay(date)

        // Keep these requests cancellation-safe. See `isClockedInForToday`.
        let todayAttendance = try? await HRConvexAPIService.getTodayAttendance(token: token)
        let daySessions = try? await HRConvexAPIService.getDaySessions(token: token, date: today)

        let firstPunchIn = daySessions?.firstPunchIn.nilIfBlank
            ?? todayAttendance?.firstPunchIn.nilIfBlank
            ?? todayAttendance?.punchInTime.nilIfBlank
            ?? daySessions?.sessions?.compactMap { $0.punchInTime.nilIfBlank }.first
        let hasOpenSession = todayAttendance?.hasOpenSession == true
            || daySessions?.hasOpenSession == true
            || todayAttendance?.isOpen == true
            || hasOpenPunch(daySessions: daySessions?.sessions, attendanceSessions: todayAttendance?.sessions)

        // Android parity (AttendanceTrackingGate.isMobileWorkSessionActive): a
        // biometric gate punch-out closes the raw attendance pair but does NOT
        // end the mobile work day - only a Clock Out in the app does. This used
        // to read any punch-out as "clocked out", so a staffer who badged out
        // at the gate to go to the field could not start a trip, and the Clock
        // In screen it sent them to refused a second clock-in.
        return isMobileWorkSessionActive(
            firstPunchIn: firstPunchIn,
            hasOpenSession: hasOpenSession,
            clockedOutOnMobile: isClockedOutOnMobile(
                daySessions: daySessions?.sessions,
                attendanceSessions: todayAttendance?.sessions
            )
        )
    }

    /// Android `isMobileWorkSessionActive`: an open session, or a punch-in today
    /// whose latest relevant event is not a Clock Out in the app.
    static func isMobileWorkSessionActive(
        firstPunchIn: String?,
        hasOpenSession: Bool,
        clockedOutOnMobile: Bool
    ) -> Bool {
        if hasOpenSession { return true }
        guard firstPunchIn.nilIfBlank != nil else { return false }
        return !clockedOutOnMobile
    }

    /// A session row with a punch-in and no punch-out (the canonical open
    /// session, before a denormalised flag catches up).
    private static func hasOpenPunch(
        daySessions: [ConvexDaySession]?,
        attendanceSessions: [ConvexAttendanceSession]?
    ) -> Bool {
        if let daySessions, !daySessions.isEmpty {
            return daySessions.contains { $0.punchInTime.nilIfBlank != nil && $0.punchOutTime.nilIfBlank == nil }
        }
        return (attendanceSessions ?? []).contains {
            $0.punchInTime.nilIfBlank != nil && $0.punchOutTime.nilIfBlank == nil
        }
    }

    /// When today's work day was ended by a Clock Out in the app, its time;
    /// otherwise nil (not clocked in, still working, or only a gate
    /// punch-out). Lets a trip start explain itself instead of opening a
    /// Clock In screen that cannot succeed.
    static func mobileClockOutToday(token: String, date: Date = Date()) async -> Date? {
        if let localPunch = LocalPunchState.freshPunch(token: token, now: date), !localPunch.isPunchIn {
            return localPunch.at
        }
        let today = LocalPunchState.indiaDay(date)
        let todayAttendance = try? await HRConvexAPIService.getTodayAttendance(token: token)
        let daySessions = try? await HRConvexAPIService.getDaySessions(token: token, date: today)
        guard todayAttendance != nil || daySessions != nil else { return nil }
        let open = todayAttendance?.hasOpenSession == true
            || daySessions?.hasOpenSession == true
            || hasOpenPunch(daySessions: daySessions?.sessions, attendanceSessions: todayAttendance?.sessions)
        guard !open,
              isClockedOutOnMobile(daySessions: daySessions?.sessions, attendanceSessions: todayAttendance?.sessions)
        else { return nil }
        let mobileOuts: [String?]
        if let sessions = daySessions?.sessions, !sessions.isEmpty {
            mobileOuts = sessions
                .filter { $0.punchOutSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mobile" }
                .map(\.punchOutTime)
        } else {
            mobileOuts = (todayAttendance?.sessions ?? [])
                .filter { $0.punchOutSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mobile" }
                .map(\.punchOutTime)
        }
        return mobileOuts.compactMap { attendanceTimestamp($0) }.max()
    }

    /// The message for a refused trip start.
    static func tripStartBlockedMessage(token: String) async -> String {
        guard let clockOut = await mobileClockOutToday(token: token) else {
            return "Please clock in before starting a trip."
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return "You clocked out at \(formatter.string(from: clockOut)). Trips can't be started after clocking out."
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
    /// Source-agnostic for clocking IN: a biometric punch at the office gate opens
    /// the trip-start gate exactly as an in-app punch does. For clocking OUT only
    /// an in-app Clock Out ends the work day (Android parity); a gate punch-out
    /// keeps it running.
    static func hasOpenSessionNow(token: String, date: Date = Date()) async -> Bool? {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Within minutes of a punch on this phone, the punch is the truth: the
        // server's cached read would otherwise tell GeoTrack "closed" right
        // after a clock-in and the tracking start was discarded.
        if let fresh = LocalPunchState.freshPunch(token: token, now: date) { return fresh.isPunchIn }
        let today = LocalPunchState.indiaDay(date)

        var todayAnswered = false
        var dayAnswered = false
        var open = false
        var attendance: ConvexTodayAttendance?
        var daySessions: ConvexDaySessionsResponse?

        do {
            attendance = try await HRConvexAPIService.getTodayAttendance(token: token)
            todayAnswered = true
            if attendance?.hasOpenSession == true || attendance?.isOpen == true {
                open = true
            }
        } catch {
            // endpoint didn't answer authoritatively
        }

        do {
            daySessions = try await HRConvexAPIService.getDaySessions(token: token, date: today)
            dayAnswered = true
            if daySessions?.hasOpenSession == true {
                open = true
            }
        } catch {
            // endpoint didn't answer authoritatively
        }

        // Neither endpoint answered → unknown; don't let callers act on a guess.
        if !todayAnswered && !dayAnswered { return nil }
        if open || hasOpenPunch(daySessions: daySessions?.sessions, attendanceSessions: attendance?.sessions) {
            return true
        }
        // Android parity: after a biometric gate punch-out the mobile work day
        // (and its tracking) continues until a Clock Out in the app.
        let firstPunchIn = daySessions?.firstPunchIn.nilIfBlank
            ?? attendance?.firstPunchIn.nilIfBlank
            ?? attendance?.punchInTime.nilIfBlank
            ?? daySessions?.sessions?.compactMap { $0.punchInTime.nilIfBlank }.first
        return isMobileWorkSessionActive(
            firstPunchIn: firstPunchIn,
            hasOpenSession: false,
            clockedOutOnMobile: isClockedOutOnMobile(
                daySessions: daySessions?.sessions,
                attendanceSessions: attendance?.sessions
            )
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
