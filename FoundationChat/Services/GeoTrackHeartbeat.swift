import Foundation
import UIKit

// MARK: - GeoTrackHeartbeat

/// Sends a recurring heartbeat to the Convex backend every 120 seconds while tracking is active.
/// Matches Android's `startHeartbeatLoop()` with `HEARTBEAT_INTERVAL_MS = 120_000`.
///
/// On each successful ping it:
///  - Updates `lastHeartbeatDate` (observable for UI if needed)
///  - Calls `onSuccess()` — wired to `tamperMonitor.recordHeartbeat()` so device-reboot
///    detection always has a fresh "still alive" timestamp.
///
/// All dependencies are injected closures, making every behavior unit-testable without
/// touching UIKit, Bundle, or the network.
@MainActor
@Observable
final class GeoTrackHeartbeat {

    // MARK: - Constants

    /// Matches Android: `HEARTBEAT_INTERVAL_MS = 120_000`
    nonisolated static let defaultInterval: TimeInterval = 120

    // MARK: - Injected providers

    /// Returns current battery percentage (0–100). Defaults to UIDevice.
    var batteryProvider: () -> Int

    /// Returns the app version string embedded in the heartbeat payload.
    /// Defaults to `"<CFBundleShortVersionString>-ios"` so the backend can
    /// distinguish iOS from Android clients.
    var appVersionProvider: () -> String

    /// Performs the actual network call. Injected so tests run without a network.
    var sendHeartbeat: (Int, String) async throws -> Void

    /// Called after each successful ping. Wired to `tamperMonitor.recordHeartbeat()`
    /// in production so device-reboot detection stays current.
    var onSuccess: () -> Void

    /// Heartbeat interval. Use a short value in tests.
    let interval: TimeInterval

    // MARK: - Observable state

    private(set) var isRunning = false
    private(set) var lastHeartbeatDate: Date?
    private(set) var consecutiveFailures = 0

    // MARK: - Private

    private var heartbeatTask: Task<Void, Never>?

    // MARK: - Init (production)

    /// Creates a heartbeat service wired to the given API service and tamper monitor.
    init(
        geoAPI: GeoTrackAPIService = .shared,
        tamperMonitor: GeoTrackTamperMonitor,
        interval: TimeInterval = defaultInterval
    ) {
        self.interval = interval

        self.batteryProvider = {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level >= 0 ? Int(level * 100) : 100
        }

        self.appVersionProvider = {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            return "\(v)-ios"
        }

        let capturedAPI = geoAPI
        self.sendHeartbeat = { batteryPct, appVersion in
            try await capturedAPI.heartbeat(batteryPct: batteryPct, appVersion: appVersion)
        }

        let capturedMonitor = tamperMonitor
        self.onSuccess = {
            capturedMonitor.recordHeartbeat()
        }
    }

    // MARK: - Init (testable)

    /// All-injectable init for unit tests. No UIKit, no network.
    init(
        batteryProvider: @escaping () -> Int,
        appVersionProvider: @escaping () -> String,
        sendHeartbeat: @escaping (Int, String) async throws -> Void,
        onSuccess: @escaping () -> Void = {},
        interval: TimeInterval = defaultInterval
    ) {
        self.batteryProvider = batteryProvider
        self.appVersionProvider = appVersionProvider
        self.sendHeartbeat = sendHeartbeat
        self.onSuccess = onSuccess
        self.interval = interval
    }

    // MARK: - Lifecycle

    /// Starts the heartbeat loop. Pings immediately then waits `interval` seconds.
    /// Idempotent — calling `start()` while already running is a no-op.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        consecutiveFailures = 0
        scheduleLoop()
    }

    /// Cancels the heartbeat loop. Safe to call multiple times.
    func stop() {
        isRunning = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Private

    private func scheduleLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            // Fire immediately so the server knows we're live the moment tracking starts,
            // then repeat every `interval` seconds — matching Android's first-fire pattern.
            while !Task.isCancelled {
                await self?.ping()
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(self?.interval ?? Self.defaultInterval))
            }
        }
    }

    private func ping() async {
        let batteryPct  = batteryProvider()
        let appVersion  = appVersionProvider()
        do {
            try await sendHeartbeat(batteryPct, appVersion)
            lastHeartbeatDate = Date()
            consecutiveFailures = 0
            onSuccess()
        } catch {
            consecutiveFailures += 1
            // Swallow: the next timer tick will retry automatically.
            // Missed pings are detected server-side via HEARTBEAT_MISSED tamper events.
        }
    }
}
