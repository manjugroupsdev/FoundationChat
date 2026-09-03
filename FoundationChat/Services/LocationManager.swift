import CoreLocation
import CoreMotion
import Foundation
import UIKit

@MainActor
@Observable
final class LocationTracker: NSObject {
    private let locationManager = CLLocationManager()
    private var uploadTask: Task<Void, Never>?

    private static let batchSize = 200
    // Drain up to this many batches per upload cycle so a long offline period
    // (thousands of buffered points) recovers in a single reconnect instead of
    // trickling out 200 points per 30 s. Matches Android MAX_BATCHES_PER_SYNC.
    private static let maxBatchesPerSync = 25
    // Unsent buffer safety cap (30 days), matches Android MAX_UNSENT_POINT_AGE_MS.
    private static let maxUnsentPointAgeMillis: Int64 = 30 * 24 * 60 * 60 * 1000
    private static let uploadInterval: TimeInterval = 30
    private static let foregroundDistanceFilter: CLLocationDistance = 30
    private static let backgroundDistanceFilter: CLLocationDistance = 100
    private static let minimumPointInterval: TimeInterval = 10
    private var lastRecordedDate: Date?

    private let persistence: GeoTrackPersistence
    private let geoAPI: GeoTrackAPIService
    let tamperMonitor: GeoTrackTamperMonitor
    let heartbeat: GeoTrackHeartbeat
    let activityMonitor: GeoTrackActivityMonitor

    // Active tracking state
    private(set) var isTracking = false
    private(set) var tripStartTime: Date?

    var lastLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    // Tracks previous auth status so tamper monitor can detect downgrades mid-session
    private var previousAuthStatus: CLAuthorizationStatus = .notDetermined

    var isTripActive: Bool { isTracking }
    /// Placeholder reference number displayed in GPSRecordingView.
    var activeRefNo: String? { nil }
    /// Placeholder waypoint count for GPSRecordingView display.
    var waypointCount: Int { 0 }

    init(
        persistence: GeoTrackPersistence? = nil,
        geoAPI: GeoTrackAPIService? = nil,
        tamperMonitor: GeoTrackTamperMonitor? = nil,
        heartbeat: GeoTrackHeartbeat? = nil,
        activityMonitor: GeoTrackActivityMonitor? = nil
    ) {
        let resolvedAPI = geoAPI ?? GeoTrackAPIService.shared
        self.persistence = persistence ?? GeoTrackPersistence.shared
        self.geoAPI = resolvedAPI
        let monitor = tamperMonitor ?? GeoTrackTamperMonitor(geoAPI: resolvedAPI)
        self.tamperMonitor = monitor
        self.heartbeat = heartbeat ?? GeoTrackHeartbeat(geoAPI: resolvedAPI, tamperMonitor: monitor)
        self.activityMonitor = activityMonitor ?? GeoTrackActivityMonitor()
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = Self.foregroundDistanceFilter
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .automotiveNavigation

        // Wire the Convex session token from Keychain into the shared API service
        self.geoAPI.tokenProvider = {
            try? KeychainTokenStore().load()?.token
        }

        previousAuthStatus = locationManager.authorizationStatus
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Trip Lifecycle

    /// Starts a Convex geotrack session and begins tamper monitoring.
    /// `purpose` and `remarks` are retained for call-site compatibility.
    func startTrip(purpose: String = "", remarks: String = "") async throws {
        guard !isTracking else { return }
        try await beginTracking(shouldStartServerSession: true)
    }

    /// Resumes local GPS capture for a server-backed active session returned
    /// by `/api/tracking/bootstrap`, without creating a second backend session.
    func resumeServerBackedTracking() async throws {
        guard !isTracking else { return }
        try await beginTracking(shouldStartServerSession: false)
    }

    private func beginTracking(shouldStartServerSession: Bool) async throws {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
            throw NSError(
                domain: "LocationTracker", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Location permission required. Please try again."]
            )
        }
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            throw NSError(
                domain: "LocationTracker", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Location access denied. Enable in Settings."]
            )
        }

        locationManager.startUpdatingLocation()
        try? await Task.sleep(for: .seconds(2))

        let lat = lastLocation?.coordinate.latitude
        let lng = lastLocation?.coordinate.longitude

        if shouldStartServerSession {
            // Keep collecting into the durable local queue during an outage;
            // the direct start command is persisted and replayed unchanged.
            try? await geoAPI.startTracking(lat: lat, lng: lng)
        }

        isTracking = true
        tripStartTime = Date()
        previousAuthStatus = status

        // Start tamper monitoring, heartbeat loop, and activity recognition
        tamperMonitor.start(currentAuthStatus: status)
        heartbeat.start()
        activityMonitor.start()

        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }
        locationManager.startMonitoringSignificantLocationChanges()
        startPeriodicUpload()

        // Cap the local buffer once per session start so a device that was
        // offline/abandoned for weeks can't retain an unbounded backlog.
        // (Android runs this on a 6-hour loop inside the always-on service; on
        // iOS a per-session-start purge is sufficient and avoids a wake timer.)
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Self.maxUnsentPointAgeMillis
        try? await persistence.purgeStaleUnsentPoints(olderThan: cutoff)
        try? await persistence.purgeStaleTamperEvents(olderThan: cutoff)

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    /// Stops the session. Returns a stub `GPSSessionEndResult` for view compatibility.
    func endTrip(remarks: String = "") async throws -> GPSSessionEndResult {
        guard isTracking else {
            throw NSError(
                domain: "LocationTracker", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No active trip"]
            )
        }
        await flushWaypoints()
        // A failed direct stop is persisted by GeoTrackAPIService and retried
        // on the next bootstrap without keeping iOS location updates alive.
        try? await geoAPI.stopTracking()
        stopTracking()
        return GPSSessionEndResult(totalWaypoints: nil, totalDistanceKm: nil, totalDuration: nil)
    }

    func cancelTrip() {
        Task { await stopAndFinalize() }
    }

    /// Saves a manually captured location into the CoreData buffer.
    func markLocation(description: String) {
        guard isTracking, let location = lastLocation else { return }
        let point = buildPoint(from: location)
        let coordinator = GeoTrackBootstrapCoordinator.shared
        let sessionId = coordinator.activeSessionId
        let deviceId = coordinator.deviceId
        Task {
            try? await persistence.insert(point: point, sessionId: sessionId, deviceId: deviceId)
        }
    }

    /// Uploads a photo via Convex storage and returns the storageId.
    func capturePhoto(imageData: Data) async throws -> String {
        guard let token = try KeychainTokenStore().load()?.token else {
            throw NSError(
                domain: "LocationTracker", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            )
        }
        return try await HRConvexAPIService.uploadPhoto(token: token, imageData: imageData)
    }

    // MARK: - Private

    func stopAndFinalize(notifyServer: Bool = true) async {
        guard isTracking else {
            stopTracking()
            return
        }

        await flushWaypoints()
        if notifyServer {
            try? await geoAPI.stopTracking()
        }
        stopTracking()
    }

    private func stopTracking() {
        isTracking = false
        tripStartTime = nil
        heartbeat.stop()
        tamperMonitor.stop()
        activityMonitor.stop()
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
        }
        uploadTask?.cancel()
        uploadTask = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidEnterBackground() {
        guard isTracking else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = Self.backgroundDistanceFilter
    }

    @objc private func appWillEnterForeground() {
        guard isTracking else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = Self.foregroundDistanceFilter
    }

    private func startPeriodicUpload() {
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.uploadInterval))
                guard !Task.isCancelled else { break }
                await self?.flushWaypoints()
            }
        }
    }

    private func addLocationPoint(_ location: CLLocation) {
        lastLocation = location
        guard isTracking else { return }

        if let lastDate = lastRecordedDate,
           location.timestamp.timeIntervalSince(lastDate) < Self.minimumPointInterval {
            return
        }
        // Matches Convex backend validation: reject accuracy > 100 m
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }

        lastRecordedDate = location.timestamp

        // Tamper: check for simulated location before storing
        tamperMonitor.checkLocation(location)

        let point = buildPoint(from: location)
        let coordinator = GeoTrackBootstrapCoordinator.shared
        let sessionId = coordinator.activeSessionId
        let deviceId = coordinator.deviceId
        Task {
            try? await persistence.insert(point: point, sessionId: sessionId, deviceId: deviceId)
            if let count = try? await persistence.getUnsentCount(), count >= Self.batchSize {
                await flushWaypoints()
            }
        }
    }

    /// Derives a `GeoTrackLocationPoint` from a raw `CLLocation` + device state.
    private func buildPoint(from location: CLLocation) -> GeoTrackLocationPoint {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryPct = batteryLevel >= 0 ? Int(batteryLevel * 100) : 100

        let speed   = max(0, location.speed)    // CLLocation returns -1 when invalid
        let bearing = max(0, location.course)   // CLLocation returns -1 when invalid
        let altitude: Double? = location.verticalAccuracy >= 0 ? location.altitude : nil

        return GeoTrackLocationPoint(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            speed: speed,
            bearing: bearing,
            altitude: altitude,
            activity: activityMonitor.currentActivity,
            activityConfidence: activityMonitor.activityConfidence,
            isMock: isMockLocationProvider(location),
            batteryPct: batteryPct,
            networkType: "UNKNOWN",   // Wire CTTelephonyNetworkInfo separately if needed
            // Avoid the synchronous `locationServicesEnabled()` query on the
            // main actor. Core Location reports permission/service changes via
            // `locationManagerDidChangeAuthorization`, which keeps this cached
            // status current without blocking UI work.
            gpsEnabled: authorizationStatus == .authorizedAlways
                || authorizationStatus == .authorizedWhenInUse,
            airplaneMode: false,      // No public iOS API; NWPathMonitor handles tamper detection
            recordedAt: Int64(location.timestamp.timeIntervalSince1970 * 1000)
        )
    }

    /// Returns true if the location fix was generated by a simulator or spoofing tool.
    private func isMockLocationProvider(_ location: CLLocation) -> Bool {
        location.sourceInformation?.isSimulatedBySoftware ?? false
    }

    /// Fetches up to `batchSize` unsent points, pushes them, then deletes on success.
    /// Points remain in the buffer on failure — next cycle retries automatically.
    func flushWaypoints() async {
        guard isTracking else { return }
        do {
            // Drain in chunks of `batchSize`, up to `maxBatchesPerSync` per cycle,
            // so a large offline backlog recovers in one reconnect. `markAsSent`
            // deletes the uploaded rows, so each fetch returns the NEXT unsent
            // window. Stop early once a short (or empty) batch means the buffer
            // is drained.
            var batchesProcessed = 0
            var failedSessionIds = Set<String>()
            while batchesProcessed < Self.maxBatchesPerSync {
                let pending = try await persistence.fetchUnsent(limit: Self.batchSize)
                if pending.isEmpty { break }

                let activeSessionId = GeoTrackBootstrapCoordinator.shared.activeSessionId
                let defaultDeviceId = GeoTrackBootstrapCoordinator.shared.deviceId
                let attributable = pending.compactMap { item -> (String, PendingPoint)? in
                    guard let sessionId = item.sessionId ?? activeSessionId,
                          !failedSessionIds.contains(sessionId) else { return nil }
                    return (sessionId, item)
                }
                let grouped = Dictionary(grouping: attributable, by: \.0)
                if grouped.isEmpty { break }

                var madeProgress = false
                for (sessionId, rows) in grouped {
                    let items = rows.map(\.1)
                    let deviceId = items.first?.deviceId ?? defaultDeviceId
                    let requestId = "geo-batch-\(deviceId)-\(items.first?.id.uuidString ?? "first")-\(items.last?.id.uuidString ?? "last")"
                    let points = items.enumerated().map { index, item in
                        let point = item.point
                        return GeoTrackLocationPoint(
                            pointId: "\(deviceId)-\(point.recordedAt)-\(item.id.uuidString)",
                            deviceSequence: point.recordedAt + Int64(index),
                            lat: point.lat,
                            lng: point.lng,
                            accuracy: point.accuracy,
                            speed: point.speed,
                            bearing: point.bearing,
                            altitude: point.altitude,
                            activity: point.activity,
                            activityConfidence: point.activityConfidence,
                            isMock: point.isMock,
                            batteryPct: point.batteryPct,
                            networkType: point.networkType,
                            gpsEnabled: point.gpsEnabled,
                            airplaneMode: point.airplaneMode,
                            recordedAt: point.recordedAt
                        )
                    }
                    do {
                        _ = try await geoAPI.pushBatch(
                            sessionId: sessionId,
                            deviceId: deviceId,
                            requestId: requestId,
                            points: points
                        )
                        try await persistence.markAsSent(ids: items.map(\.id))
                        madeProgress = true
                    } catch {
                        failedSessionIds.insert(sessionId)
                    }
                }

                guard madeProgress else { break }
                batchesProcessed += 1
                if pending.count < Self.batchSize { break }
            }
            if batchesProcessed > 0 {
                try? await persistence.purgeOldSentPoints()
            }

            let events = try await persistence.fetchUnsentTamperEvents()
            var syncedEventIds: [UUID] = []
            for event in events {
                do {
                    // Replay with the ORIGINAL detection time so an offline tamper
                    // event surfaces in the feed when it happened, not at sync time.
                    try await geoAPI.reportTamper(
                        eventType: event.eventType,
                        metadata: event.metadata,
                        detectedAt: event.recordedAt
                    )
                    syncedEventIds.append(event.id)
                } catch {
                    break
                }
            }
            try await persistence.deleteTamperEvents(ids: syncedEventIds)
        } catch {
            // Swallow: points stay buffered for the next retry
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in addLocationPoint(location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let current = manager.authorizationStatus
        Task { @MainActor in
            let previous = previousAuthStatus
            previousAuthStatus = current
            authorizationStatus = current
            // Forward to tamper monitor for GPS_DISABLED and PERMISSION_DOWNGRADE checks
            tamperMonitor.handleAuthorizationChange(previous: previous, current: current)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {}
}

struct GPSSessionEndResult {
    let totalWaypoints: Int?
    let totalDistanceKm: Double?
    let totalDuration: String?
}
