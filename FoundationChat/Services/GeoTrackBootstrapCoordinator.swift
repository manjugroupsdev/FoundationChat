import SwiftUI
import UIKit

@MainActor
@Observable
final class GeoTrackBootstrapCoordinator {
    static let shared = GeoTrackBootstrapCoordinator()

    private enum DefaultsKey {
        static let deviceId = "geotrack.trackingDeviceId"
        static let activeSessionId = "geotrack.activeTrackingSessionId"
        static let shouldTrackNow = "geotrack.shouldTrackNow"
        static let trackingEnabled = "geotrack.trackingEnabled"
    }

    private let geoAPI: GeoTrackAPIService
    private let userDefaults: UserDefaults
    private var tracker: LocationTracker?
    private var lastSyncDate: Date?
    private var isSyncing = false

    private(set) var lastError: String?
    private(set) var shouldPresentConsent = false
    private(set) var shouldPresentPermissionHelp = false

    var deviceId: String {
        if let existing = userDefaults.string(forKey: DefaultsKey.deviceId), !existing.isEmpty {
            return existing
        }
        let created = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        userDefaults.set(created, forKey: DefaultsKey.deviceId)
        return created
    }

    var activeSessionId: String? {
        guard let value = userDefaults.string(forKey: DefaultsKey.activeSessionId)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private init() {
        self.geoAPI = .shared
        self.userDefaults = .standard
    }

    func sync(
        reason: String,
        force: Bool = false,
        contextId: String? = nil,
        occurredAt: Int64? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) async {
        guard !isSyncing else { return }
        // The default replay only permits a queued end. Queued starts wait
        // until the attendance gate below explicitly allows them.
        await geoAPI.retryPendingTrackingControl()
        if !force, let lastSyncDate, Date().timeIntervalSince(lastSyncDate) < 30 {
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        let attendanceOpen = await currentAttendanceOpenState()
        if attendanceOpen == false {
            await geoAPI.retryPendingTrackingControl(discardStart: true)
            await endDirectSession(
                reason: "attendance_session_closed",
                endedAt: occurredAt,
                lat: lat,
                lng: lng
            )
            return
        }
        if attendanceOpen == nil {
            // An attendance outage is not proof of a new or closed shift.
            // Preserve only a tracker already verified in this process.
            return
        }

        if userDefaults.object(forKey: DefaultsKey.trackingEnabled) != nil,
           !userDefaults.bool(forKey: DefaultsKey.trackingEnabled) {
            // The stored flag is only written when a session is validated
            // (launch/login). GeoTrack switched on later on the web stayed
            // "off" here until the next cold start. Re-check before refusing.
            await refreshTrackingEnabledFlag()
        }
        if userDefaults.object(forKey: DefaultsKey.trackingEnabled) != nil,
           !userDefaults.bool(forKey: DefaultsKey.trackingEnabled) {
            await endDirectSession(reason: "tracking_not_enabled")
            return
        }

        await geoAPI.retryPendingTrackingControl(allowStart: true)
        let startCommandStillPending = geoAPI.hasPendingTrackingStart

        let consent = GeoTrackConsentManager.shared
        if consent.needsConsent {
            shouldPresentConsent = true
            userDefaults.set(false, forKey: DefaultsKey.shouldTrackNow)
            await tracker?.stopAndFinalize(notifyServer: false)
            return
        }
        guard consent.hasConsented else {
            shouldPresentConsent = false
            userDefaults.set(false, forKey: DefaultsKey.shouldTrackNow)
            await tracker?.stopAndFinalize(notifyServer: false)
            return
        }

        do {
            // A failed current-session read must never be interpreted as
            // "there is no session"; only an acknowledged nil starts one.
            let current = try await geoAPI.currentTrackingSession()
            let directSession: GeoTrackDirectSessionData
            if let current, current.state?.lowercased() == "active" {
                directSession = current
                geoAPI.clearPendingTrackingStart()
            } else if startCommandStillPending {
                throw GeoTrackAPIError.serverError("Tracking start is waiting for network recovery.")
            } else {
                directSession = try await geoAPI.startTracking(
                    contextId: contextId,
                    startedAt: occurredAt,
                    lat: lat,
                    lng: lng
                )
            }
            applyRecoveredSessionId(directSession.sessionId)
            shouldPresentConsent = false
            let tracker = tracker ?? LocationTracker()
            self.tracker = tracker
            try await tracker.resumeServerBackedTracking()
            lastError = nil
            shouldPresentPermissionHelp = false
        } catch {
            lastError = error.localizedDescription
            shouldPresentPermissionHelp = isPermissionError(error)
        }
    }

    func handleConsentAccepted() async {
        shouldPresentConsent = false
        await sync(reason: "consent-accepted", force: true)
    }

    func handleConsentDeclined() {
        shouldPresentConsent = false
        userDefaults.set(false, forKey: DefaultsKey.shouldTrackNow)
        tracker?.cancelTrip()
    }

    func dismissPermissionHelp() {
        shouldPresentPermissionHelp = false
    }

    func stopForSessionEnd(reason: String = "user_logout") async {
        shouldPresentConsent = false
        shouldPresentPermissionHelp = false
        lastError = nil
        await endDirectSession(reason: reason)
    }

    func applyRecoveredSessionId(_ sessionId: String) {
        guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        userDefaults.set(sessionId, forKey: DefaultsKey.activeSessionId)
        userDefaults.set(true, forKey: DefaultsKey.shouldTrackNow)
    }

    func clearActiveSessionIfMatching(_ sessionId: String?) {
        guard sessionId == nil || activeSessionId == sessionId else { return }
        userDefaults.removeObject(forKey: DefaultsKey.activeSessionId)
        userDefaults.set(false, forKey: DefaultsKey.shouldTrackNow)
    }

    private func endDirectSession(
        reason: String,
        endedAt: Int64? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) async {
        await tracker?.stopAndFinalize(notifyServer: false)
        tracker = nil
        userDefaults.set(false, forKey: DefaultsKey.shouldTrackNow)

        var sessionId = activeSessionId
        if sessionId == nil {
            do {
                sessionId = try await geoAPI.currentTrackingSession()?.sessionId
            } catch {
                lastError = error.localizedDescription
            }
        }
        guard let sessionId else {
            clearActiveSessionIfMatching(nil)
            return
        }
        do {
            _ = try await geoAPI.stopTracking(
                sessionId: sessionId,
                endedAt: endedAt,
                lat: lat,
                lng: lng,
                reason: reason
            )
            clearActiveSessionIfMatching(sessionId)
        } catch {
            // GeoTrackAPIService retains the exact end body/idempotency key.
            // Keep the session id until that command is acknowledged.
            lastError = error.localizedDescription
        }
    }

    private var lastTrackingFlagRefresh: Date?

    /// Reads the current `geoTrackingEnabled` from `/api/auth/validate-session`.
    /// Throttled to one call per 2 minutes. Only an explicit server value is
    /// stored: a failed call or a missing field never switches tracking off,
    /// and an invalid session is left for the normal auth path to handle.
    private func refreshTrackingEnabledFlag() async {
        if let lastTrackingFlagRefresh, Date().timeIntervalSince(lastTrackingFlagRefresh) < 120 {
            return
        }
        lastTrackingFlagRefresh = Date()
        guard let token = geoAPI.tokenProvider?(), !token.isEmpty else { return }
        guard let user = try? await AuthAPIService.validateSession(token: token),
              let enabled = user.geoTrackingEnabled else { return }
        userDefaults.set(enabled, forKey: DefaultsKey.trackingEnabled)
    }

    private var lastTrackingVerify: Date?

    /// Keeps this device's tracking session and clock-in state in step with
    /// the server, at most every 10 minutes (Android parity).
    ///
    /// Production showed staff "Offline" while their phones kept posting: the
    /// points carried a session the server had already ended, which forces the
    /// live row Offline. And a clock-out from the web, a biometric device or
    /// another phone never reached a running tracker.
    func verifyTrackingStillValid() async {
        if let lastTrackingVerify, Date().timeIntervalSince(lastTrackingVerify) < 600 { return }
        lastTrackingVerify = Date()
        guard let token = geoAPI.tokenProvider?() else { return }

        // Only an authoritative "closed" ends tracking; an outage never does.
        if await AttendanceTrackingGate.hasOpenSessionNow(token: token) == false {
            await endDirectSession(reason: "attendance_session_closed")
            return
        }
        do {
            let current = try await geoAPI.currentTrackingSession()
            if let current, current.state?.lowercased() == "active" {
                if current.sessionId != activeSessionId {
                    applyRecoveredSessionId(current.sessionId)
                }
            } else {
                // Clocked in but the server has no open session: open one so
                // the points being captured now belong to a live session.
                await sync(reason: "tracking-session-missing", force: true)
            }
        } catch {
            // A failed read is not proof of anything; check again next time.
        }
    }

    /// MMS remains the source of truth only for whether attendance is open.
    private func currentAttendanceOpenState() async -> Bool? {
        guard let token = geoAPI.tokenProvider?() else { return nil }
        return await AttendanceTrackingGate.hasOpenSessionNow(token: token)
    }

    private func isPermissionError(_ error: any Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("location")
            || message.contains("permission")
            || message.contains("denied")
            || message.contains("settings")
    }
}

enum PushTokenCache {
    static var lastKnownToken: String?
}
