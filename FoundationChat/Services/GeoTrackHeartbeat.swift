import Foundation
import UIKit

// MARK: - GeoTrackHeartbeat

/// Sends a recurring heartbeat directly to Airix GeoTrack every 75 seconds while tracking is active.
/// Matches Android's `startHeartbeatLoop()` with `HEARTBEAT_INTERVAL_MS = 75_000`.
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

    private struct PendingHeartbeat: Codable, Sendable {
        let sessionId: String?
        let deviceId: String?
        let batteryPct: Int
        let appVersion: String
        let recordedAt: Int64
    }

    // MARK: - Constants

    /// Matches Android and the direct GeoTrack 60–90 second contract.
    nonisolated static let defaultInterval: TimeInterval = 75

    // MARK: - Injected providers

    /// Returns current battery percentage (0–100). Defaults to UIDevice.
    var batteryProvider: () -> Int

    /// Returns the app version string embedded in the heartbeat payload.
    /// Defaults to `"<CFBundleShortVersionString>-ios"` so the backend can
    /// distinguish iOS from Android clients.
    var appVersionProvider: () -> String

    /// Performs the actual network call. Injected so tests run without a network.
    var sendHeartbeat: (Int, String) async throws -> Void

    private var sendRecordedHeartbeat: (PendingHeartbeat) async throws -> Void
    private var contextProvider: () -> (sessionId: String?, deviceId: String?)

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
    private let pendingDefaultsKey = "geotrack.pendingHeartbeats"
    private let maxPendingHeartbeats = 5_000

    // MARK: - Init (production)

    /// Creates a heartbeat service wired to the given API service and tamper monitor.
    init(
        geoAPI: GeoTrackAPIService? = nil,
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

        let capturedAPI = geoAPI ?? GeoTrackAPIService.shared
        self.sendHeartbeat = { batteryPct, appVersion in
            try await capturedAPI.heartbeat(batteryPct: batteryPct, appVersion: appVersion)
        }
        self.sendRecordedHeartbeat = { heartbeat in
            try await capturedAPI.heartbeat(
                batteryPct: heartbeat.batteryPct,
                appVersion: heartbeat.appVersion,
                recordedAt: heartbeat.recordedAt,
                sessionId: heartbeat.sessionId,
                deviceId: heartbeat.deviceId
            )
        }
        self.contextProvider = {
            let coordinator = GeoTrackBootstrapCoordinator.shared
            return (coordinator.activeSessionId, coordinator.deviceId)
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
        self.sendRecordedHeartbeat = { heartbeat in
            try await sendHeartbeat(heartbeat.batteryPct, heartbeat.appVersion)
        }
        self.contextProvider = { (nil, nil) }
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
        await replayPendingHeartbeats()
        do {
            try await sendHeartbeat(batteryPct, appVersion)
            lastHeartbeatDate = Date()
            consecutiveFailures = 0
            onSuccess()
        } catch {
            consecutiveFailures += 1
            let context = contextProvider()
            enqueue(
                PendingHeartbeat(
                    sessionId: context.sessionId,
                    deviceId: context.deviceId,
                    batteryPct: batteryPct,
                    appVersion: appVersion,
                    recordedAt: Int64(Date().timeIntervalSince1970 * 1_000)
                )
            )
        }
    }

    private func replayPendingHeartbeats() async {
        var pending = loadPending()
        guard !pending.isEmpty else { return }

        var sentCount = 0
        for heartbeat in pending.prefix(100) {
            do {
                try await sendRecordedHeartbeat(heartbeat)
                sentCount += 1
            } catch {
                break
            }
        }
        if sentCount > 0 {
            pending.removeFirst(sentCount)
            savePending(pending)
        }
    }

    private func enqueue(_ heartbeat: PendingHeartbeat) {
        var pending = loadPending()
        pending.append(heartbeat)
        if pending.count > maxPendingHeartbeats {
            pending.removeFirst(pending.count - maxPendingHeartbeats)
        }
        savePending(pending)
    }

    private func loadPending() -> [PendingHeartbeat] {
        guard let data = UserDefaults.standard.data(forKey: pendingDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingHeartbeat].self, from: data)) ?? []
    }

    private func savePending(_ pending: [PendingHeartbeat]) {
        guard !pending.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingDefaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: pendingDefaultsKey)
    }
}
