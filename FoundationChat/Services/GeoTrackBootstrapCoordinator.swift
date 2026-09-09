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
