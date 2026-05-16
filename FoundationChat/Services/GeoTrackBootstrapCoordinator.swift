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
            let attendanceActive = await isClockedInForToday()
            try await apply(bootstrap: bootstrap, attendanceActive: attendanceActive)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
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

    private func apply(bootstrap: TrackingBootstrapData?, attendanceActive: Bool) async throws {
        lastBootstrap = bootstrap
        userDefaults.set(bootstrap?.activeSession?.id, forKey: DefaultsKey.activeSessionId)
        userDefaults.set(
            bootstrap?.assignment?.attendance != nil || bootstrap?.assignment?.siteVisit != nil,
            forKey: DefaultsKey.trackingEnabled
        )
        syncConsentFlags(from: bootstrap)

        let shouldTrack = attendanceActive && bootstrap?.shouldTrack == true
        userDefaults.set(shouldTrack, forKey: DefaultsKey.shouldTrackNow)

        if attendanceActive, bootstrap?.shouldPromptConsent == true {
            shouldPresentConsent = true
            tracker?.cancelTrip()
            return
        }

        shouldPresentConsent = false

        guard shouldTrack,
              bootstrap?.activeSession?.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            tracker?.cancelTrip()
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

    private func isClockedInForToday() async -> Bool {
        guard let token = geoAPI.tokenProvider?() else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        async let attendance = try? HRConvexAPIService.getTodayAttendance(token: token)
        async let sessions = try? HRConvexAPIService.getDaySessions(token: token, date: today)
        let todayAttendance = await attendance
        let daySessions = await sessions
        return (todayAttendance ?? nil)?.isOpen == true || (daySessions ?? nil)?.hasOpenSession == true
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
}

enum PushTokenCache {
    static var lastKnownToken: String?
}
