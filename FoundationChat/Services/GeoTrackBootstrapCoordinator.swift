import CoreLocation
import CoreMotion
import SwiftUI
import UIKit
import UserNotifications

@MainActor
@Observable
final class GeoTrackBootstrapCoordinator {
    static let shared = GeoTrackBootstrapCoordinator()

    private enum DefaultsKey {
        static let deviceId = "geotrack.trackingDeviceId"
        static let activeSessionId = "geotrack.activeTrackingSessionId"
        static let shouldTrackNow = "geotrack.shouldTrackNow"
        static let trackingEnabled = "geotrack.trackingEnabled"
        static let consentGiven = "geotrack.consent.given"
        static let consentDeclined = "geotrack.consent.declined"
    }

    private let geoAPI: GeoTrackAPIService
    private let userDefaults: UserDefaults
    private var tracker: LocationTracker?
    private var lastSyncDate: Date?
    private var isSyncing = false

    private(set) var lastBootstrap: TrackingBootstrapData?
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

    private init() {
        self.geoAPI = .shared
        self.userDefaults = .standard
    }

    func sync(reason: String, force: Bool = false) async {
        guard !isSyncing else { return }
        if !force, let lastSyncDate, Date().timeIntervalSince(lastSyncDate) < 30 {
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let syncResponse = try await geoAPI.syncTrackingDevice(await makeDeviceSyncRequest())
            let bootstrap: TrackingBootstrapData?
            if let responseBootstrap = syncResponse.bootstrap {
                bootstrap = responseBootstrap
            } else {
                bootstrap = try await geoAPI.trackingBootstrap(deviceId: deviceId)
            }
            let attendanceOpen = await currentAttendanceOpenState()
            try await apply(bootstrap: bootstrap, attendanceOpen: attendanceOpen)
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

    func stopForSessionEnd() async {
        shouldPresentConsent = false
        shouldPresentPermissionHelp = false
        lastError = nil
        lastBootstrap = nil
        userDefaults.set(false, forKey: DefaultsKey.shouldTrackNow)
        userDefaults.set(false, forKey: DefaultsKey.trackingEnabled)
        userDefaults.removeObject(forKey: DefaultsKey.activeSessionId)
        await tracker?.stopAndFinalize(notifyServer: false)
        tracker = nil
    }

    private func apply(bootstrap: TrackingBootstrapData?, attendanceOpen: Bool?) async throws {
        lastBootstrap = bootstrap
        userDefaults.set(bootstrap?.activeSession?.id, forKey: DefaultsKey.activeSessionId)
        userDefaults.set(
            bootstrap?.assignment?.attendance != nil || bootstrap?.assignment?.siteVisit != nil,
            forKey: DefaultsKey.trackingEnabled
        )
        syncConsentFlags(from: bootstrap)

        // Source-agnostic clock-in gate. A `nil` result means the attendance
        // endpoints didn't answer authoritatively (transient network/server
        // outage) — NOT that the staffer is clocked out. Android's
        // `enforceClockInGate()` keeps tracking on a null gate, so here we retain
        // the last-known `shouldTrackNow` state instead of stopping, so a blip
        // never drops a legitimate in-window journey. A real clock-out (a
        // definitive `false`) still stops tracking on the next successful sync.
        let previousShouldTrack = userDefaults.bool(forKey: DefaultsKey.shouldTrackNow)
        let attendanceActive = attendanceOpen ?? previousShouldTrack
        let shouldTrack = attendanceActive && bootstrap?.shouldTrack == true
        userDefaults.set(shouldTrack, forKey: DefaultsKey.shouldTrackNow)

        if bootstrap?.shouldPromptConsent == true {
            shouldPresentConsent = true
            await tracker?.stopAndFinalize()
            return
        }

        shouldPresentConsent = false

        guard shouldTrack,
              bootstrap?.activeSession?.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            await tracker?.stopAndFinalize()
            return
        }

        let tracker = tracker ?? LocationTracker()
        self.tracker = tracker
        try await tracker.resumeServerBackedTracking()
    }

    private func syncConsentFlags(from bootstrap: TrackingBootstrapData?) {
        switch bootstrap?.consent?.status {
        case "granted":
            userDefaults.set(true, forKey: DefaultsKey.consentGiven)
            userDefaults.set(false, forKey: DefaultsKey.consentDeclined)
        case "declined", "revoked":
            userDefaults.set(false, forKey: DefaultsKey.consentGiven)
            userDefaults.set(true, forKey: DefaultsKey.consentDeclined)
        default:
            break
        }
    }

    /// Live, source-agnostic clock-in gate bounded to the punch-in → punch-out
    /// window (matches Android `AttendanceTrackingGate.hasOpenSessionNow`).
    ///  - `true`  → a session is open right now; track.
    ///  - `false` → clocked out / never punched in; stop.
    ///  - `nil`   → couldn't determine (outage). Callers must NOT stop on nil.
    private func currentAttendanceOpenState() async -> Bool? {
        guard let token = geoAPI.tokenProvider?() else { return nil }
        return await AttendanceTrackingGate.hasOpenSessionNow(token: token)
    }

    private func makeDeviceSyncRequest() async -> TrackingDeviceSyncRequest {
        TrackingDeviceSyncRequest(
            deviceId: deviceId,
            appVersion: appVersionString(),
            pushToken: PushTokenCache.lastKnownToken,
            notificationPermission: await hasNotificationPermission(),
            fineLocationPermission: hasWhenInUseOrAlwaysLocationPermission,
            backgroundLocationPermission: hasAlwaysLocationPermission,
            activityRecognitionPermission: hasActivityRecognitionPermission,
            model: UIDevice.current.model
        )
    }

    private var hasWhenInUseOrAlwaysLocationPermission: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private var hasAlwaysLocationPermission: Bool {
        CLLocationManager().authorizationStatus == .authorizedAlways
    }

    private var hasActivityRecognitionPermission: Bool {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            return true
        default:
            return false
        }
    }

    private func hasNotificationPermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private func appVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "\(version)-ios"
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
