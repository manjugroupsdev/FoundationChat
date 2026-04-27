import CoreLocation
import Foundation
import Network

// MARK: - GeoTrackTamperMonitor

/// Detects five tamper conditions on iOS and reports them to the Convex backend.
///
/// Detection methods:
///  1. MOCK_LOCATION        — CLLocation.sourceInformation.isSimulatedBySoftware (iOS 15+)
///  2. AIRPLANE_MODE_ON     — NWPathMonitor: unsatisfied path with no WiFi or cellular
///  3. GPS_DISABLED         — CLLocationManager.locationServicesEnabled() == false, or
///                            authorization becomes .denied / .restricted
///  4. PERMISSION_DOWNGRADE — .authorizedAlways → .authorizedWhenInUse transition
///                            detected both mid-session and across app launches
///  5. DEVICE_REBOOT        — ProcessInfo.systemUptime < elapsed seconds since last heartbeat
///
/// All detection providers are injectable closures so the class is fully unit-testable.
@MainActor
final class GeoTrackTamperMonitor {

    // MARK: - Injected providers

    /// Called with each `CLLocation` to test for mock/simulated fixes.
    var isMockLocationProvider: (CLLocation) -> Bool

    /// Returns whether device-level location services are enabled.
    var locationServicesEnabledProvider: () -> Bool

    /// Returns seconds since last device boot (wraps ProcessInfo.systemUptime).
    var systemUptimeProvider: () -> TimeInterval

    /// Returns the current wall-clock time (wraps Date()).
    var nowProvider: () -> Date

    /// Async closure that dispatches a detected event to the Convex backend.
    /// Injectable so tests can capture events without network I/O.
    var reportHandler: (GeoTrackTamperEventType, [String: String]) async -> Void

    /// UserDefaults store for cross-session state (last heartbeat, last auth status).
    let userDefaults: UserDefaults

    // MARK: - Constants

    /// Minimum interval between consecutive reports of the same event type.
    static let cooldownDuration: TimeInterval = 120  // 2 minutes

    /// UserDefaults key for the most-recent heartbeat wall-clock timestamp.
    static let lastHeartbeatKey = "geotrack.tamper.lastHeartbeat"

    /// UserDefaults key for the most-recently stored CLAuthorizationStatus raw value.
    static let lastAuthStatusKey = "geotrack.tamper.lastAuthStatus"

    // MARK: - State

    private(set) var isRunning = false
    private var pathMonitor: NWPathMonitor?
    private var lastReportedAt: [GeoTrackTamperEventType: Date] = [:]

    // MARK: - Init

    /// Production init — wires directly to GeoTrackAPIService for reporting.
    init(geoAPI: GeoTrackAPIService = .shared) {
        self.isMockLocationProvider = { location in
            location.sourceInformation?.isSimulatedBySoftware ?? false
        }
        self.locationServicesEnabledProvider = CLLocationManager.locationServicesEnabled
        self.systemUptimeProvider = { ProcessInfo.processInfo.systemUptime }
        self.nowProvider = { Date() }
        self.userDefaults = .standard
        // Capture geoAPI so we don't hold self before init completes
        let capturedAPI = geoAPI
        self.reportHandler = { eventType, metadata in
            try? await capturedAPI.reportTamper(eventType: eventType, metadata: metadata)
        }
    }

    /// Testable init — all dependencies injected. Defaults produce a no-op monitor.
    init(
        reportHandler: @escaping (GeoTrackTamperEventType, [String: String]) async -> Void,
        isMockLocationProvider: @escaping (CLLocation) -> Bool = { _ in false },
        locationServicesEnabledProvider: @escaping () -> Bool = { true },
        systemUptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        nowProvider: @escaping () -> Date = { Date() },
        userDefaults: UserDefaults = .standard
    ) {
        self.reportHandler = reportHandler
        self.isMockLocationProvider = isMockLocationProvider
        self.locationServicesEnabledProvider = locationServicesEnabledProvider
        self.systemUptimeProvider = systemUptimeProvider
        self.nowProvider = nowProvider
        self.userDefaults = userDefaults
    }

    // MARK: - Lifecycle

    /// Begin monitoring. Call when a tracking session starts.
    func start(currentAuthStatus: CLAuthorizationStatus) {
        guard !isRunning else { return }
        isRunning = true
        lastReportedAt = [:]

        checkDeviceReboot()
        checkInitialGPSStatus(status: currentAuthStatus)
        checkStoredPermissionDowngrade(current: currentAuthStatus)
        startAirplaneModeMonitor()

        // Persist current auth status so the next launch can detect a downgrade
        userDefaults.set(currentAuthStatus.rawValue, forKey: Self.lastAuthStatusKey)
    }

    /// Stop all monitoring. Call when the tracking session ends.
    func stop() {
        isRunning = false
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - Per-location mock check

    /// Call for every CLLocation fix received. Checks isSimulatedBySoftware.
    func checkLocation(_ location: CLLocation) {
        guard isRunning else { return }
        if isMockLocationProvider(location) {
            report(.mockLocation, metadata: [
                "lat": String(location.coordinate.latitude),
                "lng": String(location.coordinate.longitude),
                "accuracy": String(location.horizontalAccuracy),
            ])
        }
    }

    // MARK: - Authorization status change

    /// Call whenever CLLocationManagerDelegate fires didChangeAuthorization.
    /// - Parameters:
    ///   - previous: The status **before** the change.
    ///   - current: The status **after** the change.
    func handleAuthorizationChange(
        previous: CLAuthorizationStatus,
        current: CLAuthorizationStatus
    ) {
        guard isRunning else { return }

        // GPS_DISABLED: either device location services are fully off, or permission was revoked
        if !locationServicesEnabledProvider() {
            report(.gpsDisabled, metadata: ["reason": "locationServicesDisabled"])
        } else if current == .denied || current == .restricted {
            report(.gpsDisabled, metadata: ["reason": statusLabel(current)])
        }

        // PERMISSION_DOWNGRADE: lost "Always" permission during an active session
        if previous == .authorizedAlways && current == .authorizedWhenInUse {
            report(.permissionDowngrade, metadata: [
                "from": "authorizedAlways",
                "to": "authorizedWhenInUse",
            ])
        }

        userDefaults.set(current.rawValue, forKey: Self.lastAuthStatusKey)
    }

    // MARK: - Heartbeat timestamp

    /// Persist a "still alive" timestamp. Call every upload cycle (~30 s).
    /// Used by device-reboot detection: if uptime < elapsed since this timestamp,
    /// the device rebooted while the app was not running.
    func recordHeartbeat() {
        userDefaults.set(nowProvider().timeIntervalSince1970, forKey: Self.lastHeartbeatKey)
    }

    // MARK: - Network path evaluation (internal for testing)

    /// Evaluates raw network-path booleans for airplane-mode detection.
    /// Exposed as `internal` so tests can exercise the logic directly
    /// without needing a real NWPath object.
    func evaluateNetworkPath(isUnsatisfied: Bool, hasWifi: Bool, hasCellular: Bool) {
        guard isUnsatisfied && !hasWifi && !hasCellular else { return }
        report(.airplaneModeOn, metadata: [
            "pathStatus": "unsatisfied",
            "wifi": String(hasWifi),
            "cellular": String(hasCellular),
        ])
    }

    // MARK: - Private detection helpers

    private func checkDeviceReboot() {
        let lastTs = userDefaults.double(forKey: Self.lastHeartbeatKey)
        defer { recordHeartbeat() }   // always update heartbeat on start
        guard lastTs > 0 else { return }   // first-ever launch: no baseline

        let elapsed = nowProvider().timeIntervalSince1970 - lastTs  // seconds since last heartbeat
        let uptime = systemUptimeProvider()                          // seconds since last boot

        // If the device uptime is shorter than the gap since the last heartbeat,
        // the device must have rebooted during that gap.
        if uptime < elapsed {
            report(.deviceReboot, metadata: [
                "uptimeSeconds": String(Int(uptime)),
                "elapsedSeconds": String(Int(elapsed)),
            ])
        }
    }

    private func checkInitialGPSStatus(status: CLAuthorizationStatus) {
        if !locationServicesEnabledProvider() {
            report(.gpsDisabled, metadata: ["reason": "locationServicesDisabled"])
        } else if status == .denied || status == .restricted {
            report(.gpsDisabled, metadata: ["reason": statusLabel(status)])
        }
    }

    /// Compares the stored (previous-session) auth status to the current one.
    private func checkStoredPermissionDowngrade(current: CLAuthorizationStatus) {
        // Use object(forKey:) so we can distinguish "never stored" from rawValue 0
        guard userDefaults.object(forKey: Self.lastAuthStatusKey) != nil else { return }
        let raw = Int32(userDefaults.integer(forKey: Self.lastAuthStatusKey))
        let previous = CLAuthorizationStatus(rawValue: raw) ?? .notDetermined
        if previous == .authorizedAlways && current == .authorizedWhenInUse {
            report(.permissionDowngrade, metadata: [
                "from": "authorizedAlways",
                "to": "authorizedWhenInUse",
                "detected": "onAppLaunch",
            ])
        }
    }

    private func startAirplaneModeMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor delivers on a background queue; hop to main actor
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.evaluateNetworkPath(
                    isUnsatisfied: path.status == .unsatisfied,
                    hasWifi: path.usesInterfaceType(.wifi),
                    hasCellular: path.usesInterfaceType(.cellular)
                )
            }
        }
        monitor.start(queue: DispatchQueue(label: "geotrack.pathmonitor", qos: .utility))
    }

    // MARK: - Reporting with per-type cooldown

    private func report(
        _ type: GeoTrackTamperEventType,
        metadata: [String: String] = [:]
    ) {
        let now = nowProvider()
        if let last = lastReportedAt[type],
           now.timeIntervalSince(last) < Self.cooldownDuration {
            return   // Suppress: still inside cooldown window
        }
        lastReportedAt[type] = now

        let handler = reportHandler
        Task {
            await handler(type, metadata)
        }
    }

    // MARK: - Utility

    private func statusLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:     return "notDetermined"
        case .restricted:        return "restricted"
        case .denied:            return "denied"
        case .authorizedAlways:  return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default:        return "unknown(\(status.rawValue))"
        }
    }
}
